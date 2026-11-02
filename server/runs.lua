--------------------------------------------------------------------------------
-- NPC runs (simulated server-side; survive restarts via eta column)
--------------------------------------------------------------------------------
function TC.startNpcRun(company, contract, driver, truck, by)
    local cfg = Config.NPC
    local minutes = contract.distance / cfg.kmPerMinute
    minutes = minutes * (1.15 - driver.skill / 500) * (0.9 + math.random() * 0.2)
    minutes = minutes * (1 + (100 - truck.health) / 400) -- beat-up trucks are slower
    local now = TC.now()
    MySQL.update.await(
        "UPDATE truckco_contracts SET status = 'in_progress', employee_id = ?, truck_id = ?, assigned_by = ?, driver_kind = 'npc', started_at = ?, eta = ? WHERE id = ?",
        { driver.id, truck.id, by, now, now + math.floor(minutes * 60), contract.id })
end

local function finishNpcRun(c)
    local cfg = Config.NPC
    local driver = MySQL.single.await('SELECT * FROM truckco_employees WHERE id = ?', { c.employee_id })
    local truck = MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ?', { c.truck_id })
    local skill = driver and driver.skill or 30
    local health = truck and truck.health or 100

    local wear = c.distance * Config.Fleet.wearPerKm
    local accidentChance = cfg.accidentBase - cfg.accidentSkillReduce * (skill / 100) + cfg.accidentConditionAdd * ((100 - health) / 100)
    local accident = math.random() < math.max(0.005, accidentChance)

    if accident then
        local severe = math.random() < cfg.severeAccident
        local dmg = severe and math.random(35, 70) or math.random(8, 25)
        wear = wear + dmg
        if truck then
            local repairLoss = math.floor(dmg * truck.price * Config.Fleet.repairCostPerPoint)
            TC.insuranceClaim(c.company_id, truck, repairLoss, ('accident repairs #%d'):format(c.id))
        end
        if severe then
            if truck then
                MySQL.update.await("UPDATE truckco_trucks SET status = 'available', health = GREATEST(0, health - ?), mileage = mileage + ? WHERE id = ?",
                    { math.floor(wear), c.distance, truck.id })
            end
            TC.failContract(c, ('%s wrecked the load'):format(driver and driver.name or 'driver'), truck)
            return
        end
    end

    MySQL.update.await("UPDATE truckco_contracts SET status = 'completed', finished_at = ? WHERE id = ?", { TC.now(), c.id })
    local pay, late = TC.payContract(c, { damage = accident and 0.15 or 0 })
    if truck then
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available', health = GREATEST(0, health - ?), mileage = mileage + ? WHERE id = ?",
            { math.floor(wear + 0.5), c.distance, truck.id })
    end
    if driver then MySQL.update.await("UPDATE truckco_employees SET status = 'idle' WHERE id = ?", { driver.id }) end
    TC.notifyCompany(c.company_id, ('%s delivered load #%d%s%s. +%s'):format(
        driver and driver.name or 'Driver', c.id, late and ' late' or '', accident and ' after a fender-bender' or '',
        TCShared.money(pay)), late and 'warning' or 'success', 'assign')
end

function TC.tickNpcRuns()
    local rows = MySQL.query.await(
        "SELECT * FROM truckco_contracts WHERE status = 'in_progress' AND driver_kind = 'npc' AND eta <= ?", { TC.now() }) or {}
    for _, c in ipairs(rows) do
        TC.decodeContract(c)
        local ok, err = pcall(finishNpcRun, c)
        if not ok then print(('[truckco] NPC run #%d error: %s'):format(c.id, err)) end
    end
end

--------------------------------------------------------------------------------
-- Player runs
--------------------------------------------------------------------------------
local function myEmployee(src)
    local company, role, emp = TC.getMembership(src)
    if not company or not emp then return nil end
    return company, emp
end

lib.callback.register('truckco:server:getMyAssignments', function(src)
    local company, emp = myEmployee(src)
    if not company then return TC.result(false, 'You are not on a trucking roster.') end
    local rows = MySQL.query.await([[
        SELECT c.*, t.plate AS truck_plate, t.model AS truck_model FROM truckco_contracts c
        LEFT JOIN truckco_trucks t ON t.id = c.truck_id
        WHERE c.employee_id = ? AND c.status IN ('assigned','in_progress','delivered')
    ]], { emp.id }) or {}
    local now = TC.now()
    for _, c in ipairs(rows) do
        TC.decodeContract(c)
        c.market_bid = nil
        c.deadlineIn = c.deadline and (c.deadline - now)
        c.active = TC.runs[c.id] ~= nil
        c.cut = company.owner ~= emp.citizenid and math.floor((c.award_amount or 0) * Config.Runs.driverCommission) or 0
        c.truck_label = c.truck_model and Config.Trucks[c.truck_model] and Config.Trucks[c.truck_model].label or c.truck_model
    end
    return TC.result(true, nil, { list = rows, pending = emp.pending_pay, onDuty = TC.onDuty[emp.citizenid] ~= nil })
end)

