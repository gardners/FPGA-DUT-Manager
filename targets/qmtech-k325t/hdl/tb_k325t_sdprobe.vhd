-- nvc testbench for k325t_sdprobe (scaled clock). A minimal SPI-mode SD card
-- model sits on J11 with a non-standard assignment (CS = pin 3, DI = pin 1,
-- DO = pin 4, CK = pin 2: assignment p13), all J11 pins have pull-ups, the
-- J9 slot is empty (pull-ups only). Checks the UART report: pin classes,
-- the winning assignment, CID decode, capacity, and "no card" for J9.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_spi_model is
  port (cs, sck, di : in std_logic; do : out std_logic);
end entity;

architecture sim of sd_spi_model is
  type bytes is array (natural range <>) of std_logic_vector(7 downto 0);
  constant CID : bytes(0 to 15) := (x"03", x"53", x"44", x"53", x"55", x"33", x"32", x"47",
                                    x"80", x"12", x"34", x"56", x"78", x"01", x"35", x"01");
  -- CSD 2.0, C_SIZE = 0x00ED7F -> 60800 * 512 KiB = 30400 MiB
  constant CSD : bytes(0 to 15) := (x"40", x"0E", x"00", x"32", x"5B", x"59", x"00", x"00",
                                    x"ED", x"7F", x"7F", x"80", x"0A", x"40", x"00", x"01");
begin
  process
    variable q : bytes(0 to 63);
    variable qh, qt : natural := 0;
    variable cmd : bytes(0 to 5);
    variable cn : natural := 0;
    variable inb, outb : std_logic_vector(7 downto 0);
    variable bc : natural := 0;
    variable acmd41s : natural := 0;
    variable app : boolean := false;
    procedure push(b : std_logic_vector(7 downto 0)) is
    begin
      q(qt) := b; qt := qt + 1;
    end procedure;
    procedure next_out is
    begin
      if qh < qt then outb := q(qh); qh := qh + 1; else outb := x"FF"; qh := 0; qt := 0; end if;
    end procedure;
  begin
    do <= 'Z';
    wait until to_x01(cs) = '0';
    bc := 0; cn := 0;
    next_out;
    do <= outb(7);
    while to_x01(cs) = '0' loop
      wait until rising_edge(sck) or to_x01(cs) /= '0' or falling_edge(sck);
      exit when to_x01(cs) /= '0';
      if rising_edge(sck) then
        inb := inb(6 downto 0) & to_x01(di);
        bc := bc + 1;
        if bc = 8 then
          if cn = 0 and inb(7 downto 6) /= "01" then
            null;  -- idle byte
          else
            cmd(cn) := inb;
            cn := cn + 1;
            if cn = 6 then
              cn := 0;
              push(x"FF");  -- NCR
              case to_integer(unsigned(cmd(0)(5 downto 0))) is
                when 0 => push(x"01"); app := false;
                when 8 => push(x"01"); push(x"00"); push(x"00"); push(x"01"); push(x"AA");
                when 55 => push(x"01"); app := true;
                when 41 =>
                  acmd41s := acmd41s + 1;
                  if acmd41s >= 3 then push(x"00"); else push(x"01"); end if;
                when 58 => push(x"00"); push(x"C0"); push(x"FF"); push(x"80"); push(x"00");
                when 9 | 10 =>
                  push(x"00"); push(x"FF"); push(x"FF"); push(x"FE");
                  for i in 0 to 15 loop
                    if to_integer(unsigned(cmd(0)(5 downto 0))) = 9 then push(CSD(i)); else push(CID(i)); end if;
                  end loop;
                  push(x"12"); push(x"34");
                when others => push(x"04");
              end case;
            end if;
          end if;
        end if;
      elsif falling_edge(sck) then
        if bc = 8 then
          bc := 0;
          next_out;
          do <= outb(7);
        else
          do <= outb(7 - bc);
        end if;
      end if;
    end loop;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_k325t_sdprobe is
end entity;

