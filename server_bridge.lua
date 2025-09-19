-- server_bridge.lua
local QBCore = exports['qb-core']:GetCoreObject()

-- Flag to ensure details are sent only once
local hasSentServerDetails = false

local PropertiesTable = nil
AddEventHandler('ps-housing:server:initialiseProperties', function(properties)
    if Config.Debug then print("[NFTconnect] Received ps-housing properties table in bridge.") end
    PropertiesTable = properties
end)
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Wait a bit for other resources
    if not PropertiesTable then
        if Config.Debug then print("[NFTconnect] Requesting ps-housing properties table in bridge...") end
        -- Trigger an event ps-housing might listen for to provide the table
        -- Ensure your ps-housing version supports this or adapt the event name
        TriggerEvent('ps-housing:server:requestProperties')
    end
end)

-- Function to send server details to the central server (called once on start)
local function SendServerDetailsToServer()
    if hasSentServerDetails then return end

    -- Check required config for identification
    if not Config.CentralServerURL or Config.CentralServerURL == '' or
       not Config.ServerBuyerWallet or Config.ServerBuyerWallet == '' then
        print("[NFTconnect] ERROR: Missing CentralServerURL or ServerBuyerWallet in config. Cannot send server details.")
        return
    end

    local detailsUrl = Config.CentralServerURL .. '/register-server' -- New endpoint
    local headers = {
        ['Content-Type'] = 'application/json'
    }
    local bodyTable = {
        walletAddress = Config.ServerBuyerWallet,
        serverName = Config.ServerName, -- Can be nil/empty
        serverIp = Config.ServerIP,       -- Can be nil/empty
        serverEmail = Config.ServerEmail   -- Can be nil/empty
    }
    local body = json.encode(bodyTable)

    if Config.Debug then print(string.format('[NFTconnect] Sending server details to %s', detailsUrl)) end
    
    PerformHttpRequest(detailsUrl, function(errorCode, responseText, responseHeaders)
        if errorCode >= 200 and errorCode < 300 then
            if Config.Debug then print(string.format('[NFTconnect] Successfully sent/updated server details. Response: %s', responseText)) end
            hasSentServerDetails = true -- Mark as sent successfully
        else
            print(string.format("[NFTconnect] ERROR: Failed to send server details to central server. Code: %s, Response: %s", errorCode, responseText))
        end
    end, 'POST', body, headers)
end