lib.callback.register('truckco:server:startPlayerRun', function(src, contractId)
    local company, emp = myEmployee(src)
    if not company then return TC.result(false, 'You are not on a trucking roster.') end
    for _, r in pairs(TC.runs) do
        if r.src == src then return TC.result(false, 'You are already on a load.') end
    end
    if TC.garageOutFor and TC.garageOutFor(src) then return TC.result(false, 'Park the company truck you took out first.') end
    local c = TC.getContract(contractId)
    if not c or c.employee_id ~= emp.id or c.status ~= 'assigned' then return TC.result(false, 'That load is not assigned to you.') end
    local truck = MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ?', { c.truck_id })
    local prop = Config.Properties[company.property]
    if not truck or not prop then return TC.result(false, 'Truck missing.') end
    if TC.inside[src] then return TC.result(false, 'Head outside to the yard first.') end
    local truckSpawn = TC.propPoint(company.property, 'truckSpawn', company)
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), truckSpawn) > 60.0 then
        return TC.result(false, 'Go to the company yard to pick up your truck.')
    end

    local netId, veh = TC.spawnVehicle(truck.model, truckSpawn, { plate = truck.plate }, GetPlayerPed(src))
    if not netId then return TC.result(false, 'Could not pull the truck out. Is the spot blocked?') end
    SetVehicleNumberPlateText(veh, truck.plate)
    Config.SetFuel(veh)
    Config.GiveKeys(src, veh, truck.plate)

    local now = TC.now()
    MySQL.update.await("UPDATE truckco_contracts SET status = 'in_progress', started_at = ? WHERE id = ?", { now, c.id })
    MySQL.update.await("UPDATE truckco_trucks SET status = 'in_use' WHERE id = ?", { truck.id })
    MySQL.update.await("UPDATE truckco_employees SET status = 'on_job' WHERE id = ?", { emp.id })

    local run = {
        src = src,
        cid = emp.citizenid,
        companyId = company.id,
        contractId = c.id,
        employeeId = emp.id,
        truckId = truck.id,
        truckNet = netId,
        trailerNet = nil,
        class = c.class,
        stage = 'pickup',
        startedAt = now,
    }
    TC.runs[c.id] = run
    return TC.result(true, nil, {
        contractId = c.id,
        truckNet = netId,
        class = c.class,
        trailer = c.trailer,
        cargo = c.cargoLabel,
        pickup = c.pickup,
        dropoff = c.dropoff,
        returnPoint = TC.propPoint(company.property, 'truckReturn', company),
        pay = c.award_amount,
        cut = company.owner ~= emp.citizenid and math.floor((c.award_amount or 0) * Config.Runs.driverCommission) or 0,
        distance = c.distance,
        deadline = c.deadline and (c.deadline - now),
        plate = truck.plate,
    })
end)

local function getRun(src, contractId)
    local run = TC.runs[contractId]
    if not run or run.src ~= src then return nil end
    return run
end

lib.callback.register('truckco:server:spawnTrailer', function(src, contractId)
    local run = getRun(src, contractId)
    if not run or run.stage ~= 'pickup' or run.class ~= 'semi' then return TC.result(false, 'No trailer for this load.') end
    if run.trailerNet and TC.entityFromNet(run.trailerNet) then return TC.result(true, nil, { trailerNet = run.trailerNet }) end
    local c = TC.getContract(contractId)
    local p = c.pickup
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), p) > 200.0 then return TC.result(false, 'Get closer to the pickup.') end
    local netId = TC.spawnVehicle(c.trailer, vec4(p.x, p.y, p.z, p.w or 0.0))
    if not netId then return TC.result(false, 'Trailer failed to spawn.') end
    run.trailerNet = netId
    return TC.result(true, nil, { trailerNet = netId })
end)

lib.callback.register('truckco:server:loaded', function(src, contractId)
    local run = getRun(src, contractId)
    if not run or run.stage ~= 'pickup' then return TC.result(false, 'Not at pickup stage.') end
    local c = TC.getContract(contractId)
    local truck = TC.entityFromNet(run.truckNet)
    if not truck then return TC.result(false, 'Where is your truck?') end
    if TC.distance(GetEntityCoords(truck), c.pickup) > 40.0 then return TC.result(false, 'Bring the truck to the pickup.') end
    if run.class == 'semi' then
        local trailer = TC.entityFromNet(run.trailerNet)
        if not trailer or TC.distance(GetEntityCoords(trailer), GetEntityCoords(truck)) > 20.0 then
            return TC.result(false, 'Hook up the trailer first.')
        end
    end
    run.stage = 'dropoff'
    run.loadedAt = TC.now()
    return TC.result(true, ('Loaded. Deliver to %s.'):format(c.dropoff.label))
end)

