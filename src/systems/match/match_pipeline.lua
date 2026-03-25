local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local MatchPipeline = {}

function MatchPipeline.run()
    StatusBus.set("Verificando autoplay")
    Logger.log("Match pipeline placeholder: autoplay check not implemented yet")
    task.wait(0.1)

    StatusBus.set("Ativando anti-AFK")
    Logger.log("Match pipeline placeholder: anti-AFK not implemented yet")
    task.wait(0.1)

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return MatchPipeline
