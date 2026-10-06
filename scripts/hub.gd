## Hub.gd - NEXUS ARCADE game selection hub.
## Shows 50 game portals across paged 5x5 grids; clicking/tapping one loads that game.
extends Node3D
class_name NexusHub

const GAMES := [
	{"name": "Gravity Golf", "scene": "res://scenes/golf/golf.tscn", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Swarm Protocol", "scene": "res://scenes/swarm/swarm.tscn", "color": Color(1.0, 0.3, 0.2)},
	{"name": "Familiar", "scene": "res://scenes/familiar/familiar.tscn", "color": Color(0.4, 0.7, 1.0)},
	{"name": "Starforge", "scene": "res://scenes/starforge/starforge.tscn", "color": Color(0.8, 0.4, 1.0)},
	{"name": "Neon Duel", "scene": "res://scenes/duel/duel.tscn", "color": Color(1.0, 0.9, 0.2)},
	{"name": "Holo Chess", "scene": "res://scenes/holo-chess/holo-chess.tscn", "color": Color(0.9, 0.9, 0.9)},
	{"name": "Portal Painter", "scene": "res://scenes/portal-painter/portal-painter.tscn", "color": Color(1.0, 0.5, 0.0)},
	{"name": "Room Racer", "scene": "res://scenes/room-racer/room-racer.tscn", "color": Color(0.0, 0.8, 1.0)},
	{"name": "AR Defender", "scene": "res://scenes/ar-defender/ar-defender.tscn", "color": Color(1.0, 0.2, 0.5)},
	{"name": "Zero-G Sandbox", "scene": "res://scenes/zero-g-sandbox/zero-g-sandbox.tscn", "color": Color(0.5, 0.0, 1.0)},
	{"name": "Holo Piano", "scene": "res://scenes/holo-piano/holo-piano.tscn", "color": Color(1.0, 1.0, 1.0)},
	{"name": "Star Map", "scene": "res://scenes/star-map/star-map.tscn", "color": Color(0.1, 0.1, 0.8)},
	{"name": "AR Measure", "scene": "res://scenes/ar-measure/ar-measure.tscn", "color": Color(0.0, 1.0, 0.5)},
	{"name": "Holo Notes", "scene": "res://scenes/holo-notes/holo-notes.tscn", "color": Color(1.0, 1.0, 0.0)},
	{"name": "Beat Blades", "scene": "res://scenes/beat-blades/beat-blades.tscn", "color": Color(1.0, 0.0, 1.0)},
	{"name": "Portal Ball", "scene": "res://scenes/portal-ball/portal-ball.tscn", "color": Color(0.0, 1.0, 1.0)},
	{"name": "AR Workout", "scene": "res://scenes/ar-workout/ar-workout.tscn", "color": Color(1.0, 0.3, 0.0)},
	{"name": "Mind Palace", "scene": "res://scenes/mind-palace/mind-palace.tscn", "color": Color(0.6, 0.3, 0.9)},
	{"name": "Holo Pets", "scene": "res://scenes/holo-pets/holo-pets.tscn", "color": Color(1.0, 0.6, 0.8)},
	{"name": "AR DJ", "scene": "res://scenes/ar-dj/ar-dj.tscn", "color": Color(0.8, 0.0, 0.8)},
	{"name": "Laser Tag AR", "scene": "res://scenes/laser-tag-ar/laser-tag-ar.tscn", "color": Color(1.0, 0.1, 0.1)},
	{"name": "Holo Dungeon", "scene": "res://scenes/holo-dungeon/holo-dungeon.tscn", "color": Color(0.4, 0.2, 0.6)},
	{"name": "AR Bowling", "scene": "res://scenes/ar-bowling/ar-bowling.tscn", "color": Color(0.2, 0.6, 1.0)},
	{"name": "Sky Defender", "scene": "res://scenes/sky-defender/sky-defender.tscn", "color": Color(0.9, 0.5, 0.1)},
	{"name": "Holo Aquarium", "scene": "res://scenes/holo-aquarium/holo-aquarium.tscn", "color": Color(0.1, 0.7, 0.9)},
	{"name": "AR Escape Room", "scene": "res://scenes/ar-escape-room/ar-escape-room.tscn", "color": Color(0.7, 0.5, 0.2)},
	{"name": "Gravity Pong", "scene": "res://scenes/gravity-pong/gravity-pong.tscn", "color": Color(0.3, 1.0, 0.6)},
	{"name": "Holo Garden", "scene": "res://scenes/holo-garden/holo-garden.tscn", "color": Color(0.3, 0.9, 0.3)},
	{"name": "AR Karaoke", "scene": "res://scenes/ar-karaoke/ar-karaoke.tscn", "color": Color(1.0, 0.4, 0.7)},
	{"name": "Time Pilot", "scene": "res://scenes/time-pilot/time-pilot.tscn", "color": Color(0.5, 0.8, 1.0)},
	{"name": "Clay Shaper", "scene": "res://scenes/clay-shaper/clay-shaper.tscn", "color": Color(0.8, 0.45, 0.25)},
	{"name": "Portal Maze", "scene": "res://scenes/portal-maze/portal-maze.tscn", "color": Color(0.2, 1.0, 0.8)},
	{"name": "Air Drums", "scene": "res://scenes/air-drums/air-drums.tscn", "color": Color(1.0, 0.35, 0.15)},
	{"name": "Drone Racer", "scene": "res://scenes/drone-racer/drone-racer.tscn", "color": Color(0.3, 0.7, 1.0)},
	{"name": "Tower Topple", "scene": "res://scenes/tower-topple/tower-topple.tscn", "color": Color(0.75, 0.55, 0.3)},
	{"name": "Light Painter", "scene": "res://scenes/light-painter/light-painter.tscn", "color": Color(1.0, 0.3, 0.9)},
	{"name": "Holo Theremin", "scene": "res://scenes/holo-theremin/holo-theremin.tscn", "color": Color(0.55, 0.3, 1.0)},
	{"name": "AR Billiards", "scene": "res://scenes/ar-billiards/ar-billiards.tscn", "color": Color(0.1, 0.6, 0.25)},
	{"name": "Spell Duel", "scene": "res://scenes/spell-duel/spell-duel.tscn", "color": Color(0.7, 0.2, 1.0)},
	{"name": "Sand Shaper", "scene": "res://scenes/sand-shaper/sand-shaper.tscn", "color": Color(0.9, 0.75, 0.45)},
	{"name": "Rhythm Boxer", "scene": "res://scenes/rhythm-boxer/rhythm-boxer.tscn", "color": Color(1.0, 0.2, 0.2)},
	{"name": "AR Graffiti", "scene": "res://scenes/graffiti-wall/graffiti-wall.tscn", "color": Color(0.5, 1.0, 0.2)},
	{"name": "Marble Run", "scene": "res://scenes/marble-run/marble-run.tscn", "color": Color(0.25, 0.5, 1.0)},
	{"name": "AR Darts", "scene": "res://scenes/ar-darts/ar-darts.tscn", "color": Color(1.0, 0.75, 0.15)},
	{"name": "Zero-G Hoops", "scene": "res://scenes/zero-g-hoops/zero-g-hoops.tscn", "color": Color(1.0, 0.55, 0.1)},
	{"name": "Shadow Puppets", "scene": "res://scenes/shadow-puppet/shadow-puppet.tscn", "color": Color(1.0, 0.65, 0.3)},
	{"name": "AR Fishing", "scene": "res://scenes/ar-fishing/ar-fishing.tscn", "color": Color(0.15, 0.8, 0.75)},
	{"name": "Laser Mirrors", "scene": "res://scenes/mirror-maze/mirror-maze.tscn", "color": Color(1.0, 0.15, 0.25)},
	{"name": "Gravity Glove", "scene": "res://scenes/gravity-glove/gravity-glove.tscn", "color": Color(0.3, 1.0, 0.9)},
	{"name": "Time Freeze", "scene": "res://scenes/time-freeze/time-freeze.tscn", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Sky Traffic", "scene": "res://scenes/sky_traffic/sky_traffic.tscn", "color": Color(0.4, 0.8, 1.0)},
]

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

const GAMES_PER_PAGE := 25
const GRID_COLS := 5

var _current_game: Node = null
var _game_buttons: Array[Node3D] = []
var _nav_buttons: Array[Node3D] = []
var _page_label: Label3D = null
var _page := 0
var _tab := 0  # 0 = ARCADE (GAMES), 1 = HALLOWEEN (HW_GAMES)
var _tab_buttons: Array[Node3D] = []
var _costumes_button: Node3D = null
var _updater: UpdateChecker
var _version_label: Label3D
var _update_status: Label3D

func _ready() -> void:
	_build_hub()
	_setup_updater()

func _build_hub() -> void:
	# Title.
	var title := Label3D.new()
	title.text = "NEXUS ARCADE"
	title.font_size = 128
	title.pixel_size = 0.005
	title.modulate = Color(0, 0.94, 1)
	title.outline_size = 16
	title.position = Vector3(0, 2.2, -1.5)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(title)

	# ARCADE / HALLOWEEN tabs.
	var arcade_tab := _make_tab_button("ARCADE", 0)
	arcade_tab.position = Vector3(-0.75, 2.72, -1.5)
	add_child(arcade_tab)
	_tab_buttons.append(arcade_tab)
	var hw_tab := _make_tab_button("HALLOWEEN", 1)
	hw_tab.position = Vector3(0.75, 2.72, -1.5)
	add_child(hw_tab)
	_tab_buttons.append(hw_tab)

	# Game selection buttons in a 5x5 paged grid (25 per page).
	_build_page()

	# Instructions.
	var hint := Label3D.new()
	hint.text = "Point and click / tap to select a game"
	hint.font_size = 48
	hint.pixel_size = 0.003
	hint.modulate = Color(0.8, 0.8, 0.8)
	hint.position = Vector3(0, -1.0, -1.5)
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(hint)

	# Version label.
	_version_label = Label3D.new()
	_version_label.text = "v" + ProjectSettings.get_setting("application/config/version", "0.1.0")
	_version_label.font_size = 36
	_version_label.pixel_size = 0.0025
	_version_label.modulate = Color(0.6, 0.6, 0.6)
	_version_label.position = Vector3(0, -1.25, -1.5)
	_version_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_version_label)

	# Update status label.
	_update_status = Label3D.new()
	_update_status.text = ""
	_update_status.font_size = 36
	_update_status.pixel_size = 0.0025
	_update_status.modulate = Color(1.0, 0.9, 0.3)
	_update_status.position = Vector3(0, -1.5, -1.5)
	_update_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_update_status)

	# Check for Updates button.
	var update_btn := _make_update_button()
	update_btn.position = Vector3(0, -1.85, -1.5)
	add_child(update_btn)

	# Costumes button (Halloween avatar picker).
	_costumes_button = _make_costumes_button()
	_costumes_button.position = Vector3(1.4, -1.85, -1.5)
	add_child(_costumes_button)

