# Work list

A running catalog of what the game needs. Nothing here is decided: each item
waits for a go-ahead. Tags: **[bug]** wrong behaviour, **[balance]** needs
tuning or a design call, **[missing]** not built yet, **[cleanup]** dead
code or art. Last updated 2026-10-20.

## Balance

- **[balance] Upkeep economy under the new compounding multiplier.** One AI game ran fine (an AI still reached 83 ships). Needs a batch of AI-vs-AI sims on GitHub to confirm economies don't stall or snowball.
- **[balance] Starbase cost tripled (1,250 minerals + 75 spice) to match its combat strength.** Check expansion pacing, and whether the scripted AI still builds a second starbase.
- **[balance] Drones: shooting them down isn't a counter yet.** Laser carriers hit drones about 3% of the time; drone carriers lose when the enemy ignores the drones and focuses the carriers. Options: faster laser bolts, less drone hull.
- **[balance] Corvettes are weak as a class at mid-game budgets** (round-robin, before the Mod fixes). Re-check now that the corvette Mods are buffed.
- **[balance] Missile Barrage swings with one value.** Around damage 0.83 one salvo either kills a corvette or doesn't. It's at 0.8.
- **[balance] Mod research costs are placeholders.** Identical within each row.
- **[balance] Plasma has no matchup of its own** (left as-is by choice, 2026-10-20): best used against cruiser/carrier-heavy fleets of uncertain mix.

## AI

- **[missing] The neural AI is blind to Mods and drones.** It can't toggle Mods, and drones aren't in the `entities` group it reads. `NeuralCommander.gd` research groups lack Mods, the Targeting row and Quantum Lenses. Needs a model update and a version bump.
- **[cleanup] The neural AI keeps a "dock" verb** for the removed hangars (RLAgent.gd, tools/rl/model.py). Never allowed now; drop it at the next model version bump.
- **[missing] Neural AI training is paused.** On resume: fix the closing-in reward loophole (count every warship, not the 8 closest); add the income reward at the expand stage; restart from the checkpoint.

## Features

- **[missing] Defensive Fire only helps turreted hulls.** Corvettes, and carriers running the drone Mod, get nothing from it.
- **[missing] Tractor Beams only grab ships**, not drones or starbases.
- **[missing] Drones on the minimap**, drone status in a selected carrier's panel, and drone kills in the stats.
- **[missing] Munitions and reloading** (idea, 2026-09-22): limited ammo, restocked at a starbase.
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).

## Cleanup

- **[cleanup] Carrier art:** `tools/gen_art.gd` (~1495, ~1591) still draws hangar-bay cradles on the carrier sprite.
- **[cleanup] Sounds:** "dock" and "launch" are never played now.
