#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="RightDock"
APP_DIR="$ROOT/${APP_NAME}.app"

cd "$ROOT"
echo "编译 ${APP_NAME}…"
swift build -c release

echo "打包 ${APP_NAME}.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

"$ROOT/scripts/codesign-app.sh" "$APP_DIR"

echo "完成: $APP_DIR"
echo "安装: ./scripts/install.sh"
