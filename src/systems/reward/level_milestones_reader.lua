local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LevelMilestonesReader = {}

local function getPlayerGui()
    local player = Players.LocalPlayer
    if not player then
        return nil
    end

    return player:FindFirstChild("PlayerGui")
end

local function getGui()
    local playerGui = getPlayerGui()
    return playerGui and playerGui:FindFirstChild("LevelMilestones")
end

local function getMain()
    local gui = getGui()
    return gui and gui:FindFirstChild("Main")
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

local function clickCloseFallback(main)
    if not main or not main:IsA("GuiObject") then
        return false
    end

    local pos = main.AbsolutePosition
    local size = main.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return false
    end

    local x = math.floor(pos.X + (size.X * 0.96))
    local y = math.floor(pos.Y + (size.Y * 0.06))
    clickAt(x, y)
    task.wait(0.2)

    return true
end

local function findFirstButton(root)
    if not root then
        return nil
    end

    if root:IsA("GuiButton") then
        return root
    end

    local direct = root:FindFirstChild("Button")
    if direct and direct:IsA("GuiButton") then
        return direct
    end

    for _, child in ipairs(root:GetDescendants()) do
        if child:IsA("GuiButton") then
            return child
        end
    end

    return nil
end

local function isMainVisible()
    local main = getMain()
    if not main or not main:IsA("GuiObject") then
        return false
    end

    return main.Visible
end

function LevelMilestonesReader.ensureMenuOpen()
    for _ = 1, 6 do
        if isMainVisible() then
            return true
        end

        task.wait(0.3)
    end

    return isMainVisible()
end

function LevelMilestonesReader.closeMenu()
    local main = getMain()
    if not main or not main:IsA("GuiObject") or not main.Visible then
        return true
    end

    local cancel = main:FindFirstChild("Cancel")
    local cancelButton = findFirstButton(cancel)
    if cancelButton and fireButton(cancelButton) then
        task.wait(0.2)
        if not isMainVisible() then
            return true
        end
    end

    main = getMain()
    if clickCloseFallback(main) then
        return not isMainVisible()
    end

    return false
end

function LevelMilestonesReader.selectLevel(level)
    local main = getMain()
    if not main then
        return false
    end

    local levels = main:FindFirstChild("Levels")
    local card = levels and levels:FindFirstChild(tostring(level))
    if not card then
        return false
    end

    local button = findFirstButton(card)
    if not button then
        return false
    end

    if not fireButton(button) then
        return false
    end

    task.wait(0.15)
    return true
end

function LevelMilestonesReader.readClaimUi()
    local main = getMain()
    local claim = main and main:FindFirstChild("Claim")
    if not claim then
        return nil
    end

    local button = claim:FindFirstChild("Button")
    local dark = claim:FindFirstChild("Dark")
    local unclaimed = claim:FindFirstChild("Unclaimed")
    local stroke = claim:FindFirstChild("UIStroke")
    local label = claim:FindFirstChild("Label")

    local labelText = nil
    if label and label:IsA("TextLabel") then
        labelText = label.ContentText
        if not labelText or labelText == "" then
            labelText = label.Text
        end
    end

    return {
        visible = claim.Visible == true,
        buttonVisible = button and button:IsA("GuiObject") and button.Visible or false,
        buttonActive = button and button:IsA("GuiButton") and button.Active or false,
        darkVisible = dark and dark:IsA("GuiObject") and dark.Visible or false,
        unclaimedVisible = unclaimed and unclaimed:IsA("GuiObject") and unclaimed.Visible or false,
        labelText = labelText,
        strokeColor = stroke and stroke:IsA("UIStroke") and stroke.Color or nil,
    }
end

local function parseCardLevel(card)
    local numericName = tonumber(card.Name)
    if numericName then
        return numericName
    end

    local main = card:FindFirstChild("Main")
    local levelLabel = main and main:FindFirstChild("Level")
    if not levelLabel or not levelLabel:IsA("TextLabel") then
        return nil
    end

    local content = levelLabel.ContentText
    if not content or content == "" then
        content = levelLabel.Text
    end

    return tonumber((content or ""):match("(%d+)"))
end

local function resolveCardState(card)
    local checkMark = card:FindFirstChild("CheckMark")
    local darkFrame = card:FindFirstChild("DarkFrame")

    local checkVisible = checkMark and checkMark:IsA("GuiObject") and checkMark.Visible
    local darkVisible = darkFrame and darkFrame:IsA("GuiObject") and darkFrame.Visible

    if checkVisible then
        return "claimed", checkVisible, darkVisible
    end

    if darkVisible then
        return "locked", checkVisible, darkVisible
    end

    return "available", checkVisible, darkVisible
end

function LevelMilestonesReader.read()
    local main = getMain()
    local levels = main and main:FindFirstChild("Levels")
    if not levels then
        return {
            listFound = false,
            cards = {},
            claimUi = nil,
        }
    end

    local cards = {}
    for _, child in ipairs(levels:GetChildren()) do
        if child:IsA("Frame") then
            local level = parseCardLevel(child)
            if level then
                local state, checkVisible, darkVisible = resolveCardState(child)
                table.insert(cards, {
                    level = level,
                    state = state,
                    checkVisible = checkVisible,
                    darkVisible = darkVisible,
                })
            end
        end
    end

    table.sort(cards, function(a, b)
        return a.level < b.level
    end)

    return {
        listFound = true,
        cards = cards,
        claimUi = LevelMilestonesReader.readClaimUi(),
    }
end

return LevelMilestonesReader
