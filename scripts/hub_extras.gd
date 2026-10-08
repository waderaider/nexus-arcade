## HubExtras - v0.8.0 menu experience upgrades for the NEXUS ARCADE hub.
##
## Self-contained: attaches to a running NexusHub WITHOUT any hub.gd edits.
## Usage (call once, after the hub is ready):
##     HubExtras.attach(hub)
##
## What it adds:
##  1. Animated aurora background: a full-rect ColorRect with a cheap
##     canvas_item shader (slow cyan/magenta gradient bands + vignette),
##     layered just above the hub's flat background.
##  2. Game descriptions: one line for every game, shown as a subtitle line
##     directly under the grid on hover/focus. Falls back to the tab tagline
##     when a name has no description.
##  3. Favorites (star toggle on every game button) + a recently-played row,
##     persisted in user://nexus_settings.cfg (section "hub_extras").
##     A "Favorites" chip row and a "Recent" chip row appear at the top of
##     the GAMES tab; tapping a star again unstars.
##  4. Search: a LineEdit above the grid filters the current tab's games by
##     name substring (case-insensitive). Enter applies, clearing restores
##     the hub's own paging.
##
## Everything is re-applied on a short timer so it survives the hub's
## _build_page() rebuilds (tab switches, paging, search restores).
class_name HubExtras
extends Node

const SETTINGS_PATH := "user://nexus_settings.cfg"
const SYNC_INTERVAL := 0.5
const SEARCH_DEBOUNCE := 0.25
const MAX_RECENTS := 8
const MAX_SEARCH_RESULTS := 25
const GRID_BTN_H := 100.0
const GRID_BTN_H_COMPACT := 80.0
const DEFAULT_HINT := "Point the laser and pull the trigger (or pinch) to select - hover a game for details"

const TAB_TAGLINES := [
	"Arcade action for your room.",
	"Handy AR utilities for everyday life.",
	"Make something new.",
	"Spooky-season mini-games.",
]

