-- tb_kbd_mk1_device: our MK-I keyboard emulator (125 MHz) driven by the real
-- MEGA65 host-side decoder mega65kbd_to_matrix (40.5 MHz, from mega65-core).
-- Checks every matrix key 0..71 and the dedicated lines 72..75 for several
-- bitmaps, and that LED data from the host arrives.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_mk1_device is
end entity;

architecture tb of tb_kbd_mk1_device is
  signal clk125   : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal done     : boolean := false;

  signal keys     : std_logic_vector(79 downto 0) := (others => '0');
  signal kio8, kio9, kio10 : std_logic;
  signal leds     : std_logic_vector(95 downto 0);
  signal leds_stb : std_logic;
  signal frames   : unsigned(15 downto 0);

  signal col_idx  : integer range 0 to 15 := 0;
  signal col      : std_logic_vector(7 downto 0);
  signal restore, capslock, upkey, leftkey : std_logic;
  signal kbd_commit : unsigned(31 downto 0);

  type pat_t is array (natural range <>) of std_logic_vector(79 downto 0);
  constant PATS : pat_t := (
    x"00000000000000000000",
    x"00000000000000000001",            -- DEL only
    x"0000_0000_0000_0000_8000",        -- key 15 (LSHIFT)
    x"00FF_0000_0000_0000_0000",        -- extra lines 72..79
    x"005A_A5C3_3C96_6912_4801",
    x"00FF_FFFF_FFFF_FFFF_FFFF",
    x"0000_0000_0000_8000_0000"         -- key 31
  );
begin
  clk125   <= not clk125 after 4 ns when not done;
  cpuclock <= not cpuclock after 12.345 ns when not done;

  dut : entity work.kbd_mk1_device
    port map (
      clk => clk125, keys_pressed => keys,
      kio8_in => kio8, kio9_in => kio9, kio10_out => kio10,
      leds => leds, leds_strobe => leds_stb, frame_count => frames);

  host : entity work.mega65kbd_to_matrix
    port map (
      cpuclock => cpuclock,
      flopmotor => '0', flopled0 => '0', flopled2 => '0', flopledsd => '0',
      powerled => '1', eth_load_enable => '0',
      kbd_commit => kbd_commit,
      kio8 => kio8, kio9 => kio9, kio10 => kio10,
      matrix_col => col, matrix_col_idx => col_idx,
      restore => restore, capslock_out => capslock,
      upkey => upkey, leftkey => leftkey);

  stim : process
    variable errors : natural := 0;
    variable got    : std_logic;
    variable want   : std_logic_vector(79 downto 0);
    procedure wait_frames(n : natural) is
      variable start : unsigned(15 downto 0);
    begin
      start := frames;
      while frames - start < n loop
        wait until rising_edge(clk125);
      end loop;
    end procedure;
  begin
    wait_frames(2);
    for p in PATS'range loop
      keys <= PATS(p);
      want := PATS(p);
      wait_frames(3);
      for k in 0 to 71 loop
        col_idx <= k / 8;
        wait until rising_edge(cpuclock);
        wait until rising_edge(cpuclock);
        got := col(k mod 8);
        if got /= not want(k) then
          report "pattern " & integer'image(p) & " key " & integer'image(k) &
            " expected " & std_logic'image(not want(k)) & " got " & std_logic'image(got)
            severity error;
          errors := errors + 1;
        end if;
      end loop;
      -- dedicated lines: capslock/restore active low, up/left active high
      if capslock /= not want(72) then errors := errors + 1;
        report "pattern " & integer'image(p) & " capslock wrong" severity error; end if;
      if upkey /= want(73) then errors := errors + 1;
        report "pattern " & integer'image(p) & " up wrong" severity error; end if;
      if leftkey /= want(74) then errors := errors + 1;
        report "pattern " & integer'image(p) & " left wrong" severity error; end if;
      if restore /= not want(75) then errors := errors + 1;
        report "pattern " & integer'image(p) & " restore wrong" severity error; end if;
    end loop;

    -- Host sends power LED green (x00FF00) on LEDs 2 and 3, zeros elsewhere.
    report "LED vector received: " & to_hstring(leds);
    if leds = (leds'range => '0') then
      report "no LED data received" severity error;
      errors := errors + 1;
    end if;
    report "host saw keyboard commit id " & to_hstring(std_logic_vector(kbd_commit));

    assert errors = 0 report integer'image(errors) & " errors" severity failure;
    report "tb_kbd_mk1_device PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture;
