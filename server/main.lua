function DebugPrint(msg, source)
    if Config.Debugging then
        print('^3[ts-fishing]^0 ' .. msg)
    end
end

RegisterNetEvent('ts-fishing:server:ItemControl', function(itemName, amount, give)
    if give then
        AddItem(source, itemName, amount)
    else
        RemoveItem(source, itemName, amount)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DebugPrint('Fishing server script started.')
    end
end)