-- 8N1 UART receiver, phase-accumulator timing (see uart_tx). On a start-bit
-- edge the accumulator is preset to half a bit so samples land mid-bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  port (
    clk       : in  std_logic;
    baud_inc  : in  unsigned(31 downto 0);
    rxd       : in  std_logic;          -- asynchronous
    data      : out std_logic_vector(7 downto 0);
    valid     : out std_logic;          -- one-cycle strobe per byte
    frame_err : out std_logic           -- strobe: stop bit was 0
  );
end entity;

architecture rtl of uart_rx is
  signal rx_s   : std_logic_vector(2 downto 0) := (others => '1');
  signal acc    : unsigned(32 downto 0) := (others => '0');
  signal shreg  : std_logic_vector(7 downto 0) := (others => '0');
  signal bitn   : integer range 0 to 9 := 0;
  signal busy   : std_logic := '0';
begin
  process (clk)
    variable s : std_logic;
  begin
    if rising_edge(clk) then
      valid     <= '0';
      frame_err <= '0';
      rx_s <= rx_s(1 downto 0) & rxd;
      s := rx_s(2);

      if busy = '0' then
        if rx_s(2) = '1' and rx_s(1) = '0' then
          busy <= '1';
          bitn <= 0;
          acc  <= '0' & x"80000000";  -- half a bit to reach mid start bit
        end if;
      else
        acc <= ('0' & acc(31 downto 0)) + ('0' & baud_inc);
        if acc(32) = '1' then
          if bitn = 0 then
            if s = '1' then             -- false start
              busy <= '0';
            end if;
            bitn <= 1;
          elsif bitn <= 8 then
            shreg <= s & shreg(7 downto 1);
            bitn  <= bitn + 1;
          else
            busy <= '0';
            if s = '1' then
              data  <= shreg;
              valid <= '1';
            else
              frame_err <= '1';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
