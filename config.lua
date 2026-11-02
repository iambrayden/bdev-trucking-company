Config = {}

Config.Debug = false            -- draws ox_target zones & prints extra logs
Config.Currency = '$'
Config.RoutingBucketBase = 7000 -- each company's office lives in bucket (base + companyId)

--------------------------------------------------------------------------------
-- Integrations (adapt these if you use different key / fuel resources)
--------------------------------------------------------------------------------
Config.GiveKeys = function(source, vehicle, plate)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(source, vehicle, true) end)
    end
end

Config.SetFuel = function(vehicle)
    Entity(vehicle).state.fuel = 100.0 -- ox_fuel / qbx statebag fuel
end

--------------------------------------------------------------------------------
-- Properties for sale (down by the docks). One company per property.
-- NOTE: coordinates are sensible defaults around Elysian Island / Terminal;
--       fly there with /truckco_pos (admin) and tweak to taste.
--------------------------------------------------------------------------------
Config.Properties = {
    elysian_depot = {
        label = 'Elysian Island Freight Depot',
        price = 450000,
        upkeep = 1500,                                   -- charged every payroll cycle
        entrance = vec4(153.68, -3211.88, 5.91, 270.0),  -- where you walk in
        truckSpawn = vec4(141.12, -3204.31, 5.85, 267.5),-- where company trucks are pulled out
        truckReturn = vec3(137.5, -3190.0, 5.86),        -- where trucks are dropped back off
        interior = 'warehouse_small',
    },
    terminal_yard = {
        label = 'Terminal Logistics Yard',
        price = 650000,
        upkeep = 2200,
        entrance = vec4(1197.07, -3253.62, 7.10, 90.0),
        truckSpawn = vec4(1184.50, -3243.80, 6.03, 90.0),
        truckReturn = vec3(1172.0, -3236.0, 6.03),
        interior = 'warehouse_small',
    },
    pier_400 = {
        label = 'Pier 400 Haulage',
        price = 325000,
        upkeep = 1100,
        entrance = vec4(-246.20, -2654.30, 6.00, 0.0),
        truckSpawn = vec4(-232.40, -2660.10, 6.00, 0.0),
        truckReturn = vec3(-222.0, -2668.0, 6.00),
        interior = 'warehouse_small',
    },
}

--------------------------------------------------------------------------------
-- Office interiors. All points are OFFSETS from `origin`.
--   type = 'interior' : teleport into an existing GTA interior at origin.
--   type = 'shell'    : spawn `model` (e.g. a K4MB1 office shell) at origin.
-- The office starts as a bare shell. Furniture appears as upgrades are bought.
--------------------------------------------------------------------------------
Config.Interiors = {
    warehouse_small = {
        label = 'Small Warehouse Office',
        type = 'interior',
        origin = vec3(1094.988, -3101.776, -39.0),
        -- spawn / exit are offsets from origin (player coords, not floor)
        spawn = vec4(0.0, 0.0, 0.0, 90.0),
        exit = vec3(-7.39, 2.30, 0.00),     -- placed in-game with /truckco_furnish
        -- fallback interaction spots, only used if the matching `interact` prop is missing
        computer = vec3(-3.0, 2.0, 0.0),
        board = vec3(-3.0, -2.0, 0.0),
        timeclock = vec3(-1.0, 3.0, 0.0),
        --[[
            Furniture. offset = vec4(x, y, heightAboveFloor, heading) relative to origin.
              * Props are snapped to the real floor (bottom of the model sits at height 0).
              * on = '<id>'  stacks the prop on top of another prop with that id.
              * interact = 'computer' | 'board' | 'timeclock' makes the prop itself the
                ox_target interaction point (opens the tablet on that app).
            Fix positions in-game with /truckco_furnish (admin): aim, place, and it
            prints the line to paste here.
        ]]
        furniture = {
            base = {
                { id = 'desk', model = 'prop_box_wood02a', offset = vec4(-3.0, 2.0, 0.0, 90.0) },
                { id = 'laptop', model = 'prop_laptop_01a', on = 'desk', offset = vec4(-3.0, 2.0, 0.0, 270.0), interact = 'computer' },
                { id = 'board', model = 'prop_tv_flat_01', offset = vec4(-3.6, -2.0, 1.1, 90.0), interact = 'board' },
            },
            -- furniture[upgradeKey][level] = list of props added at that level
            desks = {
                [1] = { { id = 'chair1', model = 'prop_off_chair_01', offset = vec4(-5.0, 1.0, 0.0, 90.0) } },
                [2] = { { id = 'chair2', model = 'prop_off_chair_01', offset = vec4(-5.0, -1.0, 0.0, 90.0) } },
            },
            breakroom = {
                [1] = { { id = 'coffee', model = 'prop_vend_coffe_01', offset = vec4(-1.0, 4.2, 0.0, 180.0) } },
            },
        },
    },

    -- Example for a K4MB1-style shell (uncomment and set property.interior = 'office_shell')
    -- office_shell = {
    --     label = 'Office Shell', type = 'shell', model = `shell_office1`,
    --     origin = vec3(0.0, 0.0, -80.0),
    --     spawn = vec4(1.2, 4.9, 1.0, 180.0), exit = vec3(1.2, 4.9, 1.0),
    --     computer = vec3(3.5, -1.0, 1.0), board = vec3(-3.0, 1.0, 1.0), timeclock = vec3(0.0, 3.0, 1.0),
    --     furniture = { base = {} },
    -- },
}

