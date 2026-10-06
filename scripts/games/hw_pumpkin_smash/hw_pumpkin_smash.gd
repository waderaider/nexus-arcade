## HwPumpkinSmash - "Pumpkin Smash": a Halloween whack-a-mole.
## Pumpkins pop up from the floor in an arc in front of the player.
## Grab the mallet with the mouse (or a pinch in XR) and smash them
## before they sink back down. 10 points per smash plus 5 per combo
## step for chained quick hits. 75-second rounds with score + restart.
extends Node3D

const ROUND_TIME := 75.0
const SMASH_RADIUS := 0.45
const COMBO_WINDOW := 1.6
const ST_PLAY := 0
const ST_OVER := 1
const PH_HIDE := 0
const PH_UP := 1
const PH_SHOW := 2
const PH_DOWN := 3

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var smashed := 0
var spawn_timer := 0.0
var elapsed := 0.0
var pumpkins: Array = [] # dicts: root, glow_mat, phase, phase_t, show_time
var mallet: Node3D = null
var mallet_tip := Vector3.ZERO
var swing_timer := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var hit_player: AudioStreamPlayer = null
var pop_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_add_light_rig()
	_ensure_fallback_camera()
	_build_moon()
	_build_spots_and_pumpkins()
	_build_mallet()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, "hw_pumpkin_smash_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, -1.0), 2.5, 36)
	hit_player = _make_player(_make_tone(180.0, 0.12, 0.7))
	pop_player = _make_player(_make_tone(520.0, 0.10, 0.5))
	miss_player = _make_player(_make_tone(240.0, 0.08, 0.35))
	end_player = _make_player(_make_tone(660.0, 0.5, 0.5))


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
	camera.position = Vector3(0.0, 1.7, 2.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.4, -1.2), Vector3.UP)
	camera.current = true


func _build_moon() -> void:
	var moon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	moon.mesh = sphere
	moon.position = Vector3(2.8, 3.2, -4.5)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.92, 0.75), 1.2)
	add_child(moon)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 1.5, -1.0), Color(1.0, 0.6, 0.2), 0.6, 6.0)


func _build_spots_and_pumpkins() -> void:
	for i in range(5):
		var a := deg_to_rad(-50.0 + float(i) * 25.0)
		var spot := Vector3(sin(a) * 1.5, 0.0, -cos(a) * 1.5)
		# Dirt mound marker for each spawn spot.
		var mound := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.30
		disc.bottom_radius = 0.34
		disc.height = 0.06
		mound.mesh = disc
		mound.position = spot + Vector3(0.0, 0.03, 0.0)
		mound.material_override = GraphicsPolish.pbr(Color(0.16, 0.10, 0.06), 0.0, 0.95)
		add_child(mound)
		pumpkins.append(_build_pumpkin(spot))


func _build_pumpkin(spot: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = spot + Vector3(0.0, -0.45, 0.0)
	root.visible = false
	add_child(root)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.85, 1.0)
	body.position = Vector3(0.0, 0.20, 0.0)
	body.material_override = GraphicsPolish.pbr(Color(1.0, 0.45, 0.05), 0.1, 0.55)
	root.add_child(body)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.03
	stem_mesh.bottom_radius = 0.05
	stem_mesh.height = 0.12
	stem.mesh = stem_mesh
	stem.position = Vector3(0.0, 0.40, 0.0)
	stem.material_override = GraphicsPolish.pbr(Color(0.25, 0.35, 0.12), 0.0, 0.9)
	root.add_child(stem)
	# Glowing jack-o'-lantern face.
	var face_mat := GraphicsPolish.glow(Color(1.0, 0.85, 0.25), 1.8)
	for ex in [-0.08, 0.08]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 0.26, 0.175)
		eye.material_override = face_mat
		root.add_child(eye)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(0.16, 0.03, 0.02)
	mouth.mesh = mouth_mesh
	mouth.position = Vector3(0.0, 0.14, 0.20)
	mouth.material_override = face_mat
	root.add_child(mouth)
	return {"root": root, "glow_mat": face_mat, "phase": PH_HIDE, "phase_t": 0.0, "show_time": 1.5}


func _build_mallet() -> void:
	mallet = Node3D.new()
	mallet.position = Vector3(0.0, 0.35, -1.0)
	add_child(mallet)
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.035
	handle_mesh.bottom_radius = 0.04
	handle_mesh.height = 0.5
	handle.mesh = handle_mesh
	handle.position = Vector3(0.0, 0.25, 0.0)
	handle.material_override = GraphicsPolish.pbr(Color(0.45, 0.28, 0.14), 0.05, 0.7)
	mallet.add_child(handle)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.30, 0.15, 0.15)
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.52, 0.0)
	head.material_override = GraphicsPolish.pbr(Color(0.7, 0.2, 0.1), 0.2, 0.5)
	mallet.add_child(head)
	mallet.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.2), 0.05))
	mallet_tip = mallet.position


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("PUMPKIN SMASH", 44, Color(1.0, 0.7, 0.2))
	hud_label.position = Vector3(-2.6, 2.4, -1.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.6, -1.8)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	for pv in pumpkins:
		var p: Dictionary = pv
		GraphicsPolish.pulse_glow(p["glow_mat"], 1.4, 0.8, elapsed + float(pv.hash()) * 0.001)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			pinch_hold += delta
			if pinch_hold >= 1.0:
				_reset_game()
				return
		else:
			pinch_hold = 0.0
		return
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_pumpkin_smash_main", global_transform)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
	# Spawn logic: keep 1-3 pumpkins up at once.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = 0.45 + rng.randf() * 0.7
		_pop_one()
	for pv in pumpkins:
		_step_pumpkin(pv, delta)
	_update_mallet(delta)
	_poll_swing()
	if swing_timer > 0.0:
		swing_timer -= delta
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY:
			_try_smash()


