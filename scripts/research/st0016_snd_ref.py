#!/usr/bin/env python3
"""ST-0016 sound reference model (port of MAME master src/devices/sound/st0016.cpp, dcca0e9b).

Also builds register-write stimulus for the RTL bench from a MAME survey capture.

  st0016_snd_ref.py stim <snd_w.txt> <frame0> <frames> <out.stim>
      convert MAME register writes (survey snd_w.txt: "F<f> L<line> pc reg data") into
      "<sample> <reg> <data>" lines, sample = ((f-frame0)*384 + line) * 62500/60/384;
      writes before frame0 are replayed at sample 0 (voices / non-linear mode in game state)
  st0016_snd_ref.py run <charram.bin> <in.stim> <nsamples> <out.txt>
      run the model; writes "<L> <R>" per sample
  st0016_snd_ref.py cmp <model.txt> <rtl.txt>
  st0016_snd_ref.py wav <model.txt> <out.wav>

Documented RTL choices mirrored here: exact (non-overflowing) interpolation product; the 8-voice
sum saturates to 16 bits (MAME: float mix clamped at output).
"""
import sys, struct, wave


def voltab(d):
    v = d & 0x7f
    return 0 if v == 0 else (((8 | (v & 7)) << (v >> 3)) * 256) // (15 << 15)


def dec(c, nonlin):
    s = c - 256 if c & 0x80 else c
    if not nonlin:
        return s << 8
    mag = min(abs(s), 127)
    e, m = mag >> 4, mag & 15
    v = (m << 1) if e == 0 else ((m | 16) << e)
    return (-v if s < 0 else v) << 3


class Voice:
    def __init__(self):
        self.regs = [0] * 32
        self.start = self.end = self.lpstart = self.lpend = 0
        self.freq = self.vol_l = self.vol_r = self.flags = 0
        self.pos = self.frac = 0
        self.lponce = False


class ST0016Snd:
    def __init__(self, cha):
        self.cha = cha
        self.v = [Voice() for _ in range(8)]
        self.nonlin = False

    def write(self, off, data):
        vo = self.v[off >> 5]
        r = off & 0x1f
        vo.regs[r] = data
        g = vo.regs
        if r in (0, 1, 2): vo.start = g[0] | g[1] << 8 | g[2] << 16
        elif r in (4, 5, 6): vo.lpstart = g[4] | g[5] << 8 | g[6] << 16
        elif r in (8, 9, 10): vo.lpend = g[8] | g[9] << 8 | g[10] << 16
        elif r in (12, 13, 14): vo.end = g[12] | g[13] << 8 | g[14] << 16
        elif r in (16, 17): vo.freq = g[16] | g[17] << 8
        elif r == 0x14: vo.vol_l = voltab(data)
        elif r == 0x15: vo.vol_r = voltab(data)
        elif r == 0x16:
            if data != vo.flags and data != 0:
                vo.pos, vo.frac, vo.lponce = vo.start, 0, False
            vo.flags = data
        if off == 0xff:
            self.nonlin = bool(data & 2)

    def next_pos(self, vo, p):
        n = p + 1
        if vo.lponce:
            return vo.lpstart if n >= vo.lpend else n
        if n >= vo.end:
            return vo.lpstart if vo.flags & 1 else p
        return n

    def sample(self):
        L = R = 0
        for vo in self.v:
            if not (vo.flags & 6):
                continue
            a = dec(self.cha[vo.pos & 0x1fffff], self.nonlin)
            b = dec(self.cha[self.next_pos(vo, vo.pos) & 0x1fffff], self.nonlin)
            out = a + (((b - a) * (vo.frac & 0xffff)) >> 16)
            vo.frac += vo.freq
            vo.pos += vo.frac >> 16
            vo.frac &= 0xffff
            if vo.lponce:
                if vo.pos >= vo.lpend: vo.pos = vo.lpstart
            elif vo.pos >= vo.end:
                if vo.flags & 1:
                    vo.pos, vo.lponce = vo.lpstart, True
                else:
                    vo.flags, vo.pos, vo.frac = 0, 0, 0
            L += (out * vo.vol_l) >> 8
            R += (out * vo.vol_r) >> 8
        sat = lambda x: max(-32768, min(32767, x))
        return sat(L), sat(R)


def parse_snd(path):
    for line in open(path):
        t = line.split()
        yield int(t[0][1:]), int(t[1][1:]), int(t[3], 16), int(t[4], 16)


def main():
    cmd = sys.argv[1]
    if cmd == 'stim':
        src, f0, nf, out = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
        with open(out, 'w') as o:
            for f, l, r, d in parse_snd(src):
                if f0 <= f < f0 + nf:
                    s = int(((f - f0) * 384 + l) * 62500 / 60 / 384)
                    o.write('%d %02x %02x\n' % (s, r, d))
    elif cmd == 'run':
        cha = open(sys.argv[2], 'rb').read()
        stim = [tuple(int(x, 16) if i else int(x) for i, x in enumerate(l.split())) for l in open(sys.argv[3])]
        n, out = int(sys.argv[4]), sys.argv[5]
        m = ST0016Snd(cha)
        k = 0
        with open(out, 'w') as o:
            for s in range(n):
                while k < len(stim) and stim[k][0] <= s:
                    m.write(stim[k][1], stim[k][2]); k += 1
                o.write('%d %d\n' % m.sample())
    elif cmd == 'cmp':
        a = [l.split() for l in open(sys.argv[2])]
        b = [l.split() for l in open(sys.argv[3])]
        n = min(len(a), len(b))
        bad = [i for i in range(n) if a[i] != b[i]]
        nz = sum(1 for i in range(n) if a[i] != ['0', '0'])
        if bad or n == 0:
            i = bad[0] if bad else 0
            print('FAIL SOUND: %d/%d samples differ; first at %d model=%s rtl=%s' % (len(bad), n, i, a[i] if a else '', b[i] if b else ''))
            sys.exit(1)
        print('PASS SOUND: %d samples identical (%d non-silent)' % (n, nz))
    elif cmd == 'wav':
        a = [l.split() for l in open(sys.argv[2])]
        w = wave.open(sys.argv[3], 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(62500)
        w.writeframes(b''.join(struct.pack('<hh', int(x), int(y)) for x, y in a)); w.close()


if __name__ == '__main__':
    main()
