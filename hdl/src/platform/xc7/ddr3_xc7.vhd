-- ddr3_xc7: DDR3 frame store on the Mimas A7 (issue 0034, ADR 0013).
--
-- Xilinx MIG 7-series (module ddr3_mig, generated from vivado/ip/ddr3_mig.prj
-- by vivado/build.tcl): MT41J128M16 x16 on bank 34, 400 MHz memory clock
-- (800 MT/s), 4:1, 100 MHz UI clock, native interface. Its PLL/MMCM sit in
-- the bank-34 CMT (X1Y0, LOCed by the MIG XDC). sys_clk is the existing
-- 200 MHz clk_ref (BUFG), also the MIG's IDELAYCTRL reference ("Use System
-- Clock"). The vendor-neutral mem_app_bridge crosses to clk_sys and holds
-- ready='0' until calibration completes.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mem_pkg.all;

entity ddr3_xc7 is
  port (
    sys_clk    : in    std_logic;    -- 200 MHz, on a BUFG
    sys_rst    : in    std_logic;    -- active high (e.g. not MMCM locked)
    clk        : in    std_logic;    -- clk_sys
    req        : in    mem_req_t;
    rsp        : out   mem_rsp_t;
    calibrated : out   std_logic;    -- clk_sys domain
    -- DDR3 pins (names as in the MIG XDC)
    ddr3_dq      : inout std_logic_vector(15 downto 0);
    ddr3_dqs_p   : inout std_logic_vector(1 downto 0);
    ddr3_dqs_n   : inout std_logic_vector(1 downto 0);
    ddr3_addr    : out   std_logic_vector(13 downto 0);
    ddr3_ba      : out   std_logic_vector(2 downto 0);
    ddr3_ras_n   : out   std_logic;
    ddr3_cas_n   : out   std_logic;
    ddr3_we_n    : out   std_logic;
    ddr3_reset_n : out   std_logic;
    ddr3_ck_p    : out   std_logic_vector(0 downto 0);
    ddr3_ck_n    : out   std_logic_vector(0 downto 0);
    ddr3_cke     : out   std_logic_vector(0 downto 0);
    ddr3_cs_n    : out   std_logic_vector(0 downto 0);
    ddr3_dm      : out   std_logic_vector(1 downto 0);
    ddr3_odt     : out   std_logic_vector(0 downto 0)
  );
end entity;

architecture rtl of ddr3_xc7 is
  component ddr3_mig
    port (
      ddr3_dq             : inout std_logic_vector(15 downto 0);
      ddr3_dqs_p          : inout std_logic_vector(1 downto 0);
      ddr3_dqs_n          : inout std_logic_vector(1 downto 0);
      ddr3_addr           : out   std_logic_vector(13 downto 0);
      ddr3_ba             : out   std_logic_vector(2 downto 0);
      ddr3_ras_n          : out   std_logic;
      ddr3_cas_n          : out   std_logic;
      ddr3_we_n           : out   std_logic;
      ddr3_reset_n        : out   std_logic;
      ddr3_ck_p           : out   std_logic_vector(0 downto 0);
      ddr3_ck_n           : out   std_logic_vector(0 downto 0);
      ddr3_cke            : out   std_logic_vector(0 downto 0);
      ddr3_cs_n           : out   std_logic_vector(0 downto 0);
      ddr3_dm             : out   std_logic_vector(1 downto 0);
      ddr3_odt            : out   std_logic_vector(0 downto 0);
      app_addr            : in    std_logic_vector(27 downto 0);
      app_cmd             : in    std_logic_vector(2 downto 0);
      app_en              : in    std_logic;
      app_wdf_data        : in    std_logic_vector(127 downto 0);
      app_wdf_end         : in    std_logic;
      app_wdf_mask        : in    std_logic_vector(15 downto 0);
      app_wdf_wren        : in    std_logic;
      app_rd_data         : out   std_logic_vector(127 downto 0);
      app_rd_data_end     : out   std_logic;
      app_rd_data_valid   : out   std_logic;
      app_rdy             : out   std_logic;
      app_wdf_rdy         : out   std_logic;
      app_sr_req          : in    std_logic;
      app_ref_req         : in    std_logic;
      app_zq_req          : in    std_logic;
      app_sr_active       : out   std_logic;
      app_ref_ack         : out   std_logic;
      app_zq_ack          : out   std_logic;
      ui_clk              : out   std_logic;
      ui_clk_sync_rst     : out   std_logic;
      init_calib_complete : out   std_logic;
      sys_clk_i           : in    std_logic;
      sys_rst             : in    std_logic
    );
  end component;

  signal ui_clk, ui_rst, cal : std_logic;
  signal app_addr : std_logic_vector(27 downto 0);
  signal app_cmd  : std_logic_vector(2 downto 0);
  signal app_en, app_rdy, app_wren, app_wend, app_wrdy, app_rv : std_logic;
  signal app_wd, app_rd : std_logic_vector(127 downto 0);
  signal app_wm : std_logic_vector(15 downto 0);
begin
  mig : ddr3_mig
    port map (
      ddr3_dq => ddr3_dq, ddr3_dqs_p => ddr3_dqs_p, ddr3_dqs_n => ddr3_dqs_n,
      ddr3_addr => ddr3_addr, ddr3_ba => ddr3_ba, ddr3_ras_n => ddr3_ras_n,
      ddr3_cas_n => ddr3_cas_n, ddr3_we_n => ddr3_we_n, ddr3_reset_n => ddr3_reset_n,
      ddr3_ck_p => ddr3_ck_p, ddr3_ck_n => ddr3_ck_n, ddr3_cke => ddr3_cke,
      ddr3_cs_n => ddr3_cs_n, ddr3_dm => ddr3_dm, ddr3_odt => ddr3_odt,
      app_addr => app_addr, app_cmd => app_cmd, app_en => app_en,
      app_wdf_data => app_wd, app_wdf_end => app_wend, app_wdf_mask => app_wm,
      app_wdf_wren => app_wren, app_rd_data => app_rd, app_rd_data_end => open,
      app_rd_data_valid => app_rv, app_rdy => app_rdy, app_wdf_rdy => app_wrdy,
      app_sr_req => '0', app_ref_req => '0', app_zq_req => '0',
      app_sr_active => open, app_ref_ack => open, app_zq_ack => open,
      ui_clk => ui_clk, ui_clk_sync_rst => ui_rst, init_calib_complete => cal,
      sys_clk_i => sys_clk, sys_rst => sys_rst);

  br : entity work.mem_app_bridge
    generic map (APP_AW => 28)
    port map (clk => clk, req => req, rsp => rsp, calibrated => calibrated,
              ui_clk => ui_clk, ui_rst => ui_rst, calib_done => cal,
              app_addr => app_addr, app_cmd => app_cmd, app_en => app_en, app_rdy => app_rdy,
              app_wdf_data => app_wd, app_wdf_mask => app_wm, app_wdf_wren => app_wren,
              app_wdf_end => app_wend, app_wdf_rdy => app_wrdy,
              app_rd_data => app_rd, app_rd_valid => app_rv);
end architecture;
