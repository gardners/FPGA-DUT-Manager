-- Protocol constants mirroring docs/adrs/0005-wire-protocol-v1.md and
-- sw/dutctl/include/dutproto.h. Change all three together.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package proto_pkg is
  constant PROTO_MAGIC   : std_logic_vector(15 downto 0) := x"4D36";
  constant PROTO_VERSION : std_logic_vector(7 downto 0)  := x"01";
  constant HDR_LEN       : natural := 8;

  -- UDP ports
  constant PORT_MGMT  : natural := 6500;
  constant PORT_HB    : natural := 6501;
  constant PORT_KBD   : natural := 6502;
  constant PORT_UART  : natural := 6503;
  constant PORT_RAST  : natural := 6504;
  constant PORT_AUDIO : natural := 6505;
  constant PORT_JTAG  : natural := 6507;
  constant PORT_TEXT  : natural := 6508;
  constant PORT_DHCP_S : natural := 67;
  constant PORT_DHCP_C : natural := 68;

  -- packet types
  constant T_HEARTBEAT : std_logic_vector(7 downto 0) := x"01";
  constant T_MGMT_SET  : std_logic_vector(7 downto 0) := x"10";
  constant T_MGMT_ACK  : std_logic_vector(7 downto 0) := x"11";
  constant T_KBD_SET   : std_logic_vector(7 downto 0) := x"20";
  constant T_UART_TX   : std_logic_vector(7 downto 0) := x"30";
  constant T_UART_SNAP : std_logic_vector(7 downto 0) := x"31";
  constant T_JTAG_REQ  : std_logic_vector(7 downto 0) := x"40";
  constant T_JTAG_RESP : std_logic_vector(7 downto 0) := x"41";
  constant T_TEXT_WRITE: std_logic_vector(7 downto 0) := x"50";
  constant T_RASTER    : std_logic_vector(7 downto 0) := x"60";

  -- raster format v1 (ADR 0005 section 8): 44 fixed bytes after the common
  -- header, then the pixels
  constant RASTER_VERSION   : std_logic_vector(7 downto 0) := x"01";
  constant RASTER_FIXED_LEN : natural := 44;

  -- capabilities word (heartbeat byte 32): b7 thumbnails (issues 0035/0038)
  constant CAP_THUMBS : natural := 7;
  -- b8 JTAG to the physical keyboard's CPLD (JTAG_REQ flags b1, ADR 0014)
  constant CAP_KBD_JTAG : natural := 8;
  -- JTAG_REQ flags (offset 18): b0 abort/reset session, b1 target = the
  -- physical keyboard's CPLD; JTAG_RESP byte 17 = target (0 DUT, 1 keyboard)
  constant JF_ABORT  : natural := 0;
  constant JF_KBD    : natural := 1;
  -- heartbeat byte 40 target_flags: b0 kbd 3V3, b1 VIO, b2 outputs enabled,
  -- b3 sense valid, b4 shield power-off hold (issue 0056)
  constant TF_PWR_HOLD : natural := 4;
  -- heartbeat byte 76 kbd_phys_type: 0 none, 1 MK-I, 2 MK-II, 3 type 3
  constant PHYS_TYPE3 : std_logic_vector(7 downto 0) := x"03";

  -- payload lengths (after the 8-byte common header)
  -- 100 fixed + 24 video block + 8 link block + 12 memory block + 8
  -- shield block + 28 relay block + 8 relay receive load + 12 network block
  -- + 28 neighbour block (ADR 0005 sections 3, 3a, 3b, 3c, 3d, 3e, 3f, 8)
  constant HB_PAYLOAD_LEN   : natural := 228;
  -- heartbeat byte 208 nb_flags (ADR 0005 section 3f, issue 0069)
  constant NBF_BUILD    : natural := 0;   -- bitstream has the neighbour link
  constant NBF_PRESENT  : natural := 1;   -- valid HELLO from another board in the last ~350 ms
  constant NBF_CLASH    : natural := 2;   -- present and the peer has the same B (DIP[7:4])
  constant NBF_LOOPBACK : natural := 3;   -- own HELLO heard back (TX looped to RX)
  constant NBF_HEARD_US : natural := 4;   -- present and the peer says it hears us
  constant NBF_VALID    : natural := 5;   -- bytes 210..223 / 234 hold a received HELLO
  constant NBF_MISMATCH : natural := 6;   -- present and the peer's role claim does not complement ours
  -- heartbeat byte 184 relay_flags (ADR 0005 section 3d, issue 0061)
  constant RLF_FULL_WANT  : natural := 0;   -- full view wanted (selected target without local video)
  constant RLF_FULL_FRESH : natural := 1;   -- a full picture in the last second (shown)
  constant RLF_FULL_STALE : natural := 2;   -- wanted, but no full picture in the last second
  constant RLF_LAST_VALID : natural := 3;   -- bytes 185/186 valid
  constant RLF_LAST_NOSRC : natural := 4;   -- the last relay frame was "present, no source"
  constant RLF_STREAMING  : natural := 5;   -- our own source is streaming
  constant ACK_PAYLOAD_LEN  : natural := 10;
  constant SNAP_PAYLOAD_LEN : natural := 680;
  constant JRESP_FIXED_LEN  : natural := 16;
  constant KBD_PAYLOAD_LEN  : natural := 10;
  constant UART_TX_FIXED    : natural := 10;
  constant JTAG_REQ_FIXED   : natural := 16;
  constant UART_TX_MAX      : natural := 1024;
  -- largest JTAG_REQ an RX slot holds: 2047 bytes incl. FCS -> UDP payload
  -- <= 2001 = 24 + 2 * 988 bytes (issue 0059); larger ones get JS_BAD_FMT
  constant JTAG_MAX_BITS    : natural := 7904;

  -- management keys
  constant K_MAC          : natural := 16#0001#;
  constant K_IP           : natural := 16#0002#;
  constant K_DEST_IP      : natural := 16#0003#;
  constant K_DEST_MAC     : natural := 16#0004#;
  constant K_IDENTITY     : natural := 16#0005#;
  constant K_DHCP_EN      : natural := 16#0006#;
  constant K_UART_BAUD    : natural := 16#0010#;
  constant K_UART_FAST    : natural := 16#0011#;
  constant K_UART_SNAP_EN : natural := 16#0012#;
  constant K_UART_PERIOD  : natural := 16#0013#;
  constant K_KBD_POLICY   : natural := 16#0020#;
  constant K_KBD_OVERRIDE : natural := 16#0021#;
  constant K_KBD_TARGET   : natural := 16#0030#;
  constant K_VID_TARGET   : natural := 16#0031#;
  constant K_COUPLED      : natural := 16#0032#;
  constant K_PK_LED_MODE  : natural := 16#0033#;  -- physical kbd LEDs: 0 status, 1 DUT, 2 host
  constant K_PK_LED_HOST  : natural := 16#0034#;  -- 12-byte LED vector for mode 2
  constant K_CON_SCREEN   : natural := 16#0035#;  -- console: 0 auto, 1 editable, 2 no video, 3 select
  constant K_CAPTURE_EN   : natural := 16#0040#;
  constant K_THUMB_FORCE  : natural := 16#0041#;  -- thumbnail relay to MAC(6) scale(1) div(1); MAC 0 = off
  constant K_VLAN         : natural := 16#0043#;  -- inter-board VLAN ID u16 0..4094 (default 1650, 0 = untagged), issue 0060
  constant K_HDMI_OWNER   : natural := 16#0044#;  -- HDMI IN owner: 0 follows the video target, 1 DUT0, 2 DUT1, 3 none (issue 0060)
  constant K_RELAY_VIEW   : natural := 16#0045#;  -- relayed full view: 0 complete pictures, 1 live line by line (default), issue 0060
  constant K_HOST_VLAN    : natural := 16#0046#;  -- host VLAN ID u16 0..4094 (default 0 = untagged), issue 0062
  constant K_VLAN_BASE    : natural := 16#0047#;  -- VLAN subnet base IPv4 (/24, last octet 0; default 10.231.50.0), issue 0063
  constant K_HB_PERIOD    : natural := 16#0050#;
  constant K_OUT_POLICY   : natural := 16#0060#;  -- 0 auto (sense), 1 UART/KIO10 on, 2 all off incl. JTAG (issue 0056)
  constant K_PK_JTAG      : natural := 16#0061#;  -- physical kbd CPLD JTAG: 0 auto, 1 on, 2 off, 3 on + JTAGEN low (ADR 0014)
  constant K_PWR_CTL      : natural := 16#0062#;  -- shield power CTRL0..7 bitmask (bit n = power-board output n), issue 0049
  constant K_KJ_QUIET     : natural := 16#0063#;  -- kbd JTAG quiet: 0 off, 1 (default) pause the kbd host during kbd JTAG, 2 kbd host stopped (issue 0054)
  constant K_TDO_VOTE     : natural := 16#0064#;  -- JTAG TDO sampling: 0 single, 1 majority of 3 (half >= 4), 2 of 5 (half >= 6) (issue 0054)

  -- MGMT_ACK status
  constant ST_OK        : std_logic_vector(7 downto 0) := x"00";
  constant ST_BAD_KEY   : std_logic_vector(7 downto 0) := x"01";
  constant ST_BAD_LEN   : std_logic_vector(7 downto 0) := x"02";
  constant ST_BAD_VALUE : std_logic_vector(7 downto 0) := x"03";
  constant ST_DUPLICATE : std_logic_vector(7 downto 0) := x"04";

  -- JTAG_RESP status (also jtag_engine dec codes, see jtag_engine.vhd)
  constant JS_DONE      : std_logic_vector(7 downto 0) := x"00";
  constant JS_BUSY      : std_logic_vector(7 downto 0) := x"01";
  constant JS_BAD_SEQ   : std_logic_vector(7 downto 0) := x"02";
  constant JS_BAD_FMT   : std_logic_vector(7 downto 0) := x"03";
  constant JS_UNPOWERED : std_logic_vector(7 downto 0) := x"04";

  -- heartbeat byte 108, video_flags bits (ADR 0005 section 8)
  constant VF_CLOCK   : natural := 0;   -- TMDS clock present
  constant VF_LOCKED  : natural := 1;   -- aligned + decoding
  constant VF_CAPTURE : natural := 2;   -- capture enabled
  constant VF_HDMI    : natural := 3;   -- HDMI preambles seen (issue 0040)
  constant VF_ISLANDS : natural := 4;   -- data islands seen (issue 0040)

  -- heartbeat byte 152, shield_flags bits (ADR 0005 section 3c, issue 0049)
  constant SF_BUILD    : natural := 0;   -- bitstream has the shield I2C master
  constant SF_PROBED   : natural := 1;   -- first probe of expander A finished
  constant SF_PRESENT  : natural := 2;   -- expander A answered (revision/features valid)
  constant SF_SENSE    : natural := 3;   -- last poll of expander B succeeded (sense valid)
  constant SF_PWRB     : natural := 4;   -- power board PRESENT (valid with SF_SENSE)
  constant SF_ADOPTED  : natural := 5;   -- CTRL state kept from before a reconfiguration

  -- defaults
  -- heartbeat byte 109, HDMI OUT shown: 0 editable, 1 no video, 2 select
  -- (console screens, issue 0029), 3 passthrough of HDMI IN (issue 0032)
  constant CON_SHOWN_PASSTHROUGH : std_logic_vector(7 downto 0) := x"03";
  -- 4: full-resolution relayed picture of the video target (issue 0060)
  constant CON_SHOWN_RELAYED     : std_logic_vector(7 downto 0) := x"04";

  constant DEFAULT_VLAN : unsigned(11 downto 0) := to_unsigned(1650, 12);   -- key 0x0043 (issue 0060)
  constant DEFAULT_VLAN_BASE : std_logic_vector(31 downto 0) := x"0AE7_3200"; -- key 0x0047: 10.231.50.0 (issue 0063)

  constant DEFAULT_BAUD_INC : unsigned(31 downto 0) := x"0418_9375"; -- 2 Mbaud @125 MHz
  constant DEFAULT_IP_BASE  : std_logic_vector(31 downto 0) := x"C0A8_4110"; -- 192.168.65.16
end package;
