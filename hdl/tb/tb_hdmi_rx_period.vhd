-- tb_hdmi_rx_period: HDMI-aware receive DE (issue 0040) on our own HDMI OUT.
--
-- Two transmitters run the console timing (720x480p60, 858x525): dvi_tx_xc7
-- with HDMI => true (guard bands, AVI + SPD data islands, issue 0037) and
-- with HDMI => false (pure DVI). Their 10-bit encoder outputs (taken with
-- external names; tb_hdmi_tx covers the serialiser) go through a model of
-- dvi2rgb's TMDS_Decode stage (control token -> C0/C1, else DE = 1 and the
-- 8b decode), then hdmi_rx_period and video_meas. Checks:
--   * HDMI and DVI both measure exactly 720x480 of 858x525;
--   * every filtered DE pixel is the transmitted one (r = x, g = x + 85,
--     b = not x, x counted from each DE rise), so no guard band char leaks;
--   * hdmi_seen and island_seen are set for HDMI, clear for DVI;
--   * the unfiltered dvi2rgb DE on the HDMI stream measures 722 wide (the
--     problem this block fixes - proves the test exercises it).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hdmi_rx_period is
end entity;

architecture tb of tb_hdmi_rx_period is
  constant TPIX : time := 37.037 ns;
  signal clk_pix, clk5, clk : std_logic := '0';
  signal done : boolean := false;
  signal rst : std_logic := '1';
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal r, g, b : std_logic_vector(7 downto 0);

  type q_arr is array (0 to 2) of std_logic_vector(9 downto 0);
  type d_arr is array (0 to 2) of std_logic_vector(7 downto 0);
  type rx_t is record
    de, c0, c1 : std_logic_vector(2 downto 0);
    d : d_arr;
  end record;
  signal rx_h, rx_d : rx_t := ((others => '0'), (others => '0'), (others => '0'), (others => x"00"));
  signal fde_h, fde_d, hdmi_h, isl_h, hdmi_d, isl_d, fhs_h, fvs_h, fhs_d, fvs_d : std_logic;

  type meas_t is record
    ht, vt, ha, va : unsigned(15 downto 0);
  end record;
  signal m_h, m_d, m_raw : meas_t;

  function decode(q : std_logic_vector(9 downto 0)) return std_logic_vector is
    variable d : std_logic_vector(7 downto 0);
    variable qq : std_logic_vector(7 downto 0);
  begin
    qq := q(7 downto 0);
    if q(9) = '1' then qq := not qq; end if;
    d(0) := qq(0);
    for i in 1 to 7 loop
      if q(8) = '1' then d(i) := qq(i) xor qq(i - 1); else d(i) := not (qq(i) xor qq(i - 1)); end if;
    end loop;
    return d;
  end function;

  -- dvi2rgb TMDS_Decode, all three channels (C0/C1 hold on data chars)
  function rx_dec(q : q_arr; prev : rx_t) return rx_t is
    variable o : rx_t;
  begin
    o := prev;
    for i in 0 to 2 loop
      o.d(i) := x"00"; o.de(i) := '0';
      case q(i) is
        when "1101010100" => o.c0(i) := '0'; o.c1(i) := '0';
        when "0010101011" => o.c0(i) := '1'; o.c1(i) := '0';
        when "0101010100" => o.c0(i) := '0'; o.c1(i) := '1';
        when "1010101011" => o.c0(i) := '1'; o.c1(i) := '1';
        when others => o.de(i) := '1'; o.d(i) := decode(q(i));
      end case;
    end loop;
    return o;
  end function;
