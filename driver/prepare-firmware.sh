#!/bin/sh
# Extract locally supplied HP firmware; never run the legacy installer/scripts.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
[ "$#" -eq 1 ] || { echo 'Usage: ./prepare-firmware.sh /path/to/HewlettPackardPrinterDrivers.dmg' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo 'Apple Silicon required.' >&2; exit 1; }
case "$1" in /*) DMG=$1 ;; *) DMG="$PWD/$1" ;; esac
cd "$(dirname "$0")"
EXPECTED_DMG=523836b630431bc39b0170a17099099d6f821ef62ff29e6ec64ebb69b9954133
EXPECTED_ACL=6458207a022bc25424e31d4996b99d3a1957e0ebf8cb5a4182eeaa62aae3165f
EXPECTED_DL=de180d0253fdc01c483c9445b433507d379d4fa7b0492edc0d92e6f48c3a6c37
[ -f "$DMG" ] || { echo 'HP disk image not found.' >&2; exit 1; }
echo 'Checking the original HP download (this may take a moment)...'
ACTUAL=$(shasum -a 256 "$DMG" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED_DMG" ] || { echo 'Unrecognised HP download. Expected HP 5.1.1 HewlettPackardPrinterDrivers.dmg; no firmware imported.' >&2; exit 1; }
shasum -a 256 -c Checksums.sha256
STAGE=$(mktemp -d /private/tmp/hp-p1008-firmware.XXXXXX)
MOUNT="$STAGE/mount"
mkdir "$MOUNT"
cleanup() {
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
echo 'Extracting firmware only. Allow approximately 2 GB of temporary disk space.'
pkgutil --expand-full "$MOUNT/HewlettPackardPrinterDrivers.pkg" "$STAGE/expanded"
ACL="$STAGE/expanded/HewlettPackardPrinterDrivers.pkg/Payload/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/Resources/HP1006.acl"
[ -f "$ACL" ] || { echo 'Expected HP1006.acl missing.' >&2; exit 1; }
[ "$(shasum -a 256 "$ACL" | awk '{print $1}')" = "$EXPECTED_ACL" ] || { echo 'Firmware source checksum mismatch.' >&2; exit 1; }
./payload/arm2hpdl "$ACL" > "$STAGE/HP1006.dl"
[ "$(shasum -a 256 "$STAGE/HP1006.dl" | awk '{print $1}')" = "$EXPECTED_DL" ] || { echo 'Converted firmware checksum mismatch.' >&2; exit 1; }
install -m 644 "$STAGE/HP1006.dl" payload/HP1006.dl
echo 'Firmware prepared locally. No printer was contacted or changed.'