--------------------------------------------------------------------------------
-- Tablet UI
--------------------------------------------------------------------------------
Config.Tablet = {
    command = 'trucktablet',   -- opens the company tablet anywhere (set nil to disable)
    allowRemote = true,        -- false = tablet only works inside the office / at the depot
    remoteDistance = 75.0,     -- when allowRemote = false: max distance from your depot
    prop = `prop_cs_tablet`,
    anim = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', clip = 'base' },
}

--------------------------------------------------------------------------------
-- Company garage (take trucks out of the yard for free driving)
--------------------------------------------------------------------------------
Config.Garage = {
    roles = { manager = true, dispatcher = true, driver = true }, -- owner can always
}

--------------------------------------------------------------------------------
-- Exterior signs (company name, placed by owners/managers outside the depot)
--------------------------------------------------------------------------------
Config.Signs = {
    max = 3,                    -- signs per company
    price = 2500,               -- charged per new sign when saved
    radius = 60.0,              -- how far from the depot entrance signs may go
    drawDistance = 120.0,       -- how far away players can see them
    size = { width = 4.0, height = 1.5, postHeight = 1.2 },  -- metres
    resolution = { 1024, 384 }, -- sign texture size (keep the same aspect as width/height)
    styles = {                  -- order = cycle order in the editor
        { id = 'orange', label = 'Highway Orange' },
        { id = 'white', label = 'Clean White' },
        { id = 'navy', label = 'Navy' },
        { id = 'red', label = 'Big Rig Red' },
    },
}

--------------------------------------------------------------------------------
-- Imperial CAD: register company trucks so police plate checks show the company
-- (uses exports['ImperialCAD']:CreateVehicleAdvanced; skipped if not running)
--------------------------------------------------------------------------------
Config.ImperialCAD = {
    enabled = true,
    resource = 'ImperialCAD',
    owner = 'company',          -- 'company' = registered to the company; 'owner' = to the owner's character
    ownerUsesCitizenId = true,  -- 'owner' mode: send the owner's citizenid as ownerSSN (to link the civ)
    regState = 'SA',
    regValidDays = 365,
    year = '2024',
    color = 'White',
    companyCity = 'Los Santos',
}

--------------------------------------------------------------------------------
-- Company baseline + office upgrades
--------------------------------------------------------------------------------
Config.Base = {
    maxEmployees = 3,
    maxTrucks = 2,
}

-- effect keys: maxEmployees (+), maxTrucks (+), dispatchBonus (+jobs per dispatcher),
--              trainingMult (x), quitMult (x)
Config.Upgrades = {
    desks = {
        label = 'Office Desks', icon = 'chair',
        description = 'Room for more staff.',
        levels = {
            { price = 20000, effect = { maxEmployees = 3 } },
            { price = 45000, effect = { maxEmployees = 4 } },
            { price = 90000, effect = { maxEmployees = 6 } },
        },
    },
    yard = {
        label = 'Truck Yard Expansion', icon = 'warehouse',
        description = 'Park more trucks.',
        levels = {
            { price = 35000, effect = { maxTrucks = 2 } },
            { price = 75000, effect = { maxTrucks = 3 } },
            { price = 150000, effect = { maxTrucks = 5 } },
        },
    },
    training = {
        label = 'Training Room', icon = 'graduation-cap',
        description = 'In-house classes make certification faster.',
        levels = {
            { price = 30000, effect = { trainingMult = 0.8 } },
            { price = 60000, effect = { trainingMult = 0.75 } },
        },
    },
    dispatch = {
        label = 'Dispatch Center', icon = 'headset',
        description = 'Each NPC dispatcher can juggle more loads.',
        levels = {
            { price = 50000, effect = { dispatchBonus = 1 } },
            { price = 110000, effect = { dispatchBonus = 1 } },
        },
    },
    breakroom = {
        label = 'Break Room', icon = 'mug-hot',
        description = 'Happier staff are less likely to quit when pay is late.',
        levels = {
            { price = 15000, effect = { quitMult = 0.5 } },
        },
    },
}

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------
Config.Roles = {
    driver     = { label = 'Driver',     icon = 'truck',       npc = true,  minWage = 400,  maxWage = 3000 },
    dispatcher = { label = 'Dispatcher', icon = 'headset',     npc = true,  minWage = 600,  maxWage = 4000 },
    manager    = { label = 'Manager',    icon = 'user-tie',    npc = false, minWage = 800,  maxWage = 6000 },
}

