-- eth_mac_tx: send one frame from slot memory as GMII bytes (clk_sys).
-- Adds preamble, SFD, zero padding to 60 bytes, FCS and a 12-byte IFG.
-- start: one-cycle pulse with base address and length (excl. FCS).
-- Memory read latency is one cycle.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity eth_mac_tx is
  generic (ADDR_W : positive := 12; LEN_W : positive := 12);
  port (
    clk      : in  std_logic;
    start    : in  std_logic;
    base     : in  unsigned(ADDR_W - 1 downto 0);
    len      : in  unsigned(LEN_W - 1 downto 0);
    busy     : out std_logic;
    done     : out std_logic;              -- strobe after IFG
    mem_addr : out unsigned(ADDR_W - 1 downto 0);
    mem_data : in  std_logic_vector(7 downto 0);
    tx_en    : out std_logic;
    txd      : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of eth_mac_tx is
  type state_t is (S_IDLE, S_PRE, S_DATA, S_FCS, S_IFG);
  signal state : state_t := S_IDLE;
  signal cnt   : unsigned(LEN_W - 1 downto 0) := (others => '0');
  signal n     : unsigned(LEN_W - 1 downto 0) := (others => '0');
  signal addr  : unsigned(ADDR_W - 1 downto 0) := (others => '0');
  signal crc   : std_logic_vector(31 downto 0) := (others => '1');
  signal fcs   : std_logic_vector(31 downto 0) := (others => '0');
begin
  busy     <= '0' when state = S_IDLE else '1';
  mem_addr <= addr;

  process (clk)
    variable b : byte_t;
  begin
    if rising_edge(clk) then
      done <= '0';
      case state is
        when S_IDLE =>
          tx_en <= '0';
          txd   <= x"00";
          if start = '1' then
            addr  <= base;
            n     <= len;
            cnt   <= (others => '0');
            crc   <= (others => '1');
            state <= S_PRE;
          end if;

        when S_PRE =>
          tx_en <= '1';
          if cnt = 7 then
            txd   <= x"D5";
            cnt   <= (others => '0');
            addr  <= addr + 1;          -- byte 0 is on mem_data next cycle
            state <= S_DATA;
          else
            txd <= x"55";
            cnt <= cnt + 1;
          end if;

        when S_DATA =>
          if cnt < n then
            b := mem_data;
          else
            b := x"00";                 -- padding
          end if;
          txd  <= b;
          crc  <= crc32_byte(crc, b);
          addr <= addr + 1;
          cnt  <= cnt + 1;
          if cnt + 1 >= n and cnt + 1 >= 60 then
            state <= S_FCS;
            fcs   <= not crc32_byte(crc, b);
            cnt   <= (others => '0');
          end if;

        when S_FCS =>
          txd <= fcs(7 downto 0);
          fcs <= x"00" & fcs(31 downto 8);
          if cnt = 3 then
            cnt   <= (others => '0');
            state <= S_IFG;
          else
            cnt <= cnt + 1;
          end if;

        when S_IFG =>
          tx_en <= '0';
          txd   <= x"00";
          if cnt = 11 then
            done  <= '1';
            state <= S_IDLE;
          else
            cnt <= cnt + 1;
          end if;
      end case;
    end if;
  end process;
end architecture;
