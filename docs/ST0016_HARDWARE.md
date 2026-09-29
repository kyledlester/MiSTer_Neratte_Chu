# Seta ST-0016: hardware reference (as used by Neratte Chu)

What the core implements and why. MAME 0.289 (`src/mame/seta/st0016.cpp`, `simple_st0016.cpp`,
`src/devices/sound/st0016.cpp`) is the behavioural reference; MAME master (2026-09) is used for the
sound model. Tags: [MAME-SOURCE] read from MAME, [MAME-TRACE] observed in MAME runs, [ROM] read from the
game program, [INFERENCE] / [APPROXIMATION] our conclusions.

## Memory map
Sources: MAME 0.289 `st0016.cpp` (`cpu_internal_map`, `cpu_internal_io_map`) and `simple_st0016.cpp`
(`st0016_mem`, `st0016_io`, `extrom_mem`) [MAME-SOURCE]; usage columns from `cap/survey1` [MAME-TRACE].
Tags: [MAME-SOURCE] read from MAME, [MAME-TRACE] observed in MAME runs, [ROM] read from the game
program, [DECISION] project choice, [UNKNOWN] not established.

### Z80 memory space (16-bit)

| Address | Size | Device | FPGA storage | Notes |
|---|---|---|---|---|
| `0000-7FFF` | 32 KiB | external ROM, fixed: `extrom[fixedrom_offset + a]`, offset 0 for nratechu | BRAM copy made at load time | reset vector `0000`, IM1 `0038`, NMI `0066` [ROM] |
| `8000-BFFF` | 16 KiB | external ROM, banked: `extrom[(rom_bank << 14) | (a & 3FFF)]` | SDRAM | 22-bit extrom space -> bank bits above 8 wrap (MAME: address space is 22 bits) |
| `C000-CFFF` | 4 KiB | sprite RAM window 0: `spr[0x1000 * spr_bank[0] + a]` | BRAM (64 KiB) | |
| `D000-DFFF` | 4 KiB | sprite RAM window 1: `spr[0x1000 * spr_bank[1] + a]` | same BRAM | |
| `E000-E7FF` | 2 KiB | RAM (board) | BRAM | |
| `E800-E87F` | 128 B | "common RAM" (board) | BRAM | initial SP = `E880` [ROM] |
| `E880-E8FF` | | unmapped | reads 0 | never accessed [MAME-TRACE] |
| `E900-E9FF` | 256 B | ST-0016 sound registers, 8 voices x 32 bytes, read/write | registers | |
| `EA00-EBFF` | 512 B | palette RAM window: `pal[0x200 * pal_bank + a]` | BRAM (2 KiB) | |
| `EC00-EC1F` | 32 B | character RAM window: `charram[0x20 * char_bank + a]` | SDRAM | main loader of graphics/samples [MAME-TRACE] |
| `EC20-EFFF` | | unmapped | reads 0 | never accessed [MAME-TRACE] |
| `F000-FFFF` | 4 KiB | work RAM (board) | BRAM | |

Unmapped reads return 0 (MAME default unmap value) [MAME-SOURCE].

### Z80 I/O space (port = A7..A0; MAME `global_mask(0xff)`)

