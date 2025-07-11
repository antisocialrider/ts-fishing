-- server/main.lua
local QBCore = exports['qb-core']:GetCoreObject()

local function DebugPrint(msg, source)
    if Config.Debugging then
        if source then
            TriggerClientEvent('ts-fishing:Debugging', source, '[Server Debug]: ' .. msg)
        else
            print('[Server Debug]: ' .. msg)
        end
    end
end

QBCore.Functions.CreateUseableItem('fishingrod', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        TriggerClientEvent('ts-fishing:client:startFishing', source)
    end
end)

QBCore.Functions.CreateUseableItem('shovel', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        TriggerClientEvent('ts-fishing:client:startFishing', source)
    end
end)

-- NEW: Usable item for fishing net
QBCore.Functions.CreateUseableItem('fishingnet', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        DebugPrint('fishingnet used, triggering client event for deepsea net fishing.', src)
        TriggerClientEvent('ts-fishing:client:startFishing', source, 'net')
    end
end)

-- NEW: Usable item for fishing pot
QBCore.Functions.CreateUseableItem('fishingpot', function(source, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.Functions.GetItemByName(item.name) then
        DebugPrint('fishingpot used, triggering client event for deepsea pot fishing.', src)
        TriggerClientEvent('ts-fishing:client:startFishing', source, 'pot')
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

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DebugPrint('Fishing server script started.')
    end
end)