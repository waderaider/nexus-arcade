## AR Fishing: cast a bobber into a glowing pond anchored on your floor.
## Fish shadows glide beneath the surface. Pinch-hold (or mouse-hold) and
## flick to cast; when the bobber dips, pinch-YANK fast to hook; then reel
## with the tension meter - hold to reel in, ease off to avoid snapping the
## line. Five species across four rarity tiers fill the collection log;
## score is total catch weight. R restarts.
extends Node3D

const POND_RADIUS := 1.25
const POND_Y := 0.05
const POND_CENTER := Vector3(0.0, 0.0, -0.9)
const ROD_TIP := Vector3(0.35, 1.35, 0.9)
const BITE_WINDOW := 1.4
const REEL_ZONE_LO := 0.25
const REEL_ZONE_HI := 0.75
const POINTER_Y := 1.0
const CAST_MIN_SPEED := 1.0

var camera: Camera3D = null
var pond_mat: StandardMaterial3D = null
var bobber_mat: StandardMaterial3D = null
var bobber: MeshInstance3D = null
var line_holder: Node3D = null
var line_mesh: MeshInstance3D = null
var fish_shadows: Array = []
var species: Array = []
var state := "idle"
var state_t := 0.0
var bite_at := 0.0
var aiming := false
var cast_samples: Array = []
var was_pinch := false
var bobber_vel := Vector3.ZERO
var tension := 0.5
var reel_progress := 0.0
var fight_t := 0.0
var fight_push := 0.0
var total_weight := 0.0
var catches := 0
var collection := {}
var hud_label: Label3D = null
var msg_label: Label3D = null
var log_label: Label3D = null
var help_label: Label3D = null
var tension_root: Node3D = null
var tension_fill: MeshInstance3D = null
var sim_t := 0.0
var ripple_t := 0.0
var anchor_t := 0.0
# v0.7.0 RoomKit: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _pond_center: Vector3 = POND_CENTER


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "ar-fishing_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_define_species()
	_build_pond()
	_build_bobber()
	_build_tension_bar()
	_build_hud()
	_reset_cast()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, -0.9), 2.2, 40)
	_apply_room_layout() # v0.7.0: pond on open floor inside the room


func _process(delta: float) -> void:
	sim_t += delta
	anchor_t += delta
	if anchor_t >= 30.0:
		anchor_t = 0.0
		ARUpgradeKit.save_anchor("ar-fishing_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_restart()
	GraphicsPolish.pulse_glow(pond_mat, 0.9, 0.35, sim_t, 1.6)
	GraphicsPolish.pulse_glow(bobber_mat, 1.4, 0.5, sim_t, 3.0)
	_swim_shadows()
	_update_line()

	var pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var just := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)

	match state:
		"idle":
			_bobber_to_rod()
			if just:
				aiming = true
				cast_samples.clear()
			if aiming and pinch:
				_record_sample()
			if aiming and was_pinch and not pinch:
				aiming = false
				_try_cast()
		"cast":
			_fly_bobber(delta)
		"waiting":
			_bob_wait(delta)
			if sim_t >= bite_at:
				state = "bite"
				state_t = 0.0
				ripple_t = 0.0
				GraphicsPolish.spawn_sparks(self, bobber.position, Color(0.4, 0.9, 1.0), 10)
		"bite":
			state_t += delta
			ripple_t += delta
			_bobber_dip()
			if ripple_t >= 0.35:
				ripple_t = 0.0
				GraphicsPolish.spawn_sparks(self, bobber.position + Vector3(0, 0.02, 0), Color(0.4, 0.9, 1.0), 8)
			if just:
				_hook_fish()
			elif state_t >= BITE_WINDOW:
				state = "idle"
				msg_label.text = "It got away..."
				state_t = 0.0
		"reel":
			_reel(delta, pinch)
		"caught":
			state_t += delta
			if state_t >= 2.6:
				state = "idle"
				state_t = 0.0
	was_pinch = pinch
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if state == "caught":
				state = "idle"
				state_t = 0.0


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.6, 2.9)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.2, -0.8), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _define_species() -> void:
	species = [
		{"name": "Bluegill", "tickets": 45, "min": 0.4, "max": 1.2, "color": Color(0.35, 0.65, 1.0), "tier": "Common"},
		{"name": "Sunny Perch", "tickets": 30, "min": 0.6, "max": 1.8, "color": Color(0.9, 0.85, 0.3), "tier": "Common"},
		{"name": "Largemouth Bass", "tickets": 15, "min": 1.0, "max": 3.0, "color": Color(0.35, 0.85, 0.4), "tier": "Uncommon"},
		{"name": "Moon Koi", "tickets": 8, "min": 2.0, "max": 5.0, "color": Color(1.0, 0.75, 0.85), "tier": "Rare"},
		{"name": "Golden Trout", "tickets": 2, "min": 3.0, "max": 8.0, "color": Color(1.0, 0.75, 0.2), "tier": "LEGENDARY"},
	]


