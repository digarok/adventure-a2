#!/usr/bin/env python3
"""TIA audio model (one channel), ported from Stella's AudioChannel.cxx,
plus Adventure's MakeSound so the game's sounds can be rendered to WAV and
the per-AUDC waveform tables for the Apple II speaker driver generated.

  tools/tiasnd.py wav DIR        write DIR/<sound>.wav for every game sound
  tools/tiasnd.py tables         print the run-length tables
  tools/tiasnd.py gen            write src/a2/sndpat.s (speaker driver tables)
"""
import sys, wave, struct, os

AUDIO_CLOCK = 3579545 / 114          # two phases per 228-clock scanline
TICK_CLOCKS = 3 * 262 * 2            # a 20 Hz game tick is three NTSC frames

class Channel:
    def __init__(self):
        self.audc = self.audf = self.audv = 0
        self.clockEnable = self.noiseFeedback = self.noiseBit4 = self.pulseHold = False
        self.div = self.pulse = self.noise = 0

    def phase0(self):
        if self.clockEnable:
            self.noiseBit4 = self.noise & 1
            m = self.audc & 3
            if m in (0, 1):
                self.pulseHold = False
            elif m == 2:
                self.pulseHold = (self.noise & 0x1e) != 0x02
            else:
                self.pulseHold = not self.noiseBit4
            if m == 0:
                self.noiseFeedback = bool(((self.pulse ^ self.noise) & 1)
                    or not (self.noise or (self.pulse != 0x0a))
                    or not (self.audc & 0x0c))
            else:
                self.noiseFeedback = bool(((1 if self.noise & 4 else 0) ^ (self.noise & 1))
                    or self.noise == 0)
        self.clockEnable = self.div == self.audf
        if self.div == self.audf or self.div == 0x1f:
            self.div = 0
        else:
            self.div += 1

    def phase1(self):
        if self.clockEnable:
            t = self.audc >> 2
            if t == 0:
                fb = bool(((1 if self.pulse & 2 else 0) ^ (self.pulse & 1))
                    and self.pulse != 0x0a and (self.audc & 3))
            elif t == 1:
                fb = not (self.pulse & 8)
            elif t == 2:
                fb = not self.noiseBit4
            else:
                fb = not ((self.pulse & 2) or not (self.pulse & 0x0e))
            self.noise >>= 1
            if self.noiseFeedback:
                self.noise |= 0x10
            if not self.pulseHold:
                self.pulse = (~(self.pulse >> 1)) & 7
                if fb:
                    self.pulse |= 8

    def clock(self):
        """one audio clock; returns the output bit"""
        self.phase0()
        self.phase1()
        return self.pulse & 1

    def volume(self):
        return (self.pulse & 1) * self.audv

# ---- Adventure's MakeSound (fa23), one tick: returns (audc, audf, audv) or None (silence)
def make_sound(ntype, count):
    """count is the value *after* the decrement, as the ROM uses it"""
    if ntype == 0:                       # game over: the port's fanfare
        i = (count ^ 0xff) - 1
        if i < len(WIN_NOTES):
            return 4, WIN_NOTES[i], WIN_VOLS[i]
        return 4, 0, 0
    if ntype == -1:                      # game over as the 2600 did it
        return count & 15, (count >> 3) & 31, (count >> 1) & 15
    if ntype == 1:                       # roar
        c = 3 if count & 1 else 8
        return c, ((count >> 2) + 0x1c) & 31, count & 15
    if ntype == 2:                       # man eaten
        return 6, (count ^ 15) & 31, ((count >> 1) + 8) & 15
    if ntype == 3:                       # dragon dying
        return 4, (count ^ 0x1f) & 31, count & 15
    if ntype == 4:                       # drop
        return 6, (count ^ 3) & 31, 5
    if ntype == 5:                       # pickup
        return 6, count & 31, 5
    return None

WC5, WE5, WG5, WC6 = 29, 23, 19, 14
WIN_NOTES = [WC5,WC5,WE5,WE5,WG5,WG5,WC6,WC6,WC6,WC6, WC6,WG5,WG5,WC6,WC6,WC6,WC6,WC6,WC6,WC6,WC6,WC6]
WIN_VOLS  = [15,12,15,12,15,12,15,13,11,9, 0,15,12,15,14,12,10,8,6,4,2,1]

