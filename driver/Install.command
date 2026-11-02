#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$BASE"
if [ ! -f payload/HP1006.dl ]; then
    echo 'Select HewlettPackardPrinterDrivers.dmg downloaded from Apple/HP. See README.md.'
    DMG=$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "Select the HP 5.1.1 HewlettPackardPrinterDrivers.dmg download")')
    ./prepare-firmware.sh "$DMG"
fi
echo 'The installed backend loads HP firmware into the P1008 RAM when printing after power-on.'
printf 'Type INSTALL to approve driver installation and on-demand firmware loading: '
read -r ANSWER
[ "$ANSWER" = INSTALL ] || { echo 'Cancelled.'; exit 1; }
STAGE=$(/usr/bin/mktemp -d /private/tmp/hp-p1008-install.XXXXXX)
trap '/bin/rm -rf "$STAGE"' EXIT
trap 'exit 130' INT TERM HUP
/usr/bin/ditto "$BASE/payload" "$STAGE/payload"
/bin/cp "$BASE/install.sh" "$BASE/Checksums.sha256" "$STAGE/"
/usr/bin/osascript - "$STAGE/install.sh" <<'APPLESCRIPT'
on run argv
    return do shell script "/bin/sh " & quoted form of (item 1 of argv) with administrator privileges
end run
APPLESCRIPT
echo 'Installation complete. Select HP LaserJet P1008 when printing.'
