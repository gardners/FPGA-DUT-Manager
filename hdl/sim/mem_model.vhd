-- mem_model: behavioural stand-in for the DDR3 memory subsystem (issue
-- 0034) for nvc testbenches. One mem_pkg port; the low ADDR_BITS of the
-- word address are stored (higher bits alias). ready stalls one cycle in
-- every STALL_EVERY (0 = never); reads return after LATENCY clk cycles.
-- Simulation only.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_model is
  generic (ADDR_BITS : positive := 20; LATENCY : positive := 20;
           STALL_EVERY : natural := 7);
  port (clk : in std_logic; req : in mem_req_t; rsp : out mem_rsp_t);
end entity;

architecture sim of mem_model is
  type ram_t is array (0 to 2 ** ADDR_BITS - 1) of std_logic_vector(127 downto 0);
  type pipe_t is array (1 to LATENCY) of std_logic_vector(128 downto 0);
  signal ready : std_logic := '1';
begin
  rsp.ready <= ready;
  process (clk)
    variable ram  : ram_t := (others => (others => '0'));
    variable pipe : pipe_t := (others => (others => '0'));
    variable cnt  : natural := 0;
    variable a    : natural;
  begin
    if rising_edge(clk) then
      rsp.rvalid <= pipe(1)(128);
      rsp.rdata  <= pipe(1)(127 downto 0);
      for i in 1 to LATENCY - 1 loop pipe(i) := pipe(i + 1); end loop;
      pipe(LATENCY) := (others => '0');
      if req.valid = '1' and ready = '1' then
        a := to_integer(req.addr(ADDR_BITS - 1 downto 0));
        if req.we = '1' then
          for i in 0 to 15 loop
            if req.wmask(i) = '1' then
              ram(a)(8 * i + 7 downto 8 * i) := req.wdata(8 * i + 7 downto 8 * i);
            end if;
          end loop;
        else
          pipe(LATENCY) := '1' & ram(a);
        end if;
      end if;
      cnt := cnt + 1;
      if STALL_EVERY /= 0 and cnt mod STALL_EVERY = 0 then ready <= '0'; else ready <= '1'; end if;
    end if;
  end process;
end architecture;
