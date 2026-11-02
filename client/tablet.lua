--[[
    Company tablet (NUI). The UI in html/ talks to the server through the same
    callbacks the old menus used, via a whitelisted bridge below. All permission
    checks stay server-side.
]]

local isOpen = false
local tabletObj = nil
local nuiReady = false
local openToken = 0

-- server callbacks the tablet may invoke
local ALLOWED = {
    getDashboard = true, getEmployees = true, getCandidates = true, hireCandidate = true,
    invitePlayer = true, fireEmployee = true, setRole = true, setWage = true, trainEmployee = true,
    getFleet = true, buyTruck = true, repairTruck = true, setInsurance = true, sellTruck = true,
    getBoard = true, placeBid = true, withdrawBid = true,
    getMyContracts = true, getAssignOptions = true, assignContract = true, unassignContract = true,
    buyUpgrade = true, saveSettings = true,
    deposit = true, withdraw = true, getLedger = true,
    joinRoster = true, renameCompany = true, sellCompany = true, quitCompany = true,
    getMyAssignments = true, toggleDuty = true, collectPay = true,
    buyProperty = true,
    setPlace = true, resetLayout = true,
    giveBonus = true, getLoans = true, takeLoan = true, repayLoan = true,
    clockOutEmployee = true,
}

-- static data the UI needs (sent once per open)
local function uiConfig()
    local props = {}
    for id, p in pairs(Config.Properties) do
        local int = Config.Interiors[p.interior]
        props[id] = { label = p.label, price = p.price, upkeep = p.upkeep, interior = int and int.label or p.interior }
    end
    return {
        currency = Config.Currency,
        roles = Config.Roles,
        certifications = Config.Certifications,
        trucks = Config.Trucks,
        insurance = Config.Insurance,
        upgrades = Config.Upgrades,
        cargo = Config.Cargo,
        properties = props,
        base = Config.Base,
        fleet = { minDispatchCondition = Config.Fleet.minDispatchCondition, sellRefund = Config.Fleet.sellRefund },
        payrollMinutes = Config.Payroll.intervalMinutes,
        overdraftLimit = Config.Payroll.overdraftLimit,
        propertyRefund = Config.Economy.propertyRefund,
        hireFee = Config.NPC.hireFee,
        driverCommission = Config.Runs.driverCommission,
        perms = TCShared.Perms,
        signs = { max = Config.Signs.max, price = Config.Signs.price },
        bonusMax = Config.Bonus and Config.Bonus.max or 50000,
    }
end

