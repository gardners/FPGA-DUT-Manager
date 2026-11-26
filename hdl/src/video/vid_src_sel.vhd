-- vid_src_sel: pick one of N video receivers' measurements for the
-- heartbeat video block (issue 0049, shield gate build). Source 0 is the
-- on-board HDMI IN; sources 1..N-1 are shield header receivers. The
-- selected source is the lowest-numbered one that is present (source 0
-- when none is), so the normal heartbeat is unchanged while the on-board
-- input has a signal, and a header receiver shows up as soon as it is the
-- only live input. All inputs are quasi-static clk-domain values from
-- video_meas (and synchronised lock flags); outputs are registered.
--
-- meas packing per source i, MEAS_W = 99 bits at meas(i*MEAS_W + ...):
--   98 locked, 97 hdmi, 96 island, 95:80 h_total, 79:64 v_total,
--   63:48 h_active, 47:32 v_active, 31:0 pixel_hz
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vid_src_pkg is
  constant MEAS_W : positive := 99;
  function meas_pack(locked, hdmi, island : std_logic; ht, vt, ha, va : unsigned(15 downto 0);
                     hz : unsigned(31 downto 0)) return std_logic_vector;
end package;

package body vid_src_pkg is
  function meas_pack(locked, hdmi, island : std_logic; ht, vt, ha, va : unsigned(15 downto 0);
                     hz : unsigned(31 downto 0)) return std_logic_vector is
  begin
    return locked & hdmi & island & std_logic_vector(ht) & std_logic_vector(vt) &
           std_logic_vector(ha) & std_logic_vector(va) & std_logic_vector(hz);
  end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vid_src_pkg.all;

entity vid_src_sel is
  generic (N : positive := 4);
  port (
    clk     : in  std_logic;
    present : in  std_logic_vector(N - 1 downto 0);
    meas    : in  std_logic_vector(N * MEAS_W - 1 downto 0);
    sel     : out unsigned(1 downto 0);            -- selected source (N <= 4)
    sel_present : out std_logic;
    locked, hdmi, island : out std_logic;
    h_total, v_total, h_active, v_active : out unsigned(15 downto 0);
    pixel_hz : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of vid_src_sel is
begin
  assert N <= 4 report "vid_src_sel: at most 4 sources" severity failure;
  process (clk)
    variable s : natural range 0 to N - 1;
    variable m : std_logic_vector(MEAS_W - 1 downto 0);
  begin
    if rising_edge(clk) then
      s := 0;
      for i in N - 1 downto 0 loop
        if present(i) = '1' then
          s := i;
        end if;
      end loop;
      m := meas(s * MEAS_W + MEAS_W - 1 downto s * MEAS_W);
      sel         <= to_unsigned(s, 2);
      sel_present <= present(s);
      locked      <= m(98);
      hdmi        <= m(97);
      island      <= m(96);
      h_total     <= unsigned(m(95 downto 80));
      v_total     <= unsigned(m(79 downto 64));
      h_active    <= unsigned(m(63 downto 48));
      v_active    <= unsigned(m(47 downto 32));
      pixel_hz    <= unsigned(m(31 downto 0));
    end if;
  end process;
end architecture;
