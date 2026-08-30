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
* One slot per thing on screen: every object that is in the room, in
* object order, then the ball.  The 2600 could only put two objects up at
* once and rotated them, which is why Adventure strobes; nothing here has
* to, and a steady picture also costs less, because an item that has not
* moved is left alone rather than being torn down and rebuilt every tick.
* Collisions still come from the core's own two cached objects, so the
* game plays exactly as it did.
NSLOT             equ   8                       ; seven objects and the ball
BALLSLOT          equ   NSLOT-1
* Merlin evaluates strictly left to right, so BALLSLOT*4 has to be spelt
* out - NewSig+BALLSLOT*4 would assemble as (NewSig+BALLSLOT)*4.
BALLSIG           equ   NSLOT*4-4
SlotSig           ds    2*NSLOT*4               ; sprite, x, y, colour
SlotRect          ds    2*NSLOT*4               ; x, w, top line, lines
NewSig            ds    NSLOT*4
NewRect           ds    NSLOT*4                 ; measured rect, before drawing
OldRect           ds    NSLOT*4                 ; what this page had before
UnionRect         ds    NSLOT*4                 ; old and new together
SolidSlot         ds    NSLOT                   ; item may be drawn edge-only
DamagedOnly       ds    NSLOT                   ; only redrawn because a neighbour was
NeedDamage        ds    NSLOT                   ; ...as well as its own edges
DrawMode          db    0                       ; 1 = this pass is the damage patch
ErasedRect        ds    NSLOT*4                     ; what each item's erase restored
DamageRect        ds    4                       ; ...of the others, for one item
MeasureOnly       db    0
ItemSpr           db    0
ChgFlags          ds    NSLOT
ActiveList        ds    NSLOT                   ; slots with something to say
ActiveN           db    0
SlotBase          db    0                       ; page*NSLOT*4
CurSlot           db    0
FullRedraw        db    0
DrawPage          db    0                       ; page being drawn (back page)
FlipPending       db    0                       ; 0 none, 1 show page 1, 2 show page 2
RoomBytes         ds    7*40                    ; template: one byte per PF pixel per row
RoomOpen          ds    7*40                    ; $7f where the row is open, $00 where a wall is
RoomLit           ds    7*40                    ; what a solid sprite shows through it
LitClass          db    $ff                     ; colour class RoomLit was built for
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
RClass            equ   $46                     ; colour class of the sprite in hand
RXOrg             equ   $4e                     ; the sprite's true left byte
BallCut           equ   $4f                     ; ball masks a hole instead of drawing
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
* A compose is split in two so it can use the whole tick rather than being
* crammed between one pair of WaitFrames.  The erase half runs in the first
* slice and the draw half in the second; in between only the back page is
* half-built, and the snapshot taken at the top means the movement that runs
* between them cannot change what is being painted.
DrawFrame         jsr   DrawFrameBegin
                  jmp   DrawFrameEnd

DrawFrameBegin    jsr   LatchCollisions
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
                  lda   #NSLOT*4
:b0               sta   SlotBase
                  lda   SceneTick               ; snapshot once per 20 Hz tick so
                  beq   :snapped                ; both pages get the same picture
                  lda   #0
                  sta   SceneTick
                  jsr   BuildNewSig
:snapped          jsr   MarkChanged
* Work out where the changed items are going before touching the screen:
* undoing one of them must not eat into another that is staying put.
                  lda   #1
                  sta   MeasureOnly
                  jsr   MeasureItems
                  lda   #0
                  sta   MeasureOnly
                  jsr   SpreadChanges
                  jsr   EraseChanged
                  rts

DrawFrameEnd      jsr   DrawItems
* The page just composed is shown at the next WaitFrame, inside VBL.  While
* both pages held the same picture the flip could go anywhere; a tick apart,
* flipping mid-frame would show the old tick above the raster and the new one
* below it.
:flip             lda   DrawPage
                  beq   :show0
                  lda   #2                      ; page 2 is ready
                  sta   FlipPending
                  lda   #0
                  sta   DrawPage
                  rts
:show0            lda   #1                      ; page 1 is ready
                  sta   FlipPending
                  sta   DrawPage
                  rts

*-------------------------------------------------------------
* What WaitFrame runs: wait out the frame, then show whatever DrawFrame
* finished while it was being displayed.
FrameSync         jsr   WaitVBL
                  ldx   FlipPending
                  beq   :none
                  lda   #0
                  sta   FlipPending
                  cpx   #1
                  bne   :page2
                  sta   PAGE1
                  rts
:page2            sta   PAGE2
:none             rts

*-------------------------------------------------------------
* Walk the three items (object 1, object 2, ball), drawing - or, in the
* measure pass, only working out the rectangle of - the changed ones.
* Fill NewRect for every item - the changed ones by running their draw
* with MeasureOnly set, the rest by carrying their current rectangle
* forward - and note which may be drawn edge-only.
MeasureItems      lda   #0
                  sta   CurSlot
