*-------------------------------------------------------------
* ADVENTURE A2 - Apple II (ProDOS 8, HGR) entry
*
* ProDOS loads SYS files at $2000, which is HGR page 1.  The
* stub below copies the body to $6000 and jumps there.
*-------------------------------------------------------------
                  org   $2000
                  typ   $ff
                  dsk   adventure
                  xc    off

MLI               equ   $bf00
KEY               equ   $c000
STROBE            equ   $c010
TXTSET            equ   $c051
TXTCLR            equ   $c050
MIXCLR            equ   $c052
PAGE1             equ   $c054
PAGE2             equ   $c055
HIRES             equ   $c057

                  use   ../core/zp

Stub              lda   #<BodyStart
                  sta   $00
                  lda   #>BodyStart
                  sta   $01
                  lda   #<Main
                  sta   $02
                  lda   #>Main
                  sta   $03
                  ldx   #>BodyEnd-Main+$ff      ; pages to copy
                  ldy   #0
:copy             lda   ($00),y
                  sta   ($02),y
                  iny
                  bne   :copy
                  inc   $01
                  inc   $03
                  dex
                  bne   :copy
                  jmp   Main
BodyStart         =     *

                  org   $6000
Main              cld
                  jsr   SetupVBL
                  jsr   HGRInit
                  jsr   TestPattern
:loop             jsr   WaitVBL
                  lda   KEY
                  bpl   :loop
                  sta   STROBE
                  cmp   #$9b                    ; Esc
                  bne   :loop
                  jmp   Quit

* temporary M1 pattern: colored bands on page 1
TestPattern       ldx   #0
:line             txa
                  lsr
                  lsr
                  lsr
                  lsr
                  lsr                           ; band = line/32
                  tay
                  lda   :colors,y
                  pha
                  lda   HgrLo,x
                  sta   $00
                  lda   HgrHi,x
                  sta   $01
                  pla
                  ldy   #39
:fill             sta   ($00),y
                  eor   :flip
                  dey
                  bpl   :fill
                  inx
                  cpx   #192
                  bne   :line
                  rts
:colors           db    $7f,$55,$2a,$d5,$aa,$7f
:flip             db    $7f

Quit              sta   TXTSET
                  sta   PAGE1
                  jsr   ShutDownVBL
                  jsr   MLI
                  dfb   $65
                  da    QuitParm
                  brk   $00
QuitParm          dfb   4
                  dfb   0
                  da    $0000
                  dfb   0
                  da    $0000

                  put   hgr
BodyEnd           =     *
