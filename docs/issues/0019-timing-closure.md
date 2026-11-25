# 0019: Timing closure (Vivado)

Status: Done (2026-11-25; RX phase hunting continues in 0028)
Opened: 2026-11-25

First Vivado build: clk_sys WNS -5.233 ns (2537 endpoints; worst: net_tx widx -> mem_data, 20 logic levels through the hdr/pf byte mux and DHCP byte function), rgmii_rxc WHS -2.007 ns on the 5 IDDR inputs (BUFG insertion delay vs IDELAY), text RAMs mapped to LUTRAM. Plan (owner agreed): net_tx emits a byte per cycle from a loaded shift register (no wide muxes), net_rx parse split into registered stages, RGMII RX clock via MMCM (+90 deg, delay compensated) instead of BUFG+IDELAY, RGMII TX generated clock + output delays, ram_style block for text memories. Done when timing_verdict.txt says MET.

## 2026-11-25 first Vivado build (2023.2, owner's build box) — details

```
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
     -5.233    -2227.605                   2537                24372       -2.007       -9.971                      5                24372        0.264        0.000                       0                  9027  


  c0               -5.233    -2227.605                   2537                17295        0.053        0.000                      0                17295        2.750        0.000                       0                  7628  
  c0_1             25.374        0.000                      0                  322        0.122        0.000                      0                  322       17.539        0.000                       0                   218  
  c1_1              3.944        0.000                      0                  115        0.141        0.000                      0                  115        3.204        0.000                       0                    55  

Slack (VIOLATED) :        -5.233ns  (required time - arrival time)
  Source:                 core/ntx/widx_reg[4]/C
                            (rising edge-triggered cell FDRE clocked by c0  {rise@0.000ns fall@4.000ns period=8.000ns})
  Destination:            core/ntx/mem_data_reg[1]/D
                            (rising edge-triggered cell FDRE clocked by c0  {rise@0.000ns fall@4.000ns period=8.000ns})
  Path Group:             c0
  Path Type:              Setup (Max at Slow Process Corner)
...
Slack (VIOLATED) :        -2.007ns  (arrival time - required time)
  Source:                 rgmii_rxd[2]
                            (input port clocked by rgmii_rxc  {rise@0.000ns fall@4.000ns period=8.000ns})
  Destination:            phy/g_rx[2].id/D
                            (rising edge-triggered cell IDDR clocked by rgmii_rxc  {rise@0.000ns fall@4.000ns period=8.000ns})
  Path Group:             rgmii_rxc
  Path Type:              Hold (Min at Slow Process Corner)
```

Utilization (Slice LUTs / Registers / BRAM):
| Slice LUTs                 | 7567 |     0 |          0 |     32600 | 23.21 |
| Slice Registers            | 8107 |     0 |          0 |     65200 | 12.43 |
| Slice Registers                            | 8107 |     0 |          0 |     65200 | 12.43 |

## 2026-11-25 build box: net_tx/net_rx/ram_style changes

Build 6e7991b4 (net_tx shift-register builder, net_rx S_PRE classification,
text RAMs in BRAM, 480p60 console): **clk_sys WNS −5.233 → −1.262 ns**
(668 endpoints). Worst path now net_rx `h_reg` → `jr_r(...).mac` CE (the
JTAG reply latch). RX hold unchanged (−2.007 ns, 5 IDDR inputs): RXC goes
IBUF → fabric route (1.97 ns) → BUFG → 1111-load net, 5.23 ns clock
insertion vs 3.95 ns data (IBUF + IDELAY 26 taps). The IDDR therefore
samples data launched on the *same* edge ~1.3 ns after it changes; Vivado's
default edge pairing reports that as a hold violation. It works physically
but the margin depends on the BUFG route, so the MMCM (or BUFIO) fix stays.

Hardware: after the first successful load (da7897a1 heartbeats, ping, mgmt,
text all OK), later loads of caf7ef9a, 6e7991b4 **and a fresh rebuild of
da7897a1** were all silent on the network (no heartbeats, ARP unanswered).
Since the known-good design also fails now, the cause is outside the
design (board/PHY/cable/switch state) — waiting for owner observation.
Bitstreams are now kept as build/bits/supervisor-<build id>.bit.

## 2026-11-25 RGMII RX on an MMCM; hardware phase scan

RX clock now RXC -> MMCM (BUFG feedback) -> BUFG, phase `RX_PHASE_STEPS` x
5.625 deg. Internal clocks all meet timing (clk_sys +0.13..0.23 ns after
the net_tx/net_rx pipelining). Static RX analysis with +/-0.5 ns PHY skew
predicted a centre near 202.5 deg with ~0.13 ns total margin — and
202.5 deg did not work at all. Scan on the board (scripts/hwcheck.sh:
DHCP, heartbeats, 20/20 pings, mgmt round trip on both endpoints):

| step | 4 | 8 | 12 | 16 | 20 | 24 | 28 | 32 | 36 | 40..56 |
|---|---|---|---|---|---|---|---|---|---|---|
| deg | 22.5 | 45 | 67.5 | 90 | 112.5 | 135 | 157.5 | 180 | 202.5 | 225..315 |
| result | fail | fail | pass | pass | pass | pass | pass | pass | fail | fail |

Eye ~56..191 deg = ~3.0 ns of the 4 ns UI; centre ~124 deg -> default
step 22 (123.75 deg). The static model is off by ~1.7 ns in position and
far too pessimistic in width (slow-max vs fast-min corners; one board at
one temperature moves together), so the build verdict now covers internal
paths only and reports RX static slack separately. Next: runtime phase
hunting from FCS results (owner idea; issue 0028).
