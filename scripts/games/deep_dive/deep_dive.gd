## Deep Dive: your room becomes the ocean. Blue fog, god-ray cones, drifting
## plankton, a sandy seabed below, coral, jellyfish and schools of fish.
## Swim with hand-paddling strokes (XR) or click-drag (desktop). Find 5 hidden
## treasure chests (Kenney pirate-kit) — pinch near one to open it for pearls
## and gold. Sharks patrol the water: a bump costs air. Watch your air meter
## and refill at glowing bubble vents. Your collection log persists to
## user://nexus_dive.cfg. R restarts the dive.
extends Node3D

const SWIM_SPEED := 1.5
const STROKE_IMPULSE := 1.35
const AIR_MAX := 100.0
const AIR_DRAIN := 1.1
const VENT_REFILL := 30.0
const CHEST_COUNT := 5
const SHARK_BITE_RANGE := 1.15
const SHARK_WARN_RANGE := 2.4
const DIVE_FILE := "user://nexus_dive.cfg"

var camera: Camera3D = null
var cam_base := Vector3(0.0, 1.4, 1.2)
var vel := Vector3.ZERO

var chests: Array = []
var pearls := 0
var sharks: Array = []
var jellies: Array = []
var schools: Array = []
var vents: Array = []
var rays: Array = []

var air := AIR_MAX
var state := "play"
var msg := ""
var msg_t := 0.0
var pulse_t := 0.0
var warn_cd := 0.0
var low_air_warned := false

var log_dives := 0
var log_pearls_total := 0
var log_best := 0
var log_opened: Array = []

# Desktop input.
var dragging := false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
# XR stroke tracking.
var xr_prev := [Vector3.ZERO, Vector3.ZERO]
var xr_vel := [Vector3.ZERO, Vector3.ZERO]
var xr_has := [false, false]
var xr_stroke_cd := [0.0, 0.0]
var xr_prev_hand := Vector3.ZERO
var xr_has_hand := false

var hud_air_bar: MeshInstance3D = null
var hud_air_bg: MeshInstance3D = null
var hud_stats: Label3D = null
var hud_msg: Label3D = null
var hud_help: Label3D = null
var hud_log: Label3D = null

var _model_cache := {}


func _load_model(file_name: String) -> Node3D:
	var path := "res://assets/models/deep_dive/" + file_name + ".fbx"
	if _model_cache.has(path):
		var cached: PackedScene = _model_cache[path]
		if cached != null and is_instance_valid(cached):
			return cached.instantiate() as Node3D
		_model_cache.erase(path)
	if not ResourceLoader.exists(path):
		push_warning("[deep_dive] missing model: " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[deep_dive] failed to load: " + path)
		return null
	_model_cache[path] = ps
	return ps.instantiate() as Node3D


func _recolor(root: Node, albedo: Color, metallic: float = 0.0, roughness: float = 0.6, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> void:
	if root == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "deep_dive_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_log()
	_build_seabed()
	_build_god_rays()
	_build_shipwreck()
	_build_rocks_and_weeds()
	_build_coral_garden()
	_build_vents()
	_build_chests()
	_build_jellies()
	_build_schools()
	_build_sharks()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, 0.0), 2.5, 60)
	_set_msg("DIVE START — find 5 treasure chests", 3.0)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		cam_base = camera.position
		return
	camera = Camera3D.new()
	camera.position = cam_base
	add_child(camera)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.06, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.35, 0.55)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.02, 0.12, 0.24)
	env.fog_depth_begin = 2.5
	env.fog_depth_end = 11.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)
	GraphicsPolish.make_point_light(self, Vector3(0, 3.4, 0), Color(0.35, 0.65, 1.0), 1.3, 10.0)


func _build_seabed() -> void:
	var sand := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11.0, 11.0)
	sand.mesh = plane
	sand.material_override = GraphicsPolish.pbr(Color(0.42, 0.35, 0.22), 0.0, 0.95)
	sand.position = Vector3(0.0, 0.0, 0.0)
	add_child(sand)
	# Scattered shell glints.
	for i in 7:
		var shell := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.035
		sph.height = 0.05
		shell.mesh = sph
		shell.material_override = GraphicsPolish.glow(Color(1.0, 0.85, 0.6), 0.7)
		var a := randf_range(0.0, TAU)
		var r := randf_range(0.8, 3.0)
		shell.position = Vector3(cos(a) * r, 0.03, sin(a) * r)
		add_child(shell)


func _build_god_rays() -> void:
	for i in 5:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.35, 0.65, 1.0, 0.10)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cone := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 1.1
		cyl.height = 6.5
		cone.mesh = cyl
		cone.material_override = mat
		var a := deg_to_rad(float(i) * 72.0 + 18.0)
		cone.position = Vector3(cos(a) * 1.7, 3.0, sin(a) * 1.7)
		cone.rotation_degrees = Vector3(8.0, 0.0, 6.0)
		add_child(cone)
		rays.append({"node": cone, "mat": mat, "ph": randf_range(0.0, TAU)})


