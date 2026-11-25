-- tb_text_screens: text_display screens 1/2 and the select-screen overlay
-- (issue 0029): sample rendered pixels at known cells.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_text_screens is
end entity;

architecture tb of tb_text_screens is
  constant TOP : natural := 40;
  constant OVX : natural := 5;          -- (78 - 68) / 2
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs, de_o, hs_o, vs_o, ft : std_logic;
  signal r, g, b : std_logic_vector(7 downto 0);
  signal screen : unsigned(1 downto 0) := "00";
  signal slots : std_logic_vector(9 downto 0) := "1111111011";   -- machine 2 absent
  type d_t is array (0 to 5) of unsigned(10 downto 0);   -- output is 4 clocks behind x
  signal xd, yd : d_t := (others => (others => '0'));
begin
  clk <= not clk after 18.5 ns when not done;
  tim : entity work.video_timing port map (clk, x, y, de, hs, vs, fs);
  dut : entity work.text_display
    port map (wr_clk => clk, wr_en => '0', wr_addr => (others => '0'), wr_data => x"00",
              clk_pix => clk, x => x, y => y, de_in => de, hs_in => hs, vs_in => vs,
              r => r, g => g, b => b, de_out => de_o, hs_out => hs_o, vs_out => vs_o,
              force_text => ft, screen => screen, slots => slots);
  process (clk)
  begin
    if rising_edge(clk) then
      xd <= x & xd(0 to 4); yd <= y & yd(0 to 4);
    end if;
  end process;

  process
    -- wait until the output shows pixel (px, py) and return its colour
    procedure pix(px, py : natural; rgb : out std_logic_vector(23 downto 0)) is
    begin
      loop
        wait until rising_edge(clk);
        exit when de_o = '1' and xd(3) = px and yd(3) = py;
      end loop;
      wait for 1 ns;
      rgb := r & g & b;
    end procedure;
    procedure expect(px, py : natural; want : std_logic_vector(23 downto 0); what : string) is
      variable got : std_logic_vector(23 downto 0);
    begin
      pix(px, py, got);
      assert got = want report what & ": got " & to_hstring(got) & " want " & to_hstring(want)
        severity failure;
    end procedure;
    function cx(col, sub : natural) return natural is begin return col * 9 + sub; end function;
    function cy(row, sub : natural) return natural is begin return TOP + row * 16 + sub; end function;
    variable got : std_logic_vector(23 downto 0);
  begin
    -- screen 1 (no video): black on green background
    screen <= "01";
    expect(cx(2, 0), cy(2, 0), x"00AA00", "screen 1 background");
    -- screen 2 (select): black background, boxes in LED colours
    screen <= "10";
    expect(cx(2, 0), cy(2, 0), x"000000", "screen 2 background");
    expect(cx(OVX, 0), cy(11, 0), x"FF0000", "box 1 (machine 0) red");
    expect(cx(OVX + 7 * 3 + 4, 8), cy(13, 15), x"00FE00", "box 4 (machine 3) green, last cell");
    expect(cx(OVX + 7 * 7, 0), cy(11, 0), x"7F0000", "box 8 (machine 7) half red");
    expect(cx(OVX + 5, 0), cy(12, 0), x"000000", "gap between boxes");
    expect(cx(OVX + 7 * 3 - 1, 8), cy(12, 2), x"000000", "last gap pixel before box 4");
    expect(cx(OVX + 7 * 3, 0), cy(12, 2), x"00FE00", "first pixel of box 4");
    -- digit '1' in box 1: CP437 '1' row 5 (cy 5) has pixel 3 set -> black fg
    expect(cx(OVX + 2, 3), cy(12, 5), x"000000", "digit 1 foreground");
    expect(cx(OVX + 2, 0), cy(12, 5), x"FF0000", "digit 1 background");
    -- machine 2 absent: frown in box 3 (yellow); frown row 4 = A5 -> pixel 0 set
    expect(cx(OVX + 7 * 2 + 2, 0), cy(12, 4), x"000000", "frown eye pixel");
    expect(cx(OVX + 7 * 2 + 2, 1), cy(12, 4), x"FFC000", "frown background");
    report "tb_text_screens PASSED";
    done <= true;
    wait;
  end process;
end architecture;
