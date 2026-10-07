## HwGoblinArchery - "Goblin Archery" (NEXUS ARCADE Halloween set).
## Pinch-hold (or mouse-hold) to draw the bow, release to loose an arrow at
## goblins popping up around the room. Golden goblins are worth triple.
## 90-second round; R or a 1-second pinch-hold restarts.
extends Node3D

const ROUND_TIME := 90.0
const MAX_GOBLINS := 6
const HIT_RADIUS := 0.42
const DRAW_SECONDS := 1.2
const ARROW_LIFE := 3.0
const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var shots := 0
var hits := 0
var drawing := false
var draw_power := 0.0
var draw_press_screen := Vector2.ZERO
var bow: Node3D = null
var bow_string: MeshInstance3D = null
var held_arrow: Node3D = null
var draw_meter: MeshInstance3D = null
var meter_mat: StandardMaterial3D = null
var arrows: Array = [] # dicts: node, vel, life
var goblins: Array = [] # dicts: node, eye_mat, pop, life, golden, base_y, phase
var goblin_timer := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var elapsed := 0.0
var shoot_player: AudioStreamPlayer = null
var hit_player: AudioStreamPlayer = null
var gold_player: AudioStreamPlayer = null
var weak_player: AudioStreamPlayer = null
var pop_player: AudioStreamPlayer = null

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
# v0.7.0: morphed table the goblins spring out of.
var _room_table_anchor: Dictionary = {}


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_room()
	_build_bow()
	_build_hud()
	for i in range(MAX_GOBLINS):
		_spawn_goblin()
	shoot_player = _make_player(_make_tone(520.0, 0.12, 0.5))
	hit_player = _make_player(_make_tone(700.0, 0.15, 0.55))
	gold_player = _make_player(_make_tone(1180.0, 0.30, 0.5))
	weak_player = _make_player(_make_tone(180.0, 0.20, 0.4))
	pop_player = _make_player(_make_tone(900.0, 0.08, 0.35))
	ARUpgradeKit.apply_anchor(self, "hw_goblin_archery_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.0), 2.5)
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
	# v0.7.0 furniture morph: the real table becomes a haunted pop-up
	# stand — goblins spring out of its top face (see _goblin_spawn_pos).
	var table_anchors := RoomKit.get_anchors("TABLE")
	if not table_anchors.is_empty():
		RoomKit.morph(table_anchors[0], "haunted")
		_room_table_anchor = table_anchors[0]


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
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 3.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -1.5), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	elapsed += delta
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_goblin_archery_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self):
			hold_restart += delta
		else:
			hold_restart = 0.0
		if hold_restart >= 1.0:
			_reset_game()
			return
		_update_hud()
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_finish()
		return
	_update_bow_pose()
	_update_draw(delta)
	_update_arrows(delta)
	_update_goblins(delta)
	goblin_timer -= delta
	if goblin_timer <= 0.0:
		goblin_timer = 0.4
		while goblins.size() < MAX_GOBLINS:
			_spawn_goblin()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


# ------------------------------------------------------------------ build --

func _build_room() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.01, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.10, 0.08, 0.14), 0.0, 0.9)
	add_child(floor_inst)
	# Spooky moon.
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.8
	ms.height = 1.6
	moon.mesh = ms
	moon.position = Vector3(4.5, 5.5, -8.0)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.93, 0.80), 1.4)
	add_child(moon)
	_spawn_pumpkin(Vector3(-2.6, 0.0, -2.8), 0.30)
	_spawn_pumpkin(Vector3(2.7, 0.0, -3.1), 0.24)


