-- neighbour_link: the UART between the two supervisors of a unit (issue
-- 0069, ADR 0007 point 2 and its "Neighbour link protocol" section).
--
-- Both boards run the same image. Every HELLO_MS (100 ms) this end sends a
-- HELLO frame with its identity (board DNA, B = DIP[7:4], build and boot
-- id, sequence number) and its role claim; it parses the peer's HELLOs.
-- The peer is present while a valid HELLO from another board (DNA /= ours)
-- arrived in the last LOST_MS (350 ms: lost after ~3 missed HELLOs).
--
-- Role rule: no peer -> standalone; peer present -> the lower B is primary,
-- equal B ("B clash", boards should have distinct B) -> the lower DNA is
-- primary. A HELLO carrying our own DNA (TX looped to RX) sets loopback and
-- never makes a peer present.
--
-- Frame (ADR 0007): A5 5A type len_hi len_lo payload crc_hi crc_lo;
-- CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over type, length and
-- payload. The receiver hunts for A5 5A after any error, and drops a frame
-- whose bytes stop for more than 32 bit times, so it resynchronises after
-- garbage within one frame. Frames of unknown type with a good CRC are
-- counted and ignored (phase 2 adds types, e.g. tunnelled host traffic).
--
-- UART 8N1, 1 Mbaud (BAUD_INC for clk = 125 MHz; BIT_CLKS clocks per bit).
-- txd idles high; rxd needs a pull-up so an open link reads idle.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.net_pkg.all;

entity neighbour_link is
  generic (
    BAUD_INC : unsigned(31 downto 0) := x"020C_49BA";  -- round(1e6 * 2^32 / 125e6)
    BIT_CLKS : positive := 125;                         -- clocks per bit (byte timeout)
    HELLO_MS : positive := 100;                         -- HELLO period, tick_1ms units
    LOST_MS  : positive := 350                          -- presence timeout, tick_1ms units
  );
  port (
    clk      : in  std_logic;
    tick_1ms : in  std_logic;
    dip      : in  std_logic_vector(7 downto 0);        -- asynchronous (switches)
    dna      : in  std_logic_vector(63 downto 0);       -- 57-bit DNA, right aligned
    build_id : in  std_logic_vector(31 downto 0);
    boot_id  : in  std_logic_vector(31 downto 0);
    txd      : out std_logic;
    rxd      : in  std_logic;                           -- asynchronous
    status   : out nb_status_t
  );
end entity;

architecture rtl of neighbour_link is
  subtype byte_t is std_logic_vector(7 downto 0);
  constant SYNC0     : byte_t := x"A5";
  constant SYNC1     : byte_t := x"5A";
  constant T_HELLO   : byte_t := x"01";
  constant HELLO_LEN : natural := 28;      -- payload bytes sent (version 1)
  constant HELLO_MIN : natural := 26;      -- fields used by this receiver
  constant HELLO_MAX : natural := 64;      -- longer HELLOs: format error
  constant LEN_MAX   : natural := 1600;    -- any frame type (ADR 0007)
  constant FRAME_LEN : natural := 5 + HELLO_LEN + 2;
  constant BYTE_TO   : natural := 32 * BIT_CLKS;

  function crc16(c : std_logic_vector(15 downto 0); d : byte_t) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0) := c;
  begin
    for i in 7 downto 0 loop
      if (r(15) xor d(i)) = '1' then
        r := (r(14 downto 0) & '0') xor x"1021";
      else
        r := r(14 downto 0) & '0';
      end if;
    end loop;
    return r;
  end function;

  signal dip_m, dip_s : byte_t := (others => '0');

  -- transmit
  type tf_t is array (0 to FRAME_LEN - 3) of byte_t;   -- frame without the CRC
  signal tf      : tf_t := (others => (others => '0'));
  signal hcnt    : integer range 0 to HELLO_MS - 1 := HELLO_MS - 1;  -- first HELLO at the first tick
  signal sending : std_logic := '0';
  signal tidx    : integer range 0 to FRAME_LEN - 1 := 0;
  signal tv      : std_logic := '0';
  signal tdata   : byte_t := (others => '0');
  signal trdy    : std_logic;
  signal tcrc    : std_logic_vector(15 downto 0) := x"FFFF";
  signal tseq    : unsigned(31 downto 0) := (others => '0');
  signal tx_cnt  : unsigned(15 downto 0) := (others => '0');

  -- receive
  type rstate_t is (R_HUNT, R_SYNC1, R_TYPE, R_LEN0, R_LEN1, R_PAY, R_CRC0, R_CRC1);
  signal rs      : rstate_t := R_HUNT;
  signal rdata   : byte_t;
  signal rval, rferr : std_logic;
  signal rtype   : byte_t := (others => '0');
  signal rlen    : unsigned(15 downto 0) := (others => '0');
  signal rcnt    : unsigned(15 downto 0) := (others => '0');
  signal rcrc    : std_logic_vector(15 downto 0) := x"FFFF";
  signal rcrc_hi : byte_t := (others => '0');
  type rb_t is array (0 to HELLO_MIN - 1) of byte_t;
  signal rb      : rb_t := (others => (others => '0'));
  signal bto     : integer range 0 to BYTE_TO := 0;
  signal hello_ok : std_logic := '0';      -- strobe: the frame just checked is a valid HELLO

  signal rx_cnt, crc_cnt, uart_cnt, fmt_cnt : unsigned(15 downto 0) := (others => '0');

  -- peer
  signal p_valid  : std_logic := '0';
  signal p_dip, p_role, p_flags : byte_t := (others => '0');
  signal p_dna    : std_logic_vector(63 downto 0) := (others => '0');
  signal p_build  : std_logic_vector(31 downto 0) := (others => '0');
  signal p_seq    : unsigned(31 downto 0) := (others => '0');
  signal present, loopback : std_logic := '0';
  signal p_age, l_age : integer range 0 to LOST_MS := LOST_MS;
  signal role     : std_logic_vector(1 downto 0) := NB_ROLE_STANDALONE;
  signal clash    : std_logic := '0';
