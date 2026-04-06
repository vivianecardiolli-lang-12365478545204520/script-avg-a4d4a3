local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local HttpService = game:GetService("HttpService")

local Logger = require("core.logger")
local config = require("core.config")
local StatusBus = require("core.status_bus")

local CustomPlaySystem = {}

local DEFAULT_BASE_POSITIONS = {
    Vector3.new(436.09, 5.30, -344.17),
    Vector3.new(441.93, 5.30, -349.75),
    Vector3.new(433.46, 5.30, -353.14),
    Vector3.new(422.96, 5.30, -349.97),
}

local warned = {}
local runtime = {
    started = false,
    queue = {},
    lastPlacementAt = 0,
}

local dependencies = nil
local remotes = nil

local function devAlertOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (CustomPlay): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function setPlayDetail(message)
    StatusBus.setDetail("Partida | AutoPlay custom | " .. tostring(message))
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

local function getSettings()
    local automation = config.automation or {}
    local settings = automation.customPlay or {}
    return {
        playMode = tostring(automation.playMode or "native"),
        matchPlaceId = tonumber(automation.matchPlaceId),
        unitName = tostring(settings.unitName or "Bounty Hunter"),
        slotIndex = tonumber(settings.slotIndex or 1) or 1,
        basePositions = settings.basePositions,
        placementCooldownSeconds = tonumber(settings.placementCooldownSeconds or 2.5) or 2.5,
        validationAttempts = tonumber(settings.validationAttempts or 15) or 15,
        jitterMin = tonumber(settings.jitterMin or -3) or -3,
        jitterMax = tonumber(settings.jitterMax or 3) or 3,
        dpsStopMinSeconds = tonumber(settings.dpsStopMinSeconds or 0.10) or 0.10,
        dpsStopMaxSeconds = tonumber(settings.dpsStopMaxSeconds or 0.20) or 0.20,
        placeReactionMinSeconds = tonumber(settings.placeReactionMinSeconds or 0.25) or 0.25,
        placeReactionMaxSeconds = tonumber(settings.placeReactionMaxSeconds or 0.45) or 0.45,
        loopDelayMinSeconds = tonumber(settings.loopDelayMinSeconds or 2.5) or 2.5,
        loopDelayMaxSeconds = tonumber(settings.loopDelayMaxSeconds or 5.0) or 5.0,
        upgradeDelayMinSeconds = tonumber(settings.upgradeDelayMinSeconds or 0.20) or 0.20,
        upgradeDelayMaxSeconds = tonumber(settings.upgradeDelayMaxSeconds or 0.40) or 0.40,
        maxPlacementsFallback = tonumber(settings.maxPlacementsFallback or 4) or 4,
    }
end

local function normalizeSettings(settings)
    if settings.slotIndex < 1 then
        settings.slotIndex = 1
    end
    if settings.placementCooldownSeconds < 0 then
        settings.placementCooldownSeconds = 0
    end
    if settings.validationAttempts < 1 then
        settings.validationAttempts = 1
    end
    if settings.jitterMax < settings.jitterMin then
        settings.jitterMax = settings.jitterMin
    end
    if settings.dpsStopMinSeconds < 0 then
        settings.dpsStopMinSeconds = 0
    end
    if settings.dpsStopMaxSeconds < settings.dpsStopMinSeconds then
        settings.dpsStopMaxSeconds = settings.dpsStopMinSeconds
    end
    if settings.placeReactionMinSeconds < 0 then
        settings.placeReactionMinSeconds = 0
    end
    if settings.placeReactionMaxSeconds < settings.placeReactionMinSeconds then
        settings.placeReactionMaxSeconds = settings.placeReactionMinSeconds
    end
    if settings.loopDelayMinSeconds < 0.1 then
        settings.loopDelayMinSeconds = 0.1
    end
    if settings.loopDelayMaxSeconds < settings.loopDelayMinSeconds then
        settings.loopDelayMaxSeconds = settings.loopDelayMinSeconds
    end
    if settings.upgradeDelayMinSeconds < 0 then
        settings.upgradeDelayMinSeconds = 0
    end
    if settings.upgradeDelayMaxSeconds < settings.upgradeDelayMinSeconds then
        settings.upgradeDelayMaxSeconds = settings.upgradeDelayMinSeconds
    end
    if settings.maxPlacementsFallback < 1 then
        settings.maxPlacementsFallback = 1
    end
end

local function randomFloat(minValue, maxValue)
    if maxValue <= minValue then
        return minValue
    end
    return minValue + (math.random() * (maxValue - minValue))
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

