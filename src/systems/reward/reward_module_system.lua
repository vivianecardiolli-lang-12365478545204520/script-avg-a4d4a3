local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Logger = require("core.logger")
local config = require("core.config")

local RewardModuleSystem = {}

local warned = {}
local runtime = {
    hooksInstalled = false,
    uiSuppressorInstalled = false,
    claimedLevel = {},
    claimedCollection = {},
    passData = {
        PlayerLevel = 0,
        ClaimedTiers = { Normal = {}, Premium = {} },
        PremiumUnlocked = false,
        DadosRecebidos = false,
    },
}

local function devAlertOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    local full = "[KAITUN] ATENCAO DESENVOLVEDOR (RewardModule): " .. tostring(message)
    warn(full)
    Logger.log(full)
end

local function rewardLog(message)
    Logger.log("[RewardModule] " .. tostring(message))
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
    return nil
end

local function safeNativeRequire(nativeRequire, moduleScript, label)
    local ok, result = pcall(nativeRequire, moduleScript)
    if not ok then
        devAlertOnce("require_" .. tostring(label), "Falha ao require de " .. tostring(label) .. ": " .. tostring(result))
        return nil
    end
    return result
end

local function randomFloat(minValue, maxValue)
    if maxValue <= minValue then
        return minValue
    end
    return minValue + (math.random() * (maxValue - minValue))
end

local function waitRandom(minValue, maxValue)
    task.wait(randomFloat(minValue, maxValue))
end

local function shuffleArray(values)
    for i = #values, 2, -1 do
        local j = math.random(i)
        values[i], values[j] = values[j], values[i]
    end
    return values
end

local function getSettings()
    local rewards = config.rewards or {}
    return {
        enabledNewPlayer = rewards.EnableNewPlayerRewards ~= false,
        enabledPirate = rewards.EnablePirateRewards ~= false,
        enabledDailySpecial = rewards.EnableSpecialRewards ~= false,
        enabledDailyWinter = rewards.EnableWinterRewards ~= false,
        enabledLevelMilestones = rewards.EnableLevelMilestones ~= false,
        enabledCollectionMilestones = rewards.EnableCollectionMilestones ~= false,
        enabledBattlePass = rewards.EnableBattlePass ~= false,
        enabledQuests = rewards.EnableQuests ~= false,
        enableUiSuppressor = rewards.ModuleEnableUiSuppressor ~= false,
        syncWaitSeconds = tonumber(rewards.ModuleSyncWaitSeconds or 12) or 12,
        delayBetweenTypesMinSeconds = tonumber(rewards.ModuleDelayBetweenTypesMinSeconds or 2.0) or 2.0,
        delayBetweenTypesMaxSeconds = tonumber(rewards.ModuleDelayBetweenTypesMaxSeconds or 5.0) or 5.0,
        delayBetweenClaimsMinSeconds = tonumber(rewards.ModuleDelayBetweenClaimsMinSeconds or 2.5) or 2.5,
        delayBetweenClaimsMaxSeconds = tonumber(rewards.ModuleDelayBetweenClaimsMaxSeconds or 5.5) or 5.5,
        battlePassMaxLevel = tonumber(rewards.ModuleBattlePassMaxLevel or 50) or 50,
    }
end

local function normalizeSettings(settings)
    if settings.syncWaitSeconds < 0 then
        settings.syncWaitSeconds = 0
    end
    if settings.delayBetweenTypesMinSeconds < 0 then
        settings.delayBetweenTypesMinSeconds = 0
    end
    if settings.delayBetweenTypesMaxSeconds < settings.delayBetweenTypesMinSeconds then
        settings.delayBetweenTypesMaxSeconds = settings.delayBetweenTypesMinSeconds
    end
    if settings.delayBetweenClaimsMinSeconds < 0 then
        settings.delayBetweenClaimsMinSeconds = 0
    end
    if settings.delayBetweenClaimsMaxSeconds < settings.delayBetweenClaimsMinSeconds then
        settings.delayBetweenClaimsMaxSeconds = settings.delayBetweenClaimsMinSeconds
    end
    if settings.battlePassMaxLevel < 1 then
        settings.battlePassMaxLevel = 1
    end
end

local function getNetworking()
    local networking = ReplicatedStorage:FindFirstChild("Networking")
    if not networking then
        devAlertOnce("networking_missing", "ReplicatedStorage.Networking nao encontrado")
        return nil
    end
    return networking
