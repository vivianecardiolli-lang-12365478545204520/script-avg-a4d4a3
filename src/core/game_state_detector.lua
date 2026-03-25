local Players = game:GetService("Players")

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

local function isLobby(playerGui)
    if not playerGui then
        return false
    end
    local hud = playerGui:FindFirstChild("HUD")
    return isUiVisible(hud)
end

local function isMatch(playerGui)
    if not playerGui then
        return false
    end
    local waveLabel = playerGui:FindFirstChild("WaveDisplay", true)
    if isUiVisible(waveLabel) then
        return true
    end
    local autoplay = playerGui:FindFirstChild("AutoPlay", true)
    if isUiVisible(autoplay) then
        return true
    end
    return false
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
    local lobby = isLobby(playerGui)
    local match = isMatch(playerGui)

    local location = "unknown"
    if lobby then
        location = "lobby"
    elseif match then
        location = "match"
    end

    return {
        location = location,
        tutorialVisible = tutorialVisible,
    }
end

return GameStateDetector
