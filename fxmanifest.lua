-- fxmanifest.lua
fx_version 'cerulean'
games { 'gta5' }

author 'Pixly Games'
description 'Connect TON Wallet for NFT-based rewards, bridged to a central verification server.'
version '1.1.0'

lua54 'yes'

ui_page 'nui/index.html'

shared_scripts {
    '@qb-core/shared/locale.lua', -- Assuming QBCore for config access
    'locales/en.lua', -- Example locale
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Dependency for server bridge storage
    'server_bridge.lua',
    'server_assignments.lua'
}

files {
    'nui/index.html',
    'nui/script.js',
    'nui/styles.css',
    'locales/en.lua'
}

-- Ensure necessary dependencies start before this script
dependencies {
    'qb-core',
    'oxmysql',
    'ps-housing',
    'qb-vehiclekeys',
    'qb-phone'
}

escrow_ignore {
    'config.lua', -- Allow server owners to configure
    'locales/*.lua', -- Allow translation
    'server_assignments.lua'
} 