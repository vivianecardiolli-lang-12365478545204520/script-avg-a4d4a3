local config = require("core.config")
local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local LegacyUiRewardSystem = require("systems.reward.reward_ui_legacy_system")
local ModuleRewardSystem = require("systems.reward.reward_module_system")

local RewardSystem = {}
local warnedInvalidMode = false

function RewardSystem.run()
    local mode = tostring((config.rewards and config.rewards.claimMode) or "module")
    local normalizedMode = string.lower(mode)

    if normalizedMode == "module" then
        Logger.log("RewardSystem mode=module")
        StatusBus.setDetail("Rewards | Execucao | iniciando rotina de rewards")
        ModuleRewardSystem.run()
        return
    end

    if normalizedMode == "legacy_ui" then
        Logger.log("RewardSystem mode=legacy_ui")
        StatusBus.setDetail("Rewards | Execucao | iniciando rotina de rewards")
        LegacyUiRewardSystem.run()
        return
    end

    local message = "[KAITUN] ATENCAO DESENVOLVEDOR (RewardSystem): rewards.claimMode invalido. Use 'module' ou 'legacy_ui'. Valor atual: " .. tostring(mode)
    if not warnedInvalidMode then
        warnedInvalidMode = true
        warn(message)
        Logger.log(message)
    end
    StatusBus.setDetail("Rewards | Configuracao | modo de claim invalido")
end

return RewardSystem
