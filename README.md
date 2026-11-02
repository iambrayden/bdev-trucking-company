# bdev-trucking-company

Player-owned trucking companies for **Qbox (qbx_core)** FiveM servers.

Buy a depot down by the docks, build out the empty office shell, hire staff (NPCs **and** real players), pay to train and certify them, buy and insure a fleet, win loads on a shared bid board and hand the busywork to dispatchers.

![Overview](docs/screenshots/00-overview.jpg)

## Screenshots

> The tablet screens are rendered from the resource's real `html/` UI with mock data (over an in-game office shot). The job-offer pop-up and driving HUD are ox_lib-style mockups. Regenerate them all with [`docs/mockups`](docs/mockups).

| | |
|---|---|
| ![Dashboard](docs/screenshots/01-dashboard.jpg) **Company tablet** | ![Finances](docs/screenshots/02-finances.jpg) **Company finances & ledger** |
| ![Bid board](docs/screenshots/03-bid-board.jpg) **Shared bid board** | ![Loads](docs/screenshots/04-loads.jpg) **Company loads** |
| ![Assign](docs/screenshots/05-assign.jpg) **Assign driver + truck** | ![Staff](docs/screenshots/06-staff.jpg) **Staff, training, roles & wages** |
| ![Hiring](docs/screenshots/07-hiring.jpg) **Hire NPC applicants or players** | ![Fleet](docs/screenshots/08-fleet.jpg) **Fleet, wear, repairs & insurance** |
| ![Dealer](docs/screenshots/09-truck-dealer.jpg) **Truck dealer** | ![Upgrades](docs/screenshots/10-office-upgrades.jpg) **Build out the office shell** |
| ![Dispatch](docs/screenshots/11-dispatch.jpg) **Dispatch automation** | ![My shift](docs/screenshots/12-my-shift.jpg) **Driver shift: clock in, paycheck, loads** |
| ![Buy property](docs/screenshots/13-buy-property.jpg) **Buy a depot** | ![Job offer](docs/screenshots/14-job-offer.jpg) **Job offer pop-up for hired players** |
| ![Driving](docs/screenshots/15-driving.jpg) **Player drivers really drive** | ![Unloading](docs/screenshots/16-unloading.jpg) **Validated deliveries** |
| ![Sign](docs/screenshots/17-sign.png) **Exterior company sign (rendered in-world)** | ![Job panel](docs/screenshots/17-job-panel.jpg) **On-screen job panel while driving a load** |

## Features

