#!/bin/sh
# Install a per-user, non-root USB event monitor. No printing/firmware changes.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
cd "$(dirname "$0")"
[ "$(id -u)" -ne 0 ] || { echo 'Run as your normal Mac user, without sudo.' >&2; exit 1; }
URI=$(lpstat -v HP_LaserJet_P1008 | /usr/bin/awk '{print $4}')
case "$URI" in hpp1008://Hewlett-Packard/HP%20LaserJet%20P1008?serial=*) ;; *) echo 'P1008 custom USB queue not found.' >&2; exit 1 ;; esac
SERIAL=${URI##*serial=}
case "$SERIAL" in ''|*[!a-zA-Z0-9._-]*) echo 'Unexpected USB serial format.' >&2; exit 1 ;; esac
LABEL=com.codex.hp-p1008-usb-status
DEST="$HOME/Library/Application Support/HP-P1008"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$DEST" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
shasum -a 256 -c Checksums.sha256
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
install -m 755 payload/usb-status "$DEST/usb-status"
cp disable-usb-monitoring.sh "$DEST/disable-usb-monitoring.sh"
chmod 755 "$DEST/disable-usb-monitoring.sh"
rm -f "$PLIST"
PB=/usr/libexec/PlistBuddy
"$PB" -c 'Clear dict' "$PLIST" >/dev/null
"$PB" -c "Add :Label string $LABEL" "$PLIST"
"$PB" -c 'Add :ProgramArguments array' "$PLIST"
"$PB" -c "Add :ProgramArguments:0 string '$DEST/usb-status'" "$PLIST"
"$PB" -c 'Add :ProgramArguments:1 string --serial' "$PLIST"
"$PB" -c "Add :ProgramArguments:2 string $SERIAL" "$PLIST"
"$PB" -c 'Add :RunAtLoad bool true' "$PLIST"
"$PB" -c 'Add :KeepAlive bool true' "$PLIST"
"$PB" -c 'Add :ThrottleInterval integer 30' "$PLIST"
"$PB" -c 'Add :ProcessType string Background' "$PLIST"
"$PB" -c 'Add :Nice integer 10' "$PLIST"
"$PB" -c 'Add :LowPriorityIO bool true' "$PLIST"
"$PB" -c "Add :StandardErrorPath string '$HOME/Library/Logs/HP-P1008-USB-status.log'" "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Enabled P1008 USB monitoring for the current user. Serial: $SERIAL"
