## HwMonsterFeed - "Monster Feed" (NEXUS ARCADE Halloween set).
## A hungry monster shows which treat it wants (floating icon). Pinch-grab
## the matching food from the tray and drop it in its mouth: +10. Wrong
## food makes it grumble: -5. 90-second round; R or a 1-second pinch-hold
## restarts.
extends Node3D

const ROUND_TIME := 90.0
const WANT_SECONDS := 15.0
const GRAB_RADIUS := 0.40
const FEED_RADIUS := 0.55
const ST_PLAY := 0
const ST_OVER := 1
const FOOD_NAMES: Array = ["APPLE", "CANDY", "COOKIE", "DONUT"]

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var fed := 0
var grumbles := 0
var monster: Node3D = null
var mouth: MeshInstance3D = null
var bounce_t := 0.0
var shake_t := 0.0
var chew_t := 0.0
var foods: Array = [] # dicts: name, node, base, held, returning, icon_col
var held_food: Dictionary = {}
var want_idx := 0
var want_timer := WANT_SECONDS
var want_label: Label3D = null
var want_icon: MeshInstance3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var elapsed := 0.0
var chomp_player: AudioStreamPlayer = null
var grumble_player: AudioStreamPlayer = null
var pop_player: AudioStreamPlayer = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_room()
	_build_monster()
	_build_tray()
	_build_hud()
	_new_want()
	chomp_player = _make_player(_make_tone(240.0, 0.18, 0.6))
	grumble_player = _make_player(_make_tone(95.0, 0.45, 0.65))
	pop_player = _make_player(_make_tone(760.0, 0.10, 0.4))
	ARUpgradeKit.apply_anchor(self, "hw_monster_feed_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -1.2), 2.2)


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
	camera.position = Vector3(0.0, 1.5, 0.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, -1.5), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	elapsed += delta
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_monster_feed_main", global_transform)
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
	want_timer -= delta
	if want_timer <= 0.0:
		_new_want()
		_show_msg("It wants something else...", 1.2)
	_update_grab()
	_update_foods(delta)
	_update_monster(delta)
	if want_icon != null:
		want_icon.position.y = 2.0 + sin(elapsed * 2.5) * 0.06
		want_icon.rotation.y += 1.5 * delta
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


# ------------------------------------------------------------------ build --

func _build_room() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.01, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.12, 0.08, 0.14), 0.0, 0.9)
	add_child(floor_inst)
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.7
	ms.height = 1.4
	moon.mesh = ms
	moon.position = Vector3(4.0, 4.5, -7.0)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.93, 0.80), 1.4)
	add_child(moon)


func _build_monster() -> void:
	monster = Node3D.new()
	monster.name = "Monster"
	monster.position = Vector3(0.0, 0.0, -1.7)
	add_child(monster)
	var fur := GraphicsPolish.pbr(Color(0.45, 0.25, 0.75), 0.05, 0.7)
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	body.mesh = s
	body.position.y = 1.0
	body.material_override = fur
	monster.add_child(body)
	var belly := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.32
	bs.height = 0.60
	belly.mesh = bs
	belly.position = Vector3(0.0, 0.92, 0.28)
	belly.material_override = GraphicsPolish.pbr(Color(0.85, 0.75, 0.95), 0.0, 0.8)
	monster.add_child(belly)
	# Horns.
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.08
		cone.height = 0.25
		horn.mesh = cone
		horn.position = Vector3(side * 0.30, 1.48, 0.0)
		horn.rotation_degrees.z = side * -25.0
		horn.material_override = GraphicsPolish.pbr_preset(Color(0.88, 0.86, 0.80), "matte")
		monster.add_child(horn)
	# Googly eyes.
	for side in [-1.0, 1.0]:
		var white := MeshInstance3D.new()
		var ws := SphereMesh.new()
		ws.radius = 0.12
		ws.height = 0.24
		white.mesh = ws
		white.position = Vector3(side * 0.18, 1.28, 0.42)
		white.material_override = GraphicsPolish.pbr(Color(0.95, 0.95, 0.97), 0.0, 0.4)
		monster.add_child(white)
		var pupil := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.05
		ps.height = 0.10
		pupil.mesh = ps
		pupil.position = Vector3(side * 0.18, 1.28, 0.53)
		pupil.material_override = GraphicsPolish.pbr(Color(0.05, 0.05, 0.08), 0.0, 0.4)
		monster.add_child(pupil)
	# Mouth (opens when fed).
	mouth = MeshInstance3D.new()
	var mshape := SphereMesh.new()
	mshape.radius = 0.14
	mshape.height = 0.20
	mouth.mesh = mshape
	mouth.scale = Vector3(1.3, 0.45, 0.5)
	mouth.position = Vector3(0.0, 0.88, 0.44)
	mouth.material_override = GraphicsPolish.pbr(Color(0.35, 0.05, 0.10), 0.0, 0.9)
	monster.add_child(mouth)
	# Stubby arms and feet.
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.08
		cap.height = 0.30
		arm.mesh = cap
		arm.position = Vector3(side * 0.55, 0.95, 0.10)
		arm.rotation_degrees.z = side * -35.0
		arm.material_override = fur
		monster.add_child(arm)
		var foot := MeshInstance3D.new()
		var fs := SphereMesh.new()
		fs.radius = 0.14
		fs.height = 0.20
		foot.mesh = fs
		foot.position = Vector3(side * 0.25, 0.10, 0.15)
		foot.material_override = fur
		monster.add_child(foot)
	GraphicsPolish.make_point_light(monster, Vector3(0, 2.2, 1.0), Color(0.7, 0.5, 1.0), 0.8, 4.0)


