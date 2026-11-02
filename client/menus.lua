local money = TCShared.money
local dur = TCShared.duration

local STATUS_LABEL = {
    idle = 'Available', training = 'In training', assigned = 'Assigned (waiting)', on_job = 'On the road',
    available = 'In yard', reserved = 'Reserved', in_use = 'On the road',
    open = 'Open', awarded = 'Needs driver', in_progress = 'In transit', delivered = 'Delivered (truck returning)',
    completed = 'Completed', failed = 'Failed', lost = 'Lost', expired = 'Expired',
}

--------------------------------------------------------------------------------
-- Main management menu
--------------------------------------------------------------------------------
function TCC.openManagement()
    local res = lib.callback.await('truckco:server:getDashboard', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local d = res.data
    local can = function(p) return TCShared.can(d.role, p) end
    local c = d.counts

    local options = {
        {
            title = d.name,
            description = ('%s • %s'):format(d.property, d.role:gsub('^%l', string.upper)),
            icon = 'building', readOnly = true,
            metadata = {
                { label = 'Balance', value = money(d.balance) },
                { label = 'Reputation', value = d.reputation .. '/100' },
                { label = 'Next payroll', value = dur(d.nextPayroll) },
            },
        },
    }
    if d.suspended then
        options[#options + 1] = { title = 'SUSPENDED', description = 'Overdrawn past the limit. Deposit funds to resume bidding.', icon = 'triangle-exclamation', iconColor = 'red', readOnly = true }
    end
    options[#options + 1] = { title = 'Employees', description = ('%d / %d staff (%d drivers, %d dispatchers)'):format(c.employees, d.effects.maxEmployees, c.drivers, c.dispatchers), icon = 'users', arrow = true, onSelect = TCC.openEmployees }
    if can('hire') then
        options[#options + 1] = { title = 'Hire staff', description = 'Recruit NPC applicants or hire a player near you', icon = 'user-plus', arrow = true, onSelect = TCC.openHire }
    end
    options[#options + 1] = { title = 'Fleet', description = ('%d / %d trucks'):format(c.trucks, d.effects.maxTrucks), icon = 'truck', arrow = true, onSelect = TCC.openFleet }
    options[#options + 1] = { title = 'Job bid board', description = ('%d open bids'):format(c.bids), icon = 'clipboard-list', arrow = true, onSelect = TCC.openBoard }
    options[#options + 1] = { title = 'Company loads', description = ('%d active • %d completed'):format(c.active, c.completed), icon = 'route', arrow = true, onSelect = TCC.openCompanyLoads }
    if can('upgrades') then
        options[#options + 1] = { title = 'Office upgrades', description = 'Build out your office shell', icon = 'hammer', arrow = true, onSelect = function() TCC.openUpgrades(d) end }
    end
    if can('settings') then
        options[#options + 1] = { title = 'Dispatch automation', description = 'What your NPC dispatchers are allowed to do', icon = 'robot', arrow = true, onSelect = function() TCC.openSettings(d) end }
    end
    if can('finance') or can('deposit') or d.role == 'owner' then
        options[#options + 1] = { title = 'Finances', description = 'Deposit, withdraw, ledger', icon = 'sack-dollar', arrow = true, onSelect = function() TCC.openFinances(d) end }
    end
    if d.role == 'owner' then
        options[#options + 1] = { title = 'Owner', description = 'Rename, roster, sell company', icon = 'crown', arrow = true, onSelect = function() TCC.openOwner(d) end }
    end

    lib.registerContext({ id = 'truckco_main', title = 'Company Management', options = options })
    lib.showContext('truckco_main')
end

--------------------------------------------------------------------------------
-- Employees
--------------------------------------------------------------------------------
function TCC.openEmployees()
    local res = lib.callback.await('truckco:server:getEmployees', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local options = {}
    for _, e in ipairs(res.data.list) do
        local role = Config.Roles[e.role]
        local status = STATUS_LABEL[e.status] or e.status
        if e.status == 'training' and e.trainingLeft then
            status = ('Training %s (%s)'):format(Config.Certifications[e.training_cert] and Config.Certifications[e.training_cert].label or '', dur(e.trainingLeft))
        end
        local who = e.kind == 'player' and (e.online and (e.onDuty and 'Player • on duty' or 'Player • off duty') or 'Player • offline') or 'NPC'
        options[#options + 1] = {
            title = ('%s — %s'):format(e.name, role and role.label or e.role),
            description = ('%s • %s'):format(who, status),
            icon = role and role.icon or 'user',
            arrow = true,
            metadata = {
                { label = 'Skill', value = e.skill },
                { label = 'Wage', value = money(e.wage) .. ' / shift' },
                { label = 'Loads done', value = e.jobs_done },
                { label = 'Certs', value = TCShared.certList(e.certs) },
            },
            onSelect = function() TCC.openEmployee(e) end,
        }
    end
    if #options == 0 then options[1] = { title = 'No staff yet', description = 'Hire someone from the management laptop.', readOnly = true } end
    lib.registerContext({ id = 'truckco_emps', title = ('Employees (%d/%d)'):format(#res.data.list, res.data.max), menu = 'truckco_main', options = options })
    lib.showContext('truckco_emps')
end

function TCC.openEmployee(e)
    local options = {}
    options[#options + 1] = {
        title = 'Train / certify', description = 'Company pays the course fee', icon = 'graduation-cap', arrow = true,
        disabled = e.status ~= 'idle',
        onSelect = function()
            local courses = {}
            for key, cert in pairs(Config.Certifications) do
                if not e.certs[key] and (not cert.roles or cert.roles[e.role]) then
                    local locked = cert.requires and not e.certs[cert.requires]
                    courses[#courses + 1] = {
                        title = cert.label,
                        description = locked and ('Requires ' .. Config.Certifications[cert.requires].label) or ('%s • %d min'):format(money(cert.cost), cert.minutes),
                        disabled = locked,
                        icon = 'certificate',
                        onSelect = function()
                            if TCC.confirm('Enroll', ('Send **%s** to **%s** for **%s**?'):format(e.name, cert.label, money(cert.cost))) then
                                TCC.call('trainEmployee', e.id, key)
                            end
                        end,
                    }
                end
            end
            if #courses == 0 then courses[1] = { title = 'No courses available', readOnly = true } end
            lib.registerContext({ id = 'truckco_train', title = 'Training: ' .. e.name, menu = 'truckco_emp', options = courses })
            lib.showContext('truckco_train')
        end,
    }
    options[#options + 1] = {
        title = 'Change role', icon = 'id-badge', arrow = true, disabled = e.status ~= 'idle',
        onSelect = function()
            local roles = {}
            for key, r in pairs(Config.Roles) do
                if key ~= e.role and (e.kind == 'player' or r.npc) then
                    roles[#roles + 1] = { title = r.label, icon = r.icon, onSelect = function() TCC.call('setRole', e.id, key) end }
                end
            end
            lib.registerContext({ id = 'truckco_role', title = 'Role: ' .. e.name, menu = 'truckco_emp', options = roles })
            lib.showContext('truckco_role')
        end,
    }
    options[#options + 1] = {
        title = 'Set wage', description = money(e.wage) .. ' per shift', icon = 'money-bill',
        onSelect = function()
            local r = Config.Roles[e.role]
            local input = lib.inputDialog('Wage for ' .. e.name, {
                { type = 'number', label = ('Per shift (%s - %s)'):format(money(r.minWage), money(r.maxWage)), default = e.wage, min = r.minWage, max = r.maxWage, required = true },
            })
            if input then TCC.call('setWage', e.id, input[1]) end
        end,
    }
    options[#options + 1] = {
        title = 'Fire', icon = 'user-xmark', iconColor = 'red',
        onSelect = function()
            if TCC.confirm('Fire employee', ('Let **%s** go?'):format(e.name)) then TCC.call('fireEmployee', e.id) end
        end,
    }
    lib.registerContext({ id = 'truckco_emp', title = e.name, menu = 'truckco_emps', options = options })
    lib.showContext('truckco_emp')
end

--------------------------------------------------------------------------------
-- Hiring
--------------------------------------------------------------------------------
function TCC.openHire()
    lib.registerContext({
        id = 'truckco_hire', title = 'Hire staff', menu = 'truckco_main',
        options = {
            { title = 'Browse NPC applicants', description = 'Recruiter fee applies', icon = 'address-book', arrow = true, onSelect = TCC.openCandidates },
            { title = 'Hire a player', description = 'Offer a job to someone standing near you', icon = 'handshake', arrow = true, onSelect = TCC.hirePlayer },
        },
    })
    lib.showContext('truckco_hire')
end

function TCC.openCandidates()
    local res = lib.callback.await('truckco:server:getCandidates', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local options = {}
    for i, cand in ipairs(res.data.list) do
        local role = Config.Roles[cand.role]
        options[#options + 1] = {
            title = ('%s — %s'):format(cand.name, role.label),
            description = ('Skill %d • %d yrs experience • asks %s/shift'):format(cand.skill, cand.years, money(cand.wage)),
            icon = role.icon,
            metadata = { { label = 'Certs', value = TCShared.certList(cand.certs) } },
            onSelect = function()
                if TCC.confirm('Hire', ('Hire **%s** as %s?\n\nRecruiter fee: **%s**\nWage: **%s** per shift'):format(cand.name, role.label, money(res.data.fee), money(cand.wage))) then
                    TCC.call('hireCandidate', i)
                end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'No applicants right now', description = 'New applicants in ' .. dur(res.data.refreshIn), readOnly = true } end
    lib.registerContext({ id = 'truckco_cands', title = ('Applicants (refresh in %s)'):format(dur(res.data.refreshIn)), menu = 'truckco_hire', options = options })
    lib.showContext('truckco_cands')
end

function TCC.hirePlayer()
    local players = lib.getNearbyPlayers(GetEntityCoords(cache.ped), 8.0, false)
    if #players == 0 then return TCC.notify('Nobody is standing near you.', 'error') end
    local opts = {}
    for _, p in ipairs(players) do
        local sid = GetPlayerServerId(p.id)
        opts[#opts + 1] = { value = sid, label = ('%s (ID %d)'):format(GetPlayerName(p.id), sid) }
    end
    local roles = {}
    for key, r in pairs(Config.Roles) do roles[#roles + 1] = { value = key, label = r.label } end
    local input = lib.inputDialog('Job offer', {
        { type = 'select', label = 'Player', options = opts, required = true },
        { type = 'select', label = 'Role', options = roles, required = true, default = 'driver' },
        { type = 'number', label = 'Wage per shift', required = true, default = Config.Roles.driver.minWage },
    })
    if input then TCC.call('invitePlayer', input[1], input[2], input[3]) end
end

--------------------------------------------------------------------------------
-- Fleet
--------------------------------------------------------------------------------
function TCC.openFleet()
    local res = lib.callback.await('truckco:server:getFleet', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local options = {
        { title = 'Buy a truck', icon = 'cart-shopping', arrow = true, onSelect = TCC.openDealer, disabled = #res.data.list >= res.data.max,
          description = #res.data.list >= res.data.max and 'Yard is full — buy a Truck Yard Expansion' or nil },
    }
    for _, t in ipairs(res.data.list) do
        local def = Config.Trucks[t.model] or { label = t.model, class = '?' }
        local ins = Config.Insurance[t.insurance] or Config.Insurance.none
        options[#options + 1] = {
            title = ('%s [%s]'):format(def.label, t.plate),
            description = ('%s • %s • %s'):format(STATUS_LABEL[t.status] or t.status, def.class == 'semi' and 'Semi' or 'Box truck', ins.label),
            icon = 'truck', arrow = true,
            progress = t.health, colorScheme = t.health > 60 and 'green' or (t.health > Config.Fleet.minDispatchCondition and 'yellow' or 'red'),
            metadata = {
                { label = 'Condition', value = t.health .. '%' },
                { label = 'Mileage', value = ('%.1f km'):format(t.mileage) },
                { label = 'Premium', value = money(t.premium) .. ' / payroll' },
            },
            onSelect = function() TCC.openTruck(t) end,
        }
    end
    lib.registerContext({ id = 'truckco_fleet', title = ('Fleet (%d/%d)'):format(#res.data.list, res.data.max), menu = 'truckco_main', options = options })
    lib.showContext('truckco_fleet')
end

function TCC.openDealer()
    local list = {}
    for model, def in pairs(Config.Trucks) do list[#list + 1] = { model = model, def = def } end
    table.sort(list, function(a, b) return a.def.price < b.def.price end)
    local options = {}
    for _, item in ipairs(list) do
        options[#options + 1] = {
            title = item.def.label,
            description = ('%s • %s'):format(money(item.def.price), item.def.class == 'semi' and 'Semi (pulls trailers, needs CDL loads)' or 'Box truck (local freight)'),
            icon = 'truck-moving',
            image = ('https://docs.fivem.net/vehicles/%s.webp'):format(item.model),
            onSelect = function()
                if TCC.confirm('Buy truck', ('Buy a **%s** for **%s** from the company account?'):format(item.def.label, money(item.def.price))) then
                    TCC.call('buyTruck', item.model)
                end
            end,
        }
    end
    lib.registerContext({ id = 'truckco_dealer', title = 'Truck dealer', menu = 'truckco_fleet', options = options })
    lib.showContext('truckco_dealer')
end

function TCC.openTruck(t)
    local def = Config.Trucks[t.model] or { label = t.model }
    local insOpts = {}
    for key, tier in pairs(Config.Insurance) do
        insOpts[#insOpts + 1] = {
            title = tier.label .. (t.insurance == key and ' (current)' or ''),
            description = ('Premium %s/payroll • covers %d%% • %s deductible'):format(money(t.price * tier.premiumPct), math.floor(tier.coverage * 100), money(tier.deductible)),
            icon = 'shield-halved', disabled = t.insurance == key,
            onSelect = function() TCC.call('setInsurance', t.id, key) end,
        }
    end
    lib.registerContext({ id = 'truckco_ins', title = 'Insurance: ' .. t.plate, menu = 'truckco_truck', options = insOpts })
    lib.registerContext({
        id = 'truckco_truck', title = ('%s [%s]'):format(def.label, t.plate), menu = 'truckco_fleet',
        options = {
            { title = 'Repair', description = t.repairCost > 0 and money(t.repairCost) or 'No repairs needed', icon = 'wrench', disabled = t.repairCost <= 0 or t.status ~= 'available',
              onSelect = function() TCC.call('repairTruck', t.id) end },
            { title = 'Insurance', description = (Config.Insurance[t.insurance] or Config.Insurance.none).label, icon = 'shield-halved', menu = 'truckco_ins' },
            { title = 'Sell', description = money(t.price * Config.Fleet.sellRefund * t.health / 100), icon = 'hand-holding-dollar', iconColor = 'red', disabled = t.status ~= 'available',
              onSelect = function()
                  if TCC.confirm('Sell truck', ('Sell **%s**?'):format(t.plate)) then TCC.call('sellTruck', t.id) end
              end },
        },
    })
    lib.showContext('truckco_truck')
end

--------------------------------------------------------------------------------
-- Bid board
--------------------------------------------------------------------------------
function TCC.openBoard()
    local res = lib.callback.await('truckco:server:getBoard', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local d = res.data
    local options = {}
    if d.suspended then
        options[1] = { title = 'Company suspended', description = 'You cannot bid while overdrawn past the limit.', icon = 'ban', iconColor = 'red', readOnly = true }
    end
    for _, c in ipairs(d.list) do
        local reqs = #c.certs > 0 and TCShared.certList((function() local m = {} for _, k in ipairs(c.certs) do m[k] = true end return m end)()) or 'None'
        options[#options + 1] = {
            title = ('#%d %s → %s'):format(c.id, c.cargoLabel, c.dropoff.label),
            description = ('Up to %s • %.1f km • closes in %s%s'):format(money(c.max_pay), c.distance, dur(c.closesIn),
                c.my_bid and (' • your bid ' .. money(c.my_bid)) or ''),
            icon = c.class == 'semi' and 'trailer' or 'box',
            iconColor = c.my_bid and 'lime' or (not c.eligible and 'gray' or nil),
            disabled = not c.eligible,
            metadata = {
                { label = 'From', value = c.pickup.label },
                { label = 'Vehicle', value = c.class == 'semi' and 'Semi + trailer' or 'Box truck' },
                { label = 'Certs', value = reqs },
                { label = 'Min. reputation', value = c.minRep },
                { label = 'Bids so far', value = c.bid_count },
            },
            onSelect = function() TCC.bidOn(c, d) end,
        }
    end
    if #d.list == 0 then options[#options + 1] = { title = 'No loads posted', description = 'Check back in a minute.', readOnly = true } end
    lib.registerContext({ id = 'truckco_board', title = ('Bid Board — Rep %d'):format(d.reputation), options = options })
    lib.showContext('truckco_board')
end

function TCC.bidOn(c, d)
    local minBid = math.floor(c.max_pay * d.minBidPct)
    local options = {
        {
            title = c.my_bid and 'Change bid' or 'Place bid', icon = 'gavel',
            description = 'Lowest effective bid wins; reputation gives you an edge. Rival companies bid too.',
            onSelect = function()
                local input = lib.inputDialog(('Bid on #%d'):format(c.id), {
                    { type = 'number', label = ('Your price (%s - %s)'):format(money(minBid), money(c.max_pay)), default = c.my_bid or math.floor(c.max_pay * 0.9), min = minBid, max = c.max_pay, required = true },
                })
                if input then TCC.call('placeBid', c.id, input[1]) end
            end,
        },
    }
    if c.my_bid then
        options[#options + 1] = { title = 'Withdraw bid', icon = 'xmark', onSelect = function() TCC.call('withdrawBid', c.id) end }
    end
    lib.registerContext({ id = 'truckco_bid', title = ('#%d %s'):format(c.id, c.cargoLabel), menu = 'truckco_board', options = options })
    lib.showContext('truckco_bid')
end

--------------------------------------------------------------------------------
-- Company loads + assignment
--------------------------------------------------------------------------------
function TCC.openCompanyLoads()
    local res = lib.callback.await('truckco:server:getMyContracts', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local options = {}
    for _, c in ipairs(res.data) do
        local desc = STATUS_LABEL[c.status] or c.status
        if c.status == 'awarded' and c.acceptIn then desc = ('Needs driver — %s left'):format(dur(c.acceptIn)) end
        if c.status == 'in_progress' and c.etaIn then desc = desc .. (' • ETA %s'):format(dur(c.etaIn)) end
        if c.driver_name then desc = desc .. ' • ' .. c.driver_name end
        options[#options + 1] = {
            title = ('#%d %s → %s'):format(c.id, c.cargoLabel, c.dropoff.label),
            description = desc,
            icon = (c.status == 'completed' and 'circle-check') or (c.status == 'failed' and 'circle-xmark') or 'truck-fast',
            iconColor = (c.status == 'awarded' and 'orange') or (c.status == 'failed' and 'red') or (c.status == 'completed' and 'green') or nil,
            metadata = {
                { label = 'Contract', value = money(c.award_amount) },
                { label = 'Distance', value = ('%.1f km'):format(c.distance) },
                { label = 'Truck', value = c.truck_plate or '—' },
                { label = 'Deadline', value = c.deadlineIn and (c.deadlineIn > 0 and dur(c.deadlineIn) or 'LATE') or '—' },
                { label = 'Assigned by', value = c.assigned_by or '—' },
            },
            arrow = c.status == 'awarded' or c.status == 'assigned',
            onSelect = function()
                if c.status == 'awarded' then TCC.openAssign(c)
                elseif c.status == 'assigned' then
                    if TCC.confirm('Unassign', ('Pull load #%d from %s?'):format(c.id, c.driver_name or 'driver')) then TCC.call('unassignContract', c.id) end
                end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'No loads yet', description = 'Win bids on the board to get work.', readOnly = true } end
    lib.registerContext({ id = 'truckco_loads', title = 'Company loads', options = options })
    lib.showContext('truckco_loads')
end

function TCC.openAssign(c)
    local res = lib.callback.await('truckco:server:getAssignOptions', false, c.id)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Unavailable', 'error') end
    local drivers, trucks = res.data.drivers, res.data.trucks
    if #drivers == 0 then return TCC.notify('No idle, qualified driver available (players must be online).', 'error') end
    if #trucks == 0 then return TCC.notify(('No available %s truck in good condition.'):format(c.class == 'semi' and 'semi' or 'box'), 'error') end
    local dOpts, tOpts = {}, {}
    for _, d in ipairs(drivers) do
        dOpts[#dOpts + 1] = { value = d.id, label = ('%s (%s, skill %d%s)'):format(d.name, d.kind == 'npc' and 'NPC' or 'Player', d.skill, d.onDuty and ', on duty' or '') }
    end
    for _, t in ipairs(trucks) do
        tOpts[#tOpts + 1] = { value = t.id, label = ('%s [%s] %d%%'):format((Config.Trucks[t.model] or {}).label or t.model, t.plate, t.health) }
    end
    local input = lib.inputDialog(('Assign load #%d'):format(c.id), {
        { type = 'select', label = 'Driver', options = dOpts, required = true, default = dOpts[1].value },
        { type = 'select', label = 'Truck', options = tOpts, required = true, default = tOpts[1].value },
    })
    if input then TCC.call('assignContract', c.id, input[1], input[2]) end
end

--------------------------------------------------------------------------------
-- Upgrades / settings / finances / owner
--------------------------------------------------------------------------------
function TCC.openUpgrades(d)
    local options = {}
    for key, up in pairs(Config.Upgrades) do
        local lvl = d.upgrades[key] or 0
        local nextLvl = up.levels[lvl + 1]
        options[#options + 1] = {
            title = ('%s (Lv %d/%d)'):format(up.label, lvl, #up.levels),
            description = nextLvl and ('%s — next level %s'):format(up.description, money(nextLvl.price)) or (up.description .. ' — maxed'),
            icon = up.icon, disabled = not nextLvl,
            progress = math.floor(lvl / #up.levels * 100),
            onSelect = function()
                if TCC.confirm('Upgrade', ('Buy **%s** level %d for **%s**?'):format(up.label, lvl + 1, money(nextLvl.price))) then
                    TCC.call('buyUpgrade', key)
                end
            end,
        }
    end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = 'truckco_upgrades', title = 'Office upgrades', menu = 'truckco_main', options = options })
    lib.showContext('truckco_upgrades')
end

function TCC.openSettings(d)
    local s = d.settings
    local input = lib.inputDialog('Dispatch automation', {
        { type = 'checkbox', label = 'Dispatchers bid on loads automatically', checked = s.autoBid },
        { type = 'checkbox', label = 'Dispatchers assign won loads to drivers', checked = s.autoAssign },
        { type = 'checkbox', label = 'Dispatchers may send loads to on-duty player drivers', checked = s.usePlayerDrivers },
    })
    if input then
        TCC.call('saveSettings', { autoBid = input[1], autoAssign = input[2], usePlayerDrivers = input[3] })
    end
end

function TCC.openFinances(d)
    local options = {
        { title = 'Balance', description = money(d.balance), icon = 'wallet', readOnly = true },
    }
    if TCShared.can(d.role, 'deposit') then
        options[#options + 1] = { title = 'Deposit', description = 'From your bank account', icon = 'arrow-down',
            onSelect = function()
                local input = lib.inputDialog('Deposit', { { type = 'number', label = 'Amount', min = 1, required = true } })
                if input then TCC.call('deposit', input[1]) end
            end }
    end
    if d.role == 'owner' then
        options[#options + 1] = { title = 'Withdraw', description = 'To your bank account', icon = 'arrow-up',
            onSelect = function()
                local input = lib.inputDialog('Withdraw', { { type = 'number', label = 'Amount', min = 1, required = true } })
                if input then TCC.call('withdraw', input[1]) end
            end }
    end
    if TCShared.can(d.role, 'finance') then
        options[#options + 1] = { title = 'Ledger', description = 'Last 40 transactions', icon = 'book', arrow = true,
            onSelect = function()
                local res = lib.callback.await('truckco:server:getLedger', false)
                if not res or not res.ok then return end
                local rows = {}
                for _, r in ipairs(res.data) do
                    rows[#rows + 1] = {
                        title = (r.amount >= 0 and '+' or '') .. money(r.amount),
                        description = r.reason .. ' • ' .. (r.ts or ''),
                        icon = r.amount >= 0 and 'circle-plus' or 'circle-minus',
                        iconColor = r.amount >= 0 and 'green' or 'red', readOnly = true,
                    }
                end
                lib.registerContext({ id = 'truckco_ledger', title = 'Ledger', menu = 'truckco_fin', options = rows })
                lib.showContext('truckco_ledger')
            end }
    end
    lib.registerContext({ id = 'truckco_fin', title = 'Finances', menu = 'truckco_main', options = options })
    lib.showContext('truckco_fin')
end

function TCC.openOwner(d)
    lib.registerContext({
        id = 'truckco_owner', title = 'Owner', menu = 'truckco_main',
        options = {
            { title = d.onRoster and 'You are on the roster' or 'Put myself on the roster', description = 'Drive loads yourself as an unpaid driver', icon = 'id-card', disabled = d.onRoster,
              onSelect = function() TCC.call('joinRoster') end },
            { title = 'Rename company', icon = 'pen',
              onSelect = function()
                  local input = lib.inputDialog('Rename', { { type = 'input', label = 'New name', default = d.name, min = 3, max = 40, required = true } })
                  if input then TCC.call('renameCompany', input[1]) end
              end },
            { title = 'Sell company', description = ('Property refund %d%%, trucks at resale value, balance paid out'):format(math.floor(Config.Economy.propertyRefund * 100)), icon = 'skull', iconColor = 'red',
              onSelect = function()
                  if TCC.confirm('Sell company', 'This **deletes** the company, all employees and trucks. Are you sure?') then
                      TCC.call('sellCompany')
                      if TCC.isInOffice() then TCC.exitOffice() end
                  end
              end },
        },
    })
    lib.showContext('truckco_owner')
end

--------------------------------------------------------------------------------
-- Driver / time clock menu (for player employees)
--------------------------------------------------------------------------------
function TCC.openDriverMenu()
    local res = lib.callback.await('truckco:server:getMyAssignments', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'You are not on a roster.', 'error') end
    local d = res.data
    local options = {
        { title = d.onDuty and 'Clock out' or 'Clock in', description = d.onDuty and 'Stop receiving loads from dispatch' or 'Let dispatch send you loads (wages require clocking in)', icon = 'clock',
          onSelect = function() TCC.call('toggleDuty') end },
        { title = 'Collect paycheck', description = money(d.pending), icon = 'money-check-dollar', disabled = d.pending <= 0,
          onSelect = function() TCC.call('collectPay') end },
    }
    for _, c in ipairs(d.list) do
        options[#options + 1] = {
            title = ('#%d %s → %s'):format(c.id, c.cargoLabel, c.dropoff.label),
            description = c.active and 'In progress' or ('Truck %s waiting • %.1f km • due in %s'):format(c.truck_plate or '?', c.distance, dur(c.deadlineIn or 0)),
            icon = 'truck-fast', disabled = c.active or c.status ~= 'assigned',
            onSelect = function() TCC.startRun(c.id) end,
        }
    end
    options[#options + 1] = { title = 'Leave the company', icon = 'door-open', iconColor = 'red',
        onSelect = function()
            if TCC.confirm('Quit', 'Leave the company? Any waiting paycheck is paid out.') then TCC.call('quitCompany') end
        end }
    lib.registerContext({ id = 'truckco_driver', title = 'Time clock', options = options })
    lib.showContext('truckco_driver')
end

RegisterCommand('truckjob', function() TCC.openDriverMenu() end, false)
RegisterCommand('truckboard', function()
    -- dispatchers can work the board remotely
    TCC.openBoard()
end, false)