func _build_shipwreck() -> void:
	var wreck: Node3D = _load_model("ship-wreck")
	if wreck == null:
		return
	_recolor(wreck, Color(0.30, 0.24, 0.16), 0.15, 0.85)
	wreck.position = Vector3(0.4, 0.05, -2.7)
	wreck.rotation_degrees = Vector3(0, 28, 9)
	wreck.scale = Vector3.ONE * 1.9
	add_child(wreck)
	# Eerie glow from the broken hull.
	GraphicsPolish.make_point_light(self, Vector3(0.4, 1.0, -2.7), Color(0.2, 0.7, 0.9), 0.9, 4.5)
	# A treasure chest tucked against the wreck (one of the five).
	_chest_spots.append(Vector3(1.5, 0.28, -2.1))


var _chest_spots: Array = []


func _build_rocks_and_weeds() -> void:
	var rock_names := ["rocks-a", "rocks-b", "rocks-c", "rocks-sand-a", "rocks-sand-b"]
	for i in 12:
		var rn: String = rock_names[i % rock_names.size()]
		var rock: Node3D = _load_model(rn)
		if rock == null:
			continue
		_recolor(rock, Color(0.30, 0.32, 0.34), 0.05, 0.9)
		var a := randf_range(0.0, TAU)
		var r := randf_range(1.6, 3.4)
		rock.position = ARUpgradeKit.clamp_to_room(Vector3(cos(a) * r, 0.0, sin(a) * r), 0.5)
		rock.rotation.y = randf_range(0.0, TAU)
		var s := randf_range(0.8, 1.8)
		rock.scale = Vector3.ONE * s
		add_child(rock)
	# Seaweed: Kenney grass tufts, tinted deep green.
	for i in 16:
		var weed: Node3D = _load_model("grass-plant" if i % 2 == 0 else "grass-patch")
		if weed == null:
			continue
		_recolor(weed, Color(0.08, 0.35, 0.18), 0.0, 0.8, Color(0.1, 0.5, 0.2), 0.4)
		var a2 := randf_range(0.0, TAU)
		var r2 := randf_range(1.2, 3.3)
		weed.position = ARUpgradeKit.clamp_to_room(Vector3(cos(a2) * r2, 0.0, sin(a2) * r2), 0.5)
		weed.rotation.y = randf_range(0.0, TAU)
		weed.scale = Vector3(randf_range(1.2, 2.0), randf_range(1.6, 2.6), randf_range(1.2, 2.0))
		add_child(weed)
	# Barrels + crates as dive dressing.
	for i in 4:
		var prop: Node3D = _load_model("barrel" if i % 2 == 0 else "crate")
		if prop == null:
			continue
		_recolor(prop, Color(0.35, 0.26, 0.15), 0.1, 0.8)
		var a3 := randf_range(0.0, TAU)
		prop.position = ARUpgradeKit.clamp_to_room(Vector3(cos(a3) * 2.4, 0.28, sin(a3) * 2.4), 0.6)
		prop.rotation.y = randf_range(0.0, TAU)
		add_child(prop)


func _build_coral_garden() -> void:
	var coral_colors := [
		Color(1.0, 0.35, 0.55), Color(1.0, 0.55, 0.2),
		Color(0.55, 0.3, 1.0), Color(0.2, 0.9, 0.8),
	]
	for i in 6:
		var coral := _make_coral(coral_colors[i % coral_colors.size()])
		var a := deg_to_rad(float(i) * 60.0 + 30.0)
		coral.position = ARUpgradeKit.clamp_to_room(Vector3(cos(a) * 2.5, 0.0, sin(a) * 2.5), 0.6)
		coral.rotation.y = randf_range(0.0, TAU)
		add_child(coral)


func _make_coral(color: Color) -> Node3D:
	var root := Node3D.new()
	var stem_mat := GraphicsPolish.pbr(Color(0.75, 0.45, 0.5), 0.0, 0.7)
	var tip_mat := GraphicsPolish.glow(color, 1.6)
	_branch(root, Vector3.ZERO, Vector3.UP, 0.55, 0.045, 3, stem_mat, tip_mat)
	return root


