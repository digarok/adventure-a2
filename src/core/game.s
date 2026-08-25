*-------------------------------------------------------------
* Adventure game logic, ported from the 2600 ROM (Warren
* Robinett, 1979).  Labels and structure follow the
* 6502disassembly.com listing; the addresses in comments
* refer to it.  Differences from the original:
*   - TIA collision registers are computed in software
*     (LatchCollisions, collide.s) whenever the 2600 would
*     have displayed a frame
*   - object graphics are referenced by sprite id, not address
*   - every object's dynamic data lives in the direct page,
*     so ($ptr),y reads of it became $00,x reads
*   - input comes from ReadInput (platform), which fills the
*     emulated SWCHA / SWCHB / INPT4 bytes
*-------------------------------------------------------------

* ---- StartGame (f2ef) ----------------------------------------
StartGame         lda   #0
                  ldx   #$7f
:clear            sta   $80,x                   ; clear $80-$ff
                  dex
                  bpl   :clear
                  ldx   #ZPConstsLen-1
:consts           lda   ZPConsts,x
                  sta   PortInfo1,x
                  dex
                  bpl   :consts
                  lda   #$ff
                  sta   PFOverride
                  lda   #$ff
                  sta   SWCHA
                  sta   SWCHB
                  sta   INPT4
                  sta   PrevSwitches
                  lda   #%00001011              ; b7/b6 difficulty (1 = A/pro), b3 color, b1 select, b0 reset (active low)
                  sta   SWCHB
                  sta   PrevSwitches
                  jsr   SetupRoomObjects
* ---- MainGameLoop (f306) -------------------------------------
MainGameLoop      jsr   CheckGameStart
                  jsr   MakeSound
                  jsr   CheckInput
                  lda   QuitFlag
                  beq   :run
                  rts                           ; back to platform -> quit
:run              lda   GameInactive
                  bne   NonActiveLoop
                  lda   Chalice                 ; chalice room
                  cmp   #$12                    ; yellow castle?
                  bne   :loop2
                  lda   #$ff
                  sta   NoiseCount
                  sta   GameInactive
                  lda   #0
                  sta   NoiseType               ; game over noise / flash
:loop2            ldy   #0                      ; phase 0: all movement
                  jsr   BallMovement
                  jsr   MoveCarriedObject
                  jsr   WaitFrame
                  jsr   SetupRoomPrint
                  jsr   DrawFrame
                  jsr   PickupPutdown
                  ldy   #1                      ; phase 1: vertical only
                  jsr   BallMovement
                  jsr   Surround
                  jsr   WaitFrame
                  jsr   MoveBat
                  jsr   Portals
                  jsr   LatchCollisions          ; phase 1: latches only - the
                  jsr   MoveGreenDragon          ; picture is unchanged since phase 0
                  jsr   MoveYellowDragon
                  jsr   WaitFrame
                  ldy   #2                      ; phase 2: horizontal only
                  jsr   BallMovement
                  jsr   MoveRedDragon
                  jsr   Mag
                  jsr   DrawFrame
                  jmp   MainGameLoop

NonActiveLoop     jsr   WaitFrame
                  jsr   DrawFrame
                  jsr   SetupRoomPrint
                  jmp   MainGameLoop

* ---- CheckGameStart (f384) -----------------------------------
CheckGameStart    lda   SWCHB
                  eor   #$ff
                  and   PrevSwitches
                  and   #$01                    ; reset newly pressed?
                  beq   CheckReset
                  lda   GameInactive
                  cmp   #$ff
                  beq   SetupRoomObjects
                  lda   #$11                    ; yellow castle
                  sta   BallRoom
                  sta   PrevRoom
                  lda   #$50
                  sta   BallX
                  sta   PrevX
                  lda   #$20
                  sta   BallY
                  sta   PrevY
                  lda   #0
                  sta   RedDragon+4
                  sta   YelDragon+4
                  sta   GrnDragon+4
                  sta   NoiseCount
                  lda   #ObjNone
                  sta   Carried
CheckReset        lda   SWCHB
                  eor   #$ff
                  and   PrevSwitches
                  and   #$02                    ; select newly pressed?
                  beq   StoreSwitches
                  lda   BallRoom
                  cmp   #0                      ; in the number room?
                  bne   SetupRoomObjects
                  lda   Level
                  clc
                  adc   #2
                  cmp   #6
                  bcc   :store
                  lda   #0
