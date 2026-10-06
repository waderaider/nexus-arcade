extends Node3D
## HwPortraitGallery - "Portrait Gallery": a wall of haunted portraits.
## Each round ONE portrait's ghost stirs and drifts — spot it and pinch-tap
## (or click) the haunted portrait. 10 rounds, faster finds earn speed bonus.
## Wrong portrait: -50. 90 second cap. R restarts; pinch-hold 1s on the
## results screen restarts.

const ROUND_LENGTH := 90.0
const TOTAL_ROUNDS := 10
const PORTRAIT_W := 0.9
const PORTRAIT_H := 1.1

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var round_time := 0.0
var round_num := 1
var round_start := 0.0
var score := 0
var correct := 0
var haunted_idx := -1
var last_haunted := -1
var portraits: Array = [] # dicts: center(Vector3), ghost(Node3D), frame(MeshInstance3D)
var wall_z := -2.2
var hud_label: Label3D = null
var msg_label: Label3D = null
var mouse_pos := Vector2.ZERO
var tap_pending := false
var good_player: AudioStreamPlayer = null
var bad_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	mouse_pos = get_viewport().get_visible_rect().size * 0.5
	_build_gallery()
	_build_hud()
	good_player = _make_player(_make_tone(740.0, 0.14, 0.5))
	bad_player = _make_player(_make_tone(200.0, 0.25, 0.5))
	win_player = _make_player(_make_tone(880.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_portrait_gallery_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.5), 3.0, 50)
	_start_round()


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 1.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, -2.2), Vector3.UP)
	camera.current = true


func _build_gallery() -> void:
	# Wall.
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(5.4, 2.8, 0.15)
	wall.mesh = wb
	wall.position = Vector3(0.0, 1.5, wall_z - 0.08)
	wall.material_override = GraphicsPolish.pbr(Color(0.16, 0.12, 0.18), 0.0, 0.85)
	add_child(wall)
	# Candle sconces.
	for sx in [-2.3, 2.3]:
		GraphicsPolish.make_point_light(self, Vector3(sx, 2.2, wall_z + 0.4), Color(1.0, 0.6, 0.25), 0.7, 4.0)
	# Six portraits in 2 rows x 3 cols.
	var xs := [-1.6, 0.0, 1.6]
	var ys := [2.05, 1.05]
	for row in range(2):
		for col in range(3):
			_build_portrait(Vector3(xs[col], ys[row], wall_z + 0.02))


func _build_portrait(center: Vector3) -> void:
	# Gilded frame.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(PORTRAIT_W + 0.16, PORTRAIT_H + 0.16, 0.08)
	frame.mesh = fb
	frame.position = center
	frame.material_override = GraphicsPolish.pbr(Color(0.55, 0.38, 0.12), 0.7, 0.35)
	add_child(frame)
	# Dark canvas.
	var canvas := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(PORTRAIT_W, PORTRAIT_H, 0.02)
	canvas.mesh = cb
	canvas.position = center + Vector3(0, 0, 0.04)
	canvas.material_override = GraphicsPolish.pbr(Color(0.07, 0.07, 0.10), 0.0, 0.9)
	add_child(canvas)
	# Pale portrait face.
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.17
	hs.height = 0.34
	head.mesh = hs
	head.position = center + Vector3(0, 0.08, 0.10)
	var skin := Color(0.75, 0.68, 0.60).lerp(Color(0.55, 0.60, 0.70), randf())
	head.material_override = GraphicsPolish.pbr(skin, 0.0, 0.7)
	add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.028
		es.height = 0.056
		eye.mesh = es
		eye.material_override = GraphicsPolish.pbr(Color(0.03, 0.03, 0.04), 0.0, 0.5)
		eye.position = center + Vector3(side * 0.07, 0.12, 0.24)
		add_child(eye)
	# The ghost: hidden unless this portrait is haunted.
	var ghost := Node3D.new()
	ghost.position = center + Vector3(0, 0.1, 0.16)
	var orb := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.11
	gs.height = 0.22
	orb.mesh = gs
	orb.material_override = GraphicsPolish.glow(Color(0.75, 0.9, 1.0), 2.2)
	ghost.add_child(orb)
	ghost.add_child(GraphicsPolish.make_trail(Color(0.6, 0.85, 1.0), 0.05))
	ghost.visible = false
	add_child(ghost)
	portraits.append({"center": center, "ghost": ghost, "frame": frame})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("PORTRAIT GALLERY", 40, Color(0.9, 0.8, 1.0))
	hud_label.position = Vector3(-2.7, 2.8, -0.4)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.5, -1.5)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("One ghost stirs each round — CLICK / pinch-tap the haunted portrait!  R: restart", 28, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.25, -0.4)
	add_child(help)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY:
			tap_pending = true


