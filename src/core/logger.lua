local config = require("core.config")

local Logger = {}
local logs = {}

function Logger.log(mensagem)
    local line = "[DEBUG] " .. tostring(mensagem)
    print(line)
    table.insert(logs, line)

    if config.logger.exportToClipboard and setclipboard then
        setclipboard(table.concat(logs, "\n"))
    end
end

function Logger.exportToClipboard()
    if setclipboard then
        setclipboard(table.concat(logs, "\n"))
        return true
    end
    return false
end

function Logger.getLogs()
    return logs
end

return Logger