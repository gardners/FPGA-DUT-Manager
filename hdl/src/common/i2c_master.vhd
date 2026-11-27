-- i2c_master: byte-level I2C bus master (issue 0049 step 2), vendor neutral.
--
-- * Open drain: scl_low/sda_low = '1' pull the line low, '0' release it; the
--   top level turns them into tri-state pins ('0' or 'Z'). scl_in/sda_in are
--   the pin levels (asynchronous, synchronised here).
-- * SCL_HZ 100 kHz or 400 kHz: each bit is two low phases (55 % of the
--   period: 1.38 us at 400 kHz >= tLOW 1.3 us) and two high phases (45 %).
--   SDA changes at the start of the first low phase and is sampled at the
--   end of the first high phase.
-- * Clock stretching: after releasing SCL the high phase only starts once
--   scl_in reads high. A slave holding SCL low longer than STRETCH_MAX
--   clocks ends the command with err = '1' and both lines released.
-- * Commands (cmd_valid while ready = '1'; done pulses when finished):
--     C_START   START, or a repeated START if the master holds the bus. From
--               idle the bus must be free (SCL and SDA high), else err.
--     C_STOP    STOP (bus released).
--     C_WRITE   send wdata, then read the slave's ACK: nack = '1' if none.
--     C_READ    receive rdata, then send ACK (rd_nack = '0') or NACK.
--     C_RECOVER bus-stuck recovery: release SDA and clock SCL up to 9
--               times until SDA reads high, then STOP. err if SDA stays low.
-- * Single master: no arbitration detection (the shield bus has one master).
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
  generic (
    CLK_HZ      : positive := 125_000_000;
    SCL_HZ      : positive := 400_000;
    STRETCH_MAX : positive := 125_000      -- clocks (1 ms at 125 MHz)
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    cmd_valid : in  std_logic;
    cmd       : in  std_logic_vector(2 downto 0);
    wdata     : in  std_logic_vector(7 downto 0);
    rd_nack   : in  std_logic;               -- C_READ: '1' = NACK (last byte)
    ready     : out std_logic;
    done      : out std_logic;               -- one clock, end of a command
    rdata     : out std_logic_vector(7 downto 0);
    nack      : out std_logic;               -- C_WRITE: no ACK (valid with done)
    err       : out std_logic;               -- timeout / bus busy / stuck (with done)
    scl_in    : in  std_logic;
    sda_in    : in  std_logic;
    scl_low   : out std_logic;
    sda_low   : out std_logic
  );
end entity;

architecture rtl of i2c_master is
  constant C_START   : std_logic_vector(2 downto 0) := "001";
  constant C_STOP    : std_logic_vector(2 downto 0) := "010";
  constant C_WRITE   : std_logic_vector(2 downto 0) := "011";
  constant C_READ    : std_logic_vector(2 downto 0) := "100";
  constant C_RECOVER : std_logic_vector(2 downto 0) := "101";

  constant LOW_Q  : positive := (CLK_HZ * 11 + 40 * SCL_HZ - 1) / (40 * SCL_HZ);
  constant HIGH_Q : positive := (CLK_HZ * 9 + 40 * SCL_HZ - 1) / (40 * SCL_HZ);
  constant TMAX   : positive := 2 * LOW_Q + 2;   -- LOW_Q >= HIGH_Q
  -- SDA changes this long after SCL has gone low (hold time, pin skew)
  constant HOLD_Q : positive := (LOW_Q + 3) / 4;

  -- B_*: one bit (SCL low, SCL released + stretch wait, SCL high);
  -- R_LOW: recovery pulse low time; ST_*: (repeated) START; SP_*: STOP
  type st_t is (S_IDLE, S_B_LOW, S_B_REL, S_B_HIGH, S_B_END, S_R_LOW,
                S_ST_LOW, S_ST_REL, S_ST_SU, S_ST_HD,
                S_SP_0, S_SP_LOW, S_SP_REL, S_SP_SU, S_SP_BUF, S_DONE);
  signal st      : st_t := S_IDLE;
  signal ret     : st_t := S_B_HIGH;       -- state after a stretch wait
  signal tmr     : natural range 0 to TMAX := 0;
  signal stretch : natural range 0 to STRETCH_MAX := 0;
  signal scl_s, sda_s : std_logic_vector(1 downto 0) := "11";
  signal scl_l, sda_l : std_logic := '0';
  signal owned   : std_logic := '0';     -- we hold SCL low (between START and STOP)
  signal sr      : std_logic_vector(8 downto 0) := (others => '1');
  signal bitn    : natural range 0 to 9 := 0;
  signal is_rd, is_rec : std_logic := '0';
  signal e_nack, e_err : std_logic := '0';
  signal rd_r    : std_logic_vector(7 downto 0) := (others => '0');
  signal done_r  : std_logic := '0';
