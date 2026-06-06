#!/bin/zsh
set -euo pipefail

APP_DIR="${1:?用法: codesign-app.sh /path/to/RightDock.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Resources/RightDock.entitlements"
CERT_CN="MacTools RightDock"

identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "$CERT_CN" \
    | head -1 \
    | sed -n 's/.*"\(.*\)"/\1/p'
}

xattr -cr "$APP_DIR" 2>/dev/null || true

if ID="$(identity)" && [[ -n "$ID" ]]; then
  echo "使用稳定签名: $ID"
  codesign --force --deep --sign "$ID" \
    --entitlements "$ENTITLEMENTS" \
    --identifier com.mactools.RightDock \
    --timestamp=none \
    "$APP_DIR"
else
  echo "未找到「${CERT_CN}」证书，使用 ad-hoc 签名（每次重装都需在辅助功能里重新添加）"
  echo "建议先运行: ./scripts/create-signing-cert.sh"
  codesign --force --deep --sign - \
    --identifier com.mactools.RightDock \
    --timestamp=none \
    "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
echo "签名完成"
