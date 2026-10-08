## Hub.gd - NEXUS ARCADE game selection hub.
## Category screens: GAMES / UTILITIES / CREATE / THEMES, each paged (25 per page).
##
## v0.8.0: the launcher is a 2D Control panel rendered into a SubViewport and
## shown on a 3D quad in front of the user. Input comes from XR laser pointers
## (see scripts/shared/xr_ui_pointer.gd): controller trigger clicks and hand
## pinches are raycast against the quad and injected into the SubViewport, so
## real 2D Buttons work on Quest 3. Desktop mouse is forwarded the same way
## when no XR tracker is live.
##
## v0.8.0 input hardening (this file):
##  - project.godot pins xr/openxr/default_action_map to openxr_action_map.tres
##    (the engine default already pointed there; now it's explicit);
##  - trigger detection ORs trigger_click / analog trigger / boolean trigger;
##  - hand trackers are found via XRServer TRACKER_HAND iteration (name
##    lookups collide with controller trackers);
##  - gaze fallback: camera-center reticle, trigger-press or 1.2s dwell
##    select, auto-hint after 10s with no input;
##  - live input-status line in the menu footer (never a silent dead menu);
##  - the panel yaw-aligns to the user's view on every menu open.
extends Node3D
class_name NexusHub

const CAT_GAMES := [
	{"name": "Gravity Golf", "scene": "res://scenes/golf/golf.tscn", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Swarm Protocol", "scene": "res://scenes/swarm/swarm.tscn", "color": Color(1.0, 0.3, 0.2)},
	{"name": "Neon Duel", "scene": "res://scenes/duel/duel.tscn", "color": Color(1.0, 0.9, 0.2)},
	{"name": "Beat Blades", "scene": "res://scenes/beat-blades/beat-blades.tscn", "color": Color(1.0, 0.0, 1.0)},
	{"name": "Laser Tag AR", "scene": "res://scenes/laser-tag-ar/laser-tag-ar.tscn", "color": Color(1.0, 0.1, 0.1)},
	{"name": "Room Racer", "scene": "res://scenes/room-racer/room-racer.tscn", "color": Color(0.0, 0.8, 1.0)},
	{"name": "AR Defender", "scene": "res://scenes/ar-defender/ar-defender.tscn", "color": Color(1.0, 0.2, 0.5)},
	{"name": "Sky Defender", "scene": "res://scenes/sky-defender/sky-defender.tscn", "color": Color(0.9, 0.5, 0.1)},
	{"name": "Drone Racer", "scene": "res://scenes/drone-racer/drone-racer.tscn", "color": Color(0.3, 0.7, 1.0)},
	{"name": "Spell Duel", "scene": "res://scenes/spell-duel/spell-duel.tscn", "color": Color(0.7, 0.2, 1.0)},
	{"name": "Rhythm Boxer", "scene": "res://scenes/rhythm-boxer/rhythm-boxer.tscn", "color": Color(1.0, 0.2, 0.2)},
	{"name": "Marble Run", "scene": "res://scenes/marble-run/marble-run.tscn", "color": Color(0.25, 0.5, 1.0)},
	{"name": "AR Darts", "scene": "res://scenes/ar-darts/ar-darts.tscn", "color": Color(1.0, 0.75, 0.15)},
	{"name": "AR Fishing", "scene": "res://scenes/ar-fishing/ar-fishing.tscn", "color": Color(0.15, 0.8, 0.75)},
	{"name": "Laser Mirrors", "scene": "res://scenes/mirror-maze/mirror-maze.tscn", "color": Color(1.0, 0.15, 0.25)},
	{"name": "Gravity Glove", "scene": "res://scenes/gravity-glove/gravity-glove.tscn", "color": Color(0.3, 1.0, 0.9)},
	{"name": "Time Freeze", "scene": "res://scenes/time-freeze/time-freeze.tscn", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Air Drums", "scene": "res://scenes/air-drums/air-drums.tscn", "color": Color(1.0, 0.35, 0.15)},
	{"name": "Shadow Puppets", "scene": "res://scenes/shadow-puppet/shadow-puppet.tscn", "color": Color(1.0, 0.65, 0.3)},
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
	{"name": "Star Map", "scene": "res://scenes/star-map/star-map.tscn", "color": Color(0.1, 0.1, 0.8)},
	{"name": "Sky Traffic", "scene": "res://scenes/sky_traffic/sky_traffic.tscn", "color": Color(0.4, 0.8, 1.0)},
	{"name": "Eye Spy AR", "scene": "res://scenes/eye_spy/eye_spy.tscn", "color": Color(0.2, 0.9, 1.0)},
	{"name": "Plant Doctor", "scene": "res://scenes/plant_doctor/plant_doctor.tscn", "color": Color(0.3, 1.0, 0.5)},
	{"name": "Holo Pets", "scene": "res://scenes/holo-pets/holo-pets.tscn", "color": Color(1.0, 0.6, 0.8)},
	{"name": "AR DJ", "scene": "res://scenes/ar-dj/ar-dj.tscn", "color": Color(0.8, 0.0, 0.8)},
	{"name": "Couch Morph", "scene": "res://scenes/couch_morph/couch_morph.tscn", "color": Color(0.9, 0.4, 1.0)},
	{"name": "Mano Mágica", "scene": "res://scenes/mano_magica/mano_magica.tscn", "color": Color(1.0, 0.75, 0.3)},
]

const CAT_CREATE := [
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
	{"name": "Haunted Maze", "scene": "res://scenes/hw_haunted_maze/hw_haunted_maze.tscn", "color": Color(0.3, 0.6, 0.2)},
	{"name": "Web Slingshot", "scene": "res://scenes/hw_web_slingshot/hw_web_slingshot.tscn", "color": Color(0.8, 0.8, 0.9)},
	{"name": "Potion Mix", "scene": "res://scenes/hw_potion_mix/hw_potion_mix.tscn", "color": Color(0.4, 0.9, 0.3)},
	{"name": "Zombie Defense", "scene": "res://scenes/hw_zombie_defense/hw_zombie_defense.tscn", "color": Color(0.5, 0.9, 0.2)},
	{"name": "Skeleton Dance", "scene": "res://scenes/hw_skeleton_dance/hw_skeleton_dance.tscn", "color": Color(0.9, 0.9, 0.85)},
	{"name": "Broom Flight", "scene": "res://scenes/hw_broom_flight/hw_broom_flight.tscn", "color": Color(0.6, 0.3, 1.0)},
	{"name": "Monster Mash", "scene": "res://scenes/hw_monster_mash/hw_monster_mash.tscn", "color": Color(0.7, 0.2, 0.9)},
	{"name": "Candy Stack", "scene": "res://scenes/hw_candy_stack/hw_candy_stack.tscn", "color": Color(1.0, 0.7, 0.1)},
	{"name": "Mummy Wrap", "scene": "res://scenes/hw_mummy_wrap/hw_mummy_wrap.tscn", "color": Color(0.85, 0.8, 0.65)},
	{"name": "Bat Dodge", "scene": "res://scenes/hw_bat_dodge/hw_bat_dodge.tscn", "color": Color(0.35, 0.1, 0.5)},
	{"name": "Pumpkin Carve", "scene": "res://scenes/hw_pumpkin_carve/hw_pumpkin_carve.tscn", "color": Color(1.0, 0.55, 0.0)},
	{"name": "Portrait Gallery", "scene": "res://scenes/hw_portrait_gallery/hw_portrait_gallery.tscn", "color": Color(0.5, 0.2, 0.6)},
	{"name": "Werewolf Howl", "scene": "res://scenes/hw_werewolf_howl/hw_werewolf_howl.tscn", "color": Color(0.4, 0.5, 1.0)},
	{"name": "Hayride Shooter", "scene": "res://scenes/hw_hayride_shooter/hw_hayride_shooter.tscn", "color": Color(1.0, 0.6, 0.15)},
	{"name": "Apple Bobbing", "scene": "res://scenes/hw_apple_bobbing/hw_apple_bobbing.tscn", "color": Color(0.9, 0.15, 0.2)},
	{"name": "Phantom Piano", "scene": "res://scenes/hw_phantom_piano/hw_phantom_piano.tscn", "color": Color(0.75, 0.6, 1.0)},
	{"name": "Goblin Archery", "scene": "res://scenes/hw_goblin_archery/hw_goblin_archery.tscn", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Haunted Mirror Maze", "scene": "res://scenes/hw_mirror_maze/hw_mirror_maze.tscn", "color": Color(0.6, 0.9, 1.0)},
	{"name": "Witch Hat Toss", "scene": "res://scenes/hw_hat_toss/hw_hat_toss.tscn", "color": Color(0.55, 0.25, 0.9)},
	{"name": "Monster Feed", "scene": "res://scenes/hw_monster_feed/hw_monster_feed.tscn", "color": Color(0.3, 1.0, 0.4)},
	{"name": "Midnight Survival", "scene": "res://scenes/hw_midnight_survival/hw_midnight_survival.tscn", "color": Color(0.15, 0.1, 0.35)},
]


const GAMES_PER_PAGE := 20
const GRID_COLS := 5
const VP_SIZE := Vector2(1600, 1000)
const QUAD_SIZE := Vector2(2.4, 1.5)
const QUAD_POS := Vector3(0, 1.6, -2.0)
# v0.8.0 input hardening tuning.
const GAZE_DWELL_TIME := 1.2  # seconds of gaze hover before dwell-select fires
const GAZE_HINT_DELAY_MSEC := 10000  # no input this long -> show the gaze hint
const PANEL_DISTANCE := 2.0  # panel recenter distance from the camera (m)
const STATUS_REFRESH := 0.5  # input-status line refresh interval (s)
const SETTINGS_PATH := "user://nexus_settings.cfg"
const ROOM_KIT_PATH := "res://scripts/shared/room_kit.gd"
const COSTUME_SCENE := "res://scenes/halloween/costume_picker.tscn"
const TAB_NAMES := ["GAMES", "UTILITIES", "CREATE", "THEMES"]

## v0.9.0 Launcher 2.1 category skins: neon GAMES / holographic UTILITIES /
## studio CREATE / halloween THEMES. Applied to tabs, card borders, and
## launch transitions (title-card accent).
const CAT_SKINS := [
	{"edge": Color(1.0, 0.25, 0.85), "tab": Color(0.45, 0.08, 0.32), "glow": Color(1.0, 0.45, 0.95)},
	{"edge": Color(0.35, 0.85, 1.0), "tab": Color(0.08, 0.28, 0.42), "glow": Color(0.55, 0.92, 1.0)},
	{"edge": Color(1.0, 0.65, 0.25), "tab": Color(0.42, 0.22, 0.08), "glow": Color(1.0, 0.8, 0.45)},
	{"edge": Color(0.7, 0.3, 1.0), "tab": Color(0.26, 0.1, 0.42), "glow": Color(1.0, 0.55, 0.15)},
]
const HUB_EXTRAS_PATH := "res://scripts/hub_extras.gd"

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
# v0.8.0 input-hardening state.
var _xr_camera: Camera3D = null
var _gaze_reticle: MeshInstance3D = null
var _gaze_reticle_mat: StandardMaterial3D = null
var _input_status: Label = null
var _input_hint: Label = null
var _version_badge: Label = null
var _menu_open_msec := 0
var _last_input_msec := 0
var _hint_shown := false
var _gaze_hover: Control = null
var _gaze_dwell := 0.0
var _status_accum := 0.0
var _trigger_prev := {}
var _recenter_timer: Timer = null
# v0.9.0 Launcher 2.1: Spotlight hero row + key-art + category skins.
var _spotlight_row: HBoxContainer = null
var _spotlight_art: TextureRect = null
var _spotlight_name: Label = null
var _spotlight_desc: Label = null
var _spotlight_play: Button = null
var _spotlight_entry := {}
var _extras_table_cache: Array = []
var _depth_toggle: CheckButton = null


func _ready() -> void:
	_build_panel()
	_build_ui()
	_build_pointers()
	_cache_xr_camera()
	_build_gaze_reticle()
	_on_menu_open()
	_setup_updater()
	# One-shot re-settle: the HMD pose is often still identity during _ready,
	# so re-align the panel once tracking has had a moment to come up.
	_recenter_timer = Timer.new()
	_recenter_timer.name = "RecenterSettle"
	_recenter_timer.wait_time = 0.75
	_recenter_timer.one_shot = true
	_recenter_timer.timeout.connect(_recenter_panel)
	add_child(_recenter_timer)
	_recenter_timer.start()
	# Deferred one frame so Main._ready has initialized OpenXR first (child
	# _ready runs before the parent's) and trackers are registered.
	call_deferred("_log_xr_input_inventory")
	# Crash reporter: offer to send the previous session's log.
	var crash: Dictionary = BugReporter.prompt_if_crash_pending()
	if not crash.is_empty():
		_show_crash_prompt(crash)
	BugReporter.session_start("hub")
	# Roomscale-first: walk through room capture on first run.
	if not _room_setup_done():
		_show_room_flow()
	if get_node_or_null("/root/AudioKit") != null: AudioKit.play_music("menu_theme")
	# Menu experience upgrades (aurora bg, descriptions, favorites, search):
	# attach by path so a missing file degrades gracefully.
	if ResourceLoader.exists("res://scripts/hub_extras.gd"):
		var he = load("res://scripts/hub_extras.gd").new()
		if he.has_method("attach"):
			he.attach(self)


func _process(delta: float) -> void:
	var xr := get_viewport().use_xr
	for p in _pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
	if is_instance_valid(_gaze_reticle) and not xr:
		_gaze_reticle.visible = false
	_process_status(delta)
	if not xr:
		return
	_poll_controller_buttons()
	_process_gaze(delta)
	_process_hint()


func _input(event: InputEvent) -> void:
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


func _unhandled_key_input(event: InputEvent) -> void:
	# H (desktop) returns to the hub. Handled here — AFTER the GUI phase — so
	# typing "h"/"H" in a text field (e.g. the launcher's search box) types
	# the letter instead of kicking back to the hub. The controller menu
	# button is polled separately in _poll_controller_buttons().
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_H:
		_return_to_hub()


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
	# Local origin: _recenter_panel() places the whole PanelRoot in world
	# space (2m in front of the user, yaw-aligned), so the quad rides along.
	_quad.position = Vector3.ZERO
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

	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 28)
	vbox.add_child(header)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "NEXUS ARCADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0, 0.94, 1))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	# BIG build badge, top of the menu — readable on the headset at a glance.
	_version_badge = Label.new()
	_version_badge.name = "VersionBadge"
	_version_badge.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.8.0"))
	_version_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_version_badge.add_theme_font_size_override("font_size", 40)
	_version_badge.add_theme_color_override("font_color", Color(1, 1, 1))
	_version_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_version_badge.add_theme_constant_override("shadow_offset_x", 2)
	_version_badge.add_theme_constant_override("shadow_offset_y", 2)
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.0, 0.5, 0.8)
	badge_bg.set_corner_radius_all(14)
	badge_bg.content_margin_left = 22.0
	badge_bg.content_margin_right = 22.0
	badge_bg.content_margin_top = 8.0
	badge_bg.content_margin_bottom = 8.0
	_version_badge.add_theme_stylebox_override("normal", badge_bg)
	header.add_child(_version_badge)

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

	_build_spotlight(vbox)

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

	# Check-for-updates gets its own row: large, accent-colored, unmissable.
	# Behavior is unchanged — it queries version.json and reports inline.
	var update_row := HBoxContainer.new()
	update_row.name = "UpdateRow"
	update_row.alignment = BoxContainer.ALIGNMENT_CENTER
	update_row.add_theme_constant_override("separation", 20)
	vbox.add_child(update_row)
	var update_btn := _make_button("CHECK FOR UPDATES", "UpdateButton", 30, Color(0.0, 0.5, 0.85))
	update_btn.custom_minimum_size = Vector2(480, 72)
	update_btn.pressed.connect(_on_update_button)
	update_row.add_child(update_btn)
	_update_status = Label.new()
	_update_status.name = "UpdateStatus"
	_update_status.add_theme_font_size_override("font_size", 22)
	_update_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_update_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	update_row.add_child(_update_status)

	var footer := HBoxContainer.new()
	footer.name = "FooterRow"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	vbox.add_child(footer)
	var room_btn := _make_button("Room setup", "RoomButton", 24, Color(0.2, 0.35, 0.25))
	room_btn.pressed.connect(_show_room_flow)
	footer.add_child(room_btn)
	_costumes_button = _make_button("Costumes", "CostumesButton", 24, Color(0.5, 0.2, 0.6))
	_costumes_button.pressed.connect(_on_costumes_pressed)
	footer.add_child(_costumes_button)
	# v0.9.0: environment-depth occlusion toggle (default on). Persisted via
	# VisualFX; gameplay objects only.
	_depth_toggle = CheckButton.new()
	_depth_toggle.name = "DepthToggle"
	_depth_toggle.text = "Depth FX"
	_depth_toggle.add_theme_font_size_override("font_size", 22)
	_depth_toggle.button_pressed = VisualFX.is_depth_occlusion_enabled()
	_depth_toggle.toggled.connect(_on_depth_toggled)
	footer.add_child(_depth_toggle)
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

	# Shown automatically if no controller/hand input happens within 10s of
	# the menu opening. Hidden again on the first input event.
	_input_hint = Label.new()
	_input_hint.name = "InputHint"
	_input_hint.text = "Look at a button and pull the trigger"
	_input_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_hint.add_theme_font_size_override("font_size", 28)
	_input_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_input_hint.visible = false
	vbox.add_child(_input_hint)

	# Live input-status line, bottom of the menu. Updated every STATUS_REFRESH
	# seconds — the menu is never silently dead: this always says SOMETHING.
	_input_status = Label.new()
	_input_status.name = "InputStatus"
	_input_status.text = "XR input: starting..."
	_input_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_status.add_theme_font_size_override("font_size", 20)
	_input_status.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
	vbox.add_child(_input_status)

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
			str(game["name"]), "Game_%d" % (i - start), 19,
			(game["color"] as Color).darkened(0.55))
		b.custom_minimum_size = Vector2(240, 128)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		# Launcher 2.1: key-art thumbnail on top, name below (card look).
		var art := game_card_icon(str(game["scene"]))
		if art != null:
			b.icon = art
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		_skin_card(b, _tab)
		b.pressed.connect(_load_game.bind(str(game["scene"]), str(game["name"])))
		_grid.add_child(b)
		_game_buttons.append(b)
	var pages := _page_count()
	_page_label.text = "Page %d / %d" % [_page + 1, maxi(pages, 1)]
	_nav_prev.visible = _page > 0
	_nav_next.visible = _page < pages - 1
	_refresh_tabs()
	_refresh_spotlight()
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
	_apply_tab_skins()


