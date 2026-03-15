local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local EventRewardReader = {}

local function getPlayerGui()
    local player = Players.LocalPlayer
    if not player then
        return nil
    end

    return player:FindFirstChild("PlayerGui")
end

local function fireButton(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end

    local fired = false

    fired = pcall(function()
        firesignal(button.Activated)
    end) or fired

    fired = pcall(function()
        firesignal(button.MouseButton1Click)
    end) or fired

    fired = pcall(function()
        button:Activate()
    end) or fired

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

local function getHolder(guiName)
    local playerGui = getPlayerGui()
    local eventGui = playerGui and playerGui:FindFirstChild(guiName)
    return eventGui and eventGui:FindFirstChild("Holder")
end

function EventRewardReader.ensureMenuOpen(guiName, sidebarButtonName)
    for _ = 1, 3 do
        local holder = getHolder(guiName)
        if holder and holder:IsA("GuiObject") and holder.Visible then
            return true
        end

        local playerGui = getPlayerGui()
        local hud = playerGui and playerGui:FindFirstChild("HUD")
        local sideButtons = hud and hud:FindFirstChild("SideButtons")
        local sidebarButton = sideButtons and sideButtons:FindFirstChild(sidebarButtonName)
        if not sidebarButton then
            return false
        end

        local buttonToFire = nil
        if sidebarButton:IsA("GuiButton") then
            buttonToFire = sidebarButton
        else
            local nested = sidebarButton:FindFirstChild("Button")
            if nested and nested:IsA("GuiButton") then
                buttonToFire = nested
            end
        end

        if not fireButton(buttonToFire) then
            return false
        end

        task.wait(0.35)
    end

    local holder = getHolder(guiName)
    return holder ~= nil and holder.Visible
end

function EventRewardReader.closeMenu(guiName)
    local holder = getHolder(guiName)
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

            holder = getHolder(guiName)
            if not holder or not holder:IsA("GuiObject") or not holder.Visible then
                return true
            end
        end
    end

    holder = getHolder(guiName)
    if clickCloseFallback(holder) then
        holder = getHolder(guiName)
        if not holder or not holder:IsA("GuiObject") or not holder.Visible then
            return true
        end
    end

    return false
end

local function parseDay(card)
    local main = card:FindFirstChild("Main")
    local dayLabel = main and main:FindFirstChild("Day")
    if not dayLabel or not dayLabel:IsA("TextLabel") then
        return nil
    end

    local content = dayLabel.ContentText
    if not content or content == "" then
        content = dayLabel.Text
    end

    return tonumber((content or ""):match("(%d+)"))
end

local function resolveCardState(card)
    local claimedFrame = card:FindFirstChild("ClaimedFrame")
    if claimedFrame and claimedFrame:IsA("GuiObject") and claimedFrame.Visible then
        return "claimed"
    end

    local button = card:FindFirstChild("Button")
    if button and button:IsA("GuiButton") and button.Visible and button.Active then
        return "available"
    end

    return "unknown"
end

local function collectCardsFromSection(holder, sectionName, cards)
    local section = holder:FindFirstChild(sectionName)
    if not section then
        return
    end

    for _, child in ipairs(section:GetChildren()) do
        if child:IsA("Frame") and (child.Name == "SmallTemplate" or child.Name == "BigTemplate") then
            local card = child:FindFirstChild(child.Name)
            if card and card:IsA("Frame") then
                table.insert(cards, {
                    dayIndex = parseDay(card),
                    state = resolveCardState(card),
                    cardType = child.Name,
                    section = sectionName,
                })
            end
        end
    end
end

function EventRewardReader.read(guiName)
    local holder = getHolder(guiName)
    if not holder then
        return {
            listFound = false,
            cards = {},
        }
    end

    local cards = {}
    collectCardsFromSection(holder, "TopRewards", cards)
    collectCardsFromSection(holder, "BottomRewards", cards)

    return {
        listFound = true,
        cards = cards,
    }
end

return EventRewardReader
