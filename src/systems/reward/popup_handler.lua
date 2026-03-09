local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Logger = require("core.logger")

local PopupHandler = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function clickRewardsScreen()
    Logger.log("Closing RewardsScreen")

    VirtualInputManager:SendMouseButtonEvent(500, 500, 0, true, game, 1)
    task.wait()
    VirtualInputManager:SendMouseButtonEvent(500, 500, 0, false, game, 1)
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

function PopupHandler.handle(timeoutSeconds)
    local start = tick()
    local timeout = timeoutSeconds or 3

    while tick() - start < timeout do
        if clickCancelPopup() then
            return true
        end

        if closeRewardPopup() then
            return true
        end

        task.wait(0.2)
    end

    Logger.log("No popup detected")
    return false
end

return PopupHandler