func _spawn_pumpkin(pos: Vector3, r: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.7
	body.mesh = s
	body.position.y = r * 0.85
	body.material_override = GraphicsPolish.pbr(Color(0.90, 0.45, 0.08), 0.05, 0.55)
	root.add_child(body)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.04
	cyl.height = 0.12
	stem.mesh = cyl
	stem.position.y = r * 1.75
	stem.material_override = GraphicsPolish.pbr(Color(0.20, 0.45, 0.15), 0.0, 0.8)
	root.add_child(stem)
	GraphicsPolish.make_point_light(root, Vector3(0, r * 2.2, 0), Color(1.0, 0.55, 0.15), 0.7, 3.0)


func _build_bow() -> void:
	bow = Node3D.new()
	bow.name = "Bow"
	add_child(bow)
	var wood := GraphicsPolish.pbr(Color(0.42, 0.24, 0.12), 0.1, 0.6)
	var arc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.345
	arc.mesh = torus
	arc.rotation_degrees.x = 90.0
	arc.material_override = wood
	bow.add_child(arc)
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.035
	gc.bottom_radius = 0.035
	gc.height = 0.16
	grip.mesh = gc
	grip.material_override = GraphicsPolish.pbr(Color(0.20, 0.10, 0.06), 0.0, 0.8)
	bow.add_child(grip)
	bow_string = MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.012, 0.62, 0.012)
	bow_string.mesh = sb
	bow_string.position = Vector3(0.0, 0.0, 0.03)
	bow_string.material_override = GraphicsPolish.glow(Color(0.9, 0.9, 0.85), 0.8)
	bow.add_child(bow_string)
	# Arrow nocked and ready.
	held_arrow = _make_arrow_node()
	held_arrow.position = Vector3(0.0, 0.0, 0.15)
	held_arrow.visible = false
	bow.add_child(held_arrow)
	# Draw-strength meter above the bow.
	draw_meter = MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.34, 0.045, 0.02)
	draw_meter.mesh = mb
	draw_meter.position = Vector3(0.0, 0.52, 0.0)
	meter_mat = StandardMaterial3D.new()
	meter_mat.albedo_color = Color(0.3, 1.0, 0.2)
	meter_mat.emission_enabled = true
	meter_mat.emission = Color(0.3, 1.0, 0.2)
	draw_meter.material_override = meter_mat
	draw_meter.visible = false
	bow.add_child(draw_meter)


func _make_arrow_node() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.55
	shaft.mesh = cyl
	shaft.rotation_degrees.x = 90.0
	shaft.material_override = GraphicsPolish.pbr(Color(0.55, 0.36, 0.18), 0.1, 0.6)
	root.add_child(shaft)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.03
	cone.height = 0.09
	tip.mesh = cone
	tip.rotation_degrees.x = -90.0
	tip.position = Vector3(0.0, 0.0, -0.32)
	tip.material_override = GraphicsPolish.pbr_preset(Color(0.75, 0.78, 0.85), "metal")
	root.add_child(tip)
	for side in [-1.0, 1.0]:
		var fl := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.005, 0.06, 0.10)
		fl.mesh = fb
		fl.position = Vector3(side * 0.012, 0.0, 0.24)
		fl.material_override = GraphicsPolish.glow(Color(0.95, 0.25, 0.15), 0.9)
		root.add_child(fl)
	root.add_child(GraphicsPolish.make_trail(Color(1.0, 0.75, 0.25), 0.03))
	return root


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("GOBLIN ARCHERY", 44, Color(1.0, 0.85, 0.4))
	hud_label.position = Vector3(-2.9, 2.5, -0.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.35))
	msg_label.position = Vector3(0.0, 1.9, -2.6)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "GOBLIN ARCHERY\nTime: %ds   Score: %d   Hits: %d/%d\nHold pinch / mouse to draw, release to fire\nR: restart" % [int(ceil(time_left)), score, hits, shots]


func _show_msg(text: String, duration: float = 1.4) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ------------------------------------------------------------------ input --

func _pointer_screen() -> Vector2:
	var wp := ARUpgradeKit.pointer_position(self)
	if camera != null:
		return camera.unproject_position(wp)
	return get_viewport().get_mouse_position()


func _update_bow_pose() -> void:
	if bow == null:
		return
	var ray: Array = ARUpgradeKit.pointer_ray(self)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	bow.global_position = o
	if d.length_squared() > 0.0001:
		bow.look_at(o + d, Vector3.UP)


func _update_draw(delta: float) -> void:
	var pinching := ARUpgradeKit.pinch_active(self)
	if not drawing and ARUpgradeKit.pinch_just_pressed(self):
		drawing = true
		draw_power = 0.0
		draw_press_screen = _pointer_screen()
		held_arrow.visible = true
		draw_meter.visible = true
	elif drawing:
		draw_power = minf(1.0, draw_power + delta / DRAW_SECONDS)
		var drag := draw_press_screen.distance_to(_pointer_screen()) / 450.0
		var power := clampf(maxf(draw_power, drag), 0.0, 1.0)
		_set_draw_visual(power)
		if not pinching:
			drawing = false
			_fire(power)


func _set_draw_visual(power: float) -> void:
	held_arrow.position.z = 0.15 + 0.28 * power
	bow_string.position.z = 0.03 + 0.28 * power
	draw_meter.scale.x = maxf(0.03, power)
	meter_mat.albedo_color = Color(1.0, 1.0 - power * 0.85, 0.15)
	meter_mat.emission = meter_mat.albedo_color


