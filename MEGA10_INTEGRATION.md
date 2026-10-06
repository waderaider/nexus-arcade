# MEGA10 Integration — 10 new games → NEXUS ARCADE hub

The 10 "mega launcher" games wade picked are built, verified, and ready to merge.
All files are self-contained; hub.gd / version files were NOT touched by the builders.

## Files (all present and parse-verified)

| # | Game | Script | Scene |
|---|------|--------|-------|
| 1 | Holo Chef | `scripts/games/holo_chef/holo_chef.gd` | `scenes/holo_chef/holo_chef.tscn` |
| 2 | Dragon Ranch | `scripts/games/dragon_ranch/dragon_ranch.gd` | `scenes/dragon_ranch/dragon_ranch.tscn` |
| 3 | Wizard Academy | `scripts/games/wizard_academy/wizard_academy.gd` | `scenes/wizard_academy/wizard_academy.tscn` |
| 4 | Holo Farm | `scripts/games/holo_farm/holo_farm.gd` | `scenes/holo_farm/holo_farm.tscn` |
| 5 | Mech Pilot | `scripts/games/mech_pilot/mech_pilot.gd` | `scenes/mech_pilot/mech_pilot.tscn` |
| 6 | Deep Dive | `scripts/games/deep_dive/deep_dive.gd` | `scenes/deep_dive/deep_dive.tscn` |
| 7 | AR Detective | `scripts/games/ar_detective/ar_detective.gd` | `scenes/ar_detective/ar_detective.tscn` |
| 8 | Sky Pirates | `scripts/games/sky_pirates/sky_pirates.gd` | `scenes/sky_pirates/sky_pirates.tscn` |
| 9 | Monster Lab | `scripts/games/monster_lab/monster_lab.gd` | `scenes/monster_lab/monster_lab.tscn` |
| 10 | Myth Zoo | `scripts/games/myth_zoo/myth_zoo.gd` | `scenes/myth_zoo/myth_zoo.tscn` |

Also new shared helper: `scripts/shared/haptics.gd` (`class_name Haptics` — controller
vibration, no-ops safely when unavailable; already in the global class cache).

Kenney CC0 models committed under `assets/models/<slug>/` with CREDITS.txt files.

## Hub merge (scripts/hub.gd)

The hub has an ARCADE/HALLOWEEN tab system and 25-games-per-page pagination.
These 10 games belong in the **ARCADE** tab → append to the `GAMES` array
(`const GAMES := [` … `]`, currently ending with the Sky Traffic entry).

Insert these 10 entries just before the closing `]` of the GAMES array:

```gdscript
	{"name": "Holo Chef", "scene": "res://scenes/holo_chef/holo_chef.tscn", "color": Color(1.0, 0.55, 0.2)},
	{"name": "Dragon Ranch", "scene": "res://scenes/dragon_ranch/dragon_ranch.tscn", "color": Color(1.0, 0.3, 0.25)},
	{"name": "Wizard Academy", "scene": "res://scenes/wizard_academy/wizard_academy.tscn", "color": Color(0.65, 0.35, 1.0)},
	{"name": "Holo Farm", "scene": "res://scenes/holo_farm/holo_farm.tscn", "color": Color(0.45, 0.9, 0.35)},
	{"name": "Mech Pilot", "scene": "res://scenes/mech_pilot/mech_pilot.tscn", "color": Color(0.35, 0.75, 0.95)},
	{"name": "Deep Dive", "scene": "res://scenes/deep_dive/deep_dive.tscn", "color": Color(0.15, 0.5, 1.0)},
	{"name": "AR Detective", "scene": "res://scenes/ar_detective/ar_detective.tscn", "color": Color(1.0, 0.75, 0.3)},
	{"name": "Sky Pirates", "scene": "res://scenes/sky_pirates/sky_pirates.tscn", "color": Color(0.3, 0.85, 0.8)},
	{"name": "Monster Lab", "scene": "res://scenes/monster_lab/monster_lab.tscn", "color": Color(0.6, 1.0, 0.3)},
	{"name": "Myth Zoo", "scene": "res://scenes/myth_zoo/myth_zoo.tscn", "color": Color(1.0, 0.4, 0.8)},
```

No other hub.gd changes needed — pagination and tabs operate on the array generically.
After merge: ARCADE tab = 61 games (50 + Sky Traffic + 10), HALLOWEEN tab unchanged (30).

## Version bump suggestion → v0.6.0

- `export_presets.cfg`: `version/code=6`, `version/name="0.6.0"`
- `project.godot`: `application/config/version="0.6.0"`
- `version.json`: version `"0.6.0"`, `version_code` 6,
  `apk_url` → `https://github.com/waderaider/nexus-arcade/releases/download/v0.6.0/NexusArcade-v0.6.0.apk`,
  changelog: 10 new games (Holo Chef, Dragon Ranch, Wizard Academy, Holo Farm,
  Mech Pilot, Deep Dive, AR Detective, Sky Pirates, Monster Lab, Myth Zoo) +
  controller haptics + real 3D model assets throughout.

## Verification (done by coordinator)

- All 10 scripts: `godot --headless --check-only` → 0 errors each
- `scripts/shared/haptics.gd`: 0 errors
- All 10 scenes reference their correct scripts (verified via grep)
- No `class_name` in any game script; no `const KEY_*` definitions
  (KEY_R/KEY_F/KEY_T usages are Godot's built-in keycodes via Input.is_key_pressed — correct usage)
- Headless runtime smoke tests by builders: no script errors; `.import` files generated

## Push checklist

1. Merge the 10 GAMES entries into hub.gd
2. Apply the v0.6.0 version bumps
3. Push via Git Data API (include: scripts/games/<10 slugs>/, scenes/<10 slugs>/,
   scripts/shared/haptics.gd, assets/models/<10 slugs>/, hub.gd, version files,
   this doc) — triggers the GitHub Actions auto-build
4. When green: cut release v0.6.0, upload `NexusArcade-v0.6.0.apk` via
   `custom.github-upload`, update website, email wade

## Open caveats (from builders, for the record)

- No physical Quest 3 testing yet: pinch feel, haptic strength, gesture speeds,
  and hold-to-water timing need on-device validation.
- Kenney has no 3D animal/creature-part packs — Dragon Ranch's dragon and Monster
  Lab's 20 snap-together parts are hand-built low-poly in Kenney style (sanctioned
  fallback); all other hero elements are real Kenney models.
- Haptics API call is best-effort guarded (`has_method` check) — needs Quest
  validation to confirm the OpenXR action signature fires.
