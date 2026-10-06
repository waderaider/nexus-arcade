## Myth Zoo: collect and care for 6 mythical creatures in AR habitats.
## Each habitat is a themed mini-diorama (volcano, pond, aerie, meadow, grove,
## tidepool) anchored in your room and persisting across sessions. Creatures
## start as mystery eggs: FEED the right food, CLEAN with wipe gestures, and
## PLAY follow-the-hand to raise happiness. At 100% the creature reveals and
## joins the collection log (silhouettes for the undiscovered).
## Progress persists in user://nexus_zoo.cfg.
## Desktop: click eggs/habitats/buttons, drag to wipe, move mouse to play.
## XR: pinch eggs/buttons/foods, wipe with hand, guide with hand.
extends Node3D

const SAVE_PATH := "user://nexus_zoo.cfg"
const MODEL_DIR := "res://assets/models/myth_zoo/"
const HAB_RADIUS := 2.3

const FOODS := [
	{"name": "Sunberry", "color": Color(1.0, 0.3, 0.15)},
	{"name": "Moonmelon", "color": Color(0.55, 0.8, 1.0)},
	{"name": "Starfruit", "color": Color(1.0, 0.9, 0.3)},
	{"name": "Honeydrop", "color": Color(1.0, 0.65, 0.15)},
	{"name": "Cloudcake", "color": Color(0.95, 0.95, 1.0)},
	{"name": "Emberpepper", "color": Color(1.0, 0.45, 0.1)},
]

const CREATURES := [
	{"id": "phoenix", "name": "Phoenix", "model": "animal-parrot.glb",
		"accent": Color(1.0, 0.45, 0.12), "food": 0, "theme": "volcano",
		"blurb": "Reborn in flame every dawn."},
	{"id": "kelpie", "name": "Kelpie", "model": "animal-deer.glb",
		"accent": Color(0.25, 0.7, 1.0), "food": 1, "theme": "pond",
		"blurb": "A shy water-horse of the mist."},
	{"id": "griffin", "name": "Griffin", "model": "animal-lion.glb",
		"accent": Color(1.0, 0.8, 0.25), "food": 2, "theme": "aerie",
		"blurb": "King of sky and stone."},
	{"id": "jackalope", "name": "Jackalope", "model": "animal-bunny.glb",
		"accent": Color(0.5, 1.0, 0.4), "food": 3, "theme": "meadow",
		"blurb": "Sings to the moon hares."},
	{"id": "kitsune", "name": "Kitsune", "model": "animal-fox.glb",
		"accent": Color(0.7, 0.5, 1.0), "food": 4, "theme": "grove",
		"blurb": "Nine tails, one trickster."},
	{"id": "kraken", "name": "Kraken Tot", "model": "animal-crab.glb",
		"accent": Color(0.65, 0.35, 1.0), "food": 5, "theme": "tidepool",
		"blurb": "Small now. Dreaming deep."},
]

var camera: Camera3D = null
var env_ref: Environment = null
var rng := RandomNumberGenerator.new()
var pulse_t := 0.0
var day_t := 0.3

var habitats: Array = [] # dicts: {def, node, egg, creature, happy, revealed, food_known, ring, anchor_id}
var selected := -1
var panel: Node3D = null
var panel_hab := -1
var clickables: Array = []
var panel_clickables: Array = []
var selectables: Array = []
var log_slots: Array = []

var care_mode := "" # "", "feed", "clean", "play"
var feed_items: Array = []
var dirt_spots: Array = []
var dirt_node: Node3D = null
var clean_t := 0.0
var play_orb: Node3D = null
var play_t := 0.0
var play_score := 0.0
var play_center := Vector3.ZERO

var toast_label: Label3D = null
var toast_t := 0.0
var xr_prev_pinch := false


func _ready() -> void:
	rng.randomize()
	ARUpgradeKit.apply_anchor(self, "myth_zoo_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_build_ground()
	_build_habitats()
	_load_progress()
	_refresh_all_habitats()
	_build_log_board()
	_build_hud()
	_toast("Welcome to the Myth Zoo! Tap a mystery egg.", 3.5)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.65, 0.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -1.6), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	env_ref = Environment.new()
	env_ref.background_mode = Environment.BG_COLOR
	env_ref.background_color = Color(0.03, 0.05, 0.09)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.ambient_light_color = Color(0.4, 0.5, 0.65)
	env_ref.ambient_light_energy = 0.85
	env_ref.fog_enabled = true
	env_ref.fog_light_color = Color(0.03, 0.06, 0.1)
	env_ref.fog_density = 0.03
	env_ref.glow_enabled = true
	env_ref.glow_intensity = 1.0
	var we := WorldEnvironment.new()
	we.environment = env_ref
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


# ---------------------------------------------------------------- helpers ---

func _load_model(fname: String) -> Node3D:
	var ps: PackedScene = load(MODEL_DIR + fname) as PackedScene
	if ps == null:
		return null
	return (ps.instantiate() as Node3D)


