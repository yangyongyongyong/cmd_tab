local preferMouseScreen = false
local switcherDisplayDelay = 0.3
local maximizeWindowOnSwitchSettingKey = "cmdTab.maximizeWindowOnSwitch"
local showMinimizedWindowsSettingKey = "cmdTab.showMinimizedWindows"
local maximizeWindowOnSwitch = hs.settings.get(maximizeWindowOnSwitchSettingKey)
if maximizeWindowOnSwitch == nil then
  maximizeWindowOnSwitch = true
  hs.settings.set(maximizeWindowOnSwitchSettingKey, maximizeWindowOnSwitch)
end
local showMinimizedWindows = hs.settings.get(showMinimizedWindowsSettingKey)
if showMinimizedWindows == nil then
  showMinimizedWindows = false
  hs.settings.set(showMinimizedWindowsSettingKey, showMinimizedWindows)
end

pcall(function()
  hs.ipc.cliInstall()
end)

pcall(function()
  hs.allowAppleScript(true)
end)

currentScreenSwitcher = currentScreenSwitcher or {}
local appIconCache = currentScreenSwitcher.iconCache or {}
currentScreenSwitcher.iconCache = appIconCache

local ignoredApps = {
  ["Hammerspoon"] = true,
}

local function screenKey(screen)
  if not screen then
    return nil
  end

  return screen:getUUID() or screen:name() or tostring(screen:id())
end

local function appKey(window)
  local app = window and window:application()
  if not app then
    return nil
  end

  return app:bundleID() or app:name()
end

local function isUsableWindow(window)
  if not window then
    return false
  end

  local app = window:application()
  if not app or ignoredApps[app:name()] then
    return false
  end

  local minimized = window:isMinimized()
  if showMinimizedWindows and minimized then
    return window:screen() ~= nil
  end

  return window:isStandard()
    and window:screen() ~= nil
    and window:isVisible()
end

local function windowIdentity(window)
  if not window then
    return nil
  end

  local ok, id = pcall(function()
    return window:id()
  end)
  if ok and id then
    return id
  end

  return tostring(window)
end

local function candidateWindows()
  local result = {}
  local seen = {}

  local function addWindow(window)
    local id = windowIdentity(window)
    if id and not seen[id] then
      seen[id] = true
      table.insert(result, window)
    end
  end

  for _, window in ipairs(hs.window.orderedWindows()) do
    addWindow(window)
  end

  if showMinimizedWindows then
    for _, window in ipairs(hs.window.allWindows()) do
      addWindow(window)
    end
  end

  return result
end

local function currentScreen()
  if preferMouseScreen then
    local mouseScreen = hs.screen.find(hs.mouse.absolutePosition())
    if mouseScreen then
      return mouseScreen
    end
  end

  local focused = hs.window.focusedWindow()
  if focused and focused:screen() then
    return focused:screen()
  end

  return hs.screen.find(hs.mouse.absolutePosition()) or hs.screen.mainScreen()
end

local function appWindowsOnScreen(screen)
  local targetScreenKey = screenKey(screen)
  local result = {}
  local windowsByApp = {}
  local fallbackOrder = {}
  local seenApps = {}

  for _, window in ipairs(candidateWindows()) do
    if isUsableWindow(window) and screenKey(window:screen()) == targetScreenKey then
      local key = appKey(window)
      if key and not seenApps[key] then
        windowsByApp[key] = window
        table.insert(fallbackOrder, key)
        seenApps[key] = true
      end
    end
  end

  local state = currentScreenSwitcher
  local screenMRU = state and state.screenMRU and state.screenMRU[targetScreenKey] or {}
  local added = {}

  for _, key in ipairs(screenMRU) do
    local window = windowsByApp[key]
    if window then
      table.insert(result, window)
      added[key] = true
    end
  end

  for _, key in ipairs(fallbackOrder) do
    if not added[key] then
      table.insert(result, windowsByApp[key])
    end
  end

  return result
end

local function appWindowsForKeyOnScreen(screen, key)
  local targetScreenKey = screenKey(screen)
  local result = {}

  for _, window in ipairs(candidateWindows()) do
    if isUsableWindow(window) and screenKey(window:screen()) == targetScreenKey and appKey(window) == key then
      table.insert(result, window)
    end
  end

  return result
end

local function appName(window)
  local app = window and window:application()
  return app and app:name() or "未知"
end

local function windowTitle(window)
  local title = window and window:title() or ""
  if title == "" then
    return appName(window)
  end

  return title
end

local function appIcon(window)
  local app = window and window:application()
  local bundleID = app and app:bundleID()
  local cacheKey = bundleID or app and app:name() or "__fallback"

  if appIconCache[cacheKey] then
    return appIconCache[cacheKey]
  end

  if bundleID then
    local icon = hs.image.imageFromAppBundle(bundleID)
    if icon then
      appIconCache[cacheKey] = icon
      return icon
    end
  end

  local fallbackIcon = hs.image.imageFromName("NSApplicationIcon")
  appIconCache[cacheKey] = fallbackIcon
  return fallbackIcon
end

local function truncateText(text, limit)
  if utf8 and utf8.len and utf8.len(text) and utf8.len(text) <= limit then
    return text
  end

  if utf8 and utf8.codes and utf8.char then
    local parts = {}
    local count = 0
    for _, codepoint in utf8.codes(text) do
      count = count + 1
      if count > limit - 1 then
        break
      end
      table.insert(parts, utf8.char(codepoint))
    end

    return table.concat(parts) .. "..."
  end

  if #text <= limit then
    return text
  end

  return string.sub(text, 1, limit - 3) .. "..."
end

local function splitTextTwoLines(text, firstLimit, secondLimit)
  text = text or ""

  if utf8 and utf8.codes and utf8.char then
    local firstParts = {}
    local secondParts = {}
    local overflow = false
    local count = 0

    for _, codepoint in utf8.codes(text) do
      count = count + 1
      if count <= firstLimit then
        table.insert(firstParts, utf8.char(codepoint))
      elseif count <= firstLimit + secondLimit - 1 then
        table.insert(secondParts, utf8.char(codepoint))
      else
        overflow = true
        break
      end
    end

    local secondLine = table.concat(secondParts)
    if overflow then
      secondLine = secondLine .. "..."
    end
    if secondLine == "" then
      secondLine = nil
    end

    return table.concat(firstParts), secondLine
  end

  if #text <= firstLimit then
    return text, nil
  end

  local firstLine = string.sub(text, 1, firstLimit)
  local secondLine = string.sub(text, firstLimit + 1)
  if #secondLine > secondLimit then
    secondLine = string.sub(secondLine, 1, math.max(0, secondLimit - 3)) .. "..."
  end

  return firstLine, secondLine
end

local function focusWindow(window)
  if not window then
    return
  end

  local app = window:application()
  if window:isMinimized() then
    pcall(function()
      window:unminimize()
    end)
  end

  if app then
    app:activate(false)
  end

  window:raise()
  window:focus()

  if maximizeWindowOnSwitch and window:isStandard() and not window:isFullScreen() then
    local screen = window:screen()
    if screen then
      pcall(function()
        window:setFrame(screen:frame(), 0)
      end)
    end
  end
end

