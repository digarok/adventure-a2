*-------------------------------------------------------------
* Title screen: 40-column text, shown once at startup.  Any key
* goes on to the game; the key is left in the keyboard so it
* also counts as the first game keystroke (R starts a game).
*-------------------------------------------------------------
HOME              equ   $fc58
COUT              equ   $fded

TitleScreen       sta   TXTSET
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
                  rts

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
