#!/bin/sh
# Developer/offline test only; sends no printer jobs and changes no queues.
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
STAGE=$(mktemp -d /private/tmp/hp-p1008-tests.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 130' INT TERM HUP
clang -arch arm64 -O1 -g -fsanitize=address,undefined -o "$STAGE/filter" src/rastertoxqx.c src/jbig.c src/jbig_ar.c -Isrc -lcups -lcupsimage
clang -O2 -o "$STAGE/fixture" tests/raster-fixture.c -lcupsimage
# The PJL job header contains the current second. Compare the complete output
# after normalising only that timestamp, not the compressed image bytes.
normalise() { /usr/bin/perl -pe 's/JobAttr4=[0-9]{14}/JobAttr4=00000000000000/' "$1" > "$2"; }
for cs in 0 3; do
    for bits in 1 8; do
        "$STAGE/fixture" "$STAGE/$cs-$bits.ras" "$cs" "$bits" 0
        "$STAGE/filter" 1 test offline 1 '' "$STAGE/$cs-$bits.ras" > "$STAGE/raw.xqx"
        normalise "$STAGE/raw.xqx" "$STAGE/$cs-$bits.xqx"
        "$ROOT/payload/rastertoxqx" 1 test offline 1 '' "$STAGE/$cs-$bits.ras" > "$STAGE/raw.xqx"
        normalise "$STAGE/raw.xqx" "$STAGE/release.xqx"
        cmp "$STAGE/$cs-$bits.xqx" "$STAGE/release.xqx"
        cmp "$STAGE/0-1.xqx" "$STAGE/$cs-$bits.xqx"
    done
done
"$STAGE/fixture" "$STAGE/truncated.ras" 3 1 1
if "$STAGE/filter" 1 test offline 1 '' "$STAGE/truncated.ras" > "$STAGE/truncated.xqx"; then
    echo 'FAIL: truncated raster accepted' >&2; exit 1
fi
./payload/usb-status --self-test
cupstestppd -I filters payload/HP-LaserJet_P1008.ppd
shasum -a 256 -c Checksums.sha256
echo 'PASS: release/sanitized output matches for four raster formats; short input rejected.'
