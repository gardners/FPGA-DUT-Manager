-- tb_text_display: TEXT_WRITE frames into text_rx_tap (clk_rx), render with
-- video_timing + text_display (27 MHz) and dump one complete frame for
-- tests/scenarios/tb_text_display.py to compare against a reference render.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_text_display is
  generic (VEC_IN : string := "text_in.txt"; CAP_OUT : string := "text_out.txt");
end entity;

architecture tb of tb_text_display is
  signal clk_rx, clk_pix : std_logic := '0';
  signal done : boolean := false;
  signal rx_dv : std_logic := '0';
  signal rxd : std_logic_vector(7 downto 0) := (others => '0');
  signal we : std_logic;
  signal wa : unsigned(14 downto 0);
  signal wd : std_logic_vector(7 downto 0);
  signal frames : unsigned(15 downto 0);
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal r, g, b : std_logic_vector(7 downto 0);
  signal de_o, hs_o, vs_o, force_text : std_logic;
  signal sent_all : boolean := false;
begin
  clk_rx  <= not clk_rx after 4 ns when not done;
  clk_pix <= not clk_pix after 18.518 ns when not done;

  tap : entity work.text_rx_tap
    port map (clk_rx, rx_dv, rxd, x"024D36350000", x"024D36350001", we, wa, wd, frames);
  tim : entity work.video_timing port map (clk_pix, x, y, de, hs, vs, fs);
  txt : entity work.text_display
    port map (clk_rx, we, wa, wd, clk_pix, x, y, de, hs, vs, r, g, b, de_o, hs_o, vs_o, force_text);

  drive : process
    file fin : text open read_mode is VEC_IN;
    variable l : line;
    variable delay, n : integer;
    variable bv : std_logic_vector(7 downto 0);
    type buf_t is array (0 to 8191) of std_logic_vector(7 downto 0);
    variable buf : buf_t;
  begin
    wait for 1 us;
    while not endfile(fin) loop
      readline(fin, l);
      read(l, delay);
      read(l, n);
      for i in 0 to n - 1 loop
        hread(l, bv);
        buf(i) := bv;
      end loop;
      wait for delay * 1 us;
      wait until rising_edge(clk_rx);
      for i in 0 to 7 loop
        rx_dv <= '1';
        if i = 7 then rxd <= x"D5"; else rxd <= x"55"; end if;
        wait until rising_edge(clk_rx);
      end loop;
      for i in 0 to n - 1 loop
        rxd <= buf(i);
        wait until rising_edge(clk_rx);
      end loop;
      rx_dv <= '0';
      for i in 0 to 11 loop
        wait until rising_edge(clk_rx);
      end loop;
    end loop;
    sent_all <= true;
    wait;
  end process;

  -- dump the first complete frame that starts after all writes
  cap : process
    file fout : text open write_mode is CAP_OUT;
    variable l : line;
    variable vs_prev : std_logic := '1';
    variable started : boolean := false;
    variable lines : natural := 0;
    variable de_prev : std_logic := '0';
  begin
    wait until sent_all;
    -- wait for the start of the next frame at the renderer output
    loop
      wait until rising_edge(clk_pix);
      exit when vs_o = '0' and vs_prev = '1';
      vs_prev := vs_o;
    end loop;
    loop
      wait until rising_edge(clk_pix);
      if de_o = '1' then
        hwrite(l, r & g & b);
        write(l, string'(" "));
      elsif de_prev = '1' then
        writeline(fout, l);
        lines := lines + 1;
      end if;
      de_prev := de_o;
      exit when lines = 480;
    end loop;
    report "text frames accepted " & integer'image(to_integer(frames)) &
      ", control force=" & std_logic'image(force_text);
    report "tb_text_display PASSED (dumped); run scenario check";
    done <= true;
    wait;
  end process;
end architecture;
