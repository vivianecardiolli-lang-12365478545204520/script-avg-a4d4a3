local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local config = require("core.config")
local StatusBus = require("core.status_bus")
local Logger = require("core.logger")

local HudSystem = {}

local EMOJI_GEMS = utf8.char(0x1F48E)
local EMOJI_LEVEL = utf8.char(0x2B50)
local EMOJI_TRAITS = utf8.char(0x1F52E)
local EMOJI_STATUS = utf8.char(0x1F4CC)
local EMOJI_FLOATING = utf8.char(0x26A1)

local ROOT_NAME = "RuntimeOverlayRoot"
local GUI_NAME = "RuntimeOverlayGui"

local ROOT_BASE_SIZE = UDim2.fromScale(0.752, 0.9)
local ROOT_BASE_POSITION = UDim2.fromScale(0.5, 0.5)
local ROOT_BASE_BG_COLOR = Color3.fromRGB(16, 18, 24)
local ROOT_BASE_BG_TRANSPARENCY = 0.1

local hudGui
local rootFrame
local contentFrame
local floatingButton
local closeButton
local gemsLabel
local levelLabel
local traitsLabel
local statusLabel

local isMenuVisible = true
local floatingPosition = UDim2.new(0, 0, 0, 0)
local hasCustomFloatingPosition = false
local floatingDrag = {
    dragging = false,
    startInput = nil,
    startPos = nil,
    buttonStartPos = nil,
    moved = false,
}
local guardingRoot = false
local ownedRootChildren = {}

local diagnostics = {
    enabled = false,
    lastLogAt = {},
    lastValueByKey = {},
}

local function getPlayer()
    return Players.LocalPlayer
end

local function getPlayerGui()
    local player = getPlayer()
    return player and player:FindFirstChild("PlayerGui")
end

local function readAttribute(attributeName)
    local player = getPlayer()
    if not player then
        return "0"
    end
    local value = player:GetAttribute(attributeName)
    if value == nil then
        return "0"
    end
    return tostring(value)
end

local function diagLog(key, message)
    if not diagnostics.enabled then
        return
    end
    local now = os.clock()
    local minInterval = 0.15
    local lastAt = diagnostics.lastLogAt[key] or 0
    if now - lastAt < minInterval then
        return
    end
    diagnostics.lastLogAt[key] = now
    Logger.log("[HUD-DIAG] " .. tostring(message))
end

