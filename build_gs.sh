#!/bin/bash
# Build the Apple IIgs GS/OS version: build/adventuregs.2mg (800K, bootable, auto-launches)
set -e
CADIUS=${CADIUS:-/Users/dbrock/appleiigs/cadius/bin/macosx/Cadius}   # needs the digarok fork for 140KB volumes
cd "$(dirname "$0")"
DISK=ADVENTUREGS
IMG=build/adventuregs.2mg
BLD=build/gs
rm -f src/gs/adventure
merlin32 -V src/gs src/gs/adventure.s
[ -f src/gs/adventure ] || { echo "assembly failed"; exit 1; }
mkdir -p $BLD
mv src/gs/adventure $BLD/ADVENTURE.SYS16
LC_ALL=C tr '\000-\177' '\200-\377' < README.md > $BLD/README
cat > $BLD/_FileInformation.txt <<EOT
ADVENTURE.SYS16=Type(B3),AuxType(0000),VersionCreate(00),MinVersion(00),Access(E3)
README=Type(04),AuxType(0000),VersionCreate(00),MinVersion(00),Access(E3)
EOT
rm -f $IMG
$CADIUS createvolume $IMG $DISK 800KB > /dev/null
# boot blocks: offset 64 = past the 2mg header (cadius leaves blocks 0-1 zeroed)
dd if=gsos/BOOT.BLOCKS of=$IMG bs=1 seek=64 conv=notrunc 2> /dev/null
for d in /$DISK/System /$DISK/System/System.Setup /$DISK/System/FSTs \
         /$DISK/System/Drivers /$DISK/System/Tools /$DISK/System/Desk.Accs; do
  $CADIUS createfolder $IMG $d > /dev/null
done
$CADIUS addfile $IMG /$DISK/ gsos/ProDOS > /dev/null
for f in GS.OS GS.OS.Dev Start.GS.OS Error.Msg; do
  $CADIUS addfile $IMG /$DISK/System/ gsos/System/$f > /dev/null
done
for f in Tool.Setup TS2 TS3 Resource.Mgr Sys.Resources FixInit; do
  $CADIUS addfile $IMG /$DISK/System/System.Setup/ gsos/System/System.Setup/$f > /dev/null
done
for f in Pro.FST Char.FST; do
  $CADIUS addfile $IMG /$DISK/System/FSTs/ gsos/System/FSTs/$f > /dev/null
done
for f in AppleDisk3.5 Console.Driver; do
  $CADIUS addfile $IMG /$DISK/System/Drivers/ gsos/System/Drivers/$f > /dev/null
done
$CADIUS addfile $IMG /$DISK/System/Desk.Accs/ gsos/System/Desk.Accs/QuitCDA > /dev/null
for f in gsos/System/Tools/Tool* gsos/System/Tools/TOOL*; do
  $CADIUS addfile $IMG /$DISK/System/Tools/ $f > /dev/null
done
for f in ADVENTURE.SYS16 README; do
  $CADIUS addfile $IMG /$DISK/ $BLD/$f > /dev/null
done
$CADIUS catalog $IMG | tail -4
