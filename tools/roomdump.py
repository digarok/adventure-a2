#!/usr/bin/env python3
"""Print a room's playfield as ASCII, in 2600 clock/count space.
   usage: tools/roomdump.py <room number, hex or decimal> [ballx bally]"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from rom2600 import load

rom, L = load()
B = lambda a: rom[a - 0xF000]
room = int(sys.argv[1], 0)
e = L['RoomDataTable'] + 9 * room
gfx = B(e) | (B(e + 1) << 8)
color, bw, ctrl = B(e + 2), B(e + 3), B(e + 4)
rows = [[B(gfx + r * 3 + i) for i in range(3)] for r in range(7)]

COLBYTE = [0]*4 + [1]*8 + [2]*8
COLMASK = [0x10,0x20,0x40,0x80, 0x80,0x40,0x20,0x10,0x08,0x04,0x02,0x01,
           0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80]

def wall(row, col):
    if col >= 20:
        col = 39 - col
    return rows[row][COLBYTE[col]] & COLMASK[col]

def rowof(count):                      # count 8..104 -> playfield row 0..6
    if count >= 97: return 0
    if count < 17:  return 6
    return (96 - count) // 16 + 1

bx = by = None
if len(sys.argv) > 3:
    bx, by = int(sys.argv[2], 0), int(sys.argv[3], 0)

print('room %02x  gfx %04x  color %02x  bw %02x  ctrl %02x  up %02x left %02x down %02x right %02x'
      % (room, gfx, color, bw, ctrl, B(e+5), B(e+6), B(e+7), B(e+8)))
print('    ' + ''.join('%d' % ((c // 4) % 10) for c in range(0, 160, 4)))
for count in range(104, 7, -1):
    r = rowof(count)
    line = ''
    for col in range(40):
        ch = '#' if wall(r, col) else '.'
        if bx is not None and by - 4 <= count <= by - 1 and bx // 4 <= col <= (bx + 3) // 4:
            ch = 'O' if ch == '.' else 'X'
        line += ch
    if ctrl & 0x80 and line[3] == '.': line = line[:3] + '|' + line[4:]
    if ctrl & 0x40 and line[37] == '.': line = line[:37] + '|' + line[38:]
    print('%3d %s' % (count, line))