func _fire(power: float) -> void:
	held_arrow.visible = false
	draw_meter.visible = false
	held_arrow.position.z = 0.15
	bow_string.position.z = 0.03
	if power < 0.12:
		weak_player.play()
		_show_msg("Draw further!", 0.8)
		return
	shots += 1
	var dir := -bow.global_transform.basis.z
	var node := _make_arrow_node()
	node.global_position = bow.global_position + dir * 0.55
	add_child(node)
	arrows.append({"node": node, "vel": dir * lerpf(7.0, 22.0, power), "life": ARROW_LIFE})
	shoot_player.play()


# ----------------------------------------------------------------- arrows --

func _update_arrows(delta: float) -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			arrows.remove_at(i)
			continue
		var vel: Vector3 = a["vel"]
		vel.y -= 3.5 * delta
		node.global_position += vel * delta
		a["vel"] = vel
		if vel.length_squared() > 0.01:
			node.look_at(node.global_position + vel, Vector3.UP)
		var life := float(a["life"]) - delta
		a["life"] = life
		var hit_something := false
		for g_v in goblins:
			var g: Dictionary = g_v
			var gnode: Node3D = g["node"]
			if not is_instance_valid(gnode):
				continue
			var center: Vector3 = gnode.global_position + Vector3(0.0, 0.25, 0.0)
			if node.global_position.distance_to(center) < HIT_RADIUS:
				_hit_goblin(g)
				hit_something = true
				break
		if hit_something or life <= 0.0 or node.global_position.y < -0.5:
			node.queue_free()
			arrows.remove_at(i)


# ---------------------------------------------------------------- goblins --

func _spawn_goblin() -> void:
	var golden := randf() < 0.12
	var base_y := 0.42
	var root := Node3D.new()
	root.position = _goblin_spawn_pos()
	root.scale = Vector3.ONE * 0.01
	add_child(root)
	var skin := GraphicsPolish.pbr(Color(0.95, 0.75, 0.15), 0.35, 0.35) if golden else GraphicsPolish.pbr(Color(0.25, 0.70, 0.22), 0.05, 0.6)
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.26
	s.height = 0.52
	body.mesh = s
	body.material_override = skin
	root.add_child(body)
	# Pointy ears.
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.07
		cone.height = 0.20
		ear.mesh = cone
		ear.position = Vector3(side * 0.27, 0.10, 0.0)
		ear.rotation_degrees.z = side * -70.0
		ear.material_override = skin
		root.add_child(ear)
	# Glowing eyes.
	var eye_mat := GraphicsPolish.glow(Color(1.0, 0.25, 0.10) if not golden else Color(1.0, 0.85, 0.20), 1.6)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.055
		es.height = 0.11
		eye.mesh = es
		eye.position = Vector3(side * 0.10, 0.08, 0.21)
		eye.material_override = eye_mat
		root.add_child(eye)
	# Warty nose.
	var nose := MeshInstance3D.new()
	var ns := SphereMesh.new()
	ns.radius = 0.05
	ns.height = 0.10
	nose.mesh = ns
	nose.position = Vector3(0.0, 0.0, 0.25)
	nose.material_override = GraphicsPolish.pbr(Color(0.15, 0.40, 0.12), 0.0, 0.7)
	root.add_child(nose)
	if golden:
		GraphicsPolish.make_point_light(root, Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.2), 0.8, 2.5)
	goblins.append({
		"node": root, "eye_mat": eye_mat, "pop": 0.0,
		"life": randf_range(4.0, 7.0), "golden": golden,
		"base_y": base_y, "phase": randf() * TAU,
	})
	if pop_player != null:
		pop_player.play()


