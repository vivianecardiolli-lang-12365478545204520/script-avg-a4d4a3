local Players = game:GetService("Players")

local GameStateDetector = {}

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
    return hud ~= nil and hud:IsA("GuiObject") and hud.Visible ~= false
end

local function isMatch(playerGui)
    if not playerGui then
        return false
    end
    local waveLabel = playerGui:FindFirstChild("WaveDisplay", true)
    if waveLabel and waveLabel:IsA("GuiObject") and waveLabel.Visible ~= false then
        return true
    end
    local autoplay = playerGui:FindFirstChild("AutoPlay", true)
    if autoplay and autoplay:IsA("GuiObject") and autoplay.Visible ~= false then
        return true
    end
    return false
end

local function isTutorialVisible(playerGui)
    if not playerGui then
        return false
    end
    local newTutorial = playerGui:FindFirstChild("NEWTutorial")
    if newTutorial and newTutorial:IsA("GuiObject") and newTutorial.Visible then
        return true
    end
    local tutorial = playerGui:FindFirstChild("Tutorial")
    if tutorial and tutorial:IsA("GuiObject") and tutorial.Visible then
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
