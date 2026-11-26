-- tb_vid_src_sel: priority selection of the first present video source
-- (issue 0049) and field unpacking.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vid_src_pkg.all;

entity tb_vid_src_sel is
end entity;

architecture tb of tb_vid_src_sel is
  constant N : positive := 4;
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal present : std_logic_vector(N - 1 downto 0) := (others => '0');
  signal meas : std_logic_vector(N * MEAS_W - 1 downto 0);
  signal sel : unsigned(1 downto 0);
  signal sp, lk, hd, isl : std_logic;
  signal ht, vt, ha, va : unsigned(15 downto 0);
  signal hz : unsigned(31 downto 0);
begin
  clk <= not clk after 4 ns when not done;
  g : for i in 0 to N - 1 generate
    -- source i: 858+i x 525, active 720 x 480+i, 27 MHz + i, locked = odd i,
    -- hdmi = i >= 2, island = i = 3
    meas(i * MEAS_W + MEAS_W - 1 downto i * MEAS_W) <=
      meas_pack(std_logic(to_unsigned(i mod 2, 1)(0)), std_logic(to_unsigned(i / 2, 1)(0)),
                std_logic(to_unsigned(i / 3, 1)(0)),
                to_unsigned(858 + i, 16), to_unsigned(525, 16), to_unsigned(720, 16),
                to_unsigned(480 + i, 16), to_unsigned(27_000_000 + i, 32));
  end generate;
  dut : entity work.vid_src_sel generic map (N => N)
    port map (clk => clk, present => present, meas => meas, sel => sel, sel_present => sp,
              locked => lk, hdmi => hd, island => isl, h_total => ht, v_total => vt,
              h_active => ha, v_active => va, pixel_hz => hz);
  process
    procedure check(p : std_logic_vector(N - 1 downto 0); exp : natural; exp_p : std_logic) is
    begin
      present <= p;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
      assert to_integer(sel) = exp
        report "present " & to_string(p) & ": selected " & integer'image(to_integer(sel)) &
               ", expected " & integer'image(exp) severity failure;
      assert sp = exp_p report "sel_present wrong" severity failure;
      assert ht = 858 + exp and va = 480 + exp and vt = 525 and ha = 720 and hz = 27_000_000 + exp
        report "geometry of the wrong source" severity failure;
      assert lk = std_logic(to_unsigned(exp mod 2, 1)(0)) and hd = std_logic(to_unsigned(exp / 2, 1)(0))
         and isl = std_logic(to_unsigned(exp / 3, 1)(0)) report "flags wrong" severity failure;
    end procedure;
  begin
    check("0000", 0, '0');     -- nothing present: the on-board input
    check("0001", 0, '1');
    check("1111", 0, '1');     -- on-board has priority
    check("0100", 2, '1');
    check("1100", 2, '1');
    check("1000", 3, '1');
    check("1010", 1, '1');
    check("0000", 0, '0');
    report "tb_vid_src_sel PASSED";
    done <= true;
    wait;
  end process;
end architecture;
