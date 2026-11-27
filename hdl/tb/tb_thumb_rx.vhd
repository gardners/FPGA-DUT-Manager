-- tb_thumb_rx: relay frames (EtherType 0x88B5) from a vector file into
-- thumb_rx_tap -> thumb_rx_writer -> mem_model, with thumb_status. At the
-- end the status, the last request and the shown buffers of machines 3 and
-- 8 are written to CAP_OUT; tests/scenarios/tb_thumb_rx.py generates the
-- frames (RAW888 and RLE24, 1/2 and 1/4 scale, bad FCS, foreign MAC, local
-- machine, no-source, request) and checks the result (issue 0038).
-- Issue 0060: the tap is on VLAN 1650 (untagged and other-VID frames are
-- dropped), local machine 1 has no local video (relay1) so its relayed
-- thumbnails are stored, machine 0's are not; 1/1 pictures of machine 1
-- (full view) go to the triple-buffered full store, whose latest complete
-- buffer is dumped too. Addresses are folded into 18 bits for mem_model.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.mem_pkg.all;

entity tb_thumb_rx is
  generic (VEC_IN : string := "tb_thumb_rx_in.txt"; CAP_OUT : string := "tb_thumb_rx_out.txt");
end entity;

architecture tb of tb_thumb_rx is
  signal clk, clk_rx : std_logic := '0';
  signal fin : boolean := false;
  signal rx_dv : std_logic := '0';
  signal rxd : std_logic_vector(7 downto 0) := (others => '0');
  signal f_valid, f_pop : std_logic;
  signal f_dout : std_logic_vector(35 downto 0);
  signal req_stb : std_logic;
  signal req_mac : std_logic_vector(47 downto 0);
  signal req_scale, req_div, req_flags, req_target : std_logic_vector(7 downto 0);
  signal nreq : natural := 0;
  signal req : mem_req_arr_t(0 to 1) := (others => MEM_REQ_IDLE);
  signal reqf : mem_req_arr_t(0 to 1);
  signal fev : std_logic := '0';
  signal fbuf : unsigned(1 downto 0);
  signal fw : unsigned(10 downto 0);
  signal fh : unsigned(9 downto 0);
  signal nfull : natural := 0;
  -- thumbnails: machine & buf, row 3:0, word; full: buf, row 5:0, word
  function fold(r : mem_req_t) return mem_req_t is
    variable o : mem_req_t := r;
  begin
    o.addr := (others => '0');
    if r.addr(21) = '1' then
      o.addr(17 downto 0) := '1' & r.addr(19 downto 18) & '0' & r.addr(13 downto 0);
    else
      o.addr(17 downto 0) := '0' & r.addr(20 downto 15) & r.addr(10 downto 7) & r.addr(6 downto 0);
    end if;
    return o;
  end function;
  signal rsp : mem_rsp_arr_t(0 to 1);
  signal ev, ev_buf, ev_q, sev : std_logic;
  signal ev_m, sm : unsigned(4 downto 0);
  signal seen, fresh, cur, quarter : std_logic_vector(31 downto 0);
  signal nseen : unsigned(5 downto 0);
  signal pics : unsigned(31 downto 0);
  signal tapfr : unsigned(15 downto 0);
  signal c_req, c_lines, c_bad, c_ovf, c_nosrc, c_vlan, c_long, c_foreign : unsigned(15 downto 0);
  signal l_v, l_ns : std_logic;
  signal l_m : unsigned(4 downto 0);
  signal l_sc : std_logic_vector(7 downto 0);
  constant L0 : unsigned(4 downto 0) := to_unsigned(0, 5);
  constant L1 : unsigned(4 downto 0) := to_unsigned(1, 5);
