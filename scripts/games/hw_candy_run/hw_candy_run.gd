## HwCandyRun - "Candy Run": candy rains down from the sky.
## Move the basket with your hand (mouse fallback: move the mouse) to
## catch falling candy. 10 points per catch. Miss a candy and you lose
## a life - 3 lives, 60 seconds.
extends Node3D

const ROUND_TIME := 60.0
const BASKET_Y := 0.85
const BASKET_RADIUS := 0.34
const SPAWN_Y := 3.0
const CATCH_Y := 0.95
const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var lives := 3
var caught := 0
var elapsed := 0.0
var spawn_timer := 0.0
var candies: Array = [] # dicts: node, speed, spin, glow_mat, active
var basket: Node3D = null
var basket_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var invuln := 0.0
var catch_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()

## RoomKit v0.7.0: cached room layout + local drop-zone ranges (defaults = old).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _room_sx0 := -1.5
var _room_sx1 := 1.5
var _room_sz0 := -1.8
var _room_sz1 := 0.4
var candy_colors: Array = [
	Color(1.0, 0.25, 0.35), Color(0.25, 0.8, 1.0), Color(0.5, 1.0, 0.3),
	Color(1.0, 0.75, 0.15), Color(0.8, 0.4, 1.0), Color(1.0, 0.5, 0.1),
]


func _ready() -> void:
	rng.randomize()
	_add_light_rig()
	_ensure_fallback_camera()
	_build_basket()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, "hw_candy_run_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.6, 0.0), 2.5, 36)
	catch_player = _make_player(_make_tone(880.0, 0.10, 0.5))
	miss_player = _make_player(_make_tone(150.0, 0.30, 0.55))
	end_player = _make_player(_make_tone(660.0, 0.5, 0.5))
	for i in range(10):
		candies.append(_build_candy())
		(candies[i] as Dictionary)["active"] = false
		((candies[i] as Dictionary)["node"] as Node3D).visible = false
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
	camera.position = Vector3(0.0, 1.7, 2.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -0.6), Vector3.UP)
	camera.current = true


func _build_basket() -> void:
	basket = Node3D.new()
	basket.position = Vector3(0.0, BASKET_Y, -0.8)
	add_child(basket)
	# Open-top bucket: dark body + glowing rim.
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.34
	body_mesh.bottom_radius = 0.24
	body_mesh.height = 0.22
	body.mesh = body_mesh
	body.material_override = GraphicsPolish.pbr(Color(0.45, 0.22, 0.08), 0.1, 0.6)
	basket.add_child(body)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.30
	rim_mesh.outer_radius = 0.36
	rim.mesh = rim_mesh
	rim.position = Vector3(0.0, 0.11, 0.0)
	basket_mat = GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.4)
	rim.material_override = basket_mat
	basket.add_child(rim)


func _build_candy() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var color: Color = candy_colors[rng.randi_range(0, candy_colors.size() - 1)]
	var glow_mat := GraphicsPolish.glow(color, 1.5)
	# Wrapped candy: capsule body + two twisted ends.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.07
	cap.height = 0.20
	body.mesh = cap
	body.rotation.z = PI * 0.5
	body.material_override = glow_mat
	root.add_child(body)
	for side in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.015
		cone.bottom_radius = 0.07
		cone.height = 0.10
		tip.mesh = cone
		tip.rotation.z = side * PI * 0.5
		tip.position = Vector3(side * 0.15, 0.0, 0.0)
		tip.material_override = GraphicsPolish.pbr(color.darkened(0.25), 0.1, 0.6)
		root.add_child(tip)
	return {"node": root, "speed": 2.0, "spin": 2.0, "glow_mat": glow_mat, "active": false}


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("CANDY RUN", 44, Color(1.0, 0.6, 0.9))
	hud_label.position = Vector3(-2.6, 2.4, -1.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.7, -1.8)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	GraphicsPolish.pulse_glow(basket_mat, 1.1, 0.6, elapsed * 2.0)
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
		ARUpgradeKit.save_anchor("hw_candy_run_main", global_transform)
	if invuln > 0.0:
		invuln -= delta
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over(true)
		return
	_update_basket(delta)
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = rng.randf_range(0.45, 0.9)
		_spawn_candy()
	for cv in candies:
		_step_candy(cv, delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _update_basket(delta: float) -> void:
	# Basket follows the hand via pointer position (mouse fallback: cursor).
	var target := Vector3(0.0, BASKET_Y, -0.8)
	if ARUpgradeKit.is_xr_active():
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		target = Vector3(pp.x, BASKET_Y, pp.z)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var ro := camera.project_ray_origin(mp)
		var rd := camera.project_ray_normal(mp)
		if absf(rd.y) > 0.001:
			var t := (BASKET_Y - ro.y) / rd.y
			if t > 0.0:
				var p := ro + rd * t
				target = Vector3(p.x, BASKET_Y, p.z)
	target = ARUpgradeKit.clamp_to_room(target, 0.45)
	basket.position = basket.position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))


