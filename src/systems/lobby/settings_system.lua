local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local config = require("core.config")

local SettingsSystem = {}
local rng = Random.new()
local hasAppliedOnce = false

local MIN_ACTION_DELAY = 0.25
local MAX_ACTION_DELAY = 0.65

local TARGET_SETTINGS = {
    DisableGlobalMessages = true,
    DisableEnemyTags = true,
    SimplifiedEnemyGui = true,
    DisableCameraShake = true,
    DisableDepthOfField = true,
    LowDetailMode = true,
    HideFamiliars = true,
    ShowFriendMarkers = true,
    SimpleInventoryMode = true,
    DisableViewCutscenes = true,
    SkipSummonAnimation = true,
    AutoSkipWaves = true,
    SelectUnitOnPlacement = true,
    ShowMultipliersOnHover = true,
    TapToRun = true,
    AutoReplay = true,
    DisableMatchEndRewardsView = true,
    ShowMaxRangeOnPlacement = true,
    AFKAlert = true,
    AutoSkipStart = true,
    HideOthersUnits = true,
    DisableStatMultiplierPopups = true,
    DisplayFortune = true,
    DisableVisualEffects = true,
    DisableDamageIndicators = true,
    AutoUpgradeDuringPlacement = true,
    DayNightCycle = "Cycle",
    PlacedUnitsVisibility = "All",
}

local function devAlert(message)
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (Settings): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function getNativeRequire()
    if type(getrenv) == "function" then
        local env = getrenv()
        if env and type(env.require) == "function" then
            return env.require
        end
    end
    if type(_G) == "table" and type(_G.require) == "function" then
        return _G.require
    end
    return nil
end

local function resolveSettingsHandler()
    local modules = StarterPlayer:FindFirstChild("Modules")
    local gameplay = modules and modules:FindFirstChild("Gameplay")
    local handlerModule = gameplay and gameplay:FindFirstChild("SettingsHandler")
    if not handlerModule or not handlerModule:IsA("ModuleScript") then
        return nil, "StarterPlayer.Modules.Gameplay.SettingsHandler nao encontrado"
    end

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        return nil, "Require nativo indisponivel para SettingsHandler"
    end

    local ok, handlerOrErr = pcall(nativeRequire, handlerModule)
    if not ok then
        return nil, "Falha ao require SettingsHandler: " .. tostring(handlerOrErr)
    end

    return handlerOrErr, nil
end

local function resolveSettingsRemote()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local settings = networking and networking:FindFirstChild("Settings")
    local event = settings and settings:FindFirstChild("SettingsEvent")
    if not event then
        return nil, "Remote Networking.Settings.SettingsEvent nao encontrado"
    end
    return event, nil
end

local function shuffledSettings()
    local list = {}
    for name, value in pairs(TARGET_SETTINGS) do
        table.insert(list, { name = name, target = value })
    end
    for i = #list, 2, -1 do
        local j = rng:NextInteger(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function SettingsSystem.run()
    local lobbyPlaceId = tonumber(config.automation and config.automation.lobbyPlaceId)
    if lobbyPlaceId and game.PlaceId ~= lobbyPlaceId then
        Logger.log(string.format(
            "Settings sync skipped: current placeId=%s is not lobby placeId=%s",
            tostring(game.PlaceId),
            tostring(lobbyPlaceId)
        ))
        return { ok = false, reason = "not_in_lobby" }
    end

    if hasAppliedOnce then
        Logger.log("Settings sync skipped: already applied once in this execution")
        return { ok = true, skippedRun = true }
    end

    local settingsHandler, handlerErr = resolveSettingsHandler()
    if handlerErr then
        devAlert(handlerErr)
        return { ok = false, reason = "settings_handler_missing" }
    end

    if type(settingsHandler.GetSetting) ~= "function" then
        devAlert("SettingsHandler.GetSetting nao disponivel")
        return { ok = false, reason = "settings_handler_api_invalid" }
    end

    local settingsEvent, remoteErr = resolveSettingsRemote()
    if remoteErr then
        devAlert(remoteErr)
        return { ok = false, reason = "settings_remote_missing" }
    end

    local appliedCount = 0
    local skippedCount = 0
    local unknownCount = 0

    for _, entry in ipairs(shuffledSettings()) do
        local okCurrent, current = pcall(function()
            return settingsHandler:GetSetting(entry.name)
        end)

        if not okCurrent then
            unknownCount = unknownCount + 1
            devAlert("Falha ao ler setting '" .. tostring(entry.name) .. "': " .. tostring(current))
            continue
        end

        if current == nil then
            unknownCount = unknownCount + 1
            devAlert("Setting '" .. tostring(entry.name) .. "' nao encontrada no handler")
            continue
        end

        if current == entry.target then
            skippedCount = skippedCount + 1
            continue
        end

        if type(entry.target) == "boolean" then
            settingsEvent:FireServer("Toggle", entry.name)
        else
            settingsEvent:FireServer("ChangeValue", {
                Name = entry.name,
                Value = entry.target,
            })
        end

        local delay = rng:NextNumber(MIN_ACTION_DELAY, MAX_ACTION_DELAY)
        task.wait(delay)
        appliedCount = appliedCount + 1
    end

    Logger.log(string.format(
        "Settings sync finished applied=%d skipped=%d unknown=%d",
        appliedCount,
        skippedCount,
        unknownCount
    ))
    hasAppliedOnce = true

    return {
        ok = true,
        applied = appliedCount,
        skipped = skippedCount,
        unknown = unknownCount,
    }
end

return SettingsSystem
