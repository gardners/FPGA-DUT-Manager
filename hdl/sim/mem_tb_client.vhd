-- mem_tb_client: traffic generator for memory subsystem testbenches
-- (issue 0034). Writes COUNT words at BASE (data from address and SEED,
-- random byte masks over a pre-filled word), interleaved with reads of
-- words already written, then reads everything back; checks every read
-- against its own shadow copy. valid drops pseudo-randomly. Simulation only.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_tb_client is
  generic (BASE : natural := 0; COUNT : positive := 64; SEED : positive := 7);
  port (
    clk    : in  std_logic;
    req    : out mem_req_t;
    rsp    : in  mem_rsp_t;
    done   : out boolean;
    errors : out natural;
    reads  : out natural
  );
end entity;

architecture sim of mem_tb_client is
  type shadow_t is array (0 to COUNT - 1) of std_logic_vector(127 downto 0);
  function word(i : natural; s : natural) return std_logic_vector is
    variable v : std_logic_vector(127 downto 0);
  begin
    for k in 0 to 3 loop
      v(32 * k + 31 downto 32 * k) := std_logic_vector(to_unsigned((i * 2654435 + s * 40503 + k * 977) mod 2 ** 30, 32));
    end loop;
    return v;
  end function;
begin
  process (clk)
    variable shadow : shadow_t := (others => (others => '0'));
    type q_t is array (0 to 255) of natural;
    variable q     : q_t;                 -- expected read indices, in order
    variable qh, qt: natural := 0;
    variable phase : natural := 0;        -- 0 fill, 1 masked writes + reads, 2 read all, 3 done
    variable i     : natural := 0;
    variable lfsr  : unsigned(15 downto 0) := to_unsigned(SEED * 37 + 1, 16);
    variable r     : mem_req_t := MEM_REQ_IDLE;
    variable errs, nrd : natural := 0;
    variable m     : std_logic_vector(15 downto 0);
    variable d     : std_logic_vector(127 downto 0);
  begin
    if rising_edge(clk) then
      -- returns
      if rsp.rvalid = '1' then
        assert qh /= qt report "mem_tb_client: unexpected rvalid" severity error;
        if rsp.rdata /= shadow(q(qh mod 256)) then
          errs := errs + 1;
          report "mem_tb_client " & integer'image(BASE) & ": word " & integer'image(q(qh mod 256)) &
                 " read back wrong" severity error;
        end if;
        qh := qh + 1;
        nrd := nrd + 1;
      end if;
      -- accepted?
      if r.valid = '1' and rsp.ready = '1' then
        r.valid := '0';
      end if;
      lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      if r.valid = '0' and lfsr(1 downto 0) /= "00" and qt - qh < 200 then
        case phase is
          when 0 =>                       -- fill
            d := word(i, SEED);
            shadow(i) := d;
            r := ('1', '1', to_unsigned(BASE + i, MEM_AW), d, x"FFFF");
            i := i + 1;
            if i = COUNT then i := 0; phase := 1; end if;
          when 1 =>                       -- masked overwrite, read every other step
            if lfsr(2) = '1' then
              m := std_logic_vector(lfsr(15 downto 0) xor x"0F0F");
              d := word(i, SEED + 1);
              for b in 0 to 15 loop
                if m(b) = '1' then
                  shadow(i)(8 * b + 7 downto 8 * b) := d(8 * b + 7 downto 8 * b);
                end if;
              end loop;
              r := ('1', '1', to_unsigned(BASE + i, MEM_AW), d, m);
              i := i + 1;
              if i = COUNT then i := 0; phase := 2; end if;
            elsif i > 0 then
              q(qt mod 256) := i - 1;
              qt := qt + 1;
              r := ('1', '0', to_unsigned(BASE + i - 1, MEM_AW), (others => '0'), (others => '0'));
            end if;
          when 2 =>
            q(qt mod 256) := i;
            qt := qt + 1;
            r := ('1', '0', to_unsigned(BASE + i, MEM_AW), (others => '0'), (others => '0'));
            i := i + 1;
            if i = COUNT then phase := 3; end if;
          when others => null;
        end case;
      end if;
      req <= r;
      done <= phase = 3 and qh = qt and r.valid = '0';
      errors <= errs;
      reads <= nrd;
    end if;
  end process;
end architecture;
