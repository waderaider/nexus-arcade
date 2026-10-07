## HwMidnightSurvival - "Midnight Survival" (NEXUS ARCADE Halloween set).
## Waves of spooks close in from all sides until the clock strikes midnight
## (90 seconds). Pinch (or click) to zap them with a lightning bolt: +10 per
## banish. A spook that reaches you costs a heart; lose all 3 and the night
## takes you. Survive to win. R or a 1-second pinch-hold restarts.
extends Node3D

const ROUND_TIME := 90.0
const MAX_SPOOKS := 14
const ZAP_ANGLE := 0.5
const ZAP_RANGE := 8.0
const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var elapsed := 0.0
var score := 0
var hearts := 3
var banished := 0
var spooks: Array = [] # dicts: node, kind, speed, phase, base_y, wings
var spawn_timer := 1.0
var beams: Array = [] # dicts: node, life
var minute_pivot: Node3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var zap_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var hurt_player: AudioStreamPlayer = null
var chime_a: AudioStreamPlayer = null
var chime_b: AudioStreamPlayer = null

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
# v0.7.0: morphed dungeon gate and monster lair the spooks pour out of
# (game-local coords).
var _room_door_pos := Vector3.ZERO
var _room_door_known := false
var _room_bed_pos := Vector3.ZERO
var _room_bed_known := false
var _clock_node: Node3D = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_room()
	_build_clock()
	_build_hud()
	zap_player = _make_player(_make_tone(1250.0, 0.14, 0.5))
	miss_player = _make_player(_make_tone(300.0, 0.08, 0.3))
	hurt_player = _make_player(_make_tone(110.0, 0.40, 0.65))
	chime_a = _make_player(_make_tone(660.0, 0.45, 0.5))
	chime_b = _make_player(_make_tone(880.0, 0.70, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_midnight_survival_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.6, -1.0), 3.0)
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
	# Keep the clock tower inside the real room.
	if _clock_node != null and _room_bounds.size.y > 1.5:
		_clock_node.position.z = maxf(_clock_node.position.z, _room_bounds.position.y + 0.8)
	# v0.7.0 furniture morphs: the real door becomes a haunted dungeon
	# gate and the bed becomes a monster lair — spooks pour out of both
	# (see _spook_spawn_pos).
	var door_anchors := RoomKit.get_anchors("DOOR")
	if not door_anchors.is_empty():
		RoomKit.morph(door_anchors[0], "haunted")
		_room_door_pos = door_anchors[0]["position"]
		_room_door_known = true
	var bed_anchors := RoomKit.get_anchors("BED")
	if not bed_anchors.is_empty():
		RoomKit.morph(bed_anchors[0], "haunted")
		_room_bed_pos = bed_anchors[0]["position"]
		_room_bed_known = true


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
	camera.position = Vector3(0.0, 1.7, 3.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, -2.0), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	elapsed += delta
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_midnight_survival_main", global_transform)
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
		_update_beams(delta)
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_win()
		return
	# Clock creeps toward midnight.
	if minute_pivot != null:
		minute_pivot.rotation.z = lerpf(0.55, 0.02, elapsed / ROUND_TIME)
	# Spawn waves, faster and quicker as midnight nears.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.55, 1.7 - elapsed * 0.013)
		if spooks.size() < MAX_SPOOKS:
			_spawn_spook()
	# Pinch / click = zap.
	if ARUpgradeKit.pinch_just_pressed(self):
		_zap()
	_update_spooks(delta)
	_update_beams(delta)
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
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.09, 0.08, 0.12), 0.0, 0.9)
	add_child(floor_inst)
	# Moon.
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.9
	ms.height = 1.8
	moon.mesh = ms
	moon.position = Vector3(5.0, 5.5, -8.0)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.93, 0.80), 1.5)
	add_child(moon)
	# Dead trees.
	_build_tree(Vector3(-3.4, 0.0, -3.2))
	_build_tree(Vector3(3.6, 0.0, -2.6))


