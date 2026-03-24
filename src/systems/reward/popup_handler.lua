local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Logger = require("core.logger")

local PopupHandler = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function clickRewardsScreen()
    Logger.log("Closing RewardsScreen")
    PopupHandler.tapAnywhere()
end

local function clickCancelPopup()
    local popup = playerGui:FindFirstChild("PopupScreen")
    if not popup then
        return false
    end

    local baseCancelFrame = popup:FindFirstChild("BaseCancelFrame")
    local main = baseCancelFrame and baseCancelFrame:FindFirstChild("Main")
    local buttons = main and main:FindFirstChild("Buttons")
    local cancel = buttons and buttons:FindFirstChild("Cancel")
    local button = cancel and cancel:FindFirstChild("Button")

    if not button or not button:IsA("GuiButton") then
        return false
    end

    Logger.log("Cancel popup detected")
    firesignal(button.Activated)
    Logger.log("Cancel closed")

    return true
end

local function closeRewardPopup()
    local reward = playerGui:FindFirstChild("RewardsScreen")

    if reward then
        Logger.log("RewardsScreen detected")
        clickRewardsScreen()
        return true
    end

    return false
end

local function closeLevelFramePopup()
    local levelFrame = playerGui:FindFirstChild("LevelFrame")
    if not levelFrame or not levelFrame:IsA("ScreenGui") or not levelFrame.Enabled then
        return false
    end

    local holder = levelFrame:FindFirstChild("Holder")
    if not holder or not holder:IsA("GuiObject") or not holder.Visible then
        return false
    end

    Logger.log("LevelFrame popup detected")
    local background = levelFrame:FindFirstChild("Background")
    if background and background:IsA("GuiObject") then
        local pos = background.AbsolutePosition
        local size = background.AbsoluteSize
        local x = math.floor(pos.X + (size.X * 0.5))
        local y = math.floor(pos.Y + (size.Y * 0.5))
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    else
        PopupHandler.tapAnywhere()
    end
    task.wait(0.05)
    Logger.log("LevelFrame popup closed")
    return true
end

function PopupHandler.handle(timeoutSeconds, pollIntervalSeconds)
    local start = tick()
    local timeout = timeoutSeconds or 3
    local pollInterval = pollIntervalSeconds or 0.2

    while tick() - start < timeout do
        if clickCancelPopup() then
            return true
        end

        if closeRewardPopup() then
            return true
        end

        if closeLevelFramePopup() then
            return true
        end

        task.wait(pollInterval)
    end

    Logger.log("No popup detected")
    return false
end

function PopupHandler.tapAnywhere()
    VirtualInputManager:SendMouseButtonEvent(500, 500, 0, true, game, 1)
    task.wait()
    VirtualInputManager:SendMouseButtonEvent(500, 500, 0, false, game, 1)
end

return PopupHandler
