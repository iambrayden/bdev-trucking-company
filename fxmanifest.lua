fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-trucking-company'
author 'bdev'
description 'Player-owned trucking companies for Qbox: offices, employees (NPC + players), fleet, insurance, bid board and automated dispatch'
version '1.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
    'shared/defaults.lua',
    'shared/utils.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
    'client/office.lua',
    'client/tablet.lua',
    'client/signs.lua',
    'client/runs.lua',
    'client/garage.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/db.lua',
    'server/places.lua',
    'server/company.lua',
    'server/employees.lua',
    'server/fleet.lua',
    'server/cad.lua',
    'server/contracts.lua',
    'server/runs.lua',
    'server/garage.lua',
    'server/dispatch.lua',
    'server/finance.lua',
    'server/payroll.lua',
    'server/ticks.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sign.html',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_target',
}
