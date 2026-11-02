--------------------------------------------------------------------------------
-- Properties
--------------------------------------------------------------------------------
local function propertyState()
    local rows = MySQL.query.await('SELECT id, name, property FROM truckco_companies') or {}
    local owned = {}
    for _, r in ipairs(rows) do owned[r.property] = { companyId = r.id, name = r.name } end
    local out = {}
    local entrances = TC.entrances()
    for id, prop in pairs(Config.Properties) do
        out[id] = {
            entrance = entrances[id],
            owned = owned[id] ~= nil,
            companyId = owned[id] and owned[id].companyId,
            name = owned[id] and owned[id].name or prop.label,
        }
    end
    return out
end

function TC.broadcastProperties()
    TriggerClientEvent('truckco:client:properties', -1, propertyState())
    if TC.broadcastSigns then TC.broadcastSigns() end
end

lib.callback.register('truckco:server:getProperties', function()
    local deadline = GetGameTimer() + 15000
    while not TC.ready and GetGameTimer() < deadline do Wait(100) end
    local ok, state = pcall(propertyState)
    if not ok then
        print('^1[truckco] getProperties failed: ' .. tostring(state) .. '^0')
        return nil
    end
    return state
end)

local function sanitizeName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('[^%w%s%-%&%.\']', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if #name < 3 or #name > 40 then return nil end
    return name
end

lib.callback.register('truckco:server:buyProperty', function(src, propertyId, name)
    local prop = Config.Properties[propertyId]
    if not prop then return TC.result(false, 'Unknown property.') end
    name = sanitizeName(name)
    if not name then return TC.result(false, 'Company name must be 3-40 letters/numbers.') end

    local player = TC.getPlayer(src)
    if not player then return TC.result(false, 'Player not loaded.') end
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), TC.propPoint(propertyId, 'entrance')) > 15.0 then
        return TC.result(false, 'You need to be at the property.')
    end
    if TC.getMembership(src) then
        return TC.result(false, 'You already own or work for a trucking company.')
    end
    if MySQL.scalar.await('SELECT id FROM truckco_companies WHERE property = ?', { propertyId }) then
        return TC.result(false, 'This property was just bought by someone else.')
    end
    if player.PlayerData.money.bank < prop.price then
        return TC.result(false, ('You need %s in the bank.'):format(TCShared.money(prop.price)))
    end
    if not player.Functions.RemoveMoney('bank', prop.price, 'truckco-buy-property') then
        return TC.result(false, 'Payment failed.')
    end

    local ok, id = pcall(MySQL.insert.await,
        'INSERT INTO truckco_companies (name, owner, property, balance, upgrades, settings, last_payroll) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { name, player.PlayerData.citizenid, propertyId, Config.Economy.startingBalance, '{}', '{}', TC.now() })
    if not ok or not id then
        player.Functions.AddMoney('bank', prop.price, 'truckco-buy-property-refund')
        return TC.result(false, 'Could not register the company. You were refunded.')
    end
    TC.ledger(id, 0, ('Company founded at %s'):format(prop.label))
    TC.broadcastProperties()
    return TC.result(true, ('Welcome to the industry, %s!'):format(name), { companyId = id })
end)

lib.callback.register('truckco:server:sellCompany', function(src)
    local company, role = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can sell the company.') end
    if company.balance < 0 then return TC.result(false, 'Clear the company debt before selling.') end
    local busy = MySQL.scalar.await(
        "SELECT COUNT(*) FROM truckco_contracts WHERE company_id = ? AND status IN ('assigned','in_progress','delivered')",
        { company.id })
    if busy and busy > 0 then return TC.result(false, 'Wait for all loads in progress to finish first.') end

    local prop = Config.Properties[company.property]
    local trucks = MySQL.query.await('SELECT price, health FROM truckco_trucks WHERE company_id = ?', { company.id }) or {}
    local truckValue = 0
    for _, t in ipairs(trucks) do truckValue = truckValue + math.floor(t.price * Config.Fleet.sellRefund * (t.health / 100)) end
    local payout = math.floor((prop and prop.price or 0) * Config.Economy.propertyRefund) + company.balance + truckValue

    -- release any open/awarded contracts back into the void
    MySQL.update.await("UPDATE truckco_contracts SET status = 'failed', finished_at = ? WHERE company_id = ? AND status = 'awarded'",
        { TC.now(), company.id })
    MySQL.query.await('DELETE FROM truckco_companies WHERE id = ?', { company.id })
    TC.candidates[company.id] = nil

    local player = TC.getPlayer(src)
    player.Functions.AddMoney('bank', payout, 'truckco-sell-company')
    TC.broadcastProperties()
    return TC.result(true, ('Company sold. %s deposited to your bank.'):format(TCShared.money(payout)))
end)

