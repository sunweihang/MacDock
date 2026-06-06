#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_DIR="$ROOT/.signing"
CERT_CN="MacTools RightDock"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
  echo "签名证书已存在: $CERT_CN"
  security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_CN"
  exit 0
fi

mkdir -p "$SIGN_DIR"

if [[ ! -f "$SIGN_DIR/cert.pem" ]]; then
  echo "生成本地代码签名证书（仅需一次）…"
  cat > "$SIGN_DIR/openssl.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no

[dn]
CN=${CERT_CN}
O=MacTools

[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:FALSE
EOF
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$SIGN_DIR/key.pem" \
    -out "$SIGN_DIR/cert.pem" \
    -days 8250 -nodes \
    -config "$SIGN_DIR/openssl.cnf" \
    -extensions ext
  openssl pkcs12 -export -legacy \
    -out "$SIGN_DIR/RightDock.p12" \
    -inkey "$SIGN_DIR/key.pem" \
    -in "$SIGN_DIR/cert.pem" \
    -passout pass:rightdock
fi

echo "导入钥匙串…"
security import "$SIGN_DIR/RightDock.p12" -P rightdock \
  -T /usr/bin/codesign -T /usr/bin/security -A 2>/dev/null \
  || security import "$SIGN_DIR/RightDock.p12" -P rightdock \
  -T /usr/bin/codesign -T /usr/bin/security

echo ""
echo "════════════════════════════════════════════════════════"
echo "  请完成最后一步（只需做一次）："
echo "  1. 打开「钥匙串访问」"
echo "  2. 左侧选「登录」→ 分类选「我的证书」"
echo "  3. 找到「${CERT_CN}」，双击"
echo "  4. 展开「信任」→「使用此证书时」选「始终信任」"
echo "  5. 关闭窗口并输入密码确认"
echo "  6. 再执行: ./scripts/install.sh"
echo "════════════════════════════════════════════════════════"
