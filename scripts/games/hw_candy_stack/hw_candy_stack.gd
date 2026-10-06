extends Node3D
## HwCandyStack - "Candy Stack": candy corn pieces rain down.
## Pinch (or hold mouse) to grab a falling piece, move it over the plate,
## release to drop it. Stack pieces straight: offset drops topple.
## Tallest stable stack in 90 seconds wins. R restarts; pinch-hold 1s on the
## results screen restarts.

const ROUND_LENGTH := 90.0
const SPAWN_INTERVAL := 1.1
const PIECE_HEIGHT := 0.18
const PLACE_RADIUS := 0.20
const GRAB_RADIUS := 0.5
const GRAVITY := 3.5

const ST_PLAY := 0
const ST_OVER := 1
const P_FALLING := 0
const P_HELD := 1
const P_PLACED := 2
const P_DEAD := 3

var camera: Camera3D = null
var state := ST_PLAY
var round_time := 0.0
var spawn_timer := 0.0
var score := 0
var toppled := 0
var stack_top_y := 0.0
var pieces: Array = [] # dicts: node, vy, pstate, drift, dead_timer
var held: Dictionary = {}
var has_held := false
var hud_label: Label3D = null
var msg_label: Label3D = null
var plate_mat: StandardMaterial3D = null
var mouse_pos := Vector2.ZERO
var mouse_held := false
var grab_player: AudioStreamPlayer = null
var place_player: AudioStreamPlayer = null
var topple_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0

const PLATE_POS := Vector3(0.0, 0.75, -1.6)


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	mouse_pos = get_viewport().get_visible_rect().size * 0.5
	_build_table()
	_build_hud()
	grab_player = _make_player(_make_tone(520.0, 0.08, 0.5))
	place_player = _make_player(_make_tone(700.0, 0.12, 0.55))
	topple_player = _make_player(_make_tone(190.0, 0.3, 0.55))
	win_player = _make_player(_make_tone(820.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_candy_stack_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.6), 2.5, 50)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 1.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -1.6), Vector3.UP)
	camera.current = true


func _build_table() -> void:
	# Table.
	var table := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.6, 0.08, 1.2)
	table.mesh = tb
	table.position = Vector3(0.0, 0.68, -1.6)
	table.material_override = GraphicsPolish.pbr(Color(0.35, 0.22, 0.12), 0.05, 0.7)
	add_child(table)
	# Plate.
	var plate := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.36
	pc.bottom_radius = 0.30
	pc.height = 0.05
	plate.mesh = pc
	plate.position = PLATE_POS
	plate_mat = GraphicsPolish.glow(Color(1.0, 0.75, 0.25), 0.8)
	plate.material_override = plate_mat
	add_child(plate)
	stack_top_y = PLATE_POS.y + 0.03
	# Candy bowl backdrop glow.
	GraphicsPolish.make_point_light(self, Vector3(0.0, 1.6, -1.6), Color(1.0, 0.6, 0.2), 0.8, 4.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("CANDY STACK", 44, Color(1.0, 0.75, 0.3))
	hud_label.position = Vector3(-2.7, 2.7, -0.4)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.2, -1.6)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("Pinch / HOLD mouse to grab candy corn, release over the plate!  R: restart", 28, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.35, -0.4)
	add_child(help)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			mouse_held = mb.pressed


func _pointer_world() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return Vector3(0.0, 1.3, -1.6)
	var o := camera.project_ray_origin(mouse_pos)
	var d := camera.project_ray_normal(mouse_pos)
	if absf(d.y) < 0.001:
		return Vector3(0.0, 1.3, -1.6)
	var t := (1.3 - o.y) / d.y
	if t < 0.0:
		return Vector3(0.0, 1.3, -1.6)
	return o + d * t


func _pinch_down() -> bool:
	if mouse_held:
		return true
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_candy_stack_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			restart_hold += delta
			if restart_hold >= 1.0:
				_reset_game()
				return
		else:
			restart_hold = 0.0
		return
	round_time += delta
	if round_time >= ROUND_LENGTH:
		_game_over()
		return
	# Spawn falling candy corn.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		_spawn_piece()
	_update_grab()
	_step_pieces(delta)
	GraphicsPolish.pulse_glow(plate_mat, 0.6, 0.5, round_time, 2.5)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _spawn_piece() -> void:
	var node := _build_candy_corn()
	node.position = Vector3(randf_range(-0.8, 0.8), 2.7, -1.6 + randf_range(-0.3, 0.3))
	node.rotation.y = randf() * TAU
	add_child(node)
	pieces.append({
		"node": node, "vy": 0.0, "pstate": P_FALLING,
		"drift": randf_range(-0.15, 0.15), "dead_timer": 0.0,
	})


