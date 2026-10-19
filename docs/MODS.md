# Mods research tab (design, agreed 2026-10-18)

A research tab called **Mods**. Each Mod changes the weapon of one ship class.

## Rules

- **Rows, not tiers.** There is one row per class: corvette, destroyer, cruiser and carrier. Each row has three Mods, so a player has at most four Mods, one per class.
- **One Mod per row.** Researching a different Mod in the same row replaces the active one, which is then lost. Going back means researching it again from 0%. The old Mod stays active until the new one finishes.
- **Paused progress** works as for any tech: a half-researched Mod keeps its progress.
- **Disable / enable.** Clicking an active Mod's card disables it, and that class goes back to its standard laser. The card turns yellow. A "Disabled Mods" line under the timer (top left) lists disabled Mods, and clicking it re-enables them. Toggling is free and instant.
- **Requirements.** The corvette row needs nothing. The destroyer, cruiser and carrier rows each need their class unlocked first.
- **Cost.** All three Mods in a row cost the same, so the choice is about play style. The numbers are still to be set.
- **Variants stack.** A Mod sets the weapon's shape and behaviour, and the Weapons Depot variant (Plasma, Breacher, Reaver, Slip, Disruptor) still sets its damage profile. For example, a Plasma corvette with Proton Torpedoes fires torpedoes that do ×2.2 damage to shields.
- **Damage per second stays the same** as the laser being replaced, except for Tractor Beams, which add to the laser (see below).

## The 12 Mods

| Class | Mod | Behaviour | Trade |
|---|---|---|---|
| Corvette | **Proton Torpedoes** | Attack runs: fly in, launch, peel away while reloading. 1/3 the shots at x1.16 damage each; the torpedoes steer gently and lose lock past 50 degrees, so evasive targets can shake them. Damage x2.92 vs destroyers, x3.73 vs cruisers, x4.5 vs carriers. | Slightly weaker than lasers vs corvettes (tuned in duels); a big-ship hunter. |
| Corvette | **Kinetic Repeaters** | Rapid slugs: 3× fire rate, ⅓ damage per shot, −25% range. | No wasted overkill, but it has to get close. |
| Corvette | **Arc Emitters** | Chain lightning: the target takes 60%, then 2 nearby enemies take 20% each. | Strong against swarms, weaker against one big ship. |
| Destroyer | **Flak Cannons** | Shells burst and hit everything within 50 for 60%. | Shreds corvette packs; −40% against a single target. |
| Destroyer | **Cluster Bombs** | Makes an attack run at the target, releases a spread of unguided bomblets that burst on contact with whatever they hit, then circles back while recharging. | Strong against big or bunched targets; small fast ships slip through the spread. |
| Destroyer | **Homing Missiles** | 4-missile volleys that never miss, with +20% range. | Reliable at range, but the damage arrives late. |
| Cruiser | **Ion Lance** | A continuous beam whose damage ramps from 60% to 140% over 4 s on the same target. | Melts big targets; the ramp resets whenever it changes target. |
| Cruiser | **Rail Cannons** | An instant slug with +40% range, fired half as often for 2× damage. | Out-ranges every other class; loses close brawls. |
| Cruiser | **Point-Defense Lattice** | Shoots down nearby torpedoes and missiles aimed at itself or allies, and fires on ships with what's left over. | Counters missile and torpedo Mods; −30% damage against ships. |
| Carrier | **Interceptor Drones** | 4 drones orbit the carrier and attack enemies within 300. | Covers a wide area; weak against heavy armor. |
| Carrier | **Tractor Beams** | Adds a beam to each turret: it slowly pulls that turret's target in and slows it from 10% (at long range) to 90% (close in). The lasers keep full damage. | Holds and pins targets for the fleet. |
| Carrier | **Missile Barrage** | A 12-missile salvo every 8 s at the longest range in the game. | Opens fights from afar; long gaps between salvos. |

### Tractor Beams details

- **Stacking:** slows from several beams stack with diminishing returns, multiplicatively. A target keeps the product of (1 − slow) for every beam on it, so two 50% beams make a 75% slow.
- **No damage trade:** the lasers keep full damage (the user's call).

## Engine change: independent turrets (all ships)

Each turret on a destroyer (2), cruiser (3) or carrier (4) gets its own target and aim. Corvette guns are fixed and stay as they are.

- **With an attack order,** every turret in range and in its arc fires at the ordered target. Focus fire is the same as today.
- **A turret picks its own target** only when the ordered target is out of its reach or arc, or when the ship is attack-moving or idle.
- **Tractor beams** follow each turret's own target, so a carrier can hold up to 4 ships at once and always prioritises the ordered one.
