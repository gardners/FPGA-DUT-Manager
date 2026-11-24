-- tb_jtag_engine: engine driving a behavioural TAP (IDCODE 0x0362C093).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_jtag_engine is
end entity;

architecture tb of tb_jtag_engine is
  signal clk : std_logic := '0';
  signal done : boolean := false;
  signal powered : std_logic := '1';
  signal req_valid, req_abort, vec_we, go : std_logic := '0';
  signal req_seq, req_bits, req_half : unsigned(31 downto 0) := (others => '0');
  signal dec_valid : std_logic;
  signal dec_code  : unsigned(2 downto 0);
  signal vec_addr  : unsigned(10 downto 0) := (others => '0');
  signal vec_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tdo_addr  : unsigned(9 downto 0) := (others => '0');
  signal tdo_data  : std_logic_vector(7 downto 0);
  signal busy, ready, dstb, aborted, oe : std_logic;
  signal nseq, lseq, lbits : unsigned(31 downto 0);
  signal tck, tms, tdi, tdo : std_logic;
  signal rises : natural := 0;

  -- TAP model
  type tap_t is (TLR, RTI, SELDR, CAPDR, SHDR, EX1DR, PADR, EX2DR, UPDR,
                 SELIR, CAPIR, SHIR, EX1IR, PAIR, EX2IR, UPIR);
  signal tap : tap_t := TLR;
  signal dr  : std_logic_vector(31 downto 0) := (others => '0');
  signal ir  : std_logic_vector(5 downto 0) := "001001";
  signal tdo_r : std_logic := '0';
  constant IDCODE : std_logic_vector(31 downto 0) := x"0362C093";

  type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