func _build_tree(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var bark := GraphicsPolish.pbr(Color(0.16, 0.11, 0.09), 0.0, 0.9)
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.06
	tc.bottom_radius = 0.11
	tc.height = 1.8
	trunk.mesh = tc
	trunk.position.y = 0.9
	trunk.material_override = bark
	root.add_child(trunk)
	for bi in range(3):
		var branch := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.02
		bc.bottom_radius = 0.045
		bc.height = 0.8
		branch.mesh = bc
		var ba := float(bi) * TAU / 3.0
		branch.position = Vector3(cos(ba) * 0.25, 1.35 + float(bi) * 0.12, sin(ba) * 0.25)
		branch.rotation = Vector3(0.0, -ba, 0.9)
		branch.material_override = bark
		root.add_child(branch)


func _build_clock() -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, 2.4, -4.2)
	add_child(root)
	_clock_node = root
	# Tower post.
	var post := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.08
	pc.bottom_radius = 0.10
	pc.height = 2.4
	post.mesh = pc
	post.position = Vector3(0.0, -1.2, 0.0)
	post.material_override = GraphicsPolish.pbr(Color(0.20, 0.14, 0.10), 0.1, 0.6)
	root.add_child(post)
	# Face.
	var face := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.55
	fc.bottom_radius = 0.55
	fc.height = 0.10
	face.mesh = fc
	face.rotation_degrees.x = 90.0
	face.material_override = GraphicsPolish.pbr(Color(0.90, 0.88, 0.80), 0.0, 0.5)
	root.add_child(face)
	var rim := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.52
	rt.outer_radius = 0.60
	rim.mesh = rt
	rim.material_override = GraphicsPolish.pbr_preset(Color(0.30, 0.20, 0.12), "metal")
	root.add_child(rim)
	# Hour hand (near 12).
	var hour_pivot := Node3D.new()
	root.add_child(hour_pivot)
	var hh := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.07, 0.30, 0.03)
	hh.mesh = hb
	hh.position = Vector3(0.0, 0.12, 0.06)
	hh.material_override = GraphicsPolish.pbr(Color(0.10, 0.10, 0.12), 0.0, 0.6)
	hour_pivot.add_child(hh)
	hour_pivot.rotation.z = -0.06
	# Minute hand creeps to 12 as the round runs.
	minute_pivot = Node3D.new()
	root.add_child(minute_pivot)
	var mh := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.05, 0.46, 0.03)
	mh.mesh = mb
	mh.position = Vector3(0.0, 0.18, 0.07)
	mh.material_override = GraphicsPolish.glow(Color(0.65, 0.85, 1.0), 0.9)
	minute_pivot.add_child(mh)
	minute_pivot.rotation.z = 0.55
	var pin := MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = 0.05
	ps.height = 0.10
	pin.mesh = ps
	pin.position = Vector3(0.0, 0.0, 0.08)
	pin.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.70, 0.20), "metal")
	root.add_child(pin)
	GraphicsPolish.make_point_light(root, Vector3(0, 0.3, 1.0), Color(0.65, 0.8, 1.0), 0.9, 4.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("MIDNIGHT SURVIVAL", 44, Color(0.75, 0.6, 1.0))
	hud_label.position = Vector3(-3.1, 2.7, 0.4)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.35))
	msg_label.position = Vector3(0.0, 2.1, -2.6)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "MIDNIGHT SURVIVAL\nMidnight in: %ds   HP: %d   Score: %d\nPinch / click to ZAP the spooks!\nR: restart" % [int(ceil(time_left)), hearts, score]


func _show_msg(text: String, duration: float = 1.6) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ----------------------------------------------------------------- spooks --

func _spawn_spook() -> void:
	var kind := randi_range(0, 2) # 0 ghost, 1 bat, 2 pumpkin-head
	var root := Node3D.new()
	var base_y := 1.2
	var speed := 0.55 + elapsed * 0.008 + randf() * 0.30
	var wings: Array = []
	match kind:
		0:
			base_y = 1.2
			_build_ghost_mesh(root)
		1:
			base_y = 2.0
			wings = _build_bat_mesh(root)
		2:
			base_y = 0.45
			_build_pumpkin_mesh(root)
			speed *= 1.25
	root.position = _spook_spawn_pos(base_y)
	add_child(root)
	spooks.append({"node": root, "kind": kind, "speed": speed, "phase": randf() * TAU, "base_y": base_y, "wings": wings})


