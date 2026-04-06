local config = require("core.config")
local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local GameStateDetector = require("core.game_state_detector")
local HudSystem = require("systems.hud.hud_system")
local TutorialSystem = require("systems.tutorial.tutorial_system")
local LobbyPipeline = require("systems.lobby.lobby_pipeline")
local LobbyUiGuardSystem = require("systems.lobby.lobby_ui_guard_system")
local MatchPipeline = require("systems.match.match_pipeline")
local AntiAfkSystem = require("systems.match.anti_afk_system")
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

    StatusBus.setDetail(string.format(
        "Local=%s | Tutorial=%s | Motivo=%s",
        tostring(state.location),
        tostring(state.tutorialVisible),
        tostring(state.reason)
    ))

    StateContext.setLocation(state.location)
    local lobbyUiGuardResult = LobbyUiGuardSystem.updateLocation(state.location)
    if not lobbyUiGuardResult.ok then
        Logger.log("Lobby UI Guard location update failed: " .. tostring(lobbyUiGuardResult.reason))
    end

    local antiAfkResult = AntiAfkSystem.updateLocation(state.location)
    if not antiAfkResult.ok then
        Logger.log("Anti-AFK location update failed: " .. tostring(antiAfkResult.reason))
    end

    local context = StateContext.get()

    if state.location == "lobby" then
        if config.automation.runLobbyPipelineOncePerSession and context.didInitialLobbyPipeline then
            StatusBus.set("Lobby pronto (aguardando proxima etapa)")
            StatusBus.setDetail("Pipeline de lobby ja executado nesta sessao")
            return
        end

        local result = LobbyPipeline.run()
        if result.ok then
            StateContext.markInitialLobbyPipelineDone()
            return
        end

        Logger.log("Lobby pipeline failed: " .. tostring(result.reason))
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
    StatusBus.setDetail("Aguardando identificacao de lobby/partida")
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
        Logger.log("Tutorial gate failed: " .. tostring(tutorialResult.reason))
        RecoverySystem.run("tutorial_failed")
        return
    end
    StateContext.markTutorialValidated()
    if tutorialResult.handled then
        StateContext.markTutorialHandled()
    end

    local lobbyUiGuardStartResult = LobbyUiGuardSystem.start()
    if not lobbyUiGuardStartResult.ok then
        Logger.log("Falha ao iniciar Lobby UI Guard: " .. tostring(lobbyUiGuardStartResult.reason))
        RecoverySystem.run("lobby_ui_guard_start_failed")
        return
    end

    local antiAfkStartResult = AntiAfkSystem.start()
    if not antiAfkStartResult.ok then
        Logger.log("Falha ao iniciar anti-AFK: " .. tostring(antiAfkStartResult.reason))
        RecoverySystem.run("anti_afk_start_failed")
        return
    end

    task.spawn(function()
        Tracker.startLoop()
    end)

    HudSystem.start()
    StatusBus.set("Inicializando")
    StatusBus.setDetail("Boot do orquestrador concluido")
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
