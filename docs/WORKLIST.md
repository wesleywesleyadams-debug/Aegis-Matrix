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
- **[ai] Queued after the economy diagnostic (user-approved):** (1) economy planner for the finite economy (fuel, claim deposits before depletion, protect harvesters, pause/rebuild mining), (2) counter-picking classes/Mods/variants from what the AI has seen, using data/matchups.json, (3) finishing games: target by cost-to-kill, coordinated siege waves, sustained pressure. Verify with same-seed sims.

- **[missing] The neural AI is blind to Mods and drones.** It can't toggle Mods, and drones aren't in the `entities` group it reads. `NeuralCommander.gd` research groups lack Mods, the Targeting row and Quantum Lenses; it also treats Spice Navigation as a speed tech (now nebula radiation resistance). Needs a model update and a version bump.
- **[partial] Neural AI and forts** (scripted AI done 2026-10-21: researches Outposts/Warp Gates, builds outposts on exposed/front-line holdings, one gate near home (two late), garrisons idle warships and warps them at winnable seen targets or to its own worlds under attack; log with SL_AI_FORTS_LOG=1). Still open: the neural AI (RLAgent.gd) labels forts as "depot" in its observation (a new entity kind changes the observation width and breaks trained checkpoints) and has no garrison/warp verbs.
- **[balance] Games resolve slowly** (sims 2026-10-21, after the spice fix): 2/5 decided within 60 min on seed set 5, 0/10 within 45 min on seed sets 3 and 7. The losing side often sits on 10k+ minerals with 0-5 warships (one starbase queue; ships die as they spawn) while the winner's upkeep multiplier hits x13-x20. Log spice in/out and stuck ships with SL_SPICE_LOG=1.
- **[bug] AI ships hold forever at the edge of the star's radiation** when their goal is inside the zone and their hull is below SUN_RISK_HP (Ship._avoid_sun), seen with Tenders and a damaged Destroyer.
- **[balance] Late spice piles up** (1-4k by 30-45 min) once extractors, barges and skimmers all run: the AI has nothing more to spend it on.
- **[cleanup] The neural AI keeps a "dock" verb** for the removed hangars (RLAgent.gd, tools/rl/model.py). Never allowed now; drop it at the next model version bump.
- **[missing] Neural AI training is paused.** On resume: fix the closing-in reward loophole (count every warship, not the 8 closest); add the income reward at the expand stage; restart from the checkpoint.

## Features

- **[missing] Munitions and reloading** (idea, 2026-09-22): limited ammo, restocked at a starbase.
- **[balance] Warp Gate reach 1,000-10,000 px** is wider than the map (radius 1,750), so in practice the limit is the map edge. Warp lines are straight and can cross the star's radiation.
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).

## Cleanup

