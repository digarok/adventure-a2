#!/bin/bash
# Launch GSplus on one of the disks.
#   tools/run.sh a2|gs
#
# GSplus rewrites its config file on exit, using the *basename* of -cfg
# relative to the current directory - run it straight from the repo and it
# overwrites the checked-in config with whatever state you quit in.  So the
# config is regenerated in build/run-<target>/ with absolute disk paths and
# GSplus is run from there.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
GSPLUS=${GSPLUS:-/Users/dbrock/dev/gsplus/gsplus/src/build/GSplus.app/Contents/MacOS/GSplus}
TARGET=$1
case $TARGET in
  a2) SRC=config_a2.kegs; DISK=$ROOT/build/adventure.po ;;
  gs) SRC=config_gs.kegs; DISK=$ROOT/build/adventuregs.2mg ;;
  *)  echo "usage: $0 a2|gs"; exit 1 ;;
esac
[ -f "$DISK" ] || { echo "$DISK not built - run 'make $TARGET' first"; exit 1; }
OUT=$ROOT/build/run-$TARGET
mkdir -p "$OUT"
sed "s|= build/adventure|= $ROOT/build/adventure|" "$SRC" > "$OUT/$SRC"
cd "$OUT"
exec "$GSPLUS" -cfg "$OUT/$SRC"
