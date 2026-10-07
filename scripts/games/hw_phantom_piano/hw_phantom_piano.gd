## HwPhantomPiano - "Phantom Piano": a haunted piano plays glowing key
## sequences; tap the keys back Simon-style with a pinch (or click).
## Sequences grow each round; 3 mistakes ends the run.
extends Node3D

const ST_SHOW := 0
const ST_INPUT := 1
const ST_OVER := 2
const NUM_KEYS := 8
const NOTE_FREQS := [262.0, 294.0, 330.0, 349.0, 392.0, 440.0, 494.0, 523.0]
const TAP_RADIUS := 0.28
const ANCHOR_NAME := "hw_phantom_piano_main"

var camera: Camera3D = null
var state := ST_SHOW
var score := 0
var mistakes := 0
var notes_hit := 0
var sequence: Array = [] # key indices
var show_idx := 0
var show_timer := 1.0
var input_idx := 0
var next_round_timer := 0.0
var elapsed := 0.0
var keys: Array = [] # dicts: node, mat, base_y, dip
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var _anchor_timer := 0.0
var _pinch_hold := 0.0
var players := {}

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
# v0.7.0: the phantom pianist seated on the player's real chair.
var _phantom: Node3D = null
var _phantom_base := Vector3.ZERO
# The piano sits on a stage so it can be centered/aligned in the real
# room; key taps use global positions so nothing else changes.
var piano_stage: Node3D = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	piano_stage = Node3D.new()
	piano_stage.name = "PianoStage"
	add_child(piano_stage)
	_build_piano()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -1.4), 2.2, 40)
	_next_round()
	_apply_room_layout()


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_known = true
	# Center the piano in the room, running its long axis along the
	# room's long axis so the keys never face a wall.
	var rot := 0.0
	if _room_bounds.size.y > _room_bounds.size.x * 1.3:
		rot = PI * 0.5
	piano_stage.rotation.y = rot
	var c := _room_bounds.get_center()
	var local_c := Vector3(0.0, 0.0, -1.4).rotated(Vector3.UP, rot)
	piano_stage.position = Vector3(c.x - local_c.x, 0.0, c.y - local_c.z)
	# v0.7.0 furniture morph: the real chair becomes the phantom's
	# haunted throne — the invisible pianist takes a visible seat and
	# sways with the music (see _process).
	var chair_anchors := RoomKit.get_anchors("CHAIR")
	if not chair_anchors.is_empty():
		var canchor: Dictionary = chair_anchors[0]
		RoomKit.morph(canchor, "haunted")
		var seat: Vector3 = RoomKit.cuboid_top(canchor)
		if _phantom == null:
			_phantom = _make_phantom()
		_phantom.position = seat + Vector3(0.0, 0.42, 0.0)
		_phantom_base = _phantom.position
		var face := piano_stage.position + local_c - seat
		_phantom.rotation.y = atan2(face.x, face.z)


func _make_phantom() -> Node3D:
	# The invisible pianist, made visible: a translucent figure seated
	# on the player's real chair, swaying with the music.
	var root := Node3D.new()
	root.name = "PhantomPianist"
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.14
	tm.height = 0.5
	torso.mesh = tm
	torso.position = Vector3(0.0, 0.25, 0.0)
	torso.material_override = GraphicsPolish.glow(Color(0.7, 0.85, 1.0), 0.9)
	root.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.22
	head.mesh = hm
	head.position = Vector3(0.0, 0.62, 0.0)
	head.material_override = GraphicsPolish.glow(Color(0.8, 0.92, 1.0), 1.2)
	root.add_child(head)
	add_child(root)
	return root


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.9, 1.3)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.85, -1.4), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.25, 0.5)


