## eye_spy.gd - Eye Spy AR: camera-powered "I spy" hunting game.
## 10 rounds; each round names a target: a COLOR ("find something BLUE"),
## a SHAPE ("find something ROUND"), or BRIGHTNESS ("find something BRIGHT" /
## "find something DARK"). Aim the headset camera and pinch/click to SNAP a
## frame; CameraVision judges it (color fraction >= 0.25, roundness >= 0.55,
## brightness >= 0.6 / <= 0.25).
## MANUAL MODE (no camera: desktop/headless): 6 floating colored orbs, a dark
## box, a bright lamp, and a donut (torus) spawn around the room; pinch/click
## the matching prop instead. 100 pts/round x streak multiplier, 30s per-round
## timer (timeout = fail, streak reset), haptics, confetti, fanfare at 10/10,
## anchor persistence, synth SFX generated in code. No camera needed to play.
extends Node3D
class_name EyeSpyGame

const ROUNDS_TOTAL := 10
const ROUND_TIME := 30.0
const SNAP_COOLDOWN := 1.0
const ANCHOR_NAME := "eye_spy_main"
const AUDIO_RATE := 22050

const ORB_COLORS := {
	"red": Color(1.0, 0.15, 0.1),
	"blue": Color(0.15, 0.4, 1.0),
	"green": Color(0.15, 0.9, 0.25),
	"yellow": Color(1.0, 0.9, 0.15),
	"purple": Color(0.7, 0.25, 1.0),
	"orange": Color(1.0, 0.55, 0.1),
}

var _cam: Camera3D = null
var _camera_mode := false ## true when a real AR camera can capture frames
var _rounds: Array = [] ## {kind, name, color, label_cam, label_manual}
var _round_idx := 0
var _state := "play" ## play | cooldown | over
var _round_timer := ROUND_TIME
var _cooldown := 0.0
var _snap_cd := 0.0
var _score := 0
var _streak := 1
var _wins := 0
var _last_tick_sec := -1
var _seeing_timer := 0.0
var _anchor_timer := 0.0
var _time := 0.0

var _hud_rig: Node3D = null
var _target_label: Label3D = null
var _seeing_label: Label3D = null
var _timer_label: Label3D = null
var _score_label: Label3D = null
var _message_label: Label3D = null
var _cross_mats: Array = [] ## pulsing crosshair materials
var _orbs: Array = [] ## manual-mode orb roots for bob animation
var _orb_bases: Array = []


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	_ensure_camera()
	_build_light()
	_build_room()
	_camera_mode = ARCamera.is_available()
	if not _camera_mode:
		ARCamera.request_permission() # no-op on desktop; harmless on device
		_build_manual_props()
	_build_hud()
	_restart()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, 0), 3.0, 40)


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	_snap_cd = maxf(0.0, _snap_cd - delta)
	_update_hud_rig()
	_animate_props(delta)

	# XR pinch: the mouse-button gate keeps desktop clicks from double-firing
	# through the kit's mouse fallback.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	var xr_pinch := pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if _state == "play":
		_round_timer -= delta
		var sec := int(ceili(_round_timer))
		if _round_timer <= 5.0 and sec != _last_tick_sec:
			_last_tick_sec = sec
			_play_tone(1250.0, 0.06, 0.35)
		if _round_timer <= 0.0:
			_round_fail("TIME'S UP!")
		elif _camera_mode:
			_seeing_timer -= delta
			if _seeing_timer <= 0.0:
				_seeing_timer = 1.2
				_update_seeing()
		if xr_pinch:
			if _camera_mode:
				_do_snap()
			else:
				_do_manual_pinch()
	elif _state == "cooldown":
		_cooldown -= delta
		if _cooldown <= 0.0:
			_next_round()
	elif _state == "over":
		if xr_pinch:
			_restart()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _state == "over":
				_restart()
			elif _state == "play":
				if _camera_mode:
					_do_snap()
				else:
					_do_manual_click(mb.position)


# ---------------------------------------------------------------- setup

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 1.6, 3.2)
	_cam.look_at(Vector3(0, 1.0, -1.0), Vector3.UP)


func _build_light() -> void:
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.ambient_light_energy = 0.9
	amb.environment = env
	add_child(amb)


func _build_room() -> void:
	_add_static_box(Vector3(0, -0.1, 0), Vector3(12, 0.2, 12), Color(0.18, 0.2, 0.26))
	_add_static_box(Vector3(0, 2.5, -6), Vector3(12, 5.0, 0.2), Color(0.22, 0.24, 0.32))


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var sb := StaticBody3D.new()
	add_child(sb)
	sb.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(color, "matte")
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)