local function udim2ToString(v)
    if typeof(v) ~= "UDim2" then
        return tostring(v)
    end
    return string.format("UDim2(%0.3f,%d,%0.3f,%d)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
end

local function colorToString(v)
    if typeof(v) ~= "Color3" then
        return tostring(v)
    end
    return string.format("Color3(%0.3f,%0.3f,%0.3f)", v.R, v.G, v.B)
end

local function watchProperty(instance, instanceName, propertyName, formatter)
    if not diagnostics.enabled or not instance then
        return
    end

    local function emit()
        local value = instance[propertyName]
        local text = formatter and formatter(value) or tostring(value)
        local dedupeKey = instanceName .. "." .. propertyName
        if diagnostics.lastValueByKey[dedupeKey] == text then
            return
        end
        diagnostics.lastValueByKey[dedupeKey] = text
        diagLog(dedupeKey, string.format("%s.%s => %s", instanceName, propertyName, text))
    end

    emit()
    instance:GetPropertyChangedSignal(propertyName):Connect(emit)
end

local function clampFloatingToViewport()
    if not hudGui or not floatingButton then
        return
    end
    local viewport = hudGui.AbsoluteSize
    local size = floatingButton.AbsoluteSize
    local x = floatingButton.Position.X.Offset
    local y = floatingButton.Position.Y.Offset

    local halfW = math.floor(size.X * 0.5)
    local halfH = math.floor(size.Y * 0.5)
    local minX = halfW
    local maxX = math.max(halfW, viewport.X - halfW)
    local minY = halfH
    local maxY = math.max(halfH, viewport.Y - halfH)

    if x < minX then
        x = minX
    elseif x > maxX then
        x = maxX
    end

    if y < minY then
        y = minY
    elseif y > maxY then
        y = maxY
    end

    floatingPosition = UDim2.new(0, x, 0, y)
    floatingButton.Position = floatingPosition
end

local function setDefaultFloatingPosition()
    if not hudGui then
        return
    end
    local viewport = hudGui.AbsoluteSize
    local centerX = math.floor(viewport.X * 0.5)
    floatingPosition = UDim2.new(0, centerX, 0, 56)
end

local function updateTextSizing()
    if not rootFrame then
        return
    end

    local h = rootFrame.AbsoluteSize.Y
    local baseSize = math.floor(math.clamp(h * 0.09, 40, 86))
    local statusSize = math.floor(math.clamp(baseSize * 0.92, 36, 80))

    if gemsLabel then
        gemsLabel.TextSize = baseSize
    end
    if levelLabel then
        levelLabel.TextSize = baseSize
    end
    if traitsLabel then
        traitsLabel.TextSize = baseSize
    end
    if statusLabel then
        statusLabel.TextSize = statusSize
    end
end

local function applyVisibility()
    if rootFrame then
        rootFrame.Visible = isMenuVisible
    end
    if floatingButton then
        floatingButton.Visible = not isMenuVisible
        if floatingButton.Visible then
            if not hasCustomFloatingPosition then
                setDefaultFloatingPosition()
            end
            floatingButton.Position = floatingPosition
            clampFloatingToViewport()
        end
    end
end

local function setStatusText(statusText)
    if statusLabel then
        statusLabel.Text = string.format("%s Status: %s", EMOJI_STATUS, tostring(statusText))
    end
end

local function refreshValues()
    if gemsLabel then
        gemsLabel.Text = string.format("%s Gemas: %s", EMOJI_GEMS, readAttribute("Gems"))
    end
    if levelLabel then
        levelLabel.Text = string.format("%s Level: %s", EMOJI_LEVEL, readAttribute("Level"))
    end
    if traitsLabel then
        traitsLabel.Text = string.format("%s Traits: %s", EMOJI_TRAITS, readAttribute("TraitRerolls"))
    end
end

local function openMenu()
    isMenuVisible = true
    applyVisibility()
end

local function closeMenu()
    isMenuVisible = false
    applyVisibility()
end

local function toggleMenu()
    if isMenuVisible then
        closeMenu()
    else
        openMenu()
    end
end

local function enforceRootGuard()
    if not rootFrame or guardingRoot then
        return
    end

    guardingRoot = true

    if rootFrame.Size ~= ROOT_BASE_SIZE then
        rootFrame.Size = ROOT_BASE_SIZE
    end
    if rootFrame.Position ~= ROOT_BASE_POSITION then
        rootFrame.Position = ROOT_BASE_POSITION
    end
    if rootFrame.BackgroundColor3 ~= ROOT_BASE_BG_COLOR then
        rootFrame.BackgroundColor3 = ROOT_BASE_BG_COLOR
    end
    if rootFrame.BackgroundTransparency ~= ROOT_BASE_BG_TRANSPARENCY then
        rootFrame.BackgroundTransparency = ROOT_BASE_BG_TRANSPARENCY
    end

    for _, child in ipairs(rootFrame:GetChildren()) do
        if not ownedRootChildren[child] then
            diagLog("guard.remove_child", "Removendo filho injetado em RuntimeOverlayRoot: " .. child.ClassName .. " (" .. child.Name .. ")")
            child:Destroy()
        end
    end

    guardingRoot = false
end

local function bindRootGuard()
    if not rootFrame then
        return
    end

    rootFrame:GetPropertyChangedSignal("Size"):Connect(function()
        enforceRootGuard()
    end)
    rootFrame:GetPropertyChangedSignal("Position"):Connect(function()
        enforceRootGuard()
    end)
    rootFrame:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
        enforceRootGuard()
    end)
    rootFrame:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
        enforceRootGuard()
    end)

    rootFrame.ChildAdded:Connect(function()
        enforceRootGuard()
    end)
end

local function makeValueLabel(name, text, parent)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Parent = parent
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Font = Enum.Font.GothamBold
    label.TextScaled = false
    label.TextSize = 56
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.Text = text
    label.ZIndex = 10001

    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = 36
    textConstraint.MaxTextSize = 86
    textConstraint.Parent = label

    return label
end

local function bindFloatingDragAndTap()
    floatingButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            floatingDrag.dragging = true
            floatingDrag.startInput = input
            floatingDrag.startPos = input.Position
            floatingDrag.buttonStartPos = floatingButton.Position
            floatingDrag.moved = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not floatingDrag.dragging then
            return
        end

        local isMouseDrag = floatingDrag.startInput and floatingDrag.startInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement
        local isTouchDrag = floatingDrag.startInput and floatingDrag.startInput.UserInputType == Enum.UserInputType.Touch
            and input.UserInputType == Enum.UserInputType.Touch

        if not isMouseDrag and not isTouchDrag then
            return
        end

        local delta = input.Position - floatingDrag.startPos
        if delta.Magnitude > 4 then
            floatingDrag.moved = true
        end

        floatingButton.Position = UDim2.new(
            0,
            floatingDrag.buttonStartPos.X.Offset + delta.X,
            0,
            floatingDrag.buttonStartPos.Y.Offset + delta.Y
        )
        clampFloatingToViewport()
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not floatingDrag.dragging then
            return
        end

        local endedMouse = input.UserInputType == Enum.UserInputType.MouseButton1 and floatingDrag.startInput and floatingDrag.startInput.UserInputType == Enum.UserInputType.MouseButton1
        local endedTouch = input.UserInputType == Enum.UserInputType.Touch and floatingDrag.startInput and floatingDrag.startInput.UserInputType == Enum.UserInputType.Touch
        if not endedMouse and not endedTouch then
            return
        end

        floatingDrag.dragging = false
        if floatingDrag.moved then
            floatingPosition = floatingButton.Position
            hasCustomFloatingPosition = true
        end

        if not floatingDrag.moved then
            openMenu()
        end

        floatingDrag.startInput = nil
    end)
