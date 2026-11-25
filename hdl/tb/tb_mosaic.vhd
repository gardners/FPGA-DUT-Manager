-- tb_mosaic: live-thumbnail select screen (issue 0036). video_timing +
-- mosaic_display + text_display (LEFT 15 as on the board) against mem_model
-- (latency 20, stalls). The frame store is filled with pixels that encode
-- (machine, buffer, row, column); whole frames are captured and checked:
--   A 4x3 layout (machines 0..7 seen, 9 local): thumbnails at 160x100 incl.
--     every pixel of two tiles and the corners of four, the second buffer,
--     colour bars (seen not fresh; fresh with mismatched scale), frown
--     (empty slot), black spare tiles, corner boxes in LED colours, text rows
--   B 2x2 layout (machines 0, 1, 3): 320x200 thumbnails (every pixel), frown,
--     bars for a scale mismatch, no RAM text, LED green not keyed
--   C fallback (enable = '0'): old boxes-only screen, no memory traffic.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity tb_mosaic is
end entity;

architecture tb of tb_mosaic is
  signal clk_sys, clk_pix : std_logic := '0';
  signal done : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs, de_o, hs_o, vs_o, ft : std_logic;
  signal r, g, b, mr, mg, mb : std_logic_vector(7 downto 0);
  signal m_on, m_quad : std_logic;
  signal enable : std_logic := '0';
  signal slots : std_logic_vector(9 downto 0) := (others => '0');
  signal seen, fresh, cur_buf, scale : std_logic_vector(31 downto 0) := (others => '0');
  signal tslots : std_logic_vector(9 downto 0);
  signal mos_req, tb_req, mm_req : mem_req_t := MEM_REQ_IDLE;
  signal mm_rsp : mem_rsp_t;
  signal sel_tb : std_logic := '1';
  type d_t is array (0 to 5) of unsigned(10 downto 0);
  signal xd, yd : d_t := (others => (others => '0'));
  signal go, ack, clr : std_logic := '0';
  signal scen : natural := 0;
  signal nreq : natural := 0;

  function tpix(m, bf, row, col : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(2 * m + bf, 8)) & std_logic_vector(to_unsigned(row, 8))
         & std_logic_vector(to_unsigned(col mod 256, 8));
  end function;
