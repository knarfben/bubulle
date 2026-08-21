#!/bin/zsh
set -e
here=${0:a:h}
app="$here/.build/Probe11.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 5 -O -o "$app/Contents/MacOS/Probe11" "$here/probe.swift"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Probe11</string>
<key>CFBundleIdentifier</key><string>local.bubulle.probe11</string>
<key>CFBundleName</key><string>Probe11</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><false/>
</dict></plist>
PLIST
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force -s - "$app"
echo "OK $app"
