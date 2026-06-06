#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift "$ROOT/scripts/generate-user-guide-pdf.swift" "$ROOT"
echo "已生成: $ROOT/docs/RightDock-使用指南.pdf"
