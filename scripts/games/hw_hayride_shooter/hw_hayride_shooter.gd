## HwHayrideShooter - "Hayride Shooter": an on-rails haunted hayride.
## The spooky scene scrolls past your cart; aim with your hand (pointer ray)
## and pinch (or click) to shoot ghosts. +25 per ghost, +100 golden. 90s.
extends Node3D

const ST_PLAY := 0
const ST_OVER := 1
const ROUND_TIME := 90.0
const GHOST_POINTS := 25
const GOLDEN_POINTS := 100
const SHOOT_RADIUS := 0.65
const RIDE_SPEED := 2.2
const TRACK_LEN := 26.0
const ANCHOR_NAME := "hw_hayride_shooter_main"

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var hits := 0
var shots := 0
var elapsed := 0.0
var ghost_timer := 0.8
var scenery: Array = [] # dicts: node
var ghosts: Array = [] # dicts: node, mat, golden, bob_phase, die_t
var crosshair: MeshInstance3D = null
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
	_build_cart()
	_build_sky()
	for i in range(26):
		_spawn_scenery(randf_range(-TRACK_LEN, 4.0))
	_build_hud()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.8, -6.0), 4.0, 50)


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.6)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.75, 3.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -8.0), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.25, 0.6)


func _build_cart() -> void:
	# Wooden cart the player rides in (fixed near the camera).
	var crate := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.6, 0.5, 1.2)
	crate.mesh = cm
	crate.position = Vector3(0.0, 0.35, 2.6)
	crate.material_override = _mat(Color(0.32, 0.20, 0.11))
	add_child(crate)
	var hay := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.4, 0.28, 1.0)
	hay.mesh = hm
	hay.position = Vector3(0.0, 0.68, 2.6)
	hay.material_override = _mat(Color(0.72, 0.58, 0.25))
	add_child(hay)
	# Aim crosshair follows the hand pointer.
	crosshair = MeshInstance3D.new()
	var xm := SphereMesh.new()
	xm.radius = 0.035
	xm.height = 0.07
	crosshair.mesh = xm
	crosshair.material_override = GraphicsPolish.glow(Color(1.0, 0.3, 0.2), 2.2)
	add_child(crosshair)


func _build_sky() -> void:
	var moon := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.6
	disc.height = 0.1
	moon.mesh = disc
	moon.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	moon.position = Vector3(-4.0, 4.5, -22.0)
	moon.material_override = _mat(Color(0.95, 0.93, 0.75), 1.7)
	add_child(moon)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 3.0, -8.0), Color(0.7, 0.8, 1.0), 0.6, 12.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("HAYRIDE SHOOTER", 44, Color(1.0, 0.7, 0.3))
	hud_label.position = Vector3(-3.0, 3.1, -4.0)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Aim with your hand, pinch or click to shoot ghosts | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-3.0, 2.6, -4.0)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.3, -5.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	var acc := 0.0
	if shots > 0:
		acc = 100.0 * float(hits) / float(shots)
	hud_label.text = "HAYRIDE SHOOTER   %ds   Score: %d\nHits: %d/%d (%.0f%%)" % [int(ceil(maxf(time_left, 0.0))), score, hits, shots, acc]


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
	# Crosshair tracks the hand pointer.
	if crosshair != null:
		crosshair.global_position = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	# Shoot on pinch.
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		_shoot(ray[0], ray[1])
	# Scroll the scenery past the cart; recycle behind.
	for s_v in scenery:
		var s: Dictionary = s_v
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			continue
		node.position.z += RIDE_SPEED * delta
		if node.position.z > 5.0:
			node.position.z -= TRACK_LEN
			node.position.x = randf_range(-6.0, 6.0)
	# Ghosts drift toward the cart and bob.
	ghost_timer -= delta
	if ghost_timer <= 0.0:
		_spawn_ghost()
		ghost_timer = randf_range(0.9, 1.7)
	_step_ghosts(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY and camera != null:
			_shoot(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))


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


func _shoot(origin: Vector3, dir: Vector3) -> void:
	if state != ST_PLAY:
		return
	shots += 1
	_sfx("shot", 340.0, 0.09, 0.4)
	var best := -1
	var best_d := SHOOT_RADIUS
	for i in range(ghosts.size()):
		var g: Dictionary = ghosts[i]
		var node: Node3D = g["node"]
		if not is_instance_valid(node) or float(g["die_t"]) > 0.0:
			continue
		var d := _ray_distance(origin, dir, node.global_position + Vector3(0.0, 0.1, 0.0))
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		_sfx("miss", 200.0, 0.08, 0.3)
		return
	var g: Dictionary = ghosts[best]
	var node: Node3D = g["node"]
	var golden := bool(g["golden"])
	var gain := GOLDEN_POINTS if golden else GHOST_POINTS
	score += gain
	hits += 1
	GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.85, 0.3) if golden else Color(0.85, 0.95, 1.0), 26)
	_sfx("hit_gold" if golden else "hit", 1180.0 if golden else 990.0, 0.16, 0.5)
	g["die_t"] = 0.001 # start dissolve
	_show_msg("+%d%s" % [gain, " GOLD!" if golden else ""], 0.8)


# --------------------------------------------------------------- spawns ----

func _spawn_scenery(z: float) -> void:
	var kind := randi() % 4
	var root := Node3D.new()
	root.position = Vector3(randf_range(-6.0, 6.0), 0.0, z)
	add_child(root)
	match kind:
		0:
			_make_scenery_tree(root)
		1:
			_make_pumpkin(root)
		2:
			_make_fence(root)
		_:
			_make_tombstone(root)
	scenery.append({"node": root})


