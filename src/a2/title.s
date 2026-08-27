*-------------------------------------------------------------
* Title screen: 40-column text, shown once at startup.  Any key
* goes on to the game, and is handed to it as its first keystroke
* (R starts a game).  While the key is down, the any-key-down flag
* is checked: a machine or emulator that does not report it gets
* the II+ scheme of a timed hold instead.
*-------------------------------------------------------------
HOME              equ   $fc58
COUT              equ   $fded
SETKBD            equ   $fe89
SETVID            equ   $fe93
INVFLG            equ   $32
WNDLFT            equ   $20
WNDWDTH           equ   $21
WNDTOP            equ   $22
WNDBTM            equ   $23
COL80OFF          equ   $c00c
ALTCHAROFF        equ   $c00e

TitleScreen       jsr   SETVID                  ; plain 40-column ROM output,
                  jsr   SETKBD                  ;  whatever launched us
                  sta   COL80OFF
                  sta   ALTCHAROFF
                  lda   #0                      ; full-screen text window
                  sta   WNDLFT
                  sta   WNDTOP
                  lda   #40
                  sta   WNDWDTH
                  lda   #24
                  sta   WNDBTM
                  lda   #$ff
                  sta   INVFLG                  ; normal text
                  sta   TXTSET
                  sta   PAGE1
                  jsr   HOME
                  lda   #<TitleText
                  sta   Ptr
                  lda   #>TitleText
                  sta   Ptr+1
                  ldy   #0
:print            lda   (Ptr),y
                  beq   :wait
                  jsr   COUT
                  inc   Ptr
                  bne   :print
                  inc   Ptr+1
                  bne   :print
:wait             lda   KEY
                  bpl   :wait
                  sta   PendingKey
                  lda   STROBE                  ; clear it; bit 7 = still down
                  bmi   :akd
                  lda   #0
                  sta   HasAKD
:akd              rts

TitleText         asc   8D,8D
                  asc   "         ADVENTURE FOR APPLE ][",8D,8D,8D
                  asc   "       CONVERSION BY DAGEN BROCK",8D,8D
                  asc   " HTTPS://GITHUB.COM/DIGAROK/ADVENTURE-A2",8D,8D,8D
                  asc   "   ARROWS   MOVE",8D
                  asc   "   SPACE    DROP WHAT YOU ARE CARRYING",8D
                  asc   "   R        RESET (START A GAME)",8D
                  asc   "   S        SELECT GAME 1/2/3",8D
                  asc   "            (IN THE NUMBER ROOM)",8D
                  asc   "   1 / 2    LEFT / RIGHT DIFFICULTY",8D
                  asc   "   Q / ESC  QUIT TO PRODOS",8D,8D,8D
                  asc   "          PRESS ANY KEY TO PLAY"
                  db    0
