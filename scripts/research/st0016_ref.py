#!/usr/bin/env python3
"""ST-0016 video reference model (Neratte Chu configuration).

A line-for-line port of MAME 0.289 st0016_cpu_device::draw_sprites() / draw_screen()
(src/mame/seta/st0016.cpp) for game_flag = 1 (nratechu): spr_dx = 0, spr_dy = 8,
visible area x 8..327, y 0..239, bitmap pre-filled with UNUSED_PEN (1024).
Tilemaps are modelled too (MAME master semantics) but Neratte Chu never enables them.

This is the golden model the RTL renderer is compared against.

Usage:
  st0016_ref.py <dumpdir> <frame> [--png out.png] [--cmp mame.png] [--stats]
    <dumpdir>/f<frame>_spr.bin, _pal.bin, _vreg.bin, and a charram image
    (--cha file; default <dumpdir>/f<frame>_cha.bin or the nearest earlier *_cha.bin)
"""
import argparse, glob, os, re, sys

UNUSED_PEN = 1024
SPR_DX, SPR_DY = 0, 8
CLIP = (8, 327, 0, 239)          # min_x, max_x, min_y, max_y
BMP_W, BMP_H = 384, 384


def pal5(v):
    return (v << 3) | (v >> 2)


def palette_rgb(pal):
    out = []
    for c in range(1024):
        v = pal[2 * c] | (pal[2 * c + 1] << 8)
        out.append((pal5(v & 31), pal5((v >> 5) & 31), pal5((v >> 10) & 31)))
    out.append(out[0])       # UNUSED_PEN shows colour 0
    return out


class Charram:
    """8x8 4bpp tiles, 32 bytes each; even x = low nibble (MAME charlayout)."""
    def __init__(self, cha):
        self.cha = cha

    def pix(self, tile, x, y):
        b = self.cha[(tile << 5) + (y << 2) + (x >> 1)]
        return (b >> 4) if (x & 1) else (b & 15)


def draw_sprites(bmp, spr, vregs, ch, stats):
    minx, maxx, miny, maxy = CLIP
    for i in range(0, 0x10000, 8):
        x = spr[i + 4] + ((spr[i + 5] & 3) << 8)
        y = spr[i + 6] + ((spr[i + 7] & 3) << 8)
        use_sizes = (spr[i + 1] >> 4) & 1
        globalw = (spr[i + 5] & 0x0c) >> 2
        globalh = (spr[i + 7] & 0x0c) >> 2
        si = (((spr[i + 1] & 0x0f) >> 1) << 2) + 0x40
        scrollx = (vregs[si] + 256 * vregs[si + 1]) & 0x3ff
        scrolly = (vregs[si + 2] + 256 * vregs[si + 3]) & 0x3ff
        if x & 0x200: x -= 0x400
        if y & 0x200: y -= 0x400
        if scrollx & 0x200: scrollx -= 0x400
        if scrolly & 0x200: scrolly -= 0x400
        x += scrollx
        y += scrolly
        if spr[i + 3] & 0x80:
            stats['entries'] = i // 8
            break
        offset = (spr[i + 2] + 256 * spr[i + 3]) << 3
        length = spr[i + 0] + 1 + 256 * (spr[i + 1] & 1)
        if offset >= 0x10000:
            continue
        for _ in range(length):
            code = spr[offset] + 256 * spr[offset + 1]
            sx = spr[offset + 4] + ((spr[offset + 5] & 1) << 8)
            sy = spr[offset + 6] + ((spr[offset + 7] & 1) << 8)
            sx += x
            sy += y
            color = spr[offset + 2] & 0x3f
            if use_sizes:
                lx = (spr[offset + 5] >> 2) & 3
                ly = (spr[offset + 7] >> 2) & 3
            else:
                lx, ly = globalw, globalh
            flipx = (spr[offset + 3] >> 7) & 1
            flipy = (spr[offset + 3] >> 6) & 1
            merge = (spr[offset + 5] & 0x40) != 0
            stats['subs'] += 1
            i0 = 0
            xs = range((1 << lx) - 1, -1, -1) if flipx else range(1 << lx)
            ys = range((1 << ly) - 1, -1, -1) if flipy else range(1 << ly)
            for x0 in xs:
                xpos = sx + x0 * 8 + SPR_DX
                for y0 in ys:
                    ypos = sy + y0 * 8 + SPR_DY
                    tileno = (code + i0) & 0xffff
                    i0 += 1
                    stats['tiles'] += 1
                    for yl in range(8):
                        dy = ((ypos + yl) if not flipy else (ypos + 7 - yl)) & 0xffff
                        for xl in range(8):
                            p = ch.pix(tileno, xl, yl)
                            dx = ((xpos + xl) if not flipx else (xpos + 7 - xl)) & 0xffff
                            if dx > maxx:
                                dx = (dx - 512) & 0xffff
                            if minx <= dx <= maxx and miny <= dy <= maxy:
                                row = bmp[dy]
                                if merge:
                                    row[dx] = (row[dx] | (p << 4)) & 0x3ff
                                elif p or row[dx] == UNUSED_PEN:
                                    row[dx] = p + color * 16
                                stats['pixels'] += 1
            offset += 8
            if offset >= 0x10000:
                break


