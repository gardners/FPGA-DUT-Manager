-- mem_selftest: built-in DDR3 frame-store test (issue 0034), one mem_pkg
-- client on clk_sys. Runs once when start goes high (DDR3 calibrated):
--   1. write pattern A(a) to every word of the region (all bytes);
--   2. write B(a) = not A(a) with a byte mask: even words the low DQ byte
--      lane (bytes 0, 2, ..., DM0 writes), odd words the high lane (DM1);
--   3. read every word back and compare with the merge of A and B.
-- A(a) mixes the address into all 128 bits (four rotated/xored copies), so
-- stuck or swapped data lines, address aliasing and broken data masks all
-- show up. The 128-bit word is 8 beats of the 16-bit bus, so bit i of a
-- word travelled on DQ (i mod 16): dq_fail folds the wrong bits that way.
-- The region is clobbered; nothing else uses it during start-up.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_selftest is
  generic (
    BASE_WORD : natural := 0;         -- first word address
    WORD_BITS : positive := 16        -- region = 2**WORD_BITS words (16 = 1 MiB)
  );
  port (
    clk       : in  std_logic;
    start     : in  std_logic;        -- level; the test runs once after it rises
    req       : out mem_req_t;
    rsp       : in  mem_rsp_t;
    running   : out std_logic;
    done      : out std_logic;
    pass      : out std_logic;
    errors    : out unsigned(15 downto 0);
    dq_fail   : out std_logic_vector(15 downto 0);
    first_err : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of mem_selftest is
  constant WORDS : natural := 2 ** WORD_BITS;

  function pat_a(a : unsigned(MEM_AW - 1 downto 0)) return std_logic_vector is
    variable x : unsigned(31 downto 0) := resize(a, 32);
    variable v : std_logic_vector(127 downto 0);
  begin
    v(31 downto 0)   := std_logic_vector(x);
    v(63 downto 32)  := std_logic_vector(not rotate_left(x, 8));
    v(95 downto 64)  := std_logic_vector(rotate_left(x, 16) xor x"A5A5_5A5A");
    v(127 downto 96) := std_logic_vector(rotate_left(x, 24) xor x"3C3C_C3C3");
    return v;
  end function;
  -- byte mask of pass 2 (bytes written with B): even words low lane
  function mask_b(a : unsigned(MEM_AW - 1 downto 0)) return std_logic_vector is
  begin
    if a(0) = '0' then return x"5555"; else return x"AAAA"; end if;
  end function;
  function expect(a : unsigned(MEM_AW - 1 downto 0)) return std_logic_vector is
    variable pa : std_logic_vector(127 downto 0) := pat_a(a);
    variable m  : std_logic_vector(15 downto 0) := mask_b(a);
    variable v  : std_logic_vector(127 downto 0);
  begin
    for i in 0 to 15 loop
      if m(i) = '1' then
        v(8 * i + 7 downto 8 * i) := not pa(8 * i + 7 downto 8 * i);
      else
        v(8 * i + 7 downto 8 * i) := pa(8 * i + 7 downto 8 * i);
      end if;
    end loop;
    return v;
  end function;

  type state_t is (S_IDLE, S_WR_A, S_WR_B, S_RD, S_DRAIN, S_DONE);
  signal state : state_t := S_IDLE;
  signal r     : mem_req_t := MEM_REQ_IDLE;
  signal ia    : unsigned(WORD_BITS downto 0) := (others => '0');  -- issue index
  signal ra    : unsigned(WORD_BITS downto 0) := (others => '0');  -- return index
  -- compare pipeline
  signal c_v   : std_logic := '0';
  signal c_x   : std_logic_vector(127 downto 0) := (others => '0');
  signal c_a   : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  signal errs  : unsigned(15 downto 0) := (others => '0');
  signal dqf   : std_logic_vector(15 downto 0) := (others => '0');
  signal ferr  : std_logic_vector(31 downto 0) := (others => '1');
  signal start_seen : std_logic := '0';

  function waddr(i : unsigned) return unsigned is
  begin
    return to_unsigned(BASE_WORD, MEM_AW) + resize(i(WORD_BITS - 1 downto 0), MEM_AW);
  end function;
begin
  req       <= r;
  running   <= '1' when state /= S_IDLE and state /= S_DONE else '0';
  done      <= '1' when state = S_DONE else '0';
  pass      <= '1' when state = S_DONE and errs = 0 else '0';
  errors    <= errs;
  dq_fail   <= dqf;
  first_err <= ferr;

  process (clk)
    variable a, last_a : unsigned(MEM_AW - 1 downto 0);
    variable nxt       : unsigned(WORD_BITS downto 0);
    variable x         : std_logic_vector(127 downto 0);
    variable f         : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      -- request issue: r holds until accepted (rsp.ready)
      if r.valid = '1' and rsp.ready = '1' then
        r.valid <= '0';
      end if;
      if r.valid = '0' or rsp.ready = '1' then
        nxt := ia;
        a := waddr(ia);
        case state is
          when S_IDLE =>
            if start = '1' and start_seen = '0' then
              start_seen <= '1';
              state <= S_WR_A;
              ia <= (others => '0');
            end if;
          when S_WR_A =>
            r <= ('1', '1', a, pat_a(a), x"FFFF");
            nxt := ia + 1;
            if nxt = WORDS then
              state <= S_WR_B; nxt := (others => '0');
            end if;
            ia <= nxt;
          when S_WR_B =>
            r <= ('1', '1', a, not pat_a(a), mask_b(a));
            nxt := ia + 1;
            if nxt = WORDS then
              state <= S_RD; nxt := (others => '0');
            end if;
            ia <= nxt;
          when S_RD =>
            r <= ('1', '0', a, (others => '0'), (others => '0'));
            nxt := ia + 1;
            if nxt = WORDS then
              state <= S_DRAIN;
            end if;
            ia <= nxt;
          when S_DRAIN =>
            if ra = WORDS and c_v = '0' then
              state <= S_DONE;
            end if;
          when S_DONE => null;
        end case;
      end if;

      -- read returns (in order): stage 1 xor with the expected word
      c_v <= '0';
      if rsp.rvalid = '1' and (state = S_RD or state = S_DRAIN) then
        a := waddr(ra);
        c_x <= rsp.rdata xor expect(a);
        c_a <= a;
        c_v <= '1';
        ra <= ra + 1;
      end if;
      -- stage 2: count and fold mismatches
      if c_v = '1' and c_x /= (127 downto 0 => '0') then
        if errs /= x"FFFF" then
          errs <= errs + 1;
        end if;
        if errs = 0 then
          ferr <= std_logic_vector(resize(c_a, 32));
        end if;
        f := dqf;
        for i in 0 to 127 loop
          f(i mod 16) := f(i mod 16) or c_x(i);
        end loop;
        dqf <= f;
      end if;
    end if;
  end process;
end architecture;
