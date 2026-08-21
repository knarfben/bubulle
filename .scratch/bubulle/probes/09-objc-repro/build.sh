#!/bin/zsh
# PROTOTYPE JETABLE — build de la sonde ObjC de reproduction (ticket 09).
set -e
here=${0:a:h}
app="$here/.build/BubulleObjCRepro.app"

/bin/rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

clang -fobjc-arc -fmodules -framework Cocoa -framework InputMethodKit \
  -o "$app/Contents/MacOS/BubulleObjCRepro" \
  "$here/main.m" "$here/BubulleController.m"

cp "$here/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --deep -s - "$app"
echo "Construit : $app"
