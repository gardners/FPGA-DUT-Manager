-- tb_shield_io: shield I2C sequencer (issue 0049 step 2) against a
-- TCA6424A model (expander A @0x22), a TCA6416A model (expander B @0x20;
-- i2c_expander_model, whose PCA9555 register map and pair-toggling pointer
-- are the TCA6416A's, SCPS194F 8.6) and a spare TCA6416A @0x21 standing in
-- for a future device behind the ext_* hook (issue 0052).
-- Checks: no shield -> present 0 and probe retries; revision/features;
-- A's port 2 configured as outputs without a glitch (output register
-- written first); 1 ms polling of B (sense in, HPD/JTAGEN out, feature
-- gating of HPD); host power state to CTRL; B unplugged -> sense invalid,
-- recovered on re-plug; FPGA "reconfiguration" (reset) keeps the power
-- state found in A; ext register write/read and NACK.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_shield_io is
end entity;

architecture tb of tb_shield_io is
  signal clk : std_logic := '0';
  signal fin : boolean := false;
  signal rst : std_logic := '0';
  signal scl, sda : std_logic;
  signal scl_low, sda_low : std_logic;
  signal hpd_want : std_logic_vector(2 downto 0) := "000";
  signal jt_want, pwr_set : std_logic := '0';
  signal pwr_ctl : std_logic_vector(7 downto 0) := x"00";
  signal ext_req, ext_rd, ext_done, ext_nack : std_logic := '0';
  signal ext_addr : std_logic_vector(6 downto 0) := "0100001";
  signal ext_reg, ext_wdata, ext_rdata : std_logic_vector(7 downto 0) := x"00";
  signal probe_done, present, valid, pwrb, jt_out, adopted : std_logic;
  signal rev, feat, pwr_out : std_logic_vector(7 downto 0);
  signal vio, kbs : std_logic_vector(3 downto 0);
  signal h5v, hpd_out : std_logic_vector(2 downto 0);
  signal errs : unsigned(15 downto 0);
  -- models
  signal a_conn, b_conn : std_logic := '0';
  signal a_pins, a_pout, a_outr, a_cfgr : std_logic_vector(23 downto 0);
  signal a_wr, a_rd, a_err : natural;
  signal b_pins, b_outr, b_cfgr : std_logic_vector(15 downto 0) := x"0000";
  signal b_cw, b_ow, b_rd, b_err : natural;
  signal c_pins, c_outr, c_cfgr : std_logic_vector(15 downto 0) := x"BEEF";
  signal c_cw, c_ow, c_rd, c_err : natural;
  signal a_rev, a_feat : std_logic_vector(7 downto 0) := x"00";
  signal ctrl_glitch : boolean := false;
  signal watch_ctrl : boolean := true;