func _active_games() -> Array:
	return HW_GAMES if _tab == 1 else GAMES

func _page_count() -> int:
	return int(ceil(_active_games().size() / float(GAMES_PER_PAGE)))

func _build_page() -> void:
	# Clear the previous page.
	for b in _game_buttons:
		if is_instance_valid(b):
			b.queue_free()
	for b in _nav_buttons:
		if is_instance_valid(b):
			b.queue_free()
	if is_instance_valid(_page_label):
		_page_label.queue_free()
	_game_buttons.clear()
	_nav_buttons.clear()

	var start := _page * GAMES_PER_PAGE
	var end := mini(start + GAMES_PER_PAGE, _active_games().size())
	for i in range(start, end):
		var game = _active_games()[i]
		var local := i - start
		var row := local / GRID_COLS
		var col := local % GRID_COLS
		var pos := Vector3((col - 2) * 0.85, 2.0 - row * 0.5, -1.5)
		var btn := _make_button(game["name"], game["color"], game["scene"])
		btn.position = pos
		add_child(btn)
		_game_buttons.append(btn)

	# Page indicator.
	_page_label = Label3D.new()
	_page_label.text = "Page %d / %d" % [_page + 1, _page_count()]
	_page_label.font_size = 40
	_page_label.pixel_size = 0.0028
	_page_label.modulate = Color(0.7, 0.85, 1.0)
	_page_label.position = Vector3(0, -0.72, -1.5)
	_page_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_page_label)

	# Prev / Next buttons.
	if _page > 0:
		var prev := _make_nav_button("< Prev", -1)
		prev.position = Vector3(-1.6, -0.72, -1.5)
		add_child(prev)
		_nav_buttons.append(prev)
	if _page < _page_count() - 1:
		var nxt := _make_nav_button("Next >", 1)
		nxt.position = Vector3(1.6, -0.72, -1.5)
		add_child(nxt)
		_nav_buttons.append(nxt)

	_refresh_tabs()

