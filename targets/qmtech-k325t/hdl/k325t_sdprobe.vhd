-- QMTECH XC7K325T + DB_FPGA V04: microSD probe (issue 0057).
--
-- Finds out how a 6-pin PMOD microSD adapter of unknown orientation is wired
-- to J11 pins 1-4, and whether the daughter board's own microSD slot (J9)
-- holds a card. Everything is reported on the JP1 UART (2 Mbaud 8N1, same
-- pins as the bring-up design).
--
-- 1. Pin test ('p'): idle level of J11 pins 1-4 and 7-10 and of the J9 slot
--    pins with the FPGA's weak pull of this build (PULL_SEL; build.tcl builds
--    one bitstream per pull), then per J11 pin 1-4: drive low 1 us and read
--    back (reads 1 = tied to 3.3 V), release and read after 50 us, drive high
--    1 us and read back (reads 0 = tied to GND), release and read after 50 us.
-- 2. J11 SD probe ('j'): SPI-mode init for all 24 assignments of
--    {CS, DI(MOSI), DO(MISO), SCK} to J11 pins 1-4, all four pins high-Z for
--    GAP_US between tries: 80 clocks with CS and DI high, CMD0 -> R1. Where
--    R1 = 0x01 the full init follows: CMD8, CMD55+ACMD41 loop, CMD58, CMD9
--    (CSD), CMD10 (CID), with the CID and capacity decoded.
-- 3. DB slot probe ('d'): the same on J9 with CS = DAT3, DI = CMD, DO = DAT0,
--    SCK = CLK (DAT1/DAT2 high-Z, 4.7k pull-ups on the board); card-detect
--    level printed.
--
-- After configuration the design runs the pin test, then 'j' and 'd' unless
-- the pin test found a J11 pin tied to a rail (then only on request). UART
-- commands: p, j, d, a (all), ? (help); DB SW1 = a.
--
-- 7-segment: alternates J11 status ("P05" = card answered at assignment 5,
-- "noC" = no answer in any assignment, "---" = not run / running) and DB slot
-- status ("d.C1" card answered, "d.C0" no answer, "d.--"). LEDs D1-D5 = the
-- winning J11 assignment number in binary. Core LED2 = heartbeat, LED3 = on
-- while the J9 card-detect pin reads low.
--
-- SPI mode 0 at CLK_HZ / (2 * SPI_HALF) (250 kHz). Plain VHDL-2008.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k325t_sdprobe is
  generic (
    CLK_HZ     : positive := 50_000_000;
    BAUD       : positive := 2_000_000;
    US         : positive := 50;         -- clocks per microsecond
    SPI_HALF   : positive := 100;        -- clocks per half SCK period
    GAP_US     : positive := 1000;       -- all pins high-Z between tries
    ACMD41_MAX : positive := 2000;       -- ACMD41 attempts (~0.7 ms each)
    PULL_SEL   : natural  := 1;          -- J11 weak pull in this build: 0 none, 1 up, 2 down
    MUX_HZ     : positive := 3_000
  );
  port (
    clk50      : in    std_logic;
    seg_n      : out   std_logic_vector(7 downto 0);
    dig        : out   std_logic_vector(2 downto 0);
    db_led_n   : out   std_logic_vector(4 downto 0);
    core_led_n : out   std_logic_vector(1 downto 0);
    sw1_n      : in    std_logic;
    uart_tx    : out   std_logic;
    uart_rx    : in    std_logic;
    j11        : inout std_logic_vector(3 downto 0);  -- J11 pins 1..4
    j11b       : in    std_logic_vector(3 downto 0);  -- J11 pins 7..10 (read only)
    sd_clk     : inout std_logic;                     -- J9 microSD (daughter board)
    sd_cmd     : inout std_logic;
    sd_dat     : inout std_logic_vector(3 downto 0);
    sd_cd      : in    std_logic
  );
end entity;