local function appCandidatesOnScreen(screen, expandWindows)
  local targetScreenKey = screenKey(screen)
  local windowsByApp = {}
  local fallbackOrder = {}
  local orderedWindowsOnScreen = {}
  local windowByID = {}
  local result = {}

  for _, window in ipairs(candidateWindows()) do
    if isUsableWindow(window) and screenKey(window:screen()) == targetScreenKey then
      local key = appKey(window)
      if key then
        if not windowsByApp[key] then
          windowsByApp[key] = {}
          table.insert(fallbackOrder, key)
        end
        table.insert(windowsByApp[key], window)
        table.insert(orderedWindowsOnScreen, window)
        windowByID[windowIdentity(window)] = window
      end
    end
  end

  if expandWindows then
    local addedSingleWindowApp = {}
    local addedWindow = {}
    local windowIndexByID = {}
    for _, windows in pairs(windowsByApp) do
      for index, window in ipairs(windows) do
        windowIndexByID[windowIdentity(window)] = index
      end
    end

    local function addWindowCandidate(window)
      local windowID = windowIdentity(window)
      if not windowID or addedWindow[windowID] then
        return
      end

      local key = appKey(window)
      local windows = key and windowsByApp[key] or nil
      if windows then
        if #windows > 1 then
          addedWindow[windowID] = true
          table.insert(result, {
            window = window,
            key = key,
            appName = appName(window),
            name = windowTitle(window),
            icon = appIcon(window),
            windows = { window },
            windowCount = #windows,
            windowIndex = windowIndexByID[windowIdentity(window)] or 1,
            isMinimized = window:isMinimized(),
            isWindowTile = true,
          })
        elseif not addedSingleWindowApp[key] then
          addedWindow[windowID] = true
          addedSingleWindowApp[key] = true
          table.insert(result, {
            window = window,
            key = key,
            appName = appName(window),
            name = appName(window),
            icon = appIcon(window),
            windows = windows,
            windowCount = #windows,
            windowIndex = 1,
            isMinimized = window:isMinimized(),
            isWindowTile = false,
          })
        end
      end
    end

    local state = currentScreenSwitcher
    local screenWindowMRU = state and state.screenWindowMRU and state.screenWindowMRU[targetScreenKey] or {}
    for _, windowID in ipairs(screenWindowMRU) do
      addWindowCandidate(windowByID[windowID])
    end

    for _, window in ipairs(orderedWindowsOnScreen) do
      addWindowCandidate(window)
    end

    return result
  end

  local state = currentScreenSwitcher
  local screenMRU = state and state.screenMRU and state.screenMRU[targetScreenKey] or {}
  local added = {}

  local function addCandidate(key)
    local windows = windowsByApp[key]
    if not windows or added[key] then
      return
    end

    if expandWindows and #windows > 1 then
      for index, window in ipairs(windows) do
        table.insert(result, {
          window = window,
          key = key,
          appName = appName(window),
          name = windowTitle(window),
          icon = appIcon(window),
          windows = { window },
          windowCount = #windows,
          windowIndex = index,
          isMinimized = window:isMinimized(),
          isWindowTile = true,
        })
      end
    else
      local window = windows[1]
      table.insert(result, {
        window = window,
        key = key,
        appName = appName(window),
        name = appName(window),
        icon = appIcon(window),
        windows = windows,
        windowCount = #windows,
        windowIndex = 1,
        isMinimized = window:isMinimized(),
        isWindowTile = false,
      })
    end
    added[key] = true
  end

  for _, key in ipairs(screenMRU) do
    addCandidate(key)
  end

  for _, key in ipairs(fallbackOrder) do
    addCandidate(key)
  end

  return result
end

currentScreenSwitcher = currentScreenSwitcher or {}

local switcher = currentScreenSwitcher
if switcher.canvas then
  switcher.canvas:delete()
end
if switcher.menuCanvas then
  switcher.menuCanvas:delete()
end
if switcher.dragCanvas then
  switcher.dragCanvas:delete()
end
if switcher.eventTap then
  switcher.eventTap:stop()
end
if switcher.mouseDragTap then
  switcher.mouseDragTap:stop()
end
if switcher.releaseWatcher then
  switcher.releaseWatcher:stop()
end
if switcher.iconWarmupTimer then
  switcher.iconWarmupTimer:stop()
end
if switcher.displayTimer then
  switcher.displayTimer:stop()
end
if switcher.hotkeys then
  for _, hotkey in ipairs(switcher.hotkeys) do
    hotkey:disable()
  end
end
if switcher.focusCallback then
  pcall(function()
    hs.window.filter.default:unsubscribe(nil, switcher.focusCallback)
  end)
end

switcher.active = false
switcher.canvas = nil
switcher.menuCanvas = nil
switcher.menuTargets = {}
switcher.menuTimer = nil
switcher.displayTimer = nil
switcher.dragCanvas = nil
switcher.mouseDragTap = nil
switcher.candidates = {}
switcher.screenGroups = {}
switcher.selectedIndex = 1
switcher.mode = "apps"
switcher.windowCandidate = nil
switcher.windowCandidates = {}
switcher.selectedWindowIndex = 1
switcher.visibleWindowStartIndex = 1
switcher.visibleWindowEndIndex = 0
switcher.screen = nil
switcher.commandSession = false
switcher.switchKeyReleased = false
switcher.lastSwitchEventAt = 0
switcher.rightClickTarget = nil
switcher.clickTargets = {}
switcher.dropTargets = {}
switcher.dragState = nil
switcher.visibleStartIndex = 1
switcher.visibleEndIndex = 0
switcher.screenMRU = switcher.screenMRU or {}
switcher.screenWindowMRU = switcher.screenWindowMRU or {}

-- 这些对象必须挂到全局表上，避免 Hammerspoon 重新加载后被 Lua GC 回收。
switcher.hotkeys = {}
switcher.iconCache = appIconCache
switcher.iconWarmupTimer = hs.timer.doAfter(0.2, function()
  for _, window in ipairs(candidateWindows()) do
    if isUsableWindow(window) then
      appIcon(window)
    end
  end
end)

local function nextIndex(index, count, reverse)
  if count <= 0 then
    return 1
  end

  if reverse then
    return ((index - 2) % count) + 1
  end

  return (index % count) + 1
end

local function nowSeconds()
  return hs.timer.secondsSinceEpoch()
end

local function modifiersIncludeCommand(modifiers)
  if modifiers and type(modifiers._raw) == "number" then
    return math.floor(modifiers._raw / 1048576) % 2 == 1
  end

  return modifiers and (modifiers.cmd or modifiers.command or modifiers.leftcmd or modifiers.rightcmd)
end

local function commandCurrentlyDown()
  local ok, modifiers = pcall(hs.eventtap.checkKeyboardModifiers, true)
  if ok and modifiers then
    return modifiersIncludeCommand(modifiers)
  end

  ok, modifiers = pcall(hs.eventtap.checkKeyboardModifiers)
  if not ok or not modifiers then
    return false
  end

  return modifiersIncludeCommand(modifiers)
end

local function anyMouseButtonDown()
  local ok, buttons = pcall(hs.eventtap.checkMouseButtons)
  if not ok or not buttons then
    return false
  end

  return buttons.left or buttons.right or buttons.middle or buttons[1] or buttons[2] or buttons[3]
end

local function isSwitchKeyCode(keyCode)
  return keyCode == hs.keycodes.map.f18 or keyCode == hs.keycodes.map.f19
end

local function markSwitchKeyDown()
  switcher.lastSwitchEventAt = nowSeconds()
  switcher.switchKeyReleased = false
end