func _branch(parent: Node, base: Vector3, dir: Vector3, length: float, radius: float, depth: int, stem_mat: Material, tip_mat: Material) -> void:
	var seg := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.7
	cyl.bottom_radius = radius
	cyl.height = length
	seg.mesh = cyl
	seg.material_override = stem_mat
	var mid: Vector3 = base + dir * (length * 0.5)
	seg.position = mid
	# Orient the cylinder's Y axis along dir.
	if dir.length() > 0.01:
		seg.basis = Basis.looking_at(dir.normalized(), Vector3.UP) * Basis.from_euler(Vector3(deg_to_rad(90), 0, 0))
	parent.add_child(seg)
	var tip: Vector3 = base + dir * length
	if depth <= 0:
		var bud := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = radius * 2.2
		sph.height = radius * 4.4
		bud.mesh = sph
		bud.material_override = tip_mat
		bud.position = tip
		parent.add_child(bud)
		return
	var n := 2 + (1 if depth % 2 == 0 else 0)
	for k in n:
		var spread := Basis.from_euler(Vector3(randf_range(0.35, 0.7), randf_range(0.0, TAU), 0.0))
		var ndir: Vector3 = (spread * dir).normalized()
		_branch(parent, tip, ndir, length * 0.72, radius * 0.72, depth - 1, stem_mat, tip_mat)


func _build_vents() -> void:
	var vent_spots := [Vector3(-2.3, 0.0, 1.6), Vector3(2.4, 0.0, 1.4), Vector3(0.2, 0.0, 2.7)]
	for spot in vent_spots:
		var root := Node3D.new()
		root.position = spot
		add_child(root)
		var base: Node3D = _load_model("rocks-sand-a")
		if base != null:
			_recolor(base, Color(0.25, 0.27, 0.30), 0.1, 0.9)
			base.scale = Vector3.ONE * 1.4
			root.add_child(base)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.28
		torus.outer_radius = 0.38
		ring.mesh = torus
		ring.material_override = GraphicsPolish.glow(Color(0.35, 0.9, 1.0), 1.8)
		ring.position = Vector3(0, 0.25, 0)
		root.add_child(ring)
		# Rising bubbles.
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 10.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		var parts := GPUParticles3D.new()
		parts.amount = 28
		parts.lifetime = 2.6
		parts.process_material = pm
		var bub := SphereMesh.new()
		bub.radius = 0.045
		bub.height = 0.09
		var bmat := StandardMaterial3D.new()
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(0.6, 0.9, 1.0, 0.55)
		bmat.emission_enabled = true
		bmat.emission = Color(0.4, 0.8, 1.0)
		bmat.emission_energy_multiplier = 0.9
		bub.material = bmat
		parts.draw_pass_1 = bub
		parts.position = Vector3(0, 0.35, 0)
		root.add_child(parts)
		GraphicsPolish.make_point_light(root, Vector3(0, 0.8, 0), Color(0.35, 0.85, 1.0), 0.8, 3.5)
		vents.append({"node": root, "pos": spot, "ring": ring})


func _build_chests() -> void:
	# Five spots: one tucked at the wreck, the rest spread around the room.
	var spots: Array = _chest_spots.duplicate()
	var angles := [100.0, 172.0, 244.0, 316.0]
	for a in angles:
		var rad := deg_to_rad(a)
		var r := randf_range(2.0, 2.8)
		spots.append(ARUpgradeKit.clamp_to_room(Vector3(cos(rad) * r, randf_range(0.28, 1.3), sin(rad) * r), 0.6))
	while spots.size() > CHEST_COUNT:
		spots.pop_back()
	var idx := 0
	for spot in spots:
		var root := Node3D.new()
		root.position = spot
		add_child(root)
		var chest: Node3D = _load_model("chest")
		if chest != null:
			_recolor(chest, Color(0.40, 0.28, 0.14), 0.3, 0.6, Color(1.0, 0.75, 0.25), 0.25)
			chest.rotation.y = randf_range(0.0, TAU)
			root.add_child(chest)
		var ring_mat := GraphicsPolish.glow(Color(1.0, 0.8, 0.3), 1.6)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.52
		ring.mesh = torus
		ring.material_override = ring_mat
		ring.position = Vector3(0, 0.06, 0)
		root.add_child(ring)
		var opened := idx < log_opened.size() and bool(log_opened[idx])
		if opened:
			ring.visible = false
		chests.append({"node": root, "pos": spot, "opened": opened, "ring": ring, "ring_mat": ring_mat, "idx": idx})
		idx += 1


