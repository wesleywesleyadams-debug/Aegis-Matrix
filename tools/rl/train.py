"""PPO training for the learning AI (see model.py, env.py, RLAgent.gd).

Runs N headless games at once (each a Godot process the agent plays one side
of, against the scripted AI), batches their observations through the policy
on the GPU, and learns from the outcome:
  reward = winning: 1000 for an instant win, falling 12.5 a minute (750 at
           20 min, 500 at 40, 0 at 80); LOSS (-300) for losing
         + fighting: what enemy ships/constructs it destroys were worth / 100,
           minus what it loses / 100 (so it learns to trade well)
         + SIEGE: 100 per whole enemy starbase hull worth of damage dealt
         + DAMAGE: 10 per whole enemy ship/construct worth of damage dealt, minus
           the same for damage taken (SIEGE likewise for starbases)
         + TIMEOUT (-100) when a real match runs out of time
         + BOMBARD: 0.2 per enemy pop bombarded away (below its low point)
         + DISCOVER: 10 the first time each enemy starbase/world is seen
         + APPROACH: 0.05 per unit its spearhead closes on a seen enemy starbase
           (minus the same for moving away)
         + BIG (20) per enemy starbase destroyed, enemy world depopulated, or
           new world colonized
         + curiosity: NEW_ACTION (2) for each kind of action (verb + what it
           builds/researches) the first time in a match, at most NEW_CAP (10)
           per match; repeats earn nothing (they could be farmed).

Curriculum: the opponent starts as a sitting duck (level 1), then a turtle
that never attacks (2), a slow scripted AI (3), the full scripted AI (4) and
then straight to self-play (5) once it beats the turtle - levels 3-4 are
skipped. In self-play each game's opponent is a past version of itself from
a pool (a new one joins every SNAPSHOT updates, the last POOL kept), and
TEST_SHARE of games are against the full scripted AI as a fixed yardstick.
The agent moves up a level once it wins PROMOTE of its last 20 games at the
current one (the stage is saved in the checkpoint; --stage overrides). First come
three drills - strike, hunt, expand - before real matches (see STAGES).

Usage (from the project root, with the venv's python):
  sd-venv/Scripts/python.exe tools/rl/train.py --envs 4 --updates 1000
Checkpoints and a log go to tools/rl/runs/ (not committed). --resume picks
up the last checkpoint.
"""
import argparse, copy, csv, os, random, shutil, threading, time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import torch

from env import StarEnv
from model import Policy, collate, SLOTS
from replay import render_replay