local function recordWindowFocus(window)
  if not isUsableWindow(window) then
    return
  end

  local screen = window:screen()
  local targetScreenKey = screenKey(screen)
  local key = appKey(window)
  if not targetScreenKey or not key then
    return
  end

  local windowID = windowIdentity(window)
  if windowID then
    local oldWindowMRU = switcher.screenWindowMRU[targetScreenKey] or {}
    local newWindowMRU = { windowID }
    for _, existingID in ipairs(oldWindowMRU) do
      if existingID ~= windowID then
        table.insert(newWindowMRU, existingID)
      end
    end
    switcher.screenWindowMRU[targetScreenKey] = newWindowMRU
  end

  local oldMRU = switcher.screenMRU[targetScreenKey] or {}
  local newMRU = { key }
  for _, existingKey in ipairs(oldMRU) do
    if existingKey ~= key then
      table.insert(newMRU, existingKey)
    end
  end
  switcher.screenMRU[targetScreenKey] = newMRU
end

switcher.focusCallback = function(window)
  recordWindowFocus(window)
end
hs.window.filter.default:subscribe(hs.window.filter.windowFocused, switcher.focusCallback)
recordWindowFocus(hs.window.focusedWindow())

local drawSwitcherCanvas
local drawWindowCanvas
local finishSwitcher
local finishCandidate
local buildCandidates
local buildScreenGroups
local startSwitcherMouseDragTap

local function stopSwitcherMouseDragTap()
  if switcher.mouseDragTap then
    switcher.mouseDragTap:stop()
    switcher.mouseDragTap = nil
  end
end

local function cancelDelayedSwitcherCanvas()
  if switcher.displayTimer then
    switcher.displayTimer:stop()
    switcher.displayTimer = nil
  end
end

local function hideSwitcherCanvas()
  cancelDelayedSwitcherCanvas()
  if switcher.canvas then
    switcher.canvas:delete()
    switcher.canvas = nil
  end
end

local function hideAppActionMenu()
  if switcher.menuTimer then
    switcher.menuTimer:stop()
    switcher.menuTimer = nil
  end

  if switcher.menuCanvas then
    switcher.menuCanvas:delete()
    switcher.menuCanvas = nil
  end

  switcher.menuTargets = {}
end

local function hideDragGhost()
  if switcher.dragCanvas then
    switcher.dragCanvas:delete()
    switcher.dragCanvas = nil
  end
end

local function switcherOverlayVisible()
  return switcher.canvas ~= nil or switcher.dragCanvas ~= nil or switcher.menuCanvas ~= nil
end

local function dismissSwitcherOverlay()
  stopSwitcherMouseDragTap()
  switcher.active = false
  switcher.commandSession = false
  switcher.switchKeyReleased = false
  switcher.rightClickTarget = nil
  switcher.dragState = nil
  hideSwitcherCanvas()
  hideAppActionMenu()
  hideDragGhost()
end

local function requestSwitcherCanvasUpdate(immediate)
  if not switcher.active or switcher.mode ~= "apps" then
    return
  end

  if immediate or switcher.canvas then
    drawSwitcherCanvas()
    return
  end

  if switcher.displayTimer then
    return
  end

  switcher.displayTimer = hs.timer.doAfter(switcherDisplayDelay, function()
    switcher.displayTimer = nil
    if switcher.active and switcher.mode == "apps" and not switcher.canvas and not switcher.dragState and commandCurrentlyDown() then
      drawSwitcherCanvas()
    end
  end)
end

local function updateDragGhost(point)
  local drag = switcher.dragState
  if not drag or not drag.dragging or not drag.candidate then
    return
  end

  local ghostWidth = drag.tileFrame and drag.tileFrame.w or 78
  local ghostHeight = drag.tileFrame and drag.tileFrame.h or 94
  local x = point.x - (drag.offsetX or ghostWidth / 2)
  local y = point.y - (drag.offsetY or ghostHeight / 2)

  if not switcher.dragCanvas then
    local candidate = drag.candidate
    local canvas = hs.canvas.new({ x = x, y = y, w = ghostWidth, h = ghostHeight })
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas:appendElements({
      type = "rectangle",
      action = "fill",
      roundedRectRadii = { xRadius = 14, yRadius = 14 },
      fillColor = { red = 0.08, green = 0.08, blue = 0.09, alpha = 0.72 },
      frame = { x = 0, y = 0, w = ghostWidth, h = ghostHeight },
    })
    canvas:appendElements({
      type = "image",
      image = candidate.icon,
      imageScaling = "scaleProportionally",
      frame = { x = (ghostWidth - 48) / 2, y = 10, w = 48, h = 48 },
    })
    canvas:appendElements({
      type = "text",
      text = truncateText(candidate.name, 12),
      textSize = 11,
      textColor = { red = 1, green = 1, blue = 1, alpha = 0.86 },
      textAlignment = "center",
      frame = { x = 4, y = ghostHeight - 26, w = ghostWidth - 8, h = 18 },
    })
    switcher.dragCanvas = canvas
    canvas:show()
  else
    switcher.dragCanvas:frame({ x = x, y = y, w = ghostWidth, h = ghostHeight })
    switcher.dragCanvas:show()
  end
end

local function pointInFrame(point, frame)
  return point.x >= frame.x
    and point.x <= frame.x + frame.w
    and point.y >= frame.y
    and point.y <= frame.y + frame.h
end

local function dragTargetForPoint(point)
  for _, target in ipairs(switcher.dropTargets or {}) do
    if pointInFrame(point, target.frame) then
      return target
    end
  end

  return nil
end

local function mapFrameToScreen(window, targetScreen)
  local targetFrame = targetScreen:frame()
  if maximizeWindowOnSwitch then
    return targetFrame
  end

  local sourceScreen = window:screen()
  if not sourceScreen then
    return targetFrame
  end

  local sourceFrame = sourceScreen:frame()
  local windowFrame = window:frame()

  return {
    x = targetFrame.x + ((windowFrame.x - sourceFrame.x) / sourceFrame.w) * targetFrame.w,
    y = targetFrame.y + ((windowFrame.y - sourceFrame.y) / sourceFrame.h) * targetFrame.h,
    w = (windowFrame.w / sourceFrame.w) * targetFrame.w,
    h = (windowFrame.h / sourceFrame.h) * targetFrame.h,
  }
end

local function moveCandidateToScreen(candidate, targetScreen)
  local window = candidate and candidate.window
  if not window or not targetScreen then
    return
  end

  local targetFrame = mapFrameToScreen(window, targetScreen)
  if window:isMinimized() then
    pcall(function()
      window:unminimize()
    end)
  end

  pcall(function()
    window:setFrame(targetFrame, 0)
  end)

  local app = window:application()
  if app then
    app:activate(false)
  end
  window:raise()
  window:focus()
  recordWindowFocus(window)
  hs.alert.show("移动 " .. (candidate.name or "窗口"))
end

local function resetDragState()
  stopSwitcherMouseDragTap()
  hideDragGhost()
  switcher.dragState = nil
end

local function beginAppDrag(target)
  if not target or target.mode ~= "app" then
    return
  end

  local startPoint = hs.mouse.absolutePosition()
  local tileFrame = target.tileFrame or { x = startPoint.x - 39, y = startPoint.y - 47, w = 78, h = 94 }

  switcher.commandSession = false
  switcher.dragState = {
    candidate = target.candidate,
    sourceScreenKey = target.screenKey,
    startPoint = startPoint,
    tileFrame = tileFrame,
    offsetX = startPoint.x - tileFrame.x,
    offsetY = startPoint.y - tileFrame.y,
    dragging = false,
    targetScreen = nil,
    targetScreenKey = nil,
  }
  if startSwitcherMouseDragTap then
    startSwitcherMouseDragTap()
  end
end

