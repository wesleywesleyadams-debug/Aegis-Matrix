# Mods research tab (agreed 2026-10-18, updated 2026-10-21)

A research tab called **Mods**. Each Mod changes the weapon of one ship class.

## Rules

- **Rows, not tiers.** There is one row per class: corvette, destroyer, cruiser and carrier. Each row has three Mods, so a player has at most four Mods, one per class.
- **One Mod per row.** Researching a different Mod in the same row replaces the active one, which is then lost. Going back means researching it again from 0%. The old Mod stays active until the new one finishes.
- **Paused progress** works as for any tech: a half-researched Mod keeps its progress.
- **Disable / enable.** Clicking an active Mod's card disables it, and that class goes back to its standard laser. The card turns yellow. A "Disabled Mods" line under the timer (top left) lists disabled Mods, and clicking it re-enables them. Toggling is free and instant.
- **Requirements.** The corvette row needs nothing. The destroyer, cruiser and carrier rows each need their class unlocked first.
- **Cost.** All three Mods in a row cost the same, so the choice is about play style: 150 energy / 25 spice for corvettes, 180 / 30 destroyers, 210 / 35 cruisers, 240 / 40 carriers. Equal costs are final.
- **Variants stack.** A Mod sets the weapon's shape and behaviour, and the Weapons Depot variant (Plasma, Breacher, Ravager, Slip, Disruptor) still sets its damage profile. For example, a Plasma corvette with Proton Torpedoes fires torpedoes that do ×3.0 damage to shields.
- **Tuned in a full round robin.** Every class's plain lasers and all twelve Mods fight each other at equal cost; class toughness, class laser damage and each Mod's damage are tuned toward a gentle size ladder: corvettes 47%, destroyers 49%, cruisers 51%, carriers 53% overall (classes within ±2, each side within ±5). Results: `docs/balance/`, and the Codex Combat page. Exact numbers live in `Defs.MOD_WEAPONS`; this page describes behaviour.
- **No hit-and-run.** Every ship, ordnance Mods included, closes to weapon range and stands and fires (attack runs were removed 2026-10-20).

## The 12 Mods

| Class | Mod | Behaviour | Trade |
|---|---|---|---|
| Corvette | **Proton Torpedoes** | Heavy torpedoes at 1/3 the fire rate. They steer gently (turn limit) and lose lock past 50°, so a hard-turning target can shake them. Blast radius 30. Damage ×2 vs destroyers, ×3 vs cruisers, ×4 vs carriers, starbases and worlds, ×2 vs other constructs. | Weak against corvettes; a big-ship and siege hunter. |
| Corvette | **Kinetic Repeaters** | Rapid slugs: 3× fire rate, reduced damage per slug, −25% range. | No wasted overkill, but it has to get close. |
| Corvette | **Arc Emitters** | Chain lightning: the target takes the main share, then up to 2 enemies within 120 of it take a smaller share each. | Strong against swarms, weaker against one big ship. |
| Destroyer | **Flak Cannons** | Shells burst on the target and hit every enemy within 20 for full damage. | Shreds bunched corvettes; weaker against a single target. |
| Destroyer | **Cluster Bombs** | Releases 3 unguided bomblets in a random 10–20° fan; each bursts on the first enemy (ship, world, depot or Mining Station) it touches (radius 25, full damage) and ignores allies. | Strong against big or bunched targets; small fast ships slip through the spread. |
| Destroyer | **Homing Missiles** | 2-missile homing volleys, +20% range; blast radius 25. Missiles have a real turn limit, so a ship that turns hard and late can slip them. | Reliable at range, but the damage arrives late. |
| Cruiser | **Ion Lance** | A continuous beam whose damage ramps up over 4 s on the same target; the ramp resets when it switches. | Melts a single big target; weak against swarms. |
| Cruiser | **Rail Cannons** | Fast slugs (900 px/s) with +40% range, fired every 4 s for heavy damage. | Out-ranges everything and hits big hulls hard; weak against swarms. |
| Cruiser | **Point-Defense Lattice** | Needle-thin lasers at the normal reload. Each ready turret first fires at an enemy missile, torpedo or bomblet within 220: the needle destroys it, then bends and bounces to up to 3 more ordnance or drones, each within 90 of the last. Then enemy drones in range (×2 damage), then ships. Defensive Fire adds nothing to it. | Hard counter to ordnance and drone Mods, including Cluster Bomb fans. |
| Carrier | **Interceptor Drones** | The turrets become spiral launch doors. The carrier builds one drone every 5 s up to 4. Each drone (40 hull, 140 px/s, 10 px hit radius) flies nose-first, picks the enemy nearest to itself within 300 of the carrier, makes strafing passes, and patrols the edge of that radius when idle. Drones can be shot down, are rebuilt, and die with their carrier. Damage ×0.7 / ×0.6 / ×0.5 vs destroyers / cruisers / carriers. | Strong while the drones live; an enemy that kills them (Point-Defense, or ignoring them to focus the carrier) wins. |
| Carrier | **Tractor Beams** | The turrets fire no lasers. Each holds a beam on an enemy ship or drone up to 2× weapon range away that burns it harder the closer it is (0.5× a laser's damage rate at full reach, 1.5× once pulled in to 60% of weapon range; no ramp over time) and drags it toward the carrier at 60/s until it is within 60% of weapon range. The beam does not slow. | Drags long-range ships in; steady damage on whatever it holds. |
| Carrier | **Missile Barrage** | Each of the 4 turrets fires 5 missiles (a 20-missile salvo) every 8 s at +60% range, the longest in the game. | Opens fights from afar; long gaps between salvos. |

### Defensive Fire (Targeting tier 3)

A gun or drone with no enemy ship, construct or world in its attack range shoots down enemy missiles, torpedoes, bombs and drones there instead, at its normal reload. The Ion Lance beam never pauses for it.

## Engine change: independent turrets (all ships)

Each turret on a destroyer (2), cruiser (3) or carrier (4) gets its own target and aim. Corvette guns are fixed and stay as they are.

- **With an attack order,** every turret in range and in its arc fires at the ordered target. Focus fire is the same as today.
- **A turret picks its own target** only when the ordered target is out of its reach or arc, or when the ship is attack-moving or idle.
- **Tractor beams** follow each turret's own target, so a carrier can pull up to 4 ships at once and always prioritises the ordered one.