local function resolveBasePositions(settings)
    local out = {}
    local list = settings.basePositions
    if type(list) == "table" then
        for _, value in ipairs(list) do
            local pos = toVector3(value)
            if pos then
                table.insert(out, pos)
            end
        end
    end
    if #out > 0 then
        return out
    end
    devAlertOnce("base_positions_invalid", "customPlay.basePositions invalido; usando fallback padrao")
    return DEFAULT_BASE_POSITIONS
end

local function isInMatch(settings)
    local matchPlaceId = settings.matchPlaceId
    if matchPlaceId and game.PlaceId ~= matchPlaceId then
        return false
    end
    return true
end

local function resolveDependencies()
    if dependencies and remotes then
        return dependencies, remotes, nil
    end

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        return nil, nil, "Require nativo indisponivel"
    end

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local gameplay = modules and modules:FindFirstChild("Gameplay")
    local starterModules = StarterPlayer:FindFirstChild("Modules")
    local starterGameplay = starterModules and starterModules:FindFirstChild("Gameplay")
    local entities = modules and modules:FindFirstChild("Data") and modules.Data:FindFirstChild("Entities")

    if not gameplay or not starterGameplay or not entities then
        return nil, nil, "Arvore de modulos de gameplay nao encontrada"
    end

    local validationModule = gameplay:FindFirstChild("PlacementValidationHandler")
    local yenModule = starterGameplay:FindFirstChild("PlayerYenHandler")
    local unitsFolder = starterGameplay:FindFirstChild("Units")
    local unitHandlerModule = unitsFolder and unitsFolder:FindFirstChild("ClientUnitHandler")
    local unitsDataModule = entities:FindFirstChild("Units")
    local unitManager = starterGameplay:FindFirstChild("UnitManager")
    local autoUpgradeFolder = unitManager and unitManager:FindFirstChild("AutoUpgrade")
    local autoUpgradeDataModule = autoUpgradeFolder and autoUpgradeFolder:FindFirstChild("AutoUpgradeDataHandler")

    if not validationModule then
        return nil, nil, "Module PlacementValidationHandler nao encontrado"
    end
    if not yenModule then
        return nil, nil, "Module PlayerYenHandler nao encontrado"
    end
    if not unitHandlerModule then
        return nil, nil, "Module ClientUnitHandler nao encontrado"
    end
    if not unitsDataModule then
        return nil, nil, "Module Data.Entities.Units nao encontrado"
    end
    if not autoUpgradeDataModule then
        return nil, nil, "Module AutoUpgradeDataHandler nao encontrado"
    end

    local okValidation, Validation = pcall(nativeRequire, validationModule)
    if not okValidation then
        return nil, nil, "Falha ao require PlacementValidationHandler: " .. tostring(Validation)
    end
    local okYen, YenHandler = pcall(nativeRequire, yenModule)
    if not okYen then
        return nil, nil, "Falha ao require PlayerYenHandler: " .. tostring(YenHandler)
    end
    local okUnitHandler, ClientUnitHandler = pcall(nativeRequire, unitHandlerModule)
    if not okUnitHandler then
        return nil, nil, "Falha ao require ClientUnitHandler: " .. tostring(ClientUnitHandler)
    end
    local okUnitsData, UnitsData = pcall(nativeRequire, unitsDataModule)
    if not okUnitsData then
        return nil, nil, "Falha ao require UnitsData: " .. tostring(UnitsData)
    end
    local okUpgradeData, AutoUpgradeData = pcall(nativeRequire, autoUpgradeDataModule)
    if not okUpgradeData then
        return nil, nil, "Falha ao require AutoUpgradeDataHandler: " .. tostring(AutoUpgradeData)
    end

    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local unitsNet = networking and networking:FindFirstChild("Units")
    local unitEvent = networking and networking:FindFirstChild("UnitEvent")
    local dpsEvent = unitsNet and unitsNet:FindFirstChild("EffectiveDPSEvent")
    local autoUpgradeEvent = unitsNet and unitsNet:FindFirstChild("AutoUpgradeEvent")

    if not unitEvent then
        return nil, nil, "Remote Networking.UnitEvent nao encontrado"
    end
    if not dpsEvent then
        return nil, nil, "Remote Networking.Units.EffectiveDPSEvent nao encontrado"
    end
    if not autoUpgradeEvent then
        return nil, nil, "Remote Networking.Units.AutoUpgradeEvent nao encontrado"
    end

    dependencies = {
        Validation = Validation,
        YenHandler = YenHandler,
        ClientUnitHandler = ClientUnitHandler,
        UnitsData = UnitsData,
        AutoUpgradeData = AutoUpgradeData,
    }
    remotes = {
        UnitEvent = unitEvent,
        DPSEvent = dpsEvent,
        AutoUpgradeEvent = autoUpgradeEvent,
    }

    return dependencies, remotes, nil
