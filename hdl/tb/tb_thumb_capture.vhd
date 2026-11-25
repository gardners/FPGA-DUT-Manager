-- tb_thumb_capture: thumb_capture against mem_model (via mem_mux_model, the
-- testbench reads the store back through a second port). Small mode: 96x24
-- active, crop 64x16 (offsets 16, 4), so 1/2 scale = 32x8, 1/4 = 16x4.
--  1. 1/2 scale, every frame: two frames stored, buffers alternate, every
--     pixel equals the 2x2 box average of the source pattern; xRGB top byte 0.
--  2. 1/4 scale, div 2: 4x4 box averages, one frame in two.
--  3. thumb_tx locks the shown buffer: after at most one frame into the other
--     buffer, frames are skipped (never written into the locked one).
--  4. disabled: nothing stored.
-- The memory stalls ready one cycle in three.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity tb_thumb_capture is
end entity;

architecture tb of tb_thumb_capture is
  constant HA : natural := 96;
  constant VA : natural := 24;
  constant X0 : natural := 16;
  constant Y0 : natural := 4;
  constant M  : natural := 5;
  signal pclk, clk : std_logic := '0';
  signal fin : boolean := false;
  signal x, y : unsigned(10 downto 0);
  signal de, hs, vs, fs : std_logic;
  signal rgb : std_logic_vector(23 downto 0);
  signal enable, quarter, lock_v, lock_b : std_logic := '0';
  signal div : unsigned(3 downto 0) := to_unsigned(1, 4);
  signal cur : std_logic_vector(31 downto 0) := (others => '0');
  signal req : mem_req_arr_t(0 to 1) := (others => MEM_REQ_IDLE);
  signal rsp : mem_rsp_arr_t(0 to 1);
  signal done, dbuf, dq : std_logic;
  signal dm : unsigned(4 downto 0);
  signal drows : unsigned(7 downto 0);
  signal frames : unsigned(31 downto 0);
  signal skipped : unsigned(15 downto 0);
  signal ndone, nfs : natural := 0;

  function chan(c, px, ln : natural) return natural is
  begin
    case c is
      when 0 => return px mod 256;
      when 1 => return (ln * 7) mod 256;
      when others => return (px * 13 + ln * 29 + 3) mod 256;
    end case;
  end function;
