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

Building and running (from the repo):
  make a2          assemble and build build/adventure.po (140K, bootable)
  make run-a2      build, then launch it in GSplus

The disk goes in slot 7, which the IIgs boot scanner tries first, so it
boots straight in without waiting on the slot 7 -> 5 -> 6 scan.  GSplus
rewrites its config file on exit, so tools/run.sh copies the config into
build/run-a2/ and runs from there rather than letting it overwrite the
checked-in one.
