-- thumb_rx_writer: relay frames from thumb_rx_tap -> frame store (issues
-- 0038, 0060), clk_sys.
--
-- Thumbnails (scales 1/2, 1/4): each LINE starts a tile row of the sending
-- machine in its buffer not currently shown (not cur(m)); RUNs are expanded
-- 4 pixels per 16-byte word (xRGB32, mem_pkg layout) and written through
-- the mem_pkg port. Lines for this board's own machines are ignored when
-- that machine has local video (relay0/relay1 = '0'): local thumbnails are
-- stored directly by thumb_capture, never through the network. A local
-- machine without local video (relay_i = '1', issue 0060) takes relayed
-- frames like a remote one.
-- Per machine it tracks the picture being received (frame number low 7
-- bits) and its rows: a frame's rows count only when the whole frame was
-- good (END good). When the rows of a picture reach its height the buffer
-- is complete: ev pulses (machine, buffer, scale) and thumb_status flips. A
-- different frame number restarts the count (lost rows mean that picture is
-- never shown). Any good relay frame marks the machine seen.
--
-- Full resolution (scale 3 = 1/1, issue 0060): only for machine full_m
-- while full_en. Pictures go into one of three buffers (mem_pkg full_addr):
-- a new picture takes the buffer that is neither shown (full_shown, from
-- the display) nor the last complete one (full_buf), so the display never
-- reads a buffer being written. Lines may be any width up to FULL_MAX_W; a
-- partial last word is written before the next LINE / END. When a
-- picture's rows reach its height, full_buf := that buffer and full_ev
-- pulses (full_width / full_height describe it).
--
-- Live view (full_live = '1', key 0x0045 = 1, issue 0060 relay-rx-speed):
-- lines go into the buffer the display shows (full_buf, kept for every new
-- picture), so each good frame shows up at once; rows of a picture that
-- never arrive keep the previous picture. full_ev pulses at every good 1/1
-- frame (the view stays fresh while lines arrive) and full_width/height
-- follow the last one; full_pics still counts complete pictures (all rows
-- of one frame number). Pixels of a frame are written as they arrive, so a
-- frame that later turns out bad (FCS) can leave wrong pixels in the live
-- view until its rows arrive again; with full_live = '0' that frame only
-- lands in a buffer that is never shown.
--
-- Throughput (issue 0060 relay-rx-speed): a RUN entry is expanded in the
-- cycle it is taken (RAW888: one pixel per clk cycle, 125 Mpx/s against the
-- 41.7 Mpx/s a gigabit link can carry), finished 16-byte words go with
-- their address into a 512-word FIFO, and the memory port is offered words
-- in batches (once 16 are waiting, or the oldest has waited 64 cycles)
-- until the FIFO is empty, so mem_arbiter's bursts keep them together. A
-- picture is reported complete (full_ev / ev) when its last entry is taken;
-- up to the FIFO's contents (a few us of DDR3 time) are still being
-- written then.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity thumb_rx_writer is
  port (
    clk      : in  std_logic;
    f_valid  : in  std_logic;
    f_dout   : in  std_logic_vector(35 downto 0);
    f_pop    : out std_logic;
    local0, local1 : in unsigned(4 downto 0);
    relay0, relay1 : in std_logic := '0';   -- local machine i takes relayed video
    cur      : in  std_logic_vector(31 downto 0);
    mem_req  : out mem_req_t;
    mem_rsp  : in  mem_rsp_t;
    ev       : out std_logic;              -- a picture is complete
    ev_machine : out unsigned(4 downto 0);
    ev_buf   : out std_logic;
    ev_quarter : out std_logic;
    seen_ev  : out std_logic;              -- relay frame heard
    seen_machine : out unsigned(4 downto 0);
    pictures : out unsigned(31 downto 0);
    -- full-resolution relayed picture (issue 0060)
    full_en     : in  std_logic := '0';
    full_m      : in  unsigned(4 downto 0) := (others => '0');
    full_shown  : in  unsigned(1 downto 0) := "00";
    full_live   : in  std_logic := '0';     -- key 0x0045: 1 = live line-by-line view
    full_ev     : out std_logic;
    full_buf    : out unsigned(1 downto 0);
    full_width  : out unsigned(10 downto 0);
    full_height : out unsigned(9 downto 0);
    full_pics   : out unsigned(15 downto 0);
    -- good lines frames none of whose lines were taken (a machine this
    -- board does not accept: its own with local video, or a 1/1 frame not
    -- for the full view; issue 0061)
    foreign     : out unsigned(15 downto 0);
    -- memory back-pressure (relay-rx-speed), wrapping, units of 256 clk
    -- cycles (2.048 us): stall = pixels to store but the word FIFO full;
    -- mwait = a word offered and the memory port not ready. wf_hwm = the
    -- word FIFO's peak fill / 2 in the window ending at the last win pulse
    win         : in  std_logic := '0';
    stall       : out unsigned(15 downto 0);
    mwait       : out unsigned(15 downto 0);
    wf_hwm      : out unsigned(7 downto 0)
  );
