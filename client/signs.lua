--[[
    Exterior company signs. Each sign is the company name rendered by a DUI
    (html/sign.html) and drawn as a textured panel on two posts. Textures are
    only created for signs near the player and released when they move away.
]]
local cfg = Config.Signs
local signs = {}      -- list of { companyId, name, items = { {x,y,z,h,style} } }
local duis = {}       -- [key] = { dui, txd, used }
local txdSeq = 0
local editor = nil
local DrawPolyTex = DrawTexturedPoly or DrawSpritePoly -- renamed native (0x29280002282F1928)

local function urlencode(str)
    return (str:gsub('[^%w%-_%.~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

local function texture(name, style)
    local key = name .. '|' .. style
    local d = duis[key]
    if not d then
        txdSeq = txdSeq + 1
        local url = ('nui://%s/html/sign.html?name=%s&style=%s'):format(GetCurrentResourceName(), urlencode(name), style)
        local dui = CreateDui(url, cfg.resolution[1], cfg.resolution[2])
        local txd = 'truckco_sign_' .. txdSeq
        CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(txd), 'sign', GetDuiHandle(dui))
        d = { dui = dui, txd = txd }
        duis[key] = d
    end
    d.used = GetGameTimer()
    return d.txd
end

-- release textures nobody has looked at for a while
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for key, d in pairs(duis) do
            if now - d.used > 20000 then
                DestroyDui(d.dui)
                duis[key] = nil
            end
        end
    end
end)

local function post(x, y, z0, z1)
    local t = 0.07
    for _, d in ipairs({ { t, 0 }, { 0, t } }) do
        local ax, ay, bx, by = x - d[1], y - d[2], x + d[1], y + d[2]
        DrawPoly(ax, ay, z0, bx, by, z0, bx, by, z1, 55, 58, 64, 255)
        DrawPoly(ax, ay, z0, bx, by, z1, ax, ay, z1, 55, 58, 64, 255)
        DrawPoly(ax, ay, z0, bx, by, z1, bx, by, z0, 55, 58, 64, 255)
        DrawPoly(ax, ay, z0, ax, ay, z1, bx, by, z1, 55, 58, 64, 255)
    end
end

local function drawSign(name, it, alpha)
    local h = math.rad(it.h)
    local rx, ry = math.cos(h), math.sin(h)        -- right
    local fx, fy = -math.sin(h), math.cos(h)       -- forward (sign faces this way)
    local hw, ht = cfg.size.width / 2, cfg.size.height
    local z0 = it.z + cfg.size.postHeight
    local z1 = z0 + ht
    -- posts
    post(it.x - rx * (hw - 0.4), it.y - ry * (hw - 0.4), it.z, z1 - 0.05)
    post(it.x + rx * (hw - 0.4), it.y + ry * (hw - 0.4), it.z, z1 - 0.05)
    local txd = texture(name, it.style or cfg.styles[1].id)
    for side = 1, 2 do
        -- front face slightly in front, back face slightly behind with mirrored U so text reads from both sides
        local o = side == 1 and 0.03 or -0.03
        local cx, cy = it.x + fx * o, it.y + fy * o
        local lx, ly = cx - rx * hw, cy - ry * hw
        local qx, qy = cx + rx * hw, cy + ry * hw
        local uL, uR = 0.0, 1.0
        if side == 2 then lx, ly, qx, qy = qx, qy, lx, ly end
        DrawPolyTex(lx, ly, z0, qx, qy, z0, qx, qy, z1, 255, 255, 255, alpha, txd, 'sign', uL, 1.0, 1.0, uR, 1.0, 1.0, uR, 0.0, 1.0)
        DrawPolyTex(lx, ly, z0, qx, qy, z1, lx, ly, z1, 255, 255, 255, alpha, txd, 'sign', uL, 1.0, 1.0, uR, 0.0, 1.0, uL, 0.0, 1.0)
        DrawPolyTex(lx, ly, z0, qx, qy, z1, qx, qy, z0, 255, 255, 255, alpha, txd, 'sign', uL, 1.0, 1.0, uR, 0.0, 1.0, uR, 1.0, 1.0)
        DrawPolyTex(lx, ly, z0, lx, ly, z1, qx, qy, z1, 255, 255, 255, alpha, txd, 'sign', uL, 1.0, 1.0, uL, 0.0, 1.0, uR, 0.0, 1.0)
    end
end

-- render loop
CreateThread(function()
    while true do
        local sleep = 500
        if not TCC.isInOffice() then
            local pos = GetEntityCoords(cache.ped)
            local dd = cfg.drawDistance
            for _, s in ipairs(signs) do
                if not (editor and editor.companyId == s.companyId) then
                    for _, it in ipairs(s.items) do
                        if #(pos - vec3(it.x, it.y, it.z)) < dd then
                            drawSign(s.name, it, 255)
                            sleep = 0
                        end
                    end
                end
            end
            if editor then
                for i, it in ipairs(editor.items) do
                    if i ~= editor.heldIndex then drawSign(editor.name, it, 255) end
                end
                if editor.held then drawSign(editor.name, editor.held, 170) end
                sleep = 0
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('truckco:client:signs', function(list) signs = list or {} end)

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    signs = lib.callback.await('truckco:server:getSigns', false) or {}
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(duis) do DestroyDui(d.dui) end
end)

