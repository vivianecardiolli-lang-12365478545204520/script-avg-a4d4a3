local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local StatusBus = require("core.status_bus")

local TutorialSystem = {}

-- Controle por sessao: evita reenviar skip para a mesma parte.
local firedParts = {}
local eventHookInstalled = false

local validParts = {
    PartOne = true,
    PartTwo = true,
    PartThree = true,
}

local resolved = {
    ready = false,
    remote = nil,
    handler = nil,
    dialogueHandler = nil,
    windowHandler = nil,
    highlightHandler = nil,
}

local warned = {}

local function devAlertOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (Tutorial): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function getNativeRequire()
    if type(getrenv) == "function" then
        local env = getrenv()
        if env and type(env.require) == "function" then
            return env.require
        end
    end
    if type(_G) == "table" and type(_G.require) == "function" then
        return _G.require
    end
    return require
end

local function safeRequire(nativeRequire, moduleScript, label)
    if not moduleScript then
        return nil
    end
    local ok, result = pcall(nativeRequire, moduleScript)
    if not ok then
        devAlertOnce("require_" .. tostring(label), "Falha ao require de " .. tostring(label) .. ": " .. tostring(result))
        return nil
    end
    return result
end

local function resolveDependencies()
    if resolved.ready then
        return true
    end

    local nativeRequire = getNativeRequire()
    local modules = StarterPlayer:FindFirstChild("Modules")
    local interface = modules and modules:FindFirstChild("Interface")
    local loader = interface and interface:FindFirstChild("Loader")
    local gameplay = modules and modules:FindFirstChild("Gameplay")

    if not loader then
        devAlertOnce("loader_missing", "StarterPlayer.Modules.Interface.Loader nao encontrado")
        return false
    end
    if not gameplay then
        devAlertOnce("gameplay_missing", "StarterPlayer.Modules.Gameplay nao encontrado")
        return false
    end

    local dialogueHandlerModule = loader:FindFirstChild("DialogueHandler")
        or (
            loader:FindFirstChild("Misc")
            and loader.Misc:FindFirstChild("PopupDialogue")
            and loader.Misc.PopupDialogue:FindFirstChild("DialogueHandler")
        )

    local windowHandlerModule = loader:FindFirstChild("WindowHandler")

    local highlightHandlerModule = (
        loader:FindFirstChild("Misc")
        and loader.Misc:FindFirstChild("ScreenHighlightHandler")
    ) or loader:FindFirstChild("ScreenHighlightHandler")

    local tutorialModule = gameplay:FindFirstChild("ClientTutorialHandler")
        or (
            gameplay:FindFirstChild("Tutorial")
            and gameplay.Tutorial:FindFirstChild("ClientTutorialHandler")
        )

    local networking = ReplicatedStorage:FindFirstChild("Networking")
    local listeners = networking and networking:FindFirstChild("ClientListeners")
    local remote = listeners and listeners:FindFirstChild("NEWTutorialEvent")

    if not tutorialModule then
        devAlertOnce("tutorial_module_missing", "ClientTutorialHandler nao encontrado")
        return false
    end
    if not remote or not remote:IsA("RemoteEvent") then
        devAlertOnce("tutorial_remote_missing", "Networking.ClientListeners.NEWTutorialEvent nao encontrado")
        return false
    end

    local tutorialHandler = safeRequire(nativeRequire, tutorialModule, "ClientTutorialHandler")
    if type(tutorialHandler) ~= "table" then
        devAlertOnce("tutorial_handler_invalid", "ClientTutorialHandler nao retornou tabela")
        return false
    end

    local windowHandler = safeRequire(nativeRequire, windowHandlerModule, "WindowHandler")
    if type(windowHandler) ~= "table" then
        devAlertOnce("window_handler_invalid", "WindowHandler indisponivel")
        return false
    end

    local dialogueHandler = safeRequire(nativeRequire, dialogueHandlerModule, "DialogueHandler")
    local highlightHandler = safeRequire(nativeRequire, highlightHandlerModule, "ScreenHighlightHandler")

    resolved.remote = remote
    resolved.handler = tutorialHandler
    resolved.dialogueHandler = dialogueHandler
    resolved.windowHandler = windowHandler
    resolved.highlightHandler = highlightHandler
    resolved.ready = true

    return true
end