func _make_nav_button(label_text: String, direction: int) -> Node3D:
	var root := Node3D.new()
	root.set_meta("nav_direction", direction)

	var box := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.7, 0.2, 0.05)
	box.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.3, 0.5)
	bmat.emission_enabled = true
	bmat.emission = Color(0.3, 0.5, 0.9)
	bmat.emission_energy_multiplier = 1.0
	box.material_override = bmat
	root.add_child(box)

	var label := Label3D.new()
	label.text = label_text
	label.font_size = 40
	label.pixel_size = 0.002
	label.modulate = Color.WHITE
	label.position = Vector3(0, 0, 0.04)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_nav_input.bind(root))
	return root

func _on_nav_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, nav_root: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var dir: int = nav_root.get_meta("nav_direction")
		_page = clampi(_page + dir, 0, _page_count() - 1)
		_build_page()

func _make_tab_button(label_text: String, tab_index: int) -> Node3D:
	var root := Node3D.new()
	root.set_meta("tab_index", tab_index)

	var box := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.15, 0.24, 0.05)
	box.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 0.12, 0.45)
	bmat.emission_enabled = true
	bmat.emission = Color(0.45, 0.18, 0.7)
	bmat.emission_energy_multiplier = 0.8
	box.material_override = bmat
	root.add_child(box)
	root.set_meta("tab_mat", bmat)

	var label := Label3D.new()
	label.text = label_text
	label.font_size = 40
	label.pixel_size = 0.002
	label.modulate = Color.WHITE
	label.position = Vector3(0, 0, 0.04)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_tab_input.bind(root))
	return root

