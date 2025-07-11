-- antisocialrider/ts-fishing/ts-fishing-30c79791400a44ebf78a174946a71c48107efe47/client/main.lua
local QBCore = exports['qb-core']:GetCoreObject()

local createdZones = {}
local isFishing = false -- General flag, true when *any* fishing animation/minigame is active
local fishingRodProp = nil
local clammingShovelProp = nil
local clammingDirtProp = nil

-- NEW GLOBAL VARIABLES for Deep Sea Net Fishing
local isNetDeployed = false -- True when net prop and rope are active and player needs to sail
local netDeployedHandle = nil -- Object handle for the deployed net
local netRopeHandle = nil -- Rope handle
local netBoatEntity = nil -- Reference to the boat entity used for net deployment
local netStartCoords = nil -- Coordinates where the net was initially deployed
local isNetReadyForCollection = false -- True when net has sailed enough and is ready to be collected
local netCollectionZone = nil -- NEW: PolyZone for net collection prompt

-- Pot props are now managed in clientActivePots table
local potProp = nil
local buoyProp = nil

-- NEW: Table to store locally created pot and buoy objects
local clientActivePots = {} -- { potId = { potObj = object, buoyObj = object } }

-- Global variable to store the current zone type the player is in.
local currentZoneType = nil

local function DebugPrint(msg)
    if Config.Debugging then
        print('^3[Fishing Debug]^0 ' .. msg)
    end
end
RegisterNetEvent('ts-fishing:Debugging', DebugPrint)

-- MODIFIED: DisplayHelpText to store the current text
local function DisplayHelpText(str)
	SetTextComponentFormat("STRING")
	AddTextComponentString(str)
	DisplayHelpTextFromStringLabel(0, 0, 1, -1)
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

-- MODIFIED: StartMinigame, removed deepsea_nui_key type
local function StartMinigame(fishingType, deepseaType)
    if fishingType == 'traditional' then
        return exports.peuren_minigames:StartPressureBar(40, 20)
    elseif fishingType == 'clamming' then
        return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
    elseif fishingType == 'deepsea' and deepseaType == 'pot' then -- Only pot uses this minigame
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

    -- TEMPORARY DEBUG: Visualize the probe's spawn point (KEEP THIS FOR TESTING!)
    --DrawMarker(1, probeX, probeY, probeZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.2, 0.2, 255, 0, 0, 100, false, true, 2, false, nil, nil, false)
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
        -- Check for either NetItem OR PotItem
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

        -- Anchor check is only relevant when we're checking for anchored boats, not just any boat for deployment.
        -- We want the player to be able to *deploy* from a moving boat, then the boat would be sailed.
        -- The anchor check here is used by the initial deepsea checks to ensure they are near their boat.
        -- The actual anchoring for collection will be done by the script.
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

-- NEW FUNCTION: Destroys the net collection zone
local function DestroyNetCollectionZone()
    if netCollectionZone then
        netCollectionZone:destroy()
        netCollectionZone = nil
        DebugPrint("Net collection zone destroyed.")
    end
end

-- NEW FUNCTION: Centralized logic to stop net fishing
local function StopNetFishing()
    local PlayerPed = PlayerPedId()
    ClearPedTasks(PlayerPed)

    if netDeployedHandle and DoesEntityExist(netDeployedHandle) then
        DeleteObject(netDeployedHandle)
        netDeployedHandle = nil
        DebugPrint('Deleted net prop.')
    end
    if netRopeHandle and DoesRopeExist(netRopeHandle) then
        DeleteRope(netRopeHandle)
        netRopeHandle = nil
        DebugPrint('Deleted net rope.')
    end

    netBoatEntity = nil
    netStartCoords = nil
    isNetDeployed = false
    isNetReadyForCollection = false
    isFishing = false -- Reset general fishing state
    DestroyNetCollectionZone() -- Ensure zone is destroyed on any stop/cancellation
    SendNotification("Net fishing stopped.", "info")
    DebugPrint('Net fishing state reset.')
end

-- NEW FUNCTION: Stops Traditional Fishing and cleans up
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

-- NEW FUNCTION: Stops Clamming and cleans up
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

