local StateContext = {}

local context = {
    lastLocation = "unknown",
    tutorialHandledAtLeastOnce = false,
    tutorialGateValidated = false,
    didInitialLobbyPipeline = false,
    didPreAutoplayPositioningInMatch = false,
    retries = 0,
    matchAutomationBlockedUntil = 0,
    matchAutomationBlockReason = nil,
}

function StateContext.get()
    return context
end

function StateContext.setLocation(location)
    local previous = context.lastLocation
    context.lastLocation = location
    if location ~= previous then
        if location == "match" then
            context.didPreAutoplayPositioningInMatch = false
        elseif previous == "match" then
            context.didPreAutoplayPositioningInMatch = false
        end
    end
end

function StateContext.markTutorialHandled()
    context.tutorialHandledAtLeastOnce = true
end

function StateContext.markTutorialValidated()
    context.tutorialGateValidated = true
end

function StateContext.markInitialLobbyPipelineDone()
    context.didInitialLobbyPipeline = true
end

function StateContext.markPreAutoplayPositioningDone()
    context.didPreAutoplayPositioningInMatch = true
end

function StateContext.incrementRetry()
    context.retries = context.retries + 1
end

function StateContext.resetRetry()
    context.retries = 0
end

function StateContext.blockMatchAutomationFor(seconds, reason)
    local duration = tonumber(seconds) or 0
    if duration < 0 then
        duration = 0
    end

    local now = os.clock()
    local candidate = now + duration
    if candidate > (context.matchAutomationBlockedUntil or 0) then
        context.matchAutomationBlockedUntil = candidate
        context.matchAutomationBlockReason = tostring(reason or "unspecified")
    end
end

function StateContext.getMatchAutomationBlockRemaining()
    local untilTs = tonumber(context.matchAutomationBlockedUntil) or 0
    local remaining = untilTs - os.clock()
    if remaining <= 0 then
        context.matchAutomationBlockedUntil = 0
        context.matchAutomationBlockReason = nil
        return 0
    end
    return remaining
end

function StateContext.getMatchAutomationBlockReason()
    return context.matchAutomationBlockReason
end

return StateContext
