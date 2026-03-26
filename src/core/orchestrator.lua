local config = require("core.config")
local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local GameStateDetector = require("core.game_state_detector")
local HudSystem = require("systems.hud.hud_system")
local TutorialSystem = require("systems.tutorial.tutorial_system")
local LobbyPipeline = require("systems.lobby.lobby_pipeline")
local MatchPipeline = require("systems.match.match_pipeline")
local RecoverySystem = require("systems.recovery.recovery_system")
local Tracker = require("systems.tracker.tracker_system")

local Orchestrator = {}
local lastUnknownRecoveryAt = 0
local UNKNOWN_RECOVERY_COOLDOWN_SECONDS = 20
local lastStateLogKey = nil

local function detectAndRun()
    local state = GameStateDetector.detect()
    local stateLogKey = string.format(
        "location=%s;tutorial=%s;reason=%s;placeId=%s",
        tostring(state.location),
        tostring(state.tutorialVisible),
        tostring(state.reason),
        tostring(state.placeId)
    )
    if stateLogKey ~= lastStateLogKey then
        lastStateLogKey = stateLogKey
        Logger.log(string.format(
            "State detected location=%s tutorial=%s reason=%s placeId=%s configuredLobby=%s configuredMatch=%s",
            tostring(state.location),
            tostring(state.tutorialVisible),
            tostring(state.reason),
            tostring(state.placeId),
            tostring(state.configuredLobbyPlaceId),
            tostring(state.configuredMatchPlaceId)
        ))
    end

    StateContext.setLocation(state.location)

    local context = StateContext.get()

    if state.location == "lobby" then
        if config.automation.runLobbyPipelineOncePerSession and context.didInitialLobbyPipeline then
            StatusBus.set("Lobby pronto (aguardando proxima etapa)")
            return
        end

        local result = LobbyPipeline.run()
        if result.ok then
            StateContext.markInitialLobbyPipelineDone()
            return
        end

        RecoverySystem.run("lobby_pipeline_failed")
        return
    end

    if state.location == "match" then
        local result = MatchPipeline.run()
        if not result.ok then
            RecoverySystem.run("match_pipeline_failed")
        end
        return
    end

    StatusBus.set("Sincronizando estado")
    local now = os.clock()
    if now - lastUnknownRecoveryAt >= UNKNOWN_RECOVERY_COOLDOWN_SECONDS then
        lastUnknownRecoveryAt = now
        RecoverySystem.run("unknown_location")
    end
end

function Orchestrator.run()
    if not config.automation.enabled then
        Logger.log("Automation disabled by config")
        return
    end

    local tutorialResult = TutorialSystem.run()
    if not tutorialResult.ok then
        RecoverySystem.run("tutorial_failed")
        return
    end
    if tutorialResult.handled then
        StateContext.markTutorialHandled()
    end

    task.spawn(function()
        Tracker.startLoop()
    end)

    HudSystem.start()
    StatusBus.set("Inicializando")
    Logger.log("Orchestrator started")

    local tickSeconds = tonumber(config.automation.tickSeconds) or 2
    if tickSeconds <= 0 then
        tickSeconds = 2
    end

    task.spawn(function()
        while true do
            local ok, err = pcall(detectAndRun)
            if not ok then
                Logger.log("Orchestrator loop error: " .. tostring(err))
                RecoverySystem.run("orchestrator_exception")
            end
            task.wait(tickSeconds)
        end
    end)
end

return Orchestrator
