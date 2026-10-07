## HwGhostCatch - "Ghost Catch": ghosts float around the room.
## Pinch and hold (or hold the mouse button) to sweep a glowing net
## through the air and catch them. 15 points per ghost. 90-second rounds.
extends Node3D

const ROUND_TIME := 90.0
const GHOST_COUNT := 6
const CATCH_RADIUS := 0.48
const ST_PLAY := 0
const ST_OVER := 1

# v0.7.0 KayKit: spectral skull model (CC0, KayKit Halloween Bits).
const MODEL_DIR := "res://assets/models/hw_ghost_catch/"
const SKULL_MODEL_SCALE := 0.55

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var caught := 0
var elapsed := 0.0
var ghosts: Array = [] # dicts: root, glow_mat, base, speed, phase, phase2, active, respawn_t
var net: Node3D = null
var net_ring: MeshInstance3D = null
var net_mat: StandardMaterial3D = null
var net_active := false
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var catch_player: AudioStreamPlayer = null
var spawn_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()

## RoomKit v0.7.0: cached room layout (world space; converted to local at use).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)


func _ready() -> void:
	rng.randomize()
	_add_light_rig()
	_ensure_fallback_camera()
	_build_moon()
	_build_net()
	_build_hud()
	for i in range(GHOST_COUNT):
		ghosts.append(_build_ghost())
		_respawn_ghost(ghosts[i], true)
	ARUpgradeKit.apply_anchor(self, "hw_ghost_catch_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, 0.0), 2.8, 40)
	catch_player = _make_player(_make_tone(740.0, 0.14, 0.55))
	spawn_player = _make_player(_make_tone(980.0, 0.10, 0.35))
	end_player = _make_player(_make_tone(660.0, 0.5, 0.5))
	_apply_room_layout()


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
	camera.look_at(Vector3(0.0, 1.2, -1.0), Vector3.UP)
	camera.current = true


func _build_moon() -> void:
	var moon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	moon.mesh = sphere
	moon.position = Vector3(-2.6, 3.0, -4.0)
	moon.material_override = GraphicsPolish.glow(Color(0.9, 0.95, 1.0), 1.1)
	add_child(moon)


func _build_ghost() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var glow_mat := GraphicsPolish.glow(Color(0.85, 0.95, 1.0), 1.2)
	var proc_parts: Array = [] # hidden when the real model loads
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	body.mesh = sphere
	body.material_override = glow_mat
	root.add_child(body)
	proc_parts.append(body)
	# Wavy tail: a dark-trimmed cone below the body.
	var tail := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.20
	cone.bottom_radius = 0.06
	cone.height = 0.22
	tail.mesh = cone
	tail.position = Vector3(0.0, -0.28, 0.0)
	tail.material_override = glow_mat
	root.add_child(tail)
	proc_parts.append(tail)
	# Spooky eyes + mouth.
	var dark := GraphicsPolish.pbr(Color(0.05, 0.05, 0.10), 0.0, 0.9)
	for ex in [-0.08, 0.08]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.045
		eye_mesh.height = 0.09
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 0.05, 0.185)
		eye.material_override = dark
		root.add_child(eye)
		proc_parts.append(eye)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.05
	mouth_mesh.height = 0.10
	mouth.mesh = mouth_mesh
	mouth.scale = Vector3(1.0, 1.4, 0.6)
	mouth.position = Vector3(0.0, -0.08, 0.19)
	mouth.material_override = dark
	root.add_child(mouth)
	proc_parts.append(mouth)
	# v0.7.0 KayKit: spectral skull takes over the ghost's look; the
	# procedural sheet-ghost stays as fallback.
	var skull := ModelLib.spawn(MODEL_DIR + "skull.gltf", root, Vector3(0.0, 0.05, 0.0))
	if skull != null:
		skull.scale = Vector3.ONE * SKULL_MODEL_SCALE
		_apply_glow(skull, glow_mat)
		for pp in proc_parts:
			(pp as Node3D).visible = false
	root.visible = false
	return {
		"root": root, "glow_mat": glow_mat, "base": Vector3.ZERO,
		"speed": 1.0, "phase": 0.0, "phase2": 0.0,
		"active": false, "respawn_t": 0.0,
	}


