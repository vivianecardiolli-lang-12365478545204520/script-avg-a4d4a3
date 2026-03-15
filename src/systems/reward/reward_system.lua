local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require("core.config")
local Logger = require("core.logger")
local DailyStateReader = require("systems.reward.daily_state_reader")
local EventRewardReader = require("systems.reward.event_reward_reader")
local PopupHandler = require("systems.reward.popup_handler")

local RewardSystem = {}

local networking = ReplicatedStorage:WaitForChild("Networking")

local newPlayerRemote = networking:WaitForChild("NewPlayerRewardsEvent")
local pirateRemote = networking:WaitForChild("APiratesWelcomeEvent")
local dailyRemote = networking:WaitForChild("DailyRewardEvent")
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

local function getEventClaimPlan(guiName, sidebarButtonName)
    if not EventRewardReader.ensureMenuOpen(guiName, sidebarButtonName) then
        return {
            days = {},
            summary = guiName .. " UI not found",
        }
    end

    local snapshot = EventRewardReader.read(guiName)
    if not snapshot.listFound then
        return {
            days = {},
            summary = guiName .. " UI not found",
        }
    end

    local counts = {
        available = 0,
        claimed = 0,
        unknown = 0,
    }

    local availableDays = {}
    local claimedDays = {}
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
            "%s snapshot available=%d claimed=%d unknown=%d",
            guiName,
            counts.available,
            counts.claimed,
            counts.unknown
        ),
        details = string.format(
            "%s days available=[%s] claimed=[%s] unknown=[%s]",
            guiName,
            formatDays(availableDays),
            formatDays(claimedDays),
            formatDays(unknownDays)
        ),
    }
end

local function claimRewards(remote, guiName, sidebarButtonName)
    Logger.log("Starting " .. remote.Name)

    local claimPlan = getEventClaimPlan(guiName, sidebarButtonName)
    Logger.log(claimPlan.summary)
    Logger.log(claimPlan.details)

    if #claimPlan.days == 0 then
        Logger.log("No available rewards for " .. remote.Name)
        if not EventRewardReader.closeMenu(guiName) then
            Logger.log("Failed to close " .. guiName .. " menu after empty plan")
        end
        Logger.log("Finished " .. remote.Name)
        return
    end

    shuffleArray(claimPlan.days)

    for i, dayIndex in ipairs(claimPlan.days) do
        waitRandom(EVENT_MIN_DELAY, EVENT_MAX_DELAY)
        Logger.log("Claim attempt " .. dayIndex)

        remote:FireServer("Claim", dayIndex)

        waitRandom(EVENT_POST_CLAIM_MIN_DELAY, EVENT_POST_CLAIM_MAX_DELAY)
        PopupHandler.handle(3)

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
    else
        Logger.log("Skipping DailyReward Winter (disabled by config)")
    end

    Logger.log("RewardSystem finished")
end

return RewardSystem