end

local function getActiveUnits(deps)
    local activeUnits = deps.ClientUnitHandler and deps.ClientUnitHandler._ActiveUnits
    if type(activeUnits) ~= "table" then
        devAlertOnce("active_units_missing", "ClientUnitHandler._ActiveUnits indisponivel")
        return nil
    end
    return activeUnits
end

local function countCurrentPlacements(deps, unitName)
    local activeUnits = getActiveUnits(deps)
    if not activeUnits then
        return 0
    end
    local count = 0
    for _, data in pairs(activeUnits) do
        if type(data) == "table" and data.Name == unitName then
            count = count + 1
        end
    end
    return count
end

local function generateSequence(settings)
    local basePositions = resolveBasePositions(settings)
    runtime.queue = {}

    local indices = {}
    for i = 1, #basePositions do
        indices[i] = i
    end

    for i = #indices, 2, -1 do
        local j = math.random(i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    for _, idx in ipairs(indices) do
        table.insert(runtime.queue, { pos = basePositions[idx], idOriginal = idx })
    end

    local seq = {}
    for _, item in ipairs(runtime.queue) do
        table.insert(seq, "#" .. tostring(item.idOriginal))
    end
    Logger.log("[CustomPlay] Nova sequencia Fisher-Yates: [ " .. table.concat(seq, " ") .. " ]")
    setPlayDetail("nova sequencia de posicionamento gerada")
end

local function ensureAutoUpgrade(settings, deps, net)
    local unitName = settings.unitName
    local okInfo, infoUnit = pcall(deps.UnitsData.GetUnitByName, deps.UnitsData, unitName)
    if not okInfo then
        devAlertOnce("unit_info_upgrade_read", "Falha ao consultar unidade para upgrade: " .. tostring(infoUnit))
        return
    end
    if not infoUnit then
        devAlertOnce("unit_missing_upgrade", "UnitsData:GetUnitByName retornou nil para " .. tostring(unitName))
        return
    end

    local maxPlacements = infoUnit.MaxPlacements or settings.maxPlacementsFallback
    if countCurrentPlacements(deps, unitName) < maxPlacements then
        return
    end

    local okUpgraded, upgradedUnits = pcall(deps.AutoUpgradeData.GetUnits)
    if not okUpgraded then
        devAlertOnce("auto_upgrade_units_read", "Falha ao ler AutoUpgradeData.GetUnits: " .. tostring(upgradedUnits))
        return
    end
    if type(upgradedUnits) ~= "table" then
        devAlertOnce("auto_upgrade_units_invalid", "AutoUpgradeData.GetUnits nao retornou tabela")
        return
    end

    local activeUnits = getActiveUnits(deps)
    if not activeUnits then
        return
    end

    for guid, data in pairs(activeUnits) do
        if type(data) == "table" and data.Name == unitName and not upgradedUnits[guid] then
            Logger.log("[CustomPlay] Ativando Auto-Upgrade para " .. tostring(data.Name))
            setPlayDetail("ativando auto-upgrade de " .. tostring(data.Name))
            local okToggle, toggleErr = pcall(function()
                net.AutoUpgradeEvent:FireServer("Toggle", guid)
                deps.AutoUpgradeData.AutoUpgradeToggled:Fire(guid, true)
            end)
            if not okToggle then
                devAlertOnce("auto_upgrade_toggle", "Falha ao ativar auto-upgrade: " .. tostring(toggleErr))
                return
            end
            task.wait(randomFloat(settings.upgradeDelayMinSeconds, settings.upgradeDelayMaxSeconds))
        end
    end
end

local function tryPlacement(settings, deps, net)
    if tick() - runtime.lastPlacementAt < settings.placementCooldownSeconds then
        return false
    end

    local unitName = settings.unitName
    local okInfo, infoUnit = pcall(deps.UnitsData.GetUnitByName, deps.UnitsData, unitName)
    if not okInfo then
        devAlertOnce("unit_info_placement_read", "Falha ao consultar unidade para placement: " .. tostring(infoUnit))
        return false
    end
    if not infoUnit then
        devAlertOnce("unit_missing_placement", "UnitsData:GetUnitByName retornou nil para " .. tostring(unitName))
        return false
    end

    local maxPlacements = infoUnit.MaxPlacements or settings.maxPlacementsFallback
    local currentPlacements = countCurrentPlacements(deps, unitName)
    local basePositions = resolveBasePositions(settings)

    if currentPlacements == 0 and #runtime.queue < #basePositions then
        generateSequence(settings)
    end

    if currentPlacements >= maxPlacements then
        return false
    end

    local okYen, currentYen = pcall(deps.YenHandler.GetYen)
    if not okYen then
        devAlertOnce("yen_read_failed", "Falha ao ler YenHandler.GetYen: " .. tostring(currentYen))
        return false
    end
    if tonumber(currentYen) == nil then
        devAlertOnce("yen_invalid", "YenHandler.GetYen nao retornou numero")
        return false
    end

    if currentYen < (infoUnit.Price or 0) then
        return false
    end

    if #runtime.queue == 0 then
        generateSequence(settings)
    end

    local target = runtime.queue[#runtime.queue]
    if not target then
        return false
    end

    Logger.log(string.format("[CustomPlay] Tentando posicao #%s (restantes apos sucesso: %s)", tostring(target.idOriginal), tostring(#runtime.queue - 1)))
    setPlayDetail("tentando posicionar unidade na referencia #" .. tostring(target.idOriginal))

    local okDpsStop, errDpsStop = pcall(function()
        net.DPSEvent:FireServer("Stop")
    end)
    if not okDpsStop then
        devAlertOnce("dps_stop_failed", "Falha ao sinalizar DPS Stop: " .. tostring(errDpsStop))
        return false
    end

    task.wait(randomFloat(settings.dpsStopMinSeconds, settings.dpsStopMaxSeconds))

    local okDpsRetrieve, errDpsRetrieve = pcall(function()
        net.DPSEvent:FireServer("Retrieve", HttpService:GenerateGUID(false))
    end)
    if not okDpsRetrieve then
        devAlertOnce("dps_retrieve_failed", "Falha ao sinalizar DPS Retrieve: " .. tostring(errDpsRetrieve))
        return false
    end

    local positionFinal = nil
    local activeUnits = getActiveUnits(deps)
    if not activeUnits then
        return false
    end

    for _ = 1, settings.validationAttempts do
        local offset = Vector3.new(
            math.random(settings.jitterMin, settings.jitterMax),
            0,
            math.random(settings.jitterMin, settings.jitterMax)
        )
        local okValidate, canFit, corrected = pcall(deps.Validation.CanFitUnit, nil, {
            UnitPosition = target.pos + offset,
            UnitName = unitName,
            Units = activeUnits,
            IgnoreOtherUnits = false,
        })
        if okValidate and canFit then
            positionFinal = corrected
            break
        end
    end

    if not positionFinal then
        return false
    end

    task.wait(randomFloat(settings.placeReactionMinSeconds, settings.placeReactionMaxSeconds))

    local okPlace, placeErr = pcall(function()
        net.UnitEvent:FireServer("Render", { unitName, infoUnit.ID, positionFinal, 0 }, { SlotIndex = settings.slotIndex })
    end)
    if not okPlace then
        devAlertOnce("unit_render_failed", "Falha no UnitEvent:FireServer(Render): " .. tostring(placeErr))
        return false
    end

    table.remove(runtime.queue, #runtime.queue)
    runtime.lastPlacementAt = tick()
    Logger.log("[CustomPlay] Sucesso no placement da referencia #" .. tostring(target.idOriginal))
    setPlayDetail("unidade posicionada na referencia #" .. tostring(target.idOriginal))
    return true
end

local function startLoopIfNeeded()
    if runtime.started then
        return
    end
    runtime.started = true

    Logger.log("[CustomPlay] Loop iniciado.")
    setPlayDetail("loop iniciado")
    generateSequence(getSettings())

    task.spawn(function()
        while true do
            local settings = getSettings()
            normalizeSettings(settings)

            if settings.playMode == "custom" and isInMatch(settings) then
                local deps, net, depErr = resolveDependencies()
                if depErr then
                    devAlertOnce("resolve_dependencies", depErr)
                    setPlayDetail("aguardando dependencias de gameplay")
                    task.wait(2)
                else
                    local okMain, errMain = pcall(function()
                        tryPlacement(settings, deps, net)
                        ensureAutoUpgrade(settings, deps, net)
                    end)
                    if not okMain then
                        devAlertOnce("custom_loop_exception", "Excecao no loop custom: " .. tostring(errMain))
                        setPlayDetail("erro interno no loop")
                    end
                    task.wait(randomFloat(settings.loopDelayMinSeconds, settings.loopDelayMaxSeconds))
                end
            else
                setPlayDetail("aguardando entrada em partida")
                task.wait(1)
            end
        end
    end)
end

function CustomPlaySystem.run()
    local settings = getSettings()
    if settings.playMode ~= "custom" then
        return { ok = true, skipped = true, reason = "mode_not_custom" }
    end

    if not isInMatch(settings) then
        return { ok = true, skipped = true, reason = "not_in_match" }
    end

    startLoopIfNeeded()
    return { ok = true }
end

return CustomPlaySystem
