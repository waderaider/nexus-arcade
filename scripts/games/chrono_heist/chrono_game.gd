## ChronoGame.gd - CHRONO HEIST: 60-second time-loop bank job.
## Your crew is recordings of yourself. 4 loops: keycard -> safe -> loot ->
## escape. Bumping your own ghost causes paradox static (-3s). The vault
## overlays your room (safe on your wall, tripwires across the room).
extends Node3D
class_name ChronoGame

## v0.11.0: combat pause profile — hands are always busy; the floating
## pause glyph hides and the menu button needs a 0.45s hold.
static var pause_profile := "combat"

const STEM := "chrono_heist"
const LOOP_SECS := 60.0
const MAX_LOOPS := 4
const PARADOX_DIST := 0.5
const PARADOX_COST := 3.0
const TRIP_COST := 5.0

var controller_config := {
	"buttons": {
		"trigger": "Grab / release",
		"grip": "Grab (alt hand)",
		"thumbstick": "—",
	}
}

var _state := "intro"  # intro | loop | secured | recap | won | lost
var _state_t := 0.0
var _loop_idx := 0
var _loop_t := 0.0
var _secured := false

var _world: ChronoWorld
var _recorder := ChronoRecorder.new()
var _recordings: Array = []  # finished loop data dicts
var _ghosts: Array = []

var _xr := false
var _origin: Node3D = null
var _cam: Camera3D = null
var _hands := {}  # 0/1 -> XRController3D or virtual Node3D
var _trig_prev := {}
var _hand_hist := {}

var _vhead: Node3D  # virtual head for desktop/headless demo
var _demo_plan: Array = []
var _demo_t := 0.0

var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _paradox_cd := 0.0
var _trip_cd := 0.0
var _flicker: Array = []  # animator: [mat, base, amp, speed, phase]
var _amb_t := 0.0

const OBJECTIVES := [
	"SLOT THE KEYCARD",
	"CRACK THE SAFE",
	"CARRY THE LOOT TO THE EXIT",
	"ESCAPE WITH THE LOOT",
]


func _ready() -> void:
	_register_sfx()
	_find_xr()
	_world = ChronoWorld.new()
	add_child(_world)
	_world.build()
	_world.keycard_slotted.connect(_on_objective_event.bind("slot"))
	_world.safe_opened.connect(_on_objective_event.bind("open"))
	_world.loot_secured.connect(_on_objective_event.bind("loot"))
	_world.escaped.connect(_on_objective_event.bind("escape"))
	add_child(_recorder)
	_build_hud()
	_build_ambient()
	if not _xr:
		_build_virtual_rig()
	_announce_text("CHRONO HEIST\nThe perfect crew doesn't exist \u2014 so you built one.\nLoop 1: grab the keycard. The ghosts handle the rest.", 4.0)
	JuiceFX.title_card("CHRONO HEIST", "Your crew is you. Four loops. Don't touch yourself.", Color(0.95, 0.6, 0.15))


func _register_sfx() -> void:
	if get_node_or_null("/root/AudioKit") == null:
		return
	var d := "res://assets/audio/sfx/"
	AudioKit.set_active_scene(STEM)
	AudioKit.register_game_sfx(STEM, {
		"loopstart": d + "chrono_loopstart.wav",
		"paradox": d + "chrono_paradox.wav",
		"keycard": d + "chrono_keycard.wav",
		"safe": d + "chrono_safe.wav",
		"loot": d + "chrono_loot.wav",
		"alarm": d + "chrono_alarm.wav",
	})


func _find_xr() -> void:
	if get_node_or_null("/root/ARUpgradeKit") != null and ARUpgradeKit.is_xr_active():
		var found := get_tree().root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			_xr = true
			_origin = found[0] as Node3D
			_cam = _origin.get_node_or_null("XRCamera3D") as Camera3D
			_hands[0] = _origin.get_node_or_null("LeftController")
			_hands[1] = _origin.get_node_or_null("RightController")
			if _cam == null:
				_xr = false


