## holo-aquarium.gd -- NEXUS ARCADE: virtual wall-mounted aquarium.
## A glass tank on the wall holds 8 boids-lite fish (cohesion, wander,
## separation). Click inside the tank to drop a food pellet: fish flee
## the tap point, then seek out and eat the pellet. A 120-second
## day/night cycle lerps the directional light and the water color,
## with a sun/moon indicator arcing overhead. R resets.
extends Node3D

const TANK_CENTER := Vector3(0.0, 1.7, -1.9)
const TANK_SIZE := Vector3(3.6, 2.0, 1.1)
const FISH_MIN := Vector3(-1.55, 0.95, -2.30)
const FISH_MAX := Vector3(1.55, 2.45, -1.50)
const DAY_LENGTH := 120.0
const MAX_SPEED := 1.7
const EAT_DIST := 0.22
const FISH_COUNT := 8
const DAY_SKY := Color(0.16, 0.52, 0.82)
const NIGHT_SKY := Color(0.015, 0.05, 0.14)
const DAY_LIGHT := Color(1.0, 0.96, 0.88)
const NIGHT_LIGHT := Color(0.45, 0.60, 1.0)

const FISH_COLORS := [
	Color(1.0, 0.55, 0.15), Color(0.25, 0.55, 1.0),
	Color(1.0, 0.85, 0.25), Color(0.70, 0.35, 1.0),
	Color(1.0, 0.30, 0.30), Color(0.25, 0.90, 0.85),
	Color(1.0, 0.45, 0.75), Color(0.55, 1.0, 0.35),
]


class Fish:
	var root: Node3D = null
	var tail: MeshInstance3D = null
	var vel: Vector3 = Vector3.ZERO
	var wander_dir: Vector3 = Vector3.FORWARD
	var wander_t: float = 0.0
	var flee_t: float = 0.0
	var phase: float = 0.0


class Pellet:
	var node: MeshInstance3D = null
	var life: float = 14.0


class Bubble:
	var node: MeshInstance3D = null
	var speed: float = 0.4


var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}
var _anchor_t := 0.0

var fishes: Array = []
var pellets: Array = []
var bubbles: Array = []
var pellets_eaten := 0

var flee_point := Vector3.ZERO
var flee_active := false

var sun_light: DirectionalLight3D = null
var env: Environment = null
var water_mat: StandardMaterial3D = null
var sun_node: MeshInstance3D = null
var moon_node: MeshInstance3D = null
var cycle_label: Label3D = null

var hud_main: Label3D = null
var hud_help: Label3D = null


func _ready() -> void:
	# Restore the persisted tank placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "holo-aquarium_main")
	_build_environment()
	_build_tank()
	_build_fish()
	_build_bubbles()
	_build_sky_indicator()
	_build_ui()
	# Cool accent light inside the tank + drifting water motes.
	GraphicsPolish.make_point_light(self, TANK_CENTER + Vector3(0.0, 0.0, 0.8), Color(0.45, 0.75, 1.0), 0.9, 5.0)
	GraphicsPolish.spawn_ambient_motes(self, TANK_CENTER, 1.9, 36)


func _mat(color: Color, rough: float = 0.6, emission: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
	return m


func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 1.9, 1.7)
		add_child(cam)
		cam.look_at(Vector3(0.0, 1.55, -1.9), Vector3.UP)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun_light.light_energy = 1.1
	sun_light.shadow_enabled = true
	add_child(sun_light)

	var amb := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.45, 0.60)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)

	# Back wall the tank hangs on.
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(9.0, 5.0, 0.2)
	wall.mesh = wb
	wall.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.12, 0.20), "matte")
	wall.position = Vector3(0.0, 2.0, -2.62)
	add_child(wall)

	# Floor.
	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(9.0, 0.1, 9.0)
	floor_mi.mesh = fb
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.09, 0.10, 0.16), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 1.0)
	add_child(floor_mi)