lib.callback.register('truckco:server:deliver', function(src, contractId)
    local run = getRun(src, contractId)
    if not run or run.stage ~= 'dropoff' then return TC.result(false, 'Nothing to deliver.') end
    local c = TC.getContract(contractId)
    local truck = TC.entityFromNet(run.truckNet)
    local ped = GetPlayerPed(src)
    if TC.distance(GetEntityCoords(ped), c.dropoff) > 30.0 then return TC.result(false, 'You are not at the drop-off.') end

    local minSeconds = math.floor(c.distance * Config.Runs.minSecondsPerKm)
    if TC.now() - run.startedAt < minSeconds then
        print(('[truckco] %s delivered #%d suspiciously fast (%ds < %ds)'):format(GetPlayerName(src), c.id, TC.now() - run.startedAt, minSeconds))
        return TC.result(false, 'The receiver says you could not possibly have driven here that fast.')
    end

    local cargoEnt
    if run.class == 'semi' then
        cargoEnt = TC.entityFromNet(run.trailerNet)
        if not cargoEnt or TC.distance(GetEntityCoords(cargoEnt), c.dropoff) > 35.0 then
            return TC.result(false, 'Bring the trailer to the drop-off.')
        end
    else
        cargoEnt = truck
        if not cargoEnt or TC.distance(GetEntityCoords(cargoEnt), c.dropoff) > 35.0 then
            return TC.result(false, 'Bring the truck to the drop-off.')
        end
    end
    local damage = TCShared.clamp((1000.0 - GetVehicleBodyHealth(cargoEnt)) / 1000.0, 0.0, 1.0)
    if run.class == 'semi' then TC.deleteNet(run.trailerNet) run.trailerNet = nil end

    MySQL.update.await("UPDATE truckco_contracts SET status = 'delivered', finished_at = ? WHERE id = ?", { TC.now(), c.id })
    local pay, late = TC.payContract(c, { damage = damage })

    -- player driver commission (company pays it to the driver)
    local commission = math.floor(pay * Config.Runs.driverCommission)
    if commission > 0 and run.cid then
        local company = TC.getCompany(run.companyId)
        if company and company.owner ~= run.cid then
            TC.spend(run.companyId, commission, ('Driver commission load #%d'):format(c.id), true, true)
            TC.getPlayer(src).Functions.AddMoney('bank', commission, 'truckco-commission')
        else
            commission = 0
        end
    end

    run.stage = 'return'
    run.deliveredAt = TC.now()
    TC.notifyCompany(run.companyId, ('Load #%d delivered by %s%s. +%s'):format(c.id, GetPlayerName(src), late and ' (late)' or '', TCShared.money(pay)),
        late and 'warning' or 'success', 'assign')
    return TC.result(true, ('Delivered%s! Company earned %s%s. Return the truck to the yard.'):format(
        late and ' late' or '', TCShared.money(pay),
        commission > 0 and (', your cut: %s'):format(TCShared.money(commission)) or ''))
end)

--- Write truck wear back to the fleet record and clean up the run.
local function closeRun(run, opts)
    opts = opts or {}
    local truckEnt = TC.entityFromNet(run.truckNet)
    local truck = MySQL.single.await('SELECT * FROM truckco_trucks WHERE id = ?', { run.truckId })
    local c = TC.getContract(run.contractId)
    local km = c and c.distance or 0
    local newHealth = truck and truck.health or 100
    if truck then
        newHealth = newHealth - km * Config.Fleet.wearPerKm
        if truckEnt then
            local engine = GetVehicleEngineHealth(truckEnt)
            local body = GetVehicleBodyHealth(truckEnt)
            newHealth = math.min(newHealth, truck.health * (math.min(engine, body) / 1000.0))
        elseif opts.lost then
            newHealth = 0
        end
        newHealth = math.floor(TCShared.clamp(newHealth, 0, 100))
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available', health = ?, mileage = mileage + ? WHERE id = ?",
            { newHealth, km, truck.id })
    end
    TC.deleteNet(run.truckNet)
    TC.deleteNet(run.trailerNet)
    MySQL.update.await("UPDATE truckco_employees SET status = 'idle' WHERE id = ?", { run.employeeId })
    TC.runs[run.contractId] = nil
    return truck, newHealth
end

