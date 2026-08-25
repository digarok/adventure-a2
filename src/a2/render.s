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
* Per page, per drawn item (0 = object 1, 1 = object 2, 2 = the ball):
* what was drawn (sprite, x, y, colour) and the rectangle it went into.
* An item whose signature is unchanged is left alone - in Adventure only
* the ball usually moves, so the big sprites cost nothing most frames.
SlotSig           ds    2*3*4
SlotRect          ds    2*3*4                   ; x, w, top line, lines
NewSig            ds    3*4
ChgFlags          ds    3
SlotBase          db    0                       ; page*12
CurSlot           db    0
FullRedraw        db    0
DrawPage          db    0                       ; page being drawn (back page)
RoomBytes         ds    7*40                    ; template: one byte per PF pixel per row
RoomOpen          ds    7*40                    ; $7f where the row is open, $00 where a wall is
WallClass         db    0
* per-line pointer to the template row, and per-class colour masks
* indexed by screen byte column (parity + hi bit) - both built at init
TmplLo            ds    192
TmplHi            ds    192
MaskTab           ds    6*40
MaskTabL          ds    6
MaskTabH          ds    6
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
RXEnd             equ   $45                     ; one past the last screen byte
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
HueClass          db    1,5,5,5,5,2,2,2,4,4,4,3,3,3,3,5

* A = 2600 colour -> A = class.  Objects come in at ObjColorClass so
* that the 2600's black objects (portcullises, black key, bat, magnet)
* come out violet: we cannot draw black on a black background, and the
* walls already use white for it - the gate has to differ from its castle.
ObjColorClass     cmp   #$06
                  bcs   ColorClass
                  lda   #2
                  rts
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
InitRender        ldx   #0
:l1               txa
                  jsr   RowOfLine
                  jsr   TemplateRow
                  lda   RTmpl
                  sta   TmplLo,x
                  lda   RTmpl+1
                  sta   TmplHi,x
                  inx
                  cpx   #192
                  bne   :l1
                  lda   #<MaskTab
                  sta   RTmpl
                  lda   #>MaskTab
                  sta   RTmpl+1
                  ldx   #0                      ; class
:l2               lda   RTmpl
                  sta   MaskTabL,x
                  lda   RTmpl+1
                  sta   MaskTabH,x
                  ldy   #0
:l3               tya
                  and   #1
                  bne   :odd
                  lda   ClassMaskE,x
                  jmp   :st
:odd              lda   ClassMaskO,x
:st               ora   ClassHi,x
                  sta   (RTmpl),y
                  iny
                  cpy   #40
                  bne   :l3
                  lda   RTmpl
                  clc
                  adc   #40
                  sta   RTmpl
                  bcc   :nc
                  inc   RTmpl+1
:nc               inx
                  cpx   #6
                  bne   :l2
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
:sig0             lda   #0
                  sta   FullRedraw
                  lda   RoomGfxPtr
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
                  beq   :objects
:full             jsr   DrawRoom
                  lda   #1
                  sta   FullRedraw
:objects          lda   DrawPage
                  beq   :b0
                  lda   #12
:b0               sta   SlotBase
                  lda   SceneTick               ; snapshot once per 20 Hz tick so
                  beq   :snapped                ; both pages get the same picture
                  lda   #0
                  sta   SceneTick
                  jsr   BuildNewSig
:snapped          jsr   MarkChanged
                  jsr   EraseChanged
* draw the changed items
                  lda   ChgFlags
                  beq   :d2
                  lda   #0
                  sta   CurSlot
                  jsr   ClearSlotRect
                  lda   NewSig+1
                  sta   RX
                  lda   NewSig+2
                  sta   RLine
                  lda   NewSig+3
                  jsr   ObjColorClass
                  tay
                  lda   NewSig
                  jsr   DrawSprite