## Animator ambient-life set (v0.11.0): vault dust motes, security-camera
## red blink sweep (phase-offset), ghost shimmer (in recorder), paradox
## crackle + loop-reset swirl (transient bursts).
func _build_ambient() -> void:
	# Vault dust motes hanging in the safe-crack light.
	AmbientKit.dust(self, _world.safe_world_pos() + Vector3(0, 0.35, 0.45), 24,
		Color(0.8, 0.86, 1.0, 0.4), 0.018, 0.08, 0.02)
	# Security cameras on the vault wall: red blink sweep.
	var wall := _world.wall_dict()
	if wall.is_empty():
		return
	var n := (wall["normal"] as Vector3).normalized()
	var tangent := n.cross(Vector3.UP).normalized()
	if tangent.length() < 0.1:
		tangent = Vector3.RIGHT
	var c := wall["position"] as Vector3
	for s in [-1.0, 1.0]:
		_build_camera(c + tangent * 1.7 * s + Vector3(0, 1.05, 0) + n * 0.12, c)


func _build_camera(pos: Vector3, look_target: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	root.look_at(look_target)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.09, 0.2)
	body.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.07)
	body.material_override = dark
	root.add_child(body)
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	lens.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1, 0.1, 0.1)
	lm.emission_enabled = true
	lm.emission = Color(1, 0.05, 0.05)
	lm.emission_energy_multiplier = 2.0
	lens.material_override = lm
	lens.position = Vector3(0, 0, -0.11)
	root.add_child(lens)
	_flicker.append([lm, 2.0, 1.7, 2.4, randf() * TAU])


func _process(delta: float) -> void:
	_amb_t += delta
	AmbientKit.tick_flicker(_flicker, _amb_t)


func _build_virtual_rig() -> void:
	_vhead = Node3D.new()
	_vhead.position = Vector3(0, 1.6, 1.5)
	add_child(_vhead)
	for i in [0, 1]:
		var h := Node3D.new()
		h.position = Vector3(-0.3 + 0.6 * i, 1.3, 1.2)
		add_child(h)
		_hands[i] = h


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.font_size = 72
	_hud.pixel_size = 0.004
	_hud.position = Vector3(0, 2.4, -1.0)
	_hud.modulate = Color(1, 0.9, 0.6)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.no_depth_test = true
	_announce.font_size = 110
	_announce.pixel_size = 0.004
	_announce.modulate = Color(0.6, 0.95, 1.0)
	_announce.outline_modulate = Color(0, 0, 0)
	_announce.outline_size = 14
	_announce.visible = false
	add_child(_announce)


func _announce_text(t: String, dur := 2.0) -> void:
	_announce.text = t
	_announce.visible = true
	_announce_t = dur
	var hp := _head_pos()
	_announce.global_position = hp + Vector3(0, 0.25, 0) + _head_fwd() * 1.6


func _head_pos() -> Vector3:
	if _xr and _cam != null:
		return _cam.global_position
	return _vhead.global_position if _vhead != null else Vector3(0, 1.6, 0)


func _head_fwd() -> Vector3:
	if _xr and _cam != null:
		return -_cam.global_transform.basis.z
	return Vector3(0, 0, -1)


func _hand_node(i: int) -> Node3D:
	return _hands.get(i) as Node3D


# ------------------------------------------------------------------ loop ---

func _physics_process(delta: float) -> void:
	if _announce_t > 0:
		_announce_t -= delta
		if _announce_t <= 0:
			_announce.visible = false
	match _state:
		"intro":
			_state_t += delta
			if _state_t > 4.2:
				_start_loop(0)
		"loop":
			_tick_loop(delta)
		"secured":
			_state_t += delta
			_tick_ghosts(delta)
			if _state_t > 4.0:
				_next_loop()
		"recap":
			_state_t += delta
			if _state_t > 3.0:
				_start_loop(_loop_idx + 1)
		"won", "lost":
			pass


func _start_loop(idx: int) -> void:
	_loop_idx = idx
	_loop_t = 0.0
	_secured = false
	_paradox_cd = 0.0
	_trip_cd = 0.0
	# Clear any held objects between loops.
	for i in [0, 1]:
		if _world.held_obj(i) != "":
			_world.release(i, Vector3.ZERO)
	# Spawn ghosts of all previous loops.
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
	for i in _recordings.size():
		var gh := ChronoRecorder.ChronoGhost.new()
		gh.setup(_recordings[i], i)
		add_child(gh)
		_ghosts.append(gh)
	_recorder.start()
	_world.set_tripwires_active(idx >= 2)
	_state = "loop"
	_state_t = 0.0
	# VFX artist: signature loop-reset moment (haptics baked in).
	VFX.loop_reset(self, _head_pos(), 3.0)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("loopstart")
		AudioKit.set_intensity(1)  # audio director §4d: tense
	_announce_text("LOOP %d / %d\n%s" % [idx + 1, MAX_LOOPS, OBJECTIVES[idx]], 2.5)
	if not _xr:
		_plan_demo(idx)
	_update_hud()


