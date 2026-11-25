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
-- Thumbnail store layout (issue 0035): RGB565, 8 pixels per 16-byte word,
-- pixel 0 of a word in bits 15..0. One 256 KiB buffer per (machine, buf):
--   word address = (machine * 2 + buf) * 16384 + row * 64 + col / 8
-- (row stride 1 KiB; 360x240 uses 45 words of each row).
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

  -- thumbnail store
  constant THUMB_W        : natural := 360;
  constant THUMB_H        : natural := 240;
  constant THUMB_ROW_WORDS: natural := 64;    -- row stride in 16-byte words
  constant THUMB_MACHINES : natural := 32;    -- machine numbers 0..31
  constant THUMB_BUF_WORDS: natural := 16384; -- 256 KiB per buffer

  function thumb_addr(machine : unsigned(4 downto 0); buf : std_logic;
                      row : unsigned(7 downto 0); word : unsigned(5 downto 0))
    return unsigned;
end package;

package body mem_pkg is
  function thumb_addr(machine : unsigned(4 downto 0); buf : std_logic;
                      row : unsigned(7 downto 0); word : unsigned(5 downto 0))
    return unsigned is
    variable a : unsigned(MEM_AW - 1 downto 0) := (others => '0');
  begin
    a(19 downto 14) := machine & buf;
    a(13 downto 6)  := row;
    a(5 downto 0)   := word;
    return a;
  end function;
end package body;
