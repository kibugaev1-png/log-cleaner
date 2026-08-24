#!/bin/bash
# Запускает тесты на песочнице (без Xcode). Не трогает реальные логи.
set -e
cd "$(dirname "$0")"
SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk 2>/dev/null | sort -V | tail -1)
[ -z "$SDK" ] && SDK=$(xcrun --show-sdk-path)
mkdir -p build
swiftc \
    Sources/ChistkaLogov/LogModels.swift \
    Sources/ChistkaLogov/LogScanner.swift \
    Sources/ChistkaLogov/LogDeleter.swift \
    Sources/ChistkaLogov/IPService.swift \
    Sources/ChistkaLogov/SpeedTester.swift \
    Sources/ChistkaLogov/SecurityInspector.swift \
    Tests/main.swift \
    -o build/sandbox_test -sdk "$SDK" -target arm64-apple-macos13.0
./build/sandbox_test