begin
  ready   <= '1' when st = S_IDLE else '0';
  done    <= done_r;
  rdata   <= rd_r;
  nack    <= e_nack;
  err     <= e_err;
  scl_low <= scl_l;
  sda_low <= sda_l;

  process (clk)
    -- count n clocks in the current state; true on the last one
    impure function last(n : natural) return boolean is
    begin
      return tmr + 1 >= n;
    end function;
  begin
    if rising_edge(clk) then
      scl_s <= scl_s(0) & to_x01(scl_in);
      sda_s <= sda_s(0) & to_x01(sda_in);
      done_r <= '0';
      if st /= S_IDLE then tmr <= tmr + 1; end if;
      if rst = '1' then
        st <= S_IDLE; tmr <= 0; scl_l <= '0'; sda_l <= '0'; owned <= '0';
        e_nack <= '0'; e_err <= '0';
      else
        case st is
          when S_IDLE =>
            tmr <= 0;
            if cmd_valid = '1' then
              e_nack <= '0'; e_err <= '0'; is_rd <= '0'; is_rec <= '0'; bitn <= 0;
              case cmd is
                when C_START =>
                  if owned = '1' then
                    st <= S_ST_LOW;                    -- repeated START
                  elsif scl_s(1) = '1' and sda_s(1) = '1' then
                    st <= S_ST_SU;
                  else
                    e_err <= '1'; st <= S_DONE;        -- bus busy / stuck
                  end if;
                when C_STOP =>
                  if owned = '1' then
                    sda_l <= '1'; st <= S_SP_LOW;
                  else
                    st <= S_DONE;
                  end if;
                when C_WRITE =>
                  sr <= wdata & '1';                   -- 9th bit released: ACK
                  st <= S_B_LOW;
                when C_READ =>
                  sr <= x"FF" & rd_nack; is_rd <= '1';
                  st <= S_B_LOW;
                when C_RECOVER =>
                  sda_l <= '0'; is_rec <= '1';
                  if sda_s(1) = '1' and scl_s(1) = '1' and owned = '0' then
                    st <= S_SP_0;                      -- nothing stuck: just STOP
                  else
                    scl_l <= '1'; st <= S_R_LOW;
                  end if;
                when others =>
                  st <= S_DONE;
              end case;
            end if;

          -- data bit: SDA set HOLD_Q into the low time (SCL low)
          when S_B_LOW =>
            if tmr + 1 = HOLD_Q then sda_l <= not sr(8); end if;
            if last(2 * LOW_Q) then
              scl_l <= '0'; stretch <= 0; ret <= S_B_HIGH; st <= S_B_REL;
            end if;
          when S_R_LOW =>
            if last(2 * LOW_Q) then
              scl_l <= '0'; stretch <= 0; ret <= S_B_HIGH; st <= S_B_REL;
            end if;
          when S_B_REL | S_ST_REL | S_SP_REL =>
            -- SCL released: wait until it reads high (clock stretching)
            tmr <= 0;
            if scl_s(1) = '1' then
              st <= ret;
            elsif stretch = STRETCH_MAX then
              scl_l <= '0'; sda_l <= '0'; owned <= '0'; e_err <= '1'; st <= S_DONE;
            else
              stretch <= stretch + 1;
            end if;
          when S_B_HIGH =>
            if tmr + 1 = HIGH_Q then
              sr <= sr(7 downto 0) & sda_s(1);         -- sample mid-high
            end if;
            if last(2 * HIGH_Q) then
              scl_l <= '1'; tmr <= 0; bitn <= bitn + 1;
              if is_rec = '1' then
                -- recovery: SDA sampled high, or 9 pulses: STOP
                if sr(0) = '1' or bitn + 1 = 9 then
                  if sr(0) = '0' then e_err <= '1'; end if;
                  st <= S_SP_0;
                else
                  st <= S_R_LOW;
                end if;
              elsif bitn + 1 = 9 then
                -- sr(8 downto 1) = the 8 data samples, sr(0) = the ACK slot
                if is_rd = '1' then rd_r <= sr(8 downto 1); else e_nack <= sr(0); end if;
                owned <= '1'; st <= S_B_END;
              else
                st <= S_B_LOW;
              end if;
            end if;

          when S_B_END =>
            -- release SDA (master ACK) only once SCL is safely low
            if last(HOLD_Q) then sda_l <= '0'; st <= S_DONE; end if;

          -- repeated START: SDA released while SCL low, SCL high, SDA low
          when S_ST_LOW =>
            sda_l <= '0';
            if last(2 * LOW_Q) then
              scl_l <= '0'; stretch <= 0; ret <= S_ST_SU; st <= S_ST_REL;
            end if;
          when S_ST_SU =>
            -- SCL and SDA high: tSU;STA, then SDA low
            if last(2 * HIGH_Q) then sda_l <= '1'; tmr <= 0; st <= S_ST_HD; end if;
          when S_ST_HD =>
            -- tHD;STA, then SCL low: the bus is ours
            if last(2 * HIGH_Q) then scl_l <= '1'; owned <= '1'; st <= S_DONE; end if;

          -- STOP: SDA low while SCL low, SCL high, then SDA high
          when S_SP_0 =>
            -- (recovery) make sure SCL is low before SDA goes low
            scl_l <= '1';
            if last(LOW_Q) then sda_l <= '1'; tmr <= 0; st <= S_SP_LOW; end if;
          when S_SP_LOW =>
            scl_l <= '1'; sda_l <= '1';
            if last(2 * LOW_Q) then
              scl_l <= '0'; stretch <= 0; ret <= S_SP_SU; st <= S_SP_REL;
            end if;
          when S_SP_SU =>
            if last(2 * HIGH_Q) then sda_l <= '0'; owned <= '0'; tmr <= 0; st <= S_SP_BUF; end if;
          when S_SP_BUF =>
            -- bus free time tBUF (>= 1.3 us at 400 kHz)
            if last(2 * LOW_Q) then st <= S_DONE; end if;

          when S_DONE =>
            done_r <= '1'; st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
