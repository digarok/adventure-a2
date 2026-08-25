*-------------------------------------------------------------
* HGR renderer.  2600 geometry maps onto HGR as:
*   1 playfield pixel (4 clocks) = 1 HGR byte (7 px)
*   1 game unit (count) = 2 HGR lines; count 104 = line 0
*   object clock X -> byte X/4, phase X&3 (pre-shifted 0/2/4/6 px)
* Two pages: the back page is erased (dirty rects restored from
* the room template), redrawn, then flipped.
*-------------------------------------------------------------
* per-page state
* signature of the template on each page: gfx ptr lo/hi, wall class, ctrl.
* Keyed on the graphics pointer, not the room number: Portals can change
* the room after the last SetupRoomPrint, so the number alone lies.
DrawnSig          db    $ff,$ff,$ff,$ff, $ff,$ff,$ff,$ff
DirtyCnt          db    0,0
DirtyList         ds    2*4*4                   ; page: 4 rects of x,w,top,h
DrawPage          db    0                       ; page being drawn (back page)
RoomBytes         ds    7*40                    ; template: one byte per PF pixel per row
WallClass         db    0
* zero page scratch for the renderer (not used by the core)
RP                equ   $30                     ; screen line pointer
RQ                equ   $32                     ; sprite data pointer
RTmpl             equ   $34                     ; template row pointer
RX                equ   $36                     ; byte x
RW                equ   $37                     ; width in bytes
RLine             equ   $38                     ; current line
RRows             equ   $39                     ; rows left
RPhase            equ   $3a
RMaskE            equ   $3b                     ; color mask, even byte
RMaskO            equ   $3c                     ; color mask, odd byte
RHi               equ   $3d                     ; hi bit
RPageHi           equ   $3e                     ; $00 or $20 added to HgrHi
RPrio             equ   $3f                     ; nonzero: walls over sprites
RCnt              equ   $40
RBpr              equ   $41
RDx               equ   $42

* HGR color classes: mask for even bytes, odd bytes, hi bit
*   0 none(invisible) 1 white 2 violet 3 green 4 blue 5 orange
ClassMaskE        db    $00,$7f,$55,$2a,$55,$2a
ClassMaskO        db    $00,$7f,$2a,$55,$2a,$55
ClassHi           db    $00,$00,$00,$00,$80,$80
* 2600 hue (color>>4) -> class.  Hue 0 handled by luminance.
HueClass          db    1,1,5,5,5,2,2,2,4,4,4,3,3,3,3,5

* A = 2600 color -> A = class
ColorClass        cmp   #$10
                  bcs   :hue
                  cmp   #$06
                  bcc   :white                  ; black objects -> white on our black bg
                  cmp   #$0a
                  bcc   :none                   ; bg gray = invisible
:white            lda   #1
                  rts
:none             lda   #0
                  rts
:hue              lsr
                  lsr
                  lsr
                  lsr
                  tax
                  lda   HueClass,x
                  rts

*-------------------------------------------------------------
DrawFrame         jsr   LatchCollisions
                  ldx   DrawPage
                  lda   #0
                  sta   RPageHi
                  cpx   #0
                  beq   :p0
                  lda   #$20
                  sta   RPageHi
:p0               lda   RoomCtrl
                  and   #$04
                  sta   RPrio
                  lda   PFOverride
                  cmp   #$ff
                  bne   :ov
                  lda   RoomColor
:ov               jsr   ColorClass
                  sta   WallClass
                  ldx   DrawPage                ; ColorClass clobbers X
                  beq   :sig0
                  ldx   #4
:sig0             lda   RoomGfxPtr
                  cmp   DrawnSig,x
                  bne   :full
                  lda   RoomGfxPtr+1
                  cmp   DrawnSig+1,x
                  bne   :full
                  lda   WallClass
                  cmp   DrawnSig+2,x
                  bne   :full
                  lda   RoomCtrl
                  cmp   DrawnSig+3,x
                  bne   :full
                  jsr   EraseDirty
                  jmp   :objects
:full             jsr   DrawRoom
:objects          lda   #0
                  ldx   DrawPage
                  sta   DirtyCnt,x
                  lda   Obj1X
                  sta   RX
                  lda   Obj1Y
                  sta   RLine
                  lda   Obj1Color
                  jsr   ColorClass
                  tay
                  lda   Obj1SprId
                  jsr   DrawSprite
                  lda   Obj2X
                  sta   RX
                  lda   Obj2Y
                  sta   RLine
                  lda   Obj2Color
                  jsr   ColorClass
                  tay
                  lda   Obj2SprId
                  jsr   DrawSprite
                  jsr   DrawBall