:store            sta   Level
SetupRoomObjects  lda   #0
                  sta   BallRoom
                  sta   PrevRoom
                  sta   BallY
                  sta   PrevY
                  ldy   Level
                  lda   Loc_4,y
                  sta   Ptr
                  lda   Loc_5,y
                  sta   Ptr+1
                  ldy   #$30
:copy             lda   (Ptr),y
                  sta   $a1,y
                  dey
                  bpl   :copy
                  lda   Level
                  cmp   #4
                  bcc   SignalGameStart
                  jsr   RandomizeLevel3
                  jsr   WaitFrame
                  jsr   DrawFrame
SignalGameStart   lda   #0
                  sta   GameInactive
                  lda   #ObjNone
                  sta   Carried
StoreSwitches     lda   SWCHB
                  sta   PrevSwitches
                  rts

* ---- RandomizeLevel3 (f412) ----------------------------------
RandomizeLevel3   ldy   #30
:loop             lda   FrameLo
                  lsr
                  lsr
                  lsr
                  lsr
                  lsr
                  sec
                  adc   FrameLo
                  sta   FrameLo
                  and   #$1f
                  cmp   Loc_2,y
                  bcc   :loop
                  cmp   Loc_3,y
                  beq   :ok
                  bcs   :loop
:ok               ldx   Loc_1,y
                  sta   $00,x
                  dey
                  dey
                  dey
                  bpl   :loop
                  rts

* ---- SetupRoomPrint (f10f) -----------------------------------
* Gathers what the display kernel needs: room gfx pointer,
* the two objects to show and their positions/sprites/colors.
SetupRoomPrint    lda   #$ff
                  sta   PFOverride              ; COLUPF reloaded from room color
                  lda   BallRoom
                  jsr   RoomNumToAddress
                  ldy   #0
                  lda   (Ptr),y
                  sta   RoomGfxPtr
                  iny
                  lda   (Ptr),y
                  sta   RoomGfxPtr+1
                  ldy   #2
                  lda   (Ptr),y
                  jsr   ChangeColor
                  sta   RoomColor
                  ldy   #4
                  lda   (Ptr),y
                  sta   RoomCtrl                ; b7 left thin wall, b6 right, b2 PF priority
                  jsr   CacheObjects
                  lda   Obj1
                  cmp   #0                      ; surround must be player 1
                  beq   SwapPrintObjects
                  cmp   #$5a                    ; bridge too
                  bne   SetupObjectPrint
                  lda   Obj2
                  cmp   #0
                  beq   SetupObjectPrint
SwapPrintObjects  lda   Obj1
                  sta   Temp
                  lda   Obj2
                  sta   Obj1
                  lda   Temp
                  sta   Obj2
SetupObjectPrint  ldx   Obj1
                  jsr   GetObjPrintInfo
                  sta   Obj1SprId
                  lda   T0
                  sta   Obj1X
                  lda   T1
                  sta   Obj1Y
                  lda   T2
                  sta   Obj1Color
                  ldx   Obj2
                  jsr   GetObjPrintInfo
                  sta   Obj2SprId
                  lda   T0
                  sta   Obj2X
                  lda   T1
                  sta   Obj2Y
                  lda   T2
                  sta   Obj2Color
                  rts

* X = object number.  Returns A = sprite id, T0/T1 = x/y, T2 = color
GetObjPrintInfo   stx   T3
                  lda   Store1,x                ; dynamic data (ZP)
                  tax
                  lda   $01,x
                  sta   T0
                  lda   $02,x
                  sta   T1
                  ldx   T3
                  lda   Store3,x                ; current state byte (ZP)
                  tax
                  lda   $00,x
                  sta   ObjState
                  ldx   T3
                  lda   Store5,x
                  sta   Ptr
                  lda   Store6,x
                  sta   Ptr+1
                  jsr   GetObjectState
                  iny
                  lda   (Ptr),y                 ; sprite id
                  pha
                  lda   Store7,x
                  jsr   ChangeColor
                  sta   T2
                  pla
                  rts

* ---- CacheObjects (f235) -------------------------------------
CacheObjects      ldy   LastObj
                  lda   #ObjNone
                  sta   Obj1
                  sta   Obj2
MoveNextObject    tya
                  clc
                  adc   #9
                  cmp   #162
                  bcc   GetObjectsInfo
                  lda   #0
