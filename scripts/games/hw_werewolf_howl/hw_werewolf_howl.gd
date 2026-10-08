## HwWerewolfHowl - "Werewolf Howl": villagers close in on your moonlit clearing.
## Hold BOTH pinches (or both mouse buttons) to charge a howl, release to blast
## the villagers back. 90s round, 3 hearts. Bigger charge = bigger blast.
extends Node3D

const ST_PLAY := 0
const ST_OVER := 1
const ROUND_TIME := 90.0
const MAX_CHARGE := 3.0
const ANCHOR_NAME := "hw_werewolf_howl_main"

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var hearts := 3
var elapsed := 0.0
var charge := 0.0
var charging := false
var spawn_timer := 1.0
var villagers: Array = [] # dicts: node, speed
var blasts: Array = [] # dicts: node, mat, t, max_r
var charge_ring: MeshInstance3D = null
var charge_mat: StandardMaterial3D = null
var wolf_head: MeshInstance3D = null
var wolf_tilt: Node3D = null  # v0.9.1: model path — howl pivot tilted instead of the head
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
# v0.7.0: morphed window the moon hangs beyond (game-local coords).
var _room_window_pos := Vector3.ZERO
var _room_window_known := false
var _moon_node: MeshInstance3D = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_clearing()
	_build_wolf()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -2.0), 3.0, 40)
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
	# v0.7.0 furniture morph: the real window becomes an eerie haunted
	# vista, and the full moon hangs in the sky beyond it — howl while
	# facing your window to face the moon.
	var window_anchors := RoomKit.get_anchors("WINDOW")
	if not window_anchors.is_empty():
		RoomKit.morph(window_anchors[0], "haunted")
		var wp: Vector3 = window_anchors[0]["position"]
		_room_window_pos = wp
		_room_window_known = true
		var c := _room_bounds.get_center()
		var outward := Vector3(wp.x - c.x, 0.0, wp.z - c.y)
		if outward.length() < 0.05:
			outward = Vector3(0.0, 0.0, -1.0)
		outward = outward.normalized()
		if _moon_node != null:
			_moon_node.position = Vector3(c.x, 0.0, c.y) + outward * 8.0 + Vector3(0.0, 3.4, 0.0)


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
	GraphicsPolish.make_light_rig(self, 0.7)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.2, 4.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.9, -1.5), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.25, 0.55)


func _cone(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	return c


func _build_clearing() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, 0.0, -1.5)
	floor_inst.material_override = _mat(Color(0.07, 0.10, 0.08))
	add_child(floor_inst)
	# Full moon backdrop.
	var moon := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.4
	disc.bottom_radius = 1.4
	disc.height = 0.1
	moon.mesh = disc
	moon.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	moon.position = Vector3(0.0, 3.4, -9.0)
	moon.material_override = _mat(Color(0.95, 0.93, 0.75), 1.8)
	add_child(moon)
	_moon_node = moon
	GraphicsPolish.make_point_light(self, Vector3(0.0, 3.0, -4.0), Color(0.85, 0.9, 1.0), 0.7, 9.0)
	# Dead trees ringing the clearing.
	for i in range(7):
		var ang := TAU * float(i) / 7.0 + 0.3
		_make_tree(Vector3(cos(ang) * 5.2, 0.0, -1.5 + sin(ang) * 5.2))


