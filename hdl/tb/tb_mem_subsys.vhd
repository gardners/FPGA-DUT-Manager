-- tb_mem_subsys: memory subsystem (issue 0034).
--   A: mem_arbiter (3 ports: self-test + 2 traffic clients) -> mem_model.
--   B: the same through mem_app_bridge (125 MHz -> 100 MHz UI clock) into
--      a behavioural MIG UI model with random stalls.
--   C: as B with a stuck data bit: the self-test must fail, flag exactly
--      that DQ line and count every word that has the bit set.
--   D: as B with a controller that never calibrates: ready stays '0', the
--      self-test never starts, nothing is accepted and nothing hangs.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity tb_mem_subsys is
end entity;

architecture sim of tb_mem_subsys is
  constant WB : positive := 8;              -- self-test region 256 words
  constant STUCK : natural := 37;           -- -> DQ 5
  signal clk, uclk : std_logic := '0';
  signal stop : boolean := false;

  type sys_t is record
    st_run, st_done, st_pass : std_logic;
    st_err : unsigned(15 downto 0);
    st_dq  : std_logic_vector(15 downto 0);
    st_first : std_logic_vector(31 downto 0);
    c_done : boolean;
    c_err  : natural;
    calib  : std_logic;
  end record;
  type sys_arr_t is array (0 to 3) of sys_t;
  signal s : sys_arr_t;
  type b_arr_t is array (0 to 3) of boolean;
  type n_arr_t is array (0 to 3) of natural;
  signal c1_done : b_arr_t;
  signal c1_err, c1_rd, c0_rd : n_arr_t;
  signal acc_d : natural := 0;              -- D: requests accepted downstream