:item             ldy   CurSlot
                  lda   #0
                  sta   SolidSlot,y
                  lda   CurSlot
                  asl
                  asl
                  tax
                  lda   #0
                  sta   NewRect+3,x
                  lda   ChgFlags,y
                  beq   :next
                  lda   CurSlot
                  cmp   #BALLSLOT               ; the ball is never "solid"
                  beq   :next
                  lda   NewSig,x
                  tay
                  lda   SprSolid,y
                  beq   :next
                  ldy   CurSlot
                  sta   SolidSlot,y
                  jsr   DrawItem                ; MeasureOnly: fills NewRect
:next             inc   CurSlot
                  lda   CurSlot
                  cmp   #NSLOT
                  bne   :item
                  rts

* Two items that overlap have to be redrawn together, and drawn whole:
* the edge-only shortcut assumes the overlap still holds good pixels.
SpreadChanges     ldx   #NSLOT-1
                  lda   #0
:clr              sta   DamagedOnly,x
                  sta   NeedDamage,x
                  dex
                  bpl   :clr
                  ldx   #NSLOT-1                ; anything not being redrawn,
:chk              lda   ChgFlags,x              ; or anything solid, means
                  beq   :work                   ; there is work to do
                  lda   SolidSlot,x
                  bne   :work
                  dex
                  bpl   :chk
                  rts
:work             jsr   BuildUnions
                  lda   ActiveN
                  cmp   #2
                  bcs   :pairs
                  rts
:pairs            lda   #2                      ; settle over the slots
                  sta   T5
* only pairs with a changed item in them can matter, and there is usually
* one of those against a handful of active slots - not every pair of eight
:pass             lda   #0
                  sta   T2                      ; index into ActiveList
:i                ldx   T2
                  lda   ActiveList,x
                  tax
                  lda   ChgFlags,x
                  beq   :inext
                  stx   T0
                  lda   #0
                  sta   T4                      ; index of the other one
:j                ldx   T4
                  lda   ActiveList,x
                  cmp   T0
                  beq   :jnext
                  sta   T1
                  jsr   PairCheck
:jnext            inc   T4
                  lda   T4
                  cmp   ActiveN
                  bcc   :j
:inext            inc   T2
                  lda   T2
                  cmp   ActiveN
                  bcc   :i
                  dec   T5
                  bne   :pass
                  rts

* T0 and T1 are the two slots
PairCheck         ldx   T0
                  lda   ChgFlags,x
                  ldx   T1
                  ora   ChgFlags,x
                  bne   :any
                  rts                           ; neither is being redrawn
:any              lda   T0
                  asl
                  asl
                  tax
                  lda   T1
                  asl
                  asl
                  tay
                  jsr   RectOverlap
                  bcs   :hit
                  rts
:hit              ldx   T0
                  jsr   MarkDamaged
                  ldx   T1
MarkDamaged       lda   SolidSlot,x
                  beq   :plain
                  lda   #1                      ; solid: its edges as usual, plus
                  sta   NeedDamage,x            ; a second pass over the damage
                  sta   ChgFlags,x
                  rts
:plain            lda   ChgFlags,x
                  bne   :was
                  lda   #1                      ; only collateral: its pixels are
                  sta   DamagedOnly,x           ; still right outside the damage
:was              lda   #1
                  sta   ChgFlags,x
                  rts

* Accumulate what has actually been restored, so an item caught by it can
* be repainted over just that much.  Taking the whole old rectangle of an
* item that is only having its edges cleared would count far too much.
MergeDamage       lda   CurSlot
                  asl
                  asl
                  tax
                  lda   ErasedRect+3,x
                  bne   :grow
                  lda   RX
                  sta   ErasedRect,x
                  lda   RW
                  sta   ErasedRect+1,x
                  lda   RLine
                  sta   ErasedRect+2,x
                  lda   RRows
                  sta   ErasedRect+3,x
                  rts
:grow             lda   ErasedRect,x            ; right edge
                  clc
                  adc   ErasedRect+1,x
                  sta   T5
                  lda   RX
                  cmp   ErasedRect,x
                  bcs   :l
                  sta   ErasedRect,x
:l                lda   RX
                  clc
                  adc   RW
                  cmp   T5
                  bcs   :r
                  lda   T5
:r                sec
                  sbc   ErasedRect,x
                  sta   ErasedRect+1,x
                  lda   ErasedRect+2,x          ; bottom edge
                  clc
                  adc   ErasedRect+3,x
                  sta   T5
                  lda   RLine
                  cmp   ErasedRect+2,x
                  bcs   :t
                  sta   ErasedRect+2,x
:t                lda   RLine
                  clc
                  adc   RRows
                  cmp   T5
                  bcs   :b
                  lda   T5
:b                sec
                  sbc   ErasedRect+2,x
                  sta   ErasedRect+3,x
                  rts

* DamageRect = what the OTHER items restored over this one.  An item's own
* erase is not damage to itself, and lumping the two together would box up
* the whole sprite whenever the ball sat inside it.
BuildDamageFor    lda   #0
                  sta   DamageRect+3
                  lda   #0
                  sta   RCnt
