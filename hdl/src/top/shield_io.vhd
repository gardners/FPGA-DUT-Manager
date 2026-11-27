-- shield_io: the shield's slow lines over its I2C bus (issue 0049 step 2,
-- docs/hardware/shield-pinplan.md "I2C expanders"). A fixed sequencer
-- driving i2c_master, no soft CPU.
--
-- Expander A, TCA6424A @0x22: P0 revision straps, P1 feature straps (in),
-- P2 PWR_CTL0..7 (out, 1x11 power header, CTRL n = power-board output n).
-- Expander B, TCA6416A @0x20: P0.0-2 HDMI1..3 HPD_EN (out), P0.3 PK_JTAGEN
-- (out), P0.4-6 HDMI1..3 +5V sense, P0.7 power board PRESENT, P1.0-3 VIO
-- sense DUT0..3, P1.4-7 keyboard 3V3 sense DUT0..3 (in).
--
-- Boot: after BOOT_US, PROBE runs a bus recovery and reads A's input ports 0/1 (revision,
-- features). No ACK: present = '0', probe_done = '1' (the top level keeps
-- the bodge-harness behaviour) and the probe is retried every RETRY_MS.
-- On success: ADOPT reads A's configuration and output port 2. If port 2 is
-- already configured as outputs (0x00) the FPGA was reconfigured with the
-- shield powered, and the DUT power state it finds there is kept
-- (pwr_adopted) until the host sets one (pwr_set); a fresh power-up shows
-- 0xFF (inputs) and starts with all CTRL off. Then AINIT writes A's output
-- port 2 before its configuration (P0/P1 in, P2 out; output registers
-- power up 0xFF, so the order matters) and polarity, BINIT the same for B.
--
-- Every POLL_US: POLLB reads B's inputs and writes its output port 0;
-- POLLA writes A's output port 2. sense_valid = '1' only after a
-- successful POLLB and drops on the first failed one (the DUT-facing
-- gating then treats the DUTs as unpowered). AINIT/BINIT are repeated
-- every REINIT polls and after a failure (expander reset or brown-out),
-- in the same poll slot before the poll.
--
-- Hook for more devices on the bus (fan controller, temperature sensor,
-- issue 0052): one single-register access per poll slot through ext_*:
-- ext_req (level, held until ext_done) with ext_rd = '0' writes ext_wdata
-- to register ext_reg of 7-bit address ext_addr, ext_rd = '1' reads it
-- into ext_rdata. ext_nack reports a missing ACK or a bus error.
--
-- Failed transactions (NACK, stretch timeout, bus stuck) count in errors
-- (saturating); a bus error is followed by a 9-clock recovery.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shield_io is
  generic (
    CLK_HZ   : positive := 125_000_000;
    SCL_HZ   : positive := 400_000;
    BOOT_US  : positive := 2_000;      -- after reset, before the first probe
    POLL_US  : positive := 1_000;
    RETRY_MS : positive := 1_000;      -- probe retry while no shield answers (<= 1000)
    REINIT   : positive := 256         -- polls between configuration refreshes
  );
  port (
    clk, rst       : in  std_logic;
    -- wanted outputs
    hpd_want       : in  std_logic_vector(2 downto 0);   -- HDMI1..3 EDID ready
    pk_jtagen_want : in  std_logic;
    pwr_ctl        : in  std_logic_vector(7 downto 0);   -- host power state (key 0x0062)
    pwr_set        : in  std_logic;                      -- host has set pwr_ctl
    -- extra single-register accesses (issue 0052 hook)
    ext_req        : in  std_logic := '0';
    ext_rd         : in  std_logic := '0';
    ext_addr       : in  std_logic_vector(6 downto 0) := (others => '0');
    ext_reg        : in  std_logic_vector(7 downto 0) := (others => '0');
    ext_wdata      : in  std_logic_vector(7 downto 0) := (others => '0');
    ext_done       : out std_logic;
    ext_nack       : out std_logic;
    ext_rdata      : out std_logic_vector(7 downto 0);
    -- status
    probe_done     : out std_logic;                      -- first probe finished
    present        : out std_logic;                      -- expander A answered
    sense_valid    : out std_logic;                      -- last poll of B succeeded
    revision       : out std_logic_vector(7 downto 0);
    features       : out std_logic_vector(7 downto 0);
    vio_sense      : out std_logic_vector(3 downto 0);   -- DUT0..3
    kb_sense       : out std_logic_vector(3 downto 0);   -- DUT0..3
    hdmi_5v        : out std_logic_vector(2 downto 0);   -- HDMI1..3
    pwrb_present   : out std_logic;
    hpd_out        : out std_logic_vector(2 downto 0);   -- as written to B
    jtagen_out     : out std_logic;
    pwr_out        : out std_logic_vector(7 downto 0);   -- CTRL as written to A
    pwr_adopted    : out std_logic;
    errors         : out unsigned(15 downto 0);
    -- bus (open drain: '1' = pull low)
    scl_in, sda_in : in  std_logic;
    scl_low, sda_low : out std_logic
  );
