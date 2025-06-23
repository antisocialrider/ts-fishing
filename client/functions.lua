function DebugPrint(msg)
    if Config.Debugging then
        print('^3[ts-fishing]^0 ' .. msg)
    end
end

function WaterCheck()
    local ped = PlayerPedId()
    local headPos = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local offsetPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 50.0, -25.0)
    local water, waterPos = TestProbeAgainstWater(headPos.x, headPos.y, headPos.z, offsetPos.x, offsetPos.y, offsetPos.z)
    return water, waterPos
end

function CheckRequiredItems(config)
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

function CheckDeepSeaBoat(config, PlayerPed)
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

function CheckTraditionalLocation(PlayerPed)
    local isSwimming = IsPedSwimming(PlayerPed)
    if isSwimming then
        DebugPrint('Traditional fishing location check failed: Cannot fish while swimming.')
        return false, "You cannot traditionally fish while swimming!"
    end

    local facingFishableWater, waterHitPos = WaterCheck()
    if not facingFishableWater then
        DebugPrint('Traditional fishing location check failed: Not facing fishable water (WaterCheck returned false).')
        return false, "You need to be facing fishable water to traditionally fish!"
    end
    DebugPrint('Traditional fishing location check passed. Water found at ' .. tostring(waterHitPos.x) .. ', ' .. tostring(waterHitPos.y) .. ', ' .. tostring(waterHitPos.z))
    return true, ""
end

AddEventHandler('gameEventTriggered', function(event, data)
	if event ~= 'CEventNetworkEntityDamage' then return end
	local victim, victimDied = data[1], data[4]
	if not IsPedAPlayer(victim) then return end
	local player = PlayerId()
	if victimDied and NetworkGetPlayerIndexFromPed(victim) == player and (IsPedDeadOrDying(victim, true) or IsPedFatallyInjured(victim))  then
        CancelFishingOnDeath()
	end
end)