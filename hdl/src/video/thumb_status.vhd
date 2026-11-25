-- thumb_status: per-machine thumbnail status for the mosaic (issues 0035,
-- 0036, 0038). clk_sys domain; machine numbers 0..31.
--
--   seen(m)    any sign of machine m in the last 3 s: a local machine of
--              this board (always), or a relay frame (lines or "present,
--              no source") for it
--   fresh(m)   a complete thumbnail was stored for m in the last 2 s
--   cur(m)     the buffer (mem_pkg thumb_addr buf) holding m's latest
--              complete thumbnail; the other buffer is being written
--   quarter(m) scale of that thumbnail: 0 = 1/2 (320x200, 80 words of rows
--              0..199), 1 = 1/4 (160x100, 40 words of rows 0..99)
--   n_seen     number of machines seen (the master picks the relay scale)
--
-- Ages count 100 ms ticks (saturating), so the limits hold to -0/+100 ms.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity thumb_status is
  port (
    clk      : in  std_logic;
    tick_1ms : in  std_logic;
    -- local machines (always present)
    local0, local1 : in unsigned(4 downto 0);
    -- frame complete events (local writer, relay receiver)
    ev_a, ev_b : in std_logic;
    ev_a_machine, ev_b_machine : in unsigned(4 downto 0);
    ev_a_buf, ev_b_buf : in std_logic;
    ev_a_quarter, ev_b_quarter : in std_logic;
    -- relay frame heard for a machine
    seen_ev  : in  std_logic;
    seen_machine : in unsigned(4 downto 0);
    seen     : out std_logic_vector(31 downto 0);
    fresh    : out std_logic_vector(31 downto 0);
    cur      : out std_logic_vector(31 downto 0);
    quarter  : out std_logic_vector(31 downto 0);
    n_seen   : out unsigned(5 downto 0)
  );
end entity;

architecture rtl of thumb_status is
  type age_t is array (0 to 31) of unsigned(4 downto 0);
  signal seen_age, fresh_age : age_t := (others => (others => '1'));
  signal cur_r, q_r, seen_r, fresh_r : std_logic_vector(31 downto 0) := (others => '0');
  signal ms : unsigned(6 downto 0) := (others => '0');
  signal tick : std_logic := '0';
  signal cnt : unsigned(5 downto 0) := (others => '0');
begin
  seen <= seen_r; fresh <= fresh_r; cur <= cur_r; quarter <= q_r; n_seen <= cnt;

  process (clk)
    variable c : unsigned(5 downto 0);
  begin
    if rising_edge(clk) then
      tick <= '0';
      if tick_1ms = '1' then
        if ms = 99 then ms <= (others => '0'); tick <= '1'; else ms <= ms + 1; end if;
      end if;
      for m in 0 to 31 loop
        if tick = '1' then
          if seen_age(m) /= 31 then seen_age(m) <= seen_age(m) + 1; end if;
          if fresh_age(m) /= 31 then fresh_age(m) <= fresh_age(m) + 1; end if;
        end if;
        if m = to_integer(local0) or m = to_integer(local1) or
           (seen_ev = '1' and m = to_integer(seen_machine)) then
          seen_age(m) <= (others => '0');
        end if;
        if ev_a = '1' and m = to_integer(ev_a_machine) then
          fresh_age(m) <= (others => '0');
          cur_r(m) <= ev_a_buf;
          q_r(m)   <= ev_a_quarter;
        end if;
        if ev_b = '1' and m = to_integer(ev_b_machine) then
          fresh_age(m) <= (others => '0');
          seen_age(m)  <= (others => '0');
          cur_r(m) <= ev_b_buf;
          q_r(m)   <= ev_b_quarter;
        end if;
        if seen_age(m) < 30 then seen_r(m) <= '1'; else seen_r(m) <= '0'; end if;
        if fresh_age(m) < 20 then fresh_r(m) <= '1'; else fresh_r(m) <= '0'; end if;
      end loop;
      c := (others => '0');
      for m in 0 to 31 loop
        if seen_r(m) = '1' then c := c + 1; end if;
      end loop;
      cnt <= c;
    end if;
  end process;
end architecture;
