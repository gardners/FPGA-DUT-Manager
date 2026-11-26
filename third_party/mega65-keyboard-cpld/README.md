# MEGA65 keyboard CPLD source (simulation copies)

From the MEGA65 keyboard CPLD firmware repository
(github.com/MEGA65/mega65-keyboard-cpld, cloned at
`~/Projects/mega65/mega65-keyboard-cpld`), copied by
`scripts/sync-kbd-cpld.sh` for the nvc testbenches of issue 0046 / ADR 0014:

| File | From | Entity |
|---|---|---|
| `top_2ed09bd.vhd` | `src/top.vhd` at upstream master 2ed09bd | `megakey_2ed09bd` |
| `top_type3.vhd` | `src/top.vhd` on local branch `type3` (commit in `UPSTREAM_COMMIT`) | `megakey_t3` |
| `version_sim.vhd` | stand-in for the generated `src/version.vhdl` | package `version` |

Only the entity name differs from the source. The CPLD repo is the master
copy: edit it there, commit on `type3`, then re-run the sync script. The
upstream repository carries no licence file; it is MEGA65 project code
(the owner's), used here for simulation only. The MachXO2 OSCH oscillator
is modelled by `hdl/sim/machxo2/osch_model.vhd`.