func _on_tab_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, tab_root: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_tab = int(tab_root.get_meta("tab_index"))
		_page = 0
		_build_page()

func _refresh_tabs() -> void:
	for tb in _tab_buttons:
		if not is_instance_valid(tb):
			continue
		var mat: StandardMaterial3D = tb.get_meta("tab_mat")
		var active: bool = int(tb.get_meta("tab_index")) == _tab
		mat.emission_energy_multiplier = 2.2 if active else 0.8

func _make_costumes_button() -> Node3D:
	var root := Node3D.new()

	var box := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.0, 0.22, 0.05)
	box.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.5, 0.2, 0.6)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.45, 0.1)
	bmat.emission_energy_multiplier = 1.4
	box.material_override = bmat
	root.add_child(box)

	var label := Label3D.new()
	label.text = "Costumes"
	label.font_size = 42
	label.pixel_size = 0.002
	label.modulate = Color.WHITE
	label.position = Vector3(0, 0, 0.04)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var bsphere := SphereShape3D.new()
	bsphere.radius = 0.4
	shape.shape = bsphere
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_costumes_input.bind(root))
	return root

func _on_costumes_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, _btn: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_load_game("res://scenes/halloween/costume_picker.tscn", "Costume Picker")

func _make_button(game_name: String, color: Color, scene_path: String) -> Node3D:
	var root := Node3D.new()
	root.set_meta("scene_path", scene_path)
	root.set_meta("game_name", game_name)

	# Portal ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = color
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.emission_energy_multiplier = 2.0
	ring.material_override = rmat
	root.add_child(ring)

	# Label.
	var label := Label3D.new()
	label.text = game_name
	label.font_size = 48
	label.pixel_size = 0.0025
	label.modulate = Color.WHITE
	label.outline_size = 8
	label.position = Vector3(0, -0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	# Click detection via Area3D.
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_button_input.bind(root))

	# Rotate slowly.
	var tw := create_tween().set_loops()
	tw.tween_property(ring, "rotation:z", TAU, 4.0)

	return root

func _on_button_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, button_root: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_load_game(button_root.get_meta("scene_path"), button_root.get_meta("game_name"))

