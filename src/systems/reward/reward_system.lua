local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local config = require("core.config")
local Logger = require("core.logger")
local DailyStateReader = require("systems.reward.daily_state_reader")
local EventRewardReader = require("systems.reward.event_reward_reader")
local LevelMilestonesReader = require("systems.reward.level_milestones_reader")
local PopupHandler = require("systems.reward.popup_handler")

local RewardSystem = {}

local networking = ReplicatedStorage:WaitForChild("Networking")

local newPlayerRemote = networking:WaitForChild("NewPlayerRewardsEvent")
local pirateRemote = networking:WaitForChild("APiratesWelcomeEvent")
local dailyRemote = networking:WaitForChild("DailyRewardEvent")
local milestonesRemote = networking:WaitForChild("Milestones"):WaitForChild("MilestonesEvent")
local rng = Random.new()

local DAILY_MIN_DELAY = 0.35
local DAILY_MAX_DELAY = 1.0
local DAILY_POST_CLAIM_MIN_DELAY = 0.4
local DAILY_POST_CLAIM_MAX_DELAY = 0.8
local EVENT_MIN_DELAY = 0.35
local EVENT_MAX_DELAY = 0.95
local EVENT_POST_CLAIM_MIN_DELAY = 0.35
local EVENT_POST_CLAIM_MAX_DELAY = 0.75
local MENU_SWITCH_MIN_DELAY = 0.8
local MENU_SWITCH_MAX_DELAY = 1.9

local function waitRandom(minSeconds, maxSeconds)
    task.wait(rng:NextNumber(minSeconds, maxSeconds))
end

local function formatDays(days)
    if #days == 0 then
        return "none"
    end

    table.sort(days)

    local parts = {}
    for _, day in ipairs(days) do
        table.insert(parts, tostring(day))
    end

    return table.concat(parts, ",")
end

local function formatLevels(levels)
    if #levels == 0 then
        return "none"
    end

    table.sort(levels)

    local parts = {}
    for _, level in ipairs(levels) do
        table.insert(parts, tostring(level))
    end

    return table.concat(parts, ",")
end

local function shuffleArray(values)
    for i = #values, 2, -1 do
        local j = rng:NextInteger(1, i)
        values[i], values[j] = values[j], values[i]
    end
end

local function getDailyClaimPlan(typeName)
    if not DailyStateReader.ensureMenuOpen() then
        return {
            days = {},
            summary = "DailyRewards UI not found",
        }
    end

    if not DailyStateReader.selectType(typeName) then
        return {
            days = {},
            summary = "Daily reward type tab not found: " .. tostring(typeName),
        }
    end

    local snapshot = DailyStateReader.read()
    if not snapshot.listFound then
        return {
            days = {},
            summary = "DailyRewards UI not found",
        }
    end

    local counts = {
        available = 0,
        claimed = 0,
        locked = 0,
        unknown = 0,
    }

    local availableDays = {}
    local claimedDays = {}
    local lockedDays = {}
    local unknownDays = {}
    for _, card in ipairs(snapshot.cards) do
        local state = card.state or "unknown"
        if counts[state] ~= nil then
            counts[state] = counts[state] + 1
        end

        if state == "available" and card.dayIndex then
            table.insert(availableDays, card.dayIndex)
        elseif state == "claimed" and card.dayIndex then
            table.insert(claimedDays, card.dayIndex)
        elseif state == "locked" and card.dayIndex then
            table.insert(lockedDays, card.dayIndex)
        elseif state == "unknown" and card.dayIndex then
            table.insert(unknownDays, card.dayIndex)
        end
    end

    table.sort(availableDays)

    local dedupedDays = {}
    local seen = {}
    for _, dayIndex in ipairs(availableDays) do
        if not seen[dayIndex] then
            seen[dayIndex] = true
            table.insert(dedupedDays, dayIndex)
        end
    end

    return {
        days = dedupedDays,
        summary = string.format(
            "Daily snapshot available=%d claimed=%d locked=%d unknown=%d",
            counts.available,
            counts.claimed,
            counts.locked,
            counts.unknown
        ),
        details = string.format(
            "Daily days available=[%s] claimed=[%s] locked=[%s] unknown=[%s]",
            formatDays(availableDays),
            formatDays(claimedDays),
            formatDays(lockedDays),
            formatDays(unknownDays)
        ),
    }
end

local function countClaimedCards(cards)
    local claimed = 0
    for _, card in ipairs(cards) do
        if card.state == "claimed" then
            claimed = claimed + 1
        end
    end
    return claimed
end

