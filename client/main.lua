-- antisocialrider/ts-fishing/ts-fishing-30c79791400a44ebf78a174946a71c48107efe47/client/main.lua
local QBCore = exports['qb-core']:GetCoreObject()

local createdZones = {}
local isFishing = false
local fishingRodProp = nil
local clammingShovelProp = nil
local clammingDirtProp = nil

-- NEW GLOBAL VARIABLES
local netProp = nil
local netRope = nil
-- Pot props are now managed in clientActivePots table
local potProp = nil -- Still keep for the initiating player's immediate reference, though handled by clientActivePots for others.
local buoyProp = nil -- Still keep for the initiating player's immediate reference, though handled by clientActivePots for others.

-- NEW: Table to store locally created pot and buoy objects
local clientActivePots = {} -- { potId = { potObj = object, buoyObj = object } }

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

-- MODIFIED: StartMinigame, removed deepsea_nui_key type
local function StartMinigame(fishingType, deepseaType)
    if fishingType == 'traditional' then
        return exports.peuren_minigames:StartPressureBar(40, 20)
    elseif fishingType == 'clamming' then
        return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
    elseif fishingType == 'deepsea' then
        if deepseaType == 'net' then
            return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
        else
            return exports['SN-Hacking']:SkillBar({4000, 8000}, 10, 2)
        end
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
    DebugPrint(string.format("AdvancedWaterCheck: After %dms settle: Probe Object ID: %s, IsEntityInWater: %s, Actual Probe Z: %.2f", waitTimeForSettle, tostring(probeObject), tostring(inWater), actualProbeCoords.z))

    DeleteObject(probeObject)
    SetModelAsNoLongerNeeded(model)

    return inWater, actualProbeCoords
end

local function CheckRequiredItems(fishingType, config)

    if fishingType == 'deepsea' then
        if config.NetItem and not HasItem(config.NetItem) and config.PotItem and not HasItem(config.PotItem) then
            DebugPrint('Required item check failed: Missing Net or Pot')
            return false, "You need a Net or Pot!"
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
    -- NEW: Cleanup for net and pot props/rope
    if netProp and DoesEntityExist(netProp) then
        DeleteObject(netProp)
        netProp = nil
        DebugPrint('Deleted net prop.')
    end
    if netRope and DoesRopeExist(netRope) then -- Check if rope exists
        DeleteRope(netRope) -- Delete the rope
        netRope = nil
        DebugPrint('Deleted net rope.')
    end
    -- Note: potProp and buoyProp globals are primarily for the initiating player.
    -- General cleanup for all clients is handled by ts-fishing:client:removePotProps event.
    if potProp and DoesEntityExist(potProp) then -- This would only be set for the player who deployed the pot
        DeleteObject(potProp)
        potProp = nil
        DebugPrint('Deleted local pot prop.')
    end
    if buoyProp and DoesEntityExist(buoyProp) then -- This would only be set for the player who deployed the pot
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
    DebugPrint('Fishing state reset.')
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
    local rearOfBoat = GetRearOfBoatCoords(boatEntity, vector3(0.0, -3.0, 0.0)) -- 3m behind boat
    local distance = GetDistanceBetweenCoords(playerCoords, rearOfBoat, true)
    DebugPrint(string.format("Player distance to boat rear: %.2f (Threshold: %.2f)", distance, proximityThreshold))
    return distance <= proximityThreshold, "You need to be near the back of the boat to deploy this!"
end

