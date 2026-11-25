-- mem_arbiter: N client ports -> one mem_pkg port, round robin (issue 0034).
--
-- clk_sys domain. One registered output stage: a client request is taken
-- into the output register when that client holds the grant and the
-- register is empty or being accepted downstream, so client ready depends
-- only on the other clients' valid and the downstream ready (registers),
-- never on a long combinational chain. The grant rotates: after port i is
-- served, port i+1 has the highest priority.
--
-- Reads return in request order downstream; the port of every accepted read
-- is queued in a tag FIFO and the returning data is steered to that port.
-- At most TAG_DEPTH - 1 reads are outstanding (ready drops otherwise), so
-- the tag FIFO never overflows whatever the downstream read latency.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_arbiter is
  generic (
    N         : positive := 2;
    TAG_BITS  : positive := 6       -- tag FIFO depth 2**TAG_BITS
  );
  port (
    clk  : in  std_logic;
    reqs : in  mem_req_arr_t(0 to N - 1);
    rsps : out mem_rsp_arr_t(0 to N - 1);
    req  : out mem_req_t;           -- downstream (memory controller side)
    rsp  : in  mem_rsp_t
  );
end entity;

architecture rtl of mem_arbiter is
  constant TAG_DEPTH : natural := 2 ** TAG_BITS;
  subtype port_t is natural range 0 to N - 1;

  signal o      : mem_req_t := MEM_REQ_IDLE;   -- output register
  signal last   : port_t := N - 1;             -- last port served
  signal grant  : port_t;
  signal any_v  : std_logic;
  signal take   : std_logic;

  type tag_mem_t is array (0 to TAG_DEPTH - 1) of port_t;
  signal tags   : tag_mem_t := (others => 0);
  signal tag_wp, tag_rp : unsigned(TAG_BITS - 1 downto 0) := (others => '0');
  signal pending: natural range 0 to TAG_DEPTH := 0;   -- reads not yet returned
  signal room   : std_logic;
begin
  -- round-robin pick: first valid port after the last one served
  process (reqs, last)
    variable g : port_t;
    variable f : std_logic;
    variable p : natural;
  begin
    g := 0;
    f := '0';
    for k in 1 to N loop
      p := (last + k) mod N;
      if f = '0' and reqs(p).valid = '1' then
        g := p;
        f := '1';
      end if;
    end loop;
    grant <= g;
    any_v <= f;
  end process;

  room <= '1' when pending < TAG_DEPTH - 1 else '0';
  -- output register free this cycle?
  take <= any_v and room and ((not o.valid) or rsp.ready);

  g_rsp : for i in 0 to N - 1 generate
    rsps(i).ready  <= take when grant = i else '0';
    rsps(i).rvalid <= rsp.rvalid when tags(to_integer(tag_rp)) = i else '0';
    rsps(i).rdata  <= rsp.rdata;
  end generate;

  req <= o;

  process (clk)
    variable inc, dec : boolean;
  begin
    if rising_edge(clk) then
      if o.valid = '1' and rsp.ready = '1' then
        o.valid <= '0';
      end if;
      inc := false;
      if take = '1' then
        o <= reqs(grant);
        o.valid <= '1';
        last <= grant;
        if reqs(grant).we = '0' then
          tags(to_integer(tag_wp)) <= grant;
          tag_wp <= tag_wp + 1;
          inc := true;
        end if;
      end if;
      dec := rsp.rvalid = '1';
      if dec then
        tag_rp <= tag_rp + 1;
      end if;
      if inc and not dec then
        pending <= pending + 1;
      elsif dec and not inc then
        pending <= pending - 1;
      end if;
    end if;
  end process;
end architecture;