func _spook_spawn_pos(base_y: float) -> Vector3:
	# Spooks emerge from the real walls when the room is known,
	# otherwise close in from a circle clamped to the room's extents.
	# The morphed dungeon gate and monster lair are favored spawn mouths.
	if _room_door_known and randf() < 0.30:
		return Vector3(_room_door_pos.x, base_y, _room_door_pos.z)
	if _room_bed_known and randf() < 0.25:
		return Vector3(_room_bed_pos.x + randf_range(-0.3, 0.3), minf(base_y, 0.6), _room_bed_pos.z + randf_range(-0.3, 0.3))
	if _room_known and not _room_walls.is_empty() and randf() < 0.6:
		var w: Dictionary = _room_walls[randi() % _room_walls.size()]
		var bp: Vector3 = (w["position"] as Vector3) + _wall_inward(w) * 0.4
		return Vector3(bp.x, base_y, bp.z)
	var r := randf_range(4.2, 5.0)
	if _room_known:
		r = minf(r, maxf(1.6, minf(_room_bounds.size.x, _room_bounds.size.y) * 0.5 - 0.3))
	var ang := randf() * TAU
	return Vector3(cos(ang) * r, base_y, sin(ang) * r - 1.0)


func _build_ghost_mesh(root: Node3D) -> void:
	var sheet := GraphicsPolish.pbr(Color(0.90, 0.92, 0.97), 0.0, 0.7)
	sheet.emission_enabled = true
	sheet.emission = Color(0.70, 0.75, 0.90)
	sheet.emission_energy_multiplier = 0.4
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.16
	hs.height = 0.32
	head.mesh = hs
	head.position.y = 0.22
	head.material_override = sheet
	root.add_child(head)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.20
	cyl.height = 0.40
	body.mesh = cyl
	body.position.y = -0.10
	body.material_override = sheet
	root.add_child(body)
	var dark := GraphicsPolish.pbr(Color(0.05, 0.05, 0.08), 0.0, 0.9)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.035
		es.height = 0.07
		eye.mesh = es
		eye.position = Vector3(side * 0.06, 0.26, 0.14)
		eye.material_override = dark
		root.add_child(eye)


func _build_bat_mesh(root: Node3D) -> Array:
	var dark := GraphicsPolish.pbr(Color(0.08, 0.06, 0.12), 0.0, 0.8)
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	body.mesh = s
	body.material_override = dark
	root.add_child(body)
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.10, 0.05, 0.0)
		root.add_child(pivot)
		var wing := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(0.26, 0.02, 0.14)
		wing.mesh = wb
		wing.position = Vector3(side * 0.15, 0.0, 0.0)
		wing.material_override = dark
		pivot.add_child(wing)
		wings.append(pivot)
	var eye_mat := GraphicsPolish.glow(Color(1.0, 0.20, 0.20), 1.8)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		eye.mesh = es
		eye.position = Vector3(side * 0.05, 0.05, 0.11)
		eye.material_override = eye_mat
		root.add_child(eye)
	return wings


func _build_pumpkin_mesh(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.15
	s.height = 0.26
	body.mesh = s
	body.material_override = GraphicsPolish.pbr(Color(0.92, 0.48, 0.08), 0.05, 0.5)
	root.add_child(body)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.03
	cyl.height = 0.08
	stem.mesh = cyl
	stem.position.y = 0.16
	stem.material_override = GraphicsPolish.pbr(Color(0.20, 0.45, 0.15), 0.0, 0.8)
	root.add_child(stem)
	var face := GraphicsPolish.glow(Color(1.0, 0.80, 0.25), 1.8)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.045, 0.06, 0.02)
		eye.mesh = eb
		eye.position = Vector3(side * 0.055, 0.04, 0.135)
		eye.material_override = face
		root.add_child(eye)