local function findCardByDay(cards, dayIndex)
    for _, card in ipairs(cards) do
        if card.dayIndex == dayIndex then
            return card
        end
    end
    return nil
end

local function formatColor(color)
    if not color then
        return "n/a"
    end

    return string.format("(%.3f, %.3f, %.3f)", color.R, color.G, color.B)
end

local function getSortedCardsWithDay(cards)
    local withDay = {}
    for _, card in ipairs(cards) do
        if card.dayIndex ~= nil then
            table.insert(withDay, card)
        end
    end

    table.sort(withDay, function(a, b)
        return a.dayIndex < b.dayIndex
    end)

    return withDay
end

local function getNextUnclaimedDay(cards)
    local sorted = getSortedCardsWithDay(cards)
    for _, card in ipairs(sorted) do
        if card.state ~= "claimed" then
            return card.dayIndex
        end
    end
    return nil
end

local function findMilestoneCardByLevel(cards, level)
    for _, card in ipairs(cards) do
        if card.level == level then
            return card
        end
    end
    return nil
end

local function getHumanoidRootPart()
    local player = Players.LocalPlayer
    local character = player and player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function teleportToMilestoneNpcIfNeeded()
    if not config.rewards.LevelMilestonesTeleportToNpc then
        return nil, false
    end

    local root = getHumanoidRootPart()
    if not root then
        Logger.log("LevelMilestones teleport skipped: HumanoidRootPart not found")
        return nil, false
    end

    local mainLobby = Workspace:FindFirstChild("MainLobby")
    local npcFolder = mainLobby and mainLobby:FindFirstChild("NPC")
    local npcName = config.rewards.LevelMilestonesNpcName or "Gilgamesh"
    local npc = npcFolder and npcFolder:FindFirstChild(npcName)
    if not npc then
        Logger.log("LevelMilestones teleport skipped: NPC not found (" .. tostring(npcName) .. ")")
        return nil, false
    end

    local originalCFrame = root.CFrame
    local npcCFrame = npc:IsA("Model") and npc:GetPivot() or npc.CFrame

    local radius = tonumber(config.rewards.LevelMilestonesTeleportRadius) or 3
    if radius < 0 then
        radius = 0
    end

    local offsetX = rng:NextNumber(-radius, radius)
    local offsetZ = rng:NextNumber(-radius, radius)
    local offsetY = tonumber(config.rewards.LevelMilestonesTeleportYOffset) or 3

    root.CFrame = npcCFrame * CFrame.new(offsetX, offsetY, offsetZ)
    Logger.log(string.format(
        "LevelMilestones teleported near %s (offset=%.2f,%.2f,%.2f)",
        tostring(npcName),
        offsetX,
        offsetY,
        offsetZ
    ))

    waitRandom(1.2, 2.8)
    return originalCFrame, true
end

local function restoreOriginalPosition(originalCFrame)
    if not originalCFrame then
        return
    end
    if not config.rewards.LevelMilestonesReturnToOriginalPosition then
        return
    end

    local root = getHumanoidRootPart()
    if not root then
        Logger.log("LevelMilestones return skipped: HumanoidRootPart not found")
        return
    end

    root.CFrame = originalCFrame
    Logger.log("LevelMilestones returned to original position")
end

