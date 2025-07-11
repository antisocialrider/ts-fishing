local QBCore = exports['qb-core']:GetCoreObject()

local createdZones = {}
local isFishing = false
local fishingRodProp = nil
local clammingShovelProp = nil
local clammingDirtProp = nil

-- Global variable to store the current zone type the player is in.
-- This will still be updated by the zone checks, but traditional fishing won't strictly rely on it.
local currentZoneType = nil

local function DebugPrint(msg)
    if Config.Debugging then
        print('^3[Fishing Debug]^0 ' .. msg)
    end
end
RegisterNetEvent('ts-fishing:Debugging', DebugPrint)

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

local function StartMinigame(fishingType)
    if fishingType == 'traditional' or fishingType == 'deepsea' then
        return exports.peuren_minigames:StartPressureBar(40, 20)
    elseif fishingType == 'clamming' then
        return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2) --SkillBar(duration(milliseconds or table{min(milliseconds), max(milliseconds)}), width%(number), rounds(number))
    end
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

    -- MODIFIED: Changed the last parameter (isNetwork) from 'true' to 'false'
    local probeObject = CreateObject(model, probeX, probeY, probeZ, false, false, false)
    SetEntityVisible(probeObject, false, false) -- Keep this as false normally, turn to true for debugging
    SetEntityHasGravity(probeObject, true) -- This should now apply correctly
    ActivatePhysics(probeObject)

    local waitTimeForSettle = 7000 -- Keep this at 2000ms or increase if the probe falls from very high
    DebugPrint("AdvancedWaterCheck: Waiting " .. waitTimeForSettle .. "ms for probe to settle.")
    Wait(waitTimeForSettle)
    local inWater = IsEntityInWater(probeObject)
    local actualProbeCoords = GetEntityCoords(probeObject)
    DebugPrint(string.format("AdvancedWaterCheck: After %dms settle: Probe Object ID: %s, IsEntityInWater: %s, Actual Probe Z: %.2f", waitTimeForSettle, tostring(probeObject), tostring(inWater), actualProbeCoords.z))

    DeleteObject(probeObject)
    SetModelAsNoLongerNeeded(model)

    return inWater, actualProbeCoords
end

local function CheckRequiredItems(config)
    if config.RodItem and not HasItem(config.RodItem) then
        DebugPrint('Required item check failed: Missing ' .. config.RodItem)
        return false, "You need a " .. config.RodItem .. "!"
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
    local facingFishableWater, waterHitPos = AdvancedWaterCheck() -- Call your new function
    SendNotification("Checking fishing spot...", "info")

---    local facingFishableWater, waterHitPos = WaterCheck()
    if not facingFishableWater then
        DebugPrint('Traditional fishing location check failed: Not facing fishable water (WaterCheck returned false).')
        return false, "You need to be facing fishable water to traditionally fish!"
    end
    DebugPrint('Traditional fishing location check passed. Water found at ' .. tostring(waterHitPos.x) .. ', ' .. tostring(waterHitPos.y) .. ', ' .. tostring(waterHitPos.z))
    return true, ""
end

-- NEW FUNCTION: Centralized logic to stop fishing
local function StopFishing()
    local PlayerPed = PlayerPedId()
    if not isFishing then
        DebugPrint('StopFishing called but not currently fishing. Exiting.')
        return
    end

    DebugPrint('Stopping fishing process...')
    ClearPedTasks(PlayerPed)

    if fishingRodProp and DoesEntityExist(fishingRodProp) then
        DeleteObject(fishingRodProp)
        fishingRodProp = nil
        DebugPrint('Deleted fishing rod prop.')
    end
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

    RemoveAnimDict('mini@tennis')
    RemoveAnimDict('amb@world_human_stand_fishing@idle_a')
    RemoveAnimDict('random@burial')
    DebugPrint('Removed animation dictionaries.')

    isFishing = false
    SendNotification("Fishing stopped.", "info")
    DebugPrint('Fishing state reset.')
end

