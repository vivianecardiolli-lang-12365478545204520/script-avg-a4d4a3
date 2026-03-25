local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local TutorialSystem = {}

function TutorialSystem.run(state)
    if not state or not state.tutorialVisible then
        return {
            ok = true,
            handled = false,
        }
    end

    StatusBus.set("Pulando tutorial")
    Logger.log("Tutorial detected (placeholder), skipping not implemented yet")

    return {
        ok = true,
        handled = true,
    }
end

return TutorialSystem
