local Players = game:GetService("Players")

local config = require("core.config")
local SheetsClient = require("integrations.sheets_client")

local Tracker = {}

local player = Players.LocalPlayer
local HUD = player.PlayerGui:WaitForChild("HUD")

-- MESMA LÓGICA DO SCRIPT ORIGINAL
local function getCurrencies()

    local data = {
        Gold = "0",
        Gems = "0",
        TraitRerolls = "0",
    }

    for _, obj in pairs(HUD:GetDescendants()) do

        if obj:IsA("TextLabel") then

            for _, child in pairs(obj:GetChildren()) do

                if child:IsA("UIGradient") then

                    local name = child.Name

                    if data[name] ~= nil then
                        data[name] = obj.Text
                    end

                end

            end

        end

    end

    return data
end

local function getLevel()

    for _, obj in pairs(HUD:GetDescendants()) do

        if obj:IsA("TextLabel") then

            local lvl = obj.Text:match("Level%s+(%d+)")

            if lvl then
                return lvl
            end

        end

    end

    return "0"
end

local function collectData()
    local currencies = getCurrencies()
    currencies.Level = getLevel()
    return currencies
end

function Tracker.sendNow()
    return SheetsClient.send(collectData())
end

function Tracker.startLoop()
    while true do
        Tracker.sendNow()
        task.wait(config.tracker.intervalMinutes * 60)
    end
end

return Tracker