## HwAppleBobbing - "Apple Bobbing": apples bob in a water barrel, periodically
## dunking under. Pinch-grab (or click) an apple while it is surfaced.
## +20 per apple. 60s round.
extends Node3D

const ST_PLAY := 0
const ST_OVER := 1
const ROUND_TIME := 60.0
const APPLE_POINTS := 20
const GRAB_RADIUS := 0.42
const WATER_Y := 0.62
const BARREL_R := 0.52
const NUM_APPLES := 5
const ANCHOR_NAME := "hw_apple_bobbing_main"

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var caught := 0
var elapsed := 0.0
var apples: Array = [] # dicts: node, phase, dunk_t, dunk_interval, dunking, dunk_left, drift_phase
var water_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var _anchor_timer := 0.0
var _pinch_hold := 0.0
var players := {}


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_barrel()
	_build_hud()
	for i in range(NUM_APPLES):
		_spawn_apple()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, -1.4), 2.0, 36)


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 1.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.6, -1.4), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.2, 0.5)


func _build_barrel() -> void:
	var center := Vector3(0.0, 0.0, -1.4)
	# Floor.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, 0.0, -1.0)
	floor_inst.material_override = _mat(Color(0.09, 0.08, 0.12))
	add_child(floor_inst)
	# Wooden barrel body.
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.62
	bm.bottom_radius = 0.55
	bm.height = 0.75
	barrel.mesh = bm
	barrel.position = center + Vector3(0.0, 0.375, 0.0)
	barrel.material_override = _mat(Color(0.30, 0.19, 0.10))
	add_child(barrel)
	# Metal hoops.
	for hy in [0.18, 0.58]:
		var hoop := MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.inner_radius = 0.60
		hm.outer_radius = 0.645
		hoop.mesh = hm
		hoop.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		hoop.position = center + Vector3(0.0, hy, 0.0)
		hoop.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.25, 0.28), "metal")
		add_child(hoop)
	# Water surface.
	water_mat = GraphicsPolish.pbr_preset(Color(0.15, 0.45, 0.85), "glass")
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = BARREL_R
	wm.bottom_radius = BARREL_R
	wm.height = 0.06
	water.mesh = wm
	water.position = center + Vector3(0.0, WATER_Y, 0.0)
	water.material_override = water_mat
	add_child(water)
	GraphicsPolish.make_point_light(self, center + Vector3(0.0, 1.6, 0.0), Color(0.5, 0.8, 1.0), 0.7, 5.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("APPLE BOBBING", 44, Color(0.6, 0.85, 1.0))
	hud_label.position = Vector3(-2.6, 2.7, -2.8)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Pinch or click an apple while it is surfaced | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-2.6, 2.25, -2.8)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -3.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "APPLE BOBBING   %ds   Score: %d\nApples: %d" % [int(ceil(maxf(time_left, 0.0))), score, caught]


func _show_msg(text: String, duration: float = 1.0) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ------------------------------------------------------------------ game ----

func _process(delta: float) -> void:
	elapsed += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		_poll_restart_pinch(delta)
		return
	time_left -= delta
	if time_left <= 0.0:
		_game_over()
		return
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_grab(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT))
	_step_apples(delta)
	GraphicsPolish.pulse_glow(water_mat, 0.4, 0.25, elapsed * 1.5)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY and camera != null:
			_try_grab_ray(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))


func _poll_restart_pinch(delta: float) -> void:
	var pinch_any := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT) or ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)
	if pinch_any:
		_pinch_hold += delta
		if _pinch_hold >= 1.0:
			_pinch_hold = 0.0
			_reset_game()
	else:
		_pinch_hold = 0.0


func _ray_distance(origin: Vector3, dir: Vector3, point: Vector3) -> float:
	var to := point - origin
	var t := maxf(to.dot(dir), 0.0)
	return (origin + dir * t).distance_to(point)


func _apple_surfaced(a: Dictionary) -> bool:
	var node: Node3D = a["node"]
	return is_instance_valid(node) and not bool(a["dunking"]) and node.position.y > WATER_Y - 0.06


func _try_grab(world_pos: Vector3) -> void:
	if state != ST_PLAY:
		return
	var best := -1
	var best_d := GRAB_RADIUS
	for i in range(apples.size()):
		var a: Dictionary = apples[i]
		var node: Node3D = a["node"]
		if not is_instance_valid(node) or not _apple_surfaced(a):
			continue
		var d := world_pos.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = i
	_catch(best)


func _try_grab_ray(origin: Vector3, dir: Vector3) -> void:
	if state != ST_PLAY:
		return
	var best := -1
	var best_d := GRAB_RADIUS
	for i in range(apples.size()):
		var a: Dictionary = apples[i]
		var node: Node3D = a["node"]
		if not is_instance_valid(node) or not _apple_surfaced(a):
			continue
		var d := _ray_distance(origin, dir, node.global_position)
		if d < best_d:
			best_d = d
			best = i
	_catch(best)


