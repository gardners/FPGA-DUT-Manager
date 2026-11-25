-- hdmi_framer: turns a DVI pixel stream into HDMI encoder controls (issue 0037).
--
-- Adds, in front of hdmi_tx_encoder (third_party/mega65-core), what an HDMI
-- stream needs on top of DVI:
--   * a video preamble (8 chars, CTL0..3 = 1000) and a video guard band
--     (2 chars) before every active line;
--   * one data island per InfoFrame: 8-char preamble (CTL = 1010), 2-char
--     leading guard band, one 32-char TERC4 packet with BCH ECC, 2-char
--     trailing guard band;
--   * an AVI InfoFrame (RGB, full range, IT content, VIC from `vic`) and an
--     SPD InfoFrame (vendor "MEGA65", product "MEGA KVM" or "MEGA KVM Mnn"
--     when `machine_ok`), each once per frame.
-- The stream is delayed LOOK = 10 chars so the preamble and guard band can be
-- placed before the DE rise. Islands are placed after the DE fall of active
-- lines 2 (AVI) and 3 (SPD) of each frame (frame = VS edge, either polarity),
-- only when the previous horizontal blank was at least MIN_HB chars long
-- (4 control + 46 island + 12 control/preamble + 2 guard), so a short-blank
-- source simply gets no islands. One packet per island keeps the channel-0
-- bit-3 marker ("first char of the packet") unambiguous.
--
-- Packet layout, TERC4 mapping and BCH(64,56)/(32,24) with G(x) = 1 + x^6 +
-- x^7 + x^8 follow HDMI 1.4 section 5.2.3 / CTA-861; the LFSR form matches
-- bch_ecc_1/bch_ecc_2 in mega65-core's vga_to_hdmi.vhdl (Tyto Project,
-- Adam Barnes, LGPL-3.0+), which was used as a cross-check only; this file is
-- new code. tests/scenarios/tb_hdmi_tx.py checks the ECC independently by
-- polynomial division.
--
-- `vic`, `machine`, `machine_ok` may come from another clock domain: they
-- are quasi-static, sampled through two registers and latched at a VS edge.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package hdmi_framer_pkg is
  type byte_arr is array (natural range <>) of std_logic_vector(7 downto 0);
  subtype pkt_t is byte_arr(0 to 30);   -- HB0..HB2, PB0..PB27
  function bch_step(e : std_logic_vector(7 downto 0); b : std_logic) return std_logic_vector;
  function avi_packet(vic : std_logic_vector(6 downto 0)) return pkt_t;
  function spd_packet(machine : unsigned(4 downto 0); ok : std_logic) return pkt_t;
  constant SPD_VENDOR  : string := "MEGA65";
  constant SPD_PRODUCT : string := "MEGA KVM";
  constant SPD_SOURCE  : std_logic_vector(7 downto 0) := x"09";  -- PC general
end package;

