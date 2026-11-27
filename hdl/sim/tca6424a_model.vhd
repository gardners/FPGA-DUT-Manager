-- tca6424a_model: behavioural TI TCA6424A 24-bit I2C IO expander
-- (simulation only; datasheet SCPS193D section 8.6).
-- Command byte: b7 = AI (auto-increment), b6..b0 = register:
--   0x00-0x02 input ports 0-2 (read only), 0x04-0x06 output ports
--   (power-up 0xFF), 0x08-0x0A polarity inversion (0x00), 0x0C-0x0E
--   configuration (0xFF = inputs); 0x03/0x07/0x0B/0x0F reserved.
-- AI = 1: after each data byte read or written, the 2 low bits advance
-- within the bank of three (reserved register skipped: 2 -> 0).
-- AI = 0: the same register is read/written every time.
-- After a repeated START the pointer is where the previous access left it.
-- Input ports read the pin level XOR polarity (output pins read back the
-- driven level). pins_out shows the levels the part drives ('Z' = input).
-- The bus lines are resolved std_logic with 'H' pull-ups supplied by the
-- testbench; the model only ever drives '0' or 'Z'.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tca6424a_model is
  generic (ADDR : std_logic_vector(6 downto 0) := "0100010");   -- 0x22
  port (
    sda, scl   : inout std_logic;
    connected  : in  std_logic := '1';                -- '0': unplugged
    pins       : in  std_logic_vector(23 downto 0);   -- external pin levels (inputs)
    pins_out   : out std_logic_vector(23 downto 0);   -- driven levels, 'Z' for inputs
    out_regs   : out std_logic_vector(23 downto 0);   -- output port 2 & 1 & 0
    cfg_regs   : out std_logic_vector(23 downto 0);   -- configuration 2 & 1 & 0
    writes     : out natural;                          -- data bytes written
    reads      : out natural;                          -- addressed reads
    errors     : out natural
  );
end entity;

architecture sim of tca6424a_model is
  type regs_t is array (0 to 15) of std_logic_vector(7 downto 0);
  signal regs_s : regs_t;
begin
  scl <= 'Z';

  g_pin : for i in 0 to 23 generate
    pins_out(i) <= 'Z' when regs_s(12 + i / 8)(i mod 8) = '1' else regs_s(4 + i / 8)(i mod 8);
  end generate;
  out_regs <= regs_s(6) & regs_s(5) & regs_s(4);
  cfg_regs <= regs_s(14) & regs_s(13) & regs_s(12);

  process
    type st_t is (IDLE, RX, ACK_OUT, TX, ACK_IN);
    variable regs     : regs_t := (4 | 5 | 6 | 12 | 13 | 14 => x"FF", others => x"00");
    variable st       : st_t := IDLE;
    variable bitcnt   : natural := 0;
    variable sr       : std_logic_vector(7 downto 0);
    variable is_addr  : boolean := false;
    variable first    : boolean := false;
    variable rw       : std_logic := '0';
    variable ptr      : natural range 0 to 15 := 0;
    variable ai       : boolean := true;
    variable mack     : std_logic := '1';
    variable sda_p, scl_p, sda_x, scl_x : std_logic := '1';
    variable nerr, nwr, nrd : natural := 0;

    impure function rd(p : natural) return std_logic_vector is
      variable v : std_logic_vector(7 downto 0);
    begin
      if p <= 2 then
        for k in 0 to 7 loop
          if regs(12 + p)(k) = '0' then
            v(k) := regs(4 + p)(k);             -- output pin: driven level
          else
            v(k) := to_X01(pins(8 * p + k));
          end if;
        end loop;
        return v xor regs(8 + p);
      end if;
      return regs(p);
    end function;

    procedure advance is
    begin
      if ai then
        if ptr mod 4 = 2 then ptr := ptr - 2; else ptr := ptr + 1; end if;
      end if;
    end procedure;

    procedure drive(b : std_logic) is
    begin
      if b = '0' then sda <= '0'; else sda <= 'Z'; end if;
    end procedure;
  begin
    sda <= 'Z';
    regs_s <= regs;
    writes <= 0; reads <= 0; errors <= 0;
    loop
      wait on sda, scl, connected;
      sda_x := to_X01(sda); scl_x := to_X01(scl);
      if connected /= '1' then
        drive('1'); st := IDLE;
      elsif scl_x = '1' and scl_p = '1' and sda_x /= sda_p then
        if not (st = IDLE or (st = RX and bitcnt <= 1)) then
          nerr := nerr + 1;
          report "tca6424a model: START/STOP inside a byte, state " & st_t'image(st)
            severity warning;
        end if;
        drive('1');
        if sda_x = '0' then
          st := RX; bitcnt := 0; is_addr := true;
        else
          st := IDLE;
        end if;
      elsif scl_x = '1' and scl_p = '0' then
        case st is
          when RX     => sr := sr(6 downto 0) & sda_x; bitcnt := bitcnt + 1;
          when TX     => bitcnt := bitcnt + 1;
          when ACK_IN => mack := sda_x;
          when others => null;
        end case;
      elsif scl_x = '0' and scl_p = '1' then
        case st is
          when RX =>
            if bitcnt = 8 then
              if is_addr then
                if sr(7 downto 1) = ADDR then
                  rw := sr(0); drive('0'); st := ACK_OUT;
                  if rw = '1' then nrd := nrd + 1; end if;
                else
                  st := IDLE;
                end if;
              else
                if first then
                  ptr := to_integer(unsigned(sr(3 downto 0)));
                  ai := sr(7) = '1'; first := false;
                  if sr(6 downto 4) /= "000" or ptr mod 4 = 3 then
                    nerr := nerr + 1;
                    report "tca6424a model: reserved command " & to_hstring(sr) severity warning;
                  end if;
                else
                  if ptr >= 4 and ptr mod 4 /= 3 then regs(ptr) := sr; end if;
                  nwr := nwr + 1;
                  advance;
                end if;
                drive('0'); st := ACK_OUT;
              end if;
            end if;
          when ACK_OUT =>
            bitcnt := 0;
            if is_addr and rw = '1' then
              is_addr := false;
              sr := rd(ptr); drive(sr(7)); st := TX;
            else
              if is_addr then first := true; end if;
              is_addr := false;
              drive('1'); st := RX;
            end if;
          when TX =>
            if bitcnt = 8 then
              drive('1'); st := ACK_IN;
            else
              drive(sr(7 - bitcnt));
            end if;
          when ACK_IN =>
            if mack = '0' then
              advance;
              sr := rd(ptr); bitcnt := 0; drive(sr(7)); st := TX;
            else
              drive('1'); st := IDLE;
            end if;
          when IDLE => null;
        end case;
      end if;
      sda_p := sda_x; scl_p := scl_x;
      regs_s <= regs;
      writes <= nwr; reads <= nrd; errors <= nerr;
    end loop;
  end process;
end architecture;
