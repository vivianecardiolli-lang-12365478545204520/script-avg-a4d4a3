local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local AutoPlaySystem = require("systems.match.autoplay_system")
local CustomPlaySystem = require("systems.match.custom_play_system")
local PreAutoplayPositioningSystem = require("systems.match.pre_autoplay_positioning_system")
local config = require("core.config")

local MatchPipeline = {}
local warnedInvalidMode = false
local lastBlockLogAt = 0
local BLOCK_LOG_INTERVAL_SECONDS = 5

function MatchPipeline.run()
    local context = StateContext.get()
    if not context.tutorialGateValidated then
        Logger.log("Match pipeline blocked: tutorial gate not validated")
        return {
            ok = false,
            nextState = "recovery",
            reason = "tutorial_gate_not_validated",
        }
    end

    local blockRemaining = StateContext.getMatchAutomationBlockRemaining and StateContext.getMatchAutomationBlockRemaining() or 0
    if blockRemaining > 0 then
        local remainingSeconds = math.max(1, math.ceil(blockRemaining))
        local reason = StateContext.getMatchAutomationBlockReason and StateContext.getMatchAutomationBlockReason() or "unknown"

        StatusBus.set("Aguardando pos-tutorial")
        StatusBus.setDetail(
            string.format("Partida | AutoPlay | pausado por %ss (motivo: %s)", tostring(remainingSeconds), tostring(reason))
        )

        local now = os.clock()
        if now - lastBlockLogAt >= BLOCK_LOG_INTERVAL_SECONDS then
            lastBlockLogAt = now
            Logger.log(string.format(
                "Match pipeline pausado por bloqueio pos-tutorial: remaining=%ss reason=%s",
                tostring(remainingSeconds),
                tostring(reason)
            ))
        end

        return {
            ok = true,
            nextState = "state_detect",
            paused = true,
            reason = "post_tutorial_match_block",
        }
    end

    local mode = tostring((config.automation and config.automation.playMode) or "native")
    local modeLower = string.lower(mode)

    if not context.didPreAutoplayPositioningInMatch then
        local positioningResult = PreAutoplayPositioningSystem.run()
        if positioningResult.ok then
            StateContext.markPreAutoplayPositioningDone()
        elseif positioningResult.retryable then
            return {
                ok = true,
                nextState = "state_detect",
                paused = true,
                reason = "pre_autoplay_positioning_retry",
            }
        else
            Logger.log("Pre-autoplay positioning failed: " .. tostring(positioningResult.reason))
            StateContext.markPreAutoplayPositioningDone()
        end
    end

    if modeLower == "native" then
        StatusBus.set("Verificando autoplay")
        StatusBus.setDetail("Partida | AutoPlay nativo | verificando estado")
        local autoPlayResult = AutoPlaySystem.run()
        if not autoPlayResult.ok then
            Logger.log("AutoPlay native check failed: " .. tostring(autoPlayResult.reason))
            StatusBus.setDetail("Partida | AutoPlay nativo | falha: " .. tostring(autoPlayResult.reason))
        elseif autoPlayResult.toggled then
            StatusBus.setDetail("Partida | AutoPlay nativo | ativacao enviada")
        else
            StatusBus.setDetail("Partida | AutoPlay nativo | ja ativa")
        end
    elseif modeLower == "custom" then
        StatusBus.set("Verificando autoplay")
        StatusBus.setDetail("Partida | AutoPlay custom | preparando loop")
        local customPlayResult = CustomPlaySystem.run()
        if not customPlayResult.ok then
            Logger.log("AutoPlay custom check failed: " .. tostring(customPlayResult.reason))
            StatusBus.setDetail("Partida | AutoPlay custom | falha: " .. tostring(customPlayResult.reason))
        else
            StatusBus.setDetail("Partida | AutoPlay custom | em execucao")
        end
    else
        local message = "[KAITUN] ATENCAO DESENVOLVEDOR (MatchPipeline): automation.playMode invalido. Use 'native' ou 'custom'. Valor atual: " .. tostring(mode)
        if not warnedInvalidMode then
            warnedInvalidMode = true
            warn(message)
            Logger.log(message)
        end
        StatusBus.setDetail("Partida | Configuracao | modo de autoplay invalido")
        return {
            ok = false,
            nextState = "recovery",
            reason = "invalid_play_mode",
        }
    end

    return {
        ok = true,
        nextState = "state_detect",
    }
end

return MatchPipeline
