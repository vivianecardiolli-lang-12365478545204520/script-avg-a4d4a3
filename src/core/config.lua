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
}

local trackerOverrides = runtimeConfig.tracker or {}
local retryOverrides = trackerOverrides.retry or {}
config.tracker = {
    webhookUrl = pick(trackerOverrides.webhookUrl, ""),
    secretToken = pick(trackerOverrides.secretToken, ""),
    intervalMinutes = pick(trackerOverrides.intervalMinutes, 5),
    retry = {
        maxRetries = pick(retryOverrides.maxRetries, 3),
        retryDelaySeconds = pick(retryOverrides.retryDelaySeconds, 2),
    },
}

local loggerOverrides = runtimeConfig.logger or {}
config.logger = {
    exportToClipboard = pick(loggerOverrides.exportToClipboard, false),
}

return config
