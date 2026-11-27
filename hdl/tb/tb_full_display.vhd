-- tb_full_display: full-resolution relayed picture layer (issue 0060).
-- video_timing + full_display + text_display (editable screen) against
-- mem_model (latency 20, stalls). The full store (mem_pkg full_addr,
-- folded to 20 bits: buffer, row, word) holds pictures whose pixels encode
-- (buffer, row, column); whole frames are captured and checked:
--   A 720x480 in buffer 1: every pixel; shown = 1.
--   B 640x576 in buffer 2: raster line y shows row y + 48 (centre 480
--     lines), x >= 640 black; buf switched to 1 in the middle of the
--     checked frame: the whole frame stays buffer 2 (latched at vertical
--     blank, never torn).
--   C enable = '0': the text screen, no memory reads, layer off.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity tb_full_display is
end entity;

architecture tb of tb_full_display is
  signal clk_sys, clk_pix : std_logic := '0';
  signal done : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs, de_o, hs_o, vs_o, ft : std_logic;
  signal r, g, b, fr, fg, fbb : std_logic_vector(7 downto 0);
  signal f_on : std_logic;
  signal enable : std_logic := '0';
  signal buf_stim, buf_eff, shown : unsigned(1 downto 0) := "00";
  signal width : unsigned(10 downto 0) := (others => '0');
  signal height : unsigned(9 downto 0) := (others => '0');
  signal mid_flip : std_logic := '0';
  signal fv_req, tb_req, mm_req : mem_req_t := MEM_REQ_IDLE;
  signal mm_rsp : mem_rsp_t;
  signal sel_tb : std_logic := '1';
  type d_t is array (0 to 5) of unsigned(10 downto 0);
  signal xd, yd : d_t := (others => (others => '0'));
  signal go, ack, clr : std_logic := '0';
  signal scen : natural := 0;
  signal nreq : natural := 0;
  signal on_seen : std_logic := '0';

  function tpix(bf, row, col : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(row mod 256, 8)) & std_logic_vector(to_unsigned(col mod 256, 8))
         & std_logic_vector(to_unsigned(bf, 2)) & "00" & std_logic_vector(to_unsigned(row / 256, 2))
         & std_logic_vector(to_unsigned(col / 256, 2));
  end function;
  function fold(q : mem_req_t) return mem_req_t is
    variable o : mem_req_t := q;
  begin
    o.addr := (others => '0');
    o.addr(19 downto 0) := q.addr(19 downto 0);    -- buf(19:18) row(17:8) word(7:0)
    return o;
  end function;
