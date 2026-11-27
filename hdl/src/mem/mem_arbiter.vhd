-- mem_arbiter: N client ports -> one mem_pkg port, round robin (issue 0034).
--
-- clk_sys domain. One registered output stage: a client request is taken
-- into the output register when that client holds the grant and the
-- register is empty or being accepted downstream, so client ready depends
-- only on the other clients' valid and the downstream ready (registers),
-- never on a long combinational chain. The grant rotates: after port i is
-- served, port i+1 has the highest priority.
--
-- Bursts (BURST > 1, issue 0060 relay-rx-speed): a port that keeps its
-- request valid keeps the grant for up to BURST consecutive requests before
-- the rotation moves on. Every change between clients that read and write
-- different DDR3 rows costs a bus turnaround and often a precharge +
-- activate (~80 ns in all); one-word round robin between the full-view
-- writer and the full_display reader paid that for every word.
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
    TAG_BITS  : positive := 6;      -- tag FIFO depth 2**TAG_BITS
    BURST     : positive := 1       -- requests a port may make in a row
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
  signal hold   : natural range 0 to BURST - 1 := 0;  -- requests `last` may still add
  signal keep   : std_logic;                         -- registered: hold /= 0
begin
  -- round-robin pick: first valid port after the last one served. Written
  -- as two fixed-priority encoders (ports above `last`, then all ports)
  -- rather than (last + k) mod N: far fewer logic levels for N = 5
  -- (thumbnail ports, timing).
  process (reqs, last, keep)
    variable gh, ga : port_t;
    variable fh, fa : std_logic;
  begin
    gh := 0; fh := '0';
    ga := 0; fa := '0';
    for p in N - 1 downto 0 loop
      if reqs(p).valid = '1' then
        ga := p; fa := '1';
        if p > last then
          gh := p; fh := '1';
        end if;
      end if;
    end loop;
    if keep = '1' and reqs(last).valid = '1' then
      grant <= last;
    elsif fh = '1' then
      grant <= gh;
    else
      grant <= ga;
    end if;
    any_v <= fa;
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
        if BURST > 1 then
          if grant /= last or hold = 0 then
            hold <= BURST - 1;
            keep <= '1';
          else
            hold <= hold - 1;
            if hold = 1 then keep <= '0'; end if;
          end if;
        end if;
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
