#!/bin/zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
timestamp=$(date +%Y%m%d-%H%M%S)

if ! command -v brew >/dev/null 2>&1; then
  print "未检测到 Homebrew。请先安装 Homebrew 后再运行。" >&2
  exit 1
fi

brew install --cask hammerspoon karabiner-elements

mkdir -p "$HOME/.hammerspoon"
mkdir -p "$HOME/.config/karabiner/assets/complex_modifications"

if [[ -f "$HOME/.hammerspoon/init.lua" ]]; then
  cp "$HOME/.hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua.backup-$timestamp"
fi

if [[ -f "$HOME/.config/karabiner/karabiner.json" ]]; then
  cp "$HOME/.config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json.backup-$timestamp"
fi

cp "$repo_dir/hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua"
cp "$repo_dir/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
cp "$repo_dir/karabiner/assets/complex_modifications/current-screen-app-switcher.json" "$HOME/.config/karabiner/assets/complex_modifications/current-screen-app-switcher.json"

open -a "Hammerspoon" || true
open -a "Karabiner-Elements" || true

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload(); return "reloading"' >/dev/null 2>&1 || true
fi

if [[ -x "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" ]]; then
  "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" --select-profile "Default profile" >/dev/null 2>&1 || true
fi

print "安装完成。请在系统设置中给 Hammerspoon 和 Karabiner-Elements 授权辅助功能/输入监控。"