* flip
                  lda   DrawPage
                  beq   :show0
                  sta   PAGE2
                  lda   #0
                  sta   DrawPage
                  rts
:show0            sta   PAGE1
                  lda   #1
                  sta   DrawPage
                  rts

*-------------------------------------------------------------
* Full room draw on the back page: build RoomBytes template then
* fill all 192 lines.
DrawRoom          ldx   DrawPage
                  lda   #0
                  sta   DirtyCnt,x
                  cpx   #0
                  beq   :sig0
                  ldx   #4
:sig0             lda   RoomGfxPtr
                  sta   DrawnSig,x
                  lda   RoomGfxPtr+1
                  sta   DrawnSig+1,x
                  lda   WallClass
                  sta   DrawnSig+2,x
                  lda   RoomCtrl
                  sta   DrawnSig+3,x
                  jsr   BuildTemplate
                  lda   #0
                  sta   RLine
:line             lda   RLine
                  jsr   RowOfLine
                  jsr   TemplateRow             ; RTmpl -> 40 bytes
                  ldx   RLine
                  lda   HgrLo,x
                  sta   RP
                  lda   HgrHi,x
                  clc
                  adc   RPageHi
                  sta   RP+1
                  ldy   #39
:copy             lda   (RTmpl),y
                  sta   (RP),y
                  dey
                  bpl   :copy
                  inc   RLine
                  lda   RLine
                  cmp   #192
                  bne   :line
                  rts

* A = line -> A = playfield row 0-6
RowOfLine         cmp   #16
                  bcc   :r0
                  cmp   #176
                  bcs   :r6
                  sec
                  sbc   #16
                  lsr
                  lsr
                  lsr
                  lsr
                  lsr
                  clc
                  adc   #1
                  rts
:r0               lda   #0
                  rts
:r6               lda   #6
                  rts

* A = row -> RTmpl = RoomBytes + row*40
TemplateRow       sta   T5
                  asl
                  asl
                  adc   T5                      ; *5
                  asl
                  asl
                  asl                           ; *40
                  clc
                  adc   #<RoomBytes
                  sta   RTmpl
                  lda   #>RoomBytes
                  adc   #0
                  sta   RTmpl+1
                  rts

* RoomBytes[row][col] = wall byte (color pattern) or 0, plus thin walls
BuildTemplate     ldx   WallClass
                  lda   ClassMaskE,x
                  ora   ClassHi,x
                  sta   RMaskE
                  lda   ClassMaskO,x
                  ora   ClassHi,x
                  sta   RMaskO
                  lda   #<RoomBytes
                  sta   RTmpl
                  lda   #>RoomBytes
                  sta   RTmpl+1
                  lda   #0
                  sta   RCnt                    ; row
:row              ldy   #0
:col              tya
                  pha
                  tax
                  lda   RCnt
                  jsr   PFBitTest
                  beq   :empty
                  pla
                  tay
                  tya
                  and   #1
                  bne   :odd
                  lda   RMaskE
                  jmp   :store
:odd              lda   RMaskO
                  jmp   :store
:empty            pla
                  tay
                  lda   #0
:store            sta   (RTmpl),y
                  iny
                  cpy   #40
                  bne   :col
