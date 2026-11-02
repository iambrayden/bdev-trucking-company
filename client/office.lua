local office = nil -- { propertyId, interior, shell, floor, props = {}, items = {}, zones = {} }
local KVP_KEY = 'truckco_inside'

local INTERACT = {
    computer = { icon = 'fa-solid fa-tablet-screen-button', label = 'Company tablet', app = 'home' },
    board = { icon = 'fa-solid fa-clipboard-list', label = 'Job bid board', app = 'board' },
    timeclock = { icon = 'fa-solid fa-clock', label = 'Time clock', app = 'driver' },
}

--------------------------------------------------------------------------------
-- Placement helpers
--------------------------------------------------------------------------------
--- Real floor height under the interior origin (origin is player-height, ~1m above floor).
local function findFloor(origin)
    for _ = 1, 20 do
        local found, z = GetGroundZFor_3dCoord(origin.x, origin.y, origin.z + 1.0, false)
        if found and math.abs(z - origin.z) < 4.0 then return z end
        Wait(50)
    end
    return origin.z - 1.0
end

local function modelHash(model)
    return type(model) == 'number' and model or joaat(model)
end

--- Spawn a frozen local prop whose BOTTOM sits at `baseZ`.
local function spawnProp(model, x, y, baseZ, heading)
    local hash = modelHash(model)
    if not IsModelInCdimage(hash) then
        print(('[truckco] furniture model not found: %s'):format(tostring(model)))
        return nil
    end
    lib.requestModel(hash, 5000)
    local min = GetModelDimensions(hash)
    local obj = CreateObjectNoOffset(hash, x, y, baseZ - min.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

--- Height of an object's top surface.
local function topOf(obj)
    local _, max = GetModelDimensions(GetEntityModel(obj))
    return GetEntityCoords(obj).z + max.z
end

local function bottomOf(obj)
    local min = GetModelDimensions(GetEntityModel(obj))
    return GetEntityCoords(obj).z + min.z
end

--------------------------------------------------------------------------------
-- Furniture
--------------------------------------------------------------------------------
local function clearFurniture()
    if not office then return end
    for _, item in ipairs(office.items) do
        if item.target then exports.ox_target:removeLocalEntity(item.obj) end
        if DoesEntityExist(item.obj) then DeleteEntity(item.obj) end
    end
    office.items = {}
    office.byId = {}
end

local function addInteraction(item)
    local def = INTERACT[item.def.interact]
    if not def then return end
    exports.ox_target:addLocalEntity(item.obj, {
        {
            name = 'truckco_' .. item.def.interact,
            icon = def.icon,
            label = def.label,
            distance = 2.0,
            onSelect = function() TCC.openTablet(def.app) end,
        },
    })
    item.target = true
end

local function placeList(list, source)
    local int = office.interior
    for _, f in ipairs(list or {}) do
        local x, y = int.origin.x + f.offset.x, int.origin.y + f.offset.y
        local base = office.floor + f.offset.z
        if f.on and office.byId[f.on] then
            base = topOf(office.byId[f.on].obj) + f.offset.z
        end
        local obj = spawnProp(f.model, x, y, base, f.offset.w)
        if obj then
            local item = { def = f, obj = obj, source = source }
            office.items[#office.items + 1] = item
            if f.id then office.byId[f.id] = item end
            addInteraction(item)
        end
    end
end

local function placeFurniture(upgrades)
    clearFurniture()
    local furniture = office.interior.furniture or {}
    placeList(furniture.base, 'base')
    for key, lvl in pairs(upgrades or {}) do
        local byLevel = furniture[key]
        if type(byLevel) == 'table' and key ~= 'base' then
            for i = 1, lvl do placeList(byLevel[i], ('%s[%d]'):format(key, i)) end
        end
    end
    office.upgrades = upgrades
end

--------------------------------------------------------------------------------
-- Zones (exit door + fallback spots for missing interaction props)
--------------------------------------------------------------------------------
--- Visible exit: a door marker and an [E] prompt, so you can always find the way out.
local function addExitPoint()
    local pos = TCShared.offset(office.interior.origin, office.interior.exit)
    local markerZ = office.floor and (office.floor + 0.05) or (pos.z - 0.95)
    local shown = false
    office.exitPoint = lib.points.new({
        coords = pos,
        distance = 8.0,
        nearby = function(self)
            DrawMarker(1, pos.x, pos.y, markerZ, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.25, 253, 126, 20, 120, false, false, 2, false, nil, nil, false)
            DrawMarker(21, pos.x, pos.y, markerZ + 1.0, 0, 0, 0, 0, 180.0, 0, 0.35, 0.35, 0.35, 253, 126, 20, 200, true, true, 2, false, nil, nil, false)
            if self.currentDistance < 1.5 then
                if not shown then lib.showTextUI('[E] Leave office', { icon = 'door-open' }) shown = true end
                if IsControlJustReleased(0, 38) then
                    lib.hideTextUI()
                    shown = false
                    TCC.exitOffice()
                end
            elseif shown then
                lib.hideTextUI()
                shown = false
            end
        end,
        onExit = function()
            if shown then lib.hideTextUI() shown = false end
        end,
    })
end

local function hasInteract(kind)
    for _, item in ipairs(office.items) do
        if item.def.interact == kind then return true end
    end
    return false
end

local function addZones()
    local int = office.interior
    local function zone(point, options)
        office.zones[#office.zones + 1] = exports.ox_target:addSphereZone({
            coords = TCShared.offset(int.origin, point),
            radius = 1.5,
            debug = Config.Debug,
            options = options,
        })
    end
    zone(int.exit, {
        { name = 'truckco_exit', icon = 'fa-solid fa-door-closed', label = 'Leave office', onSelect = function() TCC.exitOffice() end },
    })
    addExitPoint()
    for kind, def in pairs(INTERACT) do
        if int[kind] and not hasInteract(kind) then
            zone(int[kind], {
                { name = 'truckco_' .. kind, icon = def.icon, label = def.label, onSelect = function() TCC.openTablet(def.app) end },
            })
        end
    end
end

local function removeZones()
    if not office then return end
    for _, z in ipairs(office.zones) do exports.ox_target:removeZone(z) end
    office.zones = {}
    if office.exitPoint then office.exitPoint:remove() office.exitPoint = nil end
    lib.hideTextUI()
end

--------------------------------------------------------------------------------
-- Enter / exit
--------------------------------------------------------------------------------
local function fadeOut()
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(10) end
end

local function moveTo(coords, heading)
    local ped = cache.ped
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, heading or 0.0)
    local timeout = GetGameTimer() + 4000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(10) end