end

local function installUiSuppressorIfEnabled(settings)
    if not settings.enableUiSuppressor or runtime.uiSuppressorInstalled then
        return
    end

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        devAlertOnce("ui_suppressor_require", "Require nativo indisponivel para instalar supressor de RewardsScreen")
        return
    end

    local modules = StarterPlayer:FindFirstChild("Modules")
    local interface = modules and modules:FindFirstChild("Interface")
    local loader = interface and interface:FindFirstChild("Loader")
    local misc = loader and loader:FindFirstChild("Misc")
    local rewardHandlerModule = misc and misc:FindFirstChild("RewardsScreenHandler")
    if not rewardHandlerModule then
        devAlertOnce("ui_suppressor_module", "StarterPlayer.Modules.Interface.Loader.Misc.RewardsScreenHandler nao encontrado")
        return
    end

    local rewardHandler = safeNativeRequire(nativeRequire, rewardHandlerModule, "RewardsScreenHandler")
    if type(rewardHandler) ~= "table" then
        devAlertOnce("ui_suppressor_handler", "RewardsScreenHandler nao retornou tabela")
        return
    end

    rewardHandler.ShowRewardScreen = function(self, rewardsData, callback)
        rewardLog("[UI-Suppressor] Bloqueada tentativa de exibir RewardsScreen.")
        if callback then
            task.spawn(callback)
        end
        return nil
    end

    runtime.uiSuppressorInstalled = true
    rewardLog("Supressor de RewardsScreen instalado.")
end

local function installHooksIfNeeded(networking)
    if runtime.hooksInstalled then
        return
    end

    local milestones = networking:FindFirstChild("Milestones")
    local requestMilestonesData = milestones and milestones:FindFirstChild("RequestMilestonesData")
    local units = networking:FindFirstChild("Units")
    local collectionMilestonesEvent = units and units:FindFirstChild("CollectionMilestonesEvent")
    local battleEvent = networking:FindFirstChild("BattlepassEvent")

    if not requestMilestonesData then
        devAlertOnce("hook_level_missing", "Remote Networking.Milestones.RequestMilestonesData nao encontrado")
    else
        requestMilestonesData.OnClientEvent:Connect(function(lvl, claimed)
            runtime.claimedLevel = claimed or {}
        end)
    end

    if not collectionMilestonesEvent then
        devAlertOnce("hook_collection_missing", "Remote Networking.Units.CollectionMilestonesEvent nao encontrado")
    else
        collectionMilestonesEvent.OnClientEvent:Connect(function(eventType, data)
            if eventType == "Update" then
                runtime.claimedCollection = data or {}
            end
        end)
    end

    if not battleEvent then
        devAlertOnce("hook_battlepass_missing", "Remote Networking.BattlepassEvent nao encontrado")
    else
        battleEvent.OnClientEvent:Connect(function(data)
            if data and type(data) == "table" then
                runtime.passData.PlayerLevel = data[1] or 0
                runtime.passData.ClaimedTiers = data[3] or { Normal = {}, Premium = {} }
                runtime.passData.PremiumUnlocked = data[4] or false
                runtime.passData.DadosRecebidos = true
            end
        end)
    end

    runtime.hooksInstalled = true
    rewardLog("Hooks de sincronizacao de rewards instalados.")
end

local function fireSyncRequests(networking)
    local dailyTrigger = networking:FindFirstChild("DailyRewardEvent")
    if dailyTrigger then
        pcall(function()
            dailyTrigger:FireServer("Request")
        end)
    end

    local milestones = networking:FindFirstChild("Milestones")
    local requestMilestonesData = milestones and milestones:FindFirstChild("RequestMilestonesData")
    if requestMilestonesData then
        pcall(function()
            requestMilestonesData:FireServer()
        end)
    end

    local units = networking:FindFirstChild("Units")
    local collectionMilestonesEvent = units and units:FindFirstChild("CollectionMilestonesEvent")
    if collectionMilestonesEvent then
        pcall(function()
            collectionMilestonesEvent:FireServer("RequestData")
        end)
    end

    local battleEvent = networking:FindFirstChild("BattlepassEvent")
    if battleEvent then
        pcall(function()
            battleEvent:FireServer("RequestData")
        end)
    end

    local quests = networking:FindFirstChild("Quests")
    local requestQuests = quests and quests:FindFirstChild("RequestQuests")
    if requestQuests then
        pcall(function()
            requestQuests:FireServer()
        end)
    end
