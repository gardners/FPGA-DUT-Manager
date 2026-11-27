-- jtag_engine: bounded, sequenced JTAG shift engine for one DUT (ADR 0010).
--
-- Admission (from the packet dispatcher), one cycle req_valid; decision one
-- cycle later on dec_valid/dec_code:
--   DEC_ACCEPT     : dispatcher must now write TMS bytes to vec addr
--                    0..nbytes-1 and TDI bytes to 1024..1024+nbytes-1, then
--                    pulse go.  The previous cached result is discarded.
--   DEC_CACHED     : seq = last completed seq -> respond with cached TDO
--   DEC_BUSY       : seq = in-flight seq
--   DEC_BAD_SEQ    : unexpected seq; nothing clocked
--   DEC_BAD_FORMAT : bit_count 0 or > MAX_BITS, half period < 2
--   DEC_UNPOWERED  : target not powered; nothing clocked
--
-- Shifting: for each bit, TMS/TDI are driven while TCK is low, TCK is held
-- high for half_period cycles and TDO (2-FF synchronised) is sampled at the
-- end of the high phase, just before the falling edge (the target updates
-- TDO on the falling edge). Exactly bit_count rising edges; TCK idles low.
--
-- Parking (issue 0056): after every transaction (done or aborted) TMS and
-- TDI go low while TCK stays low, without a TCK edge, so the TAP state is
-- unchanged (an XVC session can continue from Run-Test/Idle, Pause-DR or
-- Shift-DR) and an idle output never drives a switched-off DUT's input
-- clamps high. The next transaction drives the TMS/TDI of its first bit at
-- the start of the low phase, at least 2 clk cycles (half_period) before
-- the first rising TCK edge.
--
-- TDO sampling (MGMT key 0x0064, issue 0054), latched at admission:
-- vote 0 = the single sample above; 1 = majority of the synchronised TDO on
-- the last three clk_sys cycles of the high half period (half >= 4, else
-- single); 2 = majority of the last five (half >= 6; half 4..5 -> three).
-- start_ok (key 0x0063): after go the engine waits for it before the first
-- TCK edge (the keyboard host is pausing); '1' when unused.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jtag_engine is
  generic (
    MAX_BITS : positive := 8192
  );
  port (
    clk          : in  std_logic;
    powered      : in  std_logic;
    -- admission
    req_valid    : in  std_logic;
    req_seq      : in  unsigned(31 downto 0);
    req_bits     : in  unsigned(31 downto 0);
    req_half     : in  unsigned(31 downto 0);
    req_abort    : in  std_logic;       -- reset session: next_seq := req_seq
    dec_valid    : out std_logic;
    dec_code     : out unsigned(2 downto 0);
    -- vector write port (dispatcher)
    vec_we       : in  std_logic;
    vec_addr     : in  unsigned(10 downto 0);
    vec_data     : in  std_logic_vector(7 downto 0);
    go           : in  std_logic;
    -- result read port (packet builder), 1-cycle latency
    tdo_addr     : in  unsigned(9 downto 0);
    tdo_data     : out std_logic_vector(7 downto 0);
    -- status
    busy         : out std_logic;
    result_ready : out std_logic;
    done_strobe  : out std_logic;       -- completion or abort
    aborted      : out std_logic;
    next_seq     : out unsigned(31 downto 0);
    last_seq     : out unsigned(31 downto 0);   -- seq of cached/in-flight
    last_bits    : out unsigned(31 downto 0);
    -- pins
    tck, tms, tdi : out std_logic;
    jtag_oe      : out std_logic;
    tdo          : in  std_logic;
    -- TDO sampling mode (key 0x0064) and start permission (key 0x0063)
    vote         : in  unsigned(1 downto 0) := "00";
    start_ok     : in  std_logic := '1'
  );
end entity;

