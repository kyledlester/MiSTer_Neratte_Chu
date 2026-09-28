# Known issues, approximations and unknowns

Each item: classification, where it is implemented, and what would resolve it.

| ID | Item | Class | Where | Resolution path |
|---|---|---|---|---|
| U-1 | Ports 00/01 "raster/timer counter": MAME returns `rand()`; the game uses it for a palette-copy wait in the IRQ handler and as a pseudo-random value | APPROXIMATION (MAME behaviour, LFSR) | `nrc_st0016` (LFSR, advanced per read) | PCB measurement or logic-analyser capture |
| U-2 | NMI source: MAME pulses NMI at 6 fixed points per 384-line frame, only if IFF1 (MAME: "dirty hack") | APPROXIMATION (MAME rate/phase) | `nrc_irq` (all constants) | PCB measurement of NMI period (candidate: CRT reg `$70` = `$3E7` timer) |
| U-3 | Horizontal CRT register meanings (`$60-$65`) unknown; hsync placement chosen for a centred NTSC picture | MISTER-COMPATIBLE | `nrc_video_timing` parameters | PCB video capture |
| U-4 | Tilemaps (vregs `$00-$3F`) not implemented | DEFERRED (unused by nratechu) | - | implement from MAME master semantics for other ST-0016 games |
| U-5 | Flip screen (`$74`, DIP SW2:7) not implemented | OPEN | - | MAME also ignores `$74`; check what the game does with the DIP |
| U-6 | Frame render latency: one frame more than the PCB (framebuffer); character RAM not snapshotted during a render | DECISION | `nrc_render` | acceptable; revisit only if visible |
| U-7 | Character RAM size: MAME 2 MiB, PCB 1 MiB (2 x TC514400); nratechu uses only the first 1 MiB | INFO | SDRAM keeps 2 MiB | - |
| U-8 | Sound: non-linear decode curve and volume law are MAME approximations fitted to PCB recordings of other games | APPROXIMATION (MAME master) | `nrc_sound` | PCB recording of nratechu |
| U-9 | Watchdog (`E7`) not implemented (MAME: no-op) | MAME-EQUIVALENT | - | - |
