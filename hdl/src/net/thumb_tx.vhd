-- thumb_tx: thumbnail relay sender and scale/rate policy (issue 0038, ADR
-- 0005 s10), clk_sys.
--
-- Policy (owner, 2026-11-25):
--   * While this board's console shows the select screen it is a requester:
--     every 250 ms it asks net_tx to broadcast a request carrying the scale
--     it wants (1/2 with <= 4 machines seen, else 1/4) and divisor 2.
--   * Streaming destination: the forced MAC (management key 0x0041) when
--     set, else the source MAC of the latest request heard in the last
--     second (latest wins). Never a group (multicast/broadcast) MAC.
--   * Scale and divisor in effect (also for the local capture): own choice
--     while requesting, else the forced key's, else the latest request's,
--     else 1/2 and 2.
-- While streaming, every complete local picture (thumb_capture done) is sent:
-- its buffer is locked against the capture writer, each tile row is read
-- (mem_pkg port) into a line buffer, scanned for its RLE24 size, and packed
-- into the packet buffer as RLE24 when strictly smaller than RAW888, else
-- RAW888. Lines share a frame while the encoding is the same and the payload
-- stays within TH_PKT_BUDGET; net_tx copies each closed frame from the packet
-- buffer (pkt_valid ... pkt_taken). A picture arriving while one is being
-- sent replaces the pending one (latest wins). Local machines without a
-- picture in the last second send "present, no source" once a second.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;
use work.thumb_pkg.all;

entity thumb_tx is
  generic (MS_PER_S : positive := 1000);   -- shortened in simulation
  port (
    clk        : in  std_logic;
    tick_1ms   : in  std_logic;
    local0, local1 : in unsigned(4 downto 0);
    selecting  : in  std_logic;            -- own console on the select screen
    n_seen     : in  unsigned(5 downto 0);
    force_mac  : in  std_logic_vector(47 downto 0);   -- 0 = off
    force_scale: in  std_logic_vector(7 downto 0);
    force_div  : in  std_logic_vector(7 downto 0);
    req_stb    : in  std_logic;
    req_mac    : in  std_logic_vector(47 downto 0);
    req_scale  : in  std_logic_vector(7 downto 0);
    req_div    : in  std_logic_vector(7 downto 0);
    -- local capture
    cap_done   : in  std_logic;
    cap_machine: in  unsigned(4 downto 0);
    cap_buf    : in  std_logic;
    cap_quarter: in  std_logic;
    cap_rows   : in  unsigned(7 downto 0);
    eff_quarter: out std_logic;
    eff_div    : out unsigned(3 downto 0);
    lock_valid : out std_logic;
    lock_machine : out unsigned(4 downto 0);
    lock_buf   : out std_logic;
    -- frame store
    mem_req    : out mem_req_t;
    mem_rsp    : in  mem_rsp_t;
    -- net_tx
    pkt_valid  : out std_logic;
    pkt        : out thumb_pkt_t;
    pkt_taken  : in  std_logic;
    pb_raddr   : in  unsigned(12 downto 0);
    pb_rdata   : out std_logic_vector(7 downto 0);
    treq_valid : out std_logic;            -- broadcast a request (endpoint 0)
    treq_scale : out std_logic_vector(7 downto 0);
    treq_div   : out std_logic_vector(7 downto 0);
    treq_taken : in  std_logic;
    streaming  : out std_logic;
    pictures   : out unsigned(31 downto 0)  -- pictures sent
  );
end entity;

