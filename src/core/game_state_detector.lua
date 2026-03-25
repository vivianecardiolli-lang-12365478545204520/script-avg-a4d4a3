local Players = game:GetService("Players")
local config = require("core.config")

local GameStateDetector = {}

local function isUiVisible(instance)
    if not instance then
        return false
    end

    if instance:IsA("GuiObject") then
        return instance.Visible ~= false
    end

    if instance:IsA("LayerCollector") then
        return instance.Enabled ~= false
    end

    return true
end

local function getPlayerGui()
    local player = Players.LocalPlayer
    if not player then
        return nil
    end
    return player:FindFirstChild("PlayerGui")
end

local function isTutorialVisible(playerGui)
    if not playerGui then
        return false
    end
    local newTutorial = playerGui:FindFirstChild("NEWTutorial")
    if isUiVisible(newTutorial) then
        return true
    end
    local tutorial = playerGui:FindFirstChild("Tutorial")
    if isUiVisible(tutorial) then
        return true
    end
    return false
end

function GameStateDetector.detect()
    local playerGui = getPlayerGui()
    if not playerGui then
        return {
            location = "unknown",
            tutorialVisible = false,
        }
    end

    local tutorialVisible = isTutorialVisible(playerGui)
    local placeId = game.PlaceId

    local configuredLobbyPlaceId = tonumber(config.automation.lobbyPlaceId)
    local configuredMatchPlaceId = tonumber(config.automation.matchPlaceId)

    local location = "unknown"
    if configuredLobbyPlaceId and placeId == configuredLobbyPlaceId then
        location = "lobby"
    elseif configuredMatchPlaceId and placeId == configuredMatchPlaceId then
        location = "match"
    else
        local map = workspace:FindFirstChild("Map")
        if map ~= nil then
            location = "match"
        end
    end

    return {
        location = location,
        tutorialVisible = tutorialVisible,
    }
end

return GameStateDetector
