-- tb_i2c_master: byte-level I2C master (issue 0049) against the TCA6424A
-- model: register write/read with auto-increment and repeated START, NACK
-- of an absent address, clock stretching, SCL timing at 400 kHz, a
-- stretch timeout, and bus-stuck recovery (a slave holding SDA low).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2c_master is
end entity;

architecture tb of tb_i2c_master is
  constant C_START   : std_logic_vector(2 downto 0) := "001";
  constant C_STOP    : std_logic_vector(2 downto 0) := "010";
  constant C_WRITE   : std_logic_vector(2 downto 0) := "011";
  constant C_READ    : std_logic_vector(2 downto 0) := "100";
  constant C_RECOVER : std_logic_vector(2 downto 0) := "101";
  signal clk : std_logic := '0';
  signal fin : boolean := false;
  signal cmd_valid, rd_nack, ready, done, nack, err : std_logic := '0';
  signal cmd : std_logic_vector(2 downto 0) := "000";
  signal wdata, rdata : std_logic_vector(7 downto 0) := x"00";
  signal scl_low, sda_low : std_logic;
  signal scl, sda : std_logic;
  signal pins, pins_out, outr, cfgr : std_logic_vector(23 downto 0);
  signal nwr, nrd, nerr : natural;
  -- bus disturbers
  signal stretch_ns : natural := 0;    -- hold SCL low this long after each fall
  signal stuck_bits : natural := 0;    -- hold SDA low for this many SCL pulses
  signal hold_scl   : std_logic := '0';
  signal t_rise, t_fall : time := 0 ns;
  signal min_high, min_low : time := 1 sec;
  signal meas_on : boolean := false;
