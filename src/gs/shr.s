*-------------------------------------------------------------
* SHR support (pattern from pitfall/graphics.s)
*  bank $01 $2000-$9FFF = clean background, shadowed to $E1
*-------------------------------------------------------------
                  mx    %00
GraphicsOn        sep   #$30
                  lda   #$C1
                  stal  $00C029
                  rep   #$30
                  rts

GraphicsOff       sep   #$30
                  lda   #$01
                  stal  $00C029
                  rep   #$30
                  rts

GraphicsLinear    sep   #$30
                  ldal  $00C029
                  ora   #%01000000
                  stal  $00C029
                  rep   #$30
                  rts

ShadowActive      sep   #$30
                  ldal  $00C035
                  and   #%11110111              ; clear SHR shadow inhibit
                  stal  $00C035
                  rep   #$30
                  rts

SetSCBs           ldx   #$0100
                  lda   #0
:loop             dex
                  dex
                  stal  $E19D00,x
                  bne   :loop
                  rts

* 2600 NTSC-ish palette, 16 entries of $0RGB
SetPalette        ldx   #0
:loop             lda   Palette,x
                  stal  $E19E00,x
                  inx
                  inx
                  cpx   #32
                  bne   :loop
                  rts
Palette           dw    $0000                   ; 0 black
                  dw    $0FFF                   ; 1 white
                  dw    $0BBB                   ; 2 light gray (2600 bg $08)
                  dw    $0D00                   ; 3 red
                  dw    $0EE1                   ; 4 yellow
                  dw    $01B0                   ; 5 green
                  dw    $0138                   ; 6 blue
                  dw    $0919                   ; 7 purple
                  dw    $0E70                   ; 8 orange
                  dw    $0AFA                   ; 9 light green
                  dw    $0A8F                   ; A light blue
                  dw    $0F8F                   ; B pink
                  dw    $0888                   ; C dark gray
                  dw    $0444                   ; D darker gray
                  dw    $0FF8                   ; E pale yellow
                  dw    $0FFF                   ; F flash slot

* VBL wait: $C019 bit 7 set during VBL on the IIgs
                  mx    %11
WaitVBL           
:waitRaster       ldal  $00c019
                  bmi   :waitRaster
:waitVBL          ldal  $00c019
                  bpl   :waitVBL
                  rts
                  mx    %00

GSOSQuit          jsl   $E100A8
                  da    $29
                  adrl  QuitParm
                  bcs   Error
Error             brk
QuitParm          adrl  $0000
                  da    $00
