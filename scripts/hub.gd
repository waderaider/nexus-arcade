## Hub.gd - NEXUS ARCADE game selection hub.
## Category screens: GAMES / UTILITIES / CREATE / THEMES, each paged (25 per page).
##
## v0.7.0: the launcher is a 2D Control panel rendered into a SubViewport and
## shown on a 3D quad in front of the user. Input comes from XR laser pointers
## (see scripts/shared/xr_ui_pointer.gd): controller trigger clicks and hand
## pinches are raycast against the quad and injected into the SubViewport, so
## real 2D Buttons work on Quest 3. Desktop mouse is forwarded the same way
## when no XR tracker is live.
extends Node3D
class_name NexusHub

const CAT_GAMES := [
	{"name": "Gravity Golf", "scene": "res://scenes/golf/golf.tscn", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Swarm Protocol", "scene": "res://scenes/swarm/swarm.tscn", "color": Color(1.0, 0.3, 0.2)},
	{"name": "Neon Duel", "scene": "res://scenes/duel/duel.tscn", "color": Color(1.0, 0.9, 0.2)},
	{"name": "Beat Blades", "scene": "res://scenes/beat-blades/beat-blades.tscn", "color": Color(1.0, 0.0, 1.0)},
	{"name": "Portal Ball", "scene": "res://scenes/portal-ball/portal-ball.tscn", "color": Color(0.0, 1.0, 1.0)},
	{"name": "Laser Tag AR", "scene": "res://scenes/laser-tag-ar/laser-tag-ar.tscn", "color": Color(1.0, 0.1, 0.1)},
	{"name": "Gravity Pong", "scene": "res://scenes/gravity-pong/gravity-pong.tscn", "color": Color(0.3, 1.0, 0.6)},
	{"name": "AR Bowling", "scene": "res://scenes/ar-bowling/ar-bowling.tscn", "color": Color(0.2, 0.6, 1.0)},
	{"name": "Time Pilot", "scene": "res://scenes/time-pilot/time-pilot.tscn", "color": Color(0.5, 0.8, 1.0)},
	{"name": "Room Racer", "scene": "res://scenes/room-racer/room-racer.tscn", "color": Color(0.0, 0.8, 1.0)},
	{"name": "AR Defender", "scene": "res://scenes/ar-defender/ar-defender.tscn", "color": Color(1.0, 0.2, 0.5)},
	{"name": "Sky Defender", "scene": "res://scenes/sky-defender/sky-defender.tscn", "color": Color(0.9, 0.5, 0.1)},
	{"name": "Drone Racer", "scene": "res://scenes/drone-racer/drone-racer.tscn", "color": Color(0.3, 0.7, 1.0)},
	{"name": "Tower Topple", "scene": "res://scenes/tower-topple/tower-topple.tscn", "color": Color(0.75, 0.55, 0.3)},
	{"name": "Spell Duel", "scene": "res://scenes/spell-duel/spell-duel.tscn", "color": Color(0.7, 0.2, 1.0)},
	{"name": "Rhythm Boxer", "scene": "res://scenes/rhythm-boxer/rhythm-boxer.tscn", "color": Color(1.0, 0.2, 0.2)},
	{"name": "Marble Run", "scene": "res://scenes/marble-run/marble-run.tscn", "color": Color(0.25, 0.5, 1.0)},
	{"name": "AR Darts", "scene": "res://scenes/ar-darts/ar-darts.tscn", "color": Color(1.0, 0.75, 0.15)},
	{"name": "Zero-G Hoops", "scene": "res://scenes/zero-g-hoops/zero-g-hoops.tscn", "color": Color(1.0, 0.55, 0.1)},
	{"name": "AR Fishing", "scene": "res://scenes/ar-fishing/ar-fishing.tscn", "color": Color(0.15, 0.8, 0.75)},
	{"name": "Laser Mirrors", "scene": "res://scenes/mirror-maze/mirror-maze.tscn", "color": Color(1.0, 0.15, 0.25)},
	{"name": "Gravity Glove", "scene": "res://scenes/gravity-glove/gravity-glove.tscn", "color": Color(0.3, 1.0, 0.9)},
	{"name": "Time Freeze", "scene": "res://scenes/time-freeze/time-freeze.tscn", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Portal Maze", "scene": "res://scenes/portal-maze/portal-maze.tscn", "color": Color(0.2, 1.0, 0.8)},
	{"name": "Air Drums", "scene": "res://scenes/air-drums/air-drums.tscn", "color": Color(1.0, 0.35, 0.15)},
	{"name": "Shadow Puppets", "scene": "res://scenes/shadow-puppet/shadow-puppet.tscn", "color": Color(1.0, 0.65, 0.3)},
	{"name": "Holo Chess", "scene": "res://scenes/holo-chess/holo-chess.tscn", "color": Color(0.9, 0.9, 0.9)},
	{"name": "Starforge", "scene": "res://scenes/starforge/starforge.tscn", "color": Color(0.8, 0.4, 1.0)},
	{"name": "Holo Dungeon", "scene": "res://scenes/holo-dungeon/holo-dungeon.tscn", "color": Color(0.4, 0.2, 0.6)},
	{"name": "AR Escape Room", "scene": "res://scenes/ar-escape-room/ar-escape-room.tscn", "color": Color(0.7, 0.5, 0.2)},
	{"name": "AR Billiards", "scene": "res://scenes/ar-billiards/ar-billiards.tscn", "color": Color(0.1, 0.6, 0.25)},
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
	{"name": "QR Treasure Hunt", "scene": "res://scenes/qr_hunt/qr_hunt.tscn", "color": Color(1.0, 0.85, 0.2)},
]

const CAT_UTILITIES := [
	{"name": "AR Measure", "scene": "res://scenes/ar-measure/ar-measure.tscn", "color": Color(0.0, 1.0, 0.5)},
	{"name": "Holo Notes", "scene": "res://scenes/holo-notes/holo-notes.tscn", "color": Color(1.0, 1.0, 0.0)},
	{"name": "Star Map", "scene": "res://scenes/star-map/star-map.tscn", "color": Color(0.1, 0.1, 0.8)},
	{"name": "Sky Traffic", "scene": "res://scenes/sky_traffic/sky_traffic.tscn", "color": Color(0.4, 0.8, 1.0)},
	{"name": "Eye Spy AR", "scene": "res://scenes/eye_spy/eye_spy.tscn", "color": Color(0.2, 0.9, 1.0)},
	{"name": "Plant Doctor", "scene": "res://scenes/plant_doctor/plant_doctor.tscn", "color": Color(0.3, 1.0, 0.5)},
	{"name": "AR Workout", "scene": "res://scenes/ar-workout/ar-workout.tscn", "color": Color(1.0, 0.3, 0.0)},
	{"name": "Holo Pets", "scene": "res://scenes/holo-pets/holo-pets.tscn", "color": Color(1.0, 0.6, 0.8)},
	{"name": "Mind Palace", "scene": "res://scenes/mind-palace/mind-palace.tscn", "color": Color(0.6, 0.3, 0.9)},
	{"name": "AR DJ", "scene": "res://scenes/ar-dj/ar-dj.tscn", "color": Color(0.8, 0.0, 0.8)},
	{"name": "Familiar", "scene": "res://scenes/familiar/familiar.tscn", "color": Color(0.4, 0.7, 1.0)},
	{"name": "Couch Morph", "scene": "res://scenes/couch_morph/couch_morph.tscn", "color": Color(0.9, 0.4, 1.0)},
]

const CAT_CREATE := [
	{"name": "Portal Painter", "scene": "res://scenes/portal-painter/portal-painter.tscn", "color": Color(1.0, 0.5, 0.0)},
	{"name": "Light Painter", "scene": "res://scenes/light-painter/light-painter.tscn", "color": Color(1.0, 0.3, 0.9)},
	{"name": "Holo Piano", "scene": "res://scenes/holo-piano/holo-piano.tscn", "color": Color(1.0, 1.0, 1.0)},
	{"name": "Holo Theremin", "scene": "res://scenes/holo-theremin/holo-theremin.tscn", "color": Color(0.55, 0.3, 1.0)},
	{"name": "AR Graffiti", "scene": "res://scenes/graffiti-wall/graffiti-wall.tscn", "color": Color(0.5, 1.0, 0.2)},
	{"name": "AR Karaoke", "scene": "res://scenes/ar-karaoke/ar-karaoke.tscn", "color": Color(1.0, 0.4, 0.7)},
	{"name": "Sand Shaper", "scene": "res://scenes/sand-shaper/sand-shaper.tscn", "color": Color(0.9, 0.75, 0.45)},
	{"name": "Clay Shaper", "scene": "res://scenes/clay-shaper/clay-shaper.tscn", "color": Color(0.8, 0.45, 0.25)},
	{"name": "Sketch to 3D", "scene": "res://scenes/sketch_3d/sketch_3d.tscn", "color": Color(1.0, 0.5, 1.0)},
	{"name": "Holo Garden", "scene": "res://scenes/holo-garden/holo-garden.tscn", "color": Color(0.3, 0.9, 0.3)},
	{"name": "Zero-G Sandbox", "scene": "res://scenes/zero-g-sandbox/zero-g-sandbox.tscn", "color": Color(0.5, 0.0, 1.0)},
	{"name": "Holo Aquarium", "scene": "res://scenes/holo-aquarium/holo-aquarium.tscn", "color": Color(0.1, 0.7, 0.9)},
]

const CAT_THEMES := [
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
const VP_SIZE := Vector2(1600, 1000)
const QUAD_SIZE := Vector2(2.4, 1.5)
const QUAD_POS := Vector3(0, 1.6, -2.0)
const SETTINGS_PATH := "user://nexus_settings.cfg"
const ROOM_KIT_PATH := "res://scripts/shared/room_kit.gd"
const COSTUME_SCENE := "res://scenes/halloween/costume_picker.tscn"
const TAB_NAMES := ["GAMES", "UTILITIES", "CREATE", "THEMES"]

var _current_game: Node = null
var _page := 0
var _tab := 0  # 0 = GAMES, 1 = UTILITIES, 2 = CREATE, 3 = THEMES

var _panel_root: Node3D = null
var _viewport: SubViewport = null
var _quad: MeshInstance3D = null
var _grid: GridContainer = null
var _game_buttons: Array[Button] = []
var _tab_buttons: Array[Button] = []
var _nav_prev: Button = null
var _nav_next: Button = null
var _page_label: Label = null
var _costumes_button: Button = null
var _updater: UpdateChecker = null
var _version_label: Label = null
var _update_status: Label = null
var _changelog_overlay: Control = null
var _changelog_title: Label = null
var _changelog_text: Label = null
var _changelog_timer: Timer = null
var _crash_dialog: Control = null
var _crash_message: Label = null
var _room_dialog: Control = null
var _room_title: Label = null
var _room_body: Label = null
var _room_buttons: HBoxContainer = null
var _roomkit_cache: GDScript = null

var _pointers: Array[XRUIPointer] = []
var _controllers: Array[XRController3D] = []
var _xr_origin: Node3D = null
var _menu_prev := {}


func _ready() -> void:
	_build_panel()
	_build_ui()
	_build_pointers()
	_setup_updater()
	# Crash reporter: offer to send the previous session's log.
	var crash: Dictionary = BugReporter.prompt_if_crash_pending()
	if not crash.is_empty():
		_show_crash_prompt(crash)
	BugReporter.session_start("hub")
	# Roomscale-first: walk through room capture on first run.
	if not _room_setup_done():
		_show_room_flow()


func _process(_delta: float) -> void:
	var xr := get_viewport().use_xr
	for p in _pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
	if not xr:
		return
	# Menu button on either controller returns to the hub from a game.
	for ctl in _controllers:
		if ctl == null or not is_instance_valid(ctl):
			continue
		var pressed := false
		if ctl.get_tracker() != null:
			pressed = ctl.is_button_pressed("menu_button")
		var was: bool = _menu_prev.get(ctl.get_instance_id(), false)
		if pressed and not was and _current_game != null:
			_return_to_hub()
		_menu_prev[ctl.get_instance_id()] = pressed


func _input(event: InputEvent) -> void:
	# Press H (desktop) or the controller menu button to return to hub.
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_H:
			_return_to_hub()
		return
	if _panel_root == null or not _panel_root.visible:
		return
	# Desktop fallback: forward the real mouse into the panel viewport, but
	# only while no XR pointer is live (avoids double input on device).
	if _xr_pointer_live():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_forward_desktop_mouse(mb)
	elif event is InputEventMouseMotion:
		_forward_desktop_mouse(event as InputEventMouseMotion)


# ---------------------------------------------------------------- panel ---

func _build_panel() -> void:
	_panel_root = Node3D.new()
	_panel_root.name = "PanelRoot"
	add_child(_panel_root)

	_viewport = SubViewport.new()
	_viewport.name = "LauncherViewport"
	_viewport.size = Vector2i(int(VP_SIZE.x), int(VP_SIZE.y))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	_panel_root.add_child(_viewport)

	var qm := QuadMesh.new()
	qm.size = QUAD_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var vpt := ViewportTexture.new()
	vpt.viewport_path = _viewport.get_path()
	mat.albedo_texture = vpt
	_quad = MeshInstance3D.new()
	_quad.name = "PanelQuad"
	_quad.mesh = qm
	_quad.material_override = mat
	_quad.position = QUAD_POS
	_panel_root.add_child(_quad)


# ------------------------------------------------------------------ UI ---

func _build_ui() -> void:
	var root := Control.new()
	root.name = "UI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.08, 0.93)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "NEXUS ARCADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0, 0.94, 1))
	vbox.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.name = "TabRow"
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 16)
	vbox.add_child(tab_row)
	var tab_group := ButtonGroup.new()
	for i in range(TAB_NAMES.size()):
		var tb := _make_button(TAB_NAMES[i], "Tab_%d" % i, 30, Color(0.3, 0.12, 0.45))
		tb.toggle_mode = true
		tb.button_group = tab_group
		tb.pressed.connect(_on_tab_pressed.bind(i))
		tab_row.add_child(tb)
		_tab_buttons.append(tb)

	_grid = GridContainer.new()
	_grid.name = "GameGrid"
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_grid)

	var pager := HBoxContainer.new()
	pager.name = "PagerRow"
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 24)
	vbox.add_child(pager)
	_nav_prev = _make_button("< Prev", "NavPrev", 26)
	_nav_prev.pressed.connect(_on_nav.bind(-1))
	pager.add_child(_nav_prev)
	_page_label = Label.new()
	_page_label.name = "PageLabel"
	_page_label.add_theme_font_size_override("font_size", 26)
	_page_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	pager.add_child(_page_label)
	_nav_next = _make_button("Next >", "NavNext", 26)
	_nav_next.pressed.connect(_on_nav.bind(1))
	pager.add_child(_nav_next)

	var footer := HBoxContainer.new()
	footer.name = "FooterRow"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	vbox.add_child(footer)
	var update_btn := _make_button("Check for Updates", "UpdateButton", 24, Color(0.15, 0.35, 0.6))
	update_btn.pressed.connect(_on_update_button)
	footer.add_child(update_btn)
	var room_btn := _make_button("Room setup", "RoomButton", 24, Color(0.2, 0.35, 0.25))
	room_btn.pressed.connect(_show_room_flow)
	footer.add_child(room_btn)
	_costumes_button = _make_button("Costumes", "CostumesButton", 24, Color(0.5, 0.2, 0.6))
	_costumes_button.pressed.connect(_on_costumes_pressed)
	footer.add_child(_costumes_button)
	_update_status = Label.new()
	_update_status.name = "UpdateStatus"
	_update_status.add_theme_font_size_override("font_size", 22)
	_update_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	footer.add_child(_update_status)
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	_version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_version_label.add_theme_font_size_override("font_size", 22)
	_version_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	footer.add_child(_version_label)

	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "Point the laser and pull the trigger (or pinch) to select"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(hint)

	_build_page()
	_build_changelog_overlay(root)
	_build_crash_dialog(root)
	_build_room_dialog(root)


