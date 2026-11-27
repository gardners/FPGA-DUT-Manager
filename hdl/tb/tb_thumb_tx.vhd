-- tb_thumb_tx: thumb_tx with mem_model (the testbench writes the pictures
-- through a second port) and a net_tx stand-in that copies each frame out
-- of the packet buffer into CAP_OUT. tests/scenarios/tb_thumb_tx.py checks
-- every frame byte for byte against netproto.thumb_packets (per-line
-- RAW888/RLE24 choice, packing, budget split, flags), the no-source frames,
-- requests and the scale/divisor policy (issue 0038). MS_PER_S = 40.
-- Issue 0060: 2 Hz requests, full-view requests (targeted, priority, 1/1),
-- targeted requests for other machines ignored, a targeted request streams
-- only its machine, frames to a requester tagged, to the forced MAC not.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.mem_pkg.all;
use work.thumb_pkg.all;

entity tb_thumb_tx is
  generic (VEC_IN : string := "unused"; CAP_OUT : string := "tb_thumb_tx_out.txt");
end entity;

architecture tb of tb_thumb_tx is
  constant MSS : natural := 40;
  signal clk : std_logic := '0';
  signal fin : boolean := false;
  signal tick : std_logic := '0';
  signal selecting : std_logic := '0';
  signal n_seen : unsigned(5 downto 0) := to_unsigned(2, 6);
  signal force_mac : std_logic_vector(47 downto 0) := (others => '0');
  signal force_scale, force_div : std_logic_vector(7 downto 0) := x"01";
  signal req_stb : std_logic := '0';
  signal req_mac : std_logic_vector(47 downto 0) := (others => '0');
  signal req_scale, req_div : std_logic_vector(7 downto 0) := x"00";
  signal req_flags, req_target : std_logic_vector(7 downto 0) := x"00";
  signal full_want : std_logic := '0';
  signal full_m : unsigned(4 downto 0) := (others => '0');
  signal cap_done, cap_buf, cap_q : std_logic := '0';
  signal cap_m : unsigned(4 downto 0) := (others => '0');
  signal cap_rows : unsigned(7 downto 0) := (others => '0');
  signal eff_q, lock_v, lock_b, pkt_valid, pkt_taken, treq_valid, treq_taken, strm : std_logic;
  signal eff_div : unsigned(3 downto 0);
  signal tsc, tdv, tfl, ttg : std_logic_vector(7 downto 0);
  signal lock_m : unsigned(4 downto 0);
  signal pkt : thumb_pkt_t;
  signal pb_raddr : unsigned(12 downto 0) := (others => '0');
  signal pb_rdata : std_logic_vector(7 downto 0);
  signal req : mem_req_arr_t(0 to 1) := (others => MEM_REQ_IDLE);
  signal rsp : mem_rsp_arr_t(0 to 1);
  signal pics : unsigned(31 downto 0);
  signal npkt, ntreq : natural := 0;
  signal lock_seen : boolean := false;
  constant L0 : unsigned(4 downto 0) := to_unsigned(4, 5);
  constant L1 : unsigned(4 downto 0) := to_unsigned(5, 5);

  -- picture pattern, shared with tests/scenarios/tb_thumb_tx.py
  function pat(m, x, y : natural) return std_logic_vector is
    variable r, g, b : natural;
  begin
    if y mod 3 = 0 and y < 6 then
      r := ((x / 40) * 37 + y + m) mod 256; g := r; b := r;
    elsif y mod 3 = 2 and y < 6 and x < 160 then
      r := 10; g := 20; b := 30;
    else
      r := (x * 13 + y * 7 + m) mod 256; g := (x * x + y) mod 256; b := (x + 3 * y * y) mod 256;
    end if;
    return std_logic_vector(to_unsigned(r, 8)) & std_logic_vector(to_unsigned(g, 8)) &
           std_logic_vector(to_unsigned(b, 8));
  end function;
