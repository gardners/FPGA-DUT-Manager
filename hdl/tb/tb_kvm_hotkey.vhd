-- tb_kvm_hotkey: hold time, MEGA tap, digit order 1..9,0, ESC, timeout.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_kvm_hotkey is
end entity;

architecture tb of tb_kvm_hotkey is
  signal clk, tick : std_logic := '0';
  signal done : boolean := false;
  signal keys : std_logic_vector(79 downto 0) := (others => '0');
  signal sel, cho, can : std_logic;
  signal k : unsigned(3 downto 0);
  signal n_cho, n_can : natural := 0;
  signal last_k : natural := 99;
begin
  clk <= not clk after 4 ns when not done;
  -- "1 ms" tick every 10 clocks; HOLD 100 ticks, TIMEOUT 300 ticks
  process (clk)
    variable c : natural := 0;
  begin
    if rising_edge(clk) then
      c := (c + 1) mod 10;
      if c = 0 then tick <= '1'; else tick <= '0'; end if;
      if cho = '1' then n_cho <= n_cho + 1; last_k <= to_integer(k); end if;
      if can = '1' then n_can <= n_can + 1; end if;
    end if;
  end process;
  dut : entity work.kvm_hotkey generic map (HOLD_MS => 100, TIMEOUT_MS => 300)
    port map (clk, tick, keys, sel, cho, k, can);
  process
    procedure ticks(n : natural) is
    begin
      for i in 1 to n * 10 loop wait until rising_edge(clk); end loop;
    end procedure;
    procedure tap(key : natural) is
    begin
      keys(key) <= '1'; ticks(2); keys(key) <= '0'; ticks(2);
    end procedure;
    procedure hotkey(hold : natural) is
    begin
      keys(15) <= '1'; keys(52) <= '1'; ticks(hold);
      tap(61);
      keys(15) <= '0'; keys(52) <= '0'; ticks(2);
    end procedure;
  begin
    -- too short a hold: no selection
    hotkey(50);
    assert sel = '0' report "selected after a 50 ms hold" severity failure;
    -- proper hold, then key '3' -> machine 2
    hotkey(120);
    assert sel = '1' report "not selecting after hotkey" severity failure;
    tap(8);
    assert sel = '0' and n_cho = 1 and last_k = 2 report "digit 3 -> machine 2" severity failure;
    -- key '0' -> machine 9 (last in keyboard order)
    hotkey(120); tap(35);
    assert n_cho = 2 and last_k = 9 report "digit 0 -> machine 9" severity failure;
    -- ESC cancels
    hotkey(120); tap(71);
    assert sel = '0' and n_can = 1 and n_cho = 2 report "ESC cancel" severity failure;
    -- timeout cancels
    hotkey(120); ticks(320);
    assert sel = '0' and n_can = 2 report "timeout cancel" severity failure;
    -- MEGA without SHIFTs held does nothing
    tap(61);
    assert sel = '0' report "MEGA alone selected" severity failure;
    report "tb_kvm_hotkey PASSED";
    done <= true;
    wait;
  end process;
end architecture;