end entity;

architecture rtl of shield_io is
  constant C_START   : std_logic_vector(2 downto 0) := "001";
  constant C_STOP    : std_logic_vector(2 downto 0) := "010";
  constant C_WRITE   : std_logic_vector(2 downto 0) := "011";
  constant C_READ    : std_logic_vector(2 downto 0) := "100";
  constant C_RECOVER : std_logic_vector(2 downto 0) := "101";

  -- micro-ops
  type op_t is (O_END, O_REC, O_START, O_STOP, O_WR, O_RD_ACK, O_RD_NACK);
  -- write sources / read destinations
  type arg_t is (A_CONST, A_PWR, A_BOUT, A_EXT_AW, A_EXT_AR, A_EXT_REG, A_EXT_WD,
                 A_REV, A_FEAT, A_BIN0, A_BIN1, A_ACFG2, A_AOUT2, A_EXT);
  type uop_t is record
    op  : op_t;
    arg : arg_t;
    b   : std_logic_vector(7 downto 0);
  end record;
  type prog_t is array (natural range <>) of uop_t;
  constant AW : std_logic_vector(7 downto 0) := x"44";   -- A (0x22) write
  constant AR : std_logic_vector(7 downto 0) := x"45";
  constant BW : std_logic_vector(7 downto 0) := x"40";   -- B (0x20) write
  constant BR : std_logic_vector(7 downto 0) := x"41";
  constant X  : std_logic_vector(7 downto 0) := x"00";
  function s return uop_t is begin return (O_START, A_CONST, X); end function;
  function p return uop_t is begin return (O_STOP, A_CONST, X); end function;
  function rc return uop_t is begin return (O_REC, A_CONST, X); end function;
  function e return uop_t is begin return (O_END, A_CONST, X); end function;
  function w(v : std_logic_vector(7 downto 0)) return uop_t is begin return (O_WR, A_CONST, v); end function;
  function ws(a : arg_t) return uop_t is begin return (O_WR, a, X); end function;
  function ra(a : arg_t) return uop_t is begin return (O_RD_ACK, a, X); end function;
  function rn(a : arg_t) return uop_t is begin return (O_RD_NACK, a, X); end function;

  -- programs (TCA6424A command: b7 AI; TCA6416A: pointer toggles in a pair)
  constant P_PROBE : natural := 0;
  constant P_ADOPT : natural := 10;
  constant P_AINIT : natural := 24;
  constant P_BINIT : natural := 44;
  constant P_POLLB : natural := 63;
  constant P_POLLA : natural := 77;
  constant P_EXTW  : natural := 83;
  constant P_EXTR  : natural := 89;
  constant PROG : prog_t := (
    -- 0 PROBE: bus recovery (a slave may still hold SDA from before an
    -- FPGA reconfiguration), then A input ports 0, 1 (AI) -> revision, features
    rc, s, w(AW), w(x"80"), s, w(AR), ra(A_REV), rn(A_FEAT), p, e,
    -- 10 ADOPT: A configuration port 2, output port 2 (AI off)
    s, w(AW), w(x"0E"), s, w(AR), rn(A_ACFG2),
    s, w(AW), w(x"06"), s, w(AR), rn(A_AOUT2), p, e,
    -- 24 AINIT: output port 2 first, then configuration 0..2, polarity 0..2
    s, w(AW), w(x"06"), ws(A_PWR), p,
    s, w(AW), w(x"8C"), w(x"FF"), w(x"FF"), w(x"00"), p,
    s, w(AW), w(x"88"), w(X), w(X), w(X), p, e,
    -- 44 BINIT: output ports 0/1, configuration 0/1 (P0.0-3 out), polarity
    s, w(BW), w(x"02"), ws(A_BOUT), w(X), p,
    s, w(BW), w(x"06"), w(x"F0"), w(x"FF"), p,
    s, w(BW), w(x"04"), w(X), w(X), p, e,
    -- 63 POLLB: inputs 0, 1, then output port 0
    s, w(BW), w(x"00"), s, w(BR), ra(A_BIN0), rn(A_BIN1), p,
    s, w(BW), w(x"02"), ws(A_BOUT), p, e,
    -- 77 POLLA: output port 2
    s, w(AW), w(x"06"), ws(A_PWR), p, e,
    -- 83 EXTW: one register write
    s, ws(A_EXT_AW), ws(A_EXT_REG), ws(A_EXT_WD), p, e,
    -- 89 EXTR: one register read
    s, ws(A_EXT_AW), ws(A_EXT_REG), s, ws(A_EXT_AR), rn(A_EXT), p, e);

  -- manager
  type mst_t is (M_BOOT, M_PROBE, M_ADOPT, M_AINIT, M_BINIT, M_WAIT, M_POLLB, M_POLLA,
                 M_EXT, M_RETRY);
  signal mst : mst_t := M_BOOT;
  -- sequencer
  type qst_t is (Q_IDLE, Q_RUN, Q_ISSUE, Q_WAIT, Q_ABORT, Q_ABORT_W);
  signal qst : qst_t := Q_IDLE;
  signal pc : natural range 0 to PROG'length - 1 := 0;
  signal q_go, q_fin, q_ok : std_logic := '0';
  signal q_start : natural range 0 to PROG'length - 1 := 0;
  signal q_fail : std_logic := '0';

  signal m_valid, m_ready, m_done, m_nack, m_err, m_rdnack : std_logic;
  signal m_cmd : std_logic_vector(2 downto 0) := "000";
  signal m_wdata, m_rdata : std_logic_vector(7 downto 0) := x"00";
  signal cur : uop_t;

  -- registers
  signal rev_r, feat_r, bin0_r, bin1_r, acfg2_r, aout2_r, ext_r : std_logic_vector(7 downto 0) := x"00";
  signal pwr_adopt : std_logic_vector(7 downto 0) := x"00";
  signal adopted, present_r, done_r, valid_r : std_logic := '0';
  signal pwr_eff, bout : std_logic_vector(7 downto 0);
  signal hpd_eff : std_logic_vector(2 downto 0);
  signal err_cnt : unsigned(15 downto 0) := (others => '0');
  signal need_a, need_b : std_logic := '1';
  signal polls : natural range 0 to REINIT - 1 := 0;
  signal ext_done_r, ext_nack_r : std_logic := '0';

  -- timing: 1 us tick, us / ms counters
  constant US_DIV : positive := CLK_HZ / 1_000_000;
  signal us_div_c : natural range 0 to US_DIV - 1 := 0;
  signal us_tick : std_logic := '0';
  signal us_cnt : natural range 0 to 1_000_000 := 0;
  constant RETRY_US : positive := RETRY_MS * 1000;
