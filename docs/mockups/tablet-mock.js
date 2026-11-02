/* Mock backend for previewing html/index.html in a normal browser (and for the screenshots).
   Load this BEFORE html/app.js, then open index.html?app=home|finance|board|loads|employees|hire|fleet|upgrades|dispatch|driver|owner|listing */
(function () {
  const config = {
    currency: '$',
    roles: {
      driver: { label: 'Driver', icon: 'truck', npc: true, minWage: 400, maxWage: 3000 },
      dispatcher: { label: 'Dispatcher', icon: 'headset', npc: true, minWage: 600, maxWage: 4000 },
      manager: { label: 'Manager', icon: 'user-tie', npc: false, minWage: 800, maxWage: 6000 },
    },
    certifications: {
      cdl: { label: 'CDL Class A', cost: 6000, minutes: 8, roles: { driver: true } },
      hazmat: { label: 'HAZMAT Endorsement', cost: 14000, minutes: 15, roles: { driver: true }, requires: 'cdl' },
      tanker: { label: 'Tanker Endorsement', cost: 9000, minutes: 10, roles: { driver: true }, requires: 'cdl' },
      oversize: { label: 'Oversize Load Permit', cost: 11000, minutes: 12, roles: { driver: true }, requires: 'cdl' },
      dispatch: { label: 'Dispatch Certification', cost: 8000, minutes: 10, roles: { dispatcher: true } },
    },
    trucks: {
      mule3: { label: 'Maibatsu Mule', class: 'box', price: 45000 },
      benson: { label: 'Vapid Benson', class: 'box', price: 65000 },
      pounder: { label: 'MTL Pounder', class: 'box', price: 80000 },
      packer: { label: 'MTL Packer', class: 'semi', price: 120000 },
      hauler: { label: 'JoBuilt Hauler', class: 'semi', price: 135000 },
      phantom: { label: 'JoBuilt Phantom', class: 'semi', price: 155000 },
    },
    insurance: {
      none: { label: 'Uninsured', premiumPct: 0, coverage: 0, deductible: 0 },
      basic: { label: 'Basic Cover', premiumPct: 0.004, coverage: 0.5, deductible: 2500 },
      full: { label: 'Comprehensive', premiumPct: 0.009, coverage: 0.9, deductible: 1000 },
    },
    upgrades: {
      desks: { label: 'Office Desks', icon: 'chair', description: 'Room for more staff.', levels: [{ price: 20000 }, { price: 45000 }, { price: 90000 }] },
      yard: { label: 'Truck Yard Expansion', icon: 'warehouse', description: 'Park more trucks.', levels: [{ price: 35000 }, { price: 75000 }, { price: 150000 }] },
      training: { label: 'Training Room', icon: 'graduation-cap', description: 'In-house classes make certification faster.', levels: [{ price: 30000 }, { price: 60000 }] },
      dispatch: { label: 'Dispatch Center', icon: 'headset', description: 'Each NPC dispatcher can juggle more loads.', levels: [{ price: 50000 }, { price: 110000 }] },
      breakroom: { label: 'Break Room', icon: 'mug-hot', description: 'Happier staff are less likely to quit when pay is late.', levels: [{ price: 15000 }] },
    },
    properties: {
      elysian_depot: { label: 'Elysian Island Freight Depot', price: 450000, upkeep: 1500, interior: 'Small Warehouse Office' },
    },
    base: { maxEmployees: 3, maxTrucks: 2 },
    fleet: { minDispatchCondition: 25, sellRefund: 0.5 },
    payrollMinutes: 60,
    overdraftLimit: -50000,
    propertyRefund: 0.6,
    hireFee: 1500,
    driverCommission: 0.15,
    signs: { max: 3, price: 2500 },
    perms: {
      manager: { view: true, hire: true, fire: true, train: true, fleet: true, bid: true, assign: true, finance: true, deposit: true, upgrades: true, settings: true },
      dispatcher: { view: true, bid: true, assign: true },
      driver: { view: true },
    },
  };

  const dash = {
    id: 1, name: 'Rourke Freight Lines', property: 'Elysian Island Freight Depot', balance: 184250, reputation: 52, role: 'owner',
    upgrades: { desks: 2, yard: 1, training: 2, dispatch: 1 },
    settings: { autoBid: true, autoAssign: true, usePlayerDrivers: false },
    effects: { maxEmployees: 10, maxTrucks: 4 + 2, dispatchBonus: 1, trainingMult: 0.6, quitMult: 1 },
    counts: { employees: 7, drivers: 4, dispatchers: 2, trucks: 5, active: 4, completed: 38, bids: 3 },
    suspended: false, nextPayroll: 2472, signs: 2, onRoster: true, onDuty: true,
  };
  dash.effects.maxEmployees = 9;

  const employees = [
    { id: 1, kind: 'npc', name: 'Rosa Alvarez', role: 'dispatcher', skill: 64, wage: 1368, certs: { dispatch: true }, status: 'idle', jobs_done: 0 },
    { id: 2, kind: 'npc', name: 'Marcus Chen', role: 'dispatcher', skill: 41, wage: 1092, certs: [], status: 'training', training_cert: 'dispatch', trainingLeft: 400, jobs_done: 0 },
    { id: 3, kind: 'npc', name: 'Dale Kowalski', role: 'driver', skill: 71, wage: 1250, certs: { cdl: true, tanker: true }, status: 'on_job', jobs_done: 23 },
    { id: 4, kind: 'npc', name: 'Earl Whitfield', role: 'driver', skill: 58, wage: 1096, certs: { cdl: true }, status: 'idle', jobs_done: 14 },
    { id: 5, kind: 'player', name: 'Jordan Hayes', role: 'driver', skill: 22, wage: 1200, certs: { cdl: true }, status: 'assigned', jobs_done: 6, online: true, onDuty: true },
    { id: 6, kind: 'player', name: 'Tina Booker', role: 'driver', skill: 15, wage: 900, certs: [], status: 'idle', jobs_done: 2, online: false },
    { id: 7, kind: 'player', name: 'Sam Petrov', role: 'manager', skill: 10, wage: 2000, certs: [], status: 'idle', jobs_done: 0, online: true, onDuty: false },
  ];

  const candidates = [
    { name: 'Bill Rourke', role: 'driver', skill: 82, years: 9, wage: 1384, certs: { cdl: true, tanker: true } },
    { name: 'Gloria Santos', role: 'dispatcher', skill: 64, years: 7, wage: 1368, certs: { dispatch: true } },
    { name: 'Cody Murphy', role: 'driver', skill: 18, years: 1, wage: 616, certs: [] },
    { name: 'Lupe Delgado', role: 'driver', skill: 47, years: 4, wage: 964, certs: { cdl: true } },
    { name: 'Reggie Brooks', role: 'dispatcher', skill: 22, years: 2, wage: 864, certs: [] },
    { name: 'Mae Jenkins', role: 'driver', skill: 9, years: 0, wage: 508, certs: [] },
  ];

  const fleet = [
    { id: 1, model: 'phantom', plate: 'TC482913', health: 88, mileage: 1204.3, insurance: 'full', status: 'in_use', price: 155000, repairCost: 2790, premium: 1395 },
    { id: 2, model: 'packer', plate: 'TC107755', health: 54, mileage: 802.9, insurance: 'basic', status: 'available', price: 120000, repairCost: 8280, premium: 480 },
    { id: 3, model: 'hauler', plate: 'TC930041', health: 97, mileage: 233.1, insurance: 'full', status: 'reserved', price: 135000, repairCost: 607, premium: 1215 },
    { id: 4, model: 'benson', plate: 'TC661208', health: 19, mileage: 412.6, insurance: 'none', status: 'available', price: 65000, repairCost: 7897, premium: 0 },
    { id: 5, model: 'mule3', plate: 'TC245590', health: 72, mileage: 655.0, insurance: 'basic', status: 'in_use', price: 45000, repairCost: 1890, premium: 180 },
  ];

  const loc = (label) => ({ label });
  const board = [
    { id: 151, cargo: 'fuel', cargoLabel: 'Fuel', class: 'semi', certs: ['cdl', 'tanker', 'hazmat'], minRep: 40, pickup: loc('Port of LS - Lot A'), dropoff: loc('Paleto Globe Oil'), distance: 14.2, max_pay: 9850, my_bid: null, bid_count: 3, closesIn: 108, eligible: true },
    { id: 149, cargo: 'logs', cargoLabel: 'Timber', class: 'semi', certs: ['cdl'], minRep: 15, pickup: loc('Port of LS - Lot B'), dropoff: loc('Paleto Bay Sawmill'), distance: 12.7, max_pay: 5950, my_bid: 5100, bid_count: 2, closesIn: 150, eligible: true },
    { id: 153, cargo: 'parcels', cargoLabel: 'Parcels', class: 'box', certs: [], minRep: 0, pickup: loc('Elysian Container Yard'), dropoff: loc('Strawberry Mega Mall'), distance: 2.1, max_pay: 2500, my_bid: null, bid_count: 0, closesIn: 182, eligible: true },
    { id: 154, cargo: 'machinery', cargoLabel: 'Heavy Machinery', class: 'semi', certs: ['cdl', 'oversize'], minRep: 30, pickup: loc('Buccaneer Way Docks'), dropoff: loc('Davis Quartz Quarry'), distance: 9.6, max_pay: 8400, my_bid: null, bid_count: 1, closesIn: 281, eligible: true },
    { id: 155, cargo: 'chemicals', cargoLabel: 'Industrial Chemicals', class: 'semi', certs: ['cdl', 'hazmat'], minRep: 60, pickup: loc('Port of LS - Lot A'), dropoff: loc('Humane Labs'), distance: 11.4, max_pay: 14300, my_bid: null, bid_count: 4, closesIn: 310, eligible: false },
    { id: 156, cargo: 'produce', cargoLabel: 'Refrigerated Produce', class: 'semi', certs: ['cdl'], minRep: 10, pickup: loc('Elysian Container Yard'), dropoff: loc('Grapeseed Farms'), distance: 10.9, max_pay: 6100, my_bid: null, bid_count: 1, closesIn: 415, eligible: true },
  ];

  const loads = [
    { id: 146, cargoLabel: 'General Freight', class: 'semi', certs: ['cdl'], dropoff: loc('Sandy Shores Airfield'), distance: 8.8, status: 'awarded', award_amount: 6300, acceptIn: 492, deadlineIn: 1680 },
    { id: 141, cargoLabel: 'Timber', class: 'semi', certs: ['cdl'], dropoff: loc('Paleto Bay Sawmill'), distance: 12.7, status: 'assigned', award_amount: 5400, driver_name: 'Jordan Hayes', truck_plate: 'TC930041', deadlineIn: 1300 },
    { id: 139, cargoLabel: 'Vehicle Transport', class: 'semi', certs: ['cdl'], dropoff: loc('Harmony Garage'), distance: 9.9, status: 'in_progress', award_amount: 7450, driver_name: 'Dale Kowalski', truck_plate: 'TC482913', etaIn: 291, deadlineIn: 900 },
    { id: 137, cargoLabel: 'Furniture', class: 'box', certs: [], dropoff: loc('Strawberry Mega Mall'), distance: 2.4, status: 'in_progress', award_amount: 2300, driver_name: 'Earl Whitfield', truck_plate: 'TC245590', etaIn: 69, deadlineIn: 600 },
    { id: 131, cargoLabel: 'General Freight', class: 'semi', certs: ['cdl'], dropoff: loc('Senora Desert RON'), distance: 10.3, status: 'completed', award_amount: 6900, driver_name: 'Dale Kowalski', truck_plate: 'TC482913' },
    { id: 128, cargoLabel: 'Fuel', class: 'semi', certs: ['cdl', 'tanker', 'hazmat'], dropoff: loc('Palmer-Taylor Power'), distance: 11.0, status: 'failed', award_amount: 8800, driver_name: 'Earl Whitfield', truck_plate: 'TC107755' },
  ];

  const ledger = [
    [7450, 'Load #139 delivered', '02 Nov 21:14'], [-1297, 'Driver commission load #151', '02 Nov 21:09'], [8650, 'Load #151 delivered', '02 Nov 21:09'],
    [-6180, 'Payroll (7 staff)', '02 Nov 21:00'], [-1260, 'Insurance premiums (5 trucks)', '02 Nov 21:00'], [-1500, 'Property upkeep', '02 Nov 21:00'],
    [4210, 'Insurance claim (TC482913): accident repairs #131', '02 Nov 20:47'], [-14000, 'Training: Earl Whitfield - HAZMAT Endorsement', '02 Nov 20:40'],
    [-45000, 'Office upgrade: Office Desks (Lv 2)', '02 Nov 20:31'], [25000, 'Deposit by Bill Rourke', '02 Nov 20:30'], [-4400, 'Load #128 failed: Earl Whitfield wrecked the load', '02 Nov 20:12'],
  ].map(([amount, reason, ts]) => ({ amount, reason, ts }));

  const handlers = {
    getDashboard: () => ({ ok: true, data: dash }),
    getEmployees: () => ({ ok: true, data: { list: employees, max: 9 } }),
    getCandidates: () => ({ ok: true, data: { list: candidates, refreshIn: 1325, fee: 1500 } }),
    getFleet: () => ({ ok: true, data: { list: fleet, max: 6 } }),
    getBoard: () => ({ ok: true, data: { list: board, reputation: 52, suspended: false, minBidPct: 0.4 } }),
    getMyContracts: () => ({ ok: true, data: loads }),
    getAssignOptions: () => ({ ok: true, data: { drivers: [employees[3], employees[4]], trucks: [fleet[1]] } }),
    getLedger: () => ({ ok: true, data: ledger }),
    getMyAssignments: () => ({ ok: true, data: { pending: 2400, onDuty: true, list: [{ id: 141, cargoLabel: 'Timber', class: 'semi', dropoff: loc('Paleto Bay Sawmill'), distance: 12.7, truck_plate: 'TC930041', deadlineIn: 1300, status: 'assigned' }] } }),
  };

  window.TC_MOCK = {
    post(endpoint, data) {
      if (endpoint === 'nearbyPlayers') return Promise.resolve([{ id: 14, name: 'Jordan_Hayes (ID 14)' }, { id: 22, name: 'Ava_Moreno (ID 22)' }]);
      if (endpoint !== 'call') return Promise.resolve(1);
      const h = handlers[data.name];
      return Promise.resolve(h ? h(...(data.args || [])) : { ok: true, msg: `(mock) ${data.name} ok` });
    },
    ready(open) {
      const q = new URLSearchParams(location.search);
      const app = q.get('app') || 'home';
      window.addEventListener('DOMContentLoaded', () => {});
      open({ action: 'open', app, extra: app === 'listing' ? { propertyId: 'elysian_depot' } : null, inOffice: app !== 'listing', config });
    },
  };
})();
