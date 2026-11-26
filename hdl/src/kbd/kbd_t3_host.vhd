-- kbd_t3_host: host side of MEGA65 keyboard type 3 (ADR 0014, issue 0046):
-- an asynchronous 8N1 UART at 2 Mb/s for keyboard cables up to 3 m.
--
-- KIO9 (txd) carries host -> keyboard byte pairs, KIO10 (rxd) keyboard ->
-- host pairs; KIO8 is held low by kbd_phys_host while this block is used.
-- A pair is an address byte (bit 7 = 1, 7-bit word address) and a data byte
-- (bit 7 = 0, 7-bit word), back to back.
--
-- Words 1..19, in order, carry the 128 bits of the MK-I frames in MK-I
-- order: word w bit b = stream bit i = 7(w-1)+b (bits >= 128 are padding).
-- Host -> keyboard: the control frame C = x"00000000" & leds as
-- kbd_mk1_host shifts it out, C(127) first: stream bit i = C(127 - i); the
-- keyboard latches it after word 19 (words must arrive in order). Word 20
-- = lock LED override (lock_ovr); word 127 = sync (data 0), sent as every
-- fourth pair: its 9-bit low run is the keyboard's auto-baud reference
-- (address 0 is never used, so no other byte has a low run that long).
--
-- Keyboard -> host: stream bit i = MK-I frame bit F(i) (F(k) = key k for
-- k < 82, active low; 82..95 date; 96..127 commit id); word 20 = lock
-- state, word 21 = protocol version. A frame is published (strobe) when
-- word 19 arrives and all of words 1..19 were received since the last
-- publication. `present` = a frame was published within LOSS_CYCLES.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_t3_host is
  generic (
    BIT_CYCLES  : positive := 62;            -- 125 MHz / 62 = 2.016 Mb/s
    LOSS_CYCLES : positive := 1_250_000      -- 10 ms at 125 MHz
  );
  port (
    clk        : in  std_logic;
    enable     : in  std_logic;              -- '0': txd idle high, present '0'
    txd        : out std_logic;              -- to KIO9
    rxd        : in  std_logic;              -- from KIO10 (asynchronous)
    leds       : in  std_logic_vector(95 downto 0);
    lock_ovr   : in  std_logic_vector(3 downto 0) := "0000";
    pressed    : out std_logic_vector(79 downto 0);
    strobe     : out std_logic;
    present    : out std_logic;
    kbd_commit : out std_logic_vector(31 downto 0);
    kbd_date   : out std_logic_vector(13 downto 0);
    locks      : out std_logic_vector(3 downto 0);   -- word 20 from the keyboard
    version    : out std_logic_vector(6 downto 0);   -- word 21 from the keyboard
    rx_errors  : out unsigned(15 downto 0)           -- framing errors, orphan data bytes
  );
end entity;

architecture rtl of kbd_t3_host is
  constant SYNC_ADDR : natural := 127;

  -- transmitter
  signal tdiv   : integer range 0 to BIT_CYCLES - 1 := 0;
  signal tbit   : integer range 0 to 19 := 19;
  signal tsh    : std_logic_vector(19 downto 0) := (others => '1');
  signal tslot  : unsigned(1 downto 0) := "00";
  signal tword  : integer range 1 to 20 := 1;
  signal txd_r  : std_logic := '1';

  -- receiver
  signal rs     : std_logic_vector(2 downto 0) := "111";
  signal rbusy  : std_logic := '0';
  signal rdiv   : integer range 0 to BIT_CYCLES - 1 := 0;
  signal rbit   : integer range 0 to 9 := 0;
  signal rsh    : std_logic_vector(7 downto 0) := (others => '0');
  signal raddr  : std_logic_vector(6 downto 0) := (others => '0');
  signal raok   : std_logic := '0';
  signal frame  : std_logic_vector(132 downto 0) := (others => '1');
  signal seen   : std_logic_vector(19 downto 1) := (others => '0');
  signal loss   : integer range 0 to LOSS_CYCLES := LOSS_CYCLES;
  signal errs   : unsigned(15 downto 0) := (others => '0');
  signal locks_r   : std_logic_vector(3 downto 0) := "0000";
  signal version_r : std_logic_vector(6 downto 0) := (others => '0');
