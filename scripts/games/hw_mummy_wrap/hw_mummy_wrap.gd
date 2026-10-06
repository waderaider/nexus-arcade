extends Node3D
## HwMummyWrap - "Mummy Wrap": a mummy spins on a pedestal.
## Hold pinch (or mouse button) and make circular motions around the mummy
## to wind bandages. Each full turn adds a glowing bandage ring.
## Complete all 10 wraps as fast as you can — 90s limit.
## R restarts; pinch-hold 1s on the results screen restarts.

const ROUND_LENGTH := 90.0
const TURNS_TO_WIN := 10
const SPIN_SPEED := 1.1
const WIND_RADIUS := 1.6

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var round_time := 0.0
var total_angle := 0.0
var prev_angle := 0.0
var has_prev := false
var turns_done := 0
var won := false
var mummy: Node3D = null
var mummy_pos := Vector3(0.0, 0.8, -1.8)
var bandage_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var progress_label: Label3D = null
var mouse_pos := Vector2.ZERO
var wrap_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	mouse_pos = get_viewport().get_visible_rect().size * 0.5
	_build_scene()
	_build_hud()
	wrap_player = _make_player(_make_tone(440.0, 0.12, 0.5))
	win_player = _make_player(_make_tone(880.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_mummy_wrap_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.8), 2.5, 50)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 1.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.1, -1.8), Vector3.UP)
	camera.current = true


func _build_scene() -> void:
	# Pedestal.
	var ped := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.55
	pc.bottom_radius = 0.65
	pc.height = 0.8
	ped.mesh = pc
	ped.position = Vector3(mummy_pos.x, 0.4, mummy_pos.z)
	ped.material_override = GraphicsPolish.pbr(Color(0.30, 0.28, 0.34), 0.2, 0.6)
	add_child(ped)
	# Pedestal glow ring.
	var gring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.60
	tor.outer_radius = 0.68
	gring.mesh = tor
	gring.material_override = GraphicsPolish.glow(Color(0.6, 0.4, 1.0), 1.2)
	gring.position = Vector3(mummy_pos.x, 0.82, mummy_pos.z)
	gring.rotation.x = PI * 0.5
	add_child(gring)
	# Mummy group (spins).
	mummy = Node3D.new()
	mummy.position = mummy_pos
	add_child(mummy)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.26
	cap.height = 1.15
	body.mesh = cap
	body.position = Vector3(0.0, 0.62, 0.0)
	body.material_override = GraphicsPolish.pbr(Color(0.82, 0.74, 0.58), 0.0, 0.85)
	mummy.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.21
	hs.height = 0.42
	head.mesh = hs
	head.position = Vector3(0.0, 1.32, 0.0)
	head.material_override = GraphicsPolish.pbr(Color(0.86, 0.78, 0.62), 0.0, 0.85)
	mummy.add_child(head)
	# Spooky eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.045
		es.height = 0.09
		eye.mesh = es
		eye.material_override = GraphicsPurpleGlow()
		eye.position = Vector3(side * 0.08, 1.36, 0.17)
		mummy.add_child(eye)
	bandage_mat = GraphicsPolish.glow(Color(0.95, 0.92, 0.80), 0.9)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.2, -1.0), Color(0.7, 0.5, 1.0), 0.8, 5.0)


func GraphicsPurpleGlow() -> StandardMaterial3D:
	return GraphicsPolish.glow(Color(0.7, 0.2, 1.0), 2.2)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("MUMMY WRAP", 44, Color(0.85, 0.7, 1.0))
	hud_label.position = Vector3(-2.7, 2.7, -0.4)
	add_child(hud_label)
	progress_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.95, 0.8))
	progress_label.position = Vector3(0.0, 2.45, -1.8)
	add_child(progress_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 1.9, -1.8)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("HOLD pinch / mouse button and circle around the mummy!  R: restart", 28, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.30, -0.4)
	add_child(help)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position


func _pointer_world() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return Vector3(0.6, 1.35, -1.8)
	var o := camera.project_ray_origin(mouse_pos)
	var d := camera.project_ray_normal(mouse_pos)
	if absf(d.y) < 0.001:
		return Vector3(0.6, 1.35, -1.8)
	var t := (1.35 - o.y) / d.y
	if t < 0.0:
		return Vector3(0.6, 1.35, -1.8)
	return o + d * t


