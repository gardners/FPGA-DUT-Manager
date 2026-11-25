-- async_fifo: small dual-clock FIFO (gray-coded pointers, 2-flop
-- synchronisers, distributed RAM). First-word fall-through: rdata is valid
-- whenever rempty = '0'; ren pops it. wfull/rempty are conservative (they
-- see the other side's pointer a few cycles late), never optimistic.
-- No reset: pointers start at zero from configuration; neither side needs
-- the other clock to be running (a stopped side just looks full/empty).
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_fifo is
  generic (
    DATA_W : positive := 8;
    ADDR_W : positive := 4        -- depth 2**ADDR_W
  );
  port (
    wclk   : in  std_logic;
    wen    : in  std_logic;       -- ignored while wfull
    wdata  : in  std_logic_vector(DATA_W - 1 downto 0);
    wfull  : out std_logic;
    rclk   : in  std_logic;
    ren    : in  std_logic;       -- ignored while rempty
    rdata  : out std_logic_vector(DATA_W - 1 downto 0);
    rempty : out std_logic
  );
end entity;

architecture rtl of async_fifo is
  subtype ptr_t is unsigned(ADDR_W downto 0);
  type mem_t is array (0 to 2 ** ADDR_W - 1) of std_logic_vector(DATA_W - 1 downto 0);
  signal mem : mem_t;
  attribute ram_style : string;
  attribute ram_style of mem : signal is "distributed";

  function to_gray(b : ptr_t) return ptr_t is
  begin
    return b xor ('0' & b(ADDR_W downto 1));
  end function;
  function from_gray(g : ptr_t) return ptr_t is
    variable b : ptr_t;
  begin
    b(ADDR_W) := g(ADDR_W);
    for i in ADDR_W - 1 downto 0 loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return b;
  end function;

  signal wptr, wgray : ptr_t := (others => '0');       -- wclk
  signal rptr, rgray : ptr_t := (others => '0');       -- rclk
  signal rgray_w1, rgray_w2 : ptr_t := (others => '0'); -- rgray in wclk
  signal wgray_r1, wgray_r2 : ptr_t := (others => '0'); -- wgray in rclk
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rgray_w1, rgray_w2, wgray_r1, wgray_r2 : signal is "TRUE";
  signal full, empty : std_logic;
begin
  -- write side
  full  <= '1' when wptr - from_gray(rgray_w2) = 2 ** ADDR_W else '0';
  wfull <= full;
  process (wclk)
  begin
    if rising_edge(wclk) then
      rgray_w1 <= rgray;
      rgray_w2 <= rgray_w1;
      if wen = '1' and full = '0' then
        mem(to_integer(wptr(ADDR_W - 1 downto 0))) <= wdata;
        wptr  <= wptr + 1;
        wgray <= to_gray(wptr + 1);
      end if;
    end if;
  end process;

  -- read side
  empty  <= '1' when rgray = wgray_r2 else '0';
  rempty <= empty;
  rdata  <= mem(to_integer(rptr(ADDR_W - 1 downto 0)));
  process (rclk)
  begin
    if rising_edge(rclk) then
      wgray_r1 <= wgray;
      wgray_r2 <= wgray_r1;
      if ren = '1' and empty = '0' then
        rptr  <= rptr + 1;
        rgray <= to_gray(rptr + 1);
      end if;
    end if;
  end process;
end architecture;
