"""
Rough economy model for bdev-trucking-company: estimates hourly gross / costs / net
for small, mid and maxed NPC-run companies and for one player driving by hand,
using the pickup/destination/collection coordinates and cargo payMults from a config.lua.

    python3 docs/tools/economy-sim.py config.lua "my settings" '{"rate":200,"fuelKm":12}'

Keys you can override (JSON, 3rd arg) mirror config values: rate (ratePerKm), minPay,
msChance/msMax/msBonus (multi-stop), expChance/expMult (express), npcKmMin (NPC kmPerMinute),
npcFixedMin (loadMinutes), stopMin (stopMinutes), fuelKm, perLoad (loadFee), npcOpsMult,
wear (wearPerKm), repair (repairCostPerPoint), wageSkill (wagePerSkill), insFull (premiumPct),
upkeep, cap (hourlySoftCap), overCap (overCapPayMult). Pass "cur" in the 2nd arg for the
pre-1.3 values. It ignores accidents, idle time and lost bids, so real income is a bit lower.
"""
import re, random, math, sys, statistics
cfg = open(sys.argv[1]).read()
def coords(block):
    i = cfg.index(block); j = cfg.index('}\n', cfg.index('\n}', i)) if False else cfg.index('\n}', i)
    return [tuple(map(float, m)) for m in re.findall(r'vec[34]\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)', cfg[i:j])]
P = coords('Config.Pickups = {'); D = coords('Config.Destinations = {'); C = coords('Config.CollectionPoints = {')
d2 = lambda a, b: math.dist(a[:2], b[:2])
CARGO = {k: (float(m), int(r)) for k, m, r in re.findall(r"(\w+)\s*=\s*\{ label = '[^']+',\s*class = '\w+',.*?payMult = ([\d.]+), minRep = (\d+)", cfg)}

def run(S, label):
    random.seed(1)
    loads = []
    for _ in range(4000):
        cargo = random.choice(list(CARGO)); mult, minrep = CARGO[cargo]
        p, d = random.choice(P), random.choice(D)
        stops = random.sample(C, random.randint(1, S['msMax'])) if random.random() < S['msChance'] else []
        m, prev = 0, p
        for s in stops: m += d2(prev, s); prev = s
        m += d2(prev, d); km = m * 1.35 / 1000
        exp = random.random() < S['expChance']
        pay = max(S['minPay'], km * S['rate'] * mult * (1 + S['msBonus'] * len(stops)) * (S['expMult'] if exp else 1))
        pay *= random.uniform(0.9, 1.15)
        loads.append(dict(km=km, pay=pay * 0.85, minrep=minrep, stops=len(stops)))   # ~15% under max pay to win bids
    def company(trucks, rep, label2):
        ok = [l for l in loads if l['minrep'] <= rep]
        ok.sort(key=lambda l: -l['pay']); pool = ok[:max(1, len(ok) // 2)]  # dispatch picks the better half
        avg_pay = statistics.mean(l['pay'] for l in pool); avg_km = statistics.mean(l['km'] for l in pool); avg_stops = statistics.mean(l['stops'] for l in pool)
        mins = avg_km / S['npcKmMin'] * 1.0 + S['npcFixedMin'] + avg_stops * S['stopMin'] + 3  # +3 min assignment latency
        runs_hr = 60 / mins
        gross = trucks * runs_hr * avg_pay
        truck_price = 135000
        ops = trucks * runs_hr * (avg_km * S['fuelKm'] * S['npcOpsMult'] + S['perLoad'])
        repairs = trucks * runs_hr * avg_km * S['wear'] * truck_price * S['repair']
        disp = 1 if trucks <= 3 else (2 if trucks <= 6 else 3)
        wages = trucks * (400 + 50 * S['wageSkill']) + disp * (600 + 60 * S['wageSkill'])
        ins = trucks * truck_price * S['insFull']
        upkeep = S['upkeep']
        cap = S.get('cap')
        if cap and gross > cap: gross = cap + (gross - cap) * S['overCap']
        net = gross - ops - repairs - wages - ins - upkeep
        print(f"  {label2:<38} gross/hr {gross:>9,.0f}  costs {ops+repairs+wages+ins+upkeep:>8,.0f}  NET/hr {net:>9,.0f}   ({runs_hr:.1f} runs/truck/hr, avg load {avg_pay:,.0f})")
    print(label)
    company(2, 40, 'small: 2 NPC trucks, rep 40')
    company(5, 60, 'mid: 5 NPC trucks, rep 60')
    company(12, 100, 'maxed: 12 NPC trucks, rep 100')
    # one player driving premium loads by hand (~1.5 km/min + 10 min handling)
    ok = sorted([l for l in loads if l['minrep'] <= 100], key=lambda l: -l['pay'])[:len(loads)//4]
    ap = statistics.mean(l['pay'] for l in ok); ak = statistics.mean(l['km'] for l in ok); st = statistics.mean(l['stops'] for l in ok)
    rph = 60 / (ak / 1.5 + 10 + st * 2)
    print(f"  {'one player driving top loads':<38} gross/hr {rph*ap:>9,.0f}  ({rph:.1f} loads/hr, avg {ap:,.0f})")

CUR = dict(rate=350, minPay=2500, msChance=.3, msMax=3, msBonus=.25, expChance=.15, expMult=1.5, npcKmMin=1.2, npcFixedMin=0, stopMin=0,
           fuelKm=0, perLoad=0, npcOpsMult=1, wear=.25, repair=.0015, wageSkill=12, insFull=.009, upkeep=1500)
NEW = dict(rate=200, minPay=1200, msChance=.25, msMax=3, msBonus=.10, expChance=.12, expMult=1.25, npcKmMin=0.8, npcFixedMin=5, stopMin=3,
           fuelKm=12, perLoad=150, npcOpsMult=1.5, wear=.3, repair=.0018, wageSkill=15, insFull=.006, upkeep=2000, cap=75000, overCap=.3)
# premium multipliers are flattened in the proposed config file; this script reads payMult from whichever config is passed
import json
if len(sys.argv) > 3: NEW.update(json.loads(sys.argv[3]))
run(CUR if 'cur' in sys.argv[2] else NEW, sys.argv[2])
