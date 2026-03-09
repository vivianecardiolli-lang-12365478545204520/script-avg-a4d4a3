local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local config = require("core.config")
local Logger = require("core.logger")
local Numbers = require("utils.numbers")

local SheetsClient = {}

local player = Players.LocalPlayer

function SheetsClient.send(data)
    local payload = {
        player = player.Name,
        displayName = player.DisplayName,

        coins = Numbers.normalizeNumber(data.Gold),
        gems = Numbers.normalizeNumber(data.Gems),
        traits = Numbers.normalizeNumber(data.TraitRerolls),

        level = data.Level,

        token = config.tracker.secretToken,
    }

    local tries = 0

    while tries < config.tracker.retry.maxRetries do

        local success, err = pcall(function()

            request({
                Url = config.tracker.webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = HttpService:JSONEncode(payload),
            })

        end)

        if success then
            Logger.log("Dados enviados: " .. payload.player)
            return true
        else
            tries = tries + 1
            Logger.log("Falha ao enviar, tentativa " .. tries .. " | " .. tostring(err))
            task.wait(config.tracker.retry.retryDelaySeconds)
        end

    end

    Logger.log("Falha final ao enviar dados")

    return false
end

return SheetsClient