architecture rtl of thumb_tx is
  -- policy
  signal rq_mac : std_logic_vector(47 downto 0) := (others => '0');
  signal rq_q : std_logic := '0';
  signal rq_div : unsigned(3 downto 0) := to_unsigned(2, 4);
  signal rq_age : unsigned(11 downto 0) := (others => '1');
  signal dst : std_logic_vector(47 downto 0) := (others => '0');
  signal strm : std_logic := '0';
  signal q_eff : std_logic := '0';
  signal div_eff : unsigned(3 downto 0) := to_unsigned(2, 4);
  signal own_q : std_logic := '0';
  signal t250 : unsigned(11 downto 0) := (others => '0');
  signal treq_r : std_logic := '0';
  signal t1s : unsigned(11 downto 0) := (others => '0');
  type age2_t is array (0 to 1) of unsigned(11 downto 0);
  signal lf_age : age2_t := (others => (others => '1'));
  signal nos_due : std_logic_vector(1 downto 0) := "00";
  -- pending picture
  signal pend : std_logic := '0';
  signal pm : unsigned(4 downto 0) := (others => '0');
  signal pbf, pq : std_logic := '0';
  signal prows : unsigned(7 downto 0) := (others => '0');
  -- sending
  type st_t is (S_IDLE, S_FETCH, S_SCAN, S_DECIDE, S_EMIT, S_CLOSE, S_WAIT);
  signal st : st_t := S_IDLE;
  signal sm : unsigned(4 downto 0) := (others => '0');
  signal sb, sq : std_logic := '0';
  signal sd : integer range 0 to 1 := 0;
  signal srows, row : unsigned(7 downto 0) := (others => '0');
  signal frame : unsigned(31 downto 0) := (others => '0');
  signal lock_r : std_logic := '0';
  signal nw : unsigned(7 downto 0) := (others => '0');       -- words per row
  signal width : unsigned(8 downto 0) := (others => '0');
  signal ra_w, rcount : unsigned(7 downto 0) := (others => '0');
  signal rd_on : std_logic := '0';
  -- line buffer
  signal lb_we : std_logic := '0';
  signal lb_wa, lb_ra : unsigned(6 downto 0) := (others => '0');
  signal lb_wd, lb_q : std_logic_vector(127 downto 0);
  -- pixel walker
  type wk_t is (K_B, K_C, K_E);
  signal wk : wk_t := K_B;
  signal emit : std_logic := '0';            -- 0 scan, 1 emit
  signal p : unsigned(8 downto 0) := (others => '0');
  signal run_px : std_logic_vector(23 downto 0) := (others => '0');
  signal run_n : unsigned(7 downto 0) := (others => '0');
  signal runs : unsigned(9 downto 0) := (others => '0');
  signal t_cnt : unsigned(7 downto 0) := (others => '0');
  signal t_px : std_logic_vector(23 downto 0) := (others => '0');
  signal t_n : integer range 0 to 4 := 0;     -- bytes left to emit
  signal t_last : std_logic := '0';           -- line done after this emission
  signal enc_line : std_logic := '0';         -- 1 = RLE24
  signal lsize : unsigned(12 downto 0) := (others => '0');
  -- packet
  signal pk_open : std_logic := '0';
  signal pk_enc : std_logic := '0';
  signal pk_row : unsigned(7 downto 0) := (others => '0');
  signal pk_n : unsigned(7 downto 0) := (others => '0');
  signal pb_ptr : unsigned(12 downto 0) := (others => '0');
  signal pb_we : std_logic := '0';
  signal pb_wa : unsigned(12 downto 0) := (others => '0');
  signal pb_wd : std_logic_vector(7 downto 0) := (others => '0');
  signal pv : std_logic := '0';
  signal pk_r : thumb_pkt_t := THUMB_PKT_NONE;
  signal last_pkt : std_logic := '0';
  signal nos_i : integer range 0 to 1 := 0;
  signal npic : unsigned(31 downto 0) := (others => '0');
  signal mreq : mem_req_t := MEM_REQ_IDLE;

  function rgb_byte(px : std_logic_vector(23 downto 0); i : natural) return std_logic_vector is
  begin
    return px(23 - 8 * i downto 16 - 8 * i);
  end function;