func _spawn_candy() -> void:
	for cv in candies:
		var c: Dictionary = cv
		if bool(c["active"]):
			continue
		var node: Node3D = c["node"]
		node.visible = true
		var sp := Vector3(rng.randf_range(_room_sx0, _room_sx1), SPAWN_Y, rng.randf_range(_room_sz0, _room_sz1))
		# RoomKit v0.7.0: some candy hides behind real furniture.
		if (not _room_tables.is_empty() or not _room_furniture.is_empty()) and rng.randf() < 0.4:
			var fs := _room_furniture_lurk(SPAWN_Y)
			if fs != Vector3.INF:
				sp = fs + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		node.position = sp
		node.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0)
		c["speed"] = rng.randf_range(1.7, 2.7)
		c["spin"] = rng.randf_range(1.5, 4.0)
		c["active"] = true
		return


func _step_candy(cv: Variant, delta: float) -> void:
	var c: Dictionary = cv
	if not bool(c["active"]):
		return
	var node: Node3D = c["node"]
	var speed := float(c["speed"])
	node.position.y -= speed * delta
	node.rotation.y += float(c["spin"]) * delta
	var dxz := Vector2(node.position.x - basket.position.x, node.position.z - basket.position.z).length()
	if node.position.y <= CATCH_Y and dxz < BASKET_RADIUS:
		_catch_candy(c)
		return
	if node.position.y <= 0.06:
		_miss_candy(c)


func _catch_candy(c: Dictionary) -> void:
	var node: Node3D = c["node"]
	GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.8, 0.3), 18)
	score += 10
	caught += 1
	c["active"] = false
	node.visible = false
	_show_msg("+10", 0.5)
	if catch_player != null:
		catch_player.play()


func _miss_candy(c: Dictionary) -> void:
	var node: Node3D = c["node"]
	c["active"] = false
	node.visible = false
	if invuln > 0.0:
		return
	lives -= 1
	invuln = 0.6
	GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.2, 0.2), 20)
	_show_msg("MISS!  Lives: %d" % maxi(lives, 0), 1.2)
	if miss_player != null:
		miss_player.play()
	if lives <= 0:
		_game_over(false)


func _game_over(survived: bool) -> void:
	state = ST_OVER
	var title := "TIME UP! You survived!" if survived else "OUT OF LIVES!"
	_show_msg("%s\nScore: %d   Caught: %d\nPress R or pinch-hold to restart" % [title, score, caught], 600.0)
	GraphicsPolish.spawn_confetti(self, basket.position + Vector3(0.0, 0.6, 0.0), 60)
	ARUpgradeKit.save_anchor("hw_candy_run_main", global_transform)
	if end_player != null:
		end_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	lives = 3
	caught = 0
	spawn_timer = 0.0
	pinch_hold = 0.0
	invuln = 0.0
	for cv in candies:
		var c: Dictionary = cv
		c["active"] = false
		(c["node"] as Node3D).visible = false
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_candy_run_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "CANDY RUN\nTime: %ds   Score: %d   Lives: %d" % [int(ceil(time_left)), score, maxi(lives, 0)]


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


## Synthesize a short enveloped sine tone (catch / miss / jingle).
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
		_dress_spooky() # v0.7.0: defaults still apply without RoomKit
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		_dress_spooky() # v0.7.0: defaults still apply without room data
		return
	# v0.7.0 MORPH-C: storage becomes the candy treasure vault (the run's goal); the rug is the candy track start.
	var _morph0_storage := RoomKit.get_anchors("STORAGE")
	if not _morph0_storage.is_empty():
		RoomKit.morph(_morph0_storage[0], "candy")
	var _morph1_rug := RoomKit.get_anchors("RUG")
	if not _morph1_rug.is_empty():
		RoomKit.morph(_morph1_rug[0], "candy")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Fit the candy drop zone to the real room floor (game-local ranges).
	var b := _room_bounds
	var c0 := to_local(Vector3(b.position.x, 0.0, b.position.y))
	var c1 := to_local(Vector3(b.end.x, 0.0, b.end.y))
	_room_sx0 = minf(c0.x, c1.x) + 0.3
	_room_sx1 = maxf(c0.x, c1.x) - 0.3
	_room_sz0 = minf(c0.z, c1.z) + 0.3
	_room_sz1 = maxf(c0.z, c1.z) - 0.3
	if _room_sx1 < _room_sx0:
		_room_sx0 = -1.5
		_room_sx1 = 1.5
	if _room_sz1 < _room_sz0:
		_room_sz0 = -1.8
		_room_sz1 = 0.4
	_dress_spooky() # v0.7.0 KayKit set dressing, fit to the drop zone


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


## v0.7.0 KayKit set dressing: spooky props ringing the candy drop zone
## (candle clusters, barrels, a chest). Guarded - null spawns are skipped,
## never crash; uses the room-fit drop-zone ranges above.
func _dress_spooky() -> void:
	var dir := "res://assets/models/hw_candy_run/"
	var mid_z := (_room_sz0 + _room_sz1) * 0.5
	ModelLib.spawn(dir + "candle_triple.glb", self, Vector3(_room_sx0 - 0.60, 0.0, mid_z))
	ModelLib.spawn(dir + "candle_triple.glb", self, Vector3(_room_sx1 + 0.60, 0.0, mid_z))
	ModelLib.spawn(dir + "chest.glb", self, Vector3(_room_sx1 + 0.90, 0.0, _room_sz1 + 0.50))
	ModelLib.spawn(dir + "barrel_small.glb", self, Vector3(_room_sx0 - 0.90, 0.0, _room_sz1 + 0.50))
	ModelLib.spawn(dir + "barrel_small.glb", self, Vector3(_room_sx0 - 0.90, 0.0, _room_sz0 - 0.40))
