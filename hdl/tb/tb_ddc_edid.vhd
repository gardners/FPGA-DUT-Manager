-- tb_ddc_edid: an I2C master model reads the EDID from ddc_edid (issue 0033).
--  * expected bytes come from scripts/gen_edid.py via the scenario hook
--    (VEC_IN, one hex byte per line), so a stale edid_pkg.vhd fails here;
--  * sequential read of all 256 bytes (write offset 0, Sr, read, NACK last)
--    at 100 kHz, checked byte for byte and by block checksums;
--  * random reads at 400 kHz (offset 0x7E/0x80/0xFF wrap), a current-address
--    read that continues from the pointer, a write that must not modify the
--    contents, NACK for 0x51 and for the E-DDC segment pointer 0x30;
--  * the bytes read are written to CAP_OUT for the Python EDID decoder.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.common_pkg.all;

entity tb_ddc_edid is
  generic (VEC_IN : string := "tb_ddc_edid_in.txt"; CAP_OUT : string := "tb_ddc_edid_out.txt");
end entity;

architecture tb of tb_ddc_edid is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal scl, sda : std_logic := 'H';
  signal m_scl_low, m_sda_low, s_sda_low : std_logic := '0';
  signal reads : unsigned(15 downto 0);
  signal tq : time := 2.5 us;            -- quarter SCL period (100 kHz)
begin
  clk <= not clk after 2.5 ns when not done;    -- 200 MHz, as on the board
  -- open-drain bus with pull-ups
  scl <= 'H';
  sda <= 'H';
  scl <= '0' when m_scl_low = '1' else 'Z';
  sda <= '0' when m_sda_low = '1' else 'Z';
  sda <= '0' when s_sda_low = '1' else 'Z';

  dut : entity work.ddc_edid
    generic map (CLK_HZ => 200_000_000)
    port map (clk => clk, rst => '0', scl => scl, sda => sda, sda_low => s_sda_low,
              reads => reads);

  process
    variable exp, got : byte_array_t(0 to 255);
    variable l : line;
    variable v : std_logic_vector(7 downto 0);
    variable ack : boolean;
    variable b : byte_t;
    variable sum : unsigned(7 downto 0);
    file fin : text open read_mode is VEC_IN;
    file fout : text;

    procedure start is          -- (repeated) start; leaves SCL low
    begin
      m_sda_low <= '0'; wait for tq;
      m_scl_low <= '0'; wait for tq;
      m_sda_low <= '1'; wait for tq;
      m_scl_low <= '1'; wait for tq;
    end procedure;
    procedure stop is
    begin
      m_sda_low <= '1'; wait for tq;
      m_scl_low <= '0'; wait for tq;
      m_sda_low <= '0'; wait for 2 * tq;
    end procedure;
    procedure bit_out(x : std_logic) is
    begin
      m_sda_low <= not x; wait for tq;
      m_scl_low <= '0'; wait for 2 * tq;
      m_scl_low <= '1'; wait for tq;
    end procedure;
    procedure bit_in(x : out std_logic) is
    begin
      m_sda_low <= '0'; wait for tq;
      m_scl_low <= '0'; wait for tq;
      x := to_x01(sda); wait for tq;
      m_scl_low <= '1'; wait for tq;
    end procedure;
    procedure wr(d : byte_t; a : out boolean) is
      variable x : std_logic;
    begin
      for i in 7 downto 0 loop
        bit_out(d(i));
      end loop;
      bit_in(x);
      a := x = '0';
    end procedure;
    procedure rd(d : out byte_t; last : boolean) is
      variable x : std_logic;
    begin
      for i in 7 downto 0 loop
        bit_in(x); d(i) := x;
      end loop;
      if last then bit_out('1'); else bit_out('0'); end if;
    end procedure;
    procedure set_ptr(o : natural) is
    begin
      start; wr(x"A0", ack);
      assert ack report "0x50 write address not acknowledged" severity failure;
      wr(std_logic_vector(to_unsigned(o, 8)), ack);
      assert ack report "word offset not acknowledged" severity failure;
    end procedure;
    procedure rand_read(o : natural) is
    begin
      set_ptr(o);
      start; wr(x"A1", ack);
      assert ack report "0x50 read address not acknowledged" severity failure;
      rd(b, true); stop;
      assert b = exp(o) report "random read @" & integer'image(o) & ": got " &
        to_hstring(b) & " want " & to_hstring(exp(o)) severity failure;
    end procedure;
  begin
    for i in 0 to 255 loop
      readline(fin, l); hread(l, v); exp(i) := v;
    end loop;
    wait for 5 us;

    -- 1. whole EDID, sequential read at 100 kHz
    set_ptr(0);
    start; wr(x"A1", ack);
    assert ack report "read address not acknowledged" severity failure;
    for i in 0 to 255 loop
      rd(got(i), i = 255);
    end loop;
    stop;
    for i in 0 to 255 loop
      assert got(i) = exp(i) report "byte " & integer'image(i) & ": got " &
        to_hstring(got(i)) & " want " & to_hstring(exp(i)) severity failure;
    end loop;
    for blk in 0 to 1 loop
      sum := (others => '0');
      for i in 0 to 127 loop
        sum := sum + unsigned(got(blk * 128 + i));
      end loop;
      assert sum = 0 report "block " & integer'image(blk) & " checksum " &
        to_hstring(sum) severity failure;
    end loop;
    file_open(fout, CAP_OUT, write_mode);
    for i in 0 to 255 loop
      hwrite(l, got(i)); writeline(fout, l);
    end loop;
    file_close(fout);
    assert reads = 1 report "read counter " & integer'image(to_integer(reads)) severity failure;

    -- 2. fast mode: random reads, pointer wrap
    tq <= 0.625 us; wait for 0 ns;
    rand_read(16#7E#);
    rand_read(16#80#);
    rand_read(16#FF#);
    -- current-address read: pointer is now 0x00 (wrapped after 0xFF)
    start; wr(x"A1", ack);
    assert ack severity failure;
    rd(b, false); assert b = exp(0) report "wrap to 0" severity failure;
    rd(b, true); assert b = exp(1) report "continue at 1" severity failure;
    stop;

    -- 3. writes are acknowledged but ignored
    set_ptr(8); wr(x"55", ack);
    assert ack report "data write not acknowledged" severity failure;
    stop;
    rand_read(8);

    -- 4. other addresses are not acknowledged; bus still usable afterwards
    start; wr(x"A2", ack); stop;
    assert not ack report "0x51 acknowledged" severity failure;
    start; wr(x"60", ack); stop;
    assert not ack report "segment pointer 0x30 acknowledged" severity failure;
    rand_read(16#36#);

    report "tb_ddc_edid PASSED (" & integer'image(to_integer(reads)) & " read transfers)";
    done <= true;
    wait;
  end process;
end architecture;
