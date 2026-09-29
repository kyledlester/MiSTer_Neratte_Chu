# Neratte Chu (Seta ST-0016) for MiSTer

A MiSTer FPGA core for **Neratte Chu** (ねらってチュー), Seta's 1996 puzzle game, running on
Seta's **ST-0016** single-chip arcade system.

I created this core because I wanted to play this game on my MiSTer FPGA. I am posting it here and open sourcing it for everyone to enjoy and give feedback/make improvements. This core was created with the assistance of AI tooling.

**Status: beta.** The game boots, runs its attract mode and is fully playable, with sound, on real
MiSTer hardware (HDMI and 15 kHz CRT).

## Quick start

1. Copy the core from [`Releases/`](Releases/) (`NeratteChu_YYYYMMDD.rbf`) to
   **`/media/fat/_Arcade/cores/`**.
2. Copy the MRA from [`MRA/`](MRA/) to **`/media/fat/_Arcade/`**.
3. Put the MAME ROM zip **`nratechu.zip`** (MAME 0.289 set) in **`/media/fat/games/mame/`**.
4. Load **Neratte Chu (ver. 1.10)** from the **Arcade** menu.

ROMs are not included. You must supply your own.

## Supported games

| Game | MAME set | Year | Genre | Board | Status |
| --- | --- | --- | --- | --- | --- |
| Neratte Chu (ver. 1.10) | `nratechu` | 1996 | Puzzle | Seta ST-0016 (E56-00002) | Boots to title screen and is playable |

More detail (controls, DIP switches, ROM layout): [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## About the hardware

The ST-0016 puts a whole arcade board into one Seta custom chip:

* A **Z80**-compatible CPU at 8 MHz with banked access to up to 4 MiB of program/graphics ROM.
* A sprite engine drawing everything on screen from a 64 KiB sprite RAM, using 4-bpp characters
  that the CPU copies into 1-2 MiB of character DRAM. Two layers can be merged into 8-bpp images
  (Neratte Chu's photographic title and backgrounds).
* Tilemap layers (used by Neratte Chu only for its service menu) and a 1024-colour palette.
* An **8-voice PCM** sound engine playing samples from the same character DRAM, in stereo.

## About the core

* Runs the original game program on a T80 Z80 core; every ST-0016 function is implemented in
  logic (no game-specific shortcuts). MAME's ST-0016 drivers (0.289, sound from MAME's current
  PCB-fitted model) are the behavioural reference; video was verified pixel-for-pixel against MAME.
* Native 15 kHz output for CRTs: 320 x 240 at 15.734 kHz / 60.05 Hz, the timing the game programs
  into the chip. Optional CRT Adjust (H-size, H-position, V-shift) thanks to rmonic79/MiSTer-CRT-Adjust.
* The game's Flip Screen DIP switch works (a true 180° rotation), which does not work in MAME.
* The service menu (DIP "Service Mode") works with readable text; MAME draws its text upside down.
* Pause: a Pause button, optional pause while the OSD is open, dimming after 10 seconds
  (JimmyStones' MiSTer pause module).
* OSD options: aspect ratio, scandoubler effects, stereo mix, DIP switches, CRT Adjust, pause options,
  debug overlay, Reset.
* Two players.

### Known issues

* The picture is one frame later than on the original board (a constant 16.7 ms), because the core
  draws each frame into a framebuffer as MAME does.
* A few undocumented ST-0016 behaviours follow MAME's approximations (the chip's timer/raster
  counter, the timing of the sound-sequencer interrupts, the sound chip's volume and sample curves).
  See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Releases

Builds are in [`Releases/`](Releases/) as `NeratteChu_YYYYMMDD.rbf`. The MRA names the core without the
date (`<rbf>NeratteChu</rbf>`), and MiSTer loads the newest dated file in `_Arcade/cores/`. You are
welcome to run your own build if you'd prefer.

## Building

Quartus Prime Lite 17.0. Open `NeratteChu.qpf` and compile; the build copies a dated RBF into
`Releases/`. See [docs/BUILDING.md](docs/BUILDING.md).

## Documentation

* [Compatibility](docs/COMPATIBILITY.md)
* [Architecture](docs/ARCHITECTURE.md)
* [ST-0016 hardware reference](docs/ST0016_HARDWARE.md)
* [Building](docs/BUILDING.md)
* [Credits and third-party components](docs/REFERENCES.md)

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). The MiSTer framework in `sys/` keeps its own notices
([LICENSE.MiSTer](LICENSE.MiSTer)); the SDRAM controller, CRT Adjust and the pause module are
GPL-3.0-or-later; the T80 Z80 core is under its BSD-style license. See
[docs/REFERENCES.md](docs/REFERENCES.md).

No ROMs or other game data are included in this repository.