local function updateAppDrag()
  local drag = switcher.dragState
  if not drag then
    return false
  end

  local buttons = hs.eventtap.checkMouseButtons()
  if not buttons.left and not buttons[1] then
    return drag.dragging
  end

  local point = hs.mouse.absolutePosition()
  local dx = point.x - drag.startPoint.x
  local dy = point.y - drag.startPoint.y
  if not drag.dragging and (dx * dx + dy * dy) < 144 then
    return true
  end

  if not drag.dragging then
    drag.dragging = true
    switcher.commandSession = false
  end

  local target = dragTargetForPoint(point)
  local targetScreenKey = target and target.key or nil
  if drag.targetScreenKey ~= targetScreenKey then
    drag.targetScreenKey = targetScreenKey
    drag.targetScreen = target and target.screen or nil
    hideDragGhost()
    drawSwitcherCanvas()
  end

  updateDragGhost(point)

  return true
end

local function finishAppDrag()
  local drag = switcher.dragState
  if not drag then
    return false
  end

  local wasDragging = drag.dragging
  local point = hs.mouse.absolutePosition()
  local wasClick = not wasDragging and drag.tileFrame and pointInFrame(point, drag.tileFrame)
  local clickCandidate = drag.candidate

  if wasDragging and drag.targetScreen and drag.targetScreenKey ~= drag.sourceScreenKey then
    switcher.active = false
    switcher.commandSession = false
    hideSwitcherCanvas()
    moveCandidateToScreen(drag.candidate, drag.targetScreen)
    resetDragState()
    return true
  end

  resetDragState()
  if wasClick then
    finishCandidate(clickCandidate)
    return true
  end

  if wasDragging then
    switcher.commandSession = true
    switcher.switchKeyReleased = false
    switcher.lastSwitchEventAt = nowSeconds()
    drawSwitcherCanvas()
    return true
  end

  switcher.commandSession = true
  return false
end

startSwitcherMouseDragTap = function()
  if switcher.mouseDragTap and switcher.mouseDragTap:isEnabled() then
    return
  end

  stopSwitcherMouseDragTap()
  switcher.mouseDragTap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDragged,
    hs.eventtap.event.types.leftMouseUp,
  }, function(event)
    if not switcher.dragState then
      stopSwitcherMouseDragTap()
      return false
    end

    local eventType = event:getType()
    if eventType == hs.eventtap.event.types.leftMouseDragged then
      updateAppDrag()
      return false
    end

    if eventType == hs.eventtap.event.types.leftMouseUp then
      if finishAppDrag() then
        return true
      end
      return false
    end

    return false
  end)
  switcher.mouseDragTap:start()
end

local function optionCurrentlyDown()
  local ok, modifiers = pcall(hs.eventtap.checkKeyboardModifiers)
  if not ok or not modifiers then
    return false
  end

  return modifiers.alt or modifiers.option or modifiers.leftalt or modifiers.rightalt
end

local function performAppAction(candidate, action)
  hideAppActionMenu()
  if action == "cancel" then
    return
  end

  local window = candidate and candidate.window
  local app = window and window:application()
  local name = candidate and candidate.appName or candidate and candidate.name or app and app:name() or "App"

  if action == "hide" and app then
    app:hide()
    hs.alert.show("隐藏 " .. name)
  elseif action == "close-window" and window then
    window:close()
    hs.alert.show("关闭窗口 " .. name)
  elseif action == "quit" and app then
    app:kill()
    hs.alert.show("退出 " .. name)
  elseif action == "force-quit" and app then
    app:kill9()
    hs.alert.show("强制退出 " .. name)
  end
end

local function showAppActionMenu(candidate)
  if not candidate then
    return
  end

  switcher.active = false
  switcher.commandSession = false
  switcher.switchKeyReleased = false
  switcher.rightClickTarget = nil
  hideSwitcherCanvas()
  hideAppActionMenu()

  local point = hs.mouse.absolutePosition()
  local screen = hs.screen.find(point) or hs.screen.mainScreen()
  local frame = screen:frame()
  local width = 220
  local rowHeight = 30
  local padding = 8
  local appLabel = candidate.appName or candidate.name
  local items = {
    { title = "隐藏 " .. appLabel, action = "hide" },
    { title = "关闭当前窗口", action = "close-window" },
    { title = "退出 " .. appLabel, action = "quit" },
  }

  if optionCurrentlyDown() then
    table.insert(items, { title = "强制退出 " .. appLabel, action = "force-quit" })
  end

  table.insert(items, { title = "取消", action = "cancel" })

  local height = padding * 2 + #items * rowHeight
  local x = math.min(math.max(point.x, frame.x + 8), frame.x + frame.w - width - 8)
  local y = math.min(math.max(point.y, frame.y + 8), frame.y + frame.h - height - 8)
  local canvas = hs.canvas.new({ x = x, y = y, w = width, h = height })
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
    fillColor = { red = 0.08, green = 0.08, blue = 0.09, alpha = 0.94 },
    frame = { x = 0, y = 0, w = width, h = height },
  })

  switcher.menuTargets = {}
  for index, item in ipairs(items) do
    local rowY = padding + (index - 1) * rowHeight
    local id = "app-action-" .. tostring(index)
    switcher.menuTargets[id] = { candidate = candidate, action = item.action }

    canvas:appendElements({
      type = "text",
      text = item.title,
      textSize = 12,
      textColor = { red = 1, green = 1, blue = 1, alpha = item.action == "force-quit" and 0.95 or 0.84 },
      textAlignment = "left",
      frame = { x = padding + 8, y = rowY + 7, w = width - padding * 2 - 16, h = 18 },
    })
    canvas:appendElements({
      id = id,
      type = "rectangle",
      action = "fill",
      fillColor = { red = 1, green = 1, blue = 1, alpha = 0.01 },
      frame = { x = padding, y = rowY, w = width - padding * 2, h = rowHeight },
      trackMouseUp = true,
    })
  end

  switcher.menuCanvas = canvas
  canvas:mouseCallback(function(_, message, id)
    if message ~= "mouseUp" then
      return
    end

    local target = switcher.menuTargets[id]
    if target then
      performAppAction(target.candidate, target.action)
    end
  end)
  canvas:show()
  switcher.menuTimer = hs.timer.doAfter(8, hideAppActionMenu)
end

local function visibleRange(count, selected, maxVisible)
  if count <= maxVisible then
    return 1, count
  end

  local startIndex = selected - math.floor(maxVisible / 2)
  if startIndex < 1 then
    startIndex = 1
  end

  if startIndex + maxVisible - 1 > count then
    startIndex = count - maxVisible + 1
  end

  return startIndex, startIndex + maxVisible - 1
end

local function drawCandidateLabel(canvas, candidate, frame, selected)
  if candidate.isWindowTile then
    local firstLine, secondLine = splitTextTwoLines(candidate.name, 15, 15)
    local firstLineY = secondLine and frame.y or frame.y + 7
    canvas:appendElements({
      type = "text",
      text = firstLine,
      textSize = 9,
      textColor = { red = 1, green = 1, blue = 1, alpha = selected and 1 or 0.82 },
      textAlignment = "center",
      frame = { x = frame.x, y = firstLineY, w = frame.w, h = 14 },
    })

    if secondLine then
      canvas:appendElements({
        type = "text",
        text = secondLine,
        textSize = 9,
        textColor = { red = 1, green = 1, blue = 1, alpha = selected and 0.95 or 0.72 },
        textAlignment = "center",
        frame = { x = frame.x, y = frame.y + 13, w = frame.w, h = 14 },
      })
    end
    return
  end

  canvas:appendElements({
    type = "text",
    text = truncateText(candidate.name, 12),
    textSize = 11,
    textColor = { red = 1, green = 1, blue = 1, alpha = selected and 1 or 0.78 },
    textAlignment = "center",
    frame = { x = frame.x, y = frame.y + 6, w = frame.w, h = 18 },
  })
end

