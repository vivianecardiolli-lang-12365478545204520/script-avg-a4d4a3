local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local config = require("core.config")
local Logger = require("core.logger")

local AntiAfkSystem = {}

local runtime = {
    started = false,
    movementActive = false,
    lastLocation = "unknown",
    anchorPosition = nil,
    character = nil,
    root = nil,
    humanoid = nil,
    idledConnection = nil,
    chamblerHookInstalled = false,
    hookRetryWarned = false,
    lastBlockedEventLogAt = 0,
}

local logs = {}
local blockedAfkEventSignal = Instance.new("BindableEvent").Event

local function getSettings()
    local settings = (config.automation and config.automation.antiAfk) or {}
    return {
        enabled = settings.enabled ~= false,
        debugMode = settings.debugMode ~= false,
        movementEnabled = settings.movementEnabled ~= false,
        jumpEnabled = settings.jumpEnabled ~= false,
        roamRadiusMin = tonumber(settings.roamRadiusMin) or 10,
        roamRadiusMax = tonumber(settings.roamRadiusMax) or 50,
        intervalMinSeconds = tonumber(settings.intervalMinSeconds) or 180,
        intervalMaxSeconds = tonumber(settings.intervalMaxSeconds) or 600,
        jumpChancePercent = tonumber(settings.jumpChancePercent) or 40,
        maxJumpsPerMovement = tonumber(settings.maxJumpsPerMovement) or 2,
        moveToTimeoutSeconds = tonumber(settings.moveToTimeoutSeconds) or 25,
        destinationValidationAttempts = tonumber(settings.destinationValidationAttempts) or 10,
        destinationRaycastUp = tonumber(settings.destinationRaycastUp) or 20,
        destinationRaycastDown = tonumber(settings.destinationRaycastDown) or 80,
        chamblerHeartbeatSeconds = tonumber(settings.chamblerHeartbeatSeconds) or 5,
        autoExportLogsToClipboard = settings.autoExportLogsToClipboard == true,
        exportIntervalSeconds = tonumber(settings.exportIntervalSeconds) or 300,
    }
end

local function normalizeSettings(settings)
    if settings.roamRadiusMin < 1 then
        settings.roamRadiusMin = 1
    end
    if settings.roamRadiusMax < settings.roamRadiusMin then
        settings.roamRadiusMax = settings.roamRadiusMin
    end
    if settings.intervalMinSeconds < 1 then
        settings.intervalMinSeconds = 1
    end
    if settings.intervalMaxSeconds < settings.intervalMinSeconds then
        settings.intervalMaxSeconds = settings.intervalMinSeconds
    end
    if settings.jumpChancePercent < 0 then
        settings.jumpChancePercent = 0
    end
    if settings.jumpChancePercent > 100 then
        settings.jumpChancePercent = 100
    end
    if settings.maxJumpsPerMovement < 0 then
        settings.maxJumpsPerMovement = 0
    end
    if settings.moveToTimeoutSeconds < 1 then
        settings.moveToTimeoutSeconds = 1
    end
    if settings.destinationValidationAttempts < 1 then
        settings.destinationValidationAttempts = 1
    end
    if settings.destinationRaycastUp < 1 then
        settings.destinationRaycastUp = 1
    end
    if settings.destinationRaycastDown < 10 then
        settings.destinationRaycastDown = 10
    end
    if settings.chamblerHeartbeatSeconds < 1 then
        settings.chamblerHeartbeatSeconds = 1
    end
    if settings.exportIntervalSeconds < 10 then
        settings.exportIntervalSeconds = 10
    end
end

local function addLog(message)
    local line = string.format("[ANTI-AFK][%s] %s", os.date("%H:%M:%S"), tostring(message))
    table.insert(logs, line)
    Logger.log(line)
end

local function reportFailure(stage, err)
    local message = string.format(
        "[KAITUN] ATENCAO DESENVOLVEDOR: Falha no anti-AFK em '%s' (%s)",
        tostring(stage),
        tostring(err)
    )
    warn(message)
    addLog(message)
end

local function exportLogsToClipboard()
    if #logs == 0 then
        return
    end
    if not setclipboard then
        return
    end
    local ok, err = pcall(function()
        setclipboard(table.concat(logs, "\n"))
    end)
    if not ok then
        reportFailure("export_logs_clipboard", err)
        return
    end
    addLog("Logs do anti-AFK exportados para o clipboard.")
end

local function getCharacterStuff()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        return nil, nil, nil, "local_player_missing"
    end

    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    if not character then
        return nil, nil, nil, "character_missing"
    end

    local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)

    if not root then
        return character, nil, nil, "humanoid_root_part_missing"
    end
    if not humanoid then
        return character, root, nil, "humanoid_missing"
    end
    return character, root, humanoid, nil
end