end entity;

architecture rtl of thumb_rx_writer is
  type u8_arr is array (0 to 31) of unsigned(7 downto 0);
  signal rframe, rrows : u8_arr := (others => (others => '0'));
  signal tag : std_logic_vector(1 downto 0);
  signal ign : std_logic := '1';            -- current line not stored
  signal lfull : std_logic := '0';          -- current line is a 1/1 line
  signal lm : unsigned(4 downto 0) := (others => '0');
  signal lbuf, lq : std_logic := '0';
  signal lrow : unsigned(9 downto 0) := (others => '0');
  signal w : unsigned(7 downto 0) := (others => '0');       -- word in the row
  signal nw : unsigned(7 downto 0) := (others => '0');      -- words per row (80 / 40 / 255 cap)
  signal pos : unsigned(2 downto 0) := (others => '0');
  signal wbuf : std_logic_vector(127 downto 0) := (others => '0');
  signal rcnt : unsigned(7 downto 0) := (others => '0');
  signal rpx : std_logic_vector(23 downto 0) := (others => '0');
  -- finished words (address & data) on their way to the memory port
  constant WF_AW : natural := 9;
  constant BATCH : natural := 16;
  signal wf_we : std_logic := '0';
  signal wf_din : std_logic_vector(MEM_AW + 127 downto 0) := (others => '0');
  signal wf_used : unsigned(WF_AW downto 0);
  signal wf_valid, wf_pop : std_logic;
  signal wf_dout : std_logic_vector(MEM_AW + 127 downto 0);
  signal wf_room : std_logic := '1';
  signal go : std_logic := '0';
  signal age : unsigned(5 downto 0) := (others => '0');
  -- frame (packet) state
  signal pk : std_logic := '0';
  signal pfull : std_logic := '0';
  signal pm : unsigned(4 downto 0) := (others => '0');
  signal pbuf, pq : std_logic := '0';
  signal pheight : unsigned(9 downto 0) := (others => '0');
  signal plines : unsigned(9 downto 0) := (others => '0');
  signal npic : unsigned(31 downto 0) := (others => '0');
  signal fin : std_logic := '0';
  signal fin_rows : unsigned(9 downto 0) := (others => '0');
  signal fin_w : unsigned(10 downto 0) := (others => '0');
  -- full-resolution picture
  signal fr_valid : std_logic := '0';       -- a picture is being received
  signal fr_frame : unsigned(6 downto 0) := (others => '0');
  signal fr_rows : unsigned(9 downto 0) := (others => '0');
  signal fr_w : unsigned(1 downto 0) := "01";   -- buffer being written
  signal fr_ready : unsigned(1 downto 0) := "00";
  signal fr_width : unsigned(10 downto 0) := (others => '0');
  signal fr_height : unsigned(9 downto 0) := (others => '0');
  signal fr_ev : std_logic := '0';
  signal fr_pics : unsigned(15 downto 0) := (others => '0');
  signal nforeign : unsigned(15 downto 0) := (others => '0');
  -- one-entry input register between the FIFO (block RAM output) and the
  -- decode (timing): e_v/e_d hold the next entry; it is refilled in the
  -- cycle it is consumed, so throughput stays one entry per cycle
  signal e_v  : std_logic := '0';
  signal e_d  : std_logic_vector(35 downto 0) := (others => '0');
  signal take_e, flush : std_logic;
  signal st_c, mw_c : unsigned(23 downto 0) := (others => '0');
  signal wf_pk : unsigned(WF_AW downto 0) := (others => '0');
  signal wf_ho : unsigned(7 downto 0) := (others => '0');
  signal pop_i : std_logic;

  -- the buffer for a new full picture: neither shown nor the last complete one
  function pick(shown, ready : unsigned(1 downto 0)) return unsigned is
  begin
    for b in 0 to 2 loop
      if to_unsigned(b, 2) /= shown and to_unsigned(b, 2) /= ready then
        return to_unsigned(b, 2);
      end if;
    end loop;
    return "00";
  end function;