:item             lda   RCnt
                  cmp   CurSlot
                  beq   :next
                  asl
                  asl
                  tax
                  lda   ErasedRect+3,x
                  beq   :next
                  ldy   DamageRect+3
                  bne   :grow
                  lda   ErasedRect,x
                  sta   DamageRect
                  lda   ErasedRect+1,x
                  sta   DamageRect+1
                  lda   ErasedRect+2,x
                  sta   DamageRect+2
                  lda   ErasedRect+3,x
                  sta   DamageRect+3
                  jmp   :next
:grow             lda   DamageRect
                  clc
                  adc   DamageRect+1
                  sta   T5
                  lda   ErasedRect,x
                  cmp   DamageRect
                  bcs   :l
                  sta   DamageRect
:l                lda   ErasedRect,x
                  clc
                  adc   ErasedRect+1,x
                  cmp   T5
                  bcs   :r
                  lda   T5
:r                sec
                  sbc   DamageRect
                  sta   DamageRect+1
                  lda   DamageRect+2
                  clc
                  adc   DamageRect+3
                  sta   T5
                  lda   ErasedRect+2,x
                  cmp   DamageRect+2
                  bcs   :t
                  sta   DamageRect+2
:t                lda   ErasedRect+2,x
                  clc
                  adc   ErasedRect+3,x
                  cmp   T5
                  bcs   :b
                  lda   T5
:b                sec
                  sbc   DamageRect+2
                  sta   DamageRect+3
:next             inc   RCnt
                  lda   RCnt
                  cmp   #NSLOT
                  beq   :done
                  jmp   :item
:done             rts

* What each item covers: the rectangle it is on screen with now, plus
* where a solid item is about to move to (its erase is edge-only, so its
* new position has to count as well).
BuildUnions       lda   #0
                  sta   ActiveN
                  sta   CurSlot
:item             jsr   SlotRectIdx
                  lda   CurSlot
                  asl
                  asl
                  tay
                  lda   SlotRect,x
                  sta   UnionRect,y
                  lda   SlotRect+1,x
                  sta   UnionRect+1,y
                  lda   SlotRect+2,x
                  sta   UnionRect+2,y
                  lda   SlotRect+3,x
                  sta   UnionRect+3,y
                  lda   NewRect+3,y             ; solid items only
                  beq   :act
                  lda   SlotRect+3,x
                  bne   :both
                  lda   NewRect,y               ; nothing was there before
                  sta   UnionRect,y
                  lda   NewRect+1,y
                  sta   UnionRect+1,y
                  lda   NewRect+2,y
                  sta   UnionRect+2,y
                  lda   NewRect+3,y
                  sta   UnionRect+3,y
                  jmp   :act
:both             lda   SlotRect,x              ; left edge
                  cmp   NewRect,y
                  bcc   :lx
                  lda   NewRect,y
:lx               sta   UnionRect,y
                  lda   SlotRect,x              ; right edge
                  clc
                  adc   SlotRect+1,x
                  sta   T4
                  lda   NewRect,y
                  clc
                  adc   NewRect+1,y
                  cmp   T4
                  bcs   :rx
                  lda   T4
:rx               sec
                  sbc   UnionRect,y
                  sta   UnionRect+1,y
                  lda   SlotRect+2,x            ; top edge
                  cmp   NewRect+2,y
                  bcc   :ty
                  lda   NewRect+2,y
:ty               sta   UnionRect+2,y
                  lda   SlotRect+2,x            ; bottom edge
                  clc
                  adc   SlotRect+3,x
                  sta   T4
                  lda   NewRect+2,y
                  clc
                  adc   NewRect+3,y
                  cmp   T4
                  bcs   :by
                  lda   T4
:by               sec
                  sbc   UnionRect+2,y
                  sta   UnionRect+3,y
:act              ldy   CurSlot                 ; empty and untouched slots can
                  lda   ChgFlags,y              ; neither damage nor be damaged
                  bne   :add
                  lda   CurSlot
                  asl
                  asl
                  tay
                  lda   UnionRect+3,y
                  beq   :next
:add              ldx   ActiveN
                  lda   CurSlot
                  sta   ActiveList,x
                  inc   ActiveN
:next             inc   CurSlot
                  lda   CurSlot
                  cmp   #NSLOT
                  beq   :done
                  jmp   :item
:done             rts

* UnionRect[x] against UnionRect[y] -> carry set if they overlap
RectOverlap       lda   UnionRect+3,x
                  beq   :no
                  lda   UnionRect+3,y
                  beq   :no
                  lda   UnionRect,x
                  sec
                  sbc   UnionRect,y
                  bcs   :ax
                  lda   UnionRect,y             ; x starts to the left
                  sec
                  sbc   UnionRect,x
                  cmp   UnionRect+1,x
                  bcs   :no
                  jmp   :yy
:ax               cmp   UnionRect+1,y
                  bcs   :no
