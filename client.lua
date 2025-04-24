-- client.lua
local QBCore = exports['qb-core']:GetCoreObject()
local nuiOpen = false
local citizenId = nil -- Make sure this is populated
local isRegistered = false -- Flag to prevent duplicate registration

-- Store payload generated for the current player session (nonce)
local currentSessionPayload = nil

local commandName = "nftconnect" -- Simplified command name

-- Manifest URL (don't change)
local hardcodedManifestUrl = 'https://raw.githubusercontent.com/pixlygames/manifest/refs/heads/main/tonconnect-manifest.json'

-- Function to SET NUI focus state
local function SetNuiFocusState(hasFocus, hasCursor)
    if Config.Debug then print(string.format('[NFTconnect] Setting NUI focus: %s, Cursor: %s', tostring(hasFocus), tostring(hasCursor))) end
    _G.SetNuiFocus(hasFocus, hasCursor)
    nuiOpen = hasFocus
end

-- Function to send messages to NUI
local function SendNui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
    if Config.Debug then print(string.format('[NFTconnect] Sent NUI message: %s', action)) end
end

-- Get Player Data on startup
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.citizenid then
        print("[NFTconnect] ERROR: Could not get valid PlayerData on load.")
        return
    end
    citizenId = PlayerData.citizenid
    if Config.Debug then print(string.format('[NFTconnect] Player loaded: %s.', citizenId)) end

    -- Register command/keybind only once after player loads
    if not isRegistered then
        -- Command Handler to toggle the NUI
        RegisterCommand(commandName, function(source, args, rawCommand)
            if not Config.CentralServerURL or Config.CentralServerURL == '' then
                QBCore.Functions.Notify("NFT Connect is not configured correctly.", "error", 5000)
                if Config.Debug then print('[NFTconnect] Command executed but config missing CentralServerURL.') end
                return
            end

            local shouldOpen = not nuiOpen
            if Config.Debug then print(string.format('[NFTconnect] Command toggle. Should open: %s', tostring(shouldOpen))) end

            SendNUIMessage({ type = "ui", display = shouldOpen }) 
            SetNuiFocusState(shouldOpen, shouldOpen)

            if shouldOpen then
                 currentSessionPayload = nil
                 if Config.Debug then print('[NFTconnect] Cleared session payload on NUI open.') end
            end
        end, false)

        RegisterKeyMapping(commandName, "Connect TON Wallet (NFT)", "keyboard", Config.OpenKey)
        isRegistered = true
        if Config.Debug then print(string.format('[NFTconnect] Registered command /%s with key mapping %s', commandName, Config.OpenKey)) end
    end
end)

-- Handle player state changes
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if nuiOpen then
        if Config.Debug then print('[NFTconnect] Player unload detected while NUI open, forcing close.') end
        SendNUIMessage({ type = "ui", display = false }) -- Tell NUI to hide
        SetNuiFocusState(false, false) -- Ensure focus is released
    end
    citizenId = nil
    isRegistered = false -- Allow re-registration if player reloads
    currentSessionPayload = nil -- Clear session payload
    if Config.Debug then print('[NFTconnect] Player unloaded') end
end)

-- NUI Callback: NUI requests the Manifest URL
RegisterNUICallback('getManifestUrl', function(data, cb)
    if Config.Debug then print('[NFTconnect] NUI requested Manifest URL. Returning hardcoded value.') end
    -- Return the hardcoded URL directly
    cb(hardcodedManifestUrl)

end)

-- NUI Callback: NUI requests a payload (nonce) for this connection attempt
RegisterNUICallback('requestPayload', function(data, cb)
    if not citizenId then
        print("[NFTconnect] ERROR: Cannot generate payload, citizenId is nil.")
        cb({ error = "Missing citizenId" })
        return
    end

    -- Ask the server to generate/fetch the payload from the central server
    if Config.Debug then print(string.format('[NFTconnect] Requesting payload from server bridge for citizenId: %s', citizenId)) end

    QBCore.Functions.TriggerCallback('NFTconnect:server:GeneratePayload', function(payload)
        if payload then
            currentSessionPayload = payload -- Store the payload received from the server bridge
            if Config.Debug then print(string.format('[NFTconnect] Received payload from server bridge: %s', payload)) end
            cb({ payload = payload }) -- Send the payload back to NUI
        else
            print("[NFTconnect] ERROR: Failed to get payload from server bridge.")
            cb({ error = 'Failed to get session data from server.' })
            currentSessionPayload = nil -- Ensure no stale payload
        end
    end, citizenId) -- Pass citizenId to the server callback

end)

