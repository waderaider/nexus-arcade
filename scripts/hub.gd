## Hub.gd - NEXUS ARCADE game selection hub.
##
## v0.9.3 LAUNCHER REWORK (permanent LAUNCHER LAW): ONE simple 2D panel, one
## scrollable list (name + one-line desc, master order), controller laser +
## trigger. Keep: version badge, Check for Updates, Room setup. Deleted:
## tabs, categories, spotlight, pager, search, favorites, key art, depth
## toggle, room auto-popup, hub_extras (aurora shader) attach.
##
## Input is belt-and-suspenders: XRUIPointer signal path AND the independent
## DirectUIInput fallback (own yellow beams, raw trigger-edge polling) run
## every frame; both funnel into the single deduped inject_click(). The gaze
## reticle/dwell fallback keys on "no beam actually drawn" (never on tracker
## registration). Panel auto-frames: recenter on every menu open + 0.5s tick
## guard (push out when <0.8m, recenter when >30deg off-axis).
##
## Boot is staged: stage 0 = panel + quad + LOADING (first frame <2s);
## stage 1 = list UI + pointers; stage 2 (idle) = music, updater, telemetry
## warmup, crash prompt. AudioKit SFX lazy-load; no textures/shaders at boot.
extends Node3D
class_name NexusHub