-- MODIFIED: Centralized logic to stop ALL fishing activities (including traditional/clamming/pot)
local function StopFishing()
    -- Only proceed if any fishing activity is currently active
    if not isFishing and not isNetDeployed and not isNetReadyForCollection then
        DebugPrint('StopFishing called but no active fishing. Exiting.')
        return
    end

    DebugPrint('Stopping all fishing processes...')
    ClearPedTasks(PlayerPedId()) -- Clear tasks for current ped

    StopTraditionalFishing()
    StopClamming()
    StopNetFishing()

    -- Pot props cleanup is handled by clientActivePots table and server events,
    -- but if potProp/buoyProp globals were set for the initiating player:
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

    -- General anim dicts that might have been loaded
    RemoveAnimDict('mini@tennis')
    RemoveAnimDict('amb@world_human_stand_fishing@idle_a')
    RemoveAnimDict('random@burial')
    DebugPrint('Removed animation dictionaries.')

    isFishing = false -- Ensure this general flag is reset
    SendNotification("Fishing stopped.", "info")
    DebugPrint('Master fishing state reset.')
end


-- Helper to calculate a position at the back of the boat
local function GetRearOfBoatCoords(boatEntity, offset)
    local coords = GetEntityCoords(boatEntity)
    local heading = GetEntityHeading(boatEntity)
    local rearX = coords.x - math.sin(math.rad(heading)) * offset.y
    local rearY = coords.y + math.cos(math.rad(heading)) * offset.y
    local rearZ = coords.z + offset.z -- Z offset is relative to boat's Z
    return vector3(rearX, rearY, rearZ)
end

-- NEW FUNCTION: Check if player is near the back of the boat
local function CheckPlayerNearBoatRear(PlayerPed, boatEntity, proximityThreshold)
    local playerCoords = GetEntityCoords(PlayerPed)
    local boatCoords = GetEntityCoords(boatEntity)
    -- This is a simplistic 'rear' check, ideally would check a specific bone or more refined area
    local rearOfBoat = GetRearOfBoatCoords(boatEntity, vector3(0.0, -3.0, 0.0)) -- 3m behind boat (adjusted from original for a better point)
    local distance = GetDistanceBetweenCoords(playerCoords, rearOfBoat, true)
    DebugPrint(string.format("Player distance to boat rear: %.2f (Threshold: %.2f)", distance, proximityThreshold))
    return distance <= proximityThreshold, "You need to be near the back of the boat to deploy this!"
end

-- NEW FUNCTION: Logic for performing the net collection
local function PerformNetCollection()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local config = Config['deepsea']

    if not isNetReadyForCollection then
        SendNotification("No net ready for collection.", "error")
        return
    end

    local currentBoat = GetVehiclePedIsIn(playerPed, false)
    if currentBoat == 0 then
        SendNotification("You must be in your boat to collect the net.", "error")
        return
    end

    -- Check if player is still within the collection zone
    if netCollectionZone and not netCollectionZone:isPointInside(playerCoords) then
        SendNotification("You are no longer in the collection area.", "error")
        return
    end

    SendNotification("Collecting net...", "info")
    -- Play collection animation (reuse a_burial or similar)
    local animDict = 'random@burial'
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    TaskPlayAnim(playerPed, animDict, 'a_burial', 1.0, -1.0, -1, 48, 0, 0, 0, 0)
    Wait(5000) -- Simulate collection time
    ClearPedTasks(playerPed)

    -- Calculate catch - simplified: single item with catch chance
    local fishConfig = Config.FishTypes.deepsea
    if math.random() < fishConfig.CatchChance then
        local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
        AddItem(caughtItem, 1)
        DebugPrint('Successfully caught: ' .. caughtItem .. ' from net collection.')
    else
        SendNotification("The net came up empty this time.", "info")
        DebugPrint('Net collection: No catch.')
    end

    StopNetFishing() -- Clean up net props and reset flags
    DestroyNetCollectionZone() -- Destroy the zone after collection
end

