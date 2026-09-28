# ST-0016 audio

Reference: MAME **master** `src/devices/sound/st0016.cpp` (commit dcca0e9b, 2026-09-28), which adds
PCB-fitted non-linear decoding, interpolation and a volume law to the 0.289 model
(docs/MAME_REFERENCE.md). Golden model: `scripts/research/st0016_snd_ref.py`.

## Engine

8 voices, sample rate = CPU clock / 128 = 62.5 kHz, stereo. Samples are bytes in the character-RAM
address space (21-bit), i.e. the same memory the CPU fills through `EC00` (the game loads its
samples together with its graphics).

### Registers (per voice v, CPU address `E900 + 0x20*v + r`; all read back as written)

| r | meaning |
|---|---|
| `00-02` | start address (24 bit, little-endian; used as 21-bit charram address) |
| `04-06` | loop start |
| `08-0A` | loop end |
| `0C-0E` | end |
| `10-11` | frequency, 16-bit, 16.16 fixed-point step per output sample |
| `14` | left volume (`m_voltab[data]`) |
| `15` | right volume |
| `16` | flags: bits 1-2 = key/active (`flags & 6`), bit 0 = loop. Writing a value different from the current flags and non-zero restarts the voice: pos = start, frac = 0, looped-once = false |
| `1F` of voice 7 (`E9FF`) | global: bit 1 = non-linear sample format (nratechu writes `$0B`) |

### Per output sample, per active voice (`flags & 6`)

```
a = table[charram[pos & 0x1FFFFF]]
b = table[charram[next_pos(pos) & 0x1FFFFF]]
out = a + ((b - a) * frac) >> 16            (s16)
frac += freq; pos += frac >> 16; frac &= 0xFFFF
if looped_once: if pos >= lpend: pos = lpstart
else if pos >= end:
    if flags & 1: pos = lpstart; looped_once = true
    else: flags = 0; pos = frac = 0          (voice stops; register $16 keeps its value)
L += out * vol_l >> 8 ; R += out * vol_r >> 8
```
`next_pos(p)`: p+1, wrapping to lpstart at lpend once looped; at end: lpstart if looping, else p.

Note: when a voice stops by itself `m_flags` becomes 0 but `m_regs[0x16]` keeps the old value; a later
write of the same value is still a key-on (compared against `m_flags`).

### Tables

- linear: `code << 8` (signed byte)
- non-linear: magnitude = min(|code|, 127); e = mag >> 4, m = mag & 15;
  v = e == 0 ? m << 1 : (m | 16) << e; value = sign * v << 3  (range +-31744)
- volume: v7 = data & 0x7F; gain = v7 == 0 ? 0 : ((8 | (v7 & 7)) << (v7 >> 3)) * 256 / (15 << 15)
  (gain x256; bit 7 of the volume byte is ignored)

### Output scale
MAME adds each voice's `(out * vol) >> 8` with a full-scale of 32768 per voice into a stream; the
sum of 8 voices can exceed 16 bits, MAME's mixer then clamps. The FPGA sums in 20 bits and saturates
to 16 bits (documented choice, identical when not clipping).

## Observed nratechu usage (MAME 0.289 register stream, 3600 frames)
38,607 register writes; key flags `$06` (one-shot) and `$07` (looping); volumes mostly `$51-$6D`;
frequency register rewritten every sequencer tick (~8,300 writes/minute); voice 7 `$1F` = `$0B` once
at boot. Sequencer runs from the NMI handler (every 4th NMI).
