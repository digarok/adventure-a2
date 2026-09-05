#!/bin/bash
# Run a scene and check that everything the renderer means to draw reaches
# the screen.  The ghost checks compare two runs of one build, so they
# cannot see a sprite that is never drawn at all - this can.
#   tools/drawcheck.sh <scene>...   (tests/<name>.txt must dump NewSig and
#                                    take a screenshot named after itself)
set -e
cd "$(dirname "$0")/.."
fail=0
for scene in "$@"; do
  ./tools/harness.sh "${SECS:-30}" -script "$PWD/tests/$scene.txt" 2>&1 \
      | grep -E "^00/61" > /tmp/drawcheck-$$.txt
  printf "%-10s " "$scene"
  python3 tools/drawcheck.py /tmp/drawcheck-$$.txt "build/harness-a2/$scene.png" || fail=1
done
rm -f /tmp/drawcheck-$$.txt
exit $fail
