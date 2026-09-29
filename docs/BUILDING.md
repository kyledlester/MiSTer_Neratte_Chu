# Building the core

## Requirements

* Intel Quartus Prime Lite **17.0** (17.0.2 recommended, as for other MiSTer cores) with Cyclone V
  device support.
* About 15-25 minutes and 8 GB of RAM per full compile.

## Build

Open `NeratteChu.qpf` in Quartus and run **Processing > Start Compilation**, or from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build.ps1
```

Pass `-QuartusBin <path>` if Quartus is not installed in `C:\intelFPGA_lite\17.0\quartus\bin64`.
The script waits while another Quartus compile is running on the machine, then writes a summary
(resources, timing) to `build/build-summary.txt`.

Outputs:

* `output_files/NeratteChu.rbf`, the bitstream.
* `Releases/NeratteChu_YYYYMMDD.rbf`, a dated copy made by the post-flow script
  `scripts/release_rbf.tcl` after every full compile.

Check the timing report (`output_files/NeratteChu.sta.summary`): all clock domains should have
non-negative setup and hold slack.

## Simulation

The benches that need no game data run in ModelSim-Intel FPGA Starter (installed with Quartus 17.0):

```bash
sh scripts/sim.sh all
```

| Bench | Checks |
| --- | --- |
| `m0` | clock enables, raster, 8 MHz CPU time base under random stalls, pause |
| `m2` | ROM loader through the real SDRAM controller and an SDRAM model |
| `m8` | palette RAM, per-frame palette snapshot, colour conversion |
| `m9` | video output timing (15.734 kHz / 60.05 Hz, 320 x 240), sync during ROM loading |
| `m17` | CRT Adjust: 59 settings, geometry and sync |

## Install on MiSTer

1. Copy `Releases/NeratteChu_YYYYMMDD.rbf` to `_Arcade/cores/`.
2. Copy `MRA/Neratte Chu (ver. 1.10).mra` to `_Arcade/`.
3. Put `nratechu.zip` (MAME set) in `games/mame/`.

See [COMPATIBILITY.md](COMPATIBILITY.md) for ROM set notes.