func _make_button(text: String, node_name: String, font_size: int, bg: Color = Color(0.16, 0.22, 0.38)) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.25)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.lightened(0.45)
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = bg.darkened(0.4)
	b.add_theme_stylebox_override("disabled", disabled)
	return b


func _active_games() -> Array:
	match _tab:
		1:
			return CAT_UTILITIES
		2:
			return CAT_CREATE
		3:
			return CAT_THEMES
	return CAT_GAMES


func _page_count() -> int:
	return int(ceil(_active_games().size() / float(GAMES_PER_PAGE)))


func _build_page() -> void:
	for b in _game_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_game_buttons.clear()
	var games := _active_games()
	var start := _page * GAMES_PER_PAGE
	var end := mini(start + GAMES_PER_PAGE, games.size())
	for i in range(start, end):
		var game: Dictionary = games[i]
		var b := _make_button(
			str(game["name"]), "Game_%d" % (i - start), 20,
			(game["color"] as Color).darkened(0.55))
		b.custom_minimum_size = Vector2(280, 100)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_load_game.bind(str(game["scene"]), str(game["name"])))
		_grid.add_child(b)
		_game_buttons.append(b)
	var pages := _page_count()
	_page_label.text = "Page %d / %d" % [_page + 1, maxi(pages, 1)]
	_nav_prev.visible = _page > 0
	_nav_next.visible = _page < pages - 1
	_refresh_tabs()
	# Costumes button belongs to the THEMES (Halloween) section.
	if is_instance_valid(_costumes_button):
		_costumes_button.visible = _tab == 3


