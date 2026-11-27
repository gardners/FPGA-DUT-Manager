-- mem_pkg: the frame-store memory port contract (issues 0034-0036).
--
-- Every client of the DDR3 frame store (thumbnail writer, network
-- thumbnail receiver, mosaic display reader, memory self-test) talks to the
-- memory subsystem through one mem_req_t/mem_rsp_t pair, synchronous to
-- clk_sys (125 MHz). The memory subsystem (issue 0034) owns arbitration and
-- the crossing to the DDR3 controller clock; clients own any crossing from
-- their own clock (pixel clocks) to clk_sys.
--
-- Handshake: a request is accepted on a clk_sys edge where req.valid = '1'
-- and rsp.ready = '1'. Reads return rsp.rvalid/rdata later, in request
-- order, one pulse per accepted read. Writes are posted. wmask bit i = '1'
-- writes byte i (bits 8i+7..8i) of the 16-byte word. A read issued after a
-- write to the same address (same port) returns the written data.
--
-- Thumbnail store layout (issues 0035/0038; owner 2026-11-25: RGB888, RAM
-- is plentiful): 32-bit xRGB, 4 pixels per 16-byte word, pixel i of a word
-- in bits 32i+23..32i (R 23..16, G 15..8, B 7..0; top byte 0). One 512 KiB
-- buffer per (machine, buf):
--   word address = (machine * 2 + buf) * 32768 + row * 128 + col / 4
-- (row stride 2 KiB, up to 512 x 256 pixels; a 320x200 tile uses 80
-- words of rows 0..199, a 160x100 tile 40 words of rows 0..99).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mem_pkg is
  constant MEM_AW : natural := 24;            -- 16-byte word address (256 MiB)

  type mem_req_t is record
    valid : std_logic;
    we    : std_logic;
    addr  : unsigned(MEM_AW - 1 downto 0);
    wdata : std_logic_vector(127 downto 0);
    wmask : std_logic_vector(15 downto 0);
  end record;

  type mem_rsp_t is record
    ready  : std_logic;
    rvalid : std_logic;
    rdata  : std_logic_vector(127 downto 0);
  end record;

  type mem_req_arr_t is array (natural range <>) of mem_req_t;
  type mem_rsp_arr_t is array (natural range <>) of mem_rsp_t;

  constant MEM_REQ_IDLE : mem_req_t := ('0', '0', (others => '0'), (others => '0'), (others => '0'));
  constant MEM_RSP_IDLE : mem_rsp_t := ('0', '0', (others => '0'));

  -- memory subsystem status for the heartbeat memory block (issue 0034,
  -- ADR 0005 section 3b), clk_sys domain
  type mem_status_t is record
    calibrated : std_logic;
    st_running : std_logic;                    -- self-test
    st_done    : std_logic;
    st_pass    : std_logic;
    errors     : unsigned(15 downto 0);        -- failing words, saturating
    dq_fail    : std_logic_vector(15 downto 0);-- bit i: DQ i read a wrong bit
    test_kib   : unsigned(15 downto 0);        -- self-test region, KiB (0 = none)
    first_err  : std_logic_vector(31 downto 0);-- word address, x"FFFFFFFF" none
  end record;
  constant MEM_STATUS_NONE : mem_status_t :=
    ('0', '0', '0', '0', (others => '0'), (others => '0'), (others => '0'), (others => '1'));

  -- thumbnail store
  constant THUMB_W        : natural := 320;  -- 1/2-scale tile (centre 640x400)
  constant THUMB_H        : natural := 200;
  constant THUMB_Q_W      : natural := 160;  -- 1/4-scale tile
  constant THUMB_Q_H      : natural := 100;
  constant THUMB_ROW_WORDS: natural := 128;   -- row stride in 16-byte words
  constant THUMB_MACHINES : natural := 32;    -- machine numbers 0..31
  constant THUMB_BUF_WORDS: natural := 32768; -- 512 KiB per buffer

  function thumb_addr(machine : unsigned(4 downto 0); buf : std_logic;
                      row : unsigned(7 downto 0); word : unsigned(6 downto 0))
    return unsigned;

  -- full-resolution relayed picture (issue 0060): three buffers above the
  -- thumbnail store, xRGB32 as above, row stride 256 words (1024 px), each
  -- in its own DDR3 bank (MIG BANK_ROW_COLUMN: word address bits 23..21 are
  -- the bank; the thumbnail store is bank 0, the self-test region bank 7),
  -- so the writer and full_display never fight over one bank's open row:
  --   word address = (1 + buf) * 0x200000 + row * 256 + col / 4
  constant FULL_BASE      : natural := 16#200000#;
  constant FULL_ROW_WORDS : natural := 256;
  constant FULL_MAX_W     : natural := 1020;   -- pixels stored per line (255 words)
  function full_addr(buf : unsigned(1 downto 0); row : unsigned(9 downto 0); word : unsigned(7 downto 0))
    return unsigned;
end package;

package body mem_pkg is
  function thumb_addr(machine : unsigned(4 downto 0); buf : std_logic;
                      row : unsigned(7 downto 0); word : unsigned(6 downto 0))
    return unsigned is
    variable a : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  begin
    a(20 downto 15) := machine & buf;
    a(14 downto 7)  := row;
    a(6 downto 0)   := word;
    return a;
  end function;

  function full_addr(buf : unsigned(1 downto 0); row : unsigned(9 downto 0); word : unsigned(7 downto 0))
    return unsigned is
    variable a : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  begin
    a(23 downto 21) := resize(buf, 3) + 1; -- bank 1 + buf
    a(17 downto 8)  := row;
    a(7 downto 0)   := word;
    return a;
  end function;
end package body;
