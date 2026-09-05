#!/bin/bash
# Launch GSplus on the disk.
#   tools/run.sh
#
# GSplus rewrites its config file on exit, using the *basename* of -cfg
# relative to the current directory - run it straight from the repo and it
# overwrites the checked-in config with whatever state you quit in.  So the
# config is regenerated in build/run-a2/ with an absolute disk path and
# GSplus is run from there.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
GSPLUS=${GSPLUS:-/Users/dbrock/dev/gsplus/gsplus/src/build/GSplus.app/Contents/MacOS/GSplus}
SRC=config_a2.kegs
DISK=$ROOT/build/adventure.po
[ -f "$DISK" ] || { echo "$DISK not built - run 'make a2' first"; exit 1; }
OUT=$ROOT/build/run-a2
mkdir -p "$OUT"
sed "s|= build/adventure|= $ROOT/build/adventure|" "$SRC" > "$OUT/$SRC"
cd "$OUT"
exec "$GSPLUS" -cfg "$OUT/$SRC"
