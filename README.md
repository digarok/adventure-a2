ADVENTURE A2 - a port of Atari 2600 Adventure (Warren Robinett, 1979)
to the Apple II, from the published 6502 disassembly.

The game logic is the original 6502 code, ported line for line.  Only
three things are replaced: the TIA display kernel (a HGR renderer), the
TIA collision latches (computed in software from the same sprite and
playfield data), and the console switches / joystick (the keyboard).

Controls:
  Arrow keys    move
  Space         drop the object you are carrying
  R             reset (start a game)
  S             select game 1/2/3 (only in the number room)
  1 / 2         toggle the left / right difficulty switches
  Esc           quit to ProDOS

Runs at the original 20 ticks per second on a 1 MHz Apple II.
