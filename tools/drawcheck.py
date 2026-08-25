#!/usr/bin/env python3
"""Check that everything the renderer means to draw actually reaches the screen.

The ghost checks compare two runs of the same build, so they say nothing
about a sprite that is never drawn at all - the whole slot list could be
empty and they would still agree.  This reads the renderer's own NewSig
table out of memory, works out where each entry should be, and looks for
pixels there.

  tools/drawcheck.py <newsig hex dump> <screenshot> [<gfx2600.s>]
"""
import re
import sys

# emulator screenshot geometry: 280x192 at 2x, offset (72,39)
X0, Y0, S = 72, 39, 2
QUAD = {8, 9}                                  # surround and bridge: 8 bytes wide


def sprite_heights(path):
    for line in open(path):
        if line.startswith('SprHeight'):
            return [int(n) for n in line.split('db')[1].split(',')]
    raise SystemExit('no SprHeight in ' + path)


def colour_class(c, is_object):
    """Mirror of ColorClass / ObjColorClass in render.s."""
    if is_object and c < 0x06:
        return 2                               # black objects come out violet
    if c < 0x10:
        if c < 0x06:
            return 1
        return 0 if c < 0x0a else 1
    return [1, 5, 5, 5, 5, 2, 2, 2, 4, 4, 4, 3, 3, 3, 3, 5][c >> 4]


def main():
    dump, shot = sys.argv[1], sys.argv[2]
    heights = sprite_heights(sys.argv[3] if len(sys.argv) > 3 else 'src/core/gfx2600.s')
    rows = re.findall(r'(?m)^00/[0-9a-f]+:((?: [0-9a-f]{2})+)', open(dump).read())
    sig = [int(b, 16) for row in rows for b in row.split()]

    from PIL import Image
    im = Image.open(shot).convert('RGB')
    lit = lambda bx, ln: any(im.getpixel((X0 + S * (bx * 7 + k), Y0 + S * ln)) != (0, 0, 0)
                             for k in range(7))

    nslot = len(sig) // 4
    bad = []
    for slot in range(nslot):
        spr, x, y, col = sig[slot * 4:slot * 4 + 4]
        ball = spr == 0xfe
        if slot == nslot - 1 and not ball:
            bad.append('the ball is not in its slot (sprite %02x, not fe)' % spr)
            continue
        if not ball and spr == 0:
            continue                           # empty slot
        if colour_class(col, not ball) == 0:
            continue                           # invisible in this room by design
        if y == 0 or y > 105:
            continue                           # off the field
        top = (105 - y) * 2
        rows = 4 if ball else heights[spr]
        wide = 2 if ball else (8 if spr in QUAD else 3)
        left = x // 4
        if left >= 40 or top >= 192:
            continue
        seen = any(lit(bx, ln)
                   for bx in range(left, min(left + wide, 40))
                   for ln in range(top, min(top + rows * 2, 192)))
        if not seen:
            bad.append('slot %d: %s sprite %d at (%d,%d) colour %02x drew nothing'
                       % (slot, 'ball' if ball else 'object', spr, x, y, col))
    for b in bad:
        print('  ' + b)
    print('drawcheck: %s' % ('FAILED' if bad else 'clean'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