end

local function teleport(coords, heading)
    fadeOut()
    moveTo(coords, heading)
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
    office = { propertyId = propertyId, interior = int, items = {}, byId = {}, zones = {} }

    fadeOut()
    if int.type == 'shell' and int.model then
        lib.requestModel(int.model, 5000)
        office.shell = CreateObjectNoOffset(int.model, int.origin.x, int.origin.y, int.origin.z, false, false, false)
        FreezeEntityPosition(office.shell, true)
    end
    -- go in first so collision is streamed, THEN find the floor and furnish
    moveTo(TCShared.offset(int.origin, int.spawn), int.spawn.w)
    office.floor = findFloor(int.origin)
    placeFurniture(res.data.upgrades)
    addZones()
    SetResourceKvp(KVP_KEY, propertyId)
    Wait(250)
    DoScreenFadeIn(400)
    TCC.notify(('Welcome to %s.'):format(res.data.name), 'inform')
end

local function teardown()
    removeZones()
    clearFurniture()
    if office and office.shell and DoesEntityExist(office.shell) then DeleteEntity(office.shell) end
end

function TCC.exitOffice()
    if not office then return end
    local prop = Config.Properties[office.propertyId]
    TCC.call('exitOffice')
    teardown()
    office = nil
    DeleteResourceKvp(KVP_KEY)
    teleport(prop.entrance.xyz, prop.entrance.w + 180.0)
end

function TCC.isInOffice() return office ~= nil end
function TCC.currentProperty() return office and office.propertyId end

RegisterNetEvent('truckco:client:refreshFurniture', function(upgrades)
    if office then
        placeFurniture(upgrades)
        removeZones()
        addZones()
    end
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
    teardown()
    local prop = Config.Properties[office.propertyId]
    SetEntityCoords(cache.ped, prop.entrance.x, prop.entrance.y, prop.entrance.z, false, false, false, false)
end)

--------------------------------------------------------------------------------
-- Admin furniture placer: /truckco_furnish
--   Aim with the camera, scroll to rotate, arrows for height, ENTER to save,
--   BACKSPACE to cancel. Prints a ready-to-paste config line and copies it.
--------------------------------------------------------------------------------
local placing = false

local function aimPoint()
    local camPos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local dest = camPos + dir * 12.0
    local ray = StartShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 + 16, cache.ped, 4)
    local status, hit, coords
    repeat
        status, hit, coords = GetShapeTestResult(ray)
        if status == 1 then Wait(0) end
    until status ~= 1
    return hit == 1 and coords or dest
end

local function fmt(n) return ('%.2f'):format(n) end

