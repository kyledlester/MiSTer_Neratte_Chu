# Credits and third-party components

## Included code

| Component | Path | Origin | License |
| --- | --- | --- | --- |
| T80 Z80 core (v351) | `rtl/vendor/t80/` | T80 by Daniel Wallner, with fixes by MikeJ, TobiFlex, Sorgelig and brNX; copied unmodified from [MiSTer-devel/ZX-Spectrum_MISTer](https://github.com/MiSTer-devel/ZX-Spectrum_MISTer) `rtl/T80/` (`d41751d`) | BSD-style (see file headers) |
| SDRAM controller | `rtl/vendor/sdram.sv` | [MiSTer-devel/GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer) by Sorgelig, with the byte-enable and refresh-parameter changes from the Namco NA-1/NA-2 and NB-1 cores (see `rtl/vendor/README.md`) | GPL-3.0-or-later |
| CRT Adjust | `rtl/vendor/crt_adjust.sv` | MiSTer-CRT-Adjust by Umberto Parisi (rmonic79), unmodified | GPL-3.0-or-later |
| Pause | `rtl/vendor/pause.v` | [JimmyStones/Pause_MiSTer](https://github.com/JimmyStones/Pause_MiSTer) by Jim Gregory, unmodified (copy from MiSTer-devel/Arcade-Pacman_MiSTer) | GPL-3.0-or-later |
| MiSTer framework | `sys/` | [MiSTer-devel/Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) (`3ea1134`) | see `LICENSE.MiSTer` and file headers |

Everything specific to the Seta ST-0016 (`rtl/nrc/`) was written for this project. No other FPGA
implementation of the ST-0016 was found to build on.

## Behavioural references

The core's ST-0016 logic follows these MAME sources (BSD-3-Clause):

* `src/mame/seta/st0016.cpp` / `st0016.h` (0.289): CPU memory and I/O map, banking, video registers,
  DMA, sprite list and tilemap rendering, palette
* `src/mame/seta/simple_st0016.cpp` (0.289): Neratte Chu board, ROM layout, inputs and DIP switches,
  interrupt scheduling
* `src/devices/sound/st0016.cpp` (master, 2026-09): the 8-voice PCM engine with non-linear sample
  decoding, interpolation and volume law
* `src/devices/cpu/z80/`: Z80 behaviour

Hardware notes and the places where the core departs from MAME: [ST0016_HARDWARE.md](ST0016_HARDWARE.md).

Other MiSTer cores used as references: the owner's Namco NA-1/NA-2 and NB-1 cores (project structure,
SDRAM controller, CRT Adjust integration, Flip), MiSTer-devel/Arcade-Pacman_MiSTer (pause integration).

## Game data

No ROMs or other game data are included. The MRA lists MAME part names and CRCs only.