func _goblin_spawn_pos() -> Vector3:
	# Goblins pop out from behind the player's real furniture or wall
	# edges when the room is known, otherwise from a ring as before.
	# The morphed table is a pop-up stand: goblins spring out of its top.
	if not _room_table_anchor.is_empty() and randf() < 0.3:
		var top: Vector3 = RoomKit.cuboid_top(_room_table_anchor)
		return top + Vector3(randf_range(-0.2, 0.2), 0.05, randf_range(-0.2, 0.2))
	if _room_known:
		if randf() < 0.55:
			var all := _room_furniture + _room_tables
			if not all.is_empty():
				var f: Dictionary = all[randi() % all.size()]
				var fp: Vector3 = f["position"]
				var fs: Vector3 = f["size"]
				var c := _room_bounds.get_center()
				var away := Vector2(fp.x - c.x, fp.z - c.y)
				if away.length() < 0.05:
					away = Vector2(0.0, 1.0)
				away = away.normalized()
				var edge := maxf(fs.x, fs.z) * 0.5 + 0.4
				var px := clampf(fp.x + away.x * edge, _room_bounds.position.x + 0.4, _room_bounds.end.x - 0.4)
				var pz := clampf(fp.z + away.y * edge, _room_bounds.position.y + 0.4, _room_bounds.end.y - 0.4)
				return Vector3(px, 0.42, pz)
		if not _room_walls.is_empty():
			var w: Dictionary = _room_walls[randi() % _room_walls.size()]
			var bp: Vector3 = (w["position"] as Vector3) + _wall_inward(w) * 0.5
			return Vector3(bp.x, 0.42, bp.z)
		var rmax := minf(3.4, maxf(1.4, minf(_room_bounds.size.x, _room_bounds.size.y) * 0.5 - 0.3))
		var ang2 := randf() * TAU
		var rr := randf_range(1.6, rmax)
		return Vector3(cos(ang2) * rr, 0.42, sin(ang2) * rr - 0.6)
	var angle := randf() * TAU
	var radius := randf_range(2.0, 3.4)
	return Vector3(cos(angle) * radius, 0.42, sin(angle) * radius - 0.6)


func _update_goblins(delta: float) -> void:
	for i in range(goblins.size() - 1, -1, -1):
		var g: Dictionary = goblins[i]
		var node: Node3D = g["node"]
		if not is_instance_valid(node):
			goblins.remove_at(i)
			continue
		var pop := minf(1.0, float(g["pop"]) + delta * 3.0)
		g["pop"] = pop
		GraphicsPolish.ease_scale(node, Vector3.ONE, 7.0, delta)
		node.position.y = float(g["base_y"]) + sin(elapsed * 3.0 + float(g["phase"])) * 0.05
		GraphicsPolish.pulse_glow(g["eye_mat"] as StandardMaterial3D, 1.2, 0.8, elapsed + float(g["phase"]), 3.0)
		var life := float(g["life"]) - delta
		g["life"] = life
		if life <= 0.0:
			node.queue_free()
			goblins.remove_at(i)


func _hit_goblin(g: Dictionary) -> void:
	var node: Node3D = g["node"]
	var golden := bool(g["golden"])
	var pts := 30 if golden else 10
	score += pts
	hits += 1
	if is_instance_valid(node):
		var col := Color(1.0, 0.8, 0.2) if golden else Color(0.5, 1.0, 0.4)
		GraphicsPolish.spawn_sparks(self, to_local(node.global_position + Vector3(0, 0.3, 0)), col, 26)
		node.queue_free()
	goblins.erase(g)
	if golden:
		gold_player.play()
		_show_msg("+30 GOLDEN!", 1.0)
	else:
		hit_player.play()
		_show_msg("+10", 0.6)


# ------------------------------------------------------------------ flow ---

func _finish() -> void:
	state = ST_OVER
	held_arrow.visible = false
	draw_meter.visible = false
	drawing = false
	var acc := 0.0
	if shots > 0:
		acc = 100.0 * float(hits) / float(shots)
	_show_msg("TIME'S UP!\nScore: %d   Accuracy: %d%%\nHold pinch 1s or press R" % [score, int(acc)], 600.0)
	if score >= 120:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -1.5), 70)
	ARUpgradeKit.save_anchor("hw_goblin_archery_main", global_transform)


func _reset_game() -> void:
	for a_v in arrows:
		var a: Dictionary = a_v
		var anode: Node3D = a["node"]
		if is_instance_valid(anode):
			anode.queue_free()
	arrows.clear()
	for g_v in goblins:
		var g: Dictionary = g_v
		var gnode: Node3D = g["node"]
		if is_instance_valid(gnode):
			gnode.queue_free()
	goblins.clear()
	time_left = ROUND_TIME
	score = 0
	shots = 0
	hits = 0
	drawing = false
	hold_restart = 0.0
	state = ST_PLAY
	held_arrow.visible = false
	draw_meter.visible = false
	_show_msg("")
	for i in range(MAX_GOBLINS):
		_spawn_goblin()
	ARUpgradeKit.save_anchor("hw_goblin_archery_main", global_transform)


# ------------------------------------------------------------------ audio --

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
