# 给 Agent 的实现提示

你要在 macOS 上实现一套“当前屏幕内 App 级 Cmd+Tab 切换器”。目标不是窗口级 AltTab，也不是修改 macOS 系统切换器，而是用 Karabiner-Elements 拦截快捷键，再用 Hammerspoon 实现多屏友好的 App 切换逻辑。

## 用户问题

macOS 原生 `Cmd+Tab` 是全局 App MRU 列表。双屏或多屏时，用户在 A 屏工作，按 `Cmd+Tab` 可能因为上一个 App 在 B 屏而把焦点切到 B 屏。这不符合“当前屏幕内快速切换”的工作流。

## 目标行为

- `Cmd+Tab` 只在当前屏幕内切换 App。
- `Cmd+Shift+Tab` 反向切换。
- 当前屏幕默认指当前焦点窗口所在屏幕。
- 可选项：允许改成鼠标所在屏幕。
- 所有屏幕行中，多窗口 App 按窗口展开为多个候选项，单窗口 App 仍作为一个候选项。
- 按住 `Cmd` 后，多次按 `Tab` 应能选择更老的 App，不能只在最近两个 App 之间来回跳。
- 松开 `Cmd` 后聚焦选中的 App。
- 显示类似原生切换器的悬浮图标面板。
- 鼠标点击面板中的 App 图标时直接切换到该 App。
- 鼠标悬停到面板中的 App 图标时先选中该 App。
- 面板打开时按 `1-9`，直接切换到当前可见区域中对应编号的 App。
- 面板打开时按 `I`，切换是否显示最小化窗口。
- 每个屏幕应维护独立 App MRU，避免完全依赖 macOS 全局 App 顺序。
- 悬浮面板应按屏幕分多行展示；上下堆叠屏幕按 macOS 显示器排列从上到下显示，其他布局保持当前屏幕优先。
- 普通 `Cmd+Tab` 键盘循环仍只在当前屏幕行内进行。
- 鼠标点击其他屏幕行的 App 或窗口 tile 时，才允许跨屏聚焦。
- 任意屏幕行如果 App 有多个窗口，应展开成多个窗口 tile，共用同一个 App 图标。
- 多窗口 tile 不显示 App 名，只显示窗口标题，最多两行；两行放不下时才省略。
- 默认不显示最小化窗口；开启“显示最小化窗口”后，最小化窗口也进入候选并显示“最小”角标。
- 不再使用第二层窗口选择菜单；窗口切换应在第一层完成。
- 右键 App 图标弹出管理菜单，不要右键直接退出。
- 管理菜单提供隐藏 App、关闭当前窗口、退出 App、取消；按住 `Option` 右键时额外提供强制退出。
- 通过切换器聚焦窗口后，默认把窗口铺满当前屏幕可用区域；不要使用 macOS 原生全屏。
- 左键拖动 App 图标或窗口 tile 到其他屏幕行时，移动对应窗口到目标屏幕。
- 拖动时显示跟随鼠标的半透明 App ghost，释放在原屏幕行或空白处应取消，不做切换。
- `Esc` 取消，`Return` 确认。

## 推荐架构

使用两个工具：

- Karabiner-Elements：负责把系统保留的 `Cmd+Tab` 转发成 Hammerspoon 能监听的快捷键。
- Hammerspoon：负责窗口枚举、屏幕过滤、候选列表冻结、悬浮面板、鼠标点击和最终聚焦。

不要尝试直接覆盖 macOS 原生 `Cmd+Tab`，也不要依赖 AltTab。AltTab 更偏窗口级切换器，无法稳定表达“当前屏幕内 App MRU”。

## Karabiner 要点

必须保留 `Cmd` 修饰键，不要把 `Cmd+Tab` 转成裸 `F18`。裸 `F18` 会导致 Hammerspoon 难以判断 `Cmd` 是否仍被按住。

正向映射：