begin
  clk <= not clk after 4 ns when not fin;     -- 125 MHz
  scl <= 'H'; sda <= 'H';
  scl <= '0' when scl_low = '1' else 'Z';
  sda <= '0' when sda_low = '1' else 'Z';
  scl <= '0' when hold_scl = '1' else 'Z';

  dut : entity work.i2c_master
    generic map (CLK_HZ => 125_000_000, SCL_HZ => 400_000, STRETCH_MAX => 2_500)  -- 20 us
    port map (clk => clk, rst => '0', cmd_valid => cmd_valid, cmd => cmd, wdata => wdata,
              rd_nack => rd_nack, ready => ready, done => done, rdata => rdata, nack => nack,
              err => err, scl_in => scl, sda_in => sda, scl_low => scl_low, sda_low => sda_low);

  pins <= x"A5" & x"3C" & x"5A";      -- P2 P1 P0 external levels
  exp_a : entity work.tca6424a_model
    port map (sda => sda, scl => scl, pins => pins, pins_out => pins_out, out_regs => outr,
              cfg_regs => cfgr, writes => nwr, reads => nrd, errors => nerr);

  -- clock stretcher: after every SCL fall, hold it low for stretch_ns
  process
  begin
    wait until to_x01(scl) = '0';
    if stretch_ns > 0 then
      wait for 100 ns;
      hold_scl <= '1';
      wait for stretch_ns * 1 ns;
      hold_scl <= '0';
    end if;
  end process;

  -- stuck slave: SDA low for stuck_bits SCL pulses
  process
    variable n : natural;
  begin
    sda <= 'Z';
    wait until stuck_bits > 0;
    n := stuck_bits;
    sda <= '0';
    while n > 0 loop
      wait until to_x01(scl) = '0' or stuck_bits = 0;
      exit when stuck_bits = 0;
      wait until to_x01(scl) = '1' or stuck_bits = 0;
      exit when stuck_bits = 0;
      n := n - 1;
    end loop;
    if stuck_bits /= 0 then
      wait until to_x01(scl) = '0';
      wait for 200 ns;
    end if;
    sda <= 'Z';
    if stuck_bits /= 0 then wait until stuck_bits = 0; end if;
  end process;

  -- SCL high/low time monitor (excluding START/STOP edges)
  process (scl)
  begin
    if meas_on then
      if to_x01(scl) = '1' and t_fall > 0 ns then
        if now - t_fall < min_low then min_low <= now - t_fall; end if;
        t_rise <= now;
      elsif to_x01(scl) = '0' and t_rise > 0 ns then
        if now - t_rise < min_high then min_high <= now - t_rise; end if;
        t_fall <= now;
      elsif to_x01(scl) = '0' then
        t_fall <= now;
      end if;
    end if;
  end process;

  process
    variable r : std_logic_vector(7 downto 0);
    variable e0 : natural;
    procedure op(c : std_logic_vector(2 downto 0); d : std_logic_vector(7 downto 0) := x"00";
                 nk : std_logic := '0') is
    begin
      wait until rising_edge(clk) and ready = '1';
      cmd <= c; wdata <= d; rd_nack <= nk; cmd_valid <= '1';
      wait until rising_edge(clk);
      cmd_valid <= '0';
      wait until rising_edge(clk) and done = '1';
    end procedure;
    procedure wr(d : std_logic_vector(7 downto 0)) is
    begin
      op(C_WRITE, d);
      assert nack = '0' and err = '0' report "write " & to_hstring(d) & " not ACKed" severity failure;
    end procedure;
  begin
    wait for 1 us;
    assert to_x01(scl) = '1' and to_x01(sda) = '1' report "bus not idle" severity failure;

    -- 1. write output ports 0..2 with auto-increment, then config port 2
    meas_on <= true;
    op(C_START); assert err = '0' report "START failed" severity failure;
    wr(x"44"); wr(x"84"); wr(x"11"); wr(x"22"); wr(x"33");
    op(C_STOP);
    meas_on <= false;
    assert outr = x"332211" report "output regs " & to_hstring(outr) severity failure;
    assert min_high >= 600 ns and min_low >= 1300 ns
      report "SCL timing: high " & time'image(min_high) & " low " & time'image(min_low) severity failure;
    op(C_START); wr(x"44"); wr(x"0E"); wr(x"00"); op(C_STOP);
    assert cfgr = x"00FFFF" report "config regs " & to_hstring(cfgr) severity failure;
    assert pins_out(23 downto 16) = x"33" report "port 2 not driven" severity failure;

    -- 2. read input ports 0, 1 with AI and a repeated START
    op(C_START); wr(x"44"); wr(x"80");
    op(C_START); wr(x"45");
    op(C_READ, nk => '0'); r := rdata;
    assert r = x"5A" report "input 0 read " & to_hstring(r) severity failure;
    op(C_READ, nk => '1'); r := rdata;
    assert r = x"3C" report "input 1 read " & to_hstring(r) severity failure;
    op(C_STOP);
    -- port 2 is an output now: the input register shows the driven level
    op(C_START); wr(x"44"); wr(x"02"); op(C_START); wr(x"45");
    op(C_READ, nk => '1');
    assert rdata = x"33" report "input 2 read " & to_hstring(rdata) severity failure;
    op(C_STOP);

    -- 3. absent device: NACK on the address
    op(C_START); op(C_WRITE, x"40");
    assert nack = '1' and err = '0' report "absent address ACKed" severity failure;
    op(C_STOP);
    assert to_x01(scl) = '1' and to_x01(sda) = '1' report "bus not released after NACK" severity failure;

    -- 4. clock stretching (5 us per low phase): the transfer still works
    stretch_ns <= 5_000;
    op(C_START); wr(x"44"); wr(x"85"); wr(x"C3"); op(C_STOP);
    stretch_ns <= 0;
    wait for 10 us;
    assert outr(15 downto 8) = x"C3" report "stretched write lost" severity failure;

    assert nerr = 0 report "model saw protocol errors" severity failure;
    -- 5. stretch beyond STRETCH_MAX (20 us): err, lines released
    op(C_START); wr(x"44");
    stretch_ns <= 50_000;
    op(C_WRITE, x"86");
    assert err = '1' report "stretch timeout not reported" severity failure;
    stretch_ns <= 0;
    wait for 60 us;
    assert to_x01(scl) = '1' and to_x01(sda) = '1' report "bus not released after timeout" severity failure;
    op(C_RECOVER);   -- the model saw an unfinished byte: clock it out, STOP

    -- 6. stuck bus: a slave holds SDA low for 5 clocks; START refuses,
    -- RECOVER clocks it free and leaves the bus idle
    stuck_bits <= 5;
    wait for 1 us;
    op(C_START);
    assert err = '1' report "START on a busy bus not refused" severity failure;
    op(C_RECOVER);
    assert err = '0' report "recovery reported failure" severity failure;
    assert to_x01(scl) = '1' and to_x01(sda) = '1' report "bus not idle after recovery" severity failure;
    stuck_bits <= 0;
    wait for 1 us;
    -- 6b. permanently stuck (more than 9 clocks): err
    stuck_bits <= 20;
    wait for 1 us;
    op(C_RECOVER);
    assert err = '1' report "unrecoverable bus not reported" severity failure;
    stuck_bits <= 0;
    wait for 5 us;
    op(C_RECOVER);
    assert err = '0' and to_x01(sda) = '1' report "bus not idle after release" severity failure;
    e0 := nerr;

    -- 7. the bus still works afterwards
    op(C_START); wr(x"44"); wr(x"84"); wr(x"77"); op(C_STOP);
    assert outr(7 downto 0) = x"77" report "write after recovery lost" severity failure;
    -- the model's protocol checker (sections 5/6 abort bytes on purpose)
    assert nerr = e0 report "model saw protocol errors after recovery" severity failure;

    report "tb_i2c_master PASSED";
    fin <= true;
    wait;
  end process;
end architecture;
