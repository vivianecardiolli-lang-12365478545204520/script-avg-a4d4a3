local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local config = require("core.config")
local StatusBus = require("core.status_bus")

local LobbyUiGuardSystem = {}

local runtime = {
    started = false,
    lobbyActive = false,
    lastLocation = "unknown",
    targets = {},
    warned = {},
}

local function devAlertOnce(key, message)
    if runtime.warned[key] then
        return
    end
    runtime.warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (LobbyUIGuard): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function getSettings()
    local settings = (config.automation and config.automation.lobbyUiGuard) or {}
    return {
        enabled = settings.enabled ~= false,
        tickSeconds = tonumber(settings.tickSeconds) or 0.5,
        resolveRetrySeconds = tonumber(settings.resolveRetrySeconds) or 5,
        closeLogCooldownSeconds = tonumber(settings.closeLogCooldownSeconds) or 15,
        enableUpdateLogOptOut = settings.enableUpdateLogOptOut ~= false,
        suppressDuringLegacyRewardClaim = settings.suppressDuringLegacyRewardClaim ~= false,
    }
end

local function normalizeSettings(settings)
    if settings.tickSeconds < 0.2 then
        settings.tickSeconds = 0.2
    end
    if settings.resolveRetrySeconds < 1 then
        settings.resolveRetrySeconds = 1
    end
    if settings.closeLogCooldownSeconds < 1 then
        settings.closeLogCooldownSeconds = 1
    end
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
    return require
end

local function resolvePath(pathParts)
    local node = game
    for _, step in ipairs(pathParts) do
        if not node then
            return nil
        end
        node = node:FindFirstChild(step)
    end
    return node
end

local function ensureTargetsInitialized()
    if #runtime.targets > 0 then
        return
    end

    runtime.targets = {
        {
            name = "DailyRewards",
            path = { "StarterPlayer", "Modules", "Gameplay", "DailyRewards", "DailyRewardsHandler" },
            instance = nil,
            handler = nil,
            nextResolveAt = 0,
            lastCloseLogAt = 0,
        },
        {
            name = "NewPlayer",
            path = { "StarterPlayer", "Modules", "Gameplay", "DailyRewards", "NewPlayer", "NewPlayerHandler" },
            instance = nil,
            handler = nil,
            nextResolveAt = 0,
            lastCloseLogAt = 0,
        },
        {
            name = "ReturningPlayer",
            path = { "StarterPlayer", "Modules", "Gameplay", "DailyRewards", "ReturningPlayer", "ReturningPlayerHandler" },
            instance = nil,
            handler = nil,
            nextResolveAt = 0,
            lastCloseLogAt = 0,
        },
        {
            name = "UpdateLog",
            path = { "StarterPlayer", "Modules", "Miscellaneous", "UpdateLogHandler" },
            instance = nil,
            handler = nil,
            nextResolveAt = 0,
            lastCloseLogAt = 0,
        },
    }
end

local function shouldPauseForLegacyRewardClaim(settings)
    if not settings.suppressDuringLegacyRewardClaim then
        return false
    end

    local rewardClaimMode = tostring((config.rewards and config.rewards.claimMode) or "module")
    if string.lower(rewardClaimMode) ~= "legacy_ui" then
        return false
    end

    return StatusBus.get() == "Resgatando rewards"
end

local function resolveTargetHandler(target, settings, nativeRequire)
    if target.handler then
        return true
    end

    local now = os.clock()
    if now < target.nextResolveAt then
        return false
    end

    target.nextResolveAt = now + settings.resolveRetrySeconds
    target.instance = resolvePath(target.path)
    if not target.instance then
        devAlertOnce(
            "target_missing_" .. tostring(target.name),
            "Modulo nao encontrado para target '" .. tostring(target.name) .. "' em StarterPlayer"
        )
        return false
    end

    local ok, handlerOrErr = pcall(nativeRequire, target.instance)
    if not ok then
        devAlertOnce(
            "target_require_" .. tostring(target.name),
            "Falha ao require do target '" .. tostring(target.name) .. "': " .. tostring(handlerOrErr)
        )
        return false
    end

    if type(handlerOrErr) ~= "table" then
        devAlertOnce(
            "target_invalid_" .. tostring(target.name),
            "Require do target '" .. tostring(target.name) .. "' nao retornou tabela"
        )
        return false
    end

    if type(handlerOrErr.CloseInterface) ~= "function" then
        devAlertOnce(
            "target_close_missing_" .. tostring(target.name),
            "Target '" .. tostring(target.name) .. "' nao possui CloseInterface"
        )
        return false
    end

    target.handler = handlerOrErr
    Logger.log("[LobbyUIGuard] Handler resolvido: " .. tostring(target.name))
    return true
