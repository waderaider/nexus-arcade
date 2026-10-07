## HwGraveDigger - "Grave Digger": a haunted graveyard patch on the floor.
## Pinch-dig (or click) the glowing dig spots: candy = +15 points,
## skeleton = trick (-10). Most candy in 90s wins.
extends Node3D

const ST_PLAY := 0
const ST_OVER := 1
const ROUND_TIME := 90.0
const CANDY_POINTS := 15
const TRICK_PENALTY := 10
const DIG_RADIUS := 0.5
const PATCH_RADIUS := 1.7
const MAX_SPOTS := 4
const ANCHOR_NAME := "hw_grave_digger_main"

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var candy := 0
var tricks := 0
var elapsed := 0.0
var spots: Array = [] # dicts: node, ring_mat, mound
var finds: Array = [] # dicts: node, timer (transient candy/skeleton reveals)
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
# The graveyard sits on a stage so it can be centered in the real room;
# dig-spot math stays in stage-local coordinates.
var yard_stage: Node3D = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	yard_stage = Node3D.new()
	yard_stage.name = "YardStage"
	add_child(yard_stage)
	_build_graveyard()
	_build_hud()
	for i in range(MAX_SPOTS):
		_spawn_spot()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, -1.2), 2.5, 44)
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
	# Center the graveyard patch in the real room — on the rug when one
	# is known: the rug becomes an arcane magic-circle arena boundary.
	var c := _room_bounds.get_center()
	var rug_anchors := RoomKit.get_anchors("RUG")
	if not rug_anchors.is_empty():
		RoomKit.morph(rug_anchors[0], "arcane")
		var rp: Vector3 = rug_anchors[0]["position"]
		c = Vector2(rp.x, rp.z)
	yard_stage.position = Vector3(c.x, 0.0, c.y + 1.2)


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.8)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.6, 2.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.1, -1.2), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.2, 0.7)


func _build_graveyard() -> void:
	# Ground + soil patch.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.01, -1.2)
	ground.material_override = _mat(Color(0.08, 0.10, 0.07))
	yard_stage.add_child(ground)
	var patch := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = PATCH_RADIUS
	pcyl.bottom_radius = PATCH_RADIUS
	pcyl.height = 0.08
	patch.mesh = pcyl
	patch.position = Vector3(0.0, 0.03, -1.2)
	patch.material_override = _mat(Color(0.20, 0.13, 0.08))
	yard_stage.add_child(patch)
	# Tombstones ringing the patch.
	for i in range(7):
		var ang := TAU * float(i) / 7.0 + 0.2
		var pos := Vector3(cos(ang) * (PATCH_RADIUS + 0.55), 0.0, -1.2 + sin(ang) * (PATCH_RADIUS + 0.55))
		_make_tombstone(pos, ang)
	# Fence posts + rails around the patch.
	var post_mat := _mat(Color(0.14, 0.10, 0.08))
	for i in range(10):
		var ang := TAU * float(i) / 10.0
		var pos := Vector3(cos(ang) * (PATCH_RADIUS + 1.1), 0.0, -1.2 + sin(ang) * (PATCH_RADIUS + 1.1))
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, 0.7, 0.08)
		post.mesh = pm
		post.position = pos + Vector3(0.0, 0.35, 0.0)
		post.material_override = post_mat
		yard_stage.add_child(post)
		var nang := TAU * float(i + 1) / 10.0
		var npos := Vector3(cos(nang) * (PATCH_RADIUS + 1.1), 0.0, -1.2 + sin(nang) * (PATCH_RADIUS + 1.1))
		var mid := (pos + npos) * 0.5
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(pos.distance_to(npos), 0.05, 0.05)
		rail.mesh = rm
		rail.position = mid + Vector3(0.0, 0.5, 0.0)
		rail.rotation.y = atan2(-(npos.z - pos.z), npos.x - pos.x)
		rail.material_override = post_mat
		yard_stage.add_child(rail)
	# Sickly green accent light over the patch.
	GraphicsPolish.make_point_light(yard_stage, Vector3(0.0, 1.6, -1.2), Color(0.45, 1.0, 0.4), 0.7, 6.0)