SYSTEMS = ["orion_reach", "vega_drift", "kharon_expanse", "tethys_cluster", "sable_verge", "random"]
## The only reward: winning, scaled up the faster it happens.
WIN_REWARD = 1000.0
## Points the win reward loses per game minute (0 at 80 minutes).
WIN_DECAY = 12.5
## Progress rewards (from the game's tally of what this side did).
LOSS = -300.0
VALUE_SCALE = 1.0 / 100.0
BIG = 20.0
## Per thousandth of an enemy starbase's hull destroyed (100 for a whole one).
SIEGE = 0.1
## Per thousandth of an enemy ship's or construct's toughness damaged (10 a whole one).
DAMAGE = 0.01
## Per tenth of enemy population bombarded away (0.2 per pop).
BOMBARD = 0.02
## The first sight of each enemy starbase or world in a match.
DISCOVER = 10.0
## Per unit its spearhead closes (on average) on a seen enemy starbase; moving
## away costs the same, so it can't be farmed (about 10-15 for a final approach,
## since a starbase is usually only seen from close in).
APPROACH = 0.05
## Curriculum: share of the last 20 games at a level it must win to move up.
PROMOTE = 0.5
## Level 1: the sitting duck's starbase starts at DUCK_START of its toughness
## and is multiplied by DUCK_GROW (up to full) each time the agent wins.
## Level 1 is passed only at full toughness.
DUCK_START = 0.01
DUCK_GROW = 1.5
## The curriculum, in order: three drills (short practice scenarios against a
## sitting duck), then real matches - sitting duck (L1), turtle (L2) and
## self-play (L5). Each is passed by winning PROMOTE of its last 20 games.
##   strike: a fleet starts beside the enemy starbase; destroy it.
##   hunt:   a fleet starts midway across the map; find and destroy it.
##   expand: economy only; own Game.EXPAND_GOAL worlds to win.
STAGES = ["strike", "hunt", "expand", "L1", "L2", "L5"]
DRILL_MINUTES = {"strike": 5.0, "hunt": 6.0, "expand": 8.0}
## Strike / hunt: the enemy starbase's toughness (an 8-ship fleet sent
## straight in wins in under a minute at 0.1; at full it can't). 0.05 for an
## easier start.
DRILL_DUCK = 0.05
## Strike / hunt adapt to the agent: difficulty d (0-1) rises DRILL_STEP on a
## win and falls on a loss, so it hovers near 50% wins. d sets how far out the
## fleet starts (Game._drill_fleet) and the starbase's toughness, from
## DRILL_TOUGH[0] to DRILL_TOUGH[1]. The drill is passed at d = 1.
DRILL_STEP = 0.05
DRILL_TOUGH = (0.03, 0.3)
## Every KEEP_EVERY updates: a numbered copy of the checkpoint, and the next
## game in env 0 is traced for a replay image (runs/replays/).
KEEP_EVERY = 50
## Reward parts, for the per-game breakdown.
PARTS = ["win", "loss", "trade", "siege", "damage", "bombard", "discover", "approach", "big", "curious"]
## Self-play: how often (updates) the frozen opponent catches up with the learner.
SNAPSHOT = 25
POOL = 8
TEST_SHARE = 0.2
## Curiosity: a kind of action (verb, object) new this match, capped.
NEW_ACTION = 2.0
## A real match (not a drill) that runs out of time.
TIMEOUT = -100.0
## Rewards are multiplied by this before training (what is logged stays in
## points): the value head then predicts returns of a few units instead of
## ~1000, which keeps its updates stable. Preferences are unchanged.
REWARD_SCALE = 0.01
NEW_CAP = 10.0
## The game's time limit in seconds (set from --minutes).
LIMIT = 2400.0
RUNS = os.path.join(os.path.dirname(__file__), "runs")


