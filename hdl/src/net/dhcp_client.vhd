-- dhcp_client: RFC 2131 subset for one endpoint (ADR 0011).
--
--   INIT -> DISCOVER sent -> OFFER -> REQUEST sent -> ACK -> BOUND
--   BOUND at T1 -> REQUEST (ciaddr, broadcast) every 4 s until ACK or expiry
--   NAK or expiry -> INIT;  timeouts back off 1, 2, 4, 8, 16, 16 ... s
-- Until the first lease (and after 10 s) the endpoint uses the fallback
-- address; DHCP keeps trying in the background.
-- Frames are built by net_tx (K_DHCP) and parsed by net_rx (dhcp_rx_*).
--
-- Copyright (C) 2026 FPGA-DUT-Manager contributors. LGPL-2.1-or-later.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dhcp_client is
  generic (
    FALLBACK_MS : positive := 10_000;
    MS_PER_S    : positive := 1000      -- shortened in simulation
  );
  port (
    clk        : in  std_logic;
    tick_1ms   : in  std_logic;
    enable     : in  std_logic;          -- DHCP mode for this endpoint
    restart    : in  std_logic;          -- identity changed: start over
    xid_base   : in  std_logic_vector(31 downto 0);
    -- parsed replies (one-cycle strobe, fields valid with it)
    rx_strobe  : in  std_logic;
    rx_type    : in  std_logic_vector(7 downto 0);   -- 2 OFFER, 5 ACK, 6 NAK
    rx_xid     : in  std_logic_vector(31 downto 0);
    rx_yiaddr  : in  std_logic_vector(31 downto 0);
    rx_server  : in  std_logic_vector(31 downto 0);
    rx_lease   : in  unsigned(31 downto 0);          -- seconds, 0 = none given
    rx_t1      : in  unsigned(31 downto 0);          -- seconds, 0 = lease/2
    -- transmit request to net_tx
    tx_req     : out std_logic;                      -- level until tx_taken
    tx_taken   : in  std_logic;
    tx_type    : out std_logic_vector(7 downto 0);   -- 1 DISCOVER, 3 REQUEST
    tx_xid     : out std_logic_vector(31 downto 0);
    tx_ciaddr  : out std_logic_vector(31 downto 0);  -- renewals
    tx_reqip   : out std_logic_vector(31 downto 0);  -- option 50 (0 = omit)
    tx_server  : out std_logic_vector(31 downto 0);  -- option 54 (0 = omit)
    -- result
    bound      : out std_logic;
    lease_ip   : out std_logic_vector(31 downto 0);
    fallback   : out std_logic;                      -- no lease, use fallback
    state_o    : out unsigned(2 downto 0)
  );
end entity;

architecture rtl of dhcp_client is
  type st_t is (S_OFF, S_INIT, S_SELECTING, S_REQUESTING, S_BOUND, S_RENEWING);
  signal st      : st_t := S_OFF;
  signal xid     : unsigned(31 downto 0) := (others => '0');
  signal req     : std_logic := '0';
  signal ms      : integer range 0 to MS_PER_S := 0;
  signal sec_tick: std_logic := '0';
  signal wait_s  : unsigned(4 downto 0) := (others => '0');  -- timeout left
  signal backoff : unsigned(4 downto 0) := to_unsigned(1, 5);
  signal t1_left, exp_left : unsigned(31 downto 0) := (others => '0');
  signal infinite: std_logic := '0';
  signal ip      : std_logic_vector(31 downto 0) := (others => '0');
  signal offer_ip, server : std_logic_vector(31 downto 0) := (others => '0');
  signal have    : std_logic := '0';
  signal since   : integer range 0 to FALLBACK_MS := 0;
begin
  tx_req   <= req;
  tx_xid   <= std_logic_vector(xid);
  bound    <= have;
  lease_ip <= ip;
  fallback <= '1' when have = '0' and since = FALLBACK_MS else '0';

  with st select state_o <=
    "000" when S_OFF, "001" when S_INIT, "010" when S_SELECTING,
    "011" when S_REQUESTING, "100" when S_BOUND, "101" when S_RENEWING;

  process (clk)
    procedure send(t : std_logic_vector(7 downto 0); ci, ri, sv : std_logic_vector(31 downto 0)) is
    begin
      tx_type   <= t;
      tx_ciaddr <= ci;
      tx_reqip  <= ri;
      tx_server <= sv;
      req       <= '1';
    end procedure;
  begin
    if rising_edge(clk) then
      sec_tick <= '0';
      if tick_1ms = '1' then
        if ms = MS_PER_S - 1 then
          ms <= 0;
          sec_tick <= '1';
        else
          ms <= ms + 1;
        end if;
        if have = '0' and since < FALLBACK_MS then
          since <= since + 1;
        end if;
      end if;
      if tx_taken = '1' then
        req <= '0';
      end if;

      if enable = '0' or restart = '1' then
        st <= S_OFF; have <= '0'; req <= '0'; since <= 0;
      else
        case st is
          when S_OFF =>
            xid     <= unsigned(xid_base);
            backoff <= to_unsigned(1, 5);
            st      <= S_INIT;

          when S_INIT =>
            xid    <= xid + 1;
            send(x"01", x"00000000", x"00000000", x"00000000");
            wait_s <= backoff + 1;
            st     <= S_SELECTING;

          when S_SELECTING =>
            if rx_strobe = '1' and rx_type = x"02" and unsigned(rx_xid) = xid then
              offer_ip <= rx_yiaddr;
              server   <= rx_server;
              send(x"03", x"00000000", rx_yiaddr, rx_server);
              wait_s   <= to_unsigned(4, 5);
              st       <= S_REQUESTING;
            elsif sec_tick = '1' then
              if wait_s <= 1 then
                if backoff < 16 then backoff <= backoff(3 downto 0) & '0'; end if;
                st <= S_INIT;
              else
                wait_s <= wait_s - 1;
              end if;
            end if;

          when S_REQUESTING | S_RENEWING =>
            if rx_strobe = '1' and unsigned(rx_xid) = xid and rx_type = x"05" then
              have    <= '1';
              ip      <= rx_yiaddr;
              server  <= rx_server;
              backoff <= to_unsigned(1, 5);
              if rx_lease = 0 or rx_lease = x"FFFFFFFF" then
                infinite <= '1';
              else
                infinite <= '0';
                exp_left <= rx_lease;
                if rx_t1 /= 0 then t1_left <= rx_t1; else t1_left <= shift_right(rx_lease, 1); end if;
              end if;
              st <= S_BOUND;
            elsif rx_strobe = '1' and unsigned(rx_xid) = xid and rx_type = x"06" then
              have <= '0';
              st   <= S_INIT;
            elsif sec_tick = '1' then
              if st = S_RENEWING then
                if exp_left <= 1 then
                  have <= '0'; since <= 0; st <= S_INIT;
                else
                  exp_left <= exp_left - 1;
                  if wait_s <= 1 then
                    send(x"03", ip, x"00000000", x"00000000");   -- retry renewal
                    wait_s <= to_unsigned(4, 5);
                  else
                    wait_s <= wait_s - 1;
                  end if;
                end if;
              elsif wait_s <= 1 then
                st <= S_INIT;
              else
                wait_s <= wait_s - 1;
              end if;
            end if;

          when S_BOUND =>
            if sec_tick = '1' and infinite = '0' then
              exp_left <= exp_left - 1;
              if t1_left <= 1 then
                xid    <= xid + 1;
                send(x"03", ip, x"00000000", x"00000000");
                wait_s <= to_unsigned(4, 5);
                st     <= S_RENEWING;
              else
                t1_left <= t1_left - 1;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