package body hdmi_framer_pkg is
  -- one bit of the HDMI BCH code (LSB-first, reversed polynomial 0x83)
  function bch_step(e : std_logic_vector(7 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(7 downto 0);
  begin
    r := '0' & e(7 downto 1);
    if (e(0) xor b) = '1' then
      r := r xor x"83";
    end if;
    return r;
  end function;

  -- PB0 = checksum: all header and body bytes sum to 0 mod 256
  function with_checksum(p : pkt_t) return pkt_t is
    variable s : unsigned(7 downto 0) := (others => '0');
    variable r : pkt_t := p;
  begin
    for i in p'range loop
      if i /= 3 then s := s + unsigned(p(i)); end if;
    end loop;
    r(3) := std_logic_vector(0 - s);
    return r;
  end function;

  function avi_packet(vic : std_logic_vector(6 downto 0)) return pkt_t is
    variable p : pkt_t := (others => x"00");
    variable m : std_logic_vector(1 downto 0);
  begin
    -- picture aspect from the VIC: 2/17 4:3, 3/18 16:9, else no data
    case to_integer(unsigned(vic)) is
      when 2 | 17 => m := "01";
      when 3 | 18 => m := "10";
      when others => m := "00";
    end case;
    p(0) := x"82"; p(1) := x"02"; p(2) := x"0D";      -- AVI, version 2, 13 bytes
    p(4) := x"12";               -- PB1: RGB, active format present, underscanned
    p(5) := "00" & m & "1000";   -- PB2: no colorimetry, aspect, AFD = same as picture
    p(6) := x"88";               -- PB3: IT content, full-range RGB
    p(7) := '0' & vic;           -- PB4: VIC
    p(8) := x"00";               -- PB5: content type graphics, no repetition
    return with_checksum(p);
  end function;

  function spd_packet(machine : unsigned(4 downto 0); ok : std_logic) return pkt_t is
    variable p : pkt_t := (others => x"00");
    variable n : natural range 0 to 31;
    variable tens : natural range 0 to 3;
    constant B : natural := 4;   -- index of PB1
  begin
    p(0) := x"83"; p(1) := x"01"; p(2) := x"19";      -- SPD, version 1, 25 bytes
    for i in SPD_VENDOR'range loop                    -- PB1..PB8 vendor
      p(B + i - 1) := std_logic_vector(to_unsigned(character'pos(SPD_VENDOR(i)), 8));
    end loop;
    for i in SPD_PRODUCT'range loop                   -- PB9..PB24 product
      p(B + 8 + i - 1) := std_logic_vector(to_unsigned(character'pos(SPD_PRODUCT(i)), 8));
    end loop;
    if ok = '1' then
      n := to_integer(machine);
      if n >= 30 then tens := 3; elsif n >= 20 then tens := 2; elsif n >= 10 then tens := 1;
      else tens := 0; end if;
      p(B + 8 + SPD_PRODUCT'length)     := x"20";                       -- ' '
      p(B + 8 + SPD_PRODUCT'length + 1) := x"4D";                       -- 'M'
      p(B + 8 + SPD_PRODUCT'length + 2) := std_logic_vector(to_unsigned(48 + tens, 8));
      p(B + 8 + SPD_PRODUCT'length + 3) := std_logic_vector(to_unsigned(48 + n - 10 * tens, 8));
    end if;
    p(B + 24) := SPD_SOURCE;                          -- PB25 source information
    return with_checksum(p);
  end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hdmi_tx_encoder_pkg.all;
use work.hdmi_framer_pkg.all;

entity hdmi_framer is
  port (
    clk        : in  std_logic;   -- pixel clock
    rst        : in  std_logic;   -- synchronous
    r, g, b    : in  std_logic_vector(7 downto 0);
    hs, vs, de : in  std_logic;
    -- InfoFrame contents (quasi-static, any clock domain)
    vic        : in  std_logic_vector(6 downto 0);
    machine    : in  unsigned(4 downto 0);
    machine_ok : in  std_logic;
    -- to hdmi_tx_encoder channels 0 (blue), 1 (green), 2 (red); registered
    o_de       : out std_logic;
    o_p0, o_p1, o_p2 : out std_logic_vector(7 downto 0);
    o_enc      : out std_logic_vector(1 downto 0);
    o_c0, o_c1, o_c2 : out std_logic_vector(1 downto 0);
    o_d0, o_d1, o_d2 : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of hdmi_framer is
  constant LOOK   : natural := 10;            -- 8 preamble + 2 guard
  constant MIN_HB : natural := 4 + 46 + 12 + 2;
  constant ISL_PRE : natural := 4;            -- island timeline (chars after the DE fall)
  constant ISL_GB1 : natural := ISL_PRE + 8;
  constant ISL_PKT : natural := ISL_GB1 + 2;
  constant ISL_GB2 : natural := ISL_PKT + 32;
  constant ISL_END : natural := ISL_GB2 + 1;

  type rgb_arr is array (0 to LOOK + 1) of std_logic_vector(23 downto 0);
  signal rgb_sr : rgb_arr := (others => (others => '0'));
  signal de_sr, hs_sr, vs_sr : std_logic_vector(0 to LOOK + 1) := (others => '0');

  -- configuration: two-register sampling, latched per frame
  signal vic_s1, vic_s2, vic_l : std_logic_vector(6 downto 0) := (others => '0');
  signal m_s1, m_s2, m_l : unsigned(4 downto 0) := (others => '0');
  signal ok_s1, ok_s2, ok_l : std_logic := '0';
  signal avi_b, spd_b : pkt_t := (others => x"00");

  signal bc, hb : unsigned(11 downto 0) := (others => '0');   -- blank run, last hblank
  signal lines : unsigned(1 downto 0) := (others => '0');     -- DE runs since VS (sat. 2)
  signal vs_evt : std_logic := '0';
  signal pend : std_logic_vector(1 downto 0) := "00";         -- 0 AVI, 1 SPD
  signal isl : std_logic := '0';
  signal icnt : natural range 0 to ISL_END := 0;
  signal psel : std_logic := '0';                             -- 0 AVI, 1 SPD
  signal hdr_sr, ecc_h : std_logic_vector(7 downto 0) := (others => '0');
  signal hdr_hi : std_logic_vector(15 downto 0) := (others => '0');
  type sub_arr is array (0 to 3) of std_logic_vector(55 downto 0);
  type ecc_arr is array (0 to 3) of std_logic_vector(7 downto 0);
  signal sub_sr : sub_arr := (others => (others => '0'));
  signal ecc_s : ecc_arr := (others => (others => '0'));
begin
  process (clk)
    variable pk : pkt_t;
    variable j : integer;
    variable e : std_logic_vector(7 downto 0);
    variable ahead_pre : boolean;
  begin
    if rising_edge(clk) then
      vic_s1 <= vic; vic_s2 <= vic_s1;
      m_s1 <= machine; m_s2 <= m_s1;
      ok_s1 <= machine_ok; ok_s2 <= ok_s1;
      avi_b <= avi_packet(vic_l);
      spd_b <= spd_packet(m_l, ok_l);

      rgb_sr(0) <= r & g & b; de_sr(0) <= de; hs_sr(0) <= hs; vs_sr(0) <= vs;
      for k in 1 to LOOK + 1 loop
        rgb_sr(k) <= rgb_sr(k - 1); de_sr(k) <= de_sr(k - 1);
        hs_sr(k) <= hs_sr(k - 1); vs_sr(k) <= vs_sr(k - 1);
      end loop;

      ---------------------------------------------------------- output char
      -- position LOOK is the char being emitted now
      o_de <= de_sr(LOOK);
      o_p2 <= rgb_sr(LOOK)(23 downto 16);
      o_p1 <= rgb_sr(LOOK)(15 downto 8);
      o_p0 <= rgb_sr(LOOK)(7 downto 0);
      o_c0 <= vs_sr(LOOK) & hs_sr(LOOK);
      o_c1 <= "00"; o_c2 <= "00";
      o_enc <= ENC_DVI;
      o_d0 <= "0000"; o_d1 <= "0000"; o_d2 <= "0000";
      ahead_pre := false;
      for k in LOOK - 10 to LOOK - 3 loop
        if de_sr(k) = '1' then ahead_pre := true; end if;
      end loop;
      if de_sr(LOOK) = '1' then
        null;                                     -- video (encoder uses p)
      elsif de_sr(LOOK - 1) = '1' or de_sr(LOOK - 2) = '1' then
        o_enc <= ENC_GB_VIDEO;
      elsif ahead_pre then
        o_c1 <= "01";                             -- CTL0..3 = 1000
      elsif isl = '1' then
        if icnt >= ISL_PRE and icnt < ISL_GB1 then
          o_c1 <= "01"; o_c2 <= "01";             -- CTL0..3 = 1010
        elsif icnt >= ISL_PKT and icnt < ISL_GB2 then
          o_enc <= ENC_DATA;
          if icnt = ISL_PKT then o_d0(3) <= '0'; else o_d0(3) <= '1'; end if;
          o_d0(2 downto 0) <= hdr_sr(0) & vs_sr(LOOK) & hs_sr(LOOK);
          for i in 0 to 3 loop
            o_d1(i) <= sub_sr(i)(0);
            o_d2(i) <= sub_sr(i)(1);
          end loop;
        elsif icnt >= ISL_GB1 then
          o_enc <= ENC_GB_DATA;                   -- channel 0 takes c0 = vs & hs
        end if;
      end if;

      ---------------------------------------------------------- packet shifter
      j := icnt - ISL_PKT;
      if isl = '1' and icnt = ISL_PKT - 1 then
        if psel = '0' then pk := avi_b; else pk := spd_b; end if;
        hdr_sr <= pk(0);
        hdr_hi <= pk(2) & pk(1);
        ecc_h  <= (others => '0');
        for i in 0 to 3 loop
          for k in 0 to 6 loop
            sub_sr(i)(8 * k + 7 downto 8 * k) <= pk(3 + 7 * i + k);
          end loop;
          ecc_s(i) <= (others => '0');
        end loop;
      elsif isl = '1' and j >= 0 and j < 32 then
        -- header: 24 bits then its 8 ECC bits, one per char
        e := bch_step(ecc_h, hdr_sr(0));
        if j < 23 then
          ecc_h <= e;
          hdr_sr <= hdr_hi(0) & hdr_sr(7 downto 1);
          hdr_hi <= '0' & hdr_hi(15 downto 1);
        elsif j = 23 then
          hdr_sr <= e;
        else
          hdr_sr <= '0' & hdr_sr(7 downto 1);
        end if;
        -- subpackets: 56 bits then 8 ECC bits, two per char
        for i in 0 to 3 loop
          e := bch_step(bch_step(ecc_s(i), sub_sr(i)(0)), sub_sr(i)(1));
          if j < 27 then
            ecc_s(i) <= e;
            sub_sr(i) <= "00" & sub_sr(i)(55 downto 2);
          elsif j = 27 then
            sub_sr(i)(7 downto 0) <= e;
          else
            sub_sr(i) <= "00" & sub_sr(i)(55 downto 2);
          end if;
        end loop;
      end if;

      ---------------------------------------------------------- scheduling
      if vs_sr(LOOK) /= vs_sr(LOOK + 1) then
        vs_evt <= '1';
        pend <= "11";
        vic_l <= vic_s2; m_l <= m_s2; ok_l <= ok_s2;
      end if;
      if de_sr(LOOK) = '1' then
        if de_sr(LOOK + 1) = '0' then             -- DE rise: hblank length
          hb <= bc;
          bc <= (others => '0');
          if vs_evt = '1' then
            lines <= "01"; vs_evt <= '0';
          elsif lines /= 2 then
            lines <= lines + 1;
          end if;
        end if;
        isl <= '0';                               -- never overlap video
      else
        if de_sr(LOOK + 1) = '1' then             -- DE fall
          bc <= to_unsigned(1, bc'length);
          if lines = 2 and hb >= MIN_HB and pend /= "00" then
            isl <= '1';
            icnt <= 1;                            -- the fall char is char 0
            if pend(0) = '1' then
              psel <= '0'; pend(0) <= '0';
            else
              psel <= '1'; pend(1) <= '0';
            end if;
          end if;
        elsif bc /= 4095 then
          bc <= bc + 1;
        end if;
        if isl = '1' then
          if icnt = ISL_END then
            isl <= '0';
          else
            icnt <= icnt + 1;
          end if;
        end if;
      end if;

      if rst = '1' then
        isl <= '0'; pend <= "00"; vs_evt <= '0'; lines <= "00";
      end if;
    end if;
  end process;
end architecture;
