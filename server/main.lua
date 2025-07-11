-- antisocialrider/ts-fishing/ts-fishing-30c79791400a44ebf78a174946a71c48107efe47/server/main.lua
local QBCore = exports['qb-core']:GetCoreObject()

-- NEW GLOBAL TABLE FOR ACTIVE POTS
-- Stores server-side data for active fishing pots. Props are created client-side.
local activeFishingPots = {} -- { potId = { coords = vector3, heading = float, deployedTime = number, caughtItems = {}, maxCatches = number }, ... }

local function DebugPrint(msg, source)
    if Config.Debugging then
        if source then
            TriggerClientEvent('ts-fishing:Debugging', source, '[Server Debug]: ' .. msg)
        else
            print('[Server Debug]: ' .. msg)
        end
    end
end

-- NEW: Helper to save a single pot to the database using oxmysql
local function SavePotToDatabase(potId)
    local potData = activeFishingPots[potId]
    if potData then
        local coords = potData.coords
        local caughtItemsJson = json.encode(potData.caughtItems)
        MySQL.Async.execute([[
            INSERT INTO fishing_pots (id, x, y, z, heading, deployed_time, catches_json, max_catches)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE x=?, y=?, z=?, heading=?, deployed_time=?, catches_json=?, max_catches=?
        ]], {
            potId, coords.x, coords.y, coords.z, potData.heading, potData.deployedTime, caughtItemsJson, potData.maxCatches,
            coords.x, coords.y, coords.z, potData.heading, potData.deployedTime, caughtItemsJson, potData.maxCatches
        }, function(rowsAffected)
            if rowsAffected > 0 then
                DebugPrint('Pot ' .. potId .. ' saved to database.')
            else
                DebugPrint('Failed to save pot ' .. potId .. ' to database!')
            end
        end)
    end
end

-- NEW: Helper to delete a pot from the database using oxmysql
local function DeletePotFromDatabase(potId)
    MySQL.Async.execute("DELETE FROM fishing_pots WHERE id = ?", { potId }, function(rowsAffected)
        if rowsAffected > 0 then
            DebugPrint('Pot ' .. potId .. ' deleted from database.')
        else
            DebugPrint('Failed to delete pot ' .. potId .. ' from database!')
        end
    end)
end

-- NEW: Event to deploy a fishing pot (client to server)
RegisterNetEvent('ts-fishing:server:deployPot', function(coords, heading, maxCatches)
    local src = source
    local potId = QBCore.Shared.Functions.RandomStr(10) -- Generate a unique ID for the pot
    local deployedTime = os.time() -- Use Unix timestamp for persistence

    DebugPrint(string.format('Player %s deploying pot at %s (Heading: %.2f, Max Catches: %d)', src, tostring(coords), heading, maxCatches))

    -- Store pot data server-side
    activeFishingPots[potId] = {
        coords = coords,
        heading = heading,
        deployedTime = deployedTime,
        caughtItems = {}, -- Initially empty
        maxCatches = maxCatches,
        -- No potNetId/buoyNetId here, as props are client-created
    }

    SavePotToDatabase(potId) -- Save to DB immediately

    -- Trigger client event for ALL players to create the props
    TriggerClientEvent('ts-fishing:client:createPotProps', -1, {
        id = potId,
        coords = coords,
        heading = heading,
        potModel = Config.deepsea.PotPropModel,
        buoyModel = Config.deepsea.BuoyPropModel
    })
    DebugPrint('Pot ' .. potId .. ' data deployed and saved, broadcasted to clients for prop creation.')
end)

