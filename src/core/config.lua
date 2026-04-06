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
    claimMode = pick(rewardOverrides.claimMode, "module"),
    EnableNewPlayerRewards = pick(rewardOverrides.EnableNewPlayerRewards, true),
    EnablePirateRewards = pick(rewardOverrides.EnablePirateRewards, true),
    EnableSpecialRewards = pick(rewardOverrides.EnableSpecialRewards, true),
    EnableWinterRewards = pick(rewardOverrides.EnableWinterRewards, true),
    EnableLevelMilestones = pick(rewardOverrides.EnableLevelMilestones, true),
    EnableCollectionMilestones = pick(rewardOverrides.EnableCollectionMilestones, true),
    EnableBattlePass = pick(rewardOverrides.EnableBattlePass, true),
    EnableQuests = pick(rewardOverrides.EnableQuests, true),
    LevelMilestonesTeleportToNpc = pick(rewardOverrides.LevelMilestonesTeleportToNpc, true),
    LevelMilestonesReturnToOriginalPosition = pick(rewardOverrides.LevelMilestonesReturnToOriginalPosition, true),
    LevelMilestonesNpcName = pick(rewardOverrides.LevelMilestonesNpcName, "Gilgamesh"),
    LevelMilestonesTeleportRadius = pick(rewardOverrides.LevelMilestonesTeleportRadius, 3),
    LevelMilestonesTeleportYOffset = pick(rewardOverrides.LevelMilestonesTeleportYOffset, 3),
    ModuleEnableUiSuppressor = pick(rewardOverrides.ModuleEnableUiSuppressor, true),
    ModuleSyncWaitSeconds = pick(rewardOverrides.ModuleSyncWaitSeconds, 12),
    ModuleDelayBetweenTypesMinSeconds = pick(rewardOverrides.ModuleDelayBetweenTypesMinSeconds, 2.0),
    ModuleDelayBetweenTypesMaxSeconds = pick(rewardOverrides.ModuleDelayBetweenTypesMaxSeconds, 5.0),
    ModuleDelayBetweenClaimsMinSeconds = pick(rewardOverrides.ModuleDelayBetweenClaimsMinSeconds, 2.5),
    ModuleDelayBetweenClaimsMaxSeconds = pick(rewardOverrides.ModuleDelayBetweenClaimsMaxSeconds, 5.5),
    ModuleBattlePassMaxLevel = pick(rewardOverrides.ModuleBattlePassMaxLevel, 50),
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
local antiAfkOverrides = automationOverrides.antiAfk or {}
local customPlayOverrides = automationOverrides.customPlay or {}
local lobbyUiGuardOverrides = automationOverrides.lobbyUiGuard or {}
config.automation = {
    enabled = pick(automationOverrides.enabled, true),
    tickSeconds = pick(automationOverrides.tickSeconds, 2),
    runLobbyPipelineOncePerSession = pick(automationOverrides.runLobbyPipelineOncePerSession, true),
    playMode = pick(automationOverrides.playMode, "native"),
    lobbyPlaceId = pick(automationOverrides.lobbyPlaceId, 16146832113),
    matchPlaceId = pick(automationOverrides.matchPlaceId, 16277809958),
    equipUnitName = pick(automationOverrides.equipUnitName, "Bounty Hunter"),
    equipSlot = pick(automationOverrides.equipSlot, 1),
    matchStage = pick(automationOverrides.matchStage, "Stage1"),
    matchDifficulty = pick(automationOverrides.matchDifficulty, "Normal"),
    matchAct = pick(automationOverrides.matchAct, "Act1"),
    matchStageType = pick(automationOverrides.matchStageType, "Story"),
    matchFriendsOnly = pick(automationOverrides.matchFriendsOnly, false),
    customPlay = {
        unitName = pick(customPlayOverrides.unitName, "Bounty Hunter"),
        slotIndex = pick(customPlayOverrides.slotIndex, 1),
        basePositions = pick(customPlayOverrides.basePositions, {
            Vector3.new(436.09, 5.30, -344.17),
            Vector3.new(441.93, 5.30, -349.75),
            Vector3.new(433.46, 5.30, -353.14),
            Vector3.new(422.96, 5.30, -349.97),
        }),
        placementCooldownSeconds = pick(customPlayOverrides.placementCooldownSeconds, 2.5),
        validationAttempts = pick(customPlayOverrides.validationAttempts, 15),
        jitterMin = pick(customPlayOverrides.jitterMin, -3),
        jitterMax = pick(customPlayOverrides.jitterMax, 3),
        dpsStopMinSeconds = pick(customPlayOverrides.dpsStopMinSeconds, 0.10),
        dpsStopMaxSeconds = pick(customPlayOverrides.dpsStopMaxSeconds, 0.20),
        placeReactionMinSeconds = pick(customPlayOverrides.placeReactionMinSeconds, 0.25),
        placeReactionMaxSeconds = pick(customPlayOverrides.placeReactionMaxSeconds, 0.45),
        loopDelayMinSeconds = pick(customPlayOverrides.loopDelayMinSeconds, 2.5),
        loopDelayMaxSeconds = pick(customPlayOverrides.loopDelayMaxSeconds, 5.0),
        upgradeDelayMinSeconds = pick(customPlayOverrides.upgradeDelayMinSeconds, 0.20),
        upgradeDelayMaxSeconds = pick(customPlayOverrides.upgradeDelayMaxSeconds, 0.40),
        maxPlacementsFallback = pick(customPlayOverrides.maxPlacementsFallback, 4),
    },
    antiAfk = {
        enabled = pick(antiAfkOverrides.enabled, true),
        debugMode = pick(antiAfkOverrides.debugMode, true),
        movementEnabled = pick(antiAfkOverrides.movementEnabled, true),
        jumpEnabled = pick(antiAfkOverrides.jumpEnabled, true),
        roamRadiusMin = pick(antiAfkOverrides.roamRadiusMin, 10),
        roamRadiusMax = pick(antiAfkOverrides.roamRadiusMax, 50),
        intervalMinSeconds = pick(antiAfkOverrides.intervalMinSeconds, 180),
        intervalMaxSeconds = pick(antiAfkOverrides.intervalMaxSeconds, 600),
        jumpChancePercent = pick(antiAfkOverrides.jumpChancePercent, 40),
        maxJumpsPerMovement = pick(antiAfkOverrides.maxJumpsPerMovement, 2),
        moveToTimeoutSeconds = pick(antiAfkOverrides.moveToTimeoutSeconds, 25),
        chamblerHeartbeatSeconds = pick(antiAfkOverrides.chamblerHeartbeatSeconds, 5),
        autoExportLogsToClipboard = pick(antiAfkOverrides.autoExportLogsToClipboard, false),
        exportIntervalSeconds = pick(antiAfkOverrides.exportIntervalSeconds, 300),
    },
    lobbyUiGuard = {
        enabled = pick(lobbyUiGuardOverrides.enabled, true),
        tickSeconds = pick(lobbyUiGuardOverrides.tickSeconds, 0.5),
        resolveRetrySeconds = pick(lobbyUiGuardOverrides.resolveRetrySeconds, 5),
        closeLogCooldownSeconds = pick(lobbyUiGuardOverrides.closeLogCooldownSeconds, 15),
        enableUpdateLogOptOut = pick(lobbyUiGuardOverrides.enableUpdateLogOptOut, true),
        suppressDuringLegacyRewardClaim = pick(lobbyUiGuardOverrides.suppressDuringLegacyRewardClaim, true),
    },
}

local hudOverrides = runtimeConfig.hud or {}
config.hud = {
    enabled = pick(hudOverrides.enabled, true),
    toggleKey = pick(hudOverrides.toggleKey, "RightShift"),
    statusPrefix = pick(hudOverrides.statusPrefix, "Status"),
    diagnosticsEnabled = pick(hudOverrides.diagnosticsEnabled, false),
}

return config
