#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="RightDock"
SOURCE="$ROOT/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

# 尝试创建本地签名证书（避免每次编译后辅助功能失效）
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "MacTools RightDock"; then
  if [[ ! -f "$ROOT/.signing/RightDock.p12" ]]; then
    echo "首次安装：创建本地签名证书…"
    "$ROOT/scripts/create-signing-cert.sh" || true
    echo ""
    echo "若提示设置钥匙串信任，完成后请再运行: ./scripts/install.sh"
    echo "（本次将先用临时签名继续安装）"
    echo ""
  fi
fi

"$ROOT/scripts/build-app.sh"

echo "结束所有 ${APP_NAME} 进程…"
pkill -x RightDock 2>/dev/null || true
sleep 0.3

echo "安装到 ${DEST}…"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"
"$ROOT/scripts/codesign-app.sh" "$DEST"

echo "启动 ${APP_NAME}…"
open -a "$DEST"
sleep 1

echo ""
echo "════════════════════════════════════════════════════════"
echo "  授权辅助功能（稳定签名后一般只需做一次）："
echo "  1. 系统设置 → 隐私与安全性 → 辅助功能"
echo "  2. 若已有 RightDock：先点「-」删除"
echo "  3. 点「+」添加: ${DEST}"
echo "  4. 打开开关"
echo "  5. 菜单栏 Dock 应显示「辅助功能已生效 ✓」"
echo ""
echo "  若仍显示未生效，在终端执行后重复 2-4 步："
echo "    sudo tccutil reset Accessibility com.mactools.RightDock"
echo "════════════════════════════════════════════════════════"
