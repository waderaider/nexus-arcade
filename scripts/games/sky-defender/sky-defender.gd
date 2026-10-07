## SkyDefenderGame - "Sky Defender": anti-aircraft turret defense.
## Drones (dark boxes with spinning rotor discs) spawn at the room edges and
## fly across toward the opposite wall. Aim with the mouse (crosshair follows
## the cursor ray) and click to fire tracer shots. A hit drone explodes in an
## expanding shockwave sphere for score. A drone that crosses the room damages
## the city (3 HP). Waves escalate: more drones, faster. Wave / score / city-HP
## HUD, and a game-over screen with restart.
## Desktop/mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D

const BOUND := 6.0
const SHOT_SPEED := 26.0
const SHOT_RANGE := 30.0
const HIT_DIST := 0.55

const ST_PLAYING := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAYING
var wave := 1
var score := 0
var city_hp := 3
var drones: Array = [] # dicts: root, rotor, vel, bob
var shots: Array = [] # dicts: node, vel, travelled
var booms: Array = [] # dicts: node, mat, t
var spawn_queue := 0
var spawn_timer := 0.0
var crosshair: MeshInstance3D = null
var aim_point := Vector3(0.0, 1.5, -4.0)
var muzzle := Vector3(0.0, 1.55, 4.8)
var hud_label: Label3D = null
var help_label: Label3D = null
var center_label: Label3D = null
var center_timer := 0.0
var laser_player: AudioStreamPlayer = null
var boom_player: AudioStreamPlayer = null
var damage_player: AudioStreamPlayer = null
var wave_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _click_consumed := false

# v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_ready := false


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_ground()
	_build_city()
	_build_crosshair()
	_build_hud()
	laser_player = _make_player(_make_tone(1400.0, 0.12, 0.45))
	boom_player = _make_player(_make_tone(110.0, 0.45, 0.65))
	damage_player = _make_player(_make_tone(180.0, 0.5, 0.6))
	wave_player = _make_player(_make_tone(660.0, 0.25, 0.5))
	_start_wave()
	ARUpgradeKit.apply_anchor(self, "sky-defender_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 2.0, 0.0), 4.0)
	_apply_room_layout() # v0.7.0: drones come from real walls, AA gun sits on furniture (no-op w/o room data).


func _room_center3() -> Vector3:
	var c := _room_bounds.get_center()
	return Vector3(c.x, 0.0, c.y)


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_ready = true
	# AA position: mount the turret on the largest table/furniture top.
	var best: Dictionary = {}
	var best_a := 0.0
	for t_v in _room_tables + _room_furniture:
		var t: Dictionary = t_v
		var s: Vector3 = t["size"]
		if s.x * s.z > best_a:
			best_a = s.x * s.z
			best = t
	if not best.is_empty():
		var top: Vector3 = (best["position"] as Vector3) + Vector3(0, (best["size"] as Vector3).y * 0.5, 0)
		muzzle = to_local(top + Vector3(0, 0.35, 0))
		var tur := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.3, 0.25, 0.3)
		tur.mesh = tb
		tur.material_override = _mat(Color(0.2, 0.5, 0.8), 1.2, true)
		tur.position = muzzle + Vector3(0, -0.3, 0)
		add_child(tur)
	# v0.7.0 MORPH: the table the turret sits on becomes the AA battery platform.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_tables := RoomKit.get_anchors("TABLE")
		if not _morph_tables.is_empty():
			RoomKit.morph(_morph_tables[0], "scifi")


func _add_light_rig() -> void:
	# Three-point light rig; skipped if a directional light already exists.
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _process(delta: float) -> void:
	_poll_pinch()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("sky-defender_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_PLAYING:
		_update_aim_point()
		_update_spawning(delta)
		_step_drones(delta)
		_step_shots(delta)
	_step_booms(delta)
	if center_timer > 0.0:
		center_timer -= delta
		if center_timer <= 0.0 and center_label != null and state == ST_PLAYING:
			center_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAYING:
			_click_consumed = true
			_fire()


## Hand-tracking hook: XR pinch fires the turret (mouse still works).
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _poll_pinch() -> void:
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if _click_consumed:
		_click_consumed = false
		return
	if pinched and camera != null and state == ST_PLAYING:
		# Aim from the hand pointer, then fire.
		aim_point = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 9.0)
		if crosshair != null:
			crosshair.position = aim_point
		_fire()


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 5.5)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.4, -3.0), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	var m := GraphicsPolish.pbr(color, 0.35, 0.5)
	if unshaded:
		ARUpgradeKit.passthrough_friendly(m)
	return m


func _build_ground() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor_inst.mesh = plane
	floor_inst.material_override = _mat(Color(0.06, 0.07, 0.10))
	add_child(floor_inst)