:d2               lda   ChgFlags+1
                  beq   :d3
                  lda   #1
                  sta   CurSlot
                  jsr   ClearSlotRect
                  lda   NewSig+5
                  sta   RX
                  lda   NewSig+6
                  sta   RLine
                  lda   NewSig+7
                  jsr   ObjColorClass
                  tay
                  lda   NewSig+4
                  jsr   DrawSprite
:d3               lda   ChgFlags+2
                  beq   :flip
                  lda   #2
                  sta   CurSlot
                  jsr   ClearSlotRect
                  jsr   DrawBall
:flip
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
* What should be on screen this frame, per item.
BuildNewSig       lda   Obj1SprId
                  sta   NewSig
                  lda   Obj1X
                  sta   NewSig+1
                  lda   Obj1Y
                  sta   NewSig+2
                  lda   Obj1Color
                  sta   NewSig+3
                  lda   Obj2SprId
                  sta   NewSig+4
                  lda   Obj2X
                  sta   NewSig+5
                  lda   Obj2Y
                  sta   NewSig+6
                  lda   Obj2Color
                  sta   NewSig+7
                  lda   #$fe                    ; the ball has no sprite id
                  sta   NewSig+8
                  lda   BallX
                  sta   NewSig+9
                  lda   BallY
                  sta   NewSig+10
                  lda   WallClass               ; the ball takes the wall colour
                  sta   NewSig+11
                  rts

* ChgFlags[i] = nonzero if item i must be redrawn on this page
MarkChanged       ldx   #0                      ; NewSig index
                  ldy   SlotBase                ; SlotSig index
                  lda   #0
                  sta   RCnt                    ; item
:item             lda   FullRedraw
                  bne   :chg
                  lda   NewSig,x
                  cmp   SlotSig,y
                  bne   :chg
                  lda   NewSig+1,x
                  cmp   SlotSig+1,y
                  bne   :chg
                  lda   NewSig+2,x
                  cmp   SlotSig+2,y
                  bne   :chg
                  lda   NewSig+3,x
                  cmp   SlotSig+3,y
                  beq   :same
:chg              lda   #1
                  bne   :store
:same             lda   #0
:store            stx   T4
                  ldx   RCnt
                  sta   ChgFlags,x
                  ldx   T4
                  lda   NewSig,x                ; remember what we are about to draw
                  sta   SlotSig,y
                  lda   NewSig+1,x
                  sta   SlotSig+1,y
                  lda   NewSig+2,x
                  sta   SlotSig+2,y
                  lda   NewSig+3,x
                  sta   SlotSig+3,y
                  inx
                  inx
                  inx
                  inx
                  iny
                  iny
                  iny
                  iny
                  inc   RCnt
                  lda   RCnt
                  cmp   #3
                  bne   :item
                  rts

* SlotRect for the item in CurSlot -> zero height (nothing drawn)
ClearSlotRect     jsr   SlotRectIdx
                  lda   #0
                  sta   SlotRect+3,x
                  rts

* X = SlotBase + CurSlot*4
SlotRectIdx       lda   CurSlot
                  asl
                  asl
                  clc
                  adc   SlotBase
                  tax
                  rts

* remember the rectangle just drawn for CurSlot
SetSlotRect       jsr   SlotRectIdx
                  lda   RX
                  clc
                  adc   RW
                  cmp   #41                     ; clip the rect to the line
                  bcc   :fits
                  lda   #40
                  sec
                  sbc   RX
                  jmp   :w
:fits             lda   RW
:w                sta   SlotRect+1,x
                  lda   RX
                  sta   SlotRect,x
                  lda   RLine
                  sta   SlotRect+2,x
                  lda   RRows
                  sta   SlotRect+3,x
                  rts

* restore what the changed items covered on this page.  After a full
* room redraw there is nothing to undo.
EraseChanged      lda   FullRedraw
                  bne   :done
                  lda   #0
                  sta   CurSlot