begin
  clk_sys <= not clk_sys after 4 ns when not done;
  clk_pix <= not clk_pix after 18.5185 ns when not done;

  tim : entity work.video_timing port map (clk_pix, x, y, de, hs, vs, fs);
  mos : entity work.mosaic_display
    port map (clk_sys => clk_sys, mem_req => mos_req, mem_rsp => mm_rsp, enable => enable,
              slots => slots, seen => seen, fresh => fresh, cur_buf => cur_buf, scale => scale,
              clk_pix => clk_pix, x => x, y => y, de => de, r => mr, g => mg, b => mb,
              mos_on => m_on, mos_quad => m_quad);
  tslots <= slots or seen(9 downto 0);
  txt : entity work.text_display
    generic map (LEFT => 15)
    port map (wr_clk => clk_pix, wr_en => '0', wr_addr => (others => '0'), wr_data => x"00",
              clk_pix => clk_pix, x => x, y => y, de_in => de, hs_in => hs, vs_in => vs,
              r => r, g => g, b => b, de_out => de_o, hs_out => hs_o, vs_out => vs_o,
              force_text => ft, screen => "10", slots => tslots,
              mos_on => m_on, mos_quad => m_quad, mos_r => mr, mos_g => mg, mos_b => mb);
  mm_req <= tb_req when sel_tb = '1' else mos_req;
  mem : entity work.mem_model
    generic map (ADDR_BITS => 19, LATENCY => 20, STALL_EVERY => 7)
    port map (clk => clk_sys, req => mm_req, rsp => mm_rsp);

  -- memory reads issued by the mosaic during the checked frame
  process (clk_sys)
    variable last_clr : std_logic := '0';
  begin
    if rising_edge(clk_sys) then
      if clr /= last_clr then
        last_clr := clr; nreq <= 0;
      elsif sel_tb = '0' and mos_req.valid = '1' and mm_rsp.ready = '1' then
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
    procedure fill(m, bf, rows, words : natural) is
      variable d : std_logic_vector(127 downto 0);
    begin
      for row in 0 to rows - 1 loop
        for w in 0 to words - 1 loop
          for i in 0 to 3 loop
            d(32 * i + 31 downto 32 * i) := x"00" & tpix(m, bf, row, 4 * w + i);
          end loop;
          wr(thumb_addr(to_unsigned(m, 5), std_logic(to_unsigned(bf, 1)(0)),
                        to_unsigned(row, 8), to_unsigned(w, 7)), d);
        end loop;
      end loop;
    end procedure;
    procedure check(s : natural) is
    begin
      scen <= s; go <= not go;
      wait until ack'event;
    end procedure;
  begin
    -- frame store (ADDR_BITS 19: buffers (2m+b) mod 16 must differ)
    fill(0, 0, 200, 80);
    fill(1, 1, 200, 80);
    fill(5, 0, 100, 40);
    fill(9, 0, 100, 40);
    sel_tb <= '0';

    -- A: 4x3
    enable  <= '1';
    slots   <= "1000000000";             -- machine 9 local
    seen    <= x"000000FF";
    fresh   <= x"00000227";              -- 0 1 2 5 9
    scale   <= x"FFFFFFFB";              -- machine 2 stored at 320x200 -> bars
    cur_buf <= x"00000002";              -- machine 1 shows buffer 1
    check(1);
    -- B: 2x2
    slots   <= (others => '0');
    seen    <= x"0000000B";              -- 0 1 3
    fresh   <= x"0000000B";
    scale   <= x"00000008";              -- machine 3 still quarter scale -> bars
    check(2);
    -- C: fallback (DDR3 not calibrated)
    enable  <= '0';
    check(3);
    report "tb_mosaic PASSED";
    done <= true;
    wait;
  end process;

  ---------------------------------------------------------------- capture + checks
  process (clk_pix)
    type line_t is array (0 to 719) of std_logic_vector(23 downto 0);
    type fb_t is array (0 to 479) of line_t;
    variable fb : fb_t;
    variable armed : natural := 0;
    variable last_go : std_logic := '0';
    variable errs : natural := 0;
    variable px, py : natural;

    procedure expect(ex, ey : natural; want : std_logic_vector(23 downto 0); what : string) is
    begin
      if fb(ey)(ex) /= want then
        errs := errs + 1;
        if errs < 20 then
          report what & " at (" & integer'image(ex) & "," & integer'image(ey) & "): got "
            & to_hstring(fb(ey)(ex)) & " want " & to_hstring(want) severity error;
        end if;
      end if;
    end procedure;
    -- every pixel of a tile (raster x0, y0, w x h) except the box cells
    procedure tile(x0, y0, w, h, m, bf, bx0, bx1, by0, by1 : natural; what : string) is
    begin
      for v in 0 to h - 1 loop
        for u in 0 to w - 1 loop
          if not (x0 + u >= bx0 and x0 + u <= bx1 and y0 + v >= by0 and y0 + v <= by1) then
            expect(x0 + u, y0 + v, tpix(m, bf, v, u), what);
          end if;
        end loop;
      end loop;
    end procedure;
    procedure corners(x0, y0, w, h, m, bf : natural; what : string) is
    begin
      expect(x0 + w - 1, y0, tpix(m, bf, 0, w - 1), what & " top right");
      expect(x0, y0 + h - 1, tpix(m, bf, h - 1, 0), what & " bottom left");
      expect(x0 + w - 1, y0 + h - 1, tpix(m, bf, h - 1, w - 1), what & " bottom right");
    end procedure;
    impure function count(c : std_logic_vector(23 downto 0); x0, x1, y0, y1 : natural) return natural is
      variable n : natural := 0;
    begin
      for yy in y0 to y1 loop
        for xx in x0 to x1 loop
          if fb(yy)(xx) = c then n := n + 1; end if;
        end loop;
      end loop;
      return n;
    end function;

    procedure check_a is
    begin
      -- machine 0 (tile 0,0): whole tile; box cells x 42..68, y 104..119
      tile(40, 90, 160, 100, 0, 0, 42, 68, 104, 119, "4x3 machine 0");
      expect(40, 90, tpix(0, 0, 0, 0), "4x3 machine 0 top left");
      expect(43, 105, x"FF0000", "4x3 box 1 red");
      expect(54, 109, x"000000", "4x3 box 1 digit");
      -- machine 1, buffer 1
      corners(200, 90, 160, 100, 1, 1, "4x3 machine 1");
      expect(200, 90, tpix(1, 1, 0, 0), "4x3 machine 1 top left");
      expect(205, 105, x"FF6000", "4x3 box 2 orange");
      -- machine 5 (tile 1,1), whole tile; box x 204..230, y 200..215
      tile(200, 190, 160, 100, 5, 0, 204, 230, 200, 215, "4x3 machine 5");
      expect(205, 201, x"A000FF", "4x3 box 6 purple");
      -- machine 9 (tile 1,2)
      corners(200, 290, 160, 100, 9, 0, "4x3 machine 9");
      expect(205, 297, x"7F6000", "4x3 box 0 half yellow");
      -- machine 2: fresh but stored at 320x200 -> bars (tile 2,0, x 360..519)
      expect(370, 150, x"C0C0C0", "bars white");
      expect(390, 150, x"C0C000", "bars yellow");
      expect(460, 150, x"C000C0", "bars magenta");
      expect(519, 150, x"0000C0", "bars blue");
      -- machine 3: seen, not fresh (tile 3,0, x 520..679)
      expect(600, 150, x"00C000", "bars green (not keyed)");
      -- machine 8: empty -> frown (tile 0,2, x 40..199, y 290..389)
      expect(109, 317, x"A0A0A0", "frown pixel");
      expect(105, 317, x"303030", "frown background next to it");
      expect(150, 370, x"303030", "frown tile background");
      -- spare tiles 10, 11 and outside the block
      expect(450, 350, x"000000", "spare tile 10");
      expect(600, 350, x"000000", "spare tile 11");
      expect(20, 200, x"000000", "left of the block");
      expect(700, 200, x"000000", "right of the block");
      -- text: title in row 1, hint in row 23, rows 2 and 22 empty
      assert count(x"FFFFFF", 0, 719, 56, 71) > 100 report "4x3: no title text" severity error;
      assert count(x"FFFFFF", 0, 719, 408, 423) > 100 report "4x3: no hint text" severity error;
      assert count(x"000000", 0, 719, 72, 87) = 720 * 16 report "4x3: row 2 not empty" severity error;
      assert count(x"000000", 0, 719, 392, 407) = 720 * 16 report "4x3: row 22 not empty" severity error;
    end procedure;

    procedure check_b is
    begin
      -- machine 0 tile (40..359, 40..239), box x 42..68, y 40..55
      tile(40, 40, 320, 200, 0, 0, 42, 68, 40, 55, "2x2 machine 0");
      -- machine 1, buffer 1 (360..679), box x 366..392
      tile(360, 40, 320, 200, 1, 1, 366, 392, 40, 55, "2x2 machine 1");
      expect(43, 41, x"FF0000", "2x2 box 1 red");
      expect(367, 41, x"FF6000", "2x2 box 2 orange");
      expect(367, 249, x"00FE00", "2x2 box 4 LED green, not keyed");
      -- machine 2 empty: frown (40..359, 240..439)
      expect(180, 295, x"A0A0A0", "2x2 frown pixel");
      expect(170, 295, x"303030", "2x2 frown background");
      -- machine 3: fresh at quarter scale while 2x2 -> bars
      expect(370, 300, x"C0C0C0", "2x2 bars white");
      expect(660, 300, x"0000C0", "2x2 bars blue");
      -- no RAM text at all (title, hint, footer would be white)
      assert count(x"FFFFFF", 0, 719, 0, 479) = 0 report "2x2: RAM text shown" severity error;
      expect(20, 300, x"000000", "2x2 left of the block");
    end procedure;

    procedure check_c is
    begin
      expect(60, 216, x"FF0000", "fallback box 1 (old position)");
      expect(100, 60, x"000000", "fallback background");
      expect(43, 105, x"000000", "fallback: no mosaic box");
      expect(200, 300, x"000000", "fallback: no thumbnail");
      assert nreq = 0 report "fallback: mosaic issued " & integer'image(nreq) & " reads" severity error;
    end procedure;
  begin
    if rising_edge(clk_pix) then
      xd <= x & xd(0 to 4); yd <= y & yd(0 to 4);
      if go /= last_go then
        last_go := go; armed := 3;
      end if;
      if de_o = '1' then
        px := to_integer(xd(4)); py := to_integer(yd(4));   -- rgb registered 5 clocks after x
        fb(py)(px) := r & g & b;
        if px = 719 and py = 479 and armed > 0 then
          armed := armed - 1;
          if armed = 1 then clr <= not clr; end if;   -- the checked frame starts
          if armed = 0 then
            case scen is
              when 1 => check_a;
              when 2 => check_b;
              when others => check_c;
            end case;
            assert errs = 0 report "scenario " & integer'image(scen) & ": "
              & integer'image(errs) & " pixel errors" severity failure;
            report "scenario " & integer'image(scen) & " ok, " & integer'image(nreq) & " reads";
            ack <= not ack;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