GetObjectsInfo    tay
                  lda   Store1,y
                  tax
                  lda   $00,x                   ; object's room
                  cmp   BallRoom
                  bne   CheckForMoreObjects
                  lda   Obj1
                  cmp   #ObjNone
                  bne   StoreObjectToPrint
                  sty   Obj1
                  jmp   CheckForMoreObjects
StoreObjectToPrint
                  sty   Obj2
                  jmp   StoreCount
CheckForMoreObjects
                  cpy   LastObj
                  bne   MoveNextObject
StoreCount        sty   LastObj
                  rts

* ---- RoomNumToAddress (f271) ---------------------------------
RoomNumToAddress  sta   Temp
                  asl
                  asl
                  asl
                  adc   Temp                    ; *9 (room < 32, no carry)
                  clc
                  adc   #<RoomDataTable
                  sta   Ptr
                  lda   #>RoomDataTable
                  adc   #0
                  sta   Ptr+1
                  rts

* ---- GetObjectState (f2a1) -----------------------------------
* Ptr -> state list, ObjState = value.  Returns Y -> matching entry
GetObjectState    ldy   #0
                  lda   ObjState
:loop             cmp   (Ptr),y
                  bcc   :done
                  beq   :done
                  iny
                  iny
                  iny
                  jmp   :loop
:done             rts

* ---- CheckInput (f2b2) ---------------------------------------
CheckInput        jsr   ReadInput               ; platform: SWCHA/SWCHB/INPT4
                  inc   FrameLo
                  bne   GetJoystick
                  inc   FrameHi
                  bne   GetJoystick
                  lda   #$80
                  sta   FrameHi
GetJoystick       lda   SWCHA
                  cmp   #$ff
                  bne   :moved
                  lda   SWCHB
                  and   #$03
                  cmp   #$03
                  beq   :done
:moved            lda   #0
                  sta   FrameHi
:done             rts

* ---- ChangeColor (f2d3) --------------------------------------
* 2600 color in A; flash colors (bit0) become the frame counter,
* and after a long idle the luminance is dimmed/cycled.
ChangeColor       lsr
                  bcc   :noflash
                  lda   FrameLo                 ; ($80,y with y=$65 -> $e5)
                  lsr
:noflash          ldy   FrameHi
                  bpl   :norm
                  eor   FrameHi
                  and   #$fb
:norm             asl
                  rts

* ---- BallMovement (f4c2) -------------------------------------
BallMovement      lda   CXBLPF
                  and   #$80
                  bne   PlayerCollision
                  lda   CXM0FB
                  and   #$40
                  bne   PlayerCollision
                  lda   CXM1FB
                  and   #$40
                  beq   :bm1
                  lda   Obj2
                  cmp   #$87                    ; black dot lets you through the right thin wall
                  bne   PlayerCollision
:bm1              lda   CXP0FB
                  and   #$40
                  beq   :bm2
                  lda   Obj1
                  cmp   #0                      ; surround doesn't block
                  bne   PlayerCollision
:bm2              lda   CXP1FB
                  and   #$40
                  beq   NoCollision
                  lda   Obj2
                  cmp   #0
                  bne   PlayerCollision
                  jmp   NoCollision

PlayerCollision   cpy   #2
                  bne   ReadStick
                  lda   Carried
                  cmp   #$5a                    ; carrying the bridge?
                  beq   ReadStick
                  lda   BallRoom
                  cmp   Bridge
                  bne   ReadStick
                  lda   BallX
                  sec
                  sbc   Bridge+1
                  cmp   #$0a
                  bcc   ReadStick
                  cmp   #$17
                  bcs   ReadStick
                  lda   Bridge+2
                  sec
                  sbc   BallY
                  cmp   #$fc
                  bcs   NoCollision
                  cmp   #$19
                  bcs   ReadStick
NoCollision       lda   #$ff
                  sta   Joystick
                  lda   BallRoom
                  sta   PrevRoom
                  lda   BallX
                  sta   PrevX
                  lda   BallY
                  sta   PrevY
ReadStick         cpy   #0
                  bne   :rs2
                  lda   SWCHA
                  sta   Joystick
:rs2              lda   PrevRoom
                  sta   BallRoom
                  lda   PrevX
                  sta   BallX
                  lda   PrevY
                  sta   BallY
                  lda   Joystick
                  ora   ReadStick_3,y
                  sta   Movement
                  ldy   #3
                  ldx   #BallRoom
                  jsr   MoveGroundObject
                  rts

