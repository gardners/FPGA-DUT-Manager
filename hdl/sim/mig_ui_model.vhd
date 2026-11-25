-- mig_ui_model: behavioural MIG 7-series application (UI) interface for
-- nvc testbenches (issue 0034). Own UI clock input; init_calib_complete
-- after CALIB_CYCLES (never if CALIB_CYCLES = 0). app_rdy and app_wdf_rdy
-- drop pseudo-randomly; write data is queued and paired in order with
-- write commands (data may come before or with the command, as UG586
-- allows); reads return after LATENCY cycles, in order. STUCK_BIT >= 0
-- forces that bit of every 128-bit read word at or above STUCK_BASE to 0
-- (fault injection).
-- Addresses are in 16-bit columns (8 per 16-byte word); low ADDR_BITS of
-- the word address are stored. Simulation only.
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mig_ui_model is
  generic (
    ADDR_BITS    : positive := 16;
    LATENCY      : positive := 24;
    CALIB_CYCLES : natural := 200;
    STUCK_BIT    : integer := -1;
    STUCK_BASE   : natural := 0;          -- fault only at word addresses >= this
    SEED         : positive := 1
  );
  port (
    ui_clk       : in  std_logic;
    ui_rst       : out std_logic;
    calib_done   : out std_logic;
    app_addr     : in  std_logic_vector(27 downto 0);
    app_cmd      : in  std_logic_vector(2 downto 0);
    app_en       : in  std_logic;
    app_rdy      : out std_logic;
    app_wdf_data : in  std_logic_vector(127 downto 0);
    app_wdf_mask : in  std_logic_vector(15 downto 0);
    app_wdf_wren : in  std_logic;
    app_wdf_end  : in  std_logic;
    app_wdf_rdy  : out std_logic;
    app_rd_data  : out std_logic_vector(127 downto 0);
    app_rd_valid : out std_logic
  );
end entity;

architecture sim of mig_ui_model is
  signal rdy, wrdy : std_logic := '0';
  signal cal : std_logic := '0';
begin
  app_rdy <= rdy;
  app_wdf_rdy <= wrdy;
  calib_done <= cal;

  process (ui_clk)
    type ram_t is array (0 to 2 ** ADDR_BITS - 1) of std_logic_vector(127 downto 0);
    type pipe_t is array (1 to LATENCY) of std_logic_vector(128 downto 0);
    type wq_t is array (0 to 63) of std_logic_vector(143 downto 0);
    variable ram   : ram_t := (others => (others => '0'));
    variable pipe  : pipe_t := (others => (others => '0'));
    variable wq    : wq_t;
    variable wq_n  : natural := 0;
    variable pend_w: natural := 0;             -- write commands waiting for data
    type aq_t is array (0 to 63) of natural;
    variable aq    : aq_t;
    variable cyc   : natural := 0;
    variable lfsr  : unsigned(15 downto 0) := to_unsigned(SEED, 16);
    variable a     : natural;
    variable d     : std_logic_vector(127 downto 0);
    variable m     : std_logic_vector(15 downto 0);
    procedure do_write(addr : natural; data : std_logic_vector(127 downto 0);
                       mask : std_logic_vector(15 downto 0)) is
    begin
      for i in 0 to 15 loop
        if mask(i) = '0' then      -- MIG mask: 1 = keep the old byte
          ram(addr)(8 * i + 7 downto 8 * i) := data(8 * i + 7 downto 8 * i);
        end if;
      end loop;
    end procedure;
  begin
    if rising_edge(ui_clk) then
      cyc := cyc + 1;
      ui_rst <= '0';
      if CALIB_CYCLES /= 0 and cyc >= CALIB_CYCLES then
        cal <= '1';
      end if;
      -- read pipeline
      app_rd_valid <= pipe(1)(128);
      app_rd_data  <= pipe(1)(127 downto 0);
      for i in 1 to LATENCY - 1 loop pipe(i) := pipe(i + 1); end loop;
      pipe(LATENCY) := (others => '0');
      -- write data FIFO
      if app_wdf_wren = '1' and wrdy = '1' then
        assert app_wdf_end = '1' report "mig_ui_model: wdf_end must accompany each 4:1 BL8 word" severity error;
        wq(wq_n) := app_wdf_mask & app_wdf_data;
        wq_n := wq_n + 1;
      end if;
      -- commands
      if app_en = '1' and rdy = '1' and cal = '1' then
        a := to_integer(unsigned(app_addr(ADDR_BITS + 2 downto 3)));
        assert app_addr(2 downto 0) = "000" report "mig_ui_model: unaligned address" severity error;
        if app_cmd = "000" then
          aq(pend_w) := a;
          pend_w := pend_w + 1;
        elsif app_cmd = "001" then
          d := ram(a);
          if STUCK_BIT >= 0 and a >= STUCK_BASE then d(STUCK_BIT) := '0'; end if;
          -- reads behind queued writes see them (in-order controller)
          pipe(LATENCY) := '1' & d;
        else
          report "mig_ui_model: bad app_cmd" severity error;
        end if;
      end if;
      -- retire writes whose data has arrived
      while pend_w > 0 and wq_n > 0 loop
        do_write(aq(0), wq(0)(127 downto 0), wq(0)(143 downto 128));
        for i in 0 to 62 loop aq(i) := aq(i + 1); wq(i) := wq(i + 1); end loop;
        pend_w := pend_w - 1;
        wq_n := wq_n - 1;
      end loop;
      assert pend_w = 0 or app_en = '0' or rdy = '0' or app_cmd /= "001"
        report "mig_ui_model: read issued while a write command waits for its data" severity error;
      -- pseudo-random stalls
      lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      if cal = '1' and lfsr(2 downto 0) /= "000" then rdy <= '1'; else rdy <= '0'; end if;
      if lfsr(5 downto 3) /= "111" and wq_n < 32 then wrdy <= '1'; else wrdy <= '0'; end if;
    end if;
  end process;
end architecture;
