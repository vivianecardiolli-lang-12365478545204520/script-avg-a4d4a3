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

function DailyStateReader.read()
    local player = Players.LocalPlayer
    if not player then
        return {
            listFound = false,
            cards = {},
        }
    end

    local playerGui = player:FindFirstChild("PlayerGui")
    local dailyRewards = playerGui and playerGui:FindFirstChild("DailyRewards")
    local holder = dailyRewards and dailyRewards:FindFirstChild("Holder")
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