func _winding() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_mummy_wrap_main", global_transform)
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
	if mummy != null:
		mummy.rotation.y += SPIN_SPEED * delta
	if round_time >= ROUND_LENGTH:
		_game_over(false)
		return
	# Track circular hand motion around the mummy while winding.
	if _winding():
		var pp := _pointer_world()
		var flat := Vector2(pp.x - mummy_pos.x, pp.z - mummy_pos.z)
		if flat.length() < WIND_RADIUS and flat.length() > 0.15:
			var ang := atan2(flat.y, flat.x)
			if has_prev:
				var d := wrapf(ang - prev_angle, -PI, PI)
				total_angle += absf(d)
				_check_new_turns()
			prev_angle = ang
			has_prev = true
	else:
		has_prev = false
	GraphicsPolish.pulse_glow(bandage_mat, 0.7, 0.5, round_time, 3.0)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _check_new_turns() -> void:
	var turns := int(absf(total_angle) / TAU)
	while turns_done < turns and turns_done < TURNS_TO_WIN:
		turns_done += 1
		_add_bandage_ring(turns_done)
		_show_msg("WRAP %d/%d!" % [turns_done, TURNS_TO_WIN], 0.8)
		GraphicsPolish.spawn_sparks(self, mummy_pos + Vector3(0, 0.6 + turns_done * 0.06, 0), Color(1.0, 0.95, 0.7), 16)
		if wrap_player != null:
			wrap_player.pitch_scale = 0.9 + turns_done * 0.08
			wrap_player.play()
	if turns_done >= TURNS_TO_WIN:
		_game_over(true)


func _add_bandage_ring(n: int) -> void:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.27
	tor.outer_radius = 0.33
	ring.mesh = tor
	ring.material_override = bandage_mat
	# Wrap from the feet upward.
	ring.position = Vector3(0.0, 0.18 + float(n - 1) * (1.05 / TURNS_TO_WIN), 0.0)
	ring.rotation.x = PI * 0.5
	mummy.add_child(ring)
	ring.scale = Vector3.ZERO
	GraphicsPolish.ease_scale(ring, Vector3.ONE, 8.0, 0.016)


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := int(maxf(0.0, ROUND_LENGTH - round_time))
	hud_label.text = "MUMMY WRAP\nTime: %ds   Turns: %.1f" % [left, absf(total_angle) / TAU]
	var bars := ""
	for i in range(TURNS_TO_WIN):
		bars += "#" if i < turns_done else "-"
	progress_label.text = "[%s] %d/%d" % [bars, turns_done, TURNS_TO_WIN]


func _game_over(did_win: bool) -> void:
	state = ST_OVER
	won = did_win
	ARUpgradeKit.save_anchor("hw_mummy_wrap_main", global_transform)
	if did_win:
		var bonus := maxi(0, int((ROUND_LENGTH - round_time) * 20.0))
		var final := 1000 + bonus
		_show_msg("FULLY WRAPPED!\n%.1fs  Score: %d\nR: play again" % [round_time, final], 600.0)
		GraphicsPolish.spawn_confetti(self, mummy_pos + Vector3(0, 1.8, 0), 90)
		if win_player != null:
			win_player.play()
	else:
		_show_msg("TIME!\n%d/%d wraps\nR: try again" % [turns_done, TURNS_TO_WIN], 600.0)


func _reset_game() -> void:
	# Bandage rings are MeshInstance3D children added after body/head/eyes:
	# keep the first four, free the rest.
	if mummy != null:
		var keep := 0
		for child in mummy.get_children():
			if child is MeshInstance3D:
				if keep < 4:
					keep += 1
				else:
					child.queue_free()
	round_time = 0.0
	total_angle = 0.0
	turns_done = 0
	won = false
	has_prev = false
	restart_hold = 0.0
	state = ST_PLAY
	_show_msg("START WINDING!", 1.2)
	ARUpgradeKit.save_anchor("hw_mummy_wrap_main", global_transform)


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