local function claimRewards(remote, guiName, sidebarButtonName)
    Logger.log("Starting " .. remote.Name)

    if not EventRewardReader.ensureMenuOpen(guiName, sidebarButtonName) then
        Logger.log(guiName .. " UI not found")
        Logger.log("Finished " .. remote.Name)
        return
    end

    local snapshot = EventRewardReader.read(guiName)
    if not snapshot.listFound then
        Logger.log(guiName .. " UI not found")
        Logger.log("Finished " .. remote.Name)
        return
    end

    local claimedProgress = snapshot.claimedCount
    local totalDays = snapshot.totalDays or 7
    local claimedCards = countClaimedCards(snapshot.cards)
    Logger.log(string.format(
        "%s progress text=%s/%d cardsClaimed=%d timer=%s",
        guiName,
        tostring(claimedProgress or "n/a"),
        totalDays,
        claimedCards,
        snapshot.timerText or "n/a"
    ))

    if claimedCards >= totalDays then
        Logger.log("No available rewards for " .. remote.Name)
        if not EventRewardReader.closeMenu(guiName) then
            Logger.log("Failed to close " .. guiName .. " menu after empty plan")
        end
        Logger.log("Finished " .. remote.Name)
        return
    end

    local maxAttempts = 3
    for i = 1, maxAttempts do
        local nextDay = getNextUnclaimedDay(snapshot.cards)
        if nextDay == nil or nextDay > totalDays then
            break
        end

        local targetCard = findCardByDay(snapshot.cards, nextDay)
        if not targetCard then
            Logger.log("Next day card not found in UI, stopping at day " .. nextDay)
            break
        end

        Logger.log(string.format(
            "%s target day=%d state=%s color=%s source=%s section=%s",
            guiName,
            nextDay,
            tostring(targetCard.state),
            formatColor(targetCard.stateColor),
            tostring(targetCard.stateColorSource or "n/a"),
            tostring(targetCard.section or "n/a")
        ))

        if targetCard.state == "claimed" then
            Logger.log("Next day already marked claimed, stopping at day " .. nextDay)
            break
        end

        if targetCard.state == "locked" then
            Logger.log(
                "Next day is locked, stopping at day " .. nextDay
            )
            break
        end

        waitRandom(EVENT_MIN_DELAY, EVENT_MAX_DELAY)
        Logger.log("Claim attempt " .. nextDay)

        remote:FireServer("Claim", nextDay)

        waitRandom(EVENT_POST_CLAIM_MIN_DELAY, EVENT_POST_CLAIM_MAX_DELAY)
        PopupHandler.handle(3)

        snapshot = EventRewardReader.read(guiName)
        if not snapshot.listFound then
            Logger.log(guiName .. " UI disappeared while claiming")
            break
        end

        local newClaimedCards = countClaimedCards(snapshot.cards)
        local newClaimedProgress = snapshot.claimedCount

        Logger.log(string.format(
            "%s progress after attempt cards=%d->%d text=%s/%d",
            guiName,
            claimedCards,
            newClaimedCards,
            tostring(newClaimedProgress or "n/a"),
            totalDays
        ))

        if newClaimedCards <= claimedCards then
            Logger.log("No progress after claim attempt, stopping " .. remote.Name)
            break
        end

        claimedCards = newClaimedCards
        totalDays = snapshot.totalDays or totalDays

        if i % rng:NextInteger(3, 5) == 0 then
            waitRandom(1.0, 1.8)
        end
    end

    if not EventRewardReader.closeMenu(guiName) then
        Logger.log("Failed to close " .. guiName .. " menu after claims")
    end

    Logger.log("Finished " .. remote.Name)
end

local function claimDaily(typeName)
    Logger.log("Starting DailyReward " .. typeName)

    local claimPlan = getDailyClaimPlan(typeName)
    Logger.log(claimPlan.summary)
    Logger.log(claimPlan.details)

    if #claimPlan.days == 0 then
        Logger.log("No available daily rewards for " .. typeName)
        if not DailyStateReader.closeMenu() then
            Logger.log("Failed to close DailyRewards menu after empty plan")
        end
        Logger.log("Finished DailyReward " .. typeName)
        return
    end

    shuffleArray(claimPlan.days)

    for i, dayIndex in ipairs(claimPlan.days) do
        waitRandom(DAILY_MIN_DELAY, DAILY_MAX_DELAY)

        Logger.log("Claim attempt " .. typeName .. " day " .. dayIndex)
        dailyRemote:FireServer("Claim", { typeName, dayIndex })

        waitRandom(DAILY_POST_CLAIM_MIN_DELAY, DAILY_POST_CLAIM_MAX_DELAY)
        PopupHandler.handle(3)

        if i % rng:NextInteger(3, 5) == 0 then
            waitRandom(1.1, 2.1)
        end
    end

    if not DailyStateReader.closeMenu() then
        Logger.log("Failed to close DailyRewards menu after claims")
    end

    Logger.log("Finished DailyReward " .. typeName)
end

