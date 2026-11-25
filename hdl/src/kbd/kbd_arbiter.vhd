-- kbd_arbiter: keyboard ownership for one DUT (design brief section 10).
--
--  * A received UDP bitmap that differs from the previously stored one gives
--    ownership to UDP; identical retransmissions do not.
--  * While this DUT is the selected keyboard target (phys_route = '1'), a
--    physical key-down transition gives ownership to the physical keyboard
--    (subsequent releases stay physical). A physical release alone never
--    steals ownership.
--  * On becoming selected: policy 0 REQUIRE_FRESH_PRESS keeps UDP until a new
--    key-down; policy 1 ACCEPT_HELD takes physical ownership at once if any
--    key is already held.
--  * Losing the route (deselection, link loss) returns to UDP immediately,
--    with no residual physical holds.
--  * Simultaneous UDP change and physical key-down: UDP wins.
--  * override: 0 none, 1 force UDP, 2 force physical, 3 all keys up.
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_arbiter is
  port (
    clk        : in  std_logic;
    udp_strobe : in  std_logic;                      -- a KBD_SET arrived
    udp_keys   : in  std_logic_vector(79 downto 0);  -- its bitmap
    phys_route : in  std_logic;                      -- physical keyboard routed here
    phys_keys  : in  std_logic_vector(79 downto 0);
    policy     : in  std_logic_vector(7 downto 0);
    override   : in  std_logic_vector(7 downto 0);
    effective  : out std_logic_vector(79 downto 0);
    udp_stored : out std_logic_vector(79 downto 0);
    owner_phys : out std_logic
  );
end entity;

architecture rtl of kbd_arbiter is
  signal stored    : std_logic_vector(79 downto 0) := (others => '0');
  signal phys_prev : std_logic_vector(79 downto 0) := (others => '0');
  signal route_prev: std_logic := '0';
  signal own_phys  : std_logic := '0';
begin
  udp_stored <= stored;
  owner_phys <= own_phys;

  effective <= (others => '0') when override = x"03" else
               phys_keys       when (override = x"02" and phys_route = '1') else
               stored          when override = x"01" else
               phys_keys       when own_phys = '1' else
               stored;

  process (clk)
    variable keydown, udp_change : boolean;
  begin
    if rising_edge(clk) then
      keydown    := phys_route = '1' and (phys_keys and not phys_prev) /= (79 downto 0 => '0');
      udp_change := udp_strobe = '1' and udp_keys /= stored;
      if udp_strobe = '1' then
        stored <= udp_keys;
      end if;
      phys_prev  <= phys_keys;
      route_prev <= phys_route;

      if phys_route = '0' then
        own_phys <= '0';
      elsif udp_change then
        own_phys <= '0';                -- UDP wins ties
      elsif route_prev = '0' then
        -- just selected
        if policy = x"01" and phys_keys /= (79 downto 0 => '0') then
          own_phys <= '1';
        end if;
      elsif keydown then
        own_phys <= '1';
      end if;
    end if;
  end process;
end architecture;