func _aim_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return [Vector3(0, 1.5, 2), Vector3(0, 0, -1)]
	var o := camera.project_ray_origin(mouse_pos)
	var d := camera.project_ray_normal(mouse_pos)
	return [o, d.normalized()]


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_portrait_gallery_main", global_transform)
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
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		tap_pending = true
	if tap_pending:
		tap_pending = false
		_resolve_tap()
	_animate_ghost(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _start_round() -> void:
	# Pick a new haunted portrait (never the same twice in a row).
	var idx := randi() % portraits.size()
	while idx == last_haunted:
		idx = randi() % portraits.size()
	last_haunted = idx
	haunted_idx = idx
	for i in range(portraits.size()):
		var p: Dictionary = portraits[i]
		(p["ghost"] as Node3D).visible = (i == haunted_idx)
	round_start = round_time


func _animate_ghost(delta: float) -> void:
	if haunted_idx < 0 or haunted_idx >= portraits.size():
		return
	var p: Dictionary = portraits[haunted_idx]
	var ghost: Node3D = p["ghost"]
	var center: Vector3 = p["center"]
	var t := round_time - round_start
	# The ghost drifts in a restless orbit — the tell to spot.
	ghost.position = center + Vector3(cos(t * 3.1) * 0.26, 0.10 + sin(t * 4.3) * 0.18, 0.16 + 0.06 * sin(t * 2.2))
	var s := 1.0 + 0.25 * sin(t * 6.0)
	ghost.scale = Vector3(s, s, s)


func _resolve_tap() -> void:
	var ray := _aim_ray()
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	if absf(d.z) < 0.001:
		return
	var t := ((wall_z + 0.06) - o.z) / d.z
	if t < 0.0:
		return
	var hit := o + d * t
	var picked := -1
	for i in range(portraits.size()):
		var p: Dictionary = portraits[i]
		var c: Vector3 = p["center"]
		if absf(hit.x - c.x) < PORTRAIT_W * 0.5 + 0.08 and absf(hit.y - c.y) < PORTRAIT_H * 0.5 + 0.08:
			picked = i
			break
	if picked < 0:
		return # tapped empty wall: no penalty
	if picked == haunted_idx:
		var elapsed := round_time - round_start
		var bonus := maxi(0, 150 - int(elapsed * 30.0))
		var gained := 100 + bonus
		score += gained
		correct += 1
		_show_msg("HAUNTED! +%d" % gained, 1.0)
		var p: Dictionary = portraits[picked]
		GraphicsPolish.spawn_sparks(self, (p["center"] as Vector3) + Vector3(0, 0, 0.3), Color(0.7, 0.9, 1.0), 20)
		if good_player != null:
			good_player.play()
		if round_num >= TOTAL_ROUNDS:
			_game_over()
		else:
			round_num += 1
			_start_round()
	else:
		score = maxi(0, score - 50)
		_show_msg("WRONG PORTRAIT! -50", 1.0)
		if bad_player != null:
			bad_player.play()


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := int(maxf(0.0, ROUND_LENGTH - round_time))
	hud_label.text = "PORTRAIT GALLERY\nRound: %d/%d   Score: %d\nCorrect: %d   Time: %ds" % [
		mini(round_num, TOTAL_ROUNDS), TOTAL_ROUNDS, score, correct, left]


func _game_over() -> void:
	state = ST_OVER
	for p_v in portraits:
		var p: Dictionary = p_v
		(p["ghost"] as Node3D).visible = false
	ARUpgradeKit.save_anchor("hw_portrait_gallery_main", global_transform)
	_show_msg("GALLERY CLOSED!\n%d/%d found  Score: %d\nR: play again" % [correct, TOTAL_ROUNDS, score], 600.0)
	if win_player != null:
		win_player.play()
	if correct >= 8:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.2, -1.5), 90)


func _reset_game() -> void:
	round_time = 0.0
	round_num = 1
	score = 0
	correct = 0
	last_haunted = -1
	restart_hold = 0.0
	state = ST_PLAY
	_start_round()
	_show_msg("SPOT THE GHOST!", 1.2)
	ARUpgradeKit.save_anchor("hw_portrait_gallery_main", global_transform)


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