architecture sim of tb_k325t_sdprobe is
  constant CLK_HZ : positive := 1_000_000;
  constant BAUD   : positive := 100_000;   -- 10 clocks per bit
  constant TCLK   : time := 20 ns;
  constant TBIT   : time := 10 * TCLK;

  signal clk    : std_logic := '0';
  signal seg_n  : std_logic_vector(7 downto 0);
  signal dig    : std_logic_vector(2 downto 0);
  signal db_led_n : std_logic_vector(4 downto 0);
  signal core_led_n : std_logic_vector(1 downto 0);
  signal tx     : std_logic;
  signal j11    : std_logic_vector(3 downto 0) := (others => 'H');
  signal sd_clk, sd_cmd : std_logic := 'H';
  signal sd_dat : std_logic_vector(3 downto 0) := (others => 'H');
  signal done   : boolean := false;

  signal rxbuf : string(1 to 8000) := (others => ' ');
  signal rxlen : natural := 0;

  function contains(h : string; n : string; len : natural) return boolean is
  begin
    for i in 1 to len - n'length + 1 loop
      if h(i to i + n'length - 1) = n then return true; end if;
    end loop;
    return false;
  end function;
begin
  clk <= not clk after TCLK / 2 when not done;
  j11 <= (others => 'H');
  sd_clk <= 'H'; sd_cmd <= 'H'; sd_dat <= (others => 'H');

  card : entity work.sd_spi_model
    port map (cs => j11(2), sck => j11(1), di => j11(0), do => j11(3));

  dut : entity work.k325t_sdprobe
    generic map (CLK_HZ => CLK_HZ, BAUD => BAUD, US => 2, SPI_HALF => 3, GAP_US => 20,
                 ACMD41_MAX => 50, PULL_SEL => 1, MUX_HZ => 1000)
    port map (clk50 => clk, seg_n => seg_n, dig => dig, db_led_n => db_led_n,
              core_led_n => core_led_n, sw1_n => '1', uart_tx => tx, uart_rx => '1',
              j11 => j11, j11b => "1111", sd_clk => sd_clk, sd_cmd => sd_cmd,
              sd_dat => sd_dat, sd_cd => '1');

  process
    variable v : std_logic_vector(7 downto 0);
    variable n : natural := 0;
  begin
    wait until falling_edge(tx);
    wait for TBIT / 2;
    for i in 0 to 7 loop
      wait for TBIT;
      v(i) := tx;
    end loop;
    wait for TBIT;
    assert tx = '1' report "bad stop bit" severity failure;
    if n < rxbuf'length then
      n := n + 1;
      rxbuf(n) <= character'val(to_integer(unsigned(v)));
      rxlen <= n;
    end if;
  end process;

  process
    variable l : natural := 1;
  begin
    -- echo the report as it arrives, check at the end
    for t in 0 to 4000 loop
      wait for 50 us;
      exit when contains(rxbuf, "== done", rxlen);
    end loop;
    report "UART text:" & LF & rxbuf(1 to rxlen);
    assert contains(rxbuf, "== done", rxlen) report "no end of run" severity failure;
    assert contains(rxbuf, "=> pulled up", rxlen) report "pin class" severity failure;
    assert not contains(rxbuf, "TIED", rxlen) report "tied pin reported" severity failure;
    assert contains(rxbuf, "  p00 CS=1 DI=2 DO=3 CK=4: CMD0 R1=FF", rxlen) report "p00 line" severity failure;
    assert contains(rxbuf, "  p13 CS=3 DI=1 DO=4 CK=2: CMD0 R1=01", rxlen) report "p13 line" severity failure;
    assert contains(rxbuf, "card answers at p13: CS=J11-3 DI=J11-1 DO=J11-4 CK=J11-2", rxlen)
      report "winner" severity failure;
    assert contains(rxbuf, "CMD8 R1=01 R7=000001AA", rxlen) report "CMD8" severity failure;
    assert contains(rxbuf, "OCR=C0FF8000 CCS=1", rxlen) report "CMD58" severity failure;
    assert contains(rxbuf, "MID=0x03 OID=SD PNM=SU32G PRV=8.0 PSN=0x12345678 MDT=2019-05", rxlen)
      report "CID decode" severity failure;
    assert contains(rxbuf, "capacity      30400 MiB (CSD v2", rxlen) report "capacity" severity failure;
    assert contains(rxbuf, "J9 result: no card answered", rxlen) report "J9" severity failure;
    -- LEDs show 13 = 01101 (D1 = MSB = db_led_n(0); printed (4 downto 0), active low)
    assert db_led_n = "01001" report "LEDs " & to_string(db_led_n) severity failure;
    report "tb_k325t_sdprobe: PASS";
    done <= true;
    wait;
  end process;
end architecture;
