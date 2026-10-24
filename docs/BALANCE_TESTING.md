# Aegis Matrix balance testing

Every balance or AI test starts from this file. Each time the user corrects how testing is done, add the rule here. Balance and testing work happens in the "balance/testing" side chat; the main chat does everything else.

## Standing rules

- **Run tests on GitHub Actions** (`.github/workflows/balance.yml`), never locally (`tools/dispatch.sh` keeps `LOCAL_SLOTS=0`). A short local game is fine only as a smoke test for script errors.
- **Speed ×4 only.** ×8 distorted results badly (Rail Mod +0.05 → −0.33, Drones −0.03 → +0.26, plain classes moved 0.15–0.35 with no change).
- **Never change balance numbers on `main` without the user's OK.** That includes toughness, pixel counts, damage, prices and mineral rates. Experiments go on `test/<what>` branches made with a git worktree (the main checkout and its uncommitted work stay untouched), run with `--ref <branch>`, and the branches are deleted afterwards.
- **Fixed references (never change without permission):**
  - Plain lasers are the reference. Mods and variants are tuned only through their own damage multiplier.
  - Corvette toughness 150 is the basis. Classes are tuned with **toughness as the lever**; ask before using any other lever.
  - Tractor Beams: pull and stop are locked (damage tuning was allowed during the Mod pass).
- **Scope:** balance Mk I ships with plain lasers, Mods and variants (variants apply to Mk I). Not Mk II–IV, not upgrades. Adding a tech doesn't justify a re-run; changing base stats or base behaviour does.
- **Change one thing per test**, so a result can be pinned on it. When hunting a cause, revert one suspect per branch.
- **Small steps.** Toughness in steps of 10, 5 when closing in. Big jumps get rejected.
- **Confirm the final value** with a larger run (e.g. "go with 700 and 4900, rerun with 20 duels").
- **Report results with their conditions** (run id, duels, budget, what changed) and say plainly when a difference is within noise.
- **When the user is away:** don't work on balance; finish unfinished features instead and run sims only as regression checks.

## Goals (current)

| Area | Goal | Score |
|---|---|---|
| Classes | Every class trades evenly in medium fights (2400 budget, no Target Prediction). Single matchups may be lopsided. | class weight ≈ 0.0 |
| Mods | Slightly better than plain lasers | weight 0.00 to +0.09 in the 16-loadout field (plain lasers ignored there) |
| Variants | Slightly better than their own class's plain lasers | 0.00 to +0.09 above plain, averaged over the 4 classes |
| Defense lines | Roughly equal to each other | margin points over the same class with no tech |
| Constructs | Slightly worse than equal-cost ships; Frontier Outpost slightly better | −0.10 to 0.00; Outpost 0.00 to +0.10 |
| Target Prediction | On hold | |

Earlier goals, all superseded: bigger class wins at medium (4300, then 6725) and loses at 10,000+; 50% win rate per loadout; class win rates of 47/49/51/53%; bigger wins small fights, ties medium and loses large. Weight replaced win rate because fleet fights are near-deterministic: a 3–8% per-gun edge decides them 12–0, so win rates swing between 0 and 100% on tiny differences.

## Scoring

- **Weight** = the winner's toughness left as a fraction: positive for the winner, negative for the loser, averaged per loadout or class. **+1.0** = this side won with every ship alive at 100% toughness (took no damage). **−1.0** = this side lost every ship while the winner kept every ship at 100% (dealt no damage).
- **One fight vs the average:** a single fight scores 0.0 only as a perfect draw, where both sides lose every ship. A class weight of ≈ 0.0 is an *average*: its wins and losses cancel out, so on average it trades evenly. Individual fights are usually far from 0.
- **Draws** (time out, or both sides wiped): weight = the difference in toughness left (A keeps 40%, B 10% → A +0.30, B −0.30; a mutual wipe is 0.0 each), and each side gets half a win. Same rule as the Codex.
- `tools/rr_summary.sh <run id>` prints win % and weight per side and class, using these rules.
- `DUELP` lines every 30 s say who leads if a duel is cut off. `SL_DUEL_STATS=1` adds DSTAT/DSTAT2/DTL lines (miss and dodge %, overkill, idle turrets, engaged share).

**Noise observed:**

| Setup | Noise in weight |
|---|---|
| Class round robin, 720 duels | ±0.04–0.05 |
| One-class subset, 180 duels | about ±0.03 per weight point, estimated |
| Mods/variants, 5 repeats per pairing | ±0.05 |
| Mods/variants, 9 repeats per pairing | ±0.035 |
| Constructs, 10 duels per pairing | ±0.1 |
| Constructs, 20 duels per pairing | about ±0.05 |

Win rates need far more duels: 180 duels per side is about ±7 points at 95% confidence.

## The duel harness