begin
  clk <= not clk after 4 ns when not done;

  dut : entity work.jtag_engine
    port map (clk, powered, req_valid, req_seq, req_bits, req_half, req_abort,
              dec_valid, dec_code, vec_we, vec_addr, vec_data, go,
              tdo_addr, tdo_data, busy, ready, dstb, aborted, nseq, lseq, lbits,
              tck, tms, tdi, oe, tdo);

  tdo <= tdo_r;

  tapm : process (tck)
  begin
    if rising_edge(tck) then
      rises <= rises + 1;
      case tap is
        when TLR   => if tms = '0' then tap <= RTI; end if; ir <= "001001";
        when RTI   => if tms = '1' then tap <= SELDR; end if;
        when SELDR => if tms = '1' then tap <= SELIR; else tap <= CAPDR; end if;
        when CAPDR => dr <= IDCODE; if tms = '1' then tap <= EX1DR; else tap <= SHDR; end if;
        when SHDR  => dr <= tdi & dr(31 downto 1); if tms = '1' then tap <= EX1DR; end if;
        when EX1DR => if tms = '1' then tap <= UPDR; else tap <= PADR; end if;
        when PADR  => if tms = '1' then tap <= EX2DR; end if;
        when EX2DR => if tms = '1' then tap <= UPDR; else tap <= SHDR; end if;
        when UPDR  => if tms = '1' then tap <= SELDR; else tap <= RTI; end if;
        when SELIR => if tms = '1' then tap <= TLR; else tap <= CAPIR; end if;
        when CAPIR => if tms = '1' then tap <= EX1IR; else tap <= SHIR; end if;
        when SHIR  => if tms = '1' then tap <= EX1IR; end if;
        when EX1IR => if tms = '1' then tap <= UPIR; else tap <= PAIR; end if;
        when PAIR  => if tms = '1' then tap <= EX2IR; end if;
        when EX2IR => if tms = '1' then tap <= UPIR; else tap <= SHIR; end if;
        when UPIR  => if tms = '1' then tap <= SELDR; else tap <= RTI; end if;
      end case;
    end if;
    if falling_edge(tck) then
      if tap = SHDR then tdo_r <= dr(0); else tdo_r <= '0'; end if;
    end if;
  end process;

  stim : process
    variable tdo_bits : std_logic_vector(63 downto 0);
    variable nb : natural := 0;
    variable start_rises : natural;

    procedure request(seq, bits, half : natural; abort : std_logic := '0') is
    begin
      wait until rising_edge(clk);
      req_valid <= '1'; req_seq <= to_unsigned(seq, 32);
      req_bits <= to_unsigned(bits, 32); req_half <= to_unsigned(half, 32);
      req_abort <= abort;
      wait until rising_edge(clk);
      req_valid <= '0'; req_abort <= '0';
      wait until rising_edge(clk) and dec_valid = '1';
    end procedure;

    -- shift: TMS/TDI given as strings, char 1 = first bit
    procedure shift(seq : natural; tms_s, tdi_s : string; half : natural) is
      variable n : natural := tms_s'length;
      variable tmsb, tdib : std_logic_vector(7 downto 0);
    begin
      start_rises := rises;
      request(seq, n, half);
      assert dec_code = "000" report "expected ACCEPT, got " & integer'image(to_integer(dec_code)) severity failure;
      for byte in 0 to (n + 7) / 8 - 1 loop
        tmsb := (others => '0'); tdib := (others => '0');
        for b in 0 to 7 loop
          if byte * 8 + b < n then
            if tms_s(tms_s'low + byte * 8 + b) = '1' then tmsb(b) := '1'; end if;
            if tdi_s(tdi_s'low + byte * 8 + b) = '1' then tdib(b) := '1'; end if;
          end if;
        end loop;
        vec_we <= '1'; vec_addr <= to_unsigned(byte, 11); vec_data <= tmsb;
        wait until rising_edge(clk);
        vec_addr <= to_unsigned(1024 + byte, 11); vec_data <= tdib;
        wait until rising_edge(clk);
      end loop;
      vec_we <= '0'; go <= '1';
      wait until rising_edge(clk);
      go <= '0';
      wait until rising_edge(clk) and dstb = '1';
      wait for 100 ns;
      assert rises - start_rises = n
        report "TCK rising edges " & integer'image(rises - start_rises) & " /= " & integer'image(n)
        severity failure;
      assert tck = '0' report "TCK not idle low" severity failure;
      -- collect TDO
      for byte in 0 to (n + 7) / 8 - 1 loop
        tdo_addr <= to_unsigned(byte, 10);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        for b in 0 to 7 loop
          if byte * 8 + b < n then
            if nb < 64 then
              tdo_bits(nb) := tdo_data(b);
            end if;
            nb := nb + 1;
          else
            assert tdo_data(b) = '0' report "unused TDO bit not zero" severity failure;
          end if;
        end loop;
      end loop;
    end procedure;

    function rep(c : character; n : natural) return string is
      variable s : string(1 to n) := (others => c);
    begin
      return s;
    end function;
  begin
    wait for 100 ns;
    -- reset (5x TMS=1), RTI, SELDR, CAPDR, SHDR: TMS 1111101 00 = to Shift-DR
    -- transaction 0: 9 bits of navigation + first 4 bits of IDCODE (13 bits)
    nb := 0;
    shift(0, "11111" & "0100" & "0000", rep('0', 13), 2);
    -- the first 9 TDO bits are not from Shift-DR; discard them
    nb := 0;
    tdo_bits := (others => '0');
    -- reuse: restart collection only for IDCODE bits. Re-run cleanly instead:
    shift(1, "11111" & "0100", rep('0', 9), 3);       -- back to Shift-DR
    nb := 0;
    shift(2, rep('0', 11), rep('0', 11), 2);          -- 11 bits
    shift(3, rep('0', 20) & "1", rep('0', 21), 5);    -- 21 bits, exit
    assert tdo_bits(31 downto 0) = IDCODE
      report "IDCODE read " & to_hstring(tdo_bits(31 downto 0)) severity failure;
    report "IDCODE via split shifts: " & to_hstring(tdo_bits(31 downto 0));

    -- duplicate of last completed -> cached, no clocks
    start_rises := rises;
    request(3, 21, 5);
    assert dec_code = "001" report "duplicate not cached" severity failure;
    -- stale / future sequence
    request(1, 8, 2);
    assert dec_code = "011" report "stale seq not rejected" severity failure;
    request(9, 8, 2);
    assert dec_code = "011" report "future seq not rejected" severity failure;
    -- bad format
    request(4, 0, 2);
    assert dec_code = "100" report "zero bits accepted" severity failure;
    request(4, 8193, 2);
    assert dec_code = "100" report "oversize accepted" severity failure;
    request(4, 8, 1);
    assert dec_code = "100" report "half=1 accepted" severity failure;
    -- unpowered
    powered <= '0';
    request(4, 8, 2);
    assert dec_code = "101" report "unpowered accepted" severity failure;
    powered <= '1';
    wait for 100 ns;
    assert rises = start_rises report "rejected requests clocked TCK" severity failure;

    -- busy: accept 4 (long), then repeat 4 while in flight
    request(4, 64, 50);
    assert dec_code = "000" severity failure;
    go <= '1'; wait until rising_edge(clk); go <= '0';
    request(4, 64, 50);
    assert dec_code = "010" report "in-flight duplicate not BUSY" severity failure;
    request(5, 8, 2);
    assert dec_code = "010" report "new seq while busy not BUSY" severity failure;
    wait until rising_edge(clk) and dstb = '1';
    assert nseq = 5 report "next_seq" severity failure;

    -- abort / session reset
    request(1000, 8, 2, '1');
    assert nseq = 1000 report "session reset" severity failure;

    -- maximum length transaction
    shift(1000, rep('0', 8192), rep('1', 8192), 2);

    report "tb_jtag_engine PASSED";
    done <= true;
    wait;
  end process;
end architecture;