begin
  lb : entity work.dpram generic map (7, 128)
    port map (clk_a => clk, we_a => lb_we, addr_a => lb_wa, din_a => lb_wd,
              clk_b => clk, addr_b => lb_ra, dout_b => lb_q);
  pbuf : entity work.dpram generic map (13, 8)
    port map (clk_a => clk, we_a => pb_we, addr_a => pb_wa, din_a => pb_wd,
              clk_b => clk, addr_b => pb_raddr, dout_b => pb_rdata);

  eff_quarter <= q_eff;
  eff_div     <= div_eff;
  lock_valid  <= lock_r;
  lock_machine <= sm;
  lock_buf    <= sb;
  pkt_valid   <= pv;
  pkt         <= pk_r;
  treq_valid  <= treq_r;
  treq_scale  <= x"02" when own_q = '1' else x"01";
  treq_div    <= x"02";
  streaming   <= strm;
  pictures    <= npic;
  mem_req     <= mreq;

  ---------------------------------------------------------------- policy
  process (clk)
    variable fm : boolean;
  begin
    if rising_edge(clk) then
      if n_seen > 4 then own_q <= '1'; else own_q <= '0'; end if;
      fm := force_mac /= x"000000000000" and force_mac(40) = '0';
      if req_stb = '1' then
        rq_mac <= req_mac;
        if req_scale = x"02" then rq_q <= '1'; else rq_q <= '0'; end if;
        if unsigned(req_div) = 0 or unsigned(req_div) > 15 then
          rq_div <= to_unsigned(1, 4);
        else
          rq_div <= unsigned(req_div(3 downto 0));
        end if;
        rq_age <= (others => '0');
      elsif tick_1ms = '1' and rq_age /= x"FFF" then
        rq_age <= rq_age + 1;
      end if;
      -- destination (unicast only)
      strm <= '0';
      if fm then
        dst <= force_mac; strm <= '1';
      elsif rq_age < MS_PER_S and rq_mac(40) = '0' and rq_mac /= x"000000000000" then
        dst <= rq_mac; strm <= '1';
      end if;
      -- scale and divisor in effect
      if selecting = '1' then
        q_eff <= own_q; div_eff <= to_unsigned(2, 4);
      elsif fm then
        if force_scale = x"02" then q_eff <= '1'; else q_eff <= '0'; end if;
        if unsigned(force_div) = 0 or unsigned(force_div) > 15 then
          div_eff <= to_unsigned(1, 4);
        else
          div_eff <= unsigned(force_div(3 downto 0));
        end if;
      elsif rq_age < MS_PER_S then
        q_eff <= rq_q; div_eff <= rq_div;
      else
        q_eff <= '0'; div_eff <= to_unsigned(2, 4);
      end if;
      -- requests every 250 ms while selecting
      if treq_taken = '1' then treq_r <= '0'; end if;
      if tick_1ms = '1' then
        if t250 + 1 >= MS_PER_S / 4 then
          t250 <= (others => '0');
          if selecting = '1' then treq_r <= '1'; end if;
        else
          t250 <= t250 + 1;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------- sender
  process (clk)
    variable px : std_logic_vector(23 downto 0);
    variable flush : boolean;
    variable sz : unsigned(12 downto 0);
    variable b : natural range 0 to 3;
  begin
    if rising_edge(clk) then
      lb_we <= '0';
      pb_we <= '0';
      if pkt_taken = '1' then pv <= '0'; end if;

      -- local pictures and "present, no source" timers
      for i in 0 to 1 loop
        if tick_1ms = '1' and lf_age(i) /= x"FFF" then lf_age(i) <= lf_age(i) + 1; end if;
      end loop;
      if cap_done = '1' then
        if cap_machine = local0 then lf_age(0) <= (others => '0'); end if;
        if cap_machine = local1 then lf_age(1) <= (others => '0'); end if;
        if strm = '1' then
          pend <= '1'; pm <= cap_machine; pbf <= cap_buf; pq <= cap_quarter; prows <= cap_rows;
        end if;
      end if;
      if tick_1ms = '1' then
        if t1s + 1 >= MS_PER_S then
          t1s <= (others => '0');
          for i in 0 to 1 loop
            if strm = '1' and lf_age(i) >= MS_PER_S then nos_due(i) <= '1'; end if;
          end loop;
        else
          t1s <= t1s + 1;
        end if;
      end if;
      if strm = '0' then pend <= '0'; nos_due <= "00"; end if;

      -- frame store reads for one tile row
      if mreq.valid = '1' and mem_rsp.ready = '1' then
        if ra_w + 1 = nw then
          mreq.valid <= '0';
        end if;
        ra_w <= ra_w + 1;
        mreq.addr <= thumb_addr(sm, sb, row, ra_w(6 downto 0) + 1);
      end if;
      if mem_rsp.rvalid = '1' and rd_on = '1' then
        lb_we  <= '1';
        lb_wa  <= rcount(6 downto 0);
        lb_wd  <= mem_rsp.rdata;
        rcount <= rcount + 1;
      end if;

      case st is
        when S_IDLE =>
          lock_r <= '0';
          if pv = '0' then
            if nos_due /= "00" then
              -- present, no source
              if nos_due(0) = '1' then nos_i <= 0; nos_due(0) <= '0';
              else nos_i <= 1; nos_due(1) <= '0'; end if;
              pk_r <= THUMB_PKT_NONE;
              pk_r.sub <= TH_SUB_NOSRC;
              pk_r.dst <= dst;
              if nos_due(0) = '1' then
                pk_r.d <= 0; pk_r.machine <= local0;
              else
                pk_r.d <= 1; pk_r.machine <= local1;
              end if;
              pv <= '1';
            elsif pend = '1' then
              pend   <= '0';
              lock_r <= '1';
              sm <= pm; sb <= pbf; sq <= pq; srows <= prows;
              if pm = local1 then sd <= 1; else sd <= 0; end if;
              if pq = '1' then
                nw <= to_unsigned(40, 8); width <= to_unsigned(160, 9);
              else
                nw <= to_unsigned(80, 8); width <= to_unsigned(320, 9);
              end if;
              frame  <= frame + 1;
              row    <= (others => '0');
              pk_open <= '0';
              pb_ptr <= (others => '0');
              st <= S_FETCH;
              rd_on <= '0';
            end if;
          end if;

        when S_FETCH =>
          if rd_on = '0' then
            rd_on  <= '1';
            ra_w   <= (others => '0');
            rcount <= (others => '0');
            mreq <= (valid => '1', we => '0', addr => thumb_addr(sm, sb, row, (others => '0')),
                     wdata => (others => '0'), wmask => (others => '0'));
          elsif rcount = nw then
            rd_on <= '0';
            emit  <= '0';
            p     <= (others => '0');
            lb_ra <= (others => '0');
            runs  <= (others => '0');
            wk    <= K_B;
            st    <= S_SCAN;
          end if;

        when S_SCAN | S_EMIT =>
          case wk is
            when K_B =>
              wk <= K_C;                   -- line buffer latency
            when K_C =>
              b  := to_integer(p(1 downto 0));
              px := lb_q(32 * b + 23 downto 32 * b);
              lb_ra <= resize(shift_right(p + 1, 2), 7);
              flush := p /= 0 and (px /= run_px or run_n = 255);
              if p = 0 or flush then
                t_cnt <= run_n; t_px <= run_px;
                run_px <= px; run_n <= x"01";
                if flush then runs <= runs + 1; end if;
              else
                run_n <= run_n + 1;
              end if;
              t_last <= '0';
              if p + 1 = width then t_last <= '1'; end if;
              p <= p + 1;
              if st = S_SCAN then
                if p + 1 = width then
                  st <= S_DECIDE;
                else
                  wk <= K_B;
                end if;
              elsif enc_line = '0' then
                t_px <= px; t_n <= 3; wk <= K_E;          -- RAW888: R, G, B
              elsif flush then
                t_n <= 4; wk <= K_E;                       -- RLE24 tuple of the old run
              elsif p + 1 = width then
                t_n <= 0; wk <= K_E;                       -- final run below
              else
                wk <= K_B;
              end if;
            when K_E =>
              if t_n /= 0 then
                pb_we <= '1';
                pb_wa <= pb_ptr;
                pb_ptr <= pb_ptr + 1;
                if enc_line = '0' then
                  pb_wd <= rgb_byte(t_px, 3 - t_n);
                elsif t_n = 4 then
                  pb_wd <= std_logic_vector(t_cnt);
                else
                  pb_wd <= rgb_byte(t_px, 3 - t_n);
                end if;
                t_n <= t_n - 1;
              elsif t_last = '1' then
                if enc_line = '1' and run_n /= 0 then
                  -- final run of the line
                  t_cnt <= run_n; t_px <= run_px; run_n <= (others => '0'); t_n <= 4;
                else
                  -- line emitted
                  pk_n <= pk_n + 1;
                  row  <= row + 1;
                  if row + 1 = srows then
                    last_pkt <= '1';
                    st <= S_CLOSE;
                  else
                    st <= S_FETCH;
                  end if;
                end if;
              else
                wk <= K_C;                -- next pixel's word is on lb_q already
              end if;
          end case;

        when S_DECIDE =>
          -- RLE24 bytes = 4 * runs (incl. the final run)
          sz := resize((runs + 1) & "00", 13);
          if sz < resize(width * 3, 13) then
            enc_line <= '1';
          else
            enc_line <= '0';
            sz := resize(width * 3, 13);
          end if;
          lsize <= sz;
          if pk_open = '1' and ((sz < resize(width * 3, 13)) /= (pk_enc = '1') or
                                resize(pb_ptr, 14) + sz > TH_PKT_BUDGET) then
            last_pkt <= '0';
            st <= S_CLOSE;
          else
            if pk_open = '0' then
              pk_open <= '1';
              pk_row  <= row;
              pk_n    <= (others => '0');
              if sz < resize(width * 3, 13) then pk_enc <= '1'; else pk_enc <= '0'; end if;
            end if;
            emit  <= '1';
            p     <= (others => '0');
            lb_ra <= (others => '0');
            run_n <= (others => '0');
            wk    <= K_B;
            st    <= S_EMIT;
          end if;

        when S_CLOSE =>
          if pv = '0' then
            pk_r.sub     <= TH_SUB_LINES;
            pk_r.d       <= sd;
            pk_r.dst     <= dst;
            pk_r.machine <= sm;
            pk_r.flags   <= "000000" & last_pkt & '1';
            if sq = '1' then pk_r.scale <= x"02"; else pk_r.scale <= x"01"; end if;
            if pk_enc = '1' then pk_r.enc <= TH_ENC_RLE; else pk_r.enc <= TH_ENC_RAW; end if;
            pk_r.frame   <= frame;
            pk_r.row     <= pk_row;
            pk_r.nlines  <= pk_n;
            pk_r.height  <= srows;
            pk_r.width   <= resize(width, 16);
            pk_r.nbytes  <= pb_ptr;
            pv <= '1';
            st <= S_WAIT;
          end if;

        when S_WAIT =>
          -- net_tx copies the packet buffer; then continue with the line
          -- that did not fit (DECIDE again) or finish the picture
          if pv = '0' then
            pk_open <= '0';
            pb_ptr  <= (others => '0');
            if last_pkt = '1' then
              last_pkt <= '0';
              lock_r <= '0';
              npic <= npic + 1;
              st <= S_IDLE;
            else
              st <= S_DECIDE;
            end if;
          end if;
      end case;
      -- streaming stopped: finish nothing new (a picture in progress completes)
    end if;
  end process;
end architecture;
