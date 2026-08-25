*-------------------------------------------------------------
* SHR renderer.  2600 geometry falls out exactly on 320x200:
*   1 colour clock = 1 byte = 2 pixels  (160 clocks = 160 bytes)
*   1 game unit (count) = 2 scan lines
*   count 104 = field line 0 = screen line 4 (4 border lines top
*   and bottom make up the 200)
* Only four palette entries are used, rewritten every frame from
* the real 2600 colours, so flash/attract colours come for free:
*   0 background, 1 playfield + ball, 2 object 1, 3 object 2
* Everything below is entered and left in 8-bit mode (mx %11).
*-------------------------------------------------------------
* renderer direct page scratch, above the core's $10-$2a
GP                equ   $30                     ; template row pointer
GQ                equ   $32                     ; sprite row pointer
GDst              equ   $34                     ; screen offset (word)
GLine             equ   $36                     ; screen line (word)
GRows             equ   $38                     ; line count (word)
GW                equ   $3a                     ; width in bytes (word)
GXB               equ   $3c                     ; left byte / clock (word)
GCol              equ   $3e                     ; colour byte
GCnt              equ   $3f
GTmp              equ   $40                     ; word
GTmp2             equ   $42                     ; word

SHRBUF            equ   $E12000
SHRPAL            equ   $E19E00

                  mx    %11
ShrTmpl           ds    8*160                   ; 7 playfield rows + a blank one
DrawnSig          db    $ff,$ff,$ff             ; gfx ptr lo/hi, room ctrl
DirtyCnt          db    0
DirtyList         ds    4*4                     ; xb, w, top, h

*-------------------------------------------------------------
DrawFrame         jsr   LatchCollisions
                  jsr   SetColors
                  lda   RoomGfxPtr
                  cmp   DrawnSig
                  bne   :full
                  lda   RoomGfxPtr+1
                  cmp   DrawnSig+1
                  bne   :full
                  lda   RoomCtrl
                  cmp   DrawnSig+2
                  bne   :full
                  jsr   UndrawDirty
                  bra   :objects
:full             jsr   DrawRoom
:objects          lda   #0
                  sta   DirtyCnt
                  sta   GXB+1
                  sta   GW+1
                  sta   GLine+1
                  sta   GRows+1
                  lda   Obj1X
                  sta   GXB
                  lda   Obj1Y
                  sta   GLine
                  lda   #$22
                  sta   GCol
                  lda   Obj1SprId
                  jsr   DrawSprite
                  lda   Obj2X
                  sta   GXB
                  lda   Obj2Y
                  sta   GLine
                  lda   #$33
                  sta   GCol
                  lda   Obj2SprId
                  jsr   DrawSprite
                  jmp   DrawBall

*-------------------------------------------------------------
* Palette entries 0-3 straight from the 2600 colour bytes.
                  mx    %11
SetColors         lda   #$08                    ; the 2600's light grey background
                  jsr   ChangeColor
                  ldx   #0
                  jsr   SetPalEntry
                  lda   PFOverride
                  cmp   #$ff
                  bne   :ov
                  lda   RoomColor
:ov               ldx   #2
                  jsr   SetPalEntry
                  lda   Obj1Color
                  ldx   #4
                  jsr   SetPalEntry
                  lda   Obj2Color
                  ldx   #6
                  jsr   SetPalEntry
                  rts

* A = 2600 colour byte, X = palette entry * 2
                  mx    %11
SetPalEntry       and   #$fe
                  sta   GTmp
                  stz   GTmp+1
                  stx   GTmp2
                  stz   GTmp2+1
                  rep   #$30
                  mx    %00
                  ldx   GTmp
                  lda   Pal2600,x
                  ldx   GTmp2
                  stal  SHRPAL,x
                  sep   #$30
                  mx    %11
                  rts

*-------------------------------------------------------------
* Full redraw: rebuild the row template, then blast 200 lines.
                  mx    %11
DrawRoom          lda   RoomGfxPtr
                  sta   DrawnSig
                  lda   RoomGfxPtr+1
                  sta   DrawnSig+1
                  lda   RoomCtrl
                  sta   DrawnSig+2
                  lda   #0
                  sta   DirtyCnt
                  jsr   BuildTemplate
                  rep   #$30
                  mx    %00
                  ldy   #0                      ; line * 2
:line             lda   LineRowOfs,y
                  sta   GP
                  ldx   LineOfs,y
                  phy
                  ldy   #0
