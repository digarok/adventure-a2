*-------------------------------------------------------------
* Win tune: played once, straight through, when the chalice reaches
* the yellow castle.  Nothing else runs meanwhile - it is the end.
*
* Two voices on the speaker, after the two-oscillator idea in digarok's
* ksynth.  Each voice is a 16-bit phase accumulator stepped once a loop
* pass, and puts out a pulse for the first quarter of its period; the
* speaker follows the OR of the two pulses, so both voices are heard at
* any interval (toggling on every edge of both, as ksynth does, is an
* XOR: an octave pair cancels to one tone).  Every pass costs the same
* PASS cycles (a pass that does not toggle stores to a harmless address
* instead), so a voice with increment i runs at i * (CPU / PASS) / 65536
* Hz.  Notes are five bytes in WinSong (tools/wintune.py): length in
* 256-pass units, then the two increments, 0 for a silent voice.
* Length 0 ends the tune.
*-------------------------------------------------------------
WPh1              equ   $53                     ; the sound driver's ZP, free
WPh2              equ   $55                     ;  while a tick is not playing
WInc1             equ   $57
WInc2             equ   $5a
WLast             equ   $5c                     ; last mixed output, in bit 7
WDur              equ   $5d                     ; passes left, low byte counts down first
WIdx              equ   $5f
WDUMMY            equ   $0030                   ; the tick driver's harmless store

PlayWinTune       lda   IsGS
                  beq   :speed
                  lda   $C036                   ; IIgs: 1 MHz, like PlaySound
                  sta   WGsSpeed
                  and   #$7f
                  sta   $C036
:speed            lda   #0
                  sta   WPh1
                  sta   WPh1+1
                  sta   WPh2
                  sta   WPh2+1
                  sta   WLast
                  sta   WIdx
:note             ldy   WIdx
                  lda   WinSong,y
                  beq   :done
                  sta   WDur+1
                  lda   #0
                  sta   WDur
                  iny
                  lda   WinSong,y
                  sta   WInc1
                  iny
                  lda   WinSong,y
                  sta   WInc1+1
                  iny
                  lda   WinSong,y
                  sta   WInc2
                  iny
                  lda   WinSong,y
                  sta   WInc2+1
                  iny
                  sty   WIdx
                  lda   WInc1                   ; a silent voice is parked outside
                  ora   WInc1+1                 ;  its pulse, or it would hold the
                  bne   :v1                     ;  speaker and mask the other one
                  lda   #$80
                  sta   WPh1+1
:v1               lda   WInc2
                  ora   WInc2+1
                  bne   :v2
                  lda   #$80
                  sta   WPh2+1
:v2
* one pass: PASS = 81 cycles, every path
:pass             clc                           ; 2
                  lda   WPh1                    ; 3
                  adc   WInc1                   ; 3
                  sta   WPh1                    ; 3
                  lda   WPh1+1                  ; 3
                  adc   WInc1+1                 ; 3
                  sta   WPh1+1                  ; 3
                  clc                           ; 2
                  lda   WPh2                    ; 3
                  adc   WInc2                   ; 3
                  sta   WPh2                    ; 3
                  lda   WPh2+1                  ; 3
                  adc   WInc2+1                 ; 3
                  sta   WPh2+1                  ; 3   = 40
                  tax                           ; 2
                  lda   WPulse,x                ; 4   $80 while in the pulse
                  ldx   WPh1+1                  ; 3
                  ora   WPulse,x                ; 4   mixed output in bit 7
                  tax                           ; 2
                  eor   WLast                   ; 3   $80 if it changed
                  stx   WLast                   ; 3
                  cmp   #$80                    ; 2   carry = changed
                  ror                           ; 2   $c0 if changed, else $00
                  sta   :st+2                   ; 4   -> SPEAKER or WDUMMY
:st               sta   SPEAKER                 ; 4   = 33
                  dec   WDur                    ; 5
                  bne   :pass                   ; 3   = 8
                  dec   WDur+1                  ; (a few cycles more once in 256)
                  bne   :pass
                  beq   :note
:done             lda   IsGS
                  beq   :rts
                  lda   WGsSpeed
                  sta   $C036
:rts              rts

WGsSpeed          db    0
                  ds    \                       ; page-aligned: no index ever crosses
WPulse            ds    64,$80                  ; phase high byte -> pulse
                  ds    192,0
