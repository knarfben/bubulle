#!/bin/zsh
# PROTOTYPE JETABLE — compile et lance le clone visuel du HUD.
set -e
here=${0:a:h}
out=${TMPDIR:-/tmp}/bubulle-proto
swiftc -swift-version 5 -O -o "$out" "$here/BubulleProto.swift"
exec "$out"
