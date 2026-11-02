# bdev-trucking-company

Player-owned trucking companies for **Qbox (qbx_core)** FiveM servers.

Buy a depot down by the docks, build out the empty office shell, hire staff (NPCs **and** real players), pay to train and certify them, buy and insure a fleet, win loads on a shared bid board and hand the busywork to dispatchers.

![Overview](docs/screenshots/00-overview.jpg)

## Screenshots

> UI mockups of the in-game menus (ox_lib / ox_target style), using the resource's real menu text and default config values. Source and generator are in [`docs/mockups`](docs/mockups).

| | |
|---|---|
| ![Buy a depot](docs/screenshots/01-buy-property.jpg) **Buy a depot at the docks** | ![Management](docs/screenshots/03-management.jpg) **Company management laptop** |
| ![Employees](docs/screenshots/04-employees.jpg) **NPC + player staff** | ![Applicants](docs/screenshots/05-applicants.jpg) **Hire NPC applicants** |
| ![Hire a player](docs/screenshots/06-hire-player.jpg) **Hire real players** | ![Job offer](docs/screenshots/07-job-offer.jpg) **The job offer players receive** |
| ![Training](docs/screenshots/08-training.jpg) **Pay to train & certify** | ![Fleet](docs/screenshots/09-fleet.jpg) **Fleet with wear & tear** |
| ![Insurance](docs/screenshots/10-insurance.jpg) **Per-truck insurance** | ![Bid board](docs/screenshots/11-bid-board.jpg) **Shared job bid board** |
| ![Place bid](docs/screenshots/12-place-bid.jpg) **Bidding** | ![Loads](docs/screenshots/13-company-loads.jpg) **Company loads** |
| ![Assign](docs/screenshots/14-assign.jpg) **Assign driver + truck** | ![Dispatch](docs/screenshots/15-dispatch.jpg) **Dispatch automation** |
| ![Upgrades](docs/screenshots/16-upgrades.jpg) **Build out the office shell** | ![Time clock](docs/screenshots/19-time-clock.jpg) **Time clock for player staff** |
| ![Driving](docs/screenshots/17-driving.jpg) **Player drivers really drive** | ![Unloading](docs/screenshots/18-unloading.jpg) **Validated deliveries** |
| ![Ledger](docs/screenshots/20-finances.jpg) **Full company ledger** | ![Found company](docs/screenshots/02-found-company.jpg) **Name your company** |

## Features