local function ensureCharacter()
    if runtime.character and runtime.root and runtime.humanoid and runtime.root.Parent and runtime.humanoid.Parent then
        return true
    end

    local ok, character, root, humanoid, err = pcall(getCharacterStuff)
    if not ok then
        reportFailure("resolve_character", character)
        return false
    end
    if err then
        reportFailure("resolve_character", err)
        return false
    end

    runtime.character = character
    runtime.root = root
    runtime.humanoid = humanoid
    if runtime.anchorPosition == nil and root then
        runtime.anchorPosition = root.Position
        addLog("Ancora anti-AFK definida em " .. tostring(runtime.anchorPosition))
    end
    return true
end

local function installRobloxAntiIdle()
    if runtime.idledConnection ~= nil then
        return
    end

    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        reportFailure("install_roblox_idle_listener", "local_player_missing")
        return
    end

    local ok, connOrErr = pcall(function()
        return localPlayer.Idled:Connect(function()
            if not runtime.started then
                return
            end
            local success, err = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
            if not success then
                reportFailure("roblox_idle_reset", err)
                return
            end
            addLog("Sinal de idle do Roblox resetado.")
        end)
    end)

    if not ok then
        reportFailure("install_roblox_idle_listener", connOrErr)
        return
    end

    runtime.idledConnection = connOrErr
    addLog("Listener de anti-idle Roblox ativo.")
end

local function tryInstallChamblerHook()
    if runtime.chamblerHookInstalled then
        return true
    end

    if type(hookmetamethod) ~= "function" then
        if not runtime.hookRetryWarned then
            runtime.hookRetryWarned = true
            reportFailure("chambler_hook_install", "hookmetamethod_unavailable")
        end
        return false
    end

    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local afkEvent = networking and networking:FindFirstChild("AFKEvent")
    if not afkEvent then
        return false
    end

    local ok, err = pcall(function()
        local originalIndex
        originalIndex = hookmetamethod(afkEvent, "__index", newcclosure(function(self, key)
            if runtime.started and self == afkEvent and key == "OnClientEvent" then
                local now = os.clock()
                if now - runtime.lastBlockedEventLogAt >= 3 then
                    runtime.lastBlockedEventLogAt = now
                    addLog("Tentativa de AFKEvent (Chambler) bloqueada.")
                end
                return blockedAfkEventSignal
            end
            return originalIndex(self, key)
        end))
    end)

    if not ok then
        reportFailure("chambler_hook_install", err)
        return false
    end

    runtime.hookRetryWarned = false
    runtime.chamblerHookInstalled = true
    addLog("Hook anti-AFK Chambler ativo.")
    return true
end

local function startChamblerHeartbeatLoop()
    task.spawn(function()
        while true do
            local settings = getSettings()
            normalizeSettings(settings)
            task.wait(settings.chamblerHeartbeatSeconds)

            if not runtime.started then
                continue
            end

            local ok, err = pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
                task.wait(0.01)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
            end)

            if not ok then
                reportFailure("chambler_heartbeat_keyevent", err)
            end
        end
    end)
end

local function startChamblerHookRetryLoop()
    task.spawn(function()
        while true do
            task.wait(10)
            if not runtime.started then
                continue
            end
            local ok, err = pcall(tryInstallChamblerHook)
            if not ok then
                reportFailure("chambler_hook_retry_loop", err)
            end
        end
    end)
end