```json
{
  "type": "basic",
  "from": {
    "key_code": "tab",
    "modifiers": {
      "mandatory": ["command"],
      "optional": ["caps_lock"]
    }
  },
  "to": [
    {
      "key_code": "f18",
      "modifiers": ["left_command"]
    }
  ]
}
```

反向映射：

```json
{
  "type": "basic",
  "from": {
    "key_code": "tab",
    "modifiers": {
      "mandatory": ["command", "shift"],
      "optional": ["caps_lock"]
    }
  },
  "to": [
    {
      "key_code": "f19",
      "modifiers": ["left_command", "left_shift"]
    }
  ]
}
```

## Hammerspoon 要点

候选窗口：

- 使用 `hs.window.orderedWindows()` 获取 MRU 顺序。
- 过滤 `window:isStandard()`；默认还要求 `window:isVisible()` 且 `not window:isMinimized()`。
- 当 `cmdTab.showMinimizedWindows` 开启时，用 `hs.window.allWindows()` 补充最小化窗口；最小化窗口只要求有 `screen()`，不强制 `window:isStandard()`，以兼容 `AXDialog` 类 App 窗口。
- 用 `window:screen()` 与当前屏幕匹配。
- 所有屏幕行都用 App 的 `bundleID` 分组，并在 App 有多个窗口时展开为多个 tile。
- 一个 App 的多个窗口会变成多个 tile；只有单窗口 App 保持为 App tile。
- 候选顺序优先使用当前屏幕自己的 App MRU，再用 `hs.window.orderedWindows()` 补齐当前可见但还没有历史记录的 App。
- 展开候选时，每个窗口 tile 的 `candidate.window` 是具体窗口，`candidate.name` 使用窗口标题。
- 单窗口 App tile 或未展开候选仍保存同 App、同屏幕的所有窗口：`candidate.windows` 和 `candidate.windowCount`。

每屏独立 MRU：

- 使用 `hs.window.filter.default:subscribe(hs.window.filter.windowFocused, callback)` 监听窗口聚焦。
- 聚焦事件发生时，根据 `window:screen()` 和 App `bundleID` 更新 `screenMRU[screenKey]`。
- `screenMRU[screenKey]` 是 App key 列表，最新聚焦 App 放到第一个。
- Hammerspoon reload 前应调用 `hs.window.filter.default:unsubscribe(nil, oldCallback)` 移除旧回调。
- 在开始切换前调用一次 `recordWindowFocus(hs.window.focusedWindow())`，保证当前 App 在当前屏幕 MRU 首位。

当前屏幕：

- 默认用 `hs.window.focusedWindow():screen()`。
- 没有焦点窗口时回退到鼠标所在屏幕或主屏。
- 如果用户想鼠标优先，提供 `preferMouseScreen = true`。

切换会话：

- 第一次 `F18/F19` 触发时构建候选列表并冻结。
- 后续 `F18/F19` 只移动 `selectedIndex`，不要重新枚举窗口。
- 这样可以避免切过去后 MRU 重排，导致只能在最近两个 App 之间来回跳。
- 会话中应保留 `screenGroups`，其中当前屏幕组用于键盘选择，其他屏幕组仅用于展示和鼠标点击。

Cmd 释放：

- 不要用定时器轮询 `hs.eventtap.checkKeyboardModifiers()`，容易被 Karabiner 虚拟按键状态误导。
- 使用 `hs.eventtap` 监听 `flagsChanged`。
- 当切换会话 active 且事件 flags 不包含 command 时，调用 `finishSwitcher()`。
- 同时监听 `keyUp`，当 `F18/F19` 或 `Tab` 释放且 `Cmd` 已不在按下状态时，也调用 `finishSwitcher()`。
- 不要给 `hs.hotkey.bind` 配置 repeat 回调，否则 Karabiner 虚拟键状态异常时可能出现自动循环选择停不下来。
- 可以加一个只在 App 选择层生效的释放看门狗：如果 command 已释放且看到 switch key 释放，或距离最近 switch key 事件超过约 1 秒，则兜底完成选择。
- 如果 `switcher.active=false` 但 `switcher.canvas`、`switcher.dragCanvas` 或 `switcher.dragState` 仍存在，watcher 应调用强制 dismiss 清理残留面板。

