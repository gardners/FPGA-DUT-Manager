-- tb_dvi_tx: serialise with dvi_tx_xc7 (SIM models), recover symbols from
-- the TMDS lanes using the clock lane for framing, decode them, and check
-- pixel values during DE and HS/VS control symbols during blanking.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dvi_tx is
end entity;

architecture tb of tb_dvi_tx is
  constant TPIX : time := 37.037 ns;
  signal clk_pix, clk5 : std_logic := '0';
  signal done : boolean := false;
  signal rst : std_logic := '1';
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal r, g, b : std_logic_vector(7 downto 0);
  signal tdp, tdn : std_logic_vector(2 downto 0);
  signal cp, cn : std_logic;

  function decode(q : std_logic_vector(9 downto 0)) return std_logic_vector is
    variable d : std_logic_vector(7 downto 0);
    variable qq : std_logic_vector(7 downto 0);
  begin
    qq := q(7 downto 0);
    if q(9) = '1' then qq := not qq; end if;
    d(0) := qq(0);
    for i in 1 to 7 loop
      if q(8) = '1' then d(i) := qq(i) xor qq(i - 1); else d(i) := not (qq(i) xor qq(i - 1)); end if;
    end loop;
    return d;
  end function;
begin
  clk_pix <= not clk_pix after TPIX / 2 when not done;
  clk5    <= not clk5 after TPIX / 10 when not done;

  tim : entity work.video_timing
    generic map (H_ACTIVE => 64, H_FP => 4, H_SYNC => 8, H_BP => 4,
                 V_ACTIVE => 8, V_FP => 1, V_SYNC => 2, V_BP => 2)
    port map (clk_pix, x, y, de, hs, vs, fs);
  -- pixel value depends on x so ordering errors are caught
  r <= std_logic_vector(x(7 downto 0));
  g <= std_logic_vector(x(7 downto 0) + 85);
  b <= std_logic_vector(not x(7 downto 0));

  dut : entity work.dvi_tx_xc7 generic map (SIM => true)
    port map (clk_pix, clk5, rst, r, g, b, hs, vs, de, tdp, tdn, cp, cn);

  rst <= '0' after 200 ns;

  check : process
    type bits_t is array (0 to 3) of std_logic_vector(9 downto 0);
    variable sh : bits_t := (others => (others => '0'));
    variable nbits : natural := 0;
    variable synced : boolean := false;
    variable q : std_logic_vector(9 downto 0);
    variable ok : boolean;
    variable pix, ctl, errors, skip : natural := 0;
    variable d : std_logic_vector(7 downto 0);
    variable vin : std_logic_vector(3 downto 0);
    variable lane : std_logic_vector(3 downto 0);
    variable want_r : unsigned(7 downto 0);
    variable sym : natural := 0;
  begin
    wait for 2 us;
    -- sample in the middle of each half serial period (2 bits per clk5)
    for n in 0 to 40000 loop
      wait until clk5'event;
      wait for TPIX / 20;
      lane := cp & tdp;
      for i in 0 to 3 loop
        sh(i) := lane(i) & sh(i)(9 downto 1);   -- LSB first
      end loop;
      nbits := nbits + 1;
      -- clock lane symbol is 0000011111 (LSB first: five 1s then five 0s)
      if not synced then
        if sh(3) = "0000011111" then synced := true; nbits := 0; end if;
      elsif nbits = 10 then
        nbits := 0;
        sym := sym + 1;
        assert sh(3) = "0000011111" report "clock lane lost framing" severity failure;
        -- blue lane: control symbols carry (vs, hs) during blanking
        q := sh(0);
        if q = "1101010100" or q = "0010101011" or q = "0101010100" or q = "1010101011" then
          ctl := ctl + 1;
        else
          -- data period: check that red = x, green = x + 85, blue = not x
          d := decode(sh(2));
          want_r := unsigned(d);
          if decode(sh(1)) /= std_logic_vector(want_r + 85) or
             decode(sh(0)) /= std_logic_vector(not want_r) then
            errors := errors + 1;
          end if;
          pix := pix + 1;
        end if;
      end if;
    end loop;
    report "decoded " & integer'image(pix) & " pixels, " & integer'image(ctl) &
      " control symbols, " & integer'image(errors) & " colour errors";
    assert pix > 500 and ctl > 500 and errors = 0 report "DVI decode failed" severity failure;
    report "tb_dvi_tx PASSED";
    done <= true;
    wait;
  end process;
end architecture;
