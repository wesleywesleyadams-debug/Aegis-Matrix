"""Offline perception test: can the policy's encoder tell which target is the
visible enemy starbase? Collects hunt-drill observations (with SL_RL_LABELS,
which adds the true answer), then trains a small pointer head on them - once
with the encoder frozen (does the current representation already contain it?)
and once fine-tuning everything (can the architecture learn it at all?) - and
reports accuracy on held-out states against the chance level.

  python perception_test.py [samples]
"""
import os, random, sys
from concurrent.futures import ThreadPoolExecutor

import torch
import torch.nn as nn

from env import StarEnv, random_orders
from model import Policy, collate

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
RUNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs")


def collect(slot, want):
    os.environ["SL_RL_LABELS"] = "1"
    out = []
    while len(out) < want:
        e = StarEnv(48200 + slot, system=random.choice(["orion_reach", "random"]), minutes=6, level=1,
                    side=random.choice([1, 2]), log=os.path.join(RUNS, f"perc{slot}.log"))
        e.drill = "hunt"; e.drill_d = random.random(); e.duck = 0.1
        o = e.reset()
        while not o.get("done") and len(out) < want:
            if o.get("label_foe_sb", -1) >= 0 and random.random() < 0.5:
                out.append(o)
            o = e.step(random_orders(o, k=random.randint(0, 4)))
        e.close()
    return out


def run(data, dev, finetune):
    pol = Policy().to(dev)
    st = torch.load(os.path.join(RUNS, "ckpt.pt"), map_location=dev)
    st["model"]["slot"] = st["model"]["slot"][:pol.slot.shape[0]]
    pol.load_state_dict(st["model"], strict=False)
    d = pol.slot.shape[1]
    head = nn.Linear(2 * d, d).to(dev)
    params = list(head.parameters()) + (list(pol.parameters()) if finetune else [])
    opt = torch.optim.Adam(params, lr=3e-4 if finetune else 1e-3)
    random.Random(0).shuffle(data)
    cut = int(len(data) * 0.8)
    train, test = data[:cut], data[cut:]

    def batch_loss(obs):
        x = collate(obs, dev)
        g, _, targets, tgt_m, _ = pol.encode(x)
        if not finetune:
            g, targets = g.detach(), targets.detach()
        lg = (targets @ head(g).unsqueeze(-1)).squeeze(-1).masked_fill(~tgt_m, -1e9)
        y = torch.tensor([o["label_foe_sb"] for o in obs], device=dev)
        return nn.functional.cross_entropy(lg, y), (lg.argmax(-1) == y).float().mean().item()

    for epoch in range(15):
        random.shuffle(train)
        for i in range(0, len(train), 32):
            loss, _ = batch_loss(train[i:i + 32])
            opt.zero_grad(); loss.backward(); opt.step()
    with torch.no_grad():
        accs = [batch_loss(test[i:i + 64])[1] for i in range(0, len(test), 64)]
    return sum(accs) / len(accs)


if __name__ == "__main__":
    with ThreadPoolExecutor(3) as ex:
        parts = list(ex.map(lambda s: collect(s, N // 3), range(3)))
    data = [o for p in parts for o in p]
    chance = sum(1.0 / (len(o["entities"]) + len(o["targets"])) for o in data) / len(data)
    print(f"{len(data)} labelled states; chance accuracy {chance:.1%}", flush=True)
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"frozen encoder (does it already know?):  {run(list(data), dev, False):.1%}", flush=True)
    print(f"fine-tuned encoder (can it learn it?):   {run(list(data), dev, True):.1%}", flush=True)