func _on_tab_pressed(tab_index: int) -> void:
	_tab = tab_index
	_page = 0
	_build_page()


func _on_nav(direction: int) -> void:
	_page = clampi(_page + direction, 0, _page_count() - 1)
	_build_page()


func _refresh_tabs() -> void:
	for i in range(_tab_buttons.size()):
		if is_instance_valid(_tab_buttons[i]):
			_tab_buttons[i].button_pressed = (i == _tab)


func _on_costumes_pressed() -> void:
	_load_game(COSTUME_SCENE, "Costume Picker")


# -------------------------------------------------------------- input ---

func _build_pointers() -> void:
	_xr_origin = get_parent().get_node_or_null("XROrigin3D") as Node3D
	if _xr_origin != null:
		for side in ["LeftController", "RightController"]:
			var ctl := _xr_origin.get_node_or_null(side) as XRController3D
			if ctl != null:
				_controllers.append(ctl)
				var p := XRUIPointer.new()
				p.name = "Pointer" + side
				p.controller = ctl
				p.setup(_viewport, _quad, _xr_origin)
				p.xr_clicked.connect(_on_pointer_clicked)
				p.xr_moved.connect(_on_pointer_moved)
				_panel_root.add_child(p)
				_pointers.append(p)
	# Hand pointers: XRUIPointer discovers its XRHandTracker lazily, so hands
	# that appear later (tracking starts/stops) are picked up automatically.
	# Controllers and hands are independent; neither suppresses the other.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.name = "PointerHand%d" % side
		hp.hand_side = side
		hp.setup(_viewport, _quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked)
		hp.xr_moved.connect(_on_pointer_moved)
		_panel_root.add_child(hp)
		_pointers.append(hp)


