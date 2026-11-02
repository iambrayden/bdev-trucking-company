local office = nil -- { propertyId, interior, shell, props = {}, zones = {} }
local KVP_KEY = 'truckco_inside'

local function spawnProp(model, coords, heading)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        if Config.Debug then print('[truckco] missing model ' .. tostring(model)) end
        return nil
    end
    lib.requestModel(hash, 5000)
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

local function clearFurniture()
    if not office then return end
    for _, obj in ipairs(office.props) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    office.props = {}
end

local function placeFurniture(upgrades)
    clearFurniture()
    local int = office.interior
    local furniture = int.furniture or {}
    local function place(list)
        for _, f in ipairs(list or {}) do
            local pos = TCShared.offset(int.origin, f.offset)
            local obj = spawnProp(f.model, pos, f.offset.w)
            if obj then office.props[#office.props + 1] = obj end
        end
    end
    place(furniture.base)
    for key, lvl in pairs(upgrades or {}) do
        local byLevel = furniture[key]
        if type(byLevel) == 'table' and key ~= 'base' then
            for i = 1, lvl do place(byLevel[i]) end
        end
    end
end

local function addZones()
    local int = office.interior
    local function zone(point, options)
        office.zones[#office.zones + 1] = exports.ox_target:addSphereZone({
            coords = TCShared.offset(int.origin, point),
            radius = 1.2,
            debug = Config.Debug,
            options = options,
        })
    end
    zone(int.exit, {
        { name = 'truckco_exit', icon = 'fa-solid fa-door-closed', label = 'Leave office', onSelect = function() TCC.exitOffice() end },
    })
    zone(int.computer, {
        { name = 'truckco_computer', icon = 'fa-solid fa-laptop', label = 'Company management', onSelect = function() TCC.openManagement() end },
    })
    zone(int.board, {
        { name = 'truckco_board', icon = 'fa-solid fa-clipboard-list', label = 'Job bid board', onSelect = function() TCC.openBoard() end },
        { name = 'truckco_loads', icon = 'fa-solid fa-route', label = 'Company loads', onSelect = function() TCC.openCompanyLoads() end },
    })
    zone(int.timeclock, {
        { name = 'truckco_clock', icon = 'fa-solid fa-clock', label = 'Time clock', onSelect = function() TCC.openDriverMenu() end },
    })
end

local function removeZones()
    if not office then return end
    for _, z in ipairs(office.zones) do exports.ox_target:removeZone(z) end
    office.zones = {}
end

local function teleport(coords, heading)
    local ped = cache.ped
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(10) end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, heading or 0.0)
    local timeout = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(10) end
    Wait(250)
    DoScreenFadeIn(400)
end

function TCC.enterOffice(propertyId)
    if office then return end
    local res = TCC.call('enterOffice', propertyId)
    if not res.ok then return end
    local int = Config.Interiors[res.data.interior]
    if not int then
        TCC.call('exitOffice')
        return TCC.notify('Interior "' .. tostring(res.data.interior) .. '" is not configured.', 'error')
    end
    office = { propertyId = propertyId, interior = int, props = {}, zones = {} }

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(10) end
    if int.type == 'shell' and int.model then
        office.shell = spawnProp(int.model, int.origin, 0.0)
    end
    placeFurniture(res.data.upgrades)
    addZones()
    SetResourceKvp(KVP_KEY, propertyId)
    local spawn = TCShared.offset(int.origin, int.spawn)
    teleport(spawn, int.spawn.w)
    TCC.notify(('Welcome to %s.'):format(res.data.name), 'inform')
end

function TCC.exitOffice()
    if not office then return end
    local prop = Config.Properties[office.propertyId]
    TCC.call('exitOffice')
    removeZones()
    clearFurniture()
    if office.shell and DoesEntityExist(office.shell) then DeleteEntity(office.shell) end
    office = nil
    DeleteResourceKvp(KVP_KEY)
    teleport(prop.entrance.xyz, prop.entrance.w + 180.0)
end

function TCC.isInOffice() return office ~= nil end

RegisterNetEvent('truckco:client:refreshFurniture', function(upgrades)
    if office then placeFurniture(upgrades) end
end)

-- If a player logged out inside an office, put them back at the front door.
TCC.onLoaded = function()
    local last = GetResourceKvpString(KVP_KEY)
    if not last or last == '' or office then return end
    DeleteResourceKvp(KVP_KEY)
    local prop = Config.Properties[last]
    local int = prop and Config.Interiors[prop.interior]
    if not int then return end
    Wait(1500)
    if #(GetEntityCoords(cache.ped) - int.origin) < 60.0 then
        teleport(prop.entrance.xyz, prop.entrance.w + 180.0)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not office then return end
    removeZones()
    clearFurniture()
    if office.shell and DoesEntityExist(office.shell) then DeleteEntity(office.shell) end
    local prop = Config.Properties[office.propertyId]
    SetEntityCoords(cache.ped, prop.entrance.x, prop.entrance.y, prop.entrance.z, false, false, false, false)
end)