begin
  clk_sys <= not clk_sys after 4 ns when not done;
  clk_pix <= not clk_pix after 18.5185 ns when not done;

  tim : entity work.video_timing port map (clk_pix, x, y, de, hs, vs, fs);
  buf_eff <= "01" when mid_flip = '1' else buf_stim;
  fv : entity work.full_display
    port map (clk_sys => clk_sys, mem_req => fv_req, mem_rsp => mm_rsp, enable => enable,
              buf => buf_eff, width => width, height => height, shown => shown,
              clk_pix => clk_pix, x => x, y => y, de => de, r => fr, g => fg, b => fbb,
              layer_on => f_on);
  txt : entity work.text_display
    generic map (LEFT => 15)
    port map (wr_clk => clk_pix, wr_en => '0', wr_addr => (others => '0'), wr_data => x"00",
              clk_pix => clk_pix, x => x, y => y, de_in => de, hs_in => hs, vs_in => vs,
              r => r, g => g, b => b, de_out => de_o, hs_out => hs_o, vs_out => vs_o,
              force_text => ft, screen => "00", slots => (others => '0'),
              full_on => f_on, full_r => fr, full_g => fg, full_b => fbb);
  mm_req <= fold(tb_req) when sel_tb = '1' else fold(fv_req);
  mem : entity work.mem_model
    generic map (ADDR_BITS => 20, LATENCY => 20, STALL_EVERY => 7)
    port map (clk => clk_sys, req => mm_req, rsp => mm_rsp);

  -- memory reads issued during the checked frame
  process (clk_sys)
    variable last_clr : std_logic := '0';
  begin
    if rising_edge(clk_sys) then
      if clr /= last_clr then
        last_clr := clr; nreq <= 0;
      elsif sel_tb = '0' and fv_req.valid = '1' and mm_rsp.ready = '1' then
        nreq <= nreq + 1;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- stimulus
  process
    procedure wr(a : unsigned; d : std_logic_vector(127 downto 0)) is
    begin
      tb_req <= ('1', '1', resize(a, MEM_AW), d, (others => '1'));
      loop
        wait until rising_edge(clk_sys);
        exit when mm_rsp.ready = '1';
      end loop;
      tb_req <= MEM_REQ_IDLE;
    end procedure;
    procedure fill(bf, rows, words : natural) is
      variable d : std_logic_vector(127 downto 0);
    begin
      for row in 0 to rows - 1 loop
        for w in 0 to words - 1 loop
          for i in 0 to 3 loop
            d(32 * i + 31 downto 32 * i) := x"00" & tpix(bf, row, 4 * w + i);
          end loop;
          wr(full_addr(to_unsigned(bf, 2), to_unsigned(row, 10), to_unsigned(w, 8)), d);
        end loop;
      end loop;
    end procedure;
    procedure check(s : natural) is
    begin
      scen <= s; go <= not go;
      wait until ack'event;
    end procedure;
  begin
    fill(1, 480, 180);
    fill(2, 576, 160);
    sel_tb <= '0';
    -- A: 720x480, buffer 1
    enable <= '1'; buf_stim <= "01"; width <= to_unsigned(720, 11); height <= to_unsigned(480, 10);
    check(1);
    assert shown = 1 report "A: shown buffer " & integer'image(to_integer(shown)) severity error;
    -- B: 640x576, buffer 2, switched to 1 in the middle of the checked frame
    buf_stim <= "10"; width <= to_unsigned(640, 11); height <= to_unsigned(576, 10);
    check(2);
    -- C: off
    enable <= '0';
    check(3);
    report "tb_full_display PASSED";
    done <= true;
    wait;
  end process;

  ---------------------------------------------------------------- capture + checks
  process (clk_pix)
    type line_t is array (0 to 719) of std_logic_vector(23 downto 0);
    type fb_t is array (0 to 479) of line_t;
    variable fbuf : fb_t;
    variable armed : natural := 0;
    variable last_go : std_logic := '0';
    variable errs : natural := 0;
    variable px, py : natural;

    procedure expect(ex, ey : natural; want : std_logic_vector(23 downto 0); what : string) is
    begin
      if fbuf(ey)(ex) /= want then
        errs := errs + 1;
        if errs < 20 then
          report what & " at (" & integer'image(ex) & "," & integer'image(ey) & "): got "
            & to_hstring(fbuf(ey)(ex)) & " want " & to_hstring(want) severity error;
        end if;
      end if;
    end procedure;

    procedure check_a is
    begin
      for yy in 0 to 479 loop
        for xx in 0 to 719 loop
          expect(xx, yy, tpix(1, yy, xx), "A");
        end loop;
      end loop;
    end procedure;
    procedure check_b is
    begin
      for yy in 0 to 479 loop
        for xx in 0 to 719 loop
          if xx < 640 then expect(xx, yy, tpix(2, yy + 48, xx), "B");
          else expect(xx, yy, x"000000", "B right of the picture"); end if;
        end loop;
      end loop;
    end procedure;
    procedure check_c is
    begin
      -- the text screen again: no picture pixels
      assert fbuf(200)(300) /= tpix(1, 200, 300) and fbuf(200)(300) /= tpix(2, 248, 300)
        report "C: picture still shown" severity error;
      assert on_seen = '0' report "C: layer on" severity error;
      assert nreq = 0 report "C: " & integer'image(nreq) & " reads with the layer off" severity error;
    end procedure;
  begin
    if rising_edge(clk_pix) then
      xd <= x & xd(0 to 4); yd <= y & yd(0 to 4);
      if go /= last_go then
        last_go := go; armed := 3;
      end if;
      if de_o = '1' then
        px := to_integer(xd(4)); py := to_integer(yd(4));   -- rgb registered 5 clocks after x
        fbuf(py)(px) := r & g & b;
        if armed = 1 and f_on = '1' then on_seen <= '1'; end if;
        -- B: switch the buffer in the middle of the checked frame
        if scen = 2 and armed = 1 and py = 240 then mid_flip <= '1'; end if;
        if px = 719 and py = 479 and armed > 0 then
          armed := armed - 1;
          if armed = 1 then clr <= not clr; on_seen <= '0'; end if;   -- the checked frame starts
          if armed = 0 then
            case scen is
              when 1 => check_a;
              when 2 => check_b;
              when others => check_c;
            end case;
            assert errs = 0 report "scenario " & integer'image(scen) & ": "
              & integer'image(errs) & " pixel errors" severity failure;
            report "scenario " & integer'image(scen) & " ok, " & integer'image(nreq) & " reads, shown "
              & integer'image(to_integer(shown));
            ack <= not ack;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
