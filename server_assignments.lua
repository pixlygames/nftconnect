-- resources/[add-scripts]/NFTconnect/server_assignments.lua
local QBCore = exports['qb-core']:GetCoreObject()

-- Debug function specific to assignments
local function DebugAssign(message, ...)
    if Config.Debug then
        print(('[NFTconnect:Assignments] ' .. message):format(...))
    end
end

-- Reference to PropertiesTable from ps-housing (if available)
local PropertiesTable = nil

AddEventHandler('ps-housing:server:initialiseProperties', function(properties)
    DebugAssign("Received ps-housing properties table.")
    PropertiesTable = properties
end)

Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Wait a bit for other resources
    if not PropertiesTable then
        DebugAssign("Requesting ps-housing properties table...")
        TriggerEvent('ps-housing:server:requestProperties')
    end
end)


-- Check if player already owns the default apartment
local function HasDefaultApartment(citizenId)
    local apartmentName = Config.DefaultApartmentName
    DebugAssign("Checking if player %s already has apartment '%s'", citizenId, apartmentName)

    -- Check PropertiesTable first if available
    if PropertiesTable and next(PropertiesTable or {}) then
        for _, v in pairs(PropertiesTable) do
            local propData = v.propertyData
            -- Ensure propData and relevant fields exist before accessing
            if propData and propData.owner == citizenId and propData.apartment == apartmentName then
                DebugAssign("Player %s found owning apartment '%s' in PropertiesTable cache.", citizenId, apartmentName)
                return true
            end
        end
        DebugAssign("Player %s does not own apartment '%s' in PropertiesTable cache.", citizenId, apartmentName)
    else
        DebugAssign("PropertiesTable not available or empty, checking database directly.")
        -- Fallback to database check if PropertiesTable isn't populated/available
        local result = MySQL.Sync.fetchAll('SELECT property_id FROM properties WHERE owner_citizenid = ? AND apartment = ? LIMIT 1', { citizenId, apartmentName })
        if result and #result > 0 then
            DebugAssign("Player %s found owning apartment '%s' in database.", citizenId, apartmentName)
            return true
        end
        DebugAssign("Player %s does not own apartment '%s' in database.", citizenId, apartmentName)
    end

    return false
end

-- Function to assign the configured default apartment
local function AssignDefaultApartment(src, citizenId)
    DebugAssign("Attempting to assign default apartment '%s' to player %s", Config.DefaultApartmentName, citizenId)

    if HasDefaultApartment(citizenId) then
        DebugAssign("Player %s already owns the default apartment. Skipping assignment.", citizenId)
        return false -- Indicate no assignment was made
    end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        DebugAssign("Player not found for source %s during apartment assignment.", src)
        return false
    end

    -- Structure needed for ps-housing addTenant event
    local data = {
        apartment = Config.DefaultApartmentName,
        targetSrc = src,
        realtorSrc = src, -- Assigning automatically
    }

    DebugAssign("Triggering ps-housing:server:addTenantToApartment for %s", citizenId)
    TriggerEvent("ps-housing:server:addTenantToApartment", data) -- Ensure this event exists and works in your ps-housing version

    -- Notifications and Waypoint
    TriggerClientEvent('QBCore:Notify', src, Config.ApartmentNotifyMessage, 'success', 7000)
    TriggerClientEvent('NFTconnect:client:SetWaypoint', src, Config.ApartmentWaypointX, Config.ApartmentWaypointY, Config.ApartmentWaypointZ)
    TriggerClientEvent('NFTconnect:client:SendApartmentEmail', src) -- Trigger client to send email

    DebugAssign("Default apartment assignment process completed for %s.", citizenId)
    return true -- Indicate assignment was made
end

