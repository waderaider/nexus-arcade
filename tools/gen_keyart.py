#!/usr/bin/env python3
"""NEXUS ARCADE v0.9.0 key-art generator (Launcher 2.1).

Generates ONE consistent stylized card per game into assets/keyart/<stem>.png:
category gradient background + big glyph (game initials) + game name +
category tag chip. The game list (name/scene/color/tab) is parsed straight
from scripts/hub.gd's CAT_* lists, so cards can never drift from the hub.

Run:  python3 tools/gen_keyart.py
Requires: pillow (pip install pillow)
"""
import math
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
HUB = ROOT / "scripts" / "hub.gd"
OUT = ROOT / "assets" / "keyart"

W, H = 480, 300

# Category identity (matches the Launcher 2.1 skins in hub.gd).
CATEGORIES = {
    0: {"tag": "GAMES", "base": (16, 8, 34), "edge": (255, 45, 200)},
    1: {"tag": "UTILITIES", "base": (6, 20, 38), "edge": (60, 200, 255)},
    2: {"tag": "CREATE", "base": (34, 16, 8), "edge": (255, 150, 50)},
    3: {"tag": "THEMES", "base": (22, 8, 40), "edge": (170, 80, 255)},
}

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def parse_hub():
    """Extract (name, scene_stem, color, tab) from hub.gd CAT_* lists."""
    src = HUB.read_text()
    games = []
    for tab, const in enumerate(["CAT_GAMES", "CAT_UTILITIES", "CAT_CREATE", "CAT_THEMES"]):
        m = re.search(r"const %s := \[(.*?)\n\]" % const, src, re.S)
        if not m:
            print("WARN: %s not found" % const, file=sys.stderr)
            continue
        for gm in re.finditer(
            r'\{"name": "([^"]+)", "scene": "([^"]+)", "color": Color\(([^)]+)\)\}',
            m.group(1),
        ):
            name, scene, color = gm.group(1), gm.group(2), gm.group(3)
            stem = Path(scene).stem
            rgb = tuple(int(float(c.strip()) * 255) for c in color.split(","))
            games.append({"name": name, "stem": stem, "color": rgb, "tab": tab})
    return games


def initials(name):
    words = [w for w in re.split(r"[^A-Za-z0-9]+", name) if w]
    if not words:
        return "?"
    if len(words) == 1:
        return words[0][:2].upper()
    return (words[0][0] + words[1][0]).upper()


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_card(game):
    cat = CATEGORIES[game["tab"]]
    rng = random.Random(game["stem"])  # stable per game
    img = Image.new("RGB", (W, H))
    px = img.load()
    gc = game["color"]
    # Vertical gradient: category base -> game color (darkened) -> base.
    dark = tuple(int(c * 0.35) for c in gc)
    for y in range(H):
        t = y / (H - 1)
        if t < 0.55:
            col = mix(cat["base"], dark, t / 0.55)
        else:
            col = mix(dark, cat["base"], (t - 0.55) / 0.45)
        for x in range(W):
            px[x, y] = col
    d = ImageDraw.Draw(img, "RGBA")
    # Diagonal sheen bands.
    for i in range(3):
        off = rng.uniform(-W, W)
        band = rng.randint(60, 130)
        for x in range(W):
            y0 = int((x + off) * 0.45) % (H + 400) - 200
            if 0 <= y0 < H:
                for yy in range(max(0, y0), min(H, y0 + band)):
                    r, g, b = px[x, yy]
                    px[x, yy] = (min(255, r + 14), min(255, g + 14), min(255, b + 14))
    # Subtle grid texture.
    for gx in range(0, W, 40):
        d.line([(gx, 0), (gx, H)], fill=(255, 255, 255, 14), width=1)
    for gy in range(0, H, 40):
        d.line([(0, gy), (W, gy)], fill=(255, 255, 255, 14), width=1)
    # Big glyph: initials, large, semi-transparent, upper-center.
    glyph = initials(game["name"])
    try:
        gf = ImageFont.truetype(FONT_BOLD, 150)
    except OSError:
        gf = ImageFont.load_default()
    bb = d.textbbox((0, 0), glyph, font=gf)
    gw, gh = bb[2] - bb[0], bb[3] - bb[1]
    gx, gy = (W - gw) // 2, 34
    # Glow behind the glyph.
    d.text((gx + 3, gy + 3), glyph, font=gf,
           fill=(cat["edge"][0], cat["edge"][1], cat["edge"][2], 110))
    d.text((gx, gy), glyph, font=gf, fill=(255, 255, 255, 205))
    # Game color accent bar under the glyph.
    bar_y = gy + gh + 8
    d.rounded_rectangle([W // 2 - 90, bar_y, W // 2 + 90, bar_y + 8],
                        radius=4, fill=gc + (255,))
    # Game name, wrapped, bottom.
    try:
        nf = ImageFont.truetype(FONT_BOLD, 30)
    except OSError:
        nf = ImageFont.load_default()
    name = game["name"]
    # Wrap to max 2 lines.
    words, lines, cur = name.split(), [], ""
    for w_ in words:
        trial = (cur + " " + w_).strip()
        if d.textlength(trial, font=nf) <= W - 40:
            cur = trial
        else:
            lines.append(cur)
            cur = w_
    if cur:
        lines.append(cur)
    lines = lines[:2]
    ny = H - 24 - len(lines) * 36
    for line in lines:
        lw = d.textlength(line, font=nf)
        lx = (W - lw) / 2
        d.text((lx + 2, ny + 2), line, font=nf, fill=(0, 0, 0, 200))
        d.text((lx, ny), line, font=nf, fill=(255, 255, 255, 255))
        ny += 36
    # Category tag chip, top-left.
    try:
        tf = ImageFont.truetype(FONT_BOLD, 20)
    except OSError:
        tf = ImageFont.load_default()
    tag = cat["tag"]
    tw = d.textlength(tag, font=tf)
    d.rounded_rectangle([12, 12, 12 + tw + 24, 44], radius=10,
                        fill=cat["edge"] + (255,))
    d.text((24, 15), tag, font=tf, fill=(10, 10, 18, 255))
    # Edge border in the category color.
    d.rounded_rectangle([2, 2, W - 3, H - 3], radius=14,
                        outline=cat["edge"] + (255,), width=4)
    return img


def main():
    games = parse_hub()
    print("games parsed: %d" % len(games))
    OUT.mkdir(parents=True, exist_ok=True)
    for g in games:
        img = make_card(g)
        img.save(OUT / (g["stem"] + ".png"), optimize=True)
    print("wrote %d cards to %s" % (len(games), OUT))


if __name__ == "__main__":
    main()