:copy             lda   (GP),y
                  stal  SHRBUF,x
                  inx
                  inx
                  iny
                  iny
                  cpy   #160
                  bne   :copy
                  ply
                  iny
                  iny
                  cpy   #400
                  bne   :line
                  sep   #$30
                  mx    %11
                  rts

*-------------------------------------------------------------
* ShrTmpl[row][clock] = $11 where the playfield is set, else $00
                  mx    %11
BuildTemplate     lda   #0
                  sta   GCnt                    ; row
:row              jsr   TmplRowPtr              ; GP = &ShrTmpl[row][0]
                  ldx   #0                      ; column 0-39
:col              stx   GXB
                  lda   GCnt
                  jsr   PFBitTest               ; clobbers X
                  beq   :empty
                  lda   #$11
                  bne   :store
:empty            lda   #$00
:store            ldx   GXB
                  ldy   GXB
                  sta   GCol
                  tya
                  asl
                  asl                           ; clock = column * 4
                  tay
                  lda   GCol
                  sta   (GP),y
                  iny
                  sta   (GP),y
                  iny
                  sta   (GP),y
                  iny
                  sta   (GP),y
                  inx
                  cpx   #40
                  bne   :col
* thin walls are one clock wide and run the full height
                  lda   RoomCtrl
                  bpl   :nol
                  ldy   #13
                  lda   #$11
                  sta   (GP),y
:nol              lda   RoomCtrl
                  and   #$40
                  beq   :nor
                  ldy   #150
                  lda   #$11
                  sta   (GP),y
:nor              inc   GCnt
                  lda   GCnt
                  cmp   #7
                  bne   :row
* row 7 is the border strip: all background
                  jsr   TmplRowPtr
                  ldy   #0
                  lda   #0
:blank            sta   (GP),y
                  iny
                  cpy   #160
                  bne   :blank
                  rts

* GP = ShrTmpl + GCnt*160
                  mx    %11
TmplRowPtr        lda   GCnt
                  sta   GTmp
                  stz   GTmp+1
                  rep   #$30
                  mx    %00
                  lda   GTmp
                  asl
                  asl
                  asl
                  asl
                  asl                           ; row*32
                  sta   GTmp2
                  lda   GTmp
                  asl
                  asl
                  asl                           ; row*8
                  clc
                  adc   GTmp2                   ; row*40
                  asl
                  asl                           ; row*160
                  clc
                  adc   #ShrTmpl
                  sta   GP
                  sep   #$30
                  mx    %11
                  rts

*-------------------------------------------------------------
* Restore the dirty rects from the template
                  mx    %11
UndrawDirty       lda   DirtyCnt
                  beq   :done
                  sta   GCnt
                  ldx   #0
:rect             stx   GTmp2
                  lda   DirtyList,x
                  sta   GXB
                  lda   DirtyList+1,x
                  sta   GW
                  lda   DirtyList+2,x
                  sta   GLine
                  lda   DirtyList+3,x
                  sta   GRows
                  stz   GXB+1
                  stz   GW+1
                  stz   GLine+1
:line             jsr   RowPtrs                 ; GP = template src, GDst = screen
                  rep   #$30
                  mx    %00
                  ldx   GDst
                  ldy   #0
                  sep   #$20
                  mx    %10
:byte             lda   (GP),y
                  stal  SHRBUF,x
                  inx
                  iny
                  cpy   GW
                  bne   :byte
                  sep   #$30
                  mx    %11
                  inc   GLine
                  dec   GRows
                  bne   :line
                  ldx   GTmp2
                  inx
                  inx
                  inx
                  inx
                  dec   GCnt
                  bne   :rect
:done             rts

* line GLine, left byte GXB -> GP = template source, GDst = screen
                  mx    %11
RowPtrs           rep   #$30
                  mx    %00
                  lda   GLine
                  asl
                  tax
                  lda   LineRowOfs,x
                  clc
                  adc   GXB
                  sta   GP
                  lda   LineOfs,x
                  clc
                  adc   GXB
                  sta   GDst
                  sep   #$30
                  mx    %11
                  rts

*-------------------------------------------------------------
* record a dirty rect: GXB, GW, GLine (top), GRows (lines)
                  mx    %11