## Key-art thumbnail for a game card (assets/keyart/<stem>.png), or null.
func game_card_icon(scene_path: String) -> Texture2D:
	var stem := scene_path.get_file().get_basename()
	var path := "res://assets/keyart/%s.png" % stem
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Launcher 2.1 category skins: tab button colors per category; the active
## tab gets the category edge glow.
func _apply_tab_skins() -> void:
	for i in range(_tab_buttons.size()):
		var tb := _tab_buttons[i]
		if tb == null or not is_instance_valid(tb):
			continue
		var skin: Dictionary = CAT_SKINS[clampi(i, 0, 3)]
		var sb := tb.get_theme_stylebox("normal") as StyleBoxFlat
		if sb != null:
			sb.bg_color = skin["tab"]
			if i == _tab:
				sb.border_color = skin["edge"]
				sb.set_border_width_all(4)
			else:
				sb.set_border_width_all(0)


## Apply the category edge border to a game card button.
func _skin_card(b: Button, tab: int) -> void:
	var skin: Dictionary = CAT_SKINS[clampi(tab, 0, 3)]
	for sb_name in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(sb_name) as StyleBoxFlat
		if sb != null:
			sb.border_color = skin["edge"]
			sb.set_border_width_all(3)


## Category accent color (title-card tint, spotlight edge).
func _skin_accent(tab: int) -> Color:
	return CAT_SKINS[clampi(tab, 0, 3)]["edge"]


