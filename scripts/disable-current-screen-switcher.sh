#!/bin/zsh
set -euo pipefail

timestamp=$(date +%Y%m%d-%H%M%S)

if [[ -f "$HOME/.config/karabiner/karabiner.json" ]]; then
  mv "$HOME/.config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json.disabled-$timestamp"
fi

if [[ -f "$HOME/.hammerspoon/init.lua" ]]; then
  mv "$HOME/.hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua.disabled-$timestamp"
fi

osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Karabiner-Elements" to quit' >/dev/null 2>&1 || true

print "当前屏幕切换器配置已停用。重新打开 Karabiner-Elements 后 Cmd+Tab 会恢复系统默认行为。"