func _build_tray() -> void:
	var tray := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.7, 0.08, 0.55)
	tray.mesh = tb
	tray.position = Vector3(0.0, 0.72, -0.55)
	tray.material_override = GraphicsPolish.pbr(Color(0.40, 0.24, 0.13), 0.1, 0.6)
	add_child(tray)
	var leg_mat := GraphicsPolish.pbr(Color(0.25, 0.15, 0.08), 0.0, 0.8)
	for sx in [-0.75, 0.75]:
		for sz in [-0.20, 0.20]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.07, 0.72, 0.07)
			leg.mesh = lb
			leg.position = Vector3(sx, 0.36, -0.55 + sz)
			leg.material_override = leg_mat
			add_child(leg)
	_make_food("APPLE", Vector3(-0.60, 0.88, -0.55), Color(0.90, 0.15, 0.15))
	_make_food("CANDY", Vector3(-0.20, 0.88, -0.55), Color(1.0, 0.55, 0.10))
	_make_food("COOKIE", Vector3(0.20, 0.88, -0.55), Color(0.55, 0.32, 0.15))
	_make_food("DONUT", Vector3(0.60, 0.88, -0.55), Color(1.0, 0.45, 0.65))


func _make_food(food_name: String, base: Vector3, icon_col: Color) -> void:
	var node := MeshInstance3D.new()
	node.position = base
	add_child(node)
	match food_name:
		"APPLE":
			var b := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.09
			s.height = 0.18
			b.mesh = s
			b.material_override = GraphicsPolish.pbr(Color(0.88, 0.14, 0.14), 0.15, 0.35)
			node.add_child(b)
			var stem := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.012
			cyl.bottom_radius = 0.012
			cyl.height = 0.06
			stem.mesh = cyl
			stem.position.y = 0.11
			stem.material_override = GraphicsPolish.pbr(Color(0.25, 0.40, 0.12), 0.0, 0.8)
			node.add_child(stem)
		"CANDY":
			var c := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.07
			cone.height = 0.17
			c.mesh = cone
			c.material_override = GraphicsPolish.pbr(Color(1.0, 0.55, 0.08), 0.1, 0.4)
			node.add_child(c)
			var tipm := MeshInstance3D.new()
			var tc := CylinderMesh.new()
			tc.top_radius = 0.0
			tc.bottom_radius = 0.028
			tc.height = 0.06
			tipm.mesh = tc
			tipm.position.y = 0.10
			tipm.material_override = GraphicsPolish.pbr(Color(0.98, 0.94, 0.80), 0.1, 0.4)
			node.add_child(tipm)
		"COOKIE":
			var k := MeshInstance3D.new()
			var cyl2 := CylinderMesh.new()
			cyl2.top_radius = 0.09
			cyl2.bottom_radius = 0.09
			cyl2.height = 0.045
			k.mesh = cyl2
			k.material_override = GraphicsPolish.pbr(Color(0.60, 0.36, 0.16), 0.0, 0.7)
			node.add_child(k)
			for ci in range(4):
				var chip := MeshInstance3D.new()
				var cs := SphereMesh.new()
				cs.radius = 0.016
				cs.height = 0.032
				chip.mesh = cs
				var ca := float(ci) * PI * 0.5 + 0.4
				chip.position = Vector3(cos(ca) * 0.05, 0.028, sin(ca) * 0.05)
				chip.material_override = GraphicsPolish.pbr(Color(0.15, 0.08, 0.05), 0.0, 0.7)
				node.add_child(chip)
		"DONUT":
			var dn := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.045
			torus.outer_radius = 0.095
			dn.mesh = torus
			dn.rotation_degrees.x = 90.0
			dn.material_override = GraphicsPolish.pbr(Color(1.0, 0.50, 0.68), 0.1, 0.4)
			node.add_child(dn)
	foods.append({"name": food_name, "node": node, "base": base, "held": false, "returning": false, "icon_col": icon_col})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("MONSTER FEED", 44, Color(0.85, 0.6, 1.0))
	hud_label.position = Vector3(-2.9, 2.6, 0.0)
	add_child(hud_label)
	want_label = GraphicsPolish.make_label("WANTS: ?", 56, Color(1.0, 0.9, 0.4))
	want_label.position = Vector3(0.0, 2.35, -1.7)
	add_child(want_label)
	msg_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 1.6, -0.9)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "MONSTER FEED\nTime: %ds   Score: %d   Fed: %d\nPinch-grab food, drop it in the mouth\nR: restart" % [int(ceil(time_left)), score, fed]