func _build_pond() -> void:
	var pond := Node3D.new()
	pond.name = "Pond"
	pond.position = _pond_center
	add_child(pond)
	# Dark basin so fish shadows read through the water.
	var basin := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = POND_RADIUS
	bcyl.bottom_radius = POND_RADIUS
	bcyl.height = 0.05
	basin.mesh = bcyl
	basin.material_override = GraphicsPolish.pbr_preset(Color(0.02, 0.05, 0.10), "matte")
	basin.position = Vector3(0, -0.02, 0)
	pond.add_child(basin)
	# Water surface: translucent blue glass.
	var water := MeshInstance3D.new()
	var wcyl := CylinderMesh.new()
	wcyl.top_radius = POND_RADIUS
	wcyl.bottom_radius = POND_RADIUS
	wcyl.height = 0.02
	water.mesh = wcyl
	pond_mat = GraphicsPolish.pbr_preset(Color(0.15, 0.55, 0.85), "glass")
	pond_mat.albedo_color.a = 0.55
	water.material_override = pond_mat
	water.position = Vector3(0, POND_Y - 0.01, 0)
	pond.add_child(water)
	# Glowing rim.
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = POND_RADIUS - 0.03
	torus.outer_radius = POND_RADIUS + 0.05
	rim.mesh = torus
	rim.material_override = GraphicsPolish.glow(Color(0.25, 0.9, 1.0), 1.8)
	rim.position = Vector3(0, POND_Y, 0)
	pond.add_child(rim)
	GraphicsPolish.make_point_light(pond, Vector3(0, 0.8, 0), Color(0.3, 0.8, 1.0), 0.8, 4.0)
	# Fish shadows gliding under the surface.
	for i in 5:
		var sh := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = randf_range(0.10, 0.20)
		s.height = 0.06
		sh.mesh = s
		sh.material_override = GraphicsPolish.pbr(Color(0.01, 0.03, 0.06), 0.0, 0.9)
		pond.add_child(sh)
		fish_shadows.append({
			"node": sh,
			"r": randf_range(0.3, POND_RADIUS - 0.25),
			"speed": randf_range(0.25, 0.7) * (1.0 if i % 2 == 0 else -1.0),
			"phase": randf() * TAU,
		})


func _build_bobber() -> void:
	bobber = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	bobber.mesh = s
	bobber_mat = GraphicsPolish.glow(Color(1.0, 0.25, 0.2), 1.6)
	bobber.material_override = bobber_mat
	add_child(bobber)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 0.16
	stem.mesh = cyl
	stem.material_override = GraphicsPolish.glow(Color(1.0, 1.0, 1.0), 1.2)
	stem.position = Vector3(0, 0.10, 0)
	bobber.add_child(stem)
	# Fishing line from rod tip to bobber.
	line_holder = Node3D.new()
	add_child(line_holder)
	line_mesh = MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.008
	lc.bottom_radius = 0.008
	lc.height = 1.0
	line_mesh.mesh = lc
	line_mesh.rotation_degrees = Vector3(90, 0, 0)
	line_mesh.material_override = GraphicsPolish.pbr(Color(0.8, 0.8, 0.8), 0.0, 0.6)
	line_holder.add_child(line_mesh)


