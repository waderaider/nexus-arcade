## HwHatToss - "Hat Toss" (NEXUS ARCADE Halloween set).
## Witch hats sit on stands at varying distances. Pinch (or click-hold) to
## grab a glowing ring, release to toss it at the hats. Landing a ringer
## scores by distance: 10 / 20 / 30. 60-second round; R or a 1-second
## pinch-hold restarts.
extends Node3D

const ROUND_TIME := 60.0
const RING_R := 0.17
const THROW_DUR := 0.55
const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var throws := 0
var ringers := 0
var holding := false
var ready_ring: MeshInstance3D = null
var ring_cooldown := 0.0
var flying: Array = [] # dicts: node, from, to, t, trail
var landed: Array = [] # dicts: node, fade
var stands: Array = [] # dicts: x, z, points, top
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var elapsed := 0.0
var toss_player: AudioStreamPlayer = null
var ringer_player: AudioStreamPlayer = null
var thud_player: AudioStreamPlayer = null

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
# v0.7.0: couch imp that hides behind the player's couch and lunges at
# the stands on every ringer.
var _imp: Node3D = null
var _imp_home := Vector3.ZERO
var _imp_lunge_t := -1.0


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_room()
	_build_stands()
	_spawn_ready_ring()
	_build_hud()
	toss_player = _make_player(_make_tone(440.0, 0.15, 0.45))
	ringer_player = _make_player(_make_tone(990.0, 0.35, 0.55))
	thud_player = _make_player(_make_tone(150.0, 0.18, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_hat_toss_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -2.0), 2.5)
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
	# Fit the hat stands inside the real room: scale their layout so the
	# farthest stand lands within the room's depth and width.
	var c := _room_bounds.get_center()
	var zscale := minf(1.0, maxf(0.4, (_room_bounds.size.y - 1.0) / 3.3))
	var xscale := minf(1.0, maxf(0.4, (_room_bounds.size.x - 1.0) / 1.1))
	var base := [Vector2(-0.55, -1.7), Vector2(0.0, -2.5), Vector2(0.55, -3.3)]
	for i in range(stands.size()):
		var s: Dictionary = stands[i]
		var b: Vector2 = base[i]
		var nx: float = c.x + b.x * xscale
		var nz: float = c.y + b.y * zscale
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.position = Vector3(nx, 0.0, nz)
		s["x"] = nx
		s["z"] = nz
		s["top"] = Vector3(nx, 0.55, nz)
	# v0.7.0 furniture morph: the couch becomes a haunted perch. A
	# mischievous imp hides behind it and lunges at the stands every
	# time you land a ringer (see _resolve_landing / _update_imp).
	var couch_anchors := RoomKit.get_anchors("COUCH")
	if not couch_anchors.is_empty():
		var canchor: Dictionary = couch_anchors[0]
		RoomKit.morph(canchor, "haunted")
		var cp: Vector3 = canchor["position"]
		var cs: Vector3 = canchor["extents"]
		if _imp == null:
			_imp = _make_imp()
		# Hide on the player side of the couch, behind its bulk.
		_imp_home = Vector3(cp.x, 0.0, cp.z + cs.z * 0.5 + 0.25)
		_imp.position = _imp_home
		_imp.visible = true


func _make_imp() -> Node3D:
	# A mischievous couch imp: glowing eyes on a shadowy body, waiting
	# behind the player's couch to lunge at the stands on a ringer.
	var root := Node3D.new()
	root.name = "CouchImp"
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.16
	bm.height = 0.32
	body.mesh = bm
	body.position = Vector3(0.0, 0.30, 0.0)
	body.material_override = GraphicsPolish.pbr(Color(0.12, 0.05, 0.18), 0.0, 0.6)
	root.add_child(body)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.035
		em.height = 0.07
		eye.mesh = em
		eye.position = Vector3(side * 0.07, 0.38, -0.13)
		eye.material_override = GraphicsPolish.glow(Color(1.0, 0.25, 0.1), 2.4)
		root.add_child(eye)
	root.visible = false
	add_child(root)
	return root


func _update_imp(delta: float) -> void:
	if _imp == null or not _imp.visible:
		return
	if _imp_lunge_t < 0.0:
		# Idle: bob behind the couch, peeking over it.
		_imp.position = _imp_home + Vector3(0.0, 0.05 + sin(elapsed * 3.0) * 0.05, 0.0)
		return
	# Lunge at the stands in an arc, then sink back behind the couch.
	_imp_lunge_t += delta
	var k := clampf(_imp_lunge_t / 0.9, 0.0, 1.0)
	var arc := sin(k * PI)
	var target := Vector3(_imp_home.x * 0.4, 0.0, -2.2)
	_imp.position = _imp_home.lerp(target, arc) + Vector3(0.0, arc * 0.5, 0.0)
	if k >= 1.0:
		_imp_lunge_t = -1.0
		_imp.position = _imp_home


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
	camera.position = Vector3(0.0, 1.6, 2.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.45, -2.2), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	elapsed += delta
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_hat_toss_main", global_transform)
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
	_update_grab()
	_update_flying(delta)
	_update_landed(delta)
	_update_imp(delta)
	if ring_cooldown > 0.0:
		ring_cooldown -= delta
		if ring_cooldown <= 0.0 and ready_ring == null:
			_spawn_ready_ring()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