* ---- PickupPutdown (f556) ------------------------------------
PickupPutdown     lda   INPT4
                  asl                           ; rol INPT4 -> carry = button bit
                  ror   ButtonHist
                  lda   ButtonHist
                  and   #$c0
                  cmp   #$40                    ; just pressed?
                  bne   :pp2
                  lda   #ObjNone
                  cmp   Carried
                  beq   :pp2
                  sta   Carried                 ; drop it
                  lda   #4
                  sta   NoiseType
                  lda   #4
                  sta   NoiseCount
:pp2              lda   #$ff
                  sta   $98
                  lda   CXP0FB
                  and   #$40
                  beq   :pp3
                  lda   Obj1
                  sta   HitObj
                  jmp   CollisionDetected
:pp3              lda   CXP1FB
                  and   #$40
                  beq   NoObject
                  lda   Obj2
                  sta   HitObj
CollisionDetected ldx   HitObj
                  jsr   GetObjectAddress        ; X = dyn addr
                  lda   HitObj
                  cmp   #$51                    ; carriable? (sword and up)
                  bcc   NoObject
                  lda   $00,x
                  cmp   BallRoom
                  bne   NoObject
                  lda   HitObj
                  cmp   Carried
                  beq   PickupObject
                  lda   #5
                  sta   NoiseType
                  lda   #4
                  sta   NoiseCount
PickupObject      lda   HitObj
                  sta   Carried
                  ldy   #6
                  lda   Joystick
                  jsr   MoveObjectDelta         ; nudge it along the stick
                  lda   $01,x
                  sec
                  sbc   BallX
                  sta   CarryDX
                  lda   $02,x
                  sec
                  sbc   BallY
                  sta   CarryDY
NoObject          rts

* ---- MoveCarriedObject (f5d4) --------------------------------
MoveCarriedObject ldx   Carried
                  cpx   #ObjNone
                  beq   :done
                  jsr   GetObjectAddress
                  lda   BallRoom
                  sta   $00,x
                  lda   BallX
                  clc
                  adc   CarryDX
                  sta   $01,x
                  lda   BallY
                  clc
                  adc   CarryDY
                  sta   $02,x
                  ldy   #0
                  lda   #$ff
                  jsr   MoveGroundObject
:done             rts

* X = object number -> X = ZP address of its dynamic data
GetObjectAddress  lda   Store1,x
                  tax
                  rts

* ---- MoveGroundObject (f5ff) ---------------------------------
* X = dyn addr, Y = delta, A = movement bits
MoveGroundObject  jsr   MoveObjectDelta
                  ldy   #2
:port             sty   Temp9a
                  lda   PortState,y
                  cmp   #$1c                    ; closed?
                  beq   GetPortal
                  ldy   Temp9a
                  lda   $00,x
                  cmp   EntryRoomOffsets,y
                  bne   GetPortal
                  lda   $02,x
                  cmp   #$0d
                  bpl   GetPortal
                  lda   CastleRoomOffsets,y     ; leaving castle downwards
                  sta   $00,x
                  lda   #$50
                  sta   $01,x
                  lda   #$2c
                  sta   $02,x
                  lda   #1
                  sta   PortState,y
                  rts
GetPortal         ldy   Temp9a
                  dey
                  bpl   :port
                  lda   $02,x                   ; off the top?
                  cmp   #$6a
                  bmi   DealWithLeft
                  lda   #$0d
                  sta   $02,x
                  ldy   #5
                  jmp   GetNewRoom
DealWithLeft      lda   $01,x
                  cmp   #$03
                  bcc   :left2
                  cmp   #$f0
                  bcs   :left2
                  jmp   DealWithDown
:left2            cpx   #BallRoom
                  beq   :left3
                  lda   #$9a
                  jmp   :left4
:left3            lda   #$9e
:left4            sta   $01,x
                  ldy   #8
                  jmp   GetNewRoom
DealWithDown      lda   $02,x
                  cmp   #$0d
                  bcs   DealWithRight
                  lda   #$69
                  sta   $02,x
                  ldy   #7
                  jmp   GetNewRoom
DealWithRight     lda   $01,x
                  cpx   #BallRoom
                  bne   :right2
                  cmp   #$9f
                  bcc   MovementReturn
                  lda   $00,x
                  cmp   #$03
                  bne   :right3
                  lda   DotRoom
                  cmp   #$15
                  beq   :right3
                  lda   #$1e                    ; secret room
                  sta   $00,x
                  lda   #$03
                  sta   $01,x
                  jmp   MovementReturn
