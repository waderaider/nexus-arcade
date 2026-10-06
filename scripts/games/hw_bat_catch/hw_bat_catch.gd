## HwBatCatch - "Bat Catch": bats flutter around the room. Pinch-grab (or
## click) when your hand is near one to catch it. 60 seconds, +15 per bat.
## R restarts; hold pinch 1s on the end screen to play again.
extends Node3D

const ROUND_TIME := 60.0
const BAT_COUNT := 8
const CATCH_RADIUS := 0.42
const CATCH_SCORE := 15

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var caught := 0
var bats: Array = []
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var moon_mat: StandardMaterial3D = null
var catch_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_sky()
	_build_hud()
	catch_player = _make_player(_make_tone(990.0, 0.20, 0.50))
	miss_player = _make_player(_make_tone(320.0, 0.10, 0.30))
	win_player = _make_player(_make_tone(880.0, 0.50, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_bat_catch_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.5), 2.5, 36)
	for i in range(BAT_COUNT):
		_spawn_bat()


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 1.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.4, -2.0), Vector3.UP)
	camera.current = true


func _build_sky() -> void:
	# Big pale moon.
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.5
	ms.height = 1.0
	moon.mesh = ms
	moon.position = Vector3(-2.6, 3.2, -7.0)
	moon_mat = GraphicsPolish.glow(Color(0.95, 0.95, 0.85), 1.2)
	moon.material_override = moon_mat
	add_child(moon)
	# Dark ground far below the play space.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.02, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.05, 0.05, 0.08), 0.0, 0.95)
	add_child(floor_inst)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("BAT CATCH", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.3, 2.7, -1.6)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Pinch / click near a bat to grab it!  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.3, 2.15, -1.6)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.9, -2.6)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "BAT CATCH\nTime: %ds   Score: %d   Caught: %d" % [int(ceil(time_left)), score, caught]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text


func _random_spot() -> Vector3:
	return Vector3(randf_range(-1.7, 1.7), randf_range(1.0, 2.3), randf_range(-3.0, -0.5))


func _spawn_bat() -> void:
	var root := Node3D.new()
	root.position = _random_spot()
	add_child(root)
	var body_mat := GraphicsPolish.pbr(Color(0.15, 0.10, 0.25), 0.1, 0.7)
	var body := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.12
	bs.height = 0.24
	body.mesh = bs
	body.material_override = body_mat
	root.add_child(body)
	# Pointy ears.
	for ex in [-0.06, 0.06]:
		var ear := MeshInstance3D.new()
		var ec := CylinderMesh.new()
		ec.top_radius = 0.0
		ec.bottom_radius = 0.035
		ec.height = 0.09
		ear.mesh = ec
		ear.position = Vector3(ex, 0.15, 0.0)
		ear.material_override = body_mat
		root.add_child(ear)
	# Glowing eyes.
	for ex in [-0.05, 0.05]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		eye.mesh = es
		eye.position = Vector3(ex, 0.05, -0.10)
		eye.material_override = GraphicsPolish.glow(Color(1.0, 0.3, 0.9), 2.0)
		root.add_child(eye)
	# Flapping wings on pivots.
	var wing_mat := GraphicsPolish.pbr(Color(0.28, 0.14, 0.38), 0.0, 0.8)
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.08, 0.05, 0.0)
		root.add_child(pivot)
		var wing := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(0.36, 0.02, 0.24)
		wing.mesh = wb
		wing.position = Vector3(side * 0.20, 0.0, 0.0)
		wing.material_override = wing_mat
		pivot.add_child(wing)
		wings.append({"pivot": pivot, "side": side})
	bats.append({
		"node": root,
		"wings": wings,
		"target": _random_spot(),
		"speed": randf_range(0.8, 1.4),
		"phase": randf() * TAU,
		"flap": randf_range(9.0, 13.0),
	})


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_bat_catch_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if moon_mat != null:
		GraphicsPolish.pulse_glow(moon_mat, 1.1, 0.3, _time, 1.2)
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_pinch_hold += delta
			if _pinch_hold >= 1.0:
				_pinch_hold = 0.0
				_reset_game()
		else:
			_pinch_hold = 0.0
		_update_hud()
		return
	# ST_PLAY.
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
			or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
		_try_catch()
	_step_bats(delta)
	_update_hud()


func _step_bats(delta: float) -> void:
	for b_v in bats:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			continue
		var target: Vector3 = b["target"]
		var to := target - node.position
		if to.length() < 0.25:
			b["target"] = _random_spot()
		else:
			var speed: float = b["speed"]
			node.position += to.normalized() * speed * delta
			var look := node.position + to.normalized()
			if (look - node.position).length_squared() > 0.000001:
				node.look_at(look, Vector3.UP)
		# Wing flap + bob.
		var phase: float = b["phase"]
		var flap: float = b["flap"]
		var wave := sin(_time * flap + phase)
		for w_v in b["wings"]:
			var w: Dictionary = w_v
			var pivot: Node3D = w["pivot"]
			var side: float = w["side"]
			pivot.rotation.z = -side * (0.15 + wave * 0.75)
		node.position.y += 0.15 * wave * delta


func _hand_positions() -> Array:
	var hands: Array = []
	if ARUpgradeKit.is_xr_active():
		hands.append(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT))
		hands.append(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_LEFT))
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mp)
		var dir := camera.project_ray_normal(mp)
		if absf(dir.z) > 0.001:
			var t := (-1.5 - origin.z) / dir.z
			if t > 0.0:
				hands.append(origin + dir * t)
	return hands


func _try_catch() -> void:
	if state != ST_PLAY:
		return
	var hands := _hand_positions()
	if hands.is_empty():
		return
	var caught_any := false
	for b_v in bats:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			continue
		for h_v in hands:
			var h: Vector3 = h_v
			if node.position.distance_to(h) < CATCH_RADIUS:
				GraphicsPolish.spawn_sparks(self, node.position, Color(0.8, 0.4, 1.0), 24)
				node.position = _random_spot()
				b["target"] = _random_spot()
				score += CATCH_SCORE
				caught += 1
				caught_any = true
				break
		if caught_any:
			break
	if caught_any:
		if catch_player != null:
			catch_player.play()
	else:
		if miss_player != null:
			miss_player.play()


func _game_over() -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_bat_catch_main", global_transform)
	var rank := "Bat Buddy"
	if score >= 300:
		rank = "BAT MASTER!"
	elif score >= 150:
		rank = "Night Hunter"
	_show_msg("TIME UP!\nCaught: %d   Score: %d\n%s\nR or hold pinch 1s to play again" % [caught, score, rank])
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -1.5), 70)
	if win_player != null:
		win_player.play()


func _reset_game() -> void:
	for b_v in bats:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			node.position = _random_spot()
			b["target"] = _random_spot()
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	caught = 0
	_pinch_hold = 0.0
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_bat_catch_main", global_transform)


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