Config.Certifications = {
    cdl      = { label = 'CDL Class A',          cost = 6000,  minutes = 8,  roles = { driver = true } },
    hazmat   = { label = 'HAZMAT Endorsement',   cost = 14000, minutes = 15, roles = { driver = true }, requires = 'cdl' },
    tanker   = { label = 'Tanker Endorsement',   cost = 9000,  minutes = 10, roles = { driver = true }, requires = 'cdl' },
    oversize = { label = 'Oversize Load Permit', cost = 11000, minutes = 12, roles = { driver = true }, requires = 'cdl' },
    dispatch = { label = 'Dispatch Certification', cost = 8000, minutes = 10, roles = { dispatcher = true } },
}

Config.NPC = {
    hireFee = 1500,               -- recruiter fee per NPC hire
    candidates = 6,               -- applicants shown at once
    refreshMinutes = 30,          -- applicant pool refresh
    wagePerSkill = 12,            -- asked wage = role min + skill * this
    kmPerMinute = 1.2,            -- simulated NPC driving speed
    accidentBase = 0.10,          -- accident chance at skill 0 and 100% truck condition
    accidentSkillReduce = 0.08,   -- skill 100 removes this much chance
    accidentConditionAdd = 0.10,  -- condition 0 adds this much chance
    severeAccident = 0.25,        -- portion of accidents that destroy the load
    skillPerJob = 1,              -- skill gained per completed job (max 100)
    quitChanceUnpaid = 0.25,      -- chance per NPC per missed payroll
    firstNames = { 'Bill', 'Dale', 'Rosa', 'Marcus', 'Tina', 'Earl', 'Jo', 'Hank', 'Lupe', 'Darnell', 'Kim', 'Vic', 'Sal', 'Gloria', 'Reggie', 'Cody', 'Mae', 'Travis', 'Ana', 'Lou' },
    lastNames = { 'Rourke', 'Jenkins', 'Alvarez', 'Booker', 'Nguyen', 'Kowalski', 'Hayes', 'Petrov', 'Murphy', 'Delgado', 'Brooks', 'Chen', 'Oyelaran', 'Whitfield', 'Santos', 'McGraw' },
}

--------------------------------------------------------------------------------
-- Fleet
--------------------------------------------------------------------------------
-- class 'semi' pulls trailers, class 'box' carries its own cargo
Config.Trucks = {
    mule3   = { label = 'Maibatsu Mule',   class = 'box',  price = 45000 },
    benson  = { label = 'Vapid Benson',    class = 'box',  price = 65000 },
    pounder = { label = 'MTL Pounder',     class = 'box',  price = 80000 },
    packer  = { label = 'MTL Packer',      class = 'semi', price = 120000 },
    hauler  = { label = 'JoBuilt Hauler',  class = 'semi', price = 135000 },
    phantom = { label = 'JoBuilt Phantom', class = 'semi', price = 155000 },
}

Config.Fleet = {
    platePrefix = 'TC',
    repairCostPerPoint = 0.0015, -- * truck price per condition point
    minDispatchCondition = 25,   -- trucks below this can't take loads
    wearPerKm = 0.25,            -- condition lost per km driven
    sellRefund = 0.5,
}

Config.Insurance = {
    none  = { label = 'Uninsured',     premiumPct = 0.0,   coverage = 0.0, deductible = 0 },
    basic = { label = 'Basic Cover',   premiumPct = 0.004, coverage = 0.5, deductible = 2500 },
    full  = { label = 'Comprehensive', premiumPct = 0.009, coverage = 0.9, deductible = 1000 },
}