func _on_pointer_moved(viewport_pos: Vector2) -> void:
	inject_motion(viewport_pos)


func _on_pointer_clicked(viewport_pos: Vector2) -> void:
	inject_click(viewport_pos)


func inject_motion(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = viewport_pos
	_viewport.push_input(ev)


func inject_click(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = viewport_pos
	_viewport.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = viewport_pos
	_viewport.push_input(release)


func _xr_pointer_live() -> bool:
	# Matches main.gd: use_xr is only true after OpenXR initialized OK.
	if not get_viewport().use_xr:
		return false
	for p in _pointers:
		if is_instance_valid(p) and p.is_source_live():
			return true
	return false


func _forward_desktop_mouse(event: InputEventMouse) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _quad == null:
		return
	var hit := XRUIPointer.ray_to_viewport(
		cam.project_ray_origin(event.position),
		cam.project_ray_normal(event.position),
		_quad, VP_SIZE)
	if not bool(hit["hit"]):
		return
	var ev2 := event.duplicate() as InputEventMouse
	ev2.position = hit["pos"]
	_viewport.push_input(ev2)


# --------------------------------------------------------- game load ---

func _load_game(scene_path: String, game_name: String) -> void:
	BugReporter.session_start(game_name)
	if _current_game != null and is_instance_valid(_current_game):
		_current_game.queue_free()
		_current_game = null
	# Hide the whole panel (UI + lasers) while a game runs.
	if is_instance_valid(_panel_root):
		_panel_root.visible = false
	_crash_dialog.visible = false
	_room_dialog.visible = false
	var scene: PackedScene = load(scene_path)
	if scene != null:
		_current_game = scene.instantiate()
		_current_game.position = Vector3(0, 0, -0.5)
		add_child(_current_game)
		print("[Hub] Loaded: ", game_name)
	else:
		push_error("[Hub] Failed to load: " + scene_path)
		if is_instance_valid(_panel_root):
			_panel_root.visible = true


func _return_to_hub() -> void:
	BugReporter.session_end()
	if _current_game != null and is_instance_valid(_current_game):
		_current_game.queue_free()
	_current_game = null
	if is_instance_valid(_panel_root):
		_panel_root.visible = true


# ------------------------------------------------------- crash prompt ---

func _build_crash_dialog(root: Control) -> void:
	_crash_dialog = Control.new()
	_crash_dialog.name = "CrashDialog"
	_crash_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crash_dialog.visible = false
	root.add_child(_crash_dialog)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crash_dialog.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	_crash_message = Label.new()
	_crash_message.add_theme_font_size_override("font_size", 30)
	_crash_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_crash_message)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)
	var send_btn := _make_button("Send log", "CrashSend", 26, Color(0.5, 0.25, 0.1))
	send_btn.pressed.connect(_on_crash_send)
	row.add_child(send_btn)
	var keep_btn := _make_button("Keep local", "CrashKeep", 26, Color(0.25, 0.25, 0.3))
	keep_btn.pressed.connect(_on_crash_keep)
	row.add_child(keep_btn)