## Master game table (mirrors hub.gd's CAT_* lists): name, scene, tab, desc.
## Used for descriptions, scene lookup, and search filtering. If hub.gd ever
## drifts, scene lookup falls back to the hub's live lists and descriptions
## fall back to the tab tagline.
const GAMES := [
	{"n": "Gravity Golf", "s": "res://scenes/golf/golf.tscn", "t": 0, "d": "Putt across floating courses where every shot bends gravity."},
	{"n": "Swarm Protocol", "s": "res://scenes/swarm/swarm.tscn", "t": 0, "d": "Command your drone swarm to outmaneuver the hive."},
	{"n": "Neon Duel", "s": "res://scenes/duel/duel.tscn", "t": 0, "d": "Fast-draw light-blade duels in your living room."},
	{"n": "Beat Blades", "s": "res://scenes/beat-blades/beat-blades.tscn", "t": 0, "d": "Slice incoming beats with twin energy blades."},
	{"n": "Portal Ball", "s": "res://scenes/portal-ball/portal-ball.tscn", "t": 0, "d": "Bank shots through portals to solve kinetic puzzles."},
	{"n": "Laser Tag AR", "s": "res://scenes/laser-tag-ar/laser-tag-ar.tscn", "t": 0, "d": "Classic laser tag, played across your real room."},
	{"n": "Gravity Pong", "s": "res://scenes/gravity-pong/gravity-pong.tscn", "t": 0, "d": "Pong where the ball obeys shifting gravity."},
	{"n": "AR Bowling", "s": "res://scenes/ar-bowling/ar-bowling.tscn", "t": 0, "d": "Bowl strikes down a lane projected on your floor."},
	{"n": "Time Pilot", "s": "res://scenes/time-pilot/time-pilot.tscn", "t": 0, "d": "Rewind time mid-flight to dodge what already hit you."},
	{"n": "Room Racer", "s": "res://scenes/room-racer/room-racer.tscn", "t": 0, "d": "Race hover cars on a track mapped to your room."},
	{"n": "AR Defender", "s": "res://scenes/ar-defender/ar-defender.tscn", "t": 0, "d": "Defend your furniture forts against enemy waves."},
	{"n": "Sky Defender", "s": "res://scenes/sky-defender/sky-defender.tscn", "t": 0, "d": "Swat invading drones out of your ceiling sky."},
	{"n": "Drone Racer", "s": "res://scenes/drone-racer/drone-racer.tscn", "t": 0, "d": "Thread FPV drones through rings around your home."},
	{"n": "Tower Topple", "s": "res://scenes/tower-topple/tower-topple.tscn", "t": 0, "d": "Topple physics towers without waking the giant."},
	{"n": "Spell Duel", "s": "res://scenes/spell-duel/spell-duel.tscn", "t": 0, "d": "Duel rival wizards with gesture-cast spells."},
	{"n": "Rhythm Boxer", "s": "res://scenes/rhythm-boxer/rhythm-boxer.tscn", "t": 0, "d": "Punch targets to the beat, round after round."},
	{"n": "Marble Run", "s": "res://scenes/marble-run/marble-run.tscn", "t": 0, "d": "Build wild marble tracks across your tables."},
	{"n": "AR Darts", "s": "res://scenes/ar-darts/ar-darts.tscn", "t": 0, "d": "Darts on a holographic board on your wall."},
	{"n": "Zero-G Hoops", "s": "res://scenes/zero-g-hoops/zero-g-hoops.tscn", "t": 0, "d": "Basketball where every dunk floats."},
	{"n": "AR Fishing", "s": "res://scenes/ar-fishing/ar-fishing.tscn", "t": 0, "d": "Cast into a pond that appears on your floor."},
	{"n": "Laser Mirrors", "s": "res://scenes/mirror-maze/mirror-maze.tscn", "t": 0, "d": "Aim lasers with mirrors to hit every target."},
	{"n": "Gravity Glove", "s": "res://scenes/gravity-glove/gravity-glove.tscn", "t": 0, "d": "Grab and fling objects with a gravity glove."},
	{"n": "Time Freeze", "s": "res://scenes/time-freeze/time-freeze.tscn", "t": 0, "d": "Freeze time, reposition, then let chaos resume."},
	{"n": "Portal Maze", "s": "res://scenes/portal-maze/portal-maze.tscn", "t": 0, "d": "Escape mazes stitched together with portals."},
	{"n": "Air Drums", "s": "res://scenes/air-drums/air-drums.tscn", "t": 0, "d": "Play a full drum kit on thin air."},
	{"n": "Shadow Puppets", "s": "res://scenes/shadow-puppet/shadow-puppet.tscn", "t": 0, "d": "Cast shadow creatures onto your walls."},
	{"n": "Holo Chess", "s": "res://scenes/holo-chess/holo-chess.tscn", "t": 0, "d": "Chess with holographic pieces on your table."},
	{"n": "Starforge", "s": "res://scenes/starforge/starforge.tscn", "t": 0, "d": "Forge a star system, planet by planet."},
	{"n": "Holo Dungeon", "s": "res://scenes/holo-dungeon/holo-dungeon.tscn", "t": 0, "d": "A dungeon crawler that unfolds in your room."},
	{"n": "AR Escape Room", "s": "res://scenes/ar-escape-room/ar-escape-room.tscn", "t": 0, "d": "Solve the room to escape the room."},
	{"n": "AR Billiards", "s": "res://scenes/ar-billiards/ar-billiards.tscn", "t": 0, "d": "Pool on your coffee table - no table required."},
	{"n": "Holo Chef", "s": "res://scenes/holo_chef/holo_chef.tscn", "t": 0, "d": "Cook holographic recipes with your own hands."},
	{"n": "Dragon Ranch", "s": "res://scenes/dragon_ranch/dragon_ranch.tscn", "t": 0, "d": "Raise and train your own AR dragons."},
	{"n": "Wizard Academy", "s": "res://scenes/wizard_academy/wizard_academy.tscn", "t": 0, "d": "Learn real spell combos at wizard school."},
	{"n": "Holo Farm", "s": "res://scenes/holo_farm/holo_farm.tscn", "t": 0, "d": "Grow a farm that lives on your floor."},
	{"n": "Mech Pilot", "s": "res://scenes/mech_pilot/mech_pilot.tscn", "t": 0, "d": "Climb into a mech and stomp the block."},
	{"n": "Deep Dive", "s": "res://scenes/deep_dive/deep_dive.tscn", "t": 0, "d": "Dive an ocean trench from your couch."},
	{"n": "AR Detective", "s": "res://scenes/ar_detective/ar_detective.tscn", "t": 0, "d": "Hunt for clues hidden around your home."},
	{"n": "Sky Pirates", "s": "res://scenes/sky_pirates/sky_pirates.tscn", "t": 0, "d": "Board airships and duel sky pirates."},
	{"n": "Monster Lab", "s": "res://scenes/monster_lab/monster_lab.tscn", "t": 0, "d": "Mix monster DNA and unleash your creation."},
	{"n": "Myth Zoo", "s": "res://scenes/myth_zoo/myth_zoo.tscn", "t": 0, "d": "Mythical beasts roaming your space."},
	{"n": "QR Treasure Hunt", "s": "res://scenes/qr_hunt/qr_hunt.tscn", "t": 0, "d": "Follow QR clues to buried AR treasure."},
	{"n": "AR Measure", "s": "res://scenes/ar-measure/ar-measure.tscn", "t": 1, "d": "Measure anything with a laser tape line."},
	{"n": "Holo Notes", "s": "res://scenes/holo-notes/holo-notes.tscn", "t": 1, "d": "Sticky notes that float where you leave them."},
	{"n": "Star Map", "s": "res://scenes/star-map/star-map.tscn", "t": 1, "d": "Name the constellations on your ceiling."},
	{"n": "Sky Traffic", "s": "res://scenes/sky_traffic/sky_traffic.tscn", "t": 1, "d": "Watch live airplanes cross your sky in AR."},
	{"n": "Eye Spy AR", "s": "res://scenes/eye_spy/eye_spy.tscn", "t": 1, "d": "I spy, played with your whole house."},
	{"n": "Plant Doctor", "s": "res://scenes/plant_doctor/plant_doctor.tscn", "t": 1, "d": "Scan your houseplants for a health checkup."},
	{"n": "AR Workout", "s": "res://scenes/ar-workout/ar-workout.tscn", "t": 1, "d": "A trainer that counts your reps in AR."},
	{"n": "Holo Pets", "s": "res://scenes/holo-pets/holo-pets.tscn", "t": 1, "d": "Adopt a pet that lives on your furniture."},
	{"n": "Mind Palace", "s": "res://scenes/mind-palace/mind-palace.tscn", "t": 1, "d": "Build a memory palace out of your rooms."},
	{"n": "AR DJ", "s": "res://scenes/ar-dj/ar-dj.tscn", "t": 1, "d": "Spin tracks on floating decks."},
	{"n": "Familiar", "s": "res://scenes/familiar/familiar.tscn", "t": 1, "d": "A magical companion that follows you around."},
	{"n": "Couch Morph", "s": "res://scenes/couch_morph/couch_morph.tscn", "t": 1, "d": "Reskin your couch: spaceship, lava isle, pirate deck."},
	{"n": "Portal Painter", "s": "res://scenes/portal-painter/portal-painter.tscn", "t": 2, "d": "Paint murals that hang in midair."},
	{"n": "Light Painter", "s": "res://scenes/light-painter/light-painter.tscn", "t": 2, "d": "Draw with light and leave glowing trails."},
	{"n": "Holo Piano", "s": "res://scenes/holo-piano/holo-piano.tscn", "t": 2, "d": "A grand piano projected onto your floor."},
	{"n": "Holo Theremin", "s": "res://scenes/holo-theremin/holo-theremin.tscn", "t": 2, "d": "Make music just by waving your hands."},
	{"n": "AR Graffiti", "s": "res://scenes/graffiti-wall/graffiti-wall.tscn", "t": 2, "d": "Tag your walls with zero cleanup."},
	{"n": "AR Karaoke", "s": "res://scenes/ar-karaoke/ar-karaoke.tscn", "t": 2, "d": "Karaoke night with lyrics on your wall."},
	{"n": "Sand Shaper", "s": "res://scenes/sand-shaper/sand-shaper.tscn", "t": 2, "d": "Sculpt a sandbox that never spills."},
	{"n": "Clay Shaper", "s": "res://scenes/clay-shaper/clay-shaper.tscn", "t": 2, "d": "Throw virtual clay on a floating wheel."},
	{"n": "Sketch to 3D", "s": "res://scenes/sketch_3d/sketch_3d.tscn", "t": 2, "d": "Sketch it, then watch it pop into 3D."},
	{"n": "Holo Garden", "s": "res://scenes/holo-garden/holo-garden.tscn", "t": 2, "d": "Plant a garden that blooms overnight."},
	{"n": "Zero-G Sandbox", "s": "res://scenes/zero-g-sandbox/zero-g-sandbox.tscn", "t": 2, "d": "Build contraptions in zero gravity."},
	{"n": "Holo Aquarium", "s": "res://scenes/holo-aquarium/holo-aquarium.tscn", "t": 2, "d": "An aquarium on your wall, no water needed."},
	{"n": "Pumpkin Smash", "s": "res://scenes/hw_pumpkin_smash/hw_pumpkin_smash.tscn", "t": 3, "d": "Smash every pumpkin before time runs out."},
	{"n": "Ghost Catch", "s": "res://scenes/hw_ghost_catch/hw_ghost_catch.tscn", "t": 3, "d": "Catch mischievous ghosts with your net."},
	{"n": "Candy Run", "s": "res://scenes/hw_candy_run/hw_candy_run.tscn", "t": 3, "d": "Grab candy while dodging spooky traps."},
	{"n": "Haunted Maze", "s": "res://scenes/hw_haunted_maze/hw_haunted_maze.tscn", "t": 3, "d": "Escape a maze that rearranges itself."},
	{"n": "Web Slingshot", "s": "res://scenes/hw_web_slingshot/hw_web_slingshot.tscn", "t": 3, "d": "Slingshot through giant spider webs."},
	{"n": "Potion Mix", "s": "res://scenes/hw_potion_mix/hw_potion_mix.tscn", "t": 3, "d": "Brew the perfect potion - don't blow up the lab."},
	{"n": "Zombie Defense", "s": "res://scenes/hw_zombie_defense/hw_zombie_defense.tscn", "t": 3, "d": "Barricade your room against the horde."},
	{"n": "Bat Catch", "s": "res://scenes/hw_bat_catch/hw_bat_catch.tscn", "t": 3, "d": "Snatch bats out of the midnight sky."},
	{"n": "Door Dash", "s": "res://scenes/hw_door_dash/hw_door_dash.tscn", "t": 3, "d": "Knock on haunted doors: trick or treat?"},
	{"n": "Skeleton Dance", "s": "res://scenes/hw_skeleton_dance/hw_skeleton_dance.tscn", "t": 3, "d": "Match the skeleton's dance moves."},
	{"n": "Eyeball Pong", "s": "res://scenes/hw_eyeball_pong/hw_eyeball_pong.tscn", "t": 3, "d": "Pong with eyeballs. Obviously."},
	{"n": "Broom Flight", "s": "res://scenes/hw_broom_flight/hw_broom_flight.tscn", "t": 3, "d": "Race broomsticks through the night sky."},
	{"n": "Monster Mash", "s": "res://scenes/hw_monster_mash/hw_monster_mash.tscn", "t": 3, "d": "Dance-battle classic movie monsters."},
	{"n": "Candy Stack", "s": "res://scenes/hw_candy_stack/hw_candy_stack.tscn", "t": 3, "d": "Stack candy as high as physics allows."},
	{"n": "Mummy Wrap", "s": "res://scenes/hw_mummy_wrap/hw_mummy_wrap.tscn", "t": 3, "d": "Wrap the mummy before it wakes up."},
	{"n": "Bat Dodge", "s": "res://scenes/hw_bat_dodge/hw_bat_dodge.tscn", "t": 3, "d": "Dodge swooping bats in your hallway."},
	{"n": "Pumpkin Carve", "s": "res://scenes/hw_pumpkin_carve/hw_pumpkin_carve.tscn", "t": 3, "d": "Carve jack-o'-lanterns with light."},
	{"n": "Portrait Gallery", "s": "res://scenes/hw_portrait_gallery/hw_portrait_gallery.tscn", "t": 3, "d": "Portraits whose eyes follow you. Creepy."},
	{"n": "Spider Catch", "s": "res://scenes/hw_spider_catch/hw_spider_catch.tscn", "t": 3, "d": "Catch the spiders before they reach you."},
	{"n": "Werewolf Howl", "s": "res://scenes/hw_werewolf_howl/hw_werewolf_howl.tscn", "t": 3, "d": "Howl in tune to wake the pack."},
	{"n": "Grave Digger", "s": "res://scenes/hw_grave_digger/hw_grave_digger.tscn", "t": 3, "d": "Dig for treasure in the haunted graveyard."},
	{"n": "Hayride Shooter", "s": "res://scenes/hw_hayride_shooter/hw_hayride_shooter.tscn", "t": 3, "d": "Shoot targets from a rolling hayride."},
	{"n": "Apple Bobbing", "s": "res://scenes/hw_apple_bobbing/hw_apple_bobbing.tscn", "t": 3, "d": "Bob for apples, AR style."},
	{"n": "Phantom Piano", "s": "res://scenes/hw_phantom_piano/hw_phantom_piano.tscn", "t": 3, "d": "Play a piano that plays itself back."},
	{"n": "Goblin Archery", "s": "res://scenes/hw_goblin_archery/hw_goblin_archery.tscn", "t": 3, "d": "Outshoot goblins in the dark forest."},
	{"n": "Haunted Mirror Maze", "s": "res://scenes/hw_mirror_maze/hw_mirror_maze.tscn", "t": 3, "d": "A mirror maze full of lying reflections."},
	{"n": "Pumpkin Bowling", "s": "res://scenes/hw_pumpkin_bowling/hw_pumpkin_bowling.tscn", "t": 3, "d": "Bowling with pumpkins for balls."},
	{"n": "Witch Hat Toss", "s": "res://scenes/hw_hat_toss/hw_hat_toss.tscn", "t": 3, "d": "Toss rings onto the witch hats."},
	{"n": "Monster Feed", "s": "res://scenes/hw_monster_feed/hw_monster_feed.tscn", "t": 3, "d": "Feed the monster before it feeds on you."},
	{"n": "Midnight Survival", "s": "res://scenes/hw_midnight_survival/hw_midnight_survival.tscn", "t": 3, "d": "Survive until dawn in the haunted house."},
]

