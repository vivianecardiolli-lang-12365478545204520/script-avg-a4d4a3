local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local RecoverySystem = {}

function RecoverySystem.run(reason)
    StatusBus.set("Recovery")
    StatusBus.setDetail("Motivo: " .. tostring(reason or "unknown"))
    Logger.log("Recovery invoked: " .. tostring(reason or "unknown"))
    task.wait(0.25)
    return {
        ok = true,
        nextState = "state_detect",
    }
end

return RecoverySystem
