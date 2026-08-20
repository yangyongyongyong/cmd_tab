# cmd_tab — 当前屏幕内 Cmd+Tab 应用切换器

这个项目用 Karabiner-Elements + Hammerspoon 替换 macOS 原生 `Cmd+Tab` 行为，让应用切换限定在当前屏幕内。

原生 macOS 的 `Cmd+Tab` 是全局 App MRU 列表。多屏场景下，如果上一个 App 在另一个屏幕，切换会直接跳到另一个屏幕。本项目的目标是让 `Cmd+Tab` 更符合多屏工作流：在哪个屏幕工作，就优先在这个屏幕内切换 App。

## 当前行为

- `Cmd+Tab`：打开当前屏幕 App 切换器，并选中下一个 App。
- 按住 `Cmd` 连续按 `Tab`：继续向更老的 App 移动。
- `Cmd+Shift+Tab`：反向移动。
- 松开 `Cmd`：切到当前选中的 App。
- `Esc`：取消本次切换。
- `Return`：确认当前选中项。
- 鼠标点击悬浮框里的 App 图标：直接切到对应 App。
- 鼠标悬停到当前屏幕行的 App 图标块：先选中该 App，松开 `Cmd` 后切过去。
- 面板打开时按 `1-9`：直接切到当前可见区域中对应编号的 App。
- 如果其他屏幕也有 App，悬浮面板会按屏幕分多行展示。
- 键盘切换仍只在当前屏幕行内循环，鼠标点击其他屏幕行的 App 才会跨屏切换。
- 如果某个 App 在所在屏幕有多个窗口，图标右上角会显示 `2窗`、`3窗` 这类角标。
- 确认多窗口 App 时会自动进入第二层窗口选择，而不是立刻切到代表窗口。
- 窗口选择层里 `Tab` / `Shift+Tab` 或 `↑/↓` 选择窗口，`Enter` 确认，`Esc` 返回 App 选择层。
- 通过切换器聚焦的窗口会自动铺满当前屏幕可用区域，不进入 macOS 全屏，也不遮住菜单栏和 Dock。
- 右键 App 图标：打开管理菜单，支持隐藏 App、关闭当前窗口、退出 App、取消。
- 按住 `Option` 右键 App 图标：菜单额外显示强制退出。
- 左键拖动 App 图标到其他屏幕行：把该 App 的代表窗口移动到目标屏幕。
- 拖动时 App ghost 会跟随鼠标，目标屏幕行会高亮；释放在原屏幕行或空白处会取消移动。

# 安装

```bash
git clone https://github.com/yangyongyongyong/cmd_tab.git
cd cmd_tab
./scripts/install.sh
```

安装脚本会：

- 安装 `hammerspoon` 和 `karabiner-elements`。
- 备份现有 `~/.hammerspoon/init.lua` 和 `~/.config/karabiner/karabiner.json`。
- 写入本项目的 Hammerspoon 和 Karabiner 配置。
- 打开 Hammerspoon 和 Karabiner-Elements。

首次安装后，需要在系统设置里授权：

- 给 Hammerspoon 开启辅助功能权限。
- 如果 `Cmd` 释放无法被监听，给 Hammerspoon 开启输入监控权限。
- 给 Karabiner-Elements 按提示开启所需权限。

## 文件结构

```text
cmd_tab/
  hammerspoon/init.lua
  karabiner/karabiner.json
  karabiner/assets/complex_modifications/current-screen-app-switcher.json
  scripts/install.sh
  scripts/disable-current-screen-switcher.sh
  AGENT_PROMPT.md
  README.md
```

## 关键实现点

- Karabiner 把 `Cmd+Tab` 转成 `Cmd+F18`。
- Karabiner 把 `Cmd+Shift+Tab` 转成 `Cmd+Shift+F19`。
- Hammerspoon 监听 `F18/F19`，只枚举当前屏幕的标准可见窗口。
- 每个 App 只保留当前屏幕上最靠前的一个窗口，因此语义接近原生 App 切换，而不是窗口切换。
- Hammerspoon 监听窗口聚焦事件，为每个屏幕维护独立 App MRU 顺序。
- 第一次触发时冻结候选列表，避免系统 MRU 重排导致只能在最近两个 App 之间来回跳。
- Hammerspoon 使用 `flagsChanged` 监听 `Cmd` 释放，不使用定时器轮询。
- `eventtap` 和 `hotkey` 对象挂在全局表上，避免被 Lua GC 回收。
- F18/F19 热键不绑定 repeat 回调，避免 Karabiner 虚拟键状态异常时自动循环选择。
- App 选择层有释放看门狗兜底，防止 `Cmd` 释放事件丢失后面板残留。
- App 图标会缓存并后台预热，候选列表按屏幕单次扫描构建，减少打开面板时的延迟。
- 悬浮面板使用 `hs.canvas` 绘制，按屏幕分多行展示候选 App。
- 当前屏幕行显示 `1-9` 编号，用于键盘直达。
- 所有屏幕行都支持鼠标点击，点击其他屏幕的 App 会直接跨屏聚焦。
- App 候选项会保存同 App、同屏幕的窗口列表，并以窗口数量角标提示可展开。
- `focusWindow` 会在聚焦后调用 `window:setFrame(window:screen():frame(), 0)`，让窗口铺满可用区域。
- 第二层窗口选择只显示窗口标题，不抓取窗口内容缩略图，避免引入屏幕录制权限和性能问题。
- App 图标右键使用自绘 `hs.canvas` 菜单，不直接执行退出，避免误操作。
- App 图标左键拖动超过阈值后进入移动模式，拖到其他屏幕行会移动代表窗口。
- 拖拽模式会显示独立半透明 `hs.canvas` ghost，并保持鼠标按下时在图标块内的相对位置，避免 ghost 从鼠标右下角突兀出现。
- 自动铺满开启时，拖动到目标屏幕后窗口铺满目标屏幕可用区域；关闭时按相对位置和尺寸映射。

## 当前屏幕定义

默认使用当前焦点窗口所在屏幕。如果想改成鼠标在哪个屏幕就切哪个屏幕，修改 `hammerspoon/init.lua` 第一行：

```lua
local preferMouseScreen = true
```

## 验证

```bash
luac -p ~/.hammerspoon/init.lua
jq empty ~/.config/karabiner/karabiner.json
hs -c 'local s=currentScreenSwitcherStatus(); return tostring(s.eventTapEnabled), tostring(s.active), tostring(s.candidates)'
```

## 回滚

```bash
./scripts/disable-current-screen-switcher.sh
```

回滚脚本会把当前 Hammerspoon 和 Karabiner 配置改名备份，并退出相关 App。重新打开 Karabiner-Elements 后，`Cmd+Tab` 会恢复系统默认行为。

## 安全性

这套方案是用户态配置，不修改 macOS 系统文件，不参与登录前流程。最坏情况通常是 `Cmd+Tab` 不好用、悬浮层卡住、或者 Hammerspoon 报错退出，不会导致重启后无法进入桌面。
