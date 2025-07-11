local QBCore = exports['qb-core']:GetCoreObject()

local createdZones = {}
local isFishing = false
local fishingRodProp = nil
local clammingShovelProp = nil
local clammingDirtProp = nil

local isNetDeployed = false
local netDeployedHandle = nil
local netBoatEntity = nil
local netStartCoords = nil
local isNetReadyForCollection = false
local netCollectionZone = nil
local potProp = nil
local buoyProp = nil
local clientActivePots = {}
local currentZoneType = nil
local isBoatAnchored = false
local anchorThread = nil
local syncedAnchoredBoats = {}
local syncedNetProps = {}
local isAwaitingNetSailStart = false

AddEventHandler("onResourceStart", function(res)
    if GetCurrentResourceName() ~= res then return end

    isFishing = false
    isNetDeployed = false
    netDeployedHandle = nil
    netBoatEntity = nil
    netStartCoords = nil
    isNetReadyForCollection = false
    netCollectionZone = nil
    potProp = nil
    buoyProp = nil
    clientActivePots = {}
    isBoatAnchored = false
    anchorThread = nil
    isAwaitingNetSailStart = false
    syncedAnchoredBoats = {}
    syncedNetProps = {}
end)

local function DebugPrint(msg)
    if Config.Debugging then
        print('^3[Fishing Debug]^0 ' .. msg)
    end
end
RegisterNetEvent('ts-fishing:Debugging', DebugPrint)

local function DisplayHelpText(str)
	SetTextComponentFormat("STRING")
	AddTextComponentString(str)
	DisplayHelpTextFromStringLabel(0, 0, 0, -1)
	EndTextCommandDisplayHelp(0, 0, true, 2000)
end

CreateThread(function()
    Wait(100)
    DebugPrint('Checking for PolyZone global constructors status:')
    DebugPrint('  CircleZone: ' .. tostring(CircleZone ~= nil))
    DebugPrint('  BoxZone: ' .. tostring(BoxZone ~= nil))
    DebugPrint('  PolyZone (for polygon): ' .. tostring(PolyZone ~= nil))
    DebugPrint('  ComboZone: ' .. tostring(ComboZone ~= nil))
    DebugPrint('Global PolyZone constructor checks complete.')
end)

local function SendNotification(message, notificationType)
    SendNuiMessage(json.encode({
        type = 'showNotification',
        message = message,
        notificationType = notificationType or 'info'
    }))
    DebugPrint('NUI Notification: ' .. message .. ' (' .. (notificationType or 'info') .. ')')
end

local function HasItem(itemName)
    if itemName == nil then DebugPrint('Item check for nil item. Returning true.'); return true end
    return QBCore.Functions.HasItem(itemName)
end

local function RemoveItem(itemName, amount)
    if itemName == nil then DebugPrint('Attempted to remove nil item.'); return end
    DebugPrint("Removed " .. amount .. "x " .. itemName .. " (Standalone - no actual removal)")
    TriggerServerEvent('ts-fishing:server:ItemControl', itemName, amount, false)
    SendNotification("You used 1x " .. itemName .. ".", "info")
end

local function AddItem(itemName, amount)
    DebugPrint("Added " .. amount .. "x " .. itemName .. " (Standalone - no actual adding)")
    TriggerServerEvent('ts-fishing:server:ItemControl', itemName, amount, true)
    SendNotification("You caught a " .. itemName .. "!", "success")
end

local function StartMinigame(fishingType, deepseaType)
    if fishingType == 'traditional' then
        return exports.peuren_minigames:StartPressureBar(40, 20)
    elseif fishingType == 'clamming' then
        return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
    elseif fishingType == 'deepsea' and deepseaType == 'pot' then
        return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
    end
    return false
end

local function AdvancedWaterCheck()
    local ped = PlayerPedId()

    if not DoesEntityExist(ped) or ped == 0 then
        DebugPrint("AdvancedWaterCheck: Player ped does not exist or is invalid. Returning false.")
        return false, vector3(0.0, 0.0, 0.0)
    end

    local boneCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    if boneCoords.x == 0.0 and boneCoords.y == 0.0 and boneCoords.z == 0.0 then
        DebugPrint("AdvancedWaterCheck: GetPedBoneCoords returned (0,0,0). Ped might be in an invalid state or bone doesn't exist.")
        return false, vector3(0.0, 0.0, 0.0)
    end

    local forwardOffset = 5.0
    local spawnZOffset = 1.0

    local forwardX, forwardY
    local _, _, _, fwdX, fwdY, _, _, _, _, _, _, _ = GetEntityMatrix(ped)

    if fwdX and fwdY then
        forwardX = fwdX
        forwardY = fwdY
    else
        DebugPrint("AdvancedWaterCheck: GetEntityMatrix returned nil for forward vectors. Falling back to rotation.")
        local heading = GetEntityHeading(ped)
        forwardX = -math.sin(math.rad(heading))
        forwardY = math.cos(math.rad(heading))
    end

    local probeX = boneCoords.x + (forwardX * forwardOffset)
    local probeY = boneCoords.y + (forwardY * forwardOffset)
    local probeZ = boneCoords.z + spawnZOffset

    DebugPrint(string.format("AdvancedWaterCheck: Calculated Probe Spawn: X:%.2f, Y:%.2f, Z:%.2f", probeX, probeY, probeZ))

    local model = `prop_alien_egg_01`
    RequestModel(model)
    local timeout = 2000
    local startTime = GetGameTimer()

    while not HasModelLoaded(model) do
        Wait(0)
        if GetGameTimer() - startTime > timeout then
            DebugPrint("AdvancedWaterCheck: Model " .. model .. " failed to load within timeout. Returning false.")
            return false, vector3(0.0, 0.0, 0.0)
        end
    end

    local probeObject = CreateObject(model, probeX, probeY, probeZ, false, false, false)
    SetEntityVisible(probeObject, false, false)
    SetEntityHasGravity(probeObject, true)
    ActivatePhysics(probeObject)

    local waitTimeForSettle = 7000
    DebugPrint("AdvancedWaterCheck: Waiting " .. waitTimeForSettle .. "ms for probe to settle.")
    Wait(waitTimeForSettle)
    local inWater = IsEntityInWater(probeObject)
    local actualProbeCoords = GetEntityCoords(probeObject)
    DebugPrint(string.format("AdvancedWaterCheck: After %dms settle: Probe Object ID: %s, IsEntityInWater: %s, Actual Probe Z: %.2f", waitTimeForSettle, tostring(inWater), tostring(inWater), actualProbeCoords.z))

    DeleteObject(probeObject)
    SetModelAsNoLongerNeeded(model)

    return inWater, actualProbeCoords
