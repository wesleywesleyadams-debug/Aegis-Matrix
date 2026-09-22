# Star Lords — Defense layers, ship variants and the Weapons Depot

Reference for the combat design. A color-coded version with the ship sprites is
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
| **Ion** | x2.2 vs **shields** | 80% | light blue | dotted spine + nose emitter |
| **Breacher** | x2.2 vs **armor** | 80% | red | solid spine + ram prongs |
| **Reaver** | x1.9 vs **hull** | 80% | green | solid spine + saw-tooth edges |
| **Slip** | **ignores shields** (armor + hull) | 65% | orange V-shots | twin dashed side stripes |
| **Disruptor** | **ignores shields and armor** (hull only) | 40% | green V-shots | V-chevrons down the spine |

Color = which layer it hits; pattern = which variant it is. Cruisers fire
torpedoes in the same colors (only lasers get the V shape). Against planets,
piercing shots skip the planetary shield, Ion hits it harder, and Reaver kills
population faster.

## Which variant against what

Base damage needed to destroy a target, relative to a generalist
(1.00 = the same, lower = kills faster):

| Target | Ion | Breacher | Reaver | Slip | Disruptor |
|---|---|---|---|---|---|
| Corvette (hull-heavy) | 1.08 | 1.14 | **0.91** | 1.16 | 1.47 |
| Destroyer (shield-heavy) | **0.93** | 1.16 | 1.01 | **0.82** | 1.00 |
| Cruiser (armor-heavy) | 1.12 | **0.93** | 1.06 | 1.24 | **0.82** |
| Starbase | 1.06 | 1.10 | **0.95** | 1.12 | 1.27 |

- Reaver: corvette swarms, starbases.
- Ion / Slip: shield-heavy fleets. Slip also ignores shield regeneration.
- Breacher / Disruptor: armor-heavy fleets (Cruisers).
- Wrong target: 5-46% worse than a plain generalist, so scouting decides.

## Weapons Depot

- Built by a **Constructor** (**E**, or its panel button): 250 minerals + 20
  spice over 30 s. It has no weapons and doesn't count for victory.
- Select generalist warships, pick a refit in their panel: they fly to the
  nearest depot, dock, and convert after **12 s for 25 minerals** each.
- **A specialist can never be refitted again** — the choice is permanent.
- The AI builds a depot once its fleet grows, then refits by kill-cost maths
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