func _build_tank() -> void:
	var cx: float = TANK_CENTER.x
	var cy: float = TANK_CENTER.y
	var cz: float = TANK_CENTER.z
	var sx: float = TANK_SIZE.x
	var sy: float = TANK_SIZE.y
	var sz: float = TANK_SIZE.z

	# Water background panel (color lerps with day/night).
	var bg := MeshInstance3D.new()
	var bgb := BoxMesh.new()
	bgb.size = Vector3(sx - 0.1, sy - 0.1, 0.06)
	bg.mesh = bgb
	water_mat = GraphicsPolish.pbr(DAY_SKY, 0.1, 0.35)
	bg.material_override = water_mat
	bg.position = Vector3(cx, cy, cz - sz * 0.5 + 0.02)
	add_child(bg)

	# Glass shell (transparent).
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = TANK_SIZE
	glass.mesh = gb
	glass.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.80, 1.0), "glass")
	glass.position = TANK_CENTER
	add_child(glass)

	# Dark frame around the glass edges.
	var frame_mat := GraphicsPolish.pbr_preset(Color(0.08, 0.09, 0.13), "metal")
	var edge_t := 0.09
	for ex in [-1.0, 1.0]:
		for ey in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(edge_t, sy + edge_t, edge_t)
			post.mesh = pb
			post.material_override = frame_mat
			post.position = Vector3(cx + ex * (sx * 0.5), cy, cz + ey * (sz * 0.5))
			add_child(post)
	for ey in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(sx + edge_t, edge_t, sz + edge_t)
		rail.mesh = rb
		rail.material_override = frame_mat
		rail.position = Vector3(cx, cy + ey * (sy * 0.5), cz)
		add_child(rail)

	# Gravel bed.
	var gravel := MeshInstance3D.new()
	var grb := BoxMesh.new()
	grb.size = Vector3(sx - 0.15, 0.10, sz - 0.15)
	gravel.mesh = grb
	gravel.material_override = GraphicsPolish.pbr_preset(Color(0.42, 0.36, 0.28), "matte")
	gravel.position = Vector3(cx, cy - sy * 0.5 + 0.06, cz)
	add_child(gravel)

	# A couple of plants (green cones).
	var plant_mat := GraphicsPolish.pbr(Color(0.20, 0.65, 0.30), 0.0, 0.55)
	for px in [-1.25, 1.15]:
		var plant := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.02
		pm.bottom_radius = 0.09
		pm.height = 0.55
		plant.mesh = pm
		plant.material_override = plant_mat
		plant.position = Vector3(px, cy - sy * 0.5 + 0.38, cz - 0.25)
		add_child(plant)

	# Wall mounting brackets.
	for bx in [-1.2, 1.2]:
		var br := MeshInstance3D.new()
		var brb := BoxMesh.new()
		brb.size = Vector3(0.12, 0.5, 0.5)
		br.mesh = brb
		br.material_override = frame_mat
		br.position = Vector3(bx, cy - sy * 0.5 - 0.28, cz - 0.2)
		add_child(br)


func _build_fish() -> void:
	for i in FISH_COUNT:
		var f := Fish.new()
		f.phase = randf() * TAU
		f.root = Node3D.new()
		f.root.position = Vector3(
			randf_range(FISH_MIN.x, FISH_MAX.x),
			randf_range(FISH_MIN.y, FISH_MAX.y),
			randf_range(FISH_MIN.z, FISH_MAX.z))
		add_child(f.root)

		var col: Color = FISH_COLORS[i % FISH_COLORS.size()]

		# Body: elongated sphere (head toward -Z so look_at faces travel dir).
		var body := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.11
		bs.height = 0.22
		body.mesh = bs
		body.scale = Vector3(0.85, 0.85, 1.8)
		body.material_override = GraphicsPolish.pbr(col, 0.25, 0.35)
		f.root.add_child(body)

		# Tail fin: flattened box wagged in _process.
		f.tail = MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.03, 0.17, 0.15)
		f.tail.mesh = tb
		f.tail.material_override = GraphicsPolish.pbr(col.darkened(0.15), 0.2, 0.4)
		f.tail.position = Vector3(0.0, 0.0, 0.26)
		f.root.add_child(f.tail)

		# Eyes.
		var es := SphereMesh.new()
		es.radius = 0.022
		es.height = 0.044
		for ex in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = es
			eye.material_override = GraphicsPolish.pbr(Color(0.05, 0.05, 0.07), 0.9, 0.2)
			eye.position = Vector3(ex * 0.055, 0.045, -0.15)
			f.root.add_child(eye)

		var a := randf() * TAU
		f.vel = Vector3(cos(a), randf_range(-0.2, 0.2), sin(a)).normalized() * 0.8
		f.wander_dir = f.vel.normalized()
		fishes.append(f)


