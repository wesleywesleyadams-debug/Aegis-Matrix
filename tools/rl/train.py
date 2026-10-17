"""PPO training for the learning AI (see model.py, env.py, RLAgent.gd).

Runs N headless games at once (each a Godot process the agent plays one side
of, against the scripted AI), batches their observations through the policy
on the GPU, and learns from the outcome:
  reward = winning (+WIN_REWARD) above all; a faint hint each step from the
           change in (own score - best enemy score) / 1000,
           +WIN_REWARD (100) for a win, -5 for a loss.

Usage (from the project root, with the venv's python):
  sd-venv/Scripts/python.exe tools/rl/train.py --envs 4 --updates 1000
Checkpoints and a log go to tools/rl/runs/ (not committed). --resume picks
up the last checkpoint.
"""
import argparse, csv, os, random, time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import torch

from env import StarEnv
from model import Policy, collate, SLOTS

SYSTEMS = ["orion_reach", "vega_drift", "kharon_expanse", "tethys_cluster", "sable_verge", "random"]
## Winning is what matters: a big reward next to the small per-step score
## signal (and -5 for a loss).
WIN_REWARD = 100.0
RUNS = os.path.join(os.path.dirname(__file__), "runs")


def reward_of(prev, cur):
    # Score shaping is only a faint hint (a whole game sums to a few points);
    # winning (WIN_REWARD) is the goal.
    r = ((cur["score"] - cur["enemy_score"]) - (prev["score"] - prev["enemy_score"])) / 1000.0
    if cur.get("done"):
        r += WIN_REWARD if cur.get("won") else (-5.0 if cur.get("lost") else 0.0)
    return float(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--envs", type=int, default=4)
    ap.add_argument("--steps", type=int, default=128, help="steps per env per update")
    ap.add_argument("--updates", type=int, default=1000)
    ap.add_argument("--minutes", type=float, default=40)
    ap.add_argument("--speed", type=float, default=8)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--port", type=int, default=47100)
    args = ap.parse_args()
    os.makedirs(RUNS, exist_ok=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    pol = Policy().to(dev)
    opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
    ckpt = os.path.join(RUNS, "ckpt.pt")
    start = 0
    if args.resume and os.path.exists(ckpt):
        st = torch.load(ckpt, map_location=dev)
        pol.load_state_dict(st["model"]); opt.load_state_dict(st["opt"]); start = st["update"]
        print("resumed at update", start)
    log = open(os.path.join(RUNS, "log.csv"), "a", newline="")
    lw = csv.writer(log)

    envs = [StarEnv(args.port + i, system=random.choice(SYSTEMS), minutes=args.minutes, speed=args.speed,
                    side=random.choice([1, 2]), log=os.path.join(RUNS, f"env{i}.log")) for i in range(args.envs)]
    pool = ThreadPoolExecutor(args.envs)

    def fresh(e):
        e.system = random.choice(SYSTEMS)
        e.side = random.choice([1, 2])
        return e.reset()

    obs = list(pool.map(fresh, envs))
    ep_ret = [0.0] * args.envs
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
                ep_ret[i] += r
                rews.append(r)
                dones.append(bool(nxt[i].get("done")))
            buf["obs"].append(obs); buf["act"].append(acts.cpu()); buf["logp"].append(logp.cpu())
            buf["val"].append(val.cpu()); buf["rew"].append(torch.tensor(rews)); buf["done"].append(torch.tensor(dones, dtype=torch.float32))
            for i in range(args.envs):
                if dones[i]:
                    results.append((nxt[i].get("won"), nxt[i].get("lost"), ep_ret[i], envs[i].system))
                    ep_ret[i] = 0.0
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
                loss = pl + 0.5 * vl - 0.003 * ent.mean()
                opt.zero_grad(); loss.backward()
                torch.nn.utils.clip_grad_norm_(pol.parameters(), 0.5)
                opt.step()
                stats.append((pl.item(), vl.item(), ent.mean().item()))
        pl, vl, en = np.mean(stats, 0)
        recent = results[-20:]
        win = sum(1 for r in recent if r[0]) / max(len(recent), 1)
        mean_ret = np.mean([r[2] for r in recent]) if recent else 0.0
        print(f"upd {upd + 1}  games {len(results)}  win(last20) {win:.2f}  ret {mean_ret:+.1f}  "
              f"pol {pl:+.3f} val {vl:.3f} ent {en:.2f}  {time.time() - t0:.0f}s", flush=True)
        lw.writerow([upd + 1, len(results), win, mean_ret, pl, vl, en]); log.flush()
        torch.save({"model": pol.state_dict(), "opt": opt.state_dict(), "update": upd + 1}, ckpt)
    for e in envs:
        e.close()


if __name__ == "__main__":
    main()
