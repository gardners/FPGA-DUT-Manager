-- ddc_edid: DDC (E-DDC / I2C) slave serving a 256-byte EDID at address
-- 0x50 (issue 0033). Vendor-neutral: SCL is input only (no clock
-- stretching); SDA is open drain, sda_low = '1' pulls it low (the platform
-- layer turns that into a tri-state buffer).
--
-- Behaves like a read-only 24C02: a write sets the 8-bit word pointer
-- (further written bytes are acknowledged and ignored), reads return
-- consecutive bytes from the pointer, wrapping at 256. A repeated start
-- keeps the pointer (the usual "write offset, Sr, read" sequence). Address
-- 0x30 (E-DDC segment pointer) is not acknowledged: segment 0 only.
--
-- The contents are a RAM initialised from EDID (scripts/gen_edid.py ->
-- edid_pkg), with a write port for a later host-set EDID (US-09).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.edid_pkg.all;

entity ddc_edid is
  generic (
    CLK_HZ  : positive := 200_000_000;
    ADDR    : std_logic_vector(6 downto 0) := "1010000";   -- 0x50
    EDID    : byte_array_t(0 to 255) := EDID_DEFAULT;
    -- SCL/SDA must be stable this long before a change is seen (I2C
    -- fast-mode spike suppression is 50 ns)
    FILT_NS : positive := 100
  );
  port (
    clk, rst : in  std_logic;
    scl, sda : in  std_logic;      -- pins (asynchronous)
    sda_low  : out std_logic;      -- '1' = pull SDA low
    -- optional contents update (clk domain), e.g. from management
    we       : in  std_logic := '0';
    waddr    : in  unsigned(7 downto 0) := (others => '0');
    wdata    : in  byte_t := (others => '0');
    -- status
    reads    : out unsigned(15 downto 0)   -- address-matched read transfers
  );
end entity;

architecture rtl of ddc_edid is
  constant FILT : positive := (FILT_NS * (CLK_HZ / 1_000_000) + 999) / 1000 + 1;

  signal mem : byte_array_t(0 to 255) := EDID;
  signal rdat : byte_t;

  signal scl_s, sda_s : std_logic_vector(1 downto 0) := "11";   -- synchronisers
  signal scl_f, sda_f : std_logic := '1';                         -- filtered
  signal scl_d, sda_d : std_logic := '1';
  signal scl_cnt, sda_cnt : natural range 0 to FILT := 0;

  type state_t is (IDLE, ADDR_RX, ADDR_ACK, W_RX, W_ACK, R_TX, R_ACK);
  signal st : state_t := IDLE;
  signal sh : byte_t := (others => '0');
  signal bits : natural range 0 to 8 := 0;
  signal rnw, first : std_logic := '0';
  signal ptr : unsigned(7 downto 0) := (others => '0');
  signal drive : std_logic := '0';
  signal nreads : unsigned(15 downto 0) := (others => '0');
begin
  -- contents (registered read; a separate write port keeps it a simple RAM)
  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        mem(to_integer(waddr)) <= wdata;
      end if;
      rdat <= mem(to_integer(ptr));
    end if;
  end process;

  process (clk)
    variable scl_r, scl_fall, start, stop : boolean;
  begin
    if rising_edge(clk) then
      -- synchronise, then accept a level only once stable for FILT cycles
      scl_s <= scl_s(0) & to_x01(scl);
      sda_s <= sda_s(0) & to_x01(sda);
      if scl_s(1) = scl_f then
        scl_cnt <= 0;
      elsif scl_cnt = FILT - 1 then
        scl_f <= scl_s(1); scl_cnt <= 0;
      else
        scl_cnt <= scl_cnt + 1;
      end if;
      if sda_s(1) = sda_f then
        sda_cnt <= 0;
      elsif sda_cnt = FILT - 1 then
        sda_f <= sda_s(1); sda_cnt <= 0;
      else
        sda_cnt <= sda_cnt + 1;
      end if;
      scl_d <= scl_f;
      sda_d <= sda_f;

      scl_r    := scl_d = '0' and scl_f = '1';
      scl_fall := scl_d = '1' and scl_f = '0';
      start    := scl_f = '1' and scl_d = '1' and sda_d = '1' and sda_f = '0';
      stop     := scl_f = '1' and scl_d = '1' and sda_d = '0' and sda_f = '1';

      if start then
        st <= ADDR_RX; bits <= 0; drive <= '0';
      elsif stop then
        st <= IDLE; drive <= '0';
      else
        case st is
          when IDLE => null;

          when ADDR_RX | W_RX =>
            if scl_r then
              sh <= sh(6 downto 0) & sda_f;
              bits <= bits + 1;
            elsif scl_fall and bits = 8 then
              bits <= 0;
              if st = ADDR_RX then
                if sh(7 downto 1) = ADDR then
                  rnw <= sh(0); first <= '1'; drive <= '1'; st <= ADDR_ACK;
                  if sh(0) = '1' then
                    nreads <= nreads + 1;
                  end if;
                else
                  st <= IDLE;               -- not us: wait for the next start
                end if;
              else
                if first = '1' then
                  ptr <= unsigned(sh);      -- word address
                end if;
                first <= '0'; drive <= '1'; st <= W_ACK;
              end if;
            end if;

          when ADDR_ACK | W_ACK =>          -- holding ACK low through the 9th clock
            if scl_fall then
              if st = ADDR_ACK and rnw = '1' then
                sh <= rdat; drive <= not rdat(7); bits <= 1; st <= R_TX;
                ptr <= ptr + 1;
              else
                drive <= '0'; st <= W_RX;
              end if;
            end if;

          when R_TX =>
            if scl_fall then
              if bits = 8 then
                drive <= '0'; st <= R_ACK;  -- release for the master's ACK
              else
                drive <= not sh(7 - bits); bits <= bits + 1;
              end if;
            end if;

          when R_ACK =>
            if scl_r then
              if sda_f = '1' then
                st <= IDLE;                 -- NACK: master is done
              end if;
            elsif scl_fall then
              sh <= rdat; drive <= not rdat(7); bits <= 1; st <= R_TX;
              ptr <= ptr + 1;
            end if;
        end case;
      end if;

      if rst = '1' then
        st <= IDLE; drive <= '0'; bits <= 0;
        scl_f <= '1'; sda_f <= '1'; scl_d <= '1'; sda_d <= '1';
      end if;
    end if;
  end process;

  sda_low <= drive;
  reads <= nreads;
end architecture;
