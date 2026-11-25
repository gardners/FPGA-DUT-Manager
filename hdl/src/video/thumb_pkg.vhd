-- thumb_pkg: shared types for thumbnails (issues 0035 local capture / frame
-- store / status, 0038 relay over raw Ethernet, ADR 0005 section 10).
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package thumb_pkg is
  -- relay frames (ADR 0005 s10): EtherType 0x88B5, then version, subtype, magic
  constant TH_ETYPE    : std_logic_vector(15 downto 0) := x"88B5";
  constant TH_VERSION  : std_logic_vector(7 downto 0)  := x"01";
  constant TH_MAGIC    : std_logic_vector(15 downto 0) := x"4D36";
  constant TH_SUB_REQ  : std_logic_vector(7 downto 0)  := x"01";
  constant TH_SUB_LINES: std_logic_vector(7 downto 0)  := x"02";
  constant TH_SUB_NOSRC: std_logic_vector(7 downto 0)  := x"03";
  constant TH_REQ_LEN  : natural := 8;    -- request body after the Ethernet header
  constant TH_HDR_LEN  : natural := 22;   -- lines / no-source header after the Ethernet header
  constant TH_ENC_RAW  : std_logic_vector(7 downto 0) := x"00";   -- RGB888
  constant TH_ENC_RLE  : std_logic_vector(7 downto 0) := x"01";   -- RLE24
  -- payload budget per relay frame: lines are packed until the next one
  -- might not fit (owner: about 8 KiB frames)
  constant TH_PKT_BUDGET : natural := 8000;

  -- one relay frame for net_tx to send (thumb_tx -> net_tx)
  type thumb_pkt_t is record
    sub     : std_logic_vector(7 downto 0);   -- TH_SUB_LINES / TH_SUB_NOSRC
    d       : integer range 0 to 1;           -- sending endpoint (source MAC)
    dst     : std_logic_vector(47 downto 0);
    machine : unsigned(4 downto 0);
    flags   : std_logic_vector(7 downto 0);   -- b0 source present, b1 last frame of the picture
    scale   : std_logic_vector(7 downto 0);   -- 1 = 1/2 (320x200), 2 = 1/4 (160x100)
    enc     : std_logic_vector(7 downto 0);
    frame   : unsigned(31 downto 0);
    row     : unsigned(7 downto 0);            -- first row
    nlines  : unsigned(7 downto 0);
    height  : unsigned(7 downto 0);            -- rows in the picture
    width   : unsigned(15 downto 0);
    nbytes  : unsigned(12 downto 0);           -- payload bytes (in the packet buffer)
  end record;
  constant THUMB_PKT_NONE : thumb_pkt_t := (x"00", 0, (others => '0'), (others => '0'),
    x"00", x"00", x"00", (others => '0'), (others => '0'), (others => '0'), (others => '0'),
    (others => '0'), (others => '0'));

  -- tile width/height for a scale (quarter = '1' -> 1/4)
  function tile_w(quarter : std_logic) return natural;
  function tile_h(quarter : std_logic) return natural;
end package;

package body thumb_pkg is
  function tile_w(quarter : std_logic) return natural is
  begin
    if quarter = '1' then return 160; else return 320; end if;
  end function;
  function tile_h(quarter : std_logic) return natural is
  begin
    if quarter = '1' then return 100; else return 200; end if;
  end function;
end package body;