func _build_piano() -> void:
	var center := Vector3(0.0, 0.0, -1.4)
	# Floor.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, 0.0, -1.0)
	floor_inst.material_override = _mat(Color(0.07, 0.06, 0.10))
	add_child(floor_inst)
	# Piano body + lid + legs.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.24, 0.75)
	body.mesh = bm
	body.position = center + Vector3(0.0, 0.82, 0.0)
	body.material_override = _mat(Color(0.05, 0.05, 0.07))
	piano_stage.add_child(body)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.9, 0.05, 0.75)
	lid.mesh = lm
	lid.position = center + Vector3(0.0, 1.18, 0.18)
	lid.rotation.x = -0.5
	lid.material_override = _mat(Color(0.06, 0.06, 0.08))
	piano_stage.add_child(lid)
	for lx in [-0.8, 0.8]:
		for lz in [-0.28, 0.28]:
			var leg := MeshInstance3D.new()
			var lgm := BoxMesh.new()
			lgm.size = Vector3(0.09, 0.72, 0.09)
			leg.mesh = lgm
			leg.position = center + Vector3(lx, 0.36, lz)
			leg.material_override = _mat(Color(0.05, 0.05, 0.07))
			piano_stage.add_child(leg)
	# Candles on the piano for spooky light.
	for cx in [-0.7, 0.7]:
		var candle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 0.22
		candle.mesh = cm
		candle.position = center + Vector3(cx, 1.05, -0.22)
		candle.material_override = _mat(Color(0.9, 0.85, 0.7))
		piano_stage.add_child(candle)
		var flame := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.025
		fm.height = 0.05
		flame.mesh = fm
		flame.position = center + Vector3(cx, 1.20, -0.22)
		flame.material_override = GraphicsPolish.glow(Color(1.0, 0.6, 0.15), 2.4)
		add_child(flame)
	GraphicsPolish.make_point_light(piano_stage, center + Vector3(0.0, 1.7, 0.0), Color(1.0, 0.65, 0.3), 0.8, 5.0)
	# 8 haunted keys, each with its own material so it can light up.
	var key_w := 0.20
	var start_x := -key_w * float(NUM_KEYS - 1) * 0.5
	for i in range(NUM_KEYS):
		var kmat := GraphicsPolish.glow(Color(0.92, 0.90, 0.95), 0.25)
		var key := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(key_w - 0.02, 0.06, 0.34)
		key.mesh = km
		var kx := start_x + float(i) * key_w
		key.position = center + Vector3(kx, 0.97, 0.12)
		key.material_override = kmat
		piano_stage.add_child(key)
		keys.append({"node": key, "mat": kmat, "base_y": key.position.y, "dip": 0.0})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("PHANTOM PIANO", 44, Color(0.85, 0.8, 1.0))
	hud_label.position = Vector3(-2.6, 2.9, -3.0)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Watch the glowing keys, then tap them back in order (pinch or click) | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-2.6, 2.45, -3.0)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.1, -3.2)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	var phase := "WATCH" if state == ST_SHOW else ("PLAY" if state == ST_INPUT else "OVER")
	hud_label.text = "PHANTOM PIANO   [%s]   Score: %d\nRound: %d   Mistakes: %d/3" % [phase, score, sequence.size(), mistakes]


func _show_msg(text: String, duration: float = 1.2) -> void:
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
		_update_hud()
		return
	if next_round_timer > 0.0:
		next_round_timer -= delta
		if next_round_timer <= 0.0:
			_next_round()
	if state == ST_SHOW and next_round_timer <= 0.0:
		_step_show(delta)
	elif state == ST_INPUT:
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			_tap_at(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT))
	# Key press dip animation + idle shimmer.
	for k_v in keys:
		var k: Dictionary = k_v
		var node: MeshInstance3D = k["node"]
		if not is_instance_valid(node):
			continue
		var dip := float(k["dip"])
		if dip > 0.0:
			dip = maxf(dip - delta * 5.0, 0.0)
			k["dip"] = dip
		node.position.y = float(k["base_y"]) - 0.035 * dip
	# The phantom pianist sways on the player's real chair with the music.
	if _phantom != null:
		_phantom.position.y = _phantom_base.y + sin(elapsed * 2.2) * 0.035
		_phantom.rotation.z = sin(elapsed * 1.1) * 0.08
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_INPUT and camera != null:
			var origin := camera.project_ray_origin(mb.position)
			var dir := camera.project_ray_normal(mb.position)
			var best := -1
			var best_d := TAP_RADIUS
			for i in range(keys.size()):
				var k: Dictionary = keys[i]
				var node: MeshInstance3D = k["node"]
				if not is_instance_valid(node):
					continue
				var d := _ray_distance(origin, dir, node.global_position)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				_tap_key(best)


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