func _show_crash_prompt(crash: Dictionary) -> void:
	_crash_message.text = "Looks like %s crashed last time.\nSend the log to Brio?" \
		% str(crash.get("game", "a game"))
	_crash_dialog.visible = true


func _on_crash_send() -> void:
	BugReporter.send_report()
	_crash_dialog.visible = false


func _on_crash_keep() -> void:
	BugReporter.acknowledge_crash()
	_crash_dialog.visible = false


# ------------------------------------------------------------ updater ---

func _setup_updater() -> void:
	_updater = UpdateChecker.new()
	add_child(_updater)
	_updater.check_completed.connect(_on_update_check_completed)
	_updater.download_completed.connect(_on_update_downloaded)
	_updater.download_failed.connect(_on_update_failed)


func _on_update_button() -> void:
	# If we have a downloaded APK pending install, tapping installs it.
	var pending: String = str(_update_status.get_meta("apk_path", ""))
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
	elif latest_version == "":
		_update_status.text = "Check failed. Try again."
	else:
		_update_status.text = "You're up to date (v%s)" % _updater.current_version


func _build_changelog_overlay(root: Control) -> void:
	_changelog_overlay = Control.new()
	_changelog_overlay.name = "ChangelogOverlay"
	_changelog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_changelog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_changelog_overlay.visible = false
	root.add_child(_changelog_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_changelog_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ChangelogPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(1000, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	_changelog_title = Label.new()
	_changelog_title.add_theme_font_size_override("font_size", 32)
	_changelog_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_changelog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_changelog_title)
	_changelog_text = Label.new()
	_changelog_text.add_theme_font_size_override("font_size", 24)
	_changelog_text.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_changelog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_changelog_text)
	_changelog_timer = Timer.new()
	_changelog_timer.wait_time = 12.0
	_changelog_timer.one_shot = true
	_changelog_timer.timeout.connect(_on_changelog_timeout)
	root.add_child(_changelog_timer)