func _next_loop() -> void:
	_recordings.append(_recorder.stop())
	if _loop_idx + 1 >= MAX_LOOPS:
		_lose()
	else:
		_state = "recap"
		_state_t = 0.0
		# v0.11.0 VFX: loop reset — time-ripple rings + pale flash + static.
		VFX.loop_reset(self, _head_pos(), 3.0)
		_announce_text("LOOP RESET", 2.0)


func _tick_loop(delta: float) -> void:
	_loop_t += delta
	_paradox_cd = maxf(0.0, _paradox_cd - delta)
	_trip_cd = maxf(0.0, _trip_cd - delta)
	if _xr:
		_tick_xr_hands(delta)
	else:
		_tick_demo(delta)
	_world.update_held()
	_tick_ghosts(delta)
	_tick_paradox()
	_tick_tripwire()
	_check_objective()
	_recorder.record_frame(_head_xf(), _hand_xf(0), _hand_xf(1), delta)
	_update_hud()
	if _loop_t >= LOOP_SECS and not _secured:
		_announce_text("TIME UP", 1.5)
		_next_loop()


func _head_xf() -> Transform3D:
	if _xr and _cam != null:
		return _cam.global_transform
	return _vhead.global_transform if _vhead != null else Transform3D.IDENTITY


func _hand_xf(i: int) -> Transform3D:
	var h := _hand_node(i)
	return h.global_transform if h != null and is_instance_valid(h) else Transform3D.IDENTITY


func _tick_xr_hands(_delta: float) -> void:
	for i in [0, 1]:
		var ctl := _hand_node(i) as XRController3D
		if ctl == null or not is_instance_valid(ctl):
			continue
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var now: bool = XRUIPointer.trigger_pressed(ctl) or ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
		var was := bool(_trig_prev.get(i, false))
		_trig_prev[i] = now
		_track_hand(i, ctl)
		var local_p: Vector3 = _world.to_local(ctl.global_position)
		if now and not was:
			var obj := _world.grabbable_near(local_p)
			if obj != "" and _world.grab(i, obj, ctl):
				Haptics.tick()
				GameplayTelemetry.note_input_method("controllers")
		elif not now and was:
			_world.release(i, _hand_vel(i))
		if _world.held_obj(i) == "handle":
			_world.pull_handle(local_p.y)


func _track_hand(i: int, h: Node3D) -> void:
	var hist: Array = _hand_hist.get(i, [])
	hist.append(h.global_position)
	while hist.size() > 5:
		hist.remove_at(0)
	_hand_hist[i] = hist


func _hand_vel(i: int) -> Vector3:
	var hist: Array = _hand_hist.get(i, [])
	if hist.size() < 2:
		return Vector3.ZERO
	var dt := (hist.size() - 1) / 60.0
	return ((hist[hist.size() - 1] as Vector3) - (hist[0] as Vector3)) / maxf(dt, 0.001)


func _tick_ghosts(delta: float) -> void:
	for g in _ghosts:
		if not is_instance_valid(g):
			continue
		var fired: Array = (g as ChronoRecorder.ChronoGhost).tick(_loop_t, delta)
		for e in fired:
			var ed := e as Dictionary
			_world.ghost_event(str(ed["obj"]), str(ed["action"]))


func _tick_paradox() -> void:
	if _paradox_cd > 0:
		return
	var hp := _head_pos()
	for g in _ghosts:
		if not is_instance_valid(g):
			continue
		var gh := g as ChronoRecorder.ChronoGhost
		if hp.distance_to(gh.head_pos()) < PARADOX_DIST:
			_do_paradox()
			return
		for i in [0, 1]:
			var h := _hand_node(i)
			if h != null and h.global_position.distance_to(gh.head_pos()) < 0.3:
				_do_paradox()
				return


func _do_paradox() -> void:
	_paradox_cd = 2.0
	_loop_t += PARADOX_COST
	_announce_text("PARADOX!\n-3s", 1.5)
	# Animator: paradox static crackle — pooled burst + lingering wisps.
	AmbientKit.burst(self, _head_pos(), 24, Color(0.7, 0.95, 1.0), 3.0, 0.03, 0.9)
	AmbientKit.burst(self, _head_pos(), 10, Color(0.5, 0.8, 1.0, 0.6), 0.8, 0.05, 2.2)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("paradox")
	Haptics.play_sequence("error")
	for g in _ghosts:
		if is_instance_valid(g):
			(g as ChronoRecorder.ChronoGhost).flash_paradox()