func _build_bubbles() -> void:
	var bm := GraphicsPolish.pbr_preset(Color(0.8, 0.95, 1.0), "glass")
	for i in 12:
		var b := Bubble.new()
		b.speed = randf_range(0.25, 0.55)
		b.node = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.018, 0.045)
		sm.height = sm.radius * 2.0
		b.node.mesh = sm
		b.node.material_override = bm
		_reset_bubble(b, true)
		add_child(b.node)
		bubbles.append(b)


func _reset_bubble(b: Bubble, random_y: bool = false) -> void:
	var y := FISH_MIN.y + 0.05
	if random_y:
		y = randf_range(FISH_MIN.y, FISH_MAX.y)
	b.node.position = Vector3(
		randf_range(FISH_MIN.x, FISH_MAX.x), y,
		randf_range(FISH_MIN.z, FISH_MAX.z))


func _build_sky_indicator() -> void:
	var arc_center := Vector3(0.0, 3.05, -1.9)

	sun_node = MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.14
	ss.height = 0.28
	sun_node.mesh = ss
	sun_node.material_override = GraphicsPolish.glow(Color(1.0, 0.80, 0.25), 1.6)
	sun_node.position = arc_center
	add_child(sun_node)

	moon_node = MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.11
	ms.height = 0.22
	moon_node.mesh = ms
	moon_node.material_override = GraphicsPolish.glow(Color(0.75, 0.85, 1.0), 1.4)
	moon_node.position = arc_center
	add_child(moon_node)

	cycle_label = GraphicsPolish.make_label("", 64, Color(0.9, 0.95, 1.0))
	cycle_label.position = Vector3(0.0, 4.15, -1.9)
	cycle_label.pixel_size = 0.008
	add_child(cycle_label)


func _make_label(text: String, pos: Vector3, color: Color, pixel: float = 0.007) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 8
	add_child(l)
	return l


func _build_ui() -> void:
	hud_main = _make_label("", Vector3(-3.6, 3.3, -0.6), Color(0.85, 0.95, 1.0))
	hud_help = _make_label(
		"Click inside the tank: drop food\n(fish startle, then come eat)\nR: reset",
		Vector3(1.6, 3.3, -0.6), Color(0.65, 0.75, 0.9))


func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	# Persist the tank placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("holo-aquarium_main", global_transform)
	# XR hand: a pinch drops food at the pinch point (mouse clicks still work).
	if ARUpgradeKit.is_xr_active() and cam != null \
			and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if not cam.is_position_behind(pp):
			_handle_click(cam.unproject_position(pp))
	_update_day_night()
	_update_fish(delta)
	_update_pellets(delta)
	_update_bubbles(delta)
	_update_hud()


func _poll_keys() -> void:
	var down := Input.is_key_pressed(KEY_R)
	var was: bool = _prev_keys.get(KEY_R, false)
	if down and not was:
		_reset()
	_prev_keys[KEY_R] = down


func _day_factor() -> float:
	var phase := fmod(_time, DAY_LENGTH) / DAY_LENGTH
	return 0.5 - 0.5 * cos(TAU * phase)


