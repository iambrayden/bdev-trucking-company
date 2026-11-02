--[[
    Every Config.Payroll.intervalMinutes per company:
      - NPC wages (always), player wages (if they clocked in this cycle) -> player's pending paycheck
      - insurance premiums per truck
      - property upkeep
    The company can go into overdraft. Below the overdraft limit it is suspended
    (no bidding) and unpaid NPCs may quit.
]]

local function runPayroll(company)
    local staff = MySQL.query.await('SELECT * FROM truckco_employees WHERE company_id = ?', { company.id }) or {}
    local trucks = MySQL.query.await('SELECT price, insurance FROM truckco_trucks WHERE company_id = ?', { company.id }) or {}
    local prop = Config.Properties[company.property]

    local wages, premiums = 0, 0
    local paidPlayers = {}
    for _, e in ipairs(staff) do
        if e.wage > 0 then
            if e.kind == 'npc' then
                wages = wages + e.wage
            elseif not Config.Payroll.playerOnDutyOnly or TC.dutyCycle[e.citizenid] or TC.onDuty[e.citizenid] then
                wages = wages + e.wage
                paidPlayers[#paidPlayers + 1] = e
            end
        end
    end
    for _, t in ipairs(trucks) do
        local tier = Config.Insurance[t.insurance] or Config.Insurance.none
        premiums = premiums + math.floor(t.price * tier.premiumPct)
    end
    local upkeep = prop and prop.upkeep or 0

    if wages > 0 then TC.spend(company.id, wages, ('Payroll (%d staff)'):format(#staff), true, true) end
    if premiums > 0 then TC.spend(company.id, premiums, ('Insurance premiums (%d trucks)'):format(#trucks), true, true) end
    if upkeep > 0 then TC.spend(company.id, upkeep, 'Property upkeep', true, true) end

    for _, e in ipairs(paidPlayers) do
        MySQL.update.await('UPDATE truckco_employees SET pending_pay = pending_pay + ? WHERE id = ?', { e.wage, e.id })
        local s = TC.sourceByCid(e.citizenid)
        if s then TC.notify(s, ('Paycheck of %s is waiting at the office time clock.'):format(TCShared.money(e.wage)), 'success', company.name) end
    end

    MySQL.update.await('UPDATE truckco_companies SET last_payroll = ? WHERE id = ?', { TC.now(), company.id })

    local fresh = TC.getCompany(company.id)
    local total = wages + premiums + upkeep
    if fresh and TC.isSuspended(fresh) then
        local quitChance = Config.NPC.quitChanceUnpaid * TC.effects(fresh).quitMult
        local quitters = {}
        for _, e in ipairs(staff) do
            if e.kind == 'npc' and e.status == 'idle' and math.random() < quitChance then
                MySQL.query.await('DELETE FROM truckco_employees WHERE id = ?', { e.id })
                quitters[#quitters + 1] = e.name
            end
        end
        TC.notifyCompany(company.id, ('Payroll %s pushed the company past its overdraft. Bidding suspended.%s'):format(
            TCShared.money(total), #quitters > 0 and (' Quit: ' .. table.concat(quitters, ', ')) or ''), 'error', 'finance')
    elseif total > 0 then
        TC.notifyCompany(company.id, ('Payroll run: %s (wages %s, insurance %s, upkeep %s).'):format(
            TCShared.money(total), TCShared.money(wages), TCShared.money(premiums), TCShared.money(upkeep)), 'inform', 'finance')
    end
end

function TC.tickPayroll()
    local due = TC.now() - Config.Payroll.intervalMinutes * 60
    local rows = MySQL.query.await('SELECT id FROM truckco_companies WHERE last_payroll <= ?', { due }) or {}
    for _, r in ipairs(rows) do
        local company = TC.getCompany(r.id)
        if company then
            local ok, err = pcall(runPayroll, company)
            if not ok then print(('[truckco] payroll error for %s: %s'):format(company.name, err)) end
        end
    end
    if #rows > 0 then
        -- reset "worked this cycle" flags; anyone still on duty counts for next cycle
        TC.dutyCycle = {}
        for cid in pairs(TC.onDuty) do TC.dutyCycle[cid] = true end
    end
end