| Port | R/W | Function |
|---|---|---|
| `00-BF` | R/W | ST-0016 video registers (`vregs`). Reads return the written value, **except `00`/`01`: MAME returns `rand()`** (a real raster/timer counter; see "Ports 00/01" below) |
| `00-3F` | | 8 tilemap slots x 8 bytes; **all written 0 by nratechu** (no tilemaps) [MAME-TRACE] |
| `40-5F` | | 8 scroll slots x (X.w, Y.w), 10-bit signed; nratechu uses slot 1 (`$44-$47`) Y [MAME-TRACE] |
| `60-7B` | W | CRT registers, written once from ROM table `$8020`: see "Timing" below |
| `74` | W | bit 7 global flip, bits 6-5 X/Y flip (MAME comment; nratechu writes 0, `$59` only under a flip-screen DIP path) |
| `A0-A2` | W | DMA source >> 1 (24 bit) |
| `A3-A5` | W | DMA destination >> 1 (in char RAM) |
| `A6-A7`, `A8[4:0]` | W | DMA (length in bytes - 1) >> 1, 21 bit |
| `A8` bit 5 | W | DMA start (MAME: instantaneous copy extrom -> char RAM). **Never used by nratechu** [MAME-TRACE] |
| `C0` | R | P1 (active low: up, down, left, right, B1, B2, B3, START1) |
| `C0` | W | input mux select (bits 5-4 select DIP group for port `C2`) |
| `C1`, `C3` | R | P2 (same layout, START2) |
| `C2` | R | `SYSTEM[3:0]` (COIN1, COIN2, SERVICE1, unused) + 4 DIP bits selected by mux (see below) |
| `E0` | W | ignored (nratechu writes 0) |
| `E1` | W | ROM bank (8 bit) |
| `E2` | W | sprite banks: `[3:0]` window C000, `[7:4]` window D000 |
| `E3`, `E4` | W | character bank low / high byte (16 bit) |
| `E5` | W | palette bank `[1:0]` |
| `E6` | W | ignored (nratechu writes `$11`) |
| `E7` | W | watchdog (MAME: no-op; ~1.28 M writes per minute from the main loop) |
| `F0` | R | DMA status: 0 = complete |
| others | R | 0 |

#### DIP mux (`mux_r`, port C2)
`bits[3:0] = SYSTEM[3:0]`; bits 7..4 by `mux & 0x30`:

| mux[5:4] | bit4 | bit5 | bit6 | bit7 |
|---|---|---|---|---|
| 0 | DSW1.0 | DSW1.4 | DSW2.0 | DSW2.4 |
| 1 | DSW1.1 | DSW1.5 | DSW2.1 | DSW2.5 |
| 2 | DSW1.2 | DSW1.6 | DSW2.2 | DSW2.6 |
| 3 | DSW1.3 | DSW1.7 | DSW2.3 | DSW2.7 |

(All active low; see README for nratechu DIP meanings.)

### ST-0016 internal / external address spaces

| Space | Size | Contents | FPGA |
|---|---|---|---|
| extrom | 4 MiB (22-bit) | `sx012-01` @ `000000` (512 KiB), zero `080000-0FFFFF`, `sx012-02` @ `100000` (1 MiB), zero `200000-3FFFFF` (U33/U34 unpopulated; `ROMREGION_ERASE00`) | SDRAM `000000-3FFFFF` |
| character RAM | 2 MiB (21-bit) in MAME; nratechu writes only `000000-0FFFFF` (226 of 256 4 KiB pages; PCB has 2 x TC514400 = 1 MiB) | 8x8 4bpp tiles (32 B each) and 8-bit samples | SDRAM `800000-9FFFFF` (full 2 MiB kept) |
| sprite RAM | 64 KiB = 16 banks x 4 KiB (PCB: 2 x 62256) | sprite lists / sublists / tilemaps | BRAM |
| palette RAM | 2 KiB = 4 banks x 512 B = 1024 colours | xBGR-555 little-endian | BRAM |

### SDRAM layout (FPGA)

| SDRAM byte address | Content |
|---|---|
| `000000-3FFFFF` | extrom image (MRA stream index 0 writes `000000-1FFFFF`; the loader zero-fills to `3FFFFF`) |
| `800000-9FFFFF` | character RAM (zeroed after every ROM download) |

## Video
Reference: MAME 0.289 `st0016_cpu_device::draw_sprites / draw_screen / screen_update`, game_flag 1
(nratechu) [MAME-SOURCE]. During development a Python port of this code (pixel-identical to MAME
snapshots on every captured frame) was the golden model for the RTL renderer; it is in the git
history (see ARCHITECTURE.md, Development history).

### Frame model (MAME)

`screen_update`: fill the bitmap with `UNUSED_PEN` (1024), draw tilemaps with priority 0, all
sprites, then tilemaps with priority 1 (`vregs[j+3] == 0xFF`). Rendering happens **once per frame at
the start of vblank** (MAME screen line 240), from the RAM state at that instant.

