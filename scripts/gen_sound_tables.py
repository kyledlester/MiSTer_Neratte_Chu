#!/usr/bin/env python3
"""Regenerate the volume-law case table inside rtl/nrc/nrc_sound.sv from MAME master's formula:
gain(v) = v7 == 0 ? 0 : ((8 | (v7 & 7)) << (v7 >> 3)) * 256 / (15 << 15)   (integer division)
The table sits between the markers '// VOLTAB BEGIN' and '// VOLTAB END'."""
import re
p = 'rtl/nrc/nrc_sound.sv'
s = open(p).read()
rows = []
for v in range(128):
    g = 0 if v == 0 else (((8 | (v & 7)) << (v >> 3)) * 256) // (15 << 15)
    if g:
        rows.append("            7'd%d: g = 9'd%d;" % (v, g))
body = '\n'.join(rows)
s = re.sub(r'(// VOLTAB BEGIN\n).*?([ ]*// VOLTAB END)', lambda m: m.group(1) + body + '\n' + m.group(2), s, flags=re.S)
open(p, 'w').write(s)
print('voltab rows:', len(rows))
