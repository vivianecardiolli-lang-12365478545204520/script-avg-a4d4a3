local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local AutoPlaySystem = require("systems.match.autoplay_system")

local MatchPipeline = {}

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

    StatusBus.set("Verificando autoplay")
    local autoPlayResult = AutoPlaySystem.run()
    if not autoPlayResult.ok then
        Logger.log("AutoPlay check failed: " .. tostring(autoPlayResult.reason))
    end

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return MatchPipeline
