# 0019: Timing closure (Vivado)

Status: In progress
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
