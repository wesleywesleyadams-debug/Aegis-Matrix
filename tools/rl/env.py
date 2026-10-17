"""Stardust Dominion as a training environment.

StarEnv launches a headless Godot sim with the RLAgent (scripts/game/RLAgent.gd)
on one side and connects over TCP. Each step: the game sends an observation
(entities + option sets described by stats), we send a decision, the game plays
on for RLAgent.DECIDE seconds. Nothing here knows ship or tech names: options
come as feature rows, so new rules show up as new rows.
"""
import json, os, random, socket, subprocess

GODOT = os.environ.get("GODOT", r"C:/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe")
PROJECT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


class StarEnv:
    def __init__(self, port, system="random", minutes=40, speed=8, side=1, players=2, seed=None, log=None):
        self.port, self.system, self.minutes, self.speed = port, system, minutes, speed
        self.side, self.players, self.seed, self.log = side, players, seed, log
        self.proc = self.conn = None
        self.buf = b""

    def reset(self):
        self.close()
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", self.port))
        srv.listen(1)
        srv.settimeout(120)
        env = dict(os.environ, SL_SIM=f"rl{self.port}", SL_RL_PORT=str(self.port), SL_RL_SIDE=str(self.side),
                   SL_SYSTEM=self.system, SL_SIM_MINUTES=str(self.minutes), SL_SIM_SCALE=str(self.speed),
                   SL_PLAYERS=str(self.players), SL_SEED=str(self.seed if self.seed is not None else random.randrange(1 << 30)))
        out = open(self.log, "w") if self.log else subprocess.DEVNULL
        self.proc = subprocess.Popen([GODOT, "--headless", "--fixed-fps", "60", "--path", PROJECT, "scenes/Main.tscn"],
                                     env=env, stdout=out, stderr=subprocess.STDOUT)
        self.conn, _ = srv.accept()
        srv.close()
        self.conn.settimeout(300)
        return self._recv()

    def step(self, action):
        self._send(action)
        return self._recv()

    def _send(self, d):
        self.conn.sendall((json.dumps(d) + "\n").encode())

    def _recv(self):
        while b"\n" not in self.buf:
            chunk = self.conn.recv(1 << 20)
            if not chunk:
                return {"done": True, "lost": False, "won": False, "score": 0, "enemy_score": 0, "eof": True}
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def close(self):
        if self.conn:
            try:
                self._send({"quit": True})
            except OSError:
                pass
            self.conn.close()
            self.conn = None
        if self.proc:
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None


if __name__ == "__main__":
    # Smoke test: random decisions for one game.
    env = StarEnv(int(os.environ.get("PORT", 47000)), system=os.environ.get("SYSTEM", "orion_reach"), minutes=float(os.environ.get("MINUTES", 6)), log="rl_smoke.log")
    obs = env.reset()
    steps = 0
    while not obs.get("done"):
        a = {"build": random.randrange(len(obs["build_opts"])) if obs["build_opts"] and random.random() < 0.5 else -1,
             "tech": random.randrange(len(obs["tech_opts"])) if obs["tech_opts"] else -1,
             "target": random.randrange(len(obs["targets"])) if random.random() < 0.1 else -1}
        obs = env.step(a)
        steps += 1
        if steps % 30 == 1:
            print(f"t={obs['t']:.0f}s entities={len(obs['entities'])}x{len(obs['entities'][0]) if obs['entities'] else 0} "
                  f"builds={len(obs['build_opts'])} techs={len(obs['tech_opts'])} targets={len(obs['targets'])} score={obs['score']} vs {obs['enemy_score']}")
    print("done after", steps, "steps; won", obs.get("won"), "lost", obs.get("lost"), "score", obs.get("score"))
    env.close()
