#!/bin/zsh
# Compile le squelette et pose le bundle .app dans .build/. Ne l'installe pas — voir install.sh.
set -e
here=${0:a:h}
app="$here/.build/Bubulle.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -swift-version 5 -O \
  -o "$app/Contents/MacOS/Bubulle" \
  "$here"/Sources/*.swift

cp "$here/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$here/Resources/flags.json" "$app/Contents/Resources/flags.json"
cp -R "$here/Resources/Flags" "$app/Contents/Resources/Flags"
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --deep -s - "$app"

echo "Construit : $app"
