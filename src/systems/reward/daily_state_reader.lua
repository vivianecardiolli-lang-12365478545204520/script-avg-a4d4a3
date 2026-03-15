local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local DailyStateReader = {}

local function getLabelText(label)
    if not label then
        return ""
    end

    local text = label.ContentText
    if not text or text == "" then
        text = label.Text
    end

    return string.upper(string.gsub(text or "", "^%s*(.-)%s*$", "%1"))
end

local function parseDayIndex(frame)
    local dayLabel = frame:FindFirstChild("Day")
    if not dayLabel or not dayLabel:IsA("TextLabel") then
        return nil
    end

    local content = dayLabel.ContentText
    if not content or content == "" then
        content = dayLabel.Text
    end

    return tonumber((content or ""):match("(%d+)"))
end

local function resolveState(frame)
    local bottom = frame:FindFirstChild("Bottom")
    local bottomTextLabel = bottom and bottom:FindFirstChild("TextLabel")
    local bottomText = getLabelText(bottomTextLabel)

    local lockedFrame = frame:FindFirstChild("LockedFrame")
    local lockedVisible = lockedFrame and lockedFrame:IsA("GuiObject") and lockedFrame.Visible
    local lockIcon = lockedFrame and lockedFrame:FindFirstChild("Lock")
    local lockIconVisible = lockIcon and lockIcon:IsA("GuiObject") and lockIcon.Visible

    if bottomText == "CLAIMED" then
        return "claimed"
    end

    if lockedVisible or lockIconVisible then
        return "locked"
    end

    if bottomText == "CLAIM" then
        return "available"
    end

    return "unknown"
end

local function getPlayerGui()
    local player = Players.LocalPlayer
    if not player then
        return nil
    end

    return player:FindFirstChild("PlayerGui")
end

local function getHolder()
    local playerGui = getPlayerGui()
    local dailyRewards = playerGui and playerGui:FindFirstChild("DailyRewards")
    return dailyRewards and dailyRewards:FindFirstChild("Holder")
end

local function fireButton(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    local fired = false

    local okActivated = pcall(function()
        firesignal(button.Activated)
    end)
    fired = fired or okActivated

    local okMouse = pcall(function()
        firesignal(button.MouseButton1Click)
    end)
    fired = fired or okMouse

    local okActivateMethod = pcall(function()
        button:Activate()
    end)
    fired = fired or okActivateMethod

    return fired
end

local function clickAt(x, y)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
    task.wait()
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

local function clickCloseFallback(holder)
    if not holder or not holder:IsA("GuiObject") then
        return false
    end

    local pos = holder.AbsolutePosition
    local size = holder.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return false
    end

    local x = math.floor(pos.X + (size.X * 0.96))
    local y = math.floor(pos.Y + (size.Y * 0.06))
    clickAt(x, y)
    task.wait(0.2)

    return true
end

local function findBannerButtonByType(holder, typeName)
    local rewardTypes = holder and holder:FindFirstChild("RewardTypes")
    if not rewardTypes then
        return nil
    end

    local expected = string.upper(typeName or "")
    for _, child in ipairs(rewardTypes:GetChildren()) do
        if child:IsA("Frame") and child.Name == "BaseBanner" then
            local bannerType = child:FindFirstChild("BannerType")
            local label = bannerType and bannerType:IsA("TextLabel") and bannerType
            local text = getLabelText(label)
            if text == expected then
                local button = child:FindFirstChild("Button")
                if button and button:IsA("GuiButton") then
                    return button
                end
            end
        end
    end

    return nil
end

function DailyStateReader.ensureMenuOpen()
    for _ = 1, 3 do
        local holder = getHolder()
        if holder and holder:IsA("GuiObject") and holder.Visible then
            return true
        end

        local playerGui = getPlayerGui()
        local hud = playerGui and playerGui:FindFirstChild("HUD")
        local sideButtons = hud and hud:FindFirstChild("SideButtons")
        local dailyButton = sideButtons and sideButtons:FindFirstChild("DailyRewardsButton")

        if not dailyButton then
            return false
        end

        local buttonToFire = nil
        if dailyButton:IsA("GuiButton") then
            buttonToFire = dailyButton
        else
            local nested = dailyButton:FindFirstChild("Button")
            if nested and nested:IsA("GuiButton") then
                buttonToFire = nested
            end
        end

        if not fireButton(buttonToFire) then
            return false
        end

        task.wait(0.35)
    end

    local holder = getHolder()
    return holder ~= nil and holder.Visible
end

function DailyStateReader.selectType(typeName)
    for _ = 1, 3 do
        local holder = getHolder()
        if not holder then
            return false
        end

        local button = findBannerButtonByType(holder, typeName)
        if not button then
            return false
        end

        if fireButton(button) then
            task.wait(0.25)
            return true
        end
    end

    return false
end

function DailyStateReader.closeMenu()
    local holder = getHolder()
    if not holder or not holder:IsA("GuiObject") or not holder.Visible then
        return true
    end

    local close = holder:FindFirstChild("Close")
    if not close then
        return false
    end

    local candidates = {}
    local nested = close:FindFirstChild("Button")
    if nested and nested:IsA("GuiButton") then
        table.insert(candidates, nested)
    end
    if close:IsA("GuiButton") then
        table.insert(candidates, close)
    end

    for _, button in ipairs(candidates) do
        if fireButton(button) then
            task.wait(0.2)

            holder = getHolder()
            if not holder or not holder:IsA("GuiObject") or not holder.Visible then
                return true
            end
        end
    end

    holder = getHolder()
    if clickCloseFallback(holder) then
        holder = getHolder()
        if not holder or not holder:IsA("GuiObject") or not holder.Visible then
            return true
        end
    end

    return false
end

function DailyStateReader.read()
    local holder = getHolder()
    local rewardsList = holder and holder:FindFirstChild("RewardsList")
    if not rewardsList then
        return {
            listFound = false,
            cards = {},
        }
    end

    local cards = {}
    for _, child in ipairs(rewardsList:GetChildren()) do
        if child:IsA("Frame") and (child.Name == "RewardFrame" or child.Name == "SpecialRewardFrame") then
            local dayIndex = parseDayIndex(child)

            table.insert(cards, {
                dayIndex = dayIndex,
                frameType = child.Name,
                state = resolveState(child),
            })
        end
    end

    return {
        listFound = true,
        cards = cards,
    }
end

return DailyStateReader
