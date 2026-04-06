local StatusBus = {}

local currentStatus = "Idle"
local currentDetail = "-"
local listeners = {}

local function notifyAll()
    for _, listener in ipairs(listeners) do
        local ok = pcall(listener, currentStatus, currentDetail)
        if not ok then
            -- Ignore listener failures to keep bus resilient.
        end
    end
end

function StatusBus.set(statusText, detailText)
    local normalized = tostring(statusText or "Idle")

    local statusChanged = normalized ~= currentStatus
    local detailChanged = false

    if statusChanged then
        currentStatus = normalized
        if detailText == nil then
            if currentDetail ~= "-" then
                currentDetail = "-"
                detailChanged = true
            end
        end
    end

    if detailText ~= nil then
        local normalizedDetail = tostring(detailText)
        if normalizedDetail ~= currentDetail then
            currentDetail = normalizedDetail
            detailChanged = true
        end
    end

    if not statusChanged and not detailChanged then
        return
    end

    notifyAll()
end

function StatusBus.get()
    return currentStatus
end

function StatusBus.setDetail(detailText)
    local normalizedDetail = tostring(detailText or "-")
    if normalizedDetail == currentDetail then
        return
    end
    currentDetail = normalizedDetail
    notifyAll()
end

function StatusBus.getDetail()
    return currentDetail
end

function StatusBus.clearDetail()
    StatusBus.setDetail("-")
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
