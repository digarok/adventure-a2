*-------------------------------------------------------------
* Speaker driver: one game tick (1/20 s) of the TIA sound channel
*
* The 2600 writes AUDC0/AUDF0/AUDV0 once a tick and the TIA runs.  The
* channel's output is a 1-bit waveform: a pattern (poly counter or
* divider, chosen by AUDC) clocked at 31.4 kHz through a divide-by-
* (AUDF+1), times a 4-bit volume.  The Apple speaker is 1-bit too, so
* the waveform is played straight from the run lengths in sndpat.s,
* stretched by AUDF+1: 32.5 CPU cycles an audio clock at 1.02 MHz.
*
* Volume: a high run is played as a pulse AUDV/16 of its length wide,
* rather than the full run; the pulse train's fundamental then scales
* as sin(pi*duty), a smooth fade.  Low runs leave the speaker alone.
*
* PlaySound blocks for the whole tick, so the game runs at half speed
* while a sound plays - the sounds are short bursts.  The win tune is
* not played this way: wintune.s plays it through in one go.
*
* Delays count 5-cycle loop iterations ("units"); one audio clock is
* 6.5 units.  A run of r pattern clocks at divider F is U = 13r(F+1)/2
* units, and the run loop body costs a fixed 103 cycles which comes
* off the second delay.  For every r that the pattern can produce the
* tick setup precomputes U, the pulse delay and the rest-of-run delay,
* so the play loop is just lookups and two countdowns.
*-------------------------------------------------------------
SPat              equ   $53                     ; pattern pointer
SRemLo            equ   $55                     ; units left in the tick
SRemHi            equ   $56
SPol              equ   $57                     ; store target high byte: $C0 = speaker
SDelHi            equ   $58                     ; delay loop high count
SIdx              equ   $59                     ; pattern index
SAccU             equ   $5a                     ; 2: running 13r(F+1), half-units
SAccW             equ   $5c                     ; 3: running 13r(F+1)V, 1/32 units
SNLo              equ   $5f

SPEAKER           equ   $C030
SDUMMY            equ   $0030                   ; a store here toggles nothing
OVERHEAD          equ   22                      ; units of loop body per run (~110 cycles)
TICKU             equ   10218                   ; 51092 cycles: 3 NTSC frames
QTICKU            equ   2554                    ; a quarter of it

SLastC            db    $ff
SGsSpeed          db    0
SMaxRun           db    0

* run r (1..63) lives at index 2r
STabULo           ds    128
STabUHi           ds    128
STabH             ds    128                     ; pulse delay: X count, high count
STabL             ds    128                     ; rest of run: X count, high count

*-------------------------------------------------------------
* PlaySound: play the tick described by AUDC0/AUDF0/AUDV0.
PlaySound         lda   IsGS
                  beq   :speed
                  lda   $C036                   ; IIgs: drop to 1 MHz for the loops
                  sta   SGsSpeed
                  and   #$7f
                  sta   $C036
:speed            lda   AUDC0
                  and   #$0f
                  sta   AUDC0
                  tax
                  cmp   SLastC
                  beq   :samec
                  sta   SLastC
                  lda   #0
                  sta   SIdx                    ; new waveform: restart its pattern
:samec            lda   SndPatLo,x
                  sta   SPat
                  lda   SndPatHi,x
                  sta   SPat+1
                  lda   SndMaxRun,x
                  sta   SMaxRun
                  beq   :silent
                  lda   AUDV0
                  and   #$0f
                  sta   AUDV0
                  beq   :silent
                  jsr   BuildTables
                  jsr   NoteLength
                  lda   #>SDUMMY
                  sta   SPol
                  jsr   PlayRuns
                  jmp   :done
:silent           jsr   NoteLength              ; keep the note's length anyway
                  lda   SRemLo
                  sta   SNLo
                  lda   SRemHi
                  sta   SDelHi
                  jsr   DelayN
:done             lda   IsGS
                  beq   :rts
                  lda   SGsSpeed
                  sta   $C036
:rts              rts

*-------------------------------------------------------------
* SRem = AUDLEN quarter ticks, in units
NoteLength        lda   #0
                  sta   SRemLo
                  sta   SRemHi
                  ldx   AUDLEN
                  bne   :add
                  ldx   #4
