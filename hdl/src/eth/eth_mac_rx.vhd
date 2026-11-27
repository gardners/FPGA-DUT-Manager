-- eth_mac_rx: GMII-style receive (clk_rx domain) into two 2 KiB frame slots.
--
-- Strips preamble/SFD, checks FCS (CRC residue) and length, and stores the
-- frame (destination MAC .. FCS) in slot memory. A good frame is published to
-- the system clock domain by flipping that slot's toggle; the consumer
-- releases a slot by flipping its own toggle. Slots are used strictly
-- alternately (0,1,0,1...) so frames stay in order. Slot ownership:
--   slot full  <=>  rx_toggle(s) /= rel_toggle(s)
-- Lengths are stable while a slot is full, so the consumer may read them
-- after seeing the synchronised toggle change.
--
-- Oversize frames (more than SLOT_MAX = 2047 bytes incl. FCS, i.e. more than
-- 2043 bytes without FCS, UDP payload > 2001) still count as a drop
-- (stat_drop), but the first 2047 bytes are kept and, if the FCS over the
-- whole frame is good, published with length 2047. The IPv4 total length
-- then exceeds the slot length, so net_rx sees a truncated frame and can
-- answer an oversize JTAG_REQ with "bad format" instead of silence
-- (issue 0059).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity eth_mac_rx is
  port (
    clk        : in  std_logic;           -- clk_rx
    rx_dv      : in  std_logic;
    rx_er      : in  std_logic;
    rxd        : in  std_logic_vector(7 downto 0);
    -- slot memory write port (address bit 11 = slot)
    mem_we     : out std_logic;
    mem_addr   : out unsigned(11 downto 0);
    mem_data   : out std_logic_vector(7 downto 0);
    -- handshake
    rx_toggle  : out std_logic_vector(1 downto 0);
    rel_toggle : in  std_logic_vector(1 downto 0);  -- from sys domain (async)
    len0, len1 : out unsigned(11 downto 0);         -- frame length excl. FCS
    -- statistics strobes (clk_rx)
    stat_good, stat_crc_err, stat_drop : out std_logic
  );
end entity;

architecture rtl of eth_mac_rx is
  type state_t is (S_IDLE, S_PRE, S_DATA, S_DISCARD);
  signal state   : state_t := S_IDLE;
  signal rel_s1, rel_s2 : std_logic_vector(1 downto 0) := "00";
  signal rxt     : std_logic_vector(1 downto 0) := "00";
  signal slot    : std_logic := '0';
  signal idx     : unsigned(11 downto 0) := (others => '0');
  signal crc     : std_logic_vector(31 downto 0) := (others => '1');
  signal err     : std_logic := '0';
  signal ovf     : std_logic := '0';      -- frame longer than a slot
  signal l0, l1  : unsigned(11 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rel_s1, rel_s2 : signal is "TRUE";
begin
  rx_toggle <= rxt;
  len0 <= l0;
  len1 <= l1;

  process (clk)
    variable s : integer range 0 to 1;
  begin
    if rising_edge(clk) then
      rel_s1 <= rel_toggle;
      rel_s2 <= rel_s1;
      mem_we <= '0';
      stat_good <= '0'; stat_crc_err <= '0'; stat_drop <= '0';

      case state is
        when S_IDLE =>
          if rx_dv = '1' then
            -- pick a free slot now; if none, discard this frame
            -- slots are filled strictly alternately (consumer alternates too)
            if (slot = '0' and rxt(0) = rel_s2(0)) or (slot = '1' and rxt(1) = rel_s2(1)) then
              if rxd = x"D5" then       -- preamble may be shortened
                state <= S_DATA;
              else
                state <= S_PRE;
              end if;
            else
              stat_drop <= '1';
              state <= S_DISCARD;
            end if;
            idx <= (others => '0');
            crc <= (others => '1');
            err <= rx_er;
            ovf <= '0';
          end if;

        when S_PRE =>
          if rx_dv = '0' then
            state <= S_IDLE;
          elsif rxd = x"D5" then
            state <= S_DATA;
          elsif rxd /= x"55" then
            state <= S_DISCARD;
          end if;

        when S_DATA =>
          if rx_dv = '1' then
            if rx_er = '1' then err <= '1'; end if;
            if idx = 2047 then
              -- too long for a slot: keep the head, stop storing, keep
              -- checking the FCS (issue 0059)
              if ovf = '0' then
                stat_drop <= '1';
              end if;
              ovf <= '1';
              crc <= crc32_byte(crc, rxd);
            else
              mem_we   <= '1';
              mem_addr <= slot & idx(10 downto 0);
              mem_data <= rxd;
              idx      <= idx + 1;
              crc      <= crc32_byte(crc, rxd);
            end if;
          else
            -- end of frame: idx = bytes incl. FCS
            if err = '0' and crc = CRC32_RESIDUE and idx >= 64 then
              s := 0;
              if slot = '1' then s := 1; end if;
              if ovf = '1' then
                -- truncated head: all 2047 stored bytes are frame data
                if s = 0 then l0 <= idx; else l1 <= idx; end if;
              else
                if s = 0 then l0 <= idx - 4; else l1 <= idx - 4; end if;
                stat_good <= '1';
              end if;
              rxt(s) <= not rxt(s);
              slot <= not slot;
            elsif ovf = '1' then
              null;                     -- already counted as a drop
            else
              stat_crc_err <= '1';
            end if;
            state <= S_IDLE;
          end if;

        when S_DISCARD =>
          if rx_dv = '0' then
            state <= S_IDLE;
          end if;
      end case;
    end if;
  end process;
end architecture;
