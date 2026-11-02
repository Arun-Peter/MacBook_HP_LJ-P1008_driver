#!/bin/sh
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo, or use Install.command.' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo 'This build requires Apple Silicon.' >&2; exit 1; }
shasum -a 256 -c Checksums.sha256
[ -f payload/HP1006.dl ] || { echo 'Run prepare-firmware.sh first; see README.md.' >&2; exit 1; }
[ "$(shasum -a 256 payload/HP1006.dl | awk '{print $1}')" = de180d0253fdc01c483c9445b433507d379d4fa7b0492edc0d92e6f48c3a6c37 ] || { echo 'Firmware checksum mismatch.' >&2; exit 1; }
URI=$(/usr/libexec/cups/backend/usb | awk '$1 == "direct" && /"HP LaserJet P1008"/ && /MDL:HP LaserJet P1008;/ {print $2; n++} END {if (n != 1) exit 1}') || { echo 'Connect exactly one powered-on HP LaserJet P1008 and retry.' >&2; exit 1; }
case "$URI" in usb://Hewlett-Packard/HP%20LaserJet%20P1008?serial=*) ;; *) echo 'Unexpected P1008 USB identity.' >&2; exit 1 ;; esac
EXISTING=$(lpstat -v HP_LaserJet_P1008 2>/dev/null | awk '{print $4}')
case "$EXISTING" in ''|"hpp1008:${URI#usb:}") ;; *) echo 'Queue HP_LaserJet_P1008 already belongs to another device. No changes made.' >&2; exit 1 ;; esac
[ -z "$(lpstat -W not-completed -o HP_LaserJet_P1008 2>/dev/null)" ] || { echo 'Finish/cancel existing P1008 jobs before reinstalling.' >&2; exit 1; }
cupstestppd -I filters payload/HP-LaserJet_P1008.ppd
DEST=/Library/Printers/HP-P1008
install -d -o root -g wheel -m 755 "$DEST" /Library/Printers/PPDs/Contents/Resources
install -o root -g wheel -m 755 payload/rastertoxqx "$DEST/rastertoxqx"
install -o root -g wheel -m 644 payload/HP1006.dl "$DEST/HP1006.dl"
install -o root -g wheel -m 644 payload/HP-LaserJet_P1008.ppd "$DEST/HP-LaserJet_P1008.ppd"
install -o root -g wheel -m 644 payload/HP-LaserJet_P1008.ppd /Library/Printers/PPDs/Contents/Resources/HP-LaserJet_P1008_Native.ppd
install -o root -g wheel -m 700 payload/hpp1008 /usr/libexec/cups/backend/hpp1008
lpadmin -p HP_LaserJet_P1008 -E -v "hpp1008:${URI#usb:}" -P "$DEST/HP-LaserJet_P1008.ppd" -D 'HP LaserJet P1008' -L 'USB' -o printer-is-shared=false -o PageSize=A4
echo 'Installed HP LaserJet P1008. Other queues and the default printer were preserved.'
