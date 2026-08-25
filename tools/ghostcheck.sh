#!/bin/bash
# Check that the renderer leaves nothing stale behind.
#
# Runs a scene twice: once letting the screen build up incrementally, and
# once forcing a full room redraw part way through (by poking the page
# signature).  Both runs are deterministic and identical up to that poke,
# so the final screenshots must match pixel for pixel.
#
# Comparing two shots of a SINGLE run would also flag sprite animation -
# the bat's wings move every few ticks - which is not a bug.  This does not.
#
#   tools/ghostcheck.sh <scene>...      (scenes live in tests/<name>ghost.txt
#                                        and contain a FORCEREDRAW line)
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SECS=${SECS:-60}
fail=0
for scene in "$@"; do
  SRC=tests/$scene.txt
  [ -f "$SRC" ] || { echo "$SRC not found"; exit 1; }
  for mode in forced plain; do
    if [ $mode = forced ]; then
      sed 's|^FORCEREDRAW$|00/60fe:ff ff ff ff ff ff ff ff|' "$SRC" > /tmp/ghost-$$.txt
    else
      sed '/^FORCEREDRAW$/d' "$SRC" > /tmp/ghost-$$.txt
    fi
    ./tools/harness.sh a2 "$SECS" -script /tmp/ghost-$$.txt > /tmp/ghost-$$.log 2>&1 || true
    if grep -q "BRK at" /tmp/ghost-$$.log; then
      echo "$scene: CRASHED ($(grep -m1 'BRK at' /tmp/ghost-$$.log))"; fail=1; continue 2
    fi
    cp build/harness-a2/ghost.png /tmp/ghost-$scene-$mode.png
  done
  n=$(python3 -c "
from PIL import Image; import numpy as np
a=np.array(Image.open('/tmp/ghost-$scene-forced.png').convert('RGB'))
b=np.array(Image.open('/tmp/ghost-$scene-plain.png').convert('RGB'))
print((a!=b).any(axis=2).sum())")
  if [ "$n" = 0 ]; then echo "$scene: clean"; else echo "$scene: $n STALE PIXELS"; fail=1; fi
done
rm -f /tmp/ghost-$$.txt /tmp/ghost-$$.log
exit $fail