end

local function maybeSetUpdateLogOptOut(target, settings)
    if target.name ~= "UpdateLog" or not settings.enableUpdateLogOptOut then
        return
    end

    if target.handler.ShowOncePerUpdate ~= false then
        return
    end

    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local updateEvent = networking and networking:FindFirstChild("UpdateLogEvent")
    if not updateEvent or not updateEvent:IsA("RemoteEvent") then
        devAlertOnce("updatelog_remote_missing", "Remote Networking.UpdateLogEvent nao encontrado")
        return
    end

    local ok, err = pcall(function()
        updateEvent:FireServer("Update", true)
        target.handler.ShowOncePerUpdate = true
    end)
    if not ok then
        devAlertOnce("updatelog_optout_failed", "Falha ao marcar UpdateLog ShowOncePerUpdate=true: " .. tostring(err))
        return
    end

    Logger.log("[LobbyUIGuard] UpdateLog marcado para nao exibir novamente.")
end

local function closeTarget(target, settings)
    local ok = pcall(function()
        target.handler:CloseInterface()
    end)
    if not ok then
        ok = pcall(function()
            target.handler.CloseInterface()
        end)
    end
    if not ok then
        devAlertOnce(
            "close_failed_" .. tostring(target.name),
            "Falha ao executar CloseInterface para '" .. tostring(target.name) .. "'"
        )
        return
    end

    local now = os.clock()
    if now - target.lastCloseLogAt >= settings.closeLogCooldownSeconds then
        target.lastCloseLogAt = now
        Logger.log("[LobbyUIGuard] CloseInterface executado em " .. tostring(target.name))
    end
end

local function startLoop()
    task.spawn(function()
        local nativeRequire = getNativeRequire()
        while true do
            local settings = getSettings()
            normalizeSettings(settings)

            if runtime.started and runtime.lobbyActive and settings.enabled then
                if not shouldPauseForLegacyRewardClaim(settings) then
                    for _, target in ipairs(runtime.targets) do
                        local resolvedOk = resolveTargetHandler(target, settings, nativeRequire)
                        if resolvedOk then
                            maybeSetUpdateLogOptOut(target, settings)
                            closeTarget(target, settings)
                        end
                    end
                end
            end

            task.wait(settings.tickSeconds)
        end
    end)
end

function LobbyUiGuardSystem.start()
    local settings = getSettings()
    normalizeSettings(settings)
    if not settings.enabled then
        Logger.log("[LobbyUIGuard] Desativado por configuracao.")
        return { ok = true, disabled = true }
    end

    if runtime.started then
        return { ok = true, alreadyStarted = true }
    end

    runtime.started = true
    ensureTargetsInitialized()
    startLoop()
    Logger.log("[LobbyUIGuard] Iniciado.")
    return { ok = true }
end

function LobbyUiGuardSystem.updateLocation(location)
    if not runtime.started then
        return { ok = false, reason = "lobby_ui_guard_not_started" }
    end

    local normalized = tostring(location or "unknown")
    runtime.lobbyActive = normalized == "lobby"
    if normalized ~= runtime.lastLocation then
        runtime.lastLocation = normalized
        if runtime.lobbyActive then
            Logger.log("[LobbyUIGuard] Ativo no lobby.")
        else
            Logger.log("[LobbyUIGuard] Em pausa fora do lobby.")
        end
    end

    return {
        ok = true,
        lobbyActive = runtime.lobbyActive,
        location = normalized,
    }
end

return LobbyUiGuardSystem
