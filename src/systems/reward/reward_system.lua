local ReplicatedStorage = game:GetService("ReplicatedStorage")

local config = require("core.config")
local Logger = require("core.logger")
local PopupHandler = require("systems.reward.popup_handler")

local RewardSystem = {}

local networking = ReplicatedStorage:WaitForChild("Networking")

local newPlayerRemote = networking:WaitForChild("NewPlayerRewardsEvent")
local pirateRemote = networking:WaitForChild("APiratesWelcomeEvent")
local dailyRemote = networking:WaitForChild("DailyRewardEvent")

local function claimRewards(remote, maxRewards)
    Logger.log("Starting " .. remote.Name)

    for i = 1, maxRewards do
        Logger.log("Claim attempt " .. i)

        remote:FireServer("Claim", i)

        task.wait(0.6)
        PopupHandler.handle(3)
        task.wait(0.3)
    end

    Logger.log("Finished " .. remote.Name)
end

local function claimDaily(typeName, maxRewards)
    Logger.log("Starting DailyReward " .. typeName)

    for i = 1, maxRewards do
        Logger.log("Claim attempt " .. typeName .. " " .. i)

        dailyRemote:FireServer("Claim", { typeName, i })

        task.wait(0.6)
        PopupHandler.handle(3)
        task.wait(0.3)
    end

    Logger.log("Finished DailyReward " .. typeName)
end

function RewardSystem.run()
    claimRewards(newPlayerRemote, config.rewards.NewPlayerRewards)

    task.wait(1)

    claimRewards(pirateRemote, config.rewards.PirateRewards)

    task.wait(1)

    claimDaily("Special", config.rewards.SpecialRewards)

    task.wait(1)

    claimDaily("Winter", config.rewards.WinterRewards)

    Logger.log("RewardSystem finished")
end

return RewardSystem