func _load_game(scene_path: String, game_name: String) -> void:
	# Clear current game.
	if _current_game and is_instance_valid(_current_game):
		_current_game.queue_free()
	# Hide hub.
	for b in _game_buttons:
		b.visible = false
	for b in _nav_buttons:
		b.visible = false
	for b in _tab_buttons:
		b.visible = false
	if is_instance_valid(_costumes_button):
		_costumes_button.visible = false
	if is_instance_valid(_page_label):
		_page_label.visible = false
	# Load the game.
	var scene: PackedScene = load(scene_path)
	if scene:
		_current_game = scene.instantiate()
		_current_game.position = Vector3(0, 0, -0.5)
		add_child(_current_game)
		print("[Hub] Loaded: ", game_name)
	else:
		push_error("[Hub] Failed to load: " + scene_path)

func _input(event: InputEvent) -> void:
	# Press H or Back button to return to hub.
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_return_to_hub()

func _return_to_hub() -> void:
	if _current_game and is_instance_valid(_current_game):
		_current_game.queue_free()
		_current_game = null
	for b in _game_buttons:
		b.visible = true
	for b in _nav_buttons:
		b.visible = true
	for b in _tab_buttons:
		b.visible = true
	if is_instance_valid(_costumes_button):
		_costumes_button.visible = true
	if is_instance_valid(_page_label):
		_page_label.visible = true

# --- Update system ---

func _setup_updater() -> void:
	_updater = UpdateChecker.new()
	add_child(_updater)
	_updater.check_completed.connect(_on_update_check_completed)
	_updater.download_completed.connect(_on_update_downloaded)
	_updater.download_failed.connect(_on_update_failed)

func _make_update_button() -> Node3D:
	var root := Node3D.new()
	root.set_meta("is_update_button", true)

	# Button box.
	var box := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.9, 0.22, 0.05)
	box.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.15, 0.35, 0.6)
	bmat.emission_enabled = true
	bmat.emission = Color(0.2, 0.5, 0.9)
	bmat.emission_energy_multiplier = 1.2
	box.material_override = bmat
	root.add_child(box)

	var label := Label3D.new()
	label.text = "Check for Updates"
	label.font_size = 42
	label.pixel_size = 0.002
	label.modulate = Color.WHITE
	label.position = Vector3(0, 0, 0.04)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var bsphere := SphereShape3D.new()
	bsphere.radius = 0.35
	shape.shape = bsphere
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_update_button_input.bind(root))

	return root

func _on_update_button_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, _btn: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# If we have a downloaded APK pending install, tapping installs it.
		var pending: String = _update_status.get_meta("apk_path", "")
		if pending != "":
			_update_status.text = "Installing update..."
			if _updater.install_update(pending):
				_update_status.text = "Installing... check system prompt."
			else:
				_update_status.text = "Install needs Android. APK at: " + pending
			return
		_update_status.text = "Checking for updates..."
		_updater.check_for_updates()

func _on_update_check_completed(has_update: bool, latest_version: String, changelog: String) -> void:
	if has_update:
		_update_status.text = "v%s available! Downloading..." % latest_version
		_show_changelog(latest_version, changelog)
		_updater.download_update()
	else:
		if latest_version == "":
			_update_status.text = "Check failed. Try again."
		else:
			_update_status.text = "You're up to date (v%s)" % _updater.current_version

func _show_changelog(version: String, changelog: String) -> void:
	var panel := Label3D.new()
	panel.name = "ChangelogPanel"
	panel.text = "What's new in v%s:\n%s" % [version, changelog]
	panel.font_size = 36
	panel.pixel_size = 0.0022
	panel.modulate = Color(0.9, 0.95, 1.0)
	panel.outline_size = 6
	panel.position = Vector3(0, 1.7, -2.2)
	panel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	panel.set_meta("is_changelog", true)
	add_child(panel)
	# Auto-hide after 12 seconds.
	get_tree().create_timer(12.0).timeout.connect(
		func(): if is_instance_valid(panel): panel.queue_free()
	)

func _on_update_downloaded(apk_path: String) -> void:
	_update_status.text = "Download complete! Tap to install."
	# Change button to install.
	_update_status.set_meta("apk_path", apk_path)

func _on_update_failed(error: String) -> void:
	_update_status.text = "Update failed: %s" % error