end

local function CheckRequiredItems(fishingType, config)

    if fishingType == 'deepsea' then
        if not HasItem(config.NetItem) and not HasItem(config.PotItem) then
            DebugPrint('Required item check failed: Missing Net or Pot for deepsea fishing')
            return false, "You need a Fishing Net or a Fishing Pot!"
        end
    else
        if config.RodItem and not HasItem(config.RodItem) then
            DebugPrint('Required item check failed: Missing ' .. config.RodItem)
            return false, "You need a " .. config.RodItem .. "!"
        end
    end

    if config.BaitItem and not HasItem(config.BaitItem) then
        DebugPrint('Required item check failed: Missing ' .. config.BaitItem)
        return false, "You need " .. config.BaitItem .. "!"
    end
    DebugPrint('Required item check passed.')
    return true, ""
end

local function CheckDeepSeaBoat(config, PlayerPed)
    local playerCoords = GetEntityCoords(PlayerPed)
    local foundBoat = nil

    local allVehicles = GetGamePool('CVehicle')

    if not allVehicles then
        DebugPrint('CheckDeepSeaBoat failed: Could not get game pool for vehicles.')
        return false, "Internal error checking for boats (vehicle pool unavailable).", nil
    end

    for i = 1, #allVehicles do
        local vehicle = allVehicles[i]

        if not DoesEntityExist(vehicle) then
            goto continue
        end

        local vehicleCoords = GetEntityCoords(vehicle)

        local isCorrectBoatModel = GetEntityModel(vehicle) == GetHashKey(config.BoatModel)
        if not isCorrectBoatModel then
            goto continue
        end

        local distance = GetDistanceBetweenCoords(playerCoords, vehicleCoords, true)
        if distance > Config['deepsea'].BoatProximity then
            DebugPrint('Deep sea fishing boat check: Boat ' .. GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) .. ' found, but too far (' .. string.format("%.2f", distance) .. 'm).')
            goto continue
        end

        local boatVelocity = GetEntityVelocity(vehicle)
        local speed = Vdist(0.0, 0.0, 0.0, boatVelocity.x, boatVelocity.y, boatVelocity.z)

        if speed > Config['deepsea'].AnchoredThreshold then
            DebugPrint('Deep sea fishing boat check: Found boat ' .. GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) .. ' nearby but it is not anchored (speed: ' .. string.format("%.2f", speed) .. ').')
            goto continue
        end

        foundBoat = vehicle
        break
        ::continue::
    end

    if not foundBoat then
        DebugPrint('Deep sea fishing boat check failed: No correct, anchored boat found nearby within ' .. Config['deepsea'].BoatProximity .. 'm.')
        return false, "You need to be near an anchored " .. GetDisplayNameFromVehicleModel(GetHashKey(config.BoatModel)) .. " to deep sea fish!", nil
    end

    DebugPrint('Deep sea fishing boat check passed: Found correct boat nearby and anchored.')
    return true, "", foundBoat
end

local function CheckTraditionalLocation(PlayerPed)
    local isSwimming = IsPedSwimming(PlayerPed)
    if isSwimming then
        DebugPrint('Traditional fishing location check failed: Cannot fish while swimming.')
        return false, "You cannot traditionally fish while swimming!"
    end
    local facingFishableWater, waterHitPos = AdvancedWaterCheck()
    SendNotification("Checking fishing spot...", "info")

    if not facingFishableWater then
        DebugPrint('Traditional fishing location check failed: Not facing fishable water (WaterCheck returned false).')
        return false, "You need to be facing fishable water to traditionally fish!"
    end
    DebugPrint('Traditional fishing location check passed. Water found at ' .. tostring(waterHitPos.x) .. ', ' .. tostring(waterHitPos.y) .. ', ' .. tostring(waterHitPos.z))
    return true, ""
end

local function DestroyNetCollectionZone()
    if netCollectionZone then
        netCollectionZone:destroy()
        netCollectionZone = nil
        DebugPrint("Net collection zone destroyed.")
    end
end

local function StopNetFishing()
    local PlayerPed = PlayerPedId()
    ClearPedTasks(PlayerPed)

    if netDeployedHandle and DoesEntityExist(netDeployedHandle) then
        DeleteObject(netDeployedHandle)
        netDeployedHandle = nil
        DebugPrint('Deleted net prop.')
    end
    
    if netBoatEntity and DoesEntityExist(netBoatEntity) then
        SetEntityVelocity(netBoatEntity, 0.0, 0.0, 0.0)
        SetVehicleEngineOn(netBoatEntity, true, true, false)
        SetVehicleUndriveable(netBoatEntity, false)
        DebugPrint('Resetting netBoatEntity physics and controls.')
    end

    netBoatEntity = nil
    netStartCoords = nil
    isNetDeployed = false
    isNetReadyForCollection = false
    isFishing = false
    DestroyNetCollectionZone()
    isAwaitingNetSailStart = false
    SendNotification("Net fishing stopped.", "info")
    DebugPrint('Net fishing state reset.')
    TriggerServerEvent('ts-fishing:server:clearPlayersNetBoat')
    TriggerServerEvent('ts-fishing:server:removeNetProp', GetPlayerServerId(PlayerId()))
end

local function StopTraditionalFishing()
    local PlayerPed = PlayerPedId()
    ClearPedTasks(PlayerPed)
    if fishingRodProp and DoesEntityExist(fishingRodProp) then
        DeleteObject(fishingRodProp)
        fishingRodProp = nil
        DebugPrint('Deleted fishing rod prop.')
    end
    RemoveAnimDict('mini@tennis')
    RemoveAnimDict('amb@world_human_stand_fishing@idle_a')
    isFishing = false
    SendNotification("Traditional fishing stopped.", "info")
    DebugPrint('Traditional fishing state reset.')
end