:yy               lda   UnionRect+2,x
                  sec
                  sbc   UnionRect+2,y
                  bcs   :ay
                  lda   UnionRect+2,y           ; x starts above
                  sec
                  sbc   UnionRect+2,x
                  cmp   UnionRect+3,x
                  bcs   :no
                  sec
                  rts
:ay               cmp   UnionRect+3,y
                  bcs   :no
                  sec
                  rts
:no               clc
                  rts

*-------------------------------------------------------------
DrawItems         lda   #0
                  sta   CurSlot
:item             ldx   CurSlot
                  lda   ChgFlags,x
                  beq   :next
                  jsr   ClearSlotRect
                  lda   #0
                  sta   DrawMode
                  jsr   DrawItem
                  ldx   CurSlot
                  lda   NeedDamage,x
                  beq   :next
                  lda   #1                      ; and again over what was undone
                  sta   DrawMode
                  jsr   DrawItem
                  lda   #0
                  sta   DrawMode
:next             inc   CurSlot
                  lda   CurSlot
                  cmp   #NSLOT
                  bne   :item
                  rts

* draw (or, with MeasureOnly, just measure) the item in CurSlot
DrawItem          lda   CurSlot
                  asl
                  asl
                  tax
                  lda   NewSig,x
                  sta   ItemSpr
                  lda   CurSlot
                  cmp   #BALLSLOT
                  bne   :obj
                  jmp   DrawBall
:obj              lda   NewSig+1,x
                  sta   RX
                  lda   NewSig+2,x
                  sta   RLine
                  lda   NewSig+3,x
                  jsr   ObjColorClass
                  tay
                  lda   ItemSpr
                  jmp   DrawSprite

*-------------------------------------------------------------
* What should be on screen this frame, per item.
BuildNewSig       lda   #0
                  sta   RCnt                    ; slot being filled
                  ldx   #0                      ; object number
:obj              stx   T3
                  lda   Store1,x                ; where its dynamic data lives
                  tax
                  lda   $00,x                   ; the room it is in
                  cmp   BallRoom
                  bne   :skip
                  lda   RCnt
                  cmp   #BALLSLOT               ; no slots left
                  bcs   :skip
                  ldx   T3
                  jsr   GetObjPrintInfo         ; A = sprite, T0/T1/T2 = x/y/colour
                  sta   T4
                  lda   RCnt
                  asl
                  asl
                  tax
                  lda   T4
                  sta   NewSig,x
                  lda   T0
                  sta   NewSig+1,x
                  lda   T1
                  sta   NewSig+2,x
                  lda   T2
                  sta   NewSig+3,x
                  inc   RCnt
:skip             lda   T3
                  clc
                  adc   #9
                  cmp   #162
                  bcs   :spare
                  tax
                  jmp   :obj
:spare            ldx   RCnt                    ; nothing in the slots left over
:blank            cpx   #BALLSLOT
                  beq   :ball
                  txa
                  asl
                  asl
                  tay
                  lda   #0
                  sta   NewSig,y
                  sta   NewSig+1,y
                  sta   NewSig+2,y
                  sta   NewSig+3,y
                  inx
                  jmp   :blank
:ball             lda   #$fe                    ; the ball has no sprite id
                  sta   NewSig+BALLSIG
                  lda   BallX
                  sta   NewSig+BALLSIG+1
                  lda   BallY
                  sta   NewSig+BALLSIG+2
                  lda   WallClass               ; the ball takes the wall colour
                  sta   NewSig+BALLSIG+3
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
                  cmp   #NSLOT
                  bne   :item
                  rts

* Keep what this page had for CurSlot, then mark it as nothing drawn.
ClearSlotRect     jsr   SlotRectIdx
                  lda   CurSlot
                  asl
                  asl
                  tay
                  lda   SlotRect,x
                  sta   OldRect,y
                  lda   SlotRect+1,x
                  sta   OldRect+1,y
                  lda   SlotRect+2,x
                  sta   OldRect+2,y
                  lda   SlotRect+3,x
                  sta   OldRect+3,y
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

* remember the rectangle just drawn for CurSlot.  In the measure pass it
* goes to NewRect instead, and the real pass keeps the previous one in
* OldRect so the draw can tell how far a solid item has shifted.
SetSlotRect       lda   RX
                  clc
                  adc   RW
                  cmp   #41                     ; clip the rect to the line
                  bcc   :fits
                  lda   #40
                  sec
                  sbc   RX
                  jmp   :w
:fits             lda   RW
:w                sta   T0
                  lda   CurSlot
                  asl
                  asl
                  tax
                  lda   MeasureOnly
                  beq   :real
                  lda   RX
                  sta   NewRect,x
                  lda   T0
                  sta   NewRect+1,x
                  lda   RLine
                  sta   NewRect+2,x
                  lda   RRows
                  sta   NewRect+3,x
                  rts
:real             jsr   SlotRectIdx
                  lda   RX
                  sta   SlotRect,x
                  lda   T0
                  sta   SlotRect+1,x
                  lda   RLine
                  sta   SlotRect+2,x
                  lda   RRows
                  sta   SlotRect+3,x
                  rts