func _tick_tripwire() -> void:
	if _trip_cd > 0:
		return
	if _world.trip_alarm_at(_world.to_local(_head_pos())):
		_trip_cd = 3.0
		_loop_t += TRIP_COST
		_announce_text("TRIPWIRE!\n-5s", 1.5)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_game_sfx("alarm")
		Haptics.deny()


func _on_objective_event(kind: String) -> void:
	# Record world-changing interactions so ghosts replay them.
	if kind in ["slot", "open"]:
		_recorder.log_event("keycard" if kind == "slot" else "safe", kind)


func _check_objective() -> void:
	if _secured or _state != "loop":
		return
	var done := false
	match _loop_idx:
		0:
			done = _world.keycard_slotted_in
		1:
			done = _world.safe_open
		2:
			done = _world.loot_in_exit
		3:
			if _world.check_escape(_world.to_local(_head_pos())):
				_win()
				return
			done = false
	if done:
		_secured = true
		_state = "secured"
		_state_t = 0.0
		_announce_text("TIMELINE SECURED", 2.5)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("success")


func _win() -> void:
	_state = "won"
	_recordings.append(_recorder.stop())
	_announce_text("HEIST COMPLETE\nThe timeline holds.", 30.0)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_stinger("levelup")
		AudioKit.set_intensity(0)
	Haptics.play_sequence("fanfare")


func _lose() -> void:
	_state = "lost"
	_announce_text("THE TIMELINE COLLAPSES\nThe crew never made it out.", 30.0)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_stinger("fail")
		AudioKit.set_intensity(0)


func _update_hud() -> void:
	var left := maxf(0.0, LOOP_SECS - _loop_t)
	var obj: String = OBJECTIVES[clampi(_loop_idx, 0, 3)]
	var marks := ""
	for i in MAX_LOOPS:
		marks += "◆ " if i < _recordings.size() + (1 if _state == "loop" else 0) else "◇ "
	_hud.text = "LOOP %d/%d · %d:%02d\n◈ %s\n%s" % [
		_loop_idx + 1, MAX_LOOPS, int(left) / 60, int(left) % 60, obj, marks]


# ------------------------------------------------- desktop/headless demo ---
# Scripted virtual hands walk the critical path so every system runs with
# zero errors when no XR hardware is present.

func _plan_demo(idx: int) -> void:
	_demo_t = 0.0
	_demo_plan = []
	match idx:
		0:
			_demo_plan = [
				[1.0, "move", 1, _world.keycard_pos()],
				[2.0, "grab", 1, "keycard"],
				[3.0, "move", 1, _world._reader_slot + Vector3(0, 0, 0.3)],
				[4.0, "release", 1, ""],
			]
		1:
			_demo_plan = [
				[1.0, "move", 1, _world.to_local(_world._safe_handle.global_position)],
				[1.6, "grab", 1, "handle"],
				[2.6, "pull", 1, ""],
				[3.2, "release", 1, ""],
			]
		2:
			_demo_plan = [
				[1.0, "move", 1, _world.loot_pos()],
				[1.6, "grab", 1, "loot"],
				[2.6, "move", 1, _world.exit_pos() + Vector3(0, 0.3, 0)],
				[3.2, "release", 1, ""],
			]
		3:
			_demo_plan = [
				[1.0, "head", 0, _world.exit_pos() + Vector3(0, 1.6, 0)],
			]


func _tick_demo(delta: float) -> void:
	_demo_t += delta
	while not _demo_plan.is_empty() and float(_demo_plan[0][0]) <= _demo_t:
		var step: Array = _demo_plan.pop_front()
		_run_demo_step(step)
	# Ease virtual hands toward their targets.
	for i in [0, 1]:
		var h := _hand_node(i)
		var tgt: Vector3 = h.get_meta("demo_target", h.position)
		h.position = h.position.lerp(tgt, minf(1.0, 5.0 * delta))


func _run_demo_step(step: Array) -> void:
	var kind := str(step[1])
	var hi := int(step[2])
	var h := _hand_node(hi)
	match kind:
		"move":
			h.set_meta("demo_target", (step[3] as Vector3))
		"grab":
			_world.grab(hi, str(step[3]), h)
		"release":
			_world.release(hi, Vector3.ZERO)
		"pull":
			# Simulate pulling the handle down 0.3m.
			_world.pull_handle(_world.to_local(h.global_position).y - 0.35)
		"head":
			_vhead.position = (step[3] as Vector3)
