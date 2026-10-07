## HwWebSlingshot - "Web Slingshot": a spider-web slingshot range.
## Pinch (or press the mouse) to grab the web pouch, drag back to pull,
## release to fire a web-ball at the spider targets on the far wall.
## 20 points per hit. 60-second rounds with score + restart.
extends Node3D

const ROUND_TIME := 60.0
const TARGET_Z := -3.2
const MAX_PULL := 0.8
const ST_PLAY := 0
const ST_OVER := 1
const SLING_POS := Vector3(0.0, 0.85, 0.6)
const POUCH_REST := Vector3(0.0, 0.95, 0.45)

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var hits := 0
var shots := 0
var elapsed := 0.0
var pouch := Vector3.ZERO
var dragging := false
var drag_hand := false # true when the drag came from a pinch
var targets: Array = [] # dicts: node, mat, base, phase, speed, active, respawn_t
var bolts: Array = [] # dicts: node, vel, life
var web_left: MeshInstance3D = null
var web_right: MeshInstance3D = null
var fork_l := Vector3.ZERO
var fork_r := Vector3.ZERO
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var fire_player: AudioStreamPlayer = null
var hit_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()

## RoomKit v0.7.0: cached room layout + fake range pieces (retired on real walls).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _range_set: Array = []


func _ready() -> void:
	rng.randomize()
	_add_light_rig()
	_ensure_fallback_camera()
	_build_range()
	_build_slingshot()
	_build_targets()
	_build_hud()
	pouch = POUCH_REST
	ARUpgradeKit.apply_anchor(self, "hw_web_slingshot_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -1.5), 2.5, 36)
	fire_player = _make_player(_make_tone(300.0, 0.12, 0.5))
	hit_player = _make_player(_make_tone(700.0, 0.14, 0.55))
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
	camera.position = Vector3(0.0, 1.5, 2.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -2.0), Vector3.UP)
	camera.current = true


func _build_range() -> void:
	# Back wall the targets cling to.
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(4.4, 2.8, 0.2)
	wall.mesh = wall_box
	wall.position = Vector3(0.0, 1.4, TARGET_Z - 0.15)
	wall.material_override = GraphicsPolish.pbr(Color(0.14, 0.08, 0.12), 0.0, 0.95)
	add_child(wall)
	_range_set.append(wall)
	# Glowing orange frame around the wall.
	var frame_mat := GraphicsPolish.glow(Color(1.0, 0.45, 0.1), 1.4)
	for fx in [-2.2, 2.2]:
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.08, 2.8, 0.08)
		post.mesh = post_box
		post.position = Vector3(fx, 1.4, TARGET_Z - 0.05)
		post.material_override = frame_mat
		add_child(post)
		_range_set.append(post)
	for fy in [0.0, 2.8]:
		var beam := MeshInstance3D.new()
		var beam_box := BoxMesh.new()
		beam_box.size = Vector3(4.5, 0.08, 0.08)
		beam.mesh = beam_box
		beam.position = Vector3(0.0, fy, TARGET_Z - 0.05)
		beam.material_override = frame_mat
		add_child(beam)
		_range_set.append(beam)
	# Cobweb strands across the top corners.
	var web_mat := GraphicsPolish.pbr(Color(0.85, 0.85, 0.9), 0.0, 0.8)
	for sx in [-1.6, 1.6]:
		var strand := MeshInstance3D.new()
		var strand_box := BoxMesh.new()
		strand_box.size = Vector3(0.03, 1.1, 0.03)
		strand.mesh = strand_box
		strand.position = Vector3(sx, 2.2, TARGET_Z - 0.02)
		strand.rotation.z = sx * 0.35
		strand.material_override = web_mat
		add_child(strand)
		_range_set.append(strand)


func _build_slingshot() -> void:
	var wood := GraphicsPolish.pbr(Color(0.40, 0.24, 0.12), 0.05, 0.7)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.06
	base_mesh.bottom_radius = 0.09
	base_mesh.height = SLING_POS.y
	base.mesh = base_mesh
	base.position = Vector3(SLING_POS.x, SLING_POS.y * 0.5, SLING_POS.z)
	base.material_override = wood
	add_child(base)
	fork_l = SLING_POS + Vector3(-0.16, 0.42, -0.05)
	fork_r = SLING_POS + Vector3(0.16, 0.42, -0.05)
	for fork in [fork_l, fork_r]:
		var arm := MeshInstance3D.new()
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.035
		arm_mesh.bottom_radius = 0.045
		arm_mesh.height = 0.5
		arm.mesh = arm_mesh
		arm.position = (SLING_POS + Vector3(0.0, 0.18, 0.0) + fork) * 0.5
		arm.look_at(fork, Vector3.UP)
		arm.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		arm.material_override = wood
		add_child(arm)
	# Web strands: thin cylinders stretched from fork tips to the pouch.
	var web_mat := GraphicsPolish.glow(Color(0.9, 0.95, 1.0), 1.2)
	web_left = _make_web_strand(web_mat)
	web_right = _make_web_strand(web_mat)


