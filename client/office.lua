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
    local saved = office.layout or {}
    for i, f in ipairs(list or {}) do
        local key = f.id or ('%s#%d'):format(source, i)
        local x, y = int.origin.x + f.offset.x, int.origin.y + f.offset.y
        local base, heading = office.floor + f.offset.z, f.offset.w
        local s = saved[key]
        if type(s) == 'table' and tonumber(s.x) then
            -- company's saved layout wins over the config default
            x, y = int.origin.x + s.x, int.origin.y + s.y
            base, heading = office.floor + (s.z or 0.0), s.h or heading
        elseif f.on and office.byId[f.on] then
            base = topOf(office.byId[f.on].obj) + f.offset.z
        end
        local obj = spawnProp(f.model, x, y, base, heading)
        if obj then
            local item = { def = f, obj = obj, source = source, key = key }
            office.items[#office.items + 1] = item
            if f.id then office.byId[f.id] = item end
            addInteraction(item)
        end
    end
end

local function placeFurniture(upgrades, layout)
    if layout ~= nil then office.layout = layout or nil end
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
--- Inside spot (spawn / exit / timeclock) as an offset from the origin:
--- company choice > admin default > config (merged server-side into office.points).
local function point(kind)
    local p = office.points and office.points[kind]
    if type(p) == 'table' and tonumber(p.x) then return vec4(p.x, p.y, p.z, p.w or 0.0) end
    local d = office.interior[kind]
    if d then return vec4(d.x, d.y, d.z, d.w or 0.0) end
end

--- Visible exit: a door marker and an [E] prompt, so you can always find the way out.
local function addExitPoint()
    local pos = TCShared.offset(office.interior.origin, point('exit'))
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
    zone(point('exit'), {
        { name = 'truckco_exit', icon = 'fa-solid fa-door-closed', label = 'Leave office', onSelect = function() TCC.exitOffice() end },
    })
    addExitPoint()
    for kind, def in pairs(INTERACT) do
        if point(kind) and not hasInteract(kind) then
            zone(point(kind), {
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
    local layout = res.data.layout or {}
    office.points = layout.points or {}
    local spawn = point('spawn')
    moveTo(TCShared.offset(int.origin, spawn), spawn.w)
    office.floor = findFloor(int.origin)
    office.layout = layout.items
    office.savedLayout = layout.items
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
    local door = TCC.entrance(office.propertyId)
    TCC.call('exitOffice')
    teardown()
    office = nil
    DeleteResourceKvp(KVP_KEY)
    teleport(door.xyz, door.w + 180.0)
end

function TCC.isInOffice() return office ~= nil end
function TCC.currentProperty() return office and office.propertyId end

RegisterNetEvent('truckco:client:refreshFurniture', function(upgrades, data)
    if office and not TCC.isEditing() then
        data = data or {}
        office.points = data.points or {}
        office.savedLayout = data.items
        placeFurniture(upgrades, data.items or false)
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
        local door = TCC.entrance(last)
        teleport(door.xyz, door.w + 180.0)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not office then return end
    teardown()
    local prop = Config.Properties[office.propertyId]
    local e = TCC.entrance(office.propertyId)
    SetEntityCoords(cache.ped, e.x, e.y, e.z, false, false, false, false)
end)

--------------------------------------------------------------------------------
-- Furniture editor
--   'save'   : owner / manager arranges the office; saved for the company
--              (tablet -> Office -> Arrange furniture)
--   'config' : admin; prints ready-to-paste config lines instead (/truckco_furnish)
--
--   Look at a prop and press E to pick it up. It follows your aim: it sits on
--   floors and desks, and mounts flush on walls. Props stacked on it (the
--   laptop on the desk) move along with it.
--     Scroll       rotate (hold Shift for fine)
--     Arrow up/dn  raise / lower
--     E            put down
--     Backspace    put back (while holding) / leave without saving
--     R            reset everything to the default layout
--     Enter        save and finish
--------------------------------------------------------------------------------
local editing = nil -- { mode, held, hover }

function TCC.isEditing() return editing ~= nil end

local function camRay(ignore)
    local camPos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local dest = camPos + dir * 15.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 | 16, ignore or 0, 4)
    local _, hit, pos, normal, ent = GetShapeTestResult(ray)
    return hit == 1, pos, normal, ent
end

local function itemFromEntity(ent)
    if not ent or ent == 0 then return nil end
    for _, item in ipairs(office.items) do
        if item.obj == ent then return item end
    end
end

local function outline(obj, on)
    if obj and DoesEntityExist(obj) then
        SetEntityDrawOutline(obj, on)
        if on then SetEntityDrawOutlineColor(253, 126, 20, 255) end
    end
end

local function pickUp(item)
    local obj = item.obj
    local held = {
        item = item,
        startPos = GetEntityCoords(obj),
        startHeading = GetEntityHeading(obj),
        rot = 0.0,
        lift = 0.0,
        children = {},
    }
    -- anything stacked on this prop rides along
    for _, other in ipairs(office.items) do
        if other ~= item and other.def.on and other.def.on == item.def.id then
            local off = GetOffsetFromEntityGivenWorldCoords(obj, GetEntityCoords(other.obj))
            local rel = GetEntityHeading(other.obj) - GetEntityHeading(obj)
            FreezeEntityPosition(other.obj, false)
            AttachEntityToEntity(other.obj, obj, -1, off.x, off.y, off.z, 0.0, 0.0, rel, false, false, false, false, 2, true)
            held.children[#held.children + 1] = other
        end
    end
    SetEntityCollision(obj, false, false)
    SetEntityAlpha(obj, 210, false)
    outline(obj, true)
    editing.held = held
end

local function putDown(restore)
    local h = editing.held
    if not h then return end
    local obj = h.item.obj
    if restore then
        SetEntityCoordsNoOffset(obj, h.startPos.x, h.startPos.y, h.startPos.z, false, false, false)
        SetEntityHeading(obj, h.startHeading)
    end
    for _, child in ipairs(h.children) do
        DetachEntity(child.obj, false, false)
        FreezeEntityPosition(child.obj, true)
    end
    SetEntityCollision(obj, true, true)
    ResetEntityAlpha(obj)
    outline(obj, false)
    FreezeEntityPosition(obj, true)
    editing.held = nil
end

local function follow(h)
    local obj = h.item.obj
    local hit, pos, normal = camRay(obj)
    if not hit then return end
    local min, max = GetModelDimensions(GetEntityModel(obj))
    local x, y, z, heading
    if normal.z > 0.55 then
        -- floor / desk top: bottom of the model sits on the surface
        heading = h.startHeading + h.rot
        x, y, z = pos.x, pos.y, pos.z - min.z + h.lift
    else
        -- wall: face away from the wall, back flush against it
        heading = GetHeadingFromVector_2d(normal.x, normal.y) + h.rot
        local c, s = math.cos(math.rad(h.rot)), math.sin(math.rad(h.rot))
        local depth
        if math.abs(c) >= math.abs(s) then depth = c > 0 and -min.y or max.y
        else depth = s > 0 and -min.x or max.x end
        x, y = pos.x + normal.x * (depth + 0.01), pos.y + normal.y * (depth + 0.01)
        z = pos.z + h.lift
    end
    SetEntityCoordsNoOffset(obj, x, y, z, false, false, false)
    SetEntityHeading(obj, heading % 360.0)
end

local function fmt(n) return ('%.2f'):format(n) end

local function itemTransform(item)
    local o = office.interior.origin
    local c = GetEntityCoords(item.obj)
    return {
        x = tonumber(fmt(c.x - o.x)), y = tonumber(fmt(c.y - o.y)),
        z = tonumber(fmt(math.max(0.0, bottomOf(item.obj) - office.floor))),
        h = tonumber(fmt(GetEntityHeading(item.obj))),
    }
end

local function itemLine(item)
    local t = itemTransform(item)
    local d = item.def
    local parts = {}
    if d.id then parts[#parts + 1] = ("id = '%s'"):format(d.id) end
    parts[#parts + 1] = ("model = '%s'"):format(type(d.model) == 'string' and d.model or tostring(d.model))
    parts[#parts + 1] = ('offset = vec4(%s, %s, %s, %s)'):format(fmt(t.x), fmt(t.y), fmt(t.z), fmt(t.h))
    if d.interact then parts[#parts + 1] = ("interact = '%s'"):format(d.interact) end
    return ('{ %s },'):format(table.concat(parts, ', '))
end

local function output(text, label)
    print(('[truckco] %s:\n%s'):format(label, text))
    lib.setClipboard(text)
    TCC.notify(('Copied %s to clipboard (also printed in F8).'):format(label), 'success')
end

local function stopEditor()
    if not editing then return end
    if editing.held then putDown(true) end
    if editing.hover then outline(editing.hover.obj, false) end
    editing = nil
    lib.hideTextUI()
end

local function saveEditor()
    local mode = editing.mode
    if editing.held then putDown(false) end
    if mode == 'config' then
        local lines = {}
        for _, item in ipairs(office.items) do lines[#lines + 1] = itemLine(item) end
        output(table.concat(lines, '\n'), 'furniture config lines')
        stopEditor()
        return
    end
    local items = {}
    for _, item in ipairs(office.items) do items[item.key] = itemTransform(item) end
    stopEditor()
    if mode == 'default' then
        TCC.call('saveDefaultLayout', items)
    else
        TCC.call('saveLayout', items)
    end
end

local HELP = '[E] pick up / put down  ·  [Scroll] rotate  ·  [↑/↓] height  ·  [R] reset  ·  [Backspace] back  ·  [Enter] save'

function TCC.startEditor(mode)
    if not office then return TCC.notify('Go inside your office first.', 'error') end
    if editing then return end
    editing = { mode = mode or 'save' }
    lib.showTextUI(HELP, { position = 'top-center', icon = 'couch' })
    TCC.notify(mode == 'default' and 'Arranging the DEFAULT layout for every office of this type. Enter saves.'
        or mode == 'config' and 'Furniture editor (config mode): Enter copies config lines.'
        or 'Arrange your office. Press Enter to save.', 'inform')
    CreateThread(function()
        while editing do
            for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
            local h = editing.held
            if h then
                local step = IsControlPressed(0, 21) and 1.0 or 15.0
                if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then h.rot = h.rot + step end
                if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then h.rot = h.rot - step end
                if IsControlPressed(0, 172) then h.lift = h.lift + 0.01 end
                if IsControlPressed(0, 173) then h.lift = h.lift - 0.01 end
                follow(h)
                if IsControlJustPressed(0, 38) then putDown(false)
                elseif IsControlJustPressed(0, 177) then putDown(true) end
            else
                local _, _, _, ent = camRay(0)
                local item = itemFromEntity(ent)
                if item ~= editing.hover then
                    if editing.hover then outline(editing.hover.obj, false) end
                    if item then outline(item.obj, true) end
                    editing.hover = item
                end
                if item and IsControlJustPressed(0, 38) then
                    editing.hover = nil
                    pickUp(item)
                elseif IsControlJustPressed(0, 177) then
                    -- leave without saving: rebuild from the last saved layout
                    stopEditor()
                    placeFurniture(office.upgrades, office.savedLayout or false)
                    TCC.notify('Changes discarded.', 'inform')
                    break
                elseif IsDisabledControlJustPressed(0, 45) then
                    if editing.hover then outline(editing.hover.obj, false) editing.hover = nil end
                    placeFurniture(office.upgrades, false)
                    TCC.notify('Reset to the default layout. Press Enter to save it.', 'inform')
                end
            end
            if editing and IsControlJustPressed(0, 191) then
                saveEditor()
                break
            end
            Wait(0)
        end
    end)
end

--------------------------------------------------------------------------------
-- Admin setup menu (/truckco_furnish). Everything saves to the database;
-- "copy config lines" is only there if you want to bake it into config.lua.
--------------------------------------------------------------------------------
local function setPlace(kind, scope)
    return TCC.call('setPlace', kind, scope)
end

RegisterNetEvent('truckco:client:furnish', function()
    if editing then return end
    local options
    if office then
        options = {
            { title = 'Arrange default furniture', description = 'Saved for every company using this office (unless they arranged their own)', icon = 'couch',
              onSelect = function() TCC.startEditor('default') end },
            { title = 'Set default exit door here', description = 'Stand on the door', icon = 'door-open', onSelect = function() setPlace('exit', 'default') end },
            { title = 'Set default arrival point here', description = 'Where people appear when they walk in (uses your heading)', icon = 'person-walking-arrow-right', onSelect = function() setPlace('spawn', 'default') end },
            { title = 'Set default time clock here', description = 'Used when no prop is the time clock', icon = 'clock', onSelect = function() setPlace('timeclock', 'default') end },
            { title = 'Copy furniture as config lines', description = 'Optional: bake the current layout into config.lua', icon = 'clipboard',
              onSelect = function()
                  local lines = {}
                  for _, item in ipairs(office.items) do lines[#lines + 1] = itemLine(item) end
                  output(table.concat(lines, '\n'), 'furniture config lines')
              end },
        }
    else
        options = {
            { title = 'Move this depot entrance here', description = 'Nearest depot within 80m; blip and door move for everyone', icon = 'door-closed', onSelect = function() setPlace('entrance', 'default') end },
            { title = 'Set default truck pickup here', description = 'Where company trucks are pulled out (sit in a vehicle to use its position)', icon = 'truck', onSelect = function() setPlace('truckSpawn', 'default') end },
            { title = 'Set default truck return here', description = 'Where drivers drop trucks back off', icon = 'square-parking', onSelect = function() setPlace('truckReturn', 'default') end },
        }
    end
    lib.registerContext({ id = 'truckco_furnish', title = office and 'Office setup (admin)' or 'Depot setup (admin)', options = options })
    lib.showContext('truckco_furnish')
end)
