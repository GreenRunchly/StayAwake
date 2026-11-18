#!/usr/bin/env bash
set -euo pipefail

APP_NAME="StayAwake"
APP_BUNDLE="${APP_NAME}.app"

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
if [ -d "resources/DisableTurboBoost.64bits.kext" ]; then
    cp -R "resources/DisableTurboBoost.64bits.kext" "${APP_BUNDLE}/Contents/Resources/"
fi

swiftc -O -target x86_64-apple-macosx12.0 "src/main.swift" -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_x86_64"
swiftc -O -target arm64-apple-macosx12.0 "src/main.swift" -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_arm64"
lipo -create "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_x86_64" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_arm64" -output "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
rm "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_x86_64" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}_arm64"
codesign --force --sign - "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE} successfully."
