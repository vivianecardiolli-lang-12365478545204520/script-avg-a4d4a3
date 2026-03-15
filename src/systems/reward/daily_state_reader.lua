local Players = game:GetService("Players")

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

    if bottomText == "CLAIM" then
        return "available"
    end

    if bottomText == "CLAIMED" then
        return "claimed"
    end

    if lockedVisible then
        return "locked"
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

    local ok = pcall(function()
        firesignal(button.Activated)
    end)

    return ok
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

    holder = getHolder()
    return holder ~= nil
end

function DailyStateReader.selectType(typeName)
    local holder = getHolder()
    if not holder then
        return false
    end

    local button = findBannerButtonByType(holder, typeName)
    if not button then
        return false
    end

    if not fireButton(button) then
        return false
    end

    task.wait(0.25)
    return true
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