func _catch(idx: int) -> void:
	if idx < 0:
		return
	var a: Dictionary = apples[idx]
	var node: Node3D = a["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(0.45, 0.8, 1.0), 22)
	score += APPLE_POINTS
	caught += 1
	_sfx("splash", 700.0, 0.14, 0.5)
	_sfx("plip", 1200.0, 0.08, 0.35)
	_show_msg("+%d" % APPLE_POINTS, 0.8)
	# Respawn the apple elsewhere in the barrel.
	var ang := randf() * TAU
	var r := randf_range(0.05, BARREL_R - 0.14)
	node.position = Vector3(cos(ang) * r, WATER_Y + 0.03, -1.4 + sin(ang) * r)
	a["dunk_t"] = 0.0
	a["dunking"] = false
	a["dunk_interval"] = randf_range(2.5, 5.5)
	a["phase"] = randf() * TAU


func _spawn_apple() -> void:
	var root := Node3D.new()
	var ang := randf() * TAU
	var r := randf_range(0.05, BARREL_R - 0.14)
	root.position = Vector3(cos(ang) * r, WATER_Y + 0.03, -1.4 + sin(ang) * r)
	add_child(root)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.095
	bm.height = 0.19
	body.mesh = bm
	body.material_override = _mat(Color(0.85, 0.12, 0.12))
	root.add_child(body)
	var shine := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	shine.mesh = sm
	shine.position = Vector3(-0.04, 0.05, -0.06)
	shine.material_override = GraphicsPolish.glow(Color(1.0, 0.7, 0.7), 0.8)
	root.add_child(shine)
	var stem := MeshInstance3D.new()
	var stm := CylinderMesh.new()
	stm.top_radius = 0.012
	stm.bottom_radius = 0.018
	stm.height = 0.09
	stem.mesh = stm
	stem.position = Vector3(0.0, 0.12, 0.0)
	stem.rotation.z = 0.2
	stem.material_override = _mat(Color(0.20, 0.28, 0.12))
	root.add_child(stem)
	apples.append({
		"node": root, "phase": randf() * TAU,
		"dunk_t": 0.0, "dunk_interval": randf_range(1.5, 5.0),
		"dunking": false, "dunk_left": 0.0, "drift_phase": randf() * TAU,
	})


func _step_apples(delta: float) -> void:
	for a_v in apples:
		var a: Dictionary = a_v
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		# Slow drift around the barrel.
		node.position.x += sin(elapsed * 0.7 + float(a["drift_phase"])) * 0.08 * delta
		node.position.z += cos(elapsed * 0.6 + float(a["drift_phase"])) * 0.08 * delta
		var flat := Vector2(node.position.x, node.position.z + 1.4)
		if flat.length() > BARREL_R - 0.12:
			flat = flat.normalized() * (BARREL_R - 0.12)
			node.position.x = flat.x
			node.position.z = flat.y - 1.4
		if bool(a["dunking"]):
			# Dunked: sink below the surface, then pop back up.
			a["dunk_left"] = float(a["dunk_left"]) - delta
			node.position.y = lerpf(node.position.y, WATER_Y - 0.22, 6.0 * delta)
			if float(a["dunk_left"]) <= 0.0:
				a["dunking"] = false
				a["dunk_t"] = 0.0
				a["dunk_interval"] = randf_range(2.5, 5.5)
				_sfx("bob_up", 500.0, 0.1, 0.3)
		else:
			# Bobbing on the surface.
			node.position.y = WATER_Y + 0.03 + sin(elapsed * 2.2 + float(a["phase"])) * 0.05
			node.rotation.y += delta * 0.4
			a["dunk_t"] = float(a["dunk_t"]) + delta
			if float(a["dunk_t"]) >= float(a["dunk_interval"]):
				a["dunking"] = true
				a["dunk_left"] = 1.3
				_sfx("dunk", 300.0, 0.12, 0.35)


func _game_over() -> void:
	state = ST_OVER
	time_left = 0.0
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.4), 70)
	_sfx("win", 880.0, 0.4, 0.5)
	_show_msg("TIME UP!\nScore: %d  (%d apples)\nHold pinch 1s or press R" % [score, caught], 600.0)
	_update_hud()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	caught = 0
	elapsed = 0.0
	_pinch_hold = 0.0
	for a_v in apples:
		var a: Dictionary = a_v
		var node: Node3D = a["node"]
		if is_instance_valid(node):
			var ang := randf() * TAU
			var r := randf_range(0.05, BARREL_R - 0.14)
			node.position = Vector3(cos(ang) * r, WATER_Y + 0.03, -1.4 + sin(ang) * r)
		a["dunk_t"] = 0.0
		a["dunking"] = false
		a["dunk_interval"] = randf_range(1.5, 5.0)
	_show_msg("", 0.01)
	_update_hud()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)


# ------------------------------------------------------------------ audio ----

func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames_count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames_count * 2)
	for i in range(frames_count):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames_count)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func _sfx(sfx_name: String, freq: float, dur: float, vol: float) -> void:
	if not players.has(sfx_name):
		players[sfx_name] = _make_player(_make_tone(freq, dur, vol))
	(players[sfx_name] as AudioStreamPlayer).play()