begin
  clk  <= not clk after 4 ns when not stop;     -- 125 MHz
  uclk <= not uclk after 5 ns when not stop;    -- 100 MHz

  g : for k in 0 to 3 generate
    signal reqs : mem_req_arr_t(0 to 2);
    signal rsps : mem_rsp_arr_t(0 to 2);
    signal req  : mem_req_t;
    signal rsp  : mem_rsp_t;
    signal cal  : std_logic;
    signal app_addr : std_logic_vector(27 downto 0);
    signal app_cmd  : std_logic_vector(2 downto 0);
    signal app_en, app_rdy, app_wren, app_wend, app_wrdy, app_rv, ui_rst, cdone : std_logic;
    signal app_wd, app_rd : std_logic_vector(127 downto 0);
    signal app_wm : std_logic_vector(15 downto 0);
  begin
    st : entity work.mem_selftest
      generic map (BASE_WORD => 4096, WORD_BITS => WB)
      port map (clk => clk, start => cal, req => reqs(0), rsp => rsps(0),
                running => s(k).st_run, done => s(k).st_done, pass => s(k).st_pass,
                errors => s(k).st_err, dq_fail => s(k).st_dq, first_err => s(k).st_first);
    c0 : entity work.mem_tb_client
      generic map (BASE => 0, COUNT => 300, SEED => 3 + k)
      port map (clk => clk, req => reqs(1), rsp => rsps(1), done => s(k).c_done,
                errors => s(k).c_err, reads => c0_rd(k));
    c1 : entity work.mem_tb_client
      generic map (BASE => 1000, COUNT => 200, SEED => 11 + k)
      port map (clk => clk, req => reqs(2), rsp => rsps(2), done => c1_done(k),
                errors => c1_err(k), reads => c1_rd(k));
    arb : entity work.mem_arbiter
      generic map (N => 3)
      port map (clk => clk, reqs => reqs, rsps => rsps, req => req, rsp => rsp);
    s(k).calib <= cal;

    ga : if k = 0 generate
      cal <= '1';
      mm : entity work.mem_model
        generic map (ADDR_BITS => 13, LATENCY => 17, STALL_EVERY => 5)
        port map (clk => clk, req => req, rsp => rsp);
    end generate;

    gb : if k /= 0 generate
      br : entity work.mem_app_bridge
        port map (clk => clk, req => req, rsp => rsp, calibrated => cal,
                  ui_clk => uclk, ui_rst => ui_rst, calib_done => cdone,
                  app_addr => app_addr, app_cmd => app_cmd, app_en => app_en, app_rdy => app_rdy,
                  app_wdf_data => app_wd, app_wdf_mask => app_wm, app_wdf_wren => app_wren,
                  app_wdf_end => app_wend, app_wdf_rdy => app_wrdy,
                  app_rd_data => app_rd, app_rd_valid => app_rv);
      ui : entity work.mig_ui_model
        generic map (ADDR_BITS => 13, LATENCY => 23,
                     CALIB_CYCLES => 300 * boolean'pos(k /= 3),
                     STUCK_BIT => STUCK - 1000 * boolean'pos(k /= 2), STUCK_BASE => 4096,
                     SEED => 5 * k + 1)
        port map (ui_clk => uclk, ui_rst => ui_rst, calib_done => cdone,
                  app_addr => app_addr, app_cmd => app_cmd, app_en => app_en, app_rdy => app_rdy,
                  app_wdf_data => app_wd, app_wdf_mask => app_wm, app_wdf_wren => app_wren,
                  app_wdf_end => app_wend, app_wdf_rdy => app_wrdy,
                  app_rd_data => app_rd, app_rd_valid => app_rv);
      gd : if k = 3 generate
        process (clk)
        begin
          if rising_edge(clk) then
            if req.valid = '1' and rsp.ready = '1' then acc_d <= acc_d + 1; end if;
          end if;
        end process;
      end generate;
    end generate;
  end generate;

  process
    -- words of the self-test region whose expected bit STUCK is '1' (the
    -- stuck-at-0 fault shows only there); mirrors mem_selftest's patterns
    function stuck_words return natural is
      variable n : natural := 0;
      variable x : unsigned(31 downto 0);
      variable v, e : std_logic_vector(127 downto 0);
      variable m : std_logic_vector(15 downto 0);
    begin
      for i in 0 to 2 ** WB - 1 loop
        x := to_unsigned(4096 + i, 32);
        v(31 downto 0)   := std_logic_vector(x);
        v(63 downto 32)  := std_logic_vector(not rotate_left(x, 8));
        v(95 downto 64)  := std_logic_vector(rotate_left(x, 16) xor x"A5A5_5A5A");
        v(127 downto 96) := std_logic_vector(rotate_left(x, 24) xor x"3C3C_C3C3");
        if i mod 2 = 0 then m := x"5555"; else m := x"AAAA"; end if;
        e := v;
        if m(STUCK / 8) = '1' then e := not v; end if;
        if e(STUCK) = '1' then n := n + 1; end if;
      end loop;
      return n;
    end function;
    variable t : natural := 0;
  begin
    loop
      wait until rising_edge(clk);
      t := t + 1;
      exit when (s(0).st_done and s(1).st_done and s(2).st_done) = '1' and
                s(0).c_done and s(1).c_done and s(2).c_done and
                c1_done(0) and c1_done(1) and c1_done(2);
      assert t < 200_000 report "timeout" severity failure;
    end loop;
    for k in 0 to 2 loop
      report "system " & integer'image(k) & ": self-test errors " & integer'image(to_integer(s(k).st_err)) &
             ", client reads " & integer'image(c0_rd(k)) & "/" & integer'image(c1_rd(k));
      assert s(k).c_err = 0 and c1_err(k) = 0 report "client data errors" severity failure;
      assert c0_rd(k) > 300 and c1_rd(k) > 200 report "too few client reads" severity failure;
    end loop;
    for k in 0 to 1 loop
      assert s(k).st_pass = '1' and s(k).st_err = 0 and s(k).st_dq = x"0000" and
             s(k).st_first = x"FFFFFFFF"
        report "self-test failed on a good memory, system " & integer'image(k) severity failure;
    end loop;
    assert s(2).st_pass = '0' report "self-test passed with a stuck bit" severity failure;
    assert s(2).st_dq = x"0020" report "stuck DQ not flagged as DQ5" severity failure;
    assert to_integer(s(2).st_err) = stuck_words
      report "stuck-bit error count " & integer'image(to_integer(s(2).st_err)) &
             " /= " & integer'image(stuck_words) severity failure;
    assert unsigned(s(2).st_first) >= 4096 and unsigned(s(2).st_first) < 4096 + 2 ** WB
      report "first error address outside the region" severity failure;
    -- D: uncalibrated controller
    assert s(3).calib = '0' and acc_d = 0 and s(3).st_run = '0' and s(3).st_done = '0'
      report "uncalibrated system accepted requests" severity failure;
    assert not s(3).c_done report "client finished without memory?" severity failure;
    report "tb_mem_subsys PASSED";
    stop <= true;
    wait;
  end process;
end architecture;