func _make_fish(body_color: Color, stripe_color: Color, size: float = 1.0) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09 * size
	sph.height = 0.18 * size
	body.mesh = sph
	body.material_override = GraphicsPolish.pbr(body_color, 0.15, 0.35)
	body.scale = Vector3(0.55, 0.8, 1.9)
	root.add_child(body)
	# Emissive lateral stripe.
	var stripe := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.10 * size, 0.03 * size, 0.26 * size)
	stripe.mesh = sbox
	stripe.material_override = GraphicsPolish.glow(stripe_color, 1.5)
	stripe.position = Vector3(0, 0.02 * size, 0)
	root.add_child(stripe)
	# Tail fin.
	var tail := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.02 * size, 0.14 * size, 0.10 * size)
	tail.mesh = tbox
	tail.material_override = GraphicsPolish.pbr(body_color.darkened(0.25), 0.1, 0.5)
	tail.position = Vector3(0, 0, 0.20 * size)
	tail.rotation.y = deg_to_rad(35.0)
	root.add_child(tail)
	# Dorsal fin.
	var fin := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.02 * size, 0.09 * size, 0.12 * size)
	fin.mesh = fbox
	fin.material_override = GraphicsPolish.pbr(body_color.darkened(0.25), 0.1, 0.5)
	fin.position = Vector3(0, 0.10 * size, -0.02 * size)
	fin.rotation.x = deg_to_rad(-18.0)
	root.add_child(fin)
	# Eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var esph := SphereMesh.new()
		esph.radius = 0.018 * size
		esph.height = 0.036 * size
		eye.mesh = esph
		eye.material_override = GraphicsPolish.glow(Color(0.1, 0.1, 0.1), 0.3)
		eye.position = Vector3(side * 0.045 * size, 0.03 * size, -0.13 * size)
		root.add_child(eye)
	return root


func _make_shark() -> Node3D:
	var root := Node3D.new()
	var gray := GraphicsPolish.pbr(Color(0.42, 0.47, 0.55), 0.25, 0.45)
	# Torpedo body.
	var body := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.30
	sph.height = 0.60
	body.mesh = sph
	body.material_override = gray
	body.scale = Vector3(0.75, 0.85, 2.6)
	root.add_child(body)
	# Snout.
	var snout := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.20
	cone.height = 0.35
	snout.mesh = cone
	snout.material_override = gray
	snout.position = Vector3(0, -0.02, -0.85)
	snout.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(snout)
	# Tail fin (vertical).
	var tail := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.06, 0.55, 0.22)
	tail.mesh = tbox
	tail.material_override = gray
	tail.position = Vector3(0, 0.12, 0.85)
	tail.rotation.x = deg_to_rad(-25.0)
	root.add_child(tail)
	# Dorsal fin.
	var dorsal := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.08, 0.35, 0.30)
	dorsal.mesh = prism
	dorsal.material_override = gray
	dorsal.position = Vector3(0, 0.38, 0.05)
	root.add_child(dorsal)
	# Pectoral fins.
	for side in [-1.0, 1.0]:
		var pec := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.35, 0.05, 0.20)
		pec.mesh = pbox
		pec.material_override = gray
		pec.position = Vector3(side * 0.30, -0.18, -0.15)
		pec.rotation.z = deg_to_rad(side * -28.0)
		root.add_child(pec)
	# Glowing eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var esph := SphereMesh.new()
		esph.radius = 0.045
		esph.height = 0.09
		eye.mesh = esph
		eye.material_override = GraphicsPolish.glow(Color(1.0, 0.2, 0.1), 2.0)
		eye.position = Vector3(side * 0.16, 0.10, -0.62)
		root.add_child(eye)
	# Gill slits glow.
	for g in 3:
		var gill := MeshInstance3D.new()
		var gbox := BoxMesh.new()
		gbox.size = Vector3(0.02, 0.16, 0.03)
		gill.mesh = gbox
		gill.material_override = GraphicsPolish.glow(Color(0.3, 0.8, 1.0), 0.8)
		gill.position = Vector3(0.20, 0.0, -0.35 + float(g) * 0.10)
		root.add_child(gill)
		var gill2: MeshInstance3D = gill.duplicate()
		gill2.position.x = -0.20
		root.add_child(gill2)
	return root


func _make_jellyfish(color: Color) -> Node3D:
	var root := Node3D.new()
	var dome_mat := StandardMaterial3D.new()
	dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	dome_mat.emission_enabled = true
	dome_mat.emission = color
	dome_mat.emission_energy_multiplier = 1.4
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.30
	sph.height = 0.60
	dome.mesh = sph
	dome.material_override = dome_mat
	dome.scale = Vector3(1.0, 0.75, 1.0)
	root.add_child(dome)
	var tent_mat := GraphicsPolish.glow(color, 1.1)
	var tents: Array = []
	for i in 7:
		var t := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.015
		cyl.bottom_radius = 0.008
		cyl.height = 0.7
		t.mesh = cyl
		t.material_override = tent_mat
		var a := deg_to_rad(float(i) * (360.0 / 7.0))
		t.position = Vector3(cos(a) * 0.16, -0.45, sin(a) * 0.16)
		root.add_child(t)
		tents.append(t)
	root.set_meta("tents", tents)
	return root