end

local function bindToggleKey()
    local toggleKeyName = tostring(config.hud.toggleKey or "B")
    local toggleKey = Enum.KeyCode.B
    local customKey = Enum.KeyCode[toggleKeyName]
    if customKey then
        toggleKey = customKey
    end

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == toggleKey then
            toggleMenu()
        end
    end)
end

local function attachDiagnostics()
    diagnostics.enabled = config.hud and config.hud.diagnosticsEnabled == true
    if not diagnostics.enabled then
        return
    end

    diagnostics.lastLogAt = {}
    diagnostics.lastValueByKey = {}
    diagLog("boot", "Diagnostico de HUD ativado.")

    watchProperty(rootFrame, ROOT_NAME, "Size", udim2ToString)
    watchProperty(rootFrame, ROOT_NAME, "Position", udim2ToString)
    watchProperty(rootFrame, ROOT_NAME, "BackgroundTransparency", tostring)
    watchProperty(rootFrame, ROOT_NAME, "BackgroundColor3", colorToString)
    watchProperty(rootFrame, ROOT_NAME, "Visible", tostring)

    watchProperty(closeButton, "RuntimeOverlayClose", "AutoButtonColor", tostring)
    watchProperty(closeButton, "RuntimeOverlayClose", "BackgroundTransparency", tostring)
    watchProperty(closeButton, "RuntimeOverlayClose", "BackgroundColor3", colorToString)
    watchProperty(closeButton, "RuntimeOverlayClose", "Size", udim2ToString)

    watchProperty(floatingButton, "RuntimeOverlayFloating", "Visible", tostring)
    watchProperty(floatingButton, "RuntimeOverlayFloating", "Position", udim2ToString)

    rootFrame.ChildAdded:Connect(function(child)
        diagLog("root.child_added", ROOT_NAME .. ".ChildAdded -> " .. child.ClassName .. " (" .. child.Name .. ")")
    end)

    closeButton.MouseEnter:Connect(function()
        diagLog("close.hover.enter", "RuntimeOverlayClose.MouseEnter")
    end)
    closeButton.MouseLeave:Connect(function()
        diagLog("close.hover.leave", "RuntimeOverlayClose.MouseLeave")
    end)
    rootFrame.MouseEnter:Connect(function()
        diagLog("root.hover.enter", ROOT_NAME .. ".MouseEnter")
    end)
    rootFrame.MouseLeave:Connect(function()
        diagLog("root.hover.leave", ROOT_NAME .. ".MouseLeave")
    end)
end

