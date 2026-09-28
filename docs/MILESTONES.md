# Milestones

Status values: OPEN, IN PROGRESS, DONE (sim/build evidence), HW-CONFIRMED (seen on a DE10-Nano).
Evidence and reasons for any re-ordering are recorded per milestone.

| ID | Title | Status |
|---|---|---|
| M0 | Repository / toolchain / MiSTer skeleton | DONE |
| M1 | Hardware archaeology / executable specification | DONE |
| M2 | ROM loader / MRA / external ROM model | OPEN |
| M3 | Z80 / reset / first instruction execution | OPEN |
| M4 | ROM banking + complete CPU address map | OPEN |
| M5 | Internal banking / character RAM infrastructure | OPEN |
| M6 | Interrupt / scanline framework | OPEN |
| M7 | Character DMA | OPEN |
| M8 | Palette | OPEN |
| M9 | Video timing / MiSTer pixel pipeline | OPEN |
| M10 | Character decode | OPEN |
| M11 | Background / tilemap renderer | DEFERRED (see below) |
| M12 | Sprite / object renderer | OPEN |
| M13 | Video composition / priorities | OPEN |
| M14 | Inputs / gameplay | OPEN |
| M15 | ST-0016 audio engine | OPEN |
| M16 | First complete playable core | OPEN |
| M17-M20 | Accuracy, CRT, timing closure, release | OPEN |

## M0 - Repository / toolchain / MiSTer skeleton - DONE (2026-09-28)

Toolchain: Quartus Prime Lite 17.0.0 (`C:\intelFPGA_lite\17.0`), ModelSim-Intel FPGA Starter 10.5b,
Python 3.10 (+numpy, pillow), MAME 0.289 binary. Framework: Template_MiSTer `sys/`.

Content: `NRC.sv` (emu), `rtl/nrc/nrc_pll.sv` (100.227272 MHz), `nrc_clocks.sv`, `nrc_video_timing.sv`
(455x262, 320x240), colour-bar test pattern, `NeratteChu.qpf/.qsf`, `NRC.sdc`, `files.qip`,
`scripts/build.ps1`, `scripts/sim.sh`.

Evidence:
- Full compile: 7.9 min, 0 errors, RBF 2,541,836 bytes; PLL output 100.227272 MHz (fitter report);
  all setup/hold slacks positive (core clock setup +1.806 ns, hold +0.251 ns); 8,044 ALMs (framework).
- `scripts/sim.sh m0`: **PASS M0 TIMING: 238,429 checks** - ce_pix period 14, 455x262 raster,
  320x240 active, one vblank_start per frame at (0,256), tick8 = 176/2205 clk_sys, ce_cpu min gap 3,
  8.0000 MHz average CPU clock with 25 % random stalls, no lost credits.

## M1 - Hardware archaeology - DONE (2026-09-28)

Specification: docs/MEMORY_MAP.md, docs/ST0016_VIDEO.md, docs/ST0016_AUDIO.md, docs/ARCHITECTURE.md,
docs/MAME_REFERENCE.md. Golden video model `scripts/research/st0016_ref.py` matches MAME 0.289
snapshots pixel-for-pixel (frames 2600, 3000: 76,800/76,800).

Key findings (MAME 0.289 traces, `cap/survey1`, 3600 frames incl. coin + start):
- No character DMA is ever used; character RAM (only the first 1 MiB) is filled by the CPU through
  the `EC00` window, reading banked ROM (~880 KB at boot).
- No tilemap is ever enabled: all graphics are sprites (tilemap renderer deferred = M11).
- Sprite list: ~19 entries / ~500 sublist entries / ~2,400 tiles / ~152 k pixels per frame.
- CRT registers programmed to NTSC 455x262 (60.05 Hz); ports 00/01 are a counter (MAME: random).
- IM 1; IRQ = vblank; NMI = sound sequencer tick (every 4th NMI); 5-6 NMIs/frame in MAME.
- Sound: nonlinear sample mode enabled (voice 7 reg `$1F` = `$0B`); key flags `$06`/`$07`.

Unknowns (all non-blocking for bring-up; see KNOWN_ISSUES.md): ports 00/01 counter source, NMI source,
H CRT register semantics, reg `$70` "timer", `$74` flip bits, tilemap details, precise sound curves.

## Planned M2-M4 (concrete)

- **M2**: `nrc_loader` + `nrc_sdram_arb` + vendored `sdram.sv`; MRA `mra/Neratte Chu (ver. 1.10).mra`
  building the 4 MiB extrom image (u31 @0, 512 KiB zero, u32 @100000; loader zero-fills to 3FFFFF and
  clears char RAM). Bench: loader -> real SDRAM controller -> SDRAM model, read-back of known offsets.
- **M3**: `nrc_cpu` (T80) + `nrc_st0016` bus; real ROM in simulation; compare the first N bus
  cycles / PC trace with MAME.
- **M4**: complete CPU map incl. banked ROM, sprite/palette/char windows, I/O; MAME I/O write trace of
  the first 300 frames must match the RTL trace (ports, values, order).
