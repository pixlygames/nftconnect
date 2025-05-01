-- config.lua
-- IMPORTANT: Only the 'Config.ServerBuyerWallet' setting below is STRICTLY REQUIRED
--            for the script to connect to the central verification server.
--            The ServerName, ServerIP, and ServerEmail fields are collected once for
--            informational and support purposes but are NOT used for authentication.
Config = {}

Config.CentralServerURL = 'https://nft.pixly.games' -- Do not change, it's a verification server for NFTs

-- REQUIRED for connection. This should be your public TON wallet address. Receives 40% share of all NFT sales from your server. 
Config.ServerBuyerWallet = 'EQBmuQ8GKlpRja2lN6eXqhT1snEaqkmVOxh-lJ3elOFhxukl' -- Replace with YOUR TON wallet

-- A descriptive name for your server (Informational Only)
Config.ServerName = 'Pixly Server (Example)' -- Replace with YOUR server's name

-- The public IP address of your FiveM server (Informational Only)
Config.ServerIP = '127.0.0.1' -- Replace with YOUR server's public IP

-- Your contact email address (Informational Only)
Config.ServerEmail = 'admin@example.com' -- Replace with YOUR contact email

-- Key to press to open the TON Wallet connection UI
Config.OpenKey = 'F12'

-- Enable debug printing (true/false)
Config.Debug = true

-- How often (in minutes) NFTconnect should check the central server for pending revocations
Config.RevocationCheckIntervalMinutes = 5

-- Locales and notifications
Config.Locale = 'en'
Locales = {}
Locales['en'] = {
    ['verify_success_notify'] = 'Wallet verified! Rewards applied based on your NFTs.',
    ['verify_fail_notify'] = 'Wallet verification failed: %s',
    ['vehicle_added_notify'] = 'Vehicle %s (%s) added to your garage!',
    ['property_added_notify'] = 'Access granted to property ID %s!',
    ['no_rewards'] = 'Wallet verified, but no specific rewards found for your NFTs at this time.',
    ['error_contact_support'] = 'An error occurred. Please contact server support.'
}

-- Helper function for translations
Lang = function(key, ...)
    local translation = Locales[Config.Locale] and Locales[Config.Locale][key]
    if translation then
        if #{...} > 0 then
            return translation:format(...)
        else
            return translation
        end
    else
        return key -- Return the key if translation not found
    end
end

-- [[ First Connection Rewards ]]
Config.EnableFirstConnectionRewards = true -- Grant rewards below only for the *first* time a player connects their wallet (motivates players to create a wallet)

-- Apartment Reward
Config.GrantApartmentOnFirstConnect = true -- Grant a default apartment on first connection. (Requires ps-housing and High End Motel IPL)
Config.DefaultApartmentName = "HighEndMotel" -- The name of the apartment type in ps-housing config
Config.ApartmentNotifyMessage = "You received a High End Motel apartment for connecting your wallet!"
Config.ApartmentWaypointX = -294.57
Config.ApartmentWaypointY = -828.53
Config.ApartmentWaypointZ = 32.42
Config.ApartmentWaypointH = 53.77
Config.ApartmentEmailSender = "Realtor"
Config.ApartmentEmailSubject = "Your New Apartment"
Config.ApartmentEmailMessage = "Welcome! Your new apartment is ready. Head to the location marked on your map."

-- Car Reward
Config.GrantCarOnFirstConnect = true -- Grant a default car on first connection? (Requires qb-vehiclekeys)
Config.DefaultCarModel = "asbo" -- Vehicle spawn code (can be changed)
Config.DefaultCarGarage = "pillboxgarage" -- Default garage to add the car to
Config.CarNotifyMessage = "You received a free car (%s) for connecting your wallet! Check your email." -- %s will be replaced with car model
Config.CarEmailSender = "Car Dealer"
Config.CarEmailSubject = "Your New Vehicle"
Config.CarEmailMessage = "Congratulations on your new %s! It has been delivered to the Pillbox Parking Garage." -- %s will be replaced with car model

-- Shared Notification
Config.LongNotifyMessage = "Press [M] to read email on your phone" -- Shown after rewards are granted
Config.LongNotifyDuration = 20000 -- Duration in milliseconds (20 seconds)