begin
  ---------------------------------------------------------------- transmit
  utx : entity work.uart_tx
    port map (clk => clk, baud_inc => BAUD_INC, data => tdata, valid => tv, ready => trdy, txd => txd);

  process (clk)
    variable b : byte_t;
  begin
    if rising_edge(clk) then
      dip_m <= dip;
      dip_s <= dip_m;

      if tick_1ms = '1' then
        if hcnt = HELLO_MS - 1 then
          hcnt <= 0;
          if sending = '0' then
            -- snapshot of the HELLO (version 1, ADR 0007)
            tf(0) <= SYNC0; tf(1) <= SYNC1; tf(2) <= T_HELLO;
            tf(3) <= x"00"; tf(4) <= std_logic_vector(to_unsigned(HELLO_LEN, 8));
            tf(5) <= x"4E"; tf(6) <= x"42"; tf(7) <= x"01";   -- "NB", version 1
            tf(8) <= dip_s;
            tf(9) <= "000000" & role;
            tf(10) <= "00000" & loopback & clash & present;
            for i in 0 to 7 loop tf(11 + i) <= dna(63 - 8 * i downto 56 - 8 * i); end loop;
            for i in 0 to 3 loop
              tf(19 + i) <= build_id(31 - 8 * i downto 24 - 8 * i);
              tf(23 + i) <= boot_id(31 - 8 * i downto 24 - 8 * i);
              tf(27 + i) <= std_logic_vector(tseq(31 - 8 * i downto 24 - 8 * i));
            end loop;
            tf(31) <= x"00"; tf(32) <= x"00";
            tseq    <= tseq + 1;
            sending <= '1';
            tidx    <= 0;
            tcrc    <= x"FFFF";
          end if;
        else
          hcnt <= hcnt + 1;
        end if;
      end if;

      if tv = '1' then
        -- accepted at this edge (uart_tx was ready)
        tv <= '0';
        if tidx = FRAME_LEN - 1 then
          sending <= '0';
          tx_cnt  <= tx_cnt + 1;
        else
          tidx <= tidx + 1;
        end if;
      elsif sending = '1' and trdy = '1' then
        if tidx < FRAME_LEN - 2 then
          b := tf(tidx);
          if tidx >= 2 then
            tcrc <= crc16(tcrc, b);
          end if;
        elsif tidx = FRAME_LEN - 2 then
          b := tcrc(15 downto 8);
        else
          b := tcrc(7 downto 0);
        end if;
        tdata <= b;
        tv    <= '1';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- receive
  urx : entity work.uart_rx
    port map (clk => clk, baud_inc => BAUD_INC, rxd => rxd, data => rdata, valid => rval, frame_err => rferr);

  process (clk)
    variable len : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      hello_ok <= '0';
      if rs = R_HUNT or rval = '1' then
        bto <= 0;
      elsif bto = BYTE_TO then
        -- the frame stopped mid-way: drop it (after a lone A5 just hunt on)
        if rs /= R_SYNC1 then
          fmt_cnt <= fmt_cnt + 1;
        end if;
        rs  <= R_HUNT;
        bto <= 0;
      else
        bto <= bto + 1;
      end if;

      if rferr = '1' then
        uart_cnt <= uart_cnt + 1;
        rs <= R_HUNT;
      elsif rval = '1' then
        case rs is
          when R_HUNT =>
            if rdata = SYNC0 then rs <= R_SYNC1; end if;
          when R_SYNC1 =>
            if rdata = SYNC1 then
              rs <= R_TYPE;
            elsif rdata /= SYNC0 then
              rs <= R_HUNT;
            end if;
          when R_TYPE =>
            rtype <= rdata;
            rcrc  <= crc16(x"FFFF", rdata);
            rs    <= R_LEN0;
          when R_LEN0 =>
            rlen(15 downto 8) <= unsigned(rdata);
            rcrc <= crc16(rcrc, rdata);
            rs   <= R_LEN1;
          when R_LEN1 =>
            len := rlen(15 downto 8) & unsigned(rdata);
            rlen <= len;
            rcrc <= crc16(rcrc, rdata);
            rcnt <= (others => '0');
            if len > LEN_MAX or
               (rtype = T_HELLO and (len < HELLO_MIN or len > HELLO_MAX)) then
              fmt_cnt <= fmt_cnt + 1;
              rs <= R_HUNT;
            elsif len = 0 then
              rs <= R_CRC0;
            else
              rs <= R_PAY;
            end if;
          when R_PAY =>
            if rcnt < HELLO_MIN then
              rb(to_integer(rcnt(4 downto 0))) <= rdata;
            end if;
            rcrc <= crc16(rcrc, rdata);
            rcnt <= rcnt + 1;
            if rcnt = rlen - 1 then
              rs <= R_CRC0;
            end if;
          when R_CRC0 =>
            rcrc_hi <= rdata;
            rs <= R_CRC1;
          when R_CRC1 =>
            rs <= R_HUNT;
            if rcrc_hi & rdata /= rcrc then
              crc_cnt <= crc_cnt + 1;
            else
              rx_cnt <= rx_cnt + 1;
              if rtype = T_HELLO then
                if rb(0) = x"4E" and rb(1) = x"42" and rb(2) /= x"00" then
                  hello_ok <= '1';
                else
                  fmt_cnt <= fmt_cnt + 1;
                end if;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- peer, role
  process (clk)
    variable rdna : std_logic_vector(63 downto 0);
    variable own_b, peer_b : unsigned(3 downto 0);
  begin
    if rising_edge(clk) then
      for i in 0 to 7 loop rdna(63 - 8 * i downto 56 - 8 * i) := rb(6 + i); end loop;
      if tick_1ms = '1' then
        if p_age < LOST_MS then p_age <= p_age + 1; else present  <= '0'; end if;
        if l_age < LOST_MS then l_age <= l_age + 1; else loopback <= '0'; end if;
      end if;
      if hello_ok = '1' then
        if rdna(56 downto 0) = dna(56 downto 0) then
          loopback <= '1';
          l_age    <= 0;
        else
          present <= '1';
          p_age   <= 0;
          p_valid <= '1';
          p_dip   <= rb(3);
          p_role  <= rb(4);
          p_flags <= rb(5);
          p_dna   <= rdna;
          p_build <= rb(14) & rb(15) & rb(16) & rb(17);
          p_seq   <= unsigned(std_logic_vector'(rb(22) & rb(23) & rb(24) & rb(25)));
        end if;
      end if;

      own_b  := unsigned(dip_s(7 downto 4));
      peer_b := unsigned(p_dip(7 downto 4));
      clash  <= '0';
      if present = '0' then
        role <= NB_ROLE_STANDALONE;
      elsif own_b < peer_b then
        role <= NB_ROLE_PRIMARY;
      elsif own_b > peer_b then
        role <= NB_ROLE_SECONDARY;
      else
        clash <= '1';
        if unsigned(dna(56 downto 0)) < unsigned(p_dna(56 downto 0)) then
          role <= NB_ROLE_PRIMARY;
        else
          role <= NB_ROLE_SECONDARY;   -- equal DNA never makes a peer present
        end if;
      end if;
    end if;
  end process;

  status.present    <= present;
  status.clash      <= clash;
  status.loopback   <= loopback;
  status.heard_us   <= present and p_flags(0);
  status.mismatch   <= '1' when present = '1' and not
                         ((role = NB_ROLE_PRIMARY and p_role = x"02") or
                          (role = NB_ROLE_SECONDARY and p_role = x"01")) else '0';
  status.valid      <= p_valid;
  status.role       <= role;
  status.primary    <= '1' when role = NB_ROLE_PRIMARY else '0';
  status.peer_dip   <= p_dip;
  status.peer_role  <= p_role;
  status.peer_dna   <= p_dna;
  status.peer_build <= p_build;
  status.peer_seq   <= p_seq;
  status.rx_frames  <= rx_cnt;
  status.crc_errs   <= crc_cnt;
  status.uart_errs  <= uart_cnt;
  status.fmt_errs   <= fmt_cnt;
  status.tx_frames  <= tx_cnt;
end architecture;
