--[[
    Bonuses (owner/manager -> player employee) and business loans (owner).
]]

--------------------------------------------------------------------------------
-- Bonuses
--------------------------------------------------------------------------------
lib.callback.register('truckco:server:giveBonus', function(src, employeeId, amount, reason)
    local company, role = TC.authorize(src, 'finance')
    if not company then return TC.result(false, role) end
    amount = math.floor(tonumber(amount) or 0)
    local max = (Config.Bonus and Config.Bonus.max) or 50000
    if amount <= 0 or amount > max then
        return TC.result(false, ('Bonus must be between %s and %s.'):format(TCShared.money(1), TCShared.money(max)))
    end
    reason = type(reason) == 'string' and reason:gsub('[^%w%s%-%.,!\']', ''):sub(1, 60) or ''
    local emp = MySQL.single.await('SELECT * FROM truckco_employees WHERE id = ? AND company_id = ?', { tonumber(employeeId), company.id })
    if not emp then return TC.result(false, 'Employee not found.') end
    if emp.kind ~= 'player' then return TC.result(false, 'Bonuses can only go to player employees.') end
    if emp.citizenid == TC.cid(src) then return TC.result(false, 'You cannot give yourself a bonus.') end
    if not TC.spend(company.id, amount, ('Bonus: %s%s'):format(emp.name, reason ~= '' and (' (' .. reason .. ')') or '')) then
        return TC.result(false, ('Company needs %s.'):format(TCShared.money(amount)))
    end
    local target = TC.sourceByCid(emp.citizenid)
    if target then
        TC.getPlayer(target).Functions.AddMoney('bank', amount, 'truckco-bonus')
        TC.notify(target, ('You received a %s bonus from %s%s!'):format(TCShared.money(amount), company.name,
            reason ~= '' and (': ' .. reason) or ''), 'success', company.name)
    else
        -- offline: waits on their paycheck at the time clock
        MySQL.update.await('UPDATE truckco_employees SET pending_pay = pending_pay + ? WHERE id = ?', { amount, emp.id })
    end
    return TC.result(true, ('%s bonus sent to %s%s.'):format(TCShared.money(amount), emp.name, target and '' or ' (added to their paycheck)'))
end)

--------------------------------------------------------------------------------
-- Loans
--------------------------------------------------------------------------------
local L = Config.Loans

function TC.loanLimit(company)
    return math.floor(L.baseLimit + company.reputation * L.perRep)
end

function TC.activeLoans(companyId)
    return MySQL.query.await('SELECT * FROM truckco_loans WHERE company_id = ? AND balance > 0 ORDER BY id', { companyId }) or {}
end

lib.callback.register('truckco:server:getLoans', function(src)
    local company, err = TC.authorize(src, 'view')
    if not company then return TC.result(false, err) end
    local loans = TC.activeLoans(company.id)
    local owed = 0
    for _, l in ipairs(loans) do owed = owed + l.balance end
    return TC.result(true, nil, {
        loans = loans,
        limit = TC.loanLimit(company),
        available = math.max(0, TC.loanLimit(company) - owed),
        interest = L.interest, installments = L.installments, minReputation = L.minReputation, maxActive = L.maxActive,
        reputation = company.reputation,
    })
end)

lib.callback.register('truckco:server:takeLoan', function(src, amount)
    local company, role = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can take out loans.') end
    amount = math.floor(tonumber(amount) or 0)
    if company.reputation < L.minReputation then
        return TC.result(false, ('The bank wants at least %d reputation.'):format(L.minReputation))
    end
    local loans = TC.activeLoans(company.id)
    if #loans >= L.maxActive then return TC.result(false, 'Repay your current loan first.') end
    local owed = 0
    for _, l in ipairs(loans) do owed = owed + l.balance end
    local available = TC.loanLimit(company) - owed
    if amount < 1000 or amount > available then
        return TC.result(false, ('You can borrow between %s and %s.'):format(TCShared.money(1000), TCShared.money(math.max(0, available))))
    end
    local total = math.floor(amount * (1 + L.interest))
    local installment = math.ceil(total / L.installments)
    MySQL.insert.await('INSERT INTO truckco_loans (company_id, principal, balance, installment) VALUES (?, ?, ?, ?)',
        { company.id, amount, total, installment })
    TC.addFunds(company.id, amount, ('Business loan (repay %s)'):format(TCShared.money(total)))
    return TC.result(true, ('Loan approved: %s deposited. You repay %s over %d payrolls (%s each).')
        :format(TCShared.money(amount), TCShared.money(total), L.installments, TCShared.money(installment)))
end)

lib.callback.register('truckco:server:repayLoan', function(src, loanId, amount)
    local company, role = TC.authorize(src)
    if not company or role ~= 'owner' then return TC.result(false, 'Only the owner can repay loans.') end
    local loan = MySQL.single.await('SELECT * FROM truckco_loans WHERE id = ? AND company_id = ? AND balance > 0', { tonumber(loanId), company.id })
    if not loan then return TC.result(false, 'Loan not found.') end
    amount = math.floor(tonumber(amount) or loan.balance)
    amount = math.min(amount, loan.balance)
    if amount <= 0 then return TC.result(false, 'Invalid amount.') end
    if not TC.spend(company.id, amount, ('Loan repayment #%d'):format(loan.id)) then
        return TC.result(false, ('Company needs %s.'):format(TCShared.money(amount)))
    end
    MySQL.update.await('UPDATE truckco_loans SET balance = balance - ? WHERE id = ?', { amount, loan.id })
    local left = loan.balance - amount
    return TC.result(true, left > 0 and ('Paid %s. %s left.'):format(TCShared.money(amount), TCShared.money(left)) or 'Loan paid off!')
end)

--- Called by payroll: take this cycle's installments (forced; can push into overdraft).
function TC.loanPayroll(company)
    local total = 0
    for _, l in ipairs(TC.activeLoans(company.id)) do
        local pay = math.min(l.installment, l.balance)
        TC.spend(company.id, pay, ('Loan installment #%d'):format(l.id), true, true)
        MySQL.update.await('UPDATE truckco_loans SET balance = balance - ? WHERE id = ?', { pay, l.id })
        total = total + pay
    end
    return total
end
