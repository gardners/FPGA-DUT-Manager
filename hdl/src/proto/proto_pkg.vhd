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

  -- payload lengths (after the 8-byte common header)
  -- 100 fixed + 24 video block + 8 link block + 12 memory block
  -- (ADR 0005 sections 3, 3a, 3b, 8)
  constant HB_PAYLOAD_LEN   : natural := 144;
  constant ACK_PAYLOAD_LEN  : natural := 10;
  constant SNAP_PAYLOAD_LEN : natural := 680;
  constant JRESP_FIXED_LEN  : natural := 16;
  constant KBD_PAYLOAD_LEN  : natural := 10;
  constant UART_TX_FIXED    : natural := 10;
  constant JTAG_REQ_FIXED   : natural := 16;
  constant UART_TX_MAX      : natural := 1024;
  constant JTAG_MAX_BITS    : natural := 8192;

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
  constant K_HB_PERIOD    : natural := 16#0050#;
  constant K_OUT_POLICY   : natural := 16#0060#;

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

  -- defaults
  -- heartbeat byte 109, HDMI OUT shown: 0 editable, 1 no video, 2 select
  -- (console screens, issue 0029), 3 passthrough of HDMI IN (issue 0032)
  constant CON_SHOWN_PASSTHROUGH : std_logic_vector(7 downto 0) := x"03";

  constant DEFAULT_BAUD_INC : unsigned(31 downto 0) := x"0418_9375"; -- 2 Mbaud @125 MHz
  constant DEFAULT_IP_BASE  : std_logic_vector(31 downto 0) := x"C0A8_4110"; -- 192.168.65.16
end package;