# ------------------------------------------------- Spotlight hero row ---

## The featured game, rotating daily across all 75 experiences.
func _spotlight_game() -> Dictionary:
	var all: Array = []
	all.append_array(CAT_GAMES)
	all.append_array(CAT_UTILITIES)
	all.append_array(CAT_CREATE)
	all.append_array(CAT_THEMES)
	if all.is_empty():
		return {}
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	return all[day % all.size()]


func _build_spotlight(vbox: VBoxContainer) -> void:
	_spotlight_row = HBoxContainer.new()
	_spotlight_row.name = "SpotlightRow"
	_spotlight_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_spotlight_row.add_theme_constant_override("separation", 20)
	vbox.add_child(_spotlight_row)
	_spotlight_art = TextureRect.new()
	_spotlight_art.name = "SpotlightArt"
	_spotlight_art.custom_minimum_size = Vector2(220, 138)
	_spotlight_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spotlight_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_spotlight_row.add_child(_spotlight_art)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spotlight_row.add_child(info)
	var tag := Label.new()
	tag.text = "★ SPOTLIGHT — featured today"
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	info.add_child(tag)
	_spotlight_name = Label.new()
	_spotlight_name.add_theme_font_size_override("font_size", 36)
	_spotlight_name.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(_spotlight_name)
	_spotlight_desc = Label.new()
	_spotlight_desc.add_theme_font_size_override("font_size", 22)
	_spotlight_desc.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	_spotlight_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spotlight_desc.custom_minimum_size = Vector2(700, 0)
	info.add_child(_spotlight_desc)
	_spotlight_play = _make_button("PLAY", "SpotlightPlay", 28, Color(0.0, 0.55, 0.3))
	_spotlight_play.custom_minimum_size = Vector2(220, 76)
	_spotlight_play.pressed.connect(_on_spotlight_play)
	_spotlight_row.add_child(_spotlight_play)


