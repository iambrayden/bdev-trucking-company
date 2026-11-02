--[[
    NPC dispatchers automate the company:
      1. Assign awarded loads to idle, qualified drivers (NPC first, then on-duty players).
      2. Bid on open loads the company can actually cover.
    Each certified NPC dispatcher handles a limited number of concurrent loads
    (baseCapacity + skill/skillPerCapacity + Dispatch Center upgrade).
    A dispatcher's skill also decides how accurately they price bids.
]]

local function dispatchers(companyId)
    local rows = MySQL.query.await(
        "SELECT * FROM truckco_employees WHERE company_id = ? AND kind = 'npc' AND role = 'dispatcher' AND status = 'idle'",
        { companyId }) or {}
    local out = {}
    for _, d in ipairs(rows) do
        TC.decodeEmployee(d)
        if d.certs.dispatch then out[#out + 1] = d end
    end
    return out
end

local function capacityOf(list, effects)
    local cap, bestSkill = 0, 0
    for _, d in ipairs(list) do
        cap = cap + Config.Dispatch.baseCapacity + math.floor(d.skill / Config.Dispatch.skillPerCapacity) + effects.dispatchBonus
        if d.skill > bestSkill then bestSkill = d.skill end
    end
    return cap, bestSkill
end

--- Pick the best driver for a load: NPCs by skill, then on-duty online players.
local function pickDriver(drivers, usePlayers)
    table.sort(drivers, function(a, b) return a.skill > b.skill end)
    for _, d in ipairs(drivers) do
        if d.kind == 'npc' then return d end
    end
    if usePlayers then
        for _, d in ipairs(drivers) do
            if d.kind == 'player' and d.online and d.onDuty then return d end
        end
    end
end

--- Healthiest truck first.
local function pickTruck(trucks)
    table.sort(trucks, function(a, b) return a.health > b.health end)
    return trucks[1]
end

local function runCompany(company)
    local staff = dispatchers(company.id)
    if #staff == 0 then return end
    local effects = TC.effects(company)
    local capacity, skill = capacityOf(staff, effects)

    local active = MySQL.scalar.await(
        "SELECT COUNT(*) FROM truckco_contracts WHERE company_id = ? AND status IN ('awarded','assigned','in_progress')",
        { company.id }) or 0
    local pendingBids = MySQL.scalar.await(
        "SELECT COUNT(*) FROM truckco_bids b JOIN truckco_contracts c ON c.id = b.contract_id WHERE b.company_id = ? AND c.status = 'open'",
        { company.id }) or 0

    -- 1) assign awarded loads
    if company.settings.autoAssign then
        local awarded = MySQL.query.await(
            "SELECT * FROM truckco_contracts WHERE company_id = ? AND status = 'awarded' ORDER BY deadline ASC", { company.id }) or {}
        for _, c in ipairs(awarded) do
            TC.decodeContract(c)
            local drivers, trucks = TC.eligibleResources(company.id, c, company.settings.usePlayerDrivers)
            local driver = pickDriver(drivers, company.settings.usePlayerDrivers)
            local truck = pickTruck(trucks)
            if driver and truck then
                local ok, msg = TC.assign(company, c, driver, truck, 'dispatch')
                TC.log(company.name, 'dispatch assign', ok, msg)
            end
        end
    end

    -- 2) bid on loads we can cover
    if not company.settings.autoBid or TC.isSuspended(company) then return end
    local free = capacity - active - pendingBids
    if free <= 0 then return end

    local open = MySQL.query.await([[
        SELECT c.* FROM truckco_contracts c
        LEFT JOIN truckco_bids b ON b.contract_id = c.id AND b.company_id = ?
        WHERE c.status = 'open' AND c.bid_closes > ? AND b.contract_id IS NULL
        ORDER BY c.max_pay DESC
    ]], { company.id, TC.now() + 20 }) or {}

    -- count idle resources per class so we don't promise more than we have
    local idleNpc = MySQL.query.await(
        "SELECT certs FROM truckco_employees WHERE company_id = ? AND role = 'driver' AND status = 'idle' AND kind = 'npc'", { company.id }) or {}
    local idlePlayers = 0
    if company.settings.usePlayerDrivers then
        local players = MySQL.query.await(
            "SELECT citizenid FROM truckco_employees WHERE company_id = ? AND role = 'driver' AND status = 'idle' AND kind = 'player'", { company.id }) or {}
        for _, p in ipairs(players) do
            if TC.onDuty[p.citizenid] then idlePlayers = idlePlayers + 1 end
        end
    end
    local driverPool = #idleNpc + idlePlayers - pendingBids
    if driverPool <= 0 then return end

    local placed = 0
    for _, c in ipairs(open) do
        if placed >= Config.Dispatch.maxBidsPerPass or placed >= free or placed >= driverPool then break end
        TC.decodeContract(c)
        if company.reputation >= c.minRep then
            local drivers, trucks = TC.eligibleResources(company.id, c, company.settings.usePlayerDrivers)
            if pickDriver(drivers, company.settings.usePlayerDrivers) and #trucks > 0 then
                -- skilled dispatchers read the market better: estimate rival bid with skill-scaled noise
                local err = 0.25 * (1 - skill / 100) + 0.02
                local estimate = c.market_bid * (1 + (math.random() * 2 - 1) * err)
                local repEdge = 1 - (company.reputation - 50) / Config.Board.repAdvantage
                local bid = math.floor(estimate * 0.98 / repEdge / 50) * 50
                bid = TCShared.clamp(bid, math.floor(c.max_pay * Config.Board.minBidPct), c.max_pay)
                local ok = TC.placeBid(company, c.id, bid, true)
                if ok then placed = placed + 1 end
            end
        end
    end
end

function TC.tickDispatch()
    for _, company in ipairs(TC.getAllCompanies()) do
        local ok, err = pcall(runCompany, company)
        if not ok then print(('[truckco] dispatch error for %s: %s'):format(company.name, err)) end
    end
end