--------------------------------------------------------------------------------
-- Contracts / bid board
--------------------------------------------------------------------------------
Config.Cargo = {
    parcels   = { label = 'Parcels',              class = 'box',  certs = {},                         payMult = 0.8, minRep = 0 },
    furniture = { label = 'Furniture',            class = 'box',  certs = {},                         payMult = 0.9, minRep = 0 },
    general   = { label = 'General Freight',      class = 'semi', certs = { 'cdl' },                  payMult = 1.0, minRep = 0,  trailers = { 'trailers', 'trailers2' } },
    produce   = { label = 'Refrigerated Produce', class = 'semi', certs = { 'cdl' },                  payMult = 1.15, minRep = 10, trailers = { 'trailers3' } },
    logs      = { label = 'Timber',               class = 'semi', certs = { 'cdl' },                  payMult = 1.2, minRep = 15, trailers = { 'trailerlogs' } },
    vehicles  = { label = 'Vehicle Transport',    class = 'semi', certs = { 'cdl' },                  payMult = 1.4, minRep = 25, trailers = { 'tr4' } },
    machinery = { label = 'Heavy Machinery',      class = 'semi', certs = { 'cdl', 'oversize' },      payMult = 1.6, minRep = 30, trailers = { 'trflat' } },
    fuel      = { label = 'Fuel',                 class = 'semi', certs = { 'cdl', 'tanker', 'hazmat' }, payMult = 1.9, minRep = 40, trailers = { 'tanker', 'tanker2' } },
    chemicals = { label = 'Industrial Chemicals', class = 'semi', certs = { 'cdl', 'hazmat' },        payMult = 2.2, minRep = 60, trailers = { 'tanker' } },
}

-- Where loads are picked up (port lots). Trailers spawn here.
Config.Pickups = {
    { label = 'Port of LS - Lot A', coords = vec4(1145.40, -3256.00, 5.90, 90.0) },
    { label = 'Port of LS - Lot B', coords = vec4(860.00, -2915.00, 5.90, 90.0) },
    { label = 'Elysian Container Yard', coords = vec4(232.00, -3115.00, 5.80, 90.0) },
    { label = 'Buccaneer Way Docks', coords = vec4(-63.00, -2525.00, 6.00, 235.0) },
}

Config.Destinations = {
    { label = 'Paleto Bay Sawmill',        coords = vec3(-576.0, 5245.0, 70.5) },
    { label = 'Paleto Globe Oil',          coords = vec3(174.0, 6600.0, 31.8) },
    { label = 'Grapeseed Farms',           coords = vec3(2441.0, 4973.0, 46.8) },
    { label = 'Sandy Shores Airfield',     coords = vec3(1740.0, 3290.0, 41.1) },
    { label = 'Harmony Garage',            coords = vec3(1180.0, 2640.0, 37.8) },
    { label = 'Senora Desert RON',         coords = vec3(2680.0, 3265.0, 55.2) },
    { label = 'Palmer-Taylor Power',       coords = vec3(2732.0, 1577.0, 24.5) },
    { label = 'Davis Quartz Quarry',       coords = vec3(2953.0, 2789.0, 41.0) },
    { label = 'Humane Labs',               coords = vec3(3618.0, 3735.0, 28.6) },
    { label = 'Murrieta Oil Field',        coords = vec3(1390.0, -2060.0, 52.0) },
    { label = 'Strawberry Mega Mall',      coords = vec3(60.0, -1740.0, 29.3) },
}

Config.Board = {
    baseOpen = 8,                 -- contracts open on the board at once...
    perCompanyOpen = 3,           -- ...plus this many per existing company
    maxOpen = 40,
    generateEvery = 60,           -- seconds between generation passes
    bidWindow = { 180, 420 },     -- seconds a contract accepts bids
    acceptWindow = 600,           -- seconds after award to get the load moving
    ratePerKm = 350,
    roadFactor = 1.35,            -- straight-line -> road distance
    minPay = 2500,
    minBidPct = 0.4,              -- lowest allowed bid (% of max pay)
    marketBid = { 0.72, 0.98 },   -- hidden rival bid range (% of max pay)
    repAdvantage = 500,           -- effective bid = bid * (1 - (rep-50)/this)
    deadlineKmPerMin = 0.9,       -- deadline = dist / this + buffer
    deadlineBuffer = 12,          -- minutes
    latePenalty = 0.35,           -- payout lost when late
    failPenalty = 0.5,            -- % of contract charged when a load is lost/abandoned
    repOnTime = 2, repLate = -1, repFail = -4,
}

Config.Runs = {
    minSecondsPerKm = 25,         -- anti-exploit: fastest a player can legitimately deliver
    driverCommission = 0.15,      -- player driver's cut of the payout (paid on top of wage, from company)
    recoveryFee = 2500,           -- charged when a truck is abandoned / player disconnects
    returnGraceMinutes = 20,
}

--------------------------------------------------------------------------------
-- Automation & economy ticks
--------------------------------------------------------------------------------
Config.Dispatch = {
    interval = 45,                -- seconds between dispatcher passes
    baseCapacity = 2,             -- concurrent loads per NPC dispatcher
    skillPerCapacity = 40,        -- +1 capacity per this much skill
    maxBidsPerPass = 2,
}

Config.Payroll = {
    intervalMinutes = 60,
    playerOnDutyOnly = true,      -- player wages only paid if they clocked in during the cycle
    overdraftLimit = -50000,      -- below this the company is suspended (no bidding)
}

Config.Economy = {
    startingBalance = 0,
    propertyRefund = 0.6,
}