architecture rtl of k325t_sdprobe is

  subtype byte is std_logic_vector(7 downto 0);
  type bytes16 is array (0 to 15) of byte;
  type nat4 is array (0 to 3) of natural range 0 to 3;  -- CS, DI, DO, CK
  type perm_arr is array (0 to 23) of nat4;

  function mkperms return perm_arr is
    variable r : perm_arr;
    variable k : natural := 0;
  begin
    for a in 0 to 3 loop
      for b in 0 to 3 loop
        for c in 0 to 3 loop
          for d in 0 to 3 loop
            if a /= b and a /= c and a /= d and b /= c and b /= d and c /= d then
              r(k) := (a, b, c, d);
              k := k + 1;
            end if;
          end loop;
        end loop;
      end loop;
    end loop;
    return r;
  end function;
  constant PERMS : perm_arr := mkperms;  -- 0 = CS 1, DI 2, DO 3, CK 4 (PMOD SD order)

  ---------------------------------------------------------------------------
  -- text helpers
  ---------------------------------------------------------------------------
  constant PB_LEN : positive := 128;
  type pbuf_t is array (1 to PB_LEN) of byte;

  function pad(s : string) return pbuf_t is
    variable r : pbuf_t := (others => x"20");
  begin
    for i in 1 to PB_LEN loop
      if i <= s'length then
        r(i) := std_logic_vector(to_unsigned(character'pos(s(s'low + i - 1)), 8));
      end if;
    end loop;
    return r;
  end function;

  function hexchar(n : unsigned(3 downto 0)) return character is
    constant H : string(1 to 16) := "0123456789ABCDEF";
  begin
    return H(to_integer(n) + 1);
  end function;

  function hx(v : std_logic_vector) return string is
    constant N : natural := (v'length + 3) / 4;
    variable x : unsigned(N * 4 - 1 downto 0) := resize(unsigned(v), N * 4);
    variable r : string(1 to N);
  begin
    for i in 0 to N - 1 loop
      r(N - i) := hexchar(x(i * 4 + 3 downto i * 4));
    end loop;
    return r;
  end function;

  function hx16(b : bytes16) return string is
    variable r : string(1 to 32);
  begin
    for i in 0 to 15 loop
      r(2 * i + 1 to 2 * i + 2) := hx(b(i));
    end loop;
    return r;
  end function;

  function dec2(n : natural) return string is
    variable r : string(1 to 2);
  begin
    r(1) := character'val(48 + (n / 10) mod 10);
    r(2) := character'val(48 + n mod 10);
    return r;
  end function;

  function bit_c(s : std_logic) return character is
  begin
    if s = '1' then return '1'; else return '0'; end if;
  end function;

  function pchr(b : byte) return character is
  begin
    if unsigned(b) >= 16#20# and unsigned(b) <= 16#7E# then
      return character'val(to_integer(unsigned(b)));
    else
      return '?';
    end if;
  end function;

  function pin_c(n : natural) return character is
  begin
    return character'val(49 + n);
  end function;

  function pull_name(sel : natural) return string is
  begin
    case sel is
      when 1 => return "pull-up  ";
      when 2 => return "pull-down";
      when others => return "no pull  ";
    end case;
  end function;
  constant PNAME : string(1 to 9) := pull_name(PULL_SEL);

  type ball_arr is array (0 to 3) of string(1 to 3);
  constant BALL : ball_arr := ("A8 ", "B9 ", "A10", "D10");

  -- class of a J11 pin from the drive/release test (fixed width)
  function pin_class(dl, rl, dh, rh : std_logic) return string is
  begin
    if dl = '1' and dh = '0' then return "?? both drives lost   ";
    elsif dl = '1' then return "TIED HIGH (3.3V rail?)";
    elsif dh = '0' then return "TIED LOW (GND?)       ";
    elsif rl = '1' and rh = '1' then return "pulled up             ";
    elsif rl = '0' and rh = '0' then return "pulled down           ";
    elsif rl = '0' and rh = '1' then return "floating (keeps level)";
    else return "?? inverts            ";
    end if;
  end function;

  function bcd_str(b : unsigned(39 downto 0)) return string is
    variable r : string(1 to 10);
    variable lead : boolean := true;
    variable d : unsigned(3 downto 0);
  begin
    for i in 9 downto 0 loop
      d := b(i * 4 + 3 downto i * 4);
      if lead and d = 0 and i /= 0 then
        r(10 - i) := ' ';
      else
        lead := false;
        r(10 - i) := character'val(48 + to_integer(d));
      end if;
    end loop;
    return r;
  end function;

  function crc7(v : std_logic_vector(39 downto 0)) return std_logic_vector is
    variable c : std_logic_vector(6 downto 0) := (others => '0');
    variable fb : std_logic;
  begin
    for i in 39 downto 0 loop
      fb := v(i) xor c(6);
      c := c(5 downto 0) & '0';
      if fb = '1' then c := c xor "0001001"; end if;
    end loop;
    return c;
  end function;

  ---------------------------------------------------------------------------
  -- 7-segment patterns (bit 0 = a .. bit 6 = g, '1' = lit)
  ---------------------------------------------------------------------------
  type seg_arr is array (0 to 2) of std_logic_vector(7 downto 0);  -- bit 7 = dp
  constant SG_DASH : std_logic_vector(6 downto 0) := "1000000";
  constant SG_P    : std_logic_vector(6 downto 0) := "1110011";
  constant SG_N    : std_logic_vector(6 downto 0) := "1010100";
  constant SG_O    : std_logic_vector(6 downto 0) := "1011100";
  constant SG_C    : std_logic_vector(6 downto 0) := "0111001";
  constant SG_D    : std_logic_vector(6 downto 0) := "1011110";
  function seg7(d : natural) return std_logic_vector is
  begin
    case d is
      when 0 => return "0111111";
      when 1 => return "0000110";
      when 2 => return "1011011";
      when 3 => return "1001111";
      when 4 => return "1100110";
      when 5 => return "1101101";
      when 6 => return "1111101";
      when 7 => return "0000111";
      when 8 => return "1111111";
      when 9 => return "1101111";
      when others => return SG_DASH;
    end case;
  end function;

  ---------------------------------------------------------------------------
  -- signals
  ---------------------------------------------------------------------------
  type st_t is (
    S_BOOT, S_HELP, S_DISPATCH, S_PROMPT, S_IDLE, S_PR,
    -- pin test
    T_START, T_DB, T_PIN, T_DRV, T_REL, T_LINE, T_END,
    -- SD probe (J11 assignments 0..23, DB slot = 24)
    J_START, D_START, P_TRY, P_GAP, P_PWR, P_DUMMY, P_CMD0R, P_CHK, P_NEXT, J_DONE, D_DONE,
    -- full card init
    I_START, I_8R, I_41, I_41B, I_41C, I_58, I_58R, I_9, I_9R, I_10, I_10R, I_CID,
    I_CAP, I_DD, I_CAPP, I_END,
    -- command subroutine
    C_GO, C_F, C_R1, C_EX, C_EXR, C_TK, C_TKR, C_BK, C_BKR, C_END,
    -- byte transfer subroutine
    X_GO, X_W);
  signal st, ret_p, ret_c, ret_x, ret_i : st_t := S_BOOT;

  signal pbuf : pbuf_t := (others => x"20");
  signal plen : natural range 0 to PB_LEN := 0;
  signal pi   : natural range 1 to PB_LEN + 1 := 1;

  -- run sequence flags
  signal seq_pin, seq_j, seq_d : std_logic := '0';
  signal auto_sd : std_logic := '1';  -- run SD probes after the boot pin test
  signal tied    : std_logic := '0';

  -- pin I/O
  signal j11_s, j11_s0   : std_logic_vector(3 downto 0) := (others => '1');
  signal j11b_s, j11b_s0 : std_logic_vector(3 downto 0) := (others => '1');
  signal sd_s, sd_s0     : std_logic_vector(6 downto 0) := (others => '1'); -- cd dat0 dat1 dat2 dat3 cmd clk
  signal test_oe, test_o : std_logic_vector(3 downto 0) := (others => '0');
  signal act    : std_logic := '0';   -- SPI pins driven
  signal tgt_db : std_logic := '0';   -- '1' = J9 slot
  signal perm   : natural range 0 to 24 := 0;
  signal r_cs, r_di, r_do, r_ck : natural range 0 to 3 := 0;
  signal cs     : std_logic := '1';
  signal miso   : std_logic;

  -- pin test
  signal pt_i  : natural range 0 to 3 := 0;
  signal pt_ph : natural range 0 to 3 := 0;
  signal pt_r  : std_logic_vector(3 downto 0) := (others => '0');  -- dl rl dh rh
  signal idle_j11 : std_logic_vector(3 downto 0) := (others => '0');

  -- timers / counters
  signal tmr  : natural range 0 to 2 ** 20 - 1 := 0;
  signal cnt  : natural range 0 to 4095 := 0;
  signal tries : natural range 0 to ACMD41_MAX := 0;

  -- SPI byte engine
  signal spi_go, spi_done : std_logic := '0';
  signal spi_txb, spi_rxb : byte := x"FF";
  signal sck, mosi : std_logic := '0';
  signal xb, rx : byte := x"FF";

  -- command subroutine
  signal cmd_i   : natural range 0 to 63 := 0;
  signal cmd_a   : std_logic_vector(31 downto 0) := (others => '0');
  signal cmd_n   : natural range 0 to 4 := 0;
  signal cmd_blk : std_logic := '0';
  signal frame   : std_logic_vector(47 downto 0) := (others => '1');
  signal cbyte   : natural range 0 to 18 := 0;
  signal r1      : byte := x"FF";
  signal resp    : std_logic_vector(31 downto 0) := (others => '0');
  signal blk     : bytes16 := (others => x"00");
  signal tok_ok  : std_logic := '0';

  -- card results
  signal v2      : std_logic := '0';
  signal csd, cid : bytes16 := (others => x"00");
  signal dd_bin  : unsigned(31 downto 0) := (others => '0');
  signal dd_bcd  : unsigned(39 downto 0) := (others => '0');
  signal dd_n    : natural range 0 to 32 := 0;
  signal kib     : unsigned(31 downto 0) := (others => '0');

  -- status
  signal j_stat, d_stat : natural range 0 to 3 := 0;  -- 0 none/running, 2 card, 3 no card
  signal j_win   : natural range 0 to 31 := 31;
  signal answered : std_logic := '0';
  signal j_win_u : unsigned(4 downto 0);

  -- text FIFO + UART
  type fifo_t is array (0 to 4095) of byte;
  signal fifo : fifo_t;
  signal wr_p, rd_p : unsigned(11 downto 0) := (others => '0');
  signal f_we  : std_logic := '0';
  signal f_wd  : byte := x"00";
  signal f_rd  : byte := x"00";
  signal f_full : std_logic;
  constant BIT_CLKS : positive := CLK_HZ / BAUD;
  signal tx_shift : std_logic_vector(9 downto 0) := (others => '1');
  signal tx_bits  : natural range 0 to 10 := 0;
  signal tx_cnt   : natural range 0 to BIT_CLKS - 1 := 0;
  signal tx_ph    : natural range 0 to 2 := 0;
  signal rx_s     : std_logic_vector(2 downto 0) := "111";
  signal rx_busy  : std_logic := '0';
  signal rx_cnt   : natural range 0 to BIT_CLKS + BIT_CLKS / 2 := 0;
  signal rx_bits  : natural range 0 to 9 := 0;
  signal rx_sr    : byte := x"00";
  signal ucmd     : byte := x"00";
  signal ucmd_v   : std_logic := '0';
  signal ucmd_ack : std_logic := '0';
  signal sw1_s    : std_logic_vector(2 downto 0) := "111";

  -- display
  signal mux_cnt : natural range 0 to CLK_HZ / MUX_HZ - 1 := 0;
  signal mux_sel : natural range 0 to 2 := 0;
  signal hb_cnt  : natural range 0 to CLK_HZ / 2 - 1 := 0;
  signal hb      : std_logic := '0';
  signal page    : natural range 0 to 2 := 0;  -- counts half seconds; 0-2 J11, toggles
  signal show_db : std_logic := '0';
  signal disp    : seg_arr;

begin

  ---------------------------------------------------------------------------
  -- pin muxing
  ---------------------------------------------------------------------------
  g_j11 : for i in 0 to 3 generate
    signal oe, o : std_logic;
  begin
    oe <= '1' when test_oe(i) = '1' else
          '1' when act = '1' and tgt_db = '0' and (i = r_cs or i = r_di or i = r_ck) else '0';
    o  <= test_o(i) when test_oe(i) = '1' else
          cs   when i = r_cs else
          mosi when i = r_di else
          sck;
    j11(i) <= o when oe = '1' else 'Z';
  end generate;

  sd_dat(3) <= cs   when act = '1' and tgt_db = '1' else 'Z';
  sd_cmd    <= mosi when act = '1' and tgt_db = '1' else 'Z';
  sd_clk    <= sck  when act = '1' and tgt_db = '1' else 'Z';
  sd_dat(2 downto 0) <= (others => 'Z');

  miso <= sd_s(5) when tgt_db = '1' else j11_s(r_do);

  process (clk50)
  begin
    if rising_edge(clk50) then
      j11_s0 <= to_x01(j11);   j11_s <= j11_s0;
      j11b_s0 <= to_x01(j11b); j11b_s <= j11b_s0;
      sd_s0 <= to_x01(sd_cd & sd_dat(0) & sd_dat(1) & sd_dat(2) & sd_dat(3) & sd_cmd & sd_clk);
      sd_s <= sd_s0;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- SPI mode 0 byte engine: MOSI changes after SCK falls, MISO sampled on rise
  ---------------------------------------------------------------------------
  process (clk50)
    variable hc : natural range 0 to SPI_HALF - 1 := 0;
    variable bn : natural range 0 to 7 := 0;
    variable sh, rv : byte := x"FF";
    variable busy : boolean := false;
  begin
    if rising_edge(clk50) then
      spi_done <= '0';
      if not busy then
        sck <= '0';
        if spi_go = '1' then
          busy := true;
          sh := spi_txb;
          mosi <= spi_txb(7);
          hc := SPI_HALF - 1;
          bn := 0;
        else
          mosi <= '1';
        end if;
      elsif hc /= 0 then
        hc := hc - 1;
      else
        hc := SPI_HALF - 1;
        if sck = '0' then
          sck <= '1';
          rv := rv(6 downto 0) & miso;
        else
          sck <= '0';
          if bn = 7 then
            busy := false;
            spi_rxb <= rv;
            spi_done <= '1';
            mosi <= '1';
          else
            bn := bn + 1;
            sh := sh(6 downto 0) & '1';
            mosi <= sh(7);
          end if;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- main sequencer
  ---------------------------------------------------------------------------
  process (clk50)

    procedure say(s : string; nxt : st_t) is
    begin
      pbuf  <= pad(s & CR & LF);
      plen  <= minimum(s'length + 2, PB_LEN);
      pi    <= 1;
      ret_p <= nxt;
      st    <= S_PR;
    end procedure;

    procedure sd_cmd_call(idx : natural; arg : std_logic_vector(31 downto 0);
                          n : natural; b : std_logic; nxt : st_t) is
      variable f : std_logic_vector(39 downto 0);
    begin
      f := "01" & std_logic_vector(to_unsigned(idx, 6)) & arg;
      frame   <= f & crc7(f) & '1';
      cmd_i   <= idx;
      cmd_a   <= arg;
      cmd_n   <= n;
      cmd_blk <= b;
      ret_c   <= nxt;
      st      <= C_GO;
    end procedure;

    procedure xfer(b : byte; nxt : st_t) is
    begin
      xb    <= b;
      ret_x <= nxt;
      st    <= X_GO;
    end procedure;

    variable p : nat4;
    variable c_size : unsigned(21 downto 0);
    variable sh : natural range 0 to 31;
    variable v : unsigned(39 downto 0);
    variable nx : st_t;

  begin
    if rising_edge(clk50) then
      spi_go   <= '0';
      f_we     <= '0';
      ucmd_ack <= '0';

      case st is

        when S_BOOT =>
          if tmr < 100 * US then  -- let the pins settle
            tmr <= tmr + 1;
          else
            tmr <= 0;
            seq_pin <= '1';
            say(CR & LF & "QMTECH K325T microSD probe (FPGA-DUT-Manager 0057), J11 weak " & PNAME & " build", S_HELP);
          end if;

        when S_HELP =>
          say("commands: p = pin test, j = J11 SD probe (24 assignments), d = DB slot J9 probe, a = all", S_DISPATCH);

        when S_DISPATCH =>
          if seq_pin = '1' then
            st <= T_START;
          elsif seq_j = '1' then
            st <= J_START;
          elsif seq_d = '1' then
            st <= D_START;
          else
            st <= S_PROMPT;
          end if;

        when S_PROMPT =>
          say("== done; command (p/j/d/a)?", S_IDLE);

        when S_IDLE =>
          if ucmd_v = '1' then
            ucmd_ack <= '1';
            case ucmd is
              when x"70" | x"50" => seq_pin <= '1'; st <= S_DISPATCH;                          -- p
              when x"6A" | x"4A" => seq_j <= '1'; st <= S_DISPATCH;                            -- j
              when x"64" | x"44" => seq_d <= '1'; st <= S_DISPATCH;                            -- d
              when x"61" | x"41" => seq_pin <= '1'; seq_j <= '1'; seq_d <= '1'; st <= S_DISPATCH; -- a
              when x"0D" | x"0A" => null;
              when others => st <= S_HELP;
            end case;
          elsif sw1_s(2) = '0' then
            seq_pin <= '1'; seq_j <= '1'; seq_d <= '1'; st <= S_DISPATCH;
          end if;

        when S_PR =>
          if pi > plen then
            st <= ret_p;
          elsif f_full = '0' then
            f_we <= '1';
            f_wd <= pbuf(pi);
            pi <= pi + 1;
          end if;

        -----------------------------------------------------------------------
        -- pin test
        -----------------------------------------------------------------------
        when T_START =>
          act <= '0';
          test_oe <= (others => '0');
          idle_j11 <= j11_s;
          tied <= '0';
          say("J11 idle (weak " & PNAME & "): 1:" & bit_c(j11_s(0)) & " 2:" & bit_c(j11_s(1)) &
              " 3:" & bit_c(j11_s(2)) & " 4:" & bit_c(j11_s(3)) & "   7:" & bit_c(j11b_s(0)) &
              " 8:" & bit_c(j11b_s(1)) & " 9:" & bit_c(j11b_s(2)) & " 10:" & bit_c(j11b_s(3)), T_DB);

        when T_DB =>
          pt_i <= 0;
          pt_ph <= 0;
          say("J9 slot idle (4.7k pull-ups on DB): CD:" & bit_c(sd_s(6)) & " DAT0:" & bit_c(sd_s(5)) &
              " DAT1:" & bit_c(sd_s(4)) & " DAT2:" & bit_c(sd_s(3)) & " DAT3:" & bit_c(sd_s(2)) &
              " CMD:" & bit_c(sd_s(1)) & " CLK:" & bit_c(sd_s(0)), T_PIN);

        when T_PIN =>  -- start a drive phase (0 = low, 2 = high)
          test_oe <= (others => '0');
          test_oe(pt_i) <= '1';
          if pt_ph = 2 then test_o(pt_i) <= '1'; else test_o(pt_i) <= '0'; end if;
          tmr <= US;
          st <= T_DRV;

        when T_DRV =>
          if tmr /= 0 then
            tmr <= tmr - 1;
          else
            pt_r(3 - pt_ph) <= j11_s(pt_i);  -- read back while driving
            test_oe <= (others => '0');
            tmr <= 50 * US;
            pt_ph <= pt_ph + 1;
            st <= T_REL;
          end if;

        when T_REL =>
          if tmr /= 0 then
            tmr <= tmr - 1;
          else
            pt_r(3 - pt_ph) <= j11_s(pt_i);
            if pt_ph = 3 then
              st <= T_LINE;
            else
              pt_ph <= pt_ph + 1;
              st <= T_PIN;
            end if;
          end if;

        when T_LINE =>
          if pt_r(3) = '1' or pt_r(1) = '0' then
            tied <= '1';
          end if;
          if pt_i = 3 then
            nx := T_END;
          else
            pt_i <= pt_i + 1;
            pt_ph <= 0;
            nx := T_PIN;
          end if;
          say("J11-" & pin_c(pt_i) & " " & BALL(pt_i) & ": idle " & bit_c(idle_j11(pt_i)) &
              ", drive 0 reads " & bit_c(pt_r(3)) & ", released " & bit_c(pt_r(2)) &
              "; drive 1 reads " & bit_c(pt_r(1)) & ", released " & bit_c(pt_r(0)) &
              " => " & pin_class(pt_r(3), pt_r(2), pt_r(1), pt_r(0)), nx);

        when T_END =>
          seq_pin <= '0';
          if auto_sd = '1' then
            auto_sd <= '0';
            if tied = '0' then
              seq_j <= '1';
              seq_d <= '1';
              st <= S_DISPATCH;
            else
              say("a J11 pin looks tied to a rail: SD probes not started automatically (send j to force)", S_DISPATCH);
            end if;
          else
            st <= S_DISPATCH;
          end if;

        -----------------------------------------------------------------------
        -- SD probe loop
        -----------------------------------------------------------------------
        when J_START =>
          perm <= 0;
          j_stat <= 0;
          j_win <= 31;
          say("J11 SD probe: SPI mode, " & dec2(CLK_HZ / (2 * SPI_HALF) / 10000) &
              "0 kHz, CMD0 on 24 assignments of CS/DI/DO/CK to J11 pins 1-4", P_TRY);

        when D_START =>
          perm <= 24;
          d_stat <= 0;
          say("J9 slot SD probe: CD:" & bit_c(sd_s(6)) &
              " (pulled up; low usually means a card is inserted)", P_TRY);

        when P_TRY =>
          act <= '0';
          cs <= '1';
          answered <= '0';
          if perm = 24 then
            tgt_db <= '1';
          else
            tgt_db <= '0';
            p := PERMS(perm);
            r_cs <= p(0); r_di <= p(1); r_do <= p(2); r_ck <= p(3);
          end if;
          tmr <= GAP_US * US;
          st <= P_GAP;

        when P_GAP =>
          if tmr /= 0 then
            tmr <= tmr - 1;
          else
            act <= '1';
            tmr <= 10 * US;
            cnt <= 0;
            st <= P_PWR;
          end if;

        when P_PWR =>
          if tmr /= 0 then
            tmr <= tmr - 1;
          else
            xfer(x"FF", P_DUMMY);
          end if;

        when P_DUMMY =>  -- 10 bytes = 80 clocks with CS high
          if cnt = 9 then
            sd_cmd_call(0, x"00000000", 0, '0', P_CMD0R);
          else
            cnt <= cnt + 1;
            xfer(x"FF", P_DUMMY);
          end if;

        when P_CMD0R =>
          if r1 = x"01" then
            answered <= '1';
          end if;
          if perm = 24 then
            say("  J9 (CS=DAT3 DI=CMD DO=DAT0 CK=CLK): CMD0 R1=" & hx(r1), P_CHK);
          else
            say("  p" & dec2(perm) & " CS=" & pin_c(r_cs) & " DI=" & pin_c(r_di) & " DO=" & pin_c(r_do) &
                " CK=" & pin_c(r_ck) & ": CMD0 R1=" & hx(r1), P_CHK);
          end if;

        when P_CHK =>
          if answered = '1' then
            if perm = 24 then
              d_stat <= 2;
            else
              j_stat <= 2;
              if j_win = 31 then j_win <= perm; end if;
            end if;
            ret_i <= P_NEXT;
            st <= I_START;
          else
            st <= P_NEXT;
          end if;

        when P_NEXT =>
          act <= '0';
          cs <= '1';
          if perm = 24 then
            st <= D_DONE;
          elsif perm = 23 then
            st <= J_DONE;
          else
            perm <= perm + 1;
            st <= P_TRY;
          end if;

        when J_DONE =>
          seq_j <= '0';
          tgt_db <= '0';
          if j_win /= 31 then
            p := PERMS(j_win);
            say("J11 result: card answers at p" & dec2(j_win) & ": CS=J11-" & pin_c(p(0)) & " DI=J11-" &
                pin_c(p(1)) & " DO=J11-" & pin_c(p(2)) & " CK=J11-" & pin_c(p(3)), S_DISPATCH);
          else
            j_stat <= 3;
            say("J11 result: NO card answered CMD0 in any of the 24 assignments (no card, adapter " &
                "flipped/miswired or not powered)", S_DISPATCH);
          end if;

        when D_DONE =>
          seq_d <= '0';
          tgt_db <= '0';
          if d_stat = 2 then
            say("J9 result: card answered", S_DISPATCH);
          else
            d_stat <= 3;
            say("J9 result: no card answered (slot empty?)", S_DISPATCH);
          end if;

        -----------------------------------------------------------------------
        -- full card init
        -----------------------------------------------------------------------
        when I_START =>
          sd_cmd_call(8, x"000001AA", 4, '0', I_8R);

        when I_8R =>
          if r1 = x"01" and resp(11 downto 0) = x"1AA" then v2 <= '1'; else v2 <= '0'; end if;
          tries <= 0;
          say("    CMD8 R1=" & hx(r1) & " R7=" & hx(resp), I_41);

        when I_41 =>
          sd_cmd_call(55, x"00000000", 0, '0', I_41B);

        when I_41B =>
          if v2 = '1' then
            sd_cmd_call(41, x"40000000", 0, '0', I_41C);
          else
            sd_cmd_call(41, x"00000000", 0, '0', I_41C);
          end if;

        when I_41C =>
          if r1 = x"00" then
            say("    ACMD41 ready after " & hx(std_logic_vector(to_unsigned(tries + 1, 12))) & "h tries", I_58);
          elsif tries = ACMD41_MAX - 1 then
            say("    ACMD41 timeout, R1=" & hx(r1) & " (continuing)", I_58);
          else
            tries <= tries + 1;
            st <= I_41;
          end if;

        when I_58 =>
          sd_cmd_call(58, x"00000000", 4, '0', I_58R);

        when I_58R =>
          say("    CMD58 R1=" & hx(r1) & " OCR=" & hx(resp) & " CCS=" & bit_c(resp(30)) &
              " (1 = SDHC/SDXC)", I_9);

        when I_9 =>
          sd_cmd_call(9, x"00000000", 0, '1', I_9R);

        when I_9R =>
          csd <= blk;
          say("    CMD9 R1=" & hx(r1) & " token=" & bit_c(tok_ok) & " CSD=" & hx16(blk), I_10);

        when I_10 =>
          sd_cmd_call(10, x"00000000", 0, '1', I_10R);

        when I_10R =>
          cid <= blk;
          say("    CMD10 R1=" & hx(r1) & " token=" & bit_c(tok_ok) & " CID=" & hx16(blk), I_CID);

        when I_CID =>
          say("    CID: MID=0x" & hx(cid(0)) & " OID=" & pchr(cid(1)) & pchr(cid(2)) & " PNM=" &
              pchr(cid(3)) & pchr(cid(4)) & pchr(cid(5)) & pchr(cid(6)) & pchr(cid(7)) &
              " PRV=" & hx(cid(8)(7 downto 4)) & "." & hx(cid(8)(3 downto 0)) &
              " PSN=0x" & hx(cid(9)) & hx(cid(10)) & hx(cid(11)) & hx(cid(12)) &
              " MDT=20" & dec2(to_integer(unsigned(std_logic_vector'(cid(13)(3 downto 0) & cid(14)(7 downto 4))))) &
              "-" & dec2(to_integer(unsigned(cid(14)(3 downto 0)))), I_CAP);

        when I_CAP =>
          if csd(0)(7 downto 6) = "01" then  -- CSD 2.0: (C_SIZE + 1) * 512 KiB
            c_size := unsigned(std_logic_vector'(csd(7)(5 downto 0) & csd(8) & csd(9)));
            kib <= shift_left(resize(c_size, 32) + 1, 9);
            dd_bin <= resize(shift_right(resize(c_size, 32) + 1, 1), 32);  -- MiB
          else  -- CSD 1.0: (C_SIZE + 1) * 2^(C_SIZE_MULT + 2 + READ_BL_LEN) bytes
            c_size := resize(unsigned(std_logic_vector'(csd(6)(1 downto 0) & csd(7) & csd(8)(7 downto 6))), 22);
            sh := to_integer(unsigned(std_logic_vector'(csd(9)(1 downto 0) & csd(10)(7)))) + 2 +
                  to_integer(unsigned(csd(5)(3 downto 0)));
            if sh >= 20 then
              dd_bin <= shift_left(resize(c_size, 32) + 1, sh - 20);
            else
              dd_bin <= shift_right(resize(c_size, 32) + 1, 20 - sh);
            end if;
            if sh >= 10 then
              kib <= shift_left(resize(c_size, 32) + 1, sh - 10);
            else
              kib <= shift_right(resize(c_size, 32) + 1, 10 - sh);
            end if;
          end if;
          dd_bcd <= (others => '0');
          dd_n <= 0;
          st <= I_DD;

        when I_DD =>  -- double dabble, one bit per clock
          if dd_n = 32 then
            st <= I_CAPP;
          else
            v := dd_bcd;
            for d in 0 to 9 loop
              if v(d * 4 + 3 downto d * 4) >= 5 then
                v(d * 4 + 3 downto d * 4) := v(d * 4 + 3 downto d * 4) + 3;
              end if;
            end loop;
            dd_bcd <= v(38 downto 0) & dd_bin(31);
            dd_bin <= dd_bin(30 downto 0) & '0';
            dd_n <= dd_n + 1;
          end if;

        when I_CAPP =>
          say("    capacity " & bcd_str(dd_bcd) & " MiB (CSD v" & hx(std_logic_vector(unsigned(csd(0)(7 downto 6)) + 1)) &
              ", " & hx(std_logic_vector(kib)) & "h KiB)", I_END);

        when I_END =>
          cs <= '1';
          st <= ret_i;

        -----------------------------------------------------------------------
        -- command subroutine: one 0xFF, 6 frame bytes, R1 (<= 10 bytes),
        -- cmd_n more bytes, optionally a 16-byte data block, then CS high and
        -- 8 clocks
        -----------------------------------------------------------------------
        when C_GO =>
          cs <= '0';
          cbyte <= 0;
          r1 <= x"FF";
          resp <= (others => '0');
          tok_ok <= '0';
          xfer(x"FF", C_F);

        when C_F =>
          if cbyte = 6 then
            cnt <= 0;
            xfer(x"FF", C_R1);
          else
            cbyte <= cbyte + 1;
            frame <= frame(39 downto 0) & x"FF";
            xfer(frame(47 downto 40), C_F);
          end if;

        when C_R1 =>
          if rx(7) = '0' then
            r1 <= rx;
            cnt <= 0;
            st <= C_EX;
          elsif cnt = 9 then
            st <= C_END;
          else
            cnt <= cnt + 1;
            xfer(x"FF", C_R1);
          end if;

        when C_EX =>
          if cnt = cmd_n then
            if cmd_blk = '1' and r1 = x"00" then
              cnt <= 0;
              st <= C_TK;
            else
              st <= C_END;
            end if;
          else
            xfer(x"FF", C_EXR);
          end if;

        when C_EXR =>
          resp <= resp(23 downto 0) & rx;
          cnt <= cnt + 1;
          st <= C_EX;

        when C_TK =>
          xfer(x"FF", C_TKR);

        when C_TKR =>
          if rx = x"FE" then
            tok_ok <= '1';
            cbyte <= 0;
            st <= C_BK;
          elsif cnt = 4000 then
            st <= C_END;
          else
            cnt <= cnt + 1;
            st <= C_TK;
          end if;

        when C_BK =>
          if cbyte = 18 then
            st <= C_END;
          else
            xfer(x"FF", C_BKR);
          end if;

        when C_BKR =>
          if cbyte < 16 then
            blk(cbyte) <= rx;
          end if;
          cbyte <= cbyte + 1;
          st <= C_BK;

        when C_END =>
          cs <= '1';
          xfer(x"FF", ret_c);

        -----------------------------------------------------------------------
        when X_GO =>
          spi_txb <= xb;
          spi_go <= '1';
          st <= X_W;

        when X_W =>
          if spi_done = '1' then
            rx <= spi_rxb;
            st <= ret_x;
          end if;

      end case;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- text FIFO (block RAM) and UART
  ---------------------------------------------------------------------------
  f_full <= '1' when wr_p + 1 = rd_p else '0';

  process (clk50)
  begin
    if rising_edge(clk50) then
      if f_we = '1' then
        fifo(to_integer(wr_p)) <= f_wd;
        wr_p <= wr_p + 1;
      end if;
      f_rd <= fifo(to_integer(rd_p));
    end if;
  end process;

  process (clk50)
  begin
    if rising_edge(clk50) then
      -- transmitter: tx_ph 0 = idle, 1 = read issued, 2 = data valid
      if tx_bits /= 0 then
        if tx_cnt = 0 then
          tx_cnt   <= BIT_CLKS - 1;
          tx_shift <= '1' & tx_shift(9 downto 1);
          tx_bits  <= tx_bits - 1;
        else
          tx_cnt <= tx_cnt - 1;
        end if;
      else
        case tx_ph is
          when 0 =>
            if rd_p /= wr_p then tx_ph <= 1; end if;
          when 1 =>
            tx_ph <= 2;  -- f_rd now holds fifo(rd_p)
          when others =>
            tx_shift <= '1' & f_rd & '0';
            tx_bits  <= 10;
            tx_cnt   <= BIT_CLKS - 1;
            rd_p     <= rd_p + 1;
            tx_ph    <= 0;
        end case;
      end if;

      -- receiver (commands)
      rx_s <= rx_s(1 downto 0) & uart_rx;
      if ucmd_ack = '1' then ucmd_v <= '0'; end if;
      if rx_busy = '0' then
        if rx_s(2) = '0' then
          rx_busy <= '1';
          rx_cnt  <= BIT_CLKS + BIT_CLKS / 2 - 1;
          rx_bits <= 0;
        end if;
      elsif rx_cnt = 0 then
        rx_cnt <= BIT_CLKS - 1;
        if rx_bits = 8 then
          rx_busy <= '0';
          if rx_s(2) = '1' then
            ucmd <= rx_sr;
            ucmd_v <= '1';
          end if;
        else
          rx_sr   <= rx_s(2) & rx_sr(7 downto 1);
          rx_bits <= rx_bits + 1;
        end if;
      else
        rx_cnt <= rx_cnt - 1;
      end if;
      sw1_s <= sw1_s(1 downto 0) & sw1_n;
    end if;
  end process;
  uart_tx <= tx_shift(0) when tx_bits /= 0 else '1';

  ---------------------------------------------------------------------------
  -- 7-segment, LEDs
  ---------------------------------------------------------------------------
  process (clk50)
  begin
    if rising_edge(clk50) then
      if hb_cnt = CLK_HZ / 2 - 1 then
        hb_cnt <= 0;
        hb <= not hb;
        if page = 2 then
          page <= 0;
          show_db <= not show_db;
        else
          page <= page + 1;
        end if;
      else
        hb_cnt <= hb_cnt + 1;
      end if;

      if show_db = '0' then
        case j_stat is
          when 2 =>
            disp(0) <= '0' & SG_P;
            disp(1) <= '0' & seg7(j_win / 10);
            disp(2) <= '0' & seg7(j_win mod 10);
          when 3 =>
            disp(0) <= '0' & SG_N; disp(1) <= '0' & SG_O; disp(2) <= '0' & SG_C;
          when others =>
            disp <= (others => '0' & SG_DASH);
        end case;
      else
        disp(0) <= '1' & SG_D;
        case d_stat is
          when 2 => disp(1) <= '0' & SG_C; disp(2) <= '0' & seg7(1);
          when 3 => disp(1) <= '0' & SG_C; disp(2) <= '0' & seg7(0);
          when others => disp(1) <= '0' & SG_DASH; disp(2) <= '0' & SG_DASH;
        end case;
      end if;

      if mux_cnt = CLK_HZ / MUX_HZ - 1 then
        mux_cnt <= 0;
        if mux_sel = 2 then mux_sel <= 0; else mux_sel <= mux_sel + 1; end if;
      else
        mux_cnt <= mux_cnt + 1;
      end if;
      seg_n <= not disp(mux_sel);
      dig <= (others => '0');
      if mux_cnt > 64 and mux_cnt < CLK_HZ / MUX_HZ - 64 then
        dig(mux_sel) <= '1';
      end if;
    end if;
  end process;

  j_win_u <= to_unsigned(j_win, 5);
  g_led : for i in 0 to 4 generate  -- D5 = bit 0
    db_led_n(i) <= '0' when j_win /= 31 and j_win_u(4 - i) = '1' else '1';
  end generate;
  core_led_n(0) <= not hb;
  core_led_n(1) <= sd_s(6);  -- lit while CD reads low

end architecture;
