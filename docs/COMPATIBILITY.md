# Compatibility

The core (`NeratteChu`) runs Neratte Chu on the Seta ST-0016. Tested on a DE10-Nano (HDMI and a
15 kHz CRT).

| Game | MAME set | Year | Status |
| --- | --- | --- | --- |
| Neratte Chu (ver. 1.10) | `nratechu` | 1996 | Working: boots, attract, full game, sound, service menu |

## ROM set

`nratechu.zip` from MAME 0.289. Parts are matched by CRC:

| File | Size | CRC32 | Placed at |
| --- | --- | --- | --- |
| `sx012-01` (U31) | 512 KiB | `6ca01d57` | `000000` |
| `sx012-02` (U32) | 1 MiB | `40a4e354` | `100000` |

The MRA builds MAME's 4 MiB ROM region exactly (the gap at `080000` and the unpopulated U33/U34 range
above `200000` are zero), so the image in SDRAM is byte-identical to MAME's.

## Controls

| Input | MiSTer default | Game |
| --- | --- | --- |
| Joystick | D-pad / stick | 8-way |
| Button 1 | A | Shoot 1 |
| Button 2 | B | Shoot 2 |
| Button 3 | X | Shoot 3 |
| Start | Start | Start (P1 / P2) |
| Coin | Select | Coin |
| Service | R | Service coin |
| Pause | L | pause / resume the game |

Two players: the second controller is player 2.

## DIP switches (OSD > DIP Switches)

MAME's settings; defaults as in MAME.

| Setting | Values | Default |
| --- | --- | --- |
| Coinage | 5C/1C ... 1C/4C | 1C/1C |
| How To Play | No, Yes | Yes |
| Language | English, Japanese | Japanese |
| Difficulty | Hardest, Hard, Easy, Normal | Normal |
| VS Round | First one to win, Best 4 of 7, Best 3 of 5, Best 2 of 3 | Best 2 of 3 |
| Demo Sounds | On, Off | On |
| Flip Screen | On, Off | Off |
| Service Mode | On, Off | Off |

Service Mode opens the game's test menu (system, display, input, output and sound tests): P1 up/down
selects, Button 1 enters, Start leaves a test.

## Core features

| Feature | Notes |
| --- | --- |
| Video | 320 x 240 at 15.734 kHz / 60.05 Hz, native for CRTs; HDMI through the MiSTer scaler |
| Flip Screen | the DIP rotates the picture 180 degrees on every output, as the game expects of the PCB (MAME does not implement it) |
| Service menu | the game's test menu, drawn with the ST-0016 tilemap layer, with readable text (MAME shows it upside down) |
| CRT Adjust | OSD submenu: H-Size, H-Position, V-Shift for analog output, without losing sync; Off = native picture |
| Pause | Pause button, optional pause while the OSD is open, dimming after 10 seconds |
| Debug overlay | OSD option: one line of internal counters (ROM, CPU PC, frames, interrupts, render time) |
| Sound | 8-voice ST-0016 PCM, stereo, following MAME's current (PCB-fitted) model |

## Known issues and differences

* The picture is one frame (16.7 ms) later than on the original board, always the same delay: the
  core draws each frame into a framebuffer as MAME does (see [ARCHITECTURE.md](ARCHITECTURE.md)).
* Some ST-0016 behaviour is not documented and follows MAME: the value read from the chip's
  timer/raster counter (MAME returns random numbers), the timing of the sound-sequencer NMIs, and the
  sound chip's non-linear sample and volume curves (fitted by MAME to recordings of other ST-0016
  games).
* Flip Screen and the service-menu text orientation are inferred from how the game uses the hardware;
  they have not been compared with a real board.
* With CRT Adjust On, HDMI shows the adjusted picture too (as in the Namco NA-1/NA-2 core); switch it
  Off for an unmodified HDMI picture. When widening the picture, H-Position stops moving left at the
  point where the picture would touch the next sync pulse.
