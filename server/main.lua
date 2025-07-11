local QBCore = exports['qb-core']:GetCoreObject()
local activeFishingPots = {}
local playerNetBoats = {}
local activeAnchoredBoats = {}
local activeNetProps = {}

local function DebugPrint(msg, source)
    if Config.Debugging then
        if source then
            TriggerClientEvent('ts-fishing:Debugging', source, '[Server Debug]: ' .. msg)
        else
            print('[Server Debug]: ' .. msg)
        end
    end
end

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

local function DeletePotFromDatabase(potId)
    MySQL.Async.execute("DELETE FROM fishing_pots WHERE id = ?", { potId }, function(rowsAffected)
        if rowsAffected > 0 then
            DebugPrint('Pot ' .. potId .. ' deleted from database.')
        else
            DebugPrint('Failed to delete pot ' .. potId .. ' from database!')
        end
    end)
end

RegisterNetEvent('ts-fishing:server:deployPot', function(coords, heading, maxCatches)
    local src = source
    local potId = QBCore.Shared.Functions.RandomStr(10)
    local deployedTime = os.time()

    DebugPrint(string.format('Player %s deploying pot at %s (Heading: %.2f, Max Catches: %d)', src, tostring(coords), heading, maxCatches))

    activeFishingPots[potId] = {
        coords = coords,
        heading = heading,
        deployedTime = deployedTime,
        caughtItems = {},
        maxCatches = maxCatches,
    }

    SavePotToDatabase(potId)

    TriggerClientEvent('ts-fishing:client:createPotProps', -1, {
        id = potId,
        coords = coords,
        heading = heading,
        potModel = Config.deepsea.PotPropModel,
        buoyModel = Config.deepsea.BuoyPropModel
    })
    DebugPrint('Pot ' .. potId .. ' data deployed and saved, broadcasted to clients for prop creation.')
end)

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

    local itemsGiven = 0
    for itemName, count in pairs(potData.caughtItems) do
        Player.Functions.AddItem(itemName, count)
        TriggerClientEvent('ts-fishing:client:sendNotification', src, "Collected " .. count .. "x " .. itemName .. " from pot.", "success")
        itemsGiven = itemsGiven + 1
    end

    if itemsGiven == 0 then
        TriggerClientEvent('ts-fishing:client:sendNotification', src, "The pot was empty!", "info")
    end

    TriggerClientEvent('ts-fishing:client:removePotProps', -1, potId)

    DeletePotFromDatabase(potId)
    activeFishingPots[potId] = nil

    DebugPrint('Pot ' .. potId .. ' collected and removed from server data.')
end)

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


RegisterNetEvent('ts-fishing:server:setPlayersNetBoat', function(netBoatNetworkId)
    local src = source
    playerNetBoats[src] = netBoatNetworkId
    DebugPrint(string.format('Server: Player %s\'s net boat set to Network ID: %s', src, tostring(netBoatNetworkId)), src)
end)

RegisterNetEvent('ts-fishing:server:clearPlayersNetBoat', function()
    local src = source
    playerNetBoats[src] = nil
    DebugPrint(string.format('Server: Player %s\'s net boat record cleared.', src), src)
    if activeNetProps[src] then
        TriggerClientEvent('ts-fishing:client:removeNetPropVisual', -1, activeNetProps[src].netId)
        activeNetProps[src] = nil
        DebugPrint(string.format('Server: Removed net prop visual for player %s.', src), src)
    end
end)

RegisterNetEvent('ts-fishing:server:addNetProp', function(netId, netBoatNetworkId, netPropModel, attachmentOffsetX, attachmentOffsetY, attachmentOffsetZ)
    local src = source
    activeNetProps[src] = {
        netId = netId,
        netBoatNetworkId = netBoatNetworkId,
        netPropModel = netPropModel,
        attachmentOffsetX = attachmentOffsetX,
        attachmentOffsetY = attachmentOffsetY,
        attachmentOffsetZ = attachmentOffsetZ
    }
    TriggerClientEvent('ts-fishing:client:createNetPropVisual', -1, netId, netBoatNetworkId, netPropModel, attachmentOffsetX, attachmentOffsetY, attachmentOffsetZ)
    DebugPrint(string.format('Server: Player %s deployed net %s, broadcasting visual.', src, netId), src)
end)

RegisterNetEvent('ts-fishing:server:removeNetProp', function(netId)
    local src = source
    if activeNetProps[src] and activeNetProps[src].netId == netId then
        TriggerClientEvent('ts-fishing:client:removeNetPropVisual', -1, netId)
        activeNetProps[src] = nil
        DebugPrint(string.format('Server: Player %s removed net %s, broadcasting visual removal.', src, netId), src)
    end
end)

