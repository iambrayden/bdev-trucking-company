--[[
    Imperial CAD integration: registers company trucks so a plate check shows
    the company (or its owner), registration and insurance status.
    Docs: https://docs.imperialcad.app (ImperialCharacters -> CreateVehicleAdvanced)
    Imperial has no update/delete vehicle export, so later insurance changes and
    sold trucks are NOT reflected in the CAD.
]]

local cfg = Config.ImperialCAD

function TC.cadAvailable()
    return cfg and cfg.enabled and GetResourceState(cfg.resource) == 'started'
end

local function splitLabel(label)
    local make, model = label:match('^(%S+)%s+(.+)$')
    return make or 'Unknown', model or label
end

local function vin()
    local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
    local out = {}
    for i = 1, 17 do
        local n = math.random(#chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

local function ownerBlock(company)
    if cfg.owner == 'owner' then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { company.owner })
        local ci = row and json.decode(row.charinfo or '{}') or {}
        return {
            ownerSSN = cfg.ownerUsesCitizenId and company.owner or nil,
            ownerFirstName = ci.firstname or 'Unknown',
            ownerLastName = ci.lastname or 'Owner',
            ownerGender = ci.gender == 1 and 'Female' or 'Male',
            ownerAddress = (Config.Properties[company.property] or {}).label or 'Port of Los Santos',
            ownerCity = cfg.companyCity,
        }
    end
    return {
        ownerFirstName = company.name,
        ownerLastName = '(Company)',
        ownerGender = 'Other',
        ownerAddress = (Config.Properties[company.property] or {}).label or 'Port of Los Santos',
        ownerCity = cfg.companyCity,
    }
end

--- Register one company truck in Imperial CAD (fire and forget).
function TC.cadRegisterTruck(company, truck)
    if not TC.cadAvailable() then return end
    local def = Config.Trucks[truck.model] or { label = truck.model }
    local make, model = splitLabel(def.label)
    local tier = Config.Insurance[truck.insurance] or Config.Insurance.none
    local insured = tier.coverage > 0
    local ok, err = pcall(function()
        exports[cfg.resource]:CreateVehicleAdvanced({
            vehicleData = {
                plate = truck.plate,
                model = model,
                Make = make,
                color = cfg.color,
                year = cfg.year,
                regState = cfg.regState,
                regStatus = 'Valid',
                regExpDate = os.date('%Y-%m-%d', os.time() + cfg.regValidDays * 86400),
                vin = vin(),
                stolen = false,
            },
            vehicleInsurance = {
                hasInsurance = insured,
                insuranceStatus = insured and 'Active' or 'None',
                insurancePolicyNum = insured and ('TC-%d-%s'):format(company.id, truck.plate) or '',
            },
            vehicleOwner = ownerBlock(company),
        }, function(success, res)
            if not success then
                print(('[truckco] Imperial CAD registration failed for %s: %s'):format(truck.plate, json.encode(res)))
            elseif Config.Debug then
                print(('[truckco] Imperial CAD registered %s'):format(truck.plate))
            end
        end)
    end)
    if not ok then print('[truckco] Imperial CAD export error: ' .. tostring(err)) end
end

-- Admin: register every existing company truck (e.g. after enabling the integration)
lib.addCommand('truckco_cadsync', {
    help = 'Register all trucking company trucks in Imperial CAD',
    restricted = 'group.admin',
}, function(source)
    if not TC.cadAvailable() then return TC.notify(source, 'Imperial CAD is not running or disabled in config.', 'error') end
    local count = 0
    for _, company in ipairs(TC.getAllCompanies()) do
        for _, truck in ipairs(MySQL.query.await('SELECT * FROM truckco_trucks WHERE company_id = ?', { company.id }) or {}) do
            TC.cadRegisterTruck(company, truck)
            count = count + 1
        end
    end
    TC.notify(source, ('Sent %d trucks to Imperial CAD.'):format(count), 'success')
end)

-- start-up check so misconfiguration is obvious in the server console
CreateThread(function()
    Wait(5000)
    if not (cfg and cfg.enabled) then return end
    if GetResourceState(cfg.resource) ~= 'started' then
        print(('^3[truckco] Imperial CAD integration enabled but resource "%s" is not started; trucks will not be registered.^0'):format(cfg.resource))
        return
    end
    if GetConvar('imperialAPI', '') == '' or GetConvar('imperial_community_id', '') == '' then
        print('^3[truckco] Imperial CAD: imperialAPI / imperial_community_id convars look empty in server.cfg; registrations will fail.^0')
    else
        print('^2[truckco] Imperial CAD integration active^0')
    end
end)