const AURORA_SHADER := """
shader_type canvas_item;
uniform vec4 tint_a : source_color = vec4(0.0, 0.85, 1.0, 1.0);
uniform vec4 tint_b : source_color = vec4(1.0, 0.2, 0.85, 1.0);
void FRAGMENT() {
	vec2 uv = UV;
	float t = TIME * 0.06;
	float w1 = sin(uv.x * 6.28318 + t * 6.28318 + 1.7 * sin(uv.y * 4.0 + t * 2.0)) * 0.5 + 0.5;
	float w2 = sin((uv.y + uv.x * 0.6) * 5.0 - t * 4.0) * 0.5 + 0.5;
	vec3 col = mix(tint_a.rgb, tint_b.rgb, clamp(w1 * 0.45 + w2 * 0.35, 0.0, 1.0));
	float vig = smoothstep(0.9, 0.3, distance(uv, vec2(0.5, 0.45)));
	vec3 final_col = col * (0.25 + 0.75 * vig) * 0.35;
	COLOR = vec4(final_col, 0.5);
}
"""

var _hub: Node = null
var _ui: Control = null
var _timer: Timer = null
var _debounce: Timer = null
var _favorites: Array[String] = []
var _recents: Array[String] = []
var _query := ""
var _search_active := false
var _search_applied_for := ""
var _last_grid_sig := ""
var _rows_sig := ""
var _fav_row: HBoxContainer = null
var _rec_row: HBoxContainer = null
var _search_edit: LineEdit = null
var _desc: Label = null


