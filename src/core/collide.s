*-------------------------------------------------------------
* Software replacement for the TIA collision latches.  Called
* from DrawFrame so the latches describe exactly what is on
* screen, like the hardware did.  Everything is in 2600 units:
* clocks 0-159 across, "counts" 9-104 down (count 104 = top).
*-------------------------------------------------------------
LatchCollisions   lda   #0
                  sta   CXBLPF
                  sta   CXM0FB
                  sta   CXM1FB
                  sta   CXP0FB
                  sta   CXP1FB
                  sta   CXPPMM
                  lda   Obj1X
                  sta   DescA
                  lda   Obj1Y
                  sta   DescA+1
                  lda   Obj1SprId
                  sta   DescA+2
                  lda   Obj2X
                  sta   DescB
                  lda   Obj2Y
                  sta   DescB+1
                  lda   Obj2SprId
                  sta   DescB+2
* --- ball vs playfield and thin walls: rows at counts BallY-1..BallY-4
                  ldy   #4
:brow             sty   T3
                  lda   BallY
                  sec
                  sbc   T3
                  jsr   RowOfCount
                  bcs   :bnext
                  sta   T4
                  lda   RoomCtrl
                  bpl   :nol
                  lda   BallX                   ; left thin wall at clock 13
                  sec
                  sbc   #10
                  cmp   #4
                  bcs   :nol
                  lda   #$40
                  sta   CXM0FB
:nol              lda   RoomCtrl
                  and   #$40
                  beq   :nor
                  lda   BallX                   ; right thin wall at clock 150
                  sec
                  sbc   #147
                  cmp   #4
                  bcs   :nor
                  lda   #$40
                  sta   CXM1FB
:nor              lda   BallX
                  lsr
                  lsr
                  tax
                  lda   T4
                  jsr   PFBitTest
                  beq   :c2
                  lda   #$80
                  sta   CXBLPF
:c2               lda   BallX
                  clc
                  adc   #3
                  lsr
                  lsr
                  tax
                  lda   T4
                  jsr   PFBitTest
                  beq   :bnext
                  lda   #$80
                  sta   CXBLPF
:bnext            ldy   T3
                  dey
                  bne   :brow
* --- ball vs the two objects
                  ldx   #0
                  jsr   BallVsObj
                  beq   :nop0
                  lda   #$40
                  sta   CXP0FB
:nop0             ldx   #3
                  jsr   BallVsObj
                  beq   :nop1
                  lda   #$40
                  sta   CXP1FB
:nop1             jsr   ObjVsObj
                  beq   :done
                  lda   #$80
                  sta   CXPPMM
:done             rts

* A = count -> A = playfield row 0-6, carry set if not on screen
RowOfCount        cmp   #9
                  bcc   :no
                  cmp   #105
                  bcs   :no
                  cmp   #97
                  bcc   :r1
                  lda   #0
                  clc
                  rts
:r1               cmp   #17
                  bcs   :r2
                  lda   #6
                  clc
                  rts
:r2               sta   T5
                  lda   #96
                  sec
                  sbc   T5
                  lsr
                  lsr
                  lsr
                  lsr
                  clc
                  adc   #1
                  clc
                  rts
:no               sec
                  rts

* A = row, X = column 0-39 -> A nonzero if that playfield pixel is set
PFBitTest         sta   T5                      ; keep the row: mirroring clobbers A
                  cpx   #40
                  bcs   :zero
                  cpx   #20
                  bcc   :ok
                  txa
                  eor   #$ff                    ; mirror: 39-col
                  clc
                  adc   #40
                  tax
:ok               lda   T5
                  asl
                  clc
                  adc   T5                      ; row*3
                  clc
                  adc   ColByte,x
                  tay
                  lda   (RoomGfxPtr),y
                  and   ColMask,x
                  rts
:zero             lda   #0
                  rts
ColByte           db    0,0,0,0,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2
ColMask           db    $10,$20,$40,$80,$80,$40,$20,$10,$08,$04,$02,$01,$01,$02,$04,$08,$10,$20,$40,$80
BitMask           db    $80,$40,$20,$10,$08,$04,$02,$01

* X = descriptor offset (0 = obj1, 3 = obj2), A = clock, Y = count
* -> A nonzero if that object has a pixel there.  Preserves X, Y.
PixelAt           sta   CkT
                  sty   CtT
                  lda   DescA+1,x
                  sec
                  sbc   #1
                  sec
                  sbc   CtT                     ; row index = Y-1-count
                  bcc   :zero
                  sta   RowT
                  ldy   DescA+2,x
                  cmp   SprHeight,y
                  bcs   :zero
                  lda   CkT
                  sec
                  sbc   DescA,x                 ; clock offset
                  bcc   :zero
                  sta   DxT
                  lda   SprQuad,y
                  beq   :nq
                  lda   DxT
                  lsr
                  lsr
                  sta   DxT
