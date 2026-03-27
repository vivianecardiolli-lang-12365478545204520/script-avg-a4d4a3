local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require("core.logger")
local config = require("core.config")

local MatchCreateSystem = {}
local rng = Random.new()

local function devAlert(message)
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (MatchCreate): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function resolveRootPart()
    local player = Players.LocalPlayer
    if not player then
        return nil, "Players.LocalPlayer indisponivel"
    end

    local character = player.Character
    if not character then
        character = player.CharacterAdded:Wait()
    end
    if not character then
        return nil, "Character indisponivel"
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        rootPart = character:WaitForChild("HumanoidRootPart", 5)
    end
    if not rootPart then
        return nil, "HumanoidRootPart nao encontrado"
    end

    return rootPart, nil
end

local function resolveLobbyRemotes()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    if not networking then
        return nil, nil, "Networking nao encontrado"
    end

    local lobbyEvent = networking:FindFirstChild("LobbyEvent")
    if not lobbyEvent then
        return nil, nil, "Remote Networking.LobbyEvent nao encontrado"
    end

    local listeners = networking:FindFirstChild("ClientListeners")
    local pityEvent = listeners and listeners:FindFirstChild("ItemPityEvent")
    if not pityEvent then
        return nil, nil, "Remote Networking.ClientListeners.ItemPityEvent nao encontrado"
    end

    return lobbyEvent, pityEvent, nil
end

local function resolvePortalPart(chamber)
    if not chamber then
        return nil
    end

    local exterior = chamber:FindFirstChild("Chamber Exterior")
    local model = exterior and exterior:FindFirstChild("Model")
    if model then
        local children = model:GetChildren()
        local preferred = children[5]
        if preferred and preferred:IsA("BasePart") then
            return preferred
        end

        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                return inst
            end
        end
    end

    return nil
end

local function resolveChambers()
    local mainLobby = Workspace:FindFirstChild("MainLobby")
    local gamemodes = mainLobby and mainLobby:FindFirstChild("Gamemodes")
    local play = gamemodes and gamemodes:FindFirstChild("Play")
    local chambers = play and play:FindFirstChild("Chambers")
    if not chambers then
        return nil, "workspace.MainLobby.Gamemodes.Play.Chambers nao encontrado"
    end

    local list = chambers:GetChildren()
    if #list == 0 then
        return nil, "Nenhuma camara encontrada em Chambers"
    end

    return list, nil
end

function MatchCreateSystem.run()
    local lobbyPlaceId = tonumber(config.automation and config.automation.lobbyPlaceId)
    if lobbyPlaceId and game.PlaceId ~= lobbyPlaceId then
        devAlert(string.format(
            "Tentativa de criar partida fora do lobby (placeId atual=%s lobby=%s)",
            tostring(game.PlaceId),
            tostring(lobbyPlaceId)
        ))
        return { ok = false, reason = "not_in_lobby" }
    end

    local rootPart, rootErr = resolveRootPart()
    if rootErr then
        devAlert(rootErr)
        return { ok = false, reason = "root_part_missing" }
    end

    local lobbyEvent, pityEvent, remotesErr = resolveLobbyRemotes()
    if remotesErr then
        devAlert(remotesErr)
        return { ok = false, reason = "lobby_remotes_missing" }
    end

    local chambers, chambersErr = resolveChambers()
    if chambersErr then
        devAlert(chambersErr)
        return { ok = false, reason = "chambers_missing" }
    end

    local chamber = chambers[rng:NextInteger(1, #chambers)]
    local portalPart = resolvePortalPart(chamber)
    if not portalPart then
        devAlert("Nao foi possivel resolver parte fisica do portal para '" .. tostring(chamber.Name) .. "'")
        return { ok = false, reason = "portal_part_missing" }
    end

    rootPart.CFrame = portalPart.CFrame * CFrame.new(0, 1, 0)
    Logger.log("MatchCreate teleportado para chamber: " .. tostring(chamber.Name))

    task.wait(rng:NextNumber(1.5, 2.5))
    pityEvent:FireServer()
    task.wait(rng:NextNumber(0.6, 1.0))

    local matchSettings = {
        Difficulty = tostring((config.automation and config.automation.matchDifficulty) or "Normal"),
        Act = tostring((config.automation and config.automation.matchAct) or "Act1"),
        StageType = tostring((config.automation and config.automation.matchStageType) or "Story"),
        Stage = tostring((config.automation and config.automation.matchStage) or "Stage1"),
        FriendsOnly = not not ((config.automation and config.automation.matchFriendsOnly) or false),
    }

    Logger.log(string.format(
        "MatchCreate AddMatch stage=%s difficulty=%s act=%s stageType=%s friendsOnly=%s",
        tostring(matchSettings.Stage),
        tostring(matchSettings.Difficulty),
        tostring(matchSettings.Act),
        tostring(matchSettings.StageType),
        tostring(matchSettings.FriendsOnly)
    ))
    lobbyEvent:FireServer("AddMatch", matchSettings)

    task.wait(rng:NextNumber(2.1, 2.9))
    lobbyEvent:FireServer("StartMatch")
    Logger.log("MatchCreate StartMatch enviado")

    return {
        ok = true,
        chamber = chamber.Name,
        stage = matchSettings.Stage,
    }
end

return MatchCreateSystem