begin
  clk_pix <= not clk_pix after TPIX / 2 when not done;
  clk5    <= not clk5 after TPIX / 10 when not done;
  clk     <= not clk after 40 ns when not done;      -- 12.5 MHz "clk_sys"

  tim : entity work.video_timing
    port map (clk_pix, x, y, de, hs, vs, fs);
  r <= std_logic_vector(x(7 downto 0));
  g <= std_logic_vector(x(7 downto 0) + 85);
  b <= std_logic_vector(not x(7 downto 0));
  rst <= '0' after 200 ns;

  tx_h : entity work.dvi_tx_xc7 generic map (SIM => true, HDMI => true)
    port map (pixel_clk => clk_pix, serial_clk => clk5, rst => rst,
              r => r, g => g, b => b, hs => hs, vs => vs, de => de,
              tmds_p => open, tmds_n => open, tmds_clk_p => open, tmds_clk_n => open,
              vic => "0000011", machine => to_unsigned(5, 5), machine_ok => '1');
  tx_d : entity work.dvi_tx_xc7 generic map (SIM => true, HDMI => false)
    port map (pixel_clk => clk_pix, serial_clk => clk5, rst => rst,
              r => r, g => g, b => b, hs => hs, vs => vs, de => de,
              tmds_p => open, tmds_n => open, tmds_clk_p => open, tmds_clk_n => open);

  dec : process (clk_pix)
    alias hb is << signal .tb_hdmi_rx_period.tx_h.t_b : std_logic_vector(9 downto 0) >>;
    alias hg is << signal .tb_hdmi_rx_period.tx_h.t_g : std_logic_vector(9 downto 0) >>;
    alias hr is << signal .tb_hdmi_rx_period.tx_h.t_r : std_logic_vector(9 downto 0) >>;
    alias db is << signal .tb_hdmi_rx_period.tx_d.t_b : std_logic_vector(9 downto 0) >>;
    alias dg is << signal .tb_hdmi_rx_period.tx_d.t_g : std_logic_vector(9 downto 0) >>;
    alias dr is << signal .tb_hdmi_rx_period.tx_d.t_r : std_logic_vector(9 downto 0) >>;
  begin
    if rising_edge(clk_pix) then
      rx_h <= rx_dec((hb, hg, hr), rx_h);
      rx_d <= rx_dec((db, dg, dr), rx_d);
    end if;
  end process;

  per_h : entity work.hdmi_rx_period
    port map (clk => clk_pix, de_in => rx_h.de(0), hs_in => rx_h.c0(0), vs_in => rx_h.c1(0),
              d0 => rx_h.d(0), ctl => rx_h.c1(2) & rx_h.c0(2) & rx_h.c1(1) & rx_h.c0(1),
              de_out => fde_h, hs_out => fhs_h, vs_out => fvs_h, hdmi_seen => hdmi_h, island_seen => isl_h);
  per_d : entity work.hdmi_rx_period
    port map (clk => clk_pix, de_in => rx_d.de(0), hs_in => rx_d.c0(0), vs_in => rx_d.c1(0),
              d0 => rx_d.d(0), ctl => rx_d.c1(2) & rx_d.c0(2) & rx_d.c1(1) & rx_d.c0(1),
              de_out => fde_d, hs_out => fhs_d, vs_out => fvs_d, hdmi_seen => hdmi_d, island_seen => isl_d);

  meas_h : entity work.video_meas generic map (CLK_HZ => 12_500)
    port map (pclk => clk_pix, de => fde_h, hs => fhs_h, vs => fvs_h, clk => clk,
              h_total => m_h.ht, v_total => m_h.vt, h_active => m_h.ha, v_active => m_h.va,
              hs_pol => open, vs_pol => open, frames => open, pixel_hz => open, present => open);
  meas_d : entity work.video_meas generic map (CLK_HZ => 12_500)
    port map (pclk => clk_pix, de => fde_d, hs => fhs_d, vs => fvs_d, clk => clk,
              h_total => m_d.ht, v_total => m_d.vt, h_active => m_d.ha, v_active => m_d.va,
              hs_pol => open, vs_pol => open, frames => open, pixel_hz => open, present => open);
  meas_raw : entity work.video_meas generic map (CLK_HZ => 12_500)
    port map (pclk => clk_pix, de => rx_h.de(0), hs => rx_h.c0(0), vs => rx_h.c1(0), clk => clk,
              h_total => m_raw.ht, v_total => m_raw.vt, h_active => m_raw.ha, v_active => m_raw.va,
              hs_pol => open, vs_pol => open, frames => open, pixel_hz => open, present => open);

  -- every pixel the filtered DE passes is the transmitted pixel; the HDMI
  -- HSYNC leading edges stay exactly one line apart (islands span HSYNC).
  -- Checked from the second frame on (the TX reset cuts into the first).
  pix : process (clk_pix)
    variable n_h, n_d : natural := 0;
    variable de_hp, de_dp : std_logic := '0';
    variable hs_p : std_logic := '0';
    variable hcnt, edges : natural := 0;
  begin
    if rising_edge(clk_pix) and now > 858 * 525 * TPIX then
      hcnt := hcnt + 1;
      if fhs_h = '0' and hs_p = '1' then      -- sync is active low
        edges := edges + 1;
        assert edges < 3 or hcnt = 858
          report "HDMI HSYNC period " & integer'image(hcnt) severity failure;
        hcnt := 0;
      end if;
      hs_p := fhs_h;
      if fde_h = '1' then
        if de_hp = '0' then n_h := 0; end if;
        assert rx_h.d(2) = std_logic_vector(to_unsigned(n_h mod 256, 8)) and
               rx_h.d(1) = std_logic_vector(to_unsigned(n_h mod 256, 8) + 85) and
               rx_h.d(0) = not std_logic_vector(to_unsigned(n_h mod 256, 8))
          report "HDMI: pixel " & integer'image(n_h) & " is not the transmitted one" severity failure;
        n_h := n_h + 1;
      end if;
      if fde_d = '1' then
        if de_dp = '0' then n_d := 0; end if;
        assert rx_d.d(2) = std_logic_vector(to_unsigned(n_d mod 256, 8))
          report "DVI: pixel " & integer'image(n_d) & " is not the transmitted one" severity failure;
        n_d := n_d + 1;
      end if;
      de_hp := fde_h; de_dp := fde_d;
    end if;
  end process;

  check : process
    procedure show(name : string; m : meas_t) is
    begin
      report name & ": " & integer'image(to_integer(m.ha)) & "x" & integer'image(to_integer(m.va)) &
        " of " & integer'image(to_integer(m.ht)) & "x" & integer'image(to_integer(m.vt));
    end procedure;
  begin
    wait for 4 * 858 * 525 * TPIX;     -- 4 frames
    show("HDMI filtered", m_h); show("DVI", m_d); show("HDMI unfiltered", m_raw);
    report "HDMI seen " & std_logic'image(hdmi_h) & " islands " & std_logic'image(isl_h) &
      "; DVI seen " & std_logic'image(hdmi_d) & " islands " & std_logic'image(isl_d);
    assert m_h.ha = 720 and m_h.va = 480 and m_h.ht = 858 and m_h.vt = 525
      report "HDMI stream geometry wrong" severity failure;
    assert m_d.ha = 720 and m_d.va = 480 and m_d.ht = 858 and m_d.vt = 525
      report "DVI stream geometry wrong" severity failure;
    assert m_raw.ha = 722 report "unfiltered HDMI should measure 722 wide" severity failure;
    assert hdmi_h = '1' and isl_h = '1' report "HDMI flags not set" severity failure;
    assert hdmi_d = '0' and isl_d = '0' report "DVI flags set" severity failure;
    report "tb_hdmi_rx_period PASSED";
    done <= true;
    wait;
  end process;
end architecture;