| Area | What you get |
|---|---|
| **Property** | 3 dock-side depots for sale (configurable). One company per property, with a blip that shows the company name. Each company's office is in its own routing bucket. |
| **Company tablet** | Everything is managed on an in-game tablet (NUI) with an animation and prop: dashboard, finances, bid board, loads, staff, hiring, fleet, office upgrades, dispatch, driver shift and owner tools. Open it from the office laptop, the bid board screen, or `/trucktablet` anywhere (configurable). |
| **Office shell** | Starts nearly empty: a crate, a laptop and a screen. Office upgrades add furniture *and* gameplay effects: more staff desks, a bigger truck yard, a faster training room, a dispatch center, a break room. Works with vanilla interiors or K4MB1-style shell props. |
| **Employees** | NPC applicants (random names, skill, experience, asking wage), refreshed every 30 min. Player hires go through an invite the other player accepts. Roles: Driver, Dispatcher, Manager (players only). You can change roles and wages, or fire people. The owner can join their own roster and drive. |
| **Training** | Paid certification courses that take real time: CDL Class A, HAZMAT, Tanker, Oversize, Dispatch. Loads need the right certs. Courses can require other courses first. |
| **Fleet** | Box trucks (Mule, Benson, Pounder) and semi tractors (Packer, Hauler, Phantom). **Trailers aren't bought**: the customer's trailer is waiting at the pickup and the driver hooks it up. Trucks track condition and mileage and wear out. Pay for repairs, sell at resale value. Trucks below 25% condition can't be dispatched. |
| **Insurance** | Per-truck policy: Uninsured, Basic or Comprehensive. Premiums come out every payroll cycle. Claims pay automatically for accident repairs, wrecked trucks and cargo liability (coverage % minus a deductible). |
| **Bid board** | Shared across every company. Loads cover different cargo (parcels → chemicals) with cert and reputation gates. You bid a price, and the lowest *effective* bid wins: reputation gives an edge, and a hidden "rival" bid stops everyone just bidding the max. |
| **Loads** | Won loads get a driver and truck within the accept window, then have a delivery deadline. Late deliveries pay less and cost reputation. Failed or abandoned loads charge a liability penalty. |
| **NPC drivers** | Simulated on the server. Trip time depends on distance, skill and truck condition. Accident rolls (better skill and a healthier truck mean fewer). A severe accident loses the load. Skill grows with every load. Survives server restarts. |
| **Player drivers** | Real driving. Pick up the truck at the yard, hook the trailer at the port (or load a box truck), deliver, and return the truck. The server checks positions and minimum travel time, and cargo damage cuts the payout. Drivers get a commission plus their wage. |
| **Dispatchers** | Certified NPC dispatchers automatically **bid** on loads you can cover and **assign** won loads to idle qualified drivers (NPC first, then on-duty players). Their capacity scales with skill and the Dispatch Center upgrade, and better dispatchers price bids more accurately. You can toggle each behaviour. Player dispatchers and managers do the same work by hand. |
| **Payroll** | Every 60 min (configurable): NPC wages, player wages (only if they clocked in that cycle) paid as a paycheck collected at the time clock, insurance premiums and property upkeep. Below the overdraft limit the company is suspended, and unpaid NPCs may quit. |
| **Exterior signs** | Owners/managers place up to 3 signs with the company name outside the depot (tablet → Office → *Place signs*). 4 styles, visible to everyone, renamed automatically with the company. |
| **Imperial CAD** | Company trucks are registered in Imperial CAD when bought (`CreateVehicleAdvanced`), so plate checks show the company, registration and insurance. `/truckco_cadsync` registers existing trucks. |
| **Multi-stop jobs** | About 30% of contracts are collection runs: load at the pickup, collect more cargo at 1–3 extra stops around the map, then deliver. Each extra stop adds 25% pay. The job panel and GPS walk the driver through every stop; NPC drivers run them too. |
| **Premium & express jobs** | High-reputation cargo pays far more: electronics, pharmaceuticals, exotic cars, wind-turbine blades (oversize) and mining explosives (hazmat), at up to 3.4× pay. About 15% of contracts are **Express**: 1.5× pay with a 40% shorter deadline. |
| **Bonuses** | Owners and managers can pay a player employee a bonus with a reason (Staff → Give a bonus). It comes from company funds, goes straight to their bank (or their paycheck if they're offline), and is recorded in the ledger. |
| **Loans** | The owner can borrow from the bank (Finances → Business loans). The limit is `baseLimit + reputation × perRep`, with flat interest, repaid automatically in instalments each payroll. Pay off early any time; it must be cleared before selling the company. |
| **Finances** | Each company has its own account (`truckco_companies.balance`), separate from players' banks. Fund it with deposits (owner/manager), take profit out with withdrawals (owner), and audit every transaction in the ledger. All purchases, wages, premiums, claims and payouts go through it. Tablet → **Finances**. |

## Requirements

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_target](https://github.com/overextended/ox_target)
- Optional: `qbx_vehiclekeys` (keys), `ox_fuel` (statebag fuel). Both are adaptable in `config.lua` (`Config.GiveKeys`, `Config.SetFuel`).

## Install

1. Drop the folder into your resources, e.g. `resources/[jobs]/bdev-trucking-company`.
2. Add `ensure bdev-trucking-company` to `server.cfg` **after** qbx_core, ox_lib, oxmysql and ox_target.
3. Start the server. Tables are created automatically from `sql/install.sql`, or you can run that file yourself.
4. **Set things up in-game; no config editing needed.** As an admin, run `/truckco_furnish`:
   - **Outside, near a depot:** move the depot entrance, and set the default truck pickup and return spots, all where you're standing.
   - **Inside an office:** arrange the default furniture, and set the default exit door, arrival point and time clock.

   Everything saves to the database. Owners can still customise their own office from the tablet.
5. **Optional:** the coordinates in `config.lua` are only the fallback. The depot entrances, truck spawns, pickup lots and destinations are sensible defaults, but you should check them on your map (especially if you run dock MLOs). Stand where you want a point and use `/truckco_pos` (admin) to copy a `vec4`.

## How to play

1. **Buy a depot**: go to a green truck blip at the docks → *View property*, name your company and buy. The price comes from your personal bank.
2. **Fund the company**: tablet → *Finances* → *Deposit*. Everything the company buys comes from its own account.
3. **Buy a truck** (tablet → *Fleet* → *Buy a truck*) and **insure it** (insurance dropdown on each truck).
4. **Hire**: tablet → *Hiring*. Pick NPC applicants, or offer a job to a player standing next to you.
5. **Train**: *Staff* → pick someone → *Training*. Semi loads need a CDL. Dispatchers need Dispatch Certification before they automate anything.
6. **Bid**: open the *Bid Board* (office screen or `/truckboard`) and bid on loads. When bidding closes, the winner is notified.
7. **Assign**: *Loads* → *Assign* on a load marked "Needs driver" → pick a driver and truck. NPCs leave at once. Players get a notification.
8. **Drive it yourself** (player drivers): when a load is assigned you get a notification with the pickup, drop-off, truck and deadline. Go to the depot yard and either press *Start load* in *My shift* (`/truckjob`), or use the **Company garage** target, which starts your assigned load for you. The truck spawns with a GPS route, and an on-screen panel shows each step (pickup → delivery → return truck), the distance, time left and your cut.
9. **Automate**: hire and certify a dispatcher, then set *Dispatch* the way you want it.

### Commands

| Command | Who | What |
|---|---|---|
| `/trucktablet` | owners & employees | Open the company tablet (`Config.Tablet.command`). Bindable in Settings → Key Bindings → FiveM |
| `/truckjob` | employees | Tablet → My shift: clock in/out, paycheck, start assigned loads |
| `/truckboard` | staff | Tablet → Bid board |
| `/truckload` | driver | Re-show the current delivery step and reset the GPS |
| `/truckco_cancel` | driver | Abandon the current load (recovery fee) |
| `/truckco_signtest` | anyone | Draw a test sign in front of you for 30s (render check) |
| `/truckco_pos` | admin | Copy your current `vec4` for config |
| `/truckco_furnish` | admin | In-game defaults saved to the database. Outside: move a depot entrance, set truck pickup/return. Inside: default furniture, exit, arrival point, time clock |
| `/truckco_board [n]` | admin | Force-generate contracts |
| `/truckco_cadsync` | admin | Register all existing company trucks in Imperial CAD |
| `/truckco_givefunds <companyId> <amount>` | admin | Adjust a company balance |

## Permissions

| | Owner | Manager | Dispatcher | Driver |
|---|:-:|:-:|:-:|:-:|
| View company / board / loads | ✅ | ✅ | ✅ | ✅ |
| Bid & assign loads | ✅ | ✅ | ✅ | |
| Hire / fire / train / set wages | ✅ | ✅ | | |
| Fleet, insurance, upgrades, automation settings | ✅ | ✅ | | |
| Deposit / ledger | ✅ | ✅ | | |
| Withdraw, rename, sell, promote managers | ✅ | | | |

Edit `TCShared.Perms` in `shared/utils.lua` to change this.

## Tuning

Everything economic lives in `config.lua`:

- `Config.Board`: pay per km, bid windows, accept window, deadlines, late/fail penalties, reputation effects, how many loads are on the board.
- `Config.NPC`: applicant pool, wages, simulated speed, accident odds, quit chance.
- `Config.Fleet` / `Config.Trucks` / `Config.Insurance`: prices, wear, repair costs, policies.
- `Config.Dispatch`: dispatcher tick rate and capacity.
- `Config.Payroll`: payroll interval, overdraft limit, whether player wages need clocking in.
- `Config.Upgrades`: office upgrades and their effects. The matching furniture props are in `Config.Interiors[...].furniture`.

### Arranging the office (in-game, no config)

Owners and managers set up their own depot from tablet → **Office** → **Office setup**:

- **Inside:** *Arrange furniture*, and set the **exit door**, **arrival point** and **time clock** where you're standing. *Reset to default* puts everything back.
- **Outside:** set the **truck pickup spot** (sit in a vehicle to use its position and facing) and the **truck return spot** where you're standing.

Everything is saved for the company and applies right away for everyone inside.

Positions resolve as: **company choice → admin default (set with `/truckco_furnish`, stored in the database) → `config.lua`**.

Furniture editor keys:

| Key | Action |
|---|---|
| Aim at a prop + **E** or **left-click** | Pick it up / put it down (it's outlined and labelled when aimed at) |
| Aim | Props sit on floors and desks, and mount flush on walls (TV / board) |
| **Scroll** | Rotate (hold **Shift** for 1° steps) |
| **↑ / ↓** | Raise / lower |
| **Backspace** | Put the held prop back, or leave without saving |
| **Enter** | Save |

Anything stacked on a prop (the laptop on the desk) moves with it. Only the items you actually move are saved; everything else keeps following the default layout. To start over, use *Reset to default*.

### Company garage

Staff (owner, managers, dispatchers and drivers; configurable in `Config.Garage.roles`) can take company trucks out for free driving:

1. Go to the **truck pickup spot** at the yard and use the **Company garage** target (or tablet → **Fleet**), then press **Take out** on an available truck. It spawns at the pickup spot with keys and fuel.
2. When you're done, drive it to the **truck return spot** and press **E** to park it. You can also use *Park company truck* on the garage target.

Damage is recorded on the truck's condition. A truck that's taken out can't be assigned to loads until it's parked. If it's lost (destroyed, or the driver disconnects), it goes back to the yard and the company pays the recovery fee.

### Exterior signs

Stand outside your depot: tablet → **Office** → **Place signs**.

| Key | Action |
|---|---|
| Aim | A preview sign follows your aim (red label = too far from the depot) |
| **E** or **left-click** | Place a new sign at the preview, or pick up the sign you're aiming at / put it down |
| **Scroll** | Rotate (Shift = fine) |
| **↑ / ↓** | Pole height: raise / lower the panel; the posts always reach the ground (Shift = fine) |
| **Q** | Change style |
| **X** | Delete the held sign |
| **Backspace** | Put it back / leave without saving |
| **Enter** | Save (new signs are charged then) |

Nothing showing? Run `/truckco_signtest` to draw a test sign in front of you; it also reports whether your client supports textured signs (otherwise a plain panel with the name in 3D text is used).

### Imperial CAD

With `Config.ImperialCAD.enabled = true` and the `ImperialCAD` resource running, each truck bought is registered with plate, make/model, registration and the insurance chosen at purchase. `owner = 'company'` registers it to the company; `owner = 'owner'` to the owner's character (citizenid as SSN). Imperial has no update/delete export, so later insurance changes and sold trucks are not reflected in the CAD.

### Leaving the office

Walk to the orange door marker and press **E**. You can also use the ox_target spot there, or *Leave office* on the tablet. Move the exit onto the actual door with tablet → Office → *Exit door → Set here* (or `/truckco_furnish` for everyone's default).

### Using a shell instead of a vanilla interior

Uncomment the `office_shell` example in `Config.Interiors`, set its `model` to your shell (e.g. `shell_office1`), adjust the offsets, and set a property's `interior = 'office_shell'`.

## Updating & troubleshooting

- **Always replace the whole folder** when updating, then run in the server console:
  ```
  refresh
  ensure bdev-trucking-company
  ```
  FiveM caches `fxmanifest.lua` until you `refresh`. A plain `restart` / `ensure` silently skips any newly added files, and you get errors like `attempt to call a nil value (field 'openTablet')`.
- **Keeping your own `config.lua` is fine.** Anything an older config is missing is filled in from `shared/defaults.lua`, and the server console lists which sections were filled so you can copy them over.
- On start the server console prints `bdev-trucking-company v… loaded`, or `NOT LOADED: <files>` if something was skipped.
- Blips and door targets come from the config immediately. If they're missing, the client script itself didn't load, so check F8.

## Notes

- Company money is stored in SQL and changed with atomic `UPDATE`s, so two people spending at once can't overdraw it.
- The hidden rival bid is never sent to clients.
- Player run actions (`loaded`, `deliver`, `returnTruck`) are checked on the server against entity positions, and deliveries have a minimum travel time.
- If a player disconnects mid-load, the truck is recovered for a fee. If the deadline allows, the load goes back to the company to reassign; otherwise it fails.
- Paychecks for players are held at the time clock. When a player is fired while offline, the script tries `exports.qbx_core:AddMoney(citizenid, ...)` and logs if that fails.
