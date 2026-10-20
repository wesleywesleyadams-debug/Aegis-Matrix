# Work list

A running catalog of what the game needs. Nothing here is decided: each item
waits for a go-ahead. Tags: **[bug]** wrong behaviour, **[balance]** needs
tuning or a design call, **[missing]** not built yet, **[cleanup]** dead
code or art. Last updated 2026-10-20.

## Balance

- **[balance] Upkeep explodes late.** AI sims (2026-10-20): x2.7 at 30 min, x12 (~3,900 energy/min) at 45 min; nobody starved yet thanks to 50k stockpiles, but longer games will hit a wall. Options: smaller weight for harvesters/support, a cap, or keep.
- **[balance] Starbase cost 1,250 + 75 spice:** AI still expands, a bit later (2.3 bases at 20 min vs 3.3 before; 5.2 vs 6.0 at 45).
- **[balance] Corvettes lose to every bigger class at equal cost** (size grid, 2026-10-20). Fits the size ladder; consider giving them a job (speed, cheap upkeep, raiding).
- **[balance] Plasma has no matchup of its own** (left as-is by choice, 2026-10-20): best used against cruiser/carrier-heavy fleets of uncertain mix.

## AI

- **[missing] The neural AI is blind to Mods and drones.** It can't toggle Mods, and drones aren't in the `entities` group it reads. `NeuralCommander.gd` research groups lack Mods, the Targeting row and Quantum Lenses. Needs a model update and a version bump.
- **[cleanup] The neural AI keeps a "dock" verb** for the removed hangars (RLAgent.gd, tools/rl/model.py). Never allowed now; drop it at the next model version bump.
- **[missing] Neural AI training is paused.** On resume: fix the closing-in reward loophole (count every warship, not the 8 closest); add the income reward at the expand stage; restart from the checkpoint.

## Features

- **[missing] Defensive Fire only helps turreted hulls.** Corvettes, and carriers running the drone Mod, get nothing from it.
- **[missing] Tractor Beams only grab ships**, not drones or starbases.
- **[missing] Drone status** in a selected carrier's panel, and drone kills in the stats.
- **[missing] Munitions and reloading** (idea, 2026-09-22): limited ammo, restocked at a starbase.
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).

## Cleanup

- **[cleanup] Carrier art:** `tools/gen_art.gd` (~1495, ~1591) still draws hangar-bay cradles on the carrier sprite.
- **[cleanup] Sounds:** "dock" and "launch" are never played now.