## Manual mode: floating props to hunt when no camera is available.
func _build_manual_props() -> void:
	var names: Array = ORB_COLORS.keys()
	var spots := [
		Vector3(-1.6, 1.3, -1.6), Vector3(-0.95, 1.45, -1.9),
		Vector3(-0.32, 1.3, -2.05), Vector3(0.32, 1.45, -2.05),
		Vector3(0.95, 1.3, -1.9), Vector3(1.6, 1.45, -1.6),
	]
	for i in names.size():
		var cname := String(names[i])
		_add_orb(cname, ORB_COLORS[cname], spots[i])
	_add_lamp(Vector3(2.3, 0.8, -0.9))
	_add_dark_box(Vector3(-2.3, 0.6, -0.9))
	_add_donut(Vector3(0, 0.5, -1.1))


func _make_prop_body(root: Node3D, spy_id: String, shape: Shape3D) -> void:
	var sb := StaticBody3D.new()
	sb.set_meta("spy_id", spy_id)
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)


func _add_prop_label(root: Node3D, text: String) -> void:
	var l := GraphicsPolish.make_label(text, 40, Color(0.9, 0.95, 1.0))
	l.position = Vector3(0, 0.42, 0)
	l.pixel_size = 0.006
	root.add_child(l)


func _add_orb(cname: String, color: Color, pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	mi.material_override = GraphicsPolish.glow(color, 1.8)
	root.add_child(mi)
	var ss := SphereShape3D.new()
	ss.radius = 0.26
	_make_prop_body(root, cname, ss)
	_add_prop_label(root, cname.to_upper())
	_orbs.append(root)
	_orb_bases.append(pos)


func _add_lamp(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	mi.mesh = sm
	mi.material_override = GraphicsPolish.glow(Color(1.0, 0.95, 0.75), 2.6)
	root.add_child(mi)
	var ss := SphereShape3D.new()
	ss.radius = 0.32
	_make_prop_body(root, "bright", ss)
	GraphicsPolish.make_point_light(root, Vector3.ZERO, Color(1.0, 0.9, 0.7), 1.6, 5.0)
	_add_prop_label(root, "LAMP")


func _add_dark_box(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.45, 0.45)
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(Color(0.02, 0.02, 0.03), "matte")
	root.add_child(mi)
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.6, 0.6)
	_make_prop_body(root, "dark", bs)
	_add_prop_label(root, "DARK BOX")


func _add_donut(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.28
	mi.mesh = tm
	mi.material_override = GraphicsPolish.pbr_preset(Color(1.0, 0.45, 0.65), "plastic")
	root.add_child(mi)
	var ss := SphereShape3D.new()
	ss.radius = 0.38
	_make_prop_body(root, "round", ss)
	_add_prop_label(root, "DONUT")
	_orbs.append(root)
	_orb_bases.append(pos)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	_hud_rig = Node3D.new()
	add_child(_hud_rig)

	_target_label = GraphicsPolish.make_label("FIND: ?", 96, Color.WHITE)
	_target_label.pixel_size = 0.005
	_target_label.position = Vector3(0, 0.52, 0)
	_hud_rig.add_child(_target_label)

	_seeing_label = GraphicsPolish.make_label("", 48, Color(0.75, 0.85, 1.0))
	_seeing_label.pixel_size = 0.004
	_seeing_label.position = Vector3(0, 0.24, 0)
	_hud_rig.add_child(_seeing_label)

	_message_label = GraphicsPolish.make_label("", 72, Color(0.5, 1.0, 0.6))
	_message_label.pixel_size = 0.005
	_message_label.position = Vector3(0, -0.14, 0)
	_hud_rig.add_child(_message_label)

	_score_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.9, 0.5))
	_score_label.pixel_size = 0.004
	_score_label.position = Vector3(-0.85, 0.52, 0)
	_hud_rig.add_child(_score_label)

	_timer_label = GraphicsPolish.make_label("", 56, Color.WHITE)
	_timer_label.pixel_size = 0.004
	_timer_label.position = Vector3(0.85, 0.52, 0)
	_hud_rig.add_child(_timer_label)

	_make_crosshair()
	_make_snap_button()


func _make_crosshair() -> void:
	var mat := GraphicsPolish.glow(Color(1, 1, 1, 0.9), 1.4)
	_cross_mats.append(mat)
	for size in [Vector3(0.30, 0.018, 0.01), Vector3(0.018, 0.30, 0.01)]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		_hud_rig.add_child(mi)


