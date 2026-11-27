-- text_rx_tap: write UDP 6508 TEXT_WRITE payloads straight into the text
-- display memories at line rate, in the clk_rx domain (ADR 0012).
--
-- Watches the received byte stream (after SFD). Header checks as bytes go by:
-- destination MAC = one of ours, IPv4 (0x45), UDP, dst port 6508, magic,
-- version, type 0x50. From frame byte 54 the payload bytes are written to
-- consecutive addresses starting at the 16-bit address in bytes 50-51, for
-- (UDP length - 20) bytes, so Ethernet padding/FCS are never written.
-- No buffering and no FCS check: a corrupt frame may leave wrong characters
-- until the next refresh.
-- Host VLAN (issue 0062): with vlan = 0 only untagged frames, else only
-- frames with an 802.1Q tag carrying that VID; the 4 tag bytes are skipped
-- (parse index rewound), so the offsets above are the untagged ones.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity text_rx_tap is
  port (
    clk     : in  std_logic;                       -- clk_rx
    rx_dv   : in  std_logic;
    rxd     : in  std_logic_vector(7 downto 0);
    mac0, mac1 : in std_logic_vector(47 downto 0); -- quasi-static (sys domain)
    wr_en   : out std_logic;
    wr_addr : out unsigned(14 downto 0);   -- screen(14:13) & offset (issue 0029)
    wr_data : out std_logic_vector(7 downto 0);
    frames  : out unsigned(15 downto 0);           -- accepted TEXT_WRITE frames
    vlan    : in  unsigned(11 downto 0) := (others => '0')   -- host VLAN (quasi-static); 0 = untagged
  );
end entity;

architecture rtl of text_rx_tap is
  type st_t is (S_IDLE, S_PRE, S_DATA);
  signal st      : st_t := S_IDLE;
  signal idx     : unsigned(12 downto 0) := (others => '0');
  signal ok0, ok1: std_logic := '0';       -- MAC matches so far
  signal ok      : std_logic := '0';       -- all other checks so far
  signal ulen    : unsigned(15 downto 0) := (others => '0');
  signal addr    : unsigned(15 downto 0) := (others => '0');
  signal left    : unsigned(15 downto 0) := (others => '0');
  signal cnt     : unsigned(15 downto 0) := (others => '0');
  signal m0, m1  : std_logic_vector(47 downto 0) := (others => '0');
  signal vl      : unsigned(11 downto 0) := (others => '0');
  signal b12     : std_logic_vector(7 downto 0) := (others => '0');
  signal tagged  : std_logic := '0';
  signal skip    : unsigned(1 downto 0) := "00";
  signal vid     : unsigned(11 downto 0) := (others => '0');

  function want(i : natural) return std_logic_vector is
  begin
    case i is
      when 13 => return x"00";
      when 14 => return x"45";
      when 23 => return x"11";
      when 36 => return x"19";   -- 6508 = 0x196C
      when 37 => return x"6C";
      when 42 => return x"4D";   -- magic
      when 43 => return x"36";
      when 44 => return x"01";   -- version
      when 45 => return x"50";   -- TEXT_WRITE
      when others => return x"00";
    end case;
  end function;
  function checked(i : natural) return boolean is
  begin
    return i = 14 or i = 23 or i = 36 or i = 37 or
           (i >= 42 and i <= 45);
  end function;
begin
  frames <= cnt;

  process (clk)
    variable i : natural;
  begin
    if rising_edge(clk) then
      m0 <= mac0; m1 <= mac1; vl <= vlan;   -- (quasi-static; one register stage)
      wr_en <= '0';
      case st is
        when S_IDLE =>
          if rx_dv = '1' then
            if rxd = x"D5" then st <= S_DATA; else st <= S_PRE; end if;
            idx <= (others => '0');
            ok0 <= '1'; ok1 <= '1'; ok <= '1';
            tagged <= '0'; skip <= "00";
          end if;
        when S_PRE =>
          if rx_dv = '0' then
            st <= S_IDLE;
          elsif rxd = x"D5" then
            st <= S_DATA;
          end if;
        when S_DATA =>
          if rx_dv = '0' then
            st <= S_IDLE;
          elsif skip /= 0 then
            -- 802.1Q TCI
            skip <= skip - 1;
            if skip = 2 then vid(11 downto 8) <= unsigned(rxd(3 downto 0));
            else vid(7 downto 0) <= unsigned(rxd); end if;
          elsif idx = 13 and tagged = '0' and b12 = x"81" and rxd = x"00" then
            tagged <= '1';
            skip   <= "10";
            idx    <= to_unsigned(12, 13);
          else
            i := to_integer(idx);
            idx <= idx + 1;
            if i < 6 then
              if rxd /= m0(47 - 8 * i downto 40 - 8 * i) then ok0 <= '0'; end if;
              if rxd /= m1(47 - 8 * i downto 40 - 8 * i) then ok1 <= '0'; end if;
            elsif i = 6 then
              if ok0 = '0' and ok1 = '0' then ok <= '0'; end if;
            end if;
            if checked(i) and rxd /= want(i) then
              ok <= '0';
            end if;
            if i = 12 then b12 <= rxd; end if;
            if i = 13 and (b12 /= x"08" or rxd /= x"00") then ok <= '0'; end if;
            if i = 14 and not ((vl = 0 and tagged = '0') or (vl /= 0 and tagged = '1' and vid = vl)) then
              ok <= '0';
            end if;
            if i = 38 then ulen(15 downto 8) <= unsigned(rxd); end if;
            if i = 39 then ulen(7 downto 0) <= unsigned(rxd); end if;
            if i = 50 then addr(15 downto 8) <= unsigned(rxd); end if;
            if i = 51 then
              addr(7 downto 0) <= unsigned(rxd);
              left <= ulen - 20;            -- UDP hdr 8 + custom hdr 8 + addr/res 4
              if ok = '1' and ulen >= 20 then cnt <= cnt + 1; end if;
            end if;
            if i >= 54 and ok = '1' and left /= 0 then
              wr_en   <= '1';
              wr_addr <= addr(14 downto 0);
              wr_data <= rxd;
              addr    <= addr + 1;
              left    <= left - 1;
            end if;
            if idx = 8191 then st <= S_IDLE; end if;
          end if;
      end case;
    end if;
  end process;
end architecture;