func _build_jellies() -> void:
	var colors := [Color(1.0, 0.4, 0.8), Color(0.4, 0.8, 1.0), Color(0.7, 0.4, 1.0), Color(0.4, 1.0, 0.7)]
	for i in 4:
		var j: Node3D = _make_jellyfish(colors[i])
		var a := deg_to_rad(float(i) * 90.0 + 45.0)
		j.position = ARUpgradeKit.clamp_to_room(Vector3(cos(a) * 2.2, randf_range(1.6, 2.4), sin(a) * 2.2), 0.6)
		add_child(j)
		jellies.append({"node": j, "ph": randf_range(0.0, TAU), "base_y": j.position.y, "drift_a": randf_range(0.0, TAU)})


func _build_schools() -> void:
	var palettes := [
		[Color(1.0, 0.55, 0.2), Color(1.0, 0.9, 0.4)],
		[Color(0.25, 0.6, 1.0), Color(0.6, 1.0, 1.0)],
		[Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.8)],
	]
	for s in 3:
		var center := Vector3(cos(deg_to_rad(float(s) * 120.0)) * 1.8, 1.5 + float(s) * 0.25, sin(deg_to_rad(float(s) * 120.0)) * 1.8)
		var fishes: Array = []
		for f in 7:
			var fish: Node3D = _make_fish(palettes[s][0], palettes[s][1], randf_range(0.8, 1.2))
			add_child(fish)
			fishes.append({"node": fish, "off": randf_range(0.0, TAU), "r": randf_range(0.5, 1.0), "y": randf_range(-0.2, 0.2)})
		schools.append({"center": center, "fishes": fishes, "speed": randf_range(0.35, 0.6), "t": randf_range(0.0, TAU)})


func _build_sharks() -> void:
	for i in 2:
		var shark: Node3D = _make_shark()
		add_child(shark)
		var wps: Array = []
		for k in 5:
			var a := deg_to_rad(float(k) * 72.0 + float(i) * 40.0)
			wps.append(ARUpgradeKit.clamp_to_room(Vector3(cos(a) * 2.6, randf_range(1.1, 1.9), sin(a) * 2.6), 0.5))
		shark.position = wps[0]
		sharks.append({"node": shark, "wps": wps, "wp_i": 1, "speed": randf_range(0.7, 0.95),
			"bite_cd": 0.0, "warn_cd": 0.0, "flee": 0.0, "sway": randf_range(0.0, TAU)})


func _build_hud() -> void:
	if camera == null:
		return
	var holder := Node3D.new()
	camera.add_child(holder)
	# Air bar (top-left of view).
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(0.452, 0.047, 0.008)
	bg.mesh = bgm
	bg.material_override = GraphicsPolish.pbr(Color(0.05, 0.08, 0.12), 0.2, 0.6)
	bg.position = Vector3(-0.52, 0.40, -0.8)
	holder.add_child(bg)
	hud_air_bg = bg
	hud_air_bar = MeshInstance3D.new()
	var fgm := BoxMesh.new()
	fgm.size = Vector3(0.44, 0.035, 0.012)
	hud_air_bar.mesh = fgm
	hud_air_bar.material_override = GraphicsPolish.glow(Color(0.3, 0.85, 1.0), 1.5)
	hud_air_bar.position = Vector3(-0.52, 0.40, -0.796)
	holder.add_child(hud_air_bar)
	var air_lbl := GraphicsPolish.make_label("AIR", 28, Color(0.7, 0.92, 1.0))
	air_lbl.position = Vector3(-0.80, 0.40, -0.8)
	air_lbl.pixel_size = 0.0028
	camera.add_child(air_lbl)
	hud_stats = GraphicsPolish.make_label("", 38, Color(1.0, 0.95, 0.75))
	hud_stats.position = Vector3(0.55, 0.40, -0.8)
	hud_stats.pixel_size = 0.003
	camera.add_child(hud_stats)
	hud_msg = GraphicsPolish.make_label("", 60, Color(1.0, 0.9, 0.55))
	hud_msg.position = Vector3(0.0, 0.12, -1.1)
	hud_msg.pixel_size = 0.004
	camera.add_child(hud_msg)
	hud_help = GraphicsPolish.make_label("", 26, Color(0.72, 0.85, 0.95))
	hud_help.position = Vector3(0.0, -0.52, -0.85)
	hud_help.pixel_size = 0.0026
	camera.add_child(hud_help)
	hud_log = GraphicsPolish.make_label("", 26, Color(0.6, 0.75, 0.9))
	hud_log.position = Vector3(-0.85, -0.44, -0.85)
	hud_log.pixel_size = 0.0026
	camera.add_child(hud_log)
	_update_hud()