lib.callback.register('truckco:server:returnTruck', function(src, contractId)
    local run = getRun(src, contractId)
    if not run or run.stage ~= 'return' then return TC.result(false, 'Nothing to return.') end
    local company = TC.getCompany(run.companyId)
    local prop = company and Config.Properties[company.property]
    local truckEnt = TC.entityFromNet(run.truckNet)
    if not prop or not truckEnt or TC.distance(GetEntityCoords(truckEnt), TC.propPoint(company.property, 'truckReturn', company)) > 25.0 then
        return TC.result(false, 'Park the truck at the yard return spot.')
    end
    MySQL.update.await("UPDATE truckco_contracts SET status = 'completed' WHERE id = ?", { contractId })
    local _, health = closeRun(run)
    return TC.result(true, ('Truck parked. Condition: %d%%. Good work!'):format(health))
end)

--- Abandon (player choice, disconnect, truck wrecked).
function TC.abandonRun(run, reason)
    local c = TC.getContract(run.contractId)
    local truckEnt = TC.entityFromNet(run.truckNet)
    local wrecked = not truckEnt or GetVehicleEngineHealth(truckEnt) <= 0
    local truck, _ = closeRun(run, { lost = wrecked })

    if run.stage == 'return' then
        -- cargo was delivered, only the truck needs recovering
        MySQL.update.await("UPDATE truckco_contracts SET status = 'completed' WHERE id = ?", { run.contractId })
        TC.spend(run.companyId, Config.Runs.recoveryFee, ('Truck recovery #%d'):format(run.contractId), true, true)
        return
    end

    if wrecked and truck then
        TC.insuranceClaim(run.companyId, truck, math.floor(truck.price * 0.6), ('truck wrecked #%d'):format(run.contractId))
    end
    TC.spend(run.companyId, Config.Runs.recoveryFee, ('Truck recovery #%d'):format(run.contractId), true, true)

    if c and c.deadline and c.deadline > TC.now() + 120 and not wrecked then
        -- still time on the clock: put the load back in the queue for someone else
        TC.releaseAssignment(c)
        MySQL.update.await("UPDATE truckco_contracts SET awarded_at = ? WHERE id = ?", { TC.now(), c.id })
        TC.notifyCompany(run.companyId, ('Load #%d was dropped (%s) and needs a new driver.'):format(run.contractId, reason), 'warning', 'assign')
    elseif c then
        TC.failContract(c, reason, truck)
    end
end

lib.callback.register('truckco:server:abandonRun', function(src, contractId, reason)
    local run = getRun(src, contractId)
    if not run then return TC.result(false, 'No active load.') end
    TC.abandonRun(run, reason == 'wrecked' and 'truck wrecked' or 'driver abandoned the load')
    return TC.result(true, 'Load abandoned. The company was charged a recovery fee.')
end)

lib.callback.register('truckco:server:getActiveRun', function(src)
    for id, run in pairs(TC.runs) do
        if run.src == src then
            local c = TC.getContract(id)
            local company = TC.getCompany(run.companyId)
            return TC.result(true, nil, {
                contractId = id, truckNet = run.truckNet, trailerNet = run.trailerNet, class = run.class,
                trailer = c.trailer, cargo = c.cargoLabel, pickup = c.pickup, dropoff = c.dropoff, stage = run.stage,
                returnPoint = TC.propPoint(company.property, 'truckReturn', company),
                pay = c.award_amount, distance = c.distance,
                cut = company.owner ~= run.cid and math.floor((c.award_amount or 0) * Config.Runs.driverCommission) or 0,
                deadline = c.deadline and (c.deadline - TC.now()),
            })
        end
    end
    return TC.result(false)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, run in pairs(TC.runs) do
        if run.src == src then
            local ok, err = pcall(TC.abandonRun, run, 'driver went off the grid')
            if not ok then print('[truckco] abandon on drop failed: ' .. tostring(err)) end
        end
    end
end)

--- Runs where the truck vanished/was wrecked or the driver never returned it.
function TC.tickPlayerRuns()
    local now = TC.now()
    for _, run in pairs(TC.runs) do
        local truckEnt = TC.entityFromNet(run.truckNet)
        if not truckEnt or GetVehicleEngineHealth(truckEnt) <= -3999.0 then
            TC.notify(run.src, 'Your truck was destroyed. The load is lost.', 'error')
            TriggerClientEvent('truckco:client:runEnded', run.src)
            TC.abandonRun(run, 'truck destroyed')
        elseif run.stage == 'return' and now - run.deliveredAt > Config.Runs.returnGraceMinutes * 60 then
            TC.notify(run.src, 'You never brought the truck back. The company paid to have it towed.', 'error')
            TriggerClientEvent('truckco:client:runEnded', run.src)
            TC.abandonRun(run, 'truck not returned')
        end
    end
end

--- The assigned (not yet started) load for a player, if any.
function TC.assignedLoadFor(src)
    local company, emp = myEmployee(src)
    if not emp then return nil end
    return MySQL.scalar.await("SELECT id FROM truckco_contracts WHERE employee_id = ? AND status = 'assigned' ORDER BY deadline ASC LIMIT 1", { emp.id })
end