func _show_msg(text: String, duration: float = 1.4) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ------------------------------------------------------------------ play ---

func _new_want() -> void:
	var ni := randi_range(0, FOOD_NAMES.size() - 1)
	while ni == want_idx:
		ni = randi_range(0, FOOD_NAMES.size() - 1)
	want_idx = ni
	want_timer = WANT_SECONDS
	want_label.text = "WANTS: %s" % String(FOOD_NAMES[want_idx])
	if is_instance_valid(want_icon):
		want_icon.queue_free()
	want_icon = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.10
	s.height = 0.20
	want_icon.mesh = s
	want_icon.position = Vector3(0.0, 2.0, -1.7)
	want_icon.material_override = GraphicsPolish.glow(foods[want_idx]["icon_col"] as Color, 1.5)
	add_child(want_icon)
	if pop_player != null:
		pop_player.play()


func _mouth_world() -> Vector3:
	return monster.global_position + Vector3(0.0, 0.88, 0.44)


func _update_grab() -> void:
	var pinching := ARUpgradeKit.pinch_active(self)
	if held_food.is_empty() and ARUpgradeKit.pinch_just_pressed(self):
		var pp := ARUpgradeKit.pointer_position(self)
		var best: Dictionary = {}
		var best_d := GRAB_RADIUS
		for f_v in foods:
			var f: Dictionary = f_v
			if bool(f["held"]) or bool(f["returning"]):
				continue
			var fn: MeshInstance3D = f["node"]
			var d := pp.distance_to(fn.global_position)
			if d < best_d:
				best_d = d
				best = f
		if not best.is_empty():
			best["held"] = true
			held_food = best
			pop_player.play()
	elif not held_food.is_empty():
		var fn2: MeshInstance3D = held_food["node"]
		fn2.global_position = ARUpgradeKit.pointer_position(self)
		if not pinching:
			_try_feed()


func _try_feed() -> void:
	var f := held_food
	held_food = {}
	var fn: MeshInstance3D = f["node"]
	if fn.global_position.distance_to(_mouth_world()) < FEED_RADIUS:
		if String(f["name"]) == String(FOOD_NAMES[want_idx]):
			score += 10
			fed += 1
			chomp_player.play()
			chew_t = 0.6
			bounce_t = 0.45
			GraphicsPolish.spawn_sparks(self, to_local(_mouth_world()), Color(1.0, 0.6, 0.9), 22)
			_show_msg("YUM! +10", 1.2)
			f["returning"] = true
			_new_want()
		else:
			score = maxi(0, score - 5)
			grumbles += 1
			grumble_player.play()
			shake_t = 0.5
			_show_msg("GRRR... wrong food! -5", 1.4)
			f["returning"] = true
	else:
		f["returning"] = true
	f["held"] = false


func _update_foods(delta: float) -> void:
	for f_v in foods:
		var f: Dictionary = f_v
		if not bool(f["returning"]):
			continue
		var fn: MeshInstance3D = f["node"]
		var target: Vector3 = to_global(f["base"])
		fn.global_position = fn.global_position.lerp(target, minf(1.0, 6.0 * delta))
		if fn.global_position.distance_to(target) < 0.03:
			fn.global_position = target
			f["returning"] = false


func _update_monster(delta: float) -> void:
	monster.position.y = sin(elapsed * 2.0) * 0.04
	if bounce_t > 0.0:
		bounce_t -= delta
		var k := 1.0 + 0.18 * sin((0.45 - bounce_t) / 0.45 * PI)
		monster.scale = Vector3(k, 2.0 - k, k)
	elif shake_t > 0.0:
		shake_t -= delta
		monster.position.x = sin(elapsed * 40.0) * 0.05 * (shake_t / 0.5)
	else:
		monster.scale = monster.scale.lerp(Vector3.ONE, minf(1.0, 8.0 * delta))
		monster.position.x = lerpf(monster.position.x, 0.0, minf(1.0, 8.0 * delta))
	if chew_t > 0.0:
		chew_t -= delta
		mouth.scale.y = 0.45 + absf(sin(elapsed * 18.0)) * 0.5
	else:
		mouth.scale.y = lerpf(mouth.scale.y, 0.45, minf(1.0, 8.0 * delta))


# ------------------------------------------------------------------ flow ---

func _finish() -> void:
	state = ST_OVER
	_show_msg("TIME'S UP!\nScore: %d   Fed: %d   Grumbles: %d\nHold pinch 1s or press R" % [score, fed, grumbles], 600.0)
	if fed >= 6:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -1.5), 70)
	ARUpgradeKit.save_anchor("hw_monster_feed_main", global_transform)


func _reset_game() -> void:
	for f_v in foods:
		var f: Dictionary = f_v
		var fn: MeshInstance3D = f["node"]
		if is_instance_valid(fn):
			fn.position = f["base"]
		f["held"] = false
		f["returning"] = false
	held_food = {}
	time_left = ROUND_TIME
	score = 0
	fed = 0
	grumbles = 0
	hold_restart = 0.0
	state = ST_PLAY
	_new_want()
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_monster_feed_main", global_transform)


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