begin
  pclk <= not pclk after 18.5 ns when not fin;
  clk  <= not clk after 4 ns when not fin;

  vt : entity work.video_timing
    generic map (H_ACTIVE => HA, H_FP => 8, H_SYNC => 8, H_BP => 8,
                 V_ACTIVE => VA, V_FP => 1, V_SYNC => 2, V_BP => 1, SYNC_POL => '0')
    port map (pclk, x, y, de, hs, vs, fs);
  rgb <= std_logic_vector(to_unsigned(chan(0, to_integer(x), to_integer(y)), 8)) &
         std_logic_vector(to_unsigned(chan(1, to_integer(x), to_integer(y)), 8)) &
         std_logic_vector(to_unsigned(chan(2, to_integer(x), to_integer(y)), 8));

  mm : entity work.mem_mux_model generic map (N => 2, ADDR_BITS => 16, LATENCY => 12, STALL_EVERY => 3)
    port map (clk => clk, req => req, rsp => rsp);

  dut : entity work.thumb_capture
    generic map (CROP_W => 64, CROP_H => 16, FIFO_AW => 5)
    port map (pclk => pclk, de => de, vs => vs, rgb => rgb, clk => clk,
              enable => enable, quarter => quarter, div => div,
              machine => to_unsigned(M, 5), cur => cur,
              lock_valid => lock_v, lock_machine => to_unsigned(M, 5), lock_buf => lock_b,
              mem_req => req(0), mem_rsp => rsp(0),
              done => done, done_machine => dm, done_buf => dbuf, done_quarter => dq,
              done_rows => drows, frames => frames, skipped => skipped);

  -- the status block's part: show the new buffer
  process (clk)
  begin
    if rising_edge(clk) then
      if done = '1' then
        cur(to_integer(dm)) <= dbuf;
        ndone <= ndone + 1;
      end if;
    end if;
  end process;
  process (pclk)
  begin
    if rising_edge(pclk) then
      if fs = '1' then nfs <= nfs + 1; end if;
    end if;
  end process;

  stim : process
    variable s : natural;
    variable w : std_logic_vector(127 downto 0);
    variable errs : natural := 0;
    variable n0, f0 : natural;

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

    procedure check(sc : natural; buf : std_logic) is
      variable tw, th, acc, got : natural;
      variable wd : std_logic_vector(127 downto 0);
    begin
      tw := 64 / sc; th := 16 / sc;
      for r in 0 to th - 1 loop
        for wi in 0 to tw / 4 - 1 loop
          rd(thumb_addr(to_unsigned(M, 5), buf, to_unsigned(r, 8), to_unsigned(wi, 7)), wd);
          for p in 0 to 3 loop
            assert wd(32 * p + 31 downto 32 * p + 24) = x"00" report "top byte not 0" severity error;
            for c in 0 to 2 loop
              acc := 0;
              for j in 0 to sc - 1 loop
                for i in 0 to sc - 1 loop
                  acc := acc + chan(c, X0 + sc * (4 * wi + p) + i, Y0 + sc * r + j);
                end loop;
              end loop;
              got := to_integer(unsigned(wd(32 * p + 23 - 8 * c downto 32 * p + 16 - 8 * c)));
              if got /= acc / (sc * sc) then
                errs := errs + 1;
                report "scale 1/" & integer'image(sc) & " row " & integer'image(r) & " col " &
                  integer'image(4 * wi + p) & " ch " & integer'image(c) & ": " & integer'image(got) &
                  " /= " & integer'image(acc / (sc * sc)) severity error;
              end if;
            end loop;
          end loop;
        end loop;
      end loop;
    end procedure;
  begin
    wait for 500 us;   -- crop offsets settle (two equal frames)
    -- 1. 1/2 scale, every frame
    enable <= '1';
    wait until ndone = 1;
    assert drows = 8 and dq = '0' and dm = M report "frame 1 descriptor" severity error;
    assert dbuf = '1' report "first frame not in buffer 1" severity error;
    check(2, '1');
    wait until ndone = 2;
    assert dbuf = '0' report "second frame not in buffer 0" severity error;
    check(2, '0');
    n0 := ndone; f0 := nfs;
    wait until nfs = f0 + 3;
    assert ndone - n0 >= 2 report "not every frame stored at div 1" severity error;
    -- 2. 1/4 scale, div 2
    quarter <= '1';
    div <= to_unsigned(2, 4);
    wait until rising_edge(clk) and done = '1' and dq = '1';
    wait until rising_edge(clk);
    assert drows = 4 report "1/4 rows" severity error;
    check(4, dbuf);
    n0 := ndone; f0 := nfs;
    wait until nfs = f0 + 8;
    assert ndone - n0 >= 3 and ndone - n0 <= 5
      report "div 2: " & integer'image(ndone - n0) & " frames stored in 8" severity error;
    -- 3. thumb_tx reads the shown buffer: at most one more frame (into the
    -- other buffer) completes, after which the next would overwrite it
    lock_b <= cur(M);
    lock_v <= '1';
    wait for 300 us;   -- a frame in flight may still finish
    n0 := ndone; f0 := nfs;
    wait until nfs = f0 + 6;
    assert ndone = n0 report "frame stored into a locked buffer" severity error;
    lock_v <= '0';
    n0 := ndone; f0 := nfs;
    wait until nfs = f0 + 6;
    assert ndone > n0 report "no frame after unlock" severity error;
    -- 4. disabled
    enable <= '0';
    wait for 300 us;
    n0 := ndone; f0 := nfs;
    wait until nfs = f0 + 4;
    assert ndone = n0 report "frame stored while disabled" severity error;
    assert errs = 0 report integer'image(errs) & " pixel errors" severity failure;
    report "tb_thumb_capture PASSED: " & integer'image(to_integer(frames)) & " frames, " &
      integer'image(to_integer(skipped)) & " skipped";
    fin <= true;
    wait;
  end process;
end architecture;