* thin walls: clock 13 -> byte 3, px 1-2 ; clock 150 -> byte 37, px 3-4
* (both are odd bytes, so mask with RMaskO to keep the room's hue)
                  lda   RoomCtrl
                  bpl   :nol
                  ldy   #3
                  lda   RMaskO
                  and   #$86                    ; px window + hi bit
                  ora   (RTmpl),y
                  sta   (RTmpl),y
:nol              lda   RoomCtrl
                  and   #$40
                  beq   :nor
                  ldy   #37
                  lda   RMaskO
                  and   #$98
                  ora   (RTmpl),y
                  sta   (RTmpl),y
:nor              lda   RTmpl
                  clc
                  adc   #40
                  sta   RTmpl
                  bcc   :nc
                  inc   RTmpl+1
:nc               inc   RCnt
                  lda   RCnt
                  cmp   #7
                  bne   :row
                  rts

*-------------------------------------------------------------
* Restore the back page's dirty rects from the template
EraseDirty        ldx   DrawPage
                  lda   DirtyCnt,x
                  beq   :done
                  sta   RCnt
                  txa
                  asl
                  asl
                  asl
                  asl                           ; page*16
                  tax
:rect             lda   DirtyList,x
                  sta   RX
                  lda   DirtyList+1,x
                  sta   RW
                  lda   DirtyList+2,x
                  sta   RLine
                  lda   DirtyList+3,x
                  sta   RRows
                  stx   T4
:line             lda   RLine
                  jsr   RowOfLine
                  jsr   TemplateRow
                  ldx   RLine
                  lda   HgrLo,x
                  sta   RP
                  lda   HgrHi,x
                  clc
                  adc   RPageHi
                  sta   RP+1
                  ldy   RX
                  lda   RW
                  sta   T5
:byte             lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  dec   T5
                  bne   :byte
                  inc   RLine
                  dec   RRows
                  bne   :line
                  ldx   T4
                  inx
                  inx
                  inx
                  inx
                  dec   RCnt
                  bne   :rect
:done             rts

* record rect RX,RW,RLine(top),RRows(h) for the back page
AddDirty          ldx   DrawPage
                  lda   DirtyCnt,x
                  cmp   #4
                  bcs   :full
                  inc   DirtyCnt,x
                  asl
                  asl
                  sta   T5
                  txa
                  asl
                  asl
                  asl
                  asl
                  clc
                  adc   T5
                  tax
                  lda   RX
                  sta   DirtyList,x
                  lda   RW
                  sta   DirtyList+1,x
                  lda   RLine
                  sta   DirtyList+2,x
                  lda   RRows
                  sta   DirtyList+3,x
:full             rts

*-------------------------------------------------------------
* DrawSprite: A = sprite id, Y = color class, RX = clock x,
* RLine = 2600 Y.  OR-blits the pre-shifted sprite onto the back
* page (masked by the room template in PF-priority rooms).
DrawSprite        sta   T3
                  cpy   #0
                  bne   :vis
                  rts                           ; invisible color
:vis              tax
                  lda   SprHeight,x
                  bne   :hasrows
                  rts
:hasrows          sta   RRows
                  lda   ClassMaskE,y
                  sta   RMaskE
                  lda   ClassMaskO,y
                  sta   RMaskO
                  lda   ClassHi,y
                  sta   RHi
                  lda   SprHgrBpr,x
                  sta   RBpr
                  lda   SprHgrL,x
                  sta   RQ
                  lda   SprHgrH,x
                  sta   RQ+1
                  lda   RX
                  and   #3
                  sta   RPhase
                  lda   RX
                  lsr
                  lsr
                  sta   RX                      ; byte x
* data += phase * rows * bpr
                  lda   RPhase
                  beq   :ph0
:phl              lda   RRows
                  sta   T4
:pha              lda   RQ
                  clc
                  adc   RBpr
                  sta   RQ
                  bcc   :nc
                  inc   RQ+1
:nc               dec   T4
                  bne   :pha
                  dec   RPhase
                  bne   :phl
:ph0
* top line = (105 - Y)*2 ; skip rows above the screen
                  lda   #105
                  sec
                  sbc   RLine
                  bcs   :ok
                  jmp   :skiprows
:ok               asl
                  bcs   :below                  ; >= 256: off bottom
                  sta   RLine
                  cmp   #192
                  bcs   :below
                  jmp   :draw
:skiprows         lda   RLine                   ; Y > 105: first (Y-105) rows are off the top
                  sec
                  sbc   #105
                  sta   T4
:sk               lda   RQ
                  clc
                  adc   RBpr
                  sta   RQ
                  bcc   :nc2
                  inc   RQ+1
:nc2              dec   RRows
                  beq   :below
                  dec   T4
                  bne   :sk
                  lda   #0
                  sta   RLine
:draw             lda   RBpr
                  sta   RW
                  lda   RRows
                  asl
                  sta   RRows                   ; lines
                  lda   RLine
                  clc
                  adc   RRows
                  bcc   :fits
                  lda   #192
:fits             cmp   #193
                  bcc   :fits2
                  lda   #192
:fits2            sec
                  sbc   RLine
                  sta   RRows                   ; clipped line count
                  jsr   AddDirty
:row              jsr   BlitRow                 ; line RLine
                  inc   RLine
                  jsr   BlitRow                 ; line RLine (same data)
                  inc   RLine
                  lda   RQ
                  clc
                  adc   RBpr
                  sta   RQ
                  bcc   :nc3
                  inc   RQ+1
:nc3              dec   RRows
                  beq   :below
                  dec   RRows
                  bne   :row
:below
:skip             rts

* OR one sprite row (RBpr bytes at RQ) into line RLine at byte RX
BlitRow           lda   RLine
                  cmp   #192
                  bcs   :done
                  tax
                  lda   HgrLo,x
                  sta   RP
                  lda   HgrHi,x
                  clc
                  adc   RPageHi
                  sta   RP+1
                  lda   RLine
                  jsr   RowOfLine
                  jsr   TemplateRow
                  ldy   #0
                  sty   RDx
:byte             lda   RX
                  clc
                  adc   RDx
                  cmp   #40
                  bcs   :done
                  tay
                  and   #1
                  bne   :odd
                  lda   RMaskE
                  jmp   :mask
:odd              lda   RMaskO
:mask             sta   T5
                  ldy   RDx
                  lda   (RQ),y
                  and   T5
                  beq   :next                   ; nothing to draw
                  ora   RHi
                  sta   T5
                  lda   RX
                  clc
                  adc   RDx
                  tay
                  lda   RPrio
                  beq   :noprio
                  lda   (RTmpl),y
                  and   #$7f
                  eor   #$7f
                  and   T5
                  sta   T5                      ; walls punch through
:noprio           lda   (RP),y
                  ora   T5
                  sta   (RP),y
:next             inc   RDx
                  lda   RDx
                  cmp   RBpr
                  bne   :byte
:done             rts

*-------------------------------------------------------------
* The ball: 4 clocks x 4 counts = 7 px x 8 lines.  The 2600 drew
* it with COLUPF, so it takes the room's wall colour - which is
* what makes the man invisible in the catacombs.
BallPat           db    $7f,$00, $7c,$03, $70,$0f, $40,$3f
BallB1            db    0
BallB2            db    0
DrawBall          ldy   WallClass
                  bne   :vis                    ; invisible room
                  rts
:vis              lda   ClassMaskE,y
                  ora   ClassHi,y
                  sta   RMaskE
                  lda   ClassMaskO,y
                  ora   ClassHi,y
                  sta   RMaskO
                  lda   BallY
                  beq   :skip
                  lda   #105
                  sec
                  sbc   BallY
                  bcc   :skip
                  asl
                  cmp   #192
                  bcs   :skip
                  sta   RLine
                  lda   #8
                  sta   RRows
                  lda   BallX
                  lsr
                  lsr
                  sta   RX
                  lda   #2
                  sta   RW
                  jsr   AddDirty                ; clobbers X, so index it after
* the two screen bytes are the same on every line: build them once
                  lda   RX
                  and   #1
                  bne   :odd
                  lda   RMaskE
                  ldy   RMaskO
                  jmp   :mk
:odd              lda   RMaskO
                  ldy   RMaskE
:mk               sta   RDx                     ; mask for byte RX
                  sty   RCnt                    ; mask for byte RX+1
                  lda   BallX
                  and   #3
                  asl
                  tax
                  lda   BallPat,x
                  ldy   RDx
                  jsr   BallByte
                  sta   BallB1
                  lda   BallPat+1,x
                  ldy   RCnt
                  jsr   BallByte
                  sta   BallB2
:line             ldy   RLine
                  cpy   #192
                  bcs   :skip
                  lda   HgrLo,y
                  sta   RP
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   RP+1
                  ldy   RX
                  lda   (RP),y
                  ora   BallB1
                  sta   (RP),y
                  iny
                  cpy   #40
                  bcs   :n
                  lda   (RP),y
                  ora   BallB2
                  sta   (RP),y
:n                inc   RLine
                  dec   RRows
                  bne   :line
:skip             rts

* A = 1-bit pattern, Y = colour mask (hi bit included) -> A = byte
BallByte          sty   T4
                  and   T4
                  and   #$7f
                  beq   :zero
                  sta   T5
                  lda   T4
                  and   #$80
                  ora   T5
:zero             rts
