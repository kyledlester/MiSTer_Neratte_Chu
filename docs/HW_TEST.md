# Hardware test procedure (DE10-Nano / MiSTer)

## Files to copy

| File (repository) | Copy to (MiSTer SD card) |
|---|---|
| `releases/NeratteChu_<date>.rbf` | `/media/fat/_Arcade/cores/NeratteChu_<date>.rbf` |
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
| T | last render time in 10 us units | <= 0x190 (4 ms); 0x4D0 at boot (empty sprite RAM = 8192 tiles) |
| D | render snapshots dropped (render still busy at vblank) | 0 after boot |

## What to report

1. Does the screen show the Seta logo, the title, the attract demo? (a phone photo of the title is ideal)
2. Coin + Start: does the game start, do the joystick and buttons work?
3. Sound: music / effects present? distorted? correct pitch?
4. If anything fails: the overlay line (photo), and at which step it stopped.
