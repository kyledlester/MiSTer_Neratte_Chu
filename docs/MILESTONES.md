# Milestones

Status values: OPEN, IN PROGRESS, DONE (sim/build evidence), HW-CONFIRMED (seen on a DE10-Nano).
Evidence and reasons for any re-ordering are recorded per milestone.

| ID | Title | Status |
|---|---|---|
| M0 | Repository / toolchain / MiSTer skeleton | DONE |
| M1 | Hardware archaeology / executable specification | DONE |
| M2 | ROM loader / MRA / external ROM model | DONE (sim) |
| M3 | Z80 / reset / first instruction execution | DONE (sim, real ROM) |
| M4 | ROM banking + complete CPU address map | DONE (sim, boot phase) |
| M5 | Internal banking / character RAM infrastructure | DONE (sim, boot phase) |
| M6 | Interrupt / scanline framework | DONE (system sim) |
| M7 | Character DMA | IMPLEMENTED (unused by nratechu; MAME semantics), no bench |
| M8 | Palette | DONE (sim) |
| M9 | Video timing / MiSTer pixel pipeline | DONE (sim timing; build) |
| M10 | Character decode | DONE (sim, part of M12 bench) |
| M11 | Background / tilemap renderer | DEFERRED (nratechu never enables tilemaps) |
| M12 | Sprite / object renderer | DONE (sim, pixel-exact on 6 MAME frames) |
| M13 | Video composition / priorities | DONE for nratechu (sprites only; painter's order + UNUSED pen) |
| M14 | Inputs / gameplay | IMPLEMENTED, awaiting hardware |
| M15 | ST-0016 audio engine | DONE (sim, sample-exact vs model) |
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

## M2 - ROM loader / MRA - DONE (sim) 2026-09-28

`nrc_loader` (ioctl index 0, WIDE), `nrc_sdram_arb` (5 clients, fixed priority), vendored `sdram.sv`,
`mra/Neratte Chu (ver. 1.10).mra` (u31 @0, 512 KiB zero part, u32 @100000; the core zero-fills
200000-3FFFFF and the 2 MiB character RAM after the download; DIPs = MAME defaults FF/DF).
- `scripts/mra/check_mra.py`: PASS - the MRA stream (MiSTer part semantics) equals MAME's region
  byte-for-byte, CRCs match, DIP defaults equal MAME's.
- `sim.sh m2`: PASS (54,020 checks): synthetic 36 KiB stream through the real controller and SDRAM
  model, read-back of stream, zero-filled padding and char RAM, fixed-ROM BRAM mirror, no SDRAM
  protocol errors. Note: `sdram.sv` raises `ch1_ready` one cycle before the last burst word lands;
  the arbiter captures one cycle later (found while writing the arbiter, see its header).

## M3/M4/M5 - CPU, CPU map, internal banking - DONE (sim) 2026-09-28

`nrc_cpu` (T80 v351 + T80s strobes, exposes IFF1/PC), `nrc_st0016` (bus FSM with SDRAM stall +
credit catch-up, fixed-ROM BRAM, board RAM, vregs, bank registers E1-E5, sprite/palette/char windows,
sound registers, I/O mux, one-line extrom read cache).
- `sim.sh m3` (real ROM, `nrc_core` with behavioural SDRAM): the first **200,000 CPU writes (memory
  + I/O) are identical, in order, to MAME 0.289** (`scripts/mame/nrc_writes.lua`), i.e. through MAME
  frame 41 of the boot: CRT table, ROM bank switching, 170 k char-RAM window writes, sprite and
  palette RAM initialisation. Interrupts are still disabled by the game at that point (first EI at
  about frame 150), so this run does not exercise M6.

## M6 - Interrupts - DONE (system sim) 2026-09-28
`nrc_irq`: IRQ (HOLD_LINE semantics: held until the IM1 acknowledge cycle) at vblank start; NMIs at
IRQ + (16 + 64k)/384 of a frame (k = 0..5, MAME's 64-line spacing and phase), delivered only if the
T80's IFF1 is set at that instant (MAME behaviour), held low for 4 CPU clocks. All constants in one
module (docs/KNOWN_ISSUES.md U-2).

`sim.sh m6` (`m6_system_tb`: full `nrc_core` running the real program from reset, CPU in simulation
turbo until the game's first EI, then the exact 8 MHz time base):
- every real-time frame: exactly 1 IRQ; 6 NMIs during the boot sequence (occasionally 5 + 1 gated
  by IFF1), as MAME (6 NMIs/frame from its frame 149); no render snapshot drops;
- **106 real-time frames after the first EI the displayed framebuffer (the Seta logo) is identical,
  pen for pen (76,800/76,800), to MAME frame 250** (`st0016_ref.py --cmpidx`). This is the first
  end-to-end evidence: boot, char-RAM upload, banking, interrupts, sprite snapshot, renderer and
  framebuffer swap all agree with MAME ("video alive" in simulation).

## M8 - Palette - DONE (sim)
`sim.sh m8`: PASS (5,124 checks): 4 banks x 512 B CPU readback, snapshot copy with CPU writes
stalled during the 1024-clock copy, pen -> RGB888 = MAME pal5bit, UNUSED_PEN -> colour 0.

## M10/M12/M13 - Character decode, sprite renderer, composition - DONE (sim)
`nrc_render` + `nrc_framebuffer` + `nrc_spriteram` (snapshot FIFO). `sim.sh m10` runs the RTL on
MAME state dumps (sprite RAM written through the CPU port and FIFO, char RAM through a random-latency
SDRAM client) and compares every pen with `st0016_ref.py`:

| MAME frame | scene | tiles | fetched | render time | result |
|---|---|---|---|---|---|
| 250 | Seta logo | 559 | 558 | 1.38 ms | 76,800/76,800 |
| 700 | title (8-bpp merge photo) | 3,003 | 2,931 | 4.00 ms | 76,800/76,800 |
| 1100 | attract demo | 2,836 | 2,180 | 3.22 ms | 76,800/76,800 |
| 1500 | attract demo | 2,735 | 2,078 | 3.10 ms | 76,800/76,800 |
| 2050 | title | 3,003 | 2,975 | 4.04 ms | 76,800/76,800 |
| 2300 | mode select | 2,397 | 2,379 | 3.39 ms | 76,800/76,800 |

The golden model itself equals MAME snapshots on all 10 dumped frames (dump2).

## M15 - Sound - DONE (sim)
`nrc_sound` (MAME master algorithm, 62.5 kHz, 8 voices, per-voice 8-byte sample cache).
`sim.sh m15`: 20,000 samples of an in-game register stream (MAME frames 2300+, voice state replayed)
through RTL and `st0016_snd_ref.py`: **identical** (10,951 non-silent).

## Planned M2-M4 (as defined at M1; kept for traceability)

- **M2**: `nrc_loader` + `nrc_sdram_arb` + vendored `sdram.sv`; MRA `mra/Neratte Chu (ver. 1.10).mra`
  building the 4 MiB extrom image (u31 @0, 512 KiB zero, u32 @100000; loader zero-fills to 3FFFFF and
  clears char RAM). Bench: loader -> real SDRAM controller -> SDRAM model, read-back of known offsets.
- **M3**: `nrc_cpu` (T80) + `nrc_st0016` bus; real ROM in simulation; compare the first N bus
  cycles / PC trace with MAME.
- **M4**: complete CPU map incl. banked ROM, sprite/palette/char windows, I/O; MAME I/O write trace of
  the first 300 frames must match the RTL trace (ports, values, order).