-- NEW FUNCTION: Creates the net collection zone
local function CreateNetCollectionZone()
    local config = Config['deepsea']
    local playerPed = PlayerPedId()
    local currentBoat = GetVehiclePedIsIn(playerPed, false)

    if not DoesEntityExist(currentBoat) or currentBoat == 0 then
        DebugPrint("Failed to create collection zone: No valid boat found.")
        return
    end

    local rearOfBoatCoords = GetRearOfBoatCoords(currentBoat, config.PotDeployOffset) -- Reuse PotDeployOffset for collection spot

    if BoxZone then
        netCollectionZone = BoxZone:Create(
            rearOfBoatCoords,
            2.0, -- length
            2.0, -- width
            {
                heading = GetEntityHeading(currentBoat),
                minZ = rearOfBoatCoords.z - 2.0,
                maxZ = rearOfBoatCoords.z + 2.0,
                debugPoly = Config.Debugging,
                name = "NetCollectionZone"
            }
        )

        netCollectionZone:onPointInOut(function(isPointInside)
            if isPointInside and isNetReadyForCollection then
                DisplayHelpText("Press ~INPUT_CONTEXT~ to collect fishing net")
                -- Start a thread to listen for 'E' key press
                Citizen.CreateThread(function()
                    while isNetReadyForCollection and netCollectionZone:isPointInside(GetEntityCoords(PlayerPedId())) do
                        Wait(0)
                        if IsControlJustReleased(0, 38) then -- INPUT_CONTEXT (E key)
                            PerformNetCollection() -- Call the collection logic
                            break -- Exit this key-listening loop
                        end
                    end
                end)
            end
        end)
        DebugPrint("Net collection zone created.")
    else
        DebugPrint("BoxZone constructor is NIL, cannot create collection zone.")
        SendNotification("Error: Fishing system components missing (Zone).", "error")
    end
end


-- NEW THREAD: Net Fishing Dragging Logic
CreateThread(function()
    while true do
        Wait(0) -- Yield to prevent freezing

        if isNetDeployed and netBoatEntity and DoesEntityExist(netBoatEntity) then
            local playerPed = PlayerPedId()
            local currentBoatCoords = GetEntityCoords(netBoatEntity)
            local config = Config['deepsea']

            if GetVehiclePedIsIn(playerPed, false) ~= netBoatEntity then
                SendNotification("You left the boat! Net fishing cancelled.", "error")
                StopNetFishing()
                -- No break needed, the `if` condition will become false and `Wait(500)` will be hit.
            else
                local distanceSailed = GetDistanceBetweenCoords(netStartCoords, currentBoatCoords, true)
                DisplayHelpText(string.format("~b~Net Fishing: ~w~Sail ~y~%.1fm~w~/~g~%.1fm~w~. Press ~INPUT_CELLPHONE_CANCEL~ to cancel.", distanceSailed, config.NetMinigameSailDistance))

                DisplayHelpText("~INPUT_CELLPHONE_CANCEL~ or ~INPUT_CREATOR_LT~ Cancel Fishing")
                if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then -- 'X' keys
                    SendNotification("Net fishing cancelled by player.", "info")
                    StopNetFishing()
                    -- No break, similar to leaving boat.
                end

                if distanceSailed >= config.NetMinigameSailDistance then
                    SendNotification("Net has been dragged far enough! Anchoring boat and preparing for collection...", "info")
                    -- Stop boat movement horizontally
                    local currentVelocity = GetEntityVelocity(netBoatEntity)
                    SetEntityVelocity(netBoatEntity, 0.0, 0.0, currentVelocity.z)

                    isNetDeployed = false -- Net is no longer "being dragged"
                    isNetReadyForCollection = true -- Now it's ready for collection
                    CreateNetCollectionZone() -- NEW: Create the collection zone
                    netBoatEntity = nil -- Clear reference as it's now 'ready' and not actively dragging
                    netStartCoords = nil
                end
            end
        else
            Wait(500) -- Sleep when net fishing is not active
        end
    end
end)

-- NEW FUNCTION: Starts Traditional Fishing Process
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
        isFishing = false -- Reset general fishing state if checks fail before starting
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
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then -- 'X' key
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

-- NEW FUNCTION: Starts Clamming Process
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
        if currentZoneType ~= 'clamming' then -- Clamming requires being in a specific zone
            passedChecks = false
            message = "You need to be in a clamming zone to clam!"
        end
    end

    if not passedChecks then
        SendNotification(message, "error")
        isFishing = false
        return
    end

    if config.BaitItem then -- Clamming does not use bait, this will effectively be skipped
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
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then -- 'X' key
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

