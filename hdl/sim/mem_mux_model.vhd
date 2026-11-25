-- mem_mux_model: N mem_pkg ports sharing one mem_model (simulation only),
-- round robin, read data routed back in order. Lets testbenches check that
-- what one client writes another reads (issues 0035/0038). The real
-- arbiter is the DDR3 subsystem's (issue 0034).
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_mux_model is
  generic (N : positive := 2; ADDR_BITS : positive := 20; LATENCY : positive := 20;
           STALL_EVERY : natural := 7);
  port (clk : in std_logic; req : in mem_req_arr_t(0 to N - 1);
        rsp : out mem_rsp_arr_t(0 to N - 1));
end entity;

architecture sim of mem_mux_model is
  signal mreq : mem_req_t := MEM_REQ_IDLE;
  signal mrsp : mem_rsp_t;
  signal rr   : natural range 0 to N - 1 := 0;
  signal grant : integer range -1 to N - 1;
  type q_t is array (0 to 1023) of natural;
  signal q : q_t := (others => 0);
  signal qh, qt : natural := 0;
begin
  mm : entity work.mem_model generic map (ADDR_BITS, LATENCY, STALL_EVERY)
    port map (clk => clk, req => mreq, rsp => mrsp);

  process (req, rr)
    variable g : integer range -1 to N - 1;
  begin
    g := -1;
    for k in 0 to N - 1 loop
      if g = -1 and req((rr + k) mod N).valid = '1' then
        g := (rr + k) mod N;
      end if;
    end loop;
    grant <= g;
  end process;
  mreq <= req(grant) when grant >= 0 else MEM_REQ_IDLE;

  process (grant, mrsp, q, qh)
  begin
    for i in 0 to N - 1 loop
      rsp(i).ready  <= '0';
      rsp(i).rvalid <= '0';
      rsp(i).rdata  <= mrsp.rdata;   -- shared; only the port with rvalid uses it
      if grant = i then rsp(i).ready <= mrsp.ready; end if;
      if mrsp.rvalid = '1' and q(qh mod 1024) = i then rsp(i).rvalid <= '1'; end if;
    end loop;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      if mrsp.rvalid = '1' then
        qh <= qh + 1;
      end if;
      if grant >= 0 and mrsp.ready = '1' then
        if req(grant).we = '0' then
          q(qt mod 1024) <= grant;
          qt <= qt + 1;
        end if;
        rr <= (grant + 1) mod N;
      end if;
    end if;
  end process;
end architecture;
