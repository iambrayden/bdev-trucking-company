local cargoKeys = {}
for k in pairs(Config.Cargo) do cargoKeys[#cargoKeys + 1] = k end
table.sort(cargoKeys)

local function decodeContract(c)
    if not c then return nil end
    c.pickup = json.decode(c.pickup)
    c.dropoff = json.decode(c.dropoff)
    c.stops = c.stops and json.decode(c.stops) or {}
    c.express = c.express == 1 or c.express == true
    local cargo = Config.Cargo[c.cargo] or {}
    c.cargoLabel = cargo.label or c.cargo
    c.class = cargo.class or 'semi'
    c.certs = cargo.certs or {}
    c.minRep = cargo.minRep or 0
    return c
end
TC.decodeContract = decodeContract

function TC.getContract(id)
    return decodeContract(MySQL.single.await('SELECT * FROM truckco_contracts WHERE id = ?', { id }))
end

--------------------------------------------------------------------------------
-- Generation
--------------------------------------------------------------------------------
local function pt(label, c) return { label = label, x = c.x, y = c.y, z = c.z, w = c.w } end

local function generateContract()
    local B = Config.Board
    local cargoKey = cargoKeys[math.random(#cargoKeys)]
    local cargo = Config.Cargo[cargoKey]
    local pickup = Config.Pickups[math.random(#Config.Pickups)]
    local dest = Config.Destinations[math.random(#Config.Destinations)]

    -- multi-stop: extra collection stops between pickup and drop-off
    local stops = {}
    local pool = Config.CollectionPoints or {}
    if #pool > 0 and math.random() < (B.multiStopChance or 0) then
        local n = math.random(1, math.min(B.multiStopMax or 3, #pool))
        local used = {}
        while #stops < n do
            local i = math.random(#pool)
            if not used[i] then
                used[i] = true
                stops[#stops + 1] = pt(pool[i].label, pool[i].coords)
            end
        end
    end

    -- route length: pickup -> stops... -> drop-off
    local meters, prev = 0.0, pickup.coords
    for _, st in ipairs(stops) do
        meters = meters + TC.distance(prev, st)
        prev = st
    end
    meters = meters + TC.distance(prev, dest.coords)
    local km = meters * B.roadFactor / 1000.0

    local express = math.random() < (B.expressChance or 0)
    local mult = cargo.payMult * (1 + (B.multiStopBonus or 0) * #stops) * (express and (B.expressPayMult or 1) or 1)
    local maxPay = math.max(B.minPay, math.floor(km * B.ratePerKm * mult))
    -- small random swing so identical routes aren't identical prices
    maxPay = math.floor(maxPay * (0.9 + math.random() * 0.25) / 50) * 50
    local lo, hi = B.marketBid[1], B.marketBid[2]
    local market = math.floor(maxPay * (lo + math.random() * (hi - lo)))
    local trailer = cargo.trailers and cargo.trailers[math.random(#cargo.trailers)] or nil
    local now = TC.now()
    MySQL.insert.await(
        'INSERT INTO truckco_contracts (cargo, trailer, pickup, dropoff, stops, express, distance, max_pay, market_bid, bid_closes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            cargoKey, trailer,
            json.encode(pt(pickup.label, pickup.coords)),
            json.encode(pt(dest.label, dest.coords)),
            #stops > 0 and json.encode(stops) or nil,
            express and 1 or 0,
            math.floor(km * 10) / 10, maxPay, market,
            now + math.random(B.bidWindow[1], B.bidWindow[2]), now,
        })
end

function TC.tickGenerate()
    local companies = MySQL.scalar.await('SELECT COUNT(*) FROM truckco_companies') or 0
    if companies == 0 then return end
    local target = math.min(Config.Board.maxOpen, Config.Board.baseOpen + Config.Board.perCompanyOpen * companies)
    local open = MySQL.scalar.await("SELECT COUNT(*) FROM truckco_contracts WHERE status = 'open'") or 0
    -- trickle new loads in rather than refilling the board at once
    local toMake = math.min(target - open, 3)
    for _ = 1, toMake do generateContract() end
    -- housekeeping: forget old finished contracts
    MySQL.query.await("DELETE FROM truckco_contracts WHERE status IN ('completed','failed','lost','expired') AND COALESCE(finished_at, created_at) < ?",
        { TC.now() - 7200 })
end

--------------------------------------------------------------------------------
-- Board & bids
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:getBoard', function(src)
    local company, err = TC.authorize(src, 'view')
    if not company then return TC.result(false, err) end
    local rows = MySQL.query.await([[
        SELECT c.*, b.amount AS my_bid,
            (SELECT COUNT(*) FROM truckco_bids x WHERE x.contract_id = c.id) AS bid_count
        FROM truckco_contracts c
        LEFT JOIN truckco_bids b ON b.contract_id = c.id AND b.company_id = ?
        WHERE c.status = 'open' AND c.bid_closes > ?
        ORDER BY c.bid_closes ASC
    ]], { company.id, TC.now() }) or {}
    local now = TC.now()
    for _, c in ipairs(rows) do
        decodeContract(c)
        c.market_bid = nil -- never leak the hidden rival bid
        c.closesIn = c.bid_closes - now
        c.eligible = company.reputation >= c.minRep
    end
    return TC.result(true, nil, {
        list = rows,
        reputation = company.reputation,
        suspended = TC.isSuspended(company),
        minBidPct = Config.Board.minBidPct,
    })
end)

--- Shared by manual bids and dispatcher bids.
function TC.placeBid(company, contractId, amount, auto)
    local c = TC.getContract(contractId)
    if not c or c.status ~= 'open' or c.bid_closes <= TC.now() then return false, 'Bidding has closed on that load.' end
    if TC.isSuspended(company) then return false, 'Company is suspended for unpaid debts.' end
    if company.reputation < c.minRep then return false, ('Requires %d reputation.'):format(c.minRep) end
    amount = math.floor(tonumber(amount) or 0)
    local minBid = math.floor(c.max_pay * Config.Board.minBidPct)
    if amount < minBid or amount > c.max_pay then
        return false, ('Bid must be between %s and %s.'):format(TCShared.money(minBid), TCShared.money(c.max_pay))
    end
    MySQL.query.await(
        'INSERT INTO truckco_bids (contract_id, company_id, amount, auto, created_at) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE amount = VALUES(amount), auto = VALUES(auto), created_at = VALUES(created_at)',
        { c.id, company.id, amount, auto and 1 or 0, TC.now() })
    return true, ('Bid of %s placed on #%d.'):format(TCShared.money(amount), c.id)
end

lib.callback.register('truckco:server:placeBid', function(src, contractId, amount)
    local company, err = TC.authorize(src, 'bid')
    if not company then return TC.result(false, err) end
    local ok, msg = TC.placeBid(company, contractId, amount, false)
    return TC.result(ok, msg)
end)

lib.callback.register('truckco:server:withdrawBid', function(src, contractId)
    local company, err = TC.authorize(src, 'bid')
    if not company then return TC.result(false, err) end
    MySQL.query.await("DELETE b FROM truckco_bids b JOIN truckco_contracts c ON c.id = b.contract_id WHERE b.contract_id = ? AND b.company_id = ? AND c.status = 'open'",
        { contractId, company.id })
    return TC.result(true, 'Bid withdrawn.')
end)

--- Close bidding on expired contracts and award them.
function TC.tickResolveBids()
    local now = TC.now()
    local due = MySQL.query.await("SELECT * FROM truckco_contracts WHERE status = 'open' AND bid_closes <= ?", { now }) or {}
    for _, c in ipairs(due) do
        local bids = MySQL.query.await([[
            SELECT b.*, co.reputation, co.balance FROM truckco_bids b
            JOIN truckco_companies co ON co.id = b.company_id
            WHERE b.contract_id = ?
        ]], { c.id }) or {}
        local best, bestScore
        for _, b in ipairs(bids) do
            if b.balance > Config.Payroll.overdraftLimit then
                local score = b.amount * (1 - (b.reputation - 50) / Config.Board.repAdvantage)
                if score <= c.market_bid and (not bestScore or score < bestScore) then
                    best, bestScore = b, score
                end
            end
        end
        if best then
            local cargo = Config.Cargo[c.cargo]
            local deadlineMin = c.distance / Config.Board.deadlineKmPerMin + Config.Board.deadlineBuffer
            if c.stops then deadlineMin = deadlineMin + 3 * #(json.decode(c.stops) or {}) end -- time to load at each stop
            if c.express == 1 then deadlineMin = deadlineMin * (Config.Board.expressDeadlineMult or 1) end
            MySQL.update.await(
                "UPDATE truckco_contracts SET status = 'awarded', company_id = ?, award_amount = ?, awarded_at = ?, deadline = ? WHERE id = ?",
                { best.company_id, best.amount, now, now + math.floor(deadlineMin * 60) + Config.Board.acceptWindow, c.id })
            TC.notifyCompany(best.company_id,
                ('Won load #%d: %s to %s for %s. Assign a driver within %s.'):format(
                    c.id, cargo and cargo.label or c.cargo, json.decode(c.dropoff).label,
                    TCShared.money(best.amount), TCShared.duration(Config.Board.acceptWindow)),
                'success', 'assign')
            for _, b in ipairs(bids) do
                if b.company_id ~= best.company_id and b.auto == 0 then
                    TC.notifyCompany(b.company_id, ('Lost the bid on load #%d.'):format(c.id), 'error', 'bid')
                end
            end
        else
            MySQL.update.await("UPDATE truckco_contracts SET status = ?, finished_at = ? WHERE id = ?",
                { #bids > 0 and 'lost' or 'expired', now, c.id })
            for _, b in ipairs(bids) do
                if b.auto == 0 then
                    TC.notifyCompany(b.company_id, ('A rival outbid you on load #%d.'):format(c.id), 'error', 'bid')
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Company contracts & assignment
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:getMyContracts', function(src)
    local company, err = TC.authorize(src, 'view')
    if not company then return TC.result(false, err) end
    local rows = MySQL.query.await([[
        SELECT c.*, e.name AS driver_name, t.plate AS truck_plate, t.model AS truck_model
        FROM truckco_contracts c
        LEFT JOIN truckco_employees e ON e.id = c.employee_id
        LEFT JOIN truckco_trucks t ON t.id = c.truck_id
        WHERE c.company_id = ? AND (c.status IN ('awarded','assigned','in_progress','delivered') OR (c.finished_at IS NOT NULL AND c.finished_at > ?))
        ORDER BY FIELD(c.status, 'awarded','assigned','in_progress','delivered','completed','failed'), c.id DESC
        LIMIT 40
    ]], { company.id, TC.now() - 3600 }) or {}
    local now = TC.now()
    for _, c in ipairs(rows) do
        decodeContract(c)
        c.market_bid = nil
        if c.deadline then c.deadlineIn = c.deadline - now end
        if c.awarded_at and c.status == 'awarded' then c.acceptIn = c.awarded_at + Config.Board.acceptWindow - now end
        if c.eta then c.etaIn = math.max(0, c.eta - now) end
    end
    return TC.result(true, nil, rows)
end)

--- Which drivers + trucks can take this contract right now.
function TC.eligibleResources(companyId, contract, includePlayers)
    local drivers = MySQL.query.await(
        "SELECT * FROM truckco_employees WHERE company_id = ? AND role = 'driver' AND status = 'idle'", { companyId }) or {}
    local okDrivers = {}
    for _, d in ipairs(drivers) do
        TC.decodeEmployee(d)
        if TCShared.hasCerts(d.certs, contract.certs) then
            if d.kind == 'npc' then
                okDrivers[#okDrivers + 1] = d
            elseif includePlayers ~= false then
                d.online = TC.sourceByCid(d.citizenid) ~= nil
                d.onDuty = TC.onDuty[d.citizenid] ~= nil
                if d.online then okDrivers[#okDrivers + 1] = d end
            end
        end
    end
    local trucks = MySQL.query.await(
        "SELECT * FROM truckco_trucks WHERE company_id = ? AND status = 'available' AND health >= ?",
        { companyId, Config.Fleet.minDispatchCondition }) or {}
    local okTrucks = {}
    for _, t in ipairs(trucks) do
        local def = Config.Trucks[t.model]
        if def and def.class == contract.class then okTrucks[#okTrucks + 1] = t end
    end
    return okDrivers, okTrucks
end

lib.callback.register('truckco:server:getAssignOptions', function(src, contractId)
    local company, err = TC.authorize(src, 'assign')
    if not company then return TC.result(false, err) end
    local c = TC.getContract(contractId)
    if not c or c.company_id ~= company.id or c.status ~= 'awarded' then return TC.result(false, 'Load is not awaiting assignment.') end
    local drivers, trucks = TC.eligibleResources(company.id, c, true)
    return TC.result(true, nil, { drivers = drivers, trucks = trucks, contract = c })
end)

--- Assign a driver + truck to an awarded contract. NPCs leave right away,
--- players get notified and must pick up the truck from the yard.
function TC.assign(company, contract, driver, truck, by)
    if contract.status ~= 'awarded' then return false, 'Load is not awaiting assignment.' end
    -- reserve the truck atomically so two dispatchers can't double-book it
    local reserved = MySQL.update.await(
        "UPDATE truckco_trucks SET status = ? WHERE id = ? AND company_id = ? AND status = 'available'",
        { driver.kind == 'npc' and 'in_use' or 'reserved', truck.id, company.id })
    if reserved < 1 then return false, 'Truck is no longer available.' end
    local claimed = MySQL.update.await(
        "UPDATE truckco_employees SET status = ? WHERE id = ? AND company_id = ? AND status = 'idle'",
        { driver.kind == 'npc' and 'on_job' or 'assigned', driver.id, company.id })
    if claimed < 1 then
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE id = ?", { truck.id })
        return false, 'Driver is no longer available.'
    end

    if driver.kind == 'npc' then
        TC.startNpcRun(company, contract, driver, truck, by)
        return true, ('%s is on the way to %s in %s.'):format(driver.name, contract.pickup.label, truck.plate)
    end

    MySQL.update.await(
        "UPDATE truckco_contracts SET status = 'assigned', employee_id = ?, truck_id = ?, assigned_by = ?, driver_kind = 'player' WHERE id = ?",
        { driver.id, truck.id, by, contract.id })
    local s = TC.sourceByCid(driver.citizenid)
    if s then
        TriggerClientEvent('truckco:client:newAssignment', s, {
            id = contract.id, cargo = contract.cargoLabel, pickup = contract.pickup.label, dropoff = contract.dropoff.label,
            distance = contract.distance, plate = truck.plate, company = company.name,
            pay = contract.award_amount,
            deadline = contract.deadline and (contract.deadline - TC.now()),
        })
    end
    return true, ('Load #%d assigned to %s.'):format(contract.id, driver.name)
end

lib.callback.register('truckco:server:assignContract', function(src, contractId, employeeId, truckId)
    local company, err = TC.authorize(src, 'assign')
    if not company then return TC.result(false, err) end
    local c = TC.getContract(contractId)
    if not c or c.company_id ~= company.id then return TC.result(false, 'Load not found.') end
    local drivers, trucks = TC.eligibleResources(company.id, c, true)
    local driver, truck
    for _, d in ipairs(drivers) do if d.id == employeeId then driver = d end end
    for _, t in ipairs(trucks) do if t.id == truckId then truck = t end end
    if not driver then return TC.result(false, 'That driver cannot take this load (busy, offline or missing certs).') end
    if not truck then return TC.result(false, 'That truck cannot take this load.') end
    local ok, msg = TC.assign(company, c, driver, truck, 'manual')
    return TC.result(ok, msg)
end)

lib.callback.register('truckco:server:unassignContract', function(src, contractId)
    local company, err = TC.authorize(src, 'assign')
    if not company then return TC.result(false, err) end
    local c = TC.getContract(contractId)
    if not c or c.company_id ~= company.id or c.status ~= 'assigned' then
        return TC.result(false, 'Only loads that have not left the yard can be unassigned.')
    end
    TC.releaseAssignment(c)
    return TC.result(true, ('Load #%d is back in the queue.'):format(c.id))
end)

function TC.releaseAssignment(c)
    MySQL.update.await("UPDATE truckco_contracts SET status = 'awarded', employee_id = NULL, truck_id = NULL, driver_kind = NULL, assigned_by = NULL, started_at = NULL WHERE id = ?", { c.id })
    if c.employee_id then MySQL.update.await("UPDATE truckco_employees SET status = 'idle' WHERE id = ?", { c.employee_id }) end
    if c.truck_id then MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE id = ?", { c.truck_id }) end
end

--------------------------------------------------------------------------------
-- Completion / failure
--------------------------------------------------------------------------------
--- @param opts { damage: number? } damage 0..1 of the cargo
--- @return number payout, boolean late
function TC.payContract(c, opts)
    local now = TC.now()
    local late = c.deadline and now > c.deadline
    local pay = c.award_amount or 0
    if late then pay = pay * (1 - Config.Board.latePenalty) end
    local damage = TCShared.clamp((opts and opts.damage) or 0, 0, 1)
    pay = math.floor(pay * (1 - damage * 0.8))
    TC.addFunds(c.company_id, pay, ('Load #%d delivered%s%s'):format(
        c.id, late and ' (late)' or '', damage > 0.05 and (' (%d%% cargo damage)'):format(math.floor(damage * 100)) or ''))
    TC.adjustRep(c.company_id, late and Config.Board.repLate or Config.Board.repOnTime)
    if c.employee_id then
        MySQL.update.await('UPDATE truckco_employees SET jobs_done = jobs_done + 1, skill = LEAST(100, skill + ?) WHERE id = ?',
            { Config.NPC.skillPerJob, c.employee_id })
    end
    return pay, late
end

--- Mark a contract failed and bill the company the liability penalty.
function TC.failContract(c, reason, truck)
    local penalty = math.floor((c.award_amount or 0) * Config.Board.failPenalty)
    MySQL.update.await("UPDATE truckco_contracts SET status = 'failed', finished_at = ? WHERE id = ?", { TC.now(), c.id })
    if penalty > 0 then TC.spend(c.company_id, penalty, ('Load #%d failed: %s'):format(c.id, reason), true, true) end
    TC.adjustRep(c.company_id, Config.Board.repFail)
    if c.employee_id then MySQL.update.await("UPDATE truckco_employees SET status = 'idle' WHERE id = ? AND status IN ('on_job','assigned')", { c.employee_id }) end
    if truck then TC.insuranceClaim(c.company_id, truck, penalty, ('cargo liability #%d'):format(c.id)) end
    TC.notifyCompany(c.company_id, ('Load #%d failed (%s). Penalty %s.'):format(c.id, reason, TCShared.money(penalty)), 'error', 'assign')
    return penalty
end

--- Awarded/assigned loads nobody started in time.
function TC.tickExpireAwards()
    local cutoff = TC.now() - Config.Board.acceptWindow
    local rows = MySQL.query.await("SELECT * FROM truckco_contracts WHERE status IN ('awarded','assigned') AND awarded_at <= ?", { cutoff }) or {}
    for _, c in ipairs(rows) do
        if not TC.runs[c.id] then
            decodeContract(c)
            if c.truck_id then MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE id = ? AND status = 'reserved'", { c.truck_id }) end
            TC.failContract(c, 'never left the yard')
        end
    end
end