local function setMaximizeWindowOnSwitch(enabled)
  maximizeWindowOnSwitch = enabled and true or false
  hs.settings.set(maximizeWindowOnSwitchSettingKey, maximizeWindowOnSwitch)
end

local function toggleMaximizeWindowOnSwitch()
  setMaximizeWindowOnSwitch(not maximizeWindowOnSwitch)
  hs.alert.show(maximizeWindowOnSwitch and "自动铺满已开启" or "自动铺满已关闭")

  if switcher.active and switcher.mode == "apps" and drawSwitcherCanvas then
    drawSwitcherCanvas()
  end
end

local function setShowMinimizedWindows(enabled)
  showMinimizedWindows = enabled and true or false
  hs.settings.set(showMinimizedWindowsSettingKey, showMinimizedWindows)
end

local function refreshSwitcherCandidates()
  if not switcher.active or switcher.mode ~= "apps" or not switcher.screen or not buildScreenGroups then
    return
  end

  local candidates = appCandidatesOnScreen(switcher.screen, true)
  if #candidates == 0 then
    dismissSwitcherOverlay()
    return
  end

  switcher.candidates = candidates
  switcher.screenGroups = buildScreenGroups(switcher.screen, candidates)
  switcher.selectedIndex = math.min(math.max(1, switcher.selectedIndex or 1), #candidates)
  drawSwitcherCanvas()
end

local function toggleShowMinimizedWindows()
  setShowMinimizedWindows(not showMinimizedWindows)
  hs.alert.show(showMinimizedWindows and "显示最小化窗口已开启" or "显示最小化窗口已关闭")
  refreshSwitcherCandidates()
end

local function screenTitle(screen, isCurrent)
  local name = screen and screen:name() or "未知屏幕"
  if isCurrent then
    return "当前屏幕 · " .. name
  end

  return "其他屏幕 · " .. name
end

local function screenLayoutFrame(screen)
  if not screen then
    return { x = 0, y = 0, w = 0, h = 0 }
  end

  local ok, frame = pcall(function()
    return screen:fullFrame()
  end)
  if ok and frame then
    return frame
  end

  return screen:frame()
end

local function axisOverlap(startA, sizeA, startB, sizeB)
  return math.max(0, math.min(startA + sizeA, startB + sizeB) - math.max(startA, startB))
end

local function screensAreVerticallyStacked(screens)
  if #screens < 2 then
    return false
  end

  local verticalPairs = 0
  local horizontalPairs = 0
  for i = 1, #screens - 1 do
    for j = i + 1, #screens do
      local a = screenLayoutFrame(screens[i])
      local b = screenLayoutFrame(screens[j])
      local xOverlap = axisOverlap(a.x, a.w, b.x, b.w)
      local yOverlap = axisOverlap(a.y, a.h, b.y, b.h)
      local xOverlapRatio = xOverlap / math.max(1, math.min(a.w, b.w))
      local yOverlapRatio = yOverlap / math.max(1, math.min(a.h, b.h))

      if xOverlapRatio > 0.25 and yOverlapRatio <= 0.25 then
        verticalPairs = verticalPairs + 1
      elseif yOverlapRatio > 0.25 and xOverlapRatio <= 0.25 then
        horizontalPairs = horizontalPairs + 1
      end
    end
  end

  return verticalPairs > 0 and horizontalPairs == 0
end

local function screenPositionLessThan(a, b)
  local frameA = screenLayoutFrame(a)
  local frameB = screenLayoutFrame(b)
  if math.abs(frameA.y - frameB.y) > 8 then
    return frameA.y < frameB.y
  end

  return frameA.x < frameB.x
end

buildScreenGroups = function(activeScreen, currentCandidates)
  local groups = {}
  local activeScreenKey = screenKey(activeScreen)

  local function addGroup(screen, isCurrent, candidates)
    if not screen then
      return
    end

    candidates = candidates or appCandidatesOnScreen(screen, true)
    if #candidates == 0 then
      return
    end

    table.insert(groups, {
      screen = screen,
      key = screenKey(screen),
      title = screenTitle(screen, isCurrent),
      isCurrent = isCurrent,
      candidates = candidates,
      visibleStartIndex = 1,
      visibleEndIndex = #candidates,
    })
  end

  local screens = hs.screen.allScreens()
  if screensAreVerticallyStacked(screens) then
    table.sort(screens, screenPositionLessThan)
    local addedActiveScreen = false
    for _, screen in ipairs(screens) do
      local isCurrent = screenKey(screen) == activeScreenKey
      addGroup(screen, isCurrent, isCurrent and currentCandidates or nil)
      addedActiveScreen = addedActiveScreen or isCurrent
    end
    if not addedActiveScreen then
      addGroup(activeScreen, true, currentCandidates)
    end
  else
    addGroup(activeScreen, true, currentCandidates)

    for _, screen in ipairs(screens) do
      if screenKey(screen) ~= activeScreenKey then
        addGroup(screen, false)
      end
    end
  end

  return groups
end

drawSwitcherCanvas = function()
  hideSwitcherCanvas()
  switcher.mode = "apps"

  local count = #switcher.candidates
  if count == 0 or not switcher.screen then
    return
  end

  local frame = switcher.screen:frame()
  local itemWidth = 92
  local panelPadding = 22
  local rowHeight = 126
  local footerHeight = 54
  local maxVisible = math.max(1, math.floor((frame.w - 120) / itemWidth))
  local groups = switcher.screenGroups
  if not groups or #groups == 0 then
    groups = buildScreenGroups(switcher.screen, switcher.candidates)
    switcher.screenGroups = groups
  end

  local maxVisibleCount = 1
  for _, group in ipairs(groups) do
    local startIndex
    local endIndex

    if group.isCurrent then
      startIndex, endIndex = visibleRange(#group.candidates, switcher.selectedIndex, maxVisible)
      switcher.visibleStartIndex = startIndex
      switcher.visibleEndIndex = endIndex
    else
      startIndex = 1
      endIndex = math.min(#group.candidates, maxVisible)
    end

    group.visibleStartIndex = startIndex
    group.visibleEndIndex = endIndex
    maxVisibleCount = math.max(maxVisibleCount, endIndex - startIndex + 1)
  end

  local panelWidth = panelPadding * 2 + maxVisibleCount * itemWidth
  local panelHeight = panelPadding * 2 + #groups * rowHeight + footerHeight
  local panelX = frame.x + (frame.w - panelWidth) / 2
  local panelY = frame.y + (frame.h - panelHeight) / 2

  local canvas = hs.canvas.new({ x = panelX, y = panelY, w = panelWidth, h = panelHeight })
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  canvas:canvasMouseEvents(true, true, false, true)
  switcher.clickTargets = {}
  switcher.dropTargets = {}
  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 18, yRadius = 18 },
    fillColor = { red = 0.08, green = 0.08, blue = 0.09, alpha = 0.88 },
    frame = { x = 0, y = 0, w = panelWidth, h = panelHeight },
  })

  for groupIndex, group in ipairs(groups) do
    local rowY = panelPadding + (groupIndex - 1) * rowHeight
    local rowFrame = {
      x = panelX + panelPadding,
      y = panelY + rowY,
      w = panelWidth - panelPadding * 2,
      h = rowHeight,
    }
    table.insert(switcher.dropTargets, {
      key = group.key,
      screen = group.screen,
      isCurrent = group.isCurrent,
      frame = rowFrame,
    })
    local titleColor = group.isCurrent
      and { red = 1, green = 1, blue = 1, alpha = 0.9 }
      or { red = 1, green = 1, blue = 1, alpha = 0.58 }

    local dragState = switcher.dragState
    if dragState and dragState.dragging and dragState.targetScreenKey == group.key and dragState.sourceScreenKey ~= group.key then
      canvas:appendElements({
        type = "rectangle",
        action = "stroke",
        roundedRectRadii = { xRadius = 14, yRadius = 14 },
        strokeColor = { red = 0.22, green = 0.62, blue = 1, alpha = 0.95 },
        strokeWidth = 2.2,
        frame = { x = panelPadding + 2, y = rowY + 16, w = panelWidth - panelPadding * 2 - 4, h = rowHeight - 12 },
      })
    end

    canvas:appendElements({
      type = "text",
      text = group.title,
      textSize = 12,
      textColor = titleColor,
      textAlignment = "left",
      frame = { x = panelPadding + 8, y = rowY, w = panelWidth - panelPadding * 2 - 16, h = 18 },
    })

    if #group.candidates > group.visibleEndIndex then
      canvas:appendElements({
        type = "text",
        text = string.format("%d / %d", group.visibleEndIndex, #group.candidates),
        textSize = 10,
        textColor = { red = 1, green = 1, blue = 1, alpha = 0.42 },
        textAlignment = "right",
        frame = { x = panelPadding + 8, y = rowY, w = panelWidth - panelPadding * 2 - 16, h = 18 },
      })
    end

    for i = group.visibleStartIndex, group.visibleEndIndex do
      local candidate = group.candidates[i]
      local localIndex = i - group.visibleStartIndex
      local itemX = panelPadding + localIndex * itemWidth
      local itemY = rowY + 22
      local selected = group.isCurrent and i == switcher.selectedIndex

      if selected then
        canvas:appendElements({
          type = "rectangle",
          action = "fill",
          roundedRectRadii = { xRadius = 12, yRadius = 12 },
          fillColor = { red = 0.22, green = 0.46, blue = 0.95, alpha = 0.9 },
          frame = { x = itemX + 7, y = itemY, w = itemWidth - 14, h = 94 },
        })
      end

      canvas:appendElements({
        type = "image",
        image = candidate.icon,
        imageScaling = "scaleProportionally",
        frame = { x = itemX + 22, y = itemY + 10, w = 48, h = 48 },
      })

      local badgeText = nil
      local badgeFillColor = { red = 0.95, green = 0.42, blue = 0.12, alpha = selected and 1 or 0.86 }
      if candidate.isMinimized then
        badgeText = "最小"
        badgeFillColor = { red = 0.36, green = 0.42, blue = 0.52, alpha = selected and 1 or 0.86 }
      elseif candidate.windowCount and candidate.windowCount > 1 and not candidate.isWindowTile then
        badgeText = tostring(candidate.windowCount) .. "窗"
      end

      if badgeText then
        canvas:appendElements({
          type = "rectangle",
          action = "fill",
          roundedRectRadii = { xRadius = 7, yRadius = 7 },
          fillColor = badgeFillColor,
          frame = { x = itemX + 52, y = itemY + 7, w = 28, h = 17 },
        })
        canvas:appendElements({
          type = "text",
          text = badgeText,
          textSize = 9,
          textColor = { red = 1, green = 1, blue = 1, alpha = 0.95 },
          textAlignment = "center",
          frame = { x = itemX + 52, y = itemY + 7, w = 28, h = 17 },
        })
      end

      drawCandidateLabel(canvas, candidate, { x = itemX + 4, y = itemY + 60, w = itemWidth - 8, h = 28 }, selected)

      local digit = localIndex + 1
      if group.isCurrent and digit <= 9 then
        canvas:appendElements({
          type = "rectangle",
          action = "fill",
          roundedRectRadii = { xRadius = 7, yRadius = 7 },
          fillColor = { red = 0, green = 0, blue = 0, alpha = selected and 0.36 or 0.5 },
          frame = { x = itemX + 14, y = itemY + 7, w = 17, h = 17 },
        })
        canvas:appendElements({
          type = "text",
          text = tostring(digit),
          textSize = 10,
          textColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
          textAlignment = "center",
          frame = { x = itemX + 14, y = itemY + 7, w = 17, h = 17 },
        })
      end

      local hitboxID = "switcher-item-" .. tostring(groupIndex) .. "-" .. tostring(i)
      local tileFrame = { x = panelX + itemX + 7, y = panelY + itemY, w = itemWidth - 14, h = 94 }
      switcher.clickTargets[hitboxID] = {
        mode = "app",
        candidate = candidate,
        index = i,
        isCurrent = group.isCurrent,
        screen = group.screen,
        screenKey = group.key,
        tileFrame = tileFrame,
      }
      canvas:appendElements({
        id = hitboxID,
        type = "rectangle",
        action = "fill",
        fillColor = { red = 1, green = 1, blue = 1, alpha = 0.01 },
        frame = { x = itemX + 7, y = itemY, w = itemWidth - 14, h = 94 },
        trackMouseDown = true,
        trackMouseUp = true,
        trackMouseEnterExit = true,
        trackMouseMove = true,
      })
    end
  end

  local function drawFooterToggle(id, mode, y, checked, label)
    switcher.clickTargets[id] = { mode = mode }
    canvas:appendElements({
      id = id .. "-box",
      type = "rectangle",
      action = "stroke",
      roundedRectRadii = { xRadius = 4, yRadius = 4 },
      strokeColor = { red = 1, green = 1, blue = 1, alpha = 0.55 },
      strokeWidth = 1.4,
      frame = { x = panelPadding + 8, y = y + 2, w = 16, h = 16 },
    })
    if checked then
      canvas:appendElements({
        type = "text",
        text = "✓",
        textSize = 14,
        textColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
        textAlignment = "center",
        frame = { x = panelPadding + 8, y = y, w = 16, h = 18 },
      })
    end
    canvas:appendElements({
      type = "text",
      text = label,
      textSize = 11,
      textColor = { red = 1, green = 1, blue = 1, alpha = 0.58 },
      textAlignment = "left",
      frame = { x = panelPadding + 32, y = y + 1, w = panelWidth - panelPadding * 2 - 40, h = 18 },
    })
    canvas:appendElements({
      id = id,
      type = "rectangle",
      action = "fill",
      fillColor = { red = 1, green = 1, blue = 1, alpha = 0.01 },
      frame = { x = panelPadding + 4, y = y - 3, w = panelWidth - panelPadding * 2, h = 24 },
      trackMouseUp = true,
    })
  end

  drawFooterToggle("toggle-maximize-window-on-switch", "toggle-maximize", panelHeight - panelPadding - 44, maximizeWindowOnSwitch, "自动铺满可用区域    M 切换")
  drawFooterToggle("toggle-show-minimized-windows", "toggle-minimized", panelHeight - panelPadding - 21, showMinimizedWindows, "显示最小化窗口    I 切换")

  switcher.canvas = canvas
  canvas:mouseCallback(function(_, message, id)
    local target = switcher.clickTargets[id]
    if not target then
      if message == "mouseMove" and switcher.dragState then
        updateAppDrag()
        return
      end

      if message == "mouseUp" and switcher.dragState then
        if finishAppDrag() then
          return
        end
        if switcher.active and not commandCurrentlyDown() then
          finishSwitcher()
          return
        end
      end

      return
    end

    if target.mode == "toggle-maximize" then
      if message == "mouseUp" then
        toggleMaximizeWindowOnSwitch()
      end
      return
    end

    if target.mode == "toggle-minimized" then
      if message == "mouseUp" then
        toggleShowMinimizedWindows()
      end
      return
    end

    if message == "mouseDown" then
      local buttons = hs.eventtap.checkMouseButtons()
      if buttons.right or buttons[2] then
        switcher.rightClickTarget = id
      else
        switcher.rightClickTarget = nil
        beginAppDrag(target)
      end
      return
    end

    if message == "mouseMove" and switcher.dragState then
      if updateAppDrag() then
        return
      end
    end

    if message == "mouseEnter" or message == "mouseMove" then
      if target.isCurrent and switcher.selectedIndex ~= target.index then
        switcher.selectedIndex = target.index
        drawSwitcherCanvas()
      end
      return
    end

    if message == "mouseUp" then
      if finishAppDrag() then
        return
      end

      if switcher.rightClickTarget == id then
        showAppActionMenu(target.candidate)
        return
      end

      if target.isCurrent then
        switcher.selectedIndex = target.index
        confirmAppCandidate(target.candidate)
      else
        finishCandidate(target.candidate)
      end
    end
  end)
  canvas:show()
end

local function selectedAppCandidate()
  return switcher.candidates[switcher.selectedIndex]
end

local function enterWindowMode(candidate)
  if not candidate or not candidate.windows or #candidate.windows <= 1 then
    return false
  end

  switcher.mode = "windows"
  switcher.commandSession = false
  switcher.windowCandidate = candidate
  switcher.windowCandidates = candidate.windows
  switcher.selectedWindowIndex = 1
  drawWindowCanvas()
  return true
end

local function confirmAppCandidate(candidate)
  finishCandidate(candidate)
end

drawWindowCanvas = function()
  hideSwitcherCanvas()

  local candidate = switcher.windowCandidate
  local windows = switcher.windowCandidates or {}
  if not candidate or #windows == 0 or not switcher.screen then
    return
  end

  local frame = switcher.screen:frame()
  local panelPadding = 22
  local panelWidth = math.min(720, math.max(420, frame.w - 180))
  local rowHeight = 38
  local maxVisible = math.max(1, math.min(8, math.floor((frame.h - 220) / rowHeight)))
  local startIndex, endIndex = visibleRange(#windows, switcher.selectedWindowIndex, maxVisible)
  local visibleCount = endIndex - startIndex + 1
  switcher.visibleWindowStartIndex = startIndex
  switcher.visibleWindowEndIndex = endIndex

  local panelHeight = panelPadding * 2 + 66 + visibleCount * rowHeight
  local panelX = frame.x + (frame.w - panelWidth) / 2
  local panelY = frame.y + (frame.h - panelHeight) / 2

  local canvas = hs.canvas.new({ x = panelX, y = panelY, w = panelWidth, h = panelHeight })
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  switcher.clickTargets = {}
  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 18, yRadius = 18 },
    fillColor = { red = 0.08, green = 0.08, blue = 0.09, alpha = 0.9 },
    frame = { x = 0, y = 0, w = panelWidth, h = panelHeight },
  })

  canvas:appendElements({
    type = "image",
    image = candidate.icon,
    imageScaling = "scaleProportionally",
    frame = { x = panelPadding, y = panelPadding - 1, w = 40, h = 40 },
  })

  canvas:appendElements({
    type = "text",
    text = candidate.name .. " · 选择窗口",
    textSize = 14,
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.92 },
    textAlignment = "left",
    frame = { x = panelPadding + 52, y = panelPadding, w = panelWidth - panelPadding * 2 - 52, h = 20 },
  })

  canvas:appendElements({
    type = "text",
    text = "Tab 或 ↑↓ 选择 · Enter 确认 · Esc 返回",
    textSize = 11,
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.55 },
    textAlignment = "left",
    frame = { x = panelPadding + 52, y = panelPadding + 23, w = panelWidth - panelPadding * 2 - 52, h = 18 },
  })

  for index = startIndex, endIndex do
    local window = windows[index]
    local localIndex = index - startIndex
    local rowY = panelPadding + 58 + localIndex * rowHeight
    local selected = index == switcher.selectedWindowIndex

    if selected then
      canvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = 9, yRadius = 9 },
        fillColor = { red = 0.22, green = 0.46, blue = 0.95, alpha = 0.9 },
        frame = { x = panelPadding, y = rowY, w = panelWidth - panelPadding * 2, h = rowHeight - 4 },
      })
    end

    local digit = localIndex + 1
    if digit <= 9 then
      canvas:appendElements({
        type = "text",
        text = tostring(digit),
        textSize = 11,
        textColor = { red = 1, green = 1, blue = 1, alpha = selected and 1 or 0.55 },
        textAlignment = "center",
        frame = { x = panelPadding + 8, y = rowY + 8, w = 20, h = 16 },
      })
    end

    canvas:appendElements({
      type = "text",
      text = truncateText(windowTitle(window), 64),
      textSize = 12,
      textColor = { red = 1, green = 1, blue = 1, alpha = selected and 1 or 0.8 },
      textAlignment = "left",
      frame = { x = panelPadding + 36, y = rowY + 8, w = panelWidth - panelPadding * 2 - 44, h = 18 },
    })

    local hitboxID = "window-item-" .. tostring(index)
    switcher.clickTargets[hitboxID] = {
      window = window,
      index = index,
      mode = "windows",
    }
    canvas:appendElements({
      id = hitboxID,
      type = "rectangle",
      action = "fill",
      fillColor = { red = 1, green = 1, blue = 1, alpha = 0.01 },
      frame = { x = panelPadding, y = rowY, w = panelWidth - panelPadding * 2, h = rowHeight - 4 },
      trackMouseDown = true,
      trackMouseUp = true,
      trackMouseEnterExit = true,
      trackMouseMove = true,
    })
  end

  switcher.canvas = canvas
  canvas:mouseCallback(function(_, message, id)
    local target = switcher.clickTargets[id]
    if not target or target.mode ~= "windows" then
      return
    end

    if message == "mouseEnter" or message == "mouseMove" then
      if switcher.selectedWindowIndex ~= target.index then
        switcher.selectedWindowIndex = target.index
        drawWindowCanvas()
      end
      return
    end

    if message == "mouseUp" then
      switcher.selectedWindowIndex = target.index
      finishCandidate({ window = target.window })
    end
  end)
  canvas:show()