begin
  clk    <= not clk after 4 ns when not fin;
  clk_rx <= not clk_rx after 4.0016 ns when not fin;

  tap : entity work.thumb_rx_tap
    generic map (FIFO_AW => 11)
    port map (clk => clk_rx, rx_dv => rx_dv, rxd => rxd,
              mac0 => x"024D36350000", mac1 => x"024D36350011", vlan => to_unsigned(1650, 12),
              sclk => clk, f_valid => f_valid, f_dout => f_dout, f_pop => f_pop,
              req_stb => req_stb, req_mac => req_mac, req_scale => req_scale,
              req_div => req_div, req_flags => req_flags, req_target => req_target, frames => tapfr,
              c_req => c_req, c_lines => c_lines, c_bad => c_bad, c_ovf => c_ovf, c_nosrc => c_nosrc,
              c_vlan => c_vlan, c_long => c_long,
              last_valid => l_v, last_nosrc => l_ns, last_m => l_m, last_scale => l_sc);
  wr : entity work.thumb_rx_writer
    port map (clk => clk, f_valid => f_valid, f_dout => f_dout, f_pop => f_pop,
              local0 => L0, local1 => L1, relay0 => '0', relay1 => '1',
              cur => cur, mem_req => req(0), mem_rsp => rsp(0),
              ev => ev, ev_machine => ev_m, ev_buf => ev_buf, ev_quarter => ev_q,
              seen_ev => sev, seen_machine => sm, pictures => pics,
              full_en => '1', full_m => L1, full_shown => "00",
              full_ev => fev, full_buf => fbuf, full_width => fw, full_height => fh, full_pics => open,
              foreign => c_foreign);
  st : entity work.thumb_status
    port map (clk => clk, tick_1ms => '0', local0 => L0, local1 => L1,
              ev_a => '0', ev_a_machine => L0, ev_a_buf => '0', ev_a_quarter => '0',
              ev_b => ev, ev_b_machine => ev_m, ev_b_buf => ev_buf, ev_b_quarter => ev_q,
              seen_ev => sev, seen_machine => sm,
              seen => seen, fresh => fresh, cur => cur, quarter => quarter, n_seen => nseen);
  reqf(0) <= fold(req(0));
  reqf(1) <= fold(req(1));
  mm : entity work.mem_mux_model generic map (N => 2, ADDR_BITS => 18, LATENCY => 10, STALL_EVERY => 5)
    port map (clk => clk, req => reqf, rsp => rsp);

  process (clk)
  begin
    if rising_edge(clk) then
      if req_stb = '1' then nreq <= nreq + 1; end if;
      if fev = '1' then nfull <= nfull + 1; end if;
    end if;
  end process;

  drive : process
    file fi : text open read_mode is VEC_IN;
    file fo : text open write_mode is CAP_OUT;
    variable l : line;
    variable delay, n : integer;
    variable b : std_logic_vector(7 downto 0);
    type buf_t is array (0 to 9000) of std_logic_vector(7 downto 0);
    variable buf : buf_t;
    variable wd : std_logic_vector(127 downto 0);

    procedure rd(a : unsigned; data : out std_logic_vector) is
    begin
      req(1) <= (valid => '1', we => '0', addr => a, wdata => (others => '0'), wmask => (others => '0'));
      loop
        wait until rising_edge(clk);
        exit when rsp(1).ready = '1';
      end loop;
      req(1) <= MEM_REQ_IDLE;
      loop
        exit when rsp(1).rvalid = '1';
        wait until rising_edge(clk);
      end loop;
      data := rsp(1).rdata;
    end procedure;

    procedure dump(m, rows, words : natural) is
    begin
      for r in 0 to rows - 1 loop
        write(l, string'("row ") & integer'image(m) & " " & integer'image(r));
        for w in 0 to words - 1 loop
          rd(thumb_addr(to_unsigned(m, 5), cur(m), to_unsigned(r, 8), to_unsigned(w, 7)), wd);
          write(l, string'(" "));
          hwrite(l, wd);
        end loop;
        writeline(fo, l);
      end loop;
    end procedure;
  begin
    wait for 1 us;
    while not endfile(fi) loop
      readline(fi, l);
      read(l, delay);
      read(l, n);
      for i in 0 to n - 1 loop
        hread(l, b);
        buf(i) := b;
      end loop;
      wait for delay * 1 us;
      wait until rising_edge(clk_rx);
      for i in 0 to 7 loop
        rx_dv <= '1';
        if i = 7 then rxd <= x"D5"; else rxd <= x"55"; end if;
        wait until rising_edge(clk_rx);
      end loop;
      for i in 0 to n - 1 loop
        rxd <= buf(i);
        wait until rising_edge(clk_rx);
      end loop;
      rx_dv <= '0';
      rxd <= x"00";
      for i in 0 to 11 loop
        wait until rising_edge(clk_rx);
      end loop;
    end loop;
    wait for 100 us;
    write(l, string'("status "));
    hwrite(l, cur); write(l, string'(" ")); hwrite(l, seen); write(l, string'(" "));
    hwrite(l, fresh); write(l, string'(" ")); hwrite(l, quarter);
    write(l, string'(" ") & integer'image(to_integer(pics)) & " " & integer'image(to_integer(nseen)));
    writeline(fo, l);
    write(l, string'("req ") & integer'image(nreq) & " ");
    hwrite(l, req_mac); write(l, string'(" ")); hwrite(l, req_scale);
    write(l, string'(" ")); hwrite(l, req_div);
    write(l, string'(" ")); hwrite(l, req_flags);
    write(l, string'(" ")); hwrite(l, req_target);
    writeline(fo, l);
    dump(3, 6, 80);
    dump(8, 4, 40);
    dump(1, 4, 40);
    write(l, string'("full ") & integer'image(nfull) & " " & integer'image(to_integer(fbuf)) & " " &
      integer'image(to_integer(fw)) & " " & integer'image(to_integer(fh)));
    writeline(fo, l);
    for r in 0 to to_integer(fh) - 1 loop
      write(l, string'("frow ") & integer'image(r));
      for w in 0 to (to_integer(fw) + 3) / 4 - 1 loop
        rd(full_addr(fbuf, to_unsigned(r, 10), to_unsigned(w, 8)), wd);
        write(l, string'(" "));
        hwrite(l, wd);
      end loop;
      writeline(fo, l);
    end loop;
    -- relay counters (issue 0061): every good relay frame of the tap is a
    -- request, a good lines frame or a no-source frame; the scenario has
    -- a bad-FCS lines frame, frames off our VLAN and frames for machine 0
    -- (local, own video: not taken)
    report "relay counters: req " & integer'image(to_integer(c_req)) & " lines " &
      integer'image(to_integer(c_lines)) & " bad " & integer'image(to_integer(c_bad)) & " ovf " &
      integer'image(to_integer(c_ovf)) & " nosrc " & integer'image(to_integer(c_nosrc)) & " vlan " &
      integer'image(to_integer(c_vlan)) & " long " & integer'image(to_integer(c_long)) & " foreign " &
      integer'image(to_integer(c_foreign)) & " last " & std_logic'image(l_v) & " m " &
      integer'image(to_integer(l_m)) & " sc " & integer'image(to_integer(unsigned(l_sc)));
    assert c_req + c_lines + c_nosrc = tapfr report "relay counters do not add up to tap frames" severity failure;
    assert c_bad >= 1 and c_vlan >= 3 and c_foreign >= 1 and c_ovf = 0 and l_v = '1'
      report "relay counters unexpected" severity failure;
    report "tb_thumb_rx PASSED (frame-level); tap frames " & integer'image(to_integer(tapfr));
    fin <= true;
    wait;
  end process;
end architecture;