:add              clc
                  lda   SRemLo
                  adc   #<QTICKU
                  sta   SRemLo
                  lda   SRemHi
                  adc   #>QTICKU
                  sta   SRemHi
                  dex
                  bne   :add
                  rts

*-------------------------------------------------------------
* Delay SDelHi:SNLo units (5 cycles each), N >= 1.
DelayN            ldx   SNLo
                  bne   :go
                  dec   SDelHi
:go
:loop             dex
                  bne   :loop
                  dec   SDelHi
                  bpl   :loop
                  rts

*-------------------------------------------------------------
* The play loop.  Every path through the body costs the same, so a run
* takes exactly 103 + 5*(N1+N2) cycles: BuildTables chose N1 and N2 to
* make that 32.5 cycles a clock.  A low run does the same stores to a
* harmless address.
PlayRuns
:run              ldy   SIdx                    ; 3
                  lda   (SPat),y                ; 5
                  bne   :ok                     ; 3
                  ldy   #0                      ; end of pattern: go round
                  lda   (SPat),y
:ok               iny                           ; 2
                  sty   SIdx                    ; 3
                  asl                           ; 2
                  tay                           ; 2   Y = 2r
                  lda   SRemLo                  ; 3
                  sec                           ; 2
                  sbc   STabULo,y               ; 4
                  sta   SRemLo                  ; 3
                  lda   SRemHi                  ; 3
                  sbc   STabUHi,y               ; 4
                  sta   SRemHi                  ; 3
                  bcc   :last                   ; 2   the tick ends inside this run
                  lda   SPol                    ; 3
                  eor   #$c0                    ; 2   alternate high / low runs
                  sta   SPol                    ; 3
                  sta   :stA+2                  ; 4
                  sta   :stB+2                  ; 4
                  ldx   STabH,y                 ; 4
                  lda   STabH+1,y               ; 4
                  sta   SDelHi                  ; 3
:stA              sta   SPEAKER                 ; 4   edge
:d1               dex                           ; 2
                  bne   :d1                     ; 3
                  dec   SDelHi                  ; 5
                  bpl   :d1                     ; 3
                  ldx   STabL,y                 ; 4
                  lda   STabL+1,y               ; 4
                  sta   SDelHi                  ; 3
:stB              sta   SPEAKER                 ; 4   end of pulse
:d2               dex
                  bne   :d2
                  dec   SDelHi
                  bpl   :d2
                  jmp   :run                    ; 3
* what was left of the tick before this run, and wait it out
:last             lda   SRemLo
                  clc
                  adc   STabULo,y
                  sta   SNLo
                  lda   SRemHi
                  adc   STabUHi,y
                  sta   SDelHi
                  ora   SNLo
                  beq   :end
                  jmp   DelayN
:end              rts

*-------------------------------------------------------------
* Per-tick tables for r = 1..SMaxRun:
*   U  = 13 r (F+1) / 2           units in the run
*   W  = U * V / 16               pulse width in units
*   N1 = W - 4  (>= 1)            first countdown: pulse is 5*N1+20 cycles
*   N2 = U - OVERHEAD - N1 (>= 1) second countdown
* A countdown of N is stored as (N & $ff, (N-1) >> 8) for the loops in
* PlayRuns, less one per 256 for the 6 cycles a high-byte step costs.
BuildTables       lda   AUDF0
                  and   #$1f
                  clc
                  adc   #1                      ; F+1
                  sta   SNLo
                  lda   #0
                  sta   SDU
                  sta   SDU+1
                  ldx   #13                     ; dU = 13(F+1), half-units per r
:m13              clc
                  lda   SDU
                  adc   SNLo
                  sta   SDU
                  bcc   :m13n
                  inc   SDU+1
:m13n             dex
                  bne   :m13
                  lda   #0                      ; dW = dU * V
                  sta   SDW
                  sta   SDW+1
                  ldx   AUDV0