local function startProp()
    local ped = cache.ped
    local cfg = Config.Tablet
    if IsPedInAnyVehicle(ped, false) then return end
    lib.requestAnimDict(cfg.anim.dict, 3000)
    TaskPlayAnim(ped, cfg.anim.dict, cfg.anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
    lib.requestModel(cfg.prop, 3000)
    local c = GetEntityCoords(ped)
    tabletObj = CreateObject(cfg.prop, c.x, c.y, c.z + 0.2, true, true, false)
    AttachEntityToEntity(tabletObj, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(cfg.prop)
end

local function stopProp()
    if tabletObj and DoesEntityExist(tabletObj) then DeleteEntity(tabletObj) end
    tabletObj = nil
    StopAnimTask(cache.ped, Config.Tablet.anim.dict, Config.Tablet.anim.clip, 1.0)
end

local function remoteAllowed()
    if Config.Tablet.allowRemote or TCC.isInOffice() then return true end
    local pos = GetEntityCoords(cache.ped)
    for id, prop in pairs(Config.Properties) do
        local st = TCC.properties[id]
        if st and st.owned and #(pos - TCC.entrance(id).xyz) < Config.Tablet.remoteDistance then return true end
    end
    return false
end

---@param app string home|board|loads|employees|hire|fleet|upgrades|dispatch|finance|owner|driver|listing
---@param extra table|nil
function TCC.openTablet(app, extra)
    if isOpen then return end
    if app ~= 'listing' and not remoteAllowed() then
        return TCC.notify('No signal out here. Use the tablet at your depot.', 'error')
    end
    isOpen = true
    local ok, err = pcall(startProp)
    if not ok then print('[truckco] tablet prop/anim failed: ' .. tostring(err)) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    openToken = openToken + 1
    local token = openToken
    -- ox_target runs onSelect first and only then tears itself down, calling
    -- SetNuiFocus(false) + SetNuiFocusKeepInput(true/false) after we've opened.
    -- Re-assert our focus for a moment so the tablet keeps the mouse.
    CreateThread(function()
        local untilT = GetGameTimer() + 1000
        while isOpen and token == openToken and GetGameTimer() < untilT do
            if not IsNuiFocused() then SetNuiFocus(true, true) end
            SetNuiFocusKeepInput(false)
            Wait(0)
        end
    end)
    TCC.tabletAck = false
    SendNUIMessage({
        action = 'open',
        app = app or 'home',
        extra = extra,
        inOffice = TCC.isInOffice(),
        config = uiConfig(),
    })
    -- if the UI never confirms it opened, don't leave the player stuck with mouse focus
    SetTimeout(3000, function()
        if isOpen and token == openToken and not TCC.tabletAck then
            print(('[truckco] tablet UI did not respond (nuiReady=%s). Check F8 / NUI devtools for errors.'):format(tostring(nuiReady)))
            TCC.closeTablet()
            TCC.notify('The tablet UI failed to load. Press F8 for details.', 'error')
        end
    end)
end

function TCC.closeTablet()
    if not isOpen then return end
    isOpen = false
    openToken = openToken + 1
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    stopProp()
end

RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    cb(1)
end)

RegisterNUICallback('opened', function(_, cb)
    TCC.tabletAck = true
    cb(1)
end)

RegisterNUICallback('nuiError', function(data, cb)
    print(('[truckco] tablet UI error: %s'):format(type(data) == 'table' and tostring(data.msg) or tostring(data)))
    cb(1)
end)

RegisterNUICallback('takeOut', function(data, cb)
    cb(1)
    TCC.closeTablet()
    TCC.takeOutTruck(tonumber(data.id))
end)

RegisterNUICallback('placeSigns', function(_, cb)
    cb(1)
    TCC.closeTablet()
    TCC.startSignEditor()
end)

RegisterNUICallback('arrange', function(_, cb)
    cb(1)
    TCC.closeTablet()
    TCC.startEditor('save')
end)

RegisterNUICallback('close', function(_, cb)
    TCC.closeTablet()
    cb(1)
end)

RegisterNUICallback('call', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then
        return cb({ ok = false, msg = 'Not allowed.' })
    end
    local args = type(data.args) == 'table' and data.args or {}
    -- never let one call hang the tablet: give up after 10s
    local p, done = promise.new(), false
    local function finish(v) if not done then done = true p:resolve(v) end end
    CreateThread(function()
        local ok, r = pcall(lib.callback.await, 'truckco:server:' .. data.name, false, table.unpack(args, 1, #args))
        finish(ok and r or { ok = false, msg = 'Request failed: ' .. tostring(r) })
    end)
    SetTimeout(10000, function()
        if not done then print(('[truckco] tablet call %s timed out (is the server file that handles it loaded?)'):format(data.name)) end
        finish({ ok = false, msg = ('Server did not answer (%s). Check the server console for truckco errors.'):format(data.name) })
    end)
    local res = Citizen.Await(p)
    if data.name == 'buyProperty' and res and res.ok then
        CreateThread(function() TCC.closeTablet() end)
    end
    cb(res or { ok = false, msg = 'No response from server.' })
end)

RegisterNUICallback('nearbyPlayers', function(_, cb)
    local list = {}
    for _, p in ipairs(lib.getNearbyPlayers(GetEntityCoords(cache.ped), 8.0, false)) do
        local sid = GetPlayerServerId(p.id)
        list[#list + 1] = { id = sid, name = ('%s (ID %d)'):format(GetPlayerName(p.id), sid) }
    end
    cb(list)
end)

RegisterNUICallback('startRun', function(data, cb)
    cb(1)
    TCC.closeTablet()
    TCC.startRun(tonumber(data.id))
end)

RegisterNUICallback('leaveOffice', function(_, cb)
    cb(1)
    TCC.closeTablet()
    if TCC.isInOffice() then TCC.exitOffice() end
end)

RegisterNUICallback('companyGone', function(_, cb)
    cb(1)
    TCC.closeTablet()
    if TCC.isInOffice() then TCC.exitOffice() end
end)

-- commands: only for people who own or work for a trucking company
local function openIfMember(app)
    local res = lib.callback.await('truckco:server:tabletAccess', false)
    if not res or not res.ok then
        return TCC.notify(res and res.msg or 'You do not work for a trucking company.', 'error')
    end
    TCC.openTablet(app)
end

if Config.Tablet.command then
    RegisterCommand(Config.Tablet.command, function() openIfMember('home') end, false)
    -- lets players bind a key in Settings > Key Bindings > FiveM (no default key)
    RegisterKeyMapping(Config.Tablet.command, 'Open trucking company tablet', 'keyboard', '')
end
RegisterCommand('truckjob', function() openIfMember('driver') end, false)
RegisterCommand('truckboard', function() openIfMember('board') end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
        stopProp()
    end
end)
