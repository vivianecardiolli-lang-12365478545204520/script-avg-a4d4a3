local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local config = require("core.config")
local StatusBus = require("core.status_bus")

local HudSystem = {}

local hudGui
local statusLabel
local gemsLabel
local levelLabel
local traitsLabel
local visible = true

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

local function makeTextLabel(name, text, parent, posYScale)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Parent = parent
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -20, 0.2, 0)
    label.Position = UDim2.new(0, 10, posYScale, 0)
    label.Font = Enum.Font.Gotham
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(230, 230, 230)
    label.Text = text
    label.ZIndex = 10001
    return label
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

    local frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.Parent = hudGui
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromScale(0.42, 0.24)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    frame.BackgroundTransparency = 0.2
    frame.ZIndex = 10000

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(420, 190)
    sizeConstraint.MaxSize = Vector2.new(900, 420)
    sizeConstraint.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(70, 70, 80)
    stroke.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = frame

    gemsLabel = makeTextLabel("Gems", "💎 Gemas: 0", frame, 0.00)
    levelLabel = makeTextLabel("Level", "⭐ Level: 0", frame, 0.25)
    traitsLabel = makeTextLabel("Traits", "🔮 Traits: 0", frame, 0.50)
    statusLabel = makeTextLabel("Status", "📌 Status: Idle", frame, 0.75)
end

local function refreshValues()
    if not hudGui or not hudGui.Parent then
        return
    end
    if gemsLabel then
        gemsLabel.Text = "💎 Gemas: " .. readAttribute("Gems")
    end
    if levelLabel then
        levelLabel.Text = "⭐ Level: " .. readAttribute("Level")
    end
    if traitsLabel then
        traitsLabel.Text = "🔮 Traits: " .. readAttribute("TraitRerolls")
    end
end

local function setStatusText(statusText)
    if statusLabel then
        statusLabel.Text = string.format("📌 %s: %s", tostring(config.hud.statusPrefix), tostring(statusText))
    end
end

local function bindToggle()
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
            visible = not visible
            if hudGui then
                hudGui.Enabled = visible
            end
        end
    end)
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
    bindToggle()

    StatusBus.subscribe(function(newStatus)
        setStatusText(newStatus)
    end)

    local player = getPlayer()
    if player then
        player:GetAttributeChangedSignal("Gems"):Connect(refreshValues)
        player:GetAttributeChangedSignal("Level"):Connect(refreshValues)
        player:GetAttributeChangedSignal("TraitRerolls"):Connect(refreshValues)
    end
end

return HudSystem
