#!/bin/bash
# Собирает "Чистка логов.app" без Xcode: swiftc напрямую (SwiftPM в CLT сломан),
# упаковка бандла вручную + ad-hoc подпись.
set -e
cd "$(dirname "$0")"

APP_NAME="Чистка логов"
BIN_NAME="ChistkaLogov"
BUNDLE_ID="school.wai.chistkalogov"

# Компилятор в Command Line Tools (6.1.2) не дружит с новым SDK 26.x,
# поэтому явно берём последний доступный macOS 15 SDK.
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk 2>/dev/null | sort -V | tail -1)
if [ -z "$SDK" ]; then
    echo "Не найден macOS 15 SDK, использую SDK по умолчанию"
    SDK=$(xcrun --show-sdk-path)
fi
echo "==> SDK: $SDK"

echo "==> Компиляция (swiftc)"
mkdir -p build
SRC=$(find Sources/ChistkaLogov -name '*.swift')
swiftc $SRC -o "build/$BIN_NAME" -O \
    -sdk "$SDK" -target arm64-apple-macos13.0 -parse-as-library

APP_DIR="build/$APP_NAME.app"
echo "==> Сборка бандла $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "build/$BIN_NAME" "$APP_DIR/Contents/MacOS/$BIN_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSFaceIDUsageDescription</key><string>Подтвердите, что это ваш компьютер</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc подпись"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Готово: $APP_DIR"
