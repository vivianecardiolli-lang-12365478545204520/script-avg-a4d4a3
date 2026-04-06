local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local config = require("core.config")

local UnitEquipSystem = {}
local rng = Random.new()
local REMOVE_TO_EQUIP_MIN_DELAY = 0.14
local REMOVE_TO_EQUIP_MAX_DELAY = 0.32

local function devAlert(message)
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (UnitEquip): " .. tostring(message)
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

local function resolveRemotes()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    if not networking then
        return nil, nil, "Networking nao encontrado"
    end

    local units = networking:FindFirstChild("Units")
    local equipRemote = units and units:FindFirstChild("EquipEvent")

    local listeners = networking:FindFirstChild("ClientListeners")
    local recentRemote = listeners and listeners:FindFirstChild("RecentUnitsEvent")

    if not equipRemote then
        return nil, nil, "Remote Networking.Units.EquipEvent nao encontrado"
    end
    if not recentRemote then
        return nil, nil, "Remote Networking.ClientListeners.RecentUnitsEvent nao encontrado"
    end

    return equipRemote, recentRemote, nil
end

local function resolveOwnedUnitsHandler()
    local modules = StarterPlayer:FindFirstChild("Modules")
    local gameplay = modules and modules:FindFirstChild("Gameplay")
    local units = gameplay and gameplay:FindFirstChild("Units")
    local handlerModule = units and units:FindFirstChild("OwnedUnitsHandler")

    if not handlerModule or not handlerModule:IsA("ModuleScript") then
        return nil, "StarterPlayer.Modules.Gameplay.Units.OwnedUnitsHandler nao encontrado"
    end

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        return nil, "Require nativo indisponivel para ModuleScript (getrenv().require)"
    end

    local ok, handlerOrErr = pcall(nativeRequire, handlerModule)
    if not ok then
        return nil, "Falha ao require OwnedUnitsHandler: " .. tostring(handlerOrErr)
    end

    return handlerOrErr, nil
end

local function runEquip(unitName, slot)
    local equipRemote, recentRemote, remoteErr = resolveRemotes()
    if remoteErr then
        devAlert(remoteErr)
        return { ok = false, reason = "remote_missing" }
    end

    local ownedUnitsHandler, handlerErr = resolveOwnedUnitsHandler()
    if handlerErr then
        devAlert(handlerErr)
        return { ok = false, reason = "handler_missing" }
    end

    if type(ownedUnitsHandler.GetOwnedUnits) ~= "function" then
        devAlert("OwnedUnitsHandler.GetOwnedUnits nao disponivel")
        return { ok = false, reason = "invalid_handler_api" }
    end

    local okOwned, unitsOrErr = pcall(ownedUnitsHandler.GetOwnedUnits)
    if not okOwned or type(unitsOrErr) ~= "table" then
        devAlert("Falha ao obter unidades possuidas: " .. tostring(unitsOrErr))
        return { ok = false, reason = "owned_units_read_failed" }
    end

    local bestUUID = nil
    local bestLevel = -1
    local matchedName = false

    for uuid, info in pairs(unitsOrErr) do
        local name = ""
        if type(info) == "table" then
            if type(info.UnitData) == "table" and type(info.UnitData.Name) == "string" then
                name = info.UnitData.Name
            elseif type(info.Identifier) == "string" then
                name = info.Identifier
            end
        end

        if string.lower(name) == string.lower(unitName) then
            matchedName = true
            local level = tonumber(info.Level) or 0
            if level > bestLevel then
                bestLevel = level
                bestUUID = uuid
            end
        end
    end

    if not matchedName then
        devAlert("Nenhuma unidade '" .. tostring(unitName) .. "' encontrada no inventario")
        return { ok = false, reason = "unit_not_found" }
    end

    if not bestUUID then
        devAlert("Unidade alvo encontrada, mas UUID valido nao foi identificado")
        return { ok = false, reason = "unit_uuid_missing" }
    end

    if type(ownedUnitsHandler.GetEquippedSlot) == "function" then
        local okSlot, equippedSlot = pcall(ownedUnitsHandler.GetEquippedSlot, bestUUID)
        if okSlot and equippedSlot == slot then
            Logger.log(string.format(
                "UnitEquip skip: '%s' level=%d ja esta no slot %d",
                tostring(unitName),
                bestLevel,
                slot
            ))
            return { ok = true, skipped = true }
        end
    end

    recentRemote:FireServer("Remove", bestUUID)
    local waitBetween = rng:NextNumber(REMOVE_TO_EQUIP_MIN_DELAY, REMOVE_TO_EQUIP_MAX_DELAY)
    task.wait(waitBetween)
    equipRemote:FireServer("Equip", bestUUID, slot)

    Logger.log(string.format(
        "UnitEquip enviado: unit='%s' uuid=%s level=%d slot=%d removeToEquipDelay=%.3fs",
        tostring(unitName),
        tostring(bestUUID),
        bestLevel,
        slot,
        waitBetween
    ))

    return {
        ok = true,
        skipped = false,
        uuid = bestUUID,
        level = bestLevel,
    }
end

function UnitEquipSystem.run()
    local unitName = tostring((config.automation and config.automation.equipUnitName) or "Bounty Hunter")
    local slot = tonumber((config.automation and config.automation.equipSlot) or 1) or 1
    if slot < 1 then
        slot = 1
    end

    return runEquip(unitName, slot)
end

return UnitEquipSystem