func _update_day_night() -> void:
	var phase := fmod(_time, DAY_LENGTH) / DAY_LENGTH
	var d := _day_factor()

	sun_light.light_color = NIGHT_LIGHT.lerp(DAY_LIGHT, d)
	sun_light.light_energy = lerpf(0.25, 1.15, d)
	env.ambient_light_energy = lerpf(0.25, 0.7, d)
	water_mat.albedo_color = NIGHT_SKY.lerp(DAY_SKY, d)

	# Sun/moon arc above the tank.
	var a := TAU * phase
	var arc := Vector3(0.0, 3.05, -1.9)
	sun_node.position = arc + Vector3(cos(a) * 1.7, sin(a) * 0.85, 0.0)
	moon_node.position = arc + Vector3(cos(a + PI) * 1.7, sin(a + PI) * 0.85, 0.0)
	sun_node.visible = d >= 0.5
	moon_node.visible = d < 0.5

	var hours := int(phase * 24.0)
	var tod := "DAY" if d >= 0.5 else "NIGHT"
	cycle_label.text = "%02d:00  %s" % [hours, tod]
	cycle_label.modulate = Color(1.0, 0.9, 0.55) if d >= 0.5 else Color(0.65, 0.75, 1.0)


func _school_center() -> Vector3:
	var c := Vector3.ZERO
	for f in fishes:
		c += (f as Fish).root.position
	return c / float(maxi(1, fishes.size()))


func _update_fish(delta: float) -> void:
	var school := _school_center()
	for f in fishes:
		var fish: Fish = f
		var pos: Vector3 = fish.root.position
		var acc := Vector3.ZERO

		# Cohesion: drift toward the school center.
		acc += (school - pos) * 0.6

		# Wander.
		fish.wander_t -= delta
		if fish.wander_t <= 0.0:
			fish.wander_t = randf_range(1.0, 3.0)
			var wa := randf() * TAU
			fish.wander_dir = Vector3(cos(wa), randf_range(-0.35, 0.35), sin(wa)).normalized()
		acc += fish.wander_dir * 0.7

		# Separation.
		for o in fishes:
			var other: Fish = o
			if other == fish:
				continue
			var diff: Vector3 = pos - other.root.position
			var dist := diff.length()
			if dist > 0.001 and dist < 0.38:
				acc += diff.normalized() * (0.38 - dist) * 5.0

		# Flee the tap point.
		if fish.flee_t > 0.0:
			fish.flee_t -= delta
			var away: Vector3 = pos - flee_point
			if away.length() > 0.001:
				acc += away.normalized() * 14.0

		# Seek the nearest pellet.
		var best: Pellet = null
		var best_d := 999.0
		for p in pellets:
			var pel: Pellet = p
			var pd: float = pos.distance_to(pel.node.position)
			if pd < best_d:
				best_d = pd
				best = pel
		if best != null:
			acc += (best.node.position - pos).normalized() * 3.0
			if best_d < EAT_DIST:
				_eat_pellet(best)
				fish.vel *= 1.4

		# Soft steering inside the tank bounds.
		var margin := 0.25
		var push := 7.0
		if pos.x < FISH_MIN.x + margin:
			acc.x += push
		elif pos.x > FISH_MAX.x - margin:
			acc.x -= push
		if pos.y < FISH_MIN.y + margin:
			acc.y += push
		elif pos.y > FISH_MAX.y - margin:
			acc.y -= push
		if pos.z < FISH_MIN.z + margin:
			acc.z += push
		elif pos.z > FISH_MAX.z - margin:
			acc.z -= push

		fish.vel += acc * delta
		if fish.vel.length() > MAX_SPEED:
			fish.vel = fish.vel.limit_length(MAX_SPEED)
		if fish.vel.length() < 0.25 and fish.vel.length() > 0.001:
			fish.vel = fish.vel.normalized() * 0.25
		pos += fish.vel * delta
		pos.x = clampf(pos.x, FISH_MIN.x, FISH_MAX.x)
		pos.y = clampf(pos.y, FISH_MIN.y, FISH_MAX.y)
		pos.z = clampf(pos.z, FISH_MIN.z, FISH_MAX.z)
		fish.root.position = pos

		if fish.vel.length() > 0.05:
			fish.root.look_at(pos + fish.vel, Vector3.UP)

		# Tail wag.
		fish.tail.rotation.y = sin(_time * 10.0 + fish.phase) * 0.55


