*-------------------------------------------------------------
* HGR support: mode init, line address tables, VBL wait
*-------------------------------------------------------------
HgrLo             equ   $0800                   ; 192-byte tables in free RAM
HgrHi             equ   $08c0

HGRInit           jsr   BuildLineTables
                  jsr   ClearPages
                  sta   TXTCLR
                  sta   HIRES
                  sta   MIXCLR
                  sta   PAGE1
                  rts

* address of line L on page 1 = $2000 + (L&7)*$400 + ((L>>3)&7)*$80 + (L>>6)*$28
*   hi = $20 + (L&7)*4 + ((L>>4)&3)      lo = ((L>>3)&1)*$80 + (L>>6)*$28
BuildLineTables   ldx   #0
:next             txa
                  and   #7
                  asl
                  asl
                  sta   $00
                  txa
                  lsr
                  lsr
                  lsr
                  lsr
                  and   #3
                  clc
                  adc   $00
                  adc   #$20
                  sta   HgrHi,x
                  txa
                  and   #8
                  asl
                  asl
                  asl
                  asl                           ; bit3 -> $80
                  sta   $00
                  txa
                  lsr
                  lsr
                  lsr
                  lsr
                  lsr
                  lsr
                  tay
                  lda   :forty,y
                  clc
                  adc   $00
                  sta   HgrLo,x
                  inx
                  cpx   #192
                  bne   :next
                  rts
:forty            db    $00,$28,$50

ClearPages        lda   #0
                  sta   $00
                  lda   #$20
                  sta   $01
                  ldy   #0
                  tya
:loop             sta   ($00),y
                  iny
                  bne   :loop
                  inc   $01
                  ldx   $01
                  cpx   #$60
                  bne   :loop
                  rts

*-------------------------------------------------------------
* VBL wait, self-modified per machine (from flapple/vbl.s)
*-------------------------------------------------------------
OP_BPL            =     $10
OP_BMI            =     $30

SetupVBL          lda   $FBB3
                  cmp   #$06
                  bne   :foundII
                  lda   $FBC0
                  beq   :foundIIc
                  sec
                  jsr   $FE1F
                  bcs   :foundIIe
                  bcc   :foundIIgs
:foundII          lda   #$60                    ; RTS: no VBL on II/II+
                  sta   WaitVBL
                  rts
:foundIIc         lda   #$EA
                  sta   ShutDownVBL
                  lda   #OP_BPL
                  sta   __waitRasterOp
                  lda   #$70
                  sta   __patchVBLIIc+1
                  lda   #$60
                  sta   __patchVBLIIc+3
                  sei
                  sta   $C07F
                  sta   $C05B
                  sta   $C07E
                  rts
:foundIIe         lda   #OP_BPL
                  sta   __waitRasterOp
                  lda   #OP_BMI
                  sta   __waitVBLOp
:foundIIgs        rts

ShutDownVBL       rts                           ; SMC'd to NOP on IIc
:lastVBL          bit   $C019
                  bpl   :lastVBL
                  lda   $C070
                  sta   $C07F
                  sta   $C05A
                  sta   $C07E
                  cli
                  rts

WaitVBL
:waitRaster       lda   $c019
                  bmi   :waitRaster
__waitRasterOp    =     *-2
__patchVBLIIc     =     *
:waitVBL          lda   $c019
                  bpl   :waitVBL
__waitVBLOp       =     *-2
                  rts
