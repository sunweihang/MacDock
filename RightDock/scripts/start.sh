#!/bin/zsh
# 优先用已打包的 .app（无终端窗口）；没有则临时 open 编译产物。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/RightDock.app"
INSTALLED="/Applications/RightDock.app"

pkill -x RightDock 2>/dev/null || true
sleep 0.2

if [[ -d "$INSTALLED" ]]; then
  open -a "$INSTALLED"
elif [[ -d "$APP" ]]; then
  open "$APP"
else
  "$ROOT/scripts/build-app.sh" >/dev/null
  open "$APP"
fi