func _build_tension_bar() -> void:
	tension_root = Node3D.new()
	tension_root.position = Vector3(-1.7, 1.9, -0.4)
	add_child(tension_root)
	var bg := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.2, 0.08, 0.02)
	bg.mesh = b
	bg.material_override = GraphicsPolish.pbr(Color(0.1, 0.1, 0.12), 0.0, 0.8)
	tension_root.add_child(bg)
	var zone := MeshInstance3D.new()
	var z := BoxMesh.new()
	z.size = Vector3(REEL_ZONE_HI - REEL_ZONE_LO, 0.085, 0.015)
	zone.mesh = z
	zone.material_override = GraphicsPolish.glow(Color(0.2, 0.9, 0.4, 0.5), 0.8)
	zone.position = Vector3(-0.6 + (REEL_ZONE_LO + REEL_ZONE_HI) * 0.6, 0, 0.005)
	tension_root.add_child(zone)
	tension_fill = MeshInstance3D.new()
	var f := BoxMesh.new()
	f.size = Vector3(1.0, 0.06, 0.02)
	tension_fill.mesh = f
	tension_fill.material_override = GraphicsPolish.glow(Color(0.3, 0.9, 1.0), 1.4)
	tension_fill.position = Vector3(0, 0, 0.01)
	tension_root.add_child(tension_fill)
	var cap := GraphicsPolish.make_label("TENSION", 36, Color(0.8, 0.9, 1.0))
	cap.position = Vector3(0, 0.18, 0)
	tension_root.add_child(cap)
	tension_root.visible = false


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.95, 0.8))
	hud_label.position = Vector3(-2.1, 2.4, 0.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.5, 0.95, 1.0))
	msg_label.position = Vector3(0.0, 1.9, -1.4)
	add_child(msg_label)
	log_label = GraphicsPolish.make_label("", 40, Color(0.85, 0.9, 1.0))
	log_label.position = Vector3(1.9, 2.2, 0.4)
	add_child(log_label)
	help_label = GraphicsPolish.make_label("Hold click / pinch and FLICK to cast - yank fast on the dip! - hold to reel, ease off in the red - R: restart", 30, Color(0.7, 0.75, 0.85))
	help_label.position = Vector3(0.0, 0.45, 1.6)
	add_child(help_label)


func _pointer_pos() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return Vector3(0, POINTER_Y, 0)
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.0001:
		return ro + rd * 2.0
	var t := (POINTER_Y - ro.y) / rd.y
	if t < 0.0:
		return ro + rd * 2.0
	return ro + rd * t


func _record_sample() -> void:
	cast_samples.append({"p": _pointer_pos(), "t": sim_t})
	while cast_samples.size() > 12:
		cast_samples.pop_front()


func _flick_velocity() -> Vector3:
	if cast_samples.size() < 3:
		return Vector3.ZERO
	var first: Dictionary = cast_samples[0]
	var last: Dictionary = cast_samples[cast_samples.size() - 1]
	var dt: float = maxf(float(last["t"]) - float(first["t"]), 0.03)
	var dp: Vector3 = (last["p"] as Vector3) - (first["p"] as Vector3)
	return dp / dt


func _try_cast() -> void:
	var flick := _flick_velocity()
	var speed := Vector3(flick.x, 0, flick.z).length()
	if speed < CAST_MIN_SPEED:
		return
	var dir := Vector3(flick.x, 0, flick.z)
	if dir.length() < 0.2:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var dist := clampf(0.9 + speed * 0.45, 0.8, 3.4)
	var landing := Vector3(ROD_TIP.x, POND_Y, ROD_TIP.z) + dir * dist
	# v0.7.0: keep casts inside the scanned room.
	landing.x = clampf(landing.x, _room_bounds.position.x + 0.2, _room_bounds.end.x - 0.2)
	landing.z = clampf(landing.z, _room_bounds.position.y + 0.2, _room_bounds.end.y - 0.2)
	# Solve a 0.8s projectile arc to the landing point.
	var T := 0.8
	bobber_vel = Vector3(
		(landing.x - ROD_TIP.x) / T,
		(landing.y - ROD_TIP.y + 0.5 * 9.8 * T * T) / T,
		(landing.z - ROD_TIP.z) / T
	)
	bobber.position = ROD_TIP
	state = "cast"