:item             ldx   CurSlot
                  lda   ChgFlags,x
                  beq   :next
                  jsr   SlotRectIdx
                  lda   SlotRect+3,x
                  beq   :next
                  sta   RRows
                  lda   SlotRect,x
                  sta   RX
                  lda   SlotRect+1,x
                  sta   RW
                  lda   SlotRect+2,x
                  sta   RLine
                  jsr   EraseRect
:next             inc   CurSlot
                  lda   CurSlot
                  cmp   #3
                  bne   :item
:done             rts

*-------------------------------------------------------------
* Full room draw on the back page: build RoomBytes template then
* fill all 192 lines.
DrawRoom          ldx   DrawPage
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
RShp              equ   $43                     ; RoomOpen row pointer
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
                  lda   #<RoomOpen
                  sta   RShp
                  lda   #>RoomOpen
                  sta   RShp+1
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
                  lda   #0                      ; wall: hides sprites above it
                  sta   (RShp),y
                  tya
                  and   #1
                  bne   :odd
                  lda   RMaskE
                  jmp   :store
:odd              lda   RMaskO
                  jmp   :store
:empty            pla
                  tay
                  lda   #$7f                    ; open
                  sta   (RShp),y
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
                  ldy   #3
                  lda   (RShp),y
                  and   #$79
                  sta   (RShp),y
:nol              lda   RoomCtrl
                  and   #$40
                  beq   :nor
                  ldy   #37
                  lda   RMaskO
                  and   #$98
                  ora   (RTmpl),y
                  sta   (RTmpl),y
                  ldy   #37
                  lda   (RShp),y
                  and   #$67
                  sta   (RShp),y
:nor              lda   RTmpl
                  clc
                  adc   #40
                  sta   RTmpl
                  bcc   :nc
                  inc   RTmpl+1
:nc               lda   RShp
                  clc
                  adc   #40
                  sta   RShp
                  bcc   :nc2
                  inc   RShp+1
:nc2              inc   RCnt
                  lda   RCnt
                  cmp   #7
                  bne   :row
                  rts

*-------------------------------------------------------------
* Restore one rectangle (RX, RW, RLine, RRows) from the template.
* Sprite rows are two lines each and template rows change only on
* even lines, so lines can safely be restored in pairs.
EraseRect         ldy   RLine
                  lda   TmplLo,y
                  sta   :e1+1
                  lda   TmplHi,y
                  sta   :e1+2
                  lda   HgrLo,y
                  sta   :e2+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   :e2+2
                  dec   RRows
                  bne   :two                    ; odd line left over?
                  jmp   :same
:two              iny
                  lda   HgrLo,y
                  sta   :e3+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   :e3+2
                  dec   RRows
                  jmp   :go
:same             lda   :e2+1                   ; store the same line twice
                  sta   :e3+1
                  lda   :e2+2
                  sta   :e3+2
:go               ldx   RX
                  ldy   RW
:e1               lda   RoomBytes,x
:e2               sta   $2000,x
:e3               sta   $2000,x
                  inx
                  dey
                  bne   :e1
                  inc   RLine
                  inc   RLine
                  lda   RRows
                  bne   EraseRect
                  rts

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
                  lda   MaskTabL,y
                  sta   BR2mask+1
                  sta   BR3mask+1
                  lda   MaskTabH,y
                  sta   BR2mask+2
                  sta   BR3mask+2
                  lda   SprHgrBpr,x
                  sta   RBpr
                  lda   SprHgrL,x
                  sta   RQ
                  lda   SprHgrH,x
                  sta   RQ+1
                  lda   RX
                  and   #3
                  ldy   SprQuad,x                ; quad bits are whole HGR bytes:
                  beq   :ph                      ; no pre-shifted phases for those
                  lda   #0
:ph               sta   RPhase
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
                  lda   RX
                  clc
                  adc   RBpr
                  cmp   #41
                  bcc   :xok
                  lda   #40
:xok              sta   RXEnd
                  jsr   SetSlotRect
:row              lda   RPrio
                  bne   :prio
                  jsr   BlitRow2                ; both lines in one pass
                  jmp   :adv