## Attach all extras to a running hub. Safe to call once; extra calls are
## no-ops. Requires no changes to hub.gd: everything is built by adding
## children to the hub's viewport/panel at runtime.
static func attach(hub: Node) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	if hub.has_meta("_he_attached"):
		return
	hub.set_meta("_he_attached", true)
	# Instantiate via load() rather than the HubExtras class_name so attach()
	# works even on a fresh clone whose global class cache is stale.
	var script: GDScript = load("res://scripts/hub_extras.gd")
	var ex: Node = script.new()
	ex.name = "HubExtras"
	hub.add_child(ex)
	ex._setup(hub)


func _setup(hub: Node) -> void:
	_hub = hub
	if _hub.get("_viewport") == null:
		# Hub may not have built its panel yet; retry once next frame.
		await get_tree().process_frame
		if not is_instance_valid(_hub) or _hub.get("_viewport") == null:
			push_warning("[HubExtras] hub viewport not found; extras disabled.")
			return
	_load_settings()
	_build()
	if _ui == null:
		push_warning("[HubExtras] hub UI not found; extras disabled.")
		return
	_timer = Timer.new()
	_timer.name = "ExtrasSync"
	_timer.wait_time = SYNC_INTERVAL
	_timer.timeout.connect(_sync)
	add_child(_timer)
	_debounce = Timer.new()
	_debounce.name = "ExtrasSearchDebounce"
	_debounce.wait_time = SEARCH_DEBOUNCE
	_debounce.one_shot = true
	_debounce.timeout.connect(_apply_search)
	add_child(_debounce)
	_timer.start()
	_sync()


