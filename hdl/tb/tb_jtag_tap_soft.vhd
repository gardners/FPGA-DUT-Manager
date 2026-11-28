-- tb_jtag_tap_soft: the test_dut soft TAP (issue 0068) driven like the
-- supervisor's jtag_engine: TMS/TDI set at the start of the TCK low phase,
-- TDO sampled at the end of the high phase minus 16 ns (the engine's 2-flop
-- synchroniser at 125 MHz). Runs at half period 6 (48 ns, 10.4 MHz) and 5
-- (40 ns, 12.5 MHz), with TCK/TMS/TDI asynchronous to the TAP's 100 MHz.
-- Checks IDCODE after reset, the Capture-IR pattern, BYPASS (1-bit delay),
-- USERDR write/read, Test-Logic-Reset by 5 TMS highs, unknown opcode ->
-- bypass.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_jtag_tap_soft is
end entity;

architecture tb of tb_jtag_tap_soft is
  constant ID : std_logic_vector(31 downto 0) := x"7E57D001";
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal tck, tms, tdi : std_logic := '0';
  signal tdo, in_tlr, tck_stb : std_logic;
  signal user_dr : std_logic_vector(31 downto 0);
  signal half : time := 48 ns;
begin
  clk <= not clk after 5 ns when not done;

  dut : entity work.jtag_tap_soft generic map (IDCODE => ID)
    port map (clk, tck, tms, tdi, tdo, in_tlr, tck_stb, user_dr);

  stim : process
    -- one TCK cycle; returns TDO as sampled before the falling edge
    procedure clock(m, d : std_logic; o : out std_logic) is
    begin
      tms <= m; tdi <= d;
      wait for half;
      tck <= '1';
      wait for half - 16 ns;
      o := tdo;
      wait for 16 ns;
      tck <= '0';
    end procedure;
    procedure clock(m : std_logic) is
      variable o : std_logic;
    begin
      clock(m, '0', o);
    end procedure;
    -- from Run-Test/Idle: shift n bits (LSB first) through DR or IR, back to RTI
    procedure scan(ir_path : boolean; n : positive; din : std_logic_vector;
                   dout : out std_logic_vector) is
      variable o : std_logic;
      variable r : std_logic_vector(n - 1 downto 0);
      constant dd : std_logic_vector(n - 1 downto 0) := din;  -- literals are ascending
    begin
      clock('1');                         -- Select-DR
      if ir_path then clock('1'); end if; -- Select-IR
      clock('0');                         -- Capture
      clock('0');                         -- Shift
      for i in 0 to n - 1 loop
        if i = n - 1 then
          clock('1', dd(i), o); -- Exit1 with the last bit
        else
          clock('0', dd(i), o);
        end if;
        r(i) := o;
      end loop;
      clock('1');                         -- Update
      clock('0');                         -- RTI
      dout := r;
    end procedure;
    variable v32 : std_logic_vector(31 downto 0);
    variable v4  : std_logic_vector(3 downto 0);
    variable v8  : std_logic_vector(7 downto 0);
    constant PAT : std_logic_vector(31 downto 0) := x"A5C3_0F12";
  begin
    for sp in 0 to 1 loop
      if sp = 0 then half <= 48 ns; else half <= 40 ns; end if;
      wait for 200 ns;
      -- 5 TMS highs from wherever we are -> Test-Logic-Reset
      for i in 1 to 5 loop clock('1'); end loop;
      wait for 100 ns;
      assert in_tlr = '1' report "not in TLR after 5 TMS highs" severity failure;
      clock('0');                          -- RTI
      assert in_tlr = '0' report "still in TLR" severity failure;

      -- IDCODE is the default instruction after reset
      scan(false, 32, x"00000000", v32);
      assert v32 = ID report "IDCODE after reset: " & to_hstring(v32) severity failure;

      -- IR capture pattern 0101 while loading USERDR (0010)
      scan(true, 4, "0010", v4);
      assert v4 = "0101" report "IR capture: " & to_string(v4) severity failure;
      -- write PAT; first read returns the old value (0 or previous PAT)
      scan(false, 32, PAT, v32);
      assert v32 = x"00000000" or v32 = PAT report "USERDR old value: " & to_hstring(v32) severity failure;
      scan(false, 32, not PAT, v32);
      assert v32 = PAT report "USERDR readback: " & to_hstring(v32) severity failure;
      assert user_dr = not PAT report "USERDR not updated" severity failure;
      scan(false, 32, PAT, v32);
      assert v32 = not PAT report "USERDR readback 2: " & to_hstring(v32) severity failure;

      -- BYPASS: 1-bit register captured to 0 -> data delayed by one bit
      scan(true, 4, "1111", v4);
      assert v4 = "0101" report "IR capture (2)" severity failure;
      scan(false, 8, "11010011", v8);
      assert v8 = "10100110" report "BYPASS: " & to_string(v8) severity failure;
      -- unknown opcode 0000 -> bypass too
      scan(true, 4, "0000", v4);
      scan(false, 8, "01101001", v8);
      assert v8 = "11010010" report "opcode 0000 not bypass: " & to_string(v8) severity failure;

      -- back to USERDR, then TLR by 5 TMS highs must reselect IDCODE
      scan(true, 4, "0010", v4);
      clock('1'); clock('0'); clock('0');  -- Select-DR, Capture, Shift-DR
      for i in 1 to 5 loop clock('1'); end loop;
      assert in_tlr = '1' report "5 TMS highs from Shift-DR: not TLR" severity failure;
      clock('0');
      scan(false, 32, x"FFFFFFFF", v32);
      assert v32 = ID report "IDCODE after TLR: " & to_hstring(v32) severity failure;
      -- USERDR is not reset by TLR; the path Shift-DR -> Exit1 -> Update-DR
      -- taken by those TMS highs shifted one 0 in and updated it: PAT >> 1
      scan(true, 4, "0010", v4);
      scan(false, 32, x"00000000", v32);
      assert v32 = '0' & PAT(31 downto 1) report "USERDR after TLR: " & to_hstring(v32) severity failure;
      report "speed " & time'image(half) & " ok";
    end loop;
    report "tb_jtag_tap_soft PASSED";
    done <= true;
    wait;
  end process;
end architecture;