begin
  clk <= not clk after 4 ns when not fin;
  scl <= 'H'; sda <= 'H';
  scl <= '0' when scl_low = '1' else 'Z';
  sda <= '0' when sda_low = '1' else 'Z';

  dut : entity work.shield_io
    generic map (CLK_HZ => 125_000_000, SCL_HZ => 400_000, BOOT_US => 100, POLL_US => 1000,
                 RETRY_MS => 1, REINIT => 4)
    port map (clk => clk, rst => rst, hpd_want => hpd_want, pk_jtagen_want => jt_want,
              pwr_ctl => pwr_ctl, pwr_set => pwr_set,
              ext_req => ext_req, ext_rd => ext_rd, ext_addr => ext_addr, ext_reg => ext_reg,
              ext_wdata => ext_wdata, ext_done => ext_done, ext_nack => ext_nack,
              ext_rdata => ext_rdata,
              probe_done => probe_done, present => present, sense_valid => valid,
              revision => rev, features => feat, vio_sense => vio, kb_sense => kbs,
              hdmi_5v => h5v, pwrb_present => pwrb, hpd_out => hpd_out, jtagen_out => jt_out,
              pwr_out => pwr_out, pwr_adopted => adopted, errors => errs,
              scl_in => scl, sda_in => sda, scl_low => scl_low, sda_low => sda_low);

  -- A: P0 revision straps, P1 feature straps; P2 (outputs) pulled down
  a_pins <= x"00" & a_feat & a_rev;
  ea : entity work.tca6424a_model generic map (ADDR => "0100010")
    port map (sda => sda, scl => scl, connected => a_conn, pins => a_pins, pins_out => a_pout,
              out_regs => a_outr, cfg_regs => a_cfgr, writes => a_wr, reads => a_rd, errors => a_err);
  eb : entity work.i2c_expander_model generic map (ADDR => "0100000")
    port map (sda => sda, scl => scl, connected => b_conn, pins => b_pins, out_regs => b_outr,
              cfg_regs => b_cfgr, cfg_writes => b_cw, out_writes => b_ow, reads => b_rd, errors => b_err);
  ec : entity work.i2c_expander_model generic map (ADDR => "0100001")
    port map (sda => sda, scl => scl, pins => c_pins, out_regs => c_outr,
              cfg_regs => c_cfgr, cfg_writes => c_cw, out_writes => c_ow, reads => c_rd, errors => c_err);

  -- the power CTRL pins must never be driven high before the host asked
  process (a_pout)
  begin
    if watch_ctrl and pwr_set = '0' then
      for i in 16 to 23 loop
        if a_pout(i) = '1' then ctrl_glitch <= true; end if;
      end loop;
    end if;
  end process;

  process
    variable n0 : natural;
    procedure wait_us(n : natural) is begin wait for n * 1 us; end procedure;
    procedure ext(rd : std_logic; reg, d : std_logic_vector(7 downto 0)) is
    begin
      ext_rd <= rd; ext_reg <= reg; ext_wdata <= d; ext_req <= '1';
      wait until rising_edge(clk) and ext_done = '1';
      ext_req <= '0';
      wait until rising_edge(clk);
    end procedure;
  begin
    -- 1. no shield
    wait_us(500);
    assert probe_done = '1' and present = '0' and valid = '0'
      report "no shield: probe_done/present/valid wrong" severity failure;
    assert to_x01(scl) = '1' and to_x01(sda) = '1' report "bus not idle" severity failure;

    -- 2. shield appears (probe retried every 1 ms): rev 0x01, HDMI1 + HDMI3
    -- fitted (feature b0, b3), power header (b1)
    a_rev <= x"01"; a_feat <= x"0B";
    b_pins <= "0011" & "0101" & "1101" & "0000";   -- P1: kb 0011, vio 0101; P0: pres, 5V 101
    a_conn <= '1'; b_conn <= '1';
    wait_us(1500);
    assert present = '1' and rev = x"01" and feat = x"0B" report "revision/features wrong" severity failure;
    assert a_cfgr = x"00FFFF" report "A configuration " & to_hstring(a_cfgr) severity failure;
    assert a_outr(23 downto 16) = x"00" report "A CTRL output register not cleared" severity failure;
    assert adopted = '0' report "fresh power-up must not adopt" severity failure;
    wait_us(2500);
    assert b_cfgr = x"FFF0" report "B configuration " & to_hstring(b_cfgr) severity failure;
    assert valid = '1' and vio = "0101" and kbs = "0011" and h5v = "101" and pwrb = '1'
      report "sense bits wrong" severity failure;

    -- 3. HPD (gated by fitted features) and PK_JTAGEN
    hpd_want <= "111"; jt_want <= '1';
    wait_us(2500);
    assert b_outr(7 downto 0) = x"0D" report "B out0 " & to_hstring(b_outr(7 downto 0)) severity failure;
    assert hpd_out = "101" and jt_out = '1' report "hpd_out/jtagen_out wrong" severity failure;
    jt_want <= '0';
    wait_us(2500);
    assert b_outr(7 downto 0) = x"05" report "JTAGEN not cleared" severity failure;

    -- 4. sense changes within ~1 ms; poll rate
    n0 := b_rd;
    b_pins(11 downto 8) <= "1111";
    wait_us(1300);
    assert vio = "1111" report "VIO change not seen" severity failure;
    wait_us(8700);
    assert b_rd - n0 >= 9 and b_rd - n0 <= 11
      report "B polled " & integer'image(b_rd - n0) & " times in 10 ms" severity failure;

    -- 5. host power state
    pwr_ctl <= x"A5"; pwr_set <= '1';
    wait_us(2500);
    assert a_outr(23 downto 16) = x"A5" and a_pout(23 downto 16) = x"A5" and pwr_out = x"A5"
      report "CTRL not driven" severity failure;

    -- 6. B unplugged: sense invalid, errors counted; re-plugged: recovers
    n0 := to_integer(errs);
    b_conn <= '0';
    wait_us(2500);
    assert valid = '0' report "sense still valid with B unplugged" severity failure;
    assert to_integer(errs) > n0 report "errors not counted" severity failure;
    b_conn <= '1';
    wait_us(3500);
    assert valid = '1' and vio = "1111" report "B not recovered" severity failure;

    -- 7. FPGA reconfiguration with the shield powered: the CTRL state in
    -- A is kept (no glitch to 0, adopted until the host sets it)
    pwr_set <= '0';
    watch_ctrl <= false;
    -- (between transactions; a reset mid-byte is the recovery's job)
    loop
      wait for 1 us;
      exit when scl'last_event > 20 us and to_x01(scl) = '1' and to_x01(sda) = '1';
    end loop;
    rst <= '1'; wait_us(1); rst <= '0';
    wait_us(1000);
    assert present = '1' and adopted = '1' and pwr_out = x"A5"
      report "power state not adopted" severity failure;
    assert a_outr(23 downto 16) = x"A5" and a_pout(23 downto 16) = x"A5"
      report "CTRL lost on reconfiguration" severity failure;
    pwr_ctl <= x"03"; pwr_set <= '1';
    wait_us(2500);
    assert adopted = '0' and a_pout(23 downto 16) = x"03" report "host state not applied" severity failure;

    -- 8. ext hook: write + read back a register of the device at 0x21,
    -- read its input port, and a NACK from an absent address
    ext_addr <= "0100001";
    ext('0', x"02", x"5A");
    assert ext_nack = '0' and c_outr(7 downto 0) = x"5A" report "ext write failed" severity failure;
    ext('1', x"02", x"00");
    assert ext_nack = '0' and ext_rdata = x"5A" report "ext read back " & to_hstring(ext_rdata) severity failure;
    ext('1', x"01", x"00");
    assert ext_nack = '0' and ext_rdata = x"BE" report "ext input read " & to_hstring(ext_rdata) severity failure;
    ext_addr <= "1001000";
    ext('1', x"00", x"00");
    assert ext_nack = '1' report "ext to an absent device not NACKed" severity failure;
    wait_us(2500);
    assert valid = '1' report "polling stopped after ext NACK" severity failure;

    assert not ctrl_glitch report "CTRL driven high before the host set it" severity failure;
    assert a_err = 0 and b_err = 0 and c_err = 0
      report "models saw protocol errors: A " & integer'image(a_err) & " B " & integer'image(b_err)
             & " C " & integer'image(c_err) severity failure;
    report "tb_shield_io PASSED";
    fin <= true;
    wait;
  end process;
end architecture;
