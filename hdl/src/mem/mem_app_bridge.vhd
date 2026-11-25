-- mem_app_bridge: one mem_pkg port (clk_sys) -> a MIG 7-series style
-- "application interface" (controller UI clock), issue 0034 / ADR 0013.
--
-- Vendor-neutral: it only speaks the UI handshake (app_en/app_rdy for
-- commands, app_wdf_wren/app_wdf_rdy for write data, app_rd_data_valid for
-- read data, which cannot be back-pressured), so it is simulated against a
-- behavioural controller model and used by the platform wrapper
-- (hdl/src/platform/xc7/ddr3_xc7.vhd).
--
-- Crossing: an async FIFO carries requests (we, addr, data, mask) to the UI
-- clock, another carries read data back. Read credit is kept on the clk_sys
-- side: at most 2**RD_BITS reads are in flight, so the read FIFO can never
-- overflow. Until the controller reports calibration, ready stays '0' (no
-- request is ever accepted, nothing waits on the controller), so the rest
-- of the design keeps running if DDR3 never comes up.
--
-- Addressing: mem word a (16 bytes) = 8 columns of the x16 part, so the
-- controller address is a & "000". app_wdf_mask is active high = keep.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity mem_app_bridge is
  generic (
    APP_AW  : positive := 28;
    CMD_BITS: positive := 4;          -- request FIFO depth 2**CMD_BITS
    RD_BITS : positive := 5           -- read FIFO depth / read credit
  );
  port (
    -- clk_sys side
    clk         : in  std_logic;
    req         : in  mem_req_t;
    rsp         : out mem_rsp_t;
    calibrated  : out std_logic;      -- synchronised to clk
    -- controller side (UI clock)
    ui_clk      : in  std_logic;
    ui_rst      : in  std_logic;
    calib_done  : in  std_logic;
    app_addr    : out std_logic_vector(APP_AW - 1 downto 0);
    app_cmd     : out std_logic_vector(2 downto 0);
    app_en      : out std_logic;
    app_rdy     : in  std_logic;
    app_wdf_data: out std_logic_vector(127 downto 0);
    app_wdf_mask: out std_logic_vector(15 downto 0);
    app_wdf_wren: out std_logic;
    app_wdf_end : out std_logic;
    app_wdf_rdy : in  std_logic;
    app_rd_data : in  std_logic_vector(127 downto 0);
    app_rd_valid: in  std_logic
  );
end entity;

architecture rtl of mem_app_bridge is
  constant CW : natural := 1 + MEM_AW + 128 + 16;
  constant RD_DEPTH : natural := 2 ** RD_BITS;

  -- clk_sys side
  signal cal_s    : std_logic_vector(2 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of cal_s : signal is "TRUE";
  signal cmd_full : std_logic;
  signal cmd_w    : std_logic_vector(CW - 1 downto 0);
  signal push     : std_logic;
  signal ready    : std_logic;
  signal credit   : natural range 0 to RD_DEPTH := 0;   -- reads in flight
  signal rd_empty : std_logic;
  signal rd_q     : std_logic_vector(127 downto 0);
  signal rv       : std_logic := '0';
  signal rdat     : std_logic_vector(127 downto 0) := (others => '0');

  -- UI side
  signal cmd_empty: std_logic;
  signal cmd_r    : std_logic_vector(CW - 1 downto 0);
  signal pop      : std_logic;
  signal c_we     : std_logic;
  signal cmd_done, wdf_done : std_logic := '0';
  signal en_i, wren_i : std_logic;
  signal ok       : std_logic;
begin
  ---------------------------------------------------------------- clk_sys
  process (clk)
    variable inc, dec : boolean;
  begin
    if rising_edge(clk) then
      cal_s <= cal_s(1 downto 0) & calib_done;
      inc := push = '1' and req.we = '0';
      dec := rd_empty = '0';
      if inc and not dec then
        credit <= credit + 1;
      elsif dec and not inc then
        credit <= credit - 1;
      end if;
      -- read data: pop whenever present (clients must take rvalid)
      rv <= not rd_empty;
      rdat <= rd_q;
    end if;
  end process;
  calibrated <= cal_s(2);
  ready <= '1' when cal_s(2) = '1' and cmd_full = '0' and credit < RD_DEPTH else '0';
  push  <= req.valid and ready;
  cmd_w <= req.we & std_logic_vector(req.addr) & req.wdata & req.wmask;
  rsp.ready  <= ready;
  rsp.rvalid <= rv;
  rsp.rdata  <= rdat;

  cmdq : entity work.async_fifo
    generic map (DATA_W => CW, ADDR_W => CMD_BITS)
    port map (wclk => clk, wen => push, wdata => cmd_w, wfull => cmd_full,
              rclk => ui_clk, ren => pop, rdata => cmd_r, rempty => cmd_empty);

  rdq : entity work.async_fifo
    generic map (DATA_W => 128, ADDR_W => RD_BITS)
    port map (wclk => ui_clk, wen => app_rd_valid, wdata => app_rd_data, wfull => open,
              rclk => clk, ren => '1', rdata => rd_q, rempty => rd_empty);

  ---------------------------------------------------------------- UI clock
  -- The request at the FIFO head is presented to the controller. A write
  -- puts its data into the write-data FIFO first (or in the same cycle) and
  -- only then its command, the order UG586 always allows; once both are
  -- accepted the request is popped.
  ok     <= (not cmd_empty) and (not ui_rst);
  c_we   <= cmd_r(CW - 1);
  en_i   <= ok and (not cmd_done) and ((not c_we) or wdf_done or app_wdf_rdy);
  wren_i <= ok and c_we and not wdf_done;
  pop    <= ok and (cmd_done or (en_i and app_rdy)) and
            ((not c_we) or wdf_done or (wren_i and app_wdf_rdy));

  app_en       <= en_i;
  app_cmd      <= "00" & not c_we;          -- 000 write, 001 read
  app_addr     <= std_logic_vector(resize(unsigned(cmd_r(CW - 2 downto 144)) & "000", APP_AW));
  app_wdf_wren <= wren_i;
  app_wdf_end  <= wren_i;
  app_wdf_data <= cmd_r(143 downto 16);
  app_wdf_mask <= not cmd_r(15 downto 0);

  process (ui_clk)
  begin
    if rising_edge(ui_clk) then
      if pop = '1' or ui_rst = '1' then
        cmd_done <= '0';
        wdf_done <= '0';
      else
        if en_i = '1' and app_rdy = '1' then
          cmd_done <= '1';
        end if;
        if wren_i = '1' and app_wdf_rdy = '1' then
          wdf_done <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
