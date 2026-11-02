local run = nil -- active player run state
local blip = nil
local textShown = nil

local function setBlip(coords, label, sprite, color)
    if blip then RemoveBlip(blip) end
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipColour(blip, color or 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

local function text(msg)
    if msg == textShown then return end
    if msg then lib.showTextUI(msg, { position = 'left-center' }) else lib.hideTextUI() end
    textShown = msg
end

local function cleanup()
    if blip then RemoveBlip(blip) blip = nil end
    text(nil)
    run = nil
end

local function waitForEntity(netId, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while GetGameTimer() < deadline do
        if NetworkDoesNetworkIdExist(netId) then
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
        end
        Wait(100)
    end
end

local function marker(c, r, g, b)
    DrawMarker(1, c.x, c.y, c.z - 1.0, 0, 0, 0, 0, 0, 0, 6.0, 6.0, 1.5, r, g, b, 90, false, false, 2, false, nil, nil, false)
end

local function stageBlip()
    if run.stage == 'pickup' then
        setBlip(run.pickup, ('Pickup: %s'):format(run.cargo), 478, 5)
        TCC.notify(('Head to %s to collect %s.'):format(run.pickup.label, run.cargo), 'inform')
    elseif run.stage == 'dropoff' then
        setBlip(run.dropoff, ('Deliver: %s'):format(run.dropoff.label), 479, 2)
    elseif run.stage == 'return' then
        setBlip(run.returnPoint, 'Return truck', 477, 3)
    end
end

local function trailerAttached(truck, trailer)
    if not trailer or not DoesEntityExist(trailer) then return false end
    local has, tr = GetVehicleTrailerVehicle(truck)
    return has and tr == trailer
end

local function loop()
    CreateThread(function()
        local busy = false
        while run do
            local sleep = 500
            local ped = cache.ped
            local pos = GetEntityCoords(ped)
            local truck = run.truckNet and NetworkDoesNetworkIdExist(run.truckNet) and NetworkGetEntityFromNetworkId(run.truckNet) or 0
            local inTruck = truck ~= 0 and GetVehiclePedIsIn(ped, false) == truck
            local prompt

            if run.stage == 'pickup' then
                local dist = #(pos - vec3(run.pickup.x, run.pickup.y, run.pickup.z))
                if run.class == 'semi' then
                    if dist < 180.0 and not run.trailerNet and not busy then
                        busy = true
                        local res = lib.callback.await('truckco:server:spawnTrailer', false, run.contractId)
                        if res and res.ok then
                            run.trailerNet = res.data.trailerNet
                            TCC.notify('Back up to the trailer and hook it up.', 'inform')
                        end
                        busy = false
                    end
                    local trailer = run.trailerNet and NetworkDoesNetworkIdExist(run.trailerNet) and NetworkGetEntityFromNetworkId(run.trailerNet) or nil
                    if dist < 60.0 then
                        sleep = 0
                        if trailer then
                            local tc = GetEntityCoords(trailer)
                            DrawMarker(0, tc.x, tc.y, tc.z + 3.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, 255, 200, 0, 180, true, true, 2, false, nil, nil, false)
                        end
                        if inTruck and trailerAttached(truck, trailer) and not busy then
                            busy = true
                            local res = TCC.call('loaded', run.contractId)
                            if res.ok then run.stage = 'dropoff' stageBlip() end
                            busy = false
                        end
                    end
                else
                    if dist < 40.0 then
                        sleep = 0
                        marker(run.pickup, 255, 200, 0)
                        if dist < 6.0 and inTruck then
                            prompt = '[E] Load cargo'
                            if IsControlJustReleased(0, 38) and not busy then
                                busy = true
                                text(nil)
                                if lib.progressCircle({ duration = 8000, label = 'Loading cargo...', position = 'bottom', canCancel = true,
                                    disable = { move = true, car = true, combat = true } }) then
                                    local res = TCC.call('loaded', run.contractId)
                                    if res.ok then run.stage = 'dropoff' stageBlip() end
                                end
                                busy = false
                            end
                        end
                    end
                end

            elseif run.stage == 'dropoff' then
                local d = vec3(run.dropoff.x, run.dropoff.y, run.dropoff.z)
                local dist = #(pos - d)
                if dist < 60.0 then
                    sleep = 0
                    marker(d, 0, 200, 80)
                    if dist < 10.0 then
                        local trailer = run.trailerNet and NetworkDoesNetworkIdExist(run.trailerNet) and NetworkGetEntityFromNetworkId(run.trailerNet)
                        if run.class == 'semi' and not (inTruck and trailerAttached(truck, trailer)) then
                            prompt = 'Bring the trailer into the marker'
                        elseif not inTruck then
                            prompt = 'Get back in your truck'
                        elseif GetEntitySpeed(truck) > 1.0 then
                            prompt = 'Come to a stop'
                        else
                            prompt = '[E] Deliver load'
                            if IsControlJustReleased(0, 38) and not busy then
                                busy = true
                                text(nil)
                                if lib.progressCircle({ duration = 10000, label = 'Unloading...', position = 'bottom', canCancel = true,
                                    disable = { move = true, car = true, combat = true } }) then
                                    if run.class == 'semi' then DetachVehicleFromTrailer(truck) end
                                    local res = TCC.call('deliver', run.contractId)
                                    if res.ok then
                                        run.stage = 'return'
                                        run.trailerNet = nil
                                        stageBlip()
                                    end
                                end
                                busy = false
                            end
                        end
                    end
                end

            elseif run.stage == 'return' then
                local r = run.returnPoint
                local dist = #(pos - vec3(r.x, r.y, r.z))
                if dist < 50.0 then
                    sleep = 0
                    marker(r, 80, 160, 255)
                    if dist < 8.0 then
                        if not inTruck then
                            prompt = 'Bring the company truck here'
                        else
                            prompt = '[E] Park truck'
                            if IsControlJustReleased(0, 38) and not busy then
                                busy = true
                                text(nil)
                                TaskLeaveVehicle(ped, truck, 0)
                                Wait(1500)
                                local res = TCC.call('returnTruck', run.contractId)
                                if res.ok then cleanup() end
                                busy = false
                            end
                        end
                    end
                end
            end

            if run then text(prompt) end
            Wait(sleep)
        end
        text(nil)
    end)
end

local function begin(data)
    run = data
    local truck = waitForEntity(run.truckNet, 10000)
    if not truck then
        TCC.notify('Your truck did not arrive. Use /truckco_cancel if this persists.', 'error')
    else
        SetVehicleEngineOn(truck, true, true, false)
    end
    if run.deadline then
        TCC.notify(('Deadline: %s. Late deliveries pay less.'):format(TCShared.duration(run.deadline)), 'warning')
    end
    stageBlip()
    loop()
end

function TCC.startRun(contractId)
    if run then return TCC.notify('You are already on a load.', 'error') end
    if TCC.isInOffice() then return TCC.notify('Head out to the yard first — your truck is parked outside.', 'error') end
    local res = TCC.call('startPlayerRun', contractId)
    if res.ok and res.data then begin(res.data) end
end

RegisterNetEvent('truckco:client:newAssignment', function(contractId)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent('truckco:client:runEnded', function()
    cleanup()
end)

RegisterCommand('truckco_cancel', function()
    if not run then return TCC.notify('You are not on a load.', 'error') end
    if not TCC.confirm('Abandon load', 'The company will be charged a recovery fee and may lose the contract.') then return end
    local res = TCC.call('abandonRun', run.contractId)
    if res.ok then cleanup() end
end, false)

-- resume a run after resource restart / re-log (server still tracks it)
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    Wait(3000)
    if run then return end
    local res = lib.callback.await('truckco:server:getActiveRun', false)
    if res and res.ok and res.data then
        TCC.notify('Resuming your active load.', 'inform')
        begin(res.data)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then text(nil) end
end)

-- Self-check (this is the last client file): report files that didn't load.
CreateThread(function()
    Wait(3000)
    local missing = {}
    for fn, file in pairs({ openTablet = 'client/tablet.lua', startSignEditor = 'client/signs.lua', enterOffice = 'client/office.lua' }) do
        if type(TCC[fn]) ~= 'function' then missing[#missing + 1] = file end
    end
    if #missing > 0 then
        print(('^1[truckco] NOT LOADED: %s. Look for a SCRIPT ERROR line about that file above this. Server owner: replace the whole folder, run "refresh" then "ensure %s".^0'):format(table.concat(missing, ', '), GetCurrentResourceName()))
    end
end)
