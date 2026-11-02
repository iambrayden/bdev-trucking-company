const SCENES = {
  '01-buy-property': {
    target: { hover: 0, options: [{ icon: 'sign-hanging', label: 'View property' }] },
    ctx: {
      pos: { right: '6%' },
      title: 'Elysian Island Freight Depot',
      options: [
        { icon: 'tag', title: 'Price', desc: '$450,000' },
        { icon: 'file-invoice-dollar', title: 'Upkeep', desc: '$1,500 every payroll (60 min)' },
        { icon: 'building', title: 'Office', desc: 'Small Warehouse Office' },
        { icon: 'warehouse', title: 'Start capacity', desc: '3 staff, 2 trucks (expand with upgrades)' },
        { icon: 'file-signature', title: 'Buy & found a trucking company' },
      ],
      hover: 4,
    },
    caption: ['Buy a depot at the docks', 'Three properties for sale around Elysian Island & Terminal. One company per property.'],
  },

  '02-found-company': {
    input: {
      title: 'Found your company',
      fields: [{ type: 'input', label: 'Company name', required: true, value: 'Rourke Freight Lines', focus: true }],
    },
    caption: ['Name your company', 'Shows up on the map blip, notifications and the ledger.'],
  },

  '03-management': {
    bg: 'office',
    ctx: {
      title: 'Company Management',
      options: [
        { icon: 'building', title: 'Rourke Freight Lines', desc: 'Elysian Island Freight Depot • Owner' },
        { icon: 'users', title: 'Employees', desc: '7 / 9 staff (4 drivers, 2 dispatchers)', arrow: true },
        { icon: 'user-plus', title: 'Hire staff', desc: 'Recruit NPC applicants or hire a player near you', arrow: true },
        { icon: 'truck', title: 'Fleet', desc: '5 / 6 trucks', arrow: true },
        { icon: 'clipboard-list', title: 'Job bid board', desc: '3 open bids', arrow: true },
        { icon: 'route', title: 'Company loads', desc: '4 active • 38 completed', arrow: true },
        { icon: 'hammer', title: 'Office upgrades', desc: 'Build out your office shell', arrow: true },
        { icon: 'robot', title: 'Dispatch automation', desc: 'What your NPC dispatchers are allowed to do', arrow: true },
        { icon: 'sack-dollar', title: 'Finances', desc: 'Deposit, withdraw, ledger', arrow: true },
        { icon: 'crown', title: 'Owner', desc: 'Rename, roster, sell company', arrow: true },
      ],
      hover: 0,
      tip: [['Balance', '$184,250'], ['Reputation', '52/100'], ['Next payroll', '41m 12s']],
    },
    caption: ['Company management laptop', 'Everything runs from the laptop in your office: staff, fleet, bids, loads, upgrades and money.'],
  },

  '04-employees': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Employees (7/9)',
      options: [
        { icon: 'headset', title: 'Rosa Alvarez — Dispatcher', desc: 'NPC • Available', arrow: true },
        { icon: 'headset', title: 'Marcus Chen — Dispatcher', desc: 'NPC • Training Dispatch Certification (6m 40s)', arrow: true },
        { icon: 'truck', title: 'Dale Kowalski — Driver', desc: 'NPC • On the road', arrow: true },
        { icon: 'truck', title: 'Earl Whitfield — Driver', desc: 'NPC • Available', arrow: true },
        { icon: 'truck', title: 'Jordan Hayes — Driver', desc: 'Player • on duty • Assigned (waiting)', arrow: true },
        { icon: 'truck', title: 'Tina Booker — Driver', desc: 'Player • offline • Available', arrow: true },
        { icon: 'user-tie', title: 'Sam Petrov — Manager', desc: 'Player • off duty • Available', arrow: true },
      ],
      hover: 2,
      tip: [['Skill', '71'], ['Wage', '$1,250 / shift'], ['Loads done', '23'], ['Certs', 'CDL Class A, Tanker Endorsement']],
    },
    caption: ['NPC + player staff', 'Drivers, dispatchers and managers. See who is online, on duty, on the road or in training.'],
  },

  '05-applicants': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Applicants (refresh in 22m 05s)',
      options: [
        { icon: 'truck', title: 'Bill Rourke — Driver', desc: 'Skill 82 • 9 yrs experience • asks $1,384/shift' },
        { icon: 'headset', title: 'Gloria Santos — Dispatcher', desc: 'Skill 64 • 7 yrs experience • asks $1,368/shift' },
        { icon: 'truck', title: 'Cody Murphy — Driver', desc: 'Skill 18 • 1 yrs experience • asks $616/shift' },
        { icon: 'truck', title: 'Lupe Delgado — Driver', desc: 'Skill 47 • 4 yrs experience • asks $964/shift' },
        { icon: 'headset', title: 'Reggie Brooks — Dispatcher', desc: 'Skill 22 • 2 yrs experience • asks $864/shift' },
        { icon: 'truck', title: 'Mae Jenkins — Driver', desc: 'Skill 9 • 0 yrs experience • asks $508/shift' },
      ],
      hover: 1,
    },
    alert: {
      header: 'Hire',
      content: 'Hire **Gloria Santos** as Dispatcher?\n\nRecruiter fee: **$1,500**\nWage: **$1,368** per shift',
    },
    caption: ['Hire NPC applicants', 'A fresh pool every 30 minutes. Veterans cost more but come pre-certified.'],
  },

  '06-hire-player': {
    bg: 'office',
    input: {
      title: 'Job offer',
      fields: [
        { type: 'select', label: 'Player', required: true, value: 'Jordan_Hayes (ID 14)' },
        { type: 'select', label: 'Role', required: true, value: 'Driver' },
        { type: 'number', label: 'Wage per shift', required: true, value: '1200', focus: true },
      ],
    },
    caption: ['Hire real players', 'Offer a job to anyone standing near you. They get a pop-up to accept or decline.'],
  },

  '07-job-offer': {
    alert: {
      header: 'Job offer',
      content: '**Rourke Freight Lines** wants to hire you as a **Driver** for **$1,200** per 60-minute shift.\n\nAccept?',
      cancel: 'Decline', confirm: 'Accept',
    },
    caption: ['What the player sees', 'Accepting adds them to the roster. Wages pile up as a paycheck at the office time clock.'],
  },

  '08-training': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Training: Earl Whitfield',
      options: [
        { icon: 'certificate', title: 'HAZMAT Endorsement', desc: '$14,000 • 15 min' },
        { icon: 'certificate', title: 'Oversize Load Permit', desc: '$11,000 • 12 min' },
        { icon: 'certificate', title: 'Tanker Endorsement', desc: '$9,000 • 10 min' },
      ],
      hover: 0,
    },
    notify: [
      { type: 'success', title: 'Rourke Freight Lines', text: 'Marcus Chen completed Dispatch Certification.' },
      { type: 'success', text: 'Earl Whitfield started HAZMAT Endorsement. Done in 12m 00s.' },
    ],
    caption: ['Pay to train & certify', 'CDL, HAZMAT, Tanker, Oversize and Dispatch courses take real time. Better loads need the right certs.'],
  },

  '09-fleet': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Fleet (5/6)',
      options: [
        { icon: 'cart-shopping', title: 'Buy a truck', arrow: true },
        { icon: 'truck', title: 'JoBuilt Phantom [TC482913]', desc: 'On the road • Semi • Comprehensive', arrow: true, progress: 88, color: 'green' },
        { icon: 'truck', title: 'MTL Packer [TC107755]', desc: 'In yard • Semi • Basic Cover', arrow: true, progress: 54, color: 'yellow' },
        { icon: 'truck', title: 'JoBuilt Hauler [TC930041]', desc: 'Reserved • Semi • Comprehensive', arrow: true, progress: 97, color: 'green' },
        { icon: 'truck', title: 'Vapid Benson [TC661208]', desc: 'In yard • Box truck • Uninsured', arrow: true, progress: 19, color: 'red' },
        { icon: 'truck', title: 'Maibatsu Mule [TC245590]', desc: 'On the road • Box truck • Basic Cover', arrow: true, progress: 72, color: 'green' },
      ],
      hover: 4,
      tip: [['Condition', '19%'], ['Mileage', '412.6 km'], ['Premium', '$0 / payroll']],
    },
    caption: ['Fleet with wear & tear', 'Trucks lose condition with every km and accident. Below 25% they cannot be dispatched until repaired.'],
  },

  '10-insurance': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Insurance: TC661208',
      options: [
        { icon: 'shield-halved', title: 'Uninsured (current)', desc: 'Premium $0/payroll • covers 0% • $0 deductible', disabled: true },
        { icon: 'shield-halved', title: 'Basic Cover', desc: 'Premium $260/payroll • covers 50% • $2,500 deductible' },
        { icon: 'shield-halved', title: 'Comprehensive', desc: 'Premium $585/payroll • covers 90% • $1,000 deductible' },
      ],
      hover: 2,
    },
    notify: [{ type: 'success', title: 'Rourke Freight Lines', text: 'Insurance claim (TC482913): accident repairs #131 — +$4,210' }],
    caption: ['Per-truck insurance', 'Premiums come out with payroll. Claims pay automatically for accidents, wrecks and cargo liability.'],
  },

  '11-bid-board': {
    bg: 'office',
    ctx: {
      title: 'Bid Board — Rep 52',
      options: [
        { icon: 'trailer', title: '#151 Fuel → Paleto Globe Oil', desc: 'Up to $9,850 • 14.2 km • closes in 1m 48s', iconColor: 'lime', },
        { icon: 'trailer', title: '#149 Timber → Paleto Bay Sawmill', desc: 'Up to $5,950 • 12.7 km • closes in 2m 30s • your bid $5,100' , iconColor: 'lime'},
        { icon: 'box', title: '#153 Parcels → Strawberry Mega Mall', desc: 'Up to $2,500 • 2.1 km • closes in 3m 02s' },
        { icon: 'trailer', title: '#154 Heavy Machinery → Davis Quartz Quarry', desc: 'Up to $8,400 • 9.6 km • closes in 4m 41s' },
        { icon: 'trailer', title: '#155 Industrial Chemicals → Humane Labs', desc: 'Up to $14,300 • 11.4 km • closes in 5m 10s', disabled: true, iconColor: 'gray' },
        { icon: 'trailer', title: '#156 Refrigerated Produce → Grapeseed Farms', desc: 'Up to $6,100 • 10.9 km • closes in 6m 55s' },
      ],
      hover: 0,
      tip: [['From', 'Port of LS - Lot A'], ['Vehicle', 'Semi + trailer'], ['Certs', 'CDL Class A, HAZMAT Endorsement, Tanker Endorsement'], ['Min. reputation', '40'], ['Bids so far', '3']],
    },
    caption: ['Shared job bid board', 'Every company on the server competes for the same loads. Lowest effective bid wins, and reputation gives an edge.'],
  },

  '12-place-bid': {
    bg: 'office',
    input: {
      title: 'Bid on #151',
      fields: [{ type: 'number', label: 'Your price ($3,940 - $9,850)', required: true, value: '8650', focus: true }],
    },
    notify: [
      { type: 'success', title: 'Rourke Freight Lines', text: 'Won load #146: General Freight to Sandy Shores Airfield for $6,300. Assign a driver within 10m 00s.' },
      { type: 'error', title: 'Rourke Freight Lines', text: 'A rival outbid you on load #144.' },
    ],
    caption: ['Bid smart', 'Bid too high and rival companies win. Bid too low and you leave money on the table.'],
  },

  '13-company-loads': {
    bg: 'office',
    ctx: {
      title: 'Company loads',
      options: [
        { icon: 'truck-fast', title: '#146 General Freight → Sandy Shores Airfield', desc: 'Needs driver — 8m 12s left', iconColor: 'orange', arrow: true },
        { icon: 'truck-fast', title: '#141 Timber → Paleto Bay Sawmill', desc: 'Assigned (waiting) • Jordan Hayes', arrow: true },
        { icon: 'truck-fast', title: '#139 Vehicle Transport → Harmony Garage', desc: 'In transit • ETA 4m 51s • Dale Kowalski' },
        { icon: 'truck-fast', title: '#137 Furniture → Strawberry Mega Mall', desc: 'In transit • ETA 1m 09s • Earl Whitfield' },
        { icon: 'circle-check', title: '#131 General Freight → Senora Desert RON', desc: 'Completed • Dale Kowalski', iconColor: 'green' },
        { icon: 'circle-xmark', title: '#128 Fuel → Palmer-Taylor Power', desc: 'Failed • Earl Whitfield', iconColor: 'red' },
      ],
      hover: 0,
    },
    input: null,
    caption: ['Track every load', 'Won loads need a driver and truck. Watch ETAs, deadlines, completions and failures.'],
  },

  '14-assign': {
    bg: 'office',
    input: {
      title: 'Assign load #146',
      fields: [
        { type: 'select', label: 'Driver', required: true, value: 'Earl Whitfield (NPC, skill 58)' },
        { type: 'select', label: 'Truck', required: true, value: 'MTL Packer [TC107755] 54%' },
      ],
    },
    caption: ['Assign drivers', 'NPC drivers head out right away (simulated). Player drivers get a notification to drive it themselves.'],
  },

  '15-dispatch': {
    bg: 'office',
    input: {
      title: 'Dispatch automation',
      fields: [
        { type: 'checkbox', label: 'Dispatchers bid on loads automatically', checked: true },
        { type: 'checkbox', label: 'Dispatchers assign won loads to drivers', checked: true },
        { type: 'checkbox', label: 'Dispatchers may send loads to on-duty player drivers', checked: false },
      ],
    },
    notify: [
      { type: 'success', title: 'Rourke Freight Lines', text: 'Won load #158: Parcels to Strawberry Mega Mall for $2,150. Assign a driver within 10m 00s.' },
      { type: 'success', title: 'Rourke Freight Lines', text: 'Dale Kowalski delivered load #139. +$7,450' },
      { type: 'inform', title: 'Rourke Freight Lines', text: 'Payroll run: $8,940 (wages $6,180, insurance $1,260, upkeep $1,500).' },
    ],
    caption: ['Automate with dispatchers', 'Certified NPC dispatchers bid and assign for you. Skill decides how many loads they juggle and how well they price.'],
  },

  '16-upgrades': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Office upgrades',
      options: [
        { icon: 'mug-hot', title: 'Break Room (Lv 0/1)', desc: 'Happier staff are less likely to quit when pay is late. — next level $15,000', progress: 0 },
        { icon: 'headset', title: 'Dispatch Center (Lv 1/2)', desc: 'Each NPC dispatcher can juggle more loads. — next level $110,000', progress: 50 },
        { icon: 'chair', title: 'Office Desks (Lv 2/3)', desc: 'Room for more staff. — next level $90,000', progress: 67 },
        { icon: 'graduation-cap', title: 'Training Room (Lv 2/2)', desc: 'In-house classes make certification faster. — maxed', progress: 100, disabled: true },
        { icon: 'warehouse', title: 'Truck Yard Expansion (Lv 1/3)', desc: 'Park more trucks. — next level $75,000', progress: 33 },
      ],
      hover: 2,
    },
    caption: ['Build out the office shell', 'The office starts nearly empty. Upgrades add furniture and raise staff, fleet, training and dispatch limits.'],
  },

  '17-driving': {
    bg: 'road',
    textui: '[E] Deliver load',
    notify: [{ type: 'warning', text: 'Deadline: 14m 20s. Late deliveries pay less.' }],
    caption: ['Player drivers really drive', 'Grab the truck at the yard, hook the trailer at the port, follow the route, deliver, then bring the truck back.'],
  },

  '18-unloading': {
    bg: 'road',
    progress: { pct: 64, label: 'Unloading...' },
    notify: [{ type: 'success', text: 'Delivered! Company earned $8,650, your cut: $1,297. Return the truck to the yard.' }],
    caption: ['Validated deliveries', 'The server checks positions and travel time. Cargo damage reduces the payout, and drivers earn a commission.'],
  },

  '19-time-clock': {
    bg: 'office',
    ctx: {
      title: 'Time clock',
      options: [
        { icon: 'clock', title: 'Clock out', desc: 'Stop receiving loads from dispatch' },
        { icon: 'money-check-dollar', title: 'Collect paycheck', desc: '$2,400' },
        { icon: 'truck-fast', title: '#141 Timber → Paleto Bay Sawmill', desc: 'Truck TC930041 waiting • 12.7 km • due in 21m 40s' },
        { icon: 'door-open', title: 'Leave the company', iconColor: 'red' },
      ],
      hover: 2,
    },
    notify: [{ type: 'inform', title: 'Rourke Freight Lines', text: 'New load #141: Timber from Port of LS - Lot B to Paleto Bay Sawmill. Truck TC930041 is waiting at the yard.' }],
    caption: ['Time clock for player staff', 'Clock in for dispatch and wages, collect paychecks and start your assigned loads (/truckjob).'],
  },

  '20-finances': {
    bg: 'office',
    ctx: {
      back: true,
      title: 'Ledger',
      options: [
        { icon: 'circle-plus', iconColor: 'green', title: '+$7,450', desc: 'Load #139 delivered • 02 Nov 21:14' },
        { icon: 'circle-minus', iconColor: 'red', title: '-$1,297', desc: 'Driver commission load #151 • 02 Nov 21:09' },
        { icon: 'circle-plus', iconColor: 'green', title: '+$8,650', desc: 'Load #151 delivered • 02 Nov 21:09' },
        { icon: 'circle-minus', iconColor: 'red', title: '-$6,180', desc: 'Payroll (7 staff) • 02 Nov 21:00' },
        { icon: 'circle-minus', iconColor: 'red', title: '-$1,260', desc: 'Insurance premiums (5 trucks) • 02 Nov 21:00' },
        { icon: 'circle-minus', iconColor: 'red', title: '-$1,500', desc: 'Property upkeep • 02 Nov 21:00' },
        { icon: 'circle-plus', iconColor: 'green', title: '+$4,210', desc: 'Insurance claim (TC482913): accident repairs #131 • 02 Nov 20:47' },
        { icon: 'circle-minus', iconColor: 'red', title: '-$14,000', desc: 'Training: Earl Whitfield - HAZMAT Endorsement • 02 Nov 20:40' },
      ],
    },
    caption: ['Full company ledger', 'Every dollar in and out: deliveries, payroll, premiums, claims, training, trucks and upgrades.'],
  },
};