begin
  clk <= not clk after 4 ns when not fin;
  process
  begin
    wait for 1 us;     -- "1 ms" ticks every microsecond
    loop
      wait until rising_edge(clk);
      tick <= '1';
      wait until rising_edge(clk);
      tick <= '0';
      wait for 984 ns;
      exit when fin;
    end loop;
    wait;
  end process;

  mm : entity work.mem_mux_model generic map (N => 2, ADDR_BITS => 17, LATENCY => 15, STALL_EVERY => 4)
    port map (clk => clk, req => req, rsp => rsp);

  dut : entity work.thumb_tx
    generic map (MS_PER_S => MSS)
    port map (clk => clk, tick_1ms => tick, local0 => L0, local1 => L1,
              selecting => selecting, n_seen => n_seen,
              force_mac => force_mac, force_scale => force_scale, force_div => force_div,
              req_stb => req_stb, req_mac => req_mac, req_scale => req_scale, req_div => req_div,
              req_flags => req_flags, req_target => req_target,
              full_want => full_want, full_machine => full_m,
              cap_done => cap_done, cap_machine => cap_m, cap_buf => cap_buf,
              cap_quarter => cap_q, cap_rows => cap_rows,
              eff_quarter => eff_q, eff_div => eff_div,
              lock_valid => lock_v, lock_machine => lock_m, lock_buf => lock_b,
              mem_req => req(1), mem_rsp => rsp(1),
              pkt_valid => pkt_valid, pkt => pkt, pkt_taken => pkt_taken,
              pb_raddr => pb_raddr, pb_rdata => pb_rdata,
              treq_valid => treq_valid, treq_scale => tsc, treq_div => tdv,
              treq_flags => tfl, treq_target => ttg, treq_taken => treq_taken,
              streaming => strm, pictures => pics);

  process (clk)
  begin
    if rising_edge(clk) then
      if lock_v = '1' then
        lock_seen <= true;
        assert lock_m = cap_m and lock_b = cap_buf report "lock on the wrong buffer" severity error;
      end if;
    end if;
  end process;

  -- net_tx stand-in: copy each frame / request out
  nt : process
    file fo : text open write_mode is CAP_OUT;
    variable l : line;
  begin
    pkt_taken <= '0';
    treq_taken <= '0';
    loop
      wait until rising_edge(clk);
      exit when fin;
      if treq_valid = '1' then
        write(l, string'("treq ") & integer'image(to_integer(unsigned(tsc))) & " " &
          integer'image(to_integer(unsigned(tdv))) & " " & integer'image(to_integer(unsigned(tfl))) & " " &
          integer'image(to_integer(unsigned(ttg))));
        writeline(fo, l);
        treq_taken <= '1';
        wait until rising_edge(clk);
        treq_taken <= '0';
        ntreq <= ntreq + 1;
      elsif pkt_valid = '1' then
        write(l, string'("pkt ") & integer'image(to_integer(unsigned(pkt.sub))) & " " &
          integer'image(pkt.d) & " ");
        hwrite(l, pkt.dst);
        write(l, string'(" ") & integer'image(to_integer(pkt.machine)) & " " &
          integer'image(to_integer(unsigned(pkt.flags))) & " " &
          integer'image(to_integer(unsigned(pkt.scale))) & " " &
          integer'image(to_integer(unsigned(pkt.enc))) & " " &
          integer'image(to_integer(pkt.frame)) & " " & integer'image(to_integer(pkt.row)) & " " &
          integer'image(to_integer(pkt.nlines)) & " " & integer'image(to_integer(pkt.height)) & " " &
          integer'image(to_integer(pkt.width)) & " " & integer'image(to_integer(pkt.nbytes)) & " " &
          std_logic'image(pkt.tag)(2) & " ");
        for i in 0 to to_integer(pkt.nbytes) - 1 loop
          pb_raddr <= to_unsigned(i, 13);
          wait until rising_edge(clk);
          wait for 1 ns;
          hwrite(l, pb_rdata);
        end loop;
        writeline(fo, l);
        pkt_taken <= '1';
        wait until rising_edge(clk);
        pkt_taken <= '0';
        npkt <= npkt + 1;
      end if;
    end loop;
    wait;
  end process;

  stim : process
    procedure put(m : natural; buf : std_logic; rows, w : natural) is
      variable wd : std_logic_vector(127 downto 0);
    begin
      for y in 0 to rows - 1 loop
        for k in 0 to w / 4 - 1 loop
          for i in 0 to 3 loop
            wd(32 * i + 31 downto 32 * i) := x"00" & pat(m, 4 * k + i, y);
          end loop;
          req(0) <= (valid => '1', we => '1',
                     addr => thumb_addr(to_unsigned(m, 5), buf, to_unsigned(y, 8), to_unsigned(k, 7)),
                     wdata => wd, wmask => (others => '1'));
          loop
            wait until rising_edge(clk);
            exit when rsp(0).ready = '1';
          end loop;
          req(0) <= MEM_REQ_IDLE;
        end loop;
      end loop;
    end procedure;
    procedure done(m : natural; buf, q : std_logic; rows : natural) is
    begin
      wait until rising_edge(clk);
      cap_m <= to_unsigned(m, 5); cap_buf <= buf; cap_q <= q; cap_rows <= to_unsigned(rows, 8);
      cap_done <= '1';
      wait until rising_edge(clk);
      cap_done <= '0';
    end procedure;
    variable n0 : natural;
  begin
    put(4, '1', 16, 320);
    put(5, '0', 6, 160);
    wait for 2 us;
    -- not streaming: pictures are not sent, defaults in effect
    done(4, '1', '0', 16);
    wait for 20 us;
    assert npkt = 0 and strm = '0' report "sent without a destination" severity error;
    assert eff_q = '0' and eff_div = 2 report "default scale/divisor" severity error;
    -- forced MAC: stream; no-source for both until they have pictures
    force_mac <= x"0200000000AA"; force_scale <= x"01"; force_div <= x"02";
    wait for 45 us;
    done(4, '1', '0', 16);
    wait until pics = 1 for 2 ms;
    assert pics = 1 report "1/2 picture not sent" severity error;
    done(5, '0', '1', 6);
    wait until pics = 2 for 2 ms;
    assert pics = 2 report "1/4 picture not sent" severity error;
    assert lock_seen report "buffer never locked" severity error;
    wait until rising_edge(clk);
    assert lock_v = '0' report "lock held after sending" severity error;
    -- forced MAC off, a request (scale 1/4, divisor 3) from another board
    force_mac <= (others => '0');
    req_mac <= x"024D36350022"; req_scale <= x"02"; req_div <= x"03";
    wait until rising_edge(clk);
    req_stb <= '1';
    wait until rising_edge(clk);
    req_stb <= '0';
    wait for 1 us;
    assert strm = '1' and eff_q = '1' and eff_div = 3 report "request policy" severity error;
    done(4, '0', '1', 3);   -- (a 1/4 picture of rows 0..2 from buffer 0, never written: zeros)
    wait until pics = 3 for 2 ms;
    -- request expires after MS_PER_S without repeats
    wait for 50 us;
    assert strm = '0' and eff_q = '0' report "request did not expire" severity error;
    -- selecting: requests every MS_PER_S/2 (2 Hz) with own scale (6 seen -> 1/4)
    n_seen <= to_unsigned(6, 6);
    selecting <= '1';
    n0 := ntreq;
    wait for 65 us;
    assert ntreq - n0 >= 3 and ntreq - n0 <= 4 report "requests not sent at 2 Hz while selecting" severity error;
    assert eff_q = '1' and eff_div = 2 report "own scale while selecting" severity error;
    selecting <= '0';
    -- full view of machine 9 (issue 0060): targeted, priority, 1/1, divisor 1
    full_m <= to_unsigned(9, 5);
    full_want <= '1';
    n0 := ntreq;
    wait for 45 us;
    assert ntreq - n0 >= 2 report "no full-view requests" severity error;
    full_want <= '0';
    wait for 50 us;          -- our own requests are not heard (no req_stb)
    -- a request targeted at machine 7 (not ours) is ignored
    req_mac <= x"024D36350033"; req_scale <= x"03"; req_div <= x"01";
    req_flags <= x"03"; req_target <= x"07";
    wait until rising_edge(clk);
    req_stb <= '1';
    wait until rising_edge(clk);
    req_stb <= '0';
    wait for 1 us;
    assert strm = '0' report "streaming for a request targeted at another machine" severity error;
    -- targeted at our machine 5 (scale 3 -> answered at 1/2): only machine
    -- 5 is streamed, tagged
    req_target <= x"05";
    wait until rising_edge(clk);
    req_stb <= '1';
    wait until rising_edge(clk);
    req_stb <= '0';
    wait for 1 us;
    assert strm = '1' and eff_q = '0' and eff_div = 1 report "targeted request policy" severity error;
    done(4, '1', '0', 16);   -- not the target: not sent
    wait for 30 us;
    assert pics = 3 report "sent a picture of a machine that was not the target" severity error;
    done(5, '0', '1', 6);
    wait until pics = 4 for 2 ms;
    assert pics = 4 report "target machine's picture not sent" severity error;
    report "tb_thumb_tx PASSED (frame-level): " & integer'image(npkt) & " frames, " &
      integer'image(ntreq) & " requests";
    fin <= true;
    wait;
  end process;
end architecture;