:prio             jsr   BlitRow3                ; ... with walls in front
:adv              inc   RLine
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

* Fast path: OR one sprite row into lines RLine and RLine+1.  The
* colour mask table base at +22 and the two line addresses are
* patched in, so the inner loop is four instructions per byte.
* (No playfield priority here - see BlitRow for that.)
BlitRow2          ldy   RLine
                  lda   HgrLo,y
                  sta   BR2a1+1
                  sta   BR2a2+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR2a1+2
                  sta   BR2a2+2
                  iny
                  lda   HgrLo,y
                  sta   BR2b1+1
                  sta   BR2b2+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR2b1+2
                  sta   BR2b2+2
                  ldy   #0
                  ldx   RX
BR2byte           lda   (RQ),y
                  beq   BR2next
BR2mask           and   MaskTab,x               ; base patched per colour class
                  beq   BR2next
                  ora   RHi
                  sta   T5
BR2a1             ora   $2000,x
BR2a2             sta   $2000,x
                  lda   T5
BR2b1             ora   $2000,x
BR2b2             sta   $2000,x
BR2next           inx
                  cpx   #40
                  bcs   BR2done
                  iny
                  cpy   RBpr
                  bne   BR2byte
BR2done           rts

* Same, for rooms where the playfield is in front of the sprites
* (CTRLPF bit 2).  That is how the invisible surround reveals the
* catacomb mazes: the box shows wherever the room is open.
* Everything is indexed by the screen byte column, so the sprite row
* is reached through a base of RQ-RX; and because a pixel only lands
* where the room is open, the byte underneath is background and can be
* stored rather than OR-ed.
BlitRow3          lda   RQ
                  sec
                  sbc   RX
                  sta   BR3src+1
                  lda   RQ+1
                  sbc   #0
                  sta   BR3src+2
                  ldy   RLine
                  lda   TmplLo,y
                  clc
                  adc   #<RoomOpen-RoomBytes
                  sta   BR3op+1
                  lda   TmplHi,y
                  adc   #>RoomOpen-RoomBytes
                  sta   BR3op+2
                  lda   HgrLo,y
                  sta   BR3a+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR3a+2
                  iny
                  lda   HgrLo,y
                  sta   BR3b+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR3b+2
                  ldx   RX
BR3byte           
BR3src            lda   HGfxNull,x
                  beq   BR3next
BR3mask           and   MaskTab,x               ; base patched per colour class
                  beq   BR3next
BR3op             and   RoomOpen,x              ; walls stay in front
                  beq   BR3next
                  ora   RHi
BR3a              sta   $2000,x
BR3b              sta   $2000,x
BR3next           inx
                  cpx   RXEnd
                  bne   BR3byte
                  rts

*-------------------------------------------------------------
* The ball: 4 clocks x 4 counts = 7 px x 8 lines.  The 2600 drew
* it with COLUPF, so it takes the room's wall colour - which is
* what makes the man invisible in the catacombs.
BallPat           db    $7f,$00, $7c,$03, $70,$0f, $40,$3f
BallB1            db    0
BallB2            db    0
DrawBall          ldy   NewSig+11
                  bne   :vis                    ; invisible room
                  rts
:vis              lda   ClassMaskE,y
                  ora   ClassHi,y
                  sta   RMaskE
                  lda   ClassMaskO,y
                  ora   ClassHi,y
                  sta   RMaskO
                  lda   NewSig+10
                  bne   :on
                  rts
:on               lda   #105
                  sec
                  sbc   NewSig+10
                  bcs   :below
                  rts
:below            asl
                  bcc   :onscr
                  rts
:onscr            cmp   #192
                  bcc   :ok
                  rts
:ok
                  sta   RLine
                  lda   #8
                  sta   RRows
                  lda   NewSig+9
                  lsr
                  lsr
                  sta   RX
                  lda   #2
                  sta   RW
                  jsr   SetSlotRect             ; clobbers X, so index it after
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
                  lda   NewSig+9
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
