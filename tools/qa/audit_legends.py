#!/usr/bin/env python3
"""Legend honesty audit (QA_PLAN_V0110.md §1.4): every button named in
BUTTONS_FOR_STEM or a game's controller_config must actually be read by the
game's scripts (is_button_pressed / XRUIPointer reads / action-map reads).
Usage: python3 tools/qa/audit_legends.py  (run from project root)
Exit 0 = all honest, 1 = phantom button found."""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
GAMES = {
    "nullg_league": "scripts/games/nullg_league",
    "chrono_heist": "scripts/games/chrono_heist",
    "siege_engineer": "scripts/games/siege_engineer",
    "spectral_files": "scripts/games/spectral_files",
    "terraform": "scripts/games/terraform",
}

# button -> regexes proving the game reads it
READS = {
    "trigger": [r'trigger_pressed', r'"trigger_click"', r"'trigger_click'"],
    "grip": [r'"grip_click"', r"'grip_click'", r'"grip"', r"'grip'"],
    "thumbstick": [r'"thumbstick"', r"'thumbstick'", r"thumbstick"],
    "menu": [r'"menu_button"', r"'menu_button'"],
}


def legend_buttons(stem):
    """Collect named buttons from controller_skins.gd + per-game controller_config."""
    btns = set()
    cs = (ROOT / "scripts/shared/controller_skins.gd").read_text()
    m = re.search(r'"%s":\s*\{([^}]*)\}' % re.escape(stem), cs)
    if m:
        for b in re.findall(r'"(trigger|grip|thumbstick|a|b|x|y|menu)"\s*:', m.group(1)):
            # only count non-empty labels
            lbl = re.search(r'"%s"\s*:\s*"([^"]*)"' % b, m.group(1))
            if lbl and lbl.group(1).strip() not in ("", "—", "-"):
                btns.add(b)
    gdir = ROOT / GAMES[stem]
    for f in gdir.glob("*.gd"):
        src = f.read_text()
        for b in READS:
            if re.search(r'"%s"\s*:\s*"[^"—-][^"]*"' % b, src):
                btns.add(b)
    return btns


def game_reads(stem):
    src = ""
    for f in (ROOT / GAMES[stem]).glob("*.gd"):
        src += f.read_text() + "\n"
    # Strip the legend declarations themselves (they name buttons without reading).
    src = re.sub(r"var controller_config\s*:=\s*\{.*?\n\}", "", src, flags=re.DOTALL)
    reads = {b for b, pats in READS.items() if any(re.search(p, src) for p in pats)}
    # "menu" is read by the shared PauseExit autoload (_poll_menu_button,
    # 0.45s hold) for every game — shared-read, never phantom.
    reads.add("menu")
    return reads


fails = 0
for stem in GAMES:
    named = legend_buttons(stem)
    reads = game_reads(stem)
    phantom = sorted(named - reads)
    status = "OK  " if not phantom else "FAIL"
    if phantom:
        fails += 1
    print(f"{status} {stem}: named={sorted(named)} read={sorted(reads)}"
          + (f" PHANTOM={phantom}" if phantom else ""))
sys.exit(1 if fails else 0)