func _make_web_strand(mat: Material) -> MeshInstance3D:
	var s := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	s.mesh = cyl
	s.material_override = mat
	add_child(s)
	return s


func _stretch_strand(s: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		s.visible = false
		return
	s.visible = true
	s.position = (a + b) * 0.5
	s.scale = Vector3(1.0, length, 1.0)
	# Cylinder axis is Y; aim it along d.
	var up := Vector3.UP
	if absf(d.normalized().y) > 0.99:
		up = Vector3.RIGHT
	s.look_at(b, up)
	s.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _build_targets() -> void:
	var spots := [
		Vector3(-1.3, 1.1, TARGET_Z), Vector3(-0.45, 1.7, TARGET_Z),
		Vector3(0.45, 1.05, TARGET_Z), Vector3(1.3, 1.75, TARGET_Z),
	]
	for spot in spots:
		targets.append(_build_spider(spot))


func _build_spider(spot: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = spot
	add_child(root)
	var body_mat := GraphicsPolish.pbr(Color(0.10, 0.06, 0.12), 0.2, 0.6)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.75, 1.0)
	body.material_override = body_mat
	root.add_child(body)
	# Legs: thin cylinders splayed out.
	var leg_mat := GraphicsPolish.pbr(Color(0.06, 0.04, 0.08), 0.1, 0.8)
	for i in range(8):
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.015
		leg_mesh.bottom_radius = 0.015
		leg_mesh.height = 0.30
		leg.mesh = leg_mesh
		var ang := float(i) / 8.0 * TAU
		leg.position = Vector3(cos(ang) * 0.22, -0.02, sin(ang) * 0.22)
		leg.rotation = Vector3(sin(ang) * 1.1, 0.0, -cos(ang) * 1.1)
		leg.material_override = leg_mat
		root.add_child(leg)
	# Glowing red eyes: the bullseye.
	var eye_mat := GraphicsPolish.glow(Color(1.0, 0.15, 0.1), 2.2)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 0.05, 0.13)
		eye.material_override = eye_mat
		root.add_child(eye)
	return {
		"node": root, "mat": eye_mat, "base": spot,
		"phase": rng.randf_range(0.0, TAU), "speed": rng.randf_range(0.8, 1.6),
		"active": true, "respawn_t": 0.0,
	}


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("WEB SLINGSHOT", 44, Color(1.0, 0.7, 0.3))
	hud_label.position = Vector3(-2.6, 2.5, -1.2)
	add_child(hud_label)
	var help := GraphicsPolish.make_label("Drag back and release to fire | R: restart", 28, Color(0.85, 0.85, 0.9))
	help.position = Vector3(-2.6, 1.95, -1.2)
	add_child(help)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 2.0, -1.6)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	for tv in targets:
		var t: Dictionary = tv
		if bool(t["active"]):
			GraphicsPolish.pulse_glow(t["mat"], 1.8, 0.9, elapsed * 2.0 + float(t["phase"]))
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
		ARUpgradeKit.save_anchor("hw_web_slingshot_main", global_transform)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	_poll_drag()
	_update_pouch(delta)
	_stretch_strand(web_left, fork_l, pouch)
	_stretch_strand(web_right, fork_r, pouch)
	for tv in targets:
		_step_target(tv, delta)
	for i in range(bolts.size() - 1, -1, -1):
		_step_bolt(bolts[i], delta, i)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != ST_PLAY:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(false)
			else:
				_release_drag()


func _pointer_world() -> Vector3:
	if camera == null:
		return POUCH_REST
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	return ro + rd * 2.0


func _poll_drag() -> void:
	# XR: pinch starts/continues the drag; release fires.
	if ARUpgradeKit.is_xr_active():
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			_begin_drag(true)
		elif dragging and drag_hand and not ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_release_drag()


func _begin_drag(from_pinch: bool) -> void:
	if dragging or state != ST_PLAY:
		return
	dragging = true
	drag_hand = from_pinch


func _release_drag() -> void:
	if not dragging:
		return
	dragging = false
	var pull := POUCH_REST - pouch # rest minus pulled-back pouch
	pull.y = 0.0
	var power := clampf(pull.length() / MAX_PULL, 0.0, 1.0)
	if power < 0.08:
		pouch = POUCH_REST
		return
	var dir := pull.normalized()
	dir.y = 0.12
	_fire(dir.normalized(), 6.0 + power * 14.0)


func _update_pouch(delta: float) -> void:
	if dragging:
		var pw := _pointer_world()
		# Pull the pouch back toward the player (+z), capped at MAX_PULL.
		var offset := pw - POUCH_REST
		offset = Vector3(offset.x, 0.0, maxf(offset.z, 0.0))
		if offset.length() > MAX_PULL:
			offset = offset.normalized() * MAX_PULL
		pouch = POUCH_REST + offset * 0.6
	else:
		pouch = pouch.lerp(POUCH_REST, clampf(20.0 * delta, 0.0, 1.0))


