TCShared = {}

-- Owner can do everything. Other roles get these permissions.
TCShared.Perms = {
    manager    = { view = true, hire = true, fire = true, train = true, fleet = true, bid = true, assign = true, finance = true, deposit = true, upgrades = true, settings = true },
    dispatcher = { view = true, bid = true, assign = true },
    driver     = { view = true },
}

function TCShared.can(role, perm)
    if role == 'owner' then return true end
    local p = TCShared.Perms[role]
    return p ~= nil and p[perm] == true
end

function TCShared.money(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return (n < 0 and '-' or '') .. Config.Currency .. out
end

function TCShared.duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then
        return ('%dh %02dm'):format(sec // 3600, (sec % 3600) // 60)
    elseif sec >= 60 then
        return ('%dm %02ds'):format(sec // 60, sec % 60)
    end
    return ('%ds'):format(sec)
end

---@param certs table<string, boolean>
---@param required string[]
function TCShared.hasCerts(certs, required)
    for _, c in ipairs(required or {}) do
        if not certs or not certs[c] then return false, c end
    end
    return true
end

function TCShared.certList(certs)
    local out = {}
    for k in pairs(certs or {}) do
        out[#out + 1] = Config.Certifications[k] and Config.Certifications[k].label or k
    end
    table.sort(out)
    return #out > 0 and table.concat(out, ', ') or 'None'
end

function TCShared.offset(origin, off)
    return vec3(origin.x + off.x, origin.y + off.y, origin.z + off.z)
end

function TCShared.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end
