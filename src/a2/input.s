*-------------------------------------------------------------
* Keyboard -> emulated 2600 joystick / console switches
*   arrows move (direction held while any key is down),
*   space = button, R reset, S select, 1/2 difficulty, P full
*   reset (power cycle), Q/Esc quit
*-------------------------------------------------------------
LastDir           db    $ff
HoldTimer         db    0
HasAKD            db    0                       ; IIe/IIc/IIgs: $C010 bit7 = any key down
IsGS              db    0                       ; IIgs: slow to 1 MHz for the speaker
PendingKey        db    0                       ; a key read early, for ReadInput

ReadInput         lda   SWCHB
                  ora   #$03                    ; reset/select released
                  sta   SWCHB
                  lda   #$80
                  sta   INPT4
                  lda   PendingKey              ; the title screen's key
                  beq   :poll
                  ldx   #0
                  stx   PendingKey
                  jmp   :key
:poll             lda   KEY
                  bmi   :havekey                ; bpl :nonew is out of range
                  jmp   :nonew                  ;  now that :nonew moved further
:havekey          sta   STROBE
:key              and   #$7f
                  cmp   #$08                    ; left
                  bne   :k1
                  lda   #$bf
                  jmp   :dir
:k1               cmp   #$15                    ; right
                  bne   :k2
                  lda   #$7f
                  jmp   :dir
:k2               cmp   #$0b                    ; up
                  bne   :k3
                  lda   #$ef
                  jmp   :dir
:k3               cmp   #$0a                    ; down
                  bne   :k4
                  lda   #$df
:dir              sta   LastDir
                  lda   #6
                  sta   HoldTimer
                  jmp   :nonew
:k4               cmp   #' '
                  bne   :k5
                  lda   #0
                  sta   INPT4
                  jmp   :nonew
:k5               ora   #$20                    ; lower case
                  cmp   #'r'
                  bne   :k6
                  lda   SWCHB
                  and   #$fe
                  sta   SWCHB
                  jmp   :nonew
:k6               cmp   #'s'
                  bne   :k7
                  lda   SWCHB
                  and   #$fd
                  sta   SWCHB
                  jmp   :nonew
:k7               cmp   #'1'
                  bne   :k8
                  lda   SWCHB
                  eor   #$40
                  sta   SWCHB
                  jmp   :nonew
:k8               cmp   #'2'
                  bne   :k8p
                  lda   SWCHB
                  eor   #$80
                  sta   SWCHB
                  jmp   :nonew
:k8p              cmp   #'p'                    ; power cycle: full reset, not
                  bne   :k9                     ;  just a respawn like R
                  lda   #1
                  sta   FullResetFlag
                  jmp   :nonew
:k9               cmp   #$1b                    ; Esc
                  beq   :quit
                  cmp   #'q'
                  bne   :nonew
:quit
                  lda   #1
                  sta   QuitFlag
:nonew            lda   #$ff
                  sta   SWCHA
                  lda   HasAKD
                  beq   :timer
                  lda   STROBE                  ; any key down?
                  bpl   :done
                  jmp   :held
:timer            lda   HoldTimer
                  beq   :done
                  dec   HoldTimer
:held             lda   LastDir
                  sta   SWCHA
:done             rts
