#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo.' >&2; exit 1; }
echo 'Disable USB monitoring as your normal user before running this script.'
URI=$(/usr/bin/lpstat -v HP_LaserJet_P1008 2>/dev/null | /usr/bin/awk '{print $4}')
case "$URI" in hpp1008://Hewlett-Packard/HP%20LaserJet%20P1008?serial=*) ;; *) echo 'Expected driver queue not found; nothing removed.' >&2; exit 1 ;; esac
[ -z "$(/usr/bin/lpstat -W not-completed -o HP_LaserJet_P1008)" ] || { echo 'Finish/cancel this printer\047s pending jobs first.' >&2; exit 1; }
/usr/sbin/lpadmin -x HP_LaserJet_P1008
/bin/rm -f /usr/libexec/cups/backend/hpp1008 /Library/Printers/PPDs/Contents/Resources/HP-LaserJet_P1008_Native.ppd
/bin/rm -f /Library/Printers/HP-P1008/rastertoxqx /Library/Printers/HP-P1008/HP1006.dl /Library/Printers/HP-P1008/HP-LaserJet_P1008.ppd
/bin/rmdir /Library/Printers/HP-P1008