func _update_pellets(delta: float) -> void:
	for i in range(pellets.size() - 1, -1, -1):
		var p: Pellet = pellets[i]
		p.life -= delta
		p.node.position.y -= 0.22 * delta
		if p.node.position.y < FISH_MIN.y:
			p.node.position.y = FISH_MIN.y
		var s := 1.0
		if p.life < 3.0:
			s = maxf(0.2, p.life / 3.0)
		p.node.scale = Vector3(s, s, s)
		if p.life <= 0.0:
			p.node.queue_free()
			pellets.remove_at(i)


func _eat_pellet(p: Pellet) -> void:
	GraphicsPolish.spawn_sparks(self, p.node.position, Color(0.6, 0.9, 1.0), 14)
	p.node.queue_free()
	pellets.erase(p)
	pellets_eaten += 1


func _update_bubbles(delta: float) -> void:
	for b in bubbles:
		var bub: Bubble = b
		bub.node.position.y += bub.speed * delta
		if bub.node.position.y > FISH_MAX.y:
			_reset_bubble(bub)


func _update_hud() -> void:
	var phase := fmod(_time, DAY_LENGTH) / DAY_LENGTH
	var hours := int(phase * 24.0)
	var tod := "DAY" if _day_factor() >= 0.5 else "NIGHT"
	hud_main.text = "HOLO-AQUARIUM\nFish: %d\nTime: %02d:00 (%s)\nPellets eaten: %d" % [
		fishes.size(), hours, tod, pellets_eaten]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)


func _tank_hit(o: Vector3, d: Vector3) -> Array:
	# Intersect the ray with the tank's front-glass plane, then check bounds.
	var pz: float = TANK_CENTER.z + TANK_SIZE.z * 0.5
	if absf(d.z) < 0.0001:
		return []
	var t: float = (pz - o.z) / d.z
	if t <= 0.0:
		return []
	var p: Vector3 = o + d * t
	if absf(p.x - TANK_CENTER.x) > TANK_SIZE.x * 0.5:
		return []
	if absf(p.y - TANK_CENTER.y) > TANK_SIZE.y * 0.5:
		return []
	return [p]


func _handle_click(screen_pos: Vector2) -> void:
	if cam == null:
		return
	var o: Vector3 = cam.project_ray_origin(screen_pos)
	var d: Vector3 = cam.project_ray_normal(screen_pos)
	var hit: Array = _tank_hit(o, d)
	if hit.is_empty():
		return
	var p: Vector3 = hit[0]

	# Fish flee the tap...
	flee_point = Vector3(p.x, p.y, TANK_CENTER.z)
	for f in fishes:
		(f as Fish).flee_t = 0.9
	flee_active = true

	# ...then come back for the food pellet dropped there.
	var pellet := Pellet.new()
	pellet.node = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	pellet.node.mesh = sm
	pellet.node.material_override = GraphicsPolish.pbr(Color(0.55, 0.38, 0.20), 0.0, 0.7)
	pellet.node.position = ARUpgradeKit.clamp_to_room(Vector3(
		clampf(p.x, FISH_MIN.x, FISH_MAX.x),
		clampf(p.y, FISH_MIN.y, FISH_MAX.y),
		clampf(p.z - 0.15, FISH_MIN.z, FISH_MAX.z)))
	add_child(pellet.node)
	pellets.append(pellet)


func _reset() -> void:
	for p in pellets:
		(p as Pellet).node.queue_free()
	pellets.clear()
	pellets_eaten = 0
	for f in fishes:
		var fish: Fish = f
		fish.root.position = Vector3(
			randf_range(FISH_MIN.x, FISH_MAX.x),
			randf_range(FISH_MIN.y, FISH_MAX.y),
			randf_range(FISH_MIN.z, FISH_MAX.z))
		var a := randf() * TAU
		fish.vel = Vector3(cos(a), 0.0, sin(a)).normalized() * 0.8
		fish.flee_t = 0.0
	ARUpgradeKit.save_anchor("holo-aquarium_main", global_transform)


func _pinch_active() -> bool:
	# Hand-tracking hook: wire to XR hand pinch in a future pass.
	return false