## v0.7.0 KayKit: override every mesh material so the model pulses with glow_mat.
func _apply_glow(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_apply_glow(c, mat)


func _respawn_ghost(gv: Variant, instant: bool = false) -> void:
	var g: Dictionary = gv
	var base := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(1.0, 1.9), rng.randf_range(-2.2, 0.6))
	# RoomKit v0.7.0: ghosts emerge from real wall faces or lurk behind furniture.
	if not _room_walls.is_empty() and rng.randf() < 0.6:
		var ws := _room_wall_face(rng.randf_range(1.0, 1.9), 0.6)
		if ws != Vector3.INF:
			base = ws
	elif (not _room_tables.is_empty() or not _room_furniture.is_empty()) and rng.randf() < 0.35:
		var fs := _room_furniture_lurk(rng.randf_range(1.0, 1.7))
		if fs != Vector3.INF:
			base = fs
	g["base"] = base
	g["speed"] = rng.randf_range(0.6, 1.4)
	g["phase"] = rng.randf_range(0.0, TAU)
	g["phase2"] = rng.randf_range(0.0, TAU)
	if instant:
		g["active"] = true
		g["respawn_t"] = 0.0
		var root: Node3D = g["root"]
		root.visible = true
		root.position = base
	else:
		g["active"] = false
		g["respawn_t"] = 1.1
		var r2: Node3D = g["root"]
		r2.visible = false


func _build_net() -> void:
	net = Node3D.new()
	net.position = Vector3(0.0, 1.2, -1.2)
	add_child(net)
	net_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.30
	net_ring.mesh = torus
	net_mat = GraphicsPolish.glow(Color(0.4, 1.0, 0.5), 1.6)
	net_ring.material_override = net_mat
	net.add_child(net_ring)
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.025
	handle_mesh.bottom_radius = 0.03
	handle_mesh.height = 0.55
	handle.mesh = handle_mesh
	handle.position = Vector3(0.0, -0.42, 0.0)
	handle.material_override = GraphicsPolish.pbr(Color(0.35, 0.2, 0.1), 0.05, 0.7)
	net.add_child(handle)
	net.add_child(GraphicsPolish.make_trail(Color(0.4, 1.0, 0.5), 0.05))


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("GHOST CATCH", 44, Color(0.7, 0.95, 1.0))
	hud_label.position = Vector3(-2.6, 2.4, -1.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.8, 1.0, 0.9))
	msg_label.position = Vector3(0.0, 1.7, -1.8)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	for gv in ghosts:
		var g: Dictionary = gv
		if bool(g["active"]):
			GraphicsPolish.pulse_glow(g["glow_mat"], 0.9, 0.6, elapsed + float(g["phase"]))
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
		ARUpgradeKit.save_anchor("hw_ghost_catch_main", global_transform)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	_update_net(delta)
	for gv in ghosts:
		_step_ghost(gv, delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _update_net(delta: float) -> void:
	# Net sweeps while pinching (XR) or holding the mouse button.
	net_active = ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var target := Vector3(0.0, 1.2, -1.2)
	if ARUpgradeKit.is_xr_active():
		target = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var ro := camera.project_ray_origin(mp)
		var rd := camera.project_ray_normal(mp)
		target = ro + rd * 1.6
	target = ARUpgradeKit.clamp_to_room(target)
	target.y = clampf(target.y, 0.5, 2.4)
	net.position = net.position.lerp(target, clampf(16.0 * delta, 0.0, 1.0))
	GraphicsPolish.pulse_glow(net_mat, 1.2 if net_active else 0.5, 0.6, elapsed * 1.5)
	if net_active:
		_try_catch()


func _try_catch() -> void:
	for gv in ghosts:
		var g: Dictionary = gv
		if not bool(g["active"]):
			continue
		var root: Node3D = g["root"]
		if root.position.distance_to(net.position) < CATCH_RADIUS:
			_catch(g)


func _catch(g: Dictionary) -> void:
	var root: Node3D = g["root"]
	GraphicsPolish.spawn_sparks(self, root.position, Color(0.7, 1.0, 0.9), 30)
	score += 15
	caught += 1
	_respawn_ghost(g)
	_show_msg("+15  GHOST CAUGHT!", 0.8)
	if catch_player != null:
		catch_player.play()


func _step_ghost(gv: Variant, delta: float) -> void:
	var g: Dictionary = gv
	if not bool(g["active"]):
		var t := float(g["respawn_t"]) - delta
		g["respawn_t"] = t
		if t <= 0.0:
			_respawn_ghost(g, true)
			if spawn_player != null:
				spawn_player.play()
		return
	var root: Node3D = g["root"]
	var base: Vector3 = g["base"]
	var speed := float(g["speed"])
	var ph := float(g["phase"])
	var ph2 := float(g["phase2"])
	var pos := base + Vector3(
		sin(elapsed * speed + ph) * 0.7,
		sin(elapsed * 0.8 + ph2) * 0.28,
		cos(elapsed * speed * 0.8 + ph) * 0.7
	)
	pos = ARUpgradeKit.clamp_to_room(pos, 0.2)
	pos.y = clampf(pos.y, 0.6, 2.3)
	root.position = pos
	root.rotation.y = sin(elapsed * speed + ph) * 0.4


func _game_over() -> void:
	state = ST_OVER
	_show_msg("TIME UP!\nScore: %d   Ghosts caught: %d\nPress R or pinch-hold to restart" % [score, caught], 600.0)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -1.2), 60)
	ARUpgradeKit.save_anchor("hw_ghost_catch_main", global_transform)
	if end_player != null:
		end_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	caught = 0
	pinch_hold = 0.0
	for gv in ghosts:
		_respawn_ghost(gv, true)
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_ghost_catch_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "GHOST CATCH\nTime: %ds   Score: %d   Caught: %d" % [int(ceil(time_left)), score, caught]


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