end

finishCandidate = function(candidate)
  dismissSwitcherOverlay()

  if candidate and candidate.window then
    focusWindow(candidate.window)
    recordWindowFocus(candidate.window)
  end
end

finishSwitcher = function()
  if not switcher.active then
    return
  end

  confirmAppCandidate(switcher.candidates[switcher.selectedIndex])
end

local function cancelSwitcher()
  if not switcher.active and not switcherOverlayVisible() then
    return
  end

  dismissSwitcherOverlay()
end

buildCandidates = function(windows)
  local candidates = {}
  for _, window in ipairs(windows) do
    local key = appKey(window)
    local appWindows = appWindowsForKeyOnScreen(window:screen(), key)
    table.insert(candidates, {
      window = appWindows[1] or window,
      key = key,
      name = appName(window),
      icon = appIcon(window),
      windows = appWindows,
      windowCount = #appWindows,
    })
  end
  return candidates
end

local function confirmSelectedWindow()
  local window = switcher.windowCandidates and switcher.windowCandidates[switcher.selectedWindowIndex]
  if window then
    finishCandidate({ window = window })
  end
end

local function digitForEvent(event)
  local characters = event:getCharacters(true)
  if characters and string.match(characters, "^[1-9]$") then
    return tonumber(characters)
  end

  local keyCode = event:getKeyCode()
  for digit = 1, 9 do
    local digitText = tostring(digit)
    if keyCode == hs.keycodes.map[digitText] or keyCode == hs.keycodes.map["pad" .. digitText] then
      return digit
    end
  end

  return nil
