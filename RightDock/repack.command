#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "════════════════════════════════════════════════════════"
echo "  RightDock 重新打包并安装"
echo "  目录: $ROOT"
echo "════════════════════════════════════════════════════════"
echo ""

"$ROOT/scripts/install.sh"

echo ""
echo "完成。按回车关闭此窗口…"
read -r _
