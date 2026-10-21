# Generates the Frontier Outpost and Warp Gate pixel sprites (+ team masks)
# in the construct style: dark outline, vertical blue-grey shading.
import math, sys
from PIL import Image
OUT = sys.argv[1]
PAL = [(215,225,245),(189,200,226),(164,176,208),(137,149,187),(111,123,166),(92,102,144),(73,82,122),(44,50,80),(25,28,48)]
LINE = (14,13,28,255)

def render(size, parts, team_parts, glow=None):
    """parts: list of (mask_fn(x,y)->bool, y0, y1) drawn in order (later on top)."""
    im = Image.new("RGBA", (size, size), (0,0,0,0))
    px = im.load()
    for fn, y0, y1 in parts:
        cells = [(x, y) for y in range(size) for x in range(size) if fn(x + 0.5, y + 0.5)]
        cs = set(cells)
        for x, y in cells:
            edge = any((x+dx, y+dy) not in cs for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)))
            if edge:
                px[x, y] = LINE
                continue
            t = min(max((y - y0) / max(1, y1 - y0), 0.0), 1.0)
            i = int(round(t * (len(PAL) - 3))) + 1
            if (x, y - 1) not in cs or ((x, y - 2) not in cs and t < 0.5):
                i = max(0, i - 1)   # top highlight
            px[x, y] = PAL[i] + (255,)
    if glow:
        for x in range(size):
            for y in range(size):
                c = glow(x + 0.5, y + 0.5)
                if c:
                    px[x, y] = c
    team = Image.new("RGBA", (size, size), (0,0,0,0))
    tp = team.load()
    for fn, shade in team_parts:
        for y in range(size):
            for x in range(size):
                if fn(x + 0.5, y + 0.5) and px[x, y][3] and px[x, y] != LINE:
                    tp[x, y] = (shade, shade, shade, 255)
    return im, team

def circ(cx, cy, r):
    return lambda x, y: (x-cx)**2 + (y-cy)**2 <= r*r
def rect(x0, y0, x1, y1):
    return lambda x, y: x0 <= x <= x1 and y0 <= y <= y1
def octa(cx, cy, r):
    return lambda x, y: abs(x-cx) <= r and abs(y-cy) <= r and abs(x-cx) + abs(y-cy) <= r * 1.3

# Frontier Outpost: an octagonal bastion, four corner gun turrets, a central
# laser turret with its barrel pointing up.
S = 66; c = S / 2
parts = []
for dx, dy in ((-1,-1),(1,-1),(-1,1),(1,1)):
    parts.append((rect(c + dx*21 - 4, c + dy*21 - 4, c + dx*21 + 4, c + dy*21 + 4), c + dy*21 - 4, c + dy*21 + 4))
parts.append((octa(c, c, 22), c - 22, c + 22))
for dx, dy in ((-1,-1),(1,-1),(-1,1),(1,1)):
    parts.append((circ(c + dx*15, c + dy*15, 5.5), c + dy*15 - 5, c + dy*15 + 5))
parts.append((circ(c, c, 9), c - 9, c + 9))
parts.append((rect(c - 2, c - 20, c + 2, c - 6), c - 20, c - 6))
team = [(lambda x, y: abs(abs(x-c) + abs(y-c) - 25) < 1.4 and abs(x-c) <= 22 and abs(y-c) <= 22, 234)]
for dx, dy in ((-1,-1),(1,-1),(-1,1),(1,1)):
    team.append((circ(c + dx*15, c + dy*15, 2.2), 255))
im, tm = render(S, parts, team)
im.save(OUT + "/ship_frontier_outpost.png"); tm.save(OUT + "/ship_frontier_outpost_team.png")

# Warp Gate: a thick ring on four pylons, a dark well with a faint blue
# shimmer in the middle.
S = 76; c = S / 2
parts = []
for a in range(4):
    ang = a * math.pi / 2 + math.pi / 4
    px_, py_ = c + math.cos(ang) * 32, c + math.sin(ang) * 32
    parts.append((rect(px_ - 5, py_ - 5, px_ + 5, py_ + 5), py_ - 5, py_ + 5))
ring = lambda x, y: 20 <= math.hypot(x-c, y-c) <= 31
parts.append((ring, c - 31, c + 31))
def glow(x, y):
    d = math.hypot(x-c, y-c)
    if d < 19:
        k = 1.0 - d / 19
        return (int(30 + 60*k), int(40 + 120*k), int(80 + 160*k), 255) if (int(x) + int(y)) % 2 == 0 or d < 8 else (20, 26, 56, 255)
    return None
team = [(lambda x, y: 24.5 <= math.hypot(x-c, y-c) <= 26.5, 234)]
for a in range(4):
    ang = a * math.pi / 2 + math.pi / 4
    team.append((circ(c + math.cos(ang) * 30, c + math.sin(ang) * 32, 2.5), 255))
im, tm = render(S, parts, team, glow)
im.save(OUT + "/ship_warp_gate.png"); tm.save(OUT + "/ship_warp_gate_team.png")
print("ok")
