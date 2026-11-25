-- tb_hdmi_tx: dvi_tx_xc7 with HDMI => true (issue 0037). Recovers the
-- 10-bit symbols from the serial lanes (clock lane for framing) and walks the
-- HDMI period structure:
--   * every control period before a preamble is >= 12 chars and the preamble
--     is exactly 8 chars of one CTL pattern (video 1000 / data island 1010);
--   * video: exactly 2 video guard band chars, then exactly H_ACTIVE pixels
--     whose values are unchanged (r = x, g = x + 85, b = not x, x from 0);
--   * data island: 2 leading guard chars, 32 TERC4 chars (channel-0 bit 3
--     low on the first char only), 2 trailing guard chars, then control;
--   * the packet's header and subpacket ECC (own BCH model) and the
--     InfoFrame checksum.
-- Each packet goes to CAP_OUT (36 hex bytes: HB0-2, ECC, 4 x (7 bytes, ECC))
-- for tests/scenarios/tb_hdmi_tx.py, which checks the ECC again by polynomial
-- division and the AVI/SPD contents. The SPD machine field is changed
-- during the run: M03, then none, then M27.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.hdmi_framer_pkg.all;

entity tb_hdmi_tx is
  generic (VEC_IN : string := "tb_hdmi_tx_in.txt"; CAP_OUT : string := "tb_hdmi_tx_out.txt");
end entity;