nratechu: `spr_dx = 0`, `spr_dy = 8`; visible area x 8..327, y 0..239 of a 384x384 bitmap.
`UNUSED_PEN` displays as palette colour 0 (MAME sets pen 1024 whenever colour 0 is written).

**Neratte Chu never enables a tilemap** (vregs `$00-$3F` are all written 0) [MAME-TRACE]. All
graphics, including full-screen backgrounds, are sprites.

### Character format

Character RAM tiles: 8x8, 4 bpp, 32 bytes, row = 4 bytes. Pixel `x` of row `y` of tile `t`:
`b = charram[t*32 + y*4 + x/2]`, pixel = `x even ? b & 15 : b >> 4` (MAME `charlayout` xoffset
`{4,0,12,8,...}`). Pen 0 is transparent. Tile index is 16 bits (65536 tiles = 2 MiB).

### Palette

1024 colours, 2 bytes each, little-endian: `v = pal[2c] | pal[2c+1] << 8`; R = v[4:0], G = v[9:5],
B = v[14:10]; 5->8 bit expansion `(x << 3) | (x >> 2)` (MAME `pal5bit`). CPU window `EA00-EBFF`
shows bank `E5[1:0]` (512 bytes = 256 colours).

### Sprite list (sprite RAM, 64 KiB, 8-byte entries)

Main list, walked from address 0 in 8-byte steps up to 64 KiB, until an entry with byte 3 bit 7 set
(the terminating entry itself is not drawn):

| byte | bits | meaning |
|---|---|---|
| 0 | `llllllll` | sublist length - 1 (low 8) |
| 1 | `---gSSSl` | l = length bit 8; SSS (bits 3-1) = scroll slot; g (bit 4) = per-sprite sizes |
| 2,3 | `fooooooo oooooooo` | sublist offset / 8 (15 bit), f = end of list |
| 4,5 | `----XXxx xxxxxxxx` | X (10-bit signed), XX (bits 3-2 of byte 5) = global width code |
| 6,7 | `----YYyy yyyyyyyy` | Y (10-bit signed), YY = global height code |

Entry position = (X, Y) + scroll slot (vregs `$40 + 4*SSS`: X.w, Y.w, 10-bit signed). Sublists with
offset >= 64 KiB are skipped.

Sublist entries (8 bytes), `length` entries starting at `offset*8`, stopping at the end of RAM:

| byte | bits | meaning |
|---|---|---|
| 0,1 | 16 bit | character code |
| 2 | `--kkkkkk` | palette (colour = k*16 + pen) |
| 3 | `QW------` | Q = flip X, W = flip Y |
| 4,5 | `-B--XX-x xxxxxxxx` | x (9 bit, unsigned), XX = width code, **B = merge (8bpp) mode** |
| 6,7 | `----YY-y yyyyyyyy` | y (9 bit, unsigned), YY = height code |

Size: width = `1 << (g ? XX_sub : XX_global)` tiles, height likewise. Tiles are numbered
**column-major**: tile index = code + (column * height + row) in drawing order, where with flip the
column/row loops run backwards (tile numbering follows loop order, so flipped sprites mirror the
tile arrangement).

Pixel placement: `xpos = x_entry + sx + col*8 + spr_dx`, `ypos = y_entry + sy + row*8 + spr_dy`;
within a tile, flip mirrors the 8x8. Coordinates are computed as 16-bit unsigned; if the x
coordinate is > 327 it is reduced by 512 (wrap), then clipped to x 8..327, y 0..239.

Pixel write (non-merge): `if (pen != 0 || dest == UNUSED_PEN) dest = colour*16 + pen` - so a
transparent pixel still paints over "nothing yet".
Pixel write (merge, byte 5 bit 6): `dest = (dest | pen << 4) & 0x3FF` - unconditional, used by
Neratte Chu to build 8-bpp images (the high nibble from a second 4-bpp tile layered on the first);
it also turns an `UNUSED_PEN` pixel into `pen << 4`.