对象生命周期：

- `eventtap` 和 `hotkey` 对象必须挂到全局表上，例如 `currentScreenSwitcher.eventTap` 和 `currentScreenSwitcher.hotkeys`。
- 不要只保存在 local 变量里，否则 Hammerspoon reload 后可能被 Lua GC 回收，表现为面板还在但收不到 Cmd 释放事件。
- App 图标应缓存，避免每次打开切换器都调用 `hs.image.imageFromAppBundle`。
- 候选列表应按屏幕单次扫描构建，避免每个 App 再调用一次 `hs.window.orderedWindows()` 统计窗口数量。

悬浮面板：

- 使用 `hs.canvas`。
- 面板放在当前屏幕中心。
- 按屏幕分多行绘制；用 `screen:fullFrame()` 判断屏幕物理位置，上下堆叠时按 `y` 坐标从上到下排序，左右排列时保持当前屏幕优先。
- 每个候选项显示 App icon；普通 App tile 显示 App 名，多窗口展开后的窗口 tile 显示窗口标题。
- 只有当前屏幕行的可见候选项显示数字角标 `1-9`。
- 窗口 tile 不显示 App 名和 `1/3` 角标，通过最多两行窗口标题区分；未展开的聚合 App 可继续显示 `3窗` 这类数量角标。
- 最小化窗口 tile 显示“最小”角标；点击或键盘确认时先 `window:unminimize()` 再聚焦。
- 用 `hs.image.imageFromAppBundle(bundleID)` 获取图标。
- 为每个图标块追加一个透明矩形作为 hitbox。
- hitbox 设置 `trackMouseDown = true`、`trackMouseUp = true`、`trackMouseEnterExit = true` 和 `trackMouseMove = true`。
- 在 `canvas:mouseCallback` 里根据 hitbox id 找到候选项。
- 当前屏幕行的 `mouseEnter` 或 `mouseMove` 可以更新 `selectedIndex` 并重绘面板。
- 其他屏幕行不要仅因悬停就改变最终选择，避免用户松开 `Cmd` 时意外跨屏。
- 任意屏幕行的 `mouseUp` 都可以直接聚焦对应 App 或窗口 tile；点击其他屏幕行即跨屏切换。
- `mouseDown` 时用 `hs.eventtap.checkMouseButtons()` 检测右键，并记录 hitbox id。
- 右键 `mouseUp` 时弹出自绘 App 管理菜单；菜单出现后关闭 App 选择面板。
- App 管理菜单使用 `hs.canvas`，并设置短时间自动消失，避免菜单残留。
- 左键 `mouseDown` 记录拖拽起点，移动超过阈值后进入拖拽模式。
- 拖拽模式禁用悬停选中和释放 `Cmd` 自动确认，避免拖动过程中误切换。
- 拖拽模式使用独立 `hs.canvas` 绘制 App ghost，跟随鼠标移动，不参与点击命中。
- ghost 应记录原 tile 的绝对位置和鼠标按下时的相对偏移，拖动时保持这个偏移，避免 ghost 从鼠标右下角突兀出现。
- 使用 canvas 级 mouse events 处理释放在空白区域的情况。
- 目标屏幕行命中后高亮该行，`mouseUp` 时移动代表窗口。
- 自动铺满开启时用目标屏幕 `screen:frame()`；关闭时把源窗口相对位置和尺寸映射到目标屏幕 `screen:frame()`。

键盘控制：