# ------------------------------------------------------------------ build --

func _build_room() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.01, -1.5)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.11, 0.08, 0.13), 0.0, 0.9)
	add_child(floor_inst)
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.7
	ms.height = 1.4
	moon.mesh = ms
	moon.position = Vector3(-4.5, 5.0, -8.0)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.93, 0.80), 1.4)
	add_child(moon)


func _build_stands() -> void:
	var defs := [
		{"x": -0.55, "z": -1.7, "points": 10, "col": Color(0.35, 0.9, 1.0)},
		{"x": 0.0, "z": -2.5, "points": 20, "col": Color(0.65, 0.4, 1.0)},
		{"x": 0.55, "z": -3.3, "points": 30, "col": Color(1.0, 0.45, 0.75)},
	]
	for d_v in defs:
		var d: Dictionary = d_v
		var x := float(d["x"])
		var z := float(d["z"])
		var root := Node3D.new()
		root.position = Vector3(x, 0.0, z)
		add_child(root)
		# Base glow ring showing the point value.
		var halo := MeshInstance3D.new()
		var ht := TorusMesh.new()
		ht.inner_radius = 0.24
		ht.outer_radius = 0.30
		halo.mesh = ht
		halo.rotation_degrees.x = 90.0
		halo.position.y = 0.03
		halo.material_override = GraphicsPolish.glow(d["col"] as Color, 1.2)
		root.add_child(halo)
		var tag := GraphicsPolish.make_label("+%d" % int(d["points"]), 40, d["col"] as Color)
		tag.position = Vector3(0.0, 0.16, 0.0)
		root.add_child(tag)
		# Post.
		var post := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.035
		pc.bottom_radius = 0.045
		pc.height = 0.52
		post.mesh = pc
		post.position.y = 0.26
		post.material_override = GraphicsPolish.pbr(Color(0.35, 0.22, 0.12), 0.1, 0.6)
		root.add_child(post)
		# Witch hat: brim + cone + bent tip.
		var purple := GraphicsPolish.pbr(Color(0.38, 0.16, 0.62), 0.1, 0.55)
		var brim := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.16
		bc.bottom_radius = 0.17
		bc.height = 0.035
		brim.mesh = bc
		brim.position.y = 0.54
		brim.material_override = purple
		root.add_child(brim)
		var cone := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.0
		cc.bottom_radius = 0.125
		cc.height = 0.30
		cone.mesh = cc
		cone.position.y = 0.70
		cone.material_override = purple
		root.add_child(cone)
		var band := MeshInstance3D.new()
		var t2 := TorusMesh.new()
		t2.inner_radius = 0.115
		t2.outer_radius = 0.135
		band.mesh = t2
		band.rotation_degrees.x = 90.0
		band.position.y = 0.60
		band.material_override = GraphicsPolish.glow(Color(1.0, 0.75, 0.15), 1.1)
		root.add_child(band)
		var tip := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.0
		tc.bottom_radius = 0.035
		tc.height = 0.14
		tip.mesh = tc
		tip.position = Vector3(0.045, 0.90, 0.0)
		tip.rotation_degrees.z = -28.0
		tip.material_override = GraphicsPolish.pbr(Color(0.25, 0.10, 0.45), 0.1, 0.55)
		root.add_child(tip)
		stands.append({"x": x, "z": z, "points": int(d["points"]), "top": Vector3(x, 0.55, z), "node": root})


func _make_ring_node() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.15
	ring.mesh = torus
	ring.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.10), 1.6)
	return ring


func _spawn_ready_ring() -> void:
	ready_ring = _make_ring_node()
	ready_ring.position = ARUpgradeKit.pointer_position(self)
	add_child(ready_ring)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("HAT TOSS", 44, Color(1.0, 0.7, 0.3))
	hud_label.position = Vector3(-2.8, 2.5, 0.2)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 76, Color(1.0, 0.9, 0.35))
	msg_label.position = Vector3(0.0, 2.0, -2.4)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "HAT TOSS\nTime: %ds   Score: %d   Ringers: %d\nPinch & release to toss at the hats\nR: restart" % [int(ceil(time_left)), score, ringers]


func _show_msg(text: String, duration: float = 1.6) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ------------------------------------------------------------------ play ---

