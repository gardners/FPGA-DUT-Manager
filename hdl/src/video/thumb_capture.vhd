-- thumb_capture: HDMI IN -> box-filtered thumbnail -> frame store (issue 0035).
--
-- Pixel clock side (pclk):
--   * The centre CROP_W x CROP_H of the active picture (640x400: x offset
--     (h_active - 640)/2 = 40 at 720 wide, y offset (v_active - 400)/2 =
--     40 at 480p, 88 at 576p; offsets from the previous line/frame, 0 when
--     the picture is smaller) is averaged over S x S boxes: S = 2 gives a
--     320x200 tile, S = 4 (quarter = '1') 160x100 (owner, issue 0038).
--   * Every div-th frame is captured (div 2 = 30 Hz from 60 Hz).
--   * Horizontal sums per box go into a line buffer of vertical partial
--     sums (BRAM, 12 bits per channel); on the box's last line the average
--     is formed, packed 4 pixels per 16-byte word (xRGB32, pixel i in bits
--     32i+23..32i, mem_pkg layout) and pushed with its row/word into a
--     dual-clock FIFO, bracketed by START (scale) and END (rows, ok) tags.
--   * A tile row is only produced if the FIFO has room for all of it;
--     otherwise it is dropped and the frame marked bad (never shown).
--   * enable/quarter/div come from clk_sys (quasi-static; adopted when two
--     synchronised samples agree, at frame start).
--
-- clk_sys side: at START the frame is assigned to `machine` (when
-- machine_valid) and to its buffer not currently shown (not cur(machine));
-- if thumb_tx is reading that buffer (lock_*) the frame is skipped. WORDs
-- are written through the mem_pkg port (writes posted, backpressure by
-- rsp.ready). At END of a good frame `done` pulses with machine, buffer,
-- scale and row count: thumb_status then shows the new buffer.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity thumb_capture is
  generic (
    CROP_W  : positive := 640;
    CROP_H  : positive := 400;
    FIFO_AW : positive := 7
  );
  port (
    -- pixel clock domain
    pclk       : in  std_logic;
    de, vs     : in  std_logic;
    rgb        : in  std_logic_vector(23 downto 0);
    -- clk_sys domain
    clk        : in  std_logic;
    enable     : in  std_logic;                -- capture on (machine_valid and video locked)
    quarter    : in  std_logic;                -- 0: 1/2 scale (320x200), 1: 1/4 (160x100)
    div        : in  unsigned(3 downto 0);     -- capture every div-th frame (0 = 1)
    machine    : in  unsigned(4 downto 0);
    cur        : in  std_logic_vector(31 downto 0);   -- shown buffer per machine
    lock_valid : in  std_logic := '0';         -- thumb_tx is reading (lock_machine, lock_buf)
    lock_machine : in unsigned(4 downto 0) := (others => '0');
    lock_buf   : in  std_logic := '0';
    mem_req    : out mem_req_t;
    mem_rsp    : in  mem_rsp_t;
    done       : out std_logic;                -- one cycle: a frame is complete
    done_machine : out unsigned(4 downto 0);
    done_buf   : out std_logic;
    done_quarter : out std_logic;
    done_rows  : out unsigned(7 downto 0);
    frames     : out unsigned(31 downto 0);    -- frames completed
    skipped    : out unsigned(15 downto 0)     -- frames dropped (FIFO full, locked, bad)
  );
end entity;

