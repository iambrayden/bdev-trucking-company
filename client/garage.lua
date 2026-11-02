--[[
    Company garage spots:
      * truck pickup spot : ox_target "Company garage" -> tablet Fleet (Take out)
      * truck return spot : marker + "[E] Park company truck"
]]
local info = nil
local zoneId, retPoint = nil, nil
local outNet = nil

local function clear()
    if zoneId then exports.ox_target:removeZone(zoneId) zoneId = nil end
    if retPoint then retPoint:remove() retPoint = nil end
    lib.hideTextUI()
end

local function inGarageTruck()
    if not outNet or not NetworkDoesNetworkIdExist(outNet) then return false end
    local veh = NetworkGetEntityFromNetworkId(outNet)
    return veh ~= 0 and GetVehiclePedIsIn(cache.ped, false) == veh
end

local function park()
    local veh = outNet and NetworkDoesNetworkIdExist(outNet) and NetworkGetEntityFromNetworkId(outNet) or 0
    if veh ~= 0 and GetVehiclePedIsIn(cache.ped, false) == veh then
        TaskLeaveVehicle(cache.ped, veh, 0)
        Wait(1500)
    end
    local res = TCC.call('parkTruck')
    if res.ok or (res.msg and res.msg:find('lost')) then outNet = nil end
end

local function setup()
    clear()
    local ok, res = pcall(lib.callback.await, 'truckco:server:getGarageInfo', false)
    info = ok and res or nil
    if not info or not info.canUse or not info.spawn then return end
    local sp, rp = info.spawn, info.ret
    zoneId = exports.ox_target:addSphereZone({
        coords = vec3(sp.x, sp.y, sp.z),
        radius = 2.5,
        debug = Config.Debug,
        options = {
            { name = 'truckco_myloads', icon = 'fa-solid fa-route', label = 'My loads (start a delivery)',
              onSelect = function() TCC.openTablet('driver') end },
            { name = 'truckco_garage', icon = 'fa-solid fa-warehouse', label = 'Company garage',
              onSelect = function() TCC.openTablet('fleet') end },
            { name = 'truckco_garage_park', icon = 'fa-solid fa-square-parking', label = 'Park company truck',
              canInteract = function() return outNet ~= nil end, onSelect = park },
        },
    })
    if rp then
        local shown = false
        retPoint = lib.points.new({
            coords = vec3(rp.x, rp.y, rp.z),
            distance = 30.0,
            nearby = function(self)
                if not outNet then return end
                DrawMarker(1, rp.x, rp.y, rp.z - 1.0, 0, 0, 0, 0, 0, 0, 5.0, 5.0, 0.6, 80, 160, 255, 90, false, false, 2, false, nil, nil, false)
                if self.currentDistance < 6.0 and inGarageTruck() then
                    if not shown then lib.showTextUI('[E] Park company truck', { icon = 'square-parking' }) shown = true end
                    if IsControlJustReleased(0, 38) then
                        lib.hideTextUI() shown = false
                        park()
                    end
                elseif shown then
                    lib.hideTextUI() shown = false
                end
            end,
            onExit = function() if shown then lib.hideTextUI() shown = false end end,
        })
    end
end

function TCC.takeOutTruck(truckId)
    local res = lib.callback.await('truckco:server:takeOutTruck', false, truckId) or {}
    if res.data and res.data.startLoad then
        TCC.notify('You have a load assigned. Starting it now with its truck.', 'inform')
        return TCC.startRun(res.data.startLoad)
    end
    if res.msg then TCC.notify(res.msg, res.ok and 'success' or 'error') end
    if res.ok and res.data then
        outNet = res.data.netId
        if not zoneId then setup() end
    end
end

RegisterNetEvent('truckco:client:garageChanged', function() setup() end)

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    Wait(2000)
    setup()
end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() Wait(2000) setup() end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clear() end
end)
