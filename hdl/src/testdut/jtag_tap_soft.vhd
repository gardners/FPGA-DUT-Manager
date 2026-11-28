-- jtag_tap_soft: IEEE 1149.1 TAP in fabric for the test_dut bitstream
-- (issue 0068), oversampled in the system clock domain.
--
-- TCK/TMS/TDI are asynchronous pins, each synchronised by two flops; a
-- rising TCK edge (as seen after the synchroniser) clocks the state
-- machine and samples TMS/TDI, a falling edge updates TDO and performs the
-- Update-IR/DR actions, as the standard has them on the TCK edges. All
-- three inputs pass through identical synchronisers, so TMS/TDI keep
-- their timing relative to TCK. No TRST: the TAP starts in
-- Test-Logic-Reset (5 TMS-high clocks also get there from anywhere).
--
-- Instructions (IR length 4, Capture-IR loads "0101", LSBs 01 as the
-- standard requires):
--   0001 IDCODE  (also selected in Test-Logic-Reset) -> IDCODE generic
--   0010 USERDR  32-bit read/write data register: Capture-DR loads the
--                current value, Update-DR stores the shifted-in value
--   1111 BYPASS  (and every other opcode, including 0000)
--
-- Speed (clk = 100 MHz): TDO follows a falling TCK edge after the
-- synchroniser and one register, 3-4 clk cycles (30-40 ns), and the
-- supervisor's jtag_engine samples TDO through its own 2-flop synchroniser
-- at the end of the TCK high phase, i.e. 2 half periods after the falling
-- edge. That leaves margin down to half period 5 (12.5 MHz TCK, 80 ns
-- from fall to sample); half 4 (15.6 MHz) is marginal; dutctl's default
-- half 6 (10.4 MHz) is fine. TCK phases must be >= 2 clk cycles (20 ns).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jtag_tap_soft is
  generic (
    IDCODE : std_logic_vector(31 downto 0) := x"7E57D001"
  );
  port (
    clk      : in  std_logic;
    tck      : in  std_logic;            -- asynchronous
    tms      : in  std_logic;
    tdi      : in  std_logic;
    tdo      : out std_logic;
    in_tlr   : out std_logic;            -- state is Test-Logic-Reset
    tck_stb  : out std_logic;            -- one per rising TCK edge
    user_dr  : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of jtag_tap_soft is
  type tap_t is (TLR, RTI, SEL_DR, CAP_DR, SH_DR, EX1_DR, PA_DR, EX2_DR, UPD_DR,
                 SEL_IR, CAP_IR, SH_IR, EX1_IR, PA_IR, EX2_IR, UPD_IR);
  signal st : tap_t := TLR;

  constant I_IDCODE : std_logic_vector(3 downto 0) := "0001";
  constant I_USER   : std_logic_vector(3 downto 0) := "0010";
  constant I_BYPASS : std_logic_vector(3 downto 0) := "1111";

  signal s_tck, s_tms, s_tdi : std_logic_vector(1 downto 0) := (others => '0');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s_tck, s_tms, s_tdi : signal is "TRUE";
  signal tck_d  : std_logic := '0';

  signal ir     : std_logic_vector(3 downto 0) := I_IDCODE;
  signal ir_sr  : std_logic_vector(3 downto 0) := (others => '0');
  signal dr_sr  : std_logic_vector(31 downto 0) := (others => '0');
  signal user_r : std_logic_vector(31 downto 0) := (others => '0');
  signal tdo_r  : std_logic := '0';

  function next_state(s : tap_t; m : std_logic) return tap_t is
  begin
    case s is
      when TLR    => if m = '1' then return TLR;    else return RTI;    end if;
      when RTI    => if m = '1' then return SEL_DR; else return RTI;    end if;
      when SEL_DR => if m = '1' then return SEL_IR; else return CAP_DR; end if;
      when CAP_DR => if m = '1' then return EX1_DR; else return SH_DR;  end if;
      when SH_DR  => if m = '1' then return EX1_DR; else return SH_DR;  end if;
      when EX1_DR => if m = '1' then return UPD_DR; else return PA_DR;  end if;
      when PA_DR  => if m = '1' then return EX2_DR; else return PA_DR;  end if;
      when EX2_DR => if m = '1' then return UPD_DR; else return SH_DR;  end if;
      when UPD_DR => if m = '1' then return SEL_DR; else return RTI;    end if;
      when SEL_IR => if m = '1' then return TLR;    else return CAP_IR; end if;
      when CAP_IR => if m = '1' then return EX1_IR; else return SH_IR;  end if;
      when SH_IR  => if m = '1' then return EX1_IR; else return SH_IR;  end if;
      when EX1_IR => if m = '1' then return UPD_IR; else return PA_IR;  end if;
      when PA_IR  => if m = '1' then return EX2_IR; else return PA_IR;  end if;
      when EX2_IR => if m = '1' then return UPD_IR; else return SH_IR;  end if;
      when UPD_IR => if m = '1' then return SEL_DR; else return RTI;    end if;
    end case;
  end function;
begin
  tdo     <= tdo_r;
  in_tlr  <= '1' when st = TLR else '0';
  user_dr <= user_r;

  process (clk)
    variable m, d : std_logic;
  begin
    if rising_edge(clk) then
      s_tck <= s_tck(0) & tck;
      s_tms <= s_tms(0) & tms;
      s_tdi <= s_tdi(0) & tdi;
      tck_d <= s_tck(1);
      tck_stb <= '0';
      m := s_tms(1);
      d := s_tdi(1);

      if s_tck(1) = '1' and tck_d = '0' then          -- rising TCK
        tck_stb <= '1';
        st <= next_state(st, m);
        case st is
          when CAP_DR =>
            if ir = I_IDCODE then
              dr_sr <= IDCODE;
            elsif ir = I_USER then
              dr_sr <= user_r;
            else
              dr_sr <= (others => '0');       -- BYPASS captures 0
            end if;
          when SH_DR =>
            if ir = I_IDCODE or ir = I_USER then
              dr_sr <= d & dr_sr(31 downto 1);
            else
              dr_sr(0) <= d;                   -- 1-bit bypass register
            end if;
          when CAP_IR => ir_sr <= "0101";
          when SH_IR  => ir_sr <= d & ir_sr(3 downto 1);
          when others => null;
        end case;
      elsif s_tck(1) = '0' and tck_d = '1' then       -- falling TCK
        case st is
          when TLR    => ir <= I_IDCODE;
          when UPD_IR => ir <= ir_sr;
          when UPD_DR =>
            if ir = I_USER then
              user_r <= dr_sr;
            end if;
          when others => null;
        end case;
        if st = SH_DR then
          tdo_r <= dr_sr(0);
        elsif st = SH_IR then
          tdo_r <= ir_sr(0);
        else
          tdo_r <= '0';    -- not shifting: driven low (no tri-state, see top)
        end if;
      end if;
      -- Test-Logic-Reset selects IDCODE at once (no TCK edge needed after
      -- configuration either: ir resets to IDCODE)
      if st = TLR then
        ir <= I_IDCODE;
      end if;
    end if;
  end process;
end architecture;