func _refresh_spotlight() -> void:
	if _spotlight_row == null or not is_instance_valid(_spotlight_row):
		return
	_spotlight_entry = _spotlight_game()
	if _spotlight_entry.is_empty():
		_spotlight_row.visible = false
		return
	_spotlight_row.visible = true
	var nm := str(_spotlight_entry.get("name", "?"))
	_spotlight_name.text = nm
	_spotlight_desc.text = _game_desc(nm)
	var art := game_card_icon(str(_spotlight_entry.get("scene", "")))
	if art != null:
		_spotlight_art.texture = art


func _on_spotlight_play() -> void:
	if _spotlight_entry.is_empty():
		return
	_load_game(str(_spotlight_entry.get("scene", "")), str(_spotlight_entry.get("name", "")))


func _on_costumes_pressed() -> void:
	_load_game(COSTUME_SCENE, "Costume Picker")


func _on_depth_toggled(on: bool) -> void:
	VisualFX.set_depth_occlusion_enabled(on)


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
	_note_input_event()
	inject_motion(viewport_pos)


func _on_pointer_clicked(viewport_pos: Vector2) -> void:
	_note_input_event()
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


# -------------------------------------------- v0.8.0 input hardening ---

func _cache_xr_camera() -> void:
	_xr_camera = null
	if _xr_origin != null and is_instance_valid(_xr_origin):
		_xr_camera = _xr_origin.get_node_or_null("XRCamera3D") as Camera3D


