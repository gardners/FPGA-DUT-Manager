-- thumb_rx_writer: relay frames from thumb_rx_tap -> frame store (issue
-- 0038), clk_sys.
--
-- Each LINE starts a tile row of the sending machine in its buffer not
-- currently shown (not cur(m)); RUNs are expanded 4 pixels per 16-byte
-- word (xRGB32, mem_pkg layout) and written through the mem_pkg port. Lines
-- for this board's own machines are ignored (local thumbnails are stored
-- directly by thumb_capture, never through the network).
-- Per machine it tracks the picture being received (frame number low byte)
-- and its rows: a frame's rows count only when the whole frame was good
-- (END good). When the rows of a picture reach its height the buffer is
-- complete: ev pulses (machine, buffer, scale) and thumb_status flips. A
-- different frame number restarts the count (lost rows mean that picture is
-- never shown). Any good relay frame marks the machine seen.
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
    cur      : in  std_logic_vector(31 downto 0);
    mem_req  : out mem_req_t;
    mem_rsp  : in  mem_rsp_t;
    ev       : out std_logic;              -- a picture is complete
    ev_machine : out unsigned(4 downto 0);
    ev_buf   : out std_logic;
    ev_quarter : out std_logic;
    seen_ev  : out std_logic;              -- relay frame heard
    seen_machine : out unsigned(4 downto 0);
    pictures : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of thumb_rx_writer is
  type u8_arr is array (0 to 31) of unsigned(7 downto 0);
  signal rframe, rrows : u8_arr := (others => (others => '0'));
  signal tag : std_logic_vector(1 downto 0);
  signal ign : std_logic := '1';            -- current line not stored
  signal lm : unsigned(4 downto 0) := (others => '0');
  signal lbuf, lq : std_logic := '0';
  signal lrow : unsigned(7 downto 0) := (others => '0');
  signal w : unsigned(7 downto 0) := (others => '0');       -- word in the row
  signal nw : unsigned(7 downto 0) := (others => '0');      -- words per row (80 / 40)
  signal pos : unsigned(2 downto 0) := (others => '0');
  signal wbuf : std_logic_vector(127 downto 0) := (others => '0');
  signal rcnt : unsigned(7 downto 0) := (others => '0');
  signal rpx : std_logic_vector(23 downto 0) := (others => '0');
  signal wpend : std_logic := '0';
  -- frame (packet) state
  signal pk : std_logic := '0';
  signal pm : unsigned(4 downto 0) := (others => '0');
  signal pbuf, pq : std_logic := '0';
  signal pheight : unsigned(7 downto 0) := (others => '0');
  signal plines : unsigned(7 downto 0) := (others => '0');
  signal npic : unsigned(31 downto 0) := (others => '0');
  signal fin : std_logic := '0';
  signal fin_rows : unsigned(7 downto 0) := (others => '0');
  -- one-entry input register between the FIFO (block RAM output) and the
  -- decode (timing): e_v/e_d hold the next entry; it is refilled in the
  -- cycle it is consumed, so throughput stays one entry per cycle
  signal e_v  : std_logic := '0';
  signal e_d  : std_logic_vector(35 downto 0) := (others => '0');
  signal idle : std_logic;
  signal pop_i : std_logic;
begin
  tag <= e_d(35 downto 34);
  mem_req.valid <= wpend;
  mem_req.we    <= '1';
  mem_req.addr  <= thumb_addr(lm, lbuf, lrow, w(6 downto 0));
  mem_req.wdata <= wbuf;
  mem_req.wmask <= (others => '1');
  -- the entry in e_d is consumed when idle: no word waiting, no run being
  -- expanded; the FIFO is popped into e_d when it is empty or consumed
  idle  <= '1' when wpend = '0' and rcnt = 0 and fin = '0' else '0';
  pop_i <= f_valid and (not e_v or idle);
  f_pop <= pop_i;
  pictures <= npic;

  process (clk)
    variable m : unsigned(4 downto 0);
    variable f8 : unsigned(7 downto 0);
    variable take, k : natural range 0 to 4;
    variable np : unsigned(3 downto 0);
    variable c : natural range 0 to 255;
  begin
    if rising_edge(clk) then
      ev <= '0';
      seen_ev <= '0';
      if pop_i = '1' then
        e_v <= '1';
        e_d <= f_dout;
      elsif idle = '1' then
        e_v <= '0';
      end if;
      if fin = '1' then
        fin <= '0';
        seen_ev <= '1';
        seen_machine <= pm;
        if fin_rows >= pheight then
          ev <= '1'; ev_machine <= pm; ev_buf <= pbuf; ev_quarter <= pq;
          npic <= npic + 1;
          rrows(to_integer(pm)) <= (others => '0');
          rframe(to_integer(pm)) <= rframe(to_integer(pm)) + 1;   -- duplicates do not re-complete
        else
          rrows(to_integer(pm)) <= fin_rows;
        end if;
      elsif wpend = '1' then
        if mem_rsp.ready = '1' then
          wpend <= '0';
          w <= w + 1;
          if w + 1 = nw then
            plines <= plines + 1;    -- line complete
            ign <= '1';
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
      elsif e_v = '1' then
        case tag is
          when "00" =>                                    -- LINE
            m  := unsigned(e_d(29 downto 25));
            f8 := unsigned(e_d(16 downto 9));
            lm   <= m;
            lrow <= unsigned(e_d(24 downto 17));
            lq   <= e_d(8);
            w    <= (others => '0');
            pos  <= (others => '0');
            if e_d(8) = '1' then nw <= to_unsigned(40, 8); else nw <= to_unsigned(80, 8); end if;
            if m = local0 or m = local1 or (pk = '1' and m /= pm) then
              ign <= '1';
            else
              ign  <= '0';
              lbuf <= not cur(to_integer(m));
              if pk = '0' then
                pk <= '1'; pm <= m; pq <= e_d(8);
                pbuf <= not cur(to_integer(m));
                pheight <= unsigned(e_d(7 downto 0));
                plines <= (others => '0');
                if f8 /= rframe(to_integer(m)) then
                  rframe(to_integer(m)) <= f8;
                  rrows(to_integer(m)) <= (others => '0');
                end if;
              end if;
            end if;
          when "01" =>                                    -- RUN
            rcnt <= unsigned(e_d(31 downto 24));
            rpx  <= e_d(23 downto 0);
          when "10" =>                                    -- END
            -- rows are added in the next cycle (fin; timing)
            if pk = '1' and e_d(0) = '1' then
              fin <= '1';
              fin_rows <= rrows(to_integer(pm)) + plines;
            end if;
            pk <= '0';
            ign <= '1';
          when others =>                                  -- SEEN
            m := unsigned(e_d(4 downto 0));
            if m /= local0 and m /= local1 then
              seen_ev <= '1';
              seen_machine <= m;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
