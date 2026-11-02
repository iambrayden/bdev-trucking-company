--[[
    Exterior company signs. Each sign is the company name rendered by a DUI
    (html/sign.html) and drawn as a textured panel on two posts. Textures are
    only created for signs near the player and released when they move away.
    If textured drawing isn't available, the name is drawn as 3D text instead.
]]
local cfg = Config.Signs
local signs = {}      -- list of { companyId, name, items = { {x,y,z,h,style} } }
local duis = {}       -- [key] = { dui, txd, used }
local txdSeq = 0
local editor = nil
local testSigns = {}  -- /truckco_signtest
local DrawPolyTex = DrawTexturedPoly or DrawSpritePoly -- renamed native (0x29280002282F1928)
local texturedOk = DrawPolyTex ~= nil
local warned = false

local function warnOnce(msg)
    if warned then return end
    warned = true
    print('^3[truckco] signs: ' .. msg .. '^0')
end

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
        if not dui then return nil end
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

local function text3d(x, y, z, str, scale)
    SetDrawOrigin(x, y, z, 0)
    SetTextScale(0.0, scale or 0.5)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 240)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

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

local function panelFallback(lx, ly, qx, qy, z0, z1, alpha)
    -- plain dark panel (both windings) when textured drawing isn't available
    DrawPoly(lx, ly, z0, qx, qy, z0, qx, qy, z1, 22, 24, 29, alpha)
    DrawPoly(lx, ly, z0, qx, qy, z1, lx, ly, z1, 22, 24, 29, alpha)
    DrawPoly(lx, ly, z0, qx, qy, z1, qx, qy, z0, 22, 24, 29, alpha)
    DrawPoly(lx, ly, z0, lx, ly, z1, qx, qy, z1, 22, 24, 29, alpha)
end