architecture tb of tb_hdmi_tx is
  constant TPIX : time := 37.037 ns;
  constant H_ACTIVE : natural := 64;
  constant FRAME_CHARS : natural := (64 + 8 + 40 + 24) * (8 + 1 + 2 + 2);
  signal clk_pix, clk5 : std_logic := '0';
  signal done : boolean := false;
  signal rst : std_logic := '1';
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal r, g, b : std_logic_vector(7 downto 0);
  signal tdp, tdn : std_logic_vector(2 downto 0);
  signal cp, cn : std_logic;
  signal machine : unsigned(4 downto 0) := to_unsigned(3, 5);
  signal machine_ok : std_logic := '1';

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

  -- control token -> c (0..3), -1 if not a control token
  function ctl(q : std_logic_vector(9 downto 0)) return integer is
  begin
    case q is
      when "1101010100" => return 0;
      when "0010101011" => return 1;
      when "0101010100" => return 2;
      when "1010101011" => return 3;
      when others => return -1;
    end case;
  end function;

  type terc_t is array (0 to 15) of std_logic_vector(9 downto 0);
  constant TERC4 : terc_t := (
    "1010011100", "1001100011", "1011100100", "1011100010",
    "0101110001", "0100011110", "0110001110", "0100111100",
    "1011001100", "0100111001", "0110011100", "1011000110",
    "1010001110", "1001110001", "0101100011", "1011000011");
  function terc(q : std_logic_vector(9 downto 0)) return integer is
  begin
    for i in 0 to 15 loop
      if TERC4(i) = q then return i; end if;
    end loop;
    return -1;
  end function;

  function hex2(v : std_logic_vector(7 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789ABCDEF";
  begin
    return H(to_integer(unsigned(v(7 downto 4))) + 1) & H(to_integer(unsigned(v(3 downto 0))) + 1);
  end function;
begin
  clk_pix <= not clk_pix after TPIX / 2 when not done;
  clk5    <= not clk5 after TPIX / 10 when not done;

  tim : entity work.video_timing
    generic map (H_ACTIVE => H_ACTIVE, H_FP => 8, H_SYNC => 40, H_BP => 24,
                 V_ACTIVE => 8, V_FP => 1, V_SYNC => 2, V_BP => 2)
    port map (clk_pix, x, y, de, hs, vs, fs);
  r <= std_logic_vector(x(7 downto 0));
  g <= std_logic_vector(x(7 downto 0) + 85);
  b <= std_logic_vector(not x(7 downto 0));

  dut : entity work.dvi_tx_xc7 generic map (SIM => true, HDMI => true)
    port map (pixel_clk => clk_pix, serial_clk => clk5, rst => rst,
              r => r, g => g, b => b, hs => hs, vs => vs, de => de,
              vic => "0000011", machine => machine, machine_ok => machine_ok,
              tmds_p => tdp, tmds_n => tdn, tmds_clk_p => cp, tmds_clk_n => cn);

  rst <= '0' after 200 ns;

  -- SPD machine field: M03 for ~4 frames, then none, then M27
  stim : process
  begin
    wait for 4 * FRAME_CHARS * TPIX;
    machine_ok <= '0';
    wait for 3 * FRAME_CHARS * TPIX;
    machine <= to_unsigned(27, 5); machine_ok <= '1';
    wait;
  end process;

  check : process
    type bits_t is array (0 to 3) of std_logic_vector(9 downto 0);
    variable sh : bits_t := (others => (others => '0'));
    variable nbits : natural := 0;
    variable synced : boolean := false;
    variable lane : std_logic_vector(3 downto 0);
    variable q0, q1, q2 : std_logic_vector(9 downto 0);
    variable c0, c1, c2 : integer;
    type st_t is (S_CTL, S_VGB, S_VID, S_DGB1, S_DATA, S_DGB2, S_END);
    variable st : st_t := S_CTL;
    variable cnt, run, pre_len, pre_pat, last_pat : integer := 0;
    variable px, lines, pkts, errors : natural := 0;
    variable want : unsigned(7 downto 0);
    variable seen_ctl : boolean := false;
    -- packet assembly
    variable hdr : std_logic_vector(31 downto 0);
    type sub_t is array (0 to 3) of std_logic_vector(63 downto 0);
    variable sub : sub_t;
    variable t0, t1, t2 : integer;
    variable ecc : std_logic_vector(7 downto 0);
    variable sum : unsigned(7 downto 0);
    variable l : line;
    file fout : text;
    variable started, prev_data : boolean := false;

    procedure fail(msg : string) is
    begin
      report msg severity error;
      errors := errors + 1;
    end procedure;
  begin
    file_open(fout, CAP_OUT, write_mode);
    wait for 2 us;
    for n in 0 to 10 * 9 * FRAME_CHARS loop
      wait until clk5'event;
      wait for TPIX / 20;
      lane := cp & tdp;
      for i in 0 to 3 loop
        sh(i) := lane(i) & sh(i)(9 downto 1);   -- LSB first
      end loop;
      nbits := nbits + 1;
      if not synced then
        if sh(3) = "0000011111" then synced := true; nbits := 0; end if;
      elsif nbits = 10 then
        nbits := 0;
        assert sh(3) = "0000011111" report "clock lane lost framing" severity failure;
        q0 := sh(0); q1 := sh(1); q2 := sh(2);
        c0 := ctl(q0); c1 := ctl(q1); c2 := ctl(q2);
        -- start checking at the first control char after a non-control one
        if not started then
          if c0 >= 0 and c1 >= 0 and c2 >= 0 then
            if prev_data then
              started := true; run := 1; last_pat := c1 + 4 * c2; pre_len := 1;
            end if;
          else
            prev_data := true;
          end if;
        else
          case st is
            when S_CTL =>
              if c0 >= 0 and c1 >= 0 and c2 >= 0 then
                run := run + 1;
                if c1 + 4 * c2 = last_pat then
                  pre_len := pre_len + 1;
                else
                  last_pat := c1 + 4 * c2;
                  pre_len := 1;
                end if;
              else
                -- leaving the control period: check its preamble
                if last_pat = 1 then          -- CTL0..3 = 1000: video
                  st := S_VGB;
                elsif last_pat = 5 then       -- CTL0..3 = 1010: data island
                  st := S_DGB1;
                else
                  fail("period without preamble (pattern " & integer'image(last_pat) & ")");
                  st := S_END;
                end if;
                if pre_len /= 8 then fail("preamble length " & integer'image(pre_len)); end if;
                if run < 12 then fail("control period " & integer'image(run) & " chars"); end if;
                cnt := 0;
              end if;
            when others => null;
          end case;
          -- states that consume the current (non-control) char
          case st is
            when S_VGB =>
              if q0 /= "1011001100" or q1 /= "0100110011" or q2 /= "1011001100" then
                fail("bad video guard band");
              end if;
              cnt := cnt + 1;
              if cnt = 2 then st := S_VID; cnt := 0; end if;
            when S_VID =>
              if c0 >= 0 and c1 >= 0 and c2 >= 0 then
                if cnt /= H_ACTIVE then fail("line of " & integer'image(cnt) & " pixels"); end if;
                lines := lines + 1;
                st := S_CTL; run := 1; last_pat := c1 + 4 * c2; pre_len := 1;
              else
                want := to_unsigned(cnt, 8);
                if decode(q2) /= std_logic_vector(want) or
                   decode(q1) /= std_logic_vector(want + 85) or
                   decode(q0) /= std_logic_vector(not want) then
                  fail("pixel " & integer'image(cnt) & " changed");
                end if;
                cnt := cnt + 1;
                px := px + 1;
              end if;
            when S_DGB1 | S_DGB2 =>
              t0 := terc(q0);
              if q1 /= "0100110011" or q2 /= "0100110011" or t0 < 12 then
                fail("bad data island guard band");
              end if;
              cnt := cnt + 1;
              if cnt = 2 then
                cnt := 0;
                if st = S_DGB1 then st := S_DATA; else st := S_END; end if;
              end if;
            when S_DATA =>
              t0 := terc(q0); t1 := terc(q1); t2 := terc(q2);
              if t0 < 0 or t1 < 0 or t2 < 0 then
                fail("non-TERC4 char in data island");
                t0 := 0; t1 := 0; t2 := 0;
              end if;
              if (cnt = 0) = (t0 >= 8) then fail("channel 0 bit 3 wrong at char " & integer'image(cnt)); end if;
              hdr(cnt) := to_unsigned(t0, 4)(2);
              for i in 0 to 3 loop
                sub(i)(2 * cnt)     := to_unsigned(t1, 4)(i);
                sub(i)(2 * cnt + 1) := to_unsigned(t2, 4)(i);
              end loop;
              cnt := cnt + 1;
              if cnt = 32 then
                cnt := 0; st := S_DGB2; pkts := pkts + 1;
                ecc := x"00";
                for k in 0 to 23 loop ecc := bch_step(ecc, hdr(k)); end loop;
                if ecc /= hdr(31 downto 24) then fail("header ECC"); end if;
                sum := unsigned(hdr(7 downto 0)) + unsigned(hdr(15 downto 8)) + unsigned(hdr(23 downto 16));
                for i in 0 to 3 loop
                  ecc := x"00";
                  for k in 0 to 55 loop ecc := bch_step(ecc, sub(i)(k)); end loop;
                  if ecc /= sub(i)(63 downto 56) then fail("subpacket " & integer'image(i) & " ECC"); end if;
                  for k in 0 to 6 loop sum := sum + unsigned(sub(i)(8 * k + 7 downto 8 * k)); end loop;
                end loop;
                if sum /= 0 then fail("InfoFrame checksum"); end if;
                write(l, string'("PKT"));
                for k in 0 to 3 loop write(l, " " & hex2(hdr(8 * k + 7 downto 8 * k))); end loop;
                for i in 0 to 3 loop
                  for k in 0 to 7 loop write(l, " " & hex2(sub(i)(8 * k + 7 downto 8 * k))); end loop;
                end loop;
                writeline(fout, l);
              end if;
            when S_END =>
              if c0 >= 0 and c1 >= 0 and c2 >= 0 then
                st := S_CTL; run := 1; last_pat := c1 + 4 * c2; pre_len := 1;
              else
                fail("no control period after data island");
                st := S_CTL; run := 0; last_pat := -1; pre_len := 0;
              end if;
            when S_CTL => null;
          end case;
        end if;
      end if;
    end loop;
    write(l, "STAT lines=" & integer'image(lines) & " pixels=" & integer'image(px) &
          " packets=" & integer'image(pkts) & " errors=" & integer'image(errors));
    writeline(fout, l);
    file_close(fout);
    report "decoded " & integer'image(lines) & " lines, " & integer'image(px) & " pixels, " &
      integer'image(pkts) & " packets, " & integer'image(errors) & " errors";
    assert errors = 0 and lines > 50 and pkts >= 16 report "HDMI decode failed" severity failure;
    report "tb_hdmi_tx PASSED";
    done <= true;
    wait;
  end process;
end architecture;