local function StopClamming()
    local PlayerPed = PlayerPedId()
    ClearPedTasks(PlayerPed)
    if clammingShovelProp and DoesEntityExist(clammingShovelProp) then
        DeleteObject(clammingShovelProp)
        clammingShovelProp = nil
        DebugPrint('Deleted shovel prop.')
    end
    if clammingDirtProp and DoesEntityExist(clammingDirtProp) then
        DeleteObject(clammingDirtProp)
        clammingDirtProp = nil
        DebugPrint('Deleted dirt prop.')
    end
    RemoveAnimDict('random@burial')
    isFishing = false
    SendNotification("Clamming stopped.", "info")
    DebugPrint('Clamming state reset.')
end

local function StopFishing()
    if not isFishing and not isNetDeployed and not isNetReadyForCollection and not isAwaitingNetSailStart then
        DebugPrint('StopFishing called but no active fishing. Exiting.')
        return
    end

    DebugPrint('Stopping all fishing processes...')
    ClearPedTasks(PlayerPedId())

    StopTraditionalFishing()
    StopClamming()
    StopNetFishing()

    if potProp and DoesEntityExist(potProp) then
        DeleteObject(potProp)
        potProp = nil
        DebugPrint('Deleted local pot prop.')
    end
    if buoyProp and DoesEntityExist(buoyProp) then
        DeleteObject(buoyProp)
        buoyProp = nil
        DebugPrint('Deleted local buoy prop.')
    end

    RemoveAnimDict('mini@tennis')
    RemoveAnimDict('amb@world_human_stand_fishing@idle_a')
    RemoveAnimDict('random@burial')
    DebugPrint('Removed animation dictionaries.')

    isFishing = false
    SendNotification("Fishing stopped.", "info")
    DebugPrint('Master fishing state reset.')
end

local function GetRearOfBoatCoords(boatEntity, offset)
    local coords = GetEntityCoords(boatEntity)
    local heading = GetEntityHeading(boatEntity)
    local rearX = coords.x - math.sin(math.rad(heading)) * offset.y
    local rearY = coords.y + math.cos(math.rad(heading)) * offset.y
    local rearZ = coords.z + offset.z
    return vector3(rearX, rearY, rearZ)
end

local function CheckPlayerNearBoatRear(PlayerPed, boatEntity, proximityThreshold)
    local playerCoords = GetEntityCoords(PlayerPed)
    local rearOfBoatWorldCoords = GetOffsetFromEntityInWorldCoords(boatEntity, 0.0, -3.0, -0.5)
    local distance = GetDistanceBetweenCoords(playerCoords, rearOfBoatWorldCoords, true)
    DebugPrint(string.format("Player distance to boat rear: %.2f (Threshold: %.2f) (Target Coords: %s)", distance, proximityThreshold, tostring(rearOfBoatWorldCoords)))
    return distance <= proximityThreshold, "You need to be near the back of the boat to collect this!"
end