func _make_tree(pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = pos
	add_child(tree)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.06
	tm.bottom_radius = 0.12
	tm.height = 1.6
	trunk.mesh = tm
	trunk.position.y = 0.8
	trunk.material_override = _mat(Color(0.13, 0.09, 0.07))
	tree.add_child(trunk)
	for b in range(3):
		var branch := MeshInstance3D.new()
		branch.mesh = _cone(0.05, 0.9)
		branch.position = Vector3(0.0, 1.3 + float(b) * 0.25, 0.0)
		branch.rotation.z = 0.9 + float(b) * 0.35
		branch.rotation.y = float(b) * 2.1
		branch.material_override = _mat(Color(0.11, 0.08, 0.06))
		tree.add_child(branch)


func _build_wolf() -> void:
	var wolf := Node3D.new()
	wolf.name = "Wolf"
	wolf.position = Vector3(0.0, 0.0, -1.5)
	add_child(wolf)
	# v0.9.1: CraftPix wolf (royalty-free, no attribution required) replaces
	# the primitive stack. FBX faces -X; turned toward the moon (-Z). The howl
	# head-tilt becomes a whole-body rear-back tilt on a pivot at body height.
	var wmodel := ModelLib.spawn("res://assets/models/hw_werewolf_howl/wolf.fbx", wolf, Vector3.ZERO)
	if wmodel != null:
		var pivot := Node3D.new()
		pivot.name = "HowlPivot"
		pivot.position = Vector3(0.0, 0.55, 0.0)
		wolf.add_child(pivot)
		wolf.remove_child(wmodel)
		pivot.add_child(wmodel)
		wmodel.position = Vector3(0.0, -0.55, 0.0)
		wmodel.rotation.y = -PI * 0.5
		wmodel.scale = Vector3.ONE * 0.8
		wolf_tilt = pivot
	else:
		_build_primitive_wolf(wolf)
	_build_charge_ring()


## v0.9.1 fallback: the original procedural wolf when the staged FBX is missing.
func _build_primitive_wolf(wolf: Node3D) -> void:
	var fur := _mat(Color(0.22, 0.22, 0.28))
	# Body.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.7
	body.mesh = cap
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	body.position = Vector3(0.0, 0.45, 0.1)
	body.material_override = fur
	wolf.add_child(body)
	# Head + snout.
	wolf_head = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.20
	hm.height = 0.40
	wolf_head.mesh = hm
	wolf_head.position = Vector3(0.0, 0.78, -0.28)
	wolf_head.material_override = fur
	wolf.add_child(wolf_head)
	var snout := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 0.12, 0.22)
	snout.mesh = sm
	snout.position = Vector3(0.0, 0.72, -0.48)
	snout.material_override = _mat(Color(0.16, 0.16, 0.20))
	wolf.add_child(snout)
	# Ears.
	for ex in [-0.11, 0.11]:
		var ear := MeshInstance3D.new()
		ear.mesh = _cone(0.07, 0.18)
		ear.position = Vector3(ex, 0.96, -0.24)
		ear.material_override = fur
		wolf.add_child(ear)
	# Glowing yellow eyes.
	var eye_mat := GraphicsPolish.glow(Color(1.0, 0.85, 0.2), 2.2)
	for ex in [-0.08, 0.08]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.035
		em.height = 0.07
		eye.mesh = em
		eye.position = Vector3(ex, 0.82, -0.44)
		eye.material_override = eye_mat
		wolf.add_child(eye)
	# Tail.
	var tail := MeshInstance3D.new()
	tail.mesh = _cone(0.07, 0.5)
	tail.position = Vector3(0.0, 0.55, 0.5)
	tail.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	tail.material_override = fur
	wolf.add_child(tail)


## Charge ring (grows while charging) — shared by the model and fallback wolf.
func _build_charge_ring() -> void:
	charge_mat = GraphicsPolish.glow(Color(0.6, 0.8, 1.0), 1.6)
	charge_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	charge_ring.mesh = torus
	charge_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	charge_ring.position = Vector3(0.0, 0.45, -1.5)
	charge_ring.material_override = charge_mat
	charge_ring.visible = false
	add_child(charge_ring)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("WEREWOLF HOWL", 44, Color(0.85, 0.9, 1.0))
	hud_label.position = Vector3(-2.8, 3.0, -3.0)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Hold BOTH pinches (or both mouse buttons) to charge, release to HOWL | R: restart", 26, Color(0.8, 0.82, 0.9))
	help_label.position = Vector3(-2.8, 2.5, -3.0)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.4))
	msg_label.position = Vector3(0.0, 2.2, -3.5)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	var bar_len := int(charge / MAX_CHARGE * 12.0)
	var bar := "[" + "#".repeat(bar_len) + "-".repeat(12 - bar_len) + "]"
	hud_label.text = "WEREWOLF HOWL   %ds   Score: %d   HP: %d\nHowl charge %s" % [int(ceil(maxf(time_left, 0.0))), score, hearts, bar]


