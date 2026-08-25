#!/bin/bash
# Build the 8-bit ProDOS 8 version: build/adventure.po (140K, bootable)
set -e
CADIUS=${CADIUS:-/Users/dbrock/appleiigs/cadius/bin/macosx/Cadius}   # needs the digarok fork for 140KB volumes
cd "$(dirname "$0")"
DISK=ADVENTURE
IMG=build/adventure.po
BLD=build/a2
rm -f src/a2/adventure src/a2/ADVENT.SYSTEM
merlin32 -V src/a2 src/a2/adventure.s
[ -f src/a2/adventure ] || { echo "assembly failed"; exit 1; }
mkdir -p $BLD
mv src/a2/adventure $BLD/ADVENT.SYSTEM
cp p8/PRODOS $BLD/PRODOS
LC_ALL=C tr '\000-\177' '\200-\377' < README.md > $BLD/README
cat > $BLD/_FileInformation.txt <<EOT
PRODOS=Type(FF),AuxType(0000),VersionCreate(00),MinVersion(B0),Access(E3)
ADVENT.SYSTEM=Type(FF),AuxType(0000),VersionCreate(00),MinVersion(00),Access(E3)
README=Type(04),AuxType(0000),VersionCreate(00),MinVersion(00),Access(E3)
EOT
rm -f $IMG
$CADIUS createvolume $IMG $DISK 140KB > /dev/null
for f in PRODOS ADVENT.SYSTEM README; do
  $CADIUS addfile $IMG /$DISK/ $BLD/$f > /dev/null
done
$CADIUS catalog $IMG | tail -5
