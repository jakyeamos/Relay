#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/.build/release"
APP_ROOT="$PROJECT_ROOT/Relay.app"

cd "$PROJECT_ROOT"
swift build -c release --product RelayApp
swift build -c release --product RelayHelper

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp "$BUILD_ROOT/RelayApp" "$APP_ROOT/Contents/MacOS/RelayApp"
cp "$BUILD_ROOT/RelayHelper" "$APP_ROOT/Contents/MacOS/RelayHelper"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_ROOT/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/com.relay.helper.plist" "$APP_ROOT/Contents/Resources/com.relay.helper.plist"
chmod +x "$APP_ROOT/Contents/MacOS/RelayApp" "$APP_ROOT/Contents/MacOS/RelayHelper"

echo "Built $APP_ROOT"
