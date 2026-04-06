local Players = game:GetService("Players")

local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local config = require("core.config")

local PreAutoplayPositioningSystem = {}

local DEFAULT_BASE_POSITIONS = {
    Vector3.new(436.09, 5.30, -344.17),
    Vector3.new(441.93, 5.30, -349.75),
    Vector3.new(433.46, 5.30, -353.14),
    Vector3.new(422.96, 5.30, -349.97),
}

local warned = {}

local function devAlertOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (PreAutoPlayPositioning): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function toVector3(value)
    if typeof(value) == "Vector3" then
        return value
    end
    if type(value) == "table" then
        local x = tonumber(value.x or value.X or value[1])
        local y = tonumber(value.y or value.Y or value[2])
        local z = tonumber(value.z or value.Z or value[3])
        if x and y and z then
            return Vector3.new(x, y, z)
        end
    end
    return nil
end

local function getSettings()
    local automation = config.automation or {}
    local customPlay = automation.customPlay or {}
    local positioning = automation.preAutoplayPositioning or {}
    return {
        enabled = positioning.enabled ~= false,
        moveTimeoutSeconds = tonumber(positioning.moveTimeoutSeconds or 12) or 12,
        arrivalRadius = tonumber(positioning.arrivalRadius or 6) or 6,
        jitterMin = tonumber(customPlay.jitterMin or -3) or -3,
        jitterMax = tonumber(customPlay.jitterMax or 3) or 3,
        basePositions = customPlay.basePositions,
    }
end

local function normalizeSettings(settings)
    if settings.moveTimeoutSeconds < 2 then
        settings.moveTimeoutSeconds = 2
    end
    if settings.arrivalRadius < 1 then
        settings.arrivalRadius = 1
    end
    if settings.jitterMax < settings.jitterMin then
        settings.jitterMax = settings.jitterMin
    end
end

local function resolveBasePositions(settings)
    local result = {}
    if type(settings.basePositions) == "table" then
        for _, value in ipairs(settings.basePositions) do
            local pos = toVector3(value)
            if pos then
                table.insert(result, pos)
            end
        end
    end

    if #result > 0 then
        return result
    end

    devAlertOnce("base_positions_invalid", "customPlay.basePositions ausente/invalido; usando fallback padrao")
    return DEFAULT_BASE_POSITIONS
end

local function chooseRandomTarget(basePositions, settings)
    local shuffled = {}
    for i = 1, #basePositions do
        shuffled[i] = basePositions[i]
    end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local base = shuffled[1]
    local offset = Vector3.new(
        math.random(settings.jitterMin, settings.jitterMax),
        0,
        math.random(settings.jitterMin, settings.jitterMax)
    )
    return base + offset
end

local function getCharacterParts()
    local player = Players.LocalPlayer
    if not player then
        return nil, nil, nil, "local_player_missing"
    end

    local character = player.Character
    if not character then
        return nil, nil, nil, "character_missing"
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        return nil, nil, nil, "humanoid_or_root_missing"
    end

    return character, humanoid, rootPart, nil
end

function PreAutoplayPositioningSystem.run()
    local settings = getSettings()
    normalizeSettings(settings)
    if not settings.enabled then
        return { ok = true, skipped = true, reason = "disabled" }
    end

    local _, humanoid, rootPart, err = getCharacterParts()
    if err then
        StatusBus.setDetail("Partida | Posicionamento | aguardando personagem")
        return { ok = false, retryable = true, reason = err }
    end

    local basePositions = resolveBasePositions(settings)
    if #basePositions <= 0 then
        devAlertOnce("no_base_positions", "Nenhuma base position disponivel para pre-posicionamento")
        return { ok = false, retryable = false, reason = "no_base_positions" }
    end

    local target = chooseRandomTarget(basePositions, settings)
    StatusBus.set("Posicionando antes do autoplay")
    StatusBus.setDetail("Partida | Posicionamento | movendo para ponto inicial")
    Logger.log(string.format(
        "[PreAutoPlayPositioning] Movendo para destino inicial: (%.2f, %.2f, %.2f)",
        target.X, target.Y, target.Z
    ))

    local okMove, moveErr = pcall(function()
        humanoid:MoveTo(target)
    end)
    if not okMove then
        devAlertOnce("moveto_failed", "Falha ao executar Humanoid:MoveTo: " .. tostring(moveErr))
        return { ok = false, retryable = false, reason = "moveto_failed" }
    end

    local finished = false
    local reached = false
    local moveConnection
    moveConnection = humanoid.MoveToFinished:Connect(function(didReach)
        finished = true
        reached = didReach == true
    end)

    local deadline = os.clock() + settings.moveTimeoutSeconds
    while os.clock() < deadline and not finished do
        if not rootPart.Parent or not humanoid.Parent then
            if moveConnection then
                moveConnection:Disconnect()
            end
            return { ok = false, retryable = true, reason = "character_lost_during_move" }
        end

        local remaining = math.max(1, math.ceil(deadline - os.clock()))
        StatusBus.setDetail("Partida | Posicionamento | em deslocamento (" .. tostring(remaining) .. "s)")
        task.wait(0.2)
    end

    if moveConnection then
        moveConnection:Disconnect()
    end

    local distance = (rootPart.Position - target).Magnitude
    local consideredReached = reached or distance <= settings.arrivalRadius
    if not consideredReached then
        Logger.log(string.format(
            "[PreAutoPlayPositioning] Timeout sem chegada completa (distancia=%.2f).",
            distance
        ))
        StatusBus.setDetail("Partida | Posicionamento | timeout, seguindo fluxo")
        return { ok = false, retryable = false, reason = "move_timeout", distance = distance }
    end

    StatusBus.setDetail("Partida | Posicionamento | concluido")
    Logger.log("[PreAutoPlayPositioning] Posicionamento inicial concluido.")
    return { ok = true, moved = true, distance = distance }
end

return PreAutoplayPositioningSystem