-- Initialize Database Table for wallet mapping (on this serverbuyer's server)
Citizen.CreateThread(function()
    -- Ensure oxmysql is ready
    while not exports.oxmysql do
        Citizen.Wait(100) -- Wait if oxmysql is not loaded yet
    end
    MySQL.Async.execute([[ 
        CREATE TABLE IF NOT EXISTS `nftconnect_wallets` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid` VARCHAR(50) NOT NULL UNIQUE,
            `wallet_address` VARCHAR(100) NOT NULL,
            `last_verified` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        );
    ]], {})
    if Config.Debug then print('[NFTconnect] Database table `nftconnect_wallets` checked/created.') end

    -- Send server details once after DB is ready
    SendServerDetailsToServer()
end)

-- Function to save/update wallet mapping
local function saveWalletMapping(citizenId, walletAddress)
    if not citizenId or not walletAddress then 
        if Config.Debug then print(string.format('[NFTconnect] Cannot save wallet mapping - missing citizenId (%s) or walletAddress (%s)', tostring(citizenId), tostring(walletAddress))) end
        return 
    end
    MySQL.Async.execute(
        'INSERT INTO nftconnect_wallets (citizenid, wallet_address) VALUES (?, ?) ON DUPLICATE KEY UPDATE wallet_address = VALUES(wallet_address), last_verified = CURRENT_TIMESTAMP',
        { citizenId, walletAddress },
        function(affectedRows)
            if Config.Debug then print(string.format('[NFTconnect] Wallet mapping saved/updated for %s. Affected rows: %d', citizenId, affectedRows)) end
        end
    )
end

-- Callback: Generate Payload by calling Central Server
QBCore.Functions.CreateCallback('NFTconnect:server:GeneratePayload', function(source, cb, citizenId)
    if not citizenId then
        print("[NFTconnect] ERROR: GeneratePayload callback received nil citizenId from source " .. source)
        cb(nil)
        return
    end

    -- Check essential config values needed for the HTTP request
    if not Config.CentralServerURL or Config.CentralServerURL == '' or 
       not Config.ServerBuyerWallet or Config.ServerBuyerWallet == '' then
         print("[NFTconnect] ERROR: Missing CentralServerURL or ServerBuyerWallet in config. Cannot generate payload.")
         cb(nil)
         return
    end

    local generateUrl = Config.CentralServerURL .. '/generate-payload'
    local headers = {
        ['Content-Type'] = 'application/json',
        ['X-Server-Wallet'] = Config.ServerBuyerWallet
        -- Removed ServerName and ServerIP headers
    }
    local body = json.encode({ citizenId = citizenId })

    if Config.Debug then print(string.format('[NFTconnect] Performing HTTP request to generate payload for citizenId %s: %s', citizenId, generateUrl)) end

    PerformHttpRequest(generateUrl, function(errorCode, responseText, responseHeaders)
        if Config.Debug then print(string.format('[NFTconnect][SERVER-DEBUG] Central Server /generate-payload response - Code: %s, Body: %s', errorCode, responseText)) end

        if errorCode ~= 200 then
            print(string.format("[NFTconnect] ERROR: Failed to generate payload from central server via server bridge. Code: %s", errorCode))
            if Config.Debug then print(string.format("Central Server Response: %s", responseText)) end
            cb(nil) -- Indicate failure to client
            return
        end

        local success, responseData = pcall(json.decode, responseText)
        if not success or not responseData or not responseData.payload then
            print(string.format("[NFTconnect] ERROR: Invalid payload response from central server via server bridge."))
            if Config.Debug then print(string.format("Central Server Raw Response: %s", responseText)) end
            cb(nil) -- Indicate failure to client
            return
        end

        local payload = responseData.payload
        if Config.Debug then print(string.format('[NFTconnect] Successfully received payload from central server via server bridge: %s', payload)) end
        cb(payload) -- Send the payload back to the client script

    end, 'POST', body, headers)
end)

-- Callback: Verify Proof by calling Central Server
QBCore.Functions.CreateCallback('NFTconnect:server:VerifyProof', function(source, cb, verificationData)
    if not verificationData or not verificationData.citizenId or not verificationData.walletAddress or
       not verificationData.proof or not verificationData.publicKeyHex or not verificationData.originalPayload then
        print(string.format("[NFTconnect] ERROR: VerifyProof callback received incomplete data from source %s.", source))
        cb({ verified = false, reason = "Internal Error: Incomplete data received by server bridge." })
        return
    end

    local src = source -- Store source for later use
    local citizenId = verificationData.citizenId
    local walletAddress = verificationData.walletAddress
    local proofObject = verificationData.proof
    local publicKeyHex = verificationData.publicKeyHex
    local originalPayload = verificationData.originalPayload

    -- Check essential config values needed for the HTTP request
    if not Config.CentralServerURL or Config.CentralServerURL == '' or 
       not Config.ServerBuyerWallet or Config.ServerBuyerWallet == '' then
         print("[NFTconnect] ERROR: Missing CentralServerURL or ServerBuyerWallet in config. Cannot verify proof.")
         cb({ verified = false, reason = "Server Configuration Error." })
         return
    end

    local verifyUrl = Config.CentralServerURL .. '/verify-wallet'
    local headers = {
        ['Content-Type'] = 'application/json',
        ['X-Server-Wallet'] = Config.ServerBuyerWallet
    }
    local bodyTable = {
        citizenId = citizenId,
        walletAddress = walletAddress,
        proof = proofObject,
        publicKeyHex = publicKeyHex,
        originalPayload = originalPayload
    }
    local body = json.encode(bodyTable)

    if Config.Debug then print(string.format('[NFTconnect] Performing HTTP request via bridge to verify proof for %s: %s', citizenId, verifyUrl)) end
     if Config.Debug then print(string.format('[NFTconnect][DEBUG] Bridge verification request body: %s', body)) end

    PerformHttpRequest(verifyUrl, function(verifyErrorCode, verifyResponseText, verifyResponseHeaders)
        if Config.Debug then print(string.format('[NFTconnect][SERVER-DEBUG] Central Server /verify-wallet response - Code: %s, Body: %s', verifyErrorCode, verifyResponseText)) end

        local successDecode, verifyResult
        if verifyErrorCode >= 200 and verifyErrorCode < 300 and verifyResponseText and verifyResponseText ~= "" then
             successDecode, verifyResult = pcall(json.decode, verifyResponseText)
             if not successDecode then
                 print("[NFTconnect] ERROR: Could not decode verification response from central server via bridge.")
                 if Config.Debug then print(string.format("Central Server Raw Response: %s", verifyResponseText)) end
                 verifyResult = { verified = false, reason = 'Invalid response format from central server.' }
             end
        else
             print(string.format("[NFTconnect] ERROR: Verification request via bridge failed. Code: %s", verifyErrorCode))
             local errorReason = "Verification failed on central server."
             if verifyResponseText then
                 local _, errData = pcall(json.decode, verifyResponseText)
                 if errData and errData.reason then errorReason = errData.reason
                 elseif errData and errData.error then errorReason = errData.error end
             end
             if Config.Debug then print(string.format("Central Server Response: %s", verifyResponseText)) end
             verifyResult = { verified = false, reason = errorReason }
        end

        -- [[ NEW: Handle First Connection Rewards on Success BEFORE saving mapping ]]
        if verifyResult and verifyResult.verified then
             -- Call the exported function from server_assignments.lua
             -- This function internally checks if it's the first connection based on nftconnect_wallets table
             if Config.EnableFirstConnectionRewards then
                local wasFirstConnection = exports['NFTconnect']:HandleFirstConnectionRewards(src, citizenId)
                if wasFirstConnection then
                    if Config.Debug then print(string.format('[NFTconnect] First connection rewards processed for citizenId %s.', citizenId)) end
                    -- Rewards (notifications, etc.) are handled within HandleFirstConnectionRewards
                end
             else
                 if Config.Debug then print(string.format('[NFTconnect] First connection rewards globally disabled, skipping check for %s.', citizenId)) end
             end

             -- Save mapping *after* checking for first connection rewards
             saveWalletMapping(citizenId, walletAddress)
        end

        -- Regardless of success/failure, send the result back to the client
        cb(verifyResult)

    end, 'POST', body, headers)
end)

-- Function to check specific property ownership
local function DoesPlayerOwnProperty(citizenId, propertyId)
    if not citizenId or not propertyId then return false end
    if Config.Debug then print(string.format("[NFTconnect] Checking ownership for CitizenId: %s, Property ID: %s", citizenId, propertyId)) end

    -- Check PropertiesTable cache first
    if PropertiesTable and next(PropertiesTable or {}) then
        for key, propertyInfo in pairs(PropertiesTable) do
            if propertyInfo.propertyData and propertyInfo.propertyData.owner == citizenId and propertyInfo.propertyData.property_id == propertyId then
                if Config.Debug then print(string.format("[NFTconnect] Found ownership for %s in PropertiesTable cache.", propertyId)) end
                return true
            end
             -- Sometimes the key itself might be the property_id string
             if type(key) == "string" and key == tostring(propertyId) and propertyInfo.propertyData and propertyInfo.propertyData.owner == citizenId then
                 if Config.Debug then print(string.format("[NFTconnect] Found ownership for %s (key match) in PropertiesTable cache.", propertyId)) end
                 return true
             end
        end
         if Config.Debug then print(string.format("[NFTconnect] Ownership for %s not found in PropertiesTable cache. Checking DB.", propertyId)) end
    else
        if Config.Debug then print("[NFTconnect] PropertiesTable cache not available or empty. Checking DB.") end
    end

    -- Fallback to database check
    -- Ensure the table and column names ('properties', 'owner_citizenid', 'property_id') match your ps-housing setup
    local result = MySQL.Sync.fetchAll('SELECT property_id FROM properties WHERE owner_citizenid = ? AND property_id = ? LIMIT 1', { citizenId, propertyId })
    if result and #result > 0 then
        if Config.Debug then print(string.format("[NFTconnect] Found ownership for %s in database.", propertyId)) end
        return true
    end

    if Config.Debug then print(string.format("[NFTconnect] Ownership for %s not found in database.", propertyId)) end
    return false
end

RegisterNetEvent('NFTconnect:server:ProcessRewards', function(rewards)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        print('[NFTconnect] Error: Could not get player object for source ' .. src .. ' in ProcessRewards')
        return
    end
    local citizenId = Player.PlayerData.citizenid
    local playerLicense = Player.PlayerData.license -- Get player license for vehicle insertion

    if Config.Debug then print(string.format('[NFTconnect] Processing %d NFT rewards for source %s (citizenid: %s)', #rewards, src, citizenId)) end

    local hasGrantedReward = false
    local playerWalletAddress = nil -- Store wallet address if found in rewards

    for _, reward in ipairs(rewards) do
        if Config.Debug then print(string.format('[NFTconnect] - Processing NFT reward: type=%s, details=%s', reward.type, json.encode(reward))) end

        -- Store wallet address if it's part of the reward data
        if reward.walletAddress then
            playerWalletAddress = reward.walletAddress
        end

        if reward.type == 'vehicle' and reward.model and reward.plate then
            local vehicleModel = reward.model:lower()
            local plate = reward.plate:upper()
            local vehicleHash = GetHashKey(vehicleModel)

            -- Check if player already owns this specific vehicle model
             MySQL.Async.fetchAll('SELECT plate FROM player_vehicles WHERE citizenid = ? AND vehicle = ?', { citizenId, vehicleModel }, function(existingVehicles)
                if #existingVehicles == 0 then
                     if Config.Debug then print(string.format('[NFTconnect] Player %s does not own NFT vehicle %s yet. Adding...', citizenId, vehicleModel)) end
                     MySQL.Async.execute([[
                        INSERT INTO player_vehicles
                            (license, citizenid, vehicle, hash, mods, plate, fakeplate, garage, fuel, engine, body, state, depotprice, drivingdistance, status)
                        VALUES
                            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                     ]], {
                        playerLicense,             -- license
                        citizenId,                 -- citizenid
                        vehicleModel,              -- vehicle
                        vehicleHash,               -- hash
                        '{}',                      -- mods
                        plate,                     -- plate
                        plate,                     -- fakeplate
                        reward.garage or 'pillboxgarage', -- Use reward garage or default
                        100,                       -- fuel
                        1000.0,                    -- engine
                        1000.0,                    -- body
                        1,                         -- state
                        0,                         -- depotprice
                        0,                         -- drivingdistance
                        '{}',                      -- status
                     }, function (rowsChanged)
                         if rowsChanged > 0 then
                             hasGrantedReward = true
                             if Config.Debug then print(string.format('[NFTconnect] Added NFT vehicle %s with plate %s for %s', vehicleModel, plate, citizenId)) end
                             -- Give Keys
                             if exports['qb-vehiclekeys'] then
                                 exports['qb-vehiclekeys']:GiveKeys(src, plate)
                                 if Config.Debug then print(string.format('[NFTconnect] Gave keys for NFT vehicle plate %s', plate)) end
                             else
                                 if Config.Debug then print('[NFTconnect] WARNING: qb-vehiclekeys not found for NFT vehicle reward.') end
                             end
                             TriggerClientEvent('QBCore:Notify', src, 'Vehicle ' .. vehicleModel .. ' added to your garage via NFT!', 'success')
                             -- Add any other necessary client events for vehicle ownership/keys
                         else
                               if Config.Debug then print(string.format('[NFTconnect] Failed to insert NFT vehicle %s (%s) for %s.', vehicleModel, plate, citizenId)) end
                          end
                      end)
                else
                    if Config.Debug then print(string.format('[NFTconnect] Player %s already owns NFT vehicle model %s. Skipping grant.', citizenId, vehicleModel)) end
                end
            end)

        elseif reward.type == 'property' and reward.propertyId then
            local propertyId = reward.propertyId

            -- 1. Check if player already owns the property
            if DoesPlayerOwnProperty(citizenId, propertyId) then
                if Config.Debug then print(string.format('[NFTconnect] Player %s already owns property %s. Skipping NFT reward grant.', citizenId, propertyId)) end
                goto continue -- Skip to next reward if already owned
            end

            -- 2. Player does not own it, proceed with NFT grant logic
            if Config.Debug then print(string.format('[NFTconnect] Granting NFT property %s to %s.', propertyId, citizenId)) end

            -- 3. Verify ps-housing export exists
            if exports['ps-housing'] then
                -- 4. Construct the data table *explicitly setting nft_based = true*
                local propertyGrantData = {
                    targetSrc = src,       -- The player receiving the property
                    realtorSrc = src,      -- Use player's source as realtor for NFT grants
                    property_id = propertyId,
                    nft_based = true       -- CRUCIAL: Flag for ps-housing to skip payment
                }

                -- 5. Trigger the specific ps-housing event
                TriggerEvent("ps-housing:server:UpdateOwner", propertyGrantData)

                -- 6. Post-grant actions (notifications, etc.)
                hasGrantedReward = true
                TriggerClientEvent('QBCore:Notify', src, 'Property ' .. propertyId .. ' assigned based on your NFT!', 'success')
                if Config.Debug then print(string.format('[NFTconnect] Triggered ps-housing:server:UpdateOwner for NFT property %s, citizen %s', propertyId, citizenId)) end

            else
                -- Handle missing ps-housing dependency
                print('[NFTconnect] WARNING: Property reward received but ps-housing is not available or export not found.')
                TriggerClientEvent('QBCore:Notify', src, "Property reward could not be applied. Contact admins (ps-housing missing).", 'error')
            end

            -- Label for the goto statement to skip grant if already owned
            ::continue::

        elseif reward.type == 'item' and reward.item and reward.amount then
            local item = reward.item
            local amount = tonumber(reward.amount) or 1
            if Player.Functions.AddItem(item, amount) then
                 TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], "add")
                 TriggerClientEvent('QBCore:Notify', src, 'Received '..amount..'x '..(QBCore.Shared.Items[item].label)..' via NFT!', 'success')
                 hasGrantedReward = true
                 if Config.Debug then print(string.format('[NFTconnect] Granted item %s x%d to %s', item, amount, citizenId)) end
            else
                 if Config.Debug then print(string.format('[NFTconnect] Failed to grant item %s x%d to %s', item, amount, citizenId)) end
                 TriggerClientEvent('QBCore:Notify', src, 'Could not receive item '..(QBCore.Shared.Items[item].label)..' (Inventory full?)', 'error')
            end
        -- Add other reward types as needed
        else
            if Config.Debug then print(string.format('[NFTconnect] Skipping unknown or incomplete NFT reward type: %s', reward.type or 'nil')) end
        end

        -- Small wait between processing multiple rewards if necessary
        Wait(50)

    end -- end loop rewards

end)

-- Debug print function for revocation
local function DebugRevoke(message)
    if Config.Debug then
        print('[NFTconnect:Revoker] ' .. message)
    end
end

-- Function to revoke a vehicle from a player
-- Takes citizenId and rewardDetails (which should contain model and optionally plate)
local function RevokeVehicle(citizenId, rewardDetails)
    if not rewardDetails or not rewardDetails.model then
        DebugRevoke("Cannot revoke vehicle: Missing model in rewardDetails.")
        return
    end
    local vehicleModel = rewardDetails.model:lower()
    local plate = rewardDetails.plate -- Plate might not always be present/needed for removal

    DebugRevoke(string.format("Attempting to revoke vehicle model %s for citizen %s", vehicleModel, citizenId))

    -- Remove vehicle from database
    MySQL.Async.execute('DELETE FROM player_vehicles WHERE citizenid = ? AND vehicle = ?',
        {citizenId, vehicleModel},
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                DebugRevoke(string.format("Successfully removed vehicle %s from citizen %s (DB rows: %d)", vehicleModel, citizenId, rowsChanged))

                -- Find player if online to notify them
                local player = QBCore.Functions.GetPlayerByCitizenId(citizenId)
                if player then
                    TriggerClientEvent('QBCore:Notify', player.PlayerData.source, 'Vehicle ' .. vehicleModel:upper() .. ' has been removed - NFT ownership verification failed', 'error', 7500)
                end
            else
                DebugRevoke(string.format("No vehicle %s found for citizen %s to revoke, or DB delete failed (rows changed: %s)", vehicleModel, citizenId, tostring(rowsChanged)))
            end
        end
    )
end

-- Function to revoke a property from a player
-- Takes citizenId and rewardDetails (which should contain propertyId)
local function RevokeProperty(citizenId, rewardDetails)
    if not rewardDetails or not rewardDetails.propertyId then
        DebugRevoke("Cannot revoke property: Missing propertyId in rewardDetails.")
        return
    end
    local propertyId = rewardDetails.propertyId

    DebugRevoke(string.format("Attempting to revoke property %s from citizen %s via direct DB update.", propertyId, citizenId))

    -- Use direct DB update like nft_checker
    MySQL.Async.execute('UPDATE properties SET owner_citizenid = NULL, for_sale = 1 WHERE property_id = ? AND owner_citizenid = ?',
        {propertyId, citizenId},
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                DebugRevoke(string.format("Successfully revoked property %s from citizen %s via DB (rows: %d)", propertyId, citizenId, rowsChanged))
                
                -- Trigger client events to update UI (Important!)
                TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateOwner", propertyId, nil) -- -1 targets all clients
                TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateForSale", propertyId, 1) -- -1 targets all clients
                
                -- Find player if online to notify them
                local player = QBCore.Functions.GetPlayerByCitizenId(citizenId)
                if player then
                    TriggerClientEvent('QBCore:Notify', player.PlayerData.source, 'Property ' .. propertyId .. ' has been removed - NFT ownership verification failed', 'error', 7500)
                end
            else
                DebugRevoke(string.format("No property %s owned by citizen %s found to revoke, or DB update failed (rows changed: %s)", propertyId, citizenId, tostring(rowsChanged)))
            end
        end
    )
end

-- Revoke Item
local function RevokeItem(citizenId, rewardDetails)
    if not rewardDetails or not rewardDetails.item or not rewardDetails.amount then
        DebugRevoke("Cannot revoke item: Missing item/amount details.")
        return
    end
    local itemName = rewardDetails.item
    local amount = tonumber(rewardDetails.amount) or 1
    DebugRevoke(string.format("Attempting to revoke item %s x%d from citizen %s", itemName, amount, citizenId))
    
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenId)
    if Player then
        local success = Player.Functions.RemoveItem(itemName, amount)
        if success then
             DebugRevoke(string.format("Successfully removed item %s x%d from citizen %s's inventory", itemName, amount, citizenId))
             TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, string.format('Item %s x%d removed - NFT ownership verification failed', itemName, amount), 'error', 7500)
        else
             DebugRevoke(string.format("Failed to remove item %s x%d from citizen %s's inventory (Item not found?)", itemName, amount, citizenId))
             -- Notify anyway, as the intent was revocation
             TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, string.format('Attempted to revoke item %s x%d (NFT check failed), but item not found in inventory.', itemName, amount), 'warning', 7500)
        end
    else
        DebugRevoke(string.format("Cannot revoke item %s for citizen %s - Player offline.", itemName, citizenId))
    end
end

local function ConfirmProcessedRevocations(processedIds)
    if not processedIds or #processedIds == 0 then
        DebugRevoke("No processed revocations to confirm.")
        return
    end

    if not Config.CentralServerURL or Config.CentralServerURL == '' or 
       not Config.ServerBuyerWallet or Config.ServerBuyerWallet == '' then
        print("[NFTconnect:Revoker] ERROR: Missing CentralServerURL or ServerBuyerWallet in config. Cannot confirm revocations.")
        return
    end

    local confirmUrl = Config.CentralServerURL .. '/revocations/confirm'
    local headers = {
        ['Content-Type'] = 'application/json',
        ['X-Server-Wallet'] = Config.ServerBuyerWallet
    }
    local bodyTable = { activationIds = processedIds }
    local body = json.encode(bodyTable)

    DebugRevoke(string.format("Sending confirmation for %d revocation IDs to %s", #processedIds, confirmUrl))

    PerformHttpRequest(confirmUrl, function(errorCode, responseText, responseHeaders)
        if errorCode >= 200 and errorCode < 300 then
            local success, responseData = pcall(json.decode, responseText)
            if success and responseData then
                DebugRevoke(string.format("Successfully confirmed revocations. Central server response: Confirmed=%d, Failed=%d", responseData.confirmed or 0, responseData.failed or 0))
            else
                DebugRevoke("Successfully sent confirmation, but response was invalid or empty.")
            end
        else
            print(string.format("[NFTconnect:Revoker] ERROR: Failed to confirm processed revocations with central server. Code: %s, Response: %s", errorCode, responseText))
        end
    end, 'POST', body, headers)
end

local function CheckForRevocations()
    DebugRevoke("Checking central server for pending revocations...")

    if not Config.CentralServerURL or Config.CentralServerURL == '' or 
       not Config.ServerBuyerWallet or Config.ServerBuyerWallet == '' then
        print("[NFTconnect:Revoker] ERROR: Missing CentralServerURL or ServerBuyerWallet in config. Cannot check for revocations.")
        return
    end

    local checkUrl = Config.CentralServerURL .. '/revocations/pending'
    local headers = {
        ['X-Server-Wallet'] = Config.ServerBuyerWallet
    }

    PerformHttpRequest(checkUrl, function(errorCode, responseText, responseHeaders)
        if errorCode ~= 200 then
            print(string.format("[NFTconnect:Revoker] ERROR: Failed to fetch pending revocations from central server. Code: %s, Response: %s", errorCode, responseText))
            return
        end

        local success, responseData = pcall(json.decode, responseText)
        if not success or not responseData or type(responseData.pendingRevocations) ~= 'table' then
            print(string.format("[NFTconnect:Revoker] ERROR: Invalid response format from central server /revocations/pending. Response: %s", responseText))
            return
        end

        local pending = responseData.pendingRevocations
        if #pending == 0 then
            DebugRevoke("No pending revocations found.")
            return
        end

        DebugRevoke(string.format("Received %d pending revocation(s) from central server.", #pending))
        local processedIds = {}

        for _, revocation in ipairs(pending) do
            local citizenId = revocation.player_citizen_id
            local rewardType = revocation.reward_type
            local rewardDetails = revocation.reward_details -- Already a table from central server
            local activationId = revocation.activationId
            local nftAddress = revocation.nft_address

            if citizenId and rewardType and rewardDetails and activationId then
                DebugRevoke(string.format("Processing pending revocation ID %d: Citizen=%s, Type=%s, NFT=%s", activationId, citizenId, rewardType, nftAddress))
                
                -- Call the appropriate local revocation function
                if rewardType == 'vehicle' then
                    RevokeVehicle(citizenId, rewardDetails)
                elseif rewardType == 'property' then
                    RevokeProperty(citizenId, rewardDetails)
                elseif rewardType == 'item' then
                    RevokeItem(citizenId, rewardDetails)
                else
                    DebugRevoke(string.format("Skipping unknown reward type '%s' for revocation ID %d.", rewardType, activationId))
                end
                -- Add to list to confirm processing with central server
                table.insert(processedIds, activationId)
            else
                DebugRevoke(string.format("Skipping invalid pending revocation data received: %s", json.encode(revocation)))
            end
        end

        -- Confirm processed revocations with the central server
        if #processedIds > 0 then
            ConfirmProcessedRevocations(processedIds)
        end

    end, 'GET', nil, headers)
end

Citizen.CreateThread(function()
    -- Initial delay before first check
    Citizen.Wait(60 * 1000) -- Wait 1 minute

    while true do
        local intervalMinutes = tonumber(Config.RevocationCheckIntervalMinutes) or 5
        if intervalMinutes > 0 then
            CheckForRevocations()
            -- Wait for the configured interval
            Citizen.Wait(intervalMinutes * 60 * 1000) 
        else
            DebugRevoke("Revocation check interval is 0 or invalid, disabling periodic checks.")
            -- Wait a long time if disabled to avoid busy-looping
            Citizen.Wait(3600 * 1000) -- Wait 1 hour
        end
    end
end)

-- Ensure the necessary MySQL functions are available if using oxmysql
if not MySQL then
    MySQL = exports.oxmysql
end