#!/usr/bin/env python3
"""Validate the Neratte Chu MRA against MAME's ROM region definition and build the ioctl stream.

  check_mra.py <mra> <nratechu.zip> [--out stream.bin] [--extrom extrom.bin]

Checks: XML parses; every <part name> exists in the zip with the MRA CRC and MAME's CRC; the
stream built MiSTer-style (parts concatenated, repeat parts expanded) places every MAME ROM_LOAD
at its MAME offset with zero gaps; DIP defaults equal MAME's port defaults.
--out writes the ioctl index-0 stream, --extrom the full 4 MiB region (stream + zero fill,
what the core's SDRAM holds after loading) for the system simulations.
"""
import argparse, binascii, sys, xml.etree.ElementTree as ET, zipfile

# MAME 0.289 simple_st0016.cpp ROM_START(nratechu): (zip name, offset, size, crc)
MAME_LOADS = [('sx012-01', 0x000000, 0x080000, 0x6ca01d57),
              ('sx012-02', 0x100000, 0x100000, 0x40a4e354)]
REGION = 0x400000
MAME_DSW = (0xFF, 0xDF)      # PORT defaults: DSW1 all 1s; DSW2 Demo Sounds (0x20) = 0 = On


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mra'); ap.add_argument('zip')
    ap.add_argument('--out'); ap.add_argument('--extrom')
    a = ap.parse_args()
    fails = 0
    def check(c, m):
        nonlocal fails
        if not c:
            fails += 1; print('FAIL:', m)
    root = ET.parse(a.mra).getroot()
    z = zipfile.ZipFile(a.zip)
    rom = [r for r in root.findall('rom') if r.get('index') == '0'][0]
    stream = bytearray()
    for p in rom.findall('part'):
        if p.get('name'):
            data = z.read(p.get('name'))
            crc = binascii.crc32(data) & 0xffffffff
            check('%08x' % crc == p.get('crc').lower(), 'crc %s' % p.get('name'))
            stream += data
        else:
            n = int(p.get('repeat', '1'), 0)
            val = bytes.fromhex(''.join((p.text or '').split()))
            stream += val * n
    image = bytearray(REGION)
    for name, off, size, crc in MAME_LOADS:
        data = z.read(name)
        check(len(data) == size and (binascii.crc32(data) & 0xffffffff) == crc, 'MAME file %s' % name)
        image[off:off + size] = data
    check(len(stream) == 0x200000, 'stream length %x' % len(stream))
    check(bytes(stream) == bytes(image[:len(stream)]), 'stream == MAME region prefix')
    check(not any(image[len(stream):]), 'region beyond stream is zero (core zero-fills)')
    sw = root.find('switches')
    dflt = [int(x, 16) for x in sw.get('default').split(',')]
    check(tuple(dflt) == MAME_DSW, 'DIP defaults %s' % dflt)
    if a.out: open(a.out, 'wb').write(stream)
    if a.extrom: open(a.extrom, 'wb').write(image)
    print('%s MRA: stream %x bytes, %d checks failed' % ('PASS' if not fails else 'FAIL', len(stream), fails))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