architecture rtl of thumb_capture is
  constant DW : natural := 2 + 15 + 128;
  constant T_START : std_logic_vector(1 downto 0) := "01";
  constant T_WORD  : std_logic_vector(1 downto 0) := "10";
  constant T_END   : std_logic_vector(1 downto 0) := "11";

  ---------------------------------------------------------------- pclk
  signal cfg_s1, cfg_s2, cfg_s3, cfg_p : std_logic_vector(5 downto 0) := (others => '0');
  signal de_r, vs_r, de_d : std_logic := '0';
  signal rgb_r, rgb_d : std_logic_vector(23 downto 0) := (others => '0');
  signal vpol : std_logic := '0';
  signal vs_seen : std_logic := '0';
  signal cap : std_logic := '0';                -- this frame is captured
  signal start_pend : std_logic := '0';
  signal qtr : std_logic := '0';
  signal fdiv : unsigned(3 downto 0) := (others => '0');
  signal ok  : std_logic := '1';
  signal rows : unsigned(7 downto 0) := (others => '0');
  signal yc, vcnt, vprev, x0, y0 : unsigned(10 downto 0) := (others => '0');
  signal hcnt, hact : unsigned(10 downto 0) := (others => '0');
  signal x : unsigned(10 downto 0) := (others => '0');
  signal in_y, out_line, drop_line : std_logic := '0';
  signal ly : unsigned(1 downto 0) := (others => '0');
  signal row : unsigned(7 downto 0) := (others => '0');
  -- stage A
  type sum3_t is array (0 to 2) of unsigned(11 downto 0);
  signal hacc, hsum : sum3_t := (others => (others => '0'));
  signal hv : std_logic := '0';
  signal hcol : unsigned(8 downto 0) := (others => '0');
  -- line buffer of vertical partial sums
  signal lb_we : std_logic := '0';
  signal lb_wa, lb_ra : unsigned(8 downto 0) := (others => '0');
  signal lb_wd, lb_q : std_logic_vector(35 downto 0);
  -- stage C (packing)
  signal pv : std_logic := '0';
  signal ppx : std_logic_vector(23 downto 0) := (others => '0');
  signal pcol : unsigned(8 downto 0) := (others => '0');
  signal wbuf : std_logic_vector(127 downto 0) := (others => '0');
  -- FIFO
  signal f_we : std_logic := '0';
  signal f_din : std_logic_vector(DW - 1 downto 0) := (others => '0');
  signal f_used : unsigned(FIFO_AW downto 0);

  ---------------------------------------------------------------- clk_sys
  signal f_valid, f_pop : std_logic;
  signal f_dout : std_logic_vector(DW - 1 downto 0);
  signal act : std_logic := '0';
  signal am  : unsigned(4 downto 0) := (others => '0');
  signal ab, aq : std_logic := '0';
  signal frames_r : unsigned(31 downto 0) := (others => '0');
  signal skip_r : unsigned(15 downto 0) := (others => '0');
  signal tag : std_logic_vector(1 downto 0);
  signal info : std_logic_vector(14 downto 0);

  attribute ASYNC_REG : string;
  attribute ASYNC_REG of cfg_s1, cfg_s2 : signal is "TRUE";
