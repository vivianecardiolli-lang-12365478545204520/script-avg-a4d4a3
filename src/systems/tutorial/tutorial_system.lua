local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialSystem = {}

local TUTORIAL_REMOTE_PATH = "Networking.ClientListeners.NEWTutorialEvent"
local warnedMissingRemote = false
local warnedDetectionUnavailable = false

local function resolveTutorialRemote()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local listeners = networking and networking:FindFirstChild("ClientListeners")
    local remote = listeners and listeners:FindFirstChild("NEWTutorialEvent")
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

local function logMissingRemote()
    if warnedMissingRemote then
        return
    end
    warnedMissingRemote = true
    local message = string.format(
        "[KAITUN] ATENCAO DESENVOLVEDOR: Remote '%s' nao encontrado. Verifique se o jogo atualizou.",
        TUTORIAL_REMOTE_PATH
    )
    warn(message)
    Logger.log(message)
end

local function logDetectionUnavailable(reason)
    if warnedDetectionUnavailable then
        return
    end
    warnedDetectionUnavailable = true
    local message = "[KAITUN] ATENCAO DESENVOLVEDOR: Falha ao detectar status do tutorial via upvalues (" .. tostring(reason) .. ")"
    warn(message)
    Logger.log(message)
end

local function getTutorialStatusViaUpvalues()
    local ok, status, reason = pcall(function()
        local networking = ReplicatedStorage:FindFirstChild("Networking")
        local listeners = networking and networking:FindFirstChild("ClientListeners")
        if not listeners then
            return 0
        end

        if type(getconnections) ~= "function" then
            return nil, "getconnections_unavailable"
        end
        if type(debug) ~= "table" or type(debug.getupvalues) ~= "function" then
            return nil, "debug_getupvalues_unavailable"
        end

        local priority = listeners:FindFirstChild("NEWTutorialEvent")
        local remotes = {}

        if priority and priority:IsA("RemoteEvent") then
            table.insert(remotes, priority)
        end

        for _, remote in ipairs(listeners:GetChildren()) do
            if remote ~= priority and remote:IsA("RemoteEvent") then
                table.insert(remotes, remote)
            end
        end

        for _, remote in ipairs(remotes) do
            local connections = getconnections(remote.OnClientEvent)
            if connections then
                for _, conn in ipairs(connections) do
                    local fn = conn and conn.Function
                    if type(fn) == "function" then
                        for _, upv in pairs(debug.getupvalues(fn)) do
                            if type(upv) == "table" and rawget(upv, "IsInTutorial") ~= nil then
                                if upv.IsInTutorial == true then
                                    if type(upv.IsActive) == "function" and upv.IsActive("PartTwo") then
                                        return 2
                                    end
                                    return 1
                                end
                                return 0
                            end
                        end
                    end
                end
            end
        end

        return 0
    end)

    if not ok then
        return nil, tostring(status)
    end

    return status, reason
end

local function fireSkipTutorial(status)
    local remote = resolveTutorialRemote()
    if not remote then
        logMissingRemote()
        return false
    end

    warnedMissingRemote = false

    if status == 1 then
        remote:FireServer("PartOne", "Skip")
        Logger.log("[KAITUN] Tutorial PartOne pulado.")
        return true
    end

    if status == 2 then
        remote:FireServer("PartTwo", "Skip")
        Logger.log("[KAITUN] Tutorial PartTwo pulado.")
        return true
    end

    return false
end

function TutorialSystem.run()
    local status, detectionErr = getTutorialStatusViaUpvalues()
    if status == nil then
        logDetectionUnavailable(detectionErr)
        return {
            ok = false,
            handled = false,
            status = 0,
            reason = "tutorial_status_detection_failed",
        }
    end

    warnedDetectionUnavailable = false

    if status == 0 then
        return {
            ok = true,
            handled = false,
            status = 0,
        }
    end

    StatusBus.set("Pulando tutorial")
    local fired = fireSkipTutorial(status)
    if fired then
        task.wait(0.35)
    else
        return {
            ok = false,
            handled = false,
            status = status,
            reason = "tutorial_skip_remote_failed",
        }
    end

    return {
        ok = true,
        handled = fired,
        status = status,
    }
end

return TutorialSystem
