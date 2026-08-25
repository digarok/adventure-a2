*-------------------------------------------------------------
* ADVENTURE GS - Apple IIgs (GS/OS S16, SHR 320x200) entry
*-------------------------------------------------------------
                  rel
                  dsk   adventure
                  use   macros
                  use   ../core/zp
                  mx    %00

Start             phk
                  plb
                  _TLStartUp
                  pha
                  _MMStartUp
                  pla
                  sta   MasterId
                  ora   #$0100
                  sta   UserId

                  jsr   ShadowActive
                  jsr   GraphicsLinear
                  jsr   SetPalette
                  jsr   SetSCBs
                  jsr   TestPattern
                  jsr   GraphicsOn
                  sep   #$30
:loop             jsr   WaitVBL
                  ldal  $00c000
                  bpl   :loop
                  stal  $00c010
                  cmp   #$9b                    ; Esc
                  bne   :loop
                  rep   #$30
                  jsr   GraphicsOff
                  jmp   GSOSQuit

* temporary M1 pattern: 16 color bands in bank $01 (shadowed)
                  mx    %00
TestPattern       ldx   #0
                  lda   #$0000
:line             pha
                  ldy   #0
:byte             stal  $012000,x
                  inx
                  inx
                  iny
                  cpy   #80
                  bne   :byte
                  pla
                  inc
                  cmp   #$1000
                  bne   :skip
                  lda   #$0000
:skip             cpx   #200*160
                  bne   :line
                  rts

MasterId          ds    2
UserId            ds    2

                  put   shr
