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
    full_ev     : out std_logic;
    full_buf    : out unsigned(1 downto 0);
    full_width  : out unsigned(10 downto 0);
    full_height : out unsigned(9 downto 0);
    full_pics   : out unsigned(15 downto 0)
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
  signal wpend : std_logic := '0';
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
  -- one-entry input register between the FIFO (block RAM output) and the
  -- decode (timing): e_v/e_d hold the next entry; it is refilled in the
  -- cycle it is consumed, so throughput stays one entry per cycle
  signal e_v  : std_logic := '0';
  signal e_d  : std_logic_vector(35 downto 0) := (others => '0');
  signal idle, flush : std_logic;
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
  mem_req.valid <= wpend;
  mem_req.we    <= '1';
  mem_req.addr  <= full_addr(fr_w, lrow, w) when lfull = '1' else
                   thumb_addr(lm, lbuf, lrow(7 downto 0), w(6 downto 0));
  mem_req.wdata <= wbuf;
  mem_req.wmask <= (others => '1');
  -- a 1/1 line ending inside a word: write the partial word before the
  -- next LINE / END is taken
  flush <= '1' when e_v = '1' and (tag = "00" or tag = "10") and pos /= 0 and ign = '0' and
                    lfull = '1' else '0';
  -- the entry in e_d is consumed when idle: no word waiting, no run being
  -- expanded; the FIFO is popped into e_d when it is empty or consumed
  idle  <= '1' when wpend = '0' and rcnt = 0 and fin = '0' and flush = '0' else '0';
  pop_i <= f_valid and (not e_v or idle);
  f_pop <= pop_i;
  pictures <= npic;
  full_ev <= fr_ev;
  full_buf <= fr_ready;
  full_width <= fr_width;
  full_height <= fr_height;
  full_pics <= fr_pics;

  process (clk)
    variable m : unsigned(4 downto 0);
    variable f7 : unsigned(6 downto 0);
    variable take, k : natural range 0 to 4;
    variable np : unsigned(3 downto 0);
    variable c : natural range 0 to 255;
    variable isfull, acc, mine : boolean;
  begin
    if rising_edge(clk) then
      ev <= '0';
      seen_ev <= '0';
      fr_ev <= '0';
      if full_en = '0' then fr_valid <= '0'; end if;
      if pop_i = '1' then
        e_v <= '1';
        e_d <= f_dout;
      elsif idle = '1' then
        e_v <= '0';
      end if;
      if fin = '1' then
        fin <= '0';
        if pfull = '1' then
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
      elsif wpend = '1' then
        if mem_rsp.ready = '1' then
          wpend <= '0';
          w <= w + 1;
          if w + 1 = nw then
            if lfull = '0' then plines <= plines + 1; end if;   -- thumbnail line complete
            ign <= '1';                                        -- (1/1: width cap)
          end if;
        end if;
      elsif rcnt /= 0 then
        -- expand the run into the word being built
        c := to_integer(rcnt);
        take := 4 - to_integer(pos);
        if c < take then take := c; end if;
        for i in 0 to 3 loop
          if i >= to_integer(pos) and i < to_integer(pos) + take then
            wbuf(32 * i + 31 downto 32 * i) <= x"00" & rpx;
          end if;
        end loop;
        rcnt <= rcnt - take;
        np := resize(pos, 4) + take;
        if np = 4 then
          pos <= (others => '0');
          if ign = '0' and w < nw then wpend <= '1'; end if;
        else
          pos <= np(2 downto 0);
        end if;
      elsif flush = '1' then
        wpend <= '1';
        pos   <= (others => '0');
      elsif e_v = '1' then
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
                    fr_w     <= pick(full_shown, fr_ready);
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
          when "01" =>                                    -- RUN
            rcnt <= unsigned(e_d(31 downto 24));
            rpx  <= e_d(23 downto 0);
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