func _make_tombstone(pos: Vector3, ang: float) -> void:
	var stone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.62, 0.12)
	stone.mesh = bm
	stone.position = pos + Vector3(0.0, 0.3, 0.0)
	stone.rotation.y = -ang + PI * 0.5
	stone.rotation.z = randf_range(-0.12, 0.12)
	stone.material_override = _mat(Color(0.42, 0.42, 0.46))
	yard_stage.add_child(stone)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.2
	cm.height = 0.18
	cap.mesh = cm
	cap.position = pos + Vector3(0.0, 0.68, 0.0)
	cap.rotation.y = -ang + PI * 0.5
	cap.material_override = _mat(Color(0.38, 0.38, 0.42))
	yard_stage.add_child(cap)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("GRAVE DIGGER", 44, Color(0.7, 1.0, 0.6))
	hud_label.position = Vector3(-2.8, 3.0, -3.2)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Pinch or click a glowing dig spot | candy +15, skeleton -10 | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-2.8, 2.5, -3.2)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -3.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "GRAVE DIGGER   %ds   Score: %d\nCandy: %d   Tricks: %d" % [int(ceil(maxf(time_left, 0.0))), score, candy, tricks]


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
	time_left -= delta
	if time_left <= 0.0:
		_game_over()
		return
	# Dig via pinch.
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_dig(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT))
	# Pulse the dig-spot rings; float the reveals.
	for s_v in spots:
		var s: Dictionary = s_v
		if is_instance_valid(s["node"]):
			GraphicsPolish.pulse_glow(s["ring_mat"], 1.3, 1.1, elapsed * 3.5)
	for i in range(finds.size() - 1, -1, -1):
		var f: Dictionary = finds[i]
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			finds.remove_at(i)
			continue
		f["timer"] = float(f["timer"]) - delta
		node.position.y += delta * 0.25
		if float(f["timer"]) <= 0.0:
			node.queue_free()
			finds.remove_at(i)
			_spawn_spot()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY and camera != null:
			var origin := camera.project_ray_origin(mb.position)
			var dir := camera.project_ray_normal(mb.position)
			# Project the click onto the ground plane (y=0) for dig checks.
			if absf(dir.y) > 0.001:
				var t := -origin.y / dir.y
				if t > 0.0:
					_try_dig(origin + dir * t)


func _poll_restart_pinch(delta: float) -> void:
	var pinch_any := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT) or ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)
	if pinch_any:
		_pinch_hold += delta
		if _pinch_hold >= 1.0:
			_pinch_hold = 0.0
			_reset_game()
	else:
		_pinch_hold = 0.0


func _spot_pos() -> Vector3:
	# Dig spots stay inside the real room and out from under furniture.
	for attempt in range(6):
		var ang := randf() * TAU
		var r := randf_range(0.3, PATCH_RADIUS - 0.35)
		var p := Vector3(cos(ang) * r, 0.07, -1.2 + sin(ang) * r)
		if _room_known and yard_stage != null:
			var wp: Vector3 = yard_stage.to_global(p)
			if wp.x < _room_bounds.position.x + 0.4 or wp.x > _room_bounds.end.x - 0.4:
				continue
			if wp.z < _room_bounds.position.y + 0.4 or wp.z > _room_bounds.end.y - 0.4:
				continue
			if _spot_blocked(wp):
				continue
		return p
	return Vector3(0.0, 0.07, -1.2)


func _spot_blocked(wp: Vector3) -> bool:
	for f_v in _room_tables + _room_furniture:
		var f: Dictionary = f_v
		var fp: Vector3 = f["position"]
		var fs: Vector3 = f["size"]
		if absf(wp.x - fp.x) < fs.x * 0.5 + 0.25 and absf(wp.z - fp.z) < fs.z * 0.5 + 0.25:
			return true
	return false