:nq               lda   DxT
                  cmp   #8
                  bcs   :zero
                  lda   SprRowsL,y
                  sta   Ptr
                  lda   SprRowsH,y
                  sta   Ptr+1
                  ldy   RowT
                  lda   (Ptr),y
                  ldy   DxT
                  and   BitMask,y
                  sta   T5
                  ldy   CtT
                  lda   T5                      ; flags from the pixel, not from ldy
                  rts
:zero             ldy   CtT
                  lda   #0
                  rts

* X = descriptor offset -> A nonzero if the ball overlaps that object.
* Reject on the bounding boxes first - per-pixel work here is 16 PixelAt
* calls, and most frames nothing is anywhere near the ball.
BallVsObj         ldy   DescA+2,x
                  lda   SprHeight,y
                  beq   :miss
                  lda   BallX
                  clc
                  adc   #4
                  cmp   DescA,x                 ; ball wholly to the left?
                  bcc   :miss
                  jsr   ObjRight
                  cmp   BallX                   ; object wholly to the left?
                  beq   :miss
                  bcc   :miss
                  lda   BallY
                  sec
                  sbc   #4
                  cmp   DescA+1,x               ; ball wholly above?
                  bcs   :miss
                  jsr   ObjBottom
                  cmp   BallY                   ; object wholly above?
                  bcc   :test
                  lda   #0
                  rts
:miss             lda   #0
                  rts
:test             ldy   #4
:row              sty   T3
                  lda   BallY
                  sec
                  sbc   T3
                  bcc   :next
                  sta   CtT
                  lda   BallX
                  sta   T4
:clk              lda   T4
                  cmp   #160
                  bcs   :next
                  ldy   CtT
                  jsr   PixelAt
                  bne   :hit
                  inc   T4
                  lda   T4
                  sec
                  sbc   BallX
                  cmp   #4
                  bcc   :clk
:next             ldy   T3
                  dey
                  bne   :row
                  lda   #0
:hit              rts

* -> A nonzero if obj1 and obj2 overlap (pixel accurate)
ObjVsObj          ldy   DescA+2
                  lda   SprHeight,y
                  beq   :none
                  ldy   DescB+2
                  lda   SprHeight,y
                  beq   :none
* clock range: XLo = max(Ax,Bx), XHi = min(Ax+wA, Bx+wB) (clamped to 255)
                  lda   DescA
                  cmp   DescB
                  bcs   :xa
                  lda   DescB
:xa               sta   XLo
                  ldx   #0
                  jsr   ObjRight
                  sta   XHi
                  ldx   #3
                  jsr   ObjRight
                  cmp   XHi
                  bcs   :xb
                  sta   XHi
:xb               lda   XLo
                  cmp   XHi
                  bcs   :none
* count range: CLo = max(Ay-hA, By-hB), CHi = min(Ay-1, By-1)
                  ldx   #0
                  jsr   ObjBottom
                  sta   CLo
                  ldx   #3
                  jsr   ObjBottom
                  cmp   CLo
                  bcc   :ca
                  sta   CLo
:ca               lda   DescA+1
                  cmp   DescB+1
                  bcc   :cb
                  lda   DescB+1
:cb               sec
                  sbc   #1
                  bcc   :none
                  sta   CHi
                  cmp   CLo
                  bcc   :none
:crow             lda   XLo
                  sta   T4
:cclk             lda   T4
                  ldy   CHi
                  ldx   #0
                  jsr   PixelAt
                  beq   :cnext
                  lda   T4
                  ldx   #3
                  jsr   PixelAt
                  bne   :hit
:cnext            inc   T4
                  lda   T4
                  cmp   XHi
                  bcc   :cclk
                  dec   CHi
                  lda   CHi
                  cmp   CLo
                  bcs   :crow
:none             lda   #0
:hit              rts

* X = descriptor -> A = x + width (8 or 32), clamped to 255
ObjRight          ldy   DescA+2,x
                  lda   SprQuad,y
                  beq   :n
                  lda   #32
                  bne   :add
:n                lda   #8
:add              clc
                  adc   DescA,x
                  bcc   :ok
                  lda   #$ff
:ok               rts
* X = descriptor -> A = y - height (lowest count occupied, clamped to 0)
ObjBottom         ldy   DescA+2,x
                  lda   DescA+1,x
                  sec
                  sbc   SprHeight,y
                  bcs   :ok
                  lda   #0
:ok               rts
