# Reuse and licenses

Project code (`NRC.sv`, `rtl/nrc/`, `sim/`, `scripts/`, `docs/`): GPL-3.0-or-later (`LICENSE`).
No ROM data, no ROM-derived data and no MAME source code is contained in this repository. MAME
(BSD-3-Clause / GPL-2.0+ project, driver files BSD-3-Clause) is used as a behavioural reference
only; comments cite the MAME functions whose behaviour a module reproduces.

## Reused components

| Component | Files here | Upstream | Revision | Author(s) | License | Modifications |
|---|---|---|---|---|---|---|
| MiSTer framework | `sys/` (all) | github.com/MiSTer-devel/Template_MiSTer `sys/` | `3ea1134cf05d62c2b1db30362277a823d739ced2` (2026-08-26), byte-identical to the copy in the owner's Namco_NB1_Mister | Sorgelig et al. | GPL-2.0+/GPL-3.0 per file (`LICENSE.MiSTer`) | none |
| T80 Z80 core | `rtl/vendor/t80/T80.vhd`, `T80_ALU.vhd`, `T80_MCode.vhd`, `T80_Pack.vhd`, `T80_Reg.vhd`, `T80s.vhd` | github.com/MiSTer-devel/ZX-Spectrum_MISTer `rtl/T80/` | `d41751d0afc8abf75f31ff1094bf9731e7a1695c` (2026-09-22); T80 "v351" (Sorgelig: ZEXDOC/ZEXALL pass) | Daniel Wallner (2001-2002), MikeJ, TobiFlex, Sorgelig, brNX | BSD-style (source + synthesized-form notice retained; see file headers) | none. `T80s.vhd` is kept for reference only; `rtl/nrc/nrc_cpu.sv` instantiates `T80` directly and re-implements the T80s strobe process to expose `IntE` (IFF1) and `REG` |
| SDRAM controller | `rtl/vendor/sdram.sv` | MiSTer-devel GBA_MiSTer `rtl/sdram.sv` @ `93790a023395bbd90e5eaf4dfb2cb5910afd55f5` -> owner's NA-1 core (byte-enable delta) -> owner's NB-1 core (`CYCLES_PER_REFRESH` parameter) | copied from Namco_NB1_Mister, SHA-1 (as copied) `a5c1f349e1dc9f23ddb600b59d95427c9f6b0500` | Sorgelig (2015-2019), hamsterworks, Kyle Lester (deltas) | GPL-3.0-or-later | none here (NB-1 copy used as is) |
| CRT Adjust | `rtl/vendor/crt_adjust.sv` | MiSTer-CRT-Adjust (rmonic79), owner's local copy MiSTer-CRT-Adjust-master (the version vendored, byte-identical, in the owner's NA-1/NA-2 and NB-1 cores) | SHA-1 `ddc1b6d311f26d50cc30ce1a83df9fc539830fbc` | Umberto Parisi (rmonic79) | GPL-3.0-or-later | none; glue `rtl/nrc/nrc_crt_adjust.sv` is a port of the owner's NA-1/NA-2 glue (plus NB-1's read-line vertical blank and a widening-dependent H-Position limit) |
| Pause | `rtl/vendor/pause.v` | JimmyStones/Pause_MiSTer, copy in MiSTer-devel/Arcade-Pacman_MiSTer `rtl/pause.v` @ `6b5ccb08145eadb31912b43d53a93ed522ab34b2` | SHA-1 `d5a5effd1bf91ae788436639bae3c63b8fe40347` | Jim Gregory | GPL-3.0-or-later | none |
| SDRAM simulation model | `sim/models/sdr_sdram_model.sv` | owner's Namco_NB1_Mister `sim/models/` | as copied | Kyle Lester | GPL-3.0-or-later | none |
| Project structure, PLL hierarchy pattern, scripts style | - | owner's Namco_NB1_Mister / Namco_NA1_NA2_MiSTer | - | Kyle Lester | GPL-3.0 | re-written for ST-0016 |

T80 file SHA-1 (as copied): T80.vhd `d5d7e515fef7317544b5ed1dc4a28b2cc6138ee4`, T80_ALU.vhd
`67e54903573db008b1afaf17e4a035c79917ef6a`, T80_MCode.vhd `d84e9dd97b7e64ca89b818799ea5142aa6ba1a6f`,
T80_Pack.vhd `d994f6d97cab87124543ec205b4e98057c674f2d`, T80_Reg.vhd
`1c4bcf16fbb9052d059fee77f195399f4db37f73`, T80s.vhd `a51092b1c7a1a3ddd59c879cb1e75d823bc3c20c`.

## Components considered and not used

| Candidate | Why not |
|---|---|
| T80 0247 in MiSTer-devel/Arcade-Pacman_MiSTer | older revision (no v350/351 flag/timing fixes) |
| Existing ST-0016 FPGA implementation | none found (2026-09-28 web searches "ST-0016 Seta FPGA core Verilog OR VHDL OR MiSTer" and "\"Neratte Chu\" MiSTer": only MAME-related pages; the MiSTer-devel organisation and the local sibling projects contain no Seta ST-0016 work). Everything ST-0016-specific here is new. |