- `round_robin` fights every list line **twice** (lines × 2 = duels), splits lines across `runs` jobs, runs 2 Godot processes per job, and gives each duel a 900 s timeout. Jobs time out at 90 min.
- `minutes` is the duel limit in **game seconds** in `round_robin` (use 240).
- **The workflow's default budget is 6725. Always pass `-f budget=2400`.** Without `SL_DUEL_BUDGET` the harness itself defaults to 2550.
- `tag=file=<list>` picks the pairs file (`tag=variants` → `variant_pairs.txt`; default `rr_pairs.txt`).
- `system=KEY=VAL ...` (anything with `=`) passes extra environment variables in `round_robin` and `mod_grid`. Otherwise `system` is the map; use `orion_reach`.
- **Budget charging:** the side pays its class unlock research, mark, Mod and per-side techs out of the budget (all resources 1:1), then rounds down to whole ships, so sides can be off by about ±45.
- **Spec syntax:** `class:mark[:mod[:tech+tech]]`; constructs `starbase|outpost|station|gate|depot[:N]`; worlds `world:N` (N Defense Batteries, the fleet bombards it).
- Fog is always off in duels (`SL_NOFOG=1`).

## Recipes

**Classes** (Mk I plain lasers, `tools/rr_lasers.txt`, 6 pairings, 720 duels):
```bash
gh workflow run balance.yml -f mode=round_robin -f runs=20 -f minutes=240 -f speed=4 -f tag=file=tools/rr_lasers.txt -f budget=2400 -f system=orion_reach
```
- **Tuning one class:** a list with only that class's 3 pairings, 30 lines each (180 duels), `runs=5`. Four candidate values then run side by side in ~30–40 min. Confirm the pick with one full 720-duel run.
- Fleet-size checks: budgets 1200 / 2400 / 6725.

**Mods:** `tools/rr_mods_laser.txt` at 2400 (older fields: `rr_all16x3/x5/x9`, 16 loadouts = 4 lasers + 12 Mods). Lever: the Mod's own damage multiplier. Single-Mod sweeps: `mode=mod_grid -f mod="mod_id ours foe foe_n dmg1 dmg2 ..."` (`laser` = no Mod; `marks` carries `SL_DUEL_TECHS`; `minutes` < 45 is the duel length in seconds; `tag=amove` makes foes attack-move). Mod tests must fight laser ships with attack patterns against Mod ships with attack patterns, and check chase behaviour works.

**Variants:** `tools/rr_variants24x5.txt` (1,380 duels) or `x9` (2,484): 24 loadouts (4 classes × plain + 5 variants), 2400, no Mods. Score = variant weight minus its own class's plain weight, averaged over the classes. The lists use the current variant ids (`plazer`, `breacher`, `reaver` = Ravager, `disruptor`, `inhibitor`; checked 10-24). If variants are renamed again, update the lists.

**Defense techs:** `tools/rr_defense20x5.txt` (1,900 duels; each class with no tech, then each full line as the 4th spec field), budget 2400, **with `system=SL_DUEL_FREE_TECHS=1`**. Paying research at 2400 makes every line negative (−0.60 to −0.82), because 420–520 of research costs 18–22% of the fleet, so that compares the wrong thing. Defense techs affect ships and constructs, not worlds.

**Constructs:** `tools/construct_pairs.txt` with `system=SL_DUEL_BUDGET=match` (the ship side gets the construct's build cost plus research). Each class at equal cost against each construct. Also test two of a construct (`:2`): two Outposts face a fleet twice as big and come out much worse under the square law. Corvette and destroyer results are the most reliable (whole cruisers and carriers can't match the cost exactly). Unarmed constructs score −1.00 by design and are excluded. Before tuning, check construct guns behave like ship guns.

**Torpedoes / area damage:** `torp_sb_pairs.txt`, `torp_world_pairs.txt`, `torp_construct_pairs.txt`, `starbase_pairs.txt`, `world_pairs.txt` (with `SL_MOD_VS=<target>:<factor>`).

**Target Prediction:** a lasers round robin twice, without and with TP for both sides (`SL_DUEL_TECHS`), plus small equal-cost fights (1 carrier vs 8 corvettes, 2 carriers vs 16, 2 carriers vs 4 cruisers, 1 cruiser vs 4 corvettes, 2 cruisers vs 4 destroyers, 4 destroyers vs 8 corvettes). On hold.

