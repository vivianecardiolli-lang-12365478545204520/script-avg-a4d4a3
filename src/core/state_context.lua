local StateContext = {}

local context = {
    lastLocation = "unknown",
    tutorialHandledAtLeastOnce = false,
    tutorialGateValidated = false,
    didInitialLobbyPipeline = false,
    retries = 0,
}

function StateContext.get()
    return context
end

function StateContext.setLocation(location)
    context.lastLocation = location
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

function StateContext.incrementRetry()
    context.retries = context.retries + 1
end

function StateContext.resetRetry()
    context.retries = 0
end

return StateContext
