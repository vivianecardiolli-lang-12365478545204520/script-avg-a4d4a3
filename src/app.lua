local RewardSystem = require("systems.reward.reward_system")
local Tracker = require("systems.tracker.tracker_system")

local App = {}

function App.run()
    RewardSystem.run()
    Tracker.sendNow()
    Tracker.startLoop()
end

return App