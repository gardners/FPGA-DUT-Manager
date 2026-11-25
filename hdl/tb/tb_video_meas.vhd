-- tb_video_meas: geometry, polarity, frame count and pixel clock measured
-- from video_timing (small mode, negative syncs) at a 37 ns pixel clock.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_video_meas is
end entity;

architecture tb of tb_video_meas is
  signal pclk, clk : std_logic := '0';
  signal done : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs, hp, vp, present : std_logic;
  signal ht, vt, ha, va : unsigned(15 downto 0);
  signal frames, hz : unsigned(31 downto 0);
begin
  pclk <= not pclk after 18.5 ns when not done;   -- 27.03 MHz
  clk  <= not clk after 4 ns when not done;       -- 125 MHz
  tim : entity work.video_timing
    generic map (H_ACTIVE => 40, H_FP => 4, H_SYNC => 6, H_BP => 10,
                 V_ACTIVE => 20, V_FP => 2, V_SYNC => 3, V_BP => 5, SYNC_POL => '0')
    port map (pclk, x, y, de, hs, vs, fs);
  dut : entity work.video_meas generic map (CLK_HZ => 12_500)    -- 100 us window
    port map (pclk, de, hs, vs, clk, ht, vt, ha, va, hp, vp, frames, hz, present);
  process
  begin
    wait for 500 us;
    report "meas: " & integer'image(to_integer(ht)) & "x" & integer'image(to_integer(vt)) &
           " active " & integer'image(to_integer(ha)) & "x" & integer'image(to_integer(va)) &
           " frames " & integer'image(to_integer(frames)) & " hz/window " & integer'image(to_integer(hz));
    assert ht = 60 and vt = 30 and ha = 40 and va = 20 report "geometry wrong" severity failure;
    assert hp = '0' and vp = '0' report "polarity wrong" severity failure;
    assert frames >= 4 report "frames not counted" severity failure;
    -- 100 us / 37 ns = 2702 pixel clocks per window
    assert hz >= 2700 and hz <= 2704 report "pixel clock count wrong" severity failure;
    report "tb_video_meas PASSED";
    done <= true;
    wait;
  end process;
end architecture;
