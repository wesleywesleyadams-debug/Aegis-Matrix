# Mods research tab (agreed 2026-10-18, updated 2026-10-19)

A research tab called **Mods**. Each Mod changes the weapon of one ship class.

## Rules

- **Rows, not tiers.** There is one row per class: corvette, destroyer, cruiser and carrier. Each row has three Mods, so a player has at most four Mods, one per class.
- **One Mod per row.** Researching a different Mod in the same row replaces the active one, which is then lost. Going back means researching it again from 0%. The old Mod stays active until the new one finishes.
- **Paused progress** works as for any tech: a half-researched Mod keeps its progress.
- **Disable / enable.** Clicking an active Mod's card disables it, and that class goes back to its standard laser. The card turns yellow. A "Disabled Mods" line under the timer (top left) lists disabled Mods, and clicking it re-enables them. Toggling is free and instant.
- **Requirements.** The corvette row needs nothing. The destroyer, cruiser and carrier rows each need their class unlocked first.
- **Cost.** All three Mods in a row cost the same, so the choice is about play style: 120 energy / 20 spice / 60 s for corvettes, rising to 280 / 50 / 105 s for carriers. Equal costs are final: the round-robin keeps every Mod within about ±0.1 of the others.
- **Variants stack.** A Mod sets the weapon's shape and behaviour, and the Weapons Depot variant (Plasma, Breacher, Ravager, Slip, Disruptor) still sets its damage profile. For example, a Plasma corvette with Proton Torpedoes fires torpedoes that do ×3.0 damage to shields.
- **Tuned in duels, not by formula.** Each Mod's damage is tuned so it trades about as well as the laser it replaces in its best matchup, then shaped by its strengths (see Trade). Exact numbers live in `Defs.MOD_WEAPONS`; this page describes behaviour.

## The 12 Mods

| Class | Mod | Behaviour | Trade |
|---|---|---|---|
| Corvette | **Proton Torpedoes** | Attack runs: fly in, launch, peel away while reloading (1/3 the fire rate). Torpedoes launch straight at the target, steer gently and lose lock past 50°, so a hard-turning target can shake them. Blast radius 30. Damage ×6.2 vs destroyers, ×6.6 vs cruisers, ×7.4 vs carriers. | Weak against corvettes; a big-ship hunter. |
| Corvette | **Kinetic Repeaters** | Rapid slugs: 3× fire rate, 70% damage per slug, −25% range. | No wasted overkill, but it has to get close. |
| Corvette | **Arc Emitters** | Chain lightning: the target takes 90%, then up to 2 enemies within 120 of it take 35% each. | Strong against swarms, weaker against one big ship. |
| Destroyer | **Flak Cannons** | Shells burst on the target and hit every enemy within 20 for full damage. | Shreds bunched corvettes; weaker against a single target. |
| Destroyer | **Cluster Bombs** | Attack runs: releases 3 unguided bomblets in a random 10–20° fan; each bursts on the first enemy it touches (radius 25, full damage) and ignores allies. | Strong against big or bunched targets; small fast ships slip through the spread. |
| Destroyer | **Homing Missiles** | Attack runs: 2-missile volleys that never miss, +20% range; blast radius 25. | Reliable at range, but the damage arrives late. |
| Cruiser | **Ion Lance** | A continuous beam whose damage ramps up over 4 s on the same target; the ramp resets when it switches. | Melts a single big target; weak against swarms. |
| Cruiser | **Rail Cannons** | Fast slugs (900 px/s) with +40% range, fired every 4 s for heavy damage. | Out-ranges everything and hits big hulls hard; weak against swarms. |
| Cruiser | **Point-Defense Lattice** | Each ready turret first shoots down an enemy missile, torpedo or bomblet within 220 (of itself or nearby allies), then an enemy drone in range (×2 damage to drones), then fires at ships. | Counters ordnance and drone Mods; −20% damage against ships. |
| Carrier | **Interceptor Drones** | The turrets become spiral launch doors. The carrier builds one drone every 5 s up to 4. Each drone (40 hull, 140 px/s, 10 px hit radius) flies nose-first, picks the enemy nearest to itself within 300 of the carrier, makes strafing passes, and patrols the edge of that radius when idle. Drones can be shot down, are rebuilt, and die with their carrier. Damage ×0.7 / ×0.6 / ×0.5 vs destroyers / cruisers / carriers. | Strong while the drones live; an enemy that kills them (Point-Defense, or ignoring them to focus the carrier) wins. |
| Carrier | **Tractor Beams** | Adds a beam to each turret reaching 2× weapon range: it slows that turret's target from 10% (far) to 90% (close) and reels it in to 60% of weapon range. The lasers keep full damage. | Holds and pins targets for the fleet. |
| Carrier | **Missile Barrage** | Each of the 4 turrets fires 5 missiles (a 20-missile salvo) every 8 s at +60% range, the longest in the game. | Opens fights from afar; long gaps between salvos. |

### Tractor Beams details

- **Stacking:** slows from several beams stack with diminishing returns, multiplicatively. A target keeps the product of (1 − slow) for every beam on it, so two 50% beams make a 75% slow.
- **No damage trade:** the lasers keep full damage (the user's call).
- **Ships only:** beams don't grab drones or starbases.

## Engine change: independent turrets (all ships)

Each turret on a destroyer (2), cruiser (3) or carrier (4) gets its own target and aim. Corvette guns are fixed and stay as they are.

- **With an attack order,** every turret in range and in its arc fires at the ordered target. Focus fire is the same as today.
- **A turret picks its own target** only when the ordered target is out of its reach or arc, or when the ship is attack-moving or idle.
- **Tractor beams** follow each turret's own target, so a carrier can hold up to 4 ships at once and always prioritises the ordered one.