# ---------------------------------------------------------------- build ---

func _build() -> void:
	var vp: SubViewport = _hub.get("_viewport")
	var ui: Control = vp.get_node_or_null("UI")
	if ui == null:
		return
	_ui = ui
	var grid: GridContainer = _hub.get("_grid")
	if grid == null or not is_instance_valid(grid):
		_ui = null
		return
	var vbox := grid.get_parent() as VBoxContainer
	if vbox == null:
		_ui = null
		return
	# Tighter separations buy vertical room for the new rows.
	vbox.add_theme_constant_override("separation", 10)

	# 1. Animated aurora background, just above the hub's flat ColorRect.
	var aurora := ColorRect.new()
	aurora.name = "ExtrasAurora"
	aurora.set_anchors_preset(Control.PRESET_FULL_RECT)
	aurora.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = AURORA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	aurora.material = sm
	ui.add_child(aurora)
	ui.move_child(aurora, 1)

	# 3. Favorites + recents rows (visible on the GAMES tab when non-empty).
	_fav_row = _make_chip_row("★ Favorites")
	_rec_row = _make_chip_row("Recent")
	ui.add_child(_fav_row)  # placeholder parent; moved below
	ui.add_child(_rec_row)
	# 4. Search box above the grid.
	var search_row := HBoxContainer.new()
	search_row.name = "ExtrasSearch"
	search_row.add_theme_constant_override("separation", 12)
	var sicon := Label.new()
	sicon.text = "Search:"
	sicon.add_theme_font_size_override("font_size", 24)
	sicon.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	search_row.add_child(sicon)
	_search_edit = LineEdit.new()
	_search_edit.name = "ExtrasSearchEdit"
	_search_edit.placeholder_text = "Type to filter this tab's games..."
	_search_edit.clear_button_enabled = true
	_search_edit.custom_minimum_size = Vector2(0, 44)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.add_theme_font_size_override("font_size", 22)
	_search_edit.text_changed.connect(_on_search_text)
	_search_edit.text_submitted.connect(_on_search_submitted)
	search_row.add_child(_search_edit)

	# Insert the new rows into the hub's vbox, just above the grid.
	for row in [_fav_row, _rec_row, search_row]:
		ui.remove_child(row)
		vbox.add_child(row)
		vbox.move_child(row, grid.get_index())

	# 2. Description subtitle line directly under the grid. It takes the
	# place of the hub's static hint label (same slot, same cost); the hint
	# text becomes the default description text.
	_desc = Label.new()
	_desc.name = "ExtrasDesc"
	_desc.text = DEFAULT_HINT
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.add_theme_font_size_override("font_size", 20)
	_desc.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_desc.clip_text = true
	_desc.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_desc)
	vbox.move_child(_desc, grid.get_index() + 1)
	var hint: Label = ui.find_child("HintLabel", true, false)
	if hint != null:
		hint.visible = false
	grid.mouse_exited.connect(_reset_desc)