* restore what the changed items covered on this page.  After a full
* room redraw there is nothing to undo.
EraseChanged      ldx   #NSLOT*4-4              ; nothing undone yet
                  lda   #0
:clr              sta   ErasedRect+3,x
                  dex
                  dex
                  dex
                  dex
                  bpl   :clr
                  lda   FullRedraw
                  bne   :done
                  lda   #0
                  sta   CurSlot
:item             ldx   CurSlot
                  lda   ChgFlags,x
                  beq   :next
                  lda   DamagedOnly,x           ; nothing of its own was undone
                  bne   :next
                  jsr   EraseOld
:next             inc   CurSlot
                  lda   CurSlot
                  cmp   #NSLOT
                  bne   :item
:done             rts

* Erase what CurSlot last covered.  If it is a solid item that has only
* shifted along one axis, the overlap already holds the right pixels and
* only the strip it has left behind needs clearing.
EraseOld          jsr   SlotRectIdx
                  lda   SlotRect+3,x
                  bne   :any
                  rts                           ; nothing was drawn there
:any              sta   RRows
                  lda   SlotRect,x
                  sta   RX
                  lda   SlotRect+1,x
                  sta   RW
                  lda   SlotRect+2,x
                  sta   RLine
                  lda   CurSlot
                  asl
                  asl
                  tay
                  ldy   CurSlot                 ; edge-only erase is for solid
                  lda   SolidSlot,y             ; items that have only shifted
                  bne   :meas
                  jmp   :whole
:meas             lda   CurSlot
                  asl
                  asl
                  tay
                  lda   NewRect+3,y
                  bne   :meas2
:whole            jsr   MergeDamage
                  jmp   EraseRect
:meas2            lda   NewRect+1,y
                  cmp   RW
                  beq   :samew
                  jmp   :whole
:samew            lda   NewRect,y
                  cmp   RX
                  beq   :vert
* same width, different column: clear the columns it no longer covers
                  lda   NewRect+2,y
                  cmp   RLine
                  beq   :h1
                  jmp   :whole
:h1               lda   NewRect+3,y
                  cmp   RRows
                  beq   :h2
                  jmp   :whole
:h2               lda   NewRect,y
                  sta   T0                      ; new left
                  clc
                  adc   NewRect+1,y
                  sta   T1                      ; new right
                  lda   RX
                  sta   T2                      ; old left
                  clc
                  adc   RW
                  sta   T4                      ; old right
                  jsr   Overlap
                  bcs   :h3
                  jmp   :whole                  ; disjoint: clear the lot
:h3               lda   T0                      ; strip on the left
                  sec
                  sbc   T2
                  beq   :eright
                  bcc   :eright
                  sta   RW
                  lda   T2
                  sta   RX
                  jsr   EraseKeep
:eright           lda   T4                      ; strip on the right
                  sec
                  sbc   T1
                  beq   :edone
                  bcc   :edone
                  sta   RW
                  lda   T1
                  sta   RX
                  jsr   EraseKeep
:edone            rts
* same column and width: clear the lines it no longer covers
:vert             lda   NewRect+2,y
                  sta   T0                      ; new top
                  clc
                  adc   NewRect+3,y
                  sta   T1                      ; new bottom
                  lda   RLine
                  sta   T2                      ; old top
                  clc
                  adc   RRows
                  sta   T4                      ; old bottom
                  jsr   Overlap
                  bcs   :v1
                  jmp   :whole
:v1               lda   T0                      ; strip above
                  sec
                  sbc   T2
                  beq   :ebelow
                  bcc   :ebelow
                  sta   RRows
                  lda   T2
                  sta   RLine
                  jsr   EraseKeep
:ebelow           lda   T4                      ; strip below
                  sec
                  sbc   T1
                  beq   :vdone
                  bcc   :vdone
                  sta   RRows
                  lda   T1
                  sta   RLine
                  jsr   EraseKeep
:vdone            rts

* EraseRect eats RLine/RRows, so keep them for the second strip
EraseKeep         jsr   MergeDamage
                  lda   RLine
                  pha
                  lda   RRows
                  pha
                  jsr   EraseRect
                  pla
                  sta   RRows
                  pla
                  sta   RLine
                  rts

* ranges [T0,T1) and [T2,T4) -> carry set if they overlap
Overlap           lda   T0
                  cmp   T4
                  bcs   :no
                  lda   T2
                  cmp   T1
                  bcs   :no
                  sec
                  rts
:no               clc
                  rts

*-------------------------------------------------------------
* Everywhere a solid sprite lands in a room whose playfield is in front of
* it, what shows is the room's own lit pattern - the colour mask where the
* room is open, nothing where a wall is - and that depends only on the
* position on screen, not on the sprite.  Work it out once per room and
* the blit becomes a copy.
BuildLit          lda   RClass
                  cmp   LitClass
                  beq   :done
                  sta   LitClass
                  tay
                  lda   MaskTabL,y
                  sta   :m+1
                  lda   MaskTabH,y
                  sta   :m+2
                  lda   #<RoomOpen
                  sta   RTmpl
                  lda   #>RoomOpen
                  sta   RTmpl+1
                  lda   #<RoomLit
                  sta   RShp
                  lda   #>RoomLit
                  sta   RShp+1
                  lda   #0
                  sta   RCnt                    ; row
