-- dvi_tx_xc7: DVI (TMDS) transmitter, 3 data lanes + clock.
-- Adapted from the owner's hardweb dvi_tx_simple (reuse directed by the
-- owner; LGPL-2.1-or-later here): MEGA65/Tyto hdmi_tx_encoder (LGPL-3.0+,
-- third_party/mega65-core) per lane, 10-bit symbols shifted out two bits per
-- serial clock through ODDR at 5x the pixel clock, OBUFDS (TMDS_33).
-- The symbol load is aligned to a pixel-clock toggle sampled in the serial
-- domain (hardweb's fix for a load/edge race that nextpnr cannot time).
-- SIM => true replaces ODDR/OBUFDS with behavioural models.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_tx_encoder_pkg.all;
use work.xc7_prims_pkg.all;

entity dvi_tx_xc7 is
  generic (SIM : boolean := false);
  port (
    pixel_clk  : in  std_logic;   -- 27 MHz
    serial_clk : in  std_logic;   -- 135 MHz (5x), phase aligned
    rst        : in  std_logic;
    r, g, b    : in  std_logic_vector(7 downto 0);
    hs, vs, de : in  std_logic;
    tmds_p, tmds_n : out std_logic_vector(2 downto 0);
    tmds_clk_p, tmds_clk_n : out std_logic
  );
end entity;

architecture rtl of dvi_tx_xc7 is
  signal t_r, t_g, t_b : std_logic_vector(9 downto 0);
  signal sh_r, sh_g, sh_b : std_logic_vector(9 downto 0) := (others => '0');
  signal sh_c  : std_logic_vector(9 downto 0) := "0000011111";
  signal phase : unsigned(2 downto 0) := (others => '0');
  signal pix_tog, tog1, tog2, aligned : std_logic := '0';
  type pair_arr is array (0 to 3) of std_logic_vector(1 downto 0);
  signal ddr : pair_arr := (others => "00");
  signal ser : std_logic_vector(3 downto 0);
begin
  enc_r : entity work.hdmi_tx_encoder generic map (channel => 2)
    port map (rst => rst, clk => pixel_clk, de => de, p => r, enc => ENC_DVI,
              c => "00", d => (others => '0'), q => t_r);
  enc_g : entity work.hdmi_tx_encoder generic map (channel => 1)
    port map (rst => rst, clk => pixel_clk, de => de, p => g, enc => ENC_DVI,
              c => "00", d => (others => '0'), q => t_g);
  enc_b : entity work.hdmi_tx_encoder generic map (channel => 0)
    port map (rst => rst, clk => pixel_clk, de => de, p => b, enc => ENC_DVI,
              c => vs & hs, d => (others => '0'), q => t_b);

  process (pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      pix_tog <= not pix_tog;
    end if;
  end process;

  process (serial_clk)
  begin
    if rising_edge(serial_clk) then
      tog1 <= pix_tog;
      tog2 <= tog1;
      if rst = '1' then
        aligned <= '0';
        phase   <= (others => '0');
        sh_r <= (others => '0'); sh_g <= (others => '0'); sh_b <= (others => '0');
        sh_c <= "0000011111";
      elsif aligned = '0' and tog1 /= tog2 then
        aligned <= '1';
        phase   <= to_unsigned(4, 3);
      elsif phase = 4 then
        phase <= (others => '0');
        sh_r <= t_r; sh_g <= t_g; sh_b <= t_b;
        sh_c <= "0000011111";
      else
        phase <= phase + 1;
        sh_r <= "00" & sh_r(9 downto 2);
        sh_g <= "00" & sh_g(9 downto 2);
        sh_b <= "00" & sh_b(9 downto 2);
        sh_c <= "00" & sh_c(9 downto 2);
      end if;
      ddr(0) <= sh_b(1 downto 0);
      ddr(1) <= sh_g(1 downto 0);
      ddr(2) <= sh_r(1 downto 0);
      ddr(3) <= sh_c(1 downto 0);
    end if;
  end process;

  g_lane : for i in 0 to 3 generate
    g_hw : if not SIM generate
      o : ODDR generic map (DDR_CLK_EDGE => "SAME_EDGE", SRTYPE => "SYNC")
        port map (Q => ser(i), C => serial_clk, CE => '1',
                  D1 => ddr(i)(0), D2 => ddr(i)(1), R => '0', S => '0');
    end generate;
    g_sim : if SIM generate
      ser(i) <= ddr(i)(0) when serial_clk = '1' else ddr(i)(1);
    end generate;
  end generate;

  g_obuf : if not SIM generate
    ob0 : OBUFDS port map (I => ser(0), O => tmds_p(0), OB => tmds_n(0));
    ob1 : OBUFDS port map (I => ser(1), O => tmds_p(1), OB => tmds_n(1));
    ob2 : OBUFDS port map (I => ser(2), O => tmds_p(2), OB => tmds_n(2));
    obc : OBUFDS port map (I => ser(3), O => tmds_clk_p, OB => tmds_clk_n);
  end generate;
  g_simbuf : if SIM generate
    tmds_p <= ser(2 downto 0); tmds_n <= not ser(2 downto 0);
    tmds_clk_p <= ser(3); tmds_clk_n <= not ser(3);
  end generate;
end architecture;