:right2           cmp   #$9b
                  bcc   MovementReturn
:right3           lda   #$03
                  sta   $01,x
                  ldy   #6
GetNewRoom        lda   $00,x
                  stx   DynAddr2
                  jsr   RoomNumToAddress
                  lda   (Ptr),y
                  jsr   AdjustRoomLevel
                  ldx   DynAddr2
                  sta   $00,x
MovementReturn    rts

* ---- MoveObjectDelta (f6ac) ----------------------------------
* A = movement (active low: b7 right, b6 left, b5 down, b4 up), Y = delta
MoveObjectDelta   sta   Movement
:loop             dey
                  bmi   :done
                  lda   Movement
                  and   #$80
                  bne   :m3
                  inc   $01,x
:m3               lda   Movement
                  and   #$40
                  bne   :m4
                  dec   $01,x
:m4               lda   Movement
                  and   #$10
                  bne   :m5
                  inc   $02,x
:m5               lda   Movement
                  and   #$20
                  bne   :loop
                  dec   $02,x
                  jmp   :loop
:done             rts

* ---- AdjustRoomLevel (f6d5) ----------------------------------
AdjustRoomLevel   cmp   #$80
                  bcc   :done
                  sec
                  sbc   #$80
                  sta   Temp
                  lda   Level
                  lsr
                  clc
                  adc   Temp
                  tay
                  lda   RoomDiffs,y
:done             rts

* ---- PBCollision (f6e9) --------------------------------------
* A = object number -> A = nonzero if the ball touches it
PBCollision       cmp   Obj1
                  beq   :pb2
                  cmp   Obj2
                  beq   :pb3
                  lda   #0
                  rts
:pb2              lda   CXP0FB
                  and   #$40
                  rts
:pb3              lda   CXP1FB
                  and   #$40
                  rts

* ---- FindObjHit (f6fe) ---------------------------------------
* X = object number -> A = the other displayed object touching it
FindObjHit        lda   CXPPMM
                  and   #$80
                  beq   :none
                  cpx   Obj1
                  beq   :other2
                  cpx   Obj2
                  beq   :other1
:none             lda   #ObjNone
                  rts
:other2           lda   Obj2
                  rts
:other1           lda   Obj1
                  rts

* ---- MoveGameObject (f715) -----------------------------------
MoveGameObject    jsr   GetLinkedObject
                  ldx   DynAddr
                  lda   Movement
                  bne   :m2
                  lda   $03,x
:m2               sta   $03,x
                  ldy   Delta
                  jsr   MoveGroundObject
                  rts

* ---- GetLinkedObject (f728) ----------------------------------
* Walk the matrix at MatrixPtr: pairs (a, b) of dyn addrs.  The
* first pair whose objects share a room (neither being the object
* in Difficulty) yields the direction from a towards b in
* Movement.  Returns X = a's dyn addr.
GetLinkedObject   lda   #0
                  sta   LinkIdx
:next             ldy   LinkIdx
                  lda   (MatrixPtr),y
                  sta   T4
                  iny
                  lda   (MatrixPtr),y
                  sta   T5
                  ldx   T4
                  lda   $00,x
                  sta   T3
                  ldx   T5
                  lda   $00,x
                  cmp   T3
                  bne   :skip
                  lda   T5
                  cmp   Difficulty
                  beq   :skip
                  lda   T4
                  cmp   Difficulty
                  beq   :skip
                  jmp   LinkMove
:skip             inc   LinkIdx
                  inc   LinkIdx
                  ldy   LinkIdx
                  lda   (MatrixPtr),y
                  bne   :next
                  lda   #0
                  sta   Movement
                  rts

LinkMove          lda   #$ff
                  sta   Movement
                  ldx   T5
                  lda   $00,x
                  sta   T0
                  lda   $01,x
                  sta   T1
                  lda   $02,x
                  sta   T2
                  ldx   T4
                  lda   T0
                  cmp   $00,x
                  bne   :done
                  lda   T1
                  cmp   $01,x
                  bcc   :left
                  beq   :vert
                  lda   Movement
                  and   #$7f                    ; right
                  sta   Movement
                  jmp   :vert
:left             lda   Movement
                  and   #$bf                    ; left
                  sta   Movement