func _panel_visible() -> bool:
	return _panel_root != null and is_instance_valid(_panel_root) and _panel_root.visible


## Called on every menu open: initial _ready and _return_to_hub. Resets the
## input-event clock, hides the hint, and yaw-aligns the panel to the user.
func _on_menu_open() -> void:
	var now := Time.get_ticks_msec()
	_menu_open_msec = now
	_last_input_msec = now
	_hint_shown = false
	_gaze_dwell = 0.0
	_gaze_hover = null
	if is_instance_valid(_input_hint):
		_input_hint.visible = false
	_recenter_panel()
	BugReporter.add_breadcrumb("menu_open")


## Yaw-align the panel so it faces the user's current camera forward
## direction at ~PANEL_DISTANCE, clamped to a comfortable height and kept out
## of the floor. Falls back to the fixed QUAD_POS when no camera is found.
func _recenter_panel() -> void:
	if _panel_root == null or not is_instance_valid(_panel_root):
		return
	var cam := _xr_camera
	if cam == null or not is_instance_valid(cam):
		cam = get_viewport().get_camera_3d()
	if cam == null:
		_panel_root.position = QUAD_POS
		_panel_root.rotation = Vector3.ZERO
		return
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var target := cam_pos + fwd * PANEL_DISTANCE
	# Comfortable reading height; never below the floor.
	target.y = clampf(cam_pos.y, 1.1, 1.75)
	_panel_root.global_position = target
	# Rotate so the quad's +Z faces the user (yaw only, no pitch/roll).
	var to_user := cam_pos - target
	to_user.y = 0.0
	if to_user.length() > 0.05:
		_panel_root.rotation = Vector3(0.0, atan2(to_user.x, to_user.z), 0.0)


