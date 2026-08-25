"""Rebuild the 2600 Adventure ROM image ($F000-$FFFF) from the SourceGen
listing in ref/Adventure.txt, and expose the label table.

Used by gen_gfx.py so room bitmaps and sprite shapes come straight from the
reference disassembly instead of being hand-typed."""
import re, os

LISTING = os.path.join(os.path.dirname(__file__), '..', 'ref', 'Adventure.txt')
LINE = re.compile(r'^([0-9a-f]{4}): ((?:[0-9a-f]{2} ?)+)\+?\s+(?:([A-Za-z@_][A-Za-z0-9_]*)\s+)?(\S+)\s*(.*)$')

def load():
    rom = bytearray(0x1000)
    labels = {}
    pending = []          # (addr, directive, operand) needing label resolution
    for raw in open(LISTING, encoding='utf-8'):
        line = raw.rstrip('\n')
        m = LINE.match(line.strip()) if re.match(r'^\s*[0-9a-f]{4}: ', line) else None
        if not m:
            # label-only line: "                   Label"
            lm = re.match(r'^\s{19}([A-Za-z_][A-Za-z0-9_]*)\s*$', line)
            if lm:
                pending.append(('label', lm.group(1)))
            continue
        addr = int(m.group(1), 16)
        for kind, name in pending:
            if kind == 'label':
                labels[name] = addr
        pending = []
        label, direc, operand = m.group(3), m.group(4), m.group(5)
        if label:
            labels[label] = addr
        operand = operand.split(';')[0].strip()
        off = addr - 0xF000
        if direc in ('.bulk', '.dd1'):
            vals = []
            for v in operand.split(','):
                v = v.strip()
                if v.startswith('$'):
                    vals.append(int(v[1:], 16))
                else:           # <Label / >Label
                    pend1.append((addr + len(vals), v))
                    vals.append(0)
            rom[off:off+len(vals)] = bytes(vals)
        elif direc == '.dd2':
            pend2.append((addr, operand))
        elif direc == '.fill':
            n, v = operand.split(',')
            rom[off:off+int(n)] = bytes([int(v.strip()[1:], 16)]) * int(n)
        elif direc == '.junk':
            pass
        else:
            # code line: bytes are complete (max 3)
            bs = bytes(int(b, 16) for b in m.group(2).split())
            rom[off:off+len(bs)] = bs
        pending = [p for p in pending if p[0] == 'label']
    for addr, operand in pend1:
        v = labels[operand[1:]]
        rom[addr-0xF000] = (v & 0xff) if operand[0] == '<' else (v >> 8)
    for addr, operand in pend2:
        if operand.startswith('$'):
            v = int(operand[1:], 16)
        else:
            v = labels[operand]
        rom[addr-0xF000] = v & 0xff
        rom[addr-0xF000+1] = v >> 8
    return bytes(rom), labels

pend1 = []
pend2 = []

if __name__ == '__main__':
    import sys
    rom, labels = load()
    if len(sys.argv) > 1:
        real = open(sys.argv[1], 'rb').read()
        diffs = [i for i in range(0x1000) if rom[i] != real[i]]
        print('mismatches:', len(diffs), [hex(0xF000+i) for i in diffs[:20]])
    print(len(labels), 'labels; RoomDataTable =', hex(labels['RoomDataTable']))
