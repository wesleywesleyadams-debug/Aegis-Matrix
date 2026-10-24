# Aegis Matrix balance testing

Every balance or AI test starts from this file. Each time the user corrects how testing is done, add the rule here.

## Standing rules

- **Run tests on GitHub Actions** (`.github/workflows/balance.yml`), never locally. A short local game is fine only as a smoke test for script errors.
- **Speed ×4 only.** ×8 distorts results.
- **Never change balance numbers on `main` without the user's OK.** Experiments go on `test/<what>` branches (use a git worktree so the main checkout and its uncommitted work are untouched), run with `--ref <branch>`, and the branches are deleted afterwards.
- **Fixed references:** plain lasers are the balance reference, corvette toughness 150 is the fixed basis, and only Mk I / no-tech lasers and Mods are balanced (see the scope notes in memory/WORKLIST). Tractor Beams' rule is locked.
- **Change one thing per test**, so a result can be pinned on it. When looking for a cause, revert one suspect per branch.
- **Small steps.** Tune toughness in steps of 10 (5 when closing in). Big jumps are rejected.
- **Report results with the conditions** (run id, duels, budget, what changed) and say plainly when a difference is within noise.
- **Art and hitboxes can move balance.** Turret range is measured from each turret (`Ship.gd`), so moving mounts on new art changes effective range; hitbox radius changes who gets hit and turn rate (`48 / radius`). Re-test classes after any ship art, turret or radius change.

## Class balance (duels)

**Goal (current):** every class trades evenly on average in medium fights: class **weight ≈ 0.0**. Win rate is not the target; a class can win 35% or 65% of its duels and still be balanced if its weight is near 0.

**Conditions** (the ones the classes were balanced under):
- Class round robin, Mk I plain lasers: `tools/rr_lasers.txt` (6 pairings, 720 duels).
- Medium budget **2400**, tech costs included (don't set `SL_DUEL_FREE_TECHS`).
- Speed 4, system `orion_reach`, `minutes=240`.

```bash
gh workflow run balance.yml -f mode=round_robin -f runs=20 -f minutes=240 -f speed=4 -f tag=file=tools/rr_lasers.txt -f budget=2400 -f system=orion_reach
```

**Scoring:** `tools/rr_summary.sh <run id>` prints win % and weight per class. Weight = average margin / 100, where margin is the winner's toughness left (positive for wins, negative for losses).

**Baseline (before the ship-size change, commit 409d03c):** weights within ±0.05; win rates carrier 64%, cruiser 57%, corvette 43%, destroyer 35%.

## Speed: test only what you need

- The account runs **20 jobs at once**. A `runs=20` test fills all 20, so several such tests queue one behind another (a full round robin takes ~30–40 min each).
- **Tuning one class:** use a list with only that class's pairings (e.g. 30 lines each of `corvette:1,cruiser:1`, `destroyer:1,cruiser:1`, `cruiser:1,carrier:1` = 180 duels) with `runs=5`, so four candidate values run side by side in ~30–40 min total. Fewer duels are noisier (about ±0.03 weight), so **confirm the chosen value with one full 720-duel run**.

## Other duel options

- `SL_DUEL_FREE_TECHS=1`: listed techs free. Per-side techs: 4th spec field `class:mark:mod:tech+tech`.
- `SL_DUEL_BUDGET=match` for construct duels; construct sides `starbase|outpost|station|gate|depot[:N]`.
- Lists in `tools/`: `rr_lasers.txt` (classes), `rr_mods_laser.txt` (Mods), `rr_variants24x5.txt` / `x9` (variants), `rr_defense20x5.txt` (defense techs), `construct_pairs.txt`.

## AI tests (full games)

- 30 AI-vs-AI games, 6 per system, 60 minutes, speed 4:
  ```bash
  gh workflow run balance.yml -f mode=sims -f runs=6 -f minutes=60 -f speed=4
  ```
- Measures: games with a winner (out of 30) and average length. Batches swing by a few games, so call a change an improvement only when it clearly beats that.
- Logs: `AIBUD` lines (budget, mode, yards, upkeep cap, one a minute per side) and `CLOG` lines (colony ship fates). The sim JSON has per-minute samples (`worlds`, `minerals`, `habitable`, `free_habitable`, ...) and counters (`colony_used`, `colony_killed_env`, ...).
- The AI must never cheat: it sees only what its own fog of war allows.
- Test one AI change per batch, compared against the previous batch.
