-- tb_megakey_mk1_compat: the type-3 keyboard CPLD firmware (OSCH 24.18 MHz,
-- MK-I logic on a clock enable) must behave exactly like upstream 2ed09bd
-- (OSCH 12.09 MHz) towards an MK-I host (issue 0046, ADR 0014).
--
-- Both CPLDs run side by side from aligned oscillator models (every second
-- 24.18 MHz edge coincides with a 12.09 MHz edge), each with its own key
-- matrix model fed the same key presses, and share KIO8/KIO9 from one
-- kbd_mk1_host (this repo's MK-I host, the reference). A second, identical
-- host reads the new CPLD's KIO10. Checked:
-- * at every 12.09 MHz edge: KIO10, all 14 LED outputs and SCAN_OUT are
--   identical (the new KIO10 has one extra 24.18 MHz register stage, which
--   settles before the next 12.09 MHz edge);
-- * every published frame of the two hosts is identical (keys, commit id);
-- * the new CPLD never enters type 3 while the MK-I host clocks;
-- * a few keys map to the expected MEGA65 matrix positions (F3, DEL,
--   RETURN, SPACE, CAPS LOCK latch + raw key, SHIFT LOCK into LEFT SHIFT).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_megakey_mk1_compat is
end entity;

architecture tb of tb_megakey_mk1_compat is
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal kio8, kio9, kio8_b, kio9_b : std_logic;
  signal k10_old, k10_new : std_logic;
  signal so_old, so_new : std_logic_vector(9 downto 0);
  signal si_old, si_new : std_logic_vector(7 downto 0);
  signal keys    : std_logic_vector(79 downto 0) := (others => '0');
  signal restore : std_logic := '1';
  signal leds    : std_logic_vector(95 downto 0) := x"102030_405060_708090_A0B0C0";
  signal pa, pb  : std_logic_vector(79 downto 0);
  signal sa, sb  : std_logic;
  signal ca, cb  : std_logic_vector(31 downto 0);
  signal led_old, led_new : std_logic_vector(13 downto 0);
  signal frames, cmp_edges : natural := 0;

  function phys(r, c : natural) return natural is
  begin
    return 8 * r + c;
  end function;
begin
  clk <= not clk after 4 ns when not done;

  host_a : entity work.kbd_mk1_host
    port map (clk => clk, kio8 => kio8, kio9 => kio9, kio10 => k10_old, leds => leds,
              pressed => pa, strobe => sa, present => open, kbd_commit => ca);
  host_b : entity work.kbd_mk1_host
    port map (clk => clk, kio8 => kio8_b, kio9 => kio9_b, kio10 => k10_new, leds => leds,
              pressed => pb, strobe => sb, present => open, kbd_commit => cb);

  old_kbd : entity work.megakey_2ed09bd
    port map (KIO8 => kio8, KIO9 => kio9, KIO10 => k10_old, SCAN_OUT => so_old, SCAN_IN => si_old,
              KEY_RESTORE => restore,
              LED_R0 => led_old(0), LED_G0 => led_old(1), LED_B0 => led_old(2),
              LED_R1 => led_old(3), LED_G1 => led_old(4), LED_B1 => led_old(5),
              LED_R2 => led_old(6), LED_G2 => led_old(7), LED_B2 => led_old(8),
              LED_R3 => led_old(9), LED_G3 => led_old(10), LED_B3 => led_old(11),
              LED_SHIFT => led_old(12), LED_CAPS => led_old(13));
  new_kbd : entity work.megakey_t3
    port map (KIO8 => kio8, KIO9 => kio9, KIO10 => k10_new, SCAN_OUT => so_new, SCAN_IN => si_new,
              KEY_RESTORE => restore,
              LED_R0 => led_new(0), LED_G0 => led_new(1), LED_B0 => led_new(2),
              LED_R1 => led_new(3), LED_G1 => led_new(4), LED_B1 => led_new(5),
              LED_R2 => led_new(6), LED_G2 => led_new(7), LED_B2 => led_new(8),
              LED_R3 => led_new(9), LED_G3 => led_new(10), LED_B3 => led_new(11),
              LED_SHIFT => led_new(12), LED_CAPS => led_new(13));
  mat_old : entity work.kbd_matrix_model port map (so_old, keys, si_old);
  mat_new : entity work.kbd_matrix_model port map (so_new, keys, si_new);

  -- lock-step comparison at every 12.09 MHz edge (signals read here hold
  -- the values from before this edge)
  cmp : process
    alias old_clk is << signal .tb_megakey_mk1_compat.old_kbd.clk : std_logic >>;
    alias new_t3  is << signal .tb_megakey_mk1_compat.new_kbd.t3 : std_logic >>;
  begin
    wait until rising_edge(old_clk);
    if now > 1 us then
      assert k10_old = k10_new
        report "KIO10 differs: old " & std_logic'image(k10_old) & " new " & std_logic'image(k10_new)
        severity failure;
      assert led_old = led_new
        report "LEDs differ: old " & to_string(led_old) & " new " & to_string(led_new) severity failure;
      assert so_old = so_new report "SCAN_OUT differs" severity failure;
      assert new_t3 = '0' report "new CPLD entered type 3 under an MK-I host" severity failure;
      cmp_edges <= cmp_edges + 1;
    end if;
  end process;

  frm : process
  begin
    wait until rising_edge(clk) and sa = '1';
    -- the two hosts are identical and in lock step
    assert sb = '1' report "hosts out of step" severity failure;
    assert kio8 = kio8_b and kio9 = kio9_b report "host pins differ" severity failure;
    if frames >= 2 then
      assert pa = pb report "frame keys differ: " & to_hstring(pa) & " vs " & to_hstring(pb)
        severity failure;
      assert ca = cb report "frame commit differs" severity failure;
    end if;
    frames <= frames + 1;
  end process;

  stim : process
    variable want : std_logic_vector(79 downto 0);
    procedure frames_wait(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk) and sa = '1';
      end loop;
    end procedure;
  begin
    wait for 1500 us;
    assert ca = x"2ed09bd3" report "commit id " & to_hstring(ca) severity failure;
    assert pa(71 downto 0) = (71 downto 0 => '0') report "keys without presses" severity failure;

    -- F3 (row 1 col 0) -> 5, DEL (0,5) -> 0 (+76), RETURN (5,7) -> 1 (+77),
    -- SPACE (4,5) -> 60
    keys(phys(1, 0)) <= '1'; keys(phys(0, 5)) <= '1';
    keys(phys(5, 7)) <= '1'; keys(phys(4, 5)) <= '1';
    frames_wait(4);
    want := (5 | 0 | 76 | 1 | 77 | 60 => '1', others => '0');
    assert pa = want report "MK-I keys " & to_hstring(pa) severity failure;
    keys <= (others => '0');
    frames_wait(3);
    assert pa = (79 downto 0 => '0') report "keys not released" severity failure;

    -- CAPS LOCK (5,0): raw key 78 while held, latched state 72 toggles
    keys(phys(5, 0)) <= '1';
    leds <= x"FF0000_00FF00_0000FF_808080";
    frames_wait(4);
    assert pa(78) = '1' and pa(72) = '1' report "CAPS LOCK press " & to_hstring(pa) severity failure;
    keys(phys(5, 0)) <= '0';
    frames_wait(4);
    assert pa(78) = '0' and pa(72) = '1' report "CAPS LOCK latch " & to_hstring(pa) severity failure;

    -- SHIFT LOCK (8,3) latches LEFT SHIFT (15)
    keys(phys(8, 3)) <= '1';
    frames_wait(4);
    keys(phys(8, 3)) <= '0';
    restore <= '0';
    frames_wait(4);
    assert pa(15) = '1' report "SHIFT LOCK -> LEFT SHIFT " & to_hstring(pa) severity failure;
    restore <= '1';
    leds <= (others => '0');
    frames_wait(4);

    assert cmp_edges > 50000 report "too few comparisons" severity failure;
    report "tb_megakey_mk1_compat PASSED (" & integer'image(frames) & " frames, " &
           integer'image(cmp_edges) & " lock-step edges)";
    done <= true;
    wait;
  end process;
end architecture;
