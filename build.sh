#!/usr/bin/env bash
set -euo pipefail

APP_NAME="StayAwake"
APP_BUNDLE="${APP_NAME}.app"

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

swiftc -O "src/main.swift" -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
codesign --force --sign - "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE} successfully."