const CAT_GAMES := [
	{"name": "Gravity Golf", "scene": "res://scenes/golf/golf.tscn", "desc": "Putt across floating courses where every shot bends gravity.", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Swarm Protocol", "scene": "res://scenes/swarm/swarm.tscn", "desc": "Command your drone swarm to outmaneuver the hive.", "color": Color(1.0, 0.3, 0.2)},
	{"name": "Neon Duel", "scene": "res://scenes/duel/duel.tscn", "desc": "Fast-draw light-blade duels in your living room.", "color": Color(1.0, 0.9, 0.2)},
	{"name": "Beat Blades", "scene": "res://scenes/beat-blades/beat-blades.tscn", "desc": "Slice incoming beats with twin energy blades.", "color": Color(1.0, 0.0, 1.0)},
	{"name": "Laser Tag AR", "scene": "res://scenes/laser-tag-ar/laser-tag-ar.tscn", "desc": "Classic laser tag, played across your real room.", "color": Color(1.0, 0.1, 0.1)},
	{"name": "Room Racer", "scene": "res://scenes/room-racer/room-racer.tscn", "desc": "Race hover cars on a track mapped to your room.", "color": Color(0.0, 0.8, 1.0)},
	{"name": "AR Defender", "scene": "res://scenes/ar-defender/ar-defender.tscn", "desc": "Defend your furniture forts against enemy waves.", "color": Color(1.0, 0.2, 0.5)},
	{"name": "Sky Defender", "scene": "res://scenes/sky-defender/sky-defender.tscn", "desc": "Swat invading drones out of your ceiling sky.", "color": Color(0.9, 0.5, 0.1)},
	{"name": "Drone Racer", "scene": "res://scenes/drone-racer/drone-racer.tscn", "desc": "Thread FPV drones through rings around your home.", "color": Color(0.3, 0.7, 1.0)},
	{"name": "Spell Duel", "scene": "res://scenes/spell-duel/spell-duel.tscn", "desc": "Duel rival wizards with gesture-cast spells.", "color": Color(0.7, 0.2, 1.0)},
	{"name": "Rhythm Boxer", "scene": "res://scenes/rhythm-boxer/rhythm-boxer.tscn", "desc": "Punch targets to the beat, round after round.", "color": Color(1.0, 0.2, 0.2)},
	{"name": "Marble Run", "scene": "res://scenes/marble-run/marble-run.tscn", "desc": "Build wild marble tracks across your tables.", "color": Color(0.25, 0.5, 1.0)},
	{"name": "AR Darts", "scene": "res://scenes/ar-darts/ar-darts.tscn", "desc": "Darts on a holographic board on your wall.", "color": Color(1.0, 0.75, 0.15)},
	{"name": "AR Fishing", "scene": "res://scenes/ar-fishing/ar-fishing.tscn", "desc": "Cast into a pond that appears on your floor.", "color": Color(0.15, 0.8, 0.75)},
	{"name": "Laser Mirrors", "scene": "res://scenes/mirror-maze/mirror-maze.tscn", "desc": "Aim lasers with mirrors to hit every target.", "color": Color(1.0, 0.15, 0.25)},
	{"name": "Gravity Glove", "scene": "res://scenes/gravity-glove/gravity-glove.tscn", "desc": "Grab and fling objects with a gravity glove.", "color": Color(0.3, 1.0, 0.9)},
	{"name": "Time Freeze", "scene": "res://scenes/time-freeze/time-freeze.tscn", "desc": "Freeze time, reposition, then let chaos resume.", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Air Drums", "scene": "res://scenes/air-drums/air-drums.tscn", "desc": "Play a full drum kit on thin air.", "color": Color(1.0, 0.35, 0.15)},
	{"name": "Shadow Puppets", "scene": "res://scenes/shadow-puppet/shadow-puppet.tscn", "desc": "Cast shadow creatures onto your walls.", "color": Color(1.0, 0.65, 0.3)},
	{"name": "Starforge", "scene": "res://scenes/starforge/starforge.tscn", "desc": "Forge a star system, planet by planet.", "color": Color(0.8, 0.4, 1.0)},
	{"name": "Holo Dungeon", "scene": "res://scenes/holo-dungeon/holo-dungeon.tscn", "desc": "A dungeon crawler that unfolds in your room.", "color": Color(0.4, 0.2, 0.6)},
	{"name": "AR Escape Room", "scene": "res://scenes/ar-escape-room/ar-escape-room.tscn", "desc": "Solve the room to escape the room.", "color": Color(0.7, 0.5, 0.2)},
	{"name": "AR Billiards", "scene": "res://scenes/ar-billiards/ar-billiards.tscn", "desc": "Pool on your coffee table - no table required.", "color": Color(0.1, 0.6, 0.25)},
	{"name": "Holo Chef", "scene": "res://scenes/holo_chef/holo_chef.tscn", "desc": "Cook holographic recipes with your own hands.", "color": Color(1.0, 0.55, 0.2)},
	{"name": "Dragon Ranch", "scene": "res://scenes/dragon_ranch/dragon_ranch.tscn", "desc": "Raise and train your own AR dragons.", "color": Color(1.0, 0.3, 0.25)},
	{"name": "Wizard Academy", "scene": "res://scenes/wizard_academy/wizard_academy.tscn", "desc": "Learn real spell combos at wizard school.", "color": Color(0.65, 0.35, 1.0)},
	{"name": "Holo Farm", "scene": "res://scenes/holo_farm/holo_farm.tscn", "desc": "Grow a farm that lives on your floor.", "color": Color(0.45, 0.9, 0.35)},
	{"name": "Mech Pilot", "scene": "res://scenes/mech_pilot/mech_pilot.tscn", "desc": "Climb into a mech and stomp the block.", "color": Color(0.35, 0.75, 0.95)},
	{"name": "Deep Dive", "scene": "res://scenes/deep_dive/deep_dive.tscn", "desc": "Dive an ocean trench from your couch.", "color": Color(0.15, 0.5, 1.0)},
	{"name": "AR Detective", "scene": "res://scenes/ar_detective/ar_detective.tscn", "desc": "Hunt for clues hidden around your home.", "color": Color(1.0, 0.75, 0.3)},
	{"name": "Sky Pirates", "scene": "res://scenes/sky_pirates/sky_pirates.tscn", "desc": "Board airships and duel sky pirates.", "color": Color(0.3, 0.85, 0.8)},
	{"name": "Monster Lab", "scene": "res://scenes/monster_lab/monster_lab.tscn", "desc": "Mix monster DNA and unleash your creation.", "color": Color(0.6, 1.0, 0.3)},
	{"name": "Myth Zoo", "scene": "res://scenes/myth_zoo/myth_zoo.tscn", "desc": "Mythical beasts roaming your space.", "color": Color(1.0, 0.4, 0.8)},
	{"name": "QR Treasure Hunt", "scene": "res://scenes/qr_hunt/qr_hunt.tscn", "desc": "Follow QR clues to buried AR treasure.", "color": Color(1.0, 0.85, 0.2)},
]

const CAT_UTILITIES := [
	{"name": "Star Map", "scene": "res://scenes/star-map/star-map.tscn", "desc": "Name the constellations on your ceiling.", "color": Color(0.1, 0.1, 0.8)},
	{"name": "Sky Traffic", "scene": "res://scenes/sky_traffic/sky_traffic.tscn", "desc": "Watch live airplanes cross your sky in AR.", "color": Color(0.4, 0.8, 1.0)},
	{"name": "Eye Spy AR", "scene": "res://scenes/eye_spy/eye_spy.tscn", "desc": "I spy, played with your whole house.", "color": Color(0.2, 0.9, 1.0)},
	{"name": "Plant Doctor", "scene": "res://scenes/plant_doctor/plant_doctor.tscn", "desc": "Scan your houseplants for a health checkup.", "color": Color(0.3, 1.0, 0.5)},
	{"name": "Holo Pets", "scene": "res://scenes/holo-pets/holo-pets.tscn", "desc": "Adopt a pet that lives on your furniture.", "color": Color(1.0, 0.6, 0.8)},
	{"name": "AR DJ", "scene": "res://scenes/ar-dj/ar-dj.tscn", "desc": "Spin tracks on floating decks.", "color": Color(0.8, 0.0, 0.8)},
	{"name": "Couch Morph", "scene": "res://scenes/couch_morph/couch_morph.tscn", "desc": "Reskin your couch: spaceship, lava isle, pirate deck.", "color": Color(0.9, 0.4, 1.0)},
	{"name": "Mano Mágica", "scene": "res://scenes/mano_magica/mano_magica.tscn", "desc": "Learn hand tracking: pinch, grab, throw, sculpt, conduct, pet.", "color": Color(1.0, 0.75, 0.3)},
]

const CAT_CREATE := [
	{"name": "Light Painter", "scene": "res://scenes/light-painter/light-painter.tscn", "desc": "Draw with light and leave glowing trails.", "color": Color(1.0, 0.3, 0.9)},
	{"name": "Holo Piano", "scene": "res://scenes/holo-piano/holo-piano.tscn", "desc": "A grand piano projected onto your floor.", "color": Color(1.0, 1.0, 1.0)},
	{"name": "Holo Theremin", "scene": "res://scenes/holo-theremin/holo-theremin.tscn", "desc": "Make music just by waving your hands.", "color": Color(0.55, 0.3, 1.0)},
	{"name": "AR Graffiti", "scene": "res://scenes/graffiti-wall/graffiti-wall.tscn", "desc": "Tag your walls with zero cleanup.", "color": Color(0.5, 1.0, 0.2)},
	{"name": "AR Karaoke", "scene": "res://scenes/ar-karaoke/ar-karaoke.tscn", "desc": "Karaoke night with lyrics on your wall.", "color": Color(1.0, 0.4, 0.7)},
	{"name": "Sand Shaper", "scene": "res://scenes/sand-shaper/sand-shaper.tscn", "desc": "Sculpt a sandbox that never spills.", "color": Color(0.9, 0.75, 0.45)},
	{"name": "Clay Shaper", "scene": "res://scenes/clay-shaper/clay-shaper.tscn", "desc": "Throw virtual clay on a floating wheel.", "color": Color(0.8, 0.45, 0.25)},
	{"name": "Sketch to 3D", "scene": "res://scenes/sketch_3d/sketch_3d.tscn", "desc": "Sketch it, then watch it pop into 3D.", "color": Color(1.0, 0.5, 1.0)},
	{"name": "Holo Garden", "scene": "res://scenes/holo-garden/holo-garden.tscn", "desc": "Plant a garden that blooms overnight.", "color": Color(0.3, 0.9, 0.3)},
	{"name": "Zero-G Sandbox", "scene": "res://scenes/zero-g-sandbox/zero-g-sandbox.tscn", "desc": "Build contraptions in zero gravity.", "color": Color(0.5, 0.0, 1.0)},
	{"name": "Holo Aquarium", "scene": "res://scenes/holo-aquarium/holo-aquarium.tscn", "desc": "An aquarium on your wall, no water needed.", "color": Color(0.1, 0.7, 0.9)},
]

const CAT_THEMES := [
	{"name": "Pumpkin Smash", "scene": "res://scenes/hw_pumpkin_smash/hw_pumpkin_smash.tscn", "desc": "Smash every pumpkin before time runs out.", "color": Color(1.0, 0.45, 0.05)},
	{"name": "Haunted Maze", "scene": "res://scenes/hw_haunted_maze/hw_haunted_maze.tscn", "desc": "Escape a maze that rearranges itself.", "color": Color(0.3, 0.6, 0.2)},
	{"name": "Web Slingshot", "scene": "res://scenes/hw_web_slingshot/hw_web_slingshot.tscn", "desc": "Slingshot through giant spider webs.", "color": Color(0.8, 0.8, 0.9)},
	{"name": "Potion Mix", "scene": "res://scenes/hw_potion_mix/hw_potion_mix.tscn", "desc": "Brew the perfect potion - don't blow up the lab.", "color": Color(0.4, 0.9, 0.3)},
	{"name": "Zombie Defense", "scene": "res://scenes/hw_zombie_defense/hw_zombie_defense.tscn", "desc": "Barricade your room against the horde.", "color": Color(0.5, 0.9, 0.2)},
	{"name": "Skeleton Dance", "scene": "res://scenes/hw_skeleton_dance/hw_skeleton_dance.tscn", "desc": "Match the skeleton's dance moves.", "color": Color(0.9, 0.9, 0.85)},
	{"name": "Broom Flight", "scene": "res://scenes/hw_broom_flight/hw_broom_flight.tscn", "desc": "Race broomsticks through the night sky.", "color": Color(0.6, 0.3, 1.0)},
	{"name": "Monster Mash", "scene": "res://scenes/hw_monster_mash/hw_monster_mash.tscn", "desc": "Dance-battle classic movie monsters.", "color": Color(0.7, 0.2, 0.9)},
	{"name": "Candy Stack", "scene": "res://scenes/hw_candy_stack/hw_candy_stack.tscn", "desc": "Stack candy as high as physics allows.", "color": Color(1.0, 0.7, 0.1)},
	{"name": "Mummy Wrap", "scene": "res://scenes/hw_mummy_wrap/hw_mummy_wrap.tscn", "desc": "Wrap the mummy before it wakes up.", "color": Color(0.85, 0.8, 0.65)},
	{"name": "Bat Dodge", "scene": "res://scenes/hw_bat_dodge/hw_bat_dodge.tscn", "desc": "Dodge swooping bats in your hallway.", "color": Color(0.35, 0.1, 0.5)},
	{"name": "Pumpkin Carve", "scene": "res://scenes/hw_pumpkin_carve/hw_pumpkin_carve.tscn", "desc": "Carve jack-o'-lanterns with light.", "color": Color(1.0, 0.55, 0.0)},
	{"name": "Portrait Gallery", "scene": "res://scenes/hw_portrait_gallery/hw_portrait_gallery.tscn", "desc": "Portraits whose eyes follow you. Creepy.", "color": Color(0.5, 0.2, 0.6)},
	{"name": "Werewolf Howl", "scene": "res://scenes/hw_werewolf_howl/hw_werewolf_howl.tscn", "desc": "Howl in tune to wake the pack.", "color": Color(0.4, 0.5, 1.0)},
	{"name": "Hayride Shooter", "scene": "res://scenes/hw_hayride_shooter/hw_hayride_shooter.tscn", "desc": "Shoot targets from a rolling hayride.", "color": Color(1.0, 0.6, 0.15)},
	{"name": "Apple Bobbing", "scene": "res://scenes/hw_apple_bobbing/hw_apple_bobbing.tscn", "desc": "Bob for apples, AR style.", "color": Color(0.9, 0.15, 0.2)},
	{"name": "Phantom Piano", "scene": "res://scenes/hw_phantom_piano/hw_phantom_piano.tscn", "desc": "Play a piano that plays itself back.", "color": Color(0.75, 0.6, 1.0)},
	{"name": "Goblin Archery", "scene": "res://scenes/hw_goblin_archery/hw_goblin_archery.tscn", "desc": "Outshoot goblins in the dark forest.", "color": Color(0.2, 0.8, 0.3)},
	{"name": "Haunted Mirror Maze", "scene": "res://scenes/hw_mirror_maze/hw_mirror_maze.tscn", "desc": "A mirror maze full of lying reflections.", "color": Color(0.6, 0.9, 1.0)},
	{"name": "Witch Hat Toss", "scene": "res://scenes/hw_hat_toss/hw_hat_toss.tscn", "desc": "Toss rings onto the witch hats.", "color": Color(0.55, 0.25, 0.9)},
	{"name": "Monster Feed", "scene": "res://scenes/hw_monster_feed/hw_monster_feed.tscn", "desc": "Feed the monster before it feeds on you.", "color": Color(0.3, 1.0, 0.4)},
	{"name": "Midnight Survival", "scene": "res://scenes/hw_midnight_survival/hw_midnight_survival.tscn", "desc": "Survive until dawn in the haunted house.", "color": Color(0.15, 0.1, 0.35)},
]

## v0.9.0 Launcher 2.1 category accents (kept for the in-game title card
## tint + MoodLUT tab mapping only — the launcher itself is category-free).
const CAT_SKINS := [
	{"edge": Color(1.0, 0.25, 0.85), "tab": Color(0.45, 0.08, 0.32), "glow": Color(1.0, 0.45, 0.95)},
	{"edge": Color(0.35, 0.85, 1.0), "tab": Color(0.08, 0.28, 0.42), "glow": Color(0.55, 0.92, 1.0)},
	{"edge": Color(1.0, 0.65, 0.25), "tab": Color(0.42, 0.22, 0.08), "glow": Color(1.0, 0.8, 0.45)},
	{"edge": Color(0.7, 0.3, 1.0), "tab": Color(0.26, 0.1, 0.42), "glow": Color(1.0, 0.55, 0.15)},
]

# v0.9.3 flat palette (Design Director: constants only, StyleBoxFlat, zero
# radius, opaque; magenta used sparingly).
const COL_BG := Color(0.039, 0.055, 0.102)        # #0A0E1A
const COL_PANEL := Color(0.071, 0.094, 0.169)     # #12182B
const COL_TEXT := Color(0.910, 0.957, 1.0)        # #E8F4FF
const COL_ACCENT := Color(0.0, 0.941, 1.0)        # #00F0FF
const COL_MAGENTA := Color(1.0, 0.169, 0.839)     # #FF2BD6
const COL_DIM := Color(0.561, 0.639, 0.749)       # #8FA3BF
const COL_DARK_TEXT := Color(0.0, 0.075, 0.094)   # #001318

const VP_SIZE := Vector2(1600, 1000)
const QUAD_SIZE := Vector2(1.6, 1.0)  # v0.9.3: was 2.4x1.5 (the photo bug)
const PANEL_DISTANCE := 2.0  # DO NOT CHANGE (Headset Specialist: math verified)
const MIN_PANEL_DIST := 0.8  # emergency push-out threshold (m)
const REFRAME_ANGLE_DEG := 30.0  # off-axis recenter threshold (deg)
const GAZE_DWELL_TIME := 1.2  # seconds of gaze hover before dwell-select fires
const GAZE_HINT_DELAY_MSEC := 10000  # no input this long -> show the gaze hint
const STATUS_REFRESH := 0.5  # diagnostics + auto-frame tick interval (s)
const SETTINGS_PATH := "user://nexus_settings.cfg"
const ROOM_KIT_PATH := "res://scripts/shared/room_kit.gd"
const DIAG_PING_URL := "https://nexus-log-relay.brio-00c.workers.dev/report"
const ROW_H := 64.0
const ROW_SEP := 8.0
const CLICK_DEDUPE_MSEC := 120
const CLICK_DEDUPE_PX := 8.0
const SCROLL_REPEAT_DELAY := 0.12  # hold-to-repeat step interval (s)
const SCROLL_REPEAT_ROWS := 3

var _current_game: Node = null

# v0.9.2: current game identity for Next/Prev nav + telemetry.
var _current_game_name := ""
var _current_game_index := -1
var _master_games: Array = []  # CAT_GAMES + CAT_UTILITIES + CAT_CREATE + CAT_THEMES
var _scene_tab := {}  # scene path -> category index 0..3 (MoodLUT + title tint)

var _panel_root: Node3D = null
var _viewport: SubViewport = null
var _quad: MeshInstance3D = null
var _game_scroll: ScrollContainer = null
var _game_list: VBoxContainer = null
var _game_buttons: Array[Button] = []
var _scroll_up: Button = null
var _scroll_down: Button = null
var _scroll_dir := 0
var _scroll_accum := 0.0
var _updater: UpdateChecker = null
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
var _direct_input: DirectUIInput = null
var _controllers: Array[XRController3D] = []
var _xr_origin: Node3D = null
var _menu_prev := {}
# v0.8.0 input-hardening state.
var _xr_camera: Camera3D = null
var _gaze_reticle: MeshInstance3D = null
var _gaze_reticle_mat: StandardMaterial3D = null
var _diag_label: Label = null
var _input_hint: Label = null
var _test_btn: Button = null
var _conn_label: Label = null
var _version_badge: Label = null
var _menu_open_msec := 0
var _last_input_msec := 0
var _hint_shown := false
var _gaze_hover: Control = null
var _gaze_dwell := 0.0
var _status_accum := 0.0
var _trigger_prev := {}
var _recenter_timer: Timer = null
# v0.9.3 staged boot + click dedupe + diagnostics.
var _stage := 0
var _boot_msec := 0
var _first_frame_msec := 0
var _last_click_msec := 0
var _last_click_pos := Vector2.INF
var _no_beam_since_msec := 0
var _ping_http: HTTPRequest = null
var _ping_timer: Timer = null
var _ping_in_flight := false


# ------------------------------------------------------------ staged boot ---

func _ready() -> void:
	# STAGE 0 (synchronous): panel + quad + LOADING label only. First frame
	# must land <2s after process start — no textures, no shaders, no audio,
	# no list building here.
	_boot_msec = Time.get_ticks_msec()
	_build_panel()
	_build_stage0_ui()
	RenderingServer.frame_post_draw.connect(_on_first_frame, CONNECT_ONE_SHOT)
	call_deferred("_stage1")


func _on_first_frame() -> void:
	_first_frame_msec = Time.get_ticks_msec()
	BugReporter.add_breadcrumb("first_frame")


## STAGE 1 (first idle frame): the real launcher UI + input rigs.
func _stage1() -> void:
	if _stage >= 1:
		return
	_stage = 1
	_build_ui()
	_build_pointers()
	_cache_xr_camera()
	_build_gaze_reticle()
	_on_menu_open()
	# One-shot re-settle: the HMD pose is often still identity during _ready,
	# so re-align the panel once tracking has had a moment to come up.
	_recenter_timer = Timer.new()
	_recenter_timer.name = "RecenterSettle"
	_recenter_timer.wait_time = 0.75
	_recenter_timer.one_shot = true
	_recenter_timer.timeout.connect(_recenter_panel)
	add_child(_recenter_timer)
	_recenter_timer.start()
	# Crash reporter: offer to send the previous session's log.
	var crash: Dictionary = BugReporter.prompt_if_crash_pending()
	if not crash.is_empty():
		_show_crash_prompt(crash)
	BugReporter.session_start("hub")
	call_deferred("_stage2")


## STAGE 2 (idle, low priority): music, updater node (button-driven checks
## only — no auto-check at boot), telemetry warmup.
func _stage2() -> void:
	if _stage >= 2:
		return
	_stage = 2
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_music("menu_theme")
	_setup_updater()
	# Deferred one frame so Main._ready has initialized OpenXR first (child
	# _ready runs before the parent's) and trackers are registered.
	_log_xr_input_inventory()


func _process(delta: float) -> void:
	var xr := get_viewport().use_xr
	for p in _pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
	if _direct_input != null and is_instance_valid(_direct_input):
		_direct_input.xr_mode = xr
	if is_instance_valid(_gaze_reticle) and not xr:
		_gaze_reticle.visible = false
	_process_status(delta)
	_process_scroll_repeat(delta)
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
	# typing "h"/"H" in a text field types the letter instead of kicking back
	# to the hub. The controller menu button is polled separately in
	# _poll_controller_buttons().
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
	# Stops rendering while hidden during gameplay (perf); the ViewportTexture
	# resumes on show.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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


## Stage-0 placeholder: flat BG + LOADING label so frame 1 is never black.
func _build_stage0_ui() -> void:
	var root := Control.new()
	root.name = "Stage0UI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var lab := Label.new()
	lab.text = "LOADING…"
	lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 64)
	lab.add_theme_color_override("font_color", COL_DIM)
	root.add_child(lab)


# ------------------------------------------------------------------ UI ---

func _build_ui() -> void:
	# Drop the stage-0 placeholder.
	for c in _viewport.get_children():
		_viewport.remove_child(c)
		c.queue_free()
	var root := Control.new()
	root.name = "UI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)

	var bg := ColorRect.new()
	bg.color = COL_BG
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

	# Header: title + version badge (the debugging lifeline — wade reads it
	# back from the headset).
	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 28)
	vbox.add_child(header)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "NEXUS ARCADE — built by Muse"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", COL_ACCENT)
	header.add_child(title)
	_version_badge = Label.new()
	_version_badge.name = "VersionBadge"
	_version_badge.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.9.3"))
	_version_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_version_badge.add_theme_font_size_override("font_size", 20)
	_version_badge.add_theme_color_override("font_color", COL_DIM)
	header.add_child(_version_badge)

	# The list: ScrollContainer + 75 flat rows + explicit hold-to-repeat
	# scroll buttons (robust with injected input; synthetic clicks are
	# press+release same-frame so they can't drag-scroll).
	var list_frame := PanelContainer.new()
	list_frame.name = "ListFrame"
	list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lfsb := StyleBoxFlat.new()
	lfsb.bg_color = COL_PANEL
	lfsb.set_corner_radius_all(0)
	list_frame.add_theme_stylebox_override("panel", lfsb)
	vbox.add_child(list_frame)
	var list_hbox := HBoxContainer.new()
	list_hbox.add_theme_constant_override("separation", 12)
	list_frame.add_child(list_hbox)
	_game_scroll = ScrollContainer.new()
	_game_scroll.name = "GameScroll"
	_game_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_hbox.add_child(_game_scroll)
	_game_list = VBoxContainer.new()
	_game_list.name = "GameList"
	_game_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_list.add_theme_constant_override("separation", int(ROW_SEP))
	_game_scroll.add_child(_game_list)
	_build_list_rows()
	var scroll_col := VBoxContainer.new()
	scroll_col.name = "ScrollCol"
	scroll_col.add_theme_constant_override("separation", 12)
	list_hbox.add_child(scroll_col)
	_build_scroll_buttons(scroll_col)

	# Kept chrome: Check for Updates (prominent) + Room setup.
	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	vbox.add_child(button_row)
	var update_btn := _make_button("CHECK FOR UPDATES", "UpdateButton", 30, COL_ACCENT.darkened(0.55))
	update_btn.custom_minimum_size = Vector2(480, 80)
	update_btn.pressed.connect(_on_update_button)
	button_row.add_child(update_btn)
	_update_status = Label.new()
	_update_status.name = "UpdateStatus"
	_update_status.add_theme_font_size_override("font_size", 22)
	_update_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_update_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button_row.add_child(_update_status)
	var room_btn := _make_button("Room setup", "RoomButton", 24, Color(0.2, 0.35, 0.25))
	room_btn.pressed.connect(_show_room_flow)
	button_row.add_child(room_btn)

	# Diagnostics line (ship-blocker): input state in plain words + boot +
	# panel readouts. Refreshed every STATUS_REFRESH seconds.
	_diag_label = Label.new()
	_diag_label.name = "DiagInput"
	_diag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diag_label.add_theme_font_size_override("font_size", 24)
	_diag_label.add_theme_color_override("font_color", COL_TEXT)
	_diag_label.text = "Starting..."
	vbox.add_child(_diag_label)

	# Connection self-test: POSTs a tiny ping to the relay; Brio's side can
	# watch the relay for it as device-egress ground truth.
	var conn_row := HBoxContainer.new()
	conn_row.name = "ConnRow"
	conn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	conn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(conn_row)
	_test_btn = _make_button("Test connection", "TestConnection", 24, Color(0.16, 0.32, 0.22))
	_test_btn.pressed.connect(_on_test_connection)
	conn_row.add_child(_test_btn)
	_conn_label = Label.new()
	_conn_label.name = "ConnLabel"
	_conn_label.text = "Connection: not tested"
	_conn_label.add_theme_font_size_override("font_size", 24)
	_conn_label.add_theme_color_override("font_color", COL_DIM)
	_conn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conn_row.add_child(_conn_label)

	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "Point the laser and pull the trigger"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", COL_DIM)
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
	normal.set_corner_radius_all(0)
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
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## The 75-game flat list in MASTER order (CAT_GAMES + CAT_UTILITIES +
## CAT_CREATE + CAT_THEMES — the same order the pause menu's Next/Prev
## walks). Each row: "Name — built by Muse" + one-line desc, 64px flat.
## Selection = instant row bg→accent + dark text swap, no tween.
func _build_list_rows() -> void:
	_game_buttons.clear()
	var games := _master_game_list()
	for i in games.size():
		var game: Dictionary = games[i]
		var nm := str(game.get("name", "?"))
		var b := Button.new()
		b.name = "Game_%d" % i
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var normal := StyleBoxFlat.new()
		normal.bg_color = COL_PANEL
		normal.set_corner_radius_all(0)
		b.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = COL_ACCENT
		b.add_theme_stylebox_override("hover", hover)
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = COL_ACCENT.darkened(0.2)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var inner := MarginContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.add_theme_constant_override("margin_left", 24)
		inner.add_theme_constant_override("margin_right", 24)
		b.add_child(inner)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 2)
		inner.add_child(vb)
		var name_lbl := Label.new()
		name_lbl.text = nm
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_font_size_override("font_size", 36)
		name_lbl.add_theme_color_override("font_color", COL_ACCENT)
		name_lbl.clip_text = true
		name_lbl.max_lines_visible = 1
		vb.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = str(game.get("desc", ""))
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.add_theme_font_size_override("font_size", 24)
		desc_lbl.add_theme_color_override("font_color", COL_DIM)
		desc_lbl.clip_text = true
		desc_lbl.max_lines_visible = 1
		vb.add_child(desc_lbl)
		b.pressed.connect(_load_game.bind(str(game.get("scene", "")), nm))
		b.mouse_entered.connect(_on_row_hover.bind(name_lbl, desc_lbl, true))
		b.mouse_exited.connect(_on_row_hover.bind(name_lbl, desc_lbl, false))
		_game_list.add_child(b)
		_game_buttons.append(b)


