fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'SSRP'
description 'SSRP Business Management - businesses, payroll shifts, AFK state, and Hybrid Pay integration hooks'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/database.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependency 'oxmysql'
