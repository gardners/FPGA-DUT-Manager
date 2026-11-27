-- tb_relay_burst: full-resolution relayed pictures at gigabit line rate
-- (issue 0060, feature/relay-rx-speed).
--
-- 720x480 RAW888 pictures arrive as back-to-back 1/1 lines frames (3 lines,
-- 6530 bytes on the wire incl. the VLAN tag, minimum 12-byte gap and
-- preamble: 125 MB/s, 41.4 Mpx/s), as the HewnWeb K325T sends them, into
-- thumb_rx_tap -> thumb_rx_writer -> mem_arbiter -> mem_app_bridge -> the
-- behavioural MIG UI model with DDR3 bank/row timing (row miss 5 UI cycles,
-- read/write turnaround 3, refresh 12 cycles every 7.8 us, plus its random
-- app_rdy/app_wdf_rdy stalls). Concurrent traffic: full_display scanning
-- 720x480p60 out of the shown buffer the whole time (about 6.8 M words/s
-- while a line is fetched) and a thumbnail-capture-like writer in bank 0
-- (80 words every 64 us).
--
--   Phase A (key 0x0045 = 0, complete pictures, triple buffered): pictures
--     1 and 2 back to back (320 frames, ~2.1 MB, 16.7 ms): no frame may be
--     lost (tap: 0 bad, 0 overflow), 2 pictures complete; the latest
--     complete buffer must hold picture 2 exactly.
--   Phase B (key 0x0045 = 1, live): picture 3 with every 7th frame left
--     out: its lines go straight into the shown buffer; the rows of the
--     missing frames keep picture 2, all others show picture 3; no picture
--     completes, but the view stays fresh (full_ev per frame).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;
use work.mem_pkg.all;

entity tb_relay_burst is
  generic (
    TAP_AW   : positive := 14;
    BURST    : positive := 32;
    PICS_A   : positive := 2;
    -- memory model (analysis): DDR3 timing in UI cycles, random stalls,
    -- display on
    T_ROW    : natural := 5;
    T_TURN   : natural := 3;
    T_RANDOM : boolean := true;
    DISPLAY  : boolean := true
  );
end entity;

architecture tb of tb_relay_burst is
  constant W : natural := 720;
  constant H : natural := 480;
  constant LPF : natural := 3;                 -- lines per frame
  constant NFR : natural := H / LPF;           -- frames per picture
  constant MAC0 : std_logic_vector(47 downto 0) := x"024D36350000";
  constant PEER : std_logic_vector(47 downto 0) := x"024D36350022";

  signal clk, clk_rx, uclk, clk_pix : std_logic := '0';
  signal fin : boolean := false;
  signal rx_dv : std_logic := '0';
  signal rxd : std_logic_vector(7 downto 0) := (others => '0');

  signal f_valid, f_pop : std_logic;
  signal f_dout : std_logic_vector(35 downto 0);
  signal c_req, c_lines, c_bad, c_ovf, c_nosrc, c_vlan, c_long : unsigned(15 downto 0);
  signal tapfr : unsigned(15 downto 0);

  constant NP : natural := 4;                  -- 0 writer, 1 display, 2 capture-like, 3 checker
  signal reqs : mem_req_arr_t(0 to NP - 1) := (others => MEM_REQ_IDLE);
  signal rsps : mem_rsp_arr_t(0 to NP - 1);
  signal req  : mem_req_t;
  signal rsp  : mem_rsp_t;
  signal cal  : std_logic;
  signal app_addr, app_faddr : std_logic_vector(27 downto 0);
  signal app_cmd  : std_logic_vector(2 downto 0);
  signal app_en, app_rdy, app_wren, app_wend, app_wrdy, app_rv, ui_rst, cdone : std_logic;
  signal app_wd, app_rd : std_logic_vector(127 downto 0);
  signal app_wm : std_logic_vector(15 downto 0);

  signal live : std_logic := '0';
  signal den : std_logic := '0';
  signal fev : std_logic;
  signal fbuf, fshown : unsigned(1 downto 0);
  signal fw : unsigned(10 downto 0);
  signal fh : unsigned(9 downto 0);
  signal fpics : unsigned(15 downto 0);
  signal nfev : natural := 0;
  signal vx, vy : unsigned(10 downto 0);
  signal vde : std_logic;
  signal dr, dg, db : std_logic_vector(7 downto 0);
  signal d_on, d_frame : std_logic;
  signal disp_rd : natural := 0;
  signal wr_words : natural := 0;
  signal max_used, max_wf : natural := 0;
  signal wstall, wmwait : unsigned(15 downto 0);

  -- picture p, pixel (x, y): R = x, G = y, B = x/256 + 4 y/256 + 16 p
  function pix(x, y, p : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(x mod 256, 8)) & std_logic_vector(to_unsigned(y mod 256, 8)) &
           std_logic_vector(to_unsigned((x / 256 + 4 * (y / 256) + 16 * p) mod 256, 8));
  end function;

  -- the store is folded into 2**19 words: buffer id (2) & row (9) & word (8);
  -- full buffers are told apart in both the bank-1-only and the
  -- bank-per-buffer layouts; bank 0 (thumbnails) is id 3
  function fold(a : std_logic_vector(27 downto 0)) return std_logic_vector is
    variable wa : unsigned(24 downto 0) := unsigned(a(27 downto 3));
    variable bk : natural := to_integer(wa(23 downto 21));
    variable id : unsigned(1 downto 0);
    variable o : unsigned(24 downto 0) := (others => '0');
  begin
    if bk = 0 then id := "11";
    else id := resize(to_unsigned(to_integer(wa(19 downto 18)) + bk - 1, 3), 2); end if;
    o(18 downto 0) := id & wa(16 downto 8) & wa(7 downto 0);
    return std_logic_vector(o) & "000";
  end function;
