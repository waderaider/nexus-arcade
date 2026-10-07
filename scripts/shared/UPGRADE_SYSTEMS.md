# NEXUS ARCADE v0.7.0 — Shared Upgrade Systems

Three autoload singletons + one opt-in game template. All built for Quest 3
mobile GPU (GL Compatibility renderer): no SSAO, no volumetric fog, no heavy
post-processing. Nothing here has been Quest-tested — verify on device.

## How a game opts in

**Option A — extend the template (recommended for new games):**
```gdscript
extends NexusBaseGame

func game_ready() -> void:
    # your setup; _ready() already applied VisualFX defaults,
    # built the UIKit HUD, and wired ui_cancel to the pause menu.
    add_score(100)   # HUD updates automatically
    damage(10.0)     # health drops, haptic thump
```
Toggle visuals as member vars before `_ready()` runs:
`use_aces / use_glow / use_fog / fog_density / use_dust` (dust defaults off).

**Option B — call the autoloads directly (existing games):**
```gdscript
VisualFX.burst(self, hit_pos, Color.ORANGE)   # juice
UIKit.score_popup(hud_root, Vector2(200, 200), "+100")
agent.position += AILib.follow(agent, player_pos, delta, 2.0)
```

---

## VisualFX (autoload `VisualFX`)

| # | Func | What it does |
|---|------|--------------|
| a | `apply_aces(world)` | ACES tonemap + tuned ambient on a WorldEnvironment |
| b | `subtle_glow(world, intensity=0.5)` | Modest bloom (Compatibility renderer 4.4+) |
| c | `configure_shadows(sun, max_distance=30)` | 2-split cascades, capped distance, slight blur |
| d | `burst(parent, pos, color, amount=24)` | One-shot low-count particle explosion, self-freeing (wraps `GraphicsPolish.spawn_sparks`) |
| e | `pbr_pass(node) -> int` | Walk MeshInstance3Ds: tame roughness→~0.5, sane metallic, enable vertex-color albedo where present. Duplicates materials, never mutates shared ones |
| f | `enable_fog(world, density=0.015)` | Exponential distance fog (standard fog only — volumetric is unsupported on Compatibility) |
| g | `vignette(parent, amount=0.45) -> TextureRect` | Radial-gradient overlay; clicks pass through |
| h | `ambient_dust(parent, radius=2.5, amount=36)` | Looping floating dust (wraps `GraphicsPolish.spawn_ambient_motes`) |
| i | `animated_sky(world, top, horizon)` | Drifting-gradient shader sky, no textures. **VR scenes only — hides passthrough** |
| j | `glow_accent(node, color, base=1.2, amp=0.8, speed=2.0)` | Emissive pulse on a node via tween (materials duplicated first) |

## AILib (autoload `AILib`)

Steering helpers return **displacement vectors** (already × delta) in the
agent's **parent coordinate space**: `agent.position += AILib.follow(...)`.

| # | Func | What it does |
|---|------|--------------|
| a | `wander(agent, delta, speed, turn=2.5)` | Smooth random steering |
| b | `follow(agent, target, delta, speed)` / `flee(agent, threat, delta, speed)` | Seek / run from a position |
| c | `flock(agent, neighbors, delta, radius=2.5, max_n=6)` | Boids-lite: separation + alignment + cohesion, capped neighbor count |
| d | `new_fsm({state: callable}, start="")` | Tiny state machine: `.update(delta)`, `.change(state)`; optional `enter_<state>` callables |
| e | `report_win()` / `report_death()` / `reset_difficulty()` / `difficulty_scale() -> float` | 0.5 (struggling) … 2.0 (dominating); multiply enemy stats by it |
| f | `predictive_aim(shooter, target, vel, proj_speed) -> Vector3` | Intercept point; falls back to direct aim when unsolvable |
| g | `set_target(key, pos)` / `get_target(key)` / `has_target(key)` / `clear_target(key)` | Shared blackboard for group coordination |
| h | `investigate(agent, stimulus, delta, speed=1.2, arrive=0.4)` | Curiosity steering with arrival slowdown |
| i | `remember_seen(agent, pos)` / `last_seen(agent)` / `seen_age(agent)` | Timestamped player memory |
| j | `idle_behavior(agent, delta, look_speed=0.6, bob=0.025)` | Look-around + bob in place (bounded, no drift) |

Wired into existing games (1–3 line insertions, no rewrites):
- `scripts/games/swarm/swarm_enemy.gd` — flock separation between drones
- `scripts/games/swarm/swarm_director.gd` — `report_win()` on kill, `report_death()` on core breach
- `scripts/games/hw_zombie_defense/hw_zombie_defense.gd` — `follow()` + `wander()` shamble
- `scripts/games/laser-tag-ar/laser-tag-ar.gd` — bot movement via `follow()` + `wander()`
- `scripts/games/ar-defender/ar-defender.gd` — waypoint enemies get `wander()` drift
- `scripts/games/myth_zoo/myth_zoo.gd` — creature play-mode approach via `investigate()`

## UIKit (autoload `UIKit`)

| # | Func | What it does |
|---|------|--------------|
| a | `make_hud(parent) -> {root, score, health}` | Score top-left + health top-right, big fonts |
| b | `score_popup(parent, pos, text, color)` | Floating "+100": `Vector3` → Label3D, `Vector2` → canvas Label; rises and fades |
| c | `click_sound(parent=null, freq=880, dur=0.07) -> AudioStreamPlayer` | Generated blip, no assets; auto-frees |
| d | `ui_haptic(kind="tick")` | Via shared `Haptics` (`tick`/`pulse`/`thump`); honors persisted haptics toggle |
| e | `loading_indicator(parent, text) -> Control` | Spinner overlay; dismiss with `.hide()`; blocks input |
| f | `toast(parent, msg, duration=2.0)` | Bottom toast, fades and frees |
| g | `tutorial_hint(parent, msg) -> PanelContainer` | Top-center hint box; caller frees it |
| h | `pause_menu(parent, on_resume) -> Control` | Resume / Quit-to-Hub (returns to `res://scenes/main.tscn`); pauses tree |
| i | `big_fonts() -> Theme` | Default font size 40 for Controls |
| j | `settings_row(parent) -> HBoxContainer` | Volume slider + haptics toggle, persisted to `user://nexus_arcade_settings.cfg`; volume drives the Master bus |

## Files

- `scripts/shared/visual_fx.gd` — autoload `VisualFX`
- `scripts/shared/ai_lib.gd` — autoload `AILib`
- `scripts/shared/ui_kit.gd` — autoload `UIKit`
- `scripts/shared/base_game.gd` — `class_name NexusBaseGame extends Node3D`
- `project.godot` `[autoload]` — registers the three singletons

## Cuts

None — all 30 upgrades run cheaply on the Compatibility renderer as designed
(low particle counts, 2-split shadows, standard fog only, one 256px gradient
texture, trivial sky shader, Control-based UI). If on-device profiling shows
glow or shadows hurting a specific game, that game can set `use_glow=false`
or skip `configure_shadows`.
