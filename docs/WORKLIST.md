# Work list

A running catalog of what the game needs. Nothing here is decided: each item
waits for a go-ahead. Tags: **[bug]** wrong behaviour, **[balance]** needs
tuning or a design call, **[stale]** text that no longer matches the game,
**[missing]** not built yet, **[cleanup]** dead code. Paths are under
`scripts/game/` unless given. Last updated 2026-10-19.

## Bugs

- **[bug] Enemy drones show through fog.** `Vision._hide_unseen` (Vision.gd ~210) hides enemy ships, bases and shots but never the `drones` group. Fix: add drones to the ship loop.
- **[bug] Drones stay with an eliminated player.** `Game._hand_over` (Game.gd ~1423) passes ships to the heir but skips `drones`, so a captured carrier keeps drones owned by the dead player, hostile to their new owner. Fix: free or re-own them.
- **[bug] Ships overlap carriers.** Separation only looks `radius + MAX_HULL_RADIUS` (Ship.gd:37, 34) for neighbours, but a carrier's radius is 64, so ships sit well inside a carrier hull before being pushed out. Fix: raise MAX_HULL_RADIUS to the biggest radius.
- **[bug] Drones aren't saved.** A loaded game rebuilds them from nothing at one per 5 s. Fix: save/load them, or accept the rebuild.

## Balance and design calls

- **[balance] Drones: shooting them down isn't a counter yet.** Laser carriers hit drones about 3% of the time. In a free fight with drone damage 2.9, drone carriers trade 1.62× laser carriers. Variants tested:

  | Variant | Trade |
  |---|---|
  | Current (speed 240, 5 px hitbox) | 1.62× |
  | Speed 140 | 2.58× (slow drones turn tighter and fire more) |
  | Speed 140, 10 px hitbox | 1.57× |

  With the enemy focusing the carriers instead, drone carriers lose in every variant (about 0.69×). Next ideas: faster laser bolts (210 → 400), less drone hull, or a bigger hitbox on its own. Measure the laser hit rate on drones for each.
- **[balance] Every Mod needs re-checking.** Three changes since tuning shift them: shots only lead with the new Target Prediction tech (it used to be free), turrets now turn at 6.0 instead of 2.0, and guided shots no longer lead.
- **[balance] Proton Torpedoes vs corvettes.** By the numbers, a torpedo corvette deals about 16% of a laser corvette's damage per second to another corvette. The Codex says "a little weaker". Confirm in a duel, then fix the tuning or the text.
- **[balance] Missile Barrage swings with one value.** Around damage 0.83 one salvo either kills a corvette or doesn't (0.5× vs 3× trade). It's set to 0.8. Pick a side or reshape it (more, weaker missiles).
- **[balance] Mod costs are placeholders.** They're identical within each row (Defs.gd ~521).
- **[missing] Defensive Fire only helps turreted hulls.** Corvettes, and carriers running the drone Mod, get nothing from it. Decide whether that's fine.
- **[missing] Tractor Beams only grab ships**, not drones or starbases.

## AI

- **[missing] The scripted AI never researches or uses Mods.** `AIController.gd:114` filters them out, and it never toggles them. Wanted: pick a Mod per class that suits what the enemy fields.
- **[missing] The neural AI is blind to Mods and drones.** It can't toggle Mods, and drones aren't in the `entities` group it reads. `NeuralCommander.gd:20-27` research groups lack Mods, the Targeting row and Quantum Lenses. Needs a model update with a version bump.
- **[cleanup] The neural AI keeps a "dock" verb** for the removed hangars (RLAgent.gd:37, 255, 429; tools/rl/model.py:18,23). Removing it shifts action indices and breaks trained weights, so leave the slot until the next version bump.

## Leftovers from removing carrier hangars

All of this is dead code now (the carrier has no `bays`, and `fits_bay()` returns false).

- **[cleanup] Ship.gd:**
  - States `DOCK_GO`/`DOCKED` (enum at line 7, bodies at ~1078-1114, checks at ~1286 and ~1351).
  - Fields `bay_craft`, `dock_carrier`, `dock_slot`, `BAY_REPAIR_PER_SEC` (~516-522).
  - Functions `bay_offset`, `free_bay`, `fits_bay`, `order_dock`, `_launch_from_bay` (~703-753).
- **[cleanup] Defs.gd:** `BAY_MAX_RADIUS`, `carrier_bays()` and `WARSHIP_ART_SIZE` (~603-635).
- **[cleanup] HUD.gd:** `_add_hangar_panel` (~1215-1250) and the state names (~1438).
- **[cleanup] AIController.gd:** the block that sends hurt ships to a carrier (~226-248).
- **[cleanup] SaveGame.gd:** dock orders and re-docking (~165-169, ~358-381).
- **[cleanup] Game.gd:** the `SL_SHOT_OPEN=carrier` dev hook (~3200-3224) and the `SL_LOAD` "bay" printout (~210).
- **[cleanup] Carrier art:** `tools/gen_art.gd` (~1495, ~1591) still draws bay cradles on the carrier sprite.
- **[cleanup] Sounds:** "dock" and "launch" are now never played.

## Stale text

- **[stale] docs/MODS.md is badly out of date:**
  - Proton: says ×1.16 and ×2.92/3.73/4.5; now 0.47 and ×6.2/6.6/7.4.
  - Flak: says "within 50 for 60%"; now radius 20 at 100%.
  - Rail: says half rate ×2; now cooldown 4, ×3.4.
  - Ion Lance: says 60→140%; now 0.15→1.85 ×0.75.
  - Drones: build rate, hull, killable, PD ×2.
  - The "damage per second stays the same" rule no longer holds.
- **[stale] Flak Cannons desc** (Defs.gd:531) says "within 50 for 60%". The comment at Defs.gd:748 documents a `splash` key that's gone.
- **[stale] Codex corvette blurb** (Codex.gd:990) still says the corvette is "the only hull a carrier can dock".
- **[stale] Codex carrier blurb** (Codex.gd:993) doesn't mention carrier Mods.
- **[stale] The Weapon Mods section** has no numbers for Drones, Tractor Beams or Missile Barrage.
- **[cleanup] Small leftovers:**
  - Codex.gd:595 hangar-bays line (can no longer fire).
  - Codex.gd:475-495 "(coming)" logic (all Mods are built).
  - Drone.gd:6 cites a nonexistent `Defs.DRONE_REBUILD` (it's `Ship.DRONE_BUILD`).
  - Effect keys `mod_*` and `unlock_carrier/cruiser/destroyer` have no reader.

## Not built yet

- **[missing] Drones on the minimap.** Also missing: drone status in a selected carrier's panel, and drone kills in the stats.
- **[missing] Munitions and reloading** (an idea from 2026-09-22): limited ammo, restocked at a starbase.
- **[missing] Neural AI training is paused.** On resume:
  1. Fix the closing-in reward loophole (count every warship, not the 8 closest).
  2. Add the income reward once training reaches the expand stage.
  3. Restart from the checkpoint.
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).