| Area | What you get |
|---|---|
| **Property** | 3 dock-side depots for sale (configurable). One company per property, with a blip that shows the company name. Each company's office is in its own routing bucket. |
| **Office shell** | Starts nearly empty: a crate, a laptop and a screen. Office upgrades add furniture *and* gameplay effects: more staff desks, a bigger truck yard, a faster training room, a dispatch center, a break room. Works with vanilla interiors or K4MB1-style shell props. |
| **Employees** | NPC applicants (random names, skill, experience, asking wage), refreshed every 30 min. Player hires go through an invite the other player accepts. Roles: Driver, Dispatcher, Manager (players only). You can change roles and wages, or fire people. The owner can join their own roster and drive. |
| **Training** | Paid certification courses that take real time: CDL Class A, HAZMAT, Tanker, Oversize, Dispatch. Loads need the right certs. Courses can require other courses first. |
| **Fleet** | Box trucks (Mule, Benson, Pounder) and semis (Packer, Hauler, Phantom). Trucks track condition and mileage and wear out. Pay for repairs, sell at resale value. Trucks below 25% condition can't be dispatched. |
| **Insurance** | Per-truck policy: Uninsured, Basic or Comprehensive. Premiums come out every payroll cycle. Claims pay automatically for accident repairs, wrecked trucks and cargo liability (coverage % minus a deductible). |
| **Bid board** | Shared across every company. Loads cover different cargo (parcels → chemicals) with cert and reputation gates. You bid a price, and the lowest *effective* bid wins: reputation gives an edge, and a hidden "rival" bid stops everyone just bidding the max. |
| **Loads** | Won loads get a driver and truck within the accept window, then have a delivery deadline. Late deliveries pay less and cost reputation. Failed or abandoned loads charge a liability penalty. |
| **NPC drivers** | Simulated on the server. Trip time depends on distance, skill and truck condition. Accident rolls (better skill and a healthier truck mean fewer). A severe accident loses the load. Skill grows with every load. Survives server restarts. |
| **Player drivers** | Real driving. Pick up the truck at the yard, hook the trailer at the port (or load a box truck), deliver, and return the truck. The server checks positions and minimum travel time, and cargo damage cuts the payout. Drivers get a commission plus their wage. |
| **Dispatchers** | Certified NPC dispatchers automatically **bid** on loads you can cover and **assign** won loads to idle qualified drivers (NPC first, then on-duty players). Their capacity scales with skill and the Dispatch Center upgrade, and better dispatchers price bids more accurately. You can toggle each behaviour. Player dispatchers and managers do the same work by hand. |
| **Payroll** | Every 60 min (configurable): NPC wages, player wages (only if they clocked in that cycle) paid as a paycheck collected at the time clock, insurance premiums and property upkeep. Below the overdraft limit the company is suspended, and unpaid NPCs may quit. |
| **Finances** | Deposit (owner/manager), withdraw (owner), and a full ledger of every transaction. |

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
4. **Check the coordinates in `config.lua`.** The depot entrances, truck spawns, pickup lots and destinations are sensible defaults, but you should check them on your map (especially if you run dock MLOs). Stand where you want a point and use `/truckco_pos` (admin) to copy a `vec4`.

## How to play

1. **Buy a depot**: go to a green truck blip at the docks → *View property* → *Buy*. The price comes from your bank.
2. **Fund the company**: laptop → *Finances* → *Deposit*. Everything the company buys comes from its own account.
3. **Buy a truck** (*Fleet* → *Buy a truck*) and **insure it**.
4. **Hire**: laptop → *Hire staff*. Pick NPC applicants, or offer a job to a player standing next to you.
5. **Train**: *Employees* → pick someone → *Train / certify*. Semi loads need a CDL. Dispatchers need Dispatch Certification before they automate anything.
6. **Bid**: walk to the bid board (or use `/truckboard`) and bid on loads. When bidding closes, the winner is notified.
7. **Assign**: *Company loads* → a load marked "Needs driver" → pick a driver and truck. NPCs leave at once. Players get a notification.
8. **Drive it yourself** (player drivers): go to the depot → *My loads* (or `/truckjob`) → start the load. The truck spawns in the yard. Follow the route, hook the trailer, deliver, then bring the truck back.
9. **Automate**: hire and certify a dispatcher, then set *Dispatch automation* the way you want it.

### Commands

| Command | Who | What |
|---|---|---|
| `/truckjob` | employees | Time clock: clock in/out, paycheck, start assigned loads |
| `/truckboard` | staff | Open the bid board remotely |
| `/truckco_cancel` | driver | Abandon the current load (recovery fee) |
| `/truckco_pos` | admin | Copy your current `vec4` for config |
| `/truckco_board [n]` | admin | Force-generate contracts |
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

### Using a shell instead of a vanilla interior

Uncomment the `office_shell` example in `Config.Interiors`, set its `model` to your shell (e.g. `shell_office1`), adjust the offsets, and set a property's `interior = 'office_shell'`.

## Notes

- Company money is stored in SQL and changed with atomic `UPDATE`s, so two people spending at once can't overdraw it.
- The hidden rival bid is never sent to clients.
- Player run actions (`loaded`, `deliver`, `returnTruck`) are checked on the server against entity positions, and deliveries have a minimum travel time.
- If a player disconnects mid-load, the truck is recovered for a fee. If the deadline allows, the load goes back to the company to reassign; otherwise it fails.
- Paychecks for players are held at the time clock. When a player is fired while offline, the script tries `exports.qbx_core:AddMoney(citizenid, ...)` and logs if that fails.
