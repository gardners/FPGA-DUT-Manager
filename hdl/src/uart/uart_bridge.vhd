-- uart_bridge: one DUT's UDP<->UART bridge (ADR 0005 section 6).
--
--  * TX ring (2 KiB) with mandatory expected-offset, all-or-nothing admission.
--  * RX history (512 B) and TX history (128 B) rings addressed by absolute
--    byte counters; "clear" is O(1): bytes older than rx_seq_at_clear read
--    as zero in snapshots.
--  * Snapshot scheduler: periodic, fast mode (on RX byte), expedited (on
--    rejection), with a minimum spacing between dispatches.
--
-- Snapshot readout: the packet builder pulses snap_ack (counters latch into
-- snap_* outputs) and then reads hist_addr 0..639 with 1-cycle latency:
-- 0..511 = RX history oldest->newest, 512..639 = TX history oldest->newest.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_bridge is
  generic (
    TX_RING_AW  : positive := 11;       -- 2048-byte TX ring
    MIN_SPACING_US : positive := 100
  );
  port (
    clk           : in  std_logic;
    tick_1us      : in  std_logic;
    -- configuration
    baud_inc      : in  unsigned(31 downto 0);
    out_enable    : in  std_logic;      -- target powered / outputs allowed
    snap_enable   : in  std_logic;
    fast_mode     : in  std_logic;
    snap_period_us: in  unsigned(15 downto 0);
    -- pins
    txd           : out std_logic;
    txd_oe        : out std_logic;
    rxd           : in  std_logic;
    -- host TX admission (from packet dispatcher)
    adm_valid     : in  std_logic;      -- one-cycle request
    adm_offset    : in  unsigned(31 downto 0);
    adm_count     : in  unsigned(15 downto 0);
    adm_clear     : in  std_logic;
    adm_cmd_id    : in  unsigned(15 downto 0);
    adm_done      : out std_logic;      -- one cycle after adm_valid
    adm_ok        : out std_logic;      -- if '1', send adm_count bytes on wr_*
    wr_valid      : in  std_logic;
    wr_data       : in  std_logic_vector(7 downto 0);
    -- snapshot interface to packet builder
    snap_req      : out std_logic;      -- level: a snapshot is due
    snap_ack      : in  std_logic;      -- builder starts one now
    hist_addr     : in  unsigned(9 downto 0);
    hist_data     : out std_logic_vector(7 downto 0);
    -- latched counters for the snapshot being built
    snap_rx_seq       : out unsigned(31 downto 0);
    snap_tx_accepted  : out unsigned(31 downto 0);
    snap_tx_emitted   : out unsigned(31 downto 0);
    snap_tx_free      : out unsigned(15 downto 0);
    snap_framing_errs : out unsigned(15 downto 0);
    snap_rx_overflows : out unsigned(15 downto 0);
    snap_tx_rejects   : out unsigned(15 downto 0);
    snap_clear_gen    : out unsigned(15 downto 0);
    snap_rx_seq_clear : out unsigned(31 downto 0);
    snap_seq          : out unsigned(31 downto 0);
    -- live status (heartbeat)
    rx_seq_o      : out unsigned(31 downto 0);
    tx_accepted_o : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of uart_bridge is
  constant RING : natural := 2 ** TX_RING_AW;

  -- counters
  signal rx_seq, tx_accepted, tx_emitted, rx_seq_at_clear : unsigned(31 downto 0) := (others => '0');
  signal framing_errs, rx_overflows, tx_rejects, clear_gen : unsigned(15 downto 0) := (others => '0');
  signal last_clear_id : unsigned(15 downto 0) := (others => '1');
  signal clear_id_valid: std_logic := '0';
  signal snap_count    : unsigned(31 downto 0) := (others => '0');

  -- TX ring
  signal ring_we   : std_logic := '0';
  signal ring_wa   : unsigned(TX_RING_AW - 1 downto 0);
  signal ring_wd   : std_logic_vector(7 downto 0);
  signal ring_ra   : unsigned(TX_RING_AW - 1 downto 0);
  signal ring_rd   : std_logic_vector(7 downto 0);
  signal wr_ptr    : unsigned(31 downto 0) := (others => '0');  -- next write offset

  -- UART cores
  signal utx_data  : std_logic_vector(7 downto 0);
  signal utx_valid, utx_ready : std_logic;
  signal urx_data  : std_logic_vector(7 downto 0);
  signal urx_valid, urx_ferr : std_logic;
  type tx_state_t is (T_IDLE, T_READ, T_SEND, T_WAIT);
  signal tx_state  : tx_state_t := T_IDLE;

  -- histories
  signal rxh_we    : std_logic := '0';
  signal rxh_wa    : unsigned(8 downto 0);
  signal rxh_wd    : std_logic_vector(7 downto 0);
  signal rxh_ra    : unsigned(8 downto 0);
  signal rxh_rd    : std_logic_vector(7 downto 0);
  signal txh_we    : std_logic := '0';
  signal txh_wa    : unsigned(6 downto 0);
  signal txh_wd    : std_logic_vector(7 downto 0);
  signal txh_ra    : unsigned(6 downto 0);
  signal txh_rd    : std_logic_vector(7 downto 0);

  -- snapshot latches
  signal l_rx_seq, l_tx_emitted, l_rx_clear : unsigned(31 downto 0) := (others => '0');
  signal zero_rx, zero_tx, sel_tx : std_logic := '0';

  -- scheduler
  signal pending      : std_logic := '0';
  signal since_last   : unsigned(15 downto 0) := (others => '1');
  signal since_period : unsigned(15 downto 0) := (others => '0');

  function min512(d : unsigned(31 downto 0)) return unsigned is
  begin
    if d > 512 then return to_unsigned(512, 10); end if;
    return d(9 downto 0);
  end function;
begin
  ---------------------------------------------------------------- memories
  ring_mem : entity work.dpram generic map (TX_RING_AW, 8)
    port map (clk, ring_we, ring_wa, ring_wd, clk, ring_ra, ring_rd);
  rxh_mem : entity work.dpram generic map (9, 8)
    port map (clk, rxh_we, rxh_wa, rxh_wd, clk, rxh_ra, rxh_rd);
  txh_mem : entity work.dpram generic map (7, 8)
    port map (clk, txh_we, txh_wa, txh_wd, clk, txh_ra, txh_rd);

  utx : entity work.uart_tx port map (clk, baud_inc, utx_data, utx_valid, utx_ready, txd);
  urx : entity work.uart_rx port map (clk, baud_inc, rxd, urx_data, urx_valid, urx_ferr);

  txd_oe        <= out_enable;
  rx_seq_o      <= rx_seq;
  tx_accepted_o <= tx_accepted;
  snap_req      <= '1' when pending = '1' and since_last >= MIN_SPACING_US else '0';

  ---------------------------------------------------------------- main
  process (clk)
    variable used, free : unsigned(31 downto 0);
    variable vcount     : unsigned(9 downto 0);
    variable p          : unsigned(9 downto 0);
    variable want_snap  : boolean;
  begin
    if rising_edge(clk) then
      adm_done <= '0';
      adm_ok   <= '0';
      ring_we  <= '0';
      rxh_we   <= '0';
      txh_we   <= '0';
      utx_valid <= '0';
      want_snap := false;

      used := tx_accepted - tx_emitted;
      free := to_unsigned(RING, 32) - used;

      -- admission ---------------------------------------------------------
      if adm_valid = '1' then
        adm_done <= '1';
        if adm_clear = '1' and (clear_id_valid = '0' or adm_cmd_id /= last_clear_id) then
          last_clear_id   <= adm_cmd_id;
          clear_id_valid  <= '1';
          rx_seq_at_clear <= rx_seq;
          clear_gen       <= clear_gen + 1;
        end if;
        if adm_offset = tx_accepted and resize(adm_count, 32) <= free then
          adm_ok <= '1';
          wr_ptr <= tx_accepted;
        else
          tx_rejects <= tx_rejects + 1;
          want_snap  := true;           -- expedited feedback
        end if;
      end if;

      if wr_valid = '1' then
        ring_we     <= '1';
        ring_wa     <= wr_ptr(TX_RING_AW - 1 downto 0);
        ring_wd     <= wr_data;
        wr_ptr      <= wr_ptr + 1;
        tx_accepted <= tx_accepted + 1;
      end if;

      -- TX drain ------------------------------------------------------------
      case tx_state is
        when T_IDLE =>
          if used /= 0 and utx_ready = '1' and out_enable = '1' then
            ring_ra  <= tx_emitted(TX_RING_AW - 1 downto 0);
            tx_state <= T_READ;
          end if;
        when T_READ =>
          tx_state <= T_SEND;           -- RAM latency
        when T_SEND =>
          utx_data   <= ring_rd;
          utx_valid  <= '1';
          txh_we     <= '1';
          txh_wa     <= tx_emitted(6 downto 0);
          txh_wd     <= ring_rd;
          tx_emitted <= tx_emitted + 1;
          tx_state   <= T_WAIT;
        when T_WAIT =>
          tx_state <= T_IDLE;           -- let utx_ready fall
      end case;
      -- utx_ready drops the cycle after utx_valid; T_IDLE checks it again.

      -- RX ------------------------------------------------------------------
      if urx_valid = '1' then
        rxh_we <= '1';
        rxh_wa <= rx_seq(8 downto 0);
        rxh_wd <= urx_data;
        rx_seq <= rx_seq + 1;
        if fast_mode = '1' then
          want_snap := true;
        end if;
      end if;
      if urx_ferr = '1' then
        framing_errs <= framing_errs + 1;
      end if;

      -- scheduler -----------------------------------------------------------
      if tick_1us = '1' then
        if since_last /= x"FFFF" then
          since_last <= since_last + 1;
        end if;
        since_period <= since_period + 1;
      end if;
      if snap_enable = '1' and since_period >= snap_period_us then
        want_snap := true;
      end if;
      if snap_enable = '1' and want_snap then
        pending <= '1';
      end if;
      if snap_ack = '1' then
        pending      <= '0';
        since_last   <= (others => '0');
        since_period <= (others => '0');
        snap_count   <= snap_count + 1;
        -- latch counters
        l_rx_seq     <= rx_seq;
        l_tx_emitted <= tx_emitted;
        l_rx_clear   <= rx_seq_at_clear;
        snap_rx_seq       <= rx_seq;
        snap_tx_accepted  <= tx_accepted;
        snap_tx_emitted   <= tx_emitted;
        snap_tx_free      <= resize(free, 16);
        snap_framing_errs <= framing_errs;
        snap_rx_overflows <= rx_overflows;
        snap_tx_rejects   <= tx_rejects;
        snap_clear_gen    <= clear_gen;
        snap_rx_seq_clear <= rx_seq_at_clear;
        snap_seq          <= snap_count;
      end if;

      -- history readout: flags registered alongside the RAM read
      p := hist_addr;
      sel_tx <= p(9);
      vcount := min512(l_rx_seq - l_rx_clear);
      if p(8 downto 0) < 512 - vcount then zero_rx <= '1'; else zero_rx <= '0'; end if;
      if l_tx_emitted < 128 and p(6 downto 0) < 128 - l_tx_emitted(6 downto 0) then
        zero_tx <= '1';
      else
        zero_tx <= '0';
      end if;
    end if;
  end process;

  -- RX position p maps to absolute offset l_rx_seq - 512 + p, i.e. index
  -- (l_rx_seq + p) mod 512; TX likewise mod 128.
  rxh_ra <= l_rx_seq(8 downto 0) + hist_addr(8 downto 0);
  txh_ra <= l_tx_emitted(6 downto 0) + hist_addr(6 downto 0);
  hist_data <= (others => '0') when (sel_tx = '0' and zero_rx = '1') or (sel_tx = '1' and zero_tx = '1')
               else txh_rd when sel_tx = '1' else rxh_rd;
end architecture;