## One-line XR input inventory for the crash-log relay: the next stuck-menu
## report will carry exactly what input the device had.
func _log_xr_input_inventory() -> void:
	var use_xr: bool = get_viewport().use_xr
	var action_map := str(ProjectSettings.get_setting("xr/openxr/default_action_map", ""))
	var hands := XRUIPointer.find_hand_trackers()
	var hl := hands["left"] != null and (hands["left"] as XRHandTracker).has_tracking_data
	var hr := hands["right"] != null and (hands["right"] as XRHandTracker).has_tracking_data
	BugReporter.log("XR input inventory: use_xr=%s action_map='%s' ctl_L=%s ctl_R=%s hand_L=%s hand_R=%s gaze=%s" % [
		str(use_xr), action_map,
		str(_controller_tracked("Left")), str(_controller_tracked("Right")),
		str(hl), str(hr),
		"ready" if use_xr else "off",
	])


func _controller_tracked(side_prefix: String) -> bool:
	for ctl in _controllers:
		if ctl == null or not is_instance_valid(ctl):
			continue
		if not String(ctl.name).begins_with(side_prefix):
			continue
		# NOTE: ctl.get_tracker() returns the configured NAME (StringName,
		# never null) — liveness must be checked against XRServer.
		if XRServer.get_tracker(ctl.tracker) != null:
			return true
	return false


## Any real input event restarts the 10s hint clock and hides the hint.
func _note_input_event() -> void:
	_last_input_msec = Time.get_ticks_msec()
	if is_instance_valid(_input_hint) and _input_hint.visible:
		_input_hint.visible = false


## Menu-button polling (was inline in _process) plus trigger edges, which
## feed the gaze fallback and the input-event clock.
func _poll_controller_buttons() -> void:
	var panel_open := _panel_visible()
	for ctl in _controllers:
		if ctl == null or not is_instance_valid(ctl):
			continue
		# Skip controllers with no live tracker in XRServer. (get_tracker()
		# returns the configured name StringName, never null — not liveness.)
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var id := ctl.get_instance_id()
		# NOTE (v0.9.0): the menu button in games is owned by the PauseExit
		# autoload now (pause overlay -> Quit to Hub). The hub no longer
		# hijacks it here; this only keeps edge state fresh.
		_menu_prev[id] = ctl.is_button_pressed("menu_button")
		var trig_now := XRUIPointer.trigger_pressed(ctl)
		if trig_now and not bool(_trigger_prev.get(id, false)):
			_note_input_event()
			if panel_open:
				_gaze_trigger_click()
		_trigger_prev[id] = trig_now


# ------------------------------------------------------- gaze fallback ---