local function executeMovementCycle()
    local settings = getSettings()
    normalizeSettings(settings)

    if not runtime.movementActive or not settings.movementEnabled then
        return
    end

    if not ensureCharacter() then
        return
    end

    if runtime.anchorPosition == nil and runtime.root then
        runtime.anchorPosition = runtime.root.Position
        addLog("Ancora anti-AFK redefinida em " .. tostring(runtime.anchorPosition))
    end

    local function buildRawDestination()
        local angle = math.rad(math.random(0, 360))
        local distance = math.random(settings.roamRadiusMin, settings.roamRadiusMax)
        local offsetX = math.cos(angle) * distance
        local offsetZ = math.sin(angle) * distance
        local destination = Vector3.new(
            runtime.anchorPosition.X + offsetX,
            runtime.anchorPosition.Y,
            runtime.anchorPosition.Z + offsetZ
        )
        return destination, distance
    end

    local function projectToGround(rawDestination)
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        local filter = {}
        if runtime.character then
            table.insert(filter, runtime.character)
        end
        raycastParams.FilterDescendantsInstances = filter
        raycastParams.IgnoreWater = false

        local origin = rawDestination + Vector3.new(0, settings.destinationRaycastUp, 0)
        local direction = Vector3.new(0, -(settings.destinationRaycastUp + settings.destinationRaycastDown), 0)
        local hit = Workspace:Raycast(origin, direction, raycastParams)
        if not hit then
            return nil
        end

        -- Pequeno offset para evitar encostar exatamente na superficie.
        return hit.Position + Vector3.new(0, 2.5, 0)
    end

    local function isReachableByPath(targetDestination)
        if not runtime.humanoid or not runtime.root then
            return false
        end
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })
        local ok, err = pcall(function()
            path:ComputeAsync(runtime.root.Position, targetDestination)
        end)
        if not ok then
            reportFailure("destination_path_compute", err)
            return false
        end
        if path.Status ~= Enum.PathStatus.Success then
            return false
        end

        local waypoints = path:GetWaypoints()
        return #waypoints > 0
    end

    local destination = nil
    local chosenDistance = nil
    for _ = 1, settings.destinationValidationAttempts do
        local rawDestination, distance = buildRawDestination()
        local grounded = projectToGround(rawDestination)
        if grounded and isReachableByPath(grounded) then
            destination = grounded
            chosenDistance = distance
            break
        end
    end

    if not destination then
        addLog("Nenhum destino seguro encontrado para movimento anti-AFK neste ciclo.")
        return
    end

    addLog("Movimento anti-AFK para " .. tostring(math.floor(chosenDistance or 0)) .. " studs (destino validado).")
    local moveOk, moveErr = pcall(function()
        runtime.humanoid:MoveTo(destination)
    end)
    if not moveOk then
        reportFailure("humanoid_move_to", moveErr)
        return
    end

    if settings.jumpEnabled and math.random(1, 100) <= settings.jumpChancePercent then
        task.spawn(function()
            local jumps = math.random(0, settings.maxJumpsPerMovement)
            if jumps <= 0 then
                return
            end
            addLog("Anti-AFK sorteou " .. tostring(jumps) .. " pulo(s).")
            for _ = 1, jumps do
                task.wait(math.random(5, 25) / 10)
                if not runtime.started or not runtime.movementActive then
                    return
                end
                if runtime.humanoid and runtime.humanoid.Parent then
                    local jumpOk, jumpErr = pcall(function()
                        runtime.humanoid.Sit = false
                        runtime.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end)
                    if not jumpOk then
                        reportFailure("humanoid_jump", jumpErr)
                        return
                    end
                end
            end
        end)
    end

    local waitOk, waitErr = pcall(function()
        runtime.humanoid.MoveToFinished:Wait(settings.moveToTimeoutSeconds)
    end)
    if not waitOk then
        reportFailure("move_to_finished_wait", waitErr)
    end
end

local function startMovementLoop()
    task.spawn(function()
        while true do
            local settings = getSettings()
            normalizeSettings(settings)
            local pauseSeconds = math.random(settings.intervalMinSeconds, settings.intervalMaxSeconds)
            task.wait(pauseSeconds)
            if not runtime.started then
                continue
            end
            local ok, err = pcall(executeMovementCycle)
            if not ok then
                reportFailure("movement_cycle", err)
            end
        end
    end)
end

local function startAutoExportLoopIfEnabled()
    task.spawn(function()
        while true do
            local settings = getSettings()
            normalizeSettings(settings)
            task.wait(settings.exportIntervalSeconds)
            if not runtime.started or not settings.autoExportLogsToClipboard then
                continue
            end
            local ok, err = pcall(exportLogsToClipboard)
            if not ok then
                reportFailure("auto_export_loop", err)
            end
        end
    end)
end

function AntiAfkSystem.start()
    local settings = getSettings()
    normalizeSettings(settings)

    if not settings.enabled then
        addLog("Anti-AFK desativado por configuracao.")
        return { ok = true, disabled = true }
    end

    if runtime.started then
        return { ok = true, alreadyStarted = true }
    end

    runtime.started = true
    runtime.movementActive = false
    addLog("Sistema anti-AFK iniciado (aguardando estado da localizacao).")

    local okIdle, errIdle = pcall(installRobloxAntiIdle)
    if not okIdle then
        reportFailure("start_install_roblox_idle", errIdle)
    end

    local okHook, errHook = pcall(tryInstallChamblerHook)
    if not okHook then
        reportFailure("start_install_chambler_hook", errHook)
    end

    startChamblerHeartbeatLoop()
    startChamblerHookRetryLoop()
    startMovementLoop()
    startAutoExportLoopIfEnabled()

    return { ok = true }
end

function AntiAfkSystem.updateLocation(location)
    if not runtime.started then
        return {
            ok = false,
            reason = "anti_afk_not_started",
        }
    end

    local normalizedLocation = tostring(location or "unknown")
    local shouldMove = normalizedLocation == "match"
    runtime.movementActive = shouldMove

    if normalizedLocation ~= runtime.lastLocation then
        runtime.lastLocation = normalizedLocation
        if normalizedLocation == "match" then
            runtime.anchorPosition = nil
            addLog("Anti-AFK ativo em partida: movimentacao e pulo habilitados.")
        elseif normalizedLocation == "lobby" then
            addLog("Anti-AFK ativo em lobby: movimentacao e pulo desabilitados.")
        else
            addLog("Anti-AFK ativo em local desconhecido: movimentacao e pulo desabilitados.")
        end
    end

    return {
        ok = true,
        movementActive = runtime.movementActive,
        location = normalizedLocation,
    }
end

return AntiAfkSystem
