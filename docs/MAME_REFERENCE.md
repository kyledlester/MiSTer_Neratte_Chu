# MAME reference

MAME is used as the executable behavioural specification. This file records exactly which MAME
was used for what, and how to reproduce every reference capture.

## Versions

| Use | Version | Where |
|---|---|---|
| Binary for all traces / dumps / snapshots | **MAME 0.289** (`mame0289`) | `C:\Users\klest\Downloads\mame\mame.exe` |
| Source matching the binary | tag `mame0289` = `f34f02505e32c1993c6a782b6814232cbfc74e36` | extracted to `C:\Users\klest\NRC_research\mame0289\` |
| Newer source (behavioural updates, not runnable here) | master `dcca0e9b281be806813848db869d9ee54b4ad92e` (2026-09-28) | `C:\Users\klest\NRC_research\mame_master\` |

Files studied: `src/mame/seta/simple_st0016.cpp`, `src/mame/seta/st0016.{cpp,h}`,
`src/devices/sound/st0016.{cpp,h}`, `src/devices/cpu/z80/z80.{cpp,h}`.

### Differences 0.289 -> master that matter

| Area | 0.289 | master | Used here |
|---|---|---|---|
| Sound sample decode | signed 8-bit linear | linear **or non-linear** (3-bit exponent / 4-bit mantissa), selected by voice 7 reg `$1F` bit 1 | **master** (nratechu writes `$0B` -> non-linear) |
| Sound interpolation | nearest sample | linear interpolation between pos and next pos (loop-aware) | **master** |
| Sound volume | raw signed byte | 7-bit exponential law table (`m_voltab`) | **master** |
| Sound mix scale | `32768<<4` per voice | `32768` per voice | master (full-scale per voice) |
| Tilemaps | direct draw, no scroll, base = reg1 x `$1000` | real tilemaps, reg0/1 = scroll X (9 bit), reg2 = scroll Y, base = (reg1 & `$0E`) << 12 | master (nratechu never enables tilemaps, so irrelevant for this game) |
| Sprites, palette, CPU map, DMA, interrupts | - | unchanged | same |

Because the sprite/palette code is identical, 0.289 snapshots are valid pixel references.
Audio references from the 0.289 binary are **not** valid for the master sound model; the audio
reference is `scripts/research/st0016_snd_ref.py`, a port of master `st0016.cpp` fed with register
streams captured from 0.289 (register streams are unaffected by the sound model).

## Running MAME for research

```
cd C:\Users\klest\Downloads\mame
mame.exe nratechu -rompath roms -cfg_directory <tmp> -nvram_directory <tmp>
    -video none -sound none -nothrottle -skip_gameinfo
    -autoboot_script <repo>/scripts/mame/<script>.lua
```

Headless runs at 12-40x real time.

**Windowed runs (snapshots):** nratechu is `MACHINE_NO_COCKTAIL`, so MAME shows a warning screen and
*pauses emulation* until a key is pressed. Research runs avoid it by
1. a private `ui.ini` with `skip_warnings 1` in `C:\Users\klest\NRC_research\mameini` passed with
   `-inipath` (the user's global MAME configuration is not modified), and
2. seeding the fresh cfg directory with `scripts/mame/seed_cfg.sh <cfgdir>` (records the warning as seen).

Always wrap windowed runs in `timeout`. Use `-video auto -window -nomax -snapshot_directory <dir>`;
`-video none` produces black snapshots.

MAME 0.289 Lua notes: the ST-0016 program space is named **`regs`** (not `program`); other spaces are
`io` (8-bit port mask), `charam`, `extrom`. Shares: `:maincpu:spriteram`, `:maincpu:charam`,
`:maincpu:paletteram`. `screen:time_until_pos(0,0)` returns seconds; keep tap handles in globals.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/mame/nrc_survey.lua` | per-frame usage counters, all I/O writes, sound register stream, char-RAM coverage |
| `scripts/mame/nrc_dump.lua` | sprite RAM / palette / register shadow / char RAM dumps + snapshots at chosen frames |
| `scripts/mame/seed_cfg.sh` | cfg seed that skips the cocktail warning screen |
| `scripts/research/st0016_ref.py` | Python port of MAME `draw_sprites` (golden video model) |

Captures live in `C:\Users\klest\NRC_research\cap\` and are never committed (ROM-derived).

## Reference captures (MAME 0.289)

| Capture | Command essentials | Result |
|---|---|---|
| `cap/survey1` | survey, 3600 frames, COIN1 @2000, START1 @2200 | see docs/ST0016_VIDEO.md / ST0016_AUDIO.md facts |
| `cap/dump1` | dump @150,250,450,700,1000,1100,1500,2050,2300,2600,3000; char RAM @450,2600; same inputs | Python model == MAME snapshot, 76800/76800 pixels, frames 2600 and 3000 |