-- NEW: Event to collect a fishing pot (client to server)
RegisterNetEvent('ts-fishing:server:collectPot', function(potId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local potData = activeFishingPots[potId]

    if not potData then
        DebugPrint('Player ' .. src .. ' tried to collect non-existent pot ' .. potId)
        TriggerClientEvent('ts-fishing:client:sendNotification', src, "That fishing pot doesn't exist anymore!", "error")
        return
    end

    DebugPrint('Player ' .. src .. ' collecting pot ' .. potId)

    -- Give caught items to player
    local itemsGiven = 0
    for itemName, count in pairs(potData.caughtItems) do
        Player.Functions.AddItem(itemName, count)
        TriggerClientEvent('ts-fishing:client:sendNotification', src, "Collected " .. count .. "x " .. itemName .. " from pot.", "success")
        itemsGiven = itemsGiven + 1
    end

    if itemsGiven == 0 then
        TriggerClientEvent('ts-fishing:client:sendNotification', src, "The pot was empty!", "info")
    end

    -- Trigger client event for ALL players to remove the props
    TriggerClientEvent('ts-fishing:client:removePotProps', -1, potId)

    DeletePotFromDatabase(potId) -- Delete from DB
    activeFishingPots[potId] = nil -- Remove from active table

    DebugPrint('Pot ' .. potId .. ' collected and removed from server data.')
end)

-- NEW Event: Sends current active pot data to a connecting client
RegisterNetEvent('ts-fishing:server:syncPots', function()
    local src = source
    local potsToSend = {}
    for potId, potData in pairs(activeFishingPots) do
        table.insert(potsToSend, {
            id = potId,
            coords = potData.coords,
            heading = potData.heading,
            potModel = Config.deepsea.PotPropModel,
            buoyModel = Config.deepsea.BuoyPropModel
        })
    end
    TriggerClientEvent('ts-fishing:client:createPotProps', src, potsToSend)
    DebugPrint('Synced ' .. #potsToSend .. ' pots to client ' .. src)
end)


-- NEW THREAD: Pot Catch Generation
CreateThread(function()
    while true do
        Wait(Config.deepsea.PotCatchGenerationTime) -- Wait for configured interval in milliseconds

        for potId, potData in pairs(activeFishingPots) do
            local elapsedSinceDeploy = os.time() - potData.deployedTime -- elapsed time in seconds
            local intervalSeconds = Config.deepsea.PotCatchGenerationTime / 1000 -- interval in seconds
            local expectedCatches = math.floor(elapsedSinceDeploy / intervalSeconds)

            if potData.caughtItems == nil then potData.caughtItems = {} end -- Ensure table exists

            local currentTotalCatches = 0
            for _, count in pairs(potData.caughtItems) do
                currentTotalCatches = currentTotalCatches + count
            end

            if currentTotalCatches < potData.maxCatches then
                local numToGenerate = math.min(expectedCatches - currentTotalCatches, potData.maxCatches - currentTotalCatches)

                if numToGenerate > 0 then
                    for i = 1, numToGenerate do
                        local caughtItem = nil
                        local chance = math.random()
                        if chance < Config.FishTypes.deepsea.CatchChance then
                            if math.random() < 0.5 then -- 50% chance for fish or crustacean
                                caughtItem = Config.FishTypes.deepsea.Fish[math.random(1, #Config.FishTypes.deepsea.Fish)]
                            else
                                caughtItem = Config.FishTypes.deepsea.Crustacean[math.random(1, #Config.FishTypes.deepsea.Crustacean)]
                            end
                        end

                        if caughtItem then
                            potData.caughtItems[caughtItem] = (potData.caughtItems[caughtItem] or 0) + 1
                            DebugPrint(string.format('Pot %s generated 1x %s. Total in pot: %d', potId, caughtItem, currentTotalCatches + i))
                        end
                    end
                    SavePotToDatabase(potId) -- Save updated catches
                end
            end
        end
    end
end)

-- MODIFIED: onResourceStart to load existing pots from DB using oxmysql
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        MySQL.Sync.execute([[
            CREATE TABLE IF NOT EXISTS `fishing_pots` (
                `id` VARCHAR(10) NOT NULL,
                `x` FLOAT NOT NULL,
                `y` FLOAT NOT NULL,
                `z` FLOAT NOT NULL,
                `heading` FLOAT NOT NULL,
                `deployed_time` BIGINT NOT NULL,
                `catches_json` TEXT NOT NULL,
                `max_catches` INT NOT NULL,
                PRIMARY KEY (`id`)
            );
        ]])
        print('^2[ts-fishing]^7 Table `fishing_pots` checked/created.')
        DebugPrint('Fishing server script started. Loading existing pots from database...')
        local dbResult = MySQL.Sync.fetchAll('SELECT id, x, y, z, heading, deployed_time, catches_json, max_catches FROM fishing_pots;', {})
        if dbResult and #dbResult > 0 then
            for _, row in ipairs(dbResult) do
                local potId = row.id
                local coords = vector3(row.x, row.y, row.z)
                local caughtItems = json.decode(row.catches_json)
                if type(caughtItems) ~= 'table' then caughtItems = {} end
                -- Only load data into activeFishingPots, clients will request sync on spawn
                activeFishingPots[potId] = {
                    coords = coords,
                    heading = row.heading,
                    deployedTime = row.deployed_time,
                    caughtItems = caughtItems,
                    maxCatches = row.max_catches,
                }
                DebugPrint('Loaded pot ' .. potId .. ' data from DB at ' .. tostring(coords))
            end
        else
            DebugPrint('No existing pots found in database.')
        end
    end
end)


-- MODIFIED: Useable items now trigger specific client events
QBCore.Functions.CreateUseableItem('fishingrod', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        TriggerClientEvent('ts-fishing:client:startTraditionalFishing', source) -- NEW event
    end
end)

QBCore.Functions.CreateUseableItem('shovel', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        TriggerClientEvent('ts-fishing:client:startClamming', source) -- NEW event
    end
end)

-- NEW: Usable item for fishing net
QBCore.Functions.CreateUseableItem('fishingnet', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        DebugPrint('fishingnet used, triggering client event for deepsea net fishing.', src)
        TriggerClientEvent('ts-fishing:client:startDeepSeaFishing', source, 'net') -- NEW event
    end
end)

-- NEW: Usable item for fishing pot
QBCore.Functions.CreateUseableItem('fishingpot', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        DebugPrint('fishingpot used, triggering client event for deepsea pot fishing.', src)
        TriggerClientEvent('ts-fishing:client:startDeepSeaFishing', source, 'pot') -- NEW event
    end
end)

RegisterNetEvent('ts-fishing:server:ItemControl', function(itemName, amount, give)
    local Player = QBCore.Functions.GetPlayer(source)
    if give then
        Player.Functions.AddItem(itemName, amount)
    else
        Player.Functions.RemoveItem(itemName, amount)
    end
end)