func _make_chip_row(header_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "ExtrasRow" + header_text.replace(" ", "").replace("★", "Fav")
	row.add_theme_constant_override("separation", 12)
	row.visible = false
	var header := Label.new()
	header.text = header_text + ":"
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	row.add_child(header)
	var chips := HBoxContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("separation", 10)
	row.add_child(chips)
	return row


func _make_chip(game_name: String) -> Button:
	var b := Button.new()
	b.name = "Chip"
	b.text = game_name
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.24, 0.4)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.24, 0.34, 0.55)
	b.add_theme_stylebox_override("hover", hov)
	b.pressed.connect(_launch.bind(game_name))
	return b


# ----------------------------------------------------------------- sync ---

func _sync() -> void:
	if _hub == null or not is_instance_valid(_hub) or _ui == null:
		if is_instance_valid(_timer):
			_timer.stop()
		return
	var grid: GridContainer = _hub.get("_grid")
	if grid == null or not is_instance_valid(grid):
		return
	_hook_grid_buttons(grid)
	_update_stars(grid)
	_maybe_reapply_search(grid)
	_refresh_rows()
	_adjust_grid_height(grid)
	if _search_active:
		# Keep the pager in "search results" mode even if the hub rebuilt.
		var pl: Label = _hub.get("_page_label")
		if pl != null and is_instance_valid(pl):
			pl.text = "%d result(s) for '%s'" % [_last_search_count, _query.strip_edges()]
		for key in ["_nav_prev", "_nav_next"]:
			var nb: Button = _hub.get(key)
			if nb != null and is_instance_valid(nb):
				nb.visible = false