:vert             lda   T2
                  cmp   $02,x
                  bcc   :down
                  beq   :done
                  lda   Movement
                  and   #$ef                    ; up
                  sta   Movement
                  jmp   :done
:down             lda   Movement
                  and   #$df                    ; down
                  sta   Movement
:done             lda   Movement
                  rts

* ---- MoveRedDragon / MoveYellowDragon / MoveGreenDragon (f795..) -
MoveRedDragon     lda   #<RedDragMatrix
                  sta   MatrixPtr
                  lda   #>RedDragMatrix
                  sta   MatrixPtr+1
                  lda   #3
                  sta   Delta
                  ldx   #$36
                  jmp   MoveDragon
MoveYellowDragon  lda   #<YelDragMatrix
                  sta   MatrixPtr
                  lda   #>YelDragMatrix
                  sta   MatrixPtr+1
                  lda   #2
                  sta   Delta
                  ldx   #$3f
                  jmp   MoveDragon
MoveGreenDragon   lda   #<GreenDragMatrix
                  sta   MatrixPtr
                  lda   #>GreenDragMatrix
                  sta   MatrixPtr+1
                  lda   #2
                  sta   Delta
                  ldx   #$48
* ---- MoveDragon (f7ea) ---------------------------------------
* states: 0 normal, 1 dead, 2 has eaten the ball, $d0-$ff roaring
MoveDragon        stx   DragonObj
                  lda   Store1,x
                  tax
                  lda   $04,x
                  cmp   #0
                  bne   :md6
                  lda   SWCHB
                  and   #$80                    ; right difficulty A: dragons flee the sword
                  beq   :md2
                  lda   #0
                  jmp   :md3
:md2              lda   #$b6                    ; B: ignore the sword
:md3              sta   Difficulty
                  stx   DynAddr
                  jsr   MoveGameObject
                  ldx   DynAddr
                  lda   DragonObj
                  jsr   PBCollision
                  beq   :md4
                  lda   SWCHB
                  rol
                  rol
                  rol
                  and   #1                      ; left difficulty bit
                  ora   Level
                  tay
                  lda   DragonDiff,y
                  sta   $04,x                   ; start roaring
                  lda   PrevX
                  sta   $01,x
                  lda   PrevY
                  sta   $02,x
                  lda   #1
                  sta   NoiseType
                  lda   #$10
                  sta   NoiseCount
:md4              stx   Temp9a
                  ldx   DragonObj
                  jsr   FindObjHit
                  ldx   Temp9a
                  cmp   #$51                    ; sword?
                  bne   :md9
                  lda   #1
                  sta   $04,x                   ; dead
                  lda   #3
                  sta   NoiseType
                  lda   #$10
                  sta   NoiseCount
                  rts
:md6              cmp   #1
                  beq   :md9
                  cmp   #2
                  bne   :md7
                  lda   $00,x                   ; eaten: ball rides in the dragon
                  sta   BallRoom
                  sta   PrevRoom
                  lda   $01,x
                  clc
                  adc   #3
                  sta   BallX
                  sta   PrevX
                  lda   $02,x
                  sec
                  sbc   #$0a
                  sta   BallY
                  sta   PrevY
                  rts
:md7              inc   $04,x                   ; roaring
                  lda   $04,x
                  cmp   #$fc
                  bcc   :md9
                  lda   DragonObj
                  jsr   PBCollision
                  beq   :md9
                  lda   #2
                  sta   $04,x
                  lda   #2
                  sta   NoiseType
                  lda   #$10
                  sta   NoiseCount
                  lda   #$9b
                  cmp   $01,x
                  beq   :md8
                  bcs   :md8
                  sta   $01,x
:md8              lda   #$17
                  cmp   $02,x
                  bcc   :md9
                  sta   $02,x
:md9              rts

* ---- MoveBat (f8a5) ------------------------------------------
MoveBat           inc   Bat+4
                  lda   Bat+4
                  cmp   #8
                  bne   :mb2
                  lda   #0
                  sta   Bat+4
:mb2              lda   BatFedUp
                  beq   :mb3
                  inc   BatFedUp
                  lda   Bat+3
                  ldx   #Bat
                  ldy   #3
                  jsr   MoveGroundObject
                  jmp   :mb4
