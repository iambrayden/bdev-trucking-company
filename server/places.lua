--[[
    In-game placement (no config editing needed).

    Positions resolve in this order:  company choice  >  admin default (DB)  >  config.lua
      * inside the office : spawn (arrival), exit (door), timeclock      -> offsets from the interior origin
      * outside the depot : entrance (admin only), truckSpawn, truckReturn -> world coords
      * furniture         : per item key, same precedence

    Admin defaults live in truckco_settings:
      'interior:<name>'  = { items = { [key] = {x,y,z,h} }, points = { exit = {x,y,z}, ... } }
      'property:<id>'    = { entrance = {x,y,z,w}, truckSpawn = {...}, truckReturn = {...} }
    Company choices live in truckco_companies.layout:
      { interior = <name>, items = {...}, points = {...}, outside = { truckSpawn, truckReturn } }
]]

TC.settings = {}

function TC.loadSettings()
    for _, row in ipairs(MySQL.query.await('SELECT k, v FROM truckco_settings') or {}) do
        local ok, val = pcall(json.decode, row.v)
        if ok then TC.settings[row.k] = val end
    end
end

function TC.setSetting(k, v)
    TC.settings[k] = v
    MySQL.query.await('INSERT INTO truckco_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', { k, json.encode(v) })
end

local INSIDE = { spawn = true, exit = true, timeclock = true }
local OUTSIDE = { entrance = true, truckSpawn = true, truckReturn = true }
local LABEL = {
    spawn = 'Arrival point', exit = 'Exit door', timeclock = 'Time clock',
    entrance = 'Depot entrance', truckSpawn = 'Truck pickup spot', truckReturn = 'Truck return spot',
}

local function asVec(t, kind)
    if type(t) ~= 'table' or not tonumber(t.x) then return nil end
    if kind == 'truckReturn' or kind == 'exit' or kind == 'timeclock' then return vec3(t.x, t.y, t.z) end
    return vec4(t.x, t.y, t.z, t.w or 0.0)
end

--- Effective world position of a depot point.
function TC.propPoint(propertyId, kind, company)
    if company and kind ~= 'entrance' then
        local o = type(company.layout) == 'table' and company.layout.outside
        local v = o and asVec(o[kind], kind)
        if v then return v end
    end
    local g = TC.settings['property:' .. propertyId]
    local v = g and asVec(g[kind], kind)
    if v then return v end
    return Config.Properties[propertyId][kind]
end

--- Effective entrance for every property (sent to clients for blips/targets).
function TC.entrances()
    local out = {}
    for id in pairs(Config.Properties) do
        local e = TC.propPoint(id, 'entrance')
        out[id] = { x = e.x, y = e.y, z = e.z, w = e.w }
    end
    return out
end

--- Furniture overrides + inside points for an office, merged admin default <- company.
function TC.officeLayout(company)
    local prop = Config.Properties[company.property]
    local g = TC.settings['interior:' .. prop.interior] or {}
    local items, points = {}, {}
    for k, v in pairs(g.items or {}) do items[k] = v end
    for k, v in pairs(g.points or {}) do points[k] = v end
    local l = company.layout
    if type(l) == 'table' and l.interior == prop.interior then
        for k, v in pairs(l.items or {}) do items[k] = v end
        for k, v in pairs(l.points or {}) do points[k] = v end
    end
    return { items = items, points = points }
end

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

function TC.isAdmin(src)
    return IsPlayerAceAllowed(src, 'command.truckco_furnish')
end

function TC.refreshOffice(company)
    local data = TC.officeLayout(company)
    for s, propId in pairs(TC.inside) do
        if propId == company.property then
            TriggerClientEvent('truckco:client:refreshFurniture', s, company.upgrades, data)
        end
    end
end

local function saveCompanyLayout(company)
    MySQL.update.await('UPDATE truckco_companies SET layout = ? WHERE id = ?', { json.encode(company.layout), company.id })
end

local function companyLayoutTable(company)
    local prop = Config.Properties[company.property]
    local l = company.layout
    if type(l) ~= 'table' or l.interior ~= prop.interior then
        -- keep outside points even if the interior changed
        l = { interior = prop.interior, items = {}, points = {}, outside = type(l) == 'table' and l.outside or {} }
    end
    l.items, l.points, l.outside = l.items or {}, l.points or {}, l.outside or {}
    company.layout = l
    return l
end
TC.companyLayoutTable = companyLayoutTable

--- Nearest property to a player (for admin outside edits).
local function nearestProperty(pos, maxDist)
    local best, bestD
    for id in pairs(Config.Properties) do
        local d = TC.distance(pos, TC.propPoint(id, 'entrance'))
        if d < (maxDist or 80.0) and (not bestD or d < bestD) then best, bestD = id, d end
    end
    return best