local function AttemptFishing(fishingType, PlayerPed)
    isFishing = true
    DebugPrint('Attempting ' .. fishingType .. ' fishing.')
    local config = Config[fishingType]
    local fishConfig = Config.FishTypes[fishingType]
    local message = ""
    local passedChecks = true
    local deepSeaBoatEntity = nil 

    -- The initial item checks for the specific fishing type.
    local itemsValid, itemMessage = CheckRequiredItems(config)
    if not itemsValid then
        passedChecks = false
        message = itemMessage
    end

    if passedChecks then
        if fishingType == 'deepsea' then
            local boatValid, boatMessage, foundDeepSeaBoat = CheckDeepSeaBoat(config, PlayerPed)
            if not boatValid then
                passedChecks = false
                message = boatMessage
            else
                deepSeaBoatEntity = foundDeepSeaBoat 
                DebugPrint('Deep sea fishing: Identified deep sea boat entity: ' .. tostring(deepSeaBoatEntity))
            end
        elseif fishingType == 'traditional' then
            -- Traditional fishing now relies on WaterCheck which is handled by CheckTraditionalLocation
            local locationValid, locationMessage = CheckTraditionalLocation(PlayerPed)
            if not locationValid then
                passedChecks = false
                message = locationMessage
            end
        end
        -- Clamming already relies on being in its PolyZone for currentZoneType to be 'clamming'.
        -- No additional location check needed here beyond the initial zone entry.
    end

    if not passedChecks then
        SendNotification(message, "error")
        isFishing = false -- Reset fishing state if checks fail before starting
        return
    end

    if config.BaitItem then
        RemoveItem(config.BaitItem, 1)
    end

    SendNotification(string.format("%s...", string.gsub(fishingType, "^%l", string.upper)), "info")

    -- ANIMATION & PROP SETUP
    if fishingType == 'traditional' or fishingType == 'deepsea' then
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
        DebugPrint('Starting fishing rod animation for ' .. fishingType .. '.')

    elseif fishingType == 'clamming' then
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
    end

    local wasCancelled = false
    local startTime = GetGameTimer()
    local endTime = startTime + config.Time

    while GetGameTimer() < endTime do
        Wait(0)
        DisplayHelpText("~INPUT_CELLPHONE_CANCEL~ or ~INPUT_CREATOR_LT~ Cancel Fishing")
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 252) then -- 'X' key
            wasCancelled = true
            SendNotification("Fishing cancelled!", "info")
            DebugPrint('Fishing cancelled by player.')
            break
        end
    end

    -- Call the centralized StopFishing function for cleanup
    if wasCancelled then
        StopFishing()
        return
    end

    DebugPrint(fishingType .. ' fishing attempt duration finished. Starting minigame.')

    if StartMinigame(fishingType) then
        if math.random() < fishConfig.CatchChance then
            local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
            AddItem(caughtItem, 1)
            DebugPrint('Successfully caught: ' .. caughtItem)
        else
            SendNotification("You didn't catch anything this time.", "info")
            DebugPrint('Fishing attempt: No catch.')
        end
    end

    -- Call the centralized StopFishing function for cleanup after minigame/catch
    StopFishing()
end