**Marks** (pre-Symmetry, not re-tested since): `mode=mark_grid` (Mk N+1 vs the next class's Mk N at equal cost, aim for a near tie) and `mode=size_grid -f marks="1 2 3 4"`. Budget 6725 was chosen to field exactly 5 Mk IV carriers.

**Other duel env vars:** `SL_DUEL_SCALE=class:k[:ha]` (scale a class's toughness; `ha` = hull and armor only), `SL_DUEL_SHIFT=class:N` (move N shield into hull), `SL_DUEL_FREE_TECHS=1`, `SL_DUEL_TECHS` / `_A` / `_B`, `SL_DUEL_MAP=1` (real map instead of an empty arena), `SL_DUEL_HOLD`, `SL_DUEL_NOMOVEPEN`, `SL_MOD_DMG`, `SL_MOD_VS`, `SL_DRONE_SPEED/_HULL/_R`.

## AI tests (full games)

```bash
gh workflow run balance.yml -f mode=sims -f runs=6 -f minutes=60 -f speed=4
```
- 30 AI-vs-AI games, 6 per system. Seeds include the run id, so every batch differs; use `mode=single` / `tools/dispatch.sh` for same-seed comparisons. `players=2..8` for free-for-alls.
- Measures: games with a winner (out of 30) and average length. Batches swing by a few games, so call a change better only when it clearly beats that. Test one AI change per batch, against the previous batch.
- Logs:
  - `AIBUD` lines: budget, mode, yards and upkeep cap, one a minute per side.
  - `CLOG` lines: what happened to each colony ship.
  - Sim JSON: per-minute samples (`worlds`, `minerals`, `upkeep`, `upkeep_mult`, `habitable`, `free_habitable`, ...) and counters (`colony_used`, `colony_killed_env`, ...).
  - Optional extra logs: `SL_AI_FORTS_LOG`, `SL_SPICE_LOG`, `SL_ECON_LOG`.
- Most "draws" are one-sided games where the winner is still grinding at the limit; read the logs before calling a game even.
- The AI must never cheat: it sees only what its own fog of war allows.

**Neural AI / RL:**
- `tools/nn_validate.sh <weights> <games per system>` plays the network against the scripted AI on all 5 systems, alternating sides, 40 min each.
- `tools/es_train.pl` (evolution strategies) pushes jobs to the nn-train branch and runs `mode=nn_batch` (`SL_NN_WEIGHTS`, `SL_NN_SIDE`, `SL_NN_OPP_WEIGHTS`).
- PPO lives in `tools/rl/` (curriculum strike → hunt → expand → L1 → L2 → L5); paused.
- 16× with physics steps capped trains 27% faster than 8× with the same kills per game. `SL_PHYS_TICKS=30` was rejected (30% fewer kills).
- Watch reward loopholes: an approach reward that counted only the 8 closest ships was farmed for about +1,600 per game.

## Pitfalls and lessons

- **Default budget 6725** in the workflow: forgetting `-f budget=2400` tests large fights.
- **GitHub API rate limit:** frequent `gh run watch` polling used up the hourly allowance and downloads failed. Poll every 3–5 minutes or less often.
- **20-job limit:** a `runs=20` test uses 21 jobs, so several such tests queue one behind another. Use small `runs` and per-class lists to run candidates side by side.
- **Art, turrets and hitboxes move balance.** Turret range is measured from each turret, and turn rate is `48 / radius`. Toughness-scaled hitboxes made carriers win 100% of duels; restoring the old radii fixed that, and the remaining cruiser edge (68%) came from its turrets moving 16–22 px forward on the new art (old turret positions matched the baseline within ±3%). Re-test classes after any ship art, turret or radius change.
- **Overkill:** without Overkill Awareness, multi-gun ships waste 11–20% of shots in fleet fights, which favours swarms.
- **Movement behaviours change results:** corvette circling inflated big-ship miss rates and was removed; Target Prediction leads once overshot braking corvettes and flipped matchups.
- **Cross-contamination:** a Mod's base lasers come from its class, so changing carrier lasers moved Tractor Beams (40% → 64%). Plain-class weights in the 16-loadout field depend on the others' Mods.
- **Gun-count effects:** a shared EMP cooldown made Inhibitor bad on carriers; scaling it as 4 s / gun count fixed it.
- **Estimates miss nonlinear effects:** guns × toughness underrates range (starbase and outpost reach 260), and toughness changes act nonlinearly, so when two runs bracket the target, split the difference.
- **Sensitivity varies:** 1.5–2× Mod buffs barely showed, but +12% damage moved a variant by +0.33.
- **Sims find AI bugs:** gas giants counted as free worlds, corvette-only builds when out of spice, bombarding only small worlds, colony ships dying in nebulae, stalled fog-memory guesses.

## Baselines

- **Classes, Symmetry step 8 (10-22):** toughness corvette 150 (66/50/34), destroyer 300 (99/132/69), cruiser 800 (264/184/352), carrier 2400 (552/792/1056). Weights destroyer +0.04, carrier +0.01, corvette −0.01, cruiser −0.03.
- **Pre-resize (409d03c):** win rates carrier 64.4, cruiser 57.4, corvette 42.8, destroyer 35.4%; weights within ±0.05.
- **After the resize, old hitboxes (current main):** cruiser 68.1%, weight +0.07 → being tuned with cruiser toughness.
- **Mods pass 5** (`rr_all16x9`, 2400): all −0.01 to +0.06. Damage: Homing Missiles 0.54, Flak 0.67, Cluster Bombs 0.45, Tractor 0.51, Kinetic Repeaters 0.46, PD Lattice 0.91, Interceptor Drones 2.45.
- **Variants pass 4:** Plazer 0.79, Breacher 0.81, Ravager 0.83, Disruptor 0.36, Inhibitor 0.83 (EMP cooldown 4 s / guns); all −0.02 to +0.05 over plain.
- **Defense (free techs):** Deflectors −6/−7/−10% → +71; Shields +73, Armor +68, Hull +69.
- **Constructs (20 duels per pairing):** Outpost 2750 → +0.09 (two together −0.06); Starbase 4900 → −0.07.
- **AI sims (10-23/24, 30 games, 60 min):** 20–22 of 30 end with a winner, average about 44 min.