lib.callback.register('truckco:server:renameCompany', function(src, name)
    local company, role = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can rename the company.') end
    name = sanitizeName(name)
    if not name then return TC.result(false, 'Company name must be 3-40 letters/numbers.') end
    MySQL.update.await('UPDATE truckco_companies SET name = ? WHERE id = ?', { name, company.id })
    TC.broadcastProperties()
    return TC.result(true, 'Company renamed.')
end)

--------------------------------------------------------------------------------
-- Office access (routing bucket per company)
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:enterOffice', function(src, propertyId)
    local prop = Config.Properties[propertyId]
    if not prop then return TC.result(false, 'Unknown property.') end
    local companyId = MySQL.scalar.await('SELECT id FROM truckco_companies WHERE property = ?', { propertyId })
    if not companyId then return TC.result(false, 'This property is for sale.') end
    local company, role = TC.getMembership(src)
    if not company or company.id ~= companyId then return TC.result(false, 'The door is locked. Staff only.') end
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), TC.propPoint(propertyId, 'entrance')) > 10.0 then
        return TC.result(false, 'Too far from the door.')
    end
    TC.inside[src] = propertyId
    SetPlayerRoutingBucket(src, Config.RoutingBucketBase + company.id)
    return TC.result(true, nil, {
        interior = prop.interior,
        upgrades = company.upgrades,
        layout = TC.officeLayout(company),
        role = role,
        name = company.name,
    })
end)

lib.callback.register('truckco:server:exitOffice', function(src)
    local propertyId = TC.inside[src]
    TC.inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
    return TC.result(true, nil, { propertyId = propertyId })
end)

AddEventHandler('playerDropped', function()
    local src = source
    TC.inside[src] = nil
    TC.invites[src] = nil
end)

--------------------------------------------------------------------------------
-- Dashboard / finances
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:getDashboard', function(src)
    local company, role, emp = TC.authorize(src, 'view')
    if not company then return TC.result(false, role) end
    local counts = MySQL.single.await([[
        SELECT
          (SELECT COUNT(*) FROM truckco_employees WHERE company_id = ?) AS employees,
          (SELECT COUNT(*) FROM truckco_employees WHERE company_id = ? AND role = 'driver') AS drivers,
          (SELECT COUNT(*) FROM truckco_employees WHERE company_id = ? AND role = 'dispatcher') AS dispatchers,
          (SELECT COUNT(*) FROM truckco_trucks WHERE company_id = ?) AS trucks,
          (SELECT COUNT(*) FROM truckco_contracts WHERE company_id = ? AND status IN ('awarded','assigned','in_progress')) AS active,
          (SELECT COUNT(*) FROM truckco_contracts WHERE company_id = ? AND status = 'completed') AS completed,
          (SELECT COUNT(*) FROM truckco_bids b JOIN truckco_contracts c ON c.id = b.contract_id WHERE b.company_id = ? AND c.status = 'open') AS bids
    ]], { company.id, company.id, company.id, company.id, company.id, company.id, company.id })

    local nextPayroll = company.last_payroll + Config.Payroll.intervalMinutes * 60 - TC.now()
    return TC.result(true, nil, {
        id = company.id,
        name = company.name,
        property = Config.Properties[company.property] and Config.Properties[company.property].label or company.property,
        balance = company.balance,
        reputation = company.reputation,
        role = role,
        upgrades = company.upgrades,
        settings = company.settings,
        effects = TC.effects(company),
        counts = counts,
        suspended = TC.isSuspended(company),
        nextPayroll = math.max(0, nextPayroll),
        signs = #(company.signs or {}),
        onRoster = emp ~= nil,
        onDuty = TC.onDuty[TC.cid(src)] ~= nil,
    })
