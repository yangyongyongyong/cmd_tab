# cmd_tab — 当前屏幕内 Cmd+Tab 应用切换器

这个项目用 Karabiner-Elements + Hammerspoon 替换 macOS 原生 `Cmd+Tab` 行为，让应用切换限定在当前屏幕内。

原生 macOS 的 `Cmd+Tab` 是全局 App MRU 列表。多屏场景下，如果上一个 App 在另一个屏幕，切换会直接跳到另一个屏幕。本项目的目标是让 `Cmd+Tab` 更符合多屏工作流：在哪个屏幕工作，就优先在这个屏幕内切换 App。

## 当前行为

- `Cmd+Tab`：打开当前屏幕 App 切换器，并选中下一个 App。
- 快速按下并释放 `Cmd+Tab`：直接切换，不绘制悬浮面板。
- 按住 `Cmd` 超过约 `0.3s`：才显示悬浮面板。
- 按住 `Cmd` 连续按 `Tab`：继续向更老的 App 移动。
- `Cmd+Shift+Tab`：反向移动。
- 松开 `Cmd`：切到当前选中的 App。
- `Esc`：取消本次切换；如果出现残留面板，也会强制清理。
- `Return`：确认当前选中项。
- `I`：面板打开时切换是否显示最小化窗口。
- 鼠标点击悬浮框里的 App 图标：直接切到对应 App。
- 鼠标悬停到当前屏幕行的 App 图标块：先选中该 App，松开 `Cmd` 后切过去。
- 面板打开时按 `1-9`：直接切到当前可见区域中对应编号的 App。
- 如果其他屏幕也有 App，悬浮面板会按屏幕分多行展示。
- 如果 macOS 显示器排列是上下堆叠，面板行顺序会按真实上下位置展示；左右排列时仍保持当前屏幕优先。
- 键盘切换仍只在当前屏幕行内循环，鼠标点击其他屏幕行的 App 或窗口 tile 才会跨屏切换。
- 所有屏幕行都会把多窗口 App 展开成多个窗口 tile，共用同一个 App 图标。
- 多窗口 tile 不显示 App 名，只显示窗口标题，最多两行；两行放不下时才省略。
- 默认只显示标准可见窗口；勾选底部“显示最小化窗口”或按 `I` 后，会把最小化窗口也纳入候选，并用“最小”角标标识。
- 通过切换器聚焦的窗口会自动铺满当前屏幕可用区域，不进入 macOS 全屏，也不遮住菜单栏和 Dock。
- 右键 App 图标：打开管理菜单，支持隐藏 App、关闭当前窗口、退出 App、取消。
- 按住 `Option` 右键 App 图标：菜单额外显示强制退出。
- 左键拖动 App 图标或窗口 tile 到其他屏幕行：把对应窗口移动到目标屏幕。
- 拖动时 App ghost 会跟随鼠标，目标屏幕行会高亮；释放在原屏幕行或空白处会取消移动。

## 安装

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
- Hammerspoon 监听 `F18/F19`，枚举各屏幕的标准可见窗口并按屏幕分组。
- 所有屏幕行都会按窗口展开多窗口 App，单窗口 App 仍以 App tile 展示。
- 展开后的窗口 tile 按每屏独立窗口 MRU 排序，不再把同 App 的多个窗口强行连续排在一起，保证最近两个不同 App/窗口能正常互相切换。
- Hammerspoon 监听窗口聚焦事件，为每个屏幕维护独立 App MRU 顺序。
- Hammerspoon 同时维护每个屏幕的窗口 MRU 顺序，避免 macOS 或 IDE 把同 App 多个窗口整体抬高后打乱 `Cmd+Tab` 的最近切换语义。
- 第一次触发时冻结候选列表，避免系统 MRU 重排导致只能在最近两个 App 之间来回跳。
- 悬浮面板延迟 `0.3s` 绘制，秒切时只更新候选和选中项，不创建 `hs.canvas`，减少体感卡顿。
- Hammerspoon 使用 `flagsChanged` 监听 `Cmd` 释放，不使用定时器轮询。
- `eventtap` 和 `hotkey` 对象挂在全局表上，避免被 Lua GC 回收。
- F18/F19 热键不绑定 repeat 回调，避免 Karabiner 虚拟键状态异常时自动循环选择。
- App 选择层有释放看门狗兜底，防止 `Cmd` 释放事件丢失后面板残留；如果内部状态已退出但 canvas 还在，watcher 会自动清理。
- App 图标会缓存并后台预热，候选列表按屏幕单次扫描构建，减少打开面板时的延迟。
- 悬浮面板使用 `hs.canvas` 绘制，按屏幕分多行展示候选项。
- 通过 `screen:fullFrame()` 判断 macOS 显示器排列；上下堆叠时按 `y` 坐标从上到下绘制屏幕行，左右排列时仍优先绘制当前屏幕行。
- 当前屏幕行显示 `1-9` 编号，用于键盘直达。
- 面板底部提供“自动铺满可用区域”和“显示最小化窗口”两个持久化勾选项，分别可用 `M` 和 `I` 切换。
- 所有屏幕行都支持鼠标点击，点击其他屏幕的 App 或窗口 tile 会直接跨屏聚焦。
- 所有屏幕候选项都会按窗口展开多窗口 App，便于鼠标精准命中目标窗口。
- 聚焦最小化窗口时会先自动恢复窗口，再执行聚焦和可选铺满。
- 某些 App 的最小化窗口不是标准窗口，例如 `AXDialog`，开启“显示最小化窗口”后也会纳入候选。
- `focusWindow` 会在聚焦后调用 `window:setFrame(window:screen():frame(), 0)`，让窗口铺满可用区域。
- 聚焦窗口时使用 `app:activate(false)`，避免把同一 App 在其他屏幕上的窗口一起抬到前台。
- App 图标右键使用自绘 `hs.canvas` 菜单，不直接执行退出，避免误操作。
- App 图标或窗口 tile 左键拖动超过阈值后进入移动模式，拖到其他屏幕行会移动对应窗口。
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