func _make_snap_button() -> void:
	var root := Node3D.new()
	root.name = "SnapButton"
	root.position = Vector3(0, -0.62, 0)
	_hud_rig.add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.28, 0.08)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr_preset(Color(0.2, 0.7, 1.0), "plastic")
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 1.0) * 0.5
	mi.material_override = mat
	root.add_child(mi)
	var label := GraphicsPolish.make_label("SNAP", 56, Color.WHITE)
	label.position = Vector3(0, 0, 0.06)
	label.pixel_size = 0.004
	root.add_child(label)
	if _camera_mode:
		root.visible = true
	else:
		root.visible = false


## Keep the HUD floating ~2 m in front of the current camera (HMD or desktop).
func _update_hud_rig() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _hud_rig == null:
		return
	var t := cam.global_transform
	_hud_rig.global_transform = Transform3D(
		t.basis, t.origin + (-t.basis.z) * 2.0 + Vector3(0, 0.05, 0))


func _update_hud() -> void:
	if _hud_rig == null:
		return
	_score_label.text = "SCORE %d\nSTREAK x%d" % [_score, _streak]
	if _state == "play":
		var r: Dictionary = _rounds[_round_idx]
		_target_label.text = "ROUND %d/%d\n%s" % [_round_idx + 1, ROUNDS_TOTAL,
			String(r["label_manual"] if not _camera_mode else r["label_cam"])]
		if String(r["kind"]) == "color":
			_target_label.modulate = r["color"]
		else:
			_target_label.modulate = Color.WHITE
		var secs := int(ceili(_round_timer))
		_timer_label.text = "%ds" % secs
		_timer_label.modulate = Color(1.0, 0.35, 0.3) if secs <= 10 else Color.WHITE
	elif _state == "over":
		_timer_label.text = ""


func _update_seeing() -> void:
	if not _camera_mode or _state != "play":
		return
	var img := ARCamera.capture()
	if img == null:
		_seeing_label.text = "camera warming up..."
		return
	_seeing_label.text = "seeing: %s-ish" % CameraVision.dominant_color_name(img)


func _animate_props(delta: float) -> void:
	for m in _cross_mats:
		GraphicsPolish.pulse_glow(m, 1.2, 0.5, _time, 3.0)
	for i in _orbs.size():
		var o: Node3D = _orbs[i]
		var base: Vector3 = _orb_bases[i]
		o.position = base + Vector3(0, 0.08 * sin(_time * 1.6 + float(i) * 1.1), 0)
		o.rotation.y += delta * 0.4


# ---------------------------------------------------------------- rounds

func _restart() -> void:
	_rounds = _build_rounds()
	_round_idx = 0
	_score = 0
	_streak = 1
	_wins = 0
	_state = "play"
	_message_label.text = ""
	if _camera_mode:
		_seeing_label.text = "aim at the target, then SNAP"
	else:
		_seeing_label.text = "pinch / click the matching prop"
	_start_round()


func _build_rounds() -> Array:
	var colors: Array = ORB_COLORS.keys()
	colors.shuffle()
	var rounds: Array = []
	for c in colors:
		rounds.append(_round_for("color", String(c)))
	rounds.append(_round_for("shape", "round"))
	rounds.append(_round_for("bright", "bright"))
	rounds.append(_round_for("dark", "dark"))
	rounds.append(_round_for("color", String(colors[randi() % colors.size()])))
	rounds.shuffle()
	return rounds


func _round_for(kind: String, cname: String) -> Dictionary:
	var d := {"kind": kind, "name": cname, "color": Color.WHITE}
	match kind:
		"color":
			d["color"] = ORB_COLORS[cname]
			d["label_cam"] = "FIND: " + cname.to_upper()
			d["label_manual"] = "FIND THE " + cname.to_upper() + " ORB"
		"shape":
			d["label_cam"] = "FIND: SOMETHING ROUND"
			d["label_manual"] = "FIND THE DONUT (ROUND)"
		"bright":
			d["label_cam"] = "FIND: SOMETHING BRIGHT"
			d["label_manual"] = "FIND THE BRIGHT LAMP"
		"dark":
			d["label_cam"] = "FIND: SOMETHING DARK"
			d["label_manual"] = "FIND THE DARK BOX"
	return d


func _start_round() -> void:
	_round_timer = ROUND_TIME
	_last_tick_sec = -1
	_message_label.text = ""
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)


func _next_round() -> void:
	_round_idx += 1
	if _round_idx >= ROUNDS_TOTAL:
		_game_over()
		return
	_state = "play"
	_start_round()


func _round_success() -> void:
	if _state != "play":
		return
	_state = "cooldown"
	_cooldown = 1.4
	var pts := 100 * _streak
	_score += pts
	_wins += 1
	_streak += 1
	_message_label.text = "CORRECT! +%d" % pts
	_message_label.modulate = Color(0.5, 1.0, 0.6)
	var rig := _hud_rig if _hud_rig != null else self
	GraphicsPolish.spawn_confetti(rig, rig.global_position, 50)
	Haptics.pulse(0.8, 0.2)
	_play_tone(660.0, 0.12, 0.6)
	_play_tone(990.0, 0.18, 0.6, 0.1)


