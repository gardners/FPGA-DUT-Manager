-- mosaic_pkg: geometry shared by mosaic_display (thumbnail layer) and
-- text_display (select-screen boxes) for the live-thumbnail select screen
-- (issue 0036). Raster coordinates of the 720x480p60 console.
--
--   2x2 ("quad", <= 4 machines): tiles 320x200, block 640x400 at (40, 40)
--   4x3 (more machines):         tiles 160x100, block 640x300 at (40, 90)
-- Tile (i, j) shows machine 2j+i (2x2) or 4j+i (4x3, machines 0..9; the
-- last two tiles stay black). Each tile's selection digit sits in a
-- reverse-video box in the first text cell fully inside its top-left corner.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;

package mosaic_pkg is
  constant MOS_X0   : natural := 40;
  constant MOS_W    : natural := 640;    -- block width, both layouts
  constant MOS_Y0_Q : natural := 40;
  constant MOS_Y0_D : natural := 90;
  constant MOS_TW_Q : natural := 320;
  constant MOS_TH_Q : natural := 200;
  constant MOS_TW_D : natural := 160;
  constant MOS_TH_D : natural := 100;

  -- per-tile mode (line info from the clk_sys reader to the pixel side)
  subtype tmode_t is std_logic_vector(1 downto 0);
  constant TM_OFF   : tmode_t := "00";   -- black
  constant TM_FROWN : tmode_t := "01";   -- empty slot
  constant TM_BARS  : tmode_t := "10";   -- seen, no fresh frame (or scale mismatch)
  constant TM_THUMB : tmode_t := "11";   -- thumbnail from the frame store

  -- text pixels of exactly this colour show the thumbnail layer
  constant MOS_KEY  : std_logic_vector(23 downto 0) := x"00FF00";

  -- text cell (column, row) of tile (i, j)'s corner box, for a text area at
  -- raster (left, top) with 9x16 cells
  function mos_box_col(left : natural; quad : boolean; i : natural) return natural;
  function mos_box_row(top : natural; quad : boolean; j : natural) return natural;
end package;

package body mosaic_pkg is
  function mos_box_col(left : natural; quad : boolean; i : natural) return natural is
    variable px : natural;
  begin
    if quad then px := MOS_X0 + MOS_TW_Q * i; else px := MOS_X0 + MOS_TW_D * i; end if;
    return (px - left + 8) / 9;
  end function;
  function mos_box_row(top : natural; quad : boolean; j : natural) return natural is
    variable py : natural;
  begin
    if quad then py := MOS_Y0_Q + MOS_TH_Q * j; else py := MOS_Y0_D + MOS_TH_D * j; end if;
    return (py - top + 15) / 16;
  end function;
end package body;
