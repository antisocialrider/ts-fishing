local QBCore = exports['qb-core']:GetCoreObject()

function SendNotification(message, notificationType)
    SendNuiMessage(json.encode({
        type = 'showNotification',
        message = message,
        notificationType = notificationType or 'info'
    }))
    DebugPrint('NUI Notification: ' .. message .. ' (' .. (notificationType or 'info') .. ')')
end

function HasItem(itemName)
    if itemName == nil then DebugPrint('Item check for nil item. Returning true.'); return true end
    return QBCore.Functions.HasItem(itemName)
end

function RemoveItem(itemName, amount)
    if itemName == nil then DebugPrint('Attempted to remove nil item.'); return end
    DebugPrint("Removed " .. amount .. "x " .. itemName)
    TriggerServerEvent('ts-fishing:server:ItemControl', itemName, amount, false)
    SendNotification("You used 1x " .. itemName .. ".", "info")
end

function AddItem(itemName, amount)
    DebugPrint("Added " .. amount .. "x " .. itemName )
    TriggerServerEvent('ts-fishing:server:ItemControl', itemName, amount, true)
    SendNotification("You caught a " .. itemName .. "!", "success")
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    CreateFishingZones()
end)