local function PerformNetCollection()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local config = Config['deepsea']

    if not isNetReadyForCollection then
        SendNotification("No net ready for collection.", "error")
        return
    end
    local nearRear, rearMessage = CheckPlayerNearBoatRear(playerPed, netBoatEntity, 5)
    if not nearRear then
        SendNotification(rearMessage, "error")
        return
    end

    SendNotification("Collecting net...", "info")
    local animDict = 'random@burial'
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    TaskPlayAnim(playerPed, animDict, 'a_burial', 1.0, -1.0, -1, 48, 0, 0, 0, 0)
    Wait(5000)
    ClearPedTasks(playerPed)

    local fishConfig = Config.FishTypes.deepsea
    local amountToCatch = math.random(fishConfig.MinCatchAmount, fishConfig.MaxCatchAmount)
    local collectedItems = {}
    local possibleCatches = {}

    for _, fishName in ipairs(fishConfig.Fish) do
        table.insert(possibleCatches, fishName)
    end
    for _, crustaceanName in ipairs(fishConfig.Crustacean) do
        table.insert(possibleCatches, crustaceanName)
    end

    if amountToCatch > 0 and #possibleCatches > 0 then
        for i = 1, amountToCatch do
            local randomIndex = math.random(1, #possibleCatches)
            local caughtItem = possibleCatches[randomIndex]
            collectedItems[caughtItem] = (collectedItems[caughtItem] or 0) + 1
        end

        local notificationMessage = "Collected from net: "
        local firstItem = true

        for itemName, count in pairs(collectedItems) do
            AddItem(itemName, count)
            DebugPrint(string.format('Successfully caught: %dx %s from net collection.', count, itemName))

            if not firstItem then
                notificationMessage = notificationMessage .. ", "
            end
            notificationMessage = notificationMessage .. count .. "x " .. itemName
            firstItem = false
        end

        if firstItem then
            SendNotification("The net came up empty this time.", "info")
            DebugPrint('Net collection: No catch (no items collected).')
        else
            SendNotification(notificationMessage, "success")
        end
    else
        SendNotification("The net came up empty this time.", "info")
        DebugPrint('Net collection: No catch (amount was zero or no possible items).')
    end

    StopNetFishing()
    DestroyNetCollectionZone()
end

local function CreateNetCollectionZone()
    if netCollectionZone then
        netCollectionZone:destroy()
        netCollectionZone = nil
        DebugPrint("Destroyed existing net collection zone before creating new one.")
    end

    local config = Config['deepsea']
    local playerPed = PlayerPedId()
    local boatForCollection = netBoatEntity 

    if not DoesEntityExist(boatForCollection) or boatForCollection == 0 then
        DebugPrint("Failed to create collection zone: No valid netBoatEntity found.")
        SendNotification("Failed to create collection area: Associated boat not found.", "error")
        return
    end

    local collectionCoords = GetRearOfBoatCoords(boatForCollection, config.PotDeployOffset)
    DebugPrint("Collection point calculated at: " .. tostring(collectionCoords))

    Citizen.CreateThread(function()
        while isNetReadyForCollection do
            local currentPedCoords = GetEntityCoords(playerPed)
            local currentVehicle = GetVehiclePedIsIn(playerPed, false)
            local isPlayerInDriverSeat = (currentVehicle == boatForCollection and GetPedInVehicleSeat(currentVehicle, -1) == playerPed)

            local nearRear, rearMessage = CheckPlayerNearBoatRear(playerPed, boatForCollection, 5)

            if not isPlayerInDriverSeat and nearRear then
                DisplayHelpText("Press ~INPUT_CONTEXT~ to collect fishing net")
                if IsControlJustReleased(0, 38) then
                    PerformNetCollection()
                    break
                end
            end
            Wait(0)
        end
        DebugPrint("Net collection prompt thread terminated.")
    end)
    DebugPrint("Net collection prompt thread started.")
end

CreateThread(function()
    while true do
        Wait(0)

        local playerPed = PlayerPedId()
        local currentVehicle = GetVehiclePedIsIn(playerPed, false)
        local config = Config['deepsea']

        if isAwaitingNetSailStart then
            if currentVehicle ~= 0 and DoesEntityExist(currentVehicle) and GetVehicleClass(currentVehicle) == 14 and currentVehicle == netBoatEntity then
                DisplayHelpText("~b~Net Fishing: ~w~Un-anchor to start dragging net. Use /anchor, or ~INPUT_CELLPHONE_CANCEL~ to cancel.")
                if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then
                    SendNotification("Net deployment cancelled!", "info")
                    StopNetFishing()
                else
                    local boatVelocity = GetEntityVelocity(netBoatEntity)
                    local speed = Vdist(0.0, 0.0, 0.0, boatVelocity.x, boatVelocity.y, boatVelocity.z)

                    if speed > config.AnchoredThreshold then
                        isAwaitingNetSailStart = false
                        isNetDeployed = true
                        netStartCoords = GetEntityCoords(netBoatEntity)
                        SendNotification("Net dragging started! Sail to drag the net.", "info")
                    else
                        Wait(50)
                    end
                end
            else
                DisplayHelpText("~b~Net Fishing: ~w~Re-enter your boat to continue. Press ~INPUT_CELLPHONE_CANCEL~ to cancel.")
                if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then
                    SendNotification("Net deployment cancelled!", "info")
                    StopNetFishing()
                end
                Wait(5)
            end
        elseif isNetDeployed and netBoatEntity and DoesEntityExist(netBoatEntity) then
            local playerCoords = GetEntityCoords(playerPed)
            local boatCoords = GetEntityCoords(netBoatEntity)
            local distanceToBoat = GetDistanceBetweenCoords(playerCoords, boatCoords, true)

            if distanceToBoat > Config['deepsea'].BoatProximity + 10.0 then
                SendNotification("You moved too far from the boat! Net fishing cancelled.", "error")
                StopNetFishing()
            else
                local distanceSailed = 0
                if netStartCoords then
                    distanceSailed = GetDistanceBetweenCoords(netStartCoords, boatCoords, true)
                end
                DisplayHelpText(string.format("~b~Net Fishing: ~w~Sail ~y~%.1fm~w~/~g~%.1fm~w~. Press ~INPUT_CELLPHONE_CANCEL~ to cancel.", distanceSailed, config.NetMinigameSailDistance))

                if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then
                    SendNotification("Net fishing cancelled!", "info")
                    StopNetFishing()
                end

                if distanceSailed >= config.NetMinigameSailDistance then
                    SendNotification("Net has been dragged far enough! Anchoring boat and preparing for collection...", "info")
                    local currentVelocity = GetEntityVelocity(netBoatEntity)
                    SetEntityVelocity(netBoatEntity, 0.0, 0.0, currentVelocity.z)
                    isNetDeployed = false
                    isNetReadyForCollection = true
                    CreateNetCollectionZone()
                    ExecuteCommand("anchor")
                end
            end
        elseif isNetReadyForCollection and netBoatEntity and DoesEntityExist(netBoatEntity) then
            local playerCoords = GetEntityCoords(playerPed)
            local boatCoords = GetEntityCoords(netBoatEntity)
            local distanceToBoat = GetDistanceBetweenCoords(playerCoords, boatCoords, true)

            if distanceToBoat > Config['deepsea'].BoatProximity + 10.0 then
                SendNotification("You moved too far from the boat! Net collection cancelled.", "error")
                StopNetFishing()
            end
            Wait(5)
        else
            Wait(5)
        end
    end
end)

local function StartTraditionalFishingProcess(PlayerPed)
    local config = Config['traditional']
    local fishConfig = Config.FishTypes['traditional']
    local message = ""
    local passedChecks = true

    local itemsValid, itemMessage = CheckRequiredItems('traditional', config)
    if not itemsValid then
        passedChecks = false
        message = itemMessage
    end

    if passedChecks then
        local locationValid, locationMessage = CheckTraditionalLocation(PlayerPed)
        if not locationValid then
            passedChecks = false
            message = locationMessage
        end
    end

    if not passedChecks then
        SendNotification(message, "error")
        isFishing = false
        return
    end

    if config.BaitItem then
        RemoveItem(config.BaitItem, 1)
    end

    SendNotification("Starting Traditional Fishing...", "info")
    isFishing = true

    local model = `prop_fishing_rod_01`
    local animDictTennis = 'mini@tennis'
    local animDictFishing = 'amb@world_human_stand_fishing@idle_a'

    RequestModel(model)
    RequestAnimDict(animDictTennis)
    RequestAnimDict(animDictFishing)

    while not HasModelLoaded(model) or not HasAnimDictLoaded(animDictTennis) or not HasAnimDictLoaded(animDictFishing) do
        Wait(0)
    end

    fishingRodProp = CreateObject(model, GetEntityCoords(PlayerPed), true, false, false)
    AttachEntityToEntity(fishingRodProp, PlayerPed, GetPedBoneIndex(PlayerPed, 18905), 0.1, 0.05, 0, 80.0, 120.0, 160.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)

    TaskPlayAnim(PlayerPed, animDictTennis, 'forehand_ts_md_far', 1.0, -1.0, 1000, 48, 0, 0, 0, 0)
    Wait(1000)
    TaskPlayAnim(PlayerPed, animDictFishing, 'idle_c', 1.0, -1.0, -1, 11, 0, 0, 0, 0)
    DebugPrint('Starting traditional fishing animation.')

    local wasCancelled = false
    local startTime = GetGameTimer()
    local endTime = startTime + config.Time

    while GetGameTimer() < endTime do
        Wait(0)
        DisplayHelpText("~INPUT_CELLPHONE_CANCEL~ or ~INPUT_CREATOR_LT~ Cancel Fishing")
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then
            wasCancelled = true
            SendNotification("Fishing cancelled!", "info")
            DebugPrint('Traditional fishing cancelled by player.')
            break
        end
    end

    DebugPrint('Traditional fishing attempt duration finished. Starting minigame.')

    if not wasCancelled then
        if StartMinigame('traditional') then
            if math.random() < fishConfig.CatchChance then
                local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
                AddItem(caughtItem, 1)
                DebugPrint('Successfully caught: ' .. caughtItem)
            else
                SendNotification("You didn't catch anything this time.", "info")
                DebugPrint('Traditional fishing attempt: No catch.')
            end
        end
    end
    StopTraditionalFishing()
end

local function StartClammingProcess(PlayerPed)
    local config = Config['clamming']
    local fishConfig = Config.FishTypes['clamming']
    local message = ""
    local passedChecks = true

    local itemsValid, itemMessage = CheckRequiredItems('clamming', config)
    if not itemsValid then
        passedChecks = false
        message = itemMessage
    end

    if passedChecks then
        if currentZoneType ~= 'clamming' then
            passedChecks = false
            message = "You need to be in a clamming zone to clam!"
        end
    end

    if not passedChecks then
        SendNotification(message, "error")
        isFishing = false
        return
    end

    if config.BaitItem then
        RemoveItem(config.BaitItem, 1)
    end

    SendNotification("Starting Clamming...", "info")
    isFishing = true

    local shovelModel = `prop_tool_shovel`
    local dirtModel = `prop_ld_shovel_dirt`
    local animDictBurial = 'random@burial'

    RequestModel(shovelModel)
    RequestModel(dirtModel)
    RequestAnimDict(animDictBurial)

    while not HasModelLoaded(shovelModel) or not HasModelLoaded(dirtModel) or not HasAnimDictLoaded(animDictBurial) do
        Wait(0)
    end

    clammingShovelProp = CreateObject(shovelModel, GetEntityCoords(PlayerPed), true, false, false)
    AttachEntityToEntity(clammingShovelProp, PlayerPed, GetPedBoneIndex(PlayerPed, 28422), 0.0, 0.0, 0.24, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(shovelModel)

    clammingDirtProp = CreateObject(dirtModel, GetEntityCoords(PlayerPed), true, false, false)
    AttachEntityToEntity(clammingDirtProp, PlayerPed, GetPedBoneIndex(PlayerPed, 28422), 0.0, 0.0, 0.24, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(dirtModel)

    TaskPlayAnim(PlayerPed, animDictBurial, 'a_burial', 1.0, -1.0, -1, 48, 0, 0, 0, 0)
    DebugPrint('Starting shovel digging animation for clamming.')

    local wasCancelled = false
    local startTime = GetGameTimer()
    local endTime = startTime + config.Time

    while GetGameTimer() < endTime do
        Wait(0)
        DisplayHelpText("~INPUT_CELLPHONE_CANCEL~ or ~INPUT_CREATOR_LT~ Cancel Fishing")
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then
            wasCancelled = true
            SendNotification("Clamming cancelled!", "info")
            DebugPrint('Clamming cancelled by player.')
            break
        end
    end

    DebugPrint('Clamming attempt duration finished. Starting minigame.')

    if not wasCancelled then
        if StartMinigame('clamming') then
            if math.random() < fishConfig.CatchChance then
                local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
                AddItem(caughtItem, 1)
                DebugPrint('Successfully caught: ' .. caughtItem)
            else
                SendNotification("You didn't catch anything this time.", "info")
                DebugPrint('Clamming attempt: No catch.')
            end
        end
    end
    StopClamming()
end

local function StartDeepSeaFishingProcess(PlayerPed, deepSeaMethod)
    local config = Config['deepsea']
    local fishConfig = Config.FishTypes['deepsea']
    local message = ""
    local passedChecks = true
    local deepSeaBoatEntity = nil
    local playerCoords = GetEntityCoords(PlayerPed)

    local boatValid, boatMessage, foundDeepSeaBoat = CheckDeepSeaBoat(config, PlayerPed)
    if not boatValid then
        passedChecks = false
        message = boatMessage
    else
        deepSeaBoatEntity = foundDeepSeaBoat
        DebugPrint('Deep sea fishing: Identified deep sea boat entity: ' .. tostring(deepSeaBoatEntity))

        if deepSeaMethod == 'net' then
            if isNetDeployed or isNetReadyForCollection then
                passedChecks = false
                message = "You already have a net deployed or ready for collection!"
            else
                local nearRear, rearMessage = CheckPlayerNearBoatRear(PlayerPed, deepSeaBoatEntity, config.BoatProximity)
                if not nearRear then
                    passedChecks = false
                    message = rearMessage
                end
            end
        elseif deepSeaMethod == 'pot' then
            local nearRear, rearMessage = CheckPlayerNearBoatRear(PlayerPed, deepSeaBoatEntity, config.BoatProximity)
            if not nearRear then
                passedChecks = false
                message = rearMessage
            end
        end
    end

    if not passedChecks then
        SendNotification(message, "error")
        isFishing = false
        return
    end

    if config.BaitItem then
        RemoveItem(config.BaitItem, 1)
    end

    SendNotification("Starting Deep Sea Fishing...", "info")
    isFishing = true

    if deepSeaMethod == 'net' then
        DebugPrint('Starting net deployment (animation skipped).')
        local netPropModel = config.NetPropModel
        RequestModel(netPropModel)
        while not HasModelLoaded(netPropModel) do
            Wait(0)
        end

        netDeployedHandle = CreateObject(netPropModel, 0, 0, 0, true, true, true)
        local attachmentOffset = vector3(0.0, -12.5, -0.5)
        AttachEntityToEntity(netDeployedHandle, deepSeaBoatEntity, 0, attachmentOffset.x, attachmentOffset.y, attachmentOffset.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        
        DebugPrint('Net prop created and ATTACHED to boat. Rope attachment skipped as per user request.')
        ClearPedTasks(PlayerPed)
        SendNotification("Net deployed! Re-enter your boat and un-anchor to start sailing.", "info")
        isAwaitingNetSailStart = true
        netBoatEntity = deepSeaBoatEntity
        isFishing = false
        local netBoatNetworkId = NetworkGetNetworkIdFromEntity(deepSeaBoatEntity)
        TriggerServerEvent('ts-fishing:server:setPlayersNetBoat', netBoatNetworkId)
        DebugPrint('Client informed server about netBoatEntity with Network ID: ' .. tostring(netBoatNetworkId))

    elseif deepSeaMethod == 'pot' then
        local animDict = 'random@burial'
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(0)
        end
        TaskPlayAnim(PlayerPed, animDict, 'a_burial', 1.0, -1.0, -1, 48, 0, 0, 0, 0)
        DebugPrint('Starting pot deployment animation.')

        local minigameResult = StartMinigame('deepsea', deepSeaMethod)
        ClearPedTasks(PlayerPed)
        if minigameResult then
            SendNotification("Pot installed successfully!", "success")
            TriggerServerEvent('ts-fishing:server:deployPot', GetRearOfBoatCoords(deepSeaBoatEntity, config.PotDeployOffset), GetEntityHeading(deepSeaBoatEntity), Config.deepsea.PotMaxCatches)
        else
            SendNotification("Pot installation failed!", "error")
        end
        isFishing = false
    end
end

local function IsAnyFishingActive()
    if isFishing or isNetDeployed or isNetReadyForCollection or isAwaitingNetSailStart then
        SendNotification("You are already busy with a fishing activity!", "error")
        DebugPrint('Fishing attempt blocked: Already busy.')
        return true
    end
    return false
end

local function CreateFishingZones()
    DebugPrint('Attempting to create fishing zones...')

    for fishingTypeKey, data in pairs(Config) do
        if type(data) == 'table' and data.Zones and Config.FishTypes[fishingTypeKey] then
            DebugPrint('Processing config for fishing type: ' .. fishingTypeKey)
            local subZonesForCombo = {}
            for i, individualZoneData in ipairs(data.Zones) do
                local subZone = nil
                local options = {
                    debugPoly = Config.Debugging,
                    minZ = individualZoneData.minZ,
                    maxZ = individualZoneData.maxZ,
                    name = fishingTypeKey .. "_" .. individualZoneData.type .. "_" .. i
                }

                if individualZoneData.type == 'circle' then
                    if CircleZone then
                        subZone = CircleZone:Create(individualZoneData.coords, individualZoneData.radius, options)
                        DebugPrint('Created CircleZone for ' .. fishingTypeKey .. ' at ' .. tostring(individualZoneData.coords) .. ' (Radius: ' .. individualZoneData.radius .. ')')
                    else
                        DebugPrint('Skipped CircleZone creation: Global CircleZone is NIL.')
                    end
                elseif individualZoneData.type == 'box' then
                    if BoxZone then
                        options.heading = individualZoneData.heading
                        subZone = BoxZone:Create(individualZoneData.coords, individualZoneData.length, individualZoneData.width, options)
                        DebugPrint('Created BoxZone for ' .. fishingTypeKey .. ' at ' .. tostring(individualZoneData.coords) .. ' (Length: ' .. individualZoneData.length .. ', Width: ' .. individualZoneData.width .. ', Heading: ' .. tostring(individualZoneData.heading) .. ')')
                    else
                        DebugPrint('Skipped BoxZone creation: Global BoxZone is NIL.')
                    end
                elseif individualZoneData.type == 'poly' then
                    if PolyZone then
                        subZone = PolyZone:Create(individualZoneData.points, options)
                        DebugPrint('Created PolyZone (polygon) for ' .. fishingTypeKey .. ' with ' .. #individualZoneData.points .. ' points.')
                    else
                        DebugPrint('Skipped PolyZone (polygon) creation: Global PolyZone is NIL.')
                    end
                else
                    DebugPrint('WARNING: Unknown zone type in config for ' .. fishingTypeKey .. ': ' .. individualZoneData.type)
                end

                if subZone then
                    table.insert(subZonesForCombo, subZone)
                else
                    DebugPrint('ERROR: Sub-zone creation failed for ' .. individualZoneData.type .. ' in ' .. fishingTypeKey .. '. SubZone object is NIL.')
                end
            end

            if ComboZone then
                local mainComboZone = ComboZone:Create(subZonesForCombo, {
                    debugPoly = Config.Debugging,
                    name = fishingTypeKey .. "_Combo",
                })
                createdZones[fishingTypeKey] = {
                    zone = mainComboZone,
                    fishingType = fishingTypeKey,
                    isPlayerInside = false
                }
                DebugPrint('Successfully created ComboZone for ' .. fishingTypeKey .. ' with ' .. #subZonesForCombo .. ' sub-zones. DebugPoly set to: ' .. tostring(Config.Debugging))
            else
                DebugPrint('ERROR: Skipped ComboZone creation for ' .. fishingTypeKey .. ': Global ComboZone is NIL.')
            end
        else
            DebugPrint('Skipping non-zone or invalid config entry: ' .. fishingTypeKey)
        end
    end
    DebugPrint('Finished attempting to create all fishing zones.')
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DebugPrint('Resource ' .. resourceName .. ' started. Calling CreateFishingZones()...')
        CreateFishingZones()
        DebugPrint('CreateFishingZones() call finished.')
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    CreateFishingZones()
    TriggerServerEvent('ts-fishing:server:syncPots')
end)

CreateThread(function()
    while true do
        local PlayerPed = PlayerPedId()
        local PlayerCoords = GetEntityCoords(PlayerPed)
        local sleepTime = 500

        local inAnyFishingZoneThisTick = false
        local activeFishingTypeThisTick = nil

        for fishingTypeKey, zoneEntry in pairs(createdZones) do
            local zone = zoneEntry.zone

            if zone and zone:isPointInside(PlayerCoords) then
                inAnyFishingZoneThisTick = true
                activeFishingTypeThisTick = fishingTypeKey

                if not zoneEntry.isPlayerInside then
                    DebugPrint('Player HAS ENTERED ' .. fishingTypeKey .. ' zone.')
                    zoneEntry.isPlayerInside = true
                    SendNotification(
                        string.format("Entered %s zone.", string.gsub(fishingTypeKey, "^%l", string.upper)),
                        "info"
                    )
                end
                sleepTime = 5
                break
            else
                if zoneEntry.isPlayerInside then
                    DebugPrint('Player HAS LEFT ' .. fishingTypeKey .. ' zone.')
                    zoneEntry.isPlayerInside = false
                    if isFishing or isNetDeployed or isNetReadyForCollection or isAwaitingNetSailStart then
                        SendNotification("You left the fishing zone! Fishing cancelled.", "error")
                        StopFishing()
                    end
                end
            end
        end

        currentZoneType = activeFishingTypeThisTick

        if not inAnyFishingZoneThisTick then
            Wait(5)
        end

        Wait(sleepTime)
    end
end)

RegisterNetEvent('ts-fishing:client:startTraditionalFishing', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startTraditionalFishing event.')
    if IsAnyFishingActive() then return end
    StartTraditionalFishingProcess(playerPed)
end)

RegisterNetEvent('ts-fishing:client:startClamming', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startClamming event.')
    if IsAnyFishingActive() then return end
    StartClammingProcess(playerPed)
end)

RegisterNetEvent('ts-fishing:client:startDeepSeaFishing', function(deepSeaMethod)
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startDeepSeaFishing event with deepSeaMethod: ' .. tostring(deepSeaMethod))
    if IsAnyFishingActive() then return end
    StartDeepSeaFishingProcess(playerPed, deepSeaMethod)
end)

RegisterNetEvent('ts-fishing:client:playerEnteredNetBoat', function()
    DebugPrint('Client received ts-fishing:client:playerEnteredNetBoat event. Setting hasPlayerReEnteredNetBoat to true.')
    hasPlayerReEnteredNetBoat = true
    SendNotification("You are now in your fishing boat. Un-anchor to start sailing!", "info")
end)

RegisterNetEvent('ts-fishing:client:syncAnchorStatus', function(vehicleNetworkId, isAnchoredStatus)
    local vehicleObj = NetToVeh(vehicleNetworkId)
    if DoesEntityExist(vehicleObj) then
        syncedAnchoredBoats[vehicleNetworkId] = isAnchoredStatus
        DebugPrint(string.format('Client synced anchor status for vehicle %s (NetID: %s) to %s', GetDisplayNameFromVehicleModel(GetEntityModel(vehicleObj)), tostring(vehicleNetworkId), tostring(isAnchoredStatus)))
    else
        DebugPrint(string.format('Client received anchor status for non-existent vehicle NetID: %s. Status: %s', tostring(vehicleNetworkId), tostring(isAnchoredStatus)))
    end
end)

RegisterNetEvent('ts-fishing:client:createNetPropVisual', function(netId, netBoatNetworkId, netPropModel, attachmentOffsetX, attachmentOffsetY, attachmentOffsetZ)
    local boatObj = NetToVeh(netBoatNetworkId)
    if not DoesEntityExist(boatObj) then
        DebugPrint(string.format('Client: Cannot create net prop %s, boat %s does not exist.', netId, netBoatNetworkId), 'error')
        return
    end

    if syncedNetProps[netId] and DoesEntityExist(syncedNetProps[netId].netObj) then
        DebugPrint(string.format('Client: Net prop %s already exists, skipping creation.', netId))
        return
    end

    RequestModel(netPropModel)
    while not HasModelLoaded(netPropModel) do
        Wait(0)
    end

    local netObj = CreateObject(netPropModel, 0, 0, 0, true, true, true)
    AttachEntityToEntity(netObj, boatObj, 0, attachmentOffsetX, attachmentOffsetY, attachmentOffsetZ, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    
    syncedNetProps[netId] = {
        netObj = netObj,
        boatObj = boatObj,
        boatNetId = netBoatNetworkId
    }
    DebugPrint(string.format('Client: Created synced net prop %s for boat %s (NetID: %s)', netId, GetDisplayNameFromVehicleModel(GetEntityModel(boatObj)), netBoatNetworkId))
end)

RegisterNetEvent('ts-fishing:client:removeNetPropVisual', function(netId)
    if syncedNetProps[netId] and DoesEntityExist(syncedNetProps[netId].netObj) then
        DeleteObject(syncedNetProps[netId].netObj)
        syncedNetProps[netId] = nil
        DebugPrint(string.format('Client: Removed synced net prop %s.', netId))
    else
        DebugPrint(string.format('Client: Attempted to remove non-existent synced net prop %s.', netId))
    end
end)

CreateThread(function()
    local slowdownFactor = 0.95
    local minSpeedThreshold = 0.05

    while true do
        for vehicleNetworkId, isAnchoredStatus in pairs(syncedAnchoredBoats) do
            if isAnchoredStatus then
                local vehicleObj = NetToVeh(vehicleNetworkId)
                if DoesEntityExist(vehicleObj) and GetVehicleClass(vehicleObj) == 14 and IsEntityInWater(vehicleObj) then
                    local currentVelocity = GetEntityVelocity(vehicleObj)
                    local horizontalSpeed = Vdist(0.0, 0.0, 0.0, currentVelocity.x, currentVelocity.y, 0.0)

                    if horizontalSpeed > minSpeedThreshold then
                        SetEntityVelocity(vehicleObj, currentVelocity.x * slowdownFactor, currentVelocity.y * slowdownFactor, currentVelocity.z)
                    else
                        SetEntityVelocity(vehicleObj, 0.0, 0.0, currentVelocity.z)
                    end
                else
                    syncedAnchoredBoats[vehicleNetworkId] = nil
                    DebugPrint(string.format('Client: Removed invalid synced anchor entry for NetID: %s', tostring(vehicleNetworkId)))
                end
            end
        end
        Wait(0)
    end
end)

CreateThread(function()
    local attachmentOffset = vector3(0.0, -12.5, -0.5)

    while true do
        for netId, netData in pairs(syncedNetProps) do
            if DoesEntityExist(netData.netObj) and DoesEntityExist(netData.boatObj) then
                AttachEntityToEntity(netData.netObj, netData.boatObj, 0, attachmentOffset.x, attachmentOffset.y, attachmentOffset.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            else
                if DoesEntityExist(netData.netObj) then DeleteObject(netData.netObj) end
                syncedNetProps[netId] = nil
                DebugPrint(string.format('Client: Removed invalid synced net prop entry for ID: %s (object missing).', netId))
            end
        end
        Wait(1000)
    end
end)

RegisterNetEvent('ts-fishing:client:createPotProps', function(potsData)
    local dataToProcess = {}
    if type(potsData) == 'table' and potsData.id then
        table.insert(dataToProcess, potsData)
    elseif type(potsData) == 'table' then
        dataToProcess = potsData
    end

    for _, potInfo in ipairs(dataToProcess) do
        if not clientActivePots[potInfo.id] then
            DebugPrint('Client received request to create pot props for ID: ' .. potInfo.id)

            RequestModel(potInfo.potModel)
            RequestModel(potInfo.buoyModel)
            while not HasModelLoaded(potInfo.potModel) do Wait(0) end

            local waterZ = GetWaterHeight(potInfo.coords.x, potInfo.coords.y, potInfo.coords.z)
            local potCoords = vector3(potInfo.coords.x, potInfo.coords.y, waterZ - 1.0)
            local buoyCoords = vector3(potInfo.coords.x, potInfo.coords.y, waterZ + 0.5)

            local createdPot = CreateObject(potInfo.potModel, potCoords.x, potCoords.y, potCoords.z, true, true, true)
            SetEntityAsMissionEntity(createdPot, true, true)
            SetEntityCollision(createdPot, true, true)
            SetEntityHasGravity(createdPot, true)
            ActivatePhysics(createdPot)
            PlaceObjectOnGroundProperly(createdPot)
            SetEntityHeading(createdPot, potInfo.heading)

            local createdBuoy = CreateObject(potInfo.buoyModel, buoyCoords.x, buoyCoords.y, buoyCoords.z, true, true, true)
            SetEntityAsMissionEntity(createdBuoy, true, true)
            SetEntityCollision(createdBuoy, true, true)
            SetEntityHasGravity(createdBuoy, false)
            PlaceObjectOnGroundProperly(createdBuoy)
            SetEntityHeading(createdBuoy, potInfo.heading)

            clientActivePots[potInfo.id] = {
                potObj = createdPot,
                buoyObj = createdBuoy
            }
            DebugPrint('Created client-side pot ' .. potInfo.id .. ' at ' .. tostring(potCoords))
        else
            DebugPrint('Pot ' .. potInfo.id .. ' already exists client-side.')
        end
    end
end)

RegisterNetEvent('ts-fishing:client:removePotProps', function(potId)
    if clientActivePots[potId] then
        DebugPrint('Client received request to remove pot props for ID: ' .. potId)
        if DoesEntityExist(clientActivePots[potId].potObj) then
            DeleteObject(clientActivePots[potId].potObj)
        end
        if DoesEntityExist(clientActivePots[potId].buoyObj) then
            DeleteObject(clientActivePots[potId].buoyObj)
        end
        clientActivePots[potId] = nil
        DebugPrint('Removed client-side pot ' .. potId)
    else
        DebugPrint('Client received request to remove non-existent pot: ' .. potId)
    end
end)

local isBoatAnchored = false
local anchorThread = nil

RegisterCommand("anchor", function(source, args, rawCommand)
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if vehicle == 0 then
        SendNotification("You must be in a boat to use the anchor!", "error")
        DebugPrint('Anchor command failed: Not in a vehicle.')
        return
    end

    local vehicleClass = GetVehicleClass(vehicle)
    if vehicleClass ~= 14 then
        SendNotification("You can only drop anchor from a boat!", "error")
        DebugPrint('Anchor command failed: Not a boat (class: ' .. vehicleClass .. ').')
        return
    end

    if not IsEntityInWater(vehicle) then
        SendNotification("Your boat must be in water to drop anchor!", "error")
        DebugPrint('Anchor command failed: Boat not in water.')
        return
    end

    isBoatAnchored = not isBoatAnchored

    if isBoatAnchored then
        SendNotification("Anchor dropped! Boat is now slowing down.", "info")
        DebugPrint('Anchor dropped. Initiating anchor hold/slowdown thread.')

        if anchorThread and Citizen.DoesThreadExist(anchorThread) then
            Citizen.TerminateThread(anchorThread)
            anchorThread = nil
        end

        local anchoredVehicle = vehicle 
        local anchoredVehicleNetworkId = VehToNet(anchoredVehicle)

        TriggerServerEvent('ts-fishing:server:setBoatAnchorStatus', anchoredVehicleNetworkId, true)

        anchorThread = Citizen.CreateThread(function()
            local slowdownFactor = 0.95
            local minSpeedThreshold = 0.05

            while isBoatAnchored do
                if DoesEntityExist(anchoredVehicle) and GetVehicleClass(anchoredVehicle) == 14 and IsEntityInWater(anchoredVehicle) then
                    local currentVelocity = GetEntityVelocity(anchoredVehicle)
                    local horizontalSpeed = Vdist(0.0, 0.0, 0.0, currentVelocity.x, currentVelocity.y, 0.0)

                    if horizontalSpeed > minSpeedThreshold then
                        SetEntityVelocity(anchoredVehicle, currentVelocity.x * slowdownFactor, currentVelocity.y * slowdownFactor, currentVelocity.z)
                    else
                        SetEntityVelocity(anchoredVehicle, 0.0, 0.0, currentVelocity.z)
                    end
                else
                    DebugPrint('Anchor thread running, but no valid boat to apply force to. Anchor state remains: ' .. tostring(isBoatAnchored))
                end
                Citizen.Wait(0)
            end
            DebugPrint('Anchor hold thread stopped.')
            anchorThread = nil
        end)
    else
        SendNotification("Anchor raised! You can now drive again.", "info")
        DebugPrint('Anchor raised. Stopping anchor hold thread.')
        local vehicleNetworkId = VehToNet(vehicle)
        TriggerServerEvent('ts-fishing:server:setBoatAnchorStatus', vehicleNetworkId, false)
    end
end, false)

AddEventHandler('gameEventTriggered', function(event, data)
	if event ~= 'CEventNetworkEntityDamage' then return end
	local victim, victimDied = data[1], data[4]
	if not IsPedAPlayer(victim) then return end
	local player = PlayerId()
	if victimDied and NetworkGetPlayerIndexFromPed(victim) == player and (IsPedDeadOrDying(victim, true) or IsPedFatallyInjured(victim))  then
        if isFishing or isNetDeployed or isNetReadyForCollection or isAwaitingNetSailStart then
            DebugPrint('Player died/fatally injured. Forcing all fishing activities to stop.')
            StopFishing()
        end
	end
end)
