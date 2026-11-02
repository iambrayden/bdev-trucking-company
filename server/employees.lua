local function employeeCount(companyId)
    return MySQL.scalar.await('SELECT COUNT(*) FROM truckco_employees WHERE company_id = ?', { companyId }) or 0
end

local function getEmployee(companyId, id)
    return TC.decodeEmployee(MySQL.single.await(
        'SELECT * FROM truckco_employees WHERE id = ? AND company_id = ?', { id, companyId }))
end

--------------------------------------------------------------------------------
-- NPC applicant pool
--------------------------------------------------------------------------------
local function randomName()
    local f = Config.NPC.firstNames
    local l = Config.NPC.lastNames
    return ('%s %s'):format(f[math.random(#f)], l[math.random(#l)])
end

local function makeCandidate()
    local roles = {}
    for k, r in pairs(Config.Roles) do if r.npc then roles[#roles + 1] = k end end
    local role = roles[math.random(#roles)]
    -- skew skill low: most applicants are green, a few are veterans
    local skill = math.floor((math.random() ^ 1.7) * 90) + 5
    local certs = {}
    if role == 'driver' and skill >= 45 then certs.cdl = true end
    if role == 'driver' and skill >= 75 and math.random() < 0.5 then certs.tanker = true end
    if role == 'dispatcher' and skill >= 60 then certs.dispatch = true end
    local r = Config.Roles[role]
    return {
        name = randomName(),
        role = role,
        skill = skill,
        certs = certs,
        wage = math.min(r.maxWage, r.minWage + skill * Config.NPC.wagePerSkill),
        years = math.max(0, math.floor(skill / 10 + math.random(-2, 2))),
    }
end

local function getCandidates(companyId)
    local pool = TC.candidates[companyId]
    if not pool or pool.expires < TC.now() then
        pool = { expires = TC.now() + Config.NPC.refreshMinutes * 60, list = {} }
        for i = 1, Config.NPC.candidates do pool.list[i] = makeCandidate() end
        TC.candidates[companyId] = pool
    end
    return pool
end

lib.callback.register('truckco:server:getCandidates', function(src)
    local company, err = TC.authorize(src, 'hire')
    if not company then return TC.result(false, err) end
    local pool = getCandidates(company.id)
    return TC.result(true, nil, { list = pool.list, refreshIn = pool.expires - TC.now(), fee = Config.NPC.hireFee })
end)

lib.callback.register('truckco:server:hireCandidate', function(src, index)
    local company, err = TC.authorize(src, 'hire')
    if not company then return TC.result(false, err) end
    local pool = getCandidates(company.id)
    local cand = pool.list[index]
    if not cand then return TC.result(false, 'That applicant is no longer available.') end
    if employeeCount(company.id) >= TC.effects(company).maxEmployees then
        return TC.result(false, 'No room for more staff. Buy more desks.')
    end
    if not TC.spend(company.id, Config.NPC.hireFee, ('Recruiter fee: %s'):format(cand.name)) then
        return TC.result(false, ('Company needs %s for the recruiter fee.'):format(TCShared.money(Config.NPC.hireFee)))
    end
    MySQL.insert.await(
        "INSERT INTO truckco_employees (company_id, kind, name, role, skill, wage, certs) VALUES (?, 'npc', ?, ?, ?, ?, ?)",
        { company.id, cand.name, cand.role, cand.skill, cand.wage, json.encode(cand.certs) })
    table.remove(pool.list, index)
    return TC.result(true, ('%s joined as a %s.'):format(cand.name, Config.Roles[cand.role].label))
end)

--------------------------------------------------------------------------------
-- Player hires (invite -> accept)
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:invitePlayer', function(src, target, role, wage)
    local company, myRole = TC.authorize(src, 'hire')
    if not company then return TC.result(false, myRole) end
    target = tonumber(target)
    role = Config.Roles[role] and role or nil
    if not role then return TC.result(false, 'Invalid role.') end
    if role == 'manager' and myRole ~= 'owner' then return TC.result(false, 'Only the owner can hire managers.') end
    local r = Config.Roles[role]
    wage = math.floor(tonumber(wage) or 0)
    if wage < r.minWage or wage > r.maxWage then
        return TC.result(false, ('Wage must be between %s and %s.'):format(TCShared.money(r.minWage), TCShared.money(r.maxWage)))
    end
    if not target or target == src then return TC.result(false, 'Invalid player.') end
    local tp = TC.getPlayer(target)
    if not tp then return TC.result(false, 'Player not found.') end
    if TC.distance(GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target))) > 10.0 then
        return TC.result(false, 'They need to be standing near you.')
    end
    if TC.getMembership(target) then return TC.result(false, 'They already own or work for a trucking company.') end
    if employeeCount(company.id) >= TC.effects(company).maxEmployees then
        return TC.result(false, 'No room for more staff. Buy more desks.')
    end
    TC.invites[target] = { companyId = company.id, role = role, wage = wage, expires = TC.now() + 60, from = src }
    TriggerClientEvent('truckco:client:jobOffer', target, {
        company = company.name, role = r.label, wage = wage, interval = Config.Payroll.intervalMinutes,
    })
    return TC.result(true, ('Offer sent to %s.'):format(TC.charName(tp)))
end)

lib.callback.register('truckco:server:respondOffer', function(src, accept)
    local inv = TC.invites[src]
    TC.invites[src] = nil
    if not inv or inv.expires < TC.now() then return TC.result(false, 'The offer expired.') end
    if not accept then
        if GetPlayerName(inv.from) then TC.notify(inv.from, 'Your job offer was declined.', 'error') end
        return TC.result(true, 'Offer declined.')
    end
    local company = TC.getCompany(inv.companyId)
    if not company then return TC.result(false, 'That company no longer exists.') end
    if TC.getMembership(src) then return TC.result(false, 'You already work for a trucking company.') end
    if employeeCount(company.id) >= TC.effects(company).maxEmployees then return TC.result(false, 'The position was filled.') end
    local player = TC.getPlayer(src)
    MySQL.insert.await(
        "INSERT INTO truckco_employees (company_id, kind, citizenid, name, role, skill, wage, certs) VALUES (?, 'player', ?, ?, ?, 10, ?, '{}')",
        { company.id, player.PlayerData.citizenid, TC.charName(player), inv.role, inv.wage })
    TC.notifyCompany(company.id, ('%s accepted a position as %s.'):format(TC.charName(player), Config.Roles[inv.role].label), 'success', 'hire')
    TriggerClientEvent('truckco:client:garageChanged', src)
    return TC.result(true, ('Welcome to %s!'):format(company.name))
end)

-- Owner puts themself on the roster so they can drive loads too.
lib.callback.register('truckco:server:joinRoster', function(src)
    local company, role, emp = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can do that.') end
    if emp then return TC.result(false, 'You are already on the roster.') end
    if employeeCount(company.id) >= TC.effects(company).maxEmployees then
        return TC.result(false, 'No room for more staff. Buy more desks.')
    end
    local player = TC.getPlayer(src)
    MySQL.insert.await(
        "INSERT INTO truckco_employees (company_id, kind, citizenid, name, role, skill, wage, certs) VALUES (?, 'player', ?, ?, 'driver', 10, 0, '{}')",
        { company.id, player.PlayerData.citizenid, TC.charName(player) })
    return TC.result(true, 'You are now on the roster as a driver (no wage). Get certified before taking semi loads.')
end)

lib.callback.register('truckco:server:quitCompany', function(src)
    local company, role, emp = TC.authorize(src)
    if not company or not emp then return TC.result(false, 'You are not on a roster.') end
    if emp.status == 'on_job' or emp.status == 'assigned' then return TC.result(false, 'Finish or cancel your current load first.') end
    local pay = emp.pending_pay
    MySQL.query.await('DELETE FROM truckco_employees WHERE id = ?', { emp.id })
    if pay > 0 then TC.getPlayer(src).Functions.AddMoney('bank', pay, 'truckco-final-paycheck') end
    TC.onDuty[emp.citizenid] = nil
    if role ~= 'owner' then
        TC.notifyCompany(company.id, ('%s quit.'):format(emp.name), 'error', 'hire')
    end
    return TC.result(true, pay > 0 and ('You left. Final paycheck: %s'):format(TCShared.money(pay)) or 'You left the company.')
end)

--------------------------------------------------------------------------------
-- Roster management
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:getEmployees', function(src)
    local company, err = TC.authorize(src, 'view')
    if not company then return TC.result(false, err) end
    local rows = MySQL.query.await('SELECT * FROM truckco_employees WHERE company_id = ? ORDER BY role, name', { company.id }) or {}
    local now = TC.now()
    for _, e in ipairs(rows) do
        TC.decodeEmployee(e)
        if e.kind == 'player' then
            e.online = TC.sourceByCid(e.citizenid) ~= nil
            e.onDuty = TC.onDuty[e.citizenid] ~= nil
        end
        if e.training_until then e.trainingLeft = math.max(0, e.training_until - now) end
    end
    return TC.result(true, nil, { list = rows, max = TC.effects(company).maxEmployees })
end)

lib.callback.register('truckco:server:fireEmployee', function(src, id)
    local company, err = TC.authorize(src, 'fire')
    if not company then return TC.result(false, err) end
    local emp = getEmployee(company.id, id)
    if not emp then return TC.result(false, 'Employee not found.') end
    if emp.citizenid == company.owner then return TC.result(false, 'Use "Leave roster" to remove yourself.') end
    if emp.status == 'on_job' then return TC.result(false, 'They are out on a load right now.') end
    if emp.status == 'assigned' then
        MySQL.update.await("UPDATE truckco_contracts SET status = 'awarded', employee_id = NULL, truck_id = NULL, driver_kind = NULL WHERE employee_id = ? AND status = 'assigned'", { emp.id })
        MySQL.update.await("UPDATE truckco_trucks SET status = 'available' WHERE company_id = ? AND status = 'reserved' AND id NOT IN (SELECT truck_id FROM truckco_contracts WHERE truck_id IS NOT NULL AND status IN ('assigned','in_progress','delivered'))", { company.id })
    end
    MySQL.query.await('DELETE FROM truckco_employees WHERE id = ?', { emp.id })
    if emp.kind == 'player' then
        TC.onDuty[emp.citizenid] = nil
        local s = TC.sourceByCid(emp.citizenid)
        if emp.pending_pay > 0 then
            if s then
                TC.getPlayer(s).Functions.AddMoney('bank', emp.pending_pay, 'truckco-final-paycheck')
            else
                -- offline: hand them the cash via qbx offline money support if available
                local ok, paid = pcall(function()
                    return exports.qbx_core:AddMoney(emp.citizenid, 'bank', emp.pending_pay, 'truckco-final-paycheck')
                end)
                if not ok or paid == false then
                    print(('[truckco] could not pay %s final paycheck of %d to offline %s'):format(emp.name, emp.pending_pay, emp.citizenid))
                end
            end
        end
        if s then TC.notify(s, ('You were let go from %s.'):format(company.name), 'error') end
    end
    return TC.result(true, ('%s was let go.'):format(emp.name))
end)

lib.callback.register('truckco:server:setRole', function(src, id, role)
    local company, myRole = TC.authorize(src, 'hire')
    if not company then return TC.result(false, myRole) end
    local emp = getEmployee(company.id, id)
    local r = Config.Roles[role]
    if not emp or not r then return TC.result(false, 'Invalid employee or role.') end
    if emp.kind == 'npc' and not r.npc then return TC.result(false, 'NPCs cannot hold that role.') end
    if emp.status ~= 'idle' then return TC.result(false, 'They are busy right now.') end
    if (role == 'manager' or emp.role == 'manager') and myRole ~= 'owner' then
        return TC.result(false, 'Only the owner can promote managers.')
    end
    local wage = TCShared.clamp(emp.wage, r.minWage, r.maxWage)
    if emp.citizenid == company.owner then wage = 0 end
    MySQL.update.await('UPDATE truckco_employees SET role = ?, wage = ? WHERE id = ?', { role, wage, emp.id })
    return TC.result(true, ('%s is now a %s.'):format(emp.name, r.label))
end)

lib.callback.register('truckco:server:setWage', function(src, id, wage)
    local company, err = TC.authorize(src, 'hire')
    if not company then return TC.result(false, err) end
    local emp = getEmployee(company.id, id)
    if not emp then return TC.result(false, 'Employee not found.') end
    local r = Config.Roles[emp.role]
    wage = math.floor(tonumber(wage) or 0)
    if wage < r.minWage or wage > r.maxWage then
        return TC.result(false, ('Wage must be between %s and %s.'):format(TCShared.money(r.minWage), TCShared.money(r.maxWage)))
    end
    MySQL.update.await('UPDATE truckco_employees SET wage = ? WHERE id = ?', { wage, emp.id })
    return TC.result(true, ('%s now earns %s per shift.'):format(emp.name, TCShared.money(wage)))
end)

--------------------------------------------------------------------------------
-- Training
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:trainEmployee', function(src, id, certKey)
    local company, err = TC.authorize(src, 'train')
    if not company then return TC.result(false, err) end
    local emp = getEmployee(company.id, id)
    local cert = Config.Certifications[certKey]
    if not emp or not cert then return TC.result(false, 'Invalid employee or course.') end
    if emp.status ~= 'idle' then return TC.result(false, 'They are busy right now.') end
    if emp.certs[certKey] then return TC.result(false, 'Already certified.') end
    if cert.roles and not cert.roles[emp.role] then return TC.result(false, 'That course is not for their role.') end
    if cert.requires and not emp.certs[cert.requires] then
        return TC.result(false, ('Requires %s first.'):format(Config.Certifications[cert.requires].label))
    end
    if not TC.spend(company.id, cert.cost, ('Training: %s - %s'):format(emp.name, cert.label)) then
        return TC.result(false, ('Company needs %s for this course.'):format(TCShared.money(cert.cost)))
    end
    local seconds = math.floor(cert.minutes * 60 * TC.effects(company).trainingMult)
    MySQL.update.await("UPDATE truckco_employees SET status = 'training', training_cert = ?, training_until = ? WHERE id = ?",
        { certKey, TC.now() + seconds, emp.id })
    if emp.kind == 'player' then
        TC.onDuty[emp.citizenid] = nil
        local s = TC.sourceByCid(emp.citizenid)
        if s then TC.notify(s, ('You were enrolled in %s (%s).'):format(cert.label, TCShared.duration(seconds)), 'inform') end
    end
    return TC.result(true, ('%s started %s. Done in %s.'):format(emp.name, cert.label, TCShared.duration(seconds)))
end)

function TC.tickTraining()
    local rows = MySQL.query.await("SELECT * FROM truckco_employees WHERE status = 'training' AND training_until <= ?", { TC.now() }) or {}
    for _, e in ipairs(rows) do
        TC.decodeEmployee(e)
        if e.training_cert then e.certs[e.training_cert] = true end
        MySQL.update.await("UPDATE truckco_employees SET status = 'idle', certs = ?, training_cert = NULL, training_until = NULL, skill = LEAST(100, skill + 3) WHERE id = ?",
            { json.encode(e.certs), e.id })
        local label = Config.Certifications[e.training_cert] and Config.Certifications[e.training_cert].label or e.training_cert
        TC.notifyCompany(e.company_id, ('%s completed %s.'):format(e.name, label), 'success', 'train')
        if e.kind == 'player' then
            local s = TC.sourceByCid(e.citizenid)
            if s then TC.notify(s, ('You earned your %s!'):format(label), 'success') end
        end
    end
end

--------------------------------------------------------------------------------
-- Player employee: duty + paycheck
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:toggleDuty', function(src)
    local company, role, emp = TC.authorize(src)
    if not company or not emp then return TC.result(false, 'You are not on the roster.') end
    if emp.status == 'training' then return TC.result(false, 'You are in training.') end
    local cid = emp.citizenid
    if TC.onDuty[cid] then
        TC.onDuty[cid] = nil
        return TC.result(true, 'You clocked out.', { onDuty = false })
    end
    TC.onDuty[cid] = src
    TC.dutyCycle[cid] = true
    return TC.result(true, 'You clocked in. Dispatch can now send you loads.', { onDuty = true })
end)

