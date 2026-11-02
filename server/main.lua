---@diagnostic disable: undefined-global
TC = {
    ready = false,
    inside = {},      -- [src] = propertyId
    invites = {},     -- [targetSrc] = { companyId, role, wage, expires, from }
    onDuty = {},      -- [citizenid] = true
    dutyCycle = {},   -- [citizenid] = true if on duty at any point this payroll cycle
    candidates = {},  -- [companyId] = { expires, list }
    runs = {},        -- [contractId] = active player run
}

function TC.now() return os.time() end

function TC.log(...)
    if Config.Debug then print('[truckco]', ...) end
end

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------
function TC.getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function TC.cid(src)
    local p = TC.getPlayer(src)
    return p and p.PlayerData.citizenid
end

function TC.charName(player)
    local c = player.PlayerData.charinfo
    return ('%s %s'):format(c.firstname, c.lastname)
end

function TC.sourceByCid(cid)
    local p = exports.qbx_core:GetPlayerByCitizenId(cid)
    return p and p.PlayerData.source or nil
end

function TC.notify(src, msg, typ, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or 'Trucking Co.',
        description = msg,
        type = typ or 'inform',
        duration = 7000,
    })
end

function TC.result(ok, msg, data)
    return { ok = ok, msg = msg, data = data }
end

function TC.distance(a, b)
    return #(vec3(a.x, a.y, a.z) - vec3(b.x, b.y, b.z))
end

--------------------------------------------------------------------------------
-- Companies
--------------------------------------------------------------------------------
local function decodeCompany(row)
    if not row then return nil end
    row.upgrades = json.decode(row.upgrades or '{}') or {}
    row.settings = json.decode(row.settings or '{}') or {}
    row.layout = row.layout and json.decode(row.layout) or nil
    row.signs = row.signs and json.decode(row.signs) or {}
    if row.settings.autoBid == nil then row.settings.autoBid = true end
    if row.settings.autoAssign == nil then row.settings.autoAssign = true end
    if row.settings.usePlayerDrivers == nil then row.settings.usePlayerDrivers = true end
    return row
end

function TC.getCompany(id)
    return decodeCompany(MySQL.single.await('SELECT * FROM truckco_companies WHERE id = ?', { id }))
end

function TC.getAllCompanies()
    local rows = MySQL.query.await('SELECT * FROM truckco_companies') or {}
    for i = 1, #rows do decodeCompany(rows[i]) end
    return rows
end

function TC.decodeEmployee(e)
    if not e then return nil end
    e.certs = json.decode(e.certs or '{}') or {}
    return e
end

--- Resolve a player's company + role. Owners may also have an employee row in
--- their own company (when they put themselves on the roster as a driver).
---@return table|nil company, string|nil role, table|nil employeeRow
function TC.getMembership(src)
    local cid = TC.cid(src)
    if not cid then return nil end

    local company = decodeCompany(MySQL.single.await('SELECT * FROM truckco_companies WHERE owner = ?', { cid }))
    local emp = TC.decodeEmployee(MySQL.single.await(
        'SELECT * FROM truckco_employees WHERE citizenid = ? AND kind = \'player\'', { cid }))

    if company then
        if emp and emp.company_id ~= company.id then emp = nil end
        return company, 'owner', emp
    end
    if emp then
        return TC.getCompany(emp.company_id), emp.role, emp
    end
end

---@return table|nil company, string|any roleOrError, table|nil employee
function TC.authorize(src, perm)
    local company, role, emp = TC.getMembership(src)
    if not company then return nil, 'You do not work for a trucking company.' end
    if perm and not TCShared.can(role, perm) then return nil, 'You do not have permission to do that.' end
    return company, role, emp
end

function TC.effects(company)
    local e = {
        maxEmployees = Config.Base.maxEmployees,
        maxTrucks = Config.Base.maxTrucks,
        dispatchBonus = 0,
        trainingMult = 1.0,
        quitMult = 1.0,
    }
    for key, lvl in pairs(company.upgrades or {}) do
        local up = Config.Upgrades[key]
        if up then
            for i = 1, math.min(lvl, #up.levels) do
                for k, v in pairs(up.levels[i].effect) do
                    if k == 'trainingMult' or k == 'quitMult' then
                        e[k] = e[k] * v
                    else
                        e[k] = (e[k] or 0) + v
                    end
                end
            end
        end
    end
    return e
end

function TC.isSuspended(company)
    return company.balance <= Config.Payroll.overdraftLimit
end

--------------------------------------------------------------------------------
-- Money (company balance is the source of truth in SQL; updates are atomic)
--------------------------------------------------------------------------------
function TC.ledger(companyId, amount, reason)
    MySQL.insert('INSERT INTO truckco_ledger (company_id, amount, reason) VALUES (?, ?, ?)',
        { companyId, math.floor(amount), reason })
end

function TC.addFunds(companyId, amount, reason)
    amount = math.floor(amount)
    if amount == 0 then return end
    MySQL.update.await('UPDATE truckco_companies SET balance = balance + ? WHERE id = ?', { amount, companyId })
    TC.ledger(companyId, amount, reason)
end

--- Spend company money. Fails if it would drop below 0 (or below the overdraft
--- limit when allowOverdraft). force = always succeeds (payroll, penalties).
function TC.spend(companyId, amount, reason, allowOverdraft, force)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    local affected
    if force then
        affected = MySQL.update.await('UPDATE truckco_companies SET balance = balance - ? WHERE id = ?',
            { amount, companyId })
    else
        local floor = allowOverdraft and Config.Payroll.overdraftLimit or 0
        affected = MySQL.update.await(
            'UPDATE truckco_companies SET balance = balance - ? WHERE id = ? AND balance - ? >= ?',
            { amount, companyId, amount, floor })
    end
    if affected and affected > 0 then
        TC.ledger(companyId, -amount, reason)
        return true
    end
    return false
end

function TC.adjustRep(companyId, delta)
    MySQL.update.await('UPDATE truckco_companies SET reputation = LEAST(100, GREATEST(0, reputation + ?)) WHERE id = ?',
        { delta, companyId })
end

--------------------------------------------------------------------------------
-- Notifications to staff
--------------------------------------------------------------------------------
--- Notify every online member of a company who has `perm` (nil = everyone).
function TC.notifyCompany(companyId, msg, typ, perm)
    local company = TC.getCompany(companyId)
    if not company then return end
    local sent = {}
    local ownerSrc = TC.sourceByCid(company.owner)
    if ownerSrc then
        TC.notify(ownerSrc, msg, typ, company.name)
        sent[ownerSrc] = true
    end
    local staff = MySQL.query.await(
        'SELECT citizenid, role FROM truckco_employees WHERE company_id = ? AND kind = \'player\'', { companyId }) or {}
    for _, s in ipairs(staff) do
        if not perm or TCShared.can(s.role, perm) then
            local src = TC.sourceByCid(s.citizenid)
            if src and not sent[src] then
                TC.notify(src, msg, typ, company.name)
                sent[src] = true
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------
function TC.spawnVehicle(model, coords, props, warpPed)
    local ok, netId, veh = pcall(qbx.spawnVehicle, {
        model = model,
        spawnSource = coords,
        warp = warpPed,
        props = props,
    })
    if not ok or not netId then
        print(('[truckco] failed to spawn %s: %s'):format(model, tostring(netId)))
        return nil
    end
    return netId, veh
end

function TC.deleteNet(netId)
    if not netId then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
end

function TC.entityFromNet(netId)
    if not netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    return nil
end
