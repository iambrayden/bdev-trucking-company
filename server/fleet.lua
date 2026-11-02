local function getTruck(companyId, id)
    return MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ? AND company_id = ?', { id, companyId })
end

function TC.repairCost(truck)
    return math.floor((100 - truck.health) * truck.price * Config.Fleet.repairCostPerPoint)
end

local function makePlate()
    for _ = 1, 20 do
        local plate = ('%s%06d'):format(Config.Fleet.platePrefix, math.random(0, 999999)):sub(1, 8)
        if not MySQL.scalar.await('SELECT id FROM truckco_trucks WHERE plate = ?', { plate }) then return plate end
    end
    return ('%s%06d'):format(Config.Fleet.platePrefix, os.time() % 1000000):sub(1, 8)
end

lib.callback.register('truckco:server:getFleet', function(src)
    local company, err = TC.authorize(src, 'view')
    if not company then return TC.result(false, err) end
    local rows = MySQL.query.await('SELECT * FROM truckco_trucks WHERE company_id = ? ORDER BY id', { company.id }) or {}
    for _, t in ipairs(rows) do
        t.repairCost = TC.repairCost(t)
        local tier = Config.Insurance[t.insurance] or Config.Insurance.none
        t.premium = math.floor(t.price * tier.premiumPct)
    end
    return TC.result(true, nil, { list = rows, max = TC.effects(company).maxTrucks })
end)

lib.callback.register('truckco:server:buyTruck', function(src, model, tier)
    local company, err = TC.authorize(src, 'fleet')
    if not company then return TC.result(false, err) end
    local def = Config.Trucks[model]
    if not def then return TC.result(false, 'Unknown truck.') end
    tier = Config.Insurance[tier] and tier or 'none'
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM truckco_trucks WHERE company_id = ?', { company.id }) or 0
    if count >= TC.effects(company).maxTrucks then return TC.result(false, 'The yard is full. Expand it first.') end
    if not TC.spend(company.id, def.price, ('Purchased %s'):format(def.label)) then
        return TC.result(false, ('Company needs %s.'):format(TCShared.money(def.price)))
    end
    local plate = makePlate()
    local truckId = MySQL.insert.await('INSERT INTO truckco_trucks (company_id, model, plate, price, insurance) VALUES (?, ?, ?, ?, ?)',
        { company.id, model, plate, def.price, tier })
    TC.cadRegisterTruck(company, { id = truckId, model = model, plate = plate, insurance = tier, price = def.price })
    local msg = tier == 'none' and '%s [%s] added to the fleet. Consider insuring it!' or '%s [%s] added to the fleet, insured.'
    return TC.result(true, msg:format(def.label, plate))
end)

lib.callback.register('truckco:server:repairTruck', function(src, id)
    local company, err = TC.authorize(src, 'fleet')
    if not company then return TC.result(false, err) end
    local t = getTruck(company.id, id)
    if not t then return TC.result(false, 'Truck not found.') end
    if t.status ~= 'available' then return TC.result(false, 'The truck is out on the road.') end
    local cost = TC.repairCost(t)
    if cost <= 0 then return TC.result(false, 'Truck is already in perfect shape.') end
    if not TC.spend(company.id, cost, ('Repairs: %s'):format(t.plate)) then
        return TC.result(false, ('Company needs %s.'):format(TCShared.money(cost)))
    end
    MySQL.update.await('UPDATE truckco_trucks SET health = 100 WHERE id = ?', { t.id })
    return TC.result(true, ('%s repaired for %s.'):format(t.plate, TCShared.money(cost)))
end)

lib.callback.register('truckco:server:setInsurance', function(src, id, tier)
    local company, err = TC.authorize(src, 'fleet')
    if not company then return TC.result(false, err) end
    local t = getTruck(company.id, id)
    if not t or not Config.Insurance[tier] then return TC.result(false, 'Invalid truck or policy.') end
    MySQL.update.await('UPDATE truckco_trucks SET insurance = ? WHERE id = ?', { tier, t.id })
    local premium = math.floor(t.price * Config.Insurance[tier].premiumPct)
    return TC.result(true, ('%s: %s (%s per payroll).'):format(t.plate, Config.Insurance[tier].label, TCShared.money(premium)))
end)

lib.callback.register('truckco:server:sellTruck', function(src, id)
    local company, err = TC.authorize(src, 'fleet')
    if not company then return TC.result(false, err) end
    local t = getTruck(company.id, id)
    if not t then return TC.result(false, 'Truck not found.') end
    if t.status ~= 'available' then return TC.result(false, 'The truck is busy.') end
    local value = math.floor(t.price * Config.Fleet.sellRefund * (t.health / 100))
    local affected = MySQL.update.await("DELETE FROM truckco_trucks WHERE id = ? AND status = 'available'", { t.id })
    if affected < 1 then return TC.result(false, 'The truck is busy.') end
    TC.addFunds(company.id, value, ('Sold truck %s'):format(t.plate))
    return TC.result(true, ('Sold %s for %s.'):format(t.plate, TCShared.money(value)))
end)

--- Insurance claim helper: returns payout and records it.
function TC.insuranceClaim(companyId, truck, loss, what)
    local tier = Config.Insurance[truck.insurance] or Config.Insurance.none
    if tier.coverage <= 0 or loss <= 0 then return 0 end
    local payout = math.max(0, math.floor(loss * tier.coverage - tier.deductible))
    if payout > 0 then
        TC.addFunds(companyId, payout, ('Insurance claim (%s): %s'):format(truck.plate, what))
    end
    return payout
end