func _build_gaze_reticle() -> void:
	if _xr_camera == null or not is_instance_valid(_xr_camera):
		return
	_gaze_reticle_mat = StandardMaterial3D.new()
	_gaze_reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gaze_reticle_mat.emission_enabled = true
	_gaze_reticle_mat.emission = Color(0.6, 0.95, 1.0)
	_gaze_reticle_mat.emission_energy_multiplier = 2.5
	_gaze_reticle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gaze_reticle_mat.albedo_color = Color(0.6, 0.95, 1.0, 0.9)
	var sph := SphereMesh.new()
	sph.radius = 0.008
	sph.height = 0.016
	_gaze_reticle = MeshInstance3D.new()
	_gaze_reticle.name = "GazeReticle"
	_gaze_reticle.mesh = sph
	_gaze_reticle.material_override = _gaze_reticle_mat
	# Pinned to the center of the view, just in front of the recentered panel.
	_gaze_reticle.position = Vector3(0, 0, -(PANEL_DISTANCE - 0.4))
	_gaze_reticle.visible = false
	_xr_camera.add_child(_gaze_reticle)


## The gaze fallback runs only when no controller/hand pointer is live, so it
## never fights the lasers for hover.
func _gaze_should_run() -> bool:
	if not get_viewport().use_xr:
		return false
	return not _xr_pointer_live()


func _process_gaze(delta: float) -> void:
	var ret := _gaze_reticle
	if ret == null or not is_instance_valid(ret):
		return
	var active := _gaze_should_run() and _panel_visible()
	ret.visible = active
	if not active:
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	if _xr_camera == null or not is_instance_valid(_xr_camera) or _quad == null:
		return
	var origin := _xr_camera.global_position
	var dir := -_xr_camera.global_transform.basis.z.normalized()
	var hit := XRUIPointer.ray_to_viewport(origin, dir, _quad, VP_SIZE)
	if not bool(hit["hit"]):
		_update_reticle_feedback(false, 0.0)
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	var pos: Vector2 = hit["pos"]
	inject_motion(pos)
	var hovered := _viewport.gui_get_hovered_control()
	var hovering_button := hovered is Button
	if hovering_button and hovered == _gaze_hover:
		_gaze_dwell += delta
		_update_reticle_feedback(true, _gaze_dwell / GAZE_DWELL_TIME)
		if _gaze_dwell >= GAZE_DWELL_TIME:
			_gaze_dwell = 0.0
			_note_input_event()
			inject_click(pos)
	else:
		_gaze_dwell = 0.0
		_gaze_hover = hovered
		_update_reticle_feedback(hovering_button, 0.0)


## Trigger press while the gaze fallback is active: click whatever the
## camera-center ray is on.
func _gaze_trigger_click() -> void:
	if not _gaze_should_run() or not _panel_visible():
		return
	if _xr_camera == null or not is_instance_valid(_xr_camera) or _quad == null:
		return
	var hit := XRUIPointer.ray_to_viewport(
		_xr_camera.global_position,
		-_xr_camera.global_transform.basis.z.normalized(),
		_quad, VP_SIZE)
	if bool(hit["hit"]):
		inject_click(hit["pos"])


func _update_reticle_feedback(hovering: bool, dwell_frac: float) -> void:
	if _gaze_reticle_mat == null or _gaze_reticle == null:
		return
	var f := clampf(dwell_frac, 0.0, 1.0)
	if hovering:
		# Cyan -> green as the dwell fills, so "about to click" is readable.
		_gaze_reticle_mat.emission = Color(0.6, 0.95, 1.0).lerp(Color(0.4, 1.0, 0.5), f)
	else:
		_gaze_reticle_mat.emission = Color(0.6, 0.95, 1.0)
	_gaze_reticle.scale = Vector3.ONE * (1.0 + f * 0.9)


# --------------------------------------------- hint + input status line ---

func _process_hint() -> void:
	if _hint_shown or not _panel_visible():
		return
	if not get_viewport().use_xr:
		return
	var now := Time.get_ticks_msec()
	if now - _last_input_msec >= GAZE_HINT_DELAY_MSEC and is_instance_valid(_input_hint):
		_hint_shown = true
		_input_hint.visible = true
		BugReporter.add_breadcrumb("input_hint_shown")


func _process_status(delta: float) -> void:
	_status_accum += delta
	if _status_accum < STATUS_REFRESH:
		return
	_status_accum = 0.0
	if is_instance_valid(_input_status):
		_input_status.text = _input_status_text()