architecture rtl of jtag_engine is
  constant DEC_ACCEPT     : unsigned(2 downto 0) := "000";
  constant DEC_CACHED     : unsigned(2 downto 0) := "001";
  constant DEC_BUSY       : unsigned(2 downto 0) := "010";
  constant DEC_BAD_SEQ    : unsigned(2 downto 0) := "011";
  constant DEC_BAD_FORMAT : unsigned(2 downto 0) := "100";
  constant DEC_UNPOWERED  : unsigned(2 downto 0) := "101";

  type state_t is (S_IDLE, S_LOADED, S_WAIT, S_RD_TMS, S_RD_TDI, S_GOT, S_LOW, S_HIGH, S_STORE, S_DONE);
  signal state : state_t := S_IDLE;

  signal nseq, cur_seq   : unsigned(31 downto 0) := (others => '0');
  signal have_result     : std_logic := '0';
  signal in_flight       : std_logic := '0';
  signal nbits, bitn     : unsigned(13 downto 0) := (others => '0');
  signal bits32          : unsigned(31 downto 0) := (others => '0');
  signal half, cnt       : unsigned(15 downto 0) := (others => '0');
  signal tms_byte, tdi_byte, tdo_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal tck_r, tms_r, tdi_r : std_logic := '0';
  signal tdo_s           : std_logic_vector(1 downto 0) := (others => '0');
  signal tdo_h           : std_logic_vector(3 downto 0) := (others => '0');  -- tdo_s(1) history
  signal vote_r          : unsigned(1 downto 0) := "00";
  signal abort_r         : std_logic := '0';

  signal vec_ra  : unsigned(10 downto 0) := (others => '0');
  signal vec_rd  : std_logic_vector(7 downto 0);
  signal tdo_we  : std_logic := '0';
  signal tdo_wa  : unsigned(9 downto 0) := (others => '0');
