local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local AutoPlaySystem = require("systems.match.autoplay_system")
local CustomPlaySystem = require("systems.match.custom_play_system")
local config = require("core.config")

local MatchPipeline = {}
local warnedInvalidMode = false

function MatchPipeline.run()
    local context = StateContext.get()
    if not context.tutorialGateValidated then
        Logger.log("Match pipeline blocked: tutorial gate not validated")
        return {
            ok = false,
            nextState = "recovery",
            reason = "tutorial_gate_not_validated",
        }
    end

    local mode = tostring((config.automation and config.automation.playMode) or "native")
    local modeLower = string.lower(mode)

    if modeLower == "native" then
        StatusBus.set("Verificando autoplay nativo")
        local autoPlayResult = AutoPlaySystem.run()
        if not autoPlayResult.ok then
            Logger.log("AutoPlay native check failed: " .. tostring(autoPlayResult.reason))
        end
    elseif modeLower == "custom" then
        StatusBus.set("Verificando autoplay custom")
        local customPlayResult = CustomPlaySystem.run()
        if not customPlayResult.ok then
            Logger.log("AutoPlay custom check failed: " .. tostring(customPlayResult.reason))
        end
    else
        local message = "[KAITUN] ATENCAO DESENVOLVEDOR (MatchPipeline): automation.playMode invalido. Use 'native' ou 'custom'. Valor atual: " .. tostring(mode)
        if not warnedInvalidMode then
            warnedInvalidMode = true
            warn(message)
            Logger.log(message)
        end
        return {
            ok = false,
            nextState = "recovery",
            reason = "invalid_play_mode",
        }
    end

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return MatchPipeline