begin
  txd       <= txd_r;
  present   <= '1' when loss /= LOSS_CYCLES else '0';
  locks     <= locks_r;
  version   <= version_r;
  rx_errors <= errs;

  process (clk)
    variable c    : std_logic_vector(127 downto 0);
    variable wd   : std_logic_vector(6 downto 0);
    variable a    : natural range 0 to 127;
    variable w    : natural range 1 to 20;
  begin
    if rising_edge(clk) then
      strobe <= '0';

      ---------------------------------------------------------- transmitter
      if enable = '0' then
        txd_r <= '1';
        tdiv  <= 0;
        tbit  <= 19;
        tslot <= "00";
      elsif tdiv /= BIT_CYCLES - 1 then
        tdiv <= tdiv + 1;
      else
        tdiv <= 0;
        if tbit /= 19 then
          tbit  <= tbit + 1;
          txd_r <= tsh(tbit + 1);
        else
          -- next pair: sync every fourth pair, else the next word
          c := x"00000000" & leds;
          if tslot = "00" then
            a  := SYNC_ADDR;
            wd := (others => '0');
          else
            w := tword;
            a := w;
            if w <= 19 then
              wd := (others => '0');
              for ww in 1 to 19 loop
                if w = ww then
                  for b in 0 to 6 loop
                    if 7 * (ww - 1) + b <= 127 then
                      wd(b) := c(127 - (7 * (ww - 1) + b));
                    end if;
                  end loop;
                end if;
              end loop;
            else
              wd := "000" & lock_ovr;
            end if;
            if tword = 20 then
              tword <= 1;
            else
              tword <= tword + 1;
            end if;
          end if;
          tslot <= tslot + 1;
          -- LSB first: start, addr(6:0), '1', stop, start, data(6:0), '0', stop
          tsh   <= '1' & '0' & wd & '0' & '1' & '1' & std_logic_vector(to_unsigned(a, 7)) & '0';
          tbit  <= 0;
          txd_r <= '0';
        end if;
      end if;

      ---------------------------------------------------------- receiver
      rs <= rs(1 downto 0) & rxd;
      if loss /= LOSS_CYCLES then
        loss <= loss + 1;
      end if;
      if enable = '0' then
        rbusy <= '0';
        raok  <= '0';
        seen  <= (others => '0');
        loss  <= LOSS_CYCLES;
      elsif rbusy = '0' then
        if rs(2) = '1' and rs(1) = '0' then
          rbusy <= '1';
          rbit  <= 0;
          rdiv  <= BIT_CYCLES / 2;
        end if;
      elsif rdiv /= BIT_CYCLES - 1 then
        rdiv <= rdiv + 1;
      else
        rdiv <= 0;
        if rbit = 0 then
          if rs(1) = '1' then
            rbusy <= '0';                         -- glitch
          end if;
          rbit <= 1;
        elsif rbit /= 9 then
          rsh  <= rs(1) & rsh(7 downto 1);
          rbit <= rbit + 1;
        else
          rbusy <= '0';
          if rs(1) = '0' then
            raok <= '0';
            errs <= errs + 1;
          elsif rsh(7) = '1' then
            raddr <= rsh(6 downto 0);
            raok  <= '1';
          elsif raok = '0' then
            errs <= errs + 1;
          else
            raok <= '0';
            a := to_integer(unsigned(raddr));
            for ww in 1 to 19 loop
              if a = ww then
                frame(7 * (ww - 1) + 6 downto 7 * (ww - 1)) <= rsh(6 downto 0);
                seen(ww) <= '1';
              end if;
            end loop;
            if a = 20 then
              locks_r <= rsh(3 downto 0);
            end if;
            if a = 21 then
              version_r <= rsh(6 downto 0);
            end if;
            if a = 19 then
              seen <= (others => '0');
              if seen(18 downto 1) = (18 downto 1 => '1') then
                -- word 19 holds no key bits (frame bits 126..132), so the
                -- registered frame is complete here
                for k in 0 to 79 loop
                  pressed(k) <= not frame(k);
                end loop;
                kbd_date   <= frame(95 downto 82);
                kbd_commit(29 downto 0) <= frame(125 downto 96);
                kbd_commit(31 downto 30) <= rsh(1 downto 0);
                strobe <= '1';
                loss   <= 0;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