end)

lib.callback.register('truckco:server:deposit', function(src, amount)
    local company, err = TC.authorize(src, 'deposit')
    if not company then return TC.result(false, err) end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return TC.result(false, 'Invalid amount.') end
    local player = TC.getPlayer(src)
    if player.PlayerData.money.bank < amount then return TC.result(false, 'Not enough money in your bank.') end
    if not player.Functions.RemoveMoney('bank', amount, 'truckco-deposit') then return TC.result(false, 'Payment failed.') end
    TC.addFunds(company.id, amount, ('Deposit by %s'):format(TC.charName(player)))
    return TC.result(true, ('Deposited %s.'):format(TCShared.money(amount)))
end)

lib.callback.register('truckco:server:withdraw', function(src, amount)
    local company, role = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can withdraw.') end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return TC.result(false, 'Invalid amount.') end
    if not TC.spend(company.id, amount, 'Owner withdrawal') then return TC.result(false, 'Insufficient company funds.') end
    TC.getPlayer(src).Functions.AddMoney('bank', amount, 'truckco-withdraw')
    return TC.result(true, ('Withdrew %s.'):format(TCShared.money(amount)))
end)

lib.callback.register('truckco:server:getLedger', function(src)
    local company, err = TC.authorize(src, 'finance')
    if not company then return TC.result(false, err) end
    local rows = MySQL.query.await(
        "SELECT amount, reason, DATE_FORMAT(created_at, '%d %b %H:%i') AS ts FROM truckco_ledger WHERE company_id = ? ORDER BY id DESC LIMIT 40",
        { company.id }) or {}
    return TC.result(true, nil, rows)
end)

lib.callback.register('truckco:server:buyUpgrade', function(src, key)
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    local up = Config.Upgrades[key]
    if not up then return TC.result(false, 'Unknown upgrade.') end
    local lvl = company.upgrades[key] or 0
    local nextLvl = up.levels[lvl + 1]
    if not nextLvl then return TC.result(false, 'Already fully upgraded.') end
    if not TC.spend(company.id, nextLvl.price, ('Office upgrade: %s (Lv %d)'):format(up.label, lvl + 1)) then
        return TC.result(false, ('Company needs %s.'):format(TCShared.money(nextLvl.price)))
    end
    company.upgrades[key] = lvl + 1
    MySQL.update.await('UPDATE truckco_companies SET upgrades = ? WHERE id = ?', { json.encode(company.upgrades), company.id })
    -- refresh furniture for everyone currently inside
    for s, propId in pairs(TC.inside) do
        if propId == company.property then
            TriggerClientEvent('truckco:client:refreshFurniture', s, company.upgrades, TC.officeLayout(company))
        end
    end
    return TC.result(true, ('%s upgraded to level %d.'):format(up.label, lvl + 1))
end)

lib.callback.register('truckco:server:saveSettings', function(src, settings)
    local company, err = TC.authorize(src, 'settings')
    if not company then return TC.result(false, err) end
    if type(settings) ~= 'table' then return TC.result(false, 'Invalid settings.') end
    local s = {
        autoBid = settings.autoBid == true,
        autoAssign = settings.autoAssign == true,
        usePlayerDrivers = settings.usePlayerDrivers == true,
    }
    MySQL.update.await('UPDATE truckco_companies SET settings = ? WHERE id = ?', { json.encode(s), company.id })
    return TC.result(true, 'Dispatch settings saved.')
end)

--------------------------------------------------------------------------------
-- Office furniture layout (saved per company, per interior)
--------------------------------------------------------------------------------
local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.floor(TCShared.clamp(v, lo, hi) * 100 + 0.5) / 100
end

--- Validate a furniture layout { [key] = {x,y,z,h} } from a client. Returns clean table or nil.
function TC.cleanLayoutItems(items)
    if type(items) ~= 'table' then return nil end
    local clean, count = {}, 0
    for key, t in pairs(items) do
        count = count + 1
        if count > 100 or type(key) ~= 'string' or #key > 64 or type(t) ~= 'table' then return nil end
        local x, y, z, h = num(t.x, -60, 60), num(t.y, -60, 60), num(t.z, 0, 10), num(t.h, -720, 720)
        if not (x and y and z and h) then return nil end
        clean[key] = { x = x, y = y, z = z, h = h % 360 }
    end
    return clean