end

--[[
    setPlace(kind, scope)
      scope 'company' : owner/manager, saved for their company
      scope 'default' : admin, saved as the default for everyone
    The position is taken from where the player is standing (or their vehicle).
]]
lib.callback.register('truckco:server:setPlace', function(src, kind, scope)
    if not (INSIDE[kind] or OUTSIDE[kind]) then return TC.result(false, 'Unknown spot.') end
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0 and kind == 'truckSpawn') and veh or ped
    local pos, heading = GetEntityCoords(ent), GetEntityHeading(ent)

    if scope == 'default' then
        if not TC.isAdmin(src) then return TC.result(false, 'Admins only.') end
        if INSIDE[kind] then
            local propId = TC.inside[src]
            if not propId then return TC.result(false, 'Stand inside an office.') end
            local interior = Config.Properties[propId].interior
            local int = Config.Interiors[interior]
            local key = 'interior:' .. interior
            local g = TC.settings[key] or {}
            g.points = g.points or {}
            g.points[kind] = { x = round(pos.x - int.origin.x), y = round(pos.y - int.origin.y), z = round(pos.z - int.origin.z), w = round(heading) }
            TC.setSetting(key, g)
            for _, c in ipairs(TC.getAllCompanies()) do
                if Config.Properties[c.property].interior == interior then TC.refreshOffice(c) end
            end
            return TC.result(true, ('Default %s saved for every %s.'):format(LABEL[kind]:lower(), int.label))
        end
        if GetPlayerRoutingBucket(src) ~= 0 then return TC.result(false, 'Step outside first.') end
        local propId = nearestProperty(pos, 80.0)
        if not propId then return TC.result(false, 'Stand within 80m of a depot.') end
        local key = 'property:' .. propId
        local g = TC.settings[key] or {}
        g[kind] = { x = round(pos.x), y = round(pos.y), z = round(pos.z), w = round(heading) }
        TC.setSetting(key, g)
        if kind == 'entrance' then TC.broadcastProperties() end
        return TC.result(true, ('%s for %s saved.'):format(LABEL[kind], Config.Properties[propId].label))
    end

    -- company scope
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    if kind == 'entrance' then return TC.result(false, 'Only admins can move a depot entrance.') end
    local l = companyLayoutTable(company)
    if INSIDE[kind] then
        if TC.inside[src] ~= company.property then return TC.result(false, 'Stand inside your office.') end
        local int = Config.Interiors[Config.Properties[company.property].interior]
        local off = vec3(pos.x - int.origin.x, pos.y - int.origin.y, pos.z - int.origin.z)
        if #off > 60.0 then return TC.result(false, 'That spot is outside the office.') end
        l.points[kind] = { x = round(off.x), y = round(off.y), z = round(off.z), w = round(heading) }
        saveCompanyLayout(company)
        TC.refreshOffice(company)
    else
        if GetPlayerRoutingBucket(src) ~= 0 then return TC.result(false, 'Step outside first.') end
        if TC.distance(pos, TC.propPoint(company.property, 'entrance')) > 80.0 then
            return TC.result(false, 'Stand within 80m of your depot.')
        end
        l.outside[kind] = { x = round(pos.x), y = round(pos.y), z = round(pos.z), w = round(heading) }
        saveCompanyLayout(company)
    end
    return TC.result(true, ('%s saved.'):format(LABEL[kind]))
end)

--- Admin: save the default furniture layout for an interior (all companies without their own).
lib.callback.register('truckco:server:saveDefaultLayout', function(src, items)
    if not TC.isAdmin(src) then return TC.result(false, 'Admins only.') end
    local propId = TC.inside[src]
    if not propId then return TC.result(false, 'Stand inside an office.') end
    local clean = TC.cleanLayoutItems(items)
    if not clean then return TC.result(false, 'Invalid layout.') end
    local interior = Config.Properties[propId].interior
    local key = 'interior:' .. interior
    local g = TC.settings[key] or {}
    g.items = clean
    TC.setSetting(key, g)
    for _, c in ipairs(TC.getAllCompanies()) do
        if Config.Properties[c.property].interior == interior then TC.refreshOffice(c) end
    end
    return TC.result(true, 'Default furniture layout saved for every office of this type.')
end)

--- Owner/manager: forget the company's own furniture + spots (back to defaults).
lib.callback.register('truckco:server:resetLayout', function(src)
    local company, err = TC.authorize(src, 'upgrades')
    if not company then return TC.result(false, err) end
    local l = companyLayoutTable(company)
    l.items, l.points = {}, {}
    saveCompanyLayout(company)
    TC.refreshOffice(company)
    return TC.result(true, 'Office reset to the default layout.')
end)

lib.callback.register('truckco:server:isAdmin', function(src)
    return TC.isAdmin(src)
end)
