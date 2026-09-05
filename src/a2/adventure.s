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

* The file runs from $2000 past $6000, so the source and destination
* overlap: copied bottom-up, the pages from $6000 on would be read after
* they had been overwritten, and the end of the body (ZPConsts, the 2600
* sprite rows) would come out as a copy of Main.  So copy top-down.
Stub              ldx   #>BodyEnd-Main+$ff      ; pages to copy
                  dex
                  txa
                  clc
                  adc   #>BodyStart
                  sta   $01                     ; last source page
                  txa
                  clc
                  adc   #>Main
                  sta   $03                     ; last destination page
                  inx
                  lda   #<BodyStart
                  sta   $00
                  lda   #<Main
                  sta   $02
                  ldy   #0
:copy             lda   ($00),y
                  sta   ($02),y
                  iny
                  bne   :copy
                  dec   $01
                  dec   $03
                  dex
                  bne   :copy
                  jmp   Main
BodyStart         =     *

                  org   $6000
Main              cld
                  jsr   SetupVBL
:boot             jsr   TitleScreen
                  lda   #0                      ; the port's own zero page: whatever
                  ldx   #$4f                    ;  launched us may have left it dirty,
:clearzp          sta   $10,x                   ;  and a relaunch finds the last run's
                  dex                           ;  QuitFlag.  After the title: the ROM
                  bpl   :clearzp                ;  text window lives in $20-$29
                  jsr   HGRInit
                  jsr   InitRender
                  jsr   StartGame               ; returns on Esc, or a full reset
                  lda   QuitFlag                ;  (P): the only other way out
                  beq   :boot                   ; full reset: back to the title,
                  jmp   Quit                    ;  same as a cold power-on

WaitFrame         jmp   FrameSync              ; wait out the frame, then flip

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
                  put   title
                  put   render
                  put   input
                  put   gfxhgr
                  put   sound
                  put   sndpat
                  put   wintune
                  put   winsong
                  put   ../core/game
                  put   ../core/collide
                  put   ../core/data
                  put   ../core/gfx2600
BodyEnd           =     *