## Synthesize a short enveloped sine tone (catch / spawn / jingle).
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

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the TV is the haunted ghost portal ghosts emerge from; the door is the dungeon gate they drift through.
	var _morph0_tv := RoomKit.get_anchors("TV")
	if not _morph0_tv.is_empty():
		RoomKit.morph(_morph0_tv[0], "haunted")
	var _morph1_door := RoomKit.get_anchors("DOOR")
	if not _morph1_door.is_empty():
		RoomKit.morph(_morph1_door[0], "haunted")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()


## RoomKit: random wall-face point (game-local), or Vector3.INF when none.
func _room_wall_face(y: float, inset: float) -> Vector3:
	if _room_walls.is_empty():
		return Vector3.INF
	var w: Dictionary = _room_walls[rng.randi_range(0, _room_walls.size() - 1)]
	var wp: Vector3 = w["position"]
	var n: Vector3 = w["normal"]
	n.y = 0.0
	if n.length() < 0.01:
		return Vector3.INF
	n = n.normalized()
	var tangent := Vector3(-n.z, 0.0, n.x)
	var span: Vector2 = w["size"]
	var off := rng.randf_range(-1.0, 1.0) * maxf(span.x * 0.5 - 0.5, 0.0)
	return to_local(Vector3(wp.x, y, wp.z) + n * inset + tangent * off)


## RoomKit: spot behind a random table/furniture cuboid, away from room center.
func _room_furniture_lurk(y: float) -> Vector3:
	var items: Array = _room_tables + _room_furniture
	if items.is_empty():
		return Vector3.INF
	var f: Dictionary = items[rng.randi_range(0, items.size() - 1)]
	var wp: Vector3 = f["position"]
	var fs: Vector3 = f["size"]
	var rc := _room_bounds.get_center()
	var away := Vector2(wp.x - rc.x, wp.z - rc.y)
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var clearance := maxf(fs.x, fs.z) * 0.5 + 0.45
	return to_local(Vector3(wp.x + away.x * clearance, y, wp.z + away.y * clearance))
