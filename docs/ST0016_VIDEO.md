# ST-0016 video (as needed by Neratte Chu)

Reference: MAME 0.289 `st0016_cpu_device::draw_sprites / draw_screen / screen_update`, game_flag 1
(nratechu) [MAME-SOURCE]. Golden model: `scripts/research/st0016_ref.py` (pixel-identical to MAME
snapshots, see MAME_REFERENCE.md).

## Frame model (MAME)

`screen_update`: fill the bitmap with `UNUSED_PEN` (1024), draw tilemaps with priority 0, all
sprites, then tilemaps with priority 1 (`vregs[j+3] == 0xFF`). Rendering happens **once per frame at
the start of vblank** (MAME screen line 240), from the RAM state at that instant.

nratechu: `spr_dx = 0`, `spr_dy = 8`; visible area x 8..327, y 0..239 of a 384x384 bitmap.
`UNUSED_PEN` displays as palette colour 0 (MAME sets pen 1024 whenever colour 0 is written).

**Neratte Chu never enables a tilemap** (vregs `$00-$3F` are all written 0) [MAME-TRACE]. All
graphics, including full-screen backgrounds, are sprites.

## Character format

Character RAM tiles: 8x8, 4 bpp, 32 bytes, row = 4 bytes. Pixel `x` of row `y` of tile `t`:
`b = charram[t*32 + y*4 + x/2]`, pixel = `x even ? b & 15 : b >> 4` (MAME `charlayout` xoffset
`{4,0,12,8,...}`). Pen 0 is transparent. Tile index is 16 bits (65536 tiles = 2 MiB).

## Palette

1024 colours, 2 bytes each, little-endian: `v = pal[2c] | pal[2c+1] << 8`; R = v[4:0], G = v[9:5],
B = v[14:10]; 5->8 bit expansion `(x << 3) | (x >> 2)` (MAME `pal5bit`). CPU window `EA00-EBFF`
shows bank `E5[1:0]` (512 bytes = 256 colours).

## Sprite list (sprite RAM, 64 KiB, 8-byte entries)

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

### Measured workload (nratechu, MAME 0.289 dumps)
Mode-select / attract frames: 19 main entries, 496 sub-entries, 2,397 tiles, 152,256 in-clip pixel
writes per frame (~2x overdraw of 76,800 visible pixels). Sprite RAM receives only ~9 CPU writes
per frame during play (most drawn material is static between scene changes); scene changes rewrite
up to ~30,000 bytes over a few frames.

## Tilemaps (nratechu: service mode only)

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

## Timing

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

### Flip Screen
With DIP SW2:7 On the game writes `$74 = $59` (plus `$70/$71 = $0308`, `$75 = $31`) and draws
exactly as unflipped (MAME, which ignores these registers, shows an upright picture), so the PCB
flips in hardware. The core rotates the displayed framebuffer 180 degrees when `$74` bits 7-5 are
non-zero (docs/KNOWN_ISSUES.md U-5).

### Ports 00/01 (raster/timer counter)
The game reads `IN $00`, `IN $01` (low, high), inverts, subtracts `$03E7` and uses the result
(a) in the IRQ handler to wait before copying a palette buffer (`$00C2`: loop until value >= `$D4`)
and (b) as a pseudo-random Y value (`$67ED`). MAME returns `rand()` for both ports. The real
counter source is **unknown** (candidates: V counter, the `$70` timer). First-pass implementation
reproduces MAME: an LFSR. Isolated in `nrc_st0016_regs` (`RASTER_MODEL` parameter). [APPROXIMATION]