-- NEW THREAD: Net Fishing Minigame Logic (NO NUI)
local function NetFishingMinigameThread(deepSeaBoatEntity, fishConfig)
    local playerPed = PlayerPedId()
    local config = Config['deepsea']
    local distanceSailed = 0.0
    local initialBoatCoords = GetEntityCoords(deepSeaBoatEntity)
    local lastCheckCoords = initialBoatCoords
    local successCount = 0
    local promptInterval = math.random(config.NetMinigameKeyIntervalMin, config.NetMinigameKeyIntervalMax)
    local lastPromptTime = GetGameTimer()

    DebugPrint('NetFishingMinigameThread started.')

    while isFishing and distanceSailed < config.NetMinigameSailDistance do
        Wait(0) -- Yield to prevent freezing

        if not DoesEntityExist(deepSeaBoatEntity) or GetVehiclePedIsIn(playerPed, false) ~= deepSeaBoatEntity then
            SendNotification("You left the boat! Net fishing cancelled.", "error")
            StopFishing()
            break
        end

        local currentBoatCoords = GetEntityCoords(deepSeaBoatEntity)
        local segmentDistance = GetDistanceBetweenCoords(lastCheckCoords, currentBoatCoords, true)
        distanceSailed = distanceSailed + segmentDistance
        lastCheckCoords = currentBoatCoords

        DisplayHelpText(string.format("~b~Net Fishing: ~w~Sail ~y~%.1fm~w~/~g~%.1fm~w~. Successes: ~g~%d", distanceSailed, config.NetMinigameSailDistance, successCount))

        if GetGameTimer() - lastPromptTime > promptInterval then
            DebugPrint('Triggering net minigame prompt (using peuren_minigames).')
            -- Use existing minigame export for the key prompt
            if exports.peuren_minigames:StartPressureBar(40, 20) then -- Adjust parameters as needed
                successCount = successCount + 1
                SendNotification("Net lowered/raised successfully!", "success")
            else
                SendNotification("Failed to lower/raise net!", "error")
            end
            lastPromptTime = GetGameTimer()
            promptInterval = math.random(config.NetMinigameKeyIntervalMin, config.NetMinigameKeyIntervalMax)
        end
    end

    if isFishing then -- Only proceed if fishing wasn't cancelled
        DebugPrint('Net fishing distance covered. Calculating catch...')
        -- Simplified chance calculation, can be adjusted based on minigame successes logic
        local totalPossiblePrompts = math.floor(config.NetMinigameSailDistance / (config.NetMinigameKeyIntervalMin / 1000)) -- Estimate
        local effectiveCatchChance = (successCount / math.max(1, totalPossiblePrompts)) * fishConfig.CatchChance

        if math.random() < effectiveCatchChance then
            local caughtItem = fishConfig.Fish[math.random(1, #fishConfig.Fish)]
            AddItem(caughtItem, 1)
            DebugPrint('Successfully caught: ' .. caughtItem)
        else
            SendNotification("You sailed a lot but the net came up empty!", "info")
            DebugPrint('Net fishing attempt: No catch.')
        end
    end

    StopFishing() -- Stop fishing and clean up after the net minigame
end


-- MODIFIED: AttemptFishing to integrate net/pot logic
local function AttemptFishing(fishingType, PlayerPed, deepSeaMethod)
    isFishing = true
    DebugPrint('Attempting ' .. fishingType .. ' fishing' .. (deepSeaMethod and ' with method ' .. deepSeaMethod or '') .. '.')
    local config = Config[fishingType]
    local fishConfig = Config.FishTypes[fishingType]
    local message = ""
    local passedChecks = true
    local deepSeaBoatEntity = nil
    local playerCoords = GetEntityCoords(PlayerPed)

    -- The initial item checks for the specific fishing type.
    local itemsValid, itemMessage = CheckRequiredItems(fishingType, Config[fishingType])
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

                -- NEW: Specific checks for Net and Pot
                if deepSeaMethod == 'net' then
                    local nearRear, rearMessage = CheckPlayerNearBoatRear(PlayerPed, deepSeaBoatEntity, 10.0) -- 5m proximity
                    if not nearRear then
                        passedChecks = false
                        message = rearMessage
                    end
                elseif deepSeaMethod == 'pot' then
                    local nearRear, rearMessage = CheckPlayerNearBoatRear(PlayerPed, deepSeaBoatEntity, 10.0) -- 5m proximity
                    if not nearRear then
                        passedChecks = false
                        message = rearMessage
                    end
                end
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
        if deepSeaMethod == 'net' then
            -- Net deployment animation (placeholder)
            local animDict = 'amb@world_human_stand_fishing@idle_a' -- Re-using existing anim dict
            RequestAnimDict(animDict)
            while not HasAnimDictLoaded(animDict) do Wait(0) end
            TaskPlayAnim(PlayerPed, animDict, 'idle_c', 1.0, -1.0, -1, 11, 0, 0, 0, 0)
            DebugPrint('Starting net deployment animation.')

            -- Create and attach net prop
            RequestModel(config.NetPropModel)
            while not HasModelLoaded(config.NetPropModel) do Wait(0) end
            -- Create as network object
            netProp = CreateObject(config.NetPropModel, playerCoords.x, playerCoords.y, playerCoords.z - 5.0, true, true, true)
            SetEntityCoordsNoOffset(netProp, playerCoords.x, playerCoords.y, GetWaterHeight(playerCoords.x, playerCoords.y, playerCoords.z), false, false, false)
            SetEntityCollision(netProp, false, false)
            SetEntityHasGravity(netProp, true)
            ActivatePhysics(netProp)

            local boatRearBone = GetEntityBoneIndexByName(deepSeaBoatEntity, 'v_engine') -- Use a common boat rear bone
            if boatRearBone == -1 then boatRearBone = 0 end -- Fallback to root bone if specific bone not found

            netRope = AddRope(playerCoords.x, playerCoords.y, playerCoords.z, config.RopeLength, 0.5, 0.05, 0, 0, 0, 0, 0, "rope_tx", "rope_tx_01")
            Wait(100) -- Allow rope to be created
            if netRope then
                 -- Attach the rope to the boat (rear) and the net prop
                AttachEntitiesToRope(netRope, deepSeaBoatEntity, netProp, boatRearBone, 0, config.RopeAttachOffset.x, config.RopeAttachOffset.y, config.RopeAttachOffset.z, 0.0, 0.0, 0.0, true)
                DebugPrint('Net prop created and attached to boat with rope.')
                Citizen.CreateThread(function() NetFishingMinigameThread(deepSeaBoatEntity, fishConfig) end)
            else
                SendNotification("Failed to deploy net (rope error).", "error")
                StopFishing()
                return
            end

        elseif deepSeaMethod == 'pot' then
            -- Pot deployment animation (placeholder)
            local animDict = 'random@burial' -- Re-using existing anim dict
            RequestAnimDict(animDict)
            while not HasAnimDictLoaded(animDict) do Wait(0) end
            TaskPlayAnim(PlayerPed, animDict, 'a_burial', 1.0, -1.0, -1, 48, 0, 0, 0, 0)
            DebugPrint('Starting pot deployment animation.')

            -- Start install minigame
            local minigameResult = StartMinigame(fishingType, deepSeaMethod) -- Re-using SN-Hacking skill bar for "install"
            if minigameResult then
                SendNotification("Pot installed successfully!", "success")
                -- Trigger server event to save pot location and start catch generation
                -- Server will then broadcast to all clients (including this one) to create the props
                TriggerServerEvent('ts-fishing:server:deployPot', GetRearOfBoatCoords(deepSeaBoatEntity, config.PotDeployOffset), GetEntityHeading(deepSeaBoatEntity), Config.deepsea.PotMaxCatches)
            else
                SendNotification("Pot installation failed!", "error")
            end
            StopFishing()

        else -- Standard traditional/deepsea fishing with rod
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
            StopFishing()
        end

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
        StopFishing()
    end
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
                    if isFishing then
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

-- MODIFIED ts-fishing:client:startFishing EVENT HANDLER to accept deepSeaMethod
RegisterNetEvent('ts-fishing:client:startFishing', function(deepSeaMethod)
    local playerPed = PlayerPedId()
    DebugPrint('Received ts-fishing:client:startFishing event with deepSeaMethod: ' .. tostring(deepSeaMethod))

    if isFishing then
        SendNotification("You are already fishing!", "error")
        DebugPrint('Fishing attempt blocked: Already fishing.')
        return
    end

    local determinedFishingType = nil
    local errorReason = "You are not in a valid fishing spot or lack the necessary items."
    local finalDeepSeaMethod = deepSeaMethod

    if currentZoneType == 'clamming' then
        DebugPrint('Player is in a clamming zone. Checking clamming conditions...')
        local itemsValid, itemMessage = CheckRequiredItems('clamming', Config['clamming'])
        if itemsValid then
            determinedFishingType = 'clamming'
        else
            errorReason = itemMessage
        end
    else
        if finalDeepSeaMethod then
            DebugPrint('Player is in a deepsea zone. Checking deepsea conditions...')
            if finalDeepSeaMethod == 'net' or finalDeepSeaMethod == 'pot' then
                local itemsValid, itemMessage = CheckRequiredItems('deepsea', Config['deepsea'])
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
            else
                errorReason = "You must use either a fishing net or a fishing pot for deep sea fishing!"
                DebugPrint('Deep sea fishing attempt blocked: Invalid or missing deepSeaMethod.')
            end
        else
            DebugPrint('Player not in a specific fishing zone. Checking for traditional fishing conditions...')
            local itemsValid, itemMessage = CheckRequiredItems('traditional', Config['traditional'])
            if itemsValid then
                local locationValid, locationMessage = CheckTraditionalLocation(playerPed)
                if locationValid then
                    determinedFishingType = 'traditional'
                else
                    errorReason = locationMessage
                end
            else
                errorReason = itemMessage
            end
        end
    end

    if determinedFishingType then
        DebugPrint('Initiating fishing for type: ' .. determinedFishingType .. (finalDeepSeaMethod and ' (Method: ' .. finalDeepSeaMethod .. ')' or ''))
        AttemptFishing(determinedFishingType, playerPed, finalDeepSeaMethod)
    else
        SendNotification(errorReason, "error")
        DebugPrint('Fishing attempt blocked: ' .. errorReason)
    end
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
            while not HasModelLoaded(potInfo.potModel) or not HasModelLoaded(potInfo.buoyModel) do Wait(0) end

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