:row              ldy   #0
:col              lda   (RTmpl),y
                  beq   :dark
                  tya
                  tax
:m                lda   MaskTab,x
                  sta   (RShp),y
                  jmp   :next
:dark             lda   #0
                  sta   (RShp),y
:next             iny
                  cpy   #40
                  bne   :col
                  lda   RTmpl
                  clc
                  adc   #40
                  sta   RTmpl
                  bcc   :n1
                  inc   RTmpl+1
:n1               lda   RShp
                  clc
                  adc   #40
                  sta   RShp
                  bcc   :n2
                  inc   RShp+1
:n2               inc   RCnt
                  lda   RCnt
                  cmp   #7
                  bne   :row
:done             rts

* Copy one lit row into scan lines RLine and RLine+1 at RX..RXEnd
BlitRow4          ldy   RLine
                  lda   TmplLo,y
                  clc
                  adc   #<RoomLit-RoomBytes
                  sta   BR4lit+1
                  lda   TmplHi,y
                  adc   #>RoomLit-RoomBytes
                  sta   BR4lit+2
                  lda   HgrLo,y
                  sta   BR4a+1
                  sta   BR4b+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR4a+2
                  clc
                  adc   #4                      ; line+1 is one $400 lower
                  sta   BR4b+2
                  ldx   RX
BR4byte           
BR4lit            lda   RoomLit,x
                  beq   BR4next
BR4a              sta   $2000,x
BR4b              sta   $2000,x
BR4next           inx
                  cpx   RXEnd
                  bne   BR4byte
                  rts

*-------------------------------------------------------------
* Narrow the blit to the part of the item that was undone this frame.
* Carry set means nothing of it needs repainting.
ClipToDamage      jsr   BuildDamageFor
                  lda   DamageRect+3
                  bne   :any
                  sec
                  rts
:any              lda   RX                      ; columns
                  cmp   DamageRect
                  bcs   :x1
                  lda   DamageRect
:x1               sta   RX
                  lda   DamageRect
                  clc
                  adc   DamageRect+1
                  cmp   RXEnd
                  bcs   :x2
                  sta   RXEnd
:x2               lda   RX
                  cmp   RXEnd
                  bcs   :none
                  lda   RLine                   ; lines
                  sta   T0
                  clc
                  adc   RRows
                  sta   T1
                  lda   DamageRect+2
                  cmp   T0
                  bcs   :t1
                  lda   T0
:t1               sta   T2
                  lda   DamageRect+2
                  clc
                  adc   DamageRect+3
                  cmp   T1
                  bcc   :t2
                  lda   T1
:t2               sta   T4
                  lda   T2
                  cmp   T4
                  bcs   :none
                  lda   T2                      ; whole sprite rows only
                  sec
                  sbc   T0
                  and   #$fe
                  sta   T5
                  clc
                  adc   T0
                  sta   RLine
                  lda   T4
                  sec
                  sbc   RLine
                  beq   :none
                  clc
                  adc   #1
                  and   #$fe
                  sta   RRows
                  lda   T1
                  sec
                  sbc   RLine
                  cmp   RRows
                  bcs   :rok
                  sta   RRows
:rok              lda   RRows
                  beq   :none
                  lda   T5
                  lsr
                  beq   :ok
                  tax
:adv              lda   RQ
                  clc
                  adc   RBpr
                  sta   RQ
                  bcc   :nc
                  inc   RQ+1
:nc               dex
                  bne   :adv
:ok               clc
                  rts
:none             sec
                  rts

*-------------------------------------------------------------
* A solid item that has only shifted along one axis already has the
* right pixels in the overlap; narrow the blit to the new edge.
* Carry set on return means there is nothing left to draw.
RestrictDraw      lda   CurSlot
                  asl
                  asl
                  tay
                  lda   OldRect+3,y
                  bne   :any
                  clc                           ; nothing was there: draw it all
                  rts
:any              lda   OldRect+1,y
                  cmp   RW
                  beq   :w2
                  jmp   :all
:w2               lda   OldRect,y
                  cmp   RX
                  beq   :vert
                  lda   OldRect+2,y
                  cmp   RLine
                  beq   :h2
                  jmp   :all
:h2               lda   OldRect+3,y
                  cmp   RRows
                  beq   :h3
                  jmp   :all
:h3
* same lines, shifted sideways: draw only the columns it has gained
                  lda   OldRect,y
                  sta   T0
                  clc
                  adc   OldRect+1,y
                  sta   T1
                  lda   RX
                  sta   T2
                  clc
                  adc   RW
                  sta   T4
                  jsr   Overlap
                  bcs   :h4
                  jmp   :all
