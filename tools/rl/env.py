"""Aegis Matrix as a training environment.

StarEnv launches a headless Godot sim with the RLAgent (scripts/game/RLAgent.gd)
on one side and connects over TCP. Each step: the game sends an observation
(entities + option sets described by stats), we send a decision, the game plays
on for RLAgent.DECIDE seconds. Nothing here knows ship or tech names: options
come as feature rows, so new rules show up as new rows.
"""
import json, os, random, select, socket, subprocess

GODOT = os.environ.get("GODOT", r"C:/Users/whole/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe")
PROJECT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


NL = bytes([10])   # one message per line


class StarEnv:
    """One training game. At curriculum level 5 the other side is a second
    learning agent (SL_RL_PORT2) whose orders come from `opponent(obs)`,
    a frozen copy of the policy set by the trainer."""

    def __init__(self, port, system="random", minutes=40, speed=8, side=1, players=2, seed=None, log=None, level=4):
        self.port, self.system, self.minutes, self.speed = port, system, minutes, speed
        self.side, self.players, self.seed, self.log = side, players, seed, log
        self.level = level   # opponent curriculum level (Game.opp_level)
        self.opponent = None  # obs -> orders, for self-play
        self.duck = 1.0       # level 1: the sitting duck's starbase toughness
        self.drill = ""       # SL_DRILL practice scenario (strike, hunt, expand)
        self.stage = ""       # curriculum stage name, for the trainer
        self.drill_d = 0.0    # drill difficulty 0-1 (SL_DRILL_D)
        self.trace = ""       # SL_TRACE file for a replay of this game
        self.proc = self.conn = self.conn2 = None
        self.bufs = {}

    def _listen(self, port):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen(1)
        srv.settimeout(120)
        return srv

    def reset(self):
        self.close()
        selfplay = self.level >= 5 and self.opponent is not None
        srv = self._listen(self.port)
        srv2 = self._listen(self.port + 500) if selfplay else None
        env = dict(os.environ, SL_SIM=f"rl{self.port}", SL_RL_PORT=str(self.port), SL_RL_SIDE=str(self.side),
                   SL_SYSTEM=self.system, SL_SIM_MINUTES=str(self.minutes), SL_SIM_SCALE=str(self.speed),
                   SL_PLAYERS=str(self.players), SL_OPP_LEVEL=str(self.level), SL_DUCK_FRAC=str(self.duck), SL_DRILL=self.drill, SL_DRILL_D=str(self.drill_d), SL_TRACE=os.path.abspath(self.trace) if self.trace else "", SL_SEED=str(self.seed if self.seed is not None else random.randrange(1 << 30)))
        if selfplay:
            env["SL_RL_PORT2"] = str(self.port + 500)
        out = open(self.log, "w") if self.log else subprocess.DEVNULL
        self.proc = subprocess.Popen([GODOT, "--headless", "--fixed-fps", "60", "--path", PROJECT, "scenes/Main.tscn"],
                                     env=env, stdout=out, stderr=subprocess.STDOUT)
        # Both agents connect while the game sets up, in either order.
        self.conn, _ = srv.accept()
        srv.close()
        self.conn.settimeout(300)
        if srv2:
            self.conn2, _ = srv2.accept()
            srv2.close()
            self.conn2.settimeout(300)
        self.bufs = {self.conn: b"", self.conn2: b""}
        return self._await()

    def step(self, action):
        self._send(self.conn, action)
        return self._await()

    def _await(self):
        """The learner's next observation, answering the self-play opponent
        (whenever it asks) in between."""
        while True:
            socks = [self.conn] + ([self.conn2] if self.conn2 else [])
            for sk in socks:
                if NL in self.bufs[sk]:
                    break
            else:
                ready, _, _ = select.select(socks, [], [], 300)
                if not ready:
                    return self._eof()
                for sk in ready:
                    chunk = sk.recv(1 << 20)
                    if not chunk:
                        if sk is self.conn:
                            return self._eof()
                        self.conn2 = None
                    else:
                        self.bufs[sk] += chunk
                continue
            line, self.bufs[sk] = self.bufs[sk].split(NL, 1)
            obs = json.loads(line)
            if sk is self.conn:
                return obs
            if not obs.get("done"):
                self._send(self.conn2, self.opponent(obs))

    def _eof(self):
        return {"done": True, "lost": False, "won": False, "score": 0, "enemy_score": 0, "eof": True}

    def _send(self, sk, d):
        sk.sendall(json.dumps(d).encode() + NL)

    def close(self):
        for sk in [self.conn, self.conn2]:
            if sk:
                try:
                    self._send(sk, {"quit": True})
                except OSError:
                    pass
                sk.close()
        self.conn = self.conn2 = None
        if self.proc:
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None


def random_orders(obs, k=6):
    """Random valid-looking orders: for k random actors, a random allowed verb
    with a random object and target (the game ignores what doesn't apply)."""
    out = []
    acts = obs["actors"]
    for _ in range(min(k, len(acts))):
        ai = random.randrange(len(acts))
        verbs = [i for i, m in enumerate(acts[ai]["mask"]) if m]
        if not verbs:
            continue
        out.append([ai, random.choice(verbs), random.randrange(len(obs["objects"])),
                    random.randrange(len(obs["entities"]) + len(obs["targets"]))])
    return {"orders": out}


if __name__ == "__main__":
    # Smoke test: random orders for one game.
    env = StarEnv(int(os.environ.get("PORT", 47000)), system=os.environ.get("SYSTEM", "orion_reach"), minutes=float(os.environ.get("MINUTES", 6)), log="rl_smoke.log")
    obs = env.reset()
    steps = 0
    while not obs.get("done"):
        obs = env.step(random_orders(obs))
        steps += 1
        if steps % 30 == 1:
            print(f"t={obs['t']:.0f}s entities={len(obs['entities'])}x{len(obs['entities'][0])} actors={len(obs['actors'])} "
                  f"objects={len(obs['objects'])}x{len(obs['objects'][0])} targets={len(obs['entities']) + len(obs['targets'])} score={obs['score']} vs {obs['enemy_score']}")
    print("done after", steps, "steps; won", obs.get("won"), "lost", obs.get("lost"), "score", obs.get("score"))
    env.close()
