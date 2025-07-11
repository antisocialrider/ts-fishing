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

if Config.Items.create then
    if not exports['qb-core'] or type(exports['qb-core'].AddItem) ~= 'function' then
        print('^1[ts-fishing] Error: exports[\'qb-core\']:AddItem is not available. Ensure qb-core is fully loaded and updated.^7')
        return
    end
    for _, itemData in ipairs(Config.Items.list) do
        exports['qb-core']:AddItem(itemData.name, itemData)
        print(string.format('^2[ts-fishing] Registered new item via AddItem: %s (%s)^7', itemData.label, itemData.name))
    end
else
    print('^3[ts-fishing] Item creation is disabled in config. To enable, set Config.Items.create to true.^7')
end