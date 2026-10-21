# Work list

A running catalog of what the game needs. Nothing here is decided: each item
waits for a go-ahead. Tags: **[bug]** wrong behaviour, **[balance]** needs
tuning or a design call, **[missing]** not built yet, **[cleanup]** dead
code or art. Last updated 2026-10-21.

## Balance

- **[balance] Class/Mod round robin in progress.** Goal (user, 2026-10-20): in a full round robin of every class's lasers and all 12 Mods at equal cost, class averages corvette 47% / destroyer 49% / cruiser 51% / carrier 53% (within ±2), each side within ±5 of its class. Main has pass 3b (classes within 3); passes run on the `balance-wip` branch with `tools/rr_all16x9.txt`. Remaining outliers in 3b: Missile Barrage 69%, destroyer lasers 61%, Tractor Beams 40%, Proton Torpedoes 41%.
- **[balance] Next, after every side is balanced: Mods ~+5% over lasers.** Buff every Mod so it beats plain lasers by about 5 win-rate points, so researching a Mod is generally an upgrade. Tractor Beams are locked (standard laser damage 1.0, pull 60/s, about 67%): don't change them without the user's go-ahead; revisit them after the Mod buff.
- **[balance] Refresh the Codex matchup tables on each merge:** `python tools/matchups_to_json.py <duels.txt> "<label>"` rewrites `data/matchups.json`, which the Combat page reads.
- **[balance] Recheck "Which variant against what"** (Codex): its numbers are computed live, but the note that equal-cost duels confirmed them predates the recent rebalance.
- **[balance] (parked by the user 2026-10-20) Upkeep explodes late.** AI sims (2026-10-20): x2.7 at 30 min, x12 (~3,900 energy/min) at 45 min; nobody starved yet thanks to 50k stockpiles, but longer games will hit a wall. Options: smaller weight for harvesters/support, a cap, or keep.
- **[balance] Starbase cost 1,250 + 75 spice:** AI still expands, a bit later (2.3 bases at 20 min vs 3.3 before; 5.2 vs 6.0 at 45).
- **[balance] Plasma has no matchup of its own** (left as-is by choice, 2026-10-20): best used against cruiser/carrier-heavy fleets of uncertain mix.

## AI

- **[missing] The neural AI is blind to Mods and drones.** It can't toggle Mods, and drones aren't in the `entities` group it reads. `NeuralCommander.gd` research groups lack Mods, the Targeting row and Quantum Lenses; it also treats Spice Navigation as a speed tech (now nebula radiation resistance). Needs a model update and a version bump.
- **[missing] No AI builds or uses Frontier Outposts or Warp Gates** (added 2026-10-21, Constructs > Expansion row). The scripted AI never researches toward them on purpose; the neural AI (RLAgent.gd) labels forts as "depot" in its observation and has no garrison/warp verbs.
- **[cleanup] The neural AI keeps a "dock" verb** for the removed hangars (RLAgent.gd, tools/rl/model.py). Never allowed now; drop it at the next model version bump.
- **[missing] Neural AI training is paused.** On resume: fix the closing-in reward loophole (count every warship, not the 8 closest); add the income reward at the expand stage; restart from the checkpoint.

## Features

- **[missing] Munitions and reloading** (idea, 2026-09-22): limited ammo, restocked at a starbase.
- **[balance] Warp Gate reach 1,000-10,000 px** is wider than the map (radius 1,750), so in practice the limit is the map edge. Warp lines are straight and can cross the star's radiation.
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).

## Cleanup