def reward_of(prev, cur, real_match=False):
    """The step's reward, split into PARTS (they sum to the reward)."""
    p = dict.fromkeys(PARTS, 0.0)
    a, b = prev.get("tally", {}), cur.get("tally", {})
    if a and b:
        d = lambda k: max(0, b.get(k, 0) - a.get(k, 0))
        p["trade"] = VALUE_SCALE * (d("kill_value") - d("lost_value"))
        # Damage taken costs exactly what the same damage dealt earns.
        p["siege"] = SIEGE * (d("starbase_damage") - d("starbase_hurt"))
        p["damage"] = DAMAGE * (d("damage_dealt") - d("damage_hurt"))
        p["bombard"] = BOMBARD * d("pop_bombarded")
        p["discover"] = DISCOVER * d("discovered")
        p["big"] = BIG * (d("starbase_kills") + d("planet_kills") + d("colonized"))
    if "closed" in prev and "closed" in cur:
        p["approach"] = APPROACH * (cur["closed"] - prev["closed"])
    if cur.get("done"):
        if cur.get("won"):
            # 1000 for an instant win, 750 at 20 min, 500 at 40, 0 at 80+.
            p["win"] = max(0.0, WIN_REWARD - WIN_DECAY * cur.get("t", 0.0) / 60.0)
        elif cur.get("lost"):
            p["loss"] = LOSS
        elif real_match:
            p["loss"] = TIMEOUT   # ran out of time: a small loss, so stalling doesn't pay
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--envs", type=int, default=4)
    ap.add_argument("--steps", type=int, default=128, help="steps per env per update")
    ap.add_argument("--updates", type=int, default=1000)
    ap.add_argument("--minutes", type=float, default=12)
    ap.add_argument("--speed", type=float, default=8)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--ent", type=float, default=0.01, help="exploration bonus (entropy weight)")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--reset-value", action="store_true", help="re-learn the value head (after a reward change)")
    ap.add_argument("--port", type=int, default=47100)
    ap.add_argument("--stage", default="", help="force a curriculum stage (" + ", ".join(STAGES) + ")")
    args = ap.parse_args()
    global LIMIT
    LIMIT = args.minutes * 60.0
    os.makedirs(RUNS, exist_ok=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    pol = Policy().to(dev)
    opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
    ckpt = os.path.join(RUNS, "ckpt.pt")
    start = 0
    si = 0          # index into STAGES
    duck = DUCK_START
    drill_d = {"strike": 0.0, "hunt": 0.0}
    if args.resume and os.path.exists(ckpt):
        st = torch.load(ckpt, map_location=dev)
        # strict=False: parts added since (e.g. group orders) start fresh.
        missing = pol.load_state_dict(st["model"], strict=False).missing_keys
        if missing:
            print("new model parts:", ", ".join(missing))
            opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
        else:
            opt.load_state_dict(st["opt"])
        start = st["update"]
        si = st.get("stage", 0)
        duck = st.get("duck", DUCK_START)
        drill_d.update(st.get("drill_d", {}))
        print("resumed at update", start)
        if args.reset_value:
            for m in pol.value:
                if hasattr(m, "reset_parameters"):
                    m.reset_parameters()
            opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
            print("value head reset")
    log = open(os.path.join(RUNS, "log.csv"), "a", newline="")
    lw = csv.writer(log)

    if args.stage:
        si = STAGES.index(args.stage)
    stage = lambda: STAGES[si]
    # Self-play: a pool of past versions; each game gets its own frozen copy
    # (one per StarEnv, so the env threads never share one).
    pool_sd = [copy.deepcopy(pol.state_dict())]

    def make_opponent(net):
        def opponent(o):
            with torch.no_grad():
                acts, _, _, _ = net(collate([o], dev))
            return {"orders": [[int(a) for a in x] for x in acts[0].cpu().numpy() if x[0] >= 0]}
        return opponent
    print("curriculum stage", stage())
    envs = [StarEnv(args.port + i, system=random.choice(SYSTEMS), minutes=args.minutes, speed=args.speed,
                    side=random.choice([1, 2]), log=os.path.join(RUNS, f"env{i}.log")) for i in range(args.envs)]
    # Each slot also has a spare game, launched in the background while the
    # current one plays, so a finished game is replaced at once instead of
    # every slot waiting ~4 s for a new Godot to start. A launched game waits
    # at its first decision until it is swapped in.
    spare_envs = [StarEnv(args.port + 1000 + i, minutes=args.minutes, speed=args.speed,
                          log=os.path.join(RUNS, f"env{i}b.log")) for i in range(args.envs)]
    for i in range(args.envs):
        envs[i].slot = spare_envs[i].slot = i
    games = open(os.path.join(RUNS, "games.csv"), "a", newline="")
    gw = csv.writer(games)
    pool = ThreadPoolExecutor(args.envs)

    def fresh(e):
        s = stage()
        e.stage = s
        e.drill = s if s in DRILL_MINUTES else ""
        e.minutes = DRILL_MINUTES.get(s, args.minutes)
        e.level = {"L2": 2, "L5": 5}.get(s, 1)
        e.drill_d = drill_d.get(s, 0.0)
        e.duck = duck if s == "L1" else (DRILL_TOUGH[0] + (DRILL_TOUGH[1] - DRILL_TOUGH[0]) * e.drill_d if s in drill_d else 1.0)
        e.trace = ""
        if e.slot == 0 and want_trace[0]:
            want_trace[0] = False
            os.makedirs(os.path.join(RUNS, "replays"), exist_ok=True)
            e.trace = os.path.join(RUNS, "replays", "trace.jsonl")
        if s == "L5":
            if random.random() < TEST_SHARE:
                e.level = 4   # yardstick game against the full scripted AI
                e.stage = "L4"
            else:
                if getattr(e, "frozen", None) is None:
                    e.frozen = copy.deepcopy(pol).eval()
                e.frozen.load_state_dict(random.choice(pool_sd))
                e.opponent = make_opponent(e.frozen)
        e.system = random.choice(SYSTEMS)
        e.side = random.choice([1, 2])
        return e.reset()

    want_trace = [False]
    obs = list(pool.map(fresh, envs))
    launcher = ThreadPoolExecutor(args.envs)
    spares = [launcher.submit(fresh, e) for e in spare_envs]
    ep_ret = [0.0] * args.envs
    ep_parts = [dict.fromkeys(PARTS, 0.0) for _ in range(args.envs)]
    tried = [set() for _ in range(args.envs)]   # action kinds used this match
    results = []
    gamma, lam, clip = 0.995, 0.95, 0.2
    for upd in range(start, args.updates):
        t0 = time.time()
        buf = {"obs": [], "act": [], "logp": [], "val": [], "rew": [], "done": []}
        for step in range(args.steps):
            with torch.no_grad():
                acts, logp, _, val = pol(collate(obs, dev))
            acts_np = acts.cpu().numpy()
            orders = [{"orders": [[int(a) for a in o] for o in acts_np[i] if o[0] >= 0]} for i in range(args.envs)]
            nxt = list(pool.map(lambda iv: envs[iv[0]].step(iv[1]), enumerate(orders)))
            rews, dones = [], []
            for i in range(args.envs):
                parts = reward_of(obs[i], nxt[i], envs[i].drill == "")
                for o in orders[i]["orders"]:
                    kind = (o[1], o[2])   # verb, object (-1 = none)
                    if kind not in tried[i]:
                        tried[i].add(kind)
                        if len(tried[i]) * NEW_ACTION <= NEW_CAP:
                            parts["curious"] += NEW_ACTION
                for k, v in parts.items():
                    ep_parts[i][k] += v
                r = float(sum(parts.values()))
                ep_ret[i] += r
                rews.append(r * REWARD_SCALE)
                dones.append(bool(nxt[i].get("done")))
            buf["obs"].append(obs); buf["act"].append(acts.cpu()); buf["logp"].append(logp.cpu())
            buf["val"].append(val.cpu()); buf["rew"].append(torch.tensor(rews)); buf["done"].append(torch.tensor(dones, dtype=torch.float32))
            for i in range(args.envs):
                if dones[i]:
                    won = bool(nxt[i].get("won"))
                    results.append((won, nxt[i].get("lost"), ep_ret[i], envs[i].system, envs[i].stage, dict(ep_parts[i])))
                    gw.writerow([upd + 1, envs[i].stage, int(won), round(nxt[i].get("t", 0.0) / 60.0, 2), round(ep_ret[i], 1)]
                                + [round(ep_parts[i][k], 1) for k in PARTS])
                    games.flush()
                    # Every finished drill game moves its difficulty a step, even
                    # one launched (as a spare) before the last change.
                    if envs[i].stage in drill_d:
                        k = envs[i].stage
                        drill_d[k] = round(min(1.0, max(0.0, drill_d[k] + (DRILL_STEP if won else -DRILL_STEP))), 3)
                    if envs[i].trace:
                        render_replay(envs[i].trace, os.path.join(RUNS, "replays", f"upd{upd + 1}_{envs[i].stage}_{'won' if won else 'lost'}.png"))
                    if envs[i].stage == "L1" and won and envs[i].duck >= duck and duck < 1.0:
                        duck = min(1.0, duck * DUCK_GROW)
                        print(f"DUCK toughness now {duck:.3f}", flush=True)
                    # Promotion: wins PROMOTE of its last 20 games at this stage.
                    here = [r for r in results if r[4] == stage()][-20:]
                    if si < len(STAGES) - 1 and (stage() != "L1" or duck >= 1.0) and drill_d.get(stage(), 1.0) >= 1.0 and len(here) >= 20 \
                            and sum(1 for r in here if r[0]) >= PROMOTE * 20:
                        si += 1
                        print(f"PROMOTED to curriculum stage {stage()}", flush=True)
                    ep_ret[i] = 0.0
                    ep_parts[i] = dict.fromkeys(PARTS, 0.0)
                    tried[i] = set()
            # Finished games swap in their slot's spare; the finished one is
            # closed and relaunched as the next spare in the background.
            for i in range(args.envs):
                if dones[i]:
                    nxt[i] = spares[i].result()
                    envs[i], spare_envs[i] = spare_envs[i], envs[i]
                    spares[i] = launcher.submit(fresh, spare_envs[i])
            obs = nxt
        # GAE.
        with torch.no_grad():
            _, _, _, last_v = pol(collate(obs, dev))
        last_v = last_v.cpu()
        T = args.steps
        vals = torch.stack(buf["val"]); rews = torch.stack(buf["rew"]); dones = torch.stack(buf["done"])
        adv = torch.zeros(T, args.envs); gae = torch.zeros(args.envs)
        for t in reversed(range(T)):
            nv = last_v if t == T - 1 else vals[t + 1]
            nonterm = 1.0 - dones[t]
            delta = rews[t] + gamma * nv * nonterm - vals[t]
            gae = delta + gamma * lam * nonterm * gae
            adv[t] = gae
        ret = adv + vals
        flat_obs = [o for step in buf["obs"] for o in step]
        flat_act = torch.cat(buf["act"]); flat_logp = torch.cat(buf["logp"])
        flat_adv = adv.reshape(-1); flat_ret = ret.reshape(-1)
        flat_adv = (flat_adv - flat_adv.mean()) / (flat_adv.std() + 1e-8)
        n = len(flat_obs); mb = 64
        stats = []
        for epoch in range(3):
            perm = np.random.permutation(n)
            for s in range(0, n, mb):
                idx = perm[s:s + mb]
                x = collate([flat_obs[i] for i in idx], dev)
                _, lp, ent, v = pol(x, flat_act[idx].to(dev))
                ratio = torch.exp(lp - flat_logp[idx].to(dev))
                a = flat_adv[idx].to(dev)
                pl = -torch.min(ratio * a, ratio.clamp(1 - clip, 1 + clip) * a).mean()
                vl = (v - flat_ret[idx].to(dev)).pow(2).mean()
                loss = pl + 0.5 * vl - args.ent * ent.mean()
                opt.zero_grad(); loss.backward()
                torch.nn.utils.clip_grad_norm_(pol.parameters(), 0.5)
                opt.step()
                stats.append((pl.item(), vl.item(), ent.mean().item()))
        pl, vl, en = np.mean(stats, 0)
        recent = [r for r in results if r[4] == stage()][-20:]
        tests = [r for r in results if r[4] == "L4"][-20:]
        vs_ai = sum(1 for r in tests if r[0]) / max(len(tests), 1)
        win = sum(1 for r in recent if r[0]) / max(len(recent), 1)
        mean_ret = np.mean([r[2] for r in recent]) if recent else 0.0
        print(f"upd {upd + 1}  {stage()}  duck {duck:.3f}  drill {drill_d.get(stage(), 0):.2f}  games {len(results)}  win(last20) {win:.2f}  vsAI {vs_ai:.2f}/{len(tests)}  ret {mean_ret:+.1f}  "
              f"pol {pl:+.3f} val {vl:.3f} ent {en:.2f}  {time.time() - t0:.0f}s", flush=True)
        if recent and (upd + 1) % 10 == 0:
            print("  parts/game " + "  ".join(f"{k} {np.mean([r[5][k] for r in recent]):+.1f}" for k in PARTS), flush=True)
        lw.writerow([upd + 1, stage(), len(results), win, mean_ret, pl, vl, en]); log.flush()
        if (upd + 1) % SNAPSHOT == 0 and stage() == "L5":
            pool_sd.append(copy.deepcopy(pol.state_dict()))
            del pool_sd[:-POOL]
        torch.save({"model": pol.state_dict(), "opt": opt.state_dict(), "update": upd + 1, "stage": si, "duck": duck, "drill_d": drill_d}, ckpt)
        if (upd + 1) % KEEP_EVERY == 0:
            shutil.copyfile(ckpt, os.path.join(RUNS, f"ckpt_{upd + 1}.pt"))
            want_trace[0] = True
    for e in envs + spare_envs:
        e.close()


if __name__ == "__main__":
    main()