func _show_msg(text: String, duration: float = 1.4) -> void:
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
		_game_over(true)
		return
	_update_charge(delta)
	# Spawn villagers in waves.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_villager()
		spawn_timer = randf_range(0.7, 1.4) * maxf(0.5, 1.0 - elapsed * 0.004)
	_step_villagers(delta)
	_step_blasts(delta)
	# Wolf head tilts up while charging; charge ring pulses.
	# v0.9.1: the CraftPix wolf rears back on its howl pivot instead.
	if wolf_tilt != null:
		wolf_tilt.rotation.x = lerpf(wolf_tilt.rotation.x, 0.38 if charging else 0.0, 6.0 * delta)
	elif wolf_head != null:
		wolf_head.rotation.x = lerpf(wolf_head.rotation.x, -0.55 if charging else 0.0, 6.0 * delta)
	if charge_ring != null:
		charge_ring.visible = charging
		if charging:
			var s := 0.8 + charge / MAX_CHARGE * 1.4
			charge_ring.scale = Vector3(s, s, s)
			GraphicsPolish.pulse_glow(charge_mat, 1.2, 1.2, elapsed * 6.0)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _update_charge(delta: float) -> void:
	var left := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)
	var right := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	if left and right:
		if not charging:
			charging = true
			charge = 0.0
			_sfx("charge_up", 180.0, 0.5, 0.35)
		charge = minf(charge + delta, MAX_CHARGE)
	elif charging:
		_release_howl()
		charging = false
		charge = 0.0


func _release_howl() -> void:
	var radius := 1.2 + charge * 1.7
	var center := Vector3(0.0, 0.5, -1.5)
	# Expanding shockwave ring.
	var ring_mat := GraphicsPolish.glow(Color(0.65, 0.85, 1.0), 2.2)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.44
	torus.outer_radius = 0.52
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = center
	ring.material_override = ring_mat
	add_child(ring)
	blasts.append({"node": ring, "mat": ring_mat, "t": 0.0, "max_r": radius})
	_sfx("howl", 160.0, 0.7, 0.55)
	_sfx("howl_hi", 520.0, 0.25, 0.4)
	# Blast back every villager inside the radius.
	var gain := 0
	for i in range(villagers.size() - 1, -1, -1):
		var v: Dictionary = villagers[i]
		var node: Node3D = v["node"]
		if not is_instance_valid(node):
			villagers.remove_at(i)
			continue
		var d := Vector2(node.position.x - center.x, node.position.z - center.z).length()
		if d <= radius:
			GraphicsPolish.spawn_sparks(self, node.global_position + Vector3(0, 0.6, 0), Color(0.7, 0.9, 1.0), 18)
			gain += 10 + int(charge * 15.0)
			node.queue_free()
			villagers.remove_at(i)
	if gain > 0:
		score += gain
		_show_msg("HOWL! +%d" % gain, 1.0)
	else:
		_show_msg("Howl missed...", 0.8)


func _spawn_villager() -> void:
	var root := Node3D.new()
	root.position = _villager_spawn_pos()
	root.rotation.y = atan2(-root.position.x, -(root.position.z + 1.5))
	add_child(root)
	# Body + head.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.14
	cap.height = 0.55
	body.mesh = cap
	body.position.y = 0.42
	body.material_override = _mat(Color(0.35, 0.25, 0.16))
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.22
	head.mesh = hm
	head.position.y = 0.82
	head.material_override = _mat(Color(0.85, 0.68, 0.55))
	root.add_child(head)
	# Pitchfork.
	var fork := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.03, 0.9, 0.03)
	fork.mesh = fm
	fork.position = Vector3(0.22, 0.55, 0.0)
	fork.rotation.z = -0.15
	fork.material_override = _mat(Color(0.25, 0.17, 0.1))
	root.add_child(fork)
	# Torch flame.
	var flame := MeshInstance3D.new()
	var flm := SphereMesh.new()
	flm.radius = 0.06
	flm.height = 0.12
	flame.mesh = flm
	flame.position = Vector3(-0.22, 0.95, 0.0)
	flame.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 2.0)
	root.add_child(flame)
	villagers.append({"node": root, "speed": randf_range(0.35, 0.55) + elapsed * 0.002, "flame": flame})


