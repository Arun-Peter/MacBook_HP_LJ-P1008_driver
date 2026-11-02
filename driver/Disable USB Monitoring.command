#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec /bin/sh ./disable-usb-monitoring.sh