end

local function processDaily(settings, context)
    if not settings.enabledDailySpecial and not settings.enabledDailyWinter then
        return
    end

    local dailyEvent = context.networking:FindFirstChild("DailyRewardEvent")
    if not dailyEvent then
        devAlertOnce("daily_remote_missing", "Remote Networking.DailyRewardEvent nao encontrado")
        return
    end

    local dailyData = safeNativeRequire(context.nativeRequire, context.modules.dailyRewardsData, "DailyRewardsData")
    local dailyHandler = safeNativeRequire(context.nativeRequire, context.modules.dailyRewardsDataHandler, "DailyRewardsDataHandler")
    if not dailyData or not dailyHandler then
        return
    end

    if not dailyHandler.DataLoaded then
        rewardLog("[Daily] DataLoaded=false, pulando ciclo.")
        return
    end

    local queue = {}
    local rewardTypes = dailyData.GetRewardTypes()
    for typeName in pairs(rewardTypes or {}) do
        if (typeName == "Special" and settings.enabledDailySpecial) or (typeName == "Winter" and settings.enabledDailyWinter) then
            local rewards = dailyData.GetRewardsOfType(typeName) or {}
            for day in pairs(rewards) do
                local unlocked = dailyHandler.IsUnlocked(typeName, day)
                local claimed = dailyHandler.IsClaimed(typeName, day)
                if unlocked and not claimed then
                    table.insert(queue, { rewardType = typeName, day = day })
                end
            end
        end
    end

    if #queue <= 0 then
        rewardLog("[Daily] Nenhum item disponivel.")
        return
    end

    rewardLog("[Daily] " .. tostring(#queue) .. " itens encontrados.")
    for _, item in ipairs(shuffleArray(queue)) do
        waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
        local ok, err = pcall(function()
            dailyEvent:FireServer("Claim", { item.rewardType, item.day })
        end)
        if not ok then
            devAlertOnce("daily_claim_" .. tostring(item.rewardType) .. "_" .. tostring(item.day), "Falha ao resgatar Daily " .. tostring(item.rewardType) .. " dia " .. tostring(item.day) .. ": " .. tostring(err))
        else
            rewardLog("Daily claim enviado: " .. tostring(item.rewardType) .. " #" .. tostring(item.day))
        end
    end
end

local function processNewPlayer(settings, context)
    if not settings.enabledNewPlayer then
        return
    end

    local remote = context.networking:FindFirstChild("NewPlayerRewardsEvent")
    if not remote then
        devAlertOnce("new_player_remote_missing", "Remote Networking.NewPlayerRewardsEvent nao encontrado")
        return
    end

    local handler = safeNativeRequire(context.nativeRequire, context.modules.newPlayerDataHandler, "NewPlayerDataHandler")
    if not handler or type(handler.GetData) ~= "function" then
        devAlertOnce("new_player_handler_invalid", "NewPlayerDataHandler.GetData indisponivel")
        return
    end

    local data = handler.GetData()
    if not data or not data.Streak then
        return
    end

    local queue = {}
    for i = 1, data.Streak do
        if not table.find(data.ClaimedRewards or {}, i) then
            table.insert(queue, i)
        end
    end

    if #queue <= 0 then
        rewardLog("[NewPlayer] Nenhum item disponivel.")
        return
    end

    rewardLog("[NewPlayer] " .. tostring(#queue) .. " itens encontrados.")
    for _, day in ipairs(shuffleArray(queue)) do
        waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
        local ok, err = pcall(function()
            remote:FireServer("Claim", day)
        end)
        if not ok then
            devAlertOnce("new_player_claim_" .. tostring(day), "Falha ao resgatar NewPlayer dia " .. tostring(day) .. ": " .. tostring(err))
        else
            rewardLog("NewPlayer claim enviado: dia " .. tostring(day))
        end
    end
end

local function processPirates(settings, context)
    if not settings.enabledPirate then
        return
    end

    local remote = context.networking:FindFirstChild("APiratesWelcomeEvent")
    if not remote then
        devAlertOnce("pirates_remote_missing", "Remote Networking.APiratesWelcomeEvent nao encontrado")
        return
    end

    local handler = safeNativeRequire(context.nativeRequire, context.modules.piratesDataHandler, "APiratesWelcomeDataHandler")
    if not handler or type(handler.GetData) ~= "function" then
        devAlertOnce("pirates_handler_invalid", "APiratesWelcomeDataHandler.GetData indisponivel")
        return
    end

    local data = handler.GetData()
    if not data or not data.Streak then
        return
    end

    local queue = {}
    for i = 1, data.Streak do
        if not table.find(data.ClaimedRewards or {}, i) then
            table.insert(queue, i)
        end
    end

    if #queue <= 0 then
        rewardLog("[Pirates] Nenhum item disponivel.")
        return
    end

    rewardLog("[Pirates] " .. tostring(#queue) .. " itens encontrados.")
    for _, day in ipairs(shuffleArray(queue)) do
        waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
        local ok, err = pcall(function()
            remote:FireServer("Claim", day)
        end)
        if not ok then
            devAlertOnce("pirates_claim_" .. tostring(day), "Falha ao resgatar Pirates dia " .. tostring(day) .. ": " .. tostring(err))
        else
            rewardLog("Pirates claim enviado: dia " .. tostring(day))
        end
    end
end

local function processMilestones(settings, context)
    if not settings.enabledLevelMilestones and not settings.enabledCollectionMilestones then
        return
    end

    local milestonesFolder = context.networking:FindFirstChild("Milestones")
    local levelRemote = milestonesFolder and milestonesFolder:FindFirstChild("MilestonesEvent")
    local units = context.networking:FindFirstChild("Units")
    local collectionRemote = units and units:FindFirstChild("CollectionMilestonesEvent")

    if settings.enabledLevelMilestones and not levelRemote then
        devAlertOnce("milestones_level_remote_missing", "Remote Networking.Milestones.MilestonesEvent nao encontrado")
    end
    if settings.enabledCollectionMilestones and not collectionRemote then
        devAlertOnce("milestones_collection_remote_missing", "Remote Networking.Units.CollectionMilestonesEvent nao encontrado")
    end

    local queue = {}

    if settings.enabledLevelMilestones and levelRemote then
        local playerLevel = tonumber((Players.LocalPlayer and Players.LocalPlayer:GetAttribute("Level")) or 0) or 0
        for level = 5, 150, 5 do
            if playerLevel >= level and not runtime.claimedLevel[tostring(level)] then
                table.insert(queue, {
                    rewardType = "Level",
                    rewardId = level,
                    remote = levelRemote,
                    args = { "Claim", level },
                })
            end
        end
    end

    if settings.enabledCollectionMilestones and collectionRemote then
        local collectionData = safeNativeRequire(context.nativeRequire, context.modules.collectionMilestonesData, "CollectionMilestonesData")
        local collectionHandler = safeNativeRequire(context.nativeRequire, context.modules.collectionHandler, "CollectionHandler")
        if collectionData and collectionHandler and type(collectionData.GetAllMilestones) == "function" and type(collectionHandler.GetPlayerUnitCollectionByRarity) == "function" then
            for milestoneName, milestoneConfig in pairs(collectionData.GetAllMilestones() or {}) do
                local rarity = string.split(tostring(milestoneName), " ")[1]
                local owned = collectionHandler.GetPlayerUnitCollectionByRarity(rarity)
                local required = tonumber(milestoneConfig and milestoneConfig.CollectionAmount) or 0
                if owned >= required and not runtime.claimedCollection[milestoneName] then
                    table.insert(queue, {
                        rewardType = "Collection",
                        rewardId = milestoneName,
                        remote = collectionRemote,
                        args = { "Claim", milestoneName },
                    })
                end
            end
        end
    end

    if #queue <= 0 then
        rewardLog("[Milestones] Nenhum item disponivel.")
        return
    end

    rewardLog("[Milestones] " .. tostring(#queue) .. " itens encontrados.")
    local unpackFn = table.unpack or unpack
    for _, item in ipairs(shuffleArray(queue)) do
        waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
        local ok, err = pcall(function()
            item.remote:FireServer(unpackFn(item.args))
        end)
        if not ok then
            devAlertOnce(
                "milestones_claim_" .. tostring(item.rewardType) .. "_" .. tostring(item.rewardId),
                "Falha ao resgatar milestone " .. tostring(item.rewardType) .. " -> " .. tostring(item.rewardId) .. ": " .. tostring(err)
            )
        else
            rewardLog("Milestone claim enviado: " .. tostring(item.rewardType) .. " -> " .. tostring(item.rewardId))
        end
    end
end

local function processBattlePass(settings, context)
    if not settings.enabledBattlePass then
        return
    end

    local battleEvent = context.networking:FindFirstChild("BattlepassEvent")
    if not battleEvent then
        devAlertOnce("battlepass_remote_missing", "Remote Networking.BattlepassEvent nao encontrado")
        return
    end

    if not runtime.passData.DadosRecebidos then
        rewardLog("[BattlePass] Dados ainda nao recebidos.")
        return
    end

    local shouldClaim = false
    local claimedNormal = runtime.passData.ClaimedTiers.Normal or {}
    local claimedPremium = runtime.passData.ClaimedTiers.Premium or {}
    for level = 1, runtime.passData.PlayerLevel do
        if level > settings.battlePassMaxLevel then
            break
        end

        if not table.find(claimedNormal, level) then
            shouldClaim = true
            break
        end

        if runtime.passData.PremiumUnlocked and not table.find(claimedPremium, level) then
            shouldClaim = true
            break
        end
    end

    if not shouldClaim then
        rewardLog("[BattlePass] Nenhum tier pendente.")
        return
    end

    waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
    local ok, err = pcall(function()
        battleEvent:FireServer("ClaimAll")
    end)
    if not ok then
        devAlertOnce("battlepass_claimall", "Falha no BattlepassEvent:FireServer(ClaimAll): " .. tostring(err))
        return
    end
    rewardLog("[BattlePass] ClaimAll enviado.")
end

local function processQuests(settings, context)
    if not settings.enabledQuests then
        return
    end

    local questDataHandler = safeNativeRequire(context.nativeRequire, context.modules.questDataHandler, "QuestDataHandler")
    if not questDataHandler then
        return
    end

    local cache = questDataHandler.Cache
    if type(cache) ~= "table" or next(cache) == nil then
        rewardLog("[Quests] Cache vazio.")
        return
    end

    local questsReady = 0
    for _, questData in pairs(cache) do
        if type(questData) == "table" and questData.Completed and not questData.Claimed then
            questsReady = questsReady + 1
        end
    end

    if questsReady <= 0 then
        rewardLog("[Quests] Nenhuma quest pronta para claim.")
        return
    end

    local quests = context.networking:FindFirstChild("Quests")
    local claimQuest = quests and quests:FindFirstChild("ClaimQuest")
    if not claimQuest then
        devAlertOnce("quests_claim_remote_missing", "Remote Networking.Quests.ClaimQuest nao encontrado")
        return
    end

    waitRandom(settings.delayBetweenClaimsMinSeconds, settings.delayBetweenClaimsMaxSeconds)
    local ok, err = pcall(function()
        claimQuest:FireServer("ClaimAll")
    end)
    if not ok then
        devAlertOnce("quests_claimall", "Falha no Quests.ClaimQuest:FireServer(ClaimAll): " .. tostring(err))
        return
    end
    rewardLog("[Quests] ClaimAll enviado para " .. tostring(questsReady) .. " quests prontas.")
end

local function buildModulePaths()
    local spModules = StarterPlayer:FindFirstChild("Modules")
    local gameplay = spModules and spModules:FindFirstChild("Gameplay")
    local interface = spModules and spModules:FindFirstChild("Interface")
    local loader = interface and interface:FindFirstChild("Loader")
    local windows = loader and loader:FindFirstChild("Windows")
    local quests = windows and windows:FindFirstChild("Quests")
    local questHandler = quests and quests:FindFirstChild("QuestHandler")
    local unitsWindow = windows and windows:FindFirstChild("Units")
    local rpModules = ReplicatedStorage:FindFirstChild("Modules")
    local rpData = rpModules and rpModules:FindFirstChild("Data")

    local dailyRewards = gameplay and gameplay:FindFirstChild("DailyRewards")
    local newPlayerFolder = dailyRewards and dailyRewards:FindFirstChild("NewPlayer")
    local piratesFolder = dailyRewards and dailyRewards:FindFirstChild("APiratesWelcome")

    return {
        dailyRewardsData = rpData and rpData:FindFirstChild("DailyRewardsData"),
        collectionMilestonesData = rpData and rpData:FindFirstChild("CollectionMilestonesData"),
        dailyRewardsDataHandler = dailyRewards and dailyRewards:FindFirstChild("DailyRewardsDataHandler"),
        newPlayerDataHandler = newPlayerFolder and newPlayerFolder:FindFirstChild("NewPlayerDataHandler"),
        piratesDataHandler = piratesFolder and piratesFolder:FindFirstChild("APiratesWelcomeDataHandler"),
        collectionHandler = unitsWindow and unitsWindow:FindFirstChild("CollectionHandler"),
        questDataHandler = questHandler and questHandler:FindFirstChild("QuestDataHandler"),
    }
end

local function validateCriticalModules(modules)
    if not modules.dailyRewardsData then
        devAlertOnce("module_daily_data_missing", "ReplicatedStorage.Modules.Data.DailyRewardsData nao encontrado")
    end
    if not modules.dailyRewardsDataHandler then
        devAlertOnce("module_daily_handler_missing", "StarterPlayer.Modules.Gameplay.DailyRewards.DailyRewardsDataHandler nao encontrado")
    end
    if not modules.newPlayerDataHandler then
        devAlertOnce("module_new_player_handler_missing", "StarterPlayer.Modules.Gameplay.DailyRewards.NewPlayer.NewPlayerDataHandler nao encontrado")
    end
    if not modules.piratesDataHandler then
        devAlertOnce("module_pirates_handler_missing", "StarterPlayer.Modules.Gameplay.DailyRewards.APiratesWelcome.APiratesWelcomeDataHandler nao encontrado")
    end
    if not modules.collectionMilestonesData then
        devAlertOnce("module_collection_data_missing", "ReplicatedStorage.Modules.Data.CollectionMilestonesData nao encontrado")
    end
    if not modules.collectionHandler then
        devAlertOnce("module_collection_handler_missing", "StarterPlayer.Modules.Interface.Loader.Windows.Units.CollectionHandler nao encontrado")
    end
    if not modules.questDataHandler then
        devAlertOnce("module_quest_handler_missing", "StarterPlayer.Modules.Interface.Loader.Windows.Quests.QuestHandler.QuestDataHandler nao encontrado")
    end
end

function RewardModuleSystem.run()
    local settings = getSettings()
    normalizeSettings(settings)

    local networking = getNetworking()
    if not networking then
        return
    end

    installUiSuppressorIfEnabled(settings)
    installHooksIfNeeded(networking)

    local nativeRequire = getNativeRequire()
    if type(nativeRequire) ~= "function" then
        devAlertOnce("native_require_missing", "Require nativo indisponivel para reward module mode")
        return
    end

    local modules = buildModulePaths()
    validateCriticalModules(modules)

    rewardLog("Sincronizando dados de rewards via remotes...")
    fireSyncRequests(networking)
    task.wait(settings.syncWaitSeconds)

    local context = {
        networking = networking,
        nativeRequire = nativeRequire,
        modules = modules,
    }

    local processors = {}
    table.insert(processors, { name = "Daily", fn = function() processDaily(settings, context) end })
    table.insert(processors, { name = "NewPlayer", fn = function() processNewPlayer(settings, context) end })
    table.insert(processors, { name = "Pirates", fn = function() processPirates(settings, context) end })
    table.insert(processors, { name = "Milestones", fn = function() processMilestones(settings, context) end })
    table.insert(processors, { name = "BattlePass", fn = function() processBattlePass(settings, context) end })
    table.insert(processors, { name = "Quests", fn = function() processQuests(settings, context) end })

    shuffleArray(processors)

    for i, processor in ipairs(processors) do
        local ok, err = pcall(processor.fn)
        if not ok then
            devAlertOnce("processor_" .. tostring(processor.name), "Falha no modulo de rewards '" .. tostring(processor.name) .. "': " .. tostring(err))
        end
        if i < #processors then
            waitRandom(settings.delayBetweenTypesMinSeconds, settings.delayBetweenTypesMaxSeconds)
        end
    end

    rewardLog("Ciclo de rewards (module mode) finalizado.")
end

return RewardModuleSystem
