local function every(seconds, name, fn)
    CreateThread(function()
        while not TC.ready do Wait(500) end
        Wait(math.random(1000, 5000)) -- stagger
        while true do
            local ok, err = pcall(fn)
            if not ok then print(('[truckco] %s tick error: %s'):format(name, err)) end
            Wait(seconds * 1000)
        end
    end)
end

every(Config.Board.generateEvery, 'generate', TC.tickGenerate)
every(10, 'resolveBids', TC.tickResolveBids)
every(15, 'npcRuns', TC.tickNpcRuns)
every(15, 'playerRuns', TC.tickPlayerRuns)
every(20, 'training', TC.tickTraining)
every(30, 'expireAwards', TC.tickExpireAwards)
every(Config.Dispatch.interval, 'dispatch', TC.tickDispatch)
every(60, 'payroll', TC.tickPayroll)

--------------------------------------------------------------------------------
-- Admin helpers
--------------------------------------------------------------------------------
lib.addCommand('truckco_pos', {
    help = 'Print your coords (for configuring trucking properties)',
    restricted = 'group.admin',
}, function(source)
    local c = GetEntityCoords(GetPlayerPed(source))
    local h = GetEntityHeading(GetPlayerPed(source))
    local s = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, h)
    print('[truckco] ' .. s)
    TriggerClientEvent('truckco:client:copy', source, s)
end)

lib.addCommand('truckco_furnish', {
    help = 'Move office furniture / exit point and print config lines (stand inside an office)',
    restricted = 'group.admin',
}, function(source)
    TriggerClientEvent('truckco:client:furnish', source)
end)

lib.addCommand('truckco_board', {
    help = 'Force-generate contracts on the trucking bid board',
    restricted = 'group.admin',
    params = { { name = 'count', type = 'number', optional = true } },
}, function(source, args)
    for _ = 1, math.min(args.count or 5, 20) do pcall(TC.tickGenerate) end
    TC.notify(source, 'Bid board refreshed.', 'success')
end)

lib.addCommand('truckco_givefunds', {
    help = 'Add money to a trucking company balance',
    restricted = 'group.admin',
    params = {
        { name = 'company', type = 'number', help = 'company id' },
        { name = 'amount', type = 'number' },
    },
}, function(source, args)
    if not TC.getCompany(args.company) then return TC.notify(source, 'No such company.', 'error') end
    TC.addFunds(args.company, args.amount, 'Admin adjustment')
    TC.notify(source, 'Funds added.', 'success')
end)

-- On resource stop: put everyone back in the main world and clear spawned vehicles.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(TC.inside) do SetPlayerRoutingBucket(src, 0) end
    for _, run in pairs(TC.runs) do
        TC.deleteNet(run.truckNet)
        TC.deleteNet(run.trailerNet)
    end
end)

-- Self-check: if a file listed in fxmanifest.lua didn't load (usually because the
-- server is still using a cached old manifest), say so loudly.
CreateThread(function()
    Wait(2000)
    local missing = {}
    for fn, file in pairs({ propPoint = 'server/places.lua', cadRegisterTruck = 'server/cad.lua', startNpcRun = 'server/runs.lua', tickDispatch = 'server/dispatch.lua' }) do
        if type(TC[fn]) ~= 'function' then missing[#missing + 1] = file end
    end
    if #missing > 0 then
        print(('^1[truckco] NOT LOADED: %s. Run "refresh" then "ensure %s" (FiveM caches fxmanifest.lua), and make sure the whole folder is up to date.^0')
            :format(table.concat(missing, ', '), GetCurrentResourceName()))
    else
        print(('^2[truckco] %s v%s loaded^0'):format(GetCurrentResourceName(), GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '?'))
    end
end)