begin
  lb : entity work.dpram generic map (9, 36)
    port map (clk_a => pclk, we_a => lb_we, addr_a => lb_wa, din_a => lb_wd,
              clk_b => pclk, addr_b => lb_ra, dout_b => lb_q);

  fifo : entity work.async_fifo generic map (FIFO_AW, DW)
    port map (wclk => pclk, we => f_we, din => f_din, wused => f_used,
              rclk => clk, rvalid => f_valid, dout => f_dout, pop => f_pop);

  ---------------------------------------------------------------- pclk side
  process (pclk)
    variable rise, vs_a, first, last, inx : boolean;
    variable yv, yrel, xrel : unsigned(10 downto 0);
    variable s : sum3_t;
    variable lxv : unsigned(1 downto 0);
    variable colv : unsigned(8 downto 0);
    variable acc : sum3_t;
    variable pxv : std_logic_vector(23 downto 0);
    variable wpr : natural;
  begin
    if rising_edge(pclk) then
      cfg_s1 <= enable & quarter & std_logic_vector(div);
      cfg_s2 <= cfg_s1;
      cfg_s3 <= cfg_s2;
      if cfg_s2 = cfg_s3 then cfg_p <= cfg_s3; end if;
      de_r <= de; vs_r <= vs; rgb_r <= rgb;
      de_d <= de_r;
      rgb_d <= rgb_r;
      f_we <= '0';
      lb_we <= '0';
      hv <= '0';
      pv <= '0';

      if de_r = '1' then vpol <= not vs_r; end if;
      vs_a := (vs_r xnor vpol) = '1';
      rise := de_r = '1' and de_d = '0';

      -- end of the frame: VSYNC after active lines. Close the captured
      -- frame, take the crop offset from this frame's line count and decide
      -- whether the next frame is captured (START goes out a cycle later).
      start_pend <= '0';
      if start_pend = '1' then
        f_we  <= '1';
        f_din <= T_START & (14 downto 1 => '0') & qtr & (127 downto 0 => '0');
      end if;
      if vs_a and vs_seen = '0' then
        vs_seen <= '1';
        if cap = '1' then
          f_we  <= '1';
          f_din <= T_END & "000000" & ok & std_logic_vector(rows) & (127 downto 0 => '0');
        end if;
        -- crop offset from the line count once two frames agree (a partial
        -- first frame must not shift the crop)
        vprev <= vcnt;
        if vcnt = vprev then
          if vcnt > CROP_H then y0 <= shift_right(vcnt - CROP_H, 1); else y0 <= (others => '0'); end if;
        end if;
        vcnt <= (others => '0');
        cap <= '0';
        if cfg_p(5) = '1' and fdiv = 0 then
          cap        <= '1';
          qtr        <= cfg_p(4);
          ok         <= '1';
          rows       <= (others => '0');
          start_pend <= '1';
        end if;
        if fdiv + 1 >= unsigned(cfg_p(3 downto 0)) then
          fdiv <= (others => '0');
        else
          fdiv <= fdiv + 1;
        end if;
      end if;

      -- active width of the previous line
      if de_r = '1' then
        hcnt <= hcnt + 1;
      elsif de_d = '1' then
        hact <= hcnt;
      end if;

      if rise then
        hcnt <= to_unsigned(1, 11);
        x <= (others => '0');
        if hact > CROP_W then x0 <= shift_right(hact - CROP_W, 1); else x0 <= (others => '0'); end if;
        if vs_seen = '1' then
          vs_seen <= '0';
          yv := (others => '0');
        else
          yv := yc + 1;
        end if;
        yc   <= yv;
        vcnt <= vcnt + 1;
        -- tile row of this line
        yrel := yv - y0;
        in_y <= '0'; out_line <= '0'; drop_line <= '0';
        if cap = '1' and yrel < CROP_H then
          in_y <= '1';
          if qtr = '1' then
            ly <= yrel(1 downto 0); row <= resize(yrel(9 downto 2), 8);
          else
            ly <= '0' & yrel(0);    row <= yrel(8 downto 1);
          end if;
          if (qtr = '1' and yrel(1 downto 0) = "11") or (qtr = '0' and yrel(0) = '1') then
            -- the box's last line produces a tile row: room for all of it?
            out_line <= '1';
            if f_used > 2 ** FIFO_AW - (CROP_W / 8 + 4) then
              drop_line <= '1';
              ok <= '0';
            end if;
          end if;
        end if;
      elsif de_r = '1' then
        x <= x + 1;
      end if;

      -- stage A: horizontal box sums
      -- (one cycle behind the input: in_y/x0 of this line are registered)
      if de_d = '1' then
        xrel := x - x0;
        inx := in_y = '1' and xrel < CROP_W;
        if qtr = '1' then
          lxv := xrel(1 downto 0); colv := resize(xrel(9 downto 2), 9);
          last := lxv = "11";
        else
          lxv := '0' & xrel(0); colv := xrel(9 downto 1);
          last := lxv(0) = '1';
        end if;
        first := lxv = "00";
        for c in 0 to 2 loop
          if first then
            s(c) := resize(unsigned(rgb_d(23 - 8 * c downto 16 - 8 * c)), 12);
          else
            s(c) := hacc(c) + unsigned(rgb_d(23 - 8 * c downto 16 - 8 * c));
          end if;
        end loop;
        hacc <= s;
        if inx and first then
          lb_ra <= colv;
        end if;
        if inx and last then
          hv   <= '1';
          hcol <= colv;
          hsum <= s;
        end if;
      end if;

      -- stage B: vertical sums through the line buffer
      if hv = '1' then
        for c in 0 to 2 loop
          if ly = 0 then
            acc(c) := hsum(c);
          else
            acc(c) := unsigned(lb_q(35 - 12 * c downto 24 - 12 * c)) + hsum(c);
          end if;
        end loop;
        if (qtr = '1' and ly = 3) or (qtr = '0' and ly = 1) then
          for c in 0 to 2 loop
            if qtr = '1' then
              pxv(23 - 8 * c downto 16 - 8 * c) := std_logic_vector(acc(c)(11 downto 4));
            else
              pxv(23 - 8 * c downto 16 - 8 * c) := std_logic_vector(acc(c)(9 downto 2));
            end if;
          end loop;
          if drop_line = '0' and cap = '1' then
            pv   <= '1';
            ppx  <= pxv;
            pcol <= hcol;
          end if;
        else
          lb_we <= '1';
          lb_wa <= hcol;
          lb_wd <= std_logic_vector(acc(0)) & std_logic_vector(acc(1)) & std_logic_vector(acc(2));
        end if;
      end if;

      -- stage C: pack 4 pixels per word, push the word
      if pv = '1' then
        wpr := to_integer(pcol(1 downto 0));
        wbuf(32 * wpr + 31 downto 32 * wpr) <= x"00" & ppx;
        if pcol(1 downto 0) = "11" then
          f_we  <= '1';
          f_din <= T_WORD & std_logic_vector(row) & std_logic_vector(pcol(8 downto 2)) &
                   x"00" & ppx & wbuf(95 downto 0);
          rows  <= row + 1;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- clk_sys side
  tag  <= f_dout(DW - 1 downto DW - 2);
  info <= f_dout(142 downto 128);
  mem_req.valid <= '1' when f_valid = '1' and tag = T_WORD and act = '1' else '0';
  mem_req.we    <= '1';
  mem_req.addr  <= thumb_addr(am, ab, unsigned(info(14 downto 7)), unsigned(info(6 downto 0)));
  mem_req.wdata <= f_dout(127 downto 0);
  mem_req.wmask <= (others => '1');
  f_pop <= '1' when f_valid = '1' and (tag /= T_WORD or act = '0' or mem_rsp.ready = '1') else '0';
  frames  <= frames_r;
  skipped <= skip_r;

  process (clk)
    variable b : std_logic;
  begin
    if rising_edge(clk) then
      done <= '0';
      if f_valid = '1' then
        case tag is
          when T_START =>
            b := not cur(to_integer(machine));
            if act = '1' then
              skip_r <= skip_r + 1;          -- previous frame lost its END
            end if;
            if enable = '1' and not (lock_valid = '1' and lock_machine = machine and lock_buf = b) then
              act <= '1';
              am  <= machine;
              ab  <= b;
              aq  <= info(0);
            else
              act <= '0';
              skip_r <= skip_r + 1;
            end if;
          when T_END =>
            if act = '1' then
              if info(8) = '1' and unsigned(info(7 downto 0)) /= 0 then
                done         <= '1';
                done_machine <= am;
                done_buf     <= ab;
                done_quarter <= aq;
                done_rows    <= unsigned(info(7 downto 0));
                frames_r     <= frames_r + 1;
              else
                skip_r <= skip_r + 1;
              end if;
            end if;
            act <= '0';
          when others => null;
        end case;
      end if;
    end if;
  end process;
end architecture;