end

lib.callback.register('truckco:server:saveLayout', function(src, items)
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    if TC.inside[src] ~= company.property then return TC.result(false, 'You need to be inside the office.') end
    local clean = TC.cleanLayoutItems(items)
    if not clean then return TC.result(false, 'Invalid layout.') end
    local l = TC.companyLayoutTable(company)
    l.items = clean
    MySQL.update.await('UPDATE truckco_companies SET layout = ? WHERE id = ?', { json.encode(l), company.id })
    TC.refreshOffice(company)
    return TC.result(true, 'Office layout saved.')
end)

lib.callback.register('truckco:server:tabletAccess', function(src)
    local company, role = TC.getMembership(src)
    if not company then return TC.result(false, 'You do not work for a trucking company.') end
    return TC.result(true, nil, { role = role, name = company.name })
end)

--------------------------------------------------------------------------------
-- Exterior signs
--------------------------------------------------------------------------------
local STYLE = {}
for _, st in ipairs(Config.Signs.styles) do STYLE[st.id] = true end

local function signsPayload()
    local out = {}
    for _, c in ipairs(MySQL.query.await('SELECT id, name, signs FROM truckco_companies') or {}) do
        local list = c.signs and json.decode(c.signs) or {}
        if #list > 0 then out[#out + 1] = { companyId = c.id, name = c.name, items = list } end
    end
    return out
end

function TC.broadcastSigns()
    TriggerClientEvent('truckco:client:signs', -1, signsPayload())
end

lib.callback.register('truckco:server:getSigns', function()
    local deadline = GetGameTimer() + 15000
    while not TC.ready and GetGameTimer() < deadline do Wait(100) end
    local ok, list = pcall(signsPayload)
    return ok and list or {}
end)

lib.callback.register('truckco:server:getSignEditor', function(src)
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    local e = TC.propPoint(company.property, 'entrance')
    return TC.result(true, nil, { companyId = company.id, name = company.name, property = company.property, items = company.signs or {}, entrance = { x = e.x, y = e.y, z = e.z } })
end)

lib.callback.register('truckco:server:saveSigns', function(src, items)
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    if type(items) ~= 'table' or #items > Config.Signs.max then
        return TC.result(false, ('You can place up to %d signs.'):format(Config.Signs.max))
    end
    local prop = Config.Properties[company.property]
    local clean = {}
    for i = 1, #items do
        local it = items[i]
        local x, y, z, h = tonumber(it and it.x), tonumber(it and it.y), tonumber(it and it.z), tonumber(it and it.h)
        if not (x and y and z and h) then return TC.result(false, 'Invalid sign.') end
        if TC.distance(vec3(x, y, z), TC.propPoint(company.property, 'entrance')) > Config.Signs.radius + 2.0 then
            return TC.result(false, 'Signs must stay near your depot.')
        end
        clean[i] = {
            x = math.floor(x * 100 + 0.5) / 100, y = math.floor(y * 100 + 0.5) / 100, z = math.floor(z * 100 + 0.5) / 100,
            h = math.floor((h % 360) * 10 + 0.5) / 10,
            style = STYLE[it.style] and it.style or Config.Signs.styles[1].id,
        }
    end
    local added = math.max(0, #clean - #(company.signs or {}))
    local cost = added * Config.Signs.price
    if cost > 0 and not TC.spend(company.id, cost, ('Exterior signs (%d new)'):format(added)) then
        return TC.result(false, ('Company needs %s for %d new sign%s.'):format(TCShared.money(cost), added, added == 1 and '' or 's'))
    end
    MySQL.update.await('UPDATE truckco_companies SET signs = ? WHERE id = ?', { json.encode(clean), company.id })
    TC.broadcastSigns()
    return TC.result(true, cost > 0 and ('Signs saved. Paid %s.'):format(TCShared.money(cost)) or 'Signs saved.')
end)
