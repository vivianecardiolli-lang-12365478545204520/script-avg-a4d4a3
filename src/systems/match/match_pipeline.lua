local Logger = require("core.logger")
local StatusBus = require("core.status_bus")
local StateContext = require("core.state_context")
local AutoPlaySystem = require("systems.match.autoplay_system")
local CustomPlaySystem = require("systems.match.custom_play_system")
local config = require("core.config")

local MatchPipeline = {}
local warnedInvalidMode = false

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

    local mode = tostring((config.automation and config.automation.playMode) or "native")
    local modeLower = string.lower(mode)

    if modeLower == "native" then
        StatusBus.set("Verificando autoplay nativo")
        StatusBus.setDetail("Partida | AutoPlay nativo | verificando estado")
        local autoPlayResult = AutoPlaySystem.run()
        if not autoPlayResult.ok then
            Logger.log("AutoPlay native check failed: " .. tostring(autoPlayResult.reason))
            StatusBus.setDetail("Partida | AutoPlay nativo | falha: " .. tostring(autoPlayResult.reason))
        elseif autoPlayResult.toggled then
            StatusBus.setDetail("Partida | AutoPlay nativo | toggle enviado")
        else
            StatusBus.setDetail("Partida | AutoPlay nativo | ja ativo")
        end
    elseif modeLower == "custom" then
        StatusBus.set("Verificando autoplay custom")
        StatusBus.setDetail("Partida | AutoPlay custom | verificando loop")
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
        StatusBus.setDetail("Partida | Configuracao | playMode invalido: " .. tostring(mode))
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
