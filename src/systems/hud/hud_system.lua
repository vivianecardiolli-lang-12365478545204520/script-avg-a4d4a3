local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local config = require("core.config")
local StatusBus = require("core.status_bus")

local HudSystem = {}

local hudGui
local panel
local floatingButton
local closeButton
local statusLabel
local gemsLabel
local levelLabel
local traitsLabel
local isMenuVisible = true
local floatingPosition = UDim2.new(0.5, 0, 0, 26)
local floatingWasDragged = false
local dragState = {
    dragging = false,
    dragStart = nil,
    buttonStart = nil,
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

local function applyVisibility()
    if panel then
        panel.Visible = isMenuVisible
    end
    if floatingButton then
        floatingButton.Visible = not isMenuVisible
        if not isMenuVisible then
            if not floatingWasDragged then
                floatingButton.Position = floatingPosition
            end
            clampFloatingToViewport()
        end
    end
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
    label.TextSize = 40
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.Text = text
    label.ZIndex = 10001
    return label
end

local function setStatusText(statusText)
    if statusLabel then
        statusLabel.Text = string.format("Status: %s", tostring(statusText))
    end
end

local function refreshValues()
    if gemsLabel then
        gemsLabel.Text = "Gemas: " .. readAttribute("Gems")
    end
    if levelLabel then
        levelLabel.Text = "Level: " .. readAttribute("Level")
    end
    if traitsLabel then
        traitsLabel.Text = "Traits: " .. readAttribute("TraitRerolls")
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

local function bindFloatingDrag()
    floatingButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragState.dragging = true
            dragState.dragStart = input.Position
            dragState.buttonStart = floatingButton.Position
            floatingWasDragged = false
        end
    end)

    floatingButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragState.lastInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragState.dragging then
            return
        end
        if not (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            return
        end

        local delta = input.Position - dragState.dragStart
        if delta.Magnitude > 4 then
            floatingWasDragged = true
        end

        floatingButton.Position = UDim2.new(
            0,
            dragState.buttonStart.X.Offset + delta.X,
            0,
            dragState.buttonStart.Y.Offset + delta.Y
        )
        clampFloatingToViewport()
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragState.dragging = false
            if floatingButton then
                floatingPosition = floatingButton.Position
            end
        end
    end)

    floatingButton.Activated:Connect(function()
        if dragState.dragging or floatingWasDragged then
            return
        end
        openMenu()
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

local function buildHud()
    local playerGui = getPlayerGui()
    if not playerGui then
        return
    end

    local existing = playerGui:FindFirstChild("KaitunHUD")
    if existing and existing:IsA("ScreenGui") then
        existing:Destroy()
    end

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "KaitunHUD"
    hudGui.ResetOnSpawn = false
    hudGui.DisplayOrder = 999999
    hudGui.IgnoreGuiInset = true
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = playerGui

    panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Parent = hudGui
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(0.94, 0.9)
    panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
    panel.BackgroundTransparency = 0.1
    panel.ZIndex = 10000

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(620, 460)
    sizeConstraint.MaxSize = Vector2.new(2200, 1600)
    sizeConstraint.Parent = panel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(88, 98, 122)
    stroke.Parent = panel

    closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Parent = panel
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -18, 0, 14)
    closeButton.Size = UDim2.fromOffset(56, 56)
    closeButton.AutoButtonColor = true
    closeButton.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 30
    closeButton.Text = "X"
    closeButton.ZIndex = 10003

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeButton

    local closeStroke = Instance.new("UIStroke")
    closeStroke.Thickness = 1.5
    closeStroke.Color = Color3.fromRGB(95, 110, 140)
    closeStroke.Parent = closeButton

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Parent = panel
    content.BackgroundTransparency = 1
    content.Position = UDim2.new(0, 28, 0, 84)
    content.Size = UDim2.new(1, -56, 1, -110)
    content.ZIndex = 10001

    local layout = Instance.new("UIListLayout")
    layout.Parent = content
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Padding = UDim.new(0, 16)

    gemsLabel = makeValueLabel("Gems", "Gemas: 0", content)
    levelLabel = makeValueLabel("Level", "Level: 0", content)
    traitsLabel = makeValueLabel("Traits", "Traits: 0", content)
    statusLabel = makeValueLabel("Status", "Status: Idle", content)

    closeButton.Activated:Connect(function()
        closeMenu()
    end)

    floatingButton = Instance.new("TextButton")
    floatingButton.Name = "FloatingOpenButton"
    floatingButton.Parent = hudGui
    floatingButton.AnchorPoint = Vector2.new(0.5, 0.5)
    floatingButton.Position = floatingPosition
    floatingButton.Size = UDim2.fromOffset(76, 76)
    floatingButton.AutoButtonColor = true
    floatingButton.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
    floatingButton.TextColor3 = Color3.fromRGB(245, 245, 245)
    floatingButton.Font = Enum.Font.GothamBlack
    floatingButton.TextSize = 38
    floatingButton.Text = "⚡"
    floatingButton.ZIndex = 10004
    floatingButton.Visible = false

    local floatingCorner = Instance.new("UICorner")
    floatingCorner.CornerRadius = UDim.new(1, 0)
    floatingCorner.Parent = floatingButton

    local floatingStroke = Instance.new("UIStroke")
    floatingStroke.Thickness = 1.5
    floatingStroke.Color = Color3.fromRGB(110, 125, 160)
    floatingStroke.Parent = floatingButton

    bindFloatingDrag()
end

function HudSystem.setStatus(statusText)
    setStatusText(statusText)
end

function HudSystem.start()
    if not config.hud.enabled then
        return
    end

    buildHud()
    refreshValues()
    setStatusText(StatusBus.get())
    bindToggleKey()
    applyVisibility()

    StatusBus.subscribe(function(newStatus)
        setStatusText(newStatus)
    end)

    local player = getPlayer()
    if player then
        player:GetAttributeChangedSignal("Gems"):Connect(refreshValues)
        player:GetAttributeChangedSignal("Level"):Connect(refreshValues)
        player:GetAttributeChangedSignal("TraitRerolls"):Connect(refreshValues)
    end

    if hudGui then
        hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if floatingButton and floatingButton.Visible then
                clampFloatingToViewport()
            end
        end)
    end
end

return HudSystem
