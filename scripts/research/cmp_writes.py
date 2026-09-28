#!/usr/bin/env python3
"""Compare CPU write streams: MAME (scripts/mame/nrc_writes.lua) vs RTL (sim/tb/m3_cpu_tb.sv).

  cmp_writes.py <mame.txt> <rtl.txt> [--context 8]

Only 'M' (memory) and 'O' (I/O) writes are compared, in order; 'F' frame markers are used to
report where (in frames) a divergence happens; 'R' lines are ignored. Compares up to the shorter
stream. Prints PASS with the number of identical writes, or the first mismatch with context.
"""
import argparse, sys


def load(p):
    ws, frame = [], 0
    for line in open(p):
        t = line.split()
        if not t: continue
        if t[0] == 'F': frame = int(t[1]); continue
        if t[0] in ('M', 'O') and len(t) == 3: ws.append((t[0], int(t[1], 16), int(t[2], 16), frame))
    return ws


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mame'); ap.add_argument('rtl'); ap.add_argument('--context', type=int, default=8)
    a = ap.parse_args()
    m, r = load(a.mame), load(a.rtl)
    n = min(len(m), len(r))
    for i in range(n):
        if m[i][:3] != r[i][:3]:
            print('FAIL WRITES: first mismatch at write %d (MAME frame %d, RTL frame %d)' % (i, m[i][3], r[i][3]))
            for j in range(max(0, i - a.context), min(n, i + a.context)):
                f = lambda w: '%s %04x %02x' % w[:3]
                print('%s %8d  mame: %-12s rtl: %-12s' % ('>>' if j == i else '  ', j, f(m[j]), f(r[j])))
            sys.exit(1)
    print('PASS WRITES: %d of %d MAME writes identical in order (RTL logged %d; MAME frame %d)'
          % (n, len(m), len(r), m[n - 1][3] if n else 0))


if __name__ == '__main__':
    main()
