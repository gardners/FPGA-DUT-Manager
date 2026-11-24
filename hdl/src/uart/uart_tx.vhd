-- 8N1 UART transmitter. Bit timing from a 32-bit phase accumulator:
-- baud = clk * baud_inc / 2^32 (e.g. 2 Mbaud at 125 MHz: 0x0418_9375).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  port (
    clk      : in  std_logic;
    baud_inc : in  unsigned(31 downto 0);
    data     : in  std_logic_vector(7 downto 0);
    valid    : in  std_logic;           -- accepted when ready = '1'
    ready    : out std_logic;
    txd      : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  signal acc     : unsigned(32 downto 0) := (others => '0');
  signal shreg   : std_logic_vector(9 downto 0) := (others => '1');
  signal bits    : integer range 0 to 10 := 0;
  signal txd_r   : std_logic := '1';
begin
  ready <= '1' when bits = 0 else '0';
  txd   <= txd_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if bits = 0 then
        if valid = '1' then
          shreg <= '1' & data & '0';    -- stop, data LSB first, start
          bits  <= 10;
          acc   <= (others => '0');
          txd_r <= '0';                 -- start bit begins now
        end if;
      else
        acc <= ('0' & acc(31 downto 0)) + ('0' & baud_inc);
        if acc(32) = '1' then
          -- one bit period elapsed
          if bits = 1 then
            bits  <= 0;
            txd_r <= '1';
          else
            bits  <= bits - 1;
            txd_r <= shreg(1);
            shreg <= '1' & shreg(9 downto 1);
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
