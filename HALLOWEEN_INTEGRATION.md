# HALLOWEEN EXPANSION — Integration Guide

**Status:** All content built and verified (2026-10-06). This doc is for the merge step.
**Do NOT push the 20-game agent's work and this work in conflicting commits — merge hub.gd carefully.**

## What was built

30 Halloween mini-games + costume picker + 3D avatar. All files are NEW; nothing existing was modified.

| Content | Location |
|---|---|
| 30 game scripts | `scripts/games/hw_<slug>/hw_<slug>.gd` |
| 30 game scenes | `scenes/hw_<slug>/hw_<slug>.tscn` |
| Avatar script/scene | `scripts/halloween/avatar.gd`, `scenes/halloween/avatar.tscn` |
| 30 costume builders (`class_name HalloweenCostumes`) | `scripts/halloween/costume_builders.gd` |
| Costume picker script/scene | `scripts/halloween/costume_picker.gd`, `scenes/halloween/costume_picker.tscn` |

**Verification done:** 33/33 scripts parse clean (`--headless --path . --check-only`);
only one new `class_name` (`HalloweenCostumes`), no collisions; no `KEY_*` constants;
all 30 game scenes reference their correct scripts; picker/avatar scenes valid;
headless-safe (mouse fallback, guarded camera/XR calls). The "Check logged errors in
debugger" stderr lines during checks are OpenXR headless noise (no HMD), not script errors.

## The 30 games (slug → hub display name)

1. `hw_pumpkin_smash` → Pumpkin Smash — whack-a-mole with jack-o'-lanterns, mallet smash
2. `hw_ghost_catch` → Ghost Catch — sweep a glowing net through drifting ghosts
3. `hw_candy_run` → Candy Run — move a basket with your hand to catch raining candy
4. `hw_haunted_maze` → Haunted Maze — walk-through hedge maze, 5 tokens, patrolling ghoul
5. `hw_web_slingshot` → Web Slingshot — pinch-pull slingshot at spider targets
6. `hw_potion_mix` → Potion Mix — pour ingredient vials in recipe order
7. `hw_zombie_defense` → Zombie Defense — point + pinch-zap zombies from room edges
8. `hw_bat_catch` → Bat Catch — pinch-grab fluttering bats
9. `hw_door_dash` → Door Dash — knock on 3 haunted doors, trick-or-treat
10. `hw_skeleton_dance` → Skeleton Dance — mirror the skeleton's dance poses on the beat
11. `hw_eyeball_pong` → Eyeball Pong — pong vs ghost AI, first to 7
12. `hw_broom_flight` → Broom Flight — steer a witch through glowing rings
13. `hw_monster_mash` → Monster Mash — rhythm game, hit monsters on the beat
14. `hw_candy_stack` → Candy Stack — stack falling candy corn, tallest stable stack wins
15. `hw_mummy_wrap` → Mummy Wrap — circular hand motions wind bandages on a spinning mummy
16. `hw_bat_dodge` → Bat Dodge — dodge a diving bat swarm, near-misses score
17. `hw_pumpkin_carve` → Pumpkin Carve — trace carve patterns with fingertip
18. `hw_portrait_gallery` → Portrait Gallery — spot the haunted portrait, 10 rounds
19. `hw_spider_catch` → Spider Catch — grab spiders descending on webs
20. `hw_werewolf_howl` → Werewolf Howl — dual-pinch charge, release shockwave
21. `hw_grave_digger` → Grave Digger — dig glowing spots: candy or skeleton tricks
22. `hw_hayride_shooter` → Hayride Shooter — on-rails haunted ride, shoot ghosts
23. `hw_apple_bobbing` → Apple Bobbing — grab apples while surfaced
24. `hw_phantom_piano` → Phantom Piano — Simon-style haunted piano sequences
25. `hw_goblin_archery` → Goblin Archery — pinch-draw bow at popping goblins
26. `hw_mirror_maze` → Haunted Mirror Maze — navigate a generated mirror maze to the portal
27. `hw_pumpkin_bowling` → Pumpkin Bowling — roll pumpkins at ghost pins
28. `hw_hat_toss` → Witch Hat Toss — toss rings onto witch hats
29. `hw_monster_feed` → Monster Feed — feed the monster the food it wants
30. `hw_midnight_survival` → Midnight Survival — survive spook waves until 12:00

> Name note: hub display name "Haunted Mirror Maze" avoids confusion with the
> existing "Laser Mirrors" (`scenes/mirror-maze/`). Different slugs — no file collision.

## Step 1 — hub.gd: add the HW_GAMES array

After the closing `]` of `const GAMES` (line ~58), insert:

```gdscript
const HW_GAMES := [
	{"name": "Pumpkin Smash", "scene": "res://scenes/hw_pumpkin_smash/hw_pumpkin_smash.tscn", "color": Color(1.0, 0.45, 0.05)},
	{"name": "Ghost Catch", "scene": "res://scenes/hw_ghost_catch/hw_ghost_catch.tscn", "color": Color(0.7, 1.0, 0.9)},
	{"name": "Candy Run", "scene": "res://scenes/hw_candy_run/hw_candy_run.tscn", "color": Color(1.0, 0.3, 0.5)},
	{"name": "Haunted Maze", "scene": "res://scenes/hw_haunted_maze/hw_haunted_maze.tscn", "color": Color(0.3, 0.6, 0.2)},
	{"name": "Web Slingshot", "scene": "res://scenes/hw_web_slingshot/hw_web_slingshot.tscn", "color": Color(0.8, 0.8, 0.9)},
	{"name": "Potion Mix", "scene": "res://scenes/hw_potion_mix/hw_potion_mix.tscn", "color": Color(0.4, 0.9, 0.3)},
	{"name": "Zombie Defense", "scene": "res://scenes/hw_zombie_defense/hw_zombie_defense.tscn", "color": Color(0.5, 0.9, 0.2)},
	{"name": "Bat Catch", "scene": "res://scenes/hw_bat_catch/hw_bat_catch.tscn", "color": Color(0.2, 0.2, 0.4)},
	{"name": "Door Dash", "scene": "res://scenes/hw_door_dash/hw_door_dash.tscn", "color": Color(0.9, 0.5, 0.1)},
	{"name": "Skeleton Dance", "scene": "res://scenes/hw_skeleton_dance/hw_skeleton_dance.tscn", "color": Color(0.9, 0.9, 0.85)},
	{"name": "Eyeball Pong", "scene": "res://scenes/hw_eyeball_pong/hw_eyeball_pong.tscn", "color": Color(1.0, 0.2, 0.2)},
	{"name": "Broom Flight", "scene": "res://scenes/hw_broom_flight/hw_broom_flight.tscn", "color": Color(0.6, 0.3, 1.0)},
	{"name": "Monster Mash", "scene": "res://scenes/hw_monster_mash/hw_monster_mash.tscn", "color": Color(0.7, 0.2, 0.9)},
	{"name": "Candy Stack", "scene": "res://scenes/hw_candy_stack/hw_candy_stack.tscn", "color": Color(1.0, 0.7, 0.1)},
	{"name": "Mummy Wrap", "scene": "res://scenes/hw_mummy_wrap/hw_mummy_wrap.tscn", "color": Color(0.85, 0.8, 0.65)},
	{"name": "Bat Dodge", "scene": "res://scenes/hw_bat_dodge/hw_bat_dodge.tscn", "color": Color(0.35, 0.1, 0.5)},
	{"name": "Pumpkin Carve", "scene": "res://scenes/hw_pumpkin_carve/hw_pumpkin_carve.tscn", "color": Color(1.0, 0.55, 0.0)},
	{"name": "Portrait Gallery", "scene": "res://scenes/hw_portrait_gallery/hw_portrait_gallery.tscn", "color": Color(0.5, 0.2, 0.6)},
	{"name": "Spider Catch", "scene": "res://scenes/hw_spider_catch/hw_spider_catch.tscn", "color": Color(0.9, 0.1, 0.3)},
	{"name": "Werewolf Howl", "scene": "res://scenes/hw_werewolf_howl/hw_werewolf_howl.tscn", "color": Color(0.4, 0.5, 1.0)},
	{"name": "Grave Digger", "scene": "res://scenes/hw_grave_digger/hw_grave_digger.tscn", "color": Color(0.45, 0.35, 0.2)},
	{"name": "Hayride Shooter", "scene": "res://scenes/hw_hayride_shooter/hw_hayride_shooter.tscn", "color": Color(1.0, 0.6, 0.15)},
	{"name": "Apple Bobbing", "scene": "res://scenes/hw_apple_bobbing/hw_apple_bobbing.tscn", "color": Color(0.9, 0.15, 0.2)},
	{"name": "Phantom Piano", "scene": "res://scenes/hw_phantom_piano/hw_phantom_piano.tscn", "color": Color(0.75, 0.6, 1.0)},
	{"name": "Goblin Archery", "scene": "res://scenes/hw_goblin_archery/hw_goblin_archery.tscn", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Haunted Mirror Maze", "scene": "res://scenes/hw_mirror_maze/hw_mirror_maze.tscn", "color": Color(0.6, 0.9, 1.0)},
	{"name": "Pumpkin Bowling", "scene": "res://scenes/hw_pumpkin_bowling/hw_pumpkin_bowling.tscn", "color": Color(1.0, 0.5, 0.0)},
	{"name": "Witch Hat Toss", "scene": "res://scenes/hw_hat_toss/hw_hat_toss.tscn", "color": Color(0.55, 0.25, 0.9)},
	{"name": "Monster Feed", "scene": "res://scenes/hw_monster_feed/hw_monster_feed.tscn", "color": Color(0.3, 1.0, 0.4)},
	{"name": "Midnight Survival", "scene": "res://scenes/hw_midnight_survival/hw_midnight_survival.tscn", "color": Color(0.15, 0.1, 0.35)},
]
```

## Step 2 — hub.gd: tab system (ARCADE / HALLOWEEN) + Costumes button

