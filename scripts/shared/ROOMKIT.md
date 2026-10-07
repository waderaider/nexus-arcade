# RoomKit — v0.7.0 shared room-layout module

`scripts/shared/room_kit.gd` — `class_name RoomKit extends RefCounted`.
Static-only: no autoload, no instance, no `project.godot` changes.

Thin wrapper around the `godot_openxr_vendors` Meta Scene API
(`OpenXRFbSceneManager` / `OpenXRFbSpatialEntity`). All class/method names
below were verified against the actual plugin binary via headless
`ClassDB` introspection (Godot 4.7.2, 2026-10-07) — no guessing.

## Guarantees

- **Headless-safe.** No XR runtime / no room data → getters return fallbacks
  (empty arrays, `DEFAULT_BOUNDS`), `refresh()` / `request_capture()` are
  silent no-ops. Never crashes, never spams errors in the fallback path.
- **Quest-3-performant.** Results are cached. The scene is (re-)queried only
  inside `refresh()` — never per frame.
- **Plugin-optional.** Uses `ClassDB` lookups and untyped refs only, so the
  script still parses if the vendor plugin is ever disabled.

## API

| func | returns |
|---|---|
| `is_available() -> bool` | XR running AND scene manager usable |
| `has_room_data() -> bool` | room layout entities were parsed |
| `refresh() -> void` | (re-)query layout, rebuild caches; safe no-op when unavailable |
| `request_capture() -> void` | trigger Quest room capture; safe no-op when unsupported |
| `get_walls() -> Array[Dictionary]` | `{position: Vector3` (plane center, world)`, size: Vector2` (w,h)`, normal: Vector3` (normalized, world)`}` |
| `get_tables() -> Array[Dictionary]` | `{position: Vector3` (box center, world)`, size: Vector3` (full extents)`}` |
| `get_furniture() -> Array[Dictionary]` | `{position: Vector3, size: Vector3, label: String}` |
| `get_furniture_by_label(label) -> Array[Dictionary]` | furniture whose label contains `label` (case-insensitive): "couch", "bed", "storage", "screen", "plant", ... |
| `get_couch() -> Dictionary` | first couch cuboid, or `{}` when none |
| `get_bed() -> Dictionary` | first bed cuboid, or `{}` when none |
| `get_storage() -> Array[Dictionary]` | storage cuboids (shelves, cabinets), possibly empty |
| `get_anchors(label) -> Array[Dictionary]` | **generic**: every anchor whose semantic label contains `label` — "couch","chair","table","bed","storage","screen","tv","lamp","plant","door","window","wall","floor","ceiling","rug",... → `{position: Vector3, size: Vector3, yaw: float, label: String, kind: String ("box"/"quad")}` |
| `skin_anchor(anchor, skin) -> Node3D` | instantiate a PackedScene (or res:// path) aligned to an anchor; null on failure |
| `morph(anchor, skin_name) -> Node3D` | apply a themed morph skin ("scifi","arcane","lava","underwater","haunted","candy","neon","nature"); null when anchor empty or library missing |
| `place_on_cuboid(node, cuboid, y_offset=0.0)` | move a Node3D to the top-center of a cuboid (world space); no-op on empty |
| `cuboid_top(cuboid) -> Vector3` | top-center point of a cuboid; `Vector3.ZERO` on empty |
| `room_bounds() -> Rect2` | floor XZ extents (world); `Rect2(-2,-2,4,4)` when unknown |

`refresh()` is the one call designed to be used **unguarded**; guard every
getter with `RoomKit.is_available() and RoomKit.has_room_data()` so
desktop/fallback behavior is unchanged.

Label mapping (Meta semantic labels, matched case-insensitively):
`WALL_FACE` → walls (quads < 1 m are treated as wall art, not walls),
`FLOOR` → room bounds, `TABLE`/`DESK` → tables, `CEILING`/room container →
skipped, anything else with a 3D bounding box → furniture.

## How a game opts in (3 lines)

```gdscript
func _ready() -> void:
    RoomKit.refresh() # safe no-op without XR; caches the room layout

func _physics_process(_delta: float) -> void:
    if RoomKit.is_available() and RoomKit.has_room_data():
        for w in RoomKit.get_walls():
            pass # bounce / clamp / spawn using w["position"], w["size"], w["normal"]
```

## Wired games (v0.7.0)

- **ar-bowling** — ball reflects off real wall planes (`_room_wall_bounce()`,
  world-space plane test, normal-sign agnostic so it works regardless of the
  anchor's facing convention).
- **gravity-pong** — play bounds constrained to `RoomKit.room_bounds()`
  plus real wall-plane bounces (`_room_wall_bounce(pos)`), all in world space.
- **holo-pets** — 35% of wander picks choose a hiding spot just outside a
  random table/furniture cuboid instead of a random floor point
  (`_furniture_hiding_spot()`).

## Furniture morph design guide (v0.7.0)

`RoomKit.morph(anchor, skin)` wraps any anchor in a themed shell + particles +
sound. Skins: "scifi", "arcane", "lava", "underwater", "haunted", "candy",
"neon", "nature". Skins are auras/shells around the anchor cuboid —
passthrough still shows the real object underneath, so design for
augmentation, not replacement. One-liner:

```gdscript
if RoomKit.is_available() and RoomKit.has_room_data():
    var couches := RoomKit.get_anchors("couch")
    if not couches.is_empty():
        RoomKit.morph(couches[0], "haunted")  # or "scifi", "lava", ...
```

Per-object direction (pick the anchor + skin that fits the game's genre;
every game should morph at least one anchor meaningfully):
- **TV / screen** (`get_anchors("screen")`, also try "tv") → portal screen,
  mission-briefing display, live scoreboard. Skins: "scifi", "neon".
- **Rug** (`get_anchors("rug")`) → magic-circle arena, lava pit, neon dance
  floor. Skins: "arcane", "lava", "neon".
- **Chairs** (`get_anchors("chair")`) → thrones, monster nests, race seats.
  Skins: "arcane", "haunted", "neon".
- **Tables** (`get_anchors("table")` / `get_tables()`) → altar, workbench,
  battle map, DJ booth. Skins: "arcane", "scifi", "candy".
- **Bed** (`get_couch()`-style `get_bed()`) → cloud rest stop, lava-surrounded
  isle, haunted crypt slab. Skins: "nature", "lava", "haunted".
- **Storage** (`get_storage()`) → treasure vault, armory, candy stash.
  Skins: "neon", "candy", "scifi".
- **Lamps** (`get_anchors("lamp")`) → arcane beacons, haunted flicker-lights.
  Skins: "arcane", "haunted".
- **Plants** (`get_anchors("plant")`) → overgrown guardians, candy flora.
  Skins: "nature", "candy".
- **Doors** (`get_anchors("door")`) → dungeon gates, sci-fi airlocks.
  Skins: "haunted", "scifi".
- **Windows** (`get_anchors("window")`) → space vistas, underwater portholes.
  Skins: "scifi", "underwater".
- **Couch** (`get_couch()`) → the showcase morph (see Couch Morph
  experience): ship bridge, lava island, pirate deck. Any skin works.

Fallback: `morph()` returns null on empty anchors — keep the game's default
layout and, where it matters, prompt the user to complete Quest Space Setup.

## Not Quest-tested

Verified headless only (fallbacks + parse checks). On-device behavior
(wall normals, label strings, capture flow) still needs a Quest 3 run.