--------------------------------------------------------------------------------
-- Sign editor (owners / managers, outside the depot)
--   E pick up / place · Scroll rotate · Q style · X delete · Backspace back · Enter save
--------------------------------------------------------------------------------
local function groundAim()
    local camPos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local dest = camPos + dir * 40.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 | 16, cache.ped, 4)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit == 1 and normal.z > 0.55 then return pos end
end

local function styleIndex(id)
    for i, st in ipairs(cfg.styles) do if st.id == id then return i end end
    return 1
end

local HELP = '[E] pick up / place  ·  [Scroll] rotate  ·  [Q] style  ·  [X] delete  ·  [Backspace] back  ·  [Enter] save'

function TCC.startSignEditor()
    if editor then return end
    if TCC.isInOffice() then return TCC.notify('Go outside to place signs.', 'error') end
    local res = lib.callback.await('truckco:server:getSignEditor', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Not allowed.', 'error') end
    local e = res.data.entrance
    local center = e and vec3(e.x, e.y, e.z) or TCC.entrance(res.data.property).xyz
    if #(GetEntityCoords(cache.ped) - center) > cfg.radius then
        return TCC.notify('Go to your depot to place signs.', 'error')
    end
    local items = {}
    for i, it in ipairs(res.data.items or {}) do items[i] = { x = it.x, y = it.y, z = it.z, h = it.h, style = it.style } end
    editor = { companyId = res.data.companyId, name = res.data.name, items = items, original = #items, center = center }
    lib.showTextUI(HELP, { position = 'top-center', icon = 'sign-hanging' })
    TCC.notify(('Place up to %d signs within %dm of the entrance. New signs cost %s each.'):format(cfg.max, math.floor(cfg.radius), TCShared.money(cfg.price)), 'inform')

    CreateThread(function()
        while editor do
            for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 37, 44, 73, 140, 141, 142, 257, 263 }) do DisableControlAction(0, c, true) end
            local aim = groundAim()
            local inRange = aim and #(aim - editor.center) <= cfg.radius
            if editor.held and aim and inRange then
                editor.held.x, editor.held.y, editor.held.z = aim.x, aim.y, aim.z
            end
            if aim and not inRange then
                DrawMarker(1, editor.center.x, editor.center.y, editor.center.z - 1.0, 0, 0, 0, 0, 0, 0, cfg.radius * 2, cfg.radius * 2, 0.6, 253, 126, 20, 40, false, false, 2, false, nil, nil, false)
            end
            local h = editor.held
            if h then
                local step = IsControlPressed(0, 21) and 1.0 or 15.0
                if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then h.h = (h.h + step) % 360 end
                if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then h.h = (h.h - step) % 360 end
                if IsDisabledControlJustPressed(0, 44) then
                    h.style = cfg.styles[styleIndex(h.style) % #cfg.styles + 1].id
                    TCC.notify('Style: ' .. cfg.styles[styleIndex(h.style)].label, 'inform')
                end
                if IsControlJustPressed(0, 38) and inRange then
                    if editor.heldIndex then editor.items[editor.heldIndex] = h else editor.items[#editor.items + 1] = h end
                    editor.held, editor.heldIndex, editor.backup = nil, nil, nil
                elseif IsDisabledControlJustPressed(0, 73) then
                    if editor.heldIndex then table.remove(editor.items, editor.heldIndex) end
                    editor.held, editor.heldIndex, editor.backup = nil, nil, nil
                    TCC.notify('Sign removed.', 'inform')
                elseif IsControlJustPressed(0, 177) then
                    if editor.heldIndex then editor.items[editor.heldIndex] = editor.backup end
                    editor.held, editor.heldIndex, editor.backup = nil, nil, nil
                end
            else
                if IsControlJustPressed(0, 38) and aim then
                    -- pick up the sign you're looking at, or start a new one
                    local best, bestD
                    for i, it in ipairs(editor.items) do
                        local d = #(aim - vec3(it.x, it.y, it.z))
                        if d < 3.0 and (not bestD or d < bestD) then best, bestD = i, d end
                    end
                    if best then
                        local it = editor.items[best]
                        editor.backup = { x = it.x, y = it.y, z = it.z, h = it.h, style = it.style }
                        editor.held, editor.heldIndex = { x = it.x, y = it.y, z = it.z, h = it.h, style = it.style }, best
                    elseif #editor.items < cfg.max then
                        local camH = GetGameplayCamRot(2).z
                        editor.held = { x = aim.x, y = aim.y, z = aim.z, h = (camH + 180.0) % 360, style = cfg.styles[1].id }
                    else
                        TCC.notify(('You already have %d signs. Pick one up to move it, or X to delete it.'):format(cfg.max), 'error')
                    end
                elseif IsControlJustPressed(0, 177) then
                    editor = nil
                    lib.hideTextUI()
                    TCC.notify('Sign changes discarded.', 'inform')
                    break
                elseif IsControlJustPressed(0, 191) then
                    local list = editor.items
                    editor = nil
                    lib.hideTextUI()
                    TCC.call('saveSigns', list)
                    break
                end
            end
            Wait(0)
        end
    end)
end