func _spawn_spot() -> void:
	var root := Node3D.new()
	root.position = _spot_pos()
	yard_stage.add_child(root)
	# Dirt mound.
	var mound := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.22
	mm.height = 0.20
	mound.mesh = mm
	mound.position.y = 0.02
	mound.scale = Vector3(1.0, 0.55, 1.0)
	mound.material_override = _mat(Color(0.26, 0.17, 0.10))
	root.add_child(mound)
	# Glowing dig ring.
	var ring_mat := GraphicsPolish.glow(Color(1.0, 0.6, 0.15), 1.6)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.30
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position.y = 0.06
	ring.material_override = ring_mat
	root.add_child(ring)
	spots.append({"node": root, "ring_mat": ring_mat})


func _try_dig(world_pos: Vector3) -> void:
	if state != ST_PLAY:
		return
	var best := -1
	var best_d := DIG_RADIUS
	for i in range(spots.size()):
		var s: Dictionary = spots[i]
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(world_pos.x - node.global_position.x, world_pos.z - node.global_position.z).length()
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	var s: Dictionary = spots[best]
	var node: Node3D = s["node"]
	var dig_pos := node.global_position
	node.queue_free()
	spots.remove_at(best)
	# 70% candy, 30% skeleton trick.
	if randf() < 0.7:
		_reveal_candy(dig_pos)
	else:
		_reveal_skeleton(dig_pos)


func _reveal_candy(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos + Vector3(0.0, 0.25, 0.0)
	add_child(root)
	var orb := MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.11
	om.height = 0.22
	orb.mesh = om
	orb.material_override = GraphicsPolish.glow(Color(1.0, 0.45, 0.1), 1.4)
	root.add_child(orb)
	for side in [-1.0, 1.0]:
		var wrap := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.10, 0.06, 0.06)
		wrap.mesh = wm
		wrap.position = Vector3(side * 0.14, 0.0, 0.0)
		wrap.material_override = _mat(Color(1.0, 0.75, 0.3))
		root.add_child(wrap)
	finds.append({"node": root, "timer": 1.4})
	score += CANDY_POINTS
	candy += 1
	GraphicsPolish.spawn_sparks(self, root.position, Color(1.0, 0.6, 0.15), 20)
	_sfx("candy", 880.0, 0.15, 0.5)
	_show_msg("TREAT! +%d" % CANDY_POINTS, 1.0)


func _reveal_skeleton(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos + Vector3(0.0, 0.25, 0.0)
	add_child(root)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	skull.mesh = sm
	skull.material_override = _mat(Color(0.88, 0.86, 0.78))
	root.add_child(skull)
	for rot in [0.6, -0.6]:
		var bone := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.30, 0.04, 0.04)
		bone.mesh = bm
		bone.position.y = -0.14
		bone.rotation.z = rot
		bone.material_override = _mat(Color(0.82, 0.80, 0.72))
		root.add_child(bone)
	finds.append({"node": root, "timer": 1.4})
	score = maxi(0, score - TRICK_PENALTY)
	tricks += 1
	GraphicsPolish.spawn_sparks(self, root.position, Color(0.4, 1.0, 0.4), 20)
	_sfx("trick", 150.0, 0.35, 0.55)
	_show_msg("TRICK! -%d" % TRICK_PENALTY, 1.0)


func _game_over() -> void:
	state = ST_OVER
	time_left = 0.0
	for s_v in spots:
		var s: Dictionary = s_v
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
	spots.clear()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.2), 70)
	_sfx("win", 880.0, 0.4, 0.5)
	_show_msg("DIGGING DONE!\nScore: %d  (%d treats)\nHold pinch 1s or press R" % [score, candy], 600.0)
	_update_hud()


func _reset_game() -> void:
	for s_v in spots:
		var s: Dictionary = s_v
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
	spots.clear()
	for f_v in finds:
		var f: Dictionary = f_v
		var node: Node3D = f["node"]
		if is_instance_valid(node):
			node.queue_free()
	finds.clear()
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	candy = 0
	tricks = 0
	elapsed = 0.0
	_pinch_hold = 0.0
	for i in range(MAX_SPOTS):
		_spawn_spot()
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
