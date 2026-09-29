# Hardware test procedure (DE10-Nano / MiSTer)

## History
| Build | Result |
|---|---|
| NeratteChu_20260928 | owner test: boots, fully playable, sound OK, CRT OK; service menu showed only its background page; MiSTer loading screen not visible on CRT |
| NeratteChu_20260929 | service menu (tilemap layer) implemented; sync kept during ROM loading (CRT loading screen); CRT timing measured (m9) |
| NeratteChu_20260929b | Flip Screen DIP (180-degree flip), OSD CRT Adjust submenu, Pause (button + OSD options); CRT sync edge/porch change (front porch 39 -> 49 dots) |

## Files to copy

| File (repository) | Copy to (MiSTer SD card) |
|---|---|
| `releases/NeratteChu_20260929b.rbf` | `/media/fat/_Arcade/cores/NeratteChu_20260929b.rbf` |
| `mra/Neratte Chu (ver. 1.10).mra` | `/media/fat/_Arcade/Neratte Chu (ver. 1.10).mra` |
| `nratechu.zip` (your MAME set) | `/media/fat/games/mame/nratechu.zip` (or `/media/fat/_Arcade/mame/`) |

The MRA's `<rbf>NeratteChu</rbf>` matches any `NeratteChu_*.rbf` in `_Arcade/cores`.

## What should happen (MAME 0.289 reference, times from power-on)

| Time | Expected |
|---|---|
| 0-2.5 s | black screen (the game copies ~880 KB of graphics into character RAM and checksums its ROMs) |
| ~4 s | Seta logo |
| ~7-12 s | title screen: photo background + pink "ねらってチュー" logo, "(C)1996 SETA CO.,LTD", "CREDIT 0" |
| ~17-25 s | attract demo: puzzle playfield, instructions box, "INSERT COIN" |
| Coin (Select) | "CREDIT 1" and a coin sound |
| Start | mode select "1 PLAYER PUZZLE / 2 PLAYER VS" |
| In game | 8-way joystick moves, Button 1-3 act; music and effects play |

## Diagnostic overlay (OSD: Debug overlay = On)

One yellow line at the top: `R<r> P<pppp> F<ffff> I<iiii> N<nnnn> T<tttt> D<dddd>` (hex):

| Field | Meaning | Healthy |
|---|---|---|
| R | ROM loaded and zero-fill finished | `1` |
| P | Z80 program counter (sampled per frame) | changes |
| F | frames displayed (renders completed) | increments ~60/s |
| I | vblank IRQs raised | increments ~60/s from power-on |
| N | NMIs delivered (only while IFF1 = 1) | 0 during boot, then ~4-6 per frame |
| T | last render time in units of 1024 clk_sys (10.2 us) | ~0x4BA (12.4 ms) during the black boot phase (all-zero sprite RAM = 8192 tiles); ~0x90 on the Seta logo; <= 0x190 (4 ms) in attract/game |
| D | render snapshots dropped (render still busy at vblank) | 0 after boot |

## What to report

1. Does the screen show the Seta logo, the title, the attract demo? (a phone photo of the title is ideal)
2. Coin + Start: does the game start, do the joystick and buttons work?
3. Sound: music / effects present? distorted? correct pitch?
4. If anything fails: the overlay line (photo), and at which step it stopped.

## Build under test

`releases/NeratteChu_20260929b.rbf` (SHA-1 c2bf1914a590dd06d8d1a851a032b5fb577ca91c): Quartus 17.0 Lite,
fitter seed 2, all timing met (core clock setup +0.499 ns, hold +0.244 ns; SDRAM +1.849 / +3.210 ns);
12,220 ALMs, 465/553 M10K. Simulation regression `sh scripts/sim.sh all`: 0 failing.

## New in 20260929b: what to check

| Feature | How | Expected |
|---|---|---|
| Flip Screen | DIPs -> Flip Screen On, reset | whole picture rotated 180 degrees (HDMI and CRT); Off = normal |
| CRT Adjust | OSD -> CRT Adjust -> On, then H-Size / H-Position / V-Shift | picture resizes / moves; the CRT never loses sync; Off = exactly the previous picture. HDMI follows while On (core-side, as NA-1) |
| Pause | map "Pause" (J1 list; default L) and press it; or OSD -> Pause options -> Pause when OSD is open | game, music and timers freeze; press again to resume; after 10 s the picture dims (option) |
| CRT position | CRT Adjust Off | picture about 1.4 us (10 dots) further left than 20260929 (front porch 49 dots, needed for H-Position -48) |

## Service mode (DIP "Service Mode" = On)
Expected: "---[ TEST MODE ]---" menu (SYSTEM / DISPLAY / INPUT / OUTPUT / SOUND TEST), P1 up/down to
select, Button 1 to enter, Start to exit a test. Text is upright (MAME draws it upside down; see
docs/ST0016_VIDEO.md).
