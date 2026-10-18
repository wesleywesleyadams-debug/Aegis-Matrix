"""Plays the learning AI in a normal match (the lobby's "Neural AI" slots).

The game starts this with the number of neural sides; each side's RLAgent
connects, and gets orders from the policy until its match ends. It loads the
newest complete checkpoint copy (runs/ckpt_<update>.pt, written by train.py
while it trains), so a new match always gets the latest version.

  python serve.py --port 47900 --sides 1 [--ckpt runs/ckpt_3800.pt]
"""
import argparse, glob, json, os, re, socket, threading

import torch

from model import Policy, collate, SLOTS

RUNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs")
NL = bytes([10])


def newest_checkpoint():
    numbered = glob.glob(os.path.join(RUNS, "ckpt_*.pt"))
    if numbered:
        return max(numbered, key=lambda p: int(re.findall(r"ckpt_(\d+)\.pt", p)[0]))
    return os.path.join(RUNS, "ckpt.pt")


def load_policy(dev, path=""):
    path = path or newest_checkpoint()
    st = torch.load(path, map_location=dev)
    st["model"]["slot"] = st["model"]["slot"][:SLOTS]
    pol = Policy().to(dev)
    pol.load_state_dict(st["model"], strict=False)
    pol.eval()
    print(f"serving {os.path.basename(path)} (update {st.get('update')})", flush=True)
    return pol


def play(conn, pol, dev, lock):
    buf = b""
    with conn:
        while True:
            while NL not in buf:
                chunk = conn.recv(1 << 20)
                if not chunk:
                    return
                buf += chunk
            line, buf = buf.split(NL, 1)
            obs = json.loads(line)
            if obs.get("done"):
                return
            with lock, torch.no_grad():
                acts, _, _, _ = pol(collate([obs], dev))
            orders = [[int(a) for a in x] for x in acts[0].cpu().numpy() if x[0] >= 0]
            conn.sendall(json.dumps({"orders": orders}).encode() + NL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=47900)
    ap.add_argument("--sides", type=int, default=1)
    ap.add_argument("--ckpt", default="", help="checkpoint to play (default: newest ckpt_<update>.pt)")
    args = ap.parse_args()
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(args.sides)
    srv.settimeout(120)
    pol = load_policy(dev, args.ckpt)
    lock = threading.Lock()
    threads = []
    for _ in range(args.sides):
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            break
        t = threading.Thread(target=play, args=(conn, pol, dev, lock), daemon=True)
        t.start()
        threads.append(t)
    srv.close()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
