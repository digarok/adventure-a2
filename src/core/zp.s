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
AUDC0             equ   $50                     ; audio control / frequency / volume, as
AUDF0             equ   $51                     ;  written by MakeSound, played by PlaySound
AUDV0             equ   $52
AUDLEN            equ   $2c                     ; note length in quarter ticks (4 = a tick)
* ZP copies of ROM-resident object data (filled from ZPConsts at start)
PortInfo1         equ   $60                     ; room,x,y of the 3 portcullises
PortInfo2         equ   $63
PortInfo3         equ   $66
AuthorInfo        equ   $69
NumberInfo        equ   $6c
ZeroState         equ   $6f                     ; state byte for objects with one state
* port-specific variables ($10-$2f; $78-$7f is scratch the bat may write to)
PFOverride        equ   $10                     ; $ff = none, else 2600 color for playfield (game over flash)
DynAddr2          equ   $11
T0                equ   $12
T1                equ   $13
T2                equ   $14
T3                equ   $15
T4                equ   $16
T5                equ   $17
DescA             equ   $18                     ; collision descriptors: x,y,sprite id
DescB             equ   $1b
CkT               equ   $1e
CtT               equ   $1f
RowT              equ   $20
DxT               equ   $21
XLo               equ   $22
XHi               equ   $23
CLo               equ   $24
CHi               equ   $25
SceneTick         equ   $2b                     ; set by SetupRoomPrint, cleared by DrawFrame
QuitFlag          equ   $26                     ; set by ReadInput on Esc
FullResetFlag     equ   $2d                     ; set by ReadInput: full reset, like a power cycle
RoomColor         equ   $27                     ; 2600 color of the playfield this frame
RoomCtrl          equ   $28                     ; b7 left thin wall, b6 right thin wall, b2 PF priority
Obj1Color         equ   $29
Obj2Color         equ   $2a
ObjNone           equ   $a2                     ; "no object" (= null object index)