func _villager_spawn_pos() -> Vector3:
	# Villagers close in from the real walls when the room is known,
	# otherwise from a circle clamped to the room's extents.
	if _room_known and not _room_walls.is_empty():
		var w: Dictionary = _room_walls[randi() % _room_walls.size()]
		var bp: Vector3 = (w["position"] as Vector3) + _wall_inward(w) * 0.45
		return Vector3(bp.x, 0.0, bp.z)
	var r := 4.4
	if _room_known:
		r = minf(4.4, maxf(1.2, minf(_room_bounds.size.x, _room_bounds.size.y) * 0.5 - 0.4))
	var ang := randf() * TAU
	return Vector3(cos(ang) * r, 0.0, -1.5 + sin(ang) * r)


func _step_villagers(delta: float) -> void:
	var center := Vector3(0.0, 0.0, -1.5)
	for i in range(villagers.size() - 1, -1, -1):
		var v: Dictionary = villagers[i]
		var node: Node3D = v["node"]
		if not is_instance_valid(node):
			villagers.remove_at(i)
			continue
		var to := center - node.position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.7:
			# Villager reaches the wolf: lose a heart.
			node.queue_free()
			villagers.remove_at(i)
			hearts -= 1
			_sfx("hurt", 130.0, 0.3, 0.55)
			GraphicsPolish.spawn_sparks(self, center + Vector3(0, 0.8, 0), Color(1.0, 0.2, 0.15), 24)
			if hearts <= 0:
				_game_over(false)
				return
			_show_msg("Ouch! %d hearts left" % hearts, 1.2)
			continue
		node.position += to.normalized() * float(v["speed"]) * delta
		node.position.y = absf(sin(elapsed * 6.0 + float(i))) * 0.03
		var flame: MeshInstance3D = v["flame"]
		if is_instance_valid(flame):
			flame.scale = Vector3.ONE * (1.0 + 0.25 * sin(elapsed * 11.0 + float(i) * 2.0))


func _step_blasts(delta: float) -> void:
	for i in range(blasts.size() - 1, -1, -1):
		var b: Dictionary = blasts[i]
		var node: MeshInstance3D = b["node"]
		if not is_instance_valid(node):
			blasts.remove_at(i)
			continue
		var t := float(b["t"]) + delta / 0.6
		b["t"] = t
		var r := lerpf(0.4, float(b["max_r"]), minf(t, 1.0))
		node.scale = Vector3(r, r, r)
		if t >= 1.0:
			node.queue_free()
			blasts.remove_at(i)


func _poll_restart_pinch(delta: float) -> void:
	var pinch_any := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT) or ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)
	if pinch_any:
		_pinch_hold += delta
		if _pinch_hold >= 1.0:
			_pinch_hold = 0.0
			_reset_game()
	else:
		_pinch_hold = 0.0


func _game_over(won: bool) -> void:
	state = ST_OVER
	time_left = 0.0
	charging = false
	charge = 0.0
	for v_v in villagers:
		var v: Dictionary = v_v
		var node: Node3D = v["node"]
		if is_instance_valid(node):
			node.queue_free()
	villagers.clear()
	ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	if won:
		score += hearts * 50
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, -1.5), 80)
		_sfx("win", 880.0, 0.4, 0.5)
		_show_msg("DAWN BREAKS!\nScore: %d\nHold pinch 1s or press R" % score, 600.0)
	else:
		_sfx("lose", 110.0, 0.6, 0.55)
		_show_msg("OVERRUN!\nScore: %d\nHold pinch 1s or press R" % score, 600.0)
	_update_hud()


func _reset_game() -> void:
	for v_v in villagers:
		var v: Dictionary = v_v
		var node: Node3D = v["node"]
		if is_instance_valid(node):
			node.queue_free()
	villagers.clear()
	for b_v in blasts:
		var b: Dictionary = b_v
		var node: MeshInstance3D = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	blasts.clear()
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	hearts = 3
	elapsed = 0.0
	charge = 0.0
	charging = false
	spawn_timer = 1.0
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
