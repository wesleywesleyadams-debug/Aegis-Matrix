"""Replay images: turn a game trace (RLAgent's SL_TRACE, one JSON line per
decision) into one PNG of 8 snapshots across the match, so you can see where
the learning agent's ships went. Its own things are drawn larger.

  python replay.py runs/replays/trace.jsonl out.png
"""
import json, sys

from PIL import Image, ImageDraw

# Defs.TEAM_COLORS (index 0 = neutral).
COLORS = ["#9aa0b0", "#4fb4ff", "#ff4f5e", "#6fe07a", "#ffc93d", "#c77dff", "#ff8c3a", "#3de0d0", "#ff7ac8"]
MAP_RADIUS = 1750.0
CELL = 300
FRAMES = 8


def render_replay(trace, out):
    try:
        lines = [json.loads(l) for l in open(trace, encoding="utf-8") if l.strip()]
    except OSError:
        return
    if not lines:
        return
    picks = [lines[round(i * (len(lines) - 1) / (FRAMES - 1))] for i in range(FRAMES)]
    img = Image.new("RGB", (CELL * 4, (CELL + 20) * 2), "#0b0d16")
    d = ImageDraw.Draw(img)
    sc = (CELL / 2 - 6) / MAP_RADIUS
    for k, fr in enumerate(picks):
        ox, oy = (k % 4) * CELL, (k // 4) * (CELL + 20) + 20
        cx, cy = ox + CELL / 2, oy + CELL / 2
        d.ellipse([cx - CELL / 2 + 6, cy - CELL / 2 + 6, cx + CELL / 2 - 6, cy + CELL / 2 - 6], outline="#2a3150")
        d.text((ox + 6, oy - 16), f"{fr['t'] / 60:.1f} min", fill="#c8d2ea")
        me = fr.get("me", 0)
        for kind, owner, x, y in sorted(fr["e"], key=lambda r: r[1] == me):
            px, py = cx + x * sc, cy + y * sc
            col = COLORS[owner] if 0 <= owner < len(COLORS) else "#ffffff"
            big = owner == me
            if kind == "p":
                r = 4
                d.ellipse([px - r, py - r, px + r, py + r], outline=col if owner else "#3a4060")
            elif kind == "b":
                r = 5 if big else 4
                d.rectangle([px - r, py - r, px + r, py + r], fill=col)
            else:
                r = 2 if big else 1
                d.ellipse([px - r, py - r, px + r, py + r], fill=col)
    img.save(out)


if __name__ == "__main__":
    render_replay(sys.argv[1], sys.argv[2])