SOUNDS = {                     # name: (type, initial NoiseCount)
    'gameover': (0, 0xff),
    'gameover2600': (-1, 0xff),
    'roar':     (1, 0x10),
    'eaten':    (2, 0x10),
    'dragondie':(3, 0x10),
    'drop':     (4, 0x04),
    'pickup':   (5, 0x04),
}

def render(ntype, count0, ch=None):
    """yield the channel output (0..15) per audio clock for the whole sound"""
    ch = ch or Channel()
    count = count0
    out = []
    while count:
        count -= 1
        notes = [count]
        if ntype == 3 and count:         # dragon death runs at double speed
            count -= 1
            notes.append(count)
        for n in notes:
            regs = make_sound(ntype, n)
            if regs:
                ch.audc, ch.audf, ch.audv = regs
            for _ in range(TICK_CLOCKS // len(notes)):
                ch.clock()
                out.append(ch.volume())
    ch.audv = 0
    out.extend([0] * TICK_CLOCKS)     # the silent tick that follows
    return out

def write_wav(path, samples):
    rate = int(round(AUDIO_CLOCK))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b''.join(struct.pack('<h', int((v / 15.0) * 20000)) for v in samples))

def pattern(audc, audf=0, n=4096):
    """the 1-bit output sequence of a waveform at divider audf (steady state)"""
    ch = Channel(); ch.audc = audc; ch.audf = audf; ch.audv = 15
    for _ in range(n):            # settle
        ch.clock()
    return [ch.clock() for _ in range(n)]

def period(bits):
    for p in range(1, len(bits) // 2):
        if bits[p:] == bits[:-p]:
            return p
    return None

def runs(bits):
    """run lengths of one period, starting on a rising edge"""
    p = period(bits)
    seq = bits[:p]
    # rotate so it starts with a 1 that follows a 0
    for i in range(p):
        if seq[i] == 1 and seq[i - 1] == 0:
            seq = seq[i:] + seq[:i]
            break
    else:
        return None                     # constant
    r = []
    cur, n = seq[0], 0
    for b in seq:
        if b == cur:
            n += 1
        else:
            r.append(n); cur, n = b, 1
    r.append(n)
    return r

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'tables'
    if cmd == 'wav':
        d = sys.argv[2]; os.makedirs(d, exist_ok=True)
        for name, (t, c) in SOUNDS.items():
            write_wav(os.path.join(d, name + '.wav'), render(t, c))
            print('wrote', name)
    elif cmd == 'gen':
        out = ['* GENERATED by tools/tiasnd.py - do not edit',
               '* TIA channel output at AUDF=0 for each AUDC, as run lengths in audio',
               '* clocks (31.4 kHz) starting with a high run, 0-terminated.  AUDC 0 and',
               '* 11 are a constant level (silent) and have no pattern.', '']
        maxr = []
        for audc in range(16):
            r = runs(pattern(audc))
            if r is None:
                maxr.append(0); continue
            assert len(r) % 2 == 0 and max(r) < 64
            maxr.append(max(r))
            for i in range(0, len(r), 32):
                lab = 'SndPat%X' % audc if i == 0 else ''
                out.append('%-18s%-6s%s' % (lab, 'db', ','.join(str(x) for x in r[i:i+32]) + (',0' if i + 32 >= len(r) else '')))
        pats = ['SndPat%X' % c if maxr[c] else 'SndPat4' for c in range(16)]
        out += ['', 'SndPatLo          db    ' + ','.join('<' + x for x in pats),
                'SndPatHi          db    ' + ','.join('>' + x for x in pats),
                'SndMaxRun         db    ' + ','.join(str(x) for x in maxr) + '   ; 0 = silent']
        open(os.path.join(os.path.dirname(__file__), '..', 'src/a2/sndpat.s'), 'w').write('\n'.join(out) + '\n')
        print('wrote src/a2/sndpat.s')
    elif cmd == 'tables':
        for audc in range(16):
            bits = pattern(audc)
            r = runs(bits)
            print(audc, 'period', period(bits), 'runs', r if r is None else (len(r), max(r), sum(r)))
            print('   ', r)
