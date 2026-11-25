-- tb_seg7_status: check pin-level patterns for "dHCP" and the DUT IDs using
-- the Mimas A7 V3.1 wiring (7SEG_0..7 = G F A B DP C D E, active low).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_seg7_status is
end entity;

architecture tb of tb_seg7_status is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal have_ip : std_logic := '0';
  signal seg : std_logic_vector(7 downto 0);
  signal en : std_logic_vector(3 downto 0);

  -- expected pins from a list of lit segment letters
  function pins(lit : string) return std_logic_vector is
    constant ORDER : string(1 to 8) := "GFABPCDE";   -- P = decimal point
    variable v : std_logic_vector(7 downto 0) := (others => '1');
  begin
    for i in 1 to 8 loop
      for j in lit'range loop
        if lit(j) = ORDER(i) then v(i - 1) := '0'; end if;
      end loop;
    end loop;
    return v;
  end function;
begin
  clk <= not clk after 5 ns when not done;
  dut : entity work.seg7_status generic map (CLK_HZ => 40_000)
    port map (clk, have_ip, x"3", x"A", seg, en);

  process
    type exp_t is array (0 to 3) of std_logic_vector(7 downto 0);
    procedure check(e : exp_t; what : string) is
      variable seen : std_logic_vector(3 downto 0) := "0000";
    begin
      for n in 0 to 200 loop
        wait until rising_edge(clk);
        for d in 0 to 3 loop
          if en(d) = '0' and seg /= x"FF" then
            assert seg = e(d) report what & " digit " & integer'image(d) & " got " &
              to_hstring(seg) & " want " & to_hstring(e(d)) severity failure;
            seen(d) := '1';
          end if;
        end loop;
      end loop;
      assert seen = "1111" or what = "ids" report what & ": not all digits seen" severity failure;
    end procedure;
  begin
    -- before the blink phase turns them off: d H C P
    check((pins("BCDEG"), pins("BCEFG"), pins("ADEF"), pins("ABEFG")), "dHCP");
    have_ip <= '1';
    wait for 1 us;
    -- 3 - A (blank)
    check((pins("ABCDG"), pins("G"), pins("ABCEFG"), x"FF"), "ids");
    report "tb_seg7_status PASSED";
    done <= true;
    wait;
  end process;
end architecture;
