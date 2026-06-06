#!/bin/zsh
# RightDock 退出后恢复系统程序坞（可独立运行；应用退出时也会 detached 调用）
set -euo pipefail

/usr/bin/python3 <<'PY'
import json
import plistlib
import subprocess
from pathlib import Path

def run(cmd: str) -> None:
    subprocess.run(cmd, shell=True, check=False)

plist = Path.home() / "Library/Preferences/com.mactools.RightDock.plist"
orientation = "bottom"
tilesize = 64
largesize = 128
delay = 0.5
modifier = 0.5

if plist.exists():
    try:
        data = plistlib.load(plist.open("rb"))
        raw = data.get("systemDockPreferencesBackupV2")
        if isinstance(raw, bytes):
            backup = json.loads(raw.decode())
            orientation = backup.get("orientation", "bottom")
            if orientation == "right":
                orientation = "bottom"
            tilesize = int(backup.get("tilesize", 64))
            largesize = int(backup.get("largesize") or 128)
            delay = float(backup.get("autohideDelay", 0.5))
            modifier = float(backup.get("autohideTimeModifier", 0.5))
    except Exception:
        pass

# 退出后始终显示程序坞，避免 autohide 导致「看不到」
run(f"/usr/bin/defaults write com.apple.dock orientation -string {orientation}")
run("/usr/bin/defaults write com.apple.dock autohide -bool false")
run(f"/usr/bin/defaults write com.apple.dock autohide-delay -float {delay}")
run(f"/usr/bin/defaults write com.apple.dock autohide-time-modifier -float {modifier}")
run(f"/usr/bin/defaults write com.apple.dock tilesize -int {tilesize}")
run(f"/usr/bin/defaults write com.apple.dock largesize -int {largesize}")
run("/usr/bin/defaults write com.apple.dock magnification -bool true")
for corner in ("wvous-br-corner", "wvous-bl-corner", "wvous-tr-corner", "wvous-tl-corner"):
    run(f"/usr/bin/defaults delete com.apple.dock {corner} 2>/dev/null || true")
run("/usr/bin/killall Dock 2>/dev/null || true")
run("/usr/bin/defaults delete com.mactools.RightDock systemDockPreferencesBackupV2 2>/dev/null || true")
run("/usr/bin/defaults delete com.mactools.RightDock systemDockPreferencesBackup 2>/dev/null || true")
PY