func _update_spooks(delta: float) -> void:
	for i in range(spooks.size() - 1, -1, -1):
		var sp: Dictionary = spooks[i]
		var node: Node3D = sp["node"]
		if not is_instance_valid(node):
			spooks.remove_at(i)
			continue
		var to_center := Vector3(-node.position.x, 0.0, -node.position.z)
		var dist := to_center.length()
		if dist < 0.75:
			_spook_attack(sp)
			continue
		to_center = to_center.normalized()
		node.position += to_center * float(sp["speed"]) * delta
		node.position.y = float(sp["base_y"]) + sin(elapsed * 3.0 + float(sp["phase"])) * 0.08
		node.rotation.y = atan2(-to_center.x, -to_center.z)
		if int(sp["kind"]) == 1:
			for w_v in (sp["wings"] as Array):
				var pivot: Node3D = w_v
				var side_sign := 1.0 if pivot.position.x > 0.0 else -1.0
				pivot.rotation.z = side_sign * (0.25 + sin(elapsed * 12.0 + float(sp["phase"])) * 0.55)


func _spook_attack(sp: Dictionary) -> void:
	var node: Node3D = sp["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, to_local(node.global_position), Color(1.0, 0.25, 0.25), 30)
		node.queue_free()
	spooks.erase(sp)
	hearts -= 1
	hurt_player.play()
	if hearts <= 0:
		_lose()
	else:
		_show_msg("A SPOOK GOT YOU!  HP: %d" % hearts, 1.4)


# -------------------------------------------------------------------- zap --

func _zap() -> void:
	var ray: Array = ARUpgradeKit.pointer_ray(self)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var best: Dictionary = {}
	var best_ang := ZAP_ANGLE
	for sp_v in spooks:
		var sp: Dictionary = sp_v
		var node: Node3D = sp["node"]
		if not is_instance_valid(node):
			continue
		var to: Vector3 = node.global_position - o
		var dist := to.length()
		if dist > ZAP_RANGE or dist < 0.05:
			continue
		var ang := d.angle_to(to / dist)
		if ang < best_ang:
			best_ang = ang
			best = sp
	if best.is_empty():
		miss_player.play()
		return
	var bnode: Node3D = best["node"]
	var target: Vector3 = bnode.global_position
	_spawn_beam(o, target)
	GraphicsPolish.spawn_sparks(self, to_local(target), Color(0.65, 0.85, 1.0), 28)
	bnode.queue_free()
	spooks.erase(best)
	score += 10
	banished += 1
	zap_player.play()


func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = length
	beam.mesh = cyl
	beam.material_override = GraphicsPolish.glow(Color(0.70, 0.90, 1.0), 2.2)
	beam.global_position = (from + to) * 0.5
	add_child(beam)
	beam.look_at(to, Vector3.UP)
	beam.rotation.x += PI * 0.5
	beams.append({"node": beam, "life": 0.14})


func _update_beams(delta: float) -> void:
	for i in range(beams.size() - 1, -1, -1):
		var b: Dictionary = beams[i]
		var node: MeshInstance3D = b["node"]
		if not is_instance_valid(node):
			beams.remove_at(i)
			continue
		var life := float(b["life"]) - delta
		b["life"] = life
		if life <= 0.0:
			node.queue_free()
			beams.remove_at(i)


# ------------------------------------------------------------------ flow ---

func _win() -> void:
	state = ST_OVER
	chime_a.play()
	chime_b.play()
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.0), 90)
	_show_msg("MIDNIGHT!\nYou survived!  Score: %d   Banished: %d\nHold pinch 1s or press R" % [score, banished], 600.0)
	ARUpgradeKit.save_anchor("hw_midnight_survival_main", global_transform)


func _lose() -> void:
	state = ST_OVER
	_show_msg("THE SPOOKS GOT YOU!\nScore: %d   Banished: %d\nHold pinch 1s or press R to try again" % [score, banished], 600.0)
	ARUpgradeKit.save_anchor("hw_midnight_survival_main", global_transform)


func _reset_game() -> void:
	for sp_v in spooks:
		var sp: Dictionary = sp_v
		var node: Node3D = sp["node"]
		if is_instance_valid(node):
			node.queue_free()
	spooks.clear()
	for b_v in beams:
		var b: Dictionary = b_v
		var bn: MeshInstance3D = b["node"]
		if is_instance_valid(bn):
			bn.queue_free()
	beams.clear()
	time_left = ROUND_TIME
	elapsed = 0.0
	score = 0
	hearts = 3
	banished = 0
	spawn_timer = 1.0
	hold_restart = 0.0
	state = ST_PLAY
	if minute_pivot != null:
		minute_pivot.rotation.z = 0.55
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_midnight_survival_main", global_transform)


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
