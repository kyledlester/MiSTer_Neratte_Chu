# Vendored RTL

All files here are byte-identical to their upstream copies; the project never edits them. Details,
licences and reasons: [docs/REUSE_AND_LICENSES.md](../../docs/REUSE_AND_LICENSES.md).

## `t80/` - T80 Z80 core (v351)

Upstream: github.com/MiSTer-devel/ZX-Spectrum_MISTer `rtl/T80/` at
`d41751d0afc8abf75f31ff1094bf9731e7a1695c`. Authors: Daniel Wallner, MikeJ, TobiFlex, Sorgelig, brNX.
BSD-style licence (see file headers; the synthesized-form notice is reproduced in
docs/REUSE_AND_LICENSES.md).

Used files: `T80_Pack.vhd`, `T80_ALU.vhd`, `T80_Reg.vhd`, `T80_MCode.vhd`, `T80.vhd`. `T80s.vhd` is
kept for reference: `rtl/nrc/nrc_cpu.sv` instantiates `T80` directly and re-implements the T80s
strobe process (Mode 0, T2Write = 1, IOWait = 1) so that `IntE` (IFF1, needed for MAME's IFF1-gated
NMI) and the register file (`REG`) are available.

Synthesis note: T80.vhd line 393 infers a latch for `Q_reg` (upstream; harmless, present in every
MiSTer T80 build). Timing: T80-internal paths are 3-cycle multicycle paths (`NRC.sdc`), justified by
the `ce_cpu` minimum spacing of 3 `clk_sys` cycles.

## `sdram.sv` - SDRAM controller

Lineage: MiSTer-devel GBA_MiSTer `rtl/sdram.sv` @ `93790a023395bbd90e5eaf4dfb2cb5910afd55f5`
(Sorgelig, parts from hamsterworks; GPL-3.0-or-later) -> owner's Namco NA-1/NA-2 core (write byte
enables, `init` clears pending requests) -> owner's Namco NB-1 core (`CYCLES_PER_REFRESH` parameter).
Copied from `Namco_NB1_Mister/rtl/vendor/sdram.sv`, SHA-1 `a5c1f349e1dc9f23ddb600b59d95427c9f6b0500`.
Used here with `CYCLES_PER_REFRESH = 780` at 100.227 MHz: average refresh period 779 x 9.977 ns =
7.77 us <= 7.8125 us.

Only channel 1 is used (burst of 4 x 16-bit reads, single 16-bit writes with byte enables).
Behaviour relied upon: `ch1_ready` rises one cycle before the last burst word reaches `ch1_dout`
(`nrc_sdram_arb` captures one cycle later).

Simulation: ModelSim 10.5b rejects three idioms Quartus accepts; `scripts/mk_sdram_sim.py` writes a
mechanically edited copy to `build/sim/sdram_sim.sv` (same edits as the owner's NB-1 `test-m2.ps1`).

## `crt_adjust.sv` - CRT Adjust (analog geometry)

Upstream: MiSTer-CRT-Adjust by Umberto Parisi (rmonic79), GPL-3.0-or-later; byte-identical to the copy
vendored in the owner's NA-1/NA-2 and NB-1 cores (SHA-1 `ddc1b6d311f26d50cc30ce1a83df9fc539830fbc`).
Unmodified. All integration is in `rtl/nrc/nrc_crt_adjust.sv` (verified by `sim/tb/m17_crt_tb.sv`).

## `pause.v` - generic MiSTer pause

Upstream: JimmyStones/Pause_MiSTer (Jim Gregory), GPL-3.0-or-later; copied from
MiSTer-devel/Arcade-Pacman_MiSTer `rtl/pause.v` @ `6b5ccb08145eadb31912b43d53a93ed522ab34b2`
(SHA-1 `d5a5effd1bf91ae788436639bae3c63b8fe40347`). Unmodified; instantiated in `NRC.sv`.
