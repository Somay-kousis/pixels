#!/bin/sh
# Builds Pixels.app next to this script.
set -e
cd "$(dirname "$0")"
APP=Pixels.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/*.gif "$APP/Contents/Resources/"
swiftc -O -o "$APP/Contents/MacOS/Pixels" Pixels.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Pixels</string>
  <key>CFBundleIdentifier</key><string>local.somay.pixels</string>
  <key>CFBundleExecutable</key><string>Pixels</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