func _update_hud() -> void:
	if hud_air_bar != null:
		var frac := clampf(air / AIR_MAX, 0.0, 1.0)
		hud_air_bar.scale.x = maxf(frac, 0.001)
		hud_air_bar.position.x = -0.52 - 0.44 * (1.0 - frac) * 0.5
		var mat := hud_air_bar.material_override as StandardMaterial3D
		if mat != null:
			mat.emission = Color(1.0, 0.25, 0.15) if frac < 0.25 else Color(0.3, 0.85, 1.0)
	if hud_stats != null:
		var opened := 0
		for c in chests:
			if bool(c.get("opened", false)):
				opened += 1
		hud_stats.text = "PEARLS %d   CHESTS %d/%d" % [pearls, opened, CHEST_COUNT]
	if hud_msg != null:
		hud_msg.text = msg
	if hud_help != null:
		if ARUpgradeKit.is_xr_active():
			hud_help.text = "Paddle hands to swim | pinch near chest to open | reach vents for air"
		else:
			hud_help.text = "Drag: swim + steer | click near chest: open | W/S/A/D swim, Space/C up-down | R restart"
	if hud_log != null:
		hud_log.text = "LOG: %d dives, %d pearls, best %d" % [log_dives, log_pearls_total, log_best]


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_start = mb.position
				drag_cur = mb.position
			else:
				if dragging and drag_start.distance_to(mb.position) < 12.0:
					_try_open_chest_at(_player_pos(), 1.6)
				dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			drag_cur = mm.position


func _player_pos() -> Vector3:
	if camera != null:
		return camera.global_position
	return global_position + Vector3(0, 1.4, 0)


func _process(delta: float) -> void:
	pulse_t += delta
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if warn_cd > 0.0:
		warn_cd -= delta
	if Input.is_key_pressed(KEY_R):
		_restart()
		return
	if state == "win":
		_update_critters(delta)
		_update_hud()
		return
	_handle_swim(delta)
	_update_chests(delta)
	_update_sharks(delta)
	_update_critters(delta)
	_update_air(delta)
	_update_hud()


func _handle_swim(delta: float) -> void:
	var pp := _player_pos()
	var wish := Vector3.ZERO
	if ARUpgradeKit.is_xr_active() and camera != null:
		# Paddling: downward hand strokes push you forward.
		for h in [ARUpgradeKit.HAND_LEFT, ARUpgradeKit.HAND_RIGHT]:
			var hand: Vector3 = ARUpgradeKit.pointer_position(self, h)
			if xr_has[h] and delta > 0.0:
				xr_vel[h] = xr_vel[h].lerp((hand - xr_prev[h]) / delta, 0.45)
			xr_prev[h] = hand
			xr_has[h] = true
			xr_stroke_cd[h] = maxf(0.0, xr_stroke_cd[h] - delta)
			if xr_vel[h].y < -1.1 and xr_stroke_cd[h] <= 0.0:
				xr_stroke_cd[h] = 0.45
				var fwd: Vector3 = -camera.global_transform.basis.z
				vel += fwd.normalized() * STROKE_IMPULSE
				GraphicsPolish.spawn_sparks(self, hand, Color(0.5, 0.9, 1.0), 6)
				Haptics.tick()
		# Right-hand yaw steers.
		var rh: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		var rel: Vector3 = rh - pp
		var flat := Vector3(rel.x, 0.0, rel.z)
		if flat.length() > 0.08:
			var fwd2: Vector3 = -global_transform.basis.z
			fwd2.y = 0.0
			var yaw_ang := fwd2.normalized().signed_angle_to(flat.normalized(), Vector3.UP)
			rotation.y += clampf(-yaw_ang * 1.6, -1.2, 1.2) * delta
	else:
		var fwd3: Vector3 = -global_transform.basis.z
		if dragging:
			var dv: Vector2 = drag_start - drag_cur
			var swim_in := clampf(dv.y / 220.0, -1.0, 1.0)
			rotation.y += clampf(-dv.x / 260.0, -1.0, 1.0) * 2.2 * delta * 3.0
			wish += fwd3.normalized() * swim_in * SWIM_SPEED
		var key_in := Vector3.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			key_in += fwd3
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			key_in -= fwd3
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			rotation.y += 1.8 * delta
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			rotation.y -= 1.8 * delta
		if Input.is_key_pressed(KEY_SPACE):
			key_in += Vector3.UP
		if Input.is_key_pressed(KEY_C):
			key_in += Vector3.DOWN
		if key_in.length() > 0.01:
			wish += key_in.normalized() * SWIM_SPEED
		vel += (wish - vel * 0.6) * minf(delta * 3.0, 1.0)
	# Integrate + clamp to the room volume.
	global_position += vel * delta
	vel *= maxf(0.0, 1.0 - delta * 0.9)
	var p := ARUpgradeKit.clamp_to_room(global_position, 0.4)
	p.y = clampf(p.y, 0.35, 2.6)
	global_position = p
	if camera != null:
		camera.position = camera.position.lerp(cam_base, minf(delta * 2.0, 1.0))