func _fly_bobber(delta: float) -> void:
	bobber_vel.y -= 9.8 * delta
	bobber.position += bobber_vel * delta
	if bobber.position.y <= POND_Y + 0.02 and bobber_vel.y < 0.0:
		var flat := Vector2(bobber.position.x - _pond_center.x, bobber.position.z - _pond_center.z)
		bobber.position.y = POND_Y + 0.02
		if flat.length() <= POND_RADIUS:
			state = "waiting"
			bite_at = sim_t + randf_range(2.5, 7.0)
			GraphicsPolish.spawn_sparks(self, bobber.position, Color(0.4, 0.9, 1.0), 12)
		else:
			state = "idle"
			msg_label.text = "Missed the pond!"
			state_t = 0.0


func _bob_wait(delta: float) -> void:
	bobber.position.y = POND_Y + 0.02 + sin(sim_t * 2.2) * 0.015


func _bobber_dip() -> void:
	bobber.position.y = POND_Y - 0.04 + sin(sim_t * 22.0) * 0.012


func _bobber_to_rod() -> void:
	bobber.position = bobber.position.lerp(ROD_TIP, clampf(8.0 * get_process_delta_time(), 0.0, 1.0))


func _hook_fish() -> void:
	state = "reel"
	tension = 0.5
	reel_progress = 0.0
	fight_t = 0.0
	fight_push = 0.0
	tension_root.visible = true
	GraphicsPolish.spawn_sparks(self, bobber.position, Color(1.0, 0.8, 0.3), 16)
	msg_label.text = "HOOKED! Keep tension in the green!"


func _reel(delta: float, reeling: bool) -> void:
	fight_t -= delta
	if fight_t <= 0.0:
		fight_t = randf_range(0.35, 0.9)
		fight_push = randf_range(-0.45, 0.65)
	var rate := 0.55 if reeling else -0.42
	tension = clampf(tension + (rate + fight_push) * delta, 0.0, 1.05)
	# The fish runs - bobber skitters around the hook point.
	bobber.position.x += randf_range(-1.0, 1.0) * fight_push * delta * 0.6
	bobber.position.z += randf_range(-1.0, 1.0) * fight_push * delta * 0.6
	bobber.position.y = POND_Y + 0.02
	var in_zone := tension >= REEL_ZONE_LO and tension <= REEL_ZONE_HI
	if reeling:
		reel_progress += (0.34 if in_zone else 0.15) * delta
	tension_fill.scale.x = maxf(tension, 0.02)
	tension_fill.position.x = -0.6 + 0.6 * tension
	var fill_mat := tension_fill.material_override as StandardMaterial3D
	if fill_mat != null:
		var c := Color(0.3, 0.9, 1.0) if in_zone else Color(1.0, 0.25, 0.2)
		fill_mat.albedo_color = c
		fill_mat.emission = c
	if tension >= 1.0:
		state = "idle"
		tension_root.visible = false
		msg_label.text = "Line snapped!"
		state_t = 0.0
	elif reel_progress >= 1.0:
		_catch_fish()


func _catch_fish() -> void:
	tension_root.visible = false
	var total := 0
	for s in species:
		total += int(s["tickets"])
	var roll := randf() * float(total)
	var pick: Dictionary = species[0]
	for s in species:
		roll -= float(s["tickets"])
		if roll <= 0.0:
			pick = s
			break
	var w := randf_range(float(pick["min"]), float(pick["max"]))
	total_weight += w
	catches += 1
	var nm: String = pick["name"]
	collection[nm] = int(collection.get(nm, 0)) + 1
	state = "caught"
	state_t = 0.0
	msg_label.text = "Caught %s! %.1f kg (%s)" % [nm, w, pick["tier"]]
	GraphicsPolish.spawn_confetti(self, bobber.position + Vector3(0, 0.4, 0), 40)
	ARUpgradeKit.save_anchor("ar-fishing_main", global_transform)