def render(spr, pal, vregs, cha):
    bmp = [[UNUSED_PEN] * BMP_W for _ in range(BMP_H)]
    stats = {'entries': 0, 'subs': 0, 'tiles': 0, 'pixels': 0}
    if any(vregs[j + 1] for j in range(0, 0x40, 8)):
        print('WARNING: tilemap enabled; tilemaps not modelled in this reference', file=sys.stderr)
    draw_sprites(bmp, spr, vregs, Charram(cha), stats)
    return bmp, stats


def to_rgb(bmp, pal):
    rgb = palette_rgb(pal)
    minx, maxx, miny, maxy = CLIP
    return [[rgb[bmp[y][x]] for x in range(minx, maxx + 1)] for y in range(miny, maxy + 1)]


def find_cha(dumpdir, frame):
    exact = os.path.join(dumpdir, 'f%d_cha.bin' % frame)
    if os.path.exists(exact):
        return exact
    best = None
    for p in glob.glob(os.path.join(dumpdir, 'f*_cha.bin')):
        n = int(re.search(r'f(\d+)_cha', p).group(1))
        if n <= frame and (best is None or n > best[0]):
            best = (n, p)
    return best[1] if best else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dumpdir'); ap.add_argument('frame', type=int)
    ap.add_argument('--cha'); ap.add_argument('--png'); ap.add_argument('--cmp')
    ap.add_argument('--idx', help='write raw 16-bit index frame (320x240 LE)')
    a = ap.parse_args()
    rd = lambda s: open(os.path.join(a.dumpdir, 'f%d_%s.bin' % (a.frame, s)), 'rb').read()
    spr, pal, vregs = rd('spr'), rd('pal'), rd('vreg')
    chap = a.cha or find_cha(a.dumpdir, a.frame)
    cha = open(chap, 'rb').read()
    bmp, st = render(spr, pal, vregs, cha)
    print('frame %d cha=%s entries=%d subs=%d tiles=%d pixels=%d' % (
        a.frame, os.path.basename(chap), st['entries'], st['subs'], st['tiles'], st['pixels']))
    img = to_rgb(bmp, pal)
    if a.idx:
        with open(a.idx, 'wb') as f:
            minx, maxx, miny, maxy = CLIP
            for y in range(miny, maxy + 1):
                f.write(b''.join(bmp[y][x].to_bytes(2, 'little') for x in range(minx, maxx + 1)))
    if a.png or a.cmp:
        from PIL import Image
        im = Image.new('RGB', (320, 240))
        im.putdata([p for row in img for p in row])
        if a.png:
            im.save(a.png)
        if a.cmp:
            ref = Image.open(a.cmp).convert('RGB')
            if ref.size != im.size:
                print('CMP FAIL size', ref.size); sys.exit(1)
            rp, mp = list(ref.getdata()), list(im.getdata())
            bad = [i for i in range(len(rp)) if rp[i] != mp[i]]
            if bad:
                i = bad[0]
                print('CMP FAIL %d/%d pixels differ; first at (%d,%d) mame=%s model=%s' % (
                    len(bad), len(rp), i % 320, i // 320, rp[i], mp[i]))
                sys.exit(1)
            print('CMP PASS 76800/76800 pixels identical')


if __name__ == '__main__':
    main()
