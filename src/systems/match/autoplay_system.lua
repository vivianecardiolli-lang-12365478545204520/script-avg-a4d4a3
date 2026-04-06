local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local config = require("core.config")
local StatusBus = require("core.status_bus")

local AutoPlaySystem = {}

local warned = {}
local lastCheckAt = 0
local CHECK_INTERVAL_SECONDS = 4
local lastActiveLogAt = 0
local ACTIVE_LOG_INTERVAL_SECONDS = 20

local function devAlertOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (AutoPlay): " .. tostring(message)
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

local function resolveAutoPlayHandler()
    local modules = StarterPlayer:FindFirstChild("Modules")
    local gameplay = modules and modules:FindFirstChild("Gameplay")
    local autoPlay = gameplay and gameplay:FindFirstChild("AutoPlay")
    local handlerModule = autoPlay and autoPlay:FindFirstChild("AutoPlayHandler")
    if not handlerModule or not handlerModule:IsA("ModuleScript") then
        return nil, "StarterPlayer.Modules.Gameplay.AutoPlay.AutoPlayHandler nao encontrado"
    end

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        return nil, "Require nativo indisponivel para AutoPlayHandler"
    end

    local ok, moduleOrErr = pcall(nativeRequire, handlerModule)
    if not ok then
        return nil, "Falha ao require AutoPlayHandler: " .. tostring(moduleOrErr)
    end

    if type(moduleOrErr.IsAutoPlaying) ~= "function" then
        return nil, "AutoPlayHandler.IsAutoPlaying nao disponivel"
    end

    return moduleOrErr, nil
end

local function resolveAutoPlayRemote()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local event = networking and networking:FindFirstChild("AutoPlayEvent")
    if not event then
        return nil, "Remote Networking.AutoPlayEvent nao encontrado"
    end
    return event, nil
end

function AutoPlaySystem.run()
    local matchPlaceId = tonumber(config.automation and config.automation.matchPlaceId)
    if matchPlaceId and game.PlaceId ~= matchPlaceId then
        return { ok = true, skipped = true, reason = "not_in_match" }
    end

    local now = os.clock()
    if now - lastCheckAt < CHECK_INTERVAL_SECONDS then
        return { ok = true, skipped = true, reason = "check_cooldown" }
    end
    lastCheckAt = now

    local handler, handlerErr = resolveAutoPlayHandler()
    if handlerErr then
        devAlertOnce("handler", handlerErr)
        return { ok = false, reason = "autoplay_handler_missing" }
    end

    local event, remoteErr = resolveAutoPlayRemote()
    if remoteErr then
        devAlertOnce("remote", remoteErr)
        return { ok = false, reason = "autoplay_remote_missing" }
    end

    local okStatus, isPlaying = pcall(handler.IsAutoPlaying)
    if not okStatus then
        devAlertOnce("status_read", "Falha ao ler IsAutoPlaying: " .. tostring(isPlaying))
        return { ok = false, reason = "autoplay_status_read_failed" }
    end

    if not isPlaying then
        Logger.log("[AutoPlay] Desativado. Enviando Toggle.")
        StatusBus.setDetail("Partida | AutoPlay nativo | desativado, enviando ativacao")
        event:FireServer("Toggle")
        return { ok = true, toggled = true }
    end

    if now - lastActiveLogAt >= ACTIVE_LOG_INTERVAL_SECONDS then
        lastActiveLogAt = now
        Logger.log("[AutoPlay] Ja esta ativo.")
    end
    StatusBus.setDetail("Partida | AutoPlay nativo | ativo")

    return { ok = true, toggled = false }
end

return AutoPlaySystem
