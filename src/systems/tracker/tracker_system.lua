local Players = game:GetService("Players")

local config = require("core.config")
local Logger = require("core.logger")
local SheetsClient = require("integrations.sheets_client")

local Tracker = {}

local player = Players.LocalPlayer

local TRACKED_ATTRIBUTES = {
    Gold = "Gold",
    Gems = "Gems",
    TraitRerolls = "TraitRerolls",
    Level = "Level",
}

local trackedData = {
    Gold = "0",
    Gems = "0",
    TraitRerolls = "0",
    Level = "0",
}

local listenersBound = false

local function readAttribute(attributeName, fallback)
    local value = player:GetAttribute(attributeName)
    if value == nil then
        return fallback
    end
    return tostring(value)
end

local function refreshAllAttributes()
    trackedData.Gold = readAttribute(TRACKED_ATTRIBUTES.Gold, "0")
    trackedData.Gems = readAttribute(TRACKED_ATTRIBUTES.Gems, "0")
    trackedData.TraitRerolls = readAttribute(TRACKED_ATTRIBUTES.TraitRerolls, "0")
    trackedData.Level = readAttribute(TRACKED_ATTRIBUTES.Level, "0")
end

local function bindAttributeListeners()
    if listenersBound then
        return
    end

    listenersBound = true

    player:GetAttributeChangedSignal(TRACKED_ATTRIBUTES.Gold):Connect(function()
        trackedData.Gold = readAttribute(TRACKED_ATTRIBUTES.Gold, trackedData.Gold)
    end)

    player:GetAttributeChangedSignal(TRACKED_ATTRIBUTES.Gems):Connect(function()
        trackedData.Gems = readAttribute(TRACKED_ATTRIBUTES.Gems, trackedData.Gems)
    end)

    player:GetAttributeChangedSignal(TRACKED_ATTRIBUTES.TraitRerolls):Connect(function()
        trackedData.TraitRerolls = readAttribute(TRACKED_ATTRIBUTES.TraitRerolls, trackedData.TraitRerolls)
    end)

    player:GetAttributeChangedSignal(TRACKED_ATTRIBUTES.Level):Connect(function()
        trackedData.Level = readAttribute(TRACKED_ATTRIBUTES.Level, trackedData.Level)
    end)
end

local function collectData()
    return {
        Gold = trackedData.Gold,
        Gems = trackedData.Gems,
        TraitRerolls = trackedData.TraitRerolls,
        Level = trackedData.Level,
    }
end

local function makeSignature(data)
    return string.format(
        "%s|%s|%s|%s",
        tostring(data.Gold),
        tostring(data.Gems),
        tostring(data.TraitRerolls),
        tostring(data.Level)
    )
end

local function formatData(data)
    return string.format(
        "gold=%s gems=%s traits=%s level=%s",
        tostring(data.Gold),
        tostring(data.Gems),
        tostring(data.TraitRerolls),
        tostring(data.Level)
    )
end

function Tracker.sendNow()
    local data = collectData()
    Logger.log("Tracker sendNow manual: " .. formatData(data))
    return SheetsClient.send(data)
end

function Tracker.startLoop()
    refreshAllAttributes()
    bindAttributeListeners()

    local interval = config.tracker.intervalSeconds
    if not interval or interval <= 0 then
        interval = config.tracker.intervalMinutes * 60
    end

    local heartbeatSeconds = (config.tracker.heartbeatMinutes or 15) * 60
    if heartbeatSeconds < 0 then
        heartbeatSeconds = 0
    end

    local lastSentSignature = nil
    local lastSentAt = 0

    Logger.log(
        string.format(
            "Tracker started | interval=%.2fs sendOnChangeOnly=%s heartbeat=%.2fs",
            interval,
            tostring(config.tracker.sendOnChangeOnly),
            heartbeatSeconds
        )
    )

    while true do
        local data = collectData()
        local signature = makeSignature(data)
        local changed = signature ~= lastSentSignature
        local heartbeatDue = heartbeatSeconds > 0 and (tick() - lastSentAt >= heartbeatSeconds)

        local shouldSend = (not config.tracker.sendOnChangeOnly) or changed or heartbeatDue or not lastSentSignature

        if shouldSend then
            local reason = "forced_interval"
            if not lastSentSignature then
                reason = "first_send"
            elseif changed then
                reason = "changed"
            elseif heartbeatDue then
                reason = "heartbeat"
            end

            Logger.log("Tracker send reason=" .. reason .. " | " .. formatData(data))
            local sent = SheetsClient.send(data)
            if sent then
                lastSentSignature = signature
                lastSentAt = tick()
            else
                Logger.log("Tracker send failed, keeping previous snapshot")
            end
        else
            Logger.log("Tracker skip reason=no_change")
        end

        task.wait(interval)
    end
end

return Tracker