-- Function to generate a unique plate (simple example, consider your server's plate system)
local function GeneratePlate()
    math.randomseed(os.time())
    local plate = "NFT" .. math.random(1000, 9999)
    return string.upper(plate)
end

-- Function to assign the configured default car
local function AssignDefaultCar(src, citizenId)
    local carModel = Config.DefaultCarModel:lower()
    DebugAssign("Attempting to assign default car '%s' to player %s", carModel, citizenId)

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        DebugAssign("Player not found for source %s during car assignment.", src)
        return false
    end
    local playerLicense = Player.PlayerData.license

    -- Check if player already owns this model (basic check, might need refinement based on how you track duplicates)
    local existing = MySQL.Sync.fetchAll('SELECT plate FROM player_vehicles WHERE citizenid = ? AND vehicle = ? LIMIT 1', { citizenId, carModel })
    if existing and #existing > 0 then
        DebugAssign("Player %s already owns a vehicle model '%s'. Skipping assignment.", citizenId, carModel)
        return false -- Indicate no assignment was made
    end

    local plate = GeneratePlate() -- Generate a unique plate
    local vehicleHash = GetHashKey(carModel)

    MySQL.Async.execute([[
        INSERT INTO player_vehicles
            (license, citizenid, vehicle, hash, mods, plate, fakeplate, garage, fuel, engine, body, state, depotprice, drivingdistance, status)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        playerLicense,          -- license
        citizenId,              -- citizenid
        carModel,               -- vehicle
        vehicleHash,            -- hash
        '{}',                   -- mods
        plate,                  -- plate
        plate,                  -- fakeplate
        Config.DefaultCarGarage,-- garage
        100,                    -- fuel
        1000.0,                 -- engine
        1000.0,                 -- body
        1,                      -- state
        0,                      -- depotprice
        0,                      -- drivingdistance
        '{}',                   -- status
    }, function(rowsChanged)
        if rowsChanged > 0 then
            DebugAssign("Default car '%s' with plate '%s' added to database for %s.", carModel, plate, citizenId)
            -- Give keys using qb-vehiclekeys (ensure this export exists)
            if exports['qb-vehiclekeys'] then
                 exports['qb-vehiclekeys']:GiveKeys(src, plate)
                 DebugAssign("Gave keys for plate %s to player %s", plate, citizenId)
            else
                 DebugAssign("WARNING: qb-vehiclekeys export not found. Cannot give keys automatically.")
            end

            -- Notifications and Email
            local notifyMsg = string.format(Config.CarNotifyMessage, carModel:upper())
            TriggerClientEvent('QBCore:Notify', src, notifyMsg, 'success', 7000)
            TriggerClientEvent('NFTconnect:client:SendCarEmail', src, carModel) -- Trigger client to send email

        else
            DebugAssign("Failed to insert default car '%s' into database for %s.", carModel, citizenId)
        end
    end)

    return true -- Indicate assignment process was initiated (async)
end

-- Main function to handle first connection rewards
-- Returns: true if rewards were processed (was first connection), false otherwise
function HandleFirstConnectionRewards(src, citizenId)
    DebugAssign("Checking first connection rewards for player %s (Source: %s)", citizenId, src)

    if not Config.EnableFirstConnectionRewards then
        DebugAssign("First connection rewards are disabled globally.")
        return false -- Not handled
    end

    -- Check if this citizenId already exists in our mapping table
    local existingMapping = MySQL.Sync.fetchAll('SELECT id FROM nftconnect_wallets WHERE citizenid = ? LIMIT 1', { citizenId })

    if existingMapping and #existingMapping > 0 then
        DebugAssign("Player %s already has a wallet mapping. Not a first connection.", citizenId)
        return false -- Not a first connection
    end

    DebugAssign("Player %s is connecting a wallet for the first time. Processing rewards...", citizenId)

    local rewardsGranted = false

    -- Grant Apartment
    if Config.GrantApartmentOnFirstConnect then
        DebugAssign("Processing apartment reward for %s.", citizenId)
        if AssignDefaultApartment(src, citizenId) then
            rewardsGranted = true
        end
    else
        DebugAssign("Apartment reward disabled.")
    end

    -- Grant Car
    if Config.GrantCarOnFirstConnect then
        DebugAssign("Processing car reward for %s.", citizenId)
        if AssignDefaultCar(src, citizenId) then
            rewardsGranted = true
        end
    else
        DebugAssign("Car reward disabled.")
    end

    -- Shared Notifications if any reward was granted
    if rewardsGranted then
        DebugAssign("Triggering shared post-reward notifications for %s.", citizenId)
        -- Wait a brief moment before the long notification to avoid overlap
        Citizen.Wait(500)
        TriggerClientEvent('NFTconnect:client:ShowLongNotification', src, Config.LongNotifyMessage, Config.LongNotifyDuration)
    else
         DebugAssign("No first-time rewards were granted for %s.", citizenId)
    end

    return true -- Indicate that the first connection was detected and processed (even if specific rewards were disabled/failed)
end

-- Export the function for the bridge script to call
exports('HandleFirstConnectionRewards', HandleFirstConnectionRewards) 