:h4               lda   T0
                  cmp   T2
                  bcc   :right
                  lda   T0                      ; gained columns on the left
                  sta   RXEnd
                  jmp   :check
:right            lda   T1                      ; gained columns on the right
                  sta   RX
                  jmp   :check
* same column: draw only the lines it has gained
:vert             lda   OldRect+3,y
                  cmp   RRows
                  beq   :v1
                  jmp   :all
:v1
                  lda   OldRect+2,y
                  sta   T0
                  clc
                  adc   OldRect+3,y
                  sta   T1
                  lda   RLine
                  sta   T2
                  clc
                  adc   RRows
                  sta   T4
                  jsr   Overlap
                  bcs   :v2
                  jmp   :all
:v2               lda   T0
                  cmp   T2
                  bcc   :below
                  lda   T0                      ; gained lines above
                  sec
                  sbc   T2
                  sta   RRows
                  jmp   :check
:below            lda   T4                      ; gained lines below: skip ahead
                  sec
                  sbc   T1
                  beq   :none
                  sta   T5
                  lda   T1
                  sta   RLine
                  lda   T5
                  sta   RRows
                  lda   T1                      ; advance past the rows we skip
                  sec
                  sbc   T2
                  lsr                           ; lines -> sprite rows
                  tax
                  beq   :ok
:adv              lda   RQ
                  clc
                  adc   RBpr
                  sta   RQ
                  bcc   :nc
                  inc   RQ+1
:nc               dex
                  bne   :adv
:ok               jmp   :check
:none             sec
                  rts
:all              clc
                  rts
* an empty strip means the item has not really moved
:check            lda   RRows
                  beq   :none
                  lda   RX
                  cmp   RXEnd
                  bcs   :none
                  clc
                  rts

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
* the page is wiped, so nothing is left of the items that were on it
                  ldx   DrawPage
                  beq   :s0
                  ldx   #NSLOT*4
:s0               ldy   #NSLOT
                  lda   #0
:s1               sta   SlotRect+3,x
                  inx
                  inx
                  inx
                  inx
                  dey
                  bne   :s1
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
* the 40-byte width is a compile-time constant, so this is unrolled flat -
* no dey/bpl per byte - which is worth it here because DrawRoom only runs
* on a room transition, not every frame, so the code size is free money
                  ldy   #0
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  iny
                  lda   (RTmpl),y
                  sta   (RP),y
                  inc   RLine
                  lda   RLine
                  cmp   #192
                  beq   :alldone               ; unrolled body is >127 bytes,
                  jmp   :line                  ;  out of bne's branch range
:alldone          rts

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
BuildTemplate     lda   #$ff                    ; the lit rows go with the room
                  sta   LitClass
                  ldx   WallClass
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
                  sta   :e3+1                   ; the next line is the same
                  lda   HgrHi,y                 ; byte, one $400 block lower
                  clc
                  adc   RPageHi
                  sta   :e2+2
                  dec   RRows
                  bne   :two                    ; odd line left over?
                  sta   :e3+2                   ; store the same line twice
                  jmp   :go
:two              clc
                  adc   #4
                  sta   :e3+2
                  dec   RRows
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
                  sty   RClass
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
                  cmp   #40                     ; off the right of the screen?
                  bcc   :onscr
                  rts
:onscr            sta   RX                      ; byte x
                  sta   RXOrg
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
                  bcc   :ok2                    ; >= 256: off bottom
                  jmp   :below
:ok2              sta   RLine
                  cmp   #192
                  bcc   :draw2
                  jmp   :below
:draw2            jmp   :draw
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
                  bne   :sk2
                  jmp   :below
:sk2              dec   T4
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
                  lda   MeasureOnly
                  beq   :lit
                  rts
:lit              lda   RPrio                   ; solid sprites read the lit rows
                  beq   :solid
                  ldx   CurSlot
                  lda   SolidSlot,x
                  beq   :solid
                  jsr   BuildLit
:solid            ldx   CurSlot
                  lda   DrawMode
                  bne   :dmg
                  lda   DamagedOnly,x
                  beq   :notdmg
:dmg              jsr   ClipToDamage            ; repaint just what was undone
                  bcs   :below
                  jmp   :row
:notdmg           lda   SolidSlot,x
                  beq   :row
                  jsr   RestrictDraw            ; only the edges have changed
                  bcs   :below
:row              lda   RPrio
                  bne   :prio
                  jsr   BlitRow2                ; both lines in one pass
                  jmp   :adv
:prio             ldx   CurSlot
                  lda   SolidSlot,x
                  beq   :prio2
                  jsr   BlitRow4                ; solid: copy the lit rows
                  jmp   :adv
