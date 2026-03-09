local RewardSystem = require("systems.reward.reward_system")
local Tracker = require("systems.tracker.tracker_system")

local App = {}

function App.run()
    task.spawn(function()
        Tracker.startLoop()
    end)

    task.spawn(function()
        RewardSystem.run()
        Tracker.sendNow()
    end)
end

return App