func _mi(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	return m


func _box(sx: float, sy: float, sz: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return _mi(b, mat, pos)


func _cyl(r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	return _mi(c, mat, pos)


func _sph(r: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return _mi(s, mat, pos)


func _lbl(text: String, size: int, color: Color, pos: Vector3, px: float = 0.004) -> Label3D:
	var l := GraphicsPolish.make_label(text, size, color)
	l.position = pos
	l.pixel_size = px
	return l


func _toast(text: String, dur: float = 2.5) -> void:
	if toast_label != null:
		toast_label.text = text
		toast_t = dur


func _rising_particles(parent: Node3D, pos: Vector3, color: Color, amount: int = 24, speed: float = 0.5, spread: float = 20.0, scale_max: float = 0.05) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.015
	pm.scale_max = scale_max
	pm.color = color
	p.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	dot.material = GraphicsPolish.glow(Color(1, 1, 1), 1.6)
	p.draw_pass_1 = dot
	parent.add_child(p)
	return p


func _pointer_world() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, 1.0)
	var hit = plane.intersects_ray(ro, rd)
	if hit == null:
		return ro + rd * 2.0
	return hit


# ------------------------------------------------------------------ zoo ----

func _build_ground() -> void:
	var disc := _cyl(3.6, 3.6, 0.1, GraphicsPolish.pbr(Color(0.1, 0.13, 0.12), 0.2, 0.8), Vector3(0, -0.05, 0))
	add_child(disc)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.03
	tor.outer_radius = 3.4
	rim.mesh = tor
	rim.material_override = GraphicsPolish.glow(Color(0.4, 0.9, 0.6), 0.9)
	rim.position = Vector3(0, 0.02, 0)
	rim.rotation_degrees.x = 90.0
	add_child(rim)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, 0), 3.2, 40)


func _build_habitats() -> void:
	for i in CREATURES.size():
		var def: Dictionary = CREATURES[i]
		var ang := deg_to_rad(90.0 - float(i) * 60.0)
		var hab_node := Node3D.new()
		hab_node.name = "hab_" + str(def["id"])
		hab_node.position = Vector3(cos(ang) * HAB_RADIUS, 0, sin(ang) * HAB_RADIUS)
		add_child(hab_node)
		var anchor_id := "myth_zoo_hab_" + str(def["id"])
		if not ARUpgradeKit.apply_anchor(hab_node, anchor_id):
			ARUpgradeKit.save_anchor(anchor_id, hab_node.global_transform)
		var rec := {
			"def": def, "node": hab_node, "idx": i,
			"egg": null, "creature": null, "happy": 0.0,
			"revealed": false, "food_known": false,
			"ring": null, "name_label": null, "anchor_id": anchor_id,
		}
		habitats.append(rec)
		_build_habitat_diorama(rec)
		hab_node.rotation.y = -ang + PI * 0.5 + PI


func _build_habitat_diorama(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var n: Node3D = rec["node"]
	var accent: Color = def["accent"]
	var theme := str(def["theme"])
	# Base disc.
	var base_col := Color(0.16, 0.14, 0.13)
	match theme:
		"pond", "tidepool":
			base_col = Color(0.12, 0.16, 0.2)
		"meadow", "grove":
			base_col = Color(0.12, 0.18, 0.12)
	n.add_child(_cyl(0.62, 0.68, 0.14, GraphicsPolish.pbr(base_col, 0.1, 0.8), Vector3(0, 0.07, 0)))
	# Selection ring.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.025
	tor.outer_radius = 0.68
	ring.mesh = tor
	ring.material_override = GraphicsPolish.glow(accent, 0.4)
	ring.position = Vector3(0, 0.16, 0)
	ring.rotation_degrees.x = 90.0
	n.add_child(ring)
	rec["ring"] = ring
	match theme:
		"volcano":
			_add_prop(n, "stone_tallA.glb", Vector3(-0.4, 0.1, -0.25), 1.1, 30.0)
			_add_prop(n, "stone_tallB.glb", Vector3(0.38, 0.1, -0.3), 0.9, -20.0)
			_add_prop(n, "stone_tallC.glb", Vector3(0.05, 0.1, 0.42), 0.7, 70.0)
			n.add_child(_cyl(0.3, 0.34, 0.06, GraphicsPolish.glow(Color(1.0, 0.4, 0.08), 2.2), Vector3(0, 0.16, 0)))
			_rising_particles(n, Vector3(0, 0.25, 0), Color(1.0, 0.5, 0.15, 0.9), 26, 0.7, 25.0)
			GraphicsPolish.make_point_light(n, Vector3(0, 0.7, 0), Color(1.0, 0.45, 0.15), 1.0, 3.0)
		"pond":
			n.add_child(_cyl(0.5, 0.5, 0.05, GraphicsPolish.pbr(Color(0.15, 0.45, 0.65), 0.0, 0.15), Vector3(0, 0.15, 0)))
			_add_prop(n, "lily_large.glb", Vector3(-0.22, 0.16, 0.1), 1.0, 0.0)
			_add_prop(n, "lily_large.glb", Vector3(0.25, 0.16, -0.15), 0.8, 90.0)
			_add_prop(n, "stone_tallB.glb", Vector3(0.42, 0.1, 0.3), 0.55, 40.0)
			_rising_particles(n, Vector3(0, 0.3, 0), Color(0.7, 0.85, 1.0, 0.5), 18, 0.25, 14.0, 0.09)
			GraphicsPolish.make_point_light(n, Vector3(0, 0.7, 0), Color(0.35, 0.65, 1.0), 0.8, 3.0)
		"aerie":
			_add_prop(n, "stone_tallC.glb", Vector3(0, 0.1, -0.1), 1.5, 0.0)
			var nest := MeshInstance3D.new()
			var ntor := TorusMesh.new()
			ntor.inner_radius = 0.14
			ntor.outer_radius = 0.3
			nest.mesh = ntor
			nest.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
			nest.position = Vector3(0, 0.85, -0.1)
			nest.rotation_degrees.x = 90.0
			n.add_child(nest)
			_rising_particles(n, Vector3(0, 1.0, -0.1), Color(1.0, 0.85, 0.4, 0.9), 20, 0.4, 30.0, 0.04)
			GraphicsPolish.make_point_light(n, Vector3(0, 1.2, -0.1), Color(1.0, 0.8, 0.4), 0.9, 3.0)
		"meadow":
			_add_prop(n, "grass_large.glb", Vector3(-0.3, 0.12, 0.15), 1.2, 0.0)
			_add_prop(n, "grass_large.glb", Vector3(0.3, 0.12, -0.1), 1.0, 120.0)
			_add_prop(n, "grass.glb", Vector3(0.05, 0.12, 0.35), 1.1, 60.0)
			_add_prop(n, "flower_redA.glb", Vector3(-0.15, 0.12, -0.3), 1.0, 0.0)
			_add_prop(n, "flower_yellowB.glb", Vector3(0.35, 0.12, 0.25), 1.0, 0.0)
			_add_prop(n, "flower_purpleC.glb", Vector3(-0.4, 0.12, -0.05), 1.0, 0.0)
			_rising_particles(n, Vector3(0, 0.5, 0), Color(0.8, 1.0, 0.4, 0.9), 16, 0.2, 40.0, 0.035)
			GraphicsPolish.make_point_light(n, Vector3(0, 0.7, 0), Color(0.6, 1.0, 0.5), 0.6, 3.0)
		"grove":
			_add_prop(n, "tree_pineDefaultA.glb", Vector3(-0.3, 0.1, -0.25), 0.85, 0.0)
			_add_prop(n, "mushroom_red.glb", Vector3(0.3, 0.12, 0.1), 1.0, 0.0)
			_add_prop(n, "mushroom_tan.glb", Vector3(0.42, 0.12, -0.2), 0.9, 0.0)
			_add_prop(n, "stone_tallA.glb", Vector3(0.1, 0.1, 0.4), 0.5, 200.0)
			_rising_particles(n, Vector3(0, 0.5, 0), Color(0.6, 0.5, 1.0, 0.85), 20, 0.35, 30.0, 0.045)
			GraphicsPolish.make_point_light(n, Vector3(0, 0.9, 0), Color(0.55, 0.45, 1.0), 0.9, 3.0)
		"tidepool":
			n.add_child(_cyl(0.42, 0.46, 0.05, GraphicsPolish.pbr(Color(0.15, 0.5, 0.6), 0.0, 0.12), Vector3(0, 0.15, 0)))
			_add_prop(n, "stone_tallB.glb", Vector3(-0.4, 0.1, -0.2), 0.7, 15.0)
			_add_prop(n, "stone_tallA.glb", Vector3(0.4, 0.1, 0.25), 0.55, 160.0)
			_add_prop(n, "mushroom_tan.glb", Vector3(0.05, 0.12, -0.38), 0.8, 0.0)
			_rising_particles(n, Vector3(0, 0.25, 0), Color(0.6, 0.85, 1.0, 0.8), 22, 0.5, 18.0, 0.05)
			GraphicsPolish.make_point_light(n, Vector3(0, 0.7, 0), Color(0.4, 0.7, 1.0), 0.8, 3.0)


func _add_prop(parent: Node3D, model: String, pos: Vector3, s: float, yaw: float) -> void:
	var m := _load_model(model)
	if m == null:
		return
	m.position = pos
	m.scale = Vector3.ONE * s
	m.rotation_degrees.y = yaw
	parent.add_child(m)


# ------------------------------------------------------- eggs & creatures ---

func _egg_spot(rec: Dictionary) -> Vector3:
	var theme := str((rec["def"] as Dictionary)["theme"])
	if theme == "aerie":
		return Vector3(0, 1.05, -0.1)
	return Vector3(0, 0.42, 0)


func _build_egg(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var n: Node3D = rec["node"]
	var accent: Color = def["accent"]
	var egg := Node3D.new()
	egg.position = _egg_spot(rec)
	var shell := _sph(0.16, GraphicsPolish.pbr(Color(0.92, 0.9, 0.86), 0.0, 0.35))
	shell.scale = Vector3(1.0, 1.28, 1.0)
	egg.add_child(shell)
	# Accent speckles + glow band.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		egg.add_child(_sph(0.022, GraphicsPolish.glow(accent, 1.8), Vector3(cos(a) * 0.13, -0.05 + float(i % 2) * 0.12, sin(a) * 0.13)))
	var band := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.012
	tor.outer_radius = 0.15
	band.mesh = tor
	band.material_override = GraphicsPolish.glow(accent, 1.6)
	band.rotation_degrees.x = 90.0
	egg.add_child(band)
	egg.set_meta("hab_idx", rec["idx"])
	egg.set_meta("wob", rng.randf_range(0.0, TAU))
	n.add_child(egg)
	rec["egg"] = egg
	selectables.append(egg)
	var q := _lbl("?", 90, Color(1, 1, 1), Vector3(0, 0.62, 0), 0.005)
	n.add_child(q)
	rec["qlabel"] = q


func _reveal_creature(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var n: Node3D = rec["node"]
	var accent: Color = def["accent"]
	var egg: Node3D = rec["egg"]
	if is_instance_valid(egg):
		GraphicsPolish.spawn_sparks(n, egg.position, Color(1, 1, 1), 20)
		selectables.erase(egg)
		egg.queue_free()
	if rec.has("qlabel") and is_instance_valid(rec["qlabel"]):
		(rec["qlabel"] as Node).queue_free()
	# Shell burst.
	for i in 8:
		var bit := _box(0.05, 0.04, 0.02, GraphicsPolish.pbr(Color(0.92, 0.9, 0.86), 0.0, 0.4))
		bit.position = _egg_spot(rec)
		n.add_child(bit)
		var tw := create_tween().set_parallel(true)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.5), rng.randf_range(-1, 1)).normalized()
		tw.tween_property(bit, "position", bit.position + dir * 0.5, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(bit, "scale", Vector3.ZERO, 0.7)
	# The creature itself: real Kenney model + mythic accents.
	var c := _load_model(str(def["model"]))
	if c == null:
		c = Node3D.new()
		c.add_child(_sph(0.2, GraphicsPolish.glow(accent, 1.2)))
	c.position = _egg_spot(rec)
	c.scale = Vector3.ONE * 0.55
	n.add_child(c)
	_add_creature_accents(c, str(def["id"]), accent)
	# Aura particles + light.
	_rising_particles(n, c.position + Vector3(0, 0.1, 0), Color(accent.r, accent.g, accent.b, 0.85), 20, 0.45, 35.0, 0.045)
	GraphicsPolish.make_point_light(n, c.position + Vector3(0, 0.6, 0), accent, 1.1, 3.0)
	c.set_meta("hab_idx", rec["idx"])
	c.set_meta("wander_a", rng.randf_range(0.0, TAU))
	rec["creature"] = c
	rec["revealed"] = true
	selectables.append(c)
	var nl := _lbl(str(def["name"]), 56, Color(1, 1, 1), Vector3(0, 1.55, 0), 0.005)
	n.add_child(nl)
	rec["name_label"] = nl
	_save_progress()
	_refresh_log_slot(rec["idx"])
	Haptics.pulse(1.0, 0.35)
	GraphicsPolish.spawn_confetti(n, c.position + Vector3(0, 0.5, 0), 60)
	_toast("✨ %s revealed! %s" % [str(def["name"]), str(def["blurb"])], 4.0)


func _add_creature_accents(c: Node3D, cid: String, accent: Color) -> void:
	var gm := GraphicsPolish.glow(accent, 2.2)
	match cid:
		"phoenix":
			for i in 3:
				var fl := _cyl(0.0, 0.035, 0.16, gm, Vector3(-0.07 + float(i) * 0.07, 0.42, -0.05))
				fl.rotation_degrees.x = -18.0
				c.add_child(fl)
		"kelpie":
			var fin := _box(0.02, 0.22, 0.12, gm, Vector3(0, 0.45, -0.1))
			fin.rotation_degrees.x = -25.0
			c.add_child(fin)
		"griffin":
			for sx in [-1.0, 1.0]:
				for i in 4:
					var f := _box(0.09, 0.015, 0.3 - float(i) * 0.04, GraphicsPolish.pbr(Color(0.95, 0.8, 0.4), 0.0, 0.5), Vector3((0.15 + float(i) * 0.07) * sx, 0.35, -0.15 + float(i) * 0.05))
					f.rotation_degrees.y = -15.0 * sx
					c.add_child(f)
		"jackalope":
			for sx in [-1.0, 1.0]:
				var ant := _cyl(0.012, 0.02, 0.18, GraphicsPolish.pbr(Color(0.9, 0.85, 0.7), 0.0, 0.5), Vector3(0.06 * sx, 0.42, 0.02))
				ant.rotation_degrees.z = -18.0 * sx
				c.add_child(ant)
				var t2 := _cyl(0.008, 0.012, 0.09, GraphicsPolish.pbr(Color(0.9, 0.85, 0.7), 0.0, 0.5), Vector3(0.1 * sx, 0.48, 0.02))
				t2.rotation_degrees.z = -55.0 * sx
				c.add_child(t2)
		"kitsune":
			for i in 2:
				var prev := Vector3(-0.12 - float(i) * 0.08, 0.12, -0.28)
				for j in 3:
					var seg := _sph(0.055 - float(j) * 0.012, GraphicsPolish.pbr(Color(0.95, 0.93, 1.0), 0.0, 0.4), prev + Vector3(-0.06, 0.05 - float(j) * 0.02, -0.05))
					c.add_child(seg)
					c.add_child(_sph(0.02, gm, seg.position + Vector3(0, 0.03, 0)))
					prev = seg.position
		"kraken":
			for i in 6:
				var a := TAU * float(i) / 6.0
				var spike := _cyl(0.0, 0.025, 0.12, gm, Vector3(cos(a) * 0.1, 0.3, sin(a) * 0.1))
				spike.rotation_degrees.z = -cos(a) * 30.0
				spike.rotation_degrees.x = sin(a) * 30.0
				c.add_child(spike)


func _refresh_all_habitats() -> void:
	for i in habitats.size():
		_refresh_habitat(i)


func _refresh_habitat(i: int) -> void:
	var rec: Dictionary = habitats[i]
	if bool(rec["revealed"]):
		if rec["creature"] == null:
			_reveal_creature(rec)
	else:
		if rec["egg"] == null:
			_build_egg(rec)
	_update_happy_bar(rec)


# ------------------------------------------------------------ care panel ---

func _select_habitat(i: int) -> void:
	selected = i
	panel_hab = i
	_build_panel()
	Haptics.tick()


func _deselect() -> void:
	selected = -1
	panel_hab = -1
	care_mode = ""
	_clear_panel()
	_clear_care_nodes()


func _build_panel() -> void:
	_clear_panel()
	_clear_care_nodes()
	care_mode = ""
	if panel_hab < 0:
		return
	var rec: Dictionary = habitats[panel_hab]
	var n: Node3D = rec["node"]
	panel = Node3D.new()
	panel.position = Vector3(0, 1.85, 0)
	n.add_child(panel)
	var def: Dictionary = rec["def"]
	var title := str(def["name"]) if bool(rec["revealed"]) else "Mystery Egg"
	panel.add_child(_lbl(title, 52, Color(1, 1, 1), Vector3(0, 0.42, 0), 0.0045))
	# Happiness bar.
	panel.add_child(_box(0.72, 0.1, 0.04, GraphicsPolish.pbr(Color(0.1, 0.1, 0.12), 0.2, 0.6), Vector3(0, 0.2, 0)))
	var fill := _box(0.66, 0.06, 0.05, GraphicsPolish.glow(Color(1.0, 0.4, 0.6), 1.6), Vector3(-0.33 + 0.66 * float(rec["happy"]) / 200.0, 0.2, 0))
	fill.scale.x = maxf(float(rec["happy"]) / 100.0, 0.02)
	fill.position.x = -0.33 + 0.33 * fill.scale.x
	panel.add_child(fill)
	panel.set_meta("happy_fill", fill)
	if not bool(rec["revealed"]):
		_make_panel_button("🍎 FEED", Vector3(-0.5, -0.05, 0), "feed")
		_make_panel_button("🧽 CLEAN", Vector3(0.0, -0.05, 0), "clean")
		_make_panel_button("🎾 PLAY", Vector3(0.5, -0.05, 0), "play")
	else:
		panel.add_child(_lbl("Happiness %d%% — fully bonded!" % int(rec["happy"]), 36, Color(0.7, 1.0, 0.8), Vector3(0, -0.05, 0), 0.0038))
	_make_panel_button("✖", Vector3(0.0, -0.32, 0), "close_panel")


func _make_panel_button(text: String, pos: Vector3, action: String) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	b.set_meta("action", action)
	b.add_child(_box(0.44, 0.14, 0.05, GraphicsPolish.pbr(Color(0.16, 0.35, 0.55), 0.3, 0.4)))
	b.add_child(_lbl(text, 36, Color(1, 1, 1), Vector3(0, 0, 0.035), 0.003))
	panel.add_child(b)
	clickables.append(b)
	panel_clickables.append(b)
	return b


func _clear_panel() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null
	for c in panel_clickables:
		clickables.erase(c)
	panel_clickables.clear()


func _clear_care_nodes() -> void:
	for f in feed_items:
		if is_instance_valid(f):
			clickables.erase(f)
			(f as Node).queue_free()
	feed_items.clear()
	if dirt_node != null and is_instance_valid(dirt_node):
		dirt_node.queue_free()
	dirt_node = null
	dirt_spots.clear()
	if play_orb != null and is_instance_valid(play_orb):
		play_orb.queue_free()
	play_orb = null


func _update_happy_bar(rec: Dictionary) -> void:
	if panel != null and is_instance_valid(panel) and panel_hab == int(rec["idx"]):
		_build_panel()


func _add_happiness(rec: Dictionary, amount: float) -> void:
	rec["happy"] = minf(float(rec["happy"]) + amount, 100.0)
	_update_happy_bar(rec)
	_save_progress()
	if float(rec["happy"]) >= 100.0 and not bool(rec["revealed"]):
		_reveal_creature(rec)
		_build_panel()


# ------------------------------------------------------------------ feed ---

func _start_feed() -> void:
	if care_mode != "":
		return
	care_mode = "feed"
	_clear_care_nodes()
	var rec: Dictionary = habitats[panel_hab]
	var n: Node3D = rec["node"]
	var def: Dictionary = rec["def"]
	var correct: int = def["food"]
	var opts := [correct]
	while opts.size() < 3:
		var c := rng.randi_range(0, 5)
		if not opts.has(c):
			opts.append(c)
	opts.shuffle()
	for i in opts.size():
		var fi: int = opts[i]
		var f := Node3D.new()
		f.position = Vector3(-0.55 + float(i) * 0.55, 1.0, 0.75)
		f.set_meta("action", "food_%d" % fi)
		var col: Color = FOODS[fi]["color"]
		f.add_child(_sph(0.09, GraphicsPolish.glow(col, 1.4)))
		f.add_child(_sph(0.035, GraphicsPolish.pbr(Color(0.3, 0.6, 0.3), 0.0, 0.6), Vector3(0, 0.1, 0)))
		f.add_child(_lbl(str(FOODS[fi]["name"]), 30, Color(1, 1, 1), Vector3(0, -0.2, 0), 0.0028))
		n.add_child(f)
		clickables.append(f)
		feed_items.append(f)
	var hint := "Offer a treat!"
	if bool(rec["food_known"]):
		hint = "Loves %s!" % str(FOODS[correct]["name"])
	_toast(hint, 2.5)


func _feed_pick(fi: int) -> void:
	if care_mode != "feed" or panel_hab < 0:
		return
	var rec: Dictionary = habitats[panel_hab]
	var def: Dictionary = rec["def"]
	var n: Node3D = rec["node"]
	var target := _egg_spot(rec)
	if bool(rec["revealed"]) and rec["creature"] != null:
		target = (rec["creature"] as Node3D).position
	if fi == int(def["food"]):
		rec["food_known"] = true
		_add_happiness(rec, 30.0)
		GraphicsPolish.spawn_sparks(n, target + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.8), 24)
		Haptics.tick()
		_toast("Yummy! %s loved it! +30" % str(FOODS[fi]["name"]), 2.0)
	else:
		_add_happiness(rec, 5.0)
		Haptics.thump()
		_toast("Sniffs... not a fan. +5", 2.0)
	care_mode = ""
	_clear_care_nodes()


# ------------------------------------------------------------------ clean ---

func _start_clean() -> void:
	if care_mode != "":
		return
	care_mode = "clean"
	_clear_care_nodes()
	var rec: Dictionary = habitats[panel_hab]
	var n: Node3D = rec["node"]
	var target: Node3D = rec["egg"] if not bool(rec["revealed"]) else rec["creature"]
	if target == null or not is_instance_valid(target):
		care_mode = ""
		return
	dirt_node = Node3D.new()
	target.add_child(dirt_node)
	dirt_spots.clear()
	for i in 5:
		var a := TAU * float(i) / 5.0
		var s := _sph(0.05, GraphicsPolish.pbr(Color(0.15, 0.12, 0.1), 0.0, 0.9), Vector3(cos(a) * 0.14, 0.05 + float(i % 2) * 0.12, sin(a) * 0.14))
		dirt_node.add_child(s)
		dirt_spots.append(s)
	clean_t = 0.0
	_toast("Wipe the dirt off — rub your hand over it!", 2.5)


func _clean_process(delta: float) -> void:
	if care_mode != "clean" or panel_hab < 0:
		return
	var rec: Dictionary = habitats[panel_hab]
	var target: Node3D = rec["egg"] if not bool(rec["revealed"]) else rec["creature"]
	if target == null or not is_instance_valid(target):
		return
	var pp := _pointer_world()
	if ARUpgradeKit.is_xr_active():
		pp = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	clean_t -= delta
	if target.global_position.distance_to(pp) < 0.32 and clean_t <= 0.0 and not dirt_spots.is_empty():
		clean_t = 0.35
		var s: Node3D = dirt_spots.pop_back()
		GraphicsPolish.spawn_sparks(self, s.global_position, Color(0.9, 0.9, 1.0), 8)
		Haptics.tick()
		s.queue_free()
		if dirt_spots.is_empty():
			_add_happiness(rec, 25.0)
			_toast("Sparkling clean! +25", 2.0)
			care_mode = ""
			_clear_care_nodes()


# ------------------------------------------------------------------- play ---

func _start_play() -> void:
	if care_mode != "":
		return
	care_mode = "play"
	_clear_care_nodes()
	var rec: Dictionary = habitats[panel_hab]
	var n: Node3D = rec["node"]
	play_center = n.global_position + Vector3(0, 0.9, 0)
	play_t = 12.0
	play_score = 0.0
	play_orb = Node3D.new()
	play_orb.add_child(_sph(0.07, GraphicsPolish.glow(Color(1.0, 0.9, 0.4), 2.2)))
	play_orb.add_child(GraphicsPolish.make_trail(Color(1.0, 0.85, 0.4), 0.03))
	play_orb.position = play_center
	add_child(play_orb)
	_toast("Keep your hand on the golden orb!", 2.5)


func _play_process(delta: float) -> void:
	if care_mode != "play" or panel_hab < 0:
		return
	var rec: Dictionary = habitats[panel_hab]
	play_t -= delta
	var t := 12.0 - play_t
	var orb_pos := play_center + Vector3(sin(t * 1.4) * 0.55, sin(t * 2.3) * 0.18, cos(t * 1.1) * 0.55)
	if play_orb != null and is_instance_valid(play_orb):
		play_orb.global_position = orb_pos
	var pp := _pointer_world()
	if ARUpgradeKit.is_xr_active():
		pp = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if pp.distance_to(orb_pos) < 0.3:
		play_score += delta
	# Creature hops toward the orb.
	var c: Node3D = rec["creature"] if bool(rec["revealed"]) else rec["egg"]
	if c != null and is_instance_valid(c):
		var n: Node3D = rec["node"]
		var want: Vector3 = n.to_local(orb_pos)
		want.y = c.position.y
		var to: Vector3 = (want - c.position)
		if to.length() > 0.35:
			to = to.normalized() * 0.35
		c.position = c.position.lerp(c.position + to * 0.6, 0.1)
		c.position.y += absf(sin(t * 8.0)) * 0.02
	if play_t <= 0.0:
		var frac := clampf(play_score / 8.0, 0.0, 1.0)
		var gained := 12.0 + frac * 20.0
		_add_happiness(rec, gained)
		_toast("Playtime! +%.0f happiness" % gained, 2.0)
		Haptics.pulse(0.7, 0.2)
		care_mode = ""
		_clear_care_nodes()


# ---------------------------------------------------------- collection log ---

func _build_log_board() -> void:
	var board := Node3D.new()
	board.position = Vector3(0, 2.35, -3.1)
	add_child(board)
	board.add_child(_box(2.7, 1.5, 0.08, GraphicsPolish.pbr(Color(0.08, 0.1, 0.14), 0.3, 0.6)))
	board.add_child(_lbl("📖 COLLECTION LOG", 56, Color(1.0, 0.9, 0.5), Vector3(0, 0.62, 0.06), 0.005))
	for i in CREATURES.size():
		var def: Dictionary = CREATURES[i]
		var sx := -0.88 + float(i % 3) * 0.88
		var sy := 0.18 - float(i / 3) * 0.62
		var slot := Node3D.new()
		slot.position = Vector3(sx, sy, 0.06)
		slot.set_meta("action", "log_%d" % i)
		board.add_child(slot)
		slot.add_child(_box(0.78, 0.52, 0.04, GraphicsPolish.pbr(Color(0.12, 0.15, 0.2), 0.2, 0.6)))
		log_slots.append(slot)
		clickables.append(slot)
		_refresh_log_slot(i)


func _refresh_log_slot(i: int) -> void:
	if i >= log_slots.size():
		return
	var slot: Node3D = log_slots[i]
	for c in slot.get_children():
		if c.get_meta("logbit", false):
			c.queue_free()
	var rec: Dictionary = habitats[i]
	var def: Dictionary = rec["def"]
	var accent: Color = def["accent"]
	if bool(rec["revealed"]):
		var eggm := _sph(0.09, GraphicsPolish.glow(accent, 1.5), Vector3(-0.24, 0, 0))
		eggm.scale = Vector3(1, 1.25, 1)
		eggm.set_meta("logbit", true)
		slot.add_child(eggm)
		var nm := _lbl(str(def["name"]), 34, Color(1, 1, 1), Vector3(0.08, 0.08, 0.03), 0.0028)
		nm.set_meta("logbit", true)
		slot.add_child(nm)
		var hp := _lbl("%d%% ❤" % int(rec["happy"]), 30, Color(1.0, 0.6, 0.7), Vector3(0.08, -0.12, 0.03), 0.0026)
		hp.set_meta("logbit", true)
		slot.add_child(hp)
	else:
		var sil := _sph(0.09, GraphicsPolish.pbr(Color(0.03, 0.03, 0.05), 0.0, 0.9), Vector3(-0.24, 0, 0))
		sil.scale = Vector3(1, 1.25, 1)
		sil.set_meta("logbit", true)
		slot.add_child(sil)
		var q := _lbl("???", 38, Color(0.45, 0.5, 0.6), Vector3(0.08, 0.0, 0.03), 0.0032)
		q.set_meta("logbit", true)
		slot.add_child(q)


# ------------------------------------------------------------------- HUD ---

func _build_hud() -> void:
	add_child(_lbl("🦄 MYTH ZOO", 64, Color(0.7, 1.0, 0.8), Vector3(-2.9, 3.0, -1.2), 0.006))
	var hint := "Tap a mystery egg, then FEED / CLEAN / PLAY to 100% ❤"
	if ARUpgradeKit.is_xr_active():
		hint = "Pinch a mystery egg, then FEED / CLEAN / PLAY to 100% ❤"
	add_child(_lbl(hint, 34, Color(0.8, 0.87, 0.95), Vector3(-2.9, 2.72, -1.2), 0.004))
	toast_label = _lbl("", 52, Color(1.0, 0.9, 0.5), Vector3(0.0, 3.35, -2.6), 0.007)
	add_child(toast_label)


# ----------------------------------------------------------------- input ---

func _screen_pick(pos: Vector2, nodes: Array, max_px: float) -> Node3D:
	if camera == null:
		return null
	var best: Node3D = null
	var best_d := max_px
	for n in nodes:
		if not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var sp: Vector2 = camera.unproject_position((n as Node3D).global_position)
		var d := sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _xr_pick(nodes: Array, pp: Vector3, max_d: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_d
	for n in nodes:
		if not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var d: float = (n as Node3D).global_position.distance_to(pp)
		if d < best_d:
			best_d = d
			best = n
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_tap(mb.position)


func _tap(pos: Vector2) -> void:
	var b := _screen_pick(pos, clickables, 70.0)
	if b != null and b.has_meta("action"):
		_do_action(str(b.get_meta("action")))
		return
	var s := _screen_pick(pos, selectables, 60.0)
	if s != null and s.has_meta("hab_idx"):
		_select_habitat(int(s.get_meta("hab_idx")))
		return
	# Tapped empty space: close panel.
	if panel_hab >= 0:
		_deselect()


func _xr_process() -> void:
	if not ARUpgradeKit.is_xr_active():
		xr_prev_pinch = false
		return
	var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if pinching and not xr_prev_pinch:
		var b := _xr_pick(clickables, pp, 0.24)
		if b != null and b.has_meta("action"):
			_do_action(str(b.get_meta("action")))
		else:
			var s := _xr_pick(selectables, pp, 0.3)
			if s != null and s.has_meta("hab_idx"):
				_select_habitat(int(s.get_meta("hab_idx")))
	xr_prev_pinch = pinching


func _do_action(action: String) -> void:
	Haptics.tick()
	if action.begins_with("log_"):
		_ping_habitat(int(action.trim_prefix("log_")))
		return
	if action.begins_with("food_"):
		_feed_pick(int(action.trim_prefix("food_")))
		return
	match action:
		"feed":
			_start_feed()
		"clean":
			_start_clean()
		"play":
			_start_play()
		"close_panel":
			_deselect()


func _ping_habitat(i: int) -> void:
	if i < 0 or i >= habitats.size():
		return
	var rec: Dictionary = habitats[i]
	var ring: MeshInstance3D = rec["ring"]
	var tw := create_tween()
	var mat := ring.material_override as StandardMaterial3D
	tw.tween_method(func(v: float) -> void: mat.emission_energy_multiplier = v, 3.0, 0.4, 0.6)
	_select_habitat(i)


# ------------------------------------------------------------ persistence ---

func _save_progress() -> void:
	var cfg := ConfigFile.new()
	for rec in habitats:
		var d: Dictionary = rec
		var id := str((d["def"] as Dictionary)["id"])
		cfg.set_value("zoo", id + "_happy", float(d["happy"]))
		cfg.set_value("zoo", id + "_revealed", bool(d["revealed"]))
		cfg.set_value("zoo", id + "_foodknown", bool(d["food_known"]))
	cfg.save(SAVE_PATH)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for rec in habitats:
		var d: Dictionary = rec
		var id := str((d["def"] as Dictionary)["id"])
		d["happy"] = float(cfg.get_value("zoo", id + "_happy", 0.0))
		d["revealed"] = bool(cfg.get_value("zoo", id + "_revealed", false))
		d["food_known"] = bool(cfg.get_value("zoo", id + "_foodknown", false))


# ---------------------------------------------------------------- process ---

func _process(delta: float) -> void:
	pulse_t += delta
	_xr_process()
	# Day-cycle glow: slow drift through dawn/day/dusk/night ambience.
	day_t += delta / 150.0
	if day_t > 1.0:
		day_t -= 1.0
	if env_ref != null:
		env_ref.ambient_light_color = _day_color(day_t)
	# Toast fade.
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0 and toast_label != null:
			toast_label.text = ""
	# Eggs wobble; creatures idle-bob and wander.
	for i in habitats.size():
		var rec: Dictionary = habitats[i]
		var n: Node3D = rec["node"]
		var ring: MeshInstance3D = rec["ring"]
		if is_instance_valid(ring):
			var active := i == selected
			var mat := ring.material_override as StandardMaterial3D
			if mat != null:
				GraphicsPolish.pulse_glow(mat, 0.4 if not active else 1.8, 0.3 if not active else 0.8, pulse_t + float(i), 2.5)
		if not bool(rec["revealed"]) and rec["egg"] != null and is_instance_valid(rec["egg"]):
			var egg: Node3D = rec["egg"]
			var wob: float = egg.get_meta("wob")
			egg.rotation.z = sin(pulse_t * 2.6 + wob) * 0.1
			egg.position.y = _egg_spot(rec).y + absf(sin(pulse_t * 2.6 + wob)) * 0.03
		elif bool(rec["revealed"]) and rec["creature"] != null and is_instance_valid(rec["creature"]):
			var c: Node3D = rec["creature"]
			var wa: float = c.get_meta("wander_a") + delta * 0.25
			c.set_meta("wander_a", wa)
			if care_mode != "play" or panel_hab != i:
				var home := _egg_spot(rec)
				c.position = home + Vector3(cos(wa) * 0.18, absf(sin(pulse_t * 3.0 + wa)) * 0.05, sin(wa) * 0.18)
				c.rotation.y = -wa + PI * 0.5
	# Care modes.
	_clean_process(delta)
	_play_process(delta)


func _day_color(t: float) -> Color:
	# dawn -> day -> dusk -> night loop.
	var keys := [
		Color(0.55, 0.38, 0.5), Color(0.45, 0.55, 0.7),
		Color(0.6, 0.36, 0.38), Color(0.14, 0.2, 0.34),
	]
	var seg := t * 4.0
	var i := int(seg) % 4
	var f := seg - floorf(seg)
	return keys[i].lerp(keys[(i + 1) % 4], f)