func _update_grab() -> void:
	if holding and not ARUpgradeKit.pinch_active(self):
		holding = false
		_throw_ring()
		return
	if not holding and ready_ring != null and ARUpgradeKit.pinch_just_pressed(self):
		holding = true
	if holding and ready_ring != null:
		ready_ring.global_position = ARUpgradeKit.pointer_position(self)
		ready_ring.rotation.y += 0.02


func _throw_ring() -> void:
	if ready_ring == null:
		return
	var ray: Array = ARUpgradeKit.pointer_ray(self)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var target := o + d * 2.5
	if d.y < -0.03:
		var tt := (0.55 - o.y) / d.y
		target = o + d * tt
	target.y = 0.55
	if _room_known:
		target.x = clampf(target.x, _room_bounds.position.x + 0.2, _room_bounds.end.x - 0.2)
		target.z = clampf(target.z, _room_bounds.position.y + 0.2, _room_bounds.end.y - 0.2)
	else:
		target = ARUpgradeKit.clamp_to_room(target, 0.2)
		if target.z > -0.9:
			target.z = -0.9
	var node := ready_ring
	ready_ring = null
	node.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.15), 0.04))
	flying.append({"node": node, "from": node.global_position, "to": target, "t": 0.0})
	throws += 1
	toss_player.play()
	ring_cooldown = 0.9


func _update_flying(delta: float) -> void:
	for i in range(flying.size() - 1, -1, -1):
		var f: Dictionary = flying[i]
		var node: MeshInstance3D = f["node"]
		if not is_instance_valid(node):
			flying.remove_at(i)
			continue
		var t := float(f["t"]) + delta / THROW_DUR
		f["t"] = t
		var k := minf(1.0, t)
		var pos: Vector3 = (f["from"] as Vector3).lerp(f["to"] as Vector3, k)
		pos.y += sin(k * PI) * 0.45
		node.global_position = pos
		node.rotation.x += 9.0 * delta
		if t >= 1.0:
			_resolve_landing(node)
			flying.remove_at(i)


func _resolve_landing(node: MeshInstance3D) -> void:
	var pos := node.global_position
	var ringer := false
	var pts := 0
	for s_v in stands:
		var s: Dictionary = s_v
		var d := Vector2(pos.x - float(s["x"]), pos.z - float(s["z"])).length()
		if d < RING_R:
			ringer = true
			pts = int(s["points"])
			var top: Vector3 = s["top"]
			node.global_position = top + Vector3(0.0, 0.06, 0.0)
			node.rotation = Vector3(PI * 0.5 + 0.12, randf() * TAU, 0.0)
			break
	if ringer:
		score += pts
		ringers += 1
		ringer_player.play()
		# The couch imp lunges at the stands to celebrate (or taunt).
		_imp_lunge_t = 0.0
		GraphicsPolish.spawn_sparks(self, to_local(node.global_position), Color(1.0, 0.85, 0.25), 24)
		_show_msg("RINGER! +%d" % pts, 1.6)
	else:
		thud_player.play()
		node.global_position = Vector3(pos.x, 0.04, pos.z)
		node.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	landed.append({"node": node, "fade": 1.1})


func _update_landed(delta: float) -> void:
	for i in range(landed.size() - 1, -1, -1):
		var l: Dictionary = landed[i]
		var node: MeshInstance3D = l["node"]
		if not is_instance_valid(node):
			landed.remove_at(i)
			continue
		var fade := float(l["fade"]) - delta
		l["fade"] = fade
		if fade <= 0.0:
			node.queue_free()
			landed.remove_at(i)


# ------------------------------------------------------------------ flow ---

func _finish() -> void:
	state = ST_OVER
	holding = false
	_show_msg("TIME'S UP!\nScore: %d   Ringers: %d/%d\nHold pinch 1s or press R" % [score, ringers, throws], 600.0)
	if ringers >= 3:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -2.2), 70)
	ARUpgradeKit.save_anchor("hw_hat_toss_main", global_transform)


func _reset_game() -> void:
	if is_instance_valid(ready_ring):
		ready_ring.queue_free()
	ready_ring = null
	for f_v in flying:
		var f: Dictionary = f_v
		var fn: MeshInstance3D = f["node"]
		if is_instance_valid(fn):
			fn.queue_free()
	flying.clear()
	for l_v in landed:
		var l: Dictionary = l_v
		var ln: MeshInstance3D = l["node"]
		if is_instance_valid(ln):
			ln.queue_free()
	landed.clear()
	time_left = ROUND_TIME
	score = 0
	throws = 0
	ringers = 0
	holding = false
	hold_restart = 0.0
	state = ST_PLAY
	_show_msg("")
	_spawn_ready_ring()
	ARUpgradeKit.save_anchor("hw_hat_toss_main", global_transform)


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
