#!/bin/sh
# Optional developer rebuild. Release users already have these executables.
set -eu
cd "$(dirname "$0")"
mkdir -p payload
# GitHub web uploads do not retain executable file modes.
chmod +x ./*.sh ./*.command payload/hpp1008 tests/smoke.sh
clang -arch arm64 -O2 -Wall -o payload/rastertoxqx src/rastertoxqx.c src/jbig.c src/jbig_ar.c -Isrc -lcups -lcupsimage
clang -arch arm64 -O2 -Wall -o payload/usb-status src/usb-status.c -framework IOKit -framework CoreFoundation -lcups
clang -arch arm64 -O2 -Wall -o payload/arm2hpdl src/arm2hpdl.c
for binary in rastertoxqx usb-status arm2hpdl; do codesign --force --sign - "payload/$binary"; done
./payload/usb-status --self-test
cupstestppd -I filters payload/HP-LaserJet_P1008.ppd
# HP1006.dl, if imported locally, must never enter a public release manifest.
shasum -a 256 payload/rastertoxqx payload/usb-status payload/arm2hpdl payload/hpp1008 payload/HP-LaserJet_P1008.ppd > Checksums.sha256