local function cleanupUI(part)
    if resolved.dialogueHandler then
        local ok, err = pcall(function()
            resolved.dialogueHandler:CancelDialogue()
        end)
        if not ok then
            devAlertOnce("cleanup_dialogue_" .. tostring(part), "Falha em DialogueHandler:CancelDialogue para " .. tostring(part) .. ": " .. tostring(err))
        end
    end

    if resolved.highlightHandler then
        local ok, err = pcall(function()
            resolved.highlightHandler:RemoveHighlight()
        end)
        if not ok then
            devAlertOnce("cleanup_highlight_" .. tostring(part), "Falha em ScreenHighlightHandler:RemoveHighlight para " .. tostring(part) .. ": " .. tostring(err))
        end
    end

    if part == "PartTwo" then
        local okHud, errHud = pcall(function()
            resolved.windowHandler:SetHUDVisible(true)
        end)
        if not okHud then
            devAlertOnce("cleanup_hud_" .. tostring(part), "Falha em WindowHandler:SetHUDVisible(true): " .. tostring(errHud))
        end

        local okCam, errCam = pcall(function()
            resolved.windowHandler:ResetCamera()
        end)
        if not okCam then
            devAlertOnce("cleanup_camera_" .. tostring(part), "Falha em WindowHandler:ResetCamera(): " .. tostring(errCam))
        end
    end
end

local function forceSkip(part)
    if not validParts[part] then
        devAlertOnce("invalid_part_skip", "Tentativa de skip com parte invalida: " .. tostring(part))
        return false
    end

    if firedParts[part] then
        Logger.log("[Tutorial] Skip ja executado anteriormente: " .. tostring(part))
        return false
    end

    firedParts[part] = true
    StatusBus.set("Pulando tutorial (" .. tostring(part) .. ")")

    Logger.log("[Tutorial] Tutorial detectado: " .. tostring(part))
    cleanupUI(part)

    local ok, err = pcall(function()
        resolved.remote:FireServer(part, "Skip")
    end)
    if not ok then
        devAlertOnce("skip_fire_" .. tostring(part), "Falha ao enviar skip para " .. tostring(part) .. ": " .. tostring(err))
        return false
    end

    Logger.log("[Kaitun] Skip enviado para " .. tostring(part))
    return true
end

local function getCheckFunction()
    local checkFunction = resolved.handler.IsPartActive or resolved.handler.IsActive
    if type(checkFunction) ~= "function" then
        devAlertOnce("check_function_missing", "Nenhuma funcao de checagem encontrada (IsPartActive/IsActive)")
        return nil
    end
    return checkFunction
end

local function initialCheck()
    local checkFunction = getCheckFunction()
    if not checkFunction then
        return false
    end

    local parts = { "PartOne", "PartTwo", "PartThree" }
    for _, partName in ipairs(parts) do
        local ok, isActive = pcall(checkFunction, partName)
        if not ok then
            devAlertOnce("initial_check_" .. tostring(partName), "Falha ao checar parte " .. tostring(partName) .. ": " .. tostring(isActive))
        elseif isActive then
            Logger.log("[Tutorial] Parte ativa detectada: " .. tostring(partName))
            task.wait(0.3)
            return forceSkip(partName)
        end
    end

    return false
end

local function installEventHook()
    if eventHookInstalled then
        return
    end

    resolved.remote.OnClientEvent:Connect(function(...)
        local args = { ... }
        local part = args[1]
        local status = args[2]

        Logger.log(string.format(
            "[Tutorial DEBUG] Pacote recebido do servidor: part=%s status=%s argc=%d",
            tostring(part),
            tostring(status),
            #args
        ))

        if type(part) == "string" and validParts[part] then
            Logger.log("[Tutorial DEBUG] Tentando pular: " .. tostring(part) .. " | Status: " .. tostring(status))
            task.wait(0.3)
            forceSkip(part)
        else
            Logger.log("[Tutorial DEBUG] Evento ignorado: parte invalida ou nao suportada (" .. tostring(part) .. ")")
        end
    end)

    eventHookInstalled = true
    Logger.log("[Tutorial] Event hook instalado para NEWTutorialEvent.")
end

function TutorialSystem.run()
    local ok = resolveDependencies()
    if not ok then
        return {
            ok = false,
            handled = false,
            status = 0,
            reason = "tutorial_dependencies_unavailable",
        }
    end

    -- Mesmo comportamento do script validado: hook sempre ativo, mesmo com initialCheck.
    installEventHook()

    local handled = initialCheck()
    if not handled then
        Logger.log("[Tutorial] Monitorando tutorial via event hook.")
    else
        Logger.log("[Tutorial] initialCheck executou skip com sucesso.")
    end

    return {
        ok = true,
        handled = handled,
        status = handled and 1 or 0,
    }
end

return TutorialSystem