-- Function to create PolyZone objects from the config
local function CreateFishingZones()
    DebugPrint('Attempting to create fishing zones...')

    for fishingTypeKey, data in pairs(Config) do
        -- Ensure we only process valid fishing type configurations that have a 'Zones' table
        if type(data) == 'table' and data.Zones and Config.FishTypes[fishingTypeKey] then
            DebugPrint('Processing config for fishing type: ' .. fishingTypeKey)
            local subZonesForCombo = {}
            for i, individualZoneData in ipairs(data.Zones) do
                local subZone = nil
                local options = {
                    debugPoly = Config.Debugging, -- Use global debug setting
                    minZ = individualZoneData.minZ,
                    maxZ = individualZoneData.maxZ,
                    name = fishingTypeKey .. "_" .. individualZoneData.type .. "_" .. i -- Unique name for sub-zone
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
                        -- CORRECTED: Pass heading inside the options table for BoxZone
                        options.heading = individualZoneData.heading
                        subZone = BoxZone:Create(individualZoneData.coords, individualZoneData.length, individualZoneData.width, options)
                        DebugPrint('Created BoxZone for ' .. fishingTypeKey .. ' at ' .. tostring(individualZoneData.coords) .. ' (Length: ' .. individualZoneData.length .. ', Width: ' .. individualZoneData.width .. ', Heading: ' .. tostring(individualZoneData.heading) .. ')')
                    else
                        DebugPrint('Skipped BoxZone creation: Global BoxZone is NIL.')
                    end
                elseif individualZoneData.type == 'poly' then
                    if PolyZone then -- Assuming PolyZone is the global constructor for polygon zones
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
                -- Store the combo zone and its associated fishing type
                createdZones[fishingTypeKey] = {
                    zone = mainComboZone,
                    fishingType = fishingTypeKey,
                    isPlayerInside = false -- Initialize player inside flag for this combo zone
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
end)

CreateThread(function()
    while true do
        local PlayerPed = PlayerPedId()
        local PlayerCoords = GetEntityCoords(PlayerPed)
        local sleepTime = 500 -- Default sleep time

        local inAnyFishingZoneThisTick = false -- Track if player is in *any* zone during this tick
        local activeFishingTypeThisTick = nil -- Track the fishing type for the zone currently entered

        for fishingTypeKey, zoneEntry in pairs(createdZones) do
            local zone = zoneEntry.zone

            if zone and zone:isPointInside(PlayerCoords) then
                inAnyFishingZoneThisTick = true
                activeFishingTypeThisTick = fishingTypeKey -- Set the active type

                if not zoneEntry.isPlayerInside then
                    DebugPrint('Player HAS ENTERED ' .. fishingTypeKey .. ' zone.')
                    zoneEntry.isPlayerInside = true
                    -- Display info notification only on entry
                    SendNotification(
                        string.format("Entered %s zone.", string.gsub(fishingTypeKey, "^%l", string.upper)),
                        "info"
                    )
                end
                sleepTime = 5 -- Reduce sleep time for active zone checks
                break -- Break after finding the first zone the player is in
            else
                if zoneEntry.isPlayerInside then
                    DebugPrint('Player HAS LEFT ' .. fishingTypeKey .. ' zone.')
                    zoneEntry.isPlayerInside = false
                    -- If player leaves a zone while fishing, cancel it
                    if isFishing then
                        SendNotification("You left the fishing zone! Fishing cancelled.", "error")
                        StopFishing() -- Call the centralized stop function
                    end
                end
            end
        end

        -- Update global currentZoneType based on this tick's findings
        currentZoneType = activeFishingTypeThisTick

        if not inAnyFishingZoneThisTick then
            sleepTime = 500
        end

        -- No 'E' key input handling here anymore, as fishing is triggered by event.

        Wait(sleepTime)
    end
end)

-- MODIFIED ts-fishing:client:startFishing EVENT HANDLER
RegisterNetEvent('ts-fishing:client:startFishing', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startFishing event.')

    if isFishing then
        SendNotification("You are already fishing!", "error")
        DebugPrint('Fishing attempt blocked: Already fishing.')
        return
    end

    local determinedFishingType = nil
    local errorReason = "You are not in a valid fishing spot or lack the necessary items." -- Default error

    -- Attempt to determine fishing type based on context
    if currentZoneType == 'deepsea' then
        DebugPrint('Player is in a deepsea zone. Checking deepsea conditions...')
        local itemsValid, itemMessage = CheckRequiredItems(Config.deepsea)
        if itemsValid then
            local boatValid, boatMessage, _ = CheckDeepSeaBoat(Config.deepsea, playerPed)
            if boatValid then
                determinedFishingType = 'deepsea'
            else
                errorReason = boatMessage
            end
        else
            errorReason = itemMessage
        end
    elseif currentZoneType == 'clamming' then
        DebugPrint('Player is in a clamming zone. Checking clamming conditions...')
        local itemsValid, itemMessage = CheckRequiredItems(Config.clamming)
        if itemsValid then
            determinedFishingType = 'clamming'
        else
            errorReason = itemMessage
        end
    else
        -- If not in a specific zone, check for traditional fishing (anywhere with water + rod)
        DebugPrint('Player not in a specific fishing zone. Checking for traditional fishing conditions...')
        local rodItem = Config.traditional.RodItem
        if HasItem(rodItem) then
            local locationValid, locationMessage = CheckTraditionalLocation(playerPed)
            if locationValid then
                local baitItem = Config.traditional.BaitItem
                if baitItem and not HasItem(baitItem) then -- Check for bait specifically for traditional if configured
                    errorReason = "You need " .. baitItem .. " for traditional fishing!"
                    DebugPrint('Traditional fishing item check failed: Missing bait.')
                else
                    determinedFishingType = 'traditional'
                end
            else
                errorReason = locationMessage
            end
        else
            errorReason = "You need a " .. rodItem .. " to fish!"
            DebugPrint('Traditional fishing item check failed: Missing rod.')
        end
    end

    if determinedFishingType then
        DebugPrint('Initiating fishing for type: ' .. determinedFishingType)
        AttemptFishing(determinedFishingType, playerPed)
    else
        SendNotification(errorReason, "error")
        DebugPrint('Fishing attempt blocked: ' .. errorReason)
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
        SendNotification("Anchor dropped! Boat is now stationary horizontally.", "info")
        DebugPrint('Anchor dropped. Initiating anchor hold thread.')

        TaskLeaveVehicle(playerPed, vehicle, 0)

        anchorThread = Citizen.CreateThread(function()
            while isBoatAnchored and DoesEntityExist(vehicle) do
                local currentVelocity = GetEntityVelocity(vehicle)
                local currentZVelocity = currentVelocity.z
                SetEntityVelocity(vehicle, 0.0, 0.0, currentZVelocity)
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
        if isFishing then
            DebugPrint('Player died/fatally injured. Forcing fishing to stop.')
            StopFishing()
        end
	end
end)