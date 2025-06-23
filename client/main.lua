local createdZones = {}
local isFishing = false
local fishingRodProp = nil
local clammingShovelProp = nil
local clammingDirtProp = nil

local function StartMinigame(difficulty)
    DebugPrint('Starting minigame with difficulty: ' .. difficulty)
    local success = false
    local startTime = GetGameTimer()
    local duration = 2000
    local reactionTime = 500

    local targetKey = GetRandomIntInRange(0, 5)
    local keyNames = {"E", "F", "G", "H", "R", "T"}
    local controlIds = {38, 23, 37, 48, 45, 47} -- These are for reference, input will come from NUI

    local idealHitTime = startTime + (duration * (1 - difficulty))
    local targetWindowStart = idealHitTime - (reactionTime / 2)
    local targetWindowEnd = idealHitTime + (reactionTime / 2)

    targetWindowStart = math.max(startTime, targetWindowStart)
    targetWindowEnd = math.min(startTime + duration, targetWindowEnd)

    -- Send all timing info to NUIv
    SendNuiMessage(json.encode({
        type = 'showMinigame',
        key = keyNames[targetKey + 1],
        minigameStartTime = startTime,
        minigameDuration = duration,
        targetWindowStart = targetWindowStart,
        targetWindowEnd = targetWindowEnd
    }))

    SetNuiFocus(true, true)

    DebugPrint(string.format('Minigame: StartTime: %d, Duration: %d, IdealHit: %d, Window: [%d, %d]',
        startTime, duration, idealHitTime, targetWindowStart, targetWindowEnd))

    local minigameResultReceived = false
    local minigameSuccessResult = false

    -- Register a temporary NUI callback specifically for this minigame instance
    local minigameCallbackId = 'minigame_result_' .. tostring(GetGameTimer())
    RegisterNuiCallback(minigameCallbackId, function(data, cb)
        DebugPrint('Minigame: NUI result received: ' .. tostring(data.success))
        minigameSuccessResult = data.success
        minigameResultReceived = true
        cb(json.encode({})) -- Acknowledge callback with empty JSON
    end)

    -- Loop to wait for NUI result or timeout
    local loopStartTime = GetGameTimer()
    while GetGameTimer() < loopStartTime + duration do
        Wait(0)
        if minigameResultReceived then
            success = minigameSuccessResult
            break
        end
        -- NUI now handles its own highlighting, so no highlight message from Lua needed here.
    end

    -- If the loop finished without a result (timeout)
    if not minigameResultReceived then
        success = false
        DebugPrint('Minigame: Timeout - no key press registered by NUI.')
    end
    SendNuiMessage(json.encode({ type = 'hideMinigame' }))
    SetNuiFocus(false, false)

    if success then
        DebugPrint('Minigame: Success!')
        SendNotification("Success!", "success")
        return true
    else
        DebugPrint('Minigame: Failed!')
        SendNotification("Failed!", "error")
        return false
    end
end

local function AttemptFishing(fishingType, PlayerPed)
    isFishing = true
    DebugPrint('Attempting ' .. fishingType .. ' fishing.')
    local config = Config[fishingType]
    local fishConfig = Config.FishTypes[fishingType]
    local message = ""
    local passedChecks = true
    local deepSeaBoatEntity = nil 

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
            local locationValid, locationMessage = CheckTraditionalLocation(PlayerPed)
            if not locationValid then
                passedChecks = false
                message = locationMessage
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
        DisableControlAction(0, 194, true)
        if IsControlJustPressed(0, 194) then
            wasCancelled = true
            SendNotification("Fishing cancelled!", "info")
            DebugPrint('Fishing cancelled by player.')
            break
        end
    end

    if wasCancelled then
        goto end_fishing_attempt
    end

    DebugPrint(fishingType .. ' fishing attempt duration finished. Starting minigame.')

    if StartMinigame(config.MinigameDifficulty) then
        if math.random() < fishConfig.CatchChance then
            local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
            AddItem(caughtItem, 1)
            DebugPrint('Successfully caught: ' .. caughtItem)
        else
            SendNotification("You didn't catch anything this time.", "info")
            DebugPrint('Fishing attempt: No catch.')
        end
    end

    ::end_fishing_attempt::

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
    DebugPrint('Fishing attempt finished.')
end

function CancelFishingOnDeath()
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
    DebugPrint('Fishing attempt finished.')
end

-- Function to create PolyZone objects from the config
function CreateFishingZones()
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
                        ClearPedTasks(PlayerPed)
                        isFishing = false
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

-- REPLACE YOUR EXISTING ts-fishing:client:startFishing EVENT HANDLER WITH THIS:
RegisterNetEvent('ts-fishing:client:startFishing', function()
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startFishing event.')

    if isFishing then
        SendNotification("You are already fishing!", "error")
        DebugPrint('Fishing attempt blocked: Already fishing.')
        return
    end

    if not currentZoneType then
        SendNotification("You are not in a fishing zone!", "error")
        DebugPrint('Fishing attempt blocked: Not in a fishing zone.')
        return
    end

    -- If all checks pass, proceed to attempt fishing
    DebugPrint('Initiating fishing via ts-fishing:client:startFishing event for type: ' .. currentZoneType)
    AttemptFishing(currentZoneType, playerPed)
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