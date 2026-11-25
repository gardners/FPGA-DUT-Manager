-- i2c_expander_model: behavioural TCA9555/PCA9555 16-bit I2C IO expander
-- (simulation only). Registers: 0/1 input ports, 2/3 output ports,
-- 4/5 polarity (stored, not applied), 6/7 configuration. The register pointer
-- toggles within its pair after each data byte, as on the real part.
-- The bus lines are resolved std_logic with 'H' pull-ups supplied by the
-- testbench; the model only ever drives '0' or 'Z'.
-- Protocol errors (START/STOP later than bit 1 of a byte, or in an ACK slot
-- or while transmitting) are
-- counted in `errors`; `cfg_writes` counts data bytes written to reg 6.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_expander_model is
  generic (ADDR : std_logic_vector(6 downto 0) := "0100000");
  port (
    sda, scl   : inout std_logic;
    connected  : in  std_logic := '1';                -- '0': unplugged
    pins       : in  std_logic_vector(15 downto 0);   -- input pin levels
    out_regs   : out std_logic_vector(15 downto 0);   -- reg3 & reg2
    cfg_regs   : out std_logic_vector(15 downto 0);   -- reg7 & reg6
    cfg_writes : out natural;                          -- data bytes to reg 6
    out_writes : out natural;                          -- data bytes to reg 2
    reads      : out natural;                          -- addressed reads
    errors     : out natural
  );
end entity;

architecture sim of i2c_expander_model is
begin
  scl <= 'Z';

  process
    type st_t is (IDLE, RX, ACK_OUT, TX, ACK_IN);
    type regs_t is array (0 to 7) of std_logic_vector(7 downto 0);
    variable regs     : regs_t := (2 | 3 | 6 | 7 => x"FF", others => x"00");
    variable st       : st_t := IDLE;
    variable bitcnt   : natural := 0;
    variable sr       : std_logic_vector(7 downto 0);
    variable is_addr  : boolean := false;
    variable first    : boolean := false;
    variable rw       : std_logic := '0';
    variable ptr      : natural range 0 to 7 := 0;
    variable mack     : std_logic := '1';
    variable sda_p, scl_p, sda_x, scl_x : std_logic := '1';
    variable nerr, ncfg, nrd, nout : natural := 0;

    impure function rd(p : natural) return std_logic_vector is
    begin
      case p is
        when 0 => return to_X01(pins(7 downto 0));
        when 1 => return to_X01(pins(15 downto 8));
        when others => return regs(p);
      end case;
    end function;

    procedure drive(b : std_logic) is
    begin
      if b = '0' then sda <= '0'; else sda <= 'Z'; end if;
    end procedure;
  begin
    sda <= 'Z';
    out_regs <= regs(3) & regs(2); cfg_regs <= regs(7) & regs(6);
    cfg_writes <= 0; out_writes <= 0; reads <= 0; errors <= 0;
    loop
      wait on sda, scl, connected;
      sda_x := to_X01(sda); scl_x := to_X01(scl);
      if connected /= '1' then
        drive('1'); st := IDLE;
      elsif scl_x = '1' and scl_p = '1' and sda_x /= sda_p then
        -- START (SDA falls) or STOP (SDA rises) while SCL is high
        -- (a repeated START or a STOP follows one SCL pulse after an ACK
        -- slot, which a receiver has already counted as bit 1)
        if not (st = IDLE or (st = RX and bitcnt <= 1)) then
          nerr := nerr + 1;
          report "i2c model " & to_hstring(ADDR) & ": START/STOP inside a byte, state " & st_t'image(st) & " bit " & integer'image(bitcnt) & " sda " & std_logic'image(sda_x)
            severity warning;
        end if;
        drive('1');
        if sda_x = '0' then
          st := RX; bitcnt := 0; is_addr := true;
        else
          st := IDLE;
        end if;
      elsif scl_x = '1' and scl_p = '0' then
        -- SCL rising: sample
        case st is
          when RX     => sr := sr(6 downto 0) & sda_x; bitcnt := bitcnt + 1;
          when TX     => bitcnt := bitcnt + 1;
          when ACK_IN => mack := sda_x;
          when others => null;
        end case;
      elsif scl_x = '0' and scl_p = '1' then
        -- SCL falling: change SDA
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
                  ptr := to_integer(unsigned(sr(2 downto 0))); first := false;
                else
                  regs(ptr) := sr;
                  if ptr = 6 then ncfg := ncfg + 1; end if;
                  if ptr = 2 then nout := nout + 1; end if;
                  ptr := 2 * (ptr / 2) + (1 - ptr mod 2);
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
              ptr := 2 * (ptr / 2) + (1 - ptr mod 2);
              sr := rd(ptr); bitcnt := 0; drive(sr(7)); st := TX;
            else
              drive('1'); st := IDLE;
            end if;
          when IDLE => null;
        end case;
      end if;
      sda_p := sda_x; scl_p := scl_x;
      out_regs <= regs(3) & regs(2); cfg_regs <= regs(7) & regs(6);
      cfg_writes <= ncfg; out_writes <= nout; reads <= nrd; errors <= nerr;
    end loop;
  end process;
end architecture;
