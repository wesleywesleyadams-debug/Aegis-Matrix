"""PPO training for the learning AI (see model.py, env.py, RLAgent.gd).

Runs N headless games at once (each a Godot process the agent plays one side
of, against the scripted AI), batches their observations through the policy
on the GPU, and learns from the outcome:
  reward = winning: 1000 for an instant win, falling 12.5 a minute (750 at
           20 min, 500 at 40, 0 at 80); LOSS (-300) for losing
         + fighting: what enemy ships/constructs it destroys were worth / 100,
           minus what it loses / 100 (so it learns to trade well)
         + BIG (20) per enemy starbase destroyed, enemy world depopulated, or
           new world colonized
         + curiosity: NEW_ACTION (2) for each kind of action (verb + what it
           builds/researches) the first time in a match, at most NEW_CAP (40)
           per match; repeats earn nothing (they could be farmed).

Curriculum: the opponent starts as a sitting duck (level 1), then a turtle
that never attacks (2), a slow scripted AI (3), the full scripted AI (4) and
then straight to self-play (5) once it beats the turtle - levels 3-4 are
skipped. In self-play each game's opponent is a past version of itself from
a pool (a new one joins every SNAPSHOT updates, the last POOL kept), and
TEST_SHARE of games are against the full scripted AI as a fixed yardstick.
The agent moves up a level once it wins PROMOTE of its last 20 games at the
current one (the level is saved in the checkpoint; --level overrides).

Usage (from the project root, with the venv's python):
  sd-venv/Scripts/python.exe tools/rl/train.py --envs 4 --updates 1000
Checkpoints and a log go to tools/rl/runs/ (not committed). --resume picks
up the last checkpoint.
"""
import argparse, copy, csv, os, random, threading, time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import torch

from env import StarEnv
from model import Policy, collate, SLOTS

SYSTEMS = ["orion_reach", "vega_drift", "kharon_expanse", "tethys_cluster", "sable_verge", "random"]
## The only reward: winning, scaled up the faster it happens.
WIN_REWARD = 1000.0
## Points the win reward loses per game minute (0 at 80 minutes).
WIN_DECAY = 12.5
## Progress rewards (from the game's tally of what this side did).
LOSS = -300.0
VALUE_SCALE = 1.0 / 100.0
BIG = 20.0
## Curriculum: share of the last 20 games at a level it must win to move up.
PROMOTE = 0.5
## Self-play: how often (updates) the frozen opponent catches up with the learner.
SNAPSHOT = 25
POOL = 8
TEST_SHARE = 0.2
## Curiosity: a kind of action (verb, object) new this match, capped.
NEW_ACTION = 2.0
NEW_CAP = 40.0
## The game's time limit in seconds (set from --minutes).
LIMIT = 2400.0
RUNS = os.path.join(os.path.dirname(__file__), "runs")