begin
  den     <= '1' when DISPLAY else '0';
  clk     <= not clk after 4 ns when not fin;          -- 125 MHz
  clk_rx  <= not clk_rx after 4.0016 ns when not fin;  -- 125 MHz, other crystal
  uclk    <= not uclk after 5 ns when not fin;         -- 100 MHz MIG UI clock
  clk_pix <= not clk_pix after 18.5185 ns when not fin; -- 27 MHz

  tap : entity work.thumb_rx_tap
    generic map (FIFO_AW => TAP_AW)
    port map (clk => clk_rx, rx_dv => rx_dv, rxd => rxd,
              mac0 => MAC0, mac1 => x"024D36350011", vlan => to_unsigned(1650, 12),
              sclk => clk, f_valid => f_valid, f_dout => f_dout, f_pop => f_pop,
              req_stb => open, req_mac => open, req_scale => open, req_div => open,
              req_flags => open, req_target => open, frames => tapfr,
              c_req => c_req, c_lines => c_lines, c_bad => c_bad, c_ovf => c_ovf, c_nosrc => c_nosrc,
              c_vlan => c_vlan, c_long => c_long,
              last_valid => open, last_nosrc => open, last_m => open, last_scale => open);
  wr : entity work.thumb_rx_writer
    port map (clk => clk, f_valid => f_valid, f_dout => f_dout, f_pop => f_pop,
              local0 => to_unsigned(0, 5), local1 => to_unsigned(1, 5), relay0 => '0', relay1 => '1',
              cur => (others => '0'), mem_req => reqs(0), mem_rsp => rsps(0),
              ev => open, ev_machine => open, ev_buf => open, ev_quarter => open,
              seen_ev => open, seen_machine => open, pictures => open,
              full_en => '1', full_m => to_unsigned(1, 5), full_shown => fshown, full_live => live,
              full_ev => fev, full_buf => fbuf, full_width => fw, full_height => fh,
              full_pics => fpics, foreign => open,
              win => '0', stall => wstall, mwait => wmwait, wf_hwm => open);

  vt : entity work.video_timing
    port map (clk => clk_pix, x => vx, y => vy, de => vde, hs => open, vs => open, frame_start => open);
  -- shown the whole time (worst case for the memory: reads never pause)
  disp : entity work.full_display
    port map (clk_sys => clk, mem_req => reqs(1), mem_rsp => rsps(1), enable => den,
              buf => fbuf, width => to_unsigned(W, 11), height => to_unsigned(H, 10), shown => fshown,
              frame => d_frame,
              clk_pix => clk_pix, x => vx, y => vy, de => vde, r => dr, g => dg, b => db, layer_on => d_on);

  arb : entity work.mem_arbiter
    generic map (N => NP, BURST => BURST)
    port map (clk => clk, reqs => reqs, rsps => rsps, req => req, rsp => rsp);
  br : entity work.mem_app_bridge
    port map (clk => clk, req => req, rsp => rsp, calibrated => cal,
              ui_clk => uclk, ui_rst => ui_rst, calib_done => cdone,
              app_addr => app_addr, app_cmd => app_cmd, app_en => app_en, app_rdy => app_rdy,
              app_wdf_data => app_wd, app_wdf_mask => app_wm, app_wdf_wren => app_wren,
              app_wdf_end => app_wend, app_wdf_rdy => app_wrdy,
              app_rd_data => app_rd, app_rd_valid => app_rv);
  app_faddr <= fold(app_addr);
  -- DDR3-800 in UI cycles (10 ns): tRP + tRCD ~ 28 ns (+ tWR after a
  -- write) -> 5; write->read tWTR / read->write bus turnaround -> 3;
  -- tREFI 7.8 us, tRFC 110 ns -> 12
  ui : entity work.mig_ui_model
    generic map (ADDR_BITS => 19, LATENCY => 24, CALIB_CYCLES => 50, SEED => 3,
                 ROW_MISS => T_ROW, TURN => T_TURN, RANDOM => T_RANDOM, REFRESH_EVERY => 780, REFRESH_CYCLES => 12,
                 BANK_LSB => 21, BANK_BITS => 3, ROW_LSB => 7, TM_PORT => true)
    port map (ui_clk => uclk, ui_rst => ui_rst, calib_done => cdone,
              app_addr => app_faddr, app_cmd => app_cmd, app_en => app_en, app_rdy => app_rdy,
              app_wdf_data => app_wd, app_wdf_mask => app_wm, app_wdf_wren => app_wren,
              app_wdf_end => app_wend, app_wdf_rdy => app_wrdy,
              app_rd_data => app_rd, app_rd_valid => app_rv, tm_addr => app_addr);

  -- thumbnail-capture-like load in bank 0: 80 words every 64 us
  cap : process
    variable row : natural := 0;
  begin
    wait until cal = '1';
    loop
      for wi in 0 to 79 loop
        reqs(2) <= (valid => '1', we => '1', addr => thumb_addr(to_unsigned(4, 5), '0', to_unsigned(row, 8), to_unsigned(wi, 7)),
                    wdata => (others => '1'), wmask => (others => '1'));
        loop
          wait until rising_edge(clk);
          exit when rsps(2).ready = '1';
        end loop;
      end loop;
      reqs(2) <= MEM_REQ_IDLE;
      row := (row + 1) mod 200;
      wait for 64 us;
      exit when fin;
    end loop;
    wait;
  end process;

  stats : process (clk)
    alias used is << signal .tb_relay_burst.tap.f_used : unsigned(TAP_AW downto 0) >>;
    alias wused is << signal .tb_relay_burst.wr.wf_used : unsigned(9 downto 0) >>;
  begin
    if rising_edge(clk) then
      if fev = '1' then nfev <= nfev + 1; end if;
      if rsps(1).rvalid = '1' then disp_rd <= disp_rd + 1; end if;
      if reqs(0).valid = '1' and rsps(0).ready = '1' then wr_words <= wr_words + 1; end if;
      if to_integer(used) > max_used then max_used <= to_integer(used); end if;
      if to_integer(wused) > max_wf then max_wf <= to_integer(wused); end if;
    end if;
  end process;

  drive : process
    type bytes_t is array (0 to 8191) of std_logic_vector(7 downto 0);
    variable fb : bytes_t;
    variable n : natural;
    variable crc : std_logic_vector(31 downto 0);
    variable px : std_logic_vector(23 downto 0);
    variable t0 : time;

    procedure put(b : std_logic_vector(7 downto 0)) is
    begin
      fb(n) := b; n := n + 1;
    end procedure;
    procedure put16(v : natural) is
    begin
      put(std_logic_vector(to_unsigned(v / 256, 8))); put(std_logic_vector(to_unsigned(v mod 256, 8)));
    end procedure;

    procedure send_frame(p, k : natural) is
    begin
      n := 0;
      for i in 5 downto 0 loop put(MAC0(8 * i + 7 downto 8 * i)); end loop;
      for i in 5 downto 0 loop put(PEER(8 * i + 7 downto 8 * i)); end loop;
      put(x"81"); put(x"00"); put16(1650);                 -- 802.1Q, VID 1650
      put(x"88"); put(x"B5");
      put(x"01"); put(x"02"); put(x"4D"); put(x"36");      -- version, lines, magic
      put(x"01"); put(x"01"); put(x"03"); put(x"00");      -- machine 1, present, 1/1, RAW888
      put16(0); put16(p);                                  -- frame number
      put16(LPF * k); put16(LPF); put16(W); put16(H); put16(LPF * W * 3);
      for l in 0 to LPF - 1 loop
        for x in 0 to W - 1 loop
          px := pix(x, LPF * k + l, p);
          put(px(23 downto 16)); put(px(15 downto 8)); put(px(7 downto 0));
        end loop;
      end loop;
      crc := (others => '1');
      for i in 0 to n - 1 loop crc := crc32_byte(crc, fb(i)); end loop;
      crc := not crc;
      for i in 0 to 3 loop put(crc(8 * i + 7 downto 8 * i)); end loop;
      -- preamble, frame, 12-byte gap
      for i in 0 to 7 loop
        rx_dv <= '1';
        if i = 7 then rxd <= x"D5"; else rxd <= x"55"; end if;
        wait until rising_edge(clk_rx);
      end loop;
      for i in 0 to n - 1 loop
        rxd <= fb(i);
        wait until rising_edge(clk_rx);
      end loop;
      rx_dv <= '0';
      rxd <= x"00";
      for i in 0 to 11 loop wait until rising_edge(clk_rx); end loop;
    end procedure;

    -- read the whole picture of buffer b back (pipelined) and compare it with
    -- picture p, except rows of frame k with k mod skip = skip - 1 (picture q)
    procedure check(b : unsigned(1 downto 0); p, q, skip : natural) is
      variable bad, got : natural := 0;
      variable row, wi : natural := 0;
      variable e : std_logic_vector(127 downto 0);
      variable pp : natural;
      variable issued : natural := 0;
      constant TOTAL : natural := H * (W / 4);
    begin
      while got < TOTAL loop
        if issued < TOTAL then
          reqs(3) <= (valid => '1', we => '0',
                      addr => full_addr(b, to_unsigned(issued / (W / 4), 10), to_unsigned(issued mod (W / 4), 8)),
                      wdata => (others => '0'), wmask => (others => '0'));
        else
          reqs(3) <= MEM_REQ_IDLE;
        end if;
        wait until rising_edge(clk);
        if reqs(3).valid = '1' and rsps(3).ready = '1' then issued := issued + 1; end if;
        if rsps(3).rvalid = '1' then
          row := got / (W / 4); wi := got mod (W / 4);
          pp := p;
          if skip /= 0 and (row / LPF) mod skip = skip - 1 then pp := q; end if;
          for i in 0 to 3 loop
            e(32 * i + 31 downto 32 * i) := x"00" & pix(4 * wi + i, row, pp);
          end loop;
          if rsps(3).rdata /= e then
            if bad < 5 then
              report "buffer " & integer'image(to_integer(b)) & " row " & integer'image(row) & " word " &
                integer'image(wi) & ": " & to_hstring(rsps(3).rdata) & " expected " & to_hstring(e)
                severity warning;
            end if;
            bad := bad + 1;
          end if;
          got := got + 1;
        end if;
      end loop;
      reqs(3) <= MEM_REQ_IDLE;
      assert bad = 0 report integer'image(bad) & " words wrong in buffer " & integer'image(to_integer(b))
        severity failure;
    end procedure;
    variable wr0, rd0 : natural;
  begin
    wait until cal = '1';
    -- the display takes its first frame at line 480 (start of vertical blank)
    wait until vy = 490;
    wait until rising_edge(clk_rx);
    ---------------------------------------------------------------- phase A
    live <= '0';
    t0 := now; wr0 := wr_words; rd0 := disp_rd;
    for p in 1 to PICS_A loop
      for k in 0 to NFR - 1 loop send_frame(p, k); end loop;
    end loop;
    report "phase A: " & integer'image(PICS_A * NFR) & " frames in " & time'image(now - t0) &
      ", writer " & integer'image(wr_words - wr0) & " words, display " & integer'image(disp_rd - rd0) &
      " words, tap FIFO max " & integer'image(max_used) & " of " & integer'image(2 ** TAP_AW) &
      ", writer stalled " & integer'image(to_integer(wstall)) & " x 2.048 us, memory busy " &
      integer'image(to_integer(wmwait)) & " x 2.048 us, word FIFO max " & integer'image(max_wf) & " of 512";
    wait for 300 us;
    report "phase A counters: lines " & integer'image(to_integer(c_lines)) & " bad " &
      integer'image(to_integer(c_bad)) & " ovf " & integer'image(to_integer(c_ovf)) & " pictures " &
      integer'image(to_integer(fpics)) & " full_ev " & integer'image(nfev) & " buf " &
      integer'image(to_integer(fbuf)) & " " & integer'image(to_integer(fw)) & "x" & integer'image(to_integer(fh));
    assert c_lines = PICS_A * NFR and c_bad = 0 and c_ovf = 0
      report "phase A: frames lost" severity failure;
    assert fpics = PICS_A and fw = W and fh = H report "phase A: pictures not complete" severity failure;
    check(fbuf, PICS_A, PICS_A, 0);
    report "phase A: buffer " & integer'image(to_integer(fbuf)) & " = picture " & integer'image(PICS_A);

    ---------------------------------------------------------------- phase B
    live <= '1';
    wait for 1 us;
    wait until rising_edge(clk_rx);
    t0 := now; wr0 := wr_words; rd0 := disp_rd;
    for k in 0 to NFR - 1 loop
      if k mod 7 /= 6 then send_frame(PICS_A + 1, k); end if;
    end loop;
    wait for 300 us;
    report "phase B (live): " & integer'image(to_integer(c_lines)) & " lines frames, bad " &
      integer'image(to_integer(c_bad)) & ", pictures " & integer'image(to_integer(fpics)) &
      ", full_ev " & integer'image(nfev) & ", buf " & integer'image(to_integer(fbuf)) & ", shown " &
      integer'image(to_integer(fshown)) & ", tap FIFO max " & integer'image(max_used) &
      ", word FIFO max " & integer'image(max_wf) & ", memory busy " & integer'image(to_integer(wmwait)) &
      " x 2.048 us (both phases)";
    assert c_bad = 0 and c_ovf = 0 report "phase B: frames lost" severity failure;
    assert fpics = PICS_A report "phase B: an incomplete picture completed" severity failure;
    assert nfev >= PICS_A + NFR - NFR / 7 report "phase B: full_ev not per frame" severity failure;
    -- the display takes the live buffer at its next vertical blank
    if fshown /= fbuf then wait until fshown = fbuf for 20 ms; end if;
    assert fshown = fbuf report "phase B: the live buffer is not shown" severity failure;
    check(fbuf, PICS_A + 1, PICS_A, 7);
    report "tb_relay_burst PASSED: display read " & integer'image(disp_rd) & " words";
    fin <= true;
    wait;
  end process;
end architecture;
