-- tb_dut_out_gate: out-policy and shield power-off hold (issue 0056); UART
-- TXD driven low when the DUT is known off (tx_low, issue 0067).
library ieee;
use ieee.std_logic_1164.all;

entity tb_dut_out_gate is
end entity;

architecture tb of tb_dut_out_gate is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal policy : std_logic_vector(7 downto 0) := x"00";
  signal powered, present, pwr : std_logic := '0';
  signal out_en, jpow, hold, tx_low : std_logic;
begin
  clk <= not clk after 4 ns when not done;

  dut : entity work.dut_out_gate
    port map (clk, policy, powered, present, pwr, out_en, jpow, hold, tx_low);

  stim : process
    procedure tick(n : natural := 1) is
    begin
      for k in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;
    procedure expect(o, j, h : std_logic; what : string) is
    begin
      assert out_en = o and jpow = j and hold = h
        report what & ": out_en " & std_logic'image(out_en) & " jtag " & std_logic'image(jpow) &
               " hold " & std_logic'image(hold) severity failure;
      -- known off (hold or policy 2) <=> TXD driven low; never while enabled
      assert (tx_low = '1') = (hold = '1' or policy = x"02")
        report what & ": tx_low " & std_logic'image(tx_low) severity failure;
      assert not (tx_low = '1' and out_en = '1')
        report what & ": tx_low with outputs on" severity failure;
    end procedure;
  begin
    tick(2);
    -- no shield: policy only ------------------------------------------------
    expect('0', '0', '0', "no shield, unpowered");
    powered <= '1'; tick;
    expect('1', '1', '0', "no shield, powered");
    policy <= x"02"; tick;
    expect('0', '0', '0', "policy 2 (JTAG off too)");
    policy <= x"01"; powered <= '0'; tick;
    expect('1', '0', '0', "policy 1 unpowered: UART/KIO10 on, JTAG follows sense");
    powered <= '1'; tick;
    expect('1', '1', '0', "policy 1 powered");
    -- no shield: CTRL bit changes are ignored
    pwr <= '1'; tick(2); pwr <= '0'; tick(2);
    expect('1', '1', '0', "no shield: CTRL ignored");
    policy <= x"00"; powered <= '0'; tick;

    -- shield answers with CTRL off and DUT unpowered: hold (overrides policy 1)
    present <= '1'; tick(2);
    expect('0', '0', '1', "shield up, CTRL off, unpowered");
    policy <= x"01"; tick;
    expect('0', '0', '1', "hold overrides policy 1");
    policy <= x"00";
    -- CTRL on: hold ends, outputs follow the sense
    pwr <= '1'; tick(2);
    expect('0', '0', '0', "CTRL on, sense not yet up");
    powered <= '1'; tick;
    expect('1', '1', '0', "CTRL on, powered");
    -- CTRL off while the rail still reads powered: off at once
    pwr <= '0'; tick;
    expect('0', '0', '1', "CTRL 1->0: forced off the next clock");
    tick(20);
    expect('0', '0', '1', "hold while the rail decays");
    powered <= '0'; tick(5);
    expect('0', '0', '1', "hold, unpowered");
    -- powered again from elsewhere (sense low -> high): hold ends
    powered <= '1'; tick(2);
    expect('1', '1', '0', "sense on again");
    -- CTRL on then off again; CTRL on again ends the hold
    pwr <= '1'; tick(2); pwr <= '0'; tick;
    expect('0', '0', '1', "second CTRL 1->0");
    pwr <= '1'; tick;
    expect('1', '1', '0', "CTRL on again");

    -- shield first answers while the DUT is already sensed powered with CTRL
    -- off (powered from elsewhere): no hold
    present <= '0'; pwr <= '0'; tick(2);
    present <= '1'; tick(2);
    expect('1', '1', '0', "shield up, externally powered");

    report "tb_dut_out_gate PASSED";
    done <= true;
    wait;
  end process;
end architecture;