:mul              clc
                  lda   SDW
                  adc   SDU
                  sta   SDW
                  lda   SDW+1
                  adc   SDU+1
                  sta   SDW+1
                  dex
                  bne   :mul
                  lda   #1                      ; accumulators start at half a unit
                  sta   SAccU                   ; (rounding)
                  lda   #0
                  sta   SAccU+1
                  lda   #16
                  sta   SAccW
                  lda   #0
                  sta   SAccW+1
                  sta   SAccW+2
                  ldy   #2                      ; index 2r
:entry            clc
                  lda   SAccU
                  adc   SDU
                  sta   SAccU
                  lda   SAccU+1
                  adc   SDU+1
                  sta   SAccU+1
                  clc
                  lda   SAccW
                  adc   SDW
                  sta   SAccW
                  lda   SAccW+1
                  adc   SDW+1
                  sta   SAccW+1
                  bcc   :nc
                  inc   SAccW+2
:nc               lda   SAccU+1                 ; U = SAccU >> 1
                  lsr
                  sta   SU+1
                  lda   SAccU
                  ror
                  sta   SU
                  lda   SAccW+2                 ; W = SAccW >> 5
                  sta   SW+1
                  lda   SAccW+1
                  sta   SW
                  lda   SAccW
                  ldx   #5
:sh               lsr   SW+1
                  ror   SW
                  ror
                  dex
                  bne   :sh
                  ldx   SW                      ; W is now SW:A
                  stx   SW+1
                  sta   SW
                  sec                           ; N1 = W - 4, at least 1
                  lda   SW
                  sbc   #4
                  sta   SN1
                  lda   SW+1
                  sbc   #0
                  sta   SN1+1
                  bcs   :n1ok
                  lda   #1
                  sta   SN1
                  lda   #0
                  sta   SN1+1
:n1ok             sec                           ; N2 = U - OVERHEAD - N1
                  lda   SU
                  sbc   #OVERHEAD
                  sta   SN2
                  lda   SU+1
                  sbc   #0
                  sta   SN2+1
                  bcc   :short                  ; U < OVERHEAD: as short as it goes
                  sec
                  lda   SN2
                  sbc   SN1
                  sta   SN2
                  lda   SN2+1
                  sbc   SN1+1
                  sta   SN2+1
                  bcc   :cap
                  ora   SN2
                  bne   :store
:cap              sec                           ; no room after the pulse: shorten
                  lda   SU                      ;  the pulse, keep the run's length
                  sbc   #OVERHEAD+1
                  sta   SN1
                  lda   SU+1
                  sbc   #0
                  sta   SN1+1
                  bcc   :short
                  ora   SN1
                  bne   :n2one
:short            lda   #1
                  sta   SN1
                  lda   #0
                  sta   SN1+1
:n2one            lda   #1
                  sta   SN2
                  lda   #0
                  sta   SN2+1
:store            clc                           ; the run really takes
                  lda   SN1                     ;  OVERHEAD + N1 + N2 units
                  adc   SN2
                  sta   SU
                  lda   SN1+1
                  adc   SN2+1
                  sta   SU+1
                  clc
                  lda   SU
                  adc   #OVERHEAD
                  sta   STabULo,y
                  lda   SU+1
                  adc   #0
                  sta   STabUHi,y
                  ldx   #0                      ; SN1 -> STabH
                  jsr   SndCount
                  sta   STabH,y
                  txa
                  sta   STabH+1,y
                  ldx   #2                      ; SN2 -> STabL
                  jsr   SndCount
                  sta   STabL,y
                  txa
                  sta   STabL+1,y
                  iny
                  iny
                  tya
                  lsr
                  cmp   SMaxRun
                  beq   :more
                  bcs   :built
:more             jmp   :entry
:built            rts

* SN1+X (16-bit) -> A = low count, X = high count, corrected for the
* high-byte step cost.
SndCount        lda   SN1,x
                  sec
                  sbc   SN1+1,x                 ; N - (N >> 8), near enough
                  sta   SNLo
                  lda   SN1+1,x
                  sbc   #0
                  sta   SDelHi
                  lda   SNLo                    ; (N-1) >> 8
                  sec
                  sbc   #1
                  lda   SDelHi
                  sbc   #0
                  tax
                  lda   SNLo
                  rts

SDU               ds    2
SDW               ds    2
SU                ds    2
SW                ds    2
SN1               ds    2
SN2               ds    2
