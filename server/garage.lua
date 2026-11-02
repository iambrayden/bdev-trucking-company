--[[
    Company garage: staff can pull an available company truck out of the yard
    (at the truck pickup spot) and park it back (at the truck return spot).
    Separate from contract runs, which spawn their own assigned truck.
]]
TC.garageOut = {} -- [truckId] = { src, netId, companyId }

local function canUse(role)
    local roles = Config.Garage and Config.Garage.roles or {}
    return role == 'owner' or roles[role] == true
end

local function v(t, withW)
    if not t then return nil end
    return { x = t.x, y = t.y, z = t.z, w = withW and (t.w or 0.0) or nil }
end

lib.callback.register('truckco:server:getGarageInfo', function(src)
    local company, role = TC.getMembership(src)
    if not company then return nil end
    return {
        spawn = v(TC.propPoint(company.property, 'truckSpawn', company), true),
        ret = v(TC.propPoint(company.property, 'truckReturn', company)),
        canUse = canUse(role),
    }
end)

function TC.garageOutFor(src)
    for truckId, g in pairs(TC.garageOut) do
        if g.src == src then return truckId, g end
    end
end

--- Tell every online member to rebuild their garage spot (it moved / they joined).
function TC.garageChanged(companyId, onlySrc)
    if onlySrc then return TriggerClientEvent('truckco:client:garageChanged', onlySrc) end
    local company = TC.getCompany(companyId)
    if not company then return end
    local s = TC.sourceByCid(company.owner)
    if s then TriggerClientEvent('truckco:client:garageChanged', s) end
    for _, e in ipairs(MySQL.query.await("SELECT citizenid FROM truckco_employees WHERE company_id = ? AND kind = 'player'", { companyId }) or {}) do
        local es = TC.sourceByCid(e.citizenid)
        if es then TriggerClientEvent('truckco:client:garageChanged', es) end
    end
end

lib.callback.register('truckco:server:takeOutTruck', function(src, truckId)
    local company, role = TC.getMembership(src)
    if not company then return TC.result(false, 'You do not work for a trucking company.') end
    if not canUse(role) then return TC.result(false, 'Your role cannot take trucks out of the garage.') end
    if TC.inside[src] then return TC.result(false, 'Head outside to the yard first.') end
    if TC.garageOutFor(src) then return TC.result(false, 'You already have a company truck out. Park it first.') end
    -- a driver with an assigned load gets that load (right truck + route), not a plain truck
    local assigned = TC.assignedLoadFor and TC.assignedLoadFor(src)
    if assigned then
        return TC.result(false, nil, { startLoad = assigned })
    end
    for _, r in pairs(TC.runs) do
        if r.src == src then return TC.result(false, 'You are already on a load.') end
    end
    local spawn = TC.propPoint(company.property, 'truckSpawn', company)
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), spawn) > 40.0 then
        return TC.result(false, 'Go to the company yard (truck pickup spot) first.')
    end
    local truck = MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ? AND company_id = ?', { tonumber(truckId), company.id })
    if not truck then return TC.result(false, 'Truck not found.') end
    if truck.status ~= 'available' then return TC.result(false, 'That truck is not in the yard.') end
    if truck.health <= 0 then return TC.result(false, 'That truck is wrecked. Repair it first.') end
    local claimed = MySQL.update.await("UPDATE truckco_trucks SET status = 'out' WHERE id = ? AND status = 'available'", { truck.id })
    if claimed < 1 then return TC.result(false, 'Someone just took that truck.') end

    local netId, veh = TC.spawnVehicle(truck.model, spawn, { plate = truck.plate }, GetPlayerPed(src))
    if not netId then
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE id = ?", { truck.id })
        return TC.result(false, 'Could not pull the truck out. Is the spot blocked?')
    end
    SetVehicleNumberPlateText(veh, truck.plate)
    Config.SetFuel(veh)
    Config.GiveKeys(src, veh, truck.plate)
    TC.garageOut[truck.id] = { src = src, netId = netId, companyId = company.id }
    local def = Config.Trucks[truck.model] or { label = truck.model }
    return TC.result(true, ('%s [%s] is yours. Park it at the truck return spot when done.'):format(def.label, truck.plate), { netId = netId, truckId = truck.id })
end)

--- Return a garage truck: record wear from the vehicle's damage and despawn it.
local function checkIn(truckId, g, extraFee)
    local truck = MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ?', { truckId })
    local ent = TC.entityFromNet(g.netId)
    local health = truck and truck.health or 100
    if truck and ent then
        local dmg = math.min(GetVehicleEngineHealth(ent), GetVehicleBodyHealth(ent)) / 1000.0
        health = math.floor(TCShared.clamp(math.min(truck.health, truck.health * dmg), 0, 100))
    end
    if truck then
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available', health = ? WHERE id = ?", { health, truckId })
    end
    TC.deleteNet(g.netId)
    TC.garageOut[truckId] = nil
    if extraFee and extraFee > 0 then
        TC.spend(g.companyId, extraFee, ('Truck recovery %s'):format(truck and truck.plate or ''), true, true)
    end
    return health
end

lib.callback.register('truckco:server:parkTruck', function(src)
    local truckId, g = TC.garageOutFor(src)
    if not truckId then return TC.result(false, 'You have no company truck out.') end
    local ent = TC.entityFromNet(g.netId)
    if not ent then
        checkIn(truckId, g, Config.Runs.recoveryFee)
        return TC.result(false, 'The truck was lost; the company paid to recover it.')
    end
    local company = TC.getCompany(g.companyId)
    local pos = GetEntityCoords(ent)
    local ret = TC.propPoint(company.property, 'truckReturn', company)
    local spawn = TC.propPoint(company.property, 'truckSpawn', company)
    if TC.distance(pos, ret) > 25.0 and TC.distance(pos, spawn) > 25.0 then
        return TC.result(false, 'Bring the truck back to the yard to park it.')
    end
    local health = checkIn(truckId, g)
    return TC.result(true, ('Truck parked. Condition: %d%%.'):format(health))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local truckId, g = TC.garageOutFor(src)
    if truckId then pcall(checkIn, truckId, g) end
end)

-- trucks that vanished (destroyed / cleaned up) go back to the yard with a recovery fee
CreateThread(function()
    while true do
        Wait(20000)
        for truckId, g in pairs(TC.garageOut) do
            if not TC.entityFromNet(g.netId) then
                if GetPlayerName(g.src) then TC.notify(g.src, 'Your company truck was lost. The company paid to recover it.', 'error') end
                pcall(checkIn, truckId, g, Config.Runs.recoveryFee)
                if GetPlayerName(g.src) then TriggerClientEvent('truckco:client:garageChanged', g.src) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for truckId, g in pairs(TC.garageOut) do
        TC.deleteNet(g.netId)
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE id = ?", { truckId })
    end
end)