func _poll_swing() -> void:
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_smash()


func _pop_one() -> void:
	var hidden: Array = []
	for pv in pumpkins:
		var p: Dictionary = pv
		if int(p["phase"]) == PH_HIDE:
			hidden.append(p)
	if hidden.is_empty():
		return
	var pick: Dictionary = hidden[rng.randi_range(0, hidden.size() - 1)]
	pick["phase"] = PH_UP
	pick["phase_t"] = 0.0
	var root: Node3D = pick["root"]
	root.visible = true
	root.position.y = -0.45
	if pop_player != null:
		pop_player.play()


func _step_pumpkin(pv: Variant, delta: float) -> void:
	var p: Dictionary = pv
	var phase := int(p["phase"])
	if phase == PH_HIDE:
		return
	var root: Node3D = p["root"]
	var t := float(p["phase_t"])
	match phase:
		PH_UP:
			t += delta
			var k := clampf(t / 0.35, 0.0, 1.0)
			root.position.y = lerpf(-0.45, 0.0, k)
			if k >= 1.0:
				p["phase"] = PH_SHOW
				t = 0.0
				p["show_time"] = 1.5 + rng.randf() * 0.9
		PH_SHOW:
			t += delta
			if t >= float(p["show_time"]):
				p["phase"] = PH_DOWN
				t = 0.0
		PH_DOWN:
			t += delta
			var k2 := clampf(t / 0.3, 0.0, 1.0)
			root.position.y = lerpf(0.0, -0.45, k2)
			if k2 >= 1.0:
				p["phase"] = PH_HIDE
				root.visible = false
	p["phase_t"] = t


func _try_smash() -> void:
	swing_timer = 0.22
	var hit_any := false
	for pv in pumpkins:
		var p: Dictionary = pv
		var phase := int(p["phase"])
		if phase != PH_UP and phase != PH_SHOW:
			continue
		var root: Node3D = p["root"]
		var d := Vector2(root.position.x - mallet_tip.x, root.position.z - mallet_tip.z).length()
		if d < SMASH_RADIUS:
			_smash(p)
			hit_any = true
	if not hit_any and miss_player != null:
		miss_player.play()


func _smash(p: Dictionary) -> void:
	var root: Node3D = p["root"]
	GraphicsPolish.spawn_sparks(self, root.position + Vector3(0.0, 0.25, 0.0), Color(1.0, 0.55, 0.1), 26)
	if combo_timer > 0.0:
		combo += 1
	else:
		combo = 1
	combo_timer = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	score += 10 + 5 * (combo - 1)
	smashed += 1
	p["phase"] = PH_HIDE
	root.visible = false
	if hit_player != null:
		hit_player.play()
	_show_msg("+%d  x%d COMBO" % [10 + 5 * (combo - 1), combo], 0.8)


func _update_mallet(delta: float) -> void:
	var target := Vector3(0.0, 0.35, -1.2)
	if ARUpgradeKit.is_xr_active():
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		target = Vector3(pp.x, 0.35, pp.z)
	elif camera != null:
		target = _mouse_floor_point(0.35)
	target = ARUpgradeKit.clamp_to_room(target)
	mallet.position = mallet.position.lerp(target, clampf(14.0 * delta, 0.0, 1.0))
	mallet_tip = mallet.position
	var swing_k := clampf(swing_timer / 0.22, 0.0, 1.0)
	mallet.rotation.x = -0.55 - 1.1 * swing_k


func _mouse_floor_point(y: float) -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.001:
		return Vector3(0.0, y, -1.2)
	var t := (y - ro.y) / rd.y
	return ro + rd * t


func _game_over() -> void:
	state = ST_OVER
	_show_msg("TIME UP!\nScore: %d   Smashed: %d   Best combo x%d\nPress R or pinch-hold to restart" % [score, smashed, best_combo], 600.0)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.5, -1.2), 60)
	ARUpgradeKit.save_anchor("hw_pumpkin_smash_main", global_transform)
	if end_player != null:
		end_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	combo = 0
	combo_timer = 0.0
	best_combo = 0
	smashed = 0
	spawn_timer = 0.0
	pinch_hold = 0.0
	for pv in pumpkins:
		var p: Dictionary = pv
		p["phase"] = PH_HIDE
		var root: Node3D = p["root"]
		root.visible = false
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_pumpkin_smash_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	var combo_txt := "  COMBO x%d" % combo if combo > 1 else ""
	hud_label.text = "PUMPKIN SMASH\nTime: %ds   Score: %d%s" % [int(ceil(time_left)), score, combo_txt]


func _show_msg(text: String, duration: float) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (smash / pop / miss / jingle).
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
