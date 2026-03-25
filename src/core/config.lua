local runtimeConfig = {}
if getgenv then
    runtimeConfig = getgenv().SCRIPT_AVG_CONFIG or {}
end

local function pick(value, defaultValue)
    if value == nil then
        return defaultValue
    end
    return value
end

local config = {}

local rewardOverrides = runtimeConfig.rewards or {}
config.rewards = {
    EnableNewPlayerRewards = pick(rewardOverrides.EnableNewPlayerRewards, true),
    EnablePirateRewards = pick(rewardOverrides.EnablePirateRewards, true),
    EnableSpecialRewards = pick(rewardOverrides.EnableSpecialRewards, true),
    EnableWinterRewards = pick(rewardOverrides.EnableWinterRewards, true),
    EnableLevelMilestones = pick(rewardOverrides.EnableLevelMilestones, true),
    LevelMilestonesTeleportToNpc = pick(rewardOverrides.LevelMilestonesTeleportToNpc, true),
    LevelMilestonesReturnToOriginalPosition = pick(rewardOverrides.LevelMilestonesReturnToOriginalPosition, true),
    LevelMilestonesNpcName = pick(rewardOverrides.LevelMilestonesNpcName, "Gilgamesh"),
    LevelMilestonesTeleportRadius = pick(rewardOverrides.LevelMilestonesTeleportRadius, 3),
    LevelMilestonesTeleportYOffset = pick(rewardOverrides.LevelMilestonesTeleportYOffset, 3),
}

local trackerOverrides = runtimeConfig.tracker or {}
local retryOverrides = trackerOverrides.retry or {}
config.tracker = {
    webhookUrl = pick(trackerOverrides.webhookUrl, ""),
    secretToken = pick(trackerOverrides.secretToken, ""),
    intervalMinutes = pick(trackerOverrides.intervalMinutes, 5),
    intervalSeconds = pick(trackerOverrides.intervalSeconds, nil),
    sendOnChangeOnly = pick(trackerOverrides.sendOnChangeOnly, true),
    heartbeatMinutes = pick(trackerOverrides.heartbeatMinutes, 15),
    retry = {
        maxRetries = pick(retryOverrides.maxRetries, 3),
        retryDelaySeconds = pick(retryOverrides.retryDelaySeconds, 2),
    },
}

local loggerOverrides = runtimeConfig.logger or {}
config.logger = {
    exportToClipboard = pick(loggerOverrides.exportToClipboard, false),
}

local automationOverrides = runtimeConfig.automation or {}
config.automation = {
    enabled = pick(automationOverrides.enabled, true),
    tickSeconds = pick(automationOverrides.tickSeconds, 2),
    runLobbyPipelineOncePerSession = pick(automationOverrides.runLobbyPipelineOncePerSession, true),
    lobbyPlaceId = pick(automationOverrides.lobbyPlaceId, 16146832113),
    matchPlaceId = pick(automationOverrides.matchPlaceId, 16277809958),
}

local hudOverrides = runtimeConfig.hud or {}
config.hud = {
    enabled = pick(hudOverrides.enabled, true),
    toggleKey = pick(hudOverrides.toggleKey, "B"),
    statusPrefix = pick(hudOverrides.statusPrefix, "Status"),
}

return config