-- NUI Callback: NUI submits the signed proof for verification
RegisterNUICallback('submitProof', function(data, cb)
    -- Acknowledge receipt immediately
    cb({ status = 'received' })
    if Config.Debug then print('[NFTconnect] Received proof submission from NUI.') end
    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Received submitProof data: %s', json.encode(data))) end

    if not citizenId then
        print("[NFTconnect] ERROR: Cannot verify proof, citizenId is nil.")
        SendNui('verificationFailed', { message = 'Internal error: Player data missing.'})
        return
    end

    -- Validate received data structure (essential parts, including nested proof)
    if not data or not data.walletInfo or not data.walletInfo.account or not data.walletInfo.account.address or not data.walletInfo.account.publicKey or
       not data.proof or not data.proof.proof or not data.proof.proof.payload or not data.proof.proof.signature then
        print("[NFTconnect] ERROR: Invalid data structure received for proof submission (checked nested proof).")
        if Config.Debug then print(string.format("[NFTconnect][DEBUG] Invalid data dump: %s", json.encode(data))) end
        SendNui('verificationFailed', { message = 'Internal error: Invalid data from UI.'})
        return
    end

    local walletInfo = data.walletInfo
    local nestedProof = data.proof.proof -- Get the inner proof object
    local walletAddress = walletInfo.account.address -- Raw address
    local publicKeyHex = walletInfo.account.publicKey -- Public Key directly from walletInfo
    local receivedPayload = nestedProof.payload -- The payload that was actually signed by the wallet (from inner proof)

    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Extracted Wallet Address: %s', walletAddress)) end
    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Extracted Public Key: %s...', string.sub(publicKeyHex, 1, 10))) end
    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Received Signed Payload (from nested proof): %s', receivedPayload)) end

    -- Retrieve the original payload stored for this session
    local originalPayload = currentSessionPayload
    if not originalPayload then
        print(string.format("[NFTconnect] ERROR: No session payload found for current verification attempt. CitizenId: %s", citizenId))
        SendNui('verificationFailed', { message = 'Verification session expired or invalid.'})
        return
    end
    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Retrieved Original Session Payload: %s', originalPayload)) end

    -- Compare the payload signed by the wallet with the one we generated
    if receivedPayload ~= originalPayload then
         print(string.format("[NFTconnect] ERROR: Payload mismatch! Signed: %s, Expected: %s", receivedPayload, originalPayload))
         SendNui('verificationFailed', { message = 'Payload mismatch. Please try connecting again.' })
         -- Clear the potentially compromised session payload
         currentSessionPayload = nil
         return
    end

    -- Payload matches, proceed to central server verification via server bridge
    currentSessionPayload = nil -- Consume the payload after successful match

    -- Data to send to the server bridge
    local dataToSend = {
        citizenId = citizenId,
        walletAddress = walletAddress,
        proof = nestedProof, -- Pass the nested proof object { timestamp, domain, signature, payload }
        publicKeyHex = publicKeyHex,
        originalPayload = originalPayload -- The original nonce we matched
    }

    if Config.Debug then print('[NFTconnect] Triggering server bridge callback \'NFTconnect:server:VerifyProof\'...') end
    if Config.Debug then print(string.format('[NFTconnect][DEBUG] Data being sent to server bridge: %s', json.encode(dataToSend))) end

    -- Trigger the server callback
    QBCore.Functions.TriggerCallback('NFTconnect:server:VerifyProof', function(verifyResult)
        if Config.Debug then print(string.format('[NFTconnect] Received verification result from server bridge: %s', json.encode(verifyResult))) end

        if not verifyResult then
             print("[NFTconnect] ERROR: No response received from server bridge verification callback.")
             SendNui('verificationFailed', { message = 'Internal error: Server bridge did not respond.'})
             return
        end

        -- Process the result from the server bridge
        if verifyResult.verified then
            print(string.format('[NFTconnect] Wallet %s verified successfully for citizen %s (via bridge).', walletAddress, citizenId))
            -- Send NFT data and reward info back to NUI
            SendNui('nftData', { data = verifyResult }) -- Send the full result which includes nfts/rewards
            -- Trigger server event to handle rewards processing (if any)
            if verifyResult.rewards and #verifyResult.rewards > 0 then
                if Config.Debug then print(string.format('[NFTconnect] Triggering server reward processing for %d rewards.', #verifyResult.rewards)) end
                local rewardData = verifyResult.rewards
                -- Wallet address should already be included by central server, but double-check
                if not rewardData[1] or not rewardData[1].walletAddress then
                     if Config.Debug then print('[NFTconnect] Adding wallet address to reward data before sending to server.') end
                    for i, reward in ipairs(rewardData) do reward.walletAddress = walletAddress end
                end
                TriggerServerEvent('NFTconnect:server:ProcessRewards', rewardData)
            end
            QBCore.Functions.Notify("Wallet verified successfully!", "success", 3000)
            CreateThread(function()
                 Wait(7000) -- Wait 7 seconds to show results
                 if nuiOpen then -- Check if still open
                     SendNUIMessage({ type = "ui", display = false })
                     SetNuiFocusState(false, false)
                 end
            end)

        else
            print(string.format('[NFTconnect] Wallet verification failed for %s (via bridge). Reason: %s', walletAddress, verifyResult.reason or 'Unknown'))
            SendNui('verificationFailed', { message = verifyResult.reason or 'Verification denied by server.' })
            CreateThread(function()
                 Wait(3000) -- Wait 3 seconds
                 if nuiOpen then
                     SendNUIMessage({ type = "ui", display = false })
                     SetNuiFocusState(false, false)
                 end
            end)
        end

    end, dataToSend) -- Pass the data table to the server callback
end)

-- NUI Callback: Handle NUI close request (e.g., ESC key)
RegisterNUICallback('hideUI', function(data, cb)
    if nuiOpen then
        if Config.Debug then print('[NFTconnect] NUI requested hideUI via callback (ESC).') end
        -- Tell NUI to hide itself via message (handled in NUI script)
        SendNUIMessage({ type = "ui", display = false })
        -- Release focus
        SetNuiFocusState(false, false)
        cb({ status = 'closed' }) -- Acknowledge closure
    else
        cb({ status = 'already_closed'})
    end
end)

-- Helper to check if a table is empty
local function is_empty(tbl)
    return not next(tbl)
end

-- [[ NEW: Event Handlers for First Connection Rewards ]]

-- Set Waypoint (Used for Apartment)
RegisterNetEvent('NFTconnect:client:SetWaypoint', function(x, y, z)
    SetNewWaypoint(x, y)
    if Config.Debug then print(string.format('[NFTconnect] Waypoint set to: %s, %s', x, y)) end
end)

-- Show Long Notification (Used after rewards)
RegisterNetEvent('NFTconnect:client:ShowLongNotification', function(message, duration)
    QBCore.Functions.Notify(message, "primary", duration)
    if Config.Debug then print(string.format('[NFTconnect] Long notification shown: "%s" for %dms', message, duration)) end
end)

-- Send Apartment Email (Requires qb-phone)
RegisterNetEvent('NFTconnect:client:SendApartmentEmail', function()
    local mailData = {
        sender = Config.ApartmentEmailSender,
        subject = Config.ApartmentEmailSubject,
        message = Config.ApartmentEmailMessage,
        button = {} -- Add button if needed, e.g., { enabled = true, buttonEvent = "some_event", buttonText = "View Listing" }
    }
    -- Trigger notification for new mail
    TriggerEvent('qb-phone:client:NewMailNotify', mailData)
    -- Send mail to server to actually add it (adjust if your qb-phone handles this differently)
    TriggerServerEvent('qb-phone:server:sendNewMail', mailData)
    if Config.Debug then print(string.format('[NFTconnect] Sent apartment email. Sender: %s', Config.ApartmentEmailSender)) end
end)

-- Send Car Email (Requires qb-phone)
RegisterNetEvent('NFTconnect:client:SendCarEmail', function(carModel)
    local mailData = {
        sender = Config.CarEmailSender,
        subject = Config.CarEmailSubject,
        message = string.format(Config.CarEmailMessage, carModel:upper()), -- Format message with car model
        button = {}
    }
    -- Trigger notification for new mail
    TriggerEvent('qb-phone:client:NewMailNotify', mailData)
    -- Send mail to server to actually add it
    TriggerServerEvent('qb-phone:server:sendNewMail', mailData)
    if Config.Debug then print(string.format('[NFTconnect] Sent car email for model %s. Sender: %s', carModel, Config.CarEmailSender)) end
end)

-- [[ END NEW ]]

print('[NFTconnect] Client script loaded.') 