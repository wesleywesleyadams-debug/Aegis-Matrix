# Stardust Dominion — Defense layers, ship variants and the Weapons Depot

Reference for the combat design. In game it is the Codex screen
(title menu > Codex > Combat), which builds these tables from the same data at
runtime. A color-coded version with the ship sprites is
`docs/ship-variants.html` (open it in a browser). Numbers live in `scripts/game/Defs.gd`
(`SHIPS`, `VARIANTS`, `VARIANTS_OF`, `WEAPONS_DEPOT`, `LAYER_COLORS`); the damage
maths is in `SpaceEntity.take_damage`.

## Defense layers

Damage drains **shields → armor → hull**. A ship dies when its hull hits 0.

| Layer | Color | Regenerates | Notes |
|---|---|---|---|
| Shields | light blue | yes, costs a little energy | drained inside spice nebulae |
| Armor | red | **no** | only a Repair Tender restores it |
| Hull | green | no | Repair Tender heals hull first, then armor |

Each generalist leans on a different layer (same total toughness), which is what
makes specialists worth building:

| Ship | Shield | Armor | Hull | Leans on |
|---|---|---|---|---|
| Corvette | 30 | 20 | 70 | hull |
| Destroyer | 140 | 40 | 120 | shields |
| Cruiser | 150 | 360 | 250 | armor |
| Starbase | 1500 | 1200 | 2800 | hull (and shields) |

## Variants

Generalists deal full damage to every layer. Specialists are variants of a
generalist: they either hit one layer harder (for less base damage) or skip
layers entirely (for much less base damage). **Every variant costs the same as
its generalist.**

| Variant | Effect | Base damage | Shots | Markings |
|---|---|---|---|---|
| Generalist | full damage to all layers | 100% | yellow lasers | none |
| **Plasma** | x3.0 vs **shields** | 80% | light blue | one solid line down the spine |
| **Breacher** | x2.5 vs **armor** | 80% | red | two ribs across the hull |
| **Ravager** | x2.2 vs **hull** | 80% | green | saw teeth along both edges |
| **Slip** | **ignores shields** (armor + hull) | 70% | orange V-shots | two stripes either side of the spine |
| **Disruptor** | **ignores shields and armor** (hull only) | 35% | purple V-shots | a row of V chevrons |

Hull markings are always drawn in the owner's player color, so the pattern alone
names the variant (one line, two ribs, saw teeth, two stripes, chevrons); the
shot color names the layer it hits. Cruisers fire
torpedoes in the same colors (only lasers get the V shape). Against planets,
piercing shots skip the planetary shield, Plasma hits it harder, and Ravager kills
population faster.

## Which variant against what

Base damage needed to destroy a target, relative to a generalist
(1.00 = the same, lower = kills faster):

| Target | Plasma | Breacher | Ravager | Slip | Disruptor |
|---|---|---|---|---|---|
| Corvette (hull-heavy) | 1.08 | 1.14 | **0.91** | 1.16 | 1.47 |
| Destroyer (shield-heavy) | **0.93** | 1.16 | 1.01 | **0.82** | 1.00 |
| Cruiser (armor-heavy) | 1.12 | **0.93** | 1.06 | 1.24 | **0.82** |
| Starbase | 1.06 | 1.10 | **0.95** | 1.12 | 1.27 |

- Ravager: corvette swarms, starbases.
- Plasma / Slip: shield-heavy fleets. Slip also ignores shield regeneration.
- Breacher / Disruptor: armor-heavy fleets (Cruisers).
- Wrong target: 5-46% worse than a plain generalist, so scouting decides.

## Weapons Depots

Starbases build generalists only; every specialist is refitted at a depot.

- Built by a **Constructor** (its panel buttons, or their grid keys): 250 minerals + 20
  spice over 30 s. No weapons, and losing one doesn't lose the match.
- **There are five depot types, one per variant**: a Plasma Depot refits
  generalists into Plasma ships, a Slip Depot into Slip ships, and so on. A depot
  wears its owner's color and carries its variant's marking pattern.
- Send ships in by right-clicking the depot (or with the refit buttons in the
  ship panel). They fly in and **dock — 10 at a time, hidden and safe inside**
  — and are refitted automatically as minerals allow.
- Cost and time are per hull:

| Hull | Refit cost | Refit time |
|---|---|---|
| Corvette | 5 minerals | 15 s |
| Destroyer | 10 minerals | 25 s |
| Cruiser | 15 minerals | 35 s |

- A refit with no minerals to pay for it **waits**, and the ship stays inside
  until you cancel it; **cancelling ejects the ship unchanged**, still a
  generalist (minerals already spent are lost).
- **A specialist can never be refitted again** — the choice is permanent.
- **A depot destroyed with ships inside** throws them clear, each losing 60% of
  its shields, armor and hull.
- The AI builds the depot its intel calls for, then refits by kill-cost maths
  against the enemy warships its sensors have actually seen.

## Defense research

Three lines on the research screen's **Defenses** tab, expensive on purpose:

| Tier | Shields | Armor | Hull | Cost |
|---|---|---|---|---|
| 1 | Deflector Arrays +20% (unlocks Heat Shield Frigate) | Composite Plating +20% | Reinforced Frames +15% (unlocks Repair Tender) | 1500 energy + 40 spice, 120 s |
| 2 | Phase Shields +25% | Reactive Armor +25% | Nanite Plating +20% | 3000 energy + 100 spice, 180 s |
| 3 | Aegis Matrix +35% | Neutronium Armor +35% | Adaptive Hulls +30% | 5000 energy + 250 spice, 240 s |

## Ideas not built yet

- Variants for the job ships (Heat Shield Frigate, Repair Tender, and the
  planned Pathfinder, Storm Rider, Interdictor, Siege Monitor, Carrier,
  Battleship).
- Weapon types beyond lasers/torpedoes per specialist.
- Carrier hangars (small ships land to repair and reload) and munitions that
  need restocking at a starbase or carrier.