func _swim_shadows() -> void:
	for f in fish_shadows:
		var d: Dictionary = f
		var a: float = float(d["phase"]) + sim_t * float(d["speed"])
		var n: MeshInstance3D = d["node"]
		var r: float = float(d["r"])
		n.position = Vector3(cos(a) * r, 0.012, sin(a) * r * 0.7)
		n.rotation.y = -a


func _update_line() -> void:
	if bobber == null or line_holder == null:
		return
	var a := ROD_TIP
	var b: Vector3 = bobber.position
	var dist := a.distance_to(b)
	line_holder.visible = dist > 0.15
	if not line_holder.visible:
		return
	line_holder.position = (a + b) * 0.5
	if dist > 0.001:
		line_holder.look_at(b)
	line_mesh.scale = Vector3(1, dist, 1)


func _update_hud() -> void:
	hud_label.text = "Catch: %.1f kg   Fish: %d" % [total_weight, catches]
	match state:
		"idle":
			if aiming:
				msg_label.text = "Flick forward, release!"
			elif state_t <= 0.0 or msg_label.text == "":
				msg_label.text = "Hold click / pinch to cast"
		"cast":
			msg_label.text = ""
		"waiting":
			msg_label.text = "Waiting for a bite..."
		"bite":
			msg_label.text = "YANK! (click / pinch fast)"
		"reel":
			msg_label.text = ""
		"caught":
			pass
	var lines := PackedStringArray()
	lines.append("COLLECTION")
	for s in species:
		var nm: String = s["name"]
		if collection.has(nm):
			lines.append("%s x%d" % [nm, int(collection[nm])])
	if lines.size() == 1:
		lines.append("(empty)")
	log_label.text = "\n".join(lines)


func _reset_cast() -> void:
	state = "idle"
	state_t = 0.0
	aiming = false
	tension_root.visible = false
	if bobber != null:
		bobber.position = ROD_TIP
	msg_label.text = "Hold click / pinch to cast"


func _restart() -> void:
	total_weight = 0.0
	catches = 0
	collection.clear()
	_reset_cast()
	ARUpgradeKit.save_anchor("ar-fishing_main", global_transform)


# ------------------------------------------------- v0.7.0 RoomKit ----
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not is_inside_tree() or not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Center the pond on open floor: room center, nudged out of furniture.
	var c := _room_bounds.get_center()
	var p := Vector2(c.x, c.y)
	for f_v in _room_furniture + _room_tables:
		var f: Dictionary = f_v
		var fc: Vector3 = f["position"]
		var fs: Vector3 = f["size"]
		var hx := fs.x * 0.5 + POND_RADIUS + 0.3
		var hz := fs.z * 0.5 + POND_RADIUS + 0.3
		var dx := p.x - fc.x
		var dz := p.y - fc.z
		if absf(dx) < hx and absf(dz) < hz:
			if hx - absf(dx) < hz - absf(dz):
				p.x = fc.x + (hx if dx >= 0.0 else -hx)
			else:
				p.y = fc.z + (hz if dz >= 0.0 else -hz)
	p.x = clampf(p.x, _room_bounds.position.x + POND_RADIUS + 0.2, _room_bounds.end.x - POND_RADIUS - 0.2)
	p.y = clampf(p.y, _room_bounds.position.y + POND_RADIUS + 0.2, _room_bounds.end.y - POND_RADIUS - 0.2)
	_pond_center = Vector3(p.x, 0.0, p.y)
	var pond := get_node_or_null("Pond")
	if pond != null:
		pond.position = _pond_center
	# v0.7.0 MORPH: plants become overgrown pond reeds / water creatures in the pond biome.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_plants := RoomKit.get_anchors("PLANT")
		if not _morph_plants.is_empty():
			RoomKit.morph(_morph_plants[0], "nature")