func _fire(dir: Vector3, speed: float) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	node.mesh = sphere
	node.material_override = GraphicsPolish.glow(Color(0.9, 0.95, 1.0), 1.8)
	node.position = pouch
	add_child(node)
	node.add_child(GraphicsPolish.make_trail(Color(0.8, 0.9, 1.0), 0.04))
	bolts.append({"node": node, "vel": dir * speed, "life": 3.0})
	shots += 1
	if fire_player != null:
		fire_player.play()


func _step_bolt(bv: Variant, delta: float, idx: int) -> void:
	var b: Dictionary = bv
	var node: Node3D = b["node"]
	var vel: Vector3 = b["vel"]
	vel.y -= 6.5 * delta
	b["vel"] = vel
	node.position += vel * delta
	b["life"] = float(b["life"]) - delta
	# Hit check against active targets.
	for tv in targets:
		var t: Dictionary = tv
		if not bool(t["active"]):
			continue
		var tn: Node3D = t["node"]
		if node.position.distance_to(tn.position) < 0.34:
			_hit_target(t)
			_free_bolt(b, idx)
			return
	if float(b["life"]) <= 0.0 or node.position.z < TARGET_Z - 0.6 or node.position.y < 0.02:
		_free_bolt(b, idx)


func _free_bolt(b: Dictionary, idx: int) -> void:
	var node: Node3D = b["node"]
	if is_instance_valid(node):
		node.queue_free()
	bolts.remove_at(idx)


func _hit_target(t: Dictionary) -> void:
	var node: Node3D = t["node"]
	GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.5, 0.15), 30)
	score += 20
	hits += 1
	t["active"] = false
	t["respawn_t"] = 1.4
	node.visible = false
	_show_msg("+20  BULLSEYE!", 0.8)
	if hit_player != null:
		hit_player.play()


func _step_target(tv: Variant, delta: float) -> void:
	var t: Dictionary = tv
	if not bool(t["active"]):
		t["respawn_t"] = float(t["respawn_t"]) - delta
		if float(t["respawn_t"]) <= 0.0:
			t["active"] = true
			(t["node"] as Node3D).visible = true
		return
	var node: Node3D = t["node"]
	var base: Vector3 = t["base"]
	node.position = base + Vector3(sin(elapsed * float(t["speed"]) + float(t["phase"])) * 0.35, 0.0, 0.0)


func _game_over() -> void:
	state = ST_OVER
	var acc := 0.0
	if shots > 0:
		acc = 100.0 * float(hits) / float(shots)
	_show_msg("TIME UP!\nScore: %d   Hits: %d/%d (%.0f%%)\nPress R or pinch-hold to restart" % [score, hits, shots, acc], 600.0)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -1.5), 60)
	ARUpgradeKit.save_anchor("hw_web_slingshot_main", global_transform)
	if end_player != null:
		end_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	hits = 0
	shots = 0
	pinch_hold = 0.0
	dragging = false
	pouch = POUCH_REST
	for bv in bolts:
		var b: Dictionary = bv
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	bolts.clear()
	for tv in targets:
		var t: Dictionary = tv
		t["active"] = true
		t["respawn_t"] = 0.0
		(t["node"] as Node3D).visible = true
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_web_slingshot_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "WEB SLINGSHOT\nTime: %ds   Score: %d   Hits: %d" % [int(ceil(time_left)), score, hits]


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


## Synthesize a short enveloped sine tone (fire / hit / jingle).
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
	# v0.7.0 MORPH-C: chairs become haunted spider nests (slingshot targets guard them); windows show haunted vistas.
	var _morph0_chair := RoomKit.get_anchors("CHAIR")
	if not _morph0_chair.is_empty():
		RoomKit.morph(_morph0_chair[0], "haunted")
	var _morph1_window := RoomKit.get_anchors("WINDOW")
	if not _morph1_window.is_empty():
		RoomKit.morph(_morph1_window[0], "haunted")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	if _room_walls.is_empty():
		return
	# Mount bonus spider targets on the largest real wall; the fake
	# backboard range retires since the spiders cling to the real wall.
	var w := _room_largest_wall()
	if w.is_empty():
		return
	var wp: Vector3 = w["position"]
	var n: Vector3 = w["normal"]
	n.y = 0.0
	if n.length() < 0.01:
		return
	n = n.normalized()
	var tangent := Vector3(-n.z, 0.0, n.x)
	var span: Vector2 = w["size"]
	for k in 2:
		var off := (float(k) - 0.5) * maxf(span.x * 0.5 - 0.6, 0.6)
		var h := 1.25 + 0.35 * float(k)
		var spot := to_local(Vector3(wp.x, h, wp.z) + n * 0.5 + tangent * off)
		targets.append(_build_spider(spot))
	for piece in _range_set:
		(piece as Node3D).visible = false


## RoomKit: the wall with the largest face area, or {} when none.
func _room_largest_wall() -> Dictionary:
	var best := {}
	var best_a := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var sz: Vector2 = w["size"]
		var a := sz.x * sz.y
		if a > best_a:
			best_a = a
			best = w
	return best