func _on_row_hover(name_lbl: Label, desc_lbl: Label, hovering: bool) -> void:
	if not is_instance_valid(name_lbl) or not is_instance_valid(desc_lbl):
		return
	name_lbl.add_theme_color_override(
		"font_color", COL_DARK_TEXT if hovering else COL_ACCENT)
	desc_lbl.add_theme_color_override(
		"font_color", COL_DARK_TEXT if hovering else COL_DIM)


func _build_scroll_buttons(col: VBoxContainer) -> void:
	_scroll_up = _make_scroll_btn("▲", -1)
	col.add_child(_scroll_up)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_scroll_down = _make_scroll_btn("▼", 1)
	col.add_child(_scroll_down)


func _make_scroll_btn(text: String, dir: int) -> Button:
	var b := Button.new()
	b.name = "ScrollUp" if dir < 0 else "ScrollDown"
	b.text = text
	b.custom_minimum_size = Vector2(120, 120)
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_color_override("font_color", COL_ACCENT)
	b.add_theme_color_override("font_hover_color", COL_DARK_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(0)
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = COL_ACCENT
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# button_down/up (not pressed): injected clicks are press+release in the
	# same frame, so tap = one step; a real hold repeats in _process.
	b.button_down.connect(_on_scroll_press.bind(dir))
	b.button_up.connect(_on_scroll_release)
	return b


func _on_scroll_press(dir: int) -> void:
	_scroll_dir = dir
	_scroll_accum = 0.0
	_scroll_step(dir, 1)


func _on_scroll_release() -> void:
	_scroll_dir = 0


func _scroll_step(dir: int, rows: int) -> void:
	if _game_scroll == null or not is_instance_valid(_game_scroll):
		return
	_game_scroll.scroll_vertical += dir * (ROW_H + ROW_SEP) * rows


func _process_scroll_repeat(delta: float) -> void:
	if _scroll_dir == 0 or not _panel_visible():
		return
	_scroll_accum += delta
	while _scroll_accum >= SCROLL_REPEAT_DELAY:
		_scroll_accum -= SCROLL_REPEAT_DELAY
		_scroll_step(_scroll_dir, SCROLL_REPEAT_ROWS)


# ------------------------------------------------------------- game data ---

## Canonical ordered list of ALL experiences: CAT_GAMES + CAT_UTILITIES +
## CAT_CREATE + CAT_THEMES (flat, no dividers). This is the launcher list
## AND the pause menu's Next/Previous order — one order, one mental model.
func _master_game_list() -> Array:
	if _master_games.is_empty():
		_master_games.append_array(CAT_GAMES)
		_master_games.append_array(CAT_UTILITIES)
		_master_games.append_array(CAT_CREATE)
		_master_games.append_array(CAT_THEMES)
		var tab := 0
		for lst in [CAT_GAMES, CAT_UTILITIES, CAT_CREATE, CAT_THEMES]:
			for g in lst:
				_scene_tab[str((g as Dictionary).get("scene", ""))] = tab
			tab += 1
	return _master_games


## Category index of a game's scene path (0..3) — replaces the old launcher
## tab state for MoodLUT + title-card accent (correct even when Next/Prev
## switches into a game from a different category).
func _tab_of(scene_path: String) -> int:
	_master_game_list()
	return int(_scene_tab.get(scene_path, 0))


func _master_index_of(scene_path: String) -> int:
	var games := _master_game_list()
	for i in games.size():
		if str((games[i] as Dictionary).get("scene", "")) == scene_path:
			return i
	return -1


## Switch to the adjacent game from the pause menu (delta -1 = prev,
## +1 = next). Wraps around at the ends. Routes through _load_game so
## autowiring, music, sessions and telemetry run identically to a launcher
## launch.
func _switch_game(delta: int) -> void:
	var games := _master_game_list()
	if games.is_empty() or _current_game_index < 0:
		return
	var n := games.size()
	var next_idx := (_current_game_index + delta + n) % n
	var g: Dictionary = games[next_idx]
	_load_game(str(g["scene"]), str(g["name"]), "next" if delta > 0 else "prev")


## Category accent color (title-card tint).
func _skin_accent(tab: int) -> Color:
	return CAT_SKINS[clampi(tab, 0, 3)]["edge"]


## One-line description for the title card, from the inline CAT_* descs
## (v0.9.3: hub_extras' master table is gone — no boot cost).
func _game_desc(game_name: String) -> String:
	for g in _master_game_list():
		var gd: Dictionary = g
		if str(gd.get("name", "")) == game_name:
			return str(gd.get("desc", ""))
	return ""


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
	# Hand pointers: XRUIPointer discovers its XRHandTracker lazily via the
	# shared static hand_ray(), so hands that appear later (tracking
	# starts/stops) are picked up automatically.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.name = "PointerHand%d" % side
		hp.hand_side = side
		hp.setup(_viewport, _quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked)
		hp.xr_moved.connect(_on_pointer_moved)
		_panel_root.add_child(hp)
		_pointers.append(hp)
	# Belt-and-suspenders: the DirectUIInput fallback runs the same raycasts
	# from RAW tracker poses every frame, independent of the signal path
	# above, and draws its own yellow beams. Both paths stay live; the
	# dedupe window in inject_click() keeps them from double-firing.
	_direct_input = DirectUIInput.new()
	_direct_input.name = "DirectInput"
	_panel_root.add_child(_direct_input)
	_direct_input.configure(_viewport, _quad, _xr_origin,
		_fallback_moved, _fallback_clicked)


func _on_pointer_moved(viewport_pos: Vector2) -> void:
	_note_input_event()
	inject_motion(viewport_pos)


func _on_pointer_clicked(viewport_pos: Vector2) -> void:
	_note_input_event()
	inject_click(viewport_pos)


func _fallback_moved(viewport_pos: Vector2) -> void:
	_note_input_event()
	inject_motion(viewport_pos)


func _fallback_clicked(viewport_pos: Vector2) -> void:
	_note_input_event()
	inject_click(viewport_pos)


func inject_motion(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = viewport_pos
	_viewport.push_input(ev)


## THE single injection point for clicks: the XRUIPointer signal path and
## the DirectUIInput fallback both funnel here. A 120ms / 8px dedupe window
## prevents the dual paths from double-firing the same press.
func inject_click(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_click_msec < CLICK_DEDUPE_MSEC \
			and viewport_pos.distance_to(_last_click_pos) < CLICK_DEDUPE_PX:
		return
	_last_click_msec = now
	_last_click_pos = viewport_pos
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


## True when ANY beam (primary XRUIPointer or DirectUIInput fallback) is
## actually drawn right now. The gaze fallback keys on this — never on
## tracker registration — so a registered-but-useless tracker can't leave
## the user with invisible lasers AND no gaze reticle.
func _any_beam_drawn() -> bool:
	for p in _pointers:
		if is_instance_valid(p) and p.is_beam_visible():
			return true
	if _direct_input != null and is_instance_valid(_direct_input) \
			and _direct_input.any_beam_visible():
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


## Called on every menu open: initial stage 1 and _return_to_hub. Resets the
## input-event clock, hides the hint, and yaw-aligns the panel to the user's
## LIVE camera pose (never a stale one).
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


## Fresh camera, validated every call; falls back to the cached XR camera.
func _live_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam != null and is_instance_valid(cam):
		return cam
	if _xr_camera != null and is_instance_valid(_xr_camera):
		return _xr_camera
	return null


## Yaw-align the panel so it faces the user's current camera forward
## direction at PANEL_DISTANCE (2.0m — the distance constant is verified
## correct; the v0.9.2 defect was placement LIFECYCLE, fixed by calling this
## on every menu open + the 0.5s _auto_frame_panel() guard).
func _recenter_panel() -> void:
	if _panel_root == null or not is_instance_valid(_panel_root):
		return
	var cam := _live_camera()
	if cam == null:
		_panel_root.position = Vector3(0, 1.6, -PANEL_DISTANCE)
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


## 0.5s guard while the launcher is visible (runs inside _process_status):
## if the user walked INTO the panel (<0.8m) push it back out to 1.5m; if
## the panel drifted >30deg off-axis, recenter. Never pulls closer.
func _auto_frame_panel() -> void:
	if not _panel_visible():
		return
	var cam := _live_camera()
	if cam == null:
		return
	var cam_pos := cam.global_position
	var center := _panel_root.global_position
	var to_panel := center - cam_pos
	var d := to_panel.length()
	if d < MIN_PANEL_DIST:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.05:
			fwd = Vector3(0, 0, -1)
		fwd = fwd.normalized()
		var target := cam_pos + fwd * 1.5
		target.y = clampf(cam_pos.y, 1.1, 1.75)
		_panel_root.global_position = target
		BugReporter.add_breadcrumb("panel_pushout")
		return
	if d > 0.001:
		var fwd3 := -cam.global_transform.basis.z.normalized()
		var ang := rad_to_deg(fwd3.angle_to(to_panel / d))
		if ang > REFRAME_ANGLE_DEG:
			_recenter_panel()
			BugReporter.add_breadcrumb("panel_reframe")


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
		# autoload now (pause overlay -> Exit to Launcher). The hub no longer
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
	# v0.9.3 fix: pinned to the camera-center ray ON the panel surface
	# (2.0m out). The old code sat it 0.4m in front of the panel; and it now
	# keys on "no beam actually drawn" (see _gaze_should_run), never on
	# tracker registration.
	_gaze_reticle.position = Vector3(0, 0, -PANEL_DISTANCE)
	_gaze_reticle.visible = false
	_xr_camera.add_child(_gaze_reticle)


## The gaze fallback runs only when NO beam is actually drawn by either the
## primary pointers or the DirectUIInput fallback, so it never fights the
## lasers for hover — and a registered-but-useless tracker can no longer
## suppress it (the v0.9.2 photo state: no lasers AND no reticle).
func _gaze_should_run() -> bool:
	if not get_viewport().use_xr:
		return false
	if not _panel_visible():
		return false
	return not _any_beam_drawn()


func _process_gaze(delta: float) -> void:
	var ret := _gaze_reticle
	if ret == null or not is_instance_valid(ret):
		return
	var active := _gaze_should_run()
	ret.visible = active
	if not active:
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	var cam := _live_camera()
	if cam == null or _quad == null:
		return
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z.normalized()
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
	if not _gaze_should_run():
		return
	var cam := _live_camera()
	if cam == null or _quad == null:
		return
	var hit := XRUIPointer.ray_to_viewport(
		cam.global_position,
		-cam.global_transform.basis.z.normalized(),
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
	if is_instance_valid(_diag_label):
		_diag_label.text = _diag_text()
	# The panel auto-frame guard rides the same 0.5s tick.
	_auto_frame_panel()


## On-screen diagnostics (ship-blocker): input state in plain words, a
## self-test warning when nothing is live, boot timing, and a live readout
## (live tracker count, pointer count, panel distance). wade reads this back
## from the headset instead of us guessing.
func _diag_text() -> String:
	var xr := get_viewport().use_xr
	var ctl_l := _controller_tracked("Left")
	var ctl_r := _controller_tracked("Right")
	var hands := XRUIPointer.find_hand_trackers()
	var hl := hands["left"] != null and (hands["left"] as XRHandTracker).has_tracking_data
	var hr := hands["right"] != null and (hands["right"] as XRHandTracker).has_tracking_data
	var ctl_txt := "none"
	if ctl_l and ctl_r:
		ctl_txt = "L+R live"
	elif ctl_l:
		ctl_txt = "L live"
	elif ctl_r:
		ctl_txt = "R live"
	var hand_txt := "none"
	if hl and hr:
		hand_txt = "L+R"
	elif hl:
		hand_txt = "L"
	elif hr:
		hand_txt = "R"
	var gaze_txt := "off (desktop mouse active)"
	if xr:
		gaze_txt = "standby" if _any_beam_drawn() else "ready"
	var line1 := "Controllers: %s · Hands: %s · Gaze: %s" % [ctl_txt, hand_txt, gaze_txt]
	# Live readout: pointer count + panel distance.
	var ptrs := 0
	for p in _pointers:
		if is_instance_valid(p) and p.is_source_live():
			ptrs += 1
	var dist_txt := "?"
	var cam := _live_camera()
	if cam != null and _panel_root != null and is_instance_valid(_panel_root):
		dist_txt = "%.1fm" % cam.global_position.distance_to(_panel_root.global_position)
	var boot_txt := "booting…"
	if _first_frame_msec > 0:
		boot_txt = "first frame %.1fs" % ((_first_frame_msec - _boot_msec) / 1000.0)
	var line2 := "Ptrs: %d · Panel: %s · Boot: %s" % [ptrs, dist_txt, boot_txt]
	# Self-test: no beam drawn for >3s on-device = the photo state.
	var warn := ""
	if xr and _panel_visible():
		var now := Time.get_ticks_msec()
		if not _any_beam_drawn():
			if _no_beam_since_msec == 0:
				_no_beam_since_msec = now
			elif now - _no_beam_since_msec > 3000:
				warn = "\n⚠ NO INPUT SOURCE LIVE — look at a button and hold 1.2s"
		else:
			_no_beam_since_msec = 0
	return line1 + "\n" + line2 + warn


# ------------------------------------------------- connection self-test ---

## "Test connection" button: POSTs a tiny JSON ping to the relay (8s
## timeout, non-blocking, own HTTPRequest — never BugReporter's shared one)
## and shows SUCCESS / FAILED on screen. Brio's side can watch the relay
## for the ping as device-egress ground truth.
func _on_test_connection() -> void:
	if _ping_in_flight:
		return
	_ping_in_flight = true
	_test_btn.disabled = true
	_conn_label.text = "Connection: testing..."
	if _ping_http == null:
		_ping_http = HTTPRequest.new()
		_ping_http.name = "DiagPingHTTP"
		add_child(_ping_http)
		_ping_http.request_completed.connect(_on_ping_completed)
	if _ping_timer == null:
		_ping_timer = Timer.new()
		_ping_timer.wait_time = 8.0
		_ping_timer.one_shot = true
		_ping_timer.timeout.connect(_on_ping_timeout)
		add_child(_ping_timer)
	_ping_timer.start()
	var payload := {
		"type": "diag_ping",
		"app": "nexus-arcade",
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"ts": Time.get_unix_time_from_system(),
		"input": _diag_text(),
	}
	var err := _ping_http.request(DIAG_PING_URL,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_on_ping_done(false, "start failed")


func _on_ping_timeout() -> void:
	if _ping_in_flight:
		_on_ping_done(false, "timeout")


func _on_ping_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if not _ping_in_flight:
		return
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	_on_ping_done(ok, "" if ok else "code %d" % response_code)


func _on_ping_done(ok: bool, detail: String) -> void:
	_ping_in_flight = false
	if _ping_timer != null:
		_ping_timer.stop()
	if is_instance_valid(_test_btn):
		_test_btn.disabled = false
	if is_instance_valid(_conn_label):
		_conn_label.text = "Connection: SUCCESS" if ok \
			else "Connection: FAILED (%s)" % detail


# --------------------------------------------------------- game load ---

func _load_game(scene_path: String, game_name: String, via: String = "launcher") -> void:
	BugReporter.session_start(game_name)
	if get_node_or_null("/root/GameplayTelemetry") != null:
		GameplayTelemetry.game_start(game_name, via, _master_index_of(scene_path))
	if _current_game != null and is_instance_valid(_current_game):
		_current_game.queue_free()
		_current_game = null
	_current_game_name = game_name
	_current_game_index = _master_index_of(scene_path)
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
		if get_node_or_null("/root/GameplayTelemetry") != null:
			GameplayTelemetry.error(game_name, "scene load failed", scene_path)
		if is_instance_valid(_panel_root):
			_panel_root.visible = true


## v0.9.0 global auto-wirer (opt-OUT): every launched game automatically
## gets genre music, a passthrough mood grade, a title-card sting, and an
## affordance pass — the shared systems no game ever called are now alive
## by default. A game opts out with `static var no_auto_wire := true`.
func _autowire_game(scene_path: String, game_name: String) -> void:
	var stem := scene_path.get_file().get_basename()
	var tab := _tab_of(scene_path)
	# 1. Genre music (activates the dormant GENRE_FOR_SCENE map).
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_active_scene(stem)
		AudioKit.set_intensity(0)
		AudioKit.play_music_for_scene(stem)
	# 2. Passthrough mood grade (haunted green for THEMES, deep teal for
	# dive/aquarium, natural everywhere else).
	if get_node_or_null("/root/MoodLUT") != null:
		MoodLUT.apply_for_game(stem, tab)
	# 3. Juice: title card + affordance pass. The no_auto_wire opt-out skips
	# this and the controller-skin dressing — but NEVER the pause/exit below.
	if _current_game == null or not is_instance_valid(_current_game):
		return
	var opted_out := _game_opt_out()
	if not opted_out and get_node_or_null("/root/JuiceFX") != null:
		JuiceFX.title_card(game_name, _game_desc(game_name), _skin_accent(tab))
		JuiceFX.affordance_pass(_current_game)
	# 4. Global pause/exit (ship-blocker) + controller skins + button legend.
	# PauseExit attaches UNCONDITIONALLY, even for no_auto_wire games: the
	# standing rule is every game exits to launcher. (v0.9.1 verification:
	# the old early-return skipped this whole block for opt-out games, which
	# would have silently dropped their exit path entirely.)
	if get_node_or_null("/root/PauseExit") != null:
		PauseExit.attach_to_game(
			_current_game, _return_to_hub,
			_load_game.bind(scene_path, game_name, "restart"),
			game_name)
		# v0.9.2: Next/Previous navigation in the pause menu — ordered game
		# names + current index + the hub's wrap-around switch callable.
		var nav_names := PackedStringArray()
		for g in _master_game_list():
			nav_names.append(str((g as Dictionary).get("name", "?")))
		PauseExit.set_game_nav(nav_names, _current_game_index, _switch_game)
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


func _return_to_hub() -> void:
	BugReporter.session_end()
	if get_node_or_null("/root/GameplayTelemetry") != null:
		GameplayTelemetry.game_end("quit_to_hub")
	if get_node_or_null("/root/PauseExit") != null:
		PauseExit.detach()
	_current_game_name = ""
	_current_game_index = -1
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
	if _updater == null:
		# Stage 2 hasn't run yet (one idle frame after the UI builds).
		_update_status.text = "Still starting… try again."
		return
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

## Room setup is BUTTON-ONLY in v0.9.3 (no first-run auto-popup): wade
## taps "Room setup" when he wants it.
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

func get_game_button(list_index: int) -> Button:
	if list_index >= 0 and list_index < _game_buttons.size():
		return _game_buttons[list_index]
	return null


func get_current_game() -> Node:
	return _current_game


func dismiss_room_dialog() -> void:
	if is_instance_valid(_room_dialog):
		_room_dialog.visible = false
