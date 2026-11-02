--[[
    Company tablet (NUI). The UI in html/ talks to the server through the same
    callbacks the old menus used, via a whitelisted bridge below. All permission
    checks stay server-side.
]]

local isOpen = false
local tabletObj = nil

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
        if st and st.owned and #(pos - prop.entrance.xyz) < Config.Tablet.remoteDistance then return true end
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
    startProp()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        app = app or 'home',
        extra = extra,
        inOffice = TCC.isInOffice(),
        config = uiConfig(),
    })
end

function TCC.closeTablet()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopProp()
end

RegisterNUICallback('close', function(_, cb)
    TCC.closeTablet()
    cb(1)
end)

RegisterNUICallback('call', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then
        return cb({ ok = false, msg = 'Not allowed.' })
    end
    local args = type(data.args) == 'table' and data.args or {}
    local res = lib.callback.await('truckco:server:' .. data.name, false, table.unpack(args, 1, #args))
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

-- commands
if Config.Tablet.command then
    RegisterCommand(Config.Tablet.command, function() TCC.openTablet('home') end, false)
end
RegisterCommand('truckjob', function() TCC.openTablet('driver') end, false)
RegisterCommand('truckboard', function() TCC.openTablet('board') end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
        stopProp()
    end
end)