func _round_fail(reason: String) -> void:
	if _state != "play":
		return
	_state = "cooldown"
	_cooldown = 1.4
	_streak = 1
	_message_label.text = reason + "  (streak reset)"
	_message_label.modulate = Color(1.0, 0.45, 0.4)
	var rig := _hud_rig if _hud_rig != null else self
	GraphicsPolish.spawn_sparks(rig, rig.global_position, Color(1.0, 0.3, 0.25), 24)
	Haptics.pulse(0.4, 0.3)
	_play_tone(220.0, 0.25, 0.6)
	_play_tone(165.0, 0.3, 0.6, 0.12)


func _game_over() -> void:
	_state = "over"
	_round_timer = 0.0
	if _wins >= ROUNDS_TOTAL:
		_target_label.text = "PERFECT 10/10!"
		_target_label.modulate = Color(1.0, 0.85, 0.3)
		_message_label.text = "FINAL SCORE: %d\npinch / click to play again" % _score
		_message_label.modulate = Color(1.0, 0.85, 0.3)
		for i in 3:
			var rig := _hud_rig if _hud_rig != null else self
			GraphicsPolish.spawn_confetti(rig, rig.global_position + Vector3(randf_range(-1, 1), 0, 0), 60)
		Haptics.thump()
		_fanfare()
	else:
		_target_label.text = "GAME OVER"
		_target_label.modulate = Color.WHITE
		_message_label.text = "%d/10 found - SCORE %d\npinch / click to play again" % [_wins, _score]
		_message_label.modulate = Color(0.8, 0.9, 1.0)
	_seeing_label.text = ""
	_timer_label.text = ""


# ---------------------------------------------------------------- snapping

func _do_snap() -> void:
	if _state != "play" or _snap_cd > 0.0:
		return
	_snap_cd = SNAP_COOLDOWN
	_play_tone(500.0, 0.05, 0.4) # shutter click
	var img := ARCamera.capture()
	if img == null:
		_message_label.text = "camera not ready - aim and try again"
		_message_label.modulate = Color(1.0, 0.8, 0.4)
		return
	if _judge_camera(img):
		_round_success()
	else:
		_round_fail("NOT QUITE!")


func _judge_camera(img: Image) -> bool:
	var r: Dictionary = _rounds[_round_idx]
	match String(r["kind"]):
		"color":
			return CameraVision.color_match_fraction(img, r["color"]) >= 0.25
		"shape":
			return CameraVision.roundness(img) >= 0.55
		"bright":
			return CameraVision.brightness(img) >= 0.6
		"dark":
			return CameraVision.brightness(img) <= 0.25
	return false


func _do_manual_pinch() -> void:
	if _state != "play" or _snap_cd > 0.0:
		return
	var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	_manual_pick(ray[0], ray[1])


func _do_manual_click(screen_pos: Vector2) -> void:
	if _state != "play" or _snap_cd > 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_manual_pick(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _manual_pick(from: Vector3, dir: Vector3) -> void:
	_snap_cd = SNAP_COOLDOWN
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_message_label.text = "aim at a prop!"
		_message_label.modulate = Color(1.0, 0.8, 0.4)
		return
	var r: Dictionary = _rounds[_round_idx]
	var collider: Object = hit.get("collider")
	var sid := ""
	if collider is StaticBody3D and (collider as StaticBody3D).has_meta("spy_id"):
		sid = String((collider as StaticBody3D).get_meta("spy_id"))
	if sid == String(r["name"]):
		_round_success()
	else:
		_round_fail("WRONG PROP!")


# ---------------------------------------------------------------- audio

## Simple synth beep generated in code (8-bit mono WAV).
func _play_tone(freq: float, duration: float, volume: float = 0.6, delay: float = 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var n := int(duration * AUDIO_RATE)
	var data := PackedByteArray()
	data.resize(n)
	for i in n:
		var t := float(i) / AUDIO_RATE
		var env := minf(1.0, t / 0.01) * exp(-2.5 * t)
		var s := sin(TAU * freq * t) + 0.2 * sin(TAU * freq * 2.0 * t)
		data[i] = clampi(128 + int(s * env * volume * 110.0), 0, 255)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = AUDIO_RATE
	wav.stereo = false
	wav.data = data
	var p := AudioStreamPlayer.new()
	p.stream = wav
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _fanfare() -> void:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_play_tone(notes[i], 0.22, 0.6, float(i) * 0.14)
	_play_tone(1318.5, 0.5, 0.6, 0.6)