-- NEW FUNCTION: Starts Deep Sea Fishing Process
local function StartDeepSeaFishingProcess(PlayerPed, deepSeaMethod)
    local config = Config['deepsea']
    local fishConfig = Config.FishTypes['deepsea']
    local message = ""
    local passedChecks = true
    local deepSeaBoatEntity = nil
    local playerCoords = GetEntityCoords(PlayerPed)

    -- Initial deepsea checks
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
        local animDict = 'amb@world_human_stand_fishing@idle_a'
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(0)
        end
        TaskPlayAnim(PlayerPed, animDict, 'idle_c', 1.0, -1.0, -1, 11, 0, 0, 0, 0)
        DebugPrint('Starting net deployment animation.')
        -- Add cancellation check during initial animation wait

        local netPropModel = config.NetPropModel
        RequestModel(netPropModel)
        while not HasModelLoaded(netPropModel) do
            Wait(0)
        end

        netDeployedHandle = CreateObject(netPropModel, playerCoords.x, playerCoords.y, playerCoords.z - 5.0, true, true, true)
        SetEntityCoordsNoOffset(netDeployedHandle, playerCoords.x, playerCoords.y, GetWaterHeight(playerCoords.x, playerCoords.y, playerCoords.z), false, false, false)
        SetEntityCollision(netDeployedHandle, false, false)
        SetEntityHasGravity(netDeployedHandle, true)
        ActivatePhysics(netDeployedHandle)

        -- Simplied rope attachment, explicitly using root bone (0)
        netRopeHandle = AddRope(playerCoords.x, playerCoords.y, playerCoords.z, config.RopeLength, 0.5, 0.05, 0, 0, 0, 0, 0, "rope_tx", "rope_tx_01")
        Wait(100) -- Allow rope to be created
        if netRopeHandle then
            -- Attach to the root bone (0) of both entities
            AttachEntitiesToRope(netRopeHandle, deepSeaBoatEntity, netDeployedHandle, 0, 0, config.RopeAttachOffset.x, config.RopeAttachOffset.y, config.RopeAttachOffset.z, 0.0, 0.0, 0.0, true)
            DebugPrint('Net prop created and attached to boat with rope (using root bones).')
            ClearPedTasks(PlayerPed)
            SendNotification("Net deployed! Start sailing your boat to drag the net.", "info")
            isNetDeployed = true
            netBoatEntity = deepSeaBoatEntity
            netStartCoords = GetEntityCoords(deepSeaBoatEntity)
            isFishing = false -- Player is now free to drive, not in a static fishing state
        else
            SendNotification("Failed to deploy net (rope error).", "error")
            StopNetFishing()
            return
        end

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

-- NEW FUNCTION: Checks if any fishing activity is currently active
local function IsAnyFishingActive()
    if isFishing or isNetDeployed or isNetReadyForCollection then
        SendNotification("You are already busy with a fishing activity!", "error")
        DebugPrint('Fishing attempt blocked: Already busy.')
        return true
    end
    return false
end


-- Function to create PolyZone objects from the config
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

-- Call CreateFishingZones when the resource starts
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DebugPrint('Resource ' .. resourceName .. ' started. Calling CreateFishingZones()...')
        CreateFishingZones()
        DebugPrint('CreateFishingZones() call finished.')
    end
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    CreateFishingZones()
    -- Request active pots from server upon player load/spawn
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
                    if isFishing or isNetDeployed or isNetReadyForCollection then -- Check all active states
                        SendNotification("You left the fishing zone! Fishing cancelled.", "error")
                        StopFishing()
                    end
                end
            end
        end

        currentZoneType = activeFishingTypeThisTick

        if not inAnyFishingZoneThisTick then
            sleepTime = 500
        end

        Wait(sleepTime)
    end
end)

-- NEW EVENT: Start Traditional Fishing
RegisterNetEvent('ts-fishing:client:startTraditionalFishing', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startTraditionalFishing event.')
    if IsAnyFishingActive() then return end
    StartTraditionalFishingProcess(playerPed)
end)

-- NEW EVENT: Start Clamming
RegisterNetEvent('ts-fishing:client:startClamming', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startClamming event.')
    if IsAnyFishingActive() then return end
    StartClammingProcess(playerPed)
end)

