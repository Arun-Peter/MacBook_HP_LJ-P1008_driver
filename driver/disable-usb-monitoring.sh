#!/bin/sh
set -eu
LABEL=com.codex.hp-p1008-usb-status
DEST="$HOME/Library/Application Support/HP-P1008"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERIAL=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$PLIST" 2>/dev/null || true)
/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ -n "$SERIAL" ] && [ -x "$DEST/usb-status" ]; then
    "$DEST/usb-status" --serial "$SERIAL" --clear
fi
/bin/rm -f "$PLIST" "$DEST/usb-status"
# Leave this removal script and the small status log for troubleshooting.
echo 'P1008 USB monitoring disabled. Printer driver and queue retained.'