func _update_chests(delta: float) -> void:
	var pp := _player_pos()
	for c in chests:
		if bool(c.get("opened", false)):
			continue
		var ring_mat: StandardMaterial3D = c.get("ring_mat")
		if ring_mat != null:
			GraphicsPolish.pulse_glow(ring_mat, 1.6, 0.7, pulse_t + float(c.get("idx", 0)), 2.5)
		# XR: pinch near a chest opens it.
		if ARUpgradeKit.is_xr_active():
			if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
				_try_open_chest_at(pp, 1.3)


func _try_open_chest_at(pp: Vector3, range: float) -> void:
	var best_c: Dictionary = {}
	var best_d := range
	for c in chests:
		if bool(c.get("opened", false)):
			continue
		var d: float = pp.distance_to((c.get("node") as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_c = c
	if not best_c.is_empty():
		_open_chest(best_c)


func _open_chest(c: Dictionary) -> void:
	c["opened"] = true
	var node: Node3D = c.get("node")
	var ring: Node3D = c.get("ring")
	if ring != null:
		ring.visible = false
	var gain := randi_range(2, 4)
	pearls += gain
	log_pearls_total += gain
	var at: Vector3 = node.global_position + Vector3(0, 0.5, 0)
	GraphicsPolish.spawn_sparks(self, at, Color(1.0, 0.8, 0.25), 36)
	GraphicsPolish.spawn_confetti(self, at, 30)
	# A pearl rises out of the chest.
	var pearl := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	pearl.mesh = sph
	pearl.material_override = GraphicsPolish.glow(Color(1.0, 0.95, 0.85), 2.2)
	pearl.position = at
	add_child(pearl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pearl, "position", at + Vector3(0, 1.2, 0), 1.4).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(pearl.queue_free)
	Haptics.tick()
	_set_msg("TREASURE! +%d pearls" % gain, 1.8)
	_save_log()
	var opened := 0
	for c2 in chests:
		if bool(c2.get("opened", false)):
			opened += 1
	if opened >= CHEST_COUNT:
		_win_dive()


func _win_dive() -> void:
	state = "win"
	log_dives += 1
	if pearls > log_best:
		log_best = pearls
	_save_log()
	var pp := _player_pos()
	GraphicsPolish.spawn_confetti(self, pp + Vector3(0, 0.8, -1), 90)
	GraphicsPolish.spawn_sparks(self, pp + Vector3(0, 0.5, -1), Color(1.0, 0.85, 0.4), 50)
	_set_msg("DIVE COMPLETE! %d pearls\nR to dive again" % pearls, 60.0)
	_update_hud()


func _update_sharks(delta: float) -> void:
	var pp := _player_pos()
	for s in sharks:
		var node: Node3D = s.get("node")
		var wps: Array = s.get("wps")
		var flee: float = float(s.get("flee", 0.0))
		var speed: float = float(s.get("speed", 0.8))
		var target: Vector3 = wps[int(s.get("wp_i", 1)) % wps.size()]
		if flee > 0.0:
			s["flee"] = flee - delta
			target = node.global_position + (node.global_position - pp).normalized() * 3.0
			speed = 2.2
		var to: Vector3 = target - node.global_position
		if to.length() < 0.5 and flee <= 0.0:
			s["wp_i"] = (int(s.get("wp_i", 1)) + 1) % wps.size()
		var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
		node.global_position += dir * speed * delta
		node.global_position = ARUpgradeKit.clamp_to_room(node.global_position, 0.5)
		if dir.length() > 0.01:
			var want := Basis.looking_at(dir, Vector3.UP)
			node.global_transform.basis = node.global_transform.basis.slerp(want, minf(delta * 3.0, 1.0))
		# Tail sway.
		s["sway"] = float(s.get("sway", 0.0)) + delta * 4.0
		node.rotation.z = sin(float(s.get("sway"))) * 0.12
		# Bite + near-miss.
		s["bite_cd"] = maxf(0.0, float(s.get("bite_cd", 0.0)) - delta)
		s["warn_cd"] = maxf(0.0, float(s.get("warn_cd", 0.0)) - delta)
		var d: float = node.global_position.distance_to(pp)
		if d < SHARK_BITE_RANGE and float(s.get("bite_cd")) <= 0.0 and flee <= 0.0:
			s["bite_cd"] = 3.0
			s["flee"] = 1.6
			air = maxf(0.0, air - 25.0)
			shake_camera(0.5)
			Haptics.pulse(1.0, 0.3)
			GraphicsPolish.spawn_sparks(self, pp, Color(1.0, 0.2, 0.15), 24)
			_set_msg("SHARK BITE! -25 air", 1.6)
			low_air_warned = false
		elif d < SHARK_WARN_RANGE and float(s.get("warn_cd")) <= 0.0 and flee <= 0.0:
			s["warn_cd"] = 4.0
			Haptics.tick()
			_set_msg("Shark nearby — keep clear!", 1.4)


func shake_camera(amount: float) -> void:
	if camera != null:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * amount * 0.15


func _update_critters(delta: float) -> void:
	# Jellyfish drift + pulse.
	for j in jellies:
		var node: Node3D = j.get("node")
		j["ph"] = float(j.get("ph", 0.0)) + delta * 1.6
		var ph: float = j.get("ph")
		node.position.y = float(j.get("base_y", 1.8)) + sin(ph * 0.7) * 0.25
		node.rotation.y += delta * 0.3
		var s := 1.0 + sin(ph) * 0.12
		node.scale = Vector3(s, 2.0 - s, s).normalized() * (1.0 + sin(ph) * 0.06)
		var tents: Array = node.get_meta("tents", [])
		for ti in tents.size():
			var t: MeshInstance3D = tents[ti]
			t.rotation.x = sin(ph * 1.3 + float(ti)) * 0.25
	# Fish schools circle.
	for sc in schools:
		sc["t"] = float(sc.get("t", 0.0)) + delta * float(sc.get("speed", 0.5))
		var t: float = sc.get("t")
		var center: Vector3 = sc.get("center")
		for f in sc.get("fishes"):
			var fn: Node3D = f.get("node")
			var a: float = t + float(f.get("off", 0.0))
			var r: float = f.get("r")
			fn.position = center + Vector3(cos(a) * r, float(f.get("y", 0.0)) + sin(t * 2.0 + a) * 0.08, sin(a) * r)
			var tangent := Vector3(-sin(a), 0, cos(a))
			fn.global_transform.basis = Basis.looking_at(tangent, Vector3.UP)
	# God-ray shimmer.
	for r in rays:
		var mat: StandardMaterial3D = r.get("mat")
		if mat != null:
			var c: Color = mat.albedo_color
			c.a = 0.08 + 0.035 * sin(pulse_t * 0.8 + float(r.get("ph", 0.0)))
			mat.albedo_color = c


func _update_air(delta: float) -> void:
	var pp := _player_pos()
	var at_vent := false
	for v in vents:
		if pp.distance_to((v.get("node") as Node3D).global_position + Vector3(0, 0.5, 0)) < 1.1:
			at_vent = true
			break
	if at_vent:
		air = minf(AIR_MAX, air + VENT_REFILL * delta)
		if randf() < delta * 6.0:
			GraphicsPolish.spawn_sparks(self, pp + Vector3(0, 0.3, 0), Color(0.6, 0.95, 1.0), 3)
	else:
		air = maxf(0.0, air - AIR_DRAIN * delta)
	if air < 25.0 and not low_air_warned:
		low_air_warned = true
		_set_msg("LOW AIR — find a bubble vent!", 2.0)
		Haptics.pulse(0.6, 0.2)
	if air >= 40.0:
		low_air_warned = false
	if air <= 0.0:
		# Blackout: resurface, lose pearls.
		air = 60.0
		pearls = maxi(0, pearls - 2)
		global_position = Vector3(0, 1.4, 1.2)
		vel = Vector3.ZERO
		if camera != null:
			camera.position = cam_base
		shake_camera(0.8)
		Haptics.pulse(1.0, 0.4)
		_set_msg("OUT OF AIR! Resurfaced (-2 pearls)", 2.5)


func _restart() -> void:
	air = AIR_MAX
	pearls = 0
	vel = Vector3.ZERO
	state = "play"
	low_air_warned = false
	global_position = Vector3(0, 1.4, 1.2)
	for c in chests:
		c["opened"] = false
		var ring: Node3D = c.get("ring")
		if ring != null:
			ring.visible = true
	_set_msg("DIVE START — find 5 treasure chests", 3.0)
	_update_hud()


func _load_log() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DIVE_FILE) == OK:
		log_dives = int(cfg.get_value("dive", "dives", 0))
		log_pearls_total = int(cfg.get_value("dive", "pearls_total", 0))
		log_best = int(cfg.get_value("dive", "best_pearls", 0))
		log_opened = cfg.get_value("dive", "chests_opened", [])


func _save_log() -> void:
	var opened: Array = []
	for c in chests:
		opened.append(bool(c.get("opened", false)))
	var cfg := ConfigFile.new()
	cfg.set_value("dive", "dives", log_dives)
	cfg.set_value("dive", "pearls_total", log_pearls_total)
	cfg.set_value("dive", "best_pearls", log_best)
	cfg.set_value("dive", "chests_opened", opened)
	cfg.save(DIVE_FILE)