local function itemLine(item)
    local o = office.interior.origin
    local c = GetEntityCoords(item.obj)
    local d = item.def
    local parts = {}
    if d.id then parts[#parts + 1] = ("id = '%s'"):format(d.id) end
    parts[#parts + 1] = ("model = '%s'"):format(type(d.model) == 'string' and d.model or tostring(d.model))
    parts[#parts + 1] = ('offset = vec4(%s, %s, %s, %s)'):format(fmt(c.x - o.x), fmt(c.y - o.y),
        fmt(math.max(0.0, bottomOf(item.obj) - office.floor)), fmt(GetEntityHeading(item.obj)))
    if d.interact then parts[#parts + 1] = ("interact = '%s'"):format(d.interact) end
    return ('{ %s },'):format(table.concat(parts, ', '))
end

local function output(line, label)
    print(('[truckco] %s  ->  %s'):format(label, line))
    lib.setClipboard(line)
    TCC.notify(('Copied %s line to clipboard (also in F8).'):format(label), 'success')
end

local function placeItem(item)
    placing = true
    local obj = item.obj
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityAlpha(obj, 200, false)
    local heading = GetEntityHeading(obj)
    local lift = 0.0
    local min = GetModelDimensions(GetEntityModel(obj))
    lib.showTextUI('[Aim] move  [Scroll] rotate (Shift = fine)  [↑/↓] height  [Enter] save  [Backspace] cancel', { position = 'top-center' })
    local start = GetEntityCoords(obj)
    local startHeading = heading
    CreateThread(function()
        while placing do
            DisableControlAction(0, 14, true); DisableControlAction(0, 15, true)
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            local step = IsControlPressed(0, 21) and 1.0 or 5.0
            if IsDisabledControlJustPressed(0, 15) then heading = (heading + step) % 360 end
            if IsDisabledControlJustPressed(0, 14) then heading = (heading - step) % 360 end
            if IsControlPressed(0, 172) then lift = lift + 0.01 end
            if IsControlPressed(0, 173) then lift = lift - 0.01 end
            local p = aimPoint()
            SetEntityCoordsNoOffset(obj, p.x, p.y, p.z - min.z + lift, false, false, false)
            SetEntityHeading(obj, heading)
            if IsControlJustPressed(0, 191) then
                placing = false
                output(itemLine(item), item.def.id or item.def.model)
            elseif IsControlJustPressed(0, 177) then
                placing = false
                SetEntityCoordsNoOffset(obj, start.x, start.y, start.z, false, false, false)
                SetEntityHeading(obj, startHeading)
            end
            Wait(0)
        end
        ResetEntityAlpha(obj)
        SetEntityCollision(obj, true, true)
        lib.hideTextUI()
    end)
end

local function pointLine(name)
    local o = office.interior.origin
    local c = GetEntityCoords(cache.ped)
    if name == 'spawn' then
        return ('spawn = vec4(%s, %s, %s, %s),'):format(fmt(c.x - o.x), fmt(c.y - o.y), fmt(c.z - o.z), fmt(GetEntityHeading(cache.ped)))
    end
    return ('%s = vec3(%s, %s, %s),'):format(name, fmt(c.x - o.x), fmt(c.y - o.y), fmt(c.z - o.z))
end

RegisterNetEvent('truckco:client:furnish', function()
    if not office then return TCC.notify('Enter an office first.', 'error') end
    if placing then return end
    local options = {}
    for _, item in ipairs(office.items) do
        options[#options + 1] = {
            title = item.def.id or item.def.model,
            description = ('%s • %s%s'):format(item.def.model, item.source, item.def.interact and (' • opens ' .. item.def.interact) or ''),
            icon = item.def.interact and 'hand-pointer' or 'couch',
            onSelect = function() placeItem(item) end,
        }
    end
    for _, p in ipairs({ 'spawn', 'exit', 'timeclock' }) do
        options[#options + 1] = {
            title = ('Set %s at my feet'):format(p),
            description = p == 'timeclock' and 'Fallback spot used when no prop has interact = timeclock' or 'Stand where you want it first',
            icon = 'location-crosshairs',
            onSelect = function() output(pointLine(p), p) end,
        }
    end
    options[#options + 1] = {
        title = 'Print all furniture lines', icon = 'clipboard',
        onSelect = function()
            local lines = {}
            for _, item in ipairs(office.items) do lines[#lines + 1] = itemLine(item) end
            output(table.concat(lines, '\n'), 'all furniture')
        end,
    }
    lib.registerContext({ id = 'truckco_furnish', title = 'Furniture placer (admin)', options = options })
    lib.showContext('truckco_furnish')
end)
