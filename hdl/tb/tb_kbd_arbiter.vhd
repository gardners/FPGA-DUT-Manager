-- tb_kbd_arbiter: ownership rules of design brief section 10.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kbd_arbiter is
end entity;

architecture tb of tb_kbd_arbiter is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal ustb, route, owner : std_logic := '0';
  signal ukeys, pkeys, eff, stored : std_logic_vector(79 downto 0) := (others => '0');
  signal policy, ovr : std_logic_vector(7 downto 0) := x"00";

  function k(n : natural) return std_logic_vector is
    variable v : std_logic_vector(79 downto 0) := (others => '0');
  begin
    v(n) := '1';
    return v;
  end function;
begin
  clk <= not clk after 4 ns when not done;
  dut : entity work.kbd_arbiter
    port map (clk, ustb, ukeys, route, pkeys, policy, ovr, eff, stored, owner);

  process
    procedure tick(n : natural := 1) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
      wait for 1 ns;
    end procedure;
    procedure udp(v : std_logic_vector(79 downto 0)) is
    begin
      ukeys <= v; ustb <= '1'; tick; ustb <= '0'; tick;
    end procedure;
    procedure expect(o : std_logic; e : std_logic_vector(79 downto 0); msg : string) is
    begin
      assert owner = o and eff = e report "FAIL: " & msg severity failure;
    end procedure;
  begin
    tick(2);
    -- 1. UDP hold while unselected (e.g. key held through power-on)
    udp(k(10));
    expect('0', k(10), "udp hold");
    -- 2. selected (fresh-press policy) with a key already held: stay UDP
    pkeys <= k(20); route <= '1'; tick(3);
    expect('0', k(10), "held key must not steal with REQUIRE_FRESH_PRESS");
    -- 3. new key-down: physical owns, including later releases
    pkeys <= k(20) or k(21); tick(2);
    expect('1', k(20) or k(21), "fresh press takes ownership");
    pkeys <= (others => '0'); tick(2);
    expect('1', (79 downto 0 => '0'), "physical release stays physical");
    -- 4. identical UDP retransmission does not take ownership back
    udp(k(10));
    expect('1', (79 downto 0 => '0'), "identical UDP retransmit must not steal");
    -- 5. changed UDP bitmap does
    udp(k(11));
    expect('0', k(11), "changed UDP takes ownership");
    -- 6. physical release alone does not steal
    pkeys <= k(5); tick(2);
    expect('1', k(5), "press again -> physical");
    udp(k(12));
    expect('0', k(12), "udp change");
    pkeys <= (others => '0'); tick(2);
    expect('0', k(12), "release alone does not steal");
    -- 7. deselect: immediately back to UDP with no residual holds
    pkeys <= k(6); tick(2);
    expect('1', k(6), "physical again");
    route <= '0'; tick(2);
    expect('0', k(12), "deselect returns to UDP bitmap");
    -- 8. ACCEPT_HELD policy: held key on selection takes ownership at once
    policy <= x"01"; pkeys <= k(7); route <= '1'; tick(3);
    expect('1', k(7), "ACCEPT_HELD");
    route <= '0'; tick(2); policy <= x"00"; pkeys <= (others => '0'); tick;
    -- 9. simultaneous UDP change and key-down: UDP wins
    route <= '1'; tick(2);
    ukeys <= k(13); ustb <= '1'; pkeys <= k(8); tick; ustb <= '0'; tick(2);
    expect('0', k(13), "UDP wins simultaneous events");
    -- 10. overrides
    ovr <= x"03"; tick;
    assert eff = (79 downto 0 => '0') report "all-up override" severity failure;
    ovr <= x"02"; tick;
    assert eff = k(8) report "force physical" severity failure;
    ovr <= x"01"; tick;
    assert eff = k(13) report "force UDP" severity failure;
    report "tb_kbd_arbiter PASSED";
    done <= true;
    wait;
  end process;
end architecture;
