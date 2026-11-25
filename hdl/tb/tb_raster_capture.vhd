-- tb_raster_capture: raster_capture driven by video_timing (small mode,
-- positive syncs) with a known pixel pattern.
--  1. 3 frames read promptly: line numbering (line 0 first after enable,
--     frame increments at line 0), flags, hs_start/hs_end, every pixel.
--  2. reader stalls: ring overflow drops whole lines; the first line committed
--     after the drops carries the count and flag b5, its absolute position
--     equals previous + drops + 1; earlier and later lines have no flag.
--  3. capture disabled: no new lines; re-enabled: restarts at a line 0.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.raster_pkg.all;

entity tb_raster_capture is
end entity;

architecture tb of tb_raster_capture is
  constant HA : natural := 40;
  constant VA : natural := 10;
  constant RING_AW : natural := 8;     -- 256 px
  constant MAXPX : natural := 64;
  constant LINE_T : time := 56 * 20 ns;
  signal pclk, clk : std_logic := '0';
  signal done : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal rgb : std_logic_vector(23 downto 0);
  signal enable : std_logic := '0';
  signal valid, pop : std_logic := '0';
  signal d : rast_desc_t;
  signal raddr : unsigned(RING_AW - 1 downto 0) := (others => '0');
  signal rdata : std_logic_vector(23 downto 0);

  function pat(px, ln : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(px mod 256, 8)) & std_logic_vector(to_unsigned(ln mod 256, 8)) &
           std_logic_vector(to_unsigned((px * 7 + ln * 31 + 5) mod 256, 8));
  end function;
begin
  pclk <= not pclk after 10 ns when not done;     -- 50 MHz
  clk  <= not clk after 4 ns when not done;       -- 125 MHz
  tim : entity work.video_timing
    generic map (H_ACTIVE => HA, H_FP => 4, H_SYNC => 6, H_BP => 6,
                 V_ACTIVE => VA, V_FP => 2, V_SYNC => 2, V_BP => 2, SYNC_POL => '1')
    port map (pclk, x, y, de, hs, vs, fs);
  rgb <= pat(to_integer(x), to_integer(y));
  dut : entity work.raster_capture
    generic map (RING_AW => RING_AW, DESC_AW => 4, MAX_LINE_PX => MAXPX)
    port map (pclk => pclk, de => de, hs => hs, vs => vs, rgb => rgb, locked => '1',
              clk => clk, enable => enable, desc_valid => valid, desc => d, desc_pop => pop,
              ring_addr => raddr, ring_data => rdata);

  process
    variable prev_abs, ab : integer;
    variable first : boolean;
    variable n, ndrop : natural;
    variable fr0 : unsigned(31 downto 0);

    -- check and consume one descriptor
    procedure take(check_flags : boolean := true) is
      variable s : rast_desc_t;
    begin
      while valid /= '1' loop
        wait until rising_edge(clk);
      end loop;
      s := d;
      assert s.count = HA report "active_count " & integer'image(to_integer(s.count)) severity failure;
      assert s.line < VA report "line out of range" severity failure;
      assert s.flags(RF_ACTIVE) = '1' and s.flags(RF_LOCKED) = '1' and s.flags(RF_VSYNC) = '0'
        report "flags active/locked/vsync wrong" severity failure;
      assert s.flags(RF_VPOL) = '1' and s.flags(RF_HPOL) = '1' report "polarity flags wrong" severity failure;
      assert (s.flags(RF_FIRST) = '1') = (s.line = 0) report "line-0 flag wrong" severity failure;
      assert (s.flags(RF_DROPPED) = '1') = (s.drops /= 0) report "dropped flag /= drops" severity failure;
      -- HSYNC at 44..49 counted from the first active pixel (only known after one line)
      if not first then
        assert s.hs_start = HA + 4 and s.hs_end = HA + 10
          report "hs_start/hs_end " & integer'image(to_integer(s.hs_start)) & "/" &
                 integer'image(to_integer(s.hs_end)) severity failure;
      end if;
      ab := to_integer(s.frame) * VA + to_integer(s.line);
      if first then
        assert s.line = 0 and s.flags(RF_FIRST) = '1' report "first line after enable is not line 0" severity failure;
        assert s.drops = 0 report "drops on first line" severity failure;
      else
        assert ab = prev_abs + 1 + to_integer(s.drops)
          report "line sequence: " & integer'image(ab) & " after " & integer'image(prev_abs) &
                 " drops " & integer'image(to_integer(s.drops)) severity failure;
      end if;
      if s.drops /= 0 then ndrop := ndrop + 1; end if;
      first := false;
      prev_abs := ab;
      for i in 0 to to_integer(s.count) - 1 loop
        raddr <= resize(s.start + i, RING_AW);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert rdata = pat(i, to_integer(s.line))
          report "pixel " & integer'image(i) & " of line " & integer'image(to_integer(s.line)) severity failure;
      end loop;
      pop <= '1';
      wait until rising_edge(clk);
      pop <= '0';
      wait until rising_edge(clk);
      n := n + 1;
    end procedure;
  begin
    first := true; n := 0; ndrop := 0; prev_abs := 0;
    -- disabled: nothing captured
    wait for 3 * 16 * LINE_T;
    assert valid = '0' report "captured while disabled" severity failure;
    -- 1. three frames read promptly
    enable <= '1';
    for i in 0 to 3 * VA - 1 loop
      take;
    end loop;
    fr0 := d.frame;
    assert ndrop = 0 report "drops while reading promptly" severity failure;
    report "phase 1: " & integer'image(n) & " lines OK";
    -- 2. stall for 20 lines: ring (256 px) holds 5 lines of 40 with room for 64
    wait for 20 * LINE_T;
    for i in 0 to 2 * VA - 1 loop
      take;
    end loop;
    assert ndrop = 1 report "expected exactly one line with the dropped flag, got " &
      integer'image(ndrop) severity failure;
    report "phase 2: drops flagged once, sequence consistent";
    -- 3. disable, drain, nothing more; re-enable restarts at line 0
    enable <= '0';
    wait for 2 * LINE_T;
    while valid = '1' loop
      take;
    end loop;
    wait for 2 * 16 * LINE_T;
    assert valid = '0' report "captured after disable" severity failure;
    enable <= '1';
    first := true;
    for i in 0 to VA - 1 loop
      take;
    end loop;
    report "tb_raster_capture PASSED (" & integer'image(n) & " lines)";
    done <= true;
    wait;
  end process;
end architecture;
