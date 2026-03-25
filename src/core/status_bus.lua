local StatusBus = {}

local currentStatus = "Idle"
local listeners = {}

local function notifyAll()
    for _, listener in ipairs(listeners) do
        local ok = pcall(listener, currentStatus)
        if not ok then
            -- Ignore listener failures to keep bus resilient.
        end
    end
end

function StatusBus.set(statusText)
    local normalized = tostring(statusText or "Idle")
    if normalized == currentStatus then
        return
    end
    currentStatus = normalized
    notifyAll()
end

function StatusBus.get()
    return currentStatus
end

function StatusBus.subscribe(callback)
    if type(callback) ~= "function" then
        return function() end
    end

    table.insert(listeners, callback)
    local index = #listeners

    return function()
        if listeners[index] == callback then
            listeners[index] = function() end
        end
    end
end

return StatusBus