RegisterNetEvent('ts-fishing:server:setBoatAnchorStatus', function(vehicleNetworkId, isAnchoredStatus)
    local src = source
    if isAnchoredStatus then
        activeAnchoredBoats[vehicleNetworkId] = true
        DebugPrint(string.format('Server: Vehicle NetID %s anchored by player %s.', tostring(vehicleNetworkId), src), src)
    else
        activeAnchoredBoats[vehicleNetworkId] = nil
        DebugPrint(string.format('Server: Vehicle NetID %s unanchored by player %s.', tostring(vehicleNetworkId), src), src)
    end
    TriggerClientEvent('ts-fishing:client:syncAnchorStatus', -1, vehicleNetworkId, isAnchoredStatus)
end)

CreateThread(function()
    while true do
        Wait(Config.deepsea.PotCatchGenerationTime)

        for potId, potData in pairs(activeFishingPots) do
            local elapsedSinceDeploy = os.time() - potData.deployedTime
            local intervalSeconds = Config.deepsea.PotCatchGenerationTime / 1000
            local expectedCatches = math.floor(elapsedSinceDeploy / intervalSeconds)

            if potData.caughtItems == nil then potData.caughtItems = {} end

            local currentTotalCatches = 0
            for _, count in pairs(potData.caughtItems) do
                currentTotalCatches = currentTotalCatches + count
            end

            if currentTotalCatches < potData.maxCatches then
                local numToGenerate = math.min(expectedCatches - currentTotalCatches, potData.maxCatches - currentTotalCatches)

                if numToGenerate > 0 then
                    for i = 1, numToGenerate do
                        local caughtItem = Config.FishTypes.deepsea.Crustacean[math.random(1, #Config.FishTypes.deepsea.Crustacean)]
                        if caughtItem then
                            potData.caughtItems[caughtItem] = (potData.caughtItems[caughtItem] or 0) + 1
                            DebugPrint(string.format('Pot %s generated 1x %s. Total in pot: %d', potId, caughtItem, currentTotalCatches + i))
                        end
                    end
                    SavePotToDatabase(potId)
                end
            end
        end
    end
end)

-- MODIFIED: onResourceStart to load existing pots from DB using oxmysql and sync other states
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

-- NEW: Sync existing anchored boats and deployed nets to a new player
AddEventHandler('playerJoining', function()
    local src = source
    -- Sync existing anchored boats
    for netId, _ in pairs(activeAnchoredBoats) do
        TriggerClientEvent('ts-fishing:client:syncAnchorStatus', src, netId, true)
    end
    -- Sync existing deployed nets
    for playerSource, netData in pairs(activeNetProps) do
        TriggerClientEvent('ts-fishing:client:createNetPropVisual', src, netData.netId, netData.netBoatNetworkId, netData.netPropModel, netData.attachmentOffsetX, netData.attachmentOffsetY, netData.attachmentOffsetZ)
    end
end)

-- NEW: Clean up player-specific data on player dropping
AddEventHandler('playerDropped', function()
    local src = source
    -- Clear player's net boat record
    playerNetBoats[src] = nil
    -- Remove any net prop associated with this player
    if activeNetProps[src] then
        TriggerClientEvent('ts-fishing:client:removeNetPropVisual', -1, activeNetProps[src].netId)
        activeNetProps[src] = nil
    end
    -- If the player was in an anchored boat, that boat's anchor status might need review/reset
    -- This is more complex and might require a custom solution depending on how you want
    -- abandoned anchored boats to behave (e.g., stay anchored forever, or unanchor after timeout)
    -- For now, we assume the anchor thread on other clients will eventually detect the vehicle is invalid.
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

RegisterServerEvent('baseevents:enteredVehicle', function(veh, seat, modelName)
    local src = source
    DebugPrint(string.format('Server: Player %s entered vehicle %s (Model: %s) in seat %s.', src, tostring(veh), modelName, tostring(seat)), src)

    local playersNetBoatNetworkId = playerNetBoats[src] -- Get stored Network ID

    -- MODIFIED: Compare the Network ID of the entered vehicle with the stored Network ID
    if playersNetBoatNetworkId and NetworkGetEntityFromNetworkId(playersNetBoatNetworkId) then
        DebugPrint(string.format('Server: Player %s entered their active net fishing boat (Network ID: %s). Triggering client event.', src, tostring(playersNetBoatNetworkId)), src)
        TriggerClientEvent('ts-fishing:client:playerEnteredNetBoat', src) -- Trigger client event
    end
end)