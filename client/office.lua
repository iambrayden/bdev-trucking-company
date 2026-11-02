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
local editing = nil -- { mode, held, hover, moved = {} }

function TCC.isEditing() return editing ~= nil end

--- Was a control pressed this frame? Works even if another resource disabled it.
local function pressed(c)
    return IsControlJustPressed(0, c) or IsDisabledControlJustPressed(0, c)
end
local function held(c)
    return IsControlPressed(0, c) or IsDisabledControlPressed(0, c)
end

local function camDir()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    return GetGameplayCamCoord(), vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
end

--- Where the camera is aiming: surface hit, or the floor plane as a fallback.
local function aimPoint(ignore)
    local camPos, dir = camDir()
    local dest = camPos + dir * 20.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 | 16, ignore or 0, 4)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit == 1 then return pos, normal end
    if dir.z < -0.05 and office.floor then
        local t = (office.floor - camPos.z) / dir.z
        if t > 0 and t < 25 then return camPos + dir * t, vec3(0.0, 0.0, 1.0) end
    end
end

--- Furniture item closest to the aim line (doesn't need the prop to have collision).
local function aimedItem()
    local camPos, dir = camDir()
    local best, bestScore
    for _, item in ipairs(office.items) do
        if DoesEntityExist(item.obj) then
            local min, max = GetModelDimensions(GetEntityModel(item.obj))
            local c = GetEntityCoords(item.obj)
            local center = vec3(c.x, c.y, c.z + (min.z + max.z) / 2)
            local v = center - camPos
            local t = v.x * dir.x + v.y * dir.y + v.z * dir.z
            if t > 0.5 and t < 14.0 then
                local perp = #(v - dir * t)
                local radius = math.max(0.45, math.max(max.x - min.x, max.y - min.y, max.z - min.z) * 0.6)
                local score = perp / radius
                if score < 1.0 and (not bestScore or score < bestScore) then best, bestScore = item, score end
            end
        end
    end
    return best
end

local function label3d(pos, text)
    SetDrawOrigin(pos.x, pos.y, pos.z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function outline(obj, on)
    if obj and DoesEntityExist(obj) then
        SetEntityDrawOutline(obj, on)
        if on then SetEntityDrawOutlineColor(253, 126, 20, 255) end
    end
end

local function itemName(item)
    return item.def.label or item.def.id or item.def.model
end

local function pickUp(item)
    local obj = item.obj
    local h = {
        item = item,
        startPos = GetEntityCoords(obj),
        startHeading = GetEntityHeading(obj),
        rot = 0.0,
        lift = 0.0,
        children = {},
    }
    for _, other in ipairs(office.items) do
        if other ~= item and other.def.on and other.def.on == item.def.id then
            local off = GetOffsetFromEntityGivenWorldCoords(obj, GetEntityCoords(other.obj))
            local rel = GetEntityHeading(other.obj) - GetEntityHeading(obj)
            FreezeEntityPosition(other.obj, false)
            AttachEntityToEntity(other.obj, obj, -1, off.x, off.y, off.z, 0.0, 0.0, rel, false, false, false, false, 2, true)
            h.children[#h.children + 1] = other
        end
    end
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityAlpha(obj, 210, false)
    outline(obj, true)
    editing.held = h
end

local function putDown(restore)
    local h = editing.held
    if not h then return end
    local obj = h.item.obj
    if restore then
        SetEntityCoordsNoOffset(obj, h.startPos.x, h.startPos.y, h.startPos.z, false, false, false)
        SetEntityHeading(obj, h.startHeading)
    else
        editing.moved[h.item.key] = h.item
    end
    for _, child in ipairs(h.children) do
        DetachEntity(child.obj, false, false)
        FreezeEntityPosition(child.obj, true)
        if not restore then editing.moved[child.key] = child end
    end
    SetEntityCollision(obj, true, true)
    ResetEntityAlpha(obj)
    outline(obj, false)
    FreezeEntityPosition(obj, true)
    editing.held = nil
end

local function follow(h)
    local obj = h.item.obj
    local pos, normal = aimPoint(obj)
    if not pos then return end
    local min, max = GetModelDimensions(GetEntityModel(obj))
    local x, y, z, heading
    if normal.z > 0.55 then
        heading = h.startHeading + h.rot
        x, y, z = pos.x, pos.y, pos.z - min.z + h.lift
    else
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
    -- only send what was actually moved; everything else keeps following the default
    local items, n = {}, 0
    for key, item in pairs(editing.moved) do
        if DoesEntityExist(item.obj) then items[key] = itemTransform(item) n = n + 1 end
    end
    stopEditor()
    if n == 0 then return TCC.notify('Nothing was moved.', 'inform') end
    TCC.call(mode == 'default' and 'saveDefaultLayout' or 'saveLayout', items)
end

local HELP = '[E / Click] pick up · put down  ·  [Scroll] rotate  ·  [↑/↓] height  ·  [Backspace] back  ·  [Enter] save'

function TCC.startEditor(mode)
    if not office then return TCC.notify('Go inside your office first.', 'error') end
    if editing then return end
    mode = mode or 'save'
    if mode == 'default' then
        -- show the plain default layout (without this company's own changes) while editing it
        local res = lib.callback.await('truckco:server:getDefaultLayout', false)
        if not res or not res.ok then return TCC.notify(res and res.msg or 'Not allowed.', 'error') end
        placeFurniture(office.upgrades, next(res.data.items or {}) and res.data.items or false)
        if (res.data.overrides or 0) > 0 then
            TCC.notify(('Your own company has moved %d item(s); those keep your company\'s position after saving. Use tablet > Office > Reset to see the default.'):format(res.data.overrides), 'warning')
        end
    end
    editing = { mode = mode, moved = {} }
    lib.showTextUI(HELP, { position = 'top-center', icon = 'couch' })
    TCC.notify(mode == 'default' and 'Editing the DEFAULT layout for every office of this type. Enter saves.'
        or mode == 'config' and 'Furniture editor (config mode): Enter copies config lines.'
        or 'Aim at a piece of furniture and press E (or click) to pick it up. Enter saves.', 'inform')

    CreateThread(function()
        while editing do
            for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 140, 141, 142, 172, 173, 177, 191, 194, 199, 200, 201, 202, 257, 263 }) do
                DisableControlAction(0, c, true)
            end
            local h = editing.held
            if h then
                local step = held(21) and 1.0 or 15.0
                if pressed(15) or pressed(17) then h.rot = h.rot + step end
                if pressed(14) or pressed(16) then h.rot = h.rot - step end
                if held(172) then h.lift = h.lift + 0.01 end
                if held(173) then h.lift = h.lift - 0.01 end
                follow(h)
                local c = GetEntityCoords(h.item.obj)
                label3d(vec3(c.x, c.y, c.z + 1.2), ('~o~%s~s~  [E] put down  [Backspace] cancel'):format(itemName(h.item)))
                if pressed(38) or pressed(24) then
                    putDown(false)
                elseif pressed(177) or pressed(194) or pressed(202) then
                    putDown(true)
                end
            else
                local item = aimedItem()
                if item ~= editing.hover then
                    if editing.hover then outline(editing.hover.obj, false) end
                    if item then outline(item.obj, true) end
                    editing.hover = item
                end
                if item then
                    local c = GetEntityCoords(item.obj)
                    label3d(vec3(c.x, c.y, c.z + 1.2), ('[E] move ~o~%s'):format(itemName(item)))
                end
                if item and (pressed(38) or pressed(24)) then
                    outline(item.obj, false)
                    editing.hover = nil
                    pickUp(item)
                elseif pressed(177) or pressed(194) or pressed(202) then
                    stopEditor()
                    placeFurniture(office.upgrades, office.savedLayout or false)
                    TCC.notify('Changes discarded.', 'inform')
                    break
                end
            end
            if editing and (pressed(191) or pressed(201)) then
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
