# Memory map (ST-0016 as used by Neratte Chu)

Sources: MAME 0.289 `st0016.cpp` (`cpu_internal_map`, `cpu_internal_io_map`) and `simple_st0016.cpp`
(`st0016_mem`, `st0016_io`, `extrom_mem`) [MAME-SOURCE]; usage columns from `cap/survey1` [MAME-TRACE].
Tags: [MAME-SOURCE] read from MAME, [MAME-TRACE] observed in MAME runs, [ROM] read from the game
program, [DECISION] project choice, [UNKNOWN] not established.

## Z80 memory space (16-bit)

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

## Z80 I/O space (port = A7..A0; MAME `global_mask(0xff)`)

| Port | R/W | Function |
|---|---|---|
| `00-BF` | R/W | ST-0016 video registers (`vregs`). Reads return the written value, **except `00`/`01`: MAME returns `rand()`** (a real raster/timer counter; see ST0016_VIDEO.md "Ports 00/01") |
| `00-3F` | | 8 tilemap slots x 8 bytes; **all written 0 by nratechu** (no tilemaps) [MAME-TRACE] |
| `40-5F` | | 8 scroll slots x (X.w, Y.w), 10-bit signed; nratechu uses slot 1 (`$44-$47`) Y [MAME-TRACE] |
| `60-7B` | W | CRT registers, written once from ROM table `$8020`: see ST0016_VIDEO.md "Timing" |
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

### DIP mux (`mux_r`, port C2)
`bits[3:0] = SYSTEM[3:0]`; bits 7..4 by `mux & 0x30`:

| mux[5:4] | bit4 | bit5 | bit6 | bit7 |
|---|---|---|---|---|
| 0 | DSW1.0 | DSW1.4 | DSW2.0 | DSW2.4 |
| 1 | DSW1.1 | DSW1.5 | DSW2.1 | DSW2.5 |
| 2 | DSW1.2 | DSW1.6 | DSW2.2 | DSW2.6 |
| 3 | DSW1.3 | DSW1.7 | DSW2.3 | DSW2.7 |

(All active low; see README for nratechu DIP meanings.)

## ST-0016 internal / external address spaces

| Space | Size | Contents | FPGA |
|---|---|---|---|
| extrom | 4 MiB (22-bit) | `sx012-01` @ `000000` (512 KiB), zero `080000-0FFFFF`, `sx012-02` @ `100000` (1 MiB), zero `200000-3FFFFF` (U33/U34 unpopulated; `ROMREGION_ERASE00`) | SDRAM `000000-3FFFFF` |
| character RAM | 2 MiB (21-bit) in MAME; nratechu writes only `000000-0FFFFF` (226 of 256 4 KiB pages; PCB has 2 x TC514400 = 1 MiB) | 8x8 4bpp tiles (32 B each) and 8-bit samples | SDRAM `800000-9FFFFF` (full 2 MiB kept) |
| sprite RAM | 64 KiB = 16 banks x 4 KiB (PCB: 2 x 62256) | sprite lists / sublists / tilemaps | BRAM |
| palette RAM | 2 KiB = 4 banks x 512 B = 1024 colours | xBGR-555 little-endian | BRAM |

## SDRAM layout (FPGA)

| SDRAM byte address | Content |
|---|---|
| `000000-3FFFFF` | extrom image (MRA stream index 0 writes `000000-1FFFFF`; the loader zero-fills to `3FFFFF`) |
| `800000-9FFFFF` | character RAM (zeroed after every ROM download) |