end

local function switchCurrentScreenApp(reverse)
  markSwitchKeyDown()

  if switcher.active then
    if switcher.mode == "windows" then
      switcher.selectedWindowIndex = nextIndex(switcher.selectedWindowIndex, #switcher.windowCandidates, reverse)
      drawWindowCanvas()
      return
    end

    switcher.selectedIndex = nextIndex(switcher.selectedIndex, #switcher.candidates, reverse)
    requestSwitcherCanvasUpdate(false)
    return
  end

  local screen = currentScreen()
  if not screen then
    return
  end

  recordWindowFocus(hs.window.focusedWindow())
  local candidates = appCandidatesOnScreen(screen, true)
  local groups = buildScreenGroups(screen, candidates)
  if #groups == 1 and #candidates == 1 then
    focusWindow(candidates[1].window)
    return
  end

  if #candidates == 0 then
    return
  end

  switcher.active = true
  switcher.screen = screen
  switcher.candidates = candidates
  switcher.screenGroups = groups
  switcher.commandSession = true

  local focusedWindow = hs.window.focusedWindow()
  local focusedWindowID = focusedWindow and focusedWindow:id()
  local focusedApp = appKey(focusedWindow)
  local focusedIndex = 1
  for index, candidate in ipairs(switcher.candidates) do
    if focusedWindowID and candidate.window and candidate.window:id() == focusedWindowID then
      focusedIndex = index
      break
    end
  end

  if focusedIndex == 1 and focusedApp then
    for index, candidate in ipairs(switcher.candidates) do
      if candidate.key == focusedApp then
        focusedIndex = index
        break
      end
    end
  end

  switcher.selectedIndex = nextIndex(focusedIndex, #switcher.candidates, reverse)
  requestSwitcherCanvasUpdate(false)
end

local function eventHasCommand(event)
  local flags = event:getFlags()
  return flags.cmd or flags.command or flags.leftcmd or flags.rightcmd
end

if switcher.eventTap then
  switcher.eventTap:stop()
  switcher.eventTap = nil
end

switcher.eventTap = hs.eventtap.new({
  hs.eventtap.event.types.flagsChanged,
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.keyUp,
}, function(event)
  local eventType = event:getType()
  if eventType == hs.eventtap.event.types.keyDown and event:getKeyCode() == hs.keycodes.map.escape then
    if switcher.active or switcherOverlayVisible() then
      cancelSwitcher()
      return true
    end
  end

  if not switcher.active then
    return false
  end

  if eventType == hs.eventtap.event.types.keyUp then
    local keyCode = event:getKeyCode()
    if isSwitchKeyCode(keyCode) or keyCode == hs.keycodes.map.tab then
      switcher.switchKeyReleased = true
      if switcher.mode == "apps" and switcher.commandSession and not commandCurrentlyDown() then
        finishSwitcher()
      end
    end
    return false
  end

  if eventType == hs.eventtap.event.types.flagsChanged then
    if switcher.mode == "windows" and not eventHasCommand(event) then
      switcher.commandSession = false
      return false
    end

    if switcher.commandSession and not eventHasCommand(event) then
      finishSwitcher()
    end
    return false
  end

  if eventType == hs.eventtap.event.types.keyDown then
    local keyCode = event:getKeyCode()
    if switcher.mode == "windows" then
      if keyCode == hs.keycodes.map.down or keyCode == hs.keycodes.map.up then
        switcher.selectedWindowIndex = nextIndex(switcher.selectedWindowIndex, #switcher.windowCandidates, keyCode == hs.keycodes.map.up)
        drawWindowCanvas()
        return true
      end

      if keyCode == hs.keycodes.map.tab then
        local flags = event:getFlags()
        switcher.selectedWindowIndex = nextIndex(switcher.selectedWindowIndex, #switcher.windowCandidates, flags.shift)
        drawWindowCanvas()
        return true
      end

      local digit = digitForEvent(event)
      if digit then
        local index = (switcher.visibleWindowStartIndex or 1) + digit - 1
        if index <= (switcher.visibleWindowEndIndex or #switcher.windowCandidates) and switcher.windowCandidates[index] then
          switcher.selectedWindowIndex = index
          confirmSelectedWindow()
          return true
        end
      end

      if keyCode == hs.keycodes.map["return"] or keyCode == hs.keycodes.map.padenter then
        confirmSelectedWindow()
        return true
      end

      return false
    end

    if keyCode == hs.keycodes.map.m then
      toggleMaximizeWindowOnSwitch()
      return true
    end

    if keyCode == hs.keycodes.map.i then
      toggleShowMinimizedWindows()
      return true
    end

    local digit = digitForEvent(event)
    if digit then
      local index = (switcher.visibleStartIndex or 1) + digit - 1
      if index <= (switcher.visibleEndIndex or #switcher.candidates) and switcher.candidates[index] then
        switcher.selectedIndex = index
        finishSwitcher()
        return true
      end
    end

    if keyCode == hs.keycodes.map["return"] or keyCode == hs.keycodes.map.padenter then
      finishSwitcher()
      return true
    end
  end

  return false
end)
switcher.eventTap:start()

switcher.releaseWatcher = hs.timer.doEvery(0.12, function()
  if switcher.eventTap and not switcher.eventTap:isEnabled() then
    switcher.eventTap:start()
  end

  local mouseDown = anyMouseButtonDown()
  if switcher.dragState and not mouseDown then
    if finishAppDrag() then
      return
    end
  end

  if not switcher.active then
    if switcher.canvas or switcher.dragCanvas or switcher.dragState then
      dismissSwitcherOverlay()
    end
    return
  end

  if not switcher.active or switcher.mode ~= "apps" or mouseDown then
    return
  end

  local elapsed = nowSeconds() - (switcher.lastSwitchEventAt or 0)
  local commandDown = commandCurrentlyDown()
  if not commandDown and not switcher.commandSession and not switcher.switchKeyReleased and elapsed > 0.5 then
    dismissSwitcherOverlay()
    return
  end

  if not commandDown and (switcher.commandSession or switcher.switchKeyReleased or elapsed > 0.2) then
    finishSwitcher()
  end
end)

function currentScreenSwitcherStatus()
  return {
    active = switcher.active,
    mode = switcher.mode,
    candidates = #switcher.candidates,
    selectedIndex = switcher.selectedIndex,
    overlayVisible = switcherOverlayVisible(),
    displayTimerPending = switcher.displayTimer ~= nil,
    verticalScreenLayout = screensAreVerticallyStacked(hs.screen.allScreens()),
    commandDown = commandCurrentlyDown(),
    maximizeWindowOnSwitch = maximizeWindowOnSwitch,
    showMinimizedWindows = showMinimizedWindows,
    windowCandidates = #switcher.windowCandidates,
    selectedWindowIndex = switcher.selectedWindowIndex,
    visibleStartIndex = switcher.visibleStartIndex,
    visibleEndIndex = switcher.visibleEndIndex,
    eventTapEnabled = switcher.eventTap and switcher.eventTap:isEnabled() or false,
    mouseDragTapEnabled = switcher.mouseDragTap and switcher.mouseDragTap:isEnabled() or false,
  }
end

local function bindSwitchKey(modifiers, key, reverse)
  local action = function()
    switchCurrentScreenApp(reverse)
  end
  table.insert(switcher.hotkeys, hs.hotkey.bind(modifiers, key, action))
end

for _, modifiers in ipairs({ {}, { "cmd" }, { "shift" }, { "cmd", "shift" } }) do
  bindSwitchKey(modifiers, "F18", false)
  bindSwitchKey(modifiers, "F19", true)
end

hs.alert.show("当前屏幕应用切换已加载")
