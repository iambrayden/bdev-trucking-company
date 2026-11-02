TCC = {
    properties = {}, -- server state per property
    blips = {},
    zones = {},
}

function TCC.notify(msg, typ)
    lib.notify({ title = 'Trucking Co.', description = msg, type = typ or 'inform', duration = 6000 })
end

--- Call a server callback and show its message. Returns the result table.
function TCC.call(name, ...)
    local res = lib.callback.await('truckco:server:' .. name, false, ...)
    if type(res) ~= 'table' then
        TCC.notify('No response from server.', 'error')
        return { ok = false }
    end
    if res.msg then TCC.notify(res.msg, res.ok and 'success' or 'error') end
    return res
end

function TCC.confirm(header, content)
    return lib.alertDialog({ header = header, content = content, centered = true, cancel = true }) == 'confirm'
end

--------------------------------------------------------------------------------
-- Blips + exterior interactions
--------------------------------------------------------------------------------
local function refreshBlips()
    for _, b in pairs(TCC.blips) do RemoveBlip(b) end
    TCC.blips = {}
    for id, prop in pairs(Config.Properties) do
        local st = TCC.properties[id] or {}
        local blip = AddBlipForCoord(prop.entrance.x, prop.entrance.y, prop.entrance.z)
        SetBlipSprite(blip, 477) -- truck
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, st.owned and 5 or 2)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(st.owned and st.name or ('For Sale: ' .. prop.label))
        EndTextCommandSetBlipName(blip)
        TCC.blips[id] = blip
    end
end

local function viewProperty(id)
    local st = TCC.properties[id] or {}
    if st.owned then
        return TCC.notify(('%s is owned by %s.'):format(Config.Properties[id].label, st.name), 'inform')
    end
    TCC.openTablet('listing', { propertyId = id })
end

local function setupZones()
    for _, z in pairs(TCC.zones) do exports.ox_target:removeZone(z) end
    TCC.zones = {}
    for id, prop in pairs(Config.Properties) do
        TCC.zones[#TCC.zones + 1] = exports.ox_target:addSphereZone({
            coords = prop.entrance.xyz,
            radius = 1.5,
            debug = Config.Debug,
            options = {
                {
                    name = 'truckco_view_' .. id,
                    icon = 'fa-solid fa-sign-hanging',
                    label = 'View property',
                    canInteract = function() return not (TCC.properties[id] and TCC.properties[id].owned) end,
                    onSelect = function() viewProperty(id) end,
                },
                {
                    name = 'truckco_enter_' .. id,
                    icon = 'fa-solid fa-door-open',
                    label = 'Enter office',
                    canInteract = function() return TCC.properties[id] and TCC.properties[id].owned end,
                    onSelect = function() TCC.enterOffice(id) end,
                },
                {
                    name = 'truckco_jobs_' .. id,
                    icon = 'fa-solid fa-truck-fast',
                    label = 'My loads',
                    canInteract = function() return TCC.properties[id] and TCC.properties[id].owned end,
                    onSelect = function() TCC.openTablet('driver') end,
                },
            },
        })
    end
end

RegisterNetEvent('truckco:client:properties', function(state)
    TCC.properties = state or {}
    refreshBlips()
end)

local function init()
    TCC.properties = lib.callback.await('truckco:server:getProperties', false) or {}
    refreshBlips()
    setupZones()
    if TCC.onLoaded then TCC.onLoaded() end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', init)
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() and LocalPlayer.state.isLoggedIn then init() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(TCC.blips) do RemoveBlip(b) end
end)

--------------------------------------------------------------------------------
-- Job offers from other players
--------------------------------------------------------------------------------
RegisterNetEvent('truckco:client:jobOffer', function(offer)
    local accept = lib.alertDialog({
        header = 'Job offer',
        content = ('**%s** wants to hire you as a **%s** for **%s** per %d-minute shift.\n\nAccept?'):format(
            offer.company, offer.role, TCShared.money(offer.wage), offer.interval),
        centered = true,
        cancel = true,
        labels = { confirm = 'Accept', cancel = 'Decline' },
    }) == 'confirm'
    TCC.call('respondOffer', accept)
end)

RegisterNetEvent('truckco:client:copy', function(text)
    lib.setClipboard(text)
    TCC.notify('Copied: ' .. text, 'success')
end)