local function drawSign(name, it, alpha)
    local h = math.rad(it.h)
    local rx, ry = math.cos(h), math.sin(h)        -- right
    local fx, fy = -math.sin(h), math.cos(h)       -- forward (sign faces this way)
    local hw, ht = cfg.size.width / 2, cfg.size.height
    local z0 = it.z + cfg.size.postHeight + (it.lift or 0.0) -- raising a sign stretches its posts
    local z1 = z0 + ht
    post(it.x - rx * (hw - 0.4), it.y - ry * (hw - 0.4), it.z, z1 - 0.05)
    post(it.x + rx * (hw - 0.4), it.y + ry * (hw - 0.4), it.z, z1 - 0.05)
    local txd = texturedOk and texture(name, it.style or cfg.styles[1].id) or nil
    for side = 1, 2 do
        -- front face slightly in front, back face slightly behind with mirrored U so text reads from both sides
        local o = side == 1 and 0.03 or -0.03
        local cx, cy = it.x + fx * o, it.y + fy * o
        local lx, ly = cx - rx * hw, cy - ry * hw
        local qx, qy = cx + rx * hw, cy + ry * hw
        if side == 2 then lx, ly, qx, qy = qx, qy, lx, ly end
        if txd then
            DrawPolyTex(lx, ly, z0, qx, qy, z0, qx, qy, z1, 255, 255, 255, alpha, txd, 'sign', 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0)
            DrawPolyTex(lx, ly, z0, qx, qy, z1, lx, ly, z1, 255, 255, 255, alpha, txd, 'sign', 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0)
            DrawPolyTex(lx, ly, z0, qx, qy, z1, qx, qy, z0, 255, 255, 255, alpha, txd, 'sign', 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
            DrawPolyTex(lx, ly, z0, lx, ly, z1, qx, qy, z1, 255, 255, 255, alpha, txd, 'sign', 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
        else
            panelFallback(lx, ly, qx, qy, z0, z1, alpha)
        end
    end
    if not txd then
        text3d(it.x, it.y, (z0 + z1) / 2, name, 0.6)
    end
end

local function safeDraw(name, it, alpha)
    local ok, err = pcall(drawSign, name, it, alpha)
    if not ok then
        -- textured path failed on this client: switch to the fallback for good
        if texturedOk then
            texturedOk = false
            warnOnce('textured drawing failed (' .. tostring(err) .. '), using plain panels with 3D text')
        end
        pcall(drawSign, name, it, alpha)
    end
end

-- render loop (errors can't kill it)
CreateThread(function()
    if not texturedOk then warnOnce('DrawTexturedPoly not available on this client, using plain panels with 3D text') end
    while true do
        local sleep = 500
        local ok, err = pcall(function()
            if TCC.isInOffice() then return end
            local pos = GetEntityCoords(cache.ped)
            local dd = cfg.drawDistance
            for _, s in ipairs(signs) do
                if not (editor and editor.companyId == s.companyId) then
                    for _, it in ipairs(s.items or {}) do
                        if #(pos - vec3(it.x, it.y, it.z)) < dd then
                            safeDraw(s.name, it, 255)
                            sleep = 0
                        end
                    end
                end
            end
            if editor then
                for i, it in ipairs(editor.items) do
                    if i ~= editor.heldIndex then safeDraw(editor.name, it, 255) end
                end
                if editor.preview then safeDraw(editor.name, editor.preview, 150) end
                sleep = 0
            end
            local now = GetGameTimer()
            for i = #testSigns, 1, -1 do
                local t = testSigns[i]
                if now > t.untilT then table.remove(testSigns, i) else safeDraw(t.name, t, 255) sleep = 0 end
            end
        end)
        if not ok then print('[truckco] sign render error: ' .. tostring(err)) Wait(1000) end
        Wait(sleep)
    end
end)

RegisterNetEvent('truckco:client:signs', function(list) signs = list or {} end)

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    local ok, list = pcall(lib.callback.await, 'truckco:server:getSigns', false)
    signs = ok and list or {}
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(duis) do DestroyDui(d.dui) end
end)

-- quick render check: draws a test sign in front of you for 30 seconds
RegisterCommand('truckco_signtest', function()
    local ped = cache.ped
    local c = GetOffsetFromEntityInWorldCoords(ped, 0.0, 6.0, 0.0)
    local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
    testSigns[#testSigns + 1] = {
        name = 'Sign Test Co.', x = c.x, y = c.y, z = found and gz or (c.z - 1.0),
        h = (GetEntityHeading(ped) + 180.0) % 360, style = cfg.styles[1].id, untilT = GetGameTimer() + 30000,
    }
    local msg = ('Test sign placed 6m ahead for 30s. Textured drawing: %s.'):format(texturedOk and 'available' or 'NOT available (fallback panel)')
    print('[truckco] ' .. msg)
    TCC.notify(msg, 'inform')
end, false)

--------------------------------------------------------------------------------
-- Sign editor (owners / managers, outside the depot)
--   Aim: a preview sign follows your aim.
--   E / Click : place a new sign there, or pick up the sign you're aiming at
--   While moving one: E / Click put it down · X delete · Backspace put back
--   Scroll rotate · Q style · Backspace (nothing held) leave · Enter save
--------------------------------------------------------------------------------
local function pressed(c) return IsControlJustPressed(0, c) or IsDisabledControlJustPressed(0, c) end
local function held(c) return IsControlPressed(0, c) or IsDisabledControlPressed(0, c) end

local function groundAim(fallbackZ)
    local camPos = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local dest = camPos + dir * 60.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 | 16, cache.ped, 4)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit == 1 and normal.z > 0.5 then return pos end
    if hit == 1 then
        -- hit a wall/object: drop to the ground below that point
        local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
        if found then return vec3(pos.x, pos.y, gz) end
    end
    if dir.z < -0.02 and fallbackZ then
        local t = (fallbackZ - camPos.z) / dir.z
        if t > 0 and t < 80 then return camPos + dir * t end
    end
end

local function styleIndex(id)
    for i, st in ipairs(cfg.styles) do if st.id == id then return i end end
    return 1
end

local HELP = '[E / Click] place · pick up  ·  [Scroll] rotate  ·  [↑/↓] height  ·  [Q] style  ·  [X] delete  ·  [Backspace] back  ·  [Enter] save'
local MIN_LIFT, MAX_LIFT = -1.0, 12.0

function TCC.startSignEditor()
    if editor then return end
    if TCC.isInOffice() then return TCC.notify('Go outside to place signs.', 'error') end
    local res = lib.callback.await('truckco:server:getSignEditor', false)
    if not res or not res.ok then return TCC.notify(res and res.msg or 'Not allowed.', 'error') end
    local e = res.data.entrance
    local center = e and vec3(e.x, e.y, e.z) or TCC.entrance(res.data.property).xyz
    if #(GetEntityCoords(cache.ped) - center) > cfg.radius then
        return TCC.notify(('Go to your depot to place signs (within %dm of the entrance).'):format(math.floor(cfg.radius)), 'error')
    end
    local items = {}
    for i, it in ipairs(res.data.items or {}) do items[i] = { x = it.x, y = it.y, z = it.z, h = it.h, style = it.style, lift = it.lift or 0.0 } end
    editor = {
        companyId = res.data.companyId, name = res.data.name, items = items, center = center,
        rot = (GetGameplayCamRot(2).z + 180.0) % 360, style = cfg.styles[1].id, lift = 0.0,
    }
    lib.showTextUI(HELP, { position = 'top-center', icon = 'sign-hanging' })
    TCC.notify(('Aim where the sign should stand and press E. Up to %d signs within %dm of the entrance, %s each. Enter saves.')
        :format(cfg.max, math.floor(cfg.radius), TCShared.money(cfg.price)), 'inform')

    CreateThread(function()
        while editor do
            for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 27, 37, 38, 44, 73, 140, 141, 142, 172, 173, 177, 191, 194, 199, 200, 201, 202, 257, 263 }) do
                DisableControlAction(0, c, true)
            end
            local aim = groundAim(editor.center.z - 1.0)
            local inRange = aim and #(vec3(aim.x, aim.y, editor.center.z) - editor.center) <= cfg.radius
            local step = held(21) and 1.0 or 15.0
            if pressed(15) or pressed(17) then editor.rot = (editor.rot + step) % 360 end
            if pressed(14) or pressed(16) then editor.rot = (editor.rot - step) % 360 end
            -- height: arrow up / down (Shift = fine)
            local liftStep = held(21) and 0.01 or 0.05
            if held(172) then editor.lift = math.min(MAX_LIFT, editor.lift + liftStep) end
            if held(173) then editor.lift = math.max(MIN_LIFT, editor.lift - liftStep) end
            if pressed(44) then
                editor.style = cfg.styles[styleIndex(editor.style) % #cfg.styles + 1].id
                TCC.notify('Style: ' .. cfg.styles[styleIndex(editor.style)].label, 'inform')
            end

            -- which existing sign is under the aim (when not moving one)
            local target
            if aim and not editor.heldIndex then
                local bestD
                for i, it in ipairs(editor.items) do
                    local d = #(vec3(aim.x, aim.y, aim.z) - vec3(it.x, it.y, it.z))
                    if d < 3.0 and (not bestD or d < bestD) then target, bestD = i, d end
                end
            end

            -- preview: the held sign, or a ghost for a new one
            if aim and inRange and (editor.heldIndex or (not target and #editor.items < cfg.max)) then
                editor.preview = { x = aim.x, y = aim.y, z = aim.z, h = editor.rot, style = editor.style, lift = editor.lift }
            else
                editor.preview = nil
            end

            if aim then
                local label
                if not inRange then label = '~r~Too far from the depot'
                elseif editor.heldIndex then label = ('[E] put down  ~c~[↑/↓] height %+.1fm  [X] delete  [Backspace] put back'):format(editor.lift)
                elseif target then label = '[E] move this sign'
                elseif #editor.items >= cfg.max then label = ('~r~Limit reached (%d). Aim at a sign to move it.'):format(cfg.max)
                else label = ('[E] place sign  ~c~(%d/%d)  [↑/↓] height %+.1fm'):format(#editor.items, cfg.max, editor.lift) end
                local lz = editor.preview and (editor.preview.z + cfg.size.postHeight + (editor.preview.lift or 0) + cfg.size.height + 0.4) or (aim.z + 1.0)
                text3d(aim.x, aim.y, lz, label, 0.35)
            end
            if aim and not inRange then
                DrawMarker(1, editor.center.x, editor.center.y, editor.center.z - 1.0, 0, 0, 0, 0, 0, 0, cfg.radius * 2, cfg.radius * 2, 0.6, 253, 126, 20, 40, false, false, 2, false, nil, nil, false)
            end

            if pressed(38) or pressed(24) then
                if editor.heldIndex then
                    if editor.preview then
                        editor.items[editor.heldIndex] = editor.preview
                        editor.heldIndex, editor.backup = nil, nil
                    end
                elseif target then
                    local it = editor.items[target]
                    editor.backup = { x = it.x, y = it.y, z = it.z, h = it.h, style = it.style, lift = it.lift or 0.0 }
                    editor.heldIndex, editor.rot, editor.style, editor.lift = target, it.h, it.style or editor.style, it.lift or 0.0
                elseif editor.preview then
                    editor.items[#editor.items + 1] = editor.preview
                    TCC.notify(('Sign placed (%d/%d). Press Enter to save.'):format(#editor.items, cfg.max), 'success')
                end
            elseif pressed(73) and editor.heldIndex then
                table.remove(editor.items, editor.heldIndex)
                editor.heldIndex, editor.backup = nil, nil
                TCC.notify('Sign removed.', 'inform')
            elseif pressed(177) or pressed(194) or pressed(202) then
                if editor.heldIndex then
                    editor.items[editor.heldIndex] = editor.backup
                    editor.heldIndex, editor.backup = nil, nil
                else
                    editor = nil
                    lib.hideTextUI()
                    TCC.notify('Sign changes discarded.', 'inform')
                    break
                end
            elseif pressed(191) or pressed(201) then
                if editor.heldIndex and editor.backup then editor.items[editor.heldIndex] = editor.backup end
                local list = editor.items
                editor = nil
                lib.hideTextUI()
                TCC.call('saveSigns', list)
                break
            end
            Wait(0)
        end
    end)
end