begin
  -- program table consistency (elaboration-time check in simulation)
  assert PROG(P_ADOPT - 1).op = O_END and PROG(P_AINIT - 1).op = O_END and
         PROG(P_BINIT - 1).op = O_END and PROG(P_POLLB - 1).op = O_END and
         PROG(P_POLLA - 1).op = O_END and PROG(P_EXTW - 1).op = O_END and
         PROG(P_EXTR - 1).op = O_END and PROG(PROG'high).op = O_END and
         PROG(P_PROBE).op = O_REC and PROG(P_EXTR).op = O_START
    report "shield_io: program offsets wrong" severity failure;

  mst_i : entity work.i2c_master
    generic map (CLK_HZ => CLK_HZ, SCL_HZ => SCL_HZ, STRETCH_MAX => CLK_HZ / 1000)
    port map (clk => clk, rst => rst, cmd_valid => m_valid, cmd => m_cmd, wdata => m_wdata,
              rd_nack => m_rdnack, ready => m_ready, done => m_done, rdata => m_rdata,
              nack => m_nack, err => m_err, scl_in => scl_in, sda_in => sda_in,
              scl_low => scl_low, sda_low => sda_low);

  pwr_eff <= pwr_ctl when pwr_set = '1' else pwr_adopt;
  -- HPD only for receivers whose capture the shield says is fitted
  -- (feature b0 HDMI1, b2 HDMI2, b3 HDMI3)
  hpd_eff <= hpd_want and (feat_r(3) & feat_r(2) & feat_r(0));
  bout <= "0000" & pk_jtagen_want & hpd_eff;
  cur <= PROG(pc);

  probe_done   <= done_r;
  present      <= present_r;
  sense_valid  <= valid_r;
  revision     <= rev_r;
  features     <= feat_r;
  vio_sense    <= bin1_r(3 downto 0);
  kb_sense     <= bin1_r(7 downto 4);
  hdmi_5v      <= bin0_r(6 downto 4);
  pwrb_present <= bin0_r(7);
  pwr_adopted  <= adopted and not pwr_set;
  errors       <= err_cnt;
  ext_done     <= ext_done_r;
  ext_nack     <= ext_nack_r;
  ext_rdata    <= ext_r;

  -- 1 us tick
  process (clk)
  begin
    if rising_edge(clk) then
      us_tick <= '0';
      if us_div_c = US_DIV - 1 then
        us_div_c <= 0; us_tick <= '1';
      else
        us_div_c <= us_div_c + 1;
      end if;
    end if;
  end process;

  -- sequencer: runs PROG from q_start to O_END; q_ok = no NACK / error
  process (clk)
    variable v : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      q_fin <= '0'; m_valid <= '0';
      if rst = '1' then
        qst <= Q_IDLE;
      else
        case qst is
          when Q_IDLE =>
            if q_go = '1' then pc <= q_start; q_fail <= '0'; qst <= Q_RUN; end if;
          when Q_RUN =>
            case cur.op is
              when O_END =>
                q_ok <= not q_fail; q_fin <= '1'; qst <= Q_IDLE;
              when O_REC   => m_cmd <= C_RECOVER; qst <= Q_ISSUE;
              when O_START => m_cmd <= C_START; qst <= Q_ISSUE;
              when O_STOP  => m_cmd <= C_STOP;  qst <= Q_ISSUE;
              when O_WR =>
                case cur.arg is
                  when A_PWR     => v := pwr_eff;
                  when A_BOUT    => v := bout;
                  when A_EXT_AW  => v := ext_addr & '0';
                  when A_EXT_AR  => v := ext_addr & '1';
                  when A_EXT_REG => v := ext_reg;
                  when A_EXT_WD  => v := ext_wdata;
                  when others    => v := cur.b;
                end case;
                m_cmd <= C_WRITE; m_wdata <= v; qst <= Q_ISSUE;
              when O_RD_ACK  => m_cmd <= C_READ; m_rdnack <= '0'; qst <= Q_ISSUE;
              when O_RD_NACK => m_cmd <= C_READ; m_rdnack <= '1'; qst <= Q_ISSUE;
            end case;
          when Q_ISSUE =>
            if m_ready = '1' then m_valid <= '1'; qst <= Q_WAIT; end if;
          when Q_WAIT =>
            if m_done = '1' then
              if m_err = '1' then
                q_fail <= '1'; m_cmd <= C_RECOVER; qst <= Q_ABORT;
              elsif m_nack = '1' then
                q_fail <= '1'; m_cmd <= C_STOP; qst <= Q_ABORT;
              else
                if cur.op = O_RD_ACK or cur.op = O_RD_NACK then
                  case cur.arg is
                    when A_REV   => rev_r <= m_rdata;
                    when A_FEAT  => feat_r <= m_rdata;
                    when A_BIN0  => bin0_r <= m_rdata;
                    when A_BIN1  => bin1_r <= m_rdata;
                    when A_ACFG2 => acfg2_r <= m_rdata;
                    when A_AOUT2 => aout2_r <= m_rdata;
                    when A_EXT   => ext_r <= m_rdata;
                    when others  => null;
                  end case;
                end if;
                pc <= pc + 1; qst <= Q_RUN;
              end if;
            end if;
          when Q_ABORT =>
            if m_ready = '1' then m_valid <= '1'; qst <= Q_ABORT_W; end if;
          when Q_ABORT_W =>
            if m_done = '1' then q_ok <= '0'; q_fin <= '1'; qst <= Q_IDLE; end if;
        end case;
      end if;
    end if;
  end process;

  -- manager
  process (clk)
    procedure run(start : natural; nxt : mst_t) is
    begin
      q_start <= start; q_go <= '1'; mst <= nxt;
    end procedure;
    procedure count_err is
    begin
      if err_cnt /= x"FFFF" then err_cnt <= err_cnt + 1; end if;
    end procedure;
    -- end of a poll slot: one ext access if requested, else wait
    procedure slot_end is
    begin
      if ext_req = '1' and ext_rd = '0' then
        run(P_EXTW, M_EXT);
      elsif ext_req = '1' then
        run(P_EXTR, M_EXT);
      else
        mst <= M_WAIT;
      end if;
    end procedure;
  begin
    if rising_edge(clk) then
      q_go <= '0'; ext_done_r <= '0';
      if us_tick = '1' and us_cnt < 1_000_000 then us_cnt <= us_cnt + 1; end if;
      if rst = '1' then
        mst <= M_BOOT; us_cnt <= 0; done_r <= '0'; present_r <= '0'; valid_r <= '0';
        need_a <= '1'; need_b <= '1'; adopted <= '0'; pwr_adopt <= x"00"; polls <= 0;
      elsif q_go = '0' then
        case mst is
          when M_BOOT =>
            if us_cnt >= BOOT_US then run(P_PROBE, M_PROBE); end if;
          when M_RETRY =>
            if us_cnt >= RETRY_US then run(P_PROBE, M_PROBE); end if;
          when M_PROBE =>
            if q_fin = '1' then
              if q_ok = '1' then
                run(P_ADOPT, M_ADOPT);
              else
                done_r <= '1'; us_cnt <= 0; mst <= M_RETRY;
              end if;
            end if;
          when M_ADOPT =>
            if q_fin = '1' then
              if q_ok = '1' then
                -- port 2 already outputs: keep the power state found there
                if acfg2_r = x"00" then
                  pwr_adopt <= aout2_r; adopted <= '1';
                end if;
                present_r <= '1'; done_r <= '1';
                run(P_AINIT, M_AINIT);
              else
                done_r <= '1'; us_cnt <= 0; mst <= M_RETRY;
              end if;
            end if;
          when M_AINIT =>
            if q_fin = '1' then
              need_a <= not q_ok;
              if q_ok = '0' then count_err; end if;
              if need_b = '1' then run(P_BINIT, M_BINIT); else slot_end; end if;
            end if;
          when M_BINIT =>
            if q_fin = '1' then
              need_b <= not q_ok;
              if q_ok = '1' then
                run(P_POLLB, M_POLLB);          -- the slot's poll follows
              else
                count_err; valid_r <= '0'; mst <= M_WAIT;
              end if;
            end if;
          when M_WAIT =>
            if us_cnt >= POLL_US then
              us_cnt <= 0;
              if polls = REINIT - 1 then
                polls <= 0; need_a <= '1';
                run(P_BINIT, M_BINIT);          -- configuration refresh
              else
                polls <= polls + 1;
                if need_b = '1' then run(P_BINIT, M_BINIT); else run(P_POLLB, M_POLLB); end if;
              end if;
            end if;
          when M_POLLB =>
            if q_fin = '1' then
              valid_r <= q_ok;
              if q_ok = '0' then count_err; need_b <= '1'; end if;
              if need_a = '1' then run(P_AINIT, M_AINIT); else run(P_POLLA, M_POLLA); end if;
            end if;
          when M_POLLA =>
            if q_fin = '1' then
              if q_ok = '0' then count_err; need_a <= '1'; end if;
              slot_end;
            end if;
          when M_EXT =>
            if q_fin = '1' then
              ext_nack_r <= not q_ok; ext_done_r <= '1'; mst <= M_WAIT;
            end if;
        end case;
      end if;
    end if;
  end process;

  -- what the outputs are (last written values follow the wanted ones
  -- within one poll; reported as wanted while the shield answers)
  hpd_out    <= hpd_eff when present_r = '1' else "000";
  jtagen_out <= pk_jtagen_want when present_r = '1' else '0';
  pwr_out    <= pwr_eff when present_r = '1' else x"00";
end architecture;
