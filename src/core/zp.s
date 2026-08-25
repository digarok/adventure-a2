*-------------------------------------------------------------
* Zero page / direct page game state.  Same layout and roles
* as the 2600 original ($80-$FF) so the logic can be compared
* against the disassembly line by line.
*-------------------------------------------------------------
RoomGfxPtr        equ   $80                     ; ptr to current room's playfield rows
Obj1SprId         equ   $82                     ; (2600: gfx ptr) sprite id for object 1
Obj2SprId         equ   $84                     ; sprite id for object 2
Obj1X             equ   $86
Obj1Y             equ   $87
Obj2X             equ   $88
Obj2Y             equ   $89
BallRoom          equ   $8a
BallX             equ   $8b
BallY             equ   $8c
PrevSwitches      equ   $92
Ptr               equ   $93                     ; general 16-bit pointer
Obj1              equ   $95                     ; object index (x9) shown as player 0
Obj2              equ   $96
HitObj            equ   $97
Joystick          equ   $99                     ; SWCHA snapshot
Temp9a            equ   $9a
Movement          equ   $9b
LastObj           equ   $9c                     ; CacheObjects round-robin
Carried           equ   $9d                     ; $a2 = nothing
CarryDX           equ   $9e
CarryDY           equ   $9f
DragonObj         equ   $a0
* $a1-$d1 : object dynamic data (room,x,y[,move,state]) copied from GameNObjects
DotRoom           equ   $a1
RedDragon         equ   $a4                     ; room,x,y,move,state
YelDragon         equ   $a9
GrnDragon         equ   $ae
Magnet            equ   $b3
Sword             equ   $b6
Chalice           equ   $b9
Bridge            equ   $bc
YelKey            equ   $bf
WhtKey            equ   $c2
BlkKey            equ   $c5
PortState         equ   $c8                     ; 3 portcullis states
Bat               equ   $cb                     ; room,x,y,move,state
BatCarry          equ   $d0
BatFedUp          equ   $d1
MatrixPtr         equ   $d2
Delta             equ   $d4
DynAddr           equ   $d5
Difficulty        equ   $d6
ButtonHist        equ   $d7
Temp              equ   $d8
SurRoom           equ   $d9                     ; invisible surround room,x,y
SurX              equ   $da
SurY              equ   $db
ObjState          equ   $dc
Level             equ   $dd                     ; 0,2,4 = game 1,2,3
GameInactive      equ   $de
NoiseCount        equ   $df
NoiseType         equ   $e0
LinkIdx           equ   $e1
PrevRoom          equ   $e2
PrevX             equ   $e3
PrevY             equ   $e4
FrameLo           equ   $e5                     ; input counter / PRNG / flash
FrameHi           equ   $e6
* emulated TIA / RIOT registers
SWCHA             equ   $f0                     ; joystick, active low: R L D U in bits 7-4
SWCHB             equ   $f1                     ; console switches (active low)
INPT4             equ   $f2                     ; bit7=0 button pressed
CXBLPF            equ   $f3                     ; bit7 ball-playfield
CXM0FB            equ   $f4                     ; bit6 ball-missile0 (left thin wall)
CXM1FB            equ   $f5                     ; bit6 ball-missile1 (right thin wall)
CXP0FB            equ   $f6                     ; bit6 ball-player0
CXP1FB            equ   $f7                     ; bit6 ball-player1
CXPPMM            equ   $f8                     ; bit7 player0-player1
