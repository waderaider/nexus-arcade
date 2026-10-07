## HwSpiderCatch - "Spider Catch": spiders descend on silk webs from above.
## Pinch-grab (or click) each spider before it reaches the floor. 60s round,
## +10 per catch. Spiders that reach the floor escape (no penalty).
extends Node3D

const ST_PLAY := 0
const ST_OVER := 1
const ROUND_TIME := 60.0
const CATCH_POINTS := 10
const SPAWN_TOP := 3.1
const CEILING_Y := 3.35
const FLOOR_Y := 0.07
const GRAB_RADIUS := 0.55
const ANCHOR_NAME := "hw_spider_catch_main"

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var caught := 0
var escaped := 0
var elapsed := 0.0
var spawn_timer := 0.5
var spiders: Array = [] # dicts: node, web, eyes_mat, speed, sway_phase
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
# v0.7.0: morphed plant nest the spiders drop out of (game-local coords).
var _room_nest_pos := Vector3.ZERO
var _room_nest_known := false


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_room()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.8, -1.0), 2.5, 36)
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
	# v0.7.0 furniture morph: the real plant becomes an overgrown
	# web-nest the spiders drop out of (see _spider_spawn_pos).
	var plant_anchors := RoomKit.get_anchors("PLANT")
	if not plant_anchors.is_empty():
		RoomKit.morph(plant_anchors[0], "nature")
		_room_nest_pos = plant_anchors[0]["position"]
		_room_nest_known = true


## Wall normal flipped to point into the room (normals are sign-agnostic).
func _wall_inward(w: Dictionary) -> Vector3:
	var n: Vector3 = w["normal"]
	n.y = 0.0
	if n.length() < 0.01:
		return Vector3(0.0, 0.0, 1.0)
	n = n.normalized()
	var c := _room_bounds.get_center()
	var wp: Vector3 = w["position"]
	if n.dot(Vector3(c.x, 0.0, c.y) - Vector3(wp.x, 0.0, wp.z)) < 0.0:
		n = -n
	return n


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
	camera.position = Vector3(0.0, 1.7, 3.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.4, -1.0), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.25, 0.55)


func _build_room() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, 0.0, -1.0)
	floor_inst.material_override = _mat(Color(0.10, 0.07, 0.16))
	add_child(floor_inst)
	# Dark branch bar the webs hang from.
	var branch := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(4.4, 0.22, 0.3)
	branch.mesh = bbox
	branch.position = Vector3(0.0, CEILING_Y, -1.0)
	branch.material_override = _mat(Color(0.16, 0.10, 0.07))
	add_child(branch)
	# Spooky orange rim light.
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.6, -1.0), Color(1.0, 0.45, 0.1), 0.8, 6.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("SPIDER CATCH", 44, Color(1.0, 0.75, 0.4))
	hud_label.position = Vector3(-2.6, 2.9, -2.6)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Pinch or click spiders before they hit the floor | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-2.6, 2.45, -2.6)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -3.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "SPIDER CATCH   %ds   Score: %d\nCaught: %d   Escaped: %d" % [int(ceil(maxf(time_left, 0.0))), score, caught, escaped]


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
		return
	# Round timer.
	time_left -= delta
	if time_left <= 0.0:
		_game_over()
		return
	# Pinch-grab check (XR + mouse fallback inside pinch_active).
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		_try_grab(ray[0], ray[1])
	# Spawning (ramps up over the round).
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_spider()
		var interval := maxf(0.45, 1.1 - elapsed * 0.012)
		spawn_timer = interval * randf_range(0.7, 1.3)
	_step_spiders(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY and camera != null:
			_try_grab(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))


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


