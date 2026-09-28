# Architecture

Neratte Chu (Seta, 1996) runs on one Seta **ST-0016**: a Z80-compatible CPU with integrated sprite
video, DMA and 8-voice PCM sound, plus external program/graphics ROM (4 MiB space), 1-2 MiB DRAM
("character RAM"), 64 KiB sprite SRAM and 8 KiB work SRAM. The core reproduces the MAME model
(docs/MAME_REFERENCE.md) with the timing of the real board where the game's own programming
reveals it.

## Block diagram

```
 MiSTer HPS (ioctl) --> nrc_loader --+                         +--> nrc_sound (8 voices) --> AUDIO_L/R
                                     v                         |       ^ sample reads
                                 nrc_sdram_arb --> sdram.sv --> SDRAM (extrom 4 MiB, charram 2 MiB)
                                     ^      ^      ^
                          CPU bank/charram  |   renderer tile reads
                                     |      |      |
   T80 (nrc_cpu) -- nrc_st0016_bus --+   DMA?      |
        |  fixed ROM BRAM, work RAM, sound regs,   |
        |  palette RAM, sprite RAM (live), vregs    |
        |                                           |
   nrc_irq (IRQ at vblank, NMI x6/frame)     nrc_render (sprite list -> framebuffer, at vblank)
                                                    | uses sprite RAM render copy + scroll snapshot
                                                    v
                                     double framebuffer (11-bit pens) + palette snapshot
                                                    v
                                   nrc_video_timing 455x262 -> arcade_video -> HDMI / analog
```

## Clocks

| Clock | Rate | Source |
|---|---|---|
| `clk_sys` | 100.227273 MHz = 42.9545 x 7/3 | `nrc_pll` (fractional altera_pll) |
| dot clock `ce_pix` | 7.159091 MHz = clk_sys / 14 (exact) | NTSC dot clock implied by the CRT registers |
| CPU `ce_cpu` | 8.000000 MHz average (credit-scheduled, catches up after SDRAM stalls) | MAME: 48 MHz / 6, "verified from nratechu" |
| sound `ce_snd` | 62.5 kHz = 8 MHz / 128 | MAME stream rate |

## Interrupts

MAME (`st0016_state::interrupt`, 384 fictitious lines, 60 Hz): IRQ0 (HOLD_LINE; the game uses IM 1,
so RST 38) at line 240 = the moment MAME renders the frame; NMI pulse at lines 0, 64, 128, 192, 256,
320 **only if IFF1 = 1** (MAME calls this a "dirty hack"; the real NMI source is unknown).
The NMI handler (`$0066`) drives the music/sound sequencer (every 4th NMI).

FPGA (`nrc_irq`): IRQ asserted at the start of vblank (line 256 of the 262-line raster), released on
the interrupt-acknowledge cycle. NMIs keep MAME's *phase relative to the IRQ* as a fraction of the
frame: NMI k at `IRQ + (16 + 64k)/384` of a frame (k = 0..5), gated on T80 `IntE` (IFF1) at that
instant. [APPROXIMATION, isolated in nrc_irq; MAME-compatible rate and phase]

## Video architecture: frame renderer + double framebuffer

MAME renders the whole frame instantaneously at the vblank IRQ from the RAM state at that moment.
The FPGA renderer does the same work in a bounded time **from a snapshot**:
- Sprite RAM exists twice in BRAM: the *live* copy (CPU reads/writes) and the *render* copy. Every
  CPU write goes to the live copy immediately and into a FIFO that is applied to the render copy
  only while the renderer is idle. At the vblank IRQ instant, the FIFO position is marked; the
  renderer starts once all older writes are applied, and later writes wait in the FIFO until it
  finishes. Result: the render copy equals live sprite RAM at the IRQ instant, exactly MAME's
  snapshot, without ever stalling the CPU.
- The scroll registers (`$40-$5F`) and the palette are snapshotted at the same instant.
- The renderer clears the back buffer to UNUSED_PEN, walks the sprite list and draws into an
  11-bit-per-pixel framebuffer (pen 0-1023 + UNUSED), reading character data from SDRAM.
- The buffers swap at the start of the next displayed frame after completion; the display side
  converts pens through the palette snapshot taken for that frame.

Latency: one frame more than the (line-rendering) PCB. Character RAM is *not* snapshotted (2 MiB);
writes to it during a render affect that render (MAME: instantaneous). [DECISION, documented]

Why not a line renderer: the ST-0016 list format (arbitrary sizes, painter's order, OR-merge 8-bpp
mode, a 64 KiB list walk) needs the full list per line; a frame renderer has ~7x headroom
(152k pixels/frame vs. >1.2M pixel slots/frame) and reproduces MAME's snapshot semantics exactly.

## Memory

| Store | Size | Where | Why |
|---|---|---|---|
| extrom | 4 MiB | SDRAM | too big for BRAM; banked CPU reads and DMA source |
| fixed ROM window | 32 KiB | BRAM copy of extrom `0000-7FFF` | nearly all opcode fetches; no SDRAM wait |
| character RAM | 2 MiB | SDRAM | too big for BRAM; CPU window, renderer, sound |
| sprite RAM | 2 x 64 KiB | BRAM | renderer needs 8-byte entries per clock + snapshot |
| work RAM | 8 KiB (E000-E87F, F000-FFFF) | BRAM | |
| palette | 2 KiB live + 2 x 1024 x 15 bit snapshots | BRAM | |
| framebuffers | 2 x 320 x 240 x 11 bit | BRAM | |

SDRAM clients (fixed priority): loader > CPU > DMA > sound > renderer. The CPU is stalled (credit
scheduler) while its SDRAM access is outstanding.

## Reset

`reset` (OSD/HPS/button/download) holds CPU, video and sound; SDRAM contents survive. Each ROM
download re-zeroes character RAM and the extrom padding.
