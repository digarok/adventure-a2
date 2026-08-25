#!/bin/bash
# Headless boot test with gsplus-harness.
#   tools/harness.sh a2|gs [secs] [extra harness flags...]
# Artifacts (screenshots, state dumps) land in build/harness-<target>/
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
HARNESS=${HARNESS:-/Users/dbrock/dev/gsplus-harness/gsplus/build/GSplus.app/Contents/MacOS/GSplus}
TARGET=$1; shift || true
SECS=${1:-30}; shift || true
OUT=$ROOT/build/harness-$TARGET
rm -rf "$OUT"; mkdir -p "$OUT"
case $TARGET in
  a2) cp build/adventure.po "$OUT/disk.po"; S5=""; S6="$OUT/disk.po" ;;
  gs) cp build/adventuregs.2mg "$OUT/disk.2mg"; S5="$OUT/disk.2mg"; S6="" ;;
  *) echo "usage: $0 a2|gs [secs] [flags]"; exit 1 ;;
esac
# config is regenerated every run (gsplus rewrites it on exit)
cat > "$OUT/config.kegs" <<EOT
s5d1 = $S5
s6d1 = $S6
s7d1 =
g_limit_speed = 0
EOT
grep '^bram1' "$ROOT/config_gs.kegs" >> "$OUT/config.kegs"
cp "${ROMFILE:-/Users/dbrock/appleiigs/pitfall/ROM}" "$OUT/ROM"
cd "$OUT"
SDL_VIDEODRIVER=dummy "$HARNESS" -config "$OUT/config.kegs" -hdir "$OUT" -hturbo -hbrk \
    -hsecs "$SECS" -audio 0 -g_status_enable 0 "$@"
echo "harness exit=$?"
ls "$OUT"
