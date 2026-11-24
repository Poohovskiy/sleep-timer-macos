#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="SleepTimer.app"
rm -rf "$APP" AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1. Компіляція
swiftc -O SleepTimer.swift -o "$APP/Contents/MacOS/SleepTimer"

# 2. Іконка: icon.png -> AppIcon.icns
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d icon.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset

# 3. Info.plist
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Таймер сну</string>
    <key>CFBundleDisplayName</key><string>Таймер сну</string>
    <key>CFBundleIdentifier</key><string>local.sleeptimer</string>
    <key>CFBundleExecutable</key><string>SleepTimer</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
EOF

# 4. Підпис (без цього на Apple Silicon може не запуститись)
codesign --force --deep --sign - "$APP"

echo "Готово: $(pwd)/$APP"
