-- async_fifo: dual-clock FIFO with Gray-code pointers (issues 0035/0038).
--
-- Write side (wclk): we writes din; the writer must keep wused < 2**AW
-- (wused is conservative: the read pointer arrives late, so the FIFO only
-- looks fuller than it is).
-- Read side (rclk): first-word fall-through; rvalid/dout present the oldest
-- entry, pop (only while rvalid) removes it. Storage is a simple dual-port
-- RAM with a read enable (block RAM or LUTRAM, by size).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
  generic (AW : positive := 6; DW : positive := 8);
  port (
    wclk   : in  std_logic;
    we     : in  std_logic;
    din    : in  std_logic_vector(DW - 1 downto 0);
    wused  : out unsigned(AW downto 0);
    rclk   : in  std_logic;
    rvalid : out std_logic;
    dout   : out std_logic_vector(DW - 1 downto 0);
    pop    : in  std_logic
  );
end entity;

architecture rtl of async_fifo is
  subtype ptr_t is unsigned(AW downto 0);
  type mem_t is array (0 to 2 ** AW - 1) of std_logic_vector(DW - 1 downto 0);
  signal mem : mem_t;

  function bin2gray(b : unsigned) return std_logic_vector is
  begin
    return std_logic_vector(b xor shift_right(b, 1));
  end function;
  function gray2bin(g : std_logic_vector) return unsigned is
    variable b : std_logic_vector(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto g'low loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return unsigned(b);
  end function;

  signal wp, rp : ptr_t := (others => '0');
  signal wp_g, rp_g : std_logic_vector(AW downto 0) := (others => '0');
  signal wp_s1, wp_s2, rp_s1, rp_s2 : std_logic_vector(AW downto 0) := (others => '0');
  signal wu : ptr_t := (others => '0');
  signal ov : std_logic := '0';
  signal q  : std_logic_vector(DW - 1 downto 0) := (others => '0');

  attribute ASYNC_REG : string;
  attribute ASYNC_REG of wp_s1, wp_s2, rp_s1, rp_s2 : signal is "TRUE";
begin
  process (wclk)
  begin
    if rising_edge(wclk) then
      if we = '1' then
        mem(to_integer(wp(AW - 1 downto 0))) <= din;
        wp <= wp + 1;
        wp_g <= bin2gray(wp + 1);
      end if;
      rp_s1 <= rp_g;
      rp_s2 <= rp_s1;
      if we = '1' then
        wu <= wp + 1 - gray2bin(rp_s2);
      else
        wu <= wp - gray2bin(rp_s2);
      end if;
    end if;
  end process;

  process (rclk)
    variable fetch : boolean;
  begin
    if rising_edge(rclk) then
      wp_s1 <= wp_g;
      wp_s2 <= wp_s1;
      fetch := (ov = '0' or pop = '1') and gray2bin(wp_s2) /= rp;
      if fetch then
        q    <= mem(to_integer(rp(AW - 1 downto 0)));
        rp   <= rp + 1;
        rp_g <= bin2gray(rp + 1);
        ov   <= '1';
      elsif pop = '1' then
        ov <= '0';
      end if;
    end if;
  end process;
  wused  <= wu;
  rvalid <= ov;
  dout   <= q;
end architecture;