func _grid_signature(grid: GridContainer) -> String:
	var parts: PackedStringArray = []
	for c in grid.get_children():
		if c is Button:
			parts.append((c as Button).text)
	return "|".join(parts)


func _hook_grid_buttons(grid: GridContainer) -> void:
	for c in grid.get_children():
		if not (c is Button):
			continue
		var b := c as Button
		if b.has_meta("_he"):
			continue
		b.set_meta("_he", true)
		var game_name := b.text
		b.mouse_entered.connect(_on_hover.bind(game_name))
		b.focus_entered.connect(_on_hover.bind(game_name))
		b.pressed.connect(_on_grid_pressed.bind(game_name))
		_ensure_star(b, game_name)


func _ensure_star(b: Button, game_name: String) -> void:
	var star := b.get_node_or_null("_Star") as Button
	if star == null:
		star = Button.new()
		star.name = "_Star"
		star.focus_mode = Control.FOCUS_NONE
		star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		star.offset_left = -56.0
		star.offset_top = 4.0
		star.offset_right = -8.0
		star.offset_bottom = 52.0
		star.add_theme_font_size_override("font_size", 30)
		star.pressed.connect(_toggle_fav.bind(game_name))
		# The star sits on top of the game button and consumes its own
		# clicks, so starring never launches the game.
		b.add_child(star)


func _update_stars(grid: GridContainer) -> void:
	for c in grid.get_children():
		if not (c is Button):
			continue
		var b := c as Button
		var star := b.get_node_or_null("_Star") as Button
		if star == null:
			continue
		var fav: bool = b.text in _favorites
		star.text = "★" if fav else "☆"
		star.add_theme_color_override(
			"font_color",
			Color(1.0, 0.85, 0.2) if fav else Color(1, 1, 1, 0.55))


func _maybe_reapply_search(grid: GridContainer) -> void:
	var sig := _grid_signature(grid)
	if _search_active:
		var key := _query.strip_edges().to_lower() + "|" + str(int(_hub.get("_tab")))
		if _search_applied_for != key:
			_apply_search()
	else:
		_last_grid_sig = sig


func _refresh_rows() -> void:
	var tab := int(_hub.get("_tab"))
	var show := tab == 0
	var sig := "%d|%s|%s" % [tab,
		",".join(PackedStringArray(_favorites)),
		",".join(PackedStringArray(_recents))]
	_fav_row.visible = show and not _favorites.is_empty()
	_rec_row.visible = show and not _recents.is_empty()
	if sig == _rows_sig:
		return
	_rows_sig = sig
	_fill_chips(_fav_row, _favorites)
	_fill_chips(_rec_row, _recents)


func _fill_chips(row: HBoxContainer, names: Array[String]) -> void:
	var chips: HBoxContainer = row.get_node_or_null("Chips")
	if chips == null:
		return
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	for n in names:
		chips.add_child(_make_chip(n))


func _adjust_grid_height(grid: GridContainer) -> void:
	# When the extras rows are visible, slim the game buttons a little so the
	# footer's update/version row never clips off the 1000px viewport.
	var compact := _fav_row.visible or _rec_row.visible
	var h := GRID_BTN_H_COMPACT if compact else GRID_BTN_H
	for c in grid.get_children():
		if c is Button:
			var b := c as Button
			var ms := b.custom_minimum_size
			if ms.y != h:
				b.custom_minimum_size = Vector2(ms.x, h)


