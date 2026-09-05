#!/bin/bash
# Headless boot test with gsplus-harness.
#   tools/harness.sh [secs] [extra harness flags...]
# Artifacts (screenshots, state dumps) land in build/harness-a2/
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
HARNESS=${HARNESS:-/Users/dbrock/dev/gsplus-harness/gsplus/build/GSplus.app/Contents/MacOS/GSplus}
SECS=${1:-30}; shift || true
OUT=$ROOT/build/harness-a2
rm -rf "$OUT"; mkdir -p "$OUT"
cp build/adventure.po "$OUT/disk.po"
# config is regenerated every run (gsplus rewrites it on exit)
cat > "$OUT/config.kegs" <<EOT
s5d1 =
s6d1 = $OUT/disk.po
s7d1 =
g_limit_speed = 0
EOT
grep '^bram1' "$ROOT/config_a2.kegs" >> "$OUT/config.kegs"
cp "${ROMFILE:-/Users/dbrock/appleiigs/pitfall/ROM}" "$OUT/ROM"
cd "$OUT"
SDL_VIDEODRIVER=dummy "$HARNESS" -config "$OUT/config.kegs" -hdir "$OUT" -hturbo -hbrk \
    -hsecs "$SECS" -audio 0 -g_status_enable 0 "$@"
echo "harness exit=$?"
ls "$OUT"