func _build_city() -> void:
	# City skyline silhouette along the far wall: what the drones are after.
	var rng_xs := [-4.5, -2.8, -1.2, 0.6, 2.4, 4.2]
	for i in range(rng_xs.size()):
		var h := 1.2 + float((i * 37) % 12) * 0.09
		var b := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.3, h, 1.0)
		b.mesh = box
		b.position = Vector3(rng_xs[i], h * 0.5, -7.6)
		var mat := _mat(Color(0.16, 0.20, 0.28))
		b.material_override = mat
		add_child(b)
		# A lit window strip on each tower.
		var win := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(0.9, 0.08, 0.06)
		win.mesh = wbox
		win.position = Vector3(rng_xs[i], h * 0.72, -7.08)
		win.material_override = _mat(Color(1.0, 0.85, 0.4), 1.8, true)
		add_child(win)


func _build_crosshair() -> void:
	crosshair = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.11
	crosshair.mesh = ring
	crosshair.material_override = _mat(Color(1.0, 1.0, 1.0), 2.0, true)
	add_child(crosshair)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("SKY DEFENDER", 52, Color(1, 1, 1))
	hud_label.position = Vector3(-3.8, 3.4, 0.5)
	add_child(hud_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-3.8, 2.95, 0.5)
	help_label.pixel_size = 0.0036
	help_label.font_size = 30
	help_label.outline_size = 8
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help_label.text = "Move mouse to aim, click to fire | R: restart"
	add_child(help_label)
	center_label = Label3D.new()
	center_label.position = Vector3(0.0, 2.2, -3.0)
	center_label.pixel_size = 0.009
	center_label.font_size = 110
	center_label.outline_size = 14
	center_label.modulate = Color(1.0, 0.9, 0.35)
	center_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(center_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "SKY DEFENDER   Wave: %d   Score: %d   City HP: %d" % [wave, score, city_hp]


func _show_center(text: String, duration: float = 2.0) -> void:
	if center_label == null:
		return
	center_label.text = text
	center_timer = duration


# ---------------------------------------------------------------- drones ---

func _wave_speed() -> float:
	return 1.1 + 0.30 * float(wave)


func _wave_size() -> int:
	return mini(3 + wave, 12)


func _start_wave() -> void:
	spawn_queue = _wave_size()
	spawn_timer = 0.5
	_show_center("WAVE %d" % wave)
	if wave_player != null:
		wave_player.play()


func _update_spawning(delta: float) -> void:
	if spawn_queue > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_timer = 0.9
			spawn_queue -= 1
			_spawn_drone()
	elif drones.is_empty():
		score += 250 # wave-clear bonus
		wave += 1
		_start_wave()


func _spawn_drone() -> void:
	# Drones stream in from real wall faces toward the room center; without
	# room data they cross the default arena edge-to-edge as before.
	var speed := _wave_speed() + randf() * 0.4
	var start: Vector3
	var vel: Vector3
	if _room_ready and not _room_walls.is_empty():
		var w: Dictionary = _room_walls[randi() % _room_walls.size()]
		var inward: Vector3 = _room_center3() - (w["position"] as Vector3)
		inward.y = 0.0
		start = to_local((w["position"] as Vector3) + inward.normalized() * 0.5)
		start += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		start.y = randf_range(0.9, 2.9)
		var dir: Vector3 = _room_center3() - start
		dir.y = 0.0
		vel = dir.normalized() * speed
	else:
		var side := 1.0 if randf() < 0.5 else -1.0
		start = Vector3(side * (BOUND + 0.6), randf_range(0.9, 2.9), randf_range(-5.5, 1.5))
		vel = Vector3(-side * speed, 0.0, 0.0)
	var root := Node3D.new()
	root.position = ARUpgradeKit.clamp_to_room(start)
	# Dark boxy body.
	var body := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.5, 0.18, 0.7)
	body.mesh = bbox
	body.material_override = _mat(Color(0.12, 0.13, 0.16))
	root.add_child(body)
	# Spinning rotor disc on top.
	var rotor := MeshInstance3D.new()
	var rcyl := CylinderMesh.new()
	rcyl.top_radius = 0.30
	rcyl.bottom_radius = 0.30
	rcyl.height = 0.025
	rotor.mesh = rcyl
	rotor.position = Vector3(0.0, 0.16, 0.0)
	var rmat := _mat(Color(0.25, 0.28, 0.32))
	rmat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.25, 0.28, 0.32, 0.75)
	rotor.material_override = rmat
	root.add_child(rotor)
	# Red warning light.
	var lamp := MeshInstance3D.new()
	var lsphere := SphereMesh.new()
	lsphere.radius = 0.05
	lsphere.height = 0.1
	lamp.mesh = lsphere
	lamp.position = Vector3(0.0, -0.02, 0.36)
	lamp.material_override = _mat(Color(1.0, 0.15, 0.15), 2.5, true)
	root.add_child(lamp)
	add_child(root)
	drones.append({
		"root": root, "rotor": rotor,
		"vel": vel,
		"bob": randf() * TAU,
	})