local function buildHud()
    local playerGui = getPlayerGui()
    if not playerGui then
        return
    end

    local existing = playerGui:FindFirstChild(GUI_NAME)
    if existing and existing:IsA("ScreenGui") then
        existing:Destroy()
    end

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = GUI_NAME
    hudGui.ResetOnSpawn = false
    hudGui.DisplayOrder = 999999
    hudGui.IgnoreGuiInset = true
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = playerGui

    rootFrame = Instance.new("Frame")
    rootFrame.Name = ROOT_NAME
    rootFrame.Parent = hudGui
    rootFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    rootFrame.Position = ROOT_BASE_POSITION
    rootFrame.Size = ROOT_BASE_SIZE
    rootFrame.BackgroundColor3 = ROOT_BASE_BG_COLOR
    rootFrame.BackgroundTransparency = ROOT_BASE_BG_TRANSPARENCY
    rootFrame.ZIndex = 10000
    rootFrame.ClipsDescendants = true

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.Name = "RuntimeOverlaySizeConstraint"
    sizeConstraint.MinSize = Vector2.new(620, 460)
    sizeConstraint.MaxSize = Vector2.new(2200, 1600)
    sizeConstraint.Parent = rootFrame

    local corner = Instance.new("UICorner")
    corner.Name = "RuntimeOverlayCorner"
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = rootFrame

    local stroke = Instance.new("UIStroke")
    stroke.Name = "RuntimeOverlayStroke"
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(88, 98, 122)
    stroke.Parent = rootFrame

    closeButton = Instance.new("TextButton")
    closeButton.Name = "RuntimeOverlayClose"
    closeButton.Parent = rootFrame
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -18, 0, 14)
    closeButton.Size = UDim2.fromOffset(56, 56)
    closeButton.AutoButtonColor = false
    closeButton.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 30
    closeButton.Text = "X"
    closeButton.ZIndex = 10003

    local closeCorner = Instance.new("UICorner")
    closeCorner.Name = "RuntimeOverlayCloseCorner"
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeButton

    local closeStroke = Instance.new("UIStroke")
    closeStroke.Name = "RuntimeOverlayCloseStroke"
    closeStroke.Thickness = 1.5
    closeStroke.Color = Color3.fromRGB(95, 110, 140)
    closeStroke.Parent = closeButton

    contentFrame = Instance.new("Frame")
    contentFrame.Name = "RuntimeOverlayContent"
    contentFrame.Parent = rootFrame
    contentFrame.BackgroundTransparency = 1
    contentFrame.Position = UDim2.new(0, 28, 0, 84)
    contentFrame.Size = UDim2.new(1, -56, 1, -110)
    contentFrame.ZIndex = 10001
    contentFrame.ClipsDescendants = true

    local layout = Instance.new("UIListLayout")
    layout.Name = "RuntimeOverlayContentLayout"
    layout.Parent = contentFrame
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding = UDim.new(0, 14)

    gemsLabel = makeValueLabel("RuntimeOverlayStatsGems", string.format("%s Gemas: 0", EMOJI_GEMS), contentFrame)
    levelLabel = makeValueLabel("RuntimeOverlayStatsLevel", string.format("%s Level: 0", EMOJI_LEVEL), contentFrame)
    traitsLabel = makeValueLabel("RuntimeOverlayStatsTraits", string.format("%s Traits: 0", EMOJI_TRAITS), contentFrame)
    statusLabel = makeValueLabel("RuntimeOverlayStatus", string.format("%s Status: Idle", EMOJI_STATUS), contentFrame)

    closeButton.Activated:Connect(function()
        closeMenu()
    end)

    floatingButton = Instance.new("TextButton")
    floatingButton.Name = "RuntimeOverlayFloating"
    floatingButton.Parent = hudGui
    floatingButton.AnchorPoint = Vector2.new(0.5, 0.5)
    if not hasCustomFloatingPosition then
        setDefaultFloatingPosition()
    end
    floatingButton.Position = floatingPosition
    floatingButton.Size = UDim2.fromOffset(76, 76)
    floatingButton.AutoButtonColor = true
    floatingButton.Active = true
    floatingButton.Selectable = true
    floatingButton.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
    floatingButton.TextColor3 = Color3.fromRGB(245, 245, 245)
    floatingButton.Font = Enum.Font.GothamBlack
    floatingButton.TextSize = 38
    floatingButton.Text = EMOJI_FLOATING
    floatingButton.ZIndex = 10004
    floatingButton.Visible = false

    local floatingCorner = Instance.new("UICorner")
    floatingCorner.Name = "RuntimeOverlayFloatingCorner"
    floatingCorner.CornerRadius = UDim.new(1, 0)
    floatingCorner.Parent = floatingButton

    local floatingStroke = Instance.new("UIStroke")
    floatingStroke.Name = "RuntimeOverlayFloatingStroke"
    floatingStroke.Thickness = 1.5
    floatingStroke.Color = Color3.fromRGB(110, 125, 160)
    floatingStroke.Parent = floatingButton

    ownedRootChildren = {
        [sizeConstraint] = true,
        [corner] = true,
        [stroke] = true,
        [closeButton] = true,
        [contentFrame] = true,
    }

    bindRootGuard()
    bindFloatingDragAndTap()
end

function HudSystem.setStatus(statusText)
    setStatusText(statusText)
end

function HudSystem.start()
    if not config.hud.enabled then
        return
    end

    buildHud()
    attachDiagnostics()
    updateTextSizing()
    refreshValues()
    setStatusText(StatusBus.get())
    bindToggleKey()
    applyVisibility()
    enforceRootGuard()

    StatusBus.subscribe(function(newStatus)
        setStatusText(newStatus)
    end)

    local player = getPlayer()
    if player then
        player:GetAttributeChangedSignal("Gems"):Connect(refreshValues)
        player:GetAttributeChangedSignal("Level"):Connect(refreshValues)
        player:GetAttributeChangedSignal("TraitRerolls"):Connect(refreshValues)
    end

    if rootFrame then
        rootFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            updateTextSizing()
        end)
    end

    if hudGui then
        hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if floatingButton and floatingButton.Visible then
                if not hasCustomFloatingPosition then
                    setDefaultFloatingPosition()
                    floatingButton.Position = floatingPosition
                end
                clampFloatingToViewport()
            end
        end)
    end
end

return HudSystem