func _try_grab(origin: Vector3, dir: Vector3) -> void:
	if state != ST_PLAY:
		return
	var best := -1
	var best_d := GRAB_RADIUS
	for i in range(spiders.size()):
		var s: Dictionary = spiders[i]
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			continue
		var d := _ray_distance(origin, dir, node.global_position)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	var s: Dictionary = spiders[best]
	var node: Node3D = s["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.45, 0.1), 22)
	node.queue_free()
	spiders.remove_at(best)
	score += CATCH_POINTS
	caught += 1
	_sfx("catch", 660.0, 0.12, 0.5)
	_show_msg("Caught! +%d" % CATCH_POINTS, 0.8)


func _spawn_spider() -> void:
	var root := Node3D.new()
	root.position = _spider_spawn_pos()
	add_child(root)
	# Body.
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.09
	bm.height = 0.18
	body.mesh = bm
	body.material_override = _mat(Color(0.09, 0.09, 0.11))
	root.add_child(body)
	# Head + glowing red eyes.
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.055
	hm.height = 0.11
	head.mesh = hm
	head.position = Vector3(0.0, 0.02, -0.10)
	head.material_override = _mat(Color(0.07, 0.07, 0.09))
	root.add_child(head)
	var eyes_mat := GraphicsPolish.glow(Color(1.0, 0.15, 0.1), 2.0)
	for ex in [-0.025, 0.025]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.016
		em.height = 0.032
		eye.mesh = em
		eye.position = Vector3(ex, 0.045, -0.145)
		eye.material_override = eyes_mat
		root.add_child(eye)
	# Eight legs.
	var leg_mat := _mat(Color(0.05, 0.05, 0.07))
	for i in range(8):
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.17, 0.015, 0.015)
		leg.mesh = lm
		leg.material_override = leg_mat
		var side := -1.0 if i < 4 else 1.0
		var row := i % 4
		leg.position = Vector3(side * 0.10, -0.01, -0.06 + float(row) * 0.045)
		leg.rotation.y = side * (0.55 + float(row) * 0.18)
		leg.rotation.z = side * -0.4
		root.add_child(leg)
	# Silk web strand up to the branch (scaled each frame).
	var web := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.008, 1.0, 0.008)
	web.mesh = wm
	web.material_override = _mat(Color(0.75, 0.75, 0.8))
	root.add_child(web)
	spiders.append({
		"node": root, "web": web, "eyes_mat": eyes_mat,
		"speed": randf_range(0.35, 0.65) + elapsed * 0.004,
		"sway_phase": randf() * TAU,
	})


func _spider_spawn_pos() -> Vector3:
	# Spiders drop from the real wall faces when the room is known,
	# otherwise from a room-bounds-clamped patch of ceiling.
	# The morphed plant is an overgrown nest: some spiders drop from
	# directly above it.
	if _room_nest_known and randf() < 0.4:
		return Vector3(
			_room_nest_pos.x + randf_range(-0.25, 0.25), SPAWN_TOP,
			_room_nest_pos.z + randf_range(-0.25, 0.25))
	if _room_known and not _room_walls.is_empty() and randf() < 0.6:
		var w: Dictionary = _room_walls[randi() % _room_walls.size()]
		var bp: Vector3 = (w["position"] as Vector3) + _wall_inward(w) * 0.25
		return Vector3(bp.x, SPAWN_TOP, bp.z)
	if _room_known:
		var c := _room_bounds.get_center()
		var hx := maxf(0.6, _room_bounds.size.x * 0.5 - 0.5)
		var hz := maxf(0.6, _room_bounds.size.y * 0.5 - 0.5)
		return Vector3(c.x + randf_range(-hx, hx), SPAWN_TOP, c.y + randf_range(-hz, hz))
	return Vector3(randf_range(-1.6, 1.6), SPAWN_TOP, randf_range(-2.6, 0.4))


func _step_spiders(delta: float) -> void:
	for i in range(spiders.size() - 1, -1, -1):
		var s: Dictionary = spiders[i]
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			spiders.remove_at(i)
			continue
		node.position.y -= float(s["speed"]) * delta
		node.position.x += sin(elapsed * 2.0 + float(s["sway_phase"])) * 0.25 * delta
		node.rotation.y = sin(elapsed * 1.3 + float(s["sway_phase"])) * 0.4
		# Stretch the web strand from the body up to the branch.
		var web: MeshInstance3D = s["web"]
		var dist := CEILING_Y - node.position.y
		web.scale.y = maxf(dist, 0.05)
		web.position.y = dist * 0.5 + 0.04
		GraphicsPolish.pulse_glow(s["eyes_mat"], 1.5, 1.0, elapsed * 3.0 + float(s["sway_phase"]))
		if node.position.y <= FLOOR_Y:
			node.queue_free()
			spiders.remove_at(i)
			escaped += 1
			_sfx("escape", 150.0, 0.25, 0.45)
			_show_msg("It got away!", 0.9)


func _game_over() -> void:
	state = ST_OVER
	time_left = 0.0
	for s_v in spiders:
		var s: Dictionary = s_v
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
	spiders.clear()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.5), 70)
	_sfx("win", 880.0, 0.4, 0.5)
	_show_msg("TIME UP!\nScore: %d  (%d caught)\nHold pinch 1s or press R" % [score, caught], 600.0)
	_update_hud()


func _reset_game() -> void:
	for s_v in spiders:
		var s: Dictionary = s_v
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
	spiders.clear()
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	caught = 0
	escaped = 0
	elapsed = 0.0
	spawn_timer = 0.5
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
