# Neratte Chu (Seta ST-0016) for MiSTer

MiSTer FPGA arcade core for **Neratte Chu** (ねらってチュー, Seta 1996, MAME `nratechu`), a Seta
**ST-0016** system (Z80-compatible CPU + sprite video + 8-voice PCM on one chip).

Status: first complete build (`releases/NeratteChu_20260928.rbf`) awaiting its first hardware test;
simulation-verified against MAME (see [docs/MILESTONES.md](docs/MILESTONES.md), [docs/HW_TEST.md](docs/HW_TEST.md)).

## ROM

Uses the MAME `nratechu.zip` set (not included; the RBF contains no ROM data):

| File | Size | CRC32 | extrom offset |
|---|---|---|---|
| `sx012-01` (u31) | 512 KiB | `6ca01d57` | `000000` |
| `sx012-02` (u32) | 1 MiB | `40a4e354` | `100000` |

## Documentation

| Document | Content |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | block diagram, clocks, interrupts, render architecture, memory plan |
| [docs/MEMORY_MAP.md](docs/MEMORY_MAP.md) | Z80 memory / I/O map, ST-0016 spaces, SDRAM layout |
| [docs/ST0016_VIDEO.md](docs/ST0016_VIDEO.md) | sprite list format, character format, palette, CRT registers |
| [docs/ST0016_AUDIO.md](docs/ST0016_AUDIO.md) | sound registers and voice algorithm |
| [docs/MAME_REFERENCE.md](docs/MAME_REFERENCE.md) | MAME versions, research scripts, reference captures |
| [docs/MILESTONES.md](docs/MILESTONES.md) | milestone plan and evidence |
| [docs/REUSE_AND_LICENSES.md](docs/REUSE_AND_LICENSES.md) | reused components and licenses |
| [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) | approximations and unknowns |

## Building

Quartus Prime Lite 17.0 (the MiSTer standard):

```
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

Output: `output_files/NeratteChu.rbf`; summary in `build/build-summary.txt`.

Simulation (ModelSim-Intel FPGA Starter 10.5b from the same install): `sh scripts/sim.sh all`.

## License

GPL-3.0-or-later (see `LICENSE`); MiSTer framework `sys/` under its own licenses
(`LICENSE.MiSTer`); T80 under its BSD-style license (file headers). Details in
[docs/REUSE_AND_LICENSES.md](docs/REUSE_AND_LICENSES.md).