begin
  tag <= e_d(35 downto 34);
  -- memory port: words from the FIFO, offered in batches (go)
  wfifo : entity work.async_fifo_bram generic map (WF_AW, MEM_AW + 128)
    port map (wclk => clk, we => wf_we, din => wf_din, wused => wf_used,
              rclk => clk, rvalid => wf_valid, dout => wf_dout, pop => wf_pop);
  mem_req.valid <= wf_valid and go;
  mem_req.we    <= '1';
  mem_req.addr  <= unsigned(wf_dout(MEM_AW + 127 downto 128));
  mem_req.wdata <= wf_dout(127 downto 0);
  mem_req.wmask <= (others => '1');
  wf_pop <= wf_valid and go and mem_rsp.ready;
  -- a 1/1 line ending inside a word: write the partial word before the
  -- next LINE / END is taken
  flush <= '1' when e_v = '1' and (tag = "00" or tag = "10") and pos /= 0 and ign = '0' and
                    lfull = '1' else '0';
  -- the entry in e_d is taken when no run is being expanded, no picture is
  -- being finished, no partial word is waiting and (a RUN, which may finish
  -- a word) there is room for a word; the FIFO is popped into e_d when it
  -- is empty or taken
  take_e <= '1' when e_v = '1' and rcnt = 0 and fin = '0' and flush = '0' and
                     (tag /= "01" or wf_room = '1') else '0';
  pop_i <= f_valid and (not e_v or take_e);
  f_pop <= pop_i;
  pictures <= npic;
  full_ev <= fr_ev;
  full_buf <= fr_ready;
  full_width <= fr_width;
  full_height <= fr_height;
  full_pics <= fr_pics;
  foreign <= nforeign;
  stall <= st_c(23 downto 8);
  mwait <= mw_c(23 downto 8);
  wf_hwm <= wf_ho;

  process (clk)
  begin
    if rising_edge(clk) then
      if wf_room = '0' and (rcnt /= 0 or flush = '1' or
                            (e_v = '1' and fin = '0' and tag = "01")) then
        st_c <= st_c + 1;
      end if;
      if wf_valid = '1' and go = '1' and mem_rsp.ready = '0' then mw_c <= mw_c + 1; end if;
      if win = '1' then
        if wf_pk < 512 then wf_ho <= resize(shift_right(wf_pk, 1), 8); else wf_ho <= x"FF"; end if;
        wf_pk <= wf_used;
      elsif wf_used > wf_pk then
        wf_pk <= wf_used;
      end if;
    end if;
  end process;

  process (clk)
    variable m : unsigned(4 downto 0);
    variable f7 : unsigned(6 downto 0);
    variable take, k : natural range 0 to 4;
    variable np : unsigned(3 downto 0);
    variable c : natural range 0 to 255;
    variable isfull, acc, mine : boolean;
    variable wb : std_logic_vector(127 downto 0);
    variable ex : boolean;
    variable xc : unsigned(7 downto 0);
    variable xp : std_logic_vector(23 downto 0);

    -- push the word wd at the current address (w) and move to the next word
    procedure push(wd : std_logic_vector(127 downto 0)) is
    begin
      wf_we <= '1';
      if lfull = '1' then
        wf_din <= std_logic_vector(full_addr(fr_w, lrow, w)) & wd;
      else
        wf_din <= std_logic_vector(thumb_addr(lm, lbuf, lrow(7 downto 0), w(6 downto 0))) & wd;
      end if;
      w <= w + 1;
      if w + 1 = nw then
        if lfull = '0' then plines <= plines + 1; end if;   -- thumbnail line complete
        ign <= '1';                                        -- (1/1: width cap)
      end if;
    end procedure;
  begin
    if rising_edge(clk) then
      ev <= '0';
      seen_ev <= '0';
      fr_ev <= '0';
      wf_we <= '0';
      if wf_used < 2 ** WF_AW - 8 then wf_room <= '1'; else wf_room <= '0'; end if;
      -- batches: start when BATCH words wait or the oldest waited 64 cycles,
      -- run until the FIFO is empty
      if go = '0' then
        if wf_valid = '1' then age <= age + 1; else age <= (others => '0'); end if;
        if wf_used >= BATCH or (wf_valid = '1' and age = 63) then go <= '1'; end if;
      elsif wf_valid = '0' then
        go <= '0';
        age <= (others => '0');
      end if;
      if full_en = '0' then fr_valid <= '0'; end if;
      if pop_i = '1' then
        e_v <= '1';
        e_d <= f_dout;
      elsif take_e = '1' then
        e_v <= '0';
      end if;
      if fin = '1' then
        fin <= '0';
        if pfull = '1' then
          if full_live = '1' then
            -- live view: every good frame is shown (the buffer is the shown one)
            fr_ev <= '1';
            fr_ready <= fr_w;
            fr_width <= fin_w;
            fr_height <= pheight;
          end if;
          if fin_rows >= pheight then
            fr_ev <= '1';
            fr_ready <= fr_w;
            fr_width <= fin_w;
            fr_height <= pheight;
            fr_pics <= fr_pics + 1;
            fr_valid <= '0';               -- the next frame starts a new picture
          else
            fr_rows <= fin_rows;
          end if;
        else
          seen_ev <= '1';
          seen_machine <= pm;
          if fin_rows(7 downto 0) >= pheight(7 downto 0) then
            ev <= '1'; ev_machine <= pm; ev_buf <= pbuf; ev_quarter <= pq;
            npic <= npic + 1;
            rrows(to_integer(pm)) <= (others => '0');
            rframe(to_integer(pm)) <= rframe(to_integer(pm)) + 1;   -- duplicates do not re-complete
          else
            rrows(to_integer(pm)) <= fin_rows(7 downto 0);
          end if;
        end if;
      else
        -- expand a run: the one being expanded, else a RUN entry being taken
        ex := false;
        if rcnt /= 0 then
          if wf_room = '1' then ex := true; xc := rcnt; xp := rpx; end if;
        elsif take_e = '1' and tag = "01" then
          ex := true; xc := unsigned(e_d(31 downto 24)); xp := e_d(23 downto 0);
          rpx <= e_d(23 downto 0);
        end if;
        if ex then
          c := to_integer(xc);
          take := 4 - to_integer(pos);
          if c < take then take := c; end if;
          wb := wbuf;
          for i in 0 to 3 loop
            if i >= to_integer(pos) and i < to_integer(pos) + take then
              wb(32 * i + 31 downto 32 * i) := x"00" & xp;
            end if;
          end loop;
          wbuf <= wb;
          rcnt <= xc - take;
          np := resize(pos, 4) + take;
          if np = 4 then
            pos <= (others => '0');
            if ign = '0' and w < nw then push(wb); end if;
          else
            pos <= np(2 downto 0);
          end if;
        elsif flush = '1' then
          if wf_room = '1' then
            push(wbuf);
            pos <= (others => '0');
          end if;
        end if;
      end if;
      if fin = '0' and take_e = '1' and tag /= "01" then
        case tag is
          when "00" =>                                    -- LINE
            m  := unsigned(e_d(31 downto 27));
            f7 := unsigned(e_d(16 downto 10));
            isfull := e_d(33 downto 32) = "10";
            if isfull then
              acc := full_en = '1' and m = full_m and (pk = '0' or (pfull = '1' and m = pm));
            else
              mine := (m = local0 and relay0 = '0') or (m = local1 and relay1 = '0');
              acc := not mine and (pk = '0' or (pfull = '0' and m = pm));
            end if;
            lm   <= m;
            lrow <= unsigned(e_d(26 downto 17));
            w    <= (others => '0');
            pos  <= (others => '0');
            if isfull then
              lfull <= '1';
              nw <= to_unsigned(FULL_MAX_W / 4, 8);
            else
              lfull <= '0';
              lq <= e_d(32);
              if e_d(32) = '1' then nw <= to_unsigned(40, 8); else nw <= to_unsigned(80, 8); end if;
            end if;
            if not acc then
              ign <= '1';
            else
              ign  <= '0';
              lbuf <= not cur(to_integer(m));
              if pk = '0' then
                pk <= '1'; pm <= m; pq <= e_d(32);
                pbuf <= not cur(to_integer(m));
                pheight <= unsigned(e_d(9 downto 0));
                if isfull then
                  pfull <= '1';
                  plines <= to_unsigned(1, 10);
                  if fr_valid = '0' or f7 /= fr_frame then
                    -- a new full picture
                    fr_valid <= '1';
                    fr_frame <= f7;
                    fr_rows  <= (others => '0');
                    if full_live = '1' then
                      fr_w <= fr_ready;          -- live: into the shown buffer
                    else
                      fr_w <= pick(full_shown, fr_ready);
                    end if;
                  end if;
                else
                  pfull <= '0';
                  plines <= (others => '0');
                  if ('0' & f7) /= rframe(to_integer(m)) then
                    rframe(to_integer(m)) <= '0' & f7;
                    rrows(to_integer(m)) <= (others => '0');
                  end if;
                end if;
              elsif isfull then
                plines <= plines + 1;
              end if;
            end if;
          when "01" =>                                    -- RUN (expanded above)
            null;
          when "10" =>                                    -- END
            -- rows are added in the next cycle (fin; timing)
            if pk = '1' and e_d(0) = '1' then
              fin <= '1';
              fin_w <= unsigned(e_d(11 downto 1));
              if pfull = '1' then
                fin_rows <= fr_rows + plines;
              else
                fin_rows <= resize(rrows(to_integer(pm)), 10) + plines;
              end if;
            end if;
            if pk = '0' and e_d(0) = '1' then nforeign <= nforeign + 1; end if;
            pk <= '0';
            ign <= '1';
          when others =>                                  -- SEEN
            m := unsigned(e_d(4 downto 0));
            if not ((m = local0 and relay0 = '0') or (m = local1 and relay1 = '0')) then
              seen_ev <= '1';
              seen_machine <= m;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