# --------------------------------------------------------------- search ---

var _last_search_count := 0


func _on_search_text(new_text: String) -> void:
	_query = new_text
	_debounce.start()


func _on_search_submitted(_text: String) -> void:
	_debounce.stop()
	_apply_search()


func _apply_search() -> void:
	if _hub == null or not is_instance_valid(_hub):
		return
	var grid: GridContainer = _hub.get("_grid")
	if grid == null or not is_instance_valid(grid):
		return
	var q := _query.strip_edges().to_lower()
	var tab := int(_hub.get("_tab"))
	if q == "":
		if _search_active:
			_search_active = false
			_search_applied_for = ""
			# Hand the grid back to the hub's own paging.
			_hub.call("_build_page")
		return
	_search_active = true
	_search_applied_for = q + "|" + str(tab)
	var matches: Array = []
	for g in GAMES:
		var gd: Dictionary = g
		if int(gd["t"]) == tab and str(gd["n"]).to_lower().contains(q):
			matches.append(gd)
			if matches.size() >= MAX_SEARCH_RESULTS:
				break
	_last_search_count = matches.size()
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for i in matches.size():
		var gd: Dictionary = matches[i]
		var b: Button = _hub.call(
			"_make_button", str(gd["n"]), "Search_%d" % i, 20,
			Color(0.16, 0.22, 0.38))
		b.custom_minimum_size = Vector2(280, GRID_BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_search_chosen.bind(str(gd["s"]), str(gd["n"])))
		grid.add_child(b)
	# _sync() (already running) hooks hover/stars onto these buttons and
	# keeps the pager in search mode.


func _on_search_chosen(scene_path: String, game_name: String) -> void:
	_record_recent(game_name)
	_hub.call("_load_game", scene_path, game_name)


# ---------------------------------------------------- favorites/recents ---

func _on_grid_pressed(game_name: String) -> void:
	# The hub's own pressed handler (connected first) launches the game;
	# we just record it as recently played.
	_record_recent(game_name)


func _on_hover(game_name: String) -> void:
	if _desc == null or not is_instance_valid(_desc):
		return
	_desc.text = "%s - %s" % [game_name, _desc_for(game_name)]


func _reset_desc() -> void:
	if _desc != null and is_instance_valid(_desc):
		_desc.text = DEFAULT_HINT


func _desc_for(game_name: String) -> String:
	for g in GAMES:
		var gd: Dictionary = g
		if str(gd["n"]) == game_name:
			return str(gd["d"])
	var tab := int(_hub.get("_tab")) if _hub != null else 0
	return TAB_TAGLINES[clampi(tab, 0, TAB_TAGLINES.size() - 1)]


func _toggle_fav(game_name: String) -> void:
	if game_name in _favorites:
		_favorites.erase(game_name)
	else:
		_favorites.append(game_name)
	_save_settings()


func _launch(game_name: String) -> void:
	_record_recent(game_name)
	var scene := _scene_for(game_name)
	if scene == "":
		push_warning("[HubExtras] no scene for game: " + game_name)
		return
	_hub.call("_load_game", scene, game_name)


func _scene_for(game_name: String) -> String:
	for g in GAMES:
		var gd: Dictionary = g
		if str(gd["n"]) == game_name:
			return str(gd["s"])
	# Fallback: the hub's live lists (covers hub.gd drift).
	if _hub != null and is_instance_valid(_hub):
		var games: Array = _hub.call("_active_games")
		for entry in games:
			var ed: Dictionary = entry
			if str(ed.get("name", "")) == game_name:
				return str(ed.get("scene", ""))
	return ""


func _record_recent(game_name: String) -> void:
	_recents.erase(game_name)
	_recents.push_front(game_name)
	while _recents.size() > MAX_RECENTS:
		_recents.pop_back()
	_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_favorites.clear()
	for x in cfg.get_value("hub_extras", "favorites", []):
		_favorites.append(str(x))
	_recents.clear()
	for x in cfg.get_value("hub_extras", "recents", []):
		_recents.append(str(x))
	_recents = _recents.slice(0, MAX_RECENTS)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep the hub's own sections (e.g. room)
	cfg.set_value("hub_extras", "favorites", _favorites)
	cfg.set_value("hub_extras", "recents", _recents)
	cfg.save(SETTINGS_PATH)