Drawing order is painter's order: main list order, then sublist order, then tile order.

#### Measured workload (nratechu, MAME 0.289 dumps)
Mode-select / attract frames: 19 main entries, 496 sub-entries, 2,397 tiles, 152,256 in-clip pixel
writes per frame (~2x overdraw of 76,800 visible pixels). Sprite RAM receives only ~9 CPU writes
per frame during play (most drawn material is static between scene changes); scene changes rewrite
up to ~30,000 bytes over a few frames.

### Tilemaps (nratechu: service mode only)

Implemented per MAME 0.289 `draw_bgmap` (the runnable reference): 8 layers (vregs `$00-$3F`, 8 bytes
each), enabled when reg1 != 0; 64x32 tiles column-major in sprite RAM at `reg1 * $1000`, 4 bytes per
tile (code.w, colour & $3F, attribute); tile (x, y) drawn at (x*8 + spr_dx, y*8 + spr_dy), no scroll.
reg3 == `$FF`: drawn after the sprites with plain transparency; otherwise before the sprites with the
sprite pixel rule (merge mode when reg7 == `$12`).

The service menu (DIP SW2:8) uses one layer: regs `00 02 FF FF 7F 29 00 20` (base `$2000`, over the
sprites); every text tile has attribute `$40`. MAME 0.289 treats attribute bit 6 as flip-Y (text upside
down), MAME master as flip-X (text mirrored); the core ignores the attribute bits, which gives readable
text [INFERENCE]. With MAME's flip rule the model (`st0016_ref.py --tmflip`) equals MAME on 20 service
screens (menu, display, input, output and sound tests); the RTL equals the model (flips ignored).
MAME master's tilemap scroll (reg0/reg1 bit 0 = X, reg2 = Y) is not implemented: nratechu's only
layer has reg0 = 0 and reg2 = `$FF` (0.289 ignores scroll).

### Timing

The game writes a 28-byte table (ROM `$8020`) to ports `$60-$7B` once at boot [ROM, MAME-TRACE]:

| reg | value | MAME comment | interpretation used |
|---|---|---|---|
| `60/61` | `$0021` | H sync start? | - |
| `62/63` | `$0022` | H visible start? | - |
| `64/65` | `$00CB` | H visible end >> 1? | - |
| `66/67` | `$01C6` | H total | **455 dots** |
| `68/69` | `$0001` | V sync start? | vsync from line 1 |
| `6A/6B` | `$0010` | V visible start? | first active line 16 |
| `6C/6D` | `$0100` | V visible end? | last active line 255 (240 lines) |
| `6E/6F` | `$0105` | V total | **262 lines** |
| `70/71` | `$03E7` | "max scanline / timer?" | unknown (also the constant at ROM `$8030`) |
| `72-7B` | `00 08 00 E1 00 80 5A 78 10 D0` | unknown | ignored |

With the 42.9545 MHz crystal / 6 = 7.159 MHz dot clock: 15.734 kHz, 60.05 Hz, i.e. NTSC. MAME
instead runs a fictitious 384x384 @ 60 Hz screen and interrupts on its line numbers (see
ARCHITECTURE.md "Interrupts"). Classification: totals and vertical window = [GAME-PROGRAMMED];
dot clock = [INFERENCE from crystal]; horizontal sync placement = [MISTER-COMPATIBLE]: active dots
0-319, front porch 49, HSync 34 dots (4.75 us), back porch 52; vblank/vsync change at the HSync edge.
Measured output (sim/tb/m9_video_tb.sv): 15.734 kHz, 60.054 Hz, 262 lines, 320 x 240.

#### Flip Screen
With DIP SW2:7 On the game writes `$74 = $59` (plus `$70/$71 = $0308`, `$75 = $31`) and draws
exactly as unflipped (MAME, which ignores these registers, shows an upright picture), so the PCB
flips in hardware. The core rotates the displayed framebuffer 180 degrees when `$74` bits 7-5 are
non-zero (see COMPATIBILITY.md, Known issues).