:mb3              lda   #Bat
                  sta   DynAddr
                  lda   #3
                  sta   Delta
                  lda   #<BatMatrix
                  sta   MatrixPtr
                  lda   #>BatMatrix
                  sta   MatrixPtr+1
                  lda   BatCarry
                  sta   Difficulty
                  jsr   MoveGameObject
                  ldy   LinkIdx
                  lda   (MatrixPtr),y
                  beq   :mb4
                  iny
                  lda   (MatrixPtr),y
                  tax
                  lda   $00,x
                  cmp   Bat
                  bne   :mb4
                  lda   $01,x
                  sec
                  sbc   Bat+1
                  clc
                  adc   #4
                  and   #$f8
                  bne   :mb4
                  lda   $02,x
                  sec
                  sbc   Bat+2
                  clc
                  adc   #4
                  and   #$f8
                  bne   :mb4
                  stx   BatCarry
                  lda   #$10
                  sta   BatFedUp
:mb4              ldx   BatCarry
                  lda   Bat
                  sta   $00,x
                  lda   Bat+1
                  clc
                  adc   #8
                  sta   $01,x
                  lda   Bat+2
                  sta   $02,x
                  lda   BatCarry
                  ldy   Carried
                  cmp   Store1,y
                  bne   :mb5
                  lda   #ObjNone
                  sta   Carried
:mb5              rts

* ---- Portals (f93c) ------------------------------------------
Portals           ldy   #2
:p2               ldx   PortOffsets,y
                  jsr   FindObjHit
                  sta   HitObj
                  cmp   KeyOffsets,y
                  bne   :p3
                  tya
                  tax
                  inc   PortState,x             ; key: start opening
:p3               tya
                  tax
                  lda   PortState,x
                  cmp   #$1c
                  beq   :p7
                  lda   PortOffsets,y
                  jsr   PBCollision
                  beq   :p4
                  lda   #1
                  sta   PortState,x
                  ldx   #BallRoom
                  jmp   :p6
:p4               lda   HitObj
                  cmp   #ObjNone
                  beq   :p7
                  ldx   HitObj
                  sty   Temp9a
                  jsr   GetObjectAddress
                  ldy   Temp9a
:p6               lda   EntryRoomOffsets,y
                  sta   $00,x
                  lda   #$10
                  sta   $02,x
:p7               tya
                  tax
                  lda   PortState,x
                  cmp   #1
                  beq   :p8
                  cmp   #$1c
                  beq   :p8
                  inc   PortState,x
                  lda   PortState,x
                  cmp   #$38
                  bne   :p8
                  lda   #1
                  sta   PortState,x
:p8               dey
                  bmi   :p9
                  jmp   :p2
:p9               rts

* ---- Mag (f9b3) ----------------------------------------------
Mag               lda   Magnet+2
                  sec
                  sbc   #8
                  sta   Magnet+2
                  lda   #0
                  sta   Difficulty
                  lda   #<MagnetMatrix
                  sta   MatrixPtr
                  lda   #>MagnetMatrix
                  sta   MatrixPtr+1
                  jsr   GetLinkedObject
                  lda   Movement
                  beq   :m2
                  ldy   #1
                  jsr   MoveGroundObject        ; X = attracted object
:m2               lda   Magnet+2
                  clc
                  adc   #8
                  sta   Magnet+2
                  rts

* ---- Surround (f9e7) -----------------------------------------
Surround          lda   BallRoom
                  jsr   RoomNumToAddress
                  ldy   #2
                  lda   (Ptr),y
                  cmp   #8                      ; dark room?
                  beq   :s2
                  lda   #0
                  sta   SurY
                  rts
:s2               lda   BallRoom
                  sta   SurRoom
                  lda   BallX
                  sec
                  sbc   #$0e
                  sta   SurX
                  lda   BallY
                  clc
                  adc   #$0e
                  sta   SurY
                  lda   SurX
                  cmp   #$f0
                  bcc   :s3
                  lda   #1
                  sta   SurX
                  rts
:s3               cmp   #$82
                  bcc   :s4
                  lda   #$81
                  sta   SurX
:s4               rts

* ---- MakeSound (fa23) ----------------------------------------
* Sound is a later milestone; only the timing side effects are
* kept: the note counter, and noise 0 (game over) driving the
* playfield color.
MakeSound         lda   NoiseCount
                  bne   :ms2
                  rts
:ms2              dec   NoiseCount
                  lda   NoiseType
                  bne   :done
                  lda   NoiseCount
                  sta   PFOverride
:done             rts