func _show_changelog(version: String, changelog: String) -> void:
	_changelog_title.text = "What's new in v%s:" % version
	_changelog_text.text = changelog
	_changelog_overlay.visible = true
	_changelog_timer.start()


func _on_changelog_timeout() -> void:
	_changelog_overlay.visible = false


func _on_update_downloaded(apk_path: String) -> void:
	_update_status.text = "Download complete! Tap to install."
	# Change button to install.
	_update_status.set_meta("apk_path", apk_path)


func _on_update_failed(error: String) -> void:
	_update_status.text = "Update failed: %s" % error


# ---------------------------------------------------------- room flow ---

func _build_room_dialog(root: Control) -> void:
	_room_dialog = Control.new()
	_room_dialog.name = "RoomDialog"
	_room_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_dialog.visible = false
	root.add_child(_room_dialog)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1050, 430)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	_room_title = Label.new()
	_room_title.name = "RoomTitle"
	_room_title.add_theme_font_size_override("font_size", 40)
	_room_title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_room_title)
	_room_body = Label.new()
	_room_body.name = "RoomBody"
	_room_body.add_theme_font_size_override("font_size", 27)
	_room_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_room_body)
	_room_buttons = HBoxContainer.new()
	_room_buttons.name = "RoomButtons"
	_room_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_room_buttons.add_theme_constant_override("separation", 24)
	vbox.add_child(_room_buttons)