lib.callback.register('truckco:server:collectPay', function(src)
    local company, role, emp = TC.authorize(src)
    if not company or not emp then return TC.result(false, 'You are not on the roster.') end
    if emp.pending_pay <= 0 then return TC.result(false, 'No paycheck waiting.') end
    local affected = MySQL.update.await('UPDATE truckco_employees SET pending_pay = 0 WHERE id = ? AND pending_pay = ?',
        { emp.id, emp.pending_pay })
    if affected < 1 then return TC.result(false, 'Try again.') end
    TC.getPlayer(src).Functions.AddMoney('bank', emp.pending_pay, 'truckco-paycheck')
    return TC.result(true, ('Collected %s.'):format(TCShared.money(emp.pending_pay)))
end)

--- Clock a player employee out and let owners/managers know.
function TC.clockOut(cid, why)
    if not TC.onDuty[cid] then return false end
    TC.onDuty[cid] = nil
    local emp = MySQL.single.await("SELECT company_id, name FROM truckco_employees WHERE citizenid = ? AND kind = 'player'", { cid })
    if emp and why then
        TC.notifyCompany(emp.company_id, ('%s was clocked out (%s).'):format(emp.name, why), 'inform', 'hire')
    end
    return true
end

local function clockOutSource(src, why)
    for cid, s in pairs(TC.onDuty) do
        if s == src then pcall(TC.clockOut, cid, why) end
    end
end

-- leaving the server
AddEventHandler('playerDropped', function()
    clockOutSource(source, 'left the server')
end)

-- logging out / switching character without leaving (multicharacter)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    clockOutSource(src or source, 'logged out')
end)
AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    clockOutSource(src or source, 'logged out')
end)

--- Owner / manager clocks a player employee out.
lib.callback.register('truckco:server:clockOutEmployee', function(src, id)
    local company, err = TC.authorize(src, 'hire')
    if not company then return TC.result(false, err) end
    local emp = MySQL.single.await('SELECT * FROM truckco_employees WHERE id = ? AND company_id = ?', { tonumber(id), company.id })
    if not emp or emp.kind ~= 'player' then return TC.result(false, 'Player employee not found.') end
    if not TC.onDuty[emp.citizenid] then return TC.result(false, ('%s is not clocked in.'):format(emp.name)) end
    TC.onDuty[emp.citizenid] = nil
    local target = TC.sourceByCid(emp.citizenid)
    if target and target ~= src then
        TC.notify(target, ('You were clocked out by %s.'):format(TC.charName(TC.getPlayer(src))), 'inform', company.name)
    end
    return TC.result(true, ('%s clocked out.'):format(emp.name))
end)