func _make_scenery_tree(root: Node3D) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.07
	tm.bottom_radius = 0.14
	tm.height = 1.8
	trunk.mesh = tm
	trunk.position.y = 0.9
	trunk.material_override = _mat(Color(0.12, 0.08, 0.06))
	root.add_child(trunk)
	for b in range(3):
		var branch := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.0
		bm.bottom_radius = 0.05
		bm.height = 1.0
		branch.mesh = bm
		branch.position = Vector3(0.0, 1.4 + float(b) * 0.3, 0.0)
		branch.rotation.z = 0.8 + float(b) * 0.4
		branch.rotation.y = float(b) * 2.2
		branch.material_override = _mat(Color(0.10, 0.07, 0.05))
		root.add_child(branch)


func _make_pumpkin(root: Node3D) -> void:
	var p := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.28
	pm.height = 0.44
	p.mesh = pm
	p.position.y = 0.22
	p.scale = Vector3(1.0, 0.85, 1.0)
	p.material_override = GraphicsPolish.glow(Color(1.0, 0.45, 0.08), 0.7)
	root.add_child(p)
	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.03
	sm.bottom_radius = 0.05
	sm.height = 0.16
	stem.mesh = sm
	stem.position.y = 0.48
	stem.material_override = _mat(Color(0.15, 0.25, 0.1))
	root.add_child(stem)


func _make_fence(root: Node3D) -> void:
	var fm := _mat(Color(0.16, 0.11, 0.08))
	for px in [-0.5, 0.5]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.09, 0.8, 0.09)
		post.mesh = pm
		post.position = Vector3(px, 0.4, 0.0)
		post.material_override = fm
		root.add_child(post)
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.1, 0.06, 0.06)
	rail.mesh = rm
	rail.position = Vector3(0.0, 0.58, 0.0)
	rail.material_override = fm
	root.add_child(rail)


func _make_tombstone(root: Node3D) -> void:
	var stone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.6, 0.12)
	stone.mesh = bm
	stone.position.y = 0.3
	stone.rotation.z = randf_range(-0.1, 0.1)
	stone.material_override = _mat(Color(0.40, 0.40, 0.44))
	root.add_child(stone)


func _spawn_ghost() -> void:
	var golden := randi() % 8 == 0
	var root := Node3D.new()
	root.position = Vector3(randf_range(-3.0, 3.0), randf_range(0.9, 2.1), -16.0)
	add_child(root)
	var gmat := GraphicsPolish.glow(Color(1.0, 0.8, 0.2), 1.5) if golden else GraphicsPolish.glow(Color(0.92, 0.95, 1.0), 1.1)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.26
	bm.height = 0.62
	body.mesh = bm
	body.position.y = 0.1
	body.scale = Vector3(1.0, 1.25, 0.9)
	body.material_override = gmat
	root.add_child(body)
	var eye_mat := _mat(Color(0.05, 0.05, 0.08))
	for ex in [-0.10, 0.10]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.045
		em.height = 0.09
		eye.mesh = em
		eye.position = Vector3(ex, 0.22, -0.20)
		eye.material_override = eye_mat
		root.add_child(eye)
	ghosts.append({"node": root, "mat": gmat, "golden": golden, "bob_phase": randf() * TAU, "die_t": 0.0})


func _step_ghosts(delta: float) -> void:
	for i in range(ghosts.size() - 1, -1, -1):
		var g: Dictionary = ghosts[i]
		var node: Node3D = g["node"]
		if not is_instance_valid(node):
			ghosts.remove_at(i)
			continue
		var die_t := float(g["die_t"])
		if die_t > 0.0:
			# Dissolve animation after a hit.
			die_t += delta * 3.0
			g["die_t"] = die_t
			node.scale = Vector3.ONE * maxf(1.0 - die_t, 0.01)
			if die_t >= 1.0:
				node.queue_free()
				ghosts.remove_at(i)
			continue
		node.position.z += RIDE_SPEED * 0.55 * delta
		node.position.y += sin(elapsed * 2.5 + float(g["bob_phase"])) * 0.35 * delta
		node.position.x += sin(elapsed * 1.1 + float(g["bob_phase"])) * 0.3 * delta
		GraphicsPolish.pulse_glow(g["mat"], 0.9, 0.6, elapsed * 2.0 + float(g["bob_phase"]))
		if node.position.z > 3.2:
			node.queue_free()
			ghosts.remove_at(i)


func _game_over() -> void:
	state = ST_OVER
	time_left = 0.0
	for g_v in ghosts:
		var g: Dictionary = g_v
		var node: Node3D = g["node"]
		if is_instance_valid(node):
			node.queue_free()
	ghosts.clear()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.2, -3.0), 80)
	_sfx("win", 880.0, 0.4, 0.5)
	_show_msg("RIDE OVER!\nScore: %d  (%d hits)\nHold pinch 1s or press R" % [score, hits], 600.0)
	_update_hud()


func _reset_game() -> void:
	for g_v in ghosts:
		var g: Dictionary = g_v
		var node: Node3D = g["node"]
		if is_instance_valid(node):
			node.queue_free()
	ghosts.clear()
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	hits = 0
	shots = 0
	elapsed = 0.0
	ghost_timer = 0.8
	_pinch_hold = 0.0
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