-- NEW EVENT: Start Deep Sea Fishing (net or pot)
RegisterNetEvent('ts-fishing:client:startDeepSeaFishing', function(deepSeaMethod)
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startDeepSeaFishing event with deepSeaMethod: ' .. tostring(deepSeaMethod))
    if IsAnyFishingActive() then return end
    StartDeepSeaFishingProcess(playerPed, deepSeaMethod)
end)


-- NEW Client Event: Creates pot props from server data
RegisterNetEvent('ts-fishing:client:createPotProps', function(potsData)
    -- potsData can be a single pot or a table of pots (for initial sync)
    local dataToProcess = {}
    if type(potsData) == 'table' and potsData.id then -- single pot object structure
        table.insert(dataToProcess, potsData)
    elseif type(potsData) == 'table' then -- table of pot objects for initial sync
        dataToProcess = potsData
    end

    for _, potInfo in ipairs(dataToProcess) do
        if not clientActivePots[potInfo.id] then -- Only create if not already existing locally
            DebugPrint('Client received request to create pot props for ID: ' .. potInfo.id)

            -- Request models
            RequestModel(potInfo.potModel)
            RequestModel(potInfo.buoyModel)
            while not HasModelLoaded(potInfo.potModel) do Wait(0) end

            local waterZ = GetWaterHeight(potInfo.coords.x, potInfo.coords.y, potInfo.coords.z)
            local potCoords = vector3(potInfo.coords.x, potInfo.coords.y, waterZ - 1.0) -- Spawn slightly below water
            local buoyCoords = vector3(potInfo.coords.x, potInfo.coords.y, waterZ + 0.5) -- Buoy slightly above water

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
            SetEntityHasGravity(createdBuoy, false) -- Buoys typically float
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

-- NEW Client Event: Removes pot props by ID
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


-- Anchoring
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
    if vehicleClass ~= 14 then -- 14 is the vehicle class for boats
        SendNotification("You can only drop anchor from a boat!", "error")
        DebugPrint('Anchor command failed: Not a boat (class: ' .. vehicleClass .. ').')
        return
    end

    if not IsEntityInWater(vehicle) then
        SendNotification("Your boat must be in water to drop anchor!", "error")
        DebugPrint('Anchor command failed: Boat not in water.')
        return
    end

    -- If a net is currently being dragged, prevent manual anchoring interference.
    if isNetDeployed then
        SendNotification("You cannot manually anchor while dragging a net!", "error")
        DebugPrint('Anchor command blocked: Net is currently deployed.')
        return
    end


    isBoatAnchored = not isBoatAnchored

    if isBoatAnchored then
        SendNotification("Anchor dropped! Boat is now stationary horizontally.", "info")
        DebugPrint('Anchor dropped. Initiating anchor hold thread.')

        -- TaskLeaveVehicle is probably not desired here, as player might want to stay in vehicle.
        -- TaskLeaveVehicle(playerPed, vehicle, 0)

        anchorThread = Citizen.CreateThread(function()
            while isBoatAnchored and DoesEntityExist(vehicle) do
                local currentVelocity = GetEntityVelocity(vehicle)
                local currentZVelocity = currentVelocity.z
                SetEntityVelocity(vehicle, 0.0, 0.0, currentZVelocity) -- Set horizontal velocity to zero
                Citizen.Wait(0)
            end
            DebugPrint('Anchor hold thread stopped.')
            anchorThread = nil
        end)
    else
        SendNotification("Anchor raised! You can now drive again.", "info")
        DebugPrint('Anchor raised. Stopping anchor hold thread.')
    end
end, false)

-- MODIFIED gameEventTriggered HANDLER
AddEventHandler('gameEventTriggered', function(event, data)
	if event ~= 'CEventNetworkEntityDamage' then return end
	local victim, victimDied = data[1], data[4]
	if not IsPedAPlayer(victim) then return end
	local player = PlayerId()
	if victimDied and NetworkGetPlayerIndexFromPed(victim) == player and (IsPedDeadOrDying(victim, true) or IsPedFatallyInjured(victim))  then
        -- STOP FISHING if the player dies or is fatally injured
        if isFishing or isNetDeployed or isNetReadyForCollection then
            DebugPrint('Player died/fatally injured. Forcing all fishing activities to stop.')
            StopFishing()
        end
	end
end)