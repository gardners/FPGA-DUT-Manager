-- hdmi_rx_period: HDMI-aware video DE for the HDMI IN decoder (issue 0040).
--
-- dvi2rgb (DVI 1.0) marks every non-control TMDS character as video, so an
-- HDMI source's video guard bands (2 chars before each line) and data
-- islands (preamble, guard bands, TERC4 packets: InfoFrames, audio) appear
-- as extra pixels. This block follows the HDMI period structure on the
-- per-channel decoder outputs (registered TMDS_Decoder pVde/pC0/pC1, all
-- channels aligned) and passes DE only for real active video:
--   * a control period whose last >= PRE_MIN chars carry CTL0..3 = 1000
--     (channel 1 C0 = 1, channel 2 C0/C1 = 0) is a video preamble: the next
--     2 non-control chars are the video guard band (DE low), then video;
--   * CTL0..3 = 1010 (channels 1 and 2 C0 = 1) is a data-island preamble:
--     every non-control char up to the next control char (guard bands and
--     TERC4 packets) is DE low;
--   * any other control period (DVI: CTL = 0000) is followed directly by
--     video, as before.
-- Combinational from the decoder registers plus state, so DE keeps its
-- timing relative to pData/HS/VS. A TERC4 or guard char is never a control
-- token, so a period always ends at a control char.
-- HSYNC/VSYNC: inside a data island channel 0 carries them in TERC4 bits 0
-- and 1 rather than as control tokens, and dvi2rgb holds its last control
-- value there, which would move the HSYNC edge to the island's end (islands
-- usually span HSYNC). The 8b decode dvi2rgb makes of the 16 TERC4 chars is
-- one-to-one, so hs_out/vs_out take the TERC4 bits from `d0` inside islands
-- and pass hs_in/vs_in everywhere else.
-- hdmi_seen / island_seen: a video or data-island preamble / a data island
-- was seen during the last two frames (published every 4 VSYNC edges,
-- either polarity), pclk domain, quasi-static.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_rx_period is
  generic (PRE_MIN : positive := 4);  -- preamble chars needed (HDMI sends 8)
  port (
    clk         : in  std_logic;   -- decoder pixel clock
    de_in       : in  std_logic;   -- decoder "not a control token" (channel 0)
    hs_in       : in  std_logic;   -- channel 0 C0
    vs_in       : in  std_logic;   -- channel 0 C1
    d0          : in  std_logic_vector(7 downto 0);  -- channel 0 8b decode
    ctl         : in  std_logic_vector(3 downto 0);  -- CTL3..0 = ch2 C1, ch2 C0, ch1 C1, ch1 C0
    de_out      : out std_logic;   -- active video only
    hs_out, vs_out : out std_logic;
    hdmi_seen   : out std_logic;
    island_seen : out std_logic
  );
end entity;

architecture rtl of hdmi_rx_period is
  constant PAT_VIDEO  : std_logic_vector(3 downto 0) := "0001";
  constant PAT_ISLAND : std_logic_vector(3 downto 0) := "0101";
  type mode_t is (M_CTL, M_VGB, M_VID, M_ISL);
  signal mode : mode_t := M_CTL;
  signal last_pat : std_logic_vector(3 downto 0) := "0000";
  signal run : natural range 0 to PRE_MIN := 0;
  signal pre_video, pre_island : boolean;
  signal acc_h, acc_i, out_h, out_i, vs_d : std_logic := '0';
  signal vs_edges : unsigned(1 downto 0) := "00";
  signal in_island, t_ok : boolean;
  signal t_sync : std_logic_vector(1 downto 0);   -- vs & hs
  signal vs_o : std_logic;
begin
  -- dvi2rgb's 8b decode of TERC4 0..15 -> (vs, hs) = nibble bits 1..0
  process (d0)
  begin
    t_ok <= true;
    case d0 is
      when x"5B" | x"93" | x"AB" | x"6D" => t_sync <= "00";   -- 0, 4, 8, 12
      when x"5A" | x"22" | x"4B" | x"6C" => t_sync <= "01";   -- 1, 5, 9, 13
      when x"D3" | x"92" | x"A4" | x"A5" => t_sync <= "10";   -- 2, 6, 10, 14
      when x"D9" | x"44" | x"B5" | x"BA" => t_sync <= "11";   -- 3, 7, 11, 15
      when others => t_sync <= "00"; t_ok <= false;
    end case;
  end process;
  in_island <= de_in = '1' and t_ok and (mode = M_ISL or (mode = M_CTL and pre_island));
  hs_out <= t_sync(0) when in_island else hs_in;
  vs_o   <= t_sync(1) when in_island else vs_in;
  vs_out <= vs_o;

  pre_video  <= last_pat = PAT_VIDEO and run = PRE_MIN;
  pre_island <= last_pat = PAT_ISLAND and run = PRE_MIN;

  de_out <= '0' when de_in = '0' else
            '1' when mode = M_VID else
            '1' when mode = M_CTL and not pre_video and not pre_island else
            '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if de_in = '0' then
        mode <= M_CTL;
        if ctl = last_pat then
          if run /= PRE_MIN then run <= run + 1; end if;
        else
          last_pat <= ctl;
          run <= 1;
        end if;
      else
        run <= 0;
        case mode is
          when M_CTL =>
            if pre_video then
              mode <= M_VGB; acc_h <= '1';
            elsif pre_island then
              mode <= M_ISL; acc_h <= '1'; acc_i <= '1';
            else
              mode <= M_VID;
            end if;
          when M_VGB => mode <= M_VID;
          when others => null;
        end case;
      end if;

      vs_d <= vs_o;
      if vs_o /= vs_d then
        vs_edges <= vs_edges + 1;
        if vs_edges = 3 then
          out_h <= acc_h; out_i <= acc_i;
          acc_h <= '0'; acc_i <= '0';
        end if;
      end if;
    end if;
  end process;
  hdmi_seen <= out_h;
  island_seen <= out_i;
end architecture;