:prio2            jsr   BlitRow3                ; ... with walls in front
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
BlitRow2          lda   RQ
                  sec
                  sbc   RXOrg
                  sta   BR2src+1
                  lda   RQ+1
                  sbc   #0
                  sta   BR2src+2
                  ldy   RLine
                  lda   HgrLo,y
                  sta   BR2a1+1
                  sta   BR2a2+1
                  sta   BR2b1+1
                  sta   BR2b2+1
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR2a1+2
                  sta   BR2a2+2
                  clc
                  adc   #4                      ; line+1 is one $400 lower
                  sta   BR2b1+2
                  sta   BR2b2+2
                  ldx   RX
BR2byte           
BR2src            lda   HGfxNull,x              ; base patched to RQ-RX
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
                  cpx   RXEnd
                  bne   BR2byte
                  rts

* Same, for rooms where the playfield is in front of the sprites
* (CTRLPF bit 2).  That is how the invisible surround reveals the
* catacomb mazes: the box shows wherever the room is open.
* Everything is indexed by the screen byte column, so the sprite row
* is reached through a base of RQ-RX; and because a pixel only lands
* where the room is open, the byte underneath is background and can be
* stored rather than OR-ed.
BlitRow3          lda   RQ
                  sec
                  sbc   RXOrg
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
                  sta   BR3b+1                  ; line+1 is one $400 lower
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   BR3a+2
                  clc
                  adc   #4
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
* The ball: 4 clocks x 4 counts, which is exactly one 7-pixel byte
* by 8 lines - offset within the byte by the clock phase.  The 2600 drew
* it with COLUPF, so it takes the room's wall colour - which is
* what makes the man invisible in the catacombs.
BallPat           db    $7f,$00, $7e,$01, $78,$07, $60,$1f
BallB1            db    0
BallB2            db    0
BallTwo           db    0                       ; the block spills into a second byte
* The 2600 had no ball colour register - the ball took COLUPF.  In the
* catacombs that is the background colour, so the man is invisible against
* the room but shows as a hole punched in the lit surround.  So when the
* wall colour is our "invisible" class the ball is masked out of whatever
* is under it instead of being OR-ed in.
DrawBall          ldy   NewSig+31
                  bne   :colour
                  lda   #$7f                    ; a hole: all seven pixels
                  sta   RMaskE
                  sta   RMaskO
                  lda   #$ff
                  sta   BallCut
                  bne   :geom
:colour           lda   #0
                  sta   BallCut
                  lda   ClassMaskE,y
                  ora   ClassHi,y
                  sta   RMaskE
                  lda   ClassMaskO,y
                  ora   ClassHi,y
                  sta   RMaskO
:geom             lda   NewSig+30
                  bne   :on
                  rts
:on               lda   #105
                  sec
                  sbc   NewSig+30
                  bcs   :below
                  rts
:below            asl
                  bcc   :onscr
                  rts
:onscr            cmp   #192
                  bcc   :ok
                  rts
:ok               sta   RLine
                  lda   #8
                  sta   RRows
                  lda   NewSig+29
                  lsr
                  lsr
                  cmp   #40                     ; off the right of the screen?
                  bcc   :xok
                  rts
:xok              sta   RX
                  lda   #2
                  sta   RW
                  jsr   SetSlotRect             ; clobbers X, so index it after
                  lda   MeasureOnly
                  beq   :real
                  rts
* the two screen bytes are the same on every line: build them once
:real             lda   RX
                  and   #1
                  bne   :odd
                  lda   RMaskE
                  ldy   RMaskO
                  jmp   :mk
:odd              lda   RMaskO
                  ldy   RMaskE
:mk               sta   RDx                     ; mask for byte RX
                  sty   RCnt                    ; mask for byte RX+1
                  lda   NewSig+29
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
                  sta   BallTwo
                  lda   BallCut
                  beq   :ora
                  lda   BallB1                  ; clear those pixels, keep the
                  eor   #$7f                    ; byte's colour hi bit
                  ora   #$80
                  sta   BallB1
                  lda   BallB2
                  eor   #$7f
                  ora   #$80
                  sta   BallB2
                  lda   #$2d                    ; AND abs
                  bne   :op
:ora              lda   #$0d                    ; ORA abs
:op               sta   :o1
                  sta   :o2
                  sta   :o3
                  sta   :o4
* two lines at a time: the next one is the same byte, $400 lower
:line             ldy   RLine
                  cpy   #192
                  bcs   :skip
                  lda   HgrLo,y
                  sta   RP
                  sta   RQ
                  lda   HgrHi,y
                  clc
                  adc   RPageHi
                  sta   RP+1
                  clc
                  adc   #4
                  sta   RQ+1
                  ldy   RX
                  lda   (RP),y
:o1               ora   BallB1
                  sta   (RP),y
                  lda   (RQ),y
:o2               ora   BallB1
                  sta   (RQ),y
                  lda   BallTwo                 ; a 7-pixel block only spills
                  beq   :n                      ; into the next byte off-phase
                  iny
                  cpy   #40
                  bcs   :n
                  lda   (RP),y
:o3               ora   BallB2
                  sta   (RP),y
                  lda   (RQ),y
:o4               ora   BallB2
                  sta   (RQ),y
:n                inc   RLine
                  inc   RLine
                  dec   RRows
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