def reward_of(prev, cur):
    r = 0.0
    a, b = prev.get("tally", {}), cur.get("tally", {})
    if a and b:
        d = lambda k: max(0, b.get(k, 0) - a.get(k, 0))
        r += VALUE_SCALE * (d("kill_value") - d("lost_value"))
        r += BIG * (d("starbase_kills") + d("planet_kills") + d("colonized"))
    if cur.get("done"):
        if cur.get("won"):
            # 1000 for an instant win, 750 at 20 min, 500 at 40, 0 at 80+.
            r += max(0.0, WIN_REWARD - WIN_DECAY * cur.get("t", 0.0) / 60.0)
        elif cur.get("lost"):
            r += LOSS
    return float(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--envs", type=int, default=4)
    ap.add_argument("--steps", type=int, default=128, help="steps per env per update")
    ap.add_argument("--updates", type=int, default=1000)
    ap.add_argument("--minutes", type=float, default=40)
    ap.add_argument("--speed", type=float, default=8)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--ent", type=float, default=0.01, help="exploration bonus (entropy weight)")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--reset-value", action="store_true", help="re-learn the value head (after a reward change)")
    ap.add_argument("--port", type=int, default=47100)
    ap.add_argument("--level", type=int, default=0, help="force a curriculum level (1-4)")
    args = ap.parse_args()
    global LIMIT
    LIMIT = args.minutes * 60.0
    os.makedirs(RUNS, exist_ok=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    pol = Policy().to(dev)
    opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
    ckpt = os.path.join(RUNS, "ckpt.pt")
    start = 0
    level = 1
    if args.resume and os.path.exists(ckpt):
        st = torch.load(ckpt, map_location=dev)
        pol.load_state_dict(st["model"]); opt.load_state_dict(st["opt"]); start = st["update"]
        level = st.get("level", 1)
        print("resumed at update", start)
        if args.reset_value:
            for m in pol.value:
                if hasattr(m, "reset_parameters"):
                    m.reset_parameters()
            opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
            print("value head reset")
    log = open(os.path.join(RUNS, "log.csv"), "a", newline="")
    lw = csv.writer(log)

    if args.level:
        level = args.level
    # Self-play: a pool of past versions; each game gets its own frozen copy
    # (one per env, so the env threads never share one).
    pool_sd = [copy.deepcopy(pol.state_dict())]
    frozens = [copy.deepcopy(pol).eval() for _ in range(args.envs)]

    def make_opponent(net):
        def opponent(o):
            with torch.no_grad():
                acts, _, _, _ = net(collate([o], dev))
            return {"orders": [[int(a) for a in x] for x in acts[0].cpu().numpy() if x[0] >= 0]}
        return opponent
    print("curriculum level", level)
    envs = [StarEnv(args.port + i, system=random.choice(SYSTEMS), minutes=args.minutes, speed=args.speed,
                    side=random.choice([1, 2]), log=os.path.join(RUNS, f"env{i}.log"), level=level) for i in range(args.envs)]
    pool = ThreadPoolExecutor(args.envs)

    def fresh(e):
        e.level = level
        if level >= 5:
            if random.random() < TEST_SHARE:
                e.level = 4   # yardstick game against the full scripted AI
            else:
                k = envs.index(e)
                frozens[k].load_state_dict(random.choice(pool_sd))
                e.opponent = make_opponent(frozens[k])
        e.system = random.choice(SYSTEMS)
        e.side = random.choice([1, 2])
        return e.reset()

    obs = list(pool.map(fresh, envs))
    ep_ret = [0.0] * args.envs
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
                r = reward_of(obs[i], nxt[i])
                for o in orders[i]["orders"]:
                    kind = (o[1], o[2])   # verb, object (-1 = none)
                    if kind not in tried[i]:
                        tried[i].add(kind)
                        if len(tried[i]) * NEW_ACTION <= NEW_CAP:
                            r += NEW_ACTION
                ep_ret[i] += r
                rews.append(r)
                dones.append(bool(nxt[i].get("done")))
            buf["obs"].append(obs); buf["act"].append(acts.cpu()); buf["logp"].append(logp.cpu())
            buf["val"].append(val.cpu()); buf["rew"].append(torch.tensor(rews)); buf["done"].append(torch.tensor(dones, dtype=torch.float32))
            for i in range(args.envs):
                if dones[i]:
                    results.append((nxt[i].get("won"), nxt[i].get("lost"), ep_ret[i], envs[i].system, envs[i].level))
                    # Promotion: wins PROMOTE of its last 20 games at this level.
                    here = [r for r in results if r[4] == level][-20:]
                    if level < 5 and len(here) >= 20 and sum(1 for r in here if r[0]) >= PROMOTE * 20:
                        level = 5 if level >= 2 else level + 1
                        print(f"PROMOTED to curriculum level {level}", flush=True)
                    ep_ret[i] = 0.0
                    tried[i] = set()
            # Finished games restart (in parallel) before the next step.
            redo = [i for i in range(args.envs) if dones[i]]
            if redo:
                fresh_obs = list(pool.map(lambda i: fresh(envs[i]), redo))
                for i, o in zip(redo, fresh_obs):
                    nxt[i] = o
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
        recent = [r for r in results if r[4] == level][-20:]
        tests = [r for r in results if r[4] == 4][-20:]
        vs_ai = sum(1 for r in tests if r[0]) / max(len(tests), 1)
        win = sum(1 for r in recent if r[0]) / max(len(recent), 1)
        mean_ret = np.mean([r[2] for r in recent]) if recent else 0.0
        print(f"upd {upd + 1}  L{level}  games {len(results)}  win(last20) {win:.2f}  vsAI {vs_ai:.2f}/{len(tests)}  ret {mean_ret:+.1f}  "
              f"pol {pl:+.3f} val {vl:.3f} ent {en:.2f}  {time.time() - t0:.0f}s", flush=True)
        lw.writerow([upd + 1, level, len(results), win, mean_ret, pl, vl, en]); log.flush()
        if (upd + 1) % SNAPSHOT == 0 and level >= 5:
            pool_sd.append(copy.deepcopy(pol.state_dict()))
            del pool_sd[:-POOL]
        torch.save({"model": pol.state_dict(), "opt": opt.state_dict(), "update": upd + 1, "level": level}, ckpt)
    for e in envs:
        e.close()


if __name__ == "__main__":
    main()
