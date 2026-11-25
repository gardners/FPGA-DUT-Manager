-- video_meas: measure an incoming video stream (issue 0022) for the
-- heartbeat video block (ADR 0005 section 8).
--
-- Pixel-clock side (pclk): from DE/HSYNC/VSYNC it measures, per frame,
-- h_total (pixels between HSYNC leading edges), h_active (DE run length),
-- v_total (lines between VSYNC leading edges), v_active (lines with DE) and
-- the sync polarities (the level seen while DE is high is the inactive
-- level). At each VSYNC leading edge the set is measured; it is published
-- (handed to clk with a toggle - values stay stable for at least a frame,
-- far longer than the 2-FF crossing) only when two consecutive frames
-- measured the same, so a frame cut short (source lost / passthrough
-- switch) cannot change the reported geometry (issue 0032 hardware note).
-- clk side: pixel_hz = pixel clocks counted in a 1 s window (a Gray-coded
-- pclk counter sampled every CLK_HZ cycles); present = pixel_hz > 1 MHz.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_meas is
  generic (CLK_HZ : positive := 125_000_000);
  port (
    pclk      : in  std_logic;
    de, hs, vs: in  std_logic;
    clk       : in  std_logic;
    h_total, v_total, h_active, v_active : out unsigned(15 downto 0);
    hs_pol, vs_pol : out std_logic;           -- '1' = active high
    frames    : out unsigned(31 downto 0);
    pixel_hz  : out unsigned(31 downto 0);
    present   : out std_logic
  );
end entity;

architecture rtl of video_meas is
  -- pclk domain
  signal hs_d, vs_d, de_d : std_logic := '0';
  signal hpol, vpol : std_logic := '0';      -- active level
  signal hcnt, hact_cnt, vcnt, vact_cnt : unsigned(15 downto 0) := (others => '0');
  signal ht_l, ha_l : unsigned(15 downto 0) := (others => '0');
  signal line_de : std_logic := '0';
  signal o_ht, o_hact, o_vt, o_vact : unsigned(15 downto 0) := (others => '0');
  signal c_ht, c_hact, c_vt, c_vact : unsigned(15 downto 0) := (others => '0');   -- last frame
  signal o_hpol, o_vpol : std_logic := '0';
  signal fcnt : unsigned(31 downto 0) := (others => '0');
  signal tog  : std_logic := '0';
  signal pcount : unsigned(31 downto 0) := (others => '0');
  signal pgray  : std_logic_vector(31 downto 0) := (others => '0');
  -- clk domain
  signal tog_s : std_logic_vector(2 downto 0) := "000";
  signal g1, g2 : std_logic_vector(31 downto 0) := (others => '0');
  signal win : integer range 0 to CLK_HZ - 1 := 0;
  signal last : unsigned(31 downto 0) := (others => '0');
  signal hz : unsigned(31 downto 0) := (others => '0');
  signal r_ht, r_vt, r_ha, r_va : unsigned(15 downto 0) := (others => '0');
  signal r_hp, r_vp : std_logic := '0';
  signal r_fr : unsigned(31 downto 0) := (others => '0');

  function gray2bin(g : std_logic_vector) return unsigned is
    variable b : std_logic_vector(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto g'low loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return unsigned(b);
  end function;

  attribute ASYNC_REG : string;
  attribute ASYNC_REG of g1, g2, tog_s : signal is "TRUE";
begin
  process (pclk)
    variable hs_a, vs_a : std_logic;
  begin
    if rising_edge(pclk) then
      pcount <= pcount + 1;
      pgray  <= std_logic_vector(pcount xor shift_right(pcount, 1));
      hs_d <= hs; vs_d <= vs; de_d <= de;
      if de = '1' then hpol <= not hs; vpol <= not vs; end if;   -- inactive level seen in DE
      hs_a := hs xnor hpol;            -- '1' while HSYNC active
      vs_a := vs xnor vpol;
      -- horizontal
      hcnt <= hcnt + 1;
      if de = '1' then
        hact_cnt <= hact_cnt + 1;
        line_de  <= '1';
      elsif de_d = '1' then
        ha_l <= hact_cnt;              -- DE run ended
        hact_cnt <= (others => '0');
      end if;
      if hs_a = '1' and (hs_d xnor hpol) = '0' then   -- HSYNC leading edge
        ht_l <= hcnt + 1;
        hcnt <= (others => '0');
        vcnt <= vcnt + 1;
        if line_de = '1' then vact_cnt <= vact_cnt + 1; end if;
        line_de <= '0';
      end if;
      -- vertical: latch at the VSYNC leading edge
      if vs_a = '1' and (vs_d xnor vpol) = '0' then
        c_ht <= ht_l; c_hact <= ha_l; c_vt <= vcnt; c_vact <= vact_cnt;
        if ht_l = c_ht and ha_l = c_hact and vcnt = c_vt and vact_cnt = c_vact then
          o_ht <= ht_l; o_hact <= ha_l; o_vt <= vcnt; o_vact <= vact_cnt;
          o_hpol <= hpol; o_vpol <= vpol;
          tog <= not tog;
        end if;
        fcnt <= fcnt + 1;
        vcnt <= (others => '0');
        vact_cnt <= (others => '0');
      end if;
    end if;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      tog_s <= tog_s(1 downto 0) & tog;
      if tog_s(2) /= tog_s(1) then      -- new frame measurement (stable)
        r_ht <= o_ht; r_vt <= o_vt; r_ha <= o_hact; r_va <= o_vact;
        r_hp <= o_hpol; r_vp <= o_vpol; r_fr <= fcnt;
      end if;
      g1 <= pgray; g2 <= g1;
      if win = CLK_HZ - 1 then
        win <= 0;
        hz <= gray2bin(g2) - last;
        last <= gray2bin(g2);
      else
        win <= win + 1;
      end if;
    end if;
  end process;

  h_total <= r_ht; v_total <= r_vt; h_active <= r_ha; v_active <= r_va;
  hs_pol <= r_hp; vs_pol <= r_vp; frames <= r_fr;
  pixel_hz <= hz;
  present <= '1' when hz > 1_000_000 else '0';
end architecture;