#### Ports 00/01 (raster/timer counter)
The game reads `IN $00`, `IN $01` (low, high), inverts, subtracts `$03E7` and uses the result
(a) in the IRQ handler to wait before copying a palette buffer (`$00C2`: loop until value >= `$D4`)
and (b) as a pseudo-random Y value (`$67ED`). MAME returns `rand()` for both ports. The real
counter source is **unknown** (candidates: V counter, the `$70` timer). First-pass implementation
reproduces MAME: an LFSR advanced on every read, in `nrc_st0016`. [APPROXIMATION]

## Sound
Reference: MAME **master** `src/devices/sound/st0016.cpp` (commit dcca0e9b, 2026-09-28), which adds
PCB-fitted non-linear decoding, interpolation and a volume law to the 0.289 model. During development
a Python port was the golden model for the RTL (sample-exact); it is in the git history.

### Engine

8 voices, sample rate = CPU clock / 128 = 62.5 kHz, stereo. Samples are bytes in the character-RAM
address space (21-bit), i.e. the same memory the CPU fills through `EC00` (the game loads its
samples together with its graphics).

#### Registers (per voice v, CPU address `E900 + 0x20*v + r`; all read back as written)

| r | meaning |
|---|---|
| `00-02` | start address (24 bit, little-endian; used as 21-bit charram address) |
| `04-06` | loop start |
| `08-0A` | loop end |
| `0C-0E` | end |
| `10-11` | frequency, 16-bit, 16.16 fixed-point step per output sample |
| `14` | left volume (`m_voltab[data]`) |
| `15` | right volume |
| `16` | flags: bits 1-2 = key/active (`flags & 6`), bit 0 = loop. Writing a value different from the current flags and non-zero restarts the voice: pos = start, frac = 0, looped-once = false |
| `1F` of voice 7 (`E9FF`) | global: bit 1 = non-linear sample format (nratechu writes `$0B`) |

#### Per output sample, per active voice (`flags & 6`)

```
a = table[charram[pos & 0x1FFFFF]]
b = table[charram[next_pos(pos) & 0x1FFFFF]]
out = a + ((b - a) * frac) >> 16            (s16)
frac += freq; pos += frac >> 16; frac &= 0xFFFF
if looped_once: if pos >= lpend: pos = lpstart
else if pos >= end:
    if flags & 1: pos = lpstart; looped_once = true
    else: flags = 0; pos = frac = 0          (voice stops; register $16 keeps its value)
L += out * vol_l >> 8 ; R += out * vol_r >> 8
```
`next_pos(p)`: p+1, wrapping to lpstart at lpend once looped; at end: lpstart if looping, else p.

Note: when a voice stops by itself `m_flags` becomes 0 but `m_regs[0x16]` keeps the old value; a later
write of the same value is still a key-on (compared against `m_flags`).

#### Tables

- linear: `code << 8` (signed byte)
- non-linear: magnitude = min(|code|, 127); e = mag >> 4, m = mag & 15;
  v = e == 0 ? m << 1 : (m | 16) << e; value = sign * v << 3  (range +-31744)
- volume: v7 = data & 0x7F; gain = v7 == 0 ? 0 : ((8 | (v7 & 7)) << (v7 >> 3)) * 256 / (15 << 15)
  (gain x256; bit 7 of the volume byte is ignored)

#### Output scale
MAME adds each voice's `(out * vol) >> 8` with a full-scale of 32768 per voice into a stream; the
sum of 8 voices can exceed 16 bits, MAME's mixer then clamps. The FPGA sums in 20 bits and saturates
to 16 bits (documented choice, identical when not clipping).

### Observed nratechu usage (MAME 0.289 register stream, 3600 frames)
38,607 register writes; key flags `$06` (one-shot) and `$07` (looping); volumes mostly `$51-$6D`;
frequency register rewritten every sequencer tick (~8,300 writes/minute); voice 7 `$1F` = `$0B` once
at boot. Sequencer runs from the NMI handler (every 4th NMI).