local function claimLevelMilestones()
    Logger.log("Starting LevelMilestones")

    local snapshot = LevelMilestonesReader.read()
    if not snapshot.listFound then
        Logger.log("LevelMilestones UI not found")
        Logger.log("Finished LevelMilestones")
        return
    end

    local counts = {
        available = 0,
        claimed = 0,
        locked = 0,
        unknown = 0,
    }
    local availableLevels = {}
    local claimedLevels = {}
    local lockedLevels = {}
    local unknownLevels = {}

    for _, card in ipairs(snapshot.cards) do
        local state = card.state or "unknown"
        if counts[state] ~= nil then
            counts[state] = counts[state] + 1
        end

        if state == "available" then
            table.insert(availableLevels, card.level)
        elseif state == "claimed" then
            table.insert(claimedLevels, card.level)
        elseif state == "locked" then
            table.insert(lockedLevels, card.level)
        else
            table.insert(unknownLevels, card.level)
        end
    end

    Logger.log(string.format(
        "LevelMilestones snapshot available=%d claimed=%d locked=%d unknown=%d",
        counts.available,
        counts.claimed,
        counts.locked,
        counts.unknown
    ))
    Logger.log(string.format(
        "LevelMilestones levels available=[%s] claimed=[%s] locked=[%s] unknown=[%s]",
        formatLevels(availableLevels),
        formatLevels(claimedLevels),
        formatLevels(lockedLevels),
        formatLevels(unknownLevels)
    ))

    if #availableLevels == 0 then
        Logger.log("No available level milestones")
        Logger.log("Finished LevelMilestones")
        return
    end

    shuffleArray(availableLevels)
    local originalCFrame = nil
    local teleported = false
    originalCFrame, teleported = teleportToMilestoneNpcIfNeeded()
    if not teleported then
        Logger.log("LevelMilestones skipped: teleport to NPC failed")
        Logger.log("Finished LevelMilestones")
        return
    end

    for i, level in ipairs(availableLevels) do
        snapshot = LevelMilestonesReader.read()
        if not snapshot.listFound then
            Logger.log("LevelMilestones UI disappeared while claiming")
            break
        end

        local card = findMilestoneCardByLevel(snapshot.cards, level)
        if not card then
            Logger.log("Level milestone card not found for level " .. level)
            continue
        end

        if card.state ~= "available" then
            Logger.log("Skipping level " .. level .. " (state=" .. tostring(card.state) .. ")")
            continue
        end

        if not LevelMilestonesReader.selectLevel(level) then
            Logger.log("Level milestone card selection not available for level " .. level .. " (continuing with remote)")
        end

        local claimUi = LevelMilestonesReader.readClaimUi()
        if claimUi then
            Logger.log(string.format(
                "LevelMilestones claim UI level=%d buttonVisible=%s buttonActive=%s unclaimedOverlay=%s",
                level,
                tostring(claimUi.buttonVisible),
                tostring(claimUi.buttonActive),
                tostring(claimUi.unclaimedVisible)
            ))
        end

        waitRandom(EVENT_MIN_DELAY, EVENT_MAX_DELAY)
        Logger.log("Claim attempt LevelMilestones level " .. level)
        milestonesRemote:FireServer("Claim", level)

        waitRandom(EVENT_POST_CLAIM_MIN_DELAY, EVENT_POST_CLAIM_MAX_DELAY)
        PopupHandler.handle(3)

        local afterSnapshot = LevelMilestonesReader.read()
        local afterCard = findMilestoneCardByLevel(afterSnapshot.cards, level)
        if afterCard and afterCard.state == "claimed" then
            Logger.log("Level milestone claimed " .. level)
        else
            Logger.log("No claimed confirmation for level " .. level .. " after attempt")
        end

        if i % rng:NextInteger(3, 5) == 0 then
            waitRandom(1.0, 1.8)
        end
    end

    if teleported then
        restoreOriginalPosition(originalCFrame)
    end

    Logger.log("Finished LevelMilestones")
end

function RewardSystem.run()
    if config.rewards.EnableNewPlayerRewards then
        claimRewards(newPlayerRemote, "NewPlayers", "ReturningPlayerRewards")
        waitRandom(MENU_SWITCH_MIN_DELAY, MENU_SWITCH_MAX_DELAY)
    else
        Logger.log("Skipping NewPlayerRewards (disabled by config)")
    end

    if config.rewards.EnablePirateRewards then
        claimRewards(pirateRemote, "APiratesWelcome", "APiratesWelcomeRewards")
        waitRandom(MENU_SWITCH_MIN_DELAY, MENU_SWITCH_MAX_DELAY)
    else
        Logger.log("Skipping PirateRewards (disabled by config)")
    end

    if config.rewards.EnableSpecialRewards then
        claimDaily("Special")
        waitRandom(MENU_SWITCH_MIN_DELAY, MENU_SWITCH_MAX_DELAY)
    else
        Logger.log("Skipping DailyReward Special (disabled by config)")
    end

    if config.rewards.EnableWinterRewards then
        claimDaily("Winter")
        waitRandom(MENU_SWITCH_MIN_DELAY, MENU_SWITCH_MAX_DELAY)
    else
        Logger.log("Skipping DailyReward Winter (disabled by config)")
    end

    if config.rewards.EnableLevelMilestones then
        claimLevelMilestones()
    else
        Logger.log("Skipping LevelMilestones (disabled by config)")
    end

    Logger.log("RewardSystem finished")
end

return RewardSystem
