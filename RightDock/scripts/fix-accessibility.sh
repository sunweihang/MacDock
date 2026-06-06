#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/RightDock.app"

echo "▶ 结束 RightDock…"
pkill -x RightDock 2>/dev/null || true
sleep 0.5

echo "▶ 编译并安装…"
"$ROOT/scripts/build-app.sh"
rm -rf "$DEST"
ditto "$ROOT/RightDock.app" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
"$ROOT/scripts/codesign-app.sh" "$DEST"

echo "▶ 清除本次授权尝试标记（会重新弹出系统授权框）…"
defaults delete com.mactools.RightDock accessibilityPromptAttempted 2>/dev/null || true

echo "▶ 打开「辅助功能」系统设置…"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null \
  || open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo "▶ 启动 RightDock（将弹出授权对话框，请点「打开系统设置」并勾选 RightDock）…"
open -a "$DEST"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  请在屏幕上完成："
echo "  1. 若弹出「RightDock 想使用辅助功能」→ 点「打开系统设置」"
echo "  2. 在辅助功能列表：有 RightDock 先点 − 删除"
echo "  3. 点 + 选择: ${DEST}"
echo "  4. 打开 RightDock 开关"
echo "  5. 菜单栏 Dock 应显示「辅助功能已生效 ✓」"
echo "════════════════════════════════════════════════════════"
