local QBCore = exports['qb-core']:GetCoreObject()

function GetPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

function HasItem(src, itemName)
    return GetPlayer(src).Functions.GetItemByName(itemName)
end

function RemoveItem(src, itemName, amount)
    return GetPlayer(src).Functions.RemoveItem(itemName, amount)
end

function AddItem(src, itemName, amount)
    return GetPlayer(src).Functions.AddItem(itemName, amount)
end

QBCore.Functions.CreateUseableItem('fishingrod', function(source, item)
    local src = source
    if HasItem(src, item.name) then
        TriggerClientEvent('ts-fishing:client:startFishing', source)
    end
end)

QBCore.Functions.CreateUseableItem('shovel', function(source, item)
    local src = source
    if HasItem(src, item.name) then
        TriggerClientEvent('ts-fishing:client:startFishing', source)
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