func _next_round() -> void:
	sequence.append(randi() % NUM_KEYS)
	state = ST_SHOW
	show_idx = 0
	show_timer = 0.9
	input_idx = 0
	_show_msg("Round %d: watch..." % sequence.size(), 1.0)


func _step_show(delta: float) -> void:
	if show_idx >= sequence.size():
		state = ST_INPUT
		input_idx = 0
		_dim_all()
		_show_msg("Your turn!", 1.0)
		return
	show_timer -= delta
	if show_timer > 0.0:
		return
	var ki: int = sequence[show_idx]
	_dim_all()
	_light_key(ki, 2.6)
	_play_key_tone(ki)
	show_idx += 1
	show_timer = 0.55


func _light_key(ki: int, energy: float) -> void:
	var k: Dictionary = keys[ki]
	(k["mat"] as StandardMaterial3D).emission_energy_multiplier = energy
	k["dip"] = 1.0


func _dim_all() -> void:
	for k_v in keys:
		var k: Dictionary = k_v
		(k["mat"] as StandardMaterial3D).emission_energy_multiplier = 0.25


func _play_key_tone(ki: int) -> void:
	_sfx("key%d" % ki, NOTE_FREQS[ki], 0.35, 0.5)


func _tap_at(world_pos: Vector3) -> void:
	if state != ST_INPUT:
		return
	var best := -1
	var best_d := TAP_RADIUS
	for i in range(keys.size()):
		var k: Dictionary = keys[i]
		var node: MeshInstance3D = k["node"]
		if not is_instance_valid(node):
			continue
		var d := world_pos.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_tap_key(best)


func _tap_key(ki: int) -> void:
	if state != ST_INPUT:
		return
	_light_key(ki, 2.2)
	_play_key_tone(ki)
	var k: Dictionary = keys[ki]
	var node: MeshInstance3D = k["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position + Vector3(0, 0.1, 0), Color(0.8, 0.7, 1.0), 10)
	if ki == int(sequence[input_idx]):
		notes_hit += 1
		score += 5
		input_idx += 1
		_dim_all()
		if input_idx >= sequence.size():
			var bonus := sequence.size() * 5
			score += bonus
			_show_msg("Round clear! +%d" % bonus, 1.2)
			state = ST_SHOW # pause input until next round starts
			next_round_timer = 1.0
	else:
		mistakes += 1
		_sfx("wrong", 150.0, 0.3, 0.55)
		_dim_all()
		if mistakes >= 3:
			_game_over()
		else:
			_show_msg("Wrong key! (%d/3)" % mistakes, 1.2)
			input_idx = 0
			# Replay the sequence so the player can try again.
			state = ST_SHOW
			show_idx = 0
			show_timer = 0.9


func _game_over() -> void:
	state = ST_OVER
	_dim_all()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	if score >= 100:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.4), 80)
	_sfx("lose", 110.0, 0.6, 0.55)
	_show_msg("THE PIANO FALLS SILENT\nScore: %d  (%d notes, round %d)\nHold pinch 1s or press R" % [score, notes_hit, sequence.size()], 600.0)
	_update_hud()


func _reset_game() -> void:
	sequence.clear()
	state = ST_SHOW
	score = 0
	mistakes = 0
	notes_hit = 0
	show_idx = 0
	show_timer = 1.0
	input_idx = 0
	next_round_timer = 0.0
	elapsed = 0.0
	_pinch_hold = 0.0
	_dim_all()
	_show_msg("", 0.01)
	_update_hud()
	_next_round()
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