## RoomKit is built by a parallel agent and may not exist yet. Load it by path
## (never by class_name reference) so a missing file degrades gracefully
## instead of breaking the whole launcher at parse time.
func _roomkit() -> GDScript:
	if _roomkit_cache == null and ResourceLoader.exists(ROOM_KIT_PATH):
		_roomkit_cache = load(ROOM_KIT_PATH) as GDScript
	return _roomkit_cache


func _roomkit_ready() -> bool:
	var rk := _roomkit()
	if rk == null:
		return false
	return bool(rk.is_available())


func _room_setup_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	return bool(cfg.get_value("room", "setup_done", false))


func _set_room_setup_done() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("room", "setup_done", true)
	cfg.save(SETTINGS_PATH)


func _room_set_step(title: String, body: String, buttons: Array) -> void:
	_room_title.text = title
	_room_body.text = body
	for c in _room_buttons.get_children():
		c.queue_free()
	for spec in buttons:
		var b := _make_button(
			str(spec[0]), "RoomBtn" + str(spec[0]).replace(" ", ""), 28,
			Color(0.2, 0.35, 0.25))
		var cb: Callable = spec[1]
		b.pressed.connect(cb)
		_room_buttons.add_child(b)
	_room_dialog.visible = true


func _show_room_flow() -> void:
	if not _roomkit_ready():
		# Graceful fallback: no RoomKit in this build — never a dead end.
		_room_set_step("Room setup",
			"Room scanning isn't available in this build yet.\nEverything still works without it.",
			[["Continue", _on_room_done]])
		return
	_room_set_step("Set up your room",
		"Let's map your room so games can use your walls and furniture.",
		[["Scan my room", _on_room_scan]])


func _on_room_scan() -> void:
	var rk := _roomkit()
	if rk == null:
		_on_room_done()
		return
	rk.request_capture()
	_room_result_step()


func _room_result_step() -> void:
	var rk := _roomkit()
	if rk == null:
		_on_room_done()
		return
	rk.refresh()
	if bool(rk.has_room_data()):
		var walls: int = (rk.get_walls() as Array).size()
		var tables: int = (rk.get_tables() as Array).size()
		_room_set_step("Room ready",
			"Room ready — %d walls, %d tables found." % [walls, tables],
			[["Continue", _on_room_done]])
	else:
		_room_set_step("No room data yet",
			"No room data yet — complete room setup in your Quest system Settings, then tap Retry.",
			[["Retry", _room_result_step], ["Skip for now", _on_room_done]])


func _on_room_done() -> void:
	_set_room_setup_done()
	_room_dialog.visible = false


# ------------------------------------------------------- test helpers ---

func get_tab_button(tab_index: int) -> Button:
	if tab_index >= 0 and tab_index < _tab_buttons.size():
		return _tab_buttons[tab_index]
	return null


func get_game_button(page_index: int) -> Button:
	if page_index >= 0 and page_index < _game_buttons.size():
		return _game_buttons[page_index]
	return null


func get_current_tab() -> int:
	return _tab


func get_current_game() -> Node:
	return _current_game


func dismiss_room_dialog() -> void:
	if is_instance_valid(_room_dialog):
		_room_dialog.visible = false