1. Add member var next to `var _page := 0`:
   ```gdscript
   var _tab := 0  # 0 = ARCADE (GAMES), 1 = HALLOWEEN (HW_GAMES)
   var _tab_buttons: Array[Node3D] = []
   ```
2. Add helper (near `_page_count`):
   ```gdscript
   func _active_games() -> Array:
       return HW_GAMES if _tab == 1 else GAMES
   ```
3. In `_page_count()` and `_build_page()`: replace every `GAMES.size()` / `GAMES[i]`
   with `_active_games().size()` / `_active_games()[i]`.
4. In `_build_hub()`, after the title (or near the hint label), add two tab buttons
   reusing `_make_nav_button`-style visuals — simplest: two `_make_button`-like
   clickable labels "🎃 ARCADE" and "🎃 HALLOWEEN". On click: set `_tab`,
   reset `_page = 0`, call `_build_page()`. Give the active tab a brighter
   emission color. (Wire via `area.input_event` like `_on_nav_input`, or reuse
   `_make_nav_button` with a distinct meta flag and branch in the handler.)
5. Add a **"Costumes"** button (same clickable-label pattern) that calls:
   ```gdscript
   _load_game("res://scenes/halloween/costume_picker.tscn", "Costume Picker")
   ```
   Position it beside the update button (e.g. `Vector3(1.4, -1.85, -1.5)`).
   The existing H-key / back flow (`_return_to_hub`) already restores the hub.
6. `_load_game` hides `_game_buttons`, `_nav_buttons`, `_page_label` — also hide
   `_tab_buttons` there and re-show them in `_return_to_hub` (mirror the existing
   visible=true/false loops).

HALLOWEEN tab pagination: 30 games at 25/page = 2 pages; existing pager handles it.

## Step 3 — version bump → 0.4.0

- `export_presets.cfg`: `version/code=4`, `version/name="0.4.0"`
- `project.godot`: `application/config/version="0.4.0"`
- `version.json`: `"version": "0.4.0"`,
  `"download_url": "https://github.com/waderaider/nexus-arcade/releases/download/v0.4.0/NexusArcade-v0.4.0.apk"`,
  changelog entry describing the 30 Halloween mini-games + costume picker (30 costumes).

## Step 4 — push

Push via the Git Data API (same pattern as before — see
`~/workspace/skills/github/bin/push_project.py`; extend `INCLUDE_DIRS` with
`scenes/hw_*` — already covered by `scenes/` walk — and add `scripts/halloween/`,
`scenes/halloween/`, plus this file). The push auto-triggers the GitHub Actions
APK build. Create release `v0.4.0` and upload the APK as `NexusArcade-v0.4.0.apk`.

## Optional fix (pre-existing, not from this expansion)

`scripts/shared/ar_kit.gd` → `pinch_active()` calls
`Input.is_action_pressed("trigger_click")` unguarded. That action is not in the
project InputMap, so it logs an error every frame whenever any game's `_process`
runs. Suggested one-line fix:
```gdscript
if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
```

## Costume catalog (for reference)

30 costumes in `HalloweenCostumes.all_costumes()` (id → name → avatar anchor):
witch_hat→Witch Hat→HeadTop, vampire_cape→Vampire→Torso, pumpkin_head→Pumpkin Head→Head,
ghost_sheet→Ghost→Head, skeleton_suit→Skeleton→Torso, werewolf_ears→Werewolf→Head,
devil_horns→Devil→HeadTop, angel_halo→Angel→HeadTop, pirate_hat→Pirate→Head,
ninja_hood→Ninja→Head, robot_helmet→Robot→Head, alien_antennae→Alien→Head,
zombie_tatters→Zombie→Torso, mummy_wraps→Mummy→Head, scarecrow_hat→Scarecrow→HeadTop,
plague_doctor→Plague Doctor→Head, jester_hat→Jester→HeadTop, knight_helmet→Knight→Head,
astronaut_helmet→Astronaut→Head, diver_helmet→Deep-Sea Diver→Head,
pharaoh_headdress→Pharaoh→Head, viking_helmet→Viking→HeadTop, samurai_helmet→Samurai→Head,
clown_wig→Clown→Head, cat_ears→Cat→HeadTop, bat_wings→Bat→Back, spider_pack→Spider Rider→Back,
candycorn_hat→Candy Corn→HeadTop, top_hat→Haunted Top Hat→HeadTop, reaper_hood→Grim Reaper→Head.

Choice persists in `user://nexus_costume.cfg` (`costume`/`id`).

## Merge checklist

- [ ] HW_GAMES array added to hub.gd (30 entries, paths verified above)
- [ ] Tab system wired; both tabs paginate; Costumes button opens picker
- [ ] `_load_game`/`_return_to_hub` hide/show tab buttons
- [ ] Version bumped to 0.4.0 in export_presets.cfg + project.godot + version.json
- [ ] Full project `--check-only` on hub.gd after edits
- [ ] Push → Actions build green → release v0.4.0 → APK uploaded as NexusArcade-v0.4.0.apk
- [ ] Website download button + version.json changelog updated; email sent
