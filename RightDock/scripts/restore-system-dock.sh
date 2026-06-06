#!/bin/zsh
# 紧急恢复：RightDock 退出后系统程序坞卡在右侧细条时使用
set -e
echo "正在将系统程序坞恢复到底部…"
defaults write com.apple.dock orientation -string bottom
defaults write com.apple.dock autohide -bool false
defaults write com.apple.dock autohide-delay -float 0.5
defaults write com.apple.dock autohide-time-modifier -float 0.5
defaults write com.apple.dock tilesize -int 64
defaults write com.apple.dock largesize -int 128
defaults delete com.apple.dock wvous-br-corner 2>/dev/null || true
defaults delete com.apple.dock wvous-bl-corner 2>/dev/null || true
defaults delete com.apple.dock wvous-tr-corner 2>/dev/null || true
defaults delete com.apple.dock wvous-tl-corner 2>/dev/null || true
killall Dock 2>/dev/null || true
defaults delete com.mactools.RightDock systemDockPreferencesBackupV2 2>/dev/null || true
defaults delete com.mactools.RightDock systemDockPreferencesBackup 2>/dev/null || true
echo "完成。程序坞应已回到底部。"