func _step_drones(delta: float) -> void:
	for i in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[i]
		var root: Node3D = d["root"]
		if not is_instance_valid(root):
			drones.remove_at(i)
			continue
		var vel: Vector3 = d["vel"]
		root.position += vel * delta
		# Gentle bobbing flight.
		d["bob"] = float(d["bob"]) + delta * 3.0
		drones[i] = d
		root.position.y += sin(float(d["bob"])) * 0.15 * delta
		var rotor: MeshInstance3D = d["rotor"]
		if is_instance_valid(rotor):
			rotor.rotate_y(delta * 22.0)
		# Reached the opposite wall: the city takes a hit. With room data the
		# drone counts as through once it leaves the real room floor extents.
		var crossed := (vel.x > 0.0 and root.position.x > BOUND + 0.5) or (vel.x < 0.0 and root.position.x < -BOUND - 0.5)
		if _room_ready:
			var dw := to_global(root.position)
			crossed = not _room_bounds.grow(0.6).has_point(Vector2(dw.x, dw.z))
		if crossed:
			root.queue_free()
			drones.remove_at(i)
			_city_hit()


func _city_hit() -> void:
	city_hp -= 1
	if damage_player != null:
		damage_player.play()
	if city_hp <= 0:
		city_hp = 0
		_game_over()
	else:
		_show_center("CITY HIT!  HP: %d" % city_hp, 1.5)


# ----------------------------------------------------------------- shots ---

func _update_aim_point() -> void:
	if camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	aim_point = from + dir * 9.0
	if crosshair != null:
		crosshair.position = aim_point
		crosshair.look_at(camera.global_position, Vector3.UP)


func _fire() -> void:
	if camera == null:
		return
	var dir := (aim_point - muzzle).normalized()
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.045, 0.7)
	node.mesh = box
	node.material_override = _mat(Color(1.0, 0.9, 0.25), 3.0, true)
	node.position = muzzle
	add_child(node)
	node.add_child(GraphicsPolish.make_trail(Color(1.0, 0.9, 0.25), 0.05))
	node.look_at(muzzle + dir, Vector3.UP)
	shots.append({"node": node, "vel": dir * SHOT_SPEED, "travelled": 0.0})
	if laser_player != null:
		laser_player.play()


func _step_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var node: MeshInstance3D = s["node"]
		if not is_instance_valid(node):
			shots.remove_at(i)
			continue
		var vel: Vector3 = s["vel"]
		node.position += vel * delta
		var travelled := float(s["travelled"]) + vel.length() * delta
		if travelled > SHOT_RANGE:
			node.queue_free()
			shots.remove_at(i)
			continue
		s["travelled"] = travelled
		shots[i] = s
		if _shot_hits_drone(node.position):
			node.queue_free()
			shots.remove_at(i)


func _shot_hits_drone(pos: Vector3) -> bool:
	for i in range(drones.size() - 1, -1, -1):
		var d: Dictionary = drones[i]
		var root: Node3D = d["root"]
		if not is_instance_valid(root):
			drones.remove_at(i)
			continue
		if root.position.distance_to(pos) < HIT_DIST:
			_explode(root.position)
			root.queue_free()
			drones.remove_at(i)
			score += 100
			return true
	return false


func _explode(pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	node.mesh = sphere
	node.position = pos
	var mat := GraphicsPolish.glow(Color(1.0, 0.5, 0.1), 3.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	node.material_override = mat
	add_child(node)
	GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.6, 0.2), 30)
	booms.append({"node": node, "mat": mat, "t": 0.45})
	if boom_player != null:
		boom_player.play()


func _step_booms(delta: float) -> void:
	for i in range(booms.size() - 1, -1, -1):
		var b: Dictionary = booms[i]
		var node: MeshInstance3D = b["node"]
		var t := float(b["t"]) - delta
		if not is_instance_valid(node) or t <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			booms.remove_at(i)
			continue
		b["t"] = t
		booms[i] = b
		var k := 1.0 - t / 0.45
		node.scale = Vector3.ONE * (1.0 + k * 3.2)
		var mat: StandardMaterial3D = b["mat"]
		mat.albedo_color.a = 0.9 * (t / 0.45)


# ------------------------------------------------------------ game flow ----

func _game_over() -> void:
	state = ST_OVER
	_show_center("GAME OVER\nScore: %d   Wave: %d\nPress R to restart" % [score, wave], 600.0)
	if crosshair != null:
		crosshair.visible = false


func _reset_game() -> void:
	for d_v in drones:
		var d: Dictionary = d_v
		var root: Node3D = d["root"]
		if is_instance_valid(root):
			root.queue_free()
	drones.clear()
	for s_v in shots:
		var s: Dictionary = s_v
		var node: MeshInstance3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
	shots.clear()
	for b_v in booms:
		var b: Dictionary = b_v
		var bnode: MeshInstance3D = b["node"]
		if is_instance_valid(bnode):
			bnode.queue_free()
	booms.clear()
	wave = 1
	score = 0
	city_hp = 3
	state = ST_PLAYING
	if crosshair != null:
		crosshair.visible = true
	_show_center("")
	ARUpgradeKit.save_anchor("sky-defender_main", global_transform)
	_start_wave()


# ----------------------------------------------------------------- audio ---

func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (laser / explosion / alarm).
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
