fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    'client/framework.lua',
    'client/functions.lua',
    'client/main.lua'
}

server_scripts {
    'server/framework.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'data/**/vehicles.meta',
    'data/**/carvariations.meta',
    'data/**/carcols.meta',
    'data/**/handling.meta',
}

data_file 'HANDLING_FILE' 'data/**/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/**/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/**/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/**/carvariations.meta'

dependencies {
    'PolyZone'
}