-- tb_neighbour_link: two neighbour_link instances (A, B) cross-connected
-- (issue 0069). Time is scaled: tick_1ms every 10 us, so HELLOs go every
-- 1 ms and presence is lost 3.5 ms after the last HELLO.
--   1 HELLO exchange: A (B = 2) primary, B (B = 5) secondary, peer fields
--   2 B -> A cut: A keeps the peer for ~LOST_MS, then standalone; B sees
--     A's standalone claim (heard_us off, mismatch)
--   3 equal B: clash on both, the lower DNA is primary (both directions)
--   4 injected frames on A's RX (tests/scenarios/tb_neighbour_link.py):
--     bad CRC, truncated frame (byte timeout), garbage + good HELLO
--     (resync), unknown type, short HELLO, break, bad magic; counters
--   5 reconnected: B is the peer again, no further errors
-- A's first HELLOs go to CAP_OUT for the reference decoder.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.net_pkg.all;

entity tb_neighbour_link is
  generic (
    VEC_IN  : string := "tb_neighbour_link_in.txt";
    CAP_OUT : string := "tb_neighbour_link_out.txt"
  );
end entity;

architecture tb of tb_neighbour_link is
  constant DNA_A   : std_logic_vector(63 downto 0) := x"0000_0123_4567_89AB";
  constant DNA_A2  : std_logic_vector(63 downto 0) := x"01FF_0000_0000_0000";   -- > DNA_B
  constant DNA_B   : std_logic_vector(63 downto 0) := x"0000_0123_4567_89AC";
  constant DNA_C   : std_logic_vector(63 downto 0) := x"0100_0000_0000_0042";
  constant BUILD_A : std_logic_vector(31 downto 0) := x"C0DE0A0A";
  constant BUILD_B : std_logic_vector(31 downto 0) := x"C0DE0B0B";

  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal tick : std_logic := '0';
  signal dip_av : std_logic_vector(7 downto 0) := x"23";
  signal dip_bv : std_logic_vector(7 downto 0) := x"51";
  signal dna_av : std_logic_vector(63 downto 0) := DNA_A;
  signal a_tx, b_tx, a_rx, b_rx : std_logic;
  signal sa, sb : nb_status_t;
  -- A's RX source: 0 B, 1 idle, 2 injector, 3 low (break)
  signal sel  : integer range 0 to 3 := 0;
  signal itx  : std_logic;
  signal idata : std_logic_vector(7 downto 0) := x"00";
  signal ival, irdy : std_logic := '0';
  constant INC : unsigned(31 downto 0) := x"020C_49BA";
  -- capture of A's TX
  signal cdata : std_logic_vector(7 downto 0);
  signal cval, cferr : std_logic;
begin
  clk <= not clk after 4 ns when not done;

  ticker : process (clk)
    variable n : natural := 0;
  begin
    if rising_edge(clk) then
      tick <= '0';
      if n = 1249 then n := 0; tick <= '1'; else n := n + 1; end if;
    end if;
  end process;

  a : entity work.neighbour_link
    port map (clk => clk, tick_1ms => tick, dip => dip_av, dna => dna_av, build_id => BUILD_A,
              boot_id => x"0B007A00", txd => a_tx, rxd => a_rx, status => sa);
  b : entity work.neighbour_link
    port map (clk => clk, tick_1ms => tick, dip => dip_bv, dna => DNA_B, build_id => BUILD_B,
              boot_id => x"0B007B00", txd => b_tx, rxd => b_rx, status => sb);
  b_rx <= a_tx;
  with sel select a_rx <= b_tx when 0, '1' when 1, itx when 2, '0' when 3;

  inj : entity work.uart_tx port map (clk, INC, idata, ival, irdy, itx);
  cap_rx : entity work.uart_rx port map (clk, INC, a_tx, cdata, cval, cferr);

  -- A's HELLOs (bytes back to back; > 20 us idle ends a frame)
  cap : process
    file fout : text open write_mode is CAP_OUT;
    variable l : line;
    variable nframes : natural := 0;
    variable inframe : boolean := false;
    variable idle : natural := 0;
  begin
    while not done loop
      wait until rising_edge(clk);
      if cval = '1' then
        if not inframe then
          write(l, string'("A"));
          inframe := true;
        end if;
        write(l, string'(" "));
        hwrite(l, cdata);
        idle := 0;
      elsif inframe then
        idle := idle + 1;
        if idle = 2500 then
          writeline(fout, l);
          inframe := false;
          nframes := nframes + 1;
        end if;
      end if;
      assert cferr /= '1' report "framing error on A's TX" severity failure;
      exit when nframes = 4;
    end loop;
    wait;
  end process;

  stim : process
    file fin : text open read_mode is VEC_IN;
    variable l : line;
    variable gap, n : integer;
    variable b : std_logic_vector(7 downto 0);
    variable rx0, crc0, fmt0, uart0 : unsigned(15 downto 0);

    procedure wait_us(t : natural) is
    begin
      wait for t * 1 us;
      wait until rising_edge(clk);
    end procedure;
    -- wait for the end of one of B's HELLOs (its line is idle for ~650 us)
    procedure b_frame_end is
      variable c : unsigned(15 downto 0);
    begin
      c := sb.tx_frames;
      wait until sb.tx_frames /= c;
      wait for 20 us;   -- tx_frames counts when the last byte starts
      wait until rising_edge(clk);
    end procedure;
    procedure send(v : std_logic_vector(7 downto 0)) is
    begin
      idata <= v;
      ival  <= '1';
      wait until rising_edge(clk) and irdy = '1';
      ival <= '0';
      wait until rising_edge(clk);
    end procedure;
    procedure expect(what : string; got, want : unsigned(15 downto 0)) is
    begin
      assert got = want report what & " = " & integer'image(to_integer(got)) & ", want " &
        integer'image(to_integer(want)) severity failure;
    end procedure;
    procedure check_pair(phase : string) is
    begin
      assert sa.present = '1' and sb.present = '1' report phase & ": not both present" severity failure;
      assert sa.heard_us = '1' and sb.heard_us = '1' report phase & ": heard_us" severity failure;
      assert sa.mismatch = '0' and sb.mismatch = '0' report phase & ": role mismatch" severity failure;
      assert sa.loopback = '0' and sb.loopback = '0' report phase & ": loopback" severity failure;
      assert sa.peer_dip = dip_bv and sa.peer_dna = DNA_B and sa.peer_build = BUILD_B
        report phase & ": A's peer fields" severity failure;
      assert sb.peer_dip = dip_av and sb.peer_dna = dna_av and sb.peer_build = BUILD_A
        report phase & ": B's peer fields" severity failure;
      assert sb.peer_role = "000000" & sa.role and sa.peer_role = "000000" & sb.role
        report phase & ": role claims" severity failure;
    end procedure;
  begin
    -- 1: HELLO exchange
    wait_us(3000);
    check_pair("1");
    assert sa.role = NB_ROLE_PRIMARY and sa.primary = '1' and sb.role = NB_ROLE_SECONDARY and
      sb.primary = '0' report "1: roles (lower B primary)" severity failure;
    assert sa.clash = '0' and sb.clash = '0' report "1: clash" severity failure;
    assert sa.rx_frames >= 2 and sb.rx_frames >= 2 and sa.tx_frames >= 2 report "1: frame counts" severity failure;
    report "1: HELLO exchange ok, A rx " & integer'image(to_integer(sa.rx_frames)) & " tx " &
      integer'image(to_integer(sa.tx_frames));

    -- 2: cut B -> A between frames
    b_frame_end;
    sel <= 1;
    wait_us(3000);
    assert sa.present = '1' and sa.role = NB_ROLE_PRIMARY report "2: peer lost too early" severity failure;
    wait_us(800);
    assert sa.present = '0' and sa.role = NB_ROLE_STANDALONE and sa.primary = '0'
      report "2: peer not lost 3.8 ms (~LOST_MS) after the last HELLO" severity failure;
    assert sa.valid = '1' and sa.peer_dna = DNA_B report "2: last peer kept" severity failure;
    wait_us(1100);
    assert sb.present = '1' and sb.heard_us = '0' and sb.mismatch = '1' and sb.peer_role = x"00"
      report "2: B should see A's standalone claim" severity failure;
    report "2: presence timeout ok";

    -- 3: equal B, DNA tiebreak
    b_frame_end;
    sel   <= 0;
    dip_bv <= x"2F";
    wait_us(3000);
    check_pair("3a");
    assert sa.clash = '1' and sb.clash = '1' report "3a: clash not flagged" severity failure;
    assert sa.role = NB_ROLE_PRIMARY and sb.role = NB_ROLE_SECONDARY
      report "3a: lower DNA (A) should be primary" severity failure;
    dna_av <= DNA_A2;
    wait_us(3000);
    check_pair("3b");
    assert sa.role = NB_ROLE_SECONDARY and sb.role = NB_ROLE_PRIMARY
      report "3b: lower DNA (B) should be primary" severity failure;
    dna_av <= DNA_A;
    dip_bv <= x"51";
    wait_us(3000);
    check_pair("3c");
    assert sa.clash = '0' and sa.role = NB_ROLE_PRIMARY report "3c: back to B rule" severity failure;
    expect("A crc_errs", sa.crc_errs, x"0000");
    expect("A fmt_errs", sa.fmt_errs, x"0000");
    expect("A uart_errs", sa.uart_errs, x"0000");
    report "3: B clash / DNA tiebreak ok";

    -- 4: injected frames
    b_frame_end;
    sel <= 2;
    rx0 := sa.rx_frames; crc0 := sa.crc_errs; fmt0 := sa.fmt_errs; uart0 := sa.uart_errs;
    for line_no in 1 to 7 loop
      readline(fin, l);
      read(l, gap);
      read(l, n);
      wait_us(gap);
      if n = 0 then
        sel <= 3;
        wait_us(15);
        sel <= 2;
      else
        for i in 0 to n - 1 loop
          hread(l, b);
          send(b);
        end loop;
      end if;
      wait_us(100);
      case line_no is
        when 1 => expect("crc_errs after a bad CRC", sa.crc_errs, crc0 + 1);
                  expect("rx_frames", sa.rx_frames, rx0);
        when 2 => expect("fmt_errs after a truncated frame", sa.fmt_errs, fmt0 + 1);
        when 3 => expect("rx_frames after garbage + HELLO", sa.rx_frames, rx0 + 1);
                  assert sa.peer_dna = DNA_C and sa.peer_seq = 7 and sa.peer_dip = x"71"
                    report "4: HELLO after garbage not taken" severity failure;
        when 4 => expect("rx_frames after an unknown type", sa.rx_frames, rx0 + 2);
                  expect("fmt_errs", sa.fmt_errs, fmt0 + 1);
        when 5 => expect("fmt_errs after a short HELLO", sa.fmt_errs, fmt0 + 2);
        when 6 => expect("uart_errs after a break", sa.uart_errs, uart0 + 1);
        when 7 => expect("rx_frames after a bad magic", sa.rx_frames, rx0 + 3);
                  expect("fmt_errs after a bad magic", sa.fmt_errs, fmt0 + 3);
                  assert sa.peer_dna = DNA_C report "4: bad-magic HELLO taken" severity failure;
      end case;
    end loop;
    expect("crc_errs", sa.crc_errs, crc0 + 1);
    expect("uart_errs", sa.uart_errs, uart0 + 1);
    report "4: injected frames ok";

    -- 5: reconnected
    b_frame_end;
    sel <= 0;
    wait_us(2500);
    check_pair("5");
    assert sa.role = NB_ROLE_PRIMARY report "5: role" severity failure;
    expect("A crc_errs", sa.crc_errs, crc0 + 1);
    expect("A fmt_errs", sa.fmt_errs, fmt0 + 3);
    expect("A uart_errs", sa.uart_errs, uart0 + 1);
    expect("B crc_errs", sb.crc_errs, x"0000");
    expect("B fmt_errs", sb.fmt_errs, x"0000");
    expect("B uart_errs", sb.uart_errs, x"0000");
    expect("B rx = A tx", sb.rx_frames, sa.tx_frames);
    report "tb_neighbour_link PASSED (A rx " & integer'image(to_integer(sa.rx_frames)) & ", tx " &
      integer'image(to_integer(sa.tx_frames)) & "); run tb_neighbour_link.py check";
    done <= true;
    wait;
  end process;
end architecture;