AddDirty          ldx   DirtyCnt
                  cpx   #4
                  bcs   :done
                  inc   DirtyCnt
                  txa
                  asl
                  asl
                  tax
                  lda   GXB
                  sta   DirtyList,x
                  lda   GW
                  sta   DirtyList+1,x
                  lda   GLine
                  sta   DirtyList+2,x
                  lda   GRows
                  sta   DirtyList+3,x
:done             rts

*-------------------------------------------------------------
* A = sprite id, GXB = x clock, GLine = Y count, GCol = colour
                  mx    %11
DrawSprite        tax
                  lda   SprHeight,x
                  beq   :skip
                  sta   GRows                   ; sprite rows
                  lda   SprShrBpr,x
                  sta   GW
                  lda   SprShrL,x
                  sta   GQ
                  lda   SprShrH,x
                  sta   GQ+1
                  lda   GXB
                  cmp   #160
                  bcs   :skip
                  clc
                  adc   GW
                  bcs   :clip
                  cmp   #161
                  bcc   :wok
:clip             lda   #160
                  sec
                  sbc   GXB
                  sta   GW
* first drawn count is Y-1, so the top field line is (105-Y)*2
:wok              lda   #105
                  sec
                  sbc   GLine
                  bcc   :above
                  cmp   #96
                  bcs   :skip                   ; wholly below the field
                  asl
                  clc
                  adc   #4
                  sta   GLine
                  bra   :draw
:above            lda   GLine                   ; Y > 105: skip rows off the top
                  sec
                  sbc   #105
                  sta   GTmp
:sk               lda   GQ
                  clc
                  adc   GW
                  sta   GQ
                  bcc   :nc
                  inc   GQ+1
:nc               dec   GRows
                  beq   :skip
                  dec   GTmp
                  bne   :sk
                  lda   #4
                  sta   GLine
:draw             lda   GRows
                  asl                           ; two scan lines per sprite row
                  bcs   :cap
                  cmp   #192
                  bcc   :rok
:cap              lda   #192
:rok              sta   GRows
                  lda   #196                    ; clip at the bottom border
                  sec
                  sbc   GLine
                  cmp   GRows
                  bcs   :rok2
                  sta   GRows
:rok2             lda   GRows
                  beq   :skip
                  sta   GCnt
                  jsr   AddDirty
:row              jsr   BlitRow
                  inc   GLine
                  dec   GCnt
                  beq   :skip
                  jsr   BlitRow
                  inc   GLine
                  lda   GQ
                  clc
                  adc   GW
                  sta   GQ
                  bcc   :nc2
                  inc   GQ+1
:nc2              dec   GCnt
                  bne   :row
:skip             rts

* one sprite row (GW bytes at GQ) into line GLine starting at GXB
                  mx    %11
BlitRow           rep   #$30
                  mx    %00
                  lda   GLine
                  asl
                  tax
                  lda   LineOfs,x
                  clc
                  adc   GXB
                  tax
                  ldy   #0
                  sep   #$20
                  mx    %10
:byte             lda   (GQ),y
                  beq   :next
                  lda   GCol
                  stal  SHRBUF,x
:next             inx
                  iny
                  cpy   GW
                  bne   :byte
                  sep   #$30
                  mx    %11
                  rts

*-------------------------------------------------------------
* The ball: 4 clocks x 4 counts, drawn in the playfield colour
                  mx    %11
DrawBall          lda   BallY
                  beq   :skip
                  lda   #105
                  sec
                  sbc   BallY
                  bcc   :skip
                  cmp   #96
                  bcs   :skip
                  asl
                  clc
                  adc   #4
                  sta   GLine
                  lda   BallX
                  cmp   #157
                  bcs   :skip
                  sta   GXB
                  stz   GXB+1
                  stz   GLine+1
                  lda   #4
                  sta   GW
                  stz   GW+1
                  lda   #8
                  sta   GRows
                  jsr   AddDirty
                  lda   #$11
                  sta   GCol
                  lda   #8
                  sta   GCnt
:line             rep   #$30
                  mx    %00
                  lda   GLine
                  asl
                  tax
                  lda   LineOfs,x
                  clc
                  adc   GXB
                  tax
                  sep   #$20
                  mx    %10
                  lda   GCol
                  stal  SHRBUF,x
                  inx
                  stal  SHRBUF,x
                  inx
                  stal  SHRBUF,x
                  inx
                  stal  SHRBUF,x
                  sep   #$30
                  mx    %11
                  inc   GLine
                  dec   GCnt
                  bne   :line
:skip             rts
