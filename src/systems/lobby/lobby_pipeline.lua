local RewardSystem = require("systems.reward.reward_system")
local Tracker = require("systems.tracker.tracker_system")
local UnitEquipSystem = require("systems.lobby.unit_equip_system")
local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local LobbyPipeline = {}

local function step(statusText, fn)
    StatusBus.set(statusText)
    Logger.log(statusText)
    if fn then
        fn()
    end
end

function LobbyPipeline.run()
    step("Resgatando rewards", function()
        RewardSystem.run()
        Tracker.sendNow()
    end)

    step("Equipando unidade", function()
        local result = UnitEquipSystem.run()
        if not result or not result.ok then
            Logger.log("UnitEquip step finalizou com aviso (continuando pipeline)")
        end
    end)

    step("Lendo configuracoes")
    step("Configurando settings")
    step("Indo para area de partidas")
    step("Entrando na partida")

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return LobbyPipeline