func _input_status_text() -> String:
	var xr := get_viewport().use_xr
	if not xr:
		return "XR input: none detected — desktop mouse active"
	var ctl_l := _controller_tracked("Left")
	var ctl_r := _controller_tracked("Right")
	var hands := XRUIPointer.find_hand_trackers()
	var hl := hands["left"] != null and (hands["left"] as XRHandTracker).has_tracking_data
	var hr := hands["right"] != null and (hands["right"] as XRHandTracker).has_tracking_data
	if not ctl_l and not ctl_r and not hl and not hr:
		return "XR input: none detected — desktop mouse active"
	var ctl_txt := "none"
	if ctl_l and ctl_r:
		ctl_txt = "L+R tracked"
	elif ctl_l:
		ctl_txt = "L tracked"
	elif ctl_r:
		ctl_txt = "R tracked"
	var hand_txt := "off"
	if hl and hr:
		hand_txt = "L+R"
	elif hl:
		hand_txt = "L"
	elif hr:
		hand_txt = "R"
	var gaze_txt := "gaze ready" if _gaze_should_run() else "gaze standby"
	return "Input: controllers %s · hands %s · %s" % [ctl_txt, hand_txt, gaze_txt]


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
		_autowire_game(scene_path, game_name)
		print("[Hub] Loaded: ", game_name)
	else:
		push_error("[Hub] Failed to load: " + scene_path)
		if is_instance_valid(_panel_root):
			_panel_root.visible = true


## v0.9.0 global auto-wirer (opt-OUT): every launched game automatically
## gets genre music, a passthrough mood grade, a title-card sting, and an
## affordance pass — the shared systems no game ever called are now alive
## by default. A game opts out with `static var no_auto_wire := true`.
func _autowire_game(scene_path: String, game_name: String) -> void:
	var stem := scene_path.get_file().get_basename()
	# 1. Genre music (activates the dormant GENRE_FOR_SCENE map).
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_active_scene(stem)
		AudioKit.set_intensity(0)
		AudioKit.play_music_for_scene(stem)
	# 2. Passthrough mood grade (haunted green for THEMES, deep teal for
	# dive/aquarium, natural everywhere else).
	if get_node_or_null("/root/MoodLUT") != null:
		MoodLUT.apply_for_game(stem, _tab)
	# 3. Juice: title card + affordance pass. The no_auto_wire opt-out skips
	# this and the controller-skin dressing — but NEVER the pause/exit below.
	if _current_game == null or not is_instance_valid(_current_game):
		return
	var opted_out := _game_opt_out()
	if not opted_out and get_node_or_null("/root/JuiceFX") != null:
		JuiceFX.title_card(game_name, _game_desc(game_name), _skin_accent(_tab))
		JuiceFX.affordance_pass(_current_game)
	# 4. Global pause/exit (ship-blocker) + controller skins + button legend.
	# PauseExit attaches UNCONDITIONALLY, even for no_auto_wire games: the
	# standing rule is every game exits to launcher. (v0.9.1 verification:
	# the old early-return skipped this whole block for opt-out games, which
	# would have silently dropped their exit path entirely.)
	if get_node_or_null("/root/PauseExit") != null:
		PauseExit.attach_to_game(
			_current_game, _return_to_hub,
			_load_game.bind(scene_path, game_name))
		if not opted_out:
			# controller_skins.gd by path: immune to stale class caches.
			var skins_scr: GDScript = load("res://scripts/shared/controller_skins.gd")
			var skin_cfg: Dictionary = skins_scr.config_for(_current_game, stem)
			if bool(skin_cfg.get("uses_controllers", true)):
				skins_scr.apply(_current_game, skin_cfg)
				PauseExit.show_controls_intro(skin_cfg, game_name)


## Per-game opt-out: `static var no_auto_wire := true` in the game script.
func _game_opt_out() -> bool:
	if _current_game == null or not is_instance_valid(_current_game):
		return false
	var scr := _current_game.get_script() as GDScript
	return scr != null and bool(scr.get("no_auto_wire"))


## One-line description for the title card, from hub_extras' master table.
func _game_desc(game_name: String) -> String:
	if _extras_table_cache.is_empty() and ResourceLoader.exists(HUB_EXTRAS_PATH):
		var scr: GDScript = load(HUB_EXTRAS_PATH)
		var table: Array = scr.get("GAMES")
		if table != null:
			_extras_table_cache = table
	for g in _extras_table_cache:
		var gd: Dictionary = g
		if str(gd.get("n", "")) == game_name:
			return str(gd.get("d", ""))
	return ""


func _return_to_hub() -> void:
	BugReporter.session_end()
	if get_node_or_null("/root/PauseExit") != null:
		PauseExit.detach()
	(load("res://scripts/shared/controller_skins.gd") as GDScript).clear()
	if get_node_or_null("/root/JuiceFX") != null:
		JuiceFX.dismiss_title_card()
	if _current_game != null and is_instance_valid(_current_game):
		_current_game.queue_free()
	_current_game = null
	# Restore the hub's own atmosphere.
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_active_scene("")
		AudioKit.set_intensity(0)
		AudioKit.play_music("menu_theme")
	if get_node_or_null("/root/MoodLUT") != null:
		MoodLUT.reset()
	if is_instance_valid(_panel_root):
		_panel_root.visible = true
	_on_menu_open()


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
