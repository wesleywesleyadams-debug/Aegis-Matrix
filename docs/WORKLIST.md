# Work list

A running catalog of what the game needs. Nothing here is decided: each item
waits for a go-ahead. Tags: **[bug]** wrong behaviour, **[balance]** needs
tuning or a design call, **[missing]** not built yet, **[cleanup]** dead
code or art. Last updated 2026-10-23.

## Recently done (2026-10-23)

- Project Symmetry merged: laser 10 dmg / 1.0 s, class prices 75/150/300/600, 44/33/23 layer splits, per-turret muzzle shots.
- Mods balanced (pass 5, every Mod within 0..+0.09 of lasers).
- Variants balanced and renamed: Plazer, Breacher, Ravager, Disruptor (hull-only, was Slip), Inhibitor (shield EMP, was Disruptor); EMP cooldown 4 s / gun count.
- Defense rework: layer techs add a % of total base HP; Deflectors line (Glance Plates / Graviton Shunts / Iron Umbrella) -6/-7/-10%; new names (Phase Shields / Crystal Prisms / Aegis Matrix, Living Metals, ...); ships and constructs only, not worlds.
- Constructs fire standard ship guns: Starbase 6, Frontier Outpost 3; Mining Station, Depot and Gate unarmed.
- Construct toughness (armor 44 / shield 33 / hull 23): Starbase 4900, Outpost 2750, Mining Station 1000, Depot 1500, Gate 2000.
- Tractor Beams: pull multipliers by class (x3 corvette, x2 destroyer, x0.5 carrier, x4 drones), pull stops at 52% of range.
- Renames: Defensive Fire -> Overkill Awareness (fleet-wide overkill-aware targeting), Lance Batteries -> Starfire Batteries.
- Codex text pass after the renames (stale Mining Station guns, carrier layer, Pierce term).
- Research icon overhaul in progress: Defense tab done, Weapons tab mostly done.

## Balance

- **[balance] Playtest the new balance** (Symmetry + Mod pass 5 + variant pass 4 + Defense rework + construct toughness): nothing has been played by hand yet.
- **[balance] Target Prediction: next phase pending** (smoothed-velocity lead and braking/charge handling are in; further tuning not started).
- **Tractor Beams lock:** Tractor Beams are locked (beam-only, closer = more damage; pull x3 corvettes / x2 destroyers / x0.5 carriers / x4 drones, stops at 52% of range): change only with the user's go-ahead.
- **[balance] Refresh the Codex matchup tables on each merge:** `python tools/matchups_to_json.py <duels.txt> "<label>"` rewrites `data/matchups.json`, which the Combat page reads.
- **[balance] Recheck "Which variant against what"** (Codex): its numbers are computed live, but the note that equal-cost duels confirmed them predates the recent rebalance.
- **[balance] (parked by the user 2026-10-20) Upkeep explodes late.** AI sims (2026-10-20): x2.7 at 30 min, x12 (~3,900 energy/min) at 45 min; nobody starved yet thanks to 50k stockpiles, but longer games will hit a wall. Options: smaller weight for harvesters/support, a cap, or keep.
- **[balance] Starbase cost (now 1,200 minerals):** earlier sims at 1,250 + 75 spice had the AI expanding a bit later (2.3 bases at 20 min vs 3.3 before); not rechecked.
- **[balance] Plazer has no matchup of its own** (left as-is by choice, 2026-10-20): best used against cruiser/carrier-heavy fleets of uncertain mix.

## AI
- **[ai] Review the scripted and neural AI against the new balance** (Symmetry prices/toughness, renamed variants, Defense rework, unarmed Mining Stations, Overkill Awareness): pending.
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
- **[balance] Constructs:** toughness and guns done (see Recently done). Still open: the cost lever for Weapons Depot / Warp Gate is untested in duels (SL_DUEL_BUDGET).
- **[missing] "Claude plays a match via text"** (idea, 2026-10-17).

- **[missing] Loading screens** (user request, 2026-10-23; after the preloading work): a boot screen and a match-loading screen. Each shows a large immersive pixel-art scene that changes every time (rotating set: fleets, classes, variants, constructs, worlds) to draw the player into the setting, plus logo/progress bar (boot) or system name, players and a lore/gameplay tip (match). Show mockups before applying.

## Cleanup