- `Esc` 调用 `cancelSwitcher()`，并且要在 `switcher.active=false` 但 overlay 残留时也能强制清理。
- `Return` 调用 `finishSwitcher()`。
- `1-9` 映射到当前可见区域的第 1 到第 9 个候选项，命中后直接聚焦对应窗口。
- `I` 切换 `cmdTab.showMinimizedWindows`，并立即重建当前面板候选列表。
- `Cmd+Tab` 对应正向移动。
- `Cmd+Shift+Tab` 对应反向移动。
- 不要让 `Cmd+Tab` 默认跨屏遍历，否则会重新引入 macOS 原生切屏问题。

聚焦窗口：

```lua
local app = window:application()
if app then
  app:activate(false)
end
window:raise()
window:focus()
window:setFrame(window:screen():frame(), 0)
```

不要使用 `app:activate(true)`，否则 Chrome、IDE 这类多窗口 App 会在所有屏幕同时被抬到前台。只激活 App，再单独 `raise/focus` 目标窗口。

使用 `screen:frame()` 而不是 `screen:fullFrame()`，这样不会遮住菜单栏和 Dock。

## 安装流程

在目标机器上：

```bash
brew install --cask hammerspoon karabiner-elements
mkdir -p ~/.hammerspoon ~/.config/karabiner/assets/complex_modifications
cp hammerspoon/init.lua ~/.hammerspoon/init.lua
cp karabiner/karabiner.json ~/.config/karabiner/karabiner.json
cp karabiner/assets/complex_modifications/current-screen-app-switcher.json ~/.config/karabiner/assets/complex_modifications/current-screen-app-switcher.json
open -a Hammerspoon
open -a Karabiner-Elements
```

需要提醒用户授权：

- Hammerspoon 辅助功能权限。
- Hammerspoon 输入监控权限，如果 Cmd 释放无法触发提交。
- Karabiner-Elements 根据系统提示开启权限。

## 验证命令

```bash
luac -p ~/.hammerspoon/init.lua
jq empty ~/.config/karabiner/karabiner.json
"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" --show-current-profile-name
hs -c 'return tostring(hs.accessibilityState())'
hs -c 'local s=currentScreenSwitcherStatus(); return tostring(s.eventTapEnabled), tostring(s.active), tostring(s.candidates)'
```

## 常见 Bug 和修复

Bug：只能在最近两个 App 之间来回切。

原因：每次按 `Tab` 都重新读取系统 MRU，切换后 MRU 立刻重排。

修复：第一次触发时冻结候选列表，后续只移动 `selectedIndex`。

Bug：按住 `Cmd` 时悬浮面板提前消失。

原因：轮询键盘修饰键时被 Karabiner 虚拟事件误导。

修复：不要轮询，改用 `flagsChanged` 监听 Cmd 释放。

Bug：松开 `Cmd` 后面板不消失，也没有切换。

原因：`eventtap` 被 Lua GC 回收，或 Karabiner 转发时丢掉了 `Cmd` 修饰键。

修复：把 `eventtap` 放到全局表上，并让 Karabiner 输出 `Cmd+F18`/`Cmd+Shift+F19`。

Bug：中文 App 名称截断乱码。

原因：按字节截断 UTF-8 字符串。

修复：使用 Lua `utf8.codes`/`utf8.char` 做安全截断。

## 回滚要求

必须提供回滚脚本。回滚脚本至少要：

- 把 `~/.config/karabiner/karabiner.json` 改名备份。
- 把 `~/.hammerspoon/init.lua` 改名备份。
- 退出 Hammerspoon。
- 退出 Karabiner-Elements。

这套方案是用户态配置，不应修改系统文件，不应要求关闭 SIP，不应使用内核扩展。

## 分享项目前的改进建议

当前 `scripts/install.sh` 会备份并覆盖目标用户的 Karabiner 主配置。正式开源前，建议改成“合并现有 Karabiner profile 里的 complex_modifications.rules”，避免覆盖用户已有改键规则。