begin
  vec_mem : entity work.dpram generic map (11, 8)
    port map (clk, vec_we, vec_addr, vec_data, clk, vec_ra, vec_rd);
  tdo_mem : entity work.dpram generic map (10, 8)
    port map (clk, tdo_we, tdo_wa, tdo_byte, clk, tdo_addr, tdo_data);

  tck <= tck_r; tms <= tms_r; tdi <= tdi_r;
  jtag_oe      <= powered;
  busy         <= in_flight;
  result_ready <= have_result;
  aborted      <= abort_r;
  next_seq     <= nseq;
  last_seq     <= cur_seq;
  last_bits    <= bits32;

  process (clk)
    variable b : integer range 0 to 7;
    variable s0, s1, s2, s3, s4 : std_logic;
    variable n3 : unsigned(1 downto 0);
    variable n5 : unsigned(2 downto 0);
  begin
    if rising_edge(clk) then
      dec_valid   <= '0';
      tdo_we      <= '0';
      done_strobe <= '0';
      tdo_s <= tdo_s(0) & tdo;
      tdo_h <= tdo_h(2 downto 0) & tdo_s(1);

      -- admission -----------------------------------------------------------
      if req_valid = '1' then
        dec_valid <= '1';
        if req_abort = '1' then
          -- explicit session reset: only legal when idle
          if in_flight = '0' then
            nseq <= req_seq; have_result <= '0'; abort_r <= '0';
            dec_code <= DEC_CACHED;     -- acknowledged, nothing clocked
          else
            dec_code <= DEC_BUSY;
          end if;
        elsif in_flight = '1' and req_seq = cur_seq then
          dec_code <= DEC_BUSY;
        elsif have_result = '1' and req_seq = cur_seq then
          dec_code <= DEC_CACHED;
        elsif in_flight = '1' then
          dec_code <= DEC_BUSY;
        elsif req_seq /= nseq then
          dec_code <= DEC_BAD_SEQ;
        elsif req_bits = 0 or req_bits > MAX_BITS or req_half < 2 or req_half > 65535 then
          dec_code <= DEC_BAD_FORMAT;
        elsif powered = '0' then
          dec_code <= DEC_UNPOWERED;
        else
          dec_code    <= DEC_ACCEPT;
          in_flight   <= '1';
          have_result <= '0';
          abort_r     <= '0';
          cur_seq     <= req_seq;
          nseq        <= req_seq + 1;
          bits32      <= req_bits;
          nbits       <= req_bits(13 downto 0);
          half        <= req_half(15 downto 0);
          state       <= S_LOADED;
          vote_r      <= "00";
          if vote = 2 and req_half >= 6 then
            vote_r <= "10";
          elsif vote /= 0 and req_half >= 4 then
            vote_r <= "01";
          end if;
        end if;
      end if;

      -- shifting ------------------------------------------------------------
      case state is
        when S_IDLE =>
          null;
        when S_LOADED =>
          bitn <= (others => '0');
          if go = '1' then
            state <= S_WAIT;
          end if;
        when S_WAIT =>
          -- keyboard host pausing (key 0x0063): no TCK edge until allowed
          if powered = '0' then
            abort_r <= '1';
            state   <= S_DONE;
          elsif start_ok = '1' then
            state <= S_RD_TMS;
          end if;
        when S_RD_TMS =>
          -- fetch bytes for bit bitn (only at byte boundaries)
          vec_ra <= '0' & bitn(12 downto 3);
          state  <= S_RD_TDI;
        when S_RD_TDI =>
          vec_ra <= "1" & bitn(12 downto 3);
          state  <= S_GOT;
        when S_GOT =>
          -- vec_rd now holds TMS byte; TDI byte arrives next cycle
          tms_byte <= vec_rd;
          state    <= S_LOW;
          cnt      <= (others => '0');
          tdo_byte <= (others => '0');
        when S_LOW =>
          b := to_integer(bitn(2 downto 0));
          if cnt = 0 and b = 0 then
            tdi_byte <= vec_rd;         -- TDI byte from S_RD_TDI read
            tms_r    <= tms_byte(0);
            tdi_r    <= vec_rd(0);
          elsif cnt = 0 then
            tms_r <= tms_byte(b);
            tdi_r <= tdi_byte(b);
          end if;
          if powered = '0' then
            abort_r <= '1';
            state   <= S_DONE;
          elsif cnt = half - 1 then
            cnt   <= (others => '0');
            tck_r <= '1';
            state <= S_HIGH;
          else
            cnt <= cnt + 1;
          end if;
        when S_HIGH =>
          if cnt = half - 1 then
            cnt   <= (others => '0');
            tck_r <= '0';
            b := to_integer(bitn(2 downto 0));
            -- s0 = this cycle's synchronised TDO, s1..s4 the cycles before
            s0 := tdo_s(1); s1 := tdo_h(0); s2 := tdo_h(1); s3 := tdo_h(2); s4 := tdo_h(3);
            n3 := ('0' & s0) + ('0' & s1) + ('0' & s2);
            n5 := ("00" & s0) + ("00" & s1) + ("00" & s2) + ("00" & s3) + ("00" & s4);
            if vote_r = "10" then
              tdo_byte(b) <= n5(2) or (n5(1) and n5(0));   -- >= 3 of 5
            elsif vote_r = "01" then
              tdo_byte(b) <= n3(1);                         -- >= 2 of 3
            else
              tdo_byte(b) <= s0;
            end if;
            if b = 7 or bitn + 1 = nbits then
              state <= S_STORE;
            else
              bitn  <= bitn + 1;
              state <= S_LOW;
            end if;
          else
            cnt <= cnt + 1;
          end if;
        when S_STORE =>
          tdo_we <= '1';
          tdo_wa <= bitn(12 downto 3);
          if bitn + 1 = nbits then
            state <= S_DONE;
          else
            bitn  <= bitn + 1;
            state <= S_RD_TMS;
          end if;
        when S_DONE =>
          tck_r       <= '0';
          tms_r       <= '0';           -- park (issue 0056): no TCK edge
          tdi_r       <= '0';
          in_flight   <= '0';
          have_result <= not abort_r;
          done_strobe <= '1';
          state       <= S_IDLE;
      end case;
    end if;
  end process;
end architecture;
