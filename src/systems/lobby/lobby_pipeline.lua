local RewardSystem = require("systems.reward.reward_system")
local Tracker = require("systems.tracker.tracker_system")
local UnitEquipSystem = require("systems.lobby.unit_equip_system")
local SettingsSystem = require("systems.lobby.settings_system")
local MatchCreateSystem = require("systems.lobby.match_create_system")
local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local LobbyPipeline = {}

local function step(statusText, fn)
    StatusBus.set(statusText)
    Logger.log(statusText)
    if fn then
        return fn()
    end
    return nil
end

function LobbyPipeline.run()
    step("Resgatando rewards", function()
        RewardSystem.run()
        Tracker.sendNow()
    end)

    local equipResult = step("Equipando unidade", function()
        local result = UnitEquipSystem.run()
        if not result or not result.ok then
            Logger.log("UnitEquip step falhou (pipeline interrompido por seguranca)")
        end
        return result
    end)
    if not equipResult or not equipResult.ok then
        return {
            ok = false,
            nextState = "recovery",
            reason = "unit_equip_failed",
        }
    end

    local settingsResult = step("Configurando settings", function()
        local result = SettingsSystem.run()
        if not result or not result.ok then
            Logger.log("Settings step falhou (continuando pipeline)")
        end
        return result
    end)
    if not settingsResult or not settingsResult.ok then
        Logger.log("Settings apply failed: seguindo para proximas etapas")
    end

    local matchCreateResult = step("Entrando na partida", function()
        local result = MatchCreateSystem.run()
        if not result or not result.ok then
            Logger.log("MatchCreate step falhou (pipeline interrompido por seguranca)")
        end
        return result
    end)
    if not matchCreateResult or not matchCreateResult.ok then
        return {
            ok = false,
            nextState = "recovery",
            reason = "match_create_failed",
        }
    end

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return LobbyPipeline