func _build_candy_corn() -> MeshInstance3D:
	# Candy corn: yellow base, orange middle, white tip.
	var root := MeshInstance3D.new()
	var segs := [
		[Color(0.95, 0.75, 0.15), 0.10, 0.10],
		[Color(0.95, 0.45, 0.10), 0.10, 0.07],
		[Color(0.96, 0.94, 0.88), 0.07, 0.0],
	]
	var y := -PIECE_HEIGHT * 0.5
	for s in segs:
		var col: Color = s[0]
		var rb: float = s[1]
		var rt: float = s[2]
		var cyl := CylinderMesh.new()
		cyl.bottom_radius = rb
		cyl.top_radius = rt
		cyl.height = 0.06
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = GraphicsPolish.pbr(col, 0.0, 0.5)
		mi.position = Vector3(0.0, y + 0.03, 0.0)
		root.add_child(mi)
		y += 0.06
	return root


func _update_grab() -> void:
	var want_grab := _pinch_down()
	if want_grab and not has_held:
		var pp := _pointer_world()
		var best := -1
		var best_d := GRAB_RADIUS
		for i in range(pieces.size()):
			var p: Dictionary = pieces[i]
			if int(p["pstate"]) != P_FALLING:
				continue
			var node: MeshInstance3D = p["node"]
			if not is_instance_valid(node):
				continue
			var d: float = (node.global_position - pp).length()
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			held = pieces[best]
			has_held = true
			held["pstate"] = P_HELD
			if grab_player != null:
				grab_player.play()
	elif has_held:
		var node: MeshInstance3D = held["node"]
		if is_instance_valid(node):
			if want_grab:
				var pp := _pointer_world()
				node.global_position = node.global_position.lerp(pp + Vector3(0, 0.05, 0), 0.35)
				node.rotation.y += 0.02
			else:
				held["pstate"] = P_FALLING
				held["vy"] = 0.0
				has_held = false
				held = {}
		else:
			has_held = false
			held = {}


func _step_pieces(delta: float) -> void:
	for i in range(pieces.size() - 1, -1, -1):
		var p: Dictionary = pieces[i]
		var node: MeshInstance3D = p["node"]
		if not is_instance_valid(node):
			pieces.remove_at(i)
			continue
		var st := int(p["pstate"])
		if st == P_FALLING:
			p["vy"] = float(p["vy"]) - GRAVITY * delta
			node.position.y += float(p["vy"]) * delta
			node.position.x += float(p["drift"]) * delta
			node.rotation.y += delta * 0.6
			if node.position.y <= stack_top_y + PIECE_HEIGHT * 0.5:
				_land_piece(i, p, node)
		elif st == P_DEAD:
			p["dead_timer"] = float(p["dead_timer"]) + delta
			node.position.y -= delta * 1.2
			node.rotation.z += delta * 5.0
			if float(p["dead_timer"]) > 1.2:
				node.queue_free()
				pieces.remove_at(i)


func _land_piece(i: int, p: Dictionary, node: MeshInstance3D) -> void:
	var flat := Vector2(node.position.x - PLATE_POS.x, node.position.z - PLATE_POS.z).length()
	if flat <= PLACE_RADIUS:
		p["pstate"] = P_PLACED
		node.position = Vector3(PLATE_POS.x + (node.position.x - PLATE_POS.x) * 0.4, stack_top_y + PIECE_HEIGHT * 0.5, PLATE_POS.z + (node.position.z - PLATE_POS.z) * 0.4)
		node.rotation = Vector3.ZERO
		stack_top_y += PIECE_HEIGHT * 0.92
		score += 1
		_show_msg("NICE!  %d" % score, 0.8)
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.8, 0.3), 14)
		if place_player != null:
			place_player.pitch_scale = 1.0 + minf(score, 20) * 0.02
			place_player.play()
	else:
		p["pstate"] = P_DEAD
		p["dead_timer"] = 0.0
		toppled += 1
		_show_msg("TOPPLED!", 0.9)
		if topple_player != null:
			topple_player.play()


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := int(maxf(0.0, ROUND_LENGTH - round_time))
	hud_label.text = "CANDY STACK\nStacked: %d   Toppled: %d\nHeight: %.2fm   Time: %ds" % [
		score, toppled, score * PIECE_HEIGHT * 0.92, left]


func _game_over() -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_candy_stack_main", global_transform)
	_show_msg("TIME!\n%d stacked (%.2fm)\nR: play again" % [score, score * PIECE_HEIGHT * 0.92], 600.0)
	if win_player != null:
		win_player.play()
	if score >= 8:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.6), 80)


func _reset_game() -> void:
	for p_v in pieces:
		var p: Dictionary = p_v
		var node: MeshInstance3D = p["node"]
		if is_instance_valid(node):
			node.queue_free()
	pieces.clear()
	held = {}
	has_held = false
	round_time = 0.0
	spawn_timer = 0.0
	score = 0
	toppled = 0
	stack_top_y = PLATE_POS.y + 0.03
	restart_hold = 0.0
	state = ST_PLAY
	_show_msg("STACK 'EM HIGH!", 1.2)
	ARUpgradeKit.save_anchor("hw_candy_stack_main", global_transform)


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
