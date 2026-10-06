## Monster Lab: Frankenstein-style monster workshop.
## ASSEMBLE — drag body parts (heads/torsos/arms/legs/wings, 4 options each)
## from the shelves onto the slab sockets. ANIMATE — pull the lab lever timed
## to the charge-meter peak for maximum lightning power. TRAIN — three
## mini-games (smash targets = strength, fly rings = agility, match symbols =
## smarts) to raise your monster's stats. Build up to 3 monsters, kept in the
## gallery; progress persists in user://nexus_monster.cfg.
## Desktop: click-drag parts, click buttons/lever/targets. XR: pinch-grab parts,
## pinch lever and buttons, move hand through rings.
extends Node3D

const SAVE_PATH := "user://nexus_monster.cfg"
const MODEL_DIR := "res://assets/models/monster_lab/"
const CATS := ["head", "torso", "arms", "legs", "wings"]
const CAT_NAMES := {
	"head": "HEADS", "torso": "TORSOS", "arms": "ARMS",
	"legs": "LEGS", "wings": "WINGS",
}
const OPT_NAMES := {
	"head": ["Robot", "Beast", "Skull", "Cyclops"],
	"torso": ["Boiler", "Ribcage", "Reactor", "Barrel"],
	"arms": ["Claws", "Pistons", "Tentacles", "Blades"],
	"legs": ["Stompers", "Springs", "Wheels", "Spider"],
	"wings": ["Bat", "Feather", "Rotor", "Jetpack"],
}
const MONSTER_NAMES := ["VOLTZ", "GRIMM", "SPARK", "BOLTZ", "ZAPPER", "TESLA",
	"FRANK", "WATTY", "AMPER", "COILY", "SURGE", "JUICE"]
# Socket positions on the slab (monster lies flat, head away from player).
const SOCKETS := {
	"head": Vector3(0.0, 1.16, -2.02),
	"torso": Vector3(0.0, 1.10, -1.55),
	"arms": Vector3(0.0, 1.10, -1.55),
	"legs": Vector3(0.0, 1.06, -1.05),
	"wings": Vector3(0.0, 1.24, -1.55),
}
const CHARGE_SPEED := 85.0
const MAX_MONSTERS := 3

var camera: Camera3D = null
var cam_base := Vector3(0.0, 1.7, 1.7)
var phase := "assemble" # assemble | animate | train | game | gallery
var game := "" # smash | rings | match (only when phase == "game")
var rng := RandomNumberGenerator.new()

var draggables: Array = [] # Node3D parts on shelves
var shelf_units: Array = []
var clickables: Array = [] # Node3D buttons (meta "action")
var held_part: Node3D = null
var held_home := Vector3.ZERO
var drag_plane := Plane(Vector3.BACK, 0.0)
var xr_held := false
var xr_prev_pinch := false

var monster_root: Node3D = null
var snapped := {} # cat -> Node3D
var socket_rings := {}
var build_parts: Array = [] # chosen option idx per CATS order
var alive := false

var charge := 0.0
var charge_dir := 1.0
var charge_bar: MeshInstance3D = null
var charge_group: Node3D = null
var lever: Node3D = null
var lever_base_rot := Vector3.ZERO
var striking := false
var strike_t := 0.0
var strike_power := 0.0
var shake_t := 0.0
var flash: OmniLight3D = null

var tesla_tops: Array = []
var bolt_segs: Array = []
var bolt_t := 0.0
var arc_lights: Array = []
var blinkers: Array = []
var blink_t := 0.0
var rotor_refs: Array = []
var bubble_nodes: Array = []

var stat_str := 0.0
var stat_agi := 0.0
var stat_sma := 0.0
var power := 0.0
var monster_name := ""

var train_group: Node3D = null
var game_group: Node3D = null
var gallery_group: Node3D = null
var saved_monsters: Array = []

var title_label: Label3D = null
var phase_label: Label3D = null
var instr_label: Label3D = null
var stats_label: Label3D = null
var toast_label: Label3D = null
var toast_t := 0.0
var pulse_t := 0.0

# Mini-game state.
var smash_targets: Array = []
var smash_spawn_t := 0.0
var smash_done := 0
var smash_total := 8
var smash_hits := 0
var ring_nodes: Array = []
var ring_idx := 0
var ring_time := 0.0
var match_tiles: Array = []
var match_target := ""
var match_round := 0
var match_correct := 0
var match_symbols := ["▲", "●", "■", "★"]
var feed_t := 0.0


func _ready() -> void:
	rng.randomize()
	ARUpgradeKit.apply_anchor(self, "monster_lab_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_saved()
	_build_floor()
	_build_slab()
	_build_shelves()
	_build_lab_dressing()
	_build_teslas()
	_build_lever()
	_build_hud()
	_update_hud()


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		cam_base = camera.position
		return
	camera = Camera3D.new()
	camera.position = cam_base
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.1, -1.4), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.03, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.32, 0.45)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.05, 0.08)
	env.fog_density = 0.035
	env.glow_enabled = true
	env.glow_intensity = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.7)


# ---------------------------------------------------------------- helpers ---

func _load_model(fname: String) -> Node3D:
	var ps: PackedScene = load(MODEL_DIR + fname) as PackedScene
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate() as Node3D
	return inst


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


func _steel() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.55, 0.58, 0.62), 0.85, 0.35)


func _darkmetal() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.16, 0.17, 0.2), 0.7, 0.5)


func _copper() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.72, 0.38, 0.2), 0.9, 0.3)


func _bone() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.87, 0.82, 0.7), 0.0, 0.6)


func _skin_green() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.35, 0.62, 0.3), 0.0, 0.55)


func _toast(text: String, dur: float = 2.2) -> void:
	if toast_label != null:
		toast_label.text = text
		toast_t = dur


func _pointer_world() -> Vector3:
	# Mouse: ray from camera through cursor onto the y=1.2 work plane.
	if camera == null:
		return Vector3.ZERO
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, 1.2)
	var hit = plane.intersects_ray(ro, rd)
	if hit == null:
		return ro + rd * 2.0
	return hit


# ------------------------------------------------------- lab construction ---

func _build_floor() -> void:
	var disc := _cyl(4.6, 4.6, 0.12, GraphicsPolish.pbr(Color(0.09, 0.1, 0.13), 0.4, 0.7), Vector3(0, -0.06, -1.0))
	add_child(disc)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.03
	tor.outer_radius = 4.35
	rim.mesh = tor
	rim.material_override = GraphicsPolish.glow(Color(0.1, 0.7, 0.9), 1.2)
	rim.position = Vector3(0, 0.02, -1.0)
	rim.rotation_degrees.x = 90.0
	add_child(rim)
	# Hazard ring around the slab.
	var hz := MeshInstance3D.new()
	var hz_tor := TorusMesh.new()
	hz_tor.inner_radius = 0.035
	hz_tor.outer_radius = 1.05
	hz.mesh = hz_tor
	hz.material_override = GraphicsPolish.glow(Color(0.95, 0.75, 0.1), 1.0)
	hz.position = Vector3(0, 0.015, -1.5)
	hz.rotation_degrees.x = 90.0
	add_child(hz)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.6, -1.2), 3.0, 36)


func _build_slab() -> void:
	# The workbench slab: stone table with metal straps and glowing sockets.
	var slab := Node3D.new()
	slab.name = "Slab"
	slab.position = Vector3(0, 0, -1.5)
	add_child(slab)
	slab.add_child(_box(1.5, 0.18, 1.9, GraphicsPolish.pbr_preset(Color(0.32, 0.33, 0.36), "matte"), Vector3(0, 0.91, 0)))
	for sx in [-0.55, 0.55]:
		slab.add_child(_box(0.1, 0.18, 1.9, _darkmetal(), Vector3(sx, 0.91, 0)))
	for sz in [-0.7, 0.7]:
		for sx in [-0.6, 0.6]:
			slab.add_child(_box(0.16, 0.82, 0.16, _darkmetal(), Vector3(sx, 0.41, sz)))
	# Head rest + shackles for flavor.
	slab.add_child(_box(0.4, 0.1, 0.3, _darkmetal(), Vector3(0, 1.02, -0.55)))
	monster_root = Node3D.new()
	monster_root.name = "Monster"
	add_child(monster_root)
	# Socket glow rings.
	for cat in CATS:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.02
		tor.outer_radius = 0.14 if cat != "torso" else 0.24
		ring.mesh = tor
		var mat := GraphicsPolish.glow(Color(0.2, 0.85, 1.0), 1.6)
		ring.material_override = mat
		ring.position = SOCKETS[cat] + Vector3(0, 0.02, 0)
		ring.rotation_degrees.x = 90.0
		add_child(ring)
		socket_rings[cat] = {"node": ring, "mat": mat, "filled": false}
	# Drain grate under slab.
	var grate := _box(1.7, 0.02, 2.1, GraphicsPolish.pbr(Color(0.05, 0.06, 0.07), 0.6, 0.5), Vector3(0, 0.005, -1.5))
	add_child(grate)


func _build_shelves() -> void:
	# Two shelf units flanking the slab; 20 parts total on display.
	_add_shelf_unit(Vector3(-1.85, 0, -1.5), ["head", "torso"])
	_add_shelf_unit(Vector3(1.85, 0, -1.5), ["arms", "legs", "wings"])


func _add_shelf_unit(base: Vector3, cats: Array) -> void:
	var unit := Node3D.new()
	unit.position = base
	add_child(unit)
	shelf_units.append(unit)
	var wood := GraphicsPolish.pbr_preset(Color(0.3, 0.2, 0.12), "matte")
	for sx in [-0.75, 0.75]:
		unit.add_child(_box(0.08, 2.3, 0.5, _darkmetal(), Vector3(sx, 1.15, 0)))
	for i in cats.size():
		var cat: String = cats[i]
		var by := 0.75 + float(i) * 0.72
		unit.add_child(_box(1.6, 0.06, 0.5, wood, Vector3(0, by, 0)))
		var tag := _lbl(CAT_NAMES[cat], 40, Color(1.0, 0.85, 0.4), Vector3(0, by + 0.32, 0.1), 0.0035)
		unit.add_child(tag)
		for o in 4:
			var part := _build_part(cat, o)
			part.position = base + Vector3(-0.57 + float(o) * 0.38, by + 0.03, 0)
			part.set_meta("category", cat)
			part.set_meta("option", o)
			part.set_meta("home", part.position)
			part.set_meta("home_rot", part.rotation)
			add_child(part)
			draggables.append(part)
			var nm := _lbl(OPT_NAMES[cat][o], 26, Color(0.8, 0.85, 0.95), Vector3(0, -0.2, 0.12), 0.0028)
			part.add_child(nm)


func _build_lab_dressing() -> void:
	# Specimen tanks (Kenney factory hoppers) with bubbling liquid.
	_add_tank(Vector3(-2.5, 0, -2.1), "hopper-round.glb", Color(0.2, 1.0, 0.4))
	_add_tank(Vector3(2.5, 0, -2.1), "hopper-high-round.glb", Color(0.3, 0.7, 1.0))
	# Glass pipe run along the floor feeding the slab.
	_add_pipe("pipe-glass-large-long.glb", Vector3(-1.5, 0.12, -2.1), 0.0)
	_add_pipe("pipe-glass-large-long.glb", Vector3(1.5, 0.12, -2.1), 0.0)
	_add_pipe("pipe-glass-large-bend.glb", Vector3(-0.6, 0.12, -2.1), 90.0)
	_add_pipe("pipe-glass-large-bend.glb", Vector3(0.6, 0.12, -2.1), -90.0)
	_add_pipe("pipe-glass-large-valve.glb", Vector3(0.0, 0.12, -2.1), 0.0)
	# Lab machines along the back.
	_add_machine("machine.glb", Vector3(-1.7, 0, -3.1), 8.0)
	_add_machine("machine-window.glb", Vector3(0.0, 0, -3.2), 12.0)
	_add_machine("machine-fortified.glb", Vector3(1.7, 0, -3.1), 8.0)
	# Crates.
	_add_crate(Vector3(-3.1, 0, -0.6))
	_add_crate(Vector3(3.1, 0, -0.7))
	# Blinking status lights on the machines.
	for i in 3:
		var b := _sph(0.045, GraphicsPolish.glow(Color(1.0, 0.25, 0.2), 2.0), Vector3(-1.7 + float(i) * 1.7, 1.55, -2.95))
		add_child(b)
		blinkers.append(b)
	# Dramatic spotlight over the slab.
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 3.4, -1.2)
	add_child(spot)
	spot.look_at(Vector3(0, 1.0, -1.5), Vector3.UP)
	spot.light_color = Color(0.75, 0.9, 1.0)
	spot.light_energy = 3.2
	spot.spot_range = 7.0
	spot.spot_angle = 28.0
	spot.shadow_enabled = true
	# Flash light for lightning strikes.
	flash = OmniLight3D.new()
	flash.position = Vector3(0, 2.6, -1.5)
	flash.light_color = Color(0.85, 0.92, 1.0)
	flash.light_energy = 0.0
	flash.omni_range = 9.0
	add_child(flash)
	GraphicsPolish.make_point_light(self, Vector3(0, 2.2, -1.5), Color(0.5, 0.75, 1.0), 0.7, 6.0)


func _add_tank(pos: Vector3, model: String, liquid_color: Color) -> void:
	var tank := _load_model(model)
	if tank != null:
		tank.position = pos
		tank.scale = Vector3.ONE * 1.1
		add_child(tank)
	# Glowing liquid core + rising bubbles.
	var liquid := _cyl(0.3, 0.24, 0.55, GraphicsPolish.glow(liquid_color, 1.4), pos + Vector3(0, 0.55, 0))
	add_child(liquid)
	var bub := GPUParticles3D.new()
	bub.amount = 22
	bub.lifetime = 2.2
	bub.preprocess = 2.2
	bub.position = pos + Vector3(0, 0.35, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.color = Color(liquid_color.r, liquid_color.g, liquid_color.b, 0.8)
	bub.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	bub.draw_pass_1 = dot
	add_child(bub)
	bubble_nodes.append(bub)
	GraphicsPolish.make_point_light(self, pos + Vector3(0, 1.0, 0), liquid_color, 0.9, 3.5)
	# A preserved specimen silhouette floating inside.
	var spec := _sph(0.12, GraphicsPolish.pbr(Color(0.2, 0.5, 0.35), 0.0, 0.7), pos + Vector3(0, 0.62, 0))
	spec.scale = Vector3(1.0, 1.5, 1.0)
	add_child(spec)


func _add_pipe(model: String, pos: Vector3, yaw: float) -> void:
	var p := _load_model(model)
	if p == null:
		return
	p.position = pos
	p.rotation_degrees.y = yaw
	add_child(p)


func _add_machine(model: String, pos: Vector3, h: float) -> void:
	var m := _load_model(model)
	if m == null:
		return
	m.position = pos
	m.scale = Vector3.ONE * h * 0.12
	add_child(m)


func _add_crate(pos: Vector3) -> void:
	var c := _load_model("box-large.glb")
	if c == null:
		return
	c.position = pos + Vector3(0, 0.25, 0)
	c.rotation_degrees.y = rng.randf_range(0.0, 45.0)
	add_child(c)


func _build_teslas() -> void:
	for sx in [-1.0, 1.0]:
		var base_x: float = 1.5 * sx
		var coil := Node3D.new()
		coil.position = Vector3(base_x, 0, -2.3)
		add_child(coil)
		coil.add_child(_cyl(0.22, 0.28, 0.25, _darkmetal(), Vector3(0, 0.12, 0)))
		coil.add_child(_cyl(0.07, 0.07, 1.25, _copper(), Vector3(0, 0.85, 0)))
		for i in 3:
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.015
			tor.outer_radius = 0.13
			ring.mesh = tor
			ring.material_override = _copper()
			ring.position = Vector3(0, 0.55 + float(i) * 0.32, 0)
			ring.rotation_degrees.x = 90.0
			coil.add_child(ring)
		var top := _sph(0.13, _copper(), Vector3(0, 1.62, 0))
		coil.add_child(top)
		tesla_tops.append(coil.position + Vector3(0, 1.62, 0))
		var l := GraphicsPolish.make_point_light(coil, Vector3(0, 1.7, 0), Color(0.5, 0.7, 1.0), 0.0, 4.0)
		arc_lights.append(l)
	# Reusable jagged bolt segments (hidden unless arcing).
	var bolt_mat := GraphicsPolish.glow(Color(0.75, 0.9, 1.0), 3.0)
	for i in 16:
		var seg := _box(0.035, 1.0, 0.035, bolt_mat)
		seg.visible = false
		add_child(seg)
		bolt_segs.append(seg)


func _jagged_bolt(from: Vector3, to: Vector3, seg_offset: int) -> void:
	var n := 8
	var prev := from
	for i in n:
		var t := float(i + 1) / float(n)
		var p: Vector3 = from.lerp(to, t)
		if i < n - 1:
			p += Vector3(rng.randf_range(-0.09, 0.09), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.09, 0.09))
		var seg: MeshInstance3D = bolt_segs[(seg_offset + i) % bolt_segs.size()]
		seg.visible = true
		var mid: Vector3 = (prev + p) * 0.5
		var d: Vector3 = p - prev
		var ln := maxf(d.length(), 0.001)
		var dir := d / ln
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var b := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(1, ln, 1))
		seg.transform = Transform3D(b, mid)
		prev = p


func _hide_bolts() -> void:
	for s in bolt_segs:
		s.visible = false


func _build_lever() -> void:
	# The lightning lever: Kenney factory lever on a pedestal, right of slab.
	var ped := Node3D.new()
	ped.position = Vector3(1.15, 0, -0.35)
	add_child(ped)
	ped.add_child(_box(0.34, 0.9, 0.34, _darkmetal(), Vector3(0, 0.45, 0)))
	ped.add_child(_box(0.44, 0.08, 0.44, _steel(), Vector3(0, 0.94, 0)))
	lever = _load_model("lever-single.glb")
	if lever == null:
		lever = Node3D.new()
		lever.add_child(_cyl(0.05, 0.07, 0.5, _steel(), Vector3(0, 0.25, 0)))
		lever.add_child(_sph(0.07, GraphicsPolish.glow(Color(1.0, 0.3, 0.2), 1.5), Vector3(0, 0.52, 0)))
	lever.position = Vector3(1.15, 0.98, -0.35)
	lever_base_rot = lever.rotation
	add_child(lever)
	lever.set_meta("action", "lever")
	clickables.append(lever)
	var tag := _lbl("LIGHTNING LEVER", 40, Color(1.0, 0.85, 0.4), Vector3(1.15, 1.85, -0.35), 0.004)
	add_child(tag)
	# Charge meter group (hidden until animate phase).
	charge_group = Node3D.new()
	charge_group.position = Vector3(-1.15, 0, -0.35)
	add_child(charge_group)
	charge_group.add_child(_box(0.34, 1.3, 0.1, _darkmetal(), Vector3(0, 1.35, 0)))
	var fill := _box(0.24, 1.0, 0.06, GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 1.8), Vector3(0, 0.85, 0.03))
	charge_group.add_child(fill)
	charge_bar = fill
	charge_group.add_child(_lbl("CHARGE", 40, Color(1.0, 1.0, 1.0), Vector3(0, 2.15, 0), 0.004))
	charge_group.visible = false


# ------------------------------------------------------------ part models ---
# Chunky Kenney-style monster parts: layered primitives, bolts, glowing seams.

func _build_part(cat: String, opt: int) -> Node3D:
	match cat:
		"head":
			return [_build_head_robot(), _build_head_beast(), _build_head_skull(), _build_head_cyclops()][opt]
		"torso":
			return [_build_torso_boiler(), _build_torso_ribcage(), _build_torso_reactor(), _build_torso_barrel()][opt]
		"arms":
			return [_build_arms_claws(), _build_arms_pistons(), _build_arms_tentacles(), _build_arms_blades()][opt]
		"legs":
			return [_build_legs_stompers(), _build_legs_springs(), _build_legs_wheels(), _build_legs_spider()][opt]
		"wings":
			return [_build_wings_bat(), _build_wings_feather(), _build_wings_rotor(), _build_wings_jetpack()][opt]
	return Node3D.new()


func _eyes(parent: Node3D, color: Color, y: float, spread: float, r: float = 0.028) -> void:
	var mat := GraphicsPolish.glow(color, 2.2)
	for sx in [-1.0, 1.0]:
		parent.add_child(_sph(r, mat, Vector3(spread * sx, y, 0.085)))


func _bolts(parent: Node3D, w: float, y: float) -> void:
	for sx in [-1.0, 1.0]:
		parent.add_child(_cyl(0.02, 0.02, 0.06, _darkmetal(), Vector3(w * sx, y, 0)))
		var n := _sph(0.028, _steel(), Vector3((w + 0.03) * sx, y, 0))
		parent.get_child(parent.get_child_count() - 1).rotation_degrees.z = 90.0
		parent.add_child(n)


func _build_head_robot() -> Node3D:
	var p := Node3D.new()
	p.add_child(_box(0.2, 0.22, 0.2, _steel()))
	p.add_child(_box(0.22, 0.06, 0.22, _darkmetal(), Vector3(0, 0.12, 0)))
	p.add_child(_box(0.16, 0.07, 0.02, _darkmetal(), Vector3(0, -0.075, 0.1)))
	_eyes(p, Color(0.3, 1.0, 1.0), 0.02, 0.05)
	p.add_child(_cyl(0.012, 0.012, 0.14, _copper(), Vector3(0.06, 0.2, 0)))
	p.add_child(_sph(0.025, GraphicsPolish.glow(Color(1.0, 0.3, 0.2), 2.0), Vector3(0.06, 0.28, 0)))
	_bolts(p, 0.11, -0.02)
	return p


func _build_head_beast() -> Node3D:
	var p := Node3D.new()
	var skull := _sph(0.11, _skin_green())
	skull.scale = Vector3(1.0, 0.95, 1.05)
	p.add_child(skull)
	p.add_child(_box(0.12, 0.08, 0.12, _skin_green(), Vector3(0, -0.04, 0.1)))
	_eyes(p, Color(1.0, 0.2, 0.1), 0.03, 0.05)
	for sx in [-1.0, 1.0]:
		var horn := _cyl(0.0, 0.035, 0.14, _bone(), Vector3(0.09 * sx, 0.12, -0.02))
		horn.rotation_degrees.z = -28.0 * sx
		p.add_child(horn)
		for tx in [-1.0, 1.0]:
			p.add_child(_box(0.018, 0.035, 0.018, _bone(), Vector3(0.03 * tx + 0.02 * sx, -0.095, 0.16)))
	var brow := _box(0.2, 0.04, 0.06, _skin_green(), Vector3(0, 0.075, 0.08))
	p.add_child(brow)
	return p


func _build_head_skull() -> Node3D:
	var p := Node3D.new()
	var cr := _sph(0.105, _bone())
	cr.scale = Vector3(1.0, 1.05, 1.0)
	cr.position = Vector3(0, 0.03, 0)
	p.add_child(cr)
	p.add_child(_box(0.13, 0.07, 0.1, _bone(), Vector3(0, -0.07, 0.05)))
	for sx in [-1.0, 1.0]:
		p.add_child(_sph(0.032, GraphicsPolish.pbr(Color(0.02, 0.02, 0.03), 0.0, 0.9), Vector3(0.045 * sx, 0.03, 0.085)))
		p.add_child(_sph(0.012, GraphicsPolish.glow(Color(0.7, 1.0, 0.3), 1.6), Vector3(0.045 * sx, 0.03, 0.1)))
	for tx in [-1.0, 1.0]:
		p.add_child(_box(0.016, 0.03, 0.016, _bone(), Vector3(0.035 * tx, -0.115, 0.1)))
	return p


func _build_head_cyclops() -> Node3D:
	var p := Node3D.new()
	var hd := _sph(0.11, GraphicsPolish.pbr(Color(0.55, 0.4, 0.6), 0.0, 0.55))
	hd.scale = Vector3(1.0, 1.1, 0.95)
	p.add_child(hd)
	p.add_child(_sph(0.055, _bone(), Vector3(0, 0.02, 0.085)))
	p.add_child(_sph(0.028, GraphicsPolish.glow(Color(0.6, 0.2, 1.0), 2.4), Vector3(0, 0.02, 0.125)))
	p.add_child(_box(0.2, 0.035, 0.05, GraphicsPolish.pbr(Color(0.4, 0.28, 0.45), 0.0, 0.6), Vector3(0, 0.095, 0.07)))
	for sx in [-1.0, 1.0]:
		var spike := _cyl(0.0, 0.02, 0.09, _bone(), Vector3(0.07 * sx, 0.13, -0.03))
		spike.rotation_degrees.z = -20.0 * sx
		p.add_child(spike)
	return p


func _build_torso_boiler() -> Node3D:
	var p := Node3D.new()
	var body := _cyl(0.16, 0.16, 0.5, _steel())
	body.rotation_degrees.x = 90.0
	p.add_child(body)
	for i in 3:
		var band := _cyl(0.175, 0.175, 0.05, _copper())
		band.rotation_degrees.x = 90.0
		band.position = Vector3(0, 0, -0.16 + float(i) * 0.16)
		p.add_child(band)
	p.add_child(_cyl(0.05, 0.05, 0.1, _darkmetal(), Vector3(0, 0.18, 0.1)))
	var face := _cyl(0.045, 0.045, 0.02, _bone(), Vector3(0, 0.18, 0.16))
	face.rotation_degrees.x = 90.0
	p.add_child(face)
	p.add_child(_cyl(0.008, 0.008, 0.05, GraphicsPolish.glow(Color(1.0, 0.3, 0.2), 2.0), Vector3(0.01, 0.2, 0.16)))
	for i in 8:
		var a := TAU * float(i) / 8.0
		p.add_child(_sph(0.018, _darkmetal(), Vector3(cos(a) * 0.16, sin(a) * 0.16, 0.26)))
	return p


func _build_torso_ribcage() -> Node3D:
	var p := Node3D.new()
	var core := _box(0.24, 0.3, 0.42, GraphicsPolish.pbr(Color(0.25, 0.2, 0.22), 0.1, 0.7))
	p.add_child(core)
	for i in 4:
		var rib := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.02
		tor.outer_radius = 0.19
		rib.mesh = tor
		rib.material_override = _bone()
		rib.position = Vector3(0, 0.02, -0.15 + float(i) * 0.1)
		rib.scale = Vector3(1.0, 0.75, 1.0)
		p.add_child(rib)
	p.add_child(_cyl(0.045, 0.045, 0.5, _bone(), Vector3(0, 0, 0)))
	p.add_child(_sph(0.05, GraphicsPolish.glow(Color(0.5, 1.0, 0.4), 1.8), Vector3(0, -0.02, 0)))
	return p


func _build_torso_reactor() -> Node3D:
	var p := Node3D.new()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			p.add_child(_box(0.06, 0.34, 0.06, _darkmetal(), Vector3(0.13 * sx, 0, 0.19 * sy)))
	p.add_child(_box(0.32, 0.05, 0.44, _darkmetal(), Vector3(0, 0.19, 0)))
	p.add_child(_box(0.32, 0.05, 0.44, _darkmetal(), Vector3(0, -0.19, 0)))
	var core := _sph(0.11, GraphicsPolish.glow(Color(0.3, 0.8, 1.0), 2.6))
	core.scale = Vector3(1.0, 1.0, 1.5)
	p.add_child(core)
	for i in 3:
		var cable := _cyl(0.015, 0.015, 0.3, _copper(), Vector3(-0.16, -0.1 + float(i) * 0.1, 0))
		cable.rotation_degrees.z = 90.0
		p.add_child(cable)
	return p


func _build_torso_barrel() -> Node3D:
	var p := Node3D.new()
	var body := _sph(0.2, _copper())
	body.scale = Vector3(1.0, 0.9, 1.4)
	p.add_child(body)
	for i in 3:
		var band := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.018
		tor.outer_radius = 0.2
		band.mesh = tor
		band.material_override = _darkmetal()
		band.position = Vector3(0, 0, -0.18 + float(i) * 0.18)
		band.scale = Vector3(1.0, 0.92, 1.0)
		p.add_child(band)
	p.add_child(_cyl(0.05, 0.07, 0.12, _steel(), Vector3(0, 0.2, 0)))
	var valve := MeshInstance3D.new()
	var vtor := TorusMesh.new()
	vtor.inner_radius = 0.012
	vtor.outer_radius = 0.055
	valve.mesh = vtor
	valve.material_override = GraphicsPolish.glow(Color(1.0, 0.5, 0.1), 1.4)
	valve.position = Vector3(0, 0.3, 0)
	valve.rotation_degrees.x = 90.0
	p.add_child(valve)
	return p


func _pair_arms(build: Callable) -> Node3D:
	var p := Node3D.new()
	for sx in [-1.0, 1.0]:
		var arm: Node3D = build.call(sx)
		p.add_child(arm)
	return p


func _build_arms_claws() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var a := Node3D.new()
		a.position.x = 0.3 * sx
		a.add_child(_cyl(0.05, 0.06, 0.22, _steel(), Vector3(0.06 * sx, 0, 0)))
		var fa := _cyl(0.04, 0.05, 0.2, _darkmetal(), Vector3(0.2 * sx, 0, 0))
		fa.rotation_degrees.z = 90.0
		a.add_child(fa)
		for i in 3:
			var claw := _cyl(0.0, 0.022, 0.12, _steel(), Vector3(0.34 * sx, 0.05 - float(i) * 0.05, 0))
			claw.rotation_degrees.z = -90.0 * sx
			a.add_child(claw)
		a.add_child(_sph(0.055, _copper(), Vector3(0, 0, 0)))
		return a)


func _build_arms_pistons() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var a := Node3D.new()
		a.position.x = 0.3 * sx
		var up := _cyl(0.055, 0.055, 0.2, _darkmetal(), Vector3(0.05 * sx, 0, 0))
		up.rotation_degrees.z = 90.0
		a.add_child(up)
		var rod := _cyl(0.025, 0.025, 0.24, GraphicsPolish.pbr(Color(0.85, 0.87, 0.9), 0.95, 0.2), Vector3(0.22 * sx, 0, 0))
		rod.rotation_degrees.z = 90.0
		a.add_child(rod)
		a.add_child(_sph(0.06, _steel(), Vector3(0, 0, 0)))
		a.add_child(_box(0.1, 0.08, 0.08, _steel(), Vector3(0.36 * sx, 0, 0)))
		a.add_child(_sph(0.02, GraphicsPolish.glow(Color(1.0, 0.6, 0.1), 1.8), Vector3(0.36 * sx, 0.05, 0)))
		return a)


func _build_arms_tentacles() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var a := Node3D.new()
		a.position.x = 0.28 * sx
		var pm := GraphicsPolish.pbr(Color(0.45, 0.25, 0.55), 0.0, 0.5)
		var prev := Vector3.ZERO
		for i in 4:
			var seg := _sph(0.055 - float(i) * 0.01, pm, prev + Vector3(0.09 * sx, -0.02 * float(i), 0.01 * float(i)))
			a.add_child(seg)
			prev = seg.position
		for i in 3:
			a.add_child(_sph(0.014, GraphicsPolish.glow(Color(0.9, 0.5, 1.0), 1.5), prev + Vector3(0.05 * sx, 0.02 - float(i) * 0.025, 0.04)))
		return a)


func _build_arms_blades() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var a := Node3D.new()
		a.position.x = 0.3 * sx
		var arm := _cyl(0.05, 0.06, 0.2, _steel(), Vector3(0.05 * sx, 0, 0))
		arm.rotation_degrees.z = 90.0
		a.add_child(arm)
		var blade := _box(0.3, 0.09, 0.02, GraphicsPolish.pbr(Color(0.8, 0.83, 0.88), 0.95, 0.15), Vector3(0.3 * sx, 0, 0))
		a.add_child(blade)
		a.add_child(_box(0.3, 0.015, 0.022, GraphicsPolish.glow(Color(0.4, 0.9, 1.0), 2.0), Vector3(0.3 * sx, 0.05, 0)))
		a.add_child(_sph(0.055, _copper(), Vector3(0, 0, 0)))
		return a)


func _pair_legs(build: Callable) -> Node3D:
	var p := Node3D.new()
	for sx in [-1.0, 1.0]:
		var leg: Node3D = build.call(sx)
		p.add_child(leg)
	return p


func _build_legs_stompers() -> Node3D:
	return _pair_legs(func(sx: float) -> Node3D:
		var l := Node3D.new()
		l.position.x = 0.13 * sx
		l.add_child(_cyl(0.06, 0.07, 0.18, _steel(), Vector3(0, 0.1, 0)))
		l.add_child(_cyl(0.05, 0.06, 0.16, _darkmetal(), Vector3(0, -0.06, 0)))
		l.add_child(_box(0.13, 0.09, 0.24, _darkmetal(), Vector3(0, -0.17, 0.04)))
		l.add_child(_box(0.14, 0.03, 0.25, _steel(), Vector3(0, -0.2, 0.04)))
		return l)


func _build_legs_springs() -> Node3D:
	return _pair_legs(func(sx: float) -> Node3D:
		var l := Node3D.new()
		l.position.x = 0.13 * sx
		l.add_child(_cyl(0.06, 0.07, 0.14, _steel(), Vector3(0, 0.12, 0)))
		for i in 3:
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.012
			tor.outer_radius = 0.055 - float(i) * 0.005
			ring.mesh = tor
			ring.material_override = _copper()
			ring.position = Vector3(0, 0.0 - float(i) * 0.055, 0)
			ring.rotation_degrees.x = 90.0
			l.add_child(ring)
		l.add_child(_box(0.12, 0.06, 0.2, _steel(), Vector3(0, -0.18, 0.03)))
		return l)


func _build_legs_wheels() -> Node3D:
	return _pair_legs(func(sx: float) -> Node3D:
		var l := Node3D.new()
		l.position.x = 0.13 * sx
		l.add_child(_cyl(0.045, 0.045, 0.2, _steel(), Vector3(0, 0.05, 0)))
		var wheel := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.03
		tor.outer_radius = 0.09
		wheel.mesh = tor
		wheel.material_override = _darkmetal()
		wheel.position = Vector3(0, -0.1, 0)
		l.add_child(wheel)
		var hub := _cyl(0.035, 0.035, 0.05, _copper(), Vector3(0, -0.1, 0))
		hub.rotation_degrees.x = 90.0
		l.add_child(hub)
		return l)


func _build_legs_spider() -> Node3D:
	return _pair_legs(func(sx: float) -> Node3D:
		var l := Node3D.new()
		l.position.x = 0.13 * sx
		var pts := [Vector3(0, 0.12, 0), Vector3(0.08 * sx, 0.02, 0), Vector3(0.05 * sx, -0.12, 0), Vector3(0.1 * sx, -0.22, 0)]
		for i in 3:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d: Vector3 = b - a
			var dir := d.normalized()
			var up := Vector3.UP
			if absf(dir.dot(up)) > 0.95:
				up = Vector3.RIGHT
			var seg := _cyl(0.022, 0.028, d.length(), _darkmetal(), (a + b) * 0.5)
			seg.basis = Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5)
			l.add_child(seg)
			l.add_child(_sph(0.032, _steel(), a))
		return l)


func _build_wings_bat() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var w := Node3D.new()
		w.position = Vector3(0.15 * sx, 0.1, 0)
		var mem := _box(0.34, 0.02, 0.26, GraphicsPolish.pbr(Color(0.3, 0.15, 0.4), 0.0, 0.6), Vector3(0.2 * sx, 0.02, -0.02))
		w.add_child(mem)
		for i in 2:
			var strut := _cyl(0.012, 0.012, 0.36, _bone(), Vector3(0.19 * sx, 0.03, -0.08 + float(i) * 0.12))
			strut.rotation_degrees.z = 90.0
			strut.rotation_degrees.y = 12.0 * sx
			w.add_child(strut)
		w.add_child(_sph(0.02, GraphicsPolish.glow(Color(0.8, 0.3, 1.0), 1.6), Vector3(0.36 * sx, 0.03, -0.02)))
		return w)


func _build_wings_feather() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var w := Node3D.new()
		w.position = Vector3(0.15 * sx, 0.1, 0)
		for i in 5:
			var f := _box(0.07, 0.015, 0.3 - float(i) * 0.03, _bone(), Vector3((0.12 + float(i) * 0.055) * sx, 0.02, -0.1 + float(i) * 0.045))
			f.rotation_degrees.y = -18.0 * sx + float(i) * 6.0 * sx
			w.add_child(f)
		return w)


func _build_wings_rotor() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var w := Node3D.new()
		w.position = Vector3(0.15 * sx, 0.05, 0)
		w.add_child(_cyl(0.03, 0.04, 0.22, _steel(), Vector3(0, 0.08, 0)))
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 0.2, 0)
		var blade := _box(0.5, 0.015, 0.07, _darkmetal())
		rotor.add_child(blade)
		rotor.add_child(_box(0.07, 0.015, 0.5, _darkmetal()))
		rotor.add_child(_sph(0.035, GraphicsPolish.glow(Color(1.0, 0.5, 0.1), 1.8)))
		w.add_child(rotor)
		rotor_refs.append(rotor)
		return w)


func _build_wings_jetpack() -> Node3D:
	return _pair_arms(func(sx: float) -> Node3D:
		var w := Node3D.new()
		w.position = Vector3(0.16 * sx, 0.02, 0.12)
		w.add_child(_cyl(0.06, 0.07, 0.3, _steel(), Vector3(0, 0, 0)))
		w.add_child(_cyl(0.065, 0.065, 0.04, _copper(), Vector3(0, 0.17, 0)))
		var flame := _cyl(0.035, 0.0, 0.16, GraphicsPolish.glow(Color(0.4, 0.7, 1.0), 2.4), Vector3(0, -0.22, 0))
		w.add_child(flame)
		w.add_child(_box(0.02, 0.1, 0.08, GraphicsPolish.glow(Color(1.0, 0.6, 0.1), 1.4), Vector3(0.07 * sx, 0.05, 0)))
		return w)


# ------------------------------------------------------------------- HUD ---

func _build_hud() -> void:
	title_label = _lbl("⚡ MONSTER LAB", 64, Color(0.6, 0.95, 1.0), Vector3(-2.9, 2.95, -1.2), 0.006)
	add_child(title_label)
	phase_label = _lbl("", 44, Color(1.0, 0.85, 0.4), Vector3(-2.9, 2.68, -1.2), 0.005)
	add_child(phase_label)
	instr_label = _lbl("", 34, Color(0.8, 0.87, 0.95), Vector3(-2.9, 2.45, -1.2), 0.004)
	add_child(instr_label)
	stats_label = _lbl("", 36, Color(0.65, 1.0, 0.7), Vector3(1.35, 2.95, -1.2), 0.005)
	add_child(stats_label)
	toast_label = _lbl("", 52, Color(1.0, 0.9, 0.5), Vector3(0.0, 2.5, -2.6), 0.007)
	add_child(toast_label)


func _update_hud() -> void:
	if phase_label != null:
		phase_label.text = "PHASE: " + phase.to_upper() + (" / " + game.to_upper() if game != "" else "")
	if instr_label != null:
		match phase:
			"assemble":
				instr_label.text = "Drag parts from the shelves onto the glowing slab sockets"
			"animate":
				if striking:
					instr_label.text = "⚡ IT'S ALIVE!! ⚡"
				else:
					instr_label.text = "PULL the lever when the charge meter peaks!"
			"train":
				instr_label.text = "Train your monster, then FINISH & SAVE"
			"game":
				instr_label.text = _game_instr()
			"gallery":
				instr_label.text = "Your monster collection — build a new one anytime"
	if stats_label != null:
		if monster_name != "":
			stats_label.text = "%s\nSTR %d  AGI %d  SMA %d\nPWR %d" % [monster_name, int(stat_str), int(stat_agi), int(stat_sma), int(power)]
		else:
			stats_label.text = ""


func _game_instr() -> String:
	match game:
		"smash":
			return "SMASH the red targets! (%d/%d)" % [smash_done, smash_total]
		"rings":
			return "Guide your hand through the glowing rings! (%d/6)" % ring_idx
		"match":
			return "Pick the tile matching the big symbol! (%d/5)" % (match_round + 1)
	return ""


func _make_button(text: String, pos: Vector3, action: String, color: Color = Color(0.15, 0.45, 0.7)) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	b.set_meta("action", action)
	var plate := _box(0.52, 0.16, 0.06, GraphicsPolish.pbr(color, 0.3, 0.4))
	b.add_child(plate)
	var edge := _box(0.56, 0.03, 0.065, GraphicsPolish.glow(Color(0.5, 0.9, 1.0), 1.2), Vector3(0, 0.085, 0))
	b.add_child(edge)
	b.add_child(_lbl(text, 40, Color(1, 1, 1), Vector3(0, 0, 0.045), 0.0032))
	add_child(b)
	clickables.append(b)
	return b


func _clear_clickables() -> void:
	for c in clickables:
		if is_instance_valid(c):
			c.queue_free()
	clickables.clear()


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_press(mb.position)
			else:
				_mouse_release(mb.position)
	elif event is InputEventMouseMotion:
		if held_part != null:
			_drag_to((event as InputEventMouseMotion).position)


func _mouse_press(pos: Vector2) -> void:
	# Buttons first.
	var b := _screen_pick(pos, clickables, 70.0)
	if b != null:
		_do_action(str(b.get_meta("action")), b)
		return
	if phase == "assemble" and not alive:
		var p := _screen_pick(pos, draggables, 60.0)
		if p != null and not socket_filled(str(p.get_meta("category"))):
			_grab_part(p)
			return
	if phase == "game":
		_game_click(pos)


func _mouse_release(_pos: Vector2) -> void:
	if held_part != null:
		_try_snap(held_part)
		held_part = null


func _grab_part(p: Node3D) -> void:
	held_part = p
	held_home = p.position
	p.scale = Vector3.ONE
	if camera != null:
		drag_plane = Plane(camera.global_transform.basis.z, p.global_position)
	Haptics.tick()


func _drag_to(pos: Vector2) -> void:
	if camera == null or held_part == null:
		return
	var ro := camera.project_ray_origin(pos)
	var rd := camera.project_ray_normal(pos)
	var hit = drag_plane.intersects_ray(ro, rd)
	if hit != null:
		held_part.global_position = ARUpgradeKit.clamp_to_room(hit)


func socket_filled(cat: String) -> bool:
	return socket_rings.has(cat) and bool(socket_rings[cat]["filled"])


func _try_snap(p: Node3D) -> void:
	var cat := str(p.get_meta("category"))
	var target: Vector3 = SOCKETS[cat]
	var d: float = p.global_position.distance_to(to_global(target))
	if d < 0.42 and not socket_filled(cat):
		_snap_part(p, cat)
	else:
		# Return home with a soft tween.
		var tw := create_tween()
		tw.tween_property(p, "position", p.get_meta("home"), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _snap_part(p: Node3D, cat: String) -> void:
	if held_part == p:
		held_part = null
	draggables.erase(p)
	var target: Vector3 = SOCKETS[cat]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "position", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "rotation", Vector3.ZERO, 0.3)
	snapped[cat] = p
	socket_rings[cat]["filled"] = true
	var mat: StandardMaterial3D = socket_rings[cat]["mat"]
	mat.emission = Color(0.3, 1.0, 0.4)
	Haptics.tick()
	GraphicsPolish.spawn_sparks(self, to_global(target), Color(0.4, 1.0, 0.6), 18)
	_toast("%s snapped on!" % OPT_NAMES[cat][int(p.get_meta("option"))], 1.4)
	if snapped.size() >= CATS.size():
		alive = true
		_on_parts_snapped_record()
		await get_tree().create_timer(0.9).timeout
		_start_animate()


# XR hand handling: pinch-grab parts, pinch buttons/lever/targets.
func _xr_process(delta: float) -> void:
	if not ARUpgradeKit.is_xr_active():
		xr_prev_pinch = false
		return
	var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if pinching and not xr_prev_pinch:
		# Press: buttons first, then parts, then game targets.
		var b := _xr_pick(clickables, pp, 0.22)
		if b != null:
			_do_action(str(b.get_meta("action")), b)
		elif phase == "assemble" and not alive:
			var p := _xr_pick(draggables, pp, 0.3)
			if p != null and not socket_filled(str(p.get_meta("category"))):
				held_part = p
				held_home = p.position
				p.scale = Vector3.ONE
				Haptics.tick()
		elif phase == "game":
			_game_xr_press(pp)
	elif pinching and held_part != null:
		held_part.global_position = ARUpgradeKit.clamp_to_room(pp)
	elif not pinching and xr_prev_pinch:
		if held_part != null:
			_try_snap(held_part)
			held_part = null
	xr_prev_pinch = pinching


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


func _do_action(action: String, node: Node3D) -> void:
	Haptics.tick()
	match action:
		"lever":
			_pull_lever()
		"train_smash":
			_start_game("smash")
		"train_rings":
			_start_game("rings")
		"train_match":
			_start_game("match")
		"train_finish":
			_finish_and_save()
		"gallery_new":
			_reset_to_assemble()
		_:
			if action.begins_with("tile_"):
				_match_pick(int(action.trim_prefix("tile_")))


# ---------------------------------------------------------- phase: animate ---

func _start_animate() -> void:
	phase = "animate"
	charge = 0.0
	charge_dir = 1.0
	charge_group.visible = true
	_toast("Monster assembled! Charge the lightning!", 3.0)
	_update_hud()
	GraphicsPolish.spawn_confetti(self, Vector3(0, 1.8, -1.5), 40)


func _pull_lever() -> void:
	if phase != "animate" or striking:
		return
	strike_power = charge
	striking = true
	strike_t = 0.0
	shake_t = 1.0
	# Slam the lever down.
	var tw := create_tween()
	tw.tween_property(lever, "rotation:x", lever_base_rot.x - 0.7, 0.18)
	tw.tween_property(lever, "rotation:x", lever_base_rot.x, 0.6).set_delay(1.6)
	Haptics.thump()
	_toast("⚡ STRIKE! Power %d%%" % int(strike_power), 2.5)
	_update_hud()


func _strike_process(delta: float) -> void:
	strike_t += delta
	bolt_t -= delta
	# Flickering flash + arcs from both tesla coils to the slab.
	var flicker := 4.0 + sin(strike_t * 60.0) * 2.5 + sin(strike_t * 97.0) * 1.5
	flash.light_energy = maxf(flicker, 0.0) * maxf(1.0 - strike_t / 2.4, 0.0)
	if bolt_t <= 0.0:
		bolt_t = 0.08
		_hide_bolts()
		for i in tesla_tops.size():
			_jagged_bolt(tesla_tops[i], Vector3(rng.randf_range(-0.2, 0.2), 1.25, -1.55), i * 8)
			arc_lights[i].light_energy = 3.0
	else:
		for l in arc_lights:
			l.light_energy = maxf(l.light_energy - delta * 20.0, 0.0)
	# Monster twitches alive.
	for cat in snapped.keys():
		var p: Node3D = snapped[cat]
		if is_instance_valid(p):
			p.position = (SOCKETS[cat] as Vector3) + Vector3(rng.randf_range(-0.02, 0.02), absf(sin(strike_t * 30.0)) * 0.04, 0)
	if strike_t >= 2.4:
		_end_strike()


func _end_strike() -> void:
	striking = false
	_hide_bolts()
	flash.light_energy = 0.0
	for l in arc_lights:
		l.light_energy = 0.0
	charge_group.visible = false
	# Power sets the monster's base stats; timing near peak gives a bonus.
	power = clampf(strike_power, 5.0, 100.0)
	var base := 15.0 + power * 0.55
	stat_str = base + rng.randf_range(0.0, 10.0)
	stat_agi = base + rng.randf_range(0.0, 10.0)
	stat_sma = base + rng.randf_range(0.0, 10.0)
	monster_name = _unique_monster_name()
	monster_root.scale = Vector3.ONE * 1.06
	GraphicsPolish.spawn_confetti(self, Vector3(0, 2.0, -1.5), 80)
	Haptics.pulse(1.0, 0.4)
	if strike_power >= 90.0:
		_toast("PERFECT STRIKE! %s lives!" % monster_name, 3.0)
	elif strike_power >= 60.0:
		_toast("Strong strike! %s lives!" % monster_name, 3.0)
	else:
		_toast("Weak spark... %s twitches awake." % monster_name, 3.0)
	_start_train()


func _unique_monster_name() -> String:
	var taken := {}
	for m in saved_monsters:
		taken[str(m["name"])] = true
	for n in MONSTER_NAMES:
		if not taken.has(n):
			return n
	return "VOLTZ-%d" % (saved_monsters.size() + 1)


# ------------------------------------------------------------ phase: train ---

func _start_train() -> void:
	phase = "train"
	_clear_clickables()
	train_group = Node3D.new()
	add_child(train_group)
	_make_button("💪 SMASH\nStrength", Vector3(-1.15, 2.0, -2.2), "train_smash", Color(0.7, 0.2, 0.15))
	_make_button("🌀 RINGS\nAgility", Vector3(0.0, 2.0, -2.4), "train_rings", Color(0.15, 0.45, 0.7))
	_make_button("🧠 MATCH\nSmarts", Vector3(1.15, 2.0, -2.2), "train_match", Color(0.45, 0.25, 0.65))
	_make_button("✔ FINISH & SAVE", Vector3(0.0, 1.35, -2.35), "train_finish", Color(0.2, 0.6, 0.25))
	_update_hud()


func _start_game(g: String) -> void:
	game = g
	phase = "game"
	if train_group != null and is_instance_valid(train_group):
		train_group.visible = false
	game_group = Node3D.new()
	add_child(game_group)
	match g:
		"smash":
			_smash_begin()
		"rings":
			_rings_begin()
		"match":
			_match_begin()
	_update_hud()


func _end_game() -> void:
	for t in match_tiles:
		clickables.erase(t)
	match_tiles.clear()
	if game_group != null and is_instance_valid(game_group):
		game_group.queue_free()
	game_group = null
	game = ""
	phase = "train"
	if train_group != null and is_instance_valid(train_group):
		train_group.visible = true
	stat_str = minf(stat_str, 100.0)
	stat_agi = minf(stat_agi, 100.0)
	stat_sma = minf(stat_sma, 100.0)
	_update_hud()


# ------------------------------------------------------- game: smash -------

func _smash_begin() -> void:
	smash_targets.clear()
	smash_spawn_t = 0.0
	smash_done = 0
	smash_hits = 0
	_toast("Smash the red targets!", 2.0)


func _smash_process(delta: float) -> void:
	smash_spawn_t -= delta
	if smash_done < smash_total and smash_spawn_t <= 0.0:
		smash_spawn_t = 0.85
		_spawn_smash_target()
	for t in smash_targets.duplicate():
		if not is_instance_valid(t):
			smash_targets.erase(t)
			continue
		var age: float = t.get_meta("age") + delta
		t.set_meta("age", age)
		var life: float = t.get_meta("life")
		t.position.y = 1.1 + sin(age * 6.0) * 0.08
		var s := 1.0
		if age > life - 0.4:
			s = maxf((life - age) / 0.4, 0.01)
		t.scale = Vector3.ONE * s
		if age >= life:
			t.queue_free()
			smash_targets.erase(t)
			smash_done += 1
	if smash_done >= smash_total and smash_targets.is_empty():
		var gained := smash_hits * 9
		stat_str = minf(stat_str + float(gained), 100.0)
		_toast("Strength +%d! (%d/%d smashed)" % [gained, smash_hits, smash_total], 2.5)
		Haptics.pulse(0.8, 0.2)
		_end_game()


func _spawn_smash_target() -> void:
	var t := Node3D.new()
	t.position = Vector3(rng.randf_range(-1.5, 1.5), 1.1, rng.randf_range(-2.3, -0.7))
	t.set_meta("age", 0.0)
	t.set_meta("life", 2.3)
	t.set_meta("smash", true)
	var core := _sph(0.14, GraphicsPolish.glow(Color(1.0, 0.25, 0.15), 1.8))
	t.add_child(core)
	t.add_child(_sph(0.09, GraphicsPolish.glow(Color(1.0, 0.8, 0.3), 2.2)))
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.015
	tor.outer_radius = 0.2
	ring.mesh = tor
	ring.material_override = GraphicsPolish.glow(Color(1.0, 0.4, 0.2), 1.4)
	game_group.add_child(t)
	smash_targets.append(t)
	# Pop-in flourish.
	t.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(t, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _smash_hit(t: Node3D) -> void:
	smash_targets.erase(t)
	smash_done += 1
	smash_hits += 1
	GraphicsPolish.spawn_sparks(game_group, t.position, Color(1.0, 0.5, 0.2), 22)
	Haptics.thump()
	t.queue_free()
	_update_hud()


# ------------------------------------------------------- game: rings -------

func _rings_begin() -> void:
	ring_nodes.clear()
	ring_idx = 0
	ring_time = 45.0
	var pts := [
		Vector3(-1.4, 1.5, -1.2), Vector3(-0.7, 1.9, -1.7), Vector3(0.0, 1.4, -2.1),
		Vector3(0.7, 1.9, -1.7), Vector3(1.4, 1.5, -1.2), Vector3(0.0, 1.6, -0.9),
	]
	for i in pts.size():
		var r := Node3D.new()
		r.position = pts[i]
		var tor := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.05
		tm.outer_radius = 0.26
		tor.mesh = tm
		var active := i == 0
		tor.material_override = GraphicsPolish.glow(Color(0.3, 1.0, 0.5) if active else Color(0.25, 0.35, 0.45), 1.8 if active else 0.5)
		r.add_child(tor)
		r.set_meta("torus", tor)
		game_group.add_child(r)
		r.look_at(camera.global_position if camera != null else Vector3(0, 1.6, 2), Vector3.UP)
		ring_nodes.append(r)
	_toast("Fly your hand through the green ring!", 2.5)


func _rings_process(delta: float) -> void:
	ring_time -= delta
	if ring_idx >= ring_nodes.size() or ring_time <= 0.0:
		var gained := ring_idx * 11
		stat_agi = minf(stat_agi + float(gained), 100.0)
		_toast("Agility +%d! (%d/6 rings)" % [gained, ring_idx], 2.5)
		Haptics.pulse(0.8, 0.2)
		_end_game()
		return
	var r: Node3D = ring_nodes[ring_idx]
	var pp := _pointer_world()
	if ARUpgradeKit.is_xr_active():
		pp = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	var d: float = pp.distance_to(r.global_position)
	if d < 0.22:
		GraphicsPolish.spawn_sparks(game_group, r.global_position, Color(0.4, 1.0, 0.6), 16)
		Haptics.tick()
		var tor: MeshInstance3D = r.get_meta("torus")
		tor.material_override = GraphicsPolish.glow(Color(0.2, 0.5, 0.6), 0.4)
		ring_idx += 1
		if ring_idx < ring_nodes.size():
			var nt: MeshInstance3D = ring_nodes[ring_idx].get_meta("torus")
			nt.material_override = GraphicsPolish.glow(Color(0.3, 1.0, 0.5), 1.8)
		_update_hud()
	# Pulse the active ring.
	var tor2: MeshInstance3D = r.get_meta("torus")
	GraphicsPolish.pulse_glow(tor2.material_override as StandardMaterial3D, 1.8, 0.7, pulse_t, 4.0)


# ------------------------------------------------------- game: match -------

func _match_begin() -> void:
	match_tiles.clear()
	match_round = 0
	match_correct = 0
	_match_round()


func _match_round() -> void:
	for t in match_tiles:
		if is_instance_valid(t):
			clickables.erase(t)
			t.queue_free()
	match_tiles.clear()
	var syms := match_symbols.duplicate()
	syms.shuffle()
	match_target = syms[0]
	# Big target symbol.
	var tgt := _lbl(match_target, 160, Color(1.0, 0.9, 0.4), Vector3(0, 2.35, -2.2), 0.009)
	game_group.add_child(tgt)
	match_tiles.append(tgt)
	# 4 answer tiles.
	for i in 4:
		var tile := _make_button(syms[i], Vector3(-1.2 + float(i) * 0.8, 1.5, -2.2), "tile_%d" % i, Color(0.25, 0.3, 0.5))
		tile.reparent(game_group)
		match_tiles.append(tile)


func _match_pick(i: int) -> void:
	if phase != "game" or game != "match":
		return
	var tile: Node3D = match_tiles[i + 1]
	var glyph := ""
	for c in tile.get_children():
		if c is Label3D:
			glyph = (c as Label3D).text
	if glyph == match_target:
		match_correct += 1
		GraphicsPolish.spawn_sparks(game_group, tile.position, Color(0.5, 1.0, 0.5), 20)
		Haptics.tick()
		_toast("Correct!", 1.0)
	else:
		Haptics.thump()
		_toast("Not quite...", 1.0)
	match_round += 1
	if match_round >= 5:
		var gained := match_correct * 13
		stat_sma = minf(stat_sma + float(gained), 100.0)
		_toast("Smarts +%d! (%d/5 correct)" % [gained, match_correct], 2.5)
		_end_game()
	else:
		_match_round()
	_update_hud()


func _game_click(pos: Vector2) -> void:
	if game == "smash":
		var t := _screen_pick(pos, smash_targets, 60.0)
		if t != null:
			_smash_hit(t)
	elif game == "match":
		var b := _screen_pick(pos, clickables, 80.0)
		if b != null:
			_do_action(str(b.get_meta("action")), b)


func _game_xr_press(pp: Vector3) -> void:
	if game == "smash":
		var t := _xr_pick(smash_targets, pp, 0.3)
		if t != null:
			_smash_hit(t)
	elif game == "match":
		var b := _xr_pick(clickables, pp, 0.25)
		if b != null:
			_do_action(str(b.get_meta("action")), b)


# ------------------------------------------------------ save and gallery ---

func _finish_and_save() -> void:
	if phase != "train":
		return
	var rec := {
		"name": monster_name,
		"parts": build_parts.duplicate(),
		"stats": [stat_str, stat_agi, stat_sma],
		"power": power,
		"ts": int(Time.get_unix_time_from_system()),
	}
	saved_monsters.append(rec)
	while saved_monsters.size() > MAX_MONSTERS:
		saved_monsters.pop_front()
	_save_all()
	_toast("%s saved to the gallery!" % monster_name, 2.5)
	Haptics.pulse(0.9, 0.3)
	GraphicsPolish.spawn_confetti(self, Vector3(0, 2.2, -1.5), 90)
	_start_gallery()


func _start_gallery() -> void:
	phase = "gallery"
	_clear_clickables()
	if train_group != null and is_instance_valid(train_group):
		train_group.queue_free()
	train_group = null
	gallery_group = Node3D.new()
	add_child(gallery_group)
	# Dim the work area; pods take center stage.
	for i in saved_monsters.size():
		var rec: Dictionary = saved_monsters[i]
		var px := (float(i) - float(saved_monsters.size() - 1) * 0.5) * 1.5
		_build_pod(px, rec)
	_make_button("🔨 BUILD NEW MONSTER", Vector3(0, 2.35, -2.6), "gallery_new", Color(0.2, 0.5, 0.7))
	_update_hud()


func _build_pod(px: float, rec: Dictionary) -> void:
	var pod := Node3D.new()
	pod.position = Vector3(px, 0, -1.5)
	gallery_group.add_child(pod)
	pod.add_child(_cyl(0.55, 0.6, 0.12, _darkmetal(), Vector3(0, 0.06, 0)))
	var glass := _cyl(0.5, 0.5, 1.9, GraphicsPolish.pbr(Color(0.6, 0.85, 1.0), 0.0, 0.1), Vector3(0, 1.07, 0))
	(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(glass.material_override as StandardMaterial3D).albedo_color.a = 0.18
	pod.add_child(glass)
	pod.add_child(_cyl(0.55, 0.55, 0.1, _darkmetal(), Vector3(0, 2.06, 0)))
	GraphicsPolish.make_point_light(pod, Vector3(0, 1.9, 0), Color(0.5, 0.8, 1.0), 0.8, 2.5)
	# Mini monster lying on a tiny slab inside the pod.
	var mini := Node3D.new()
	mini.scale = Vector3.ONE * 0.42
	mini.position = Vector3(0, 0.35, 0.35)
	pod.add_child(mini)
	mini.add_child(_box(1.5, 0.1, 1.9, GraphicsPolish.pbr_preset(Color(0.32, 0.33, 0.36), "matte"), Vector3(0, 0.75, -0.35)))
	var parts: Array = rec["parts"]
	for ci in CATS.size():
		var part := _build_part(CATS[ci], int(parts[ci]))
		part.position = SOCKETS[CATS[ci]] + Vector3(0, 0, 0.35)
		mini.add_child(part)
	var stats: Array = rec["stats"]
	pod.add_child(_lbl(str(rec["name"]), 52, Color(1.0, 0.9, 0.5), Vector3(0, 2.35, 0), 0.005))
	pod.add_child(_lbl("STR %d AGI %d SMA %d PWR %d" % [int(stats[0]), int(stats[1]), int(stats[2]), int(rec["power"])], 34, Color(0.7, 1.0, 0.8), Vector3(0, -0.25, 0.62), 0.0035))


func _reset_to_assemble() -> void:
	if gallery_group != null and is_instance_valid(gallery_group):
		gallery_group.queue_free()
	gallery_group = null
	_clear_clickables()
	# Remove the old monster.
	for cat in snapped.keys():
		var p: Node3D = snapped[cat]
		if is_instance_valid(p):
			p.queue_free()
	snapped.clear()
	for cat in CATS:
		socket_rings[cat]["filled"] = false
		(socket_rings[cat]["mat"] as StandardMaterial3D).emission = Color(0.2, 0.85, 1.0)
	alive = false
	stat_str = 0.0
	stat_agi = 0.0
	stat_sma = 0.0
	power = 0.0
	monster_name = ""
	build_parts.clear()
	# Restock the shelves.
	for d in draggables:
		if is_instance_valid(d):
			d.queue_free()
	draggables.clear()
	for u in shelf_units:
		if is_instance_valid(u):
			u.queue_free()
	shelf_units.clear()
	_build_shelves()
	phase = "assemble"
	_toast("New monster: pick 5 parts!", 2.5)
	_update_hud()


func _on_parts_snapped_record() -> void:
	# Called right before animate starts; record chosen options in CATS order.
	build_parts.clear()
	for cat in CATS:
		var p: Node3D = snapped[cat]
		build_parts.append(int(p.get_meta("option")))


# ------------------------------------------------------------ persistence ---

func _load_saved() -> void:
	saved_monsters.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for i in MAX_MONSTERS:
		var sec := "monster_%d" % i
		if not cfg.has_section(sec):
			continue
		saved_monsters.append({
			"name": str(cfg.get_value(sec, "name", "VOLTZ")),
			"parts": cfg.get_value(sec, "parts", [0, 0, 0, 0, 0]),
			"stats": cfg.get_value(sec, "stats", [20.0, 20.0, 20.0]),
			"power": float(cfg.get_value(sec, "power", 50.0)),
			"ts": int(cfg.get_value(sec, "ts", 0)),
		})


func _save_all() -> void:
	var cfg := ConfigFile.new()
	for i in saved_monsters.size():
		var sec := "monster_%d" % i
		var rec: Dictionary = saved_monsters[i]
		cfg.set_value(sec, "name", str(rec["name"]))
		cfg.set_value(sec, "parts", rec["parts"])
		cfg.set_value(sec, "stats", rec["stats"])
		cfg.set_value(sec, "power", float(rec["power"]))
		cfg.set_value(sec, "ts", int(rec["ts"]))
	cfg.save(SAVE_PATH)


# ---------------------------------------------------------------- process ---

func _process(delta: float) -> void:
	pulse_t += delta
	_xr_process(delta)
	# Toast fade.
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0 and toast_label != null:
			toast_label.text = ""
	# Socket ring pulse.
	for cat in CATS:
		if not socket_filled(cat):
			GraphicsPolish.pulse_glow(socket_rings[cat]["mat"], 1.6, 0.8, pulse_t + float(CATS.find(cat)), 3.0)
	# Machine blinker lights.
	blink_t += delta
	for i in blinkers.size():
		var on := int(blink_t * 1.5 + float(i) * 2.0) % 3 != 0
		(blinkers[i] as MeshInstance3D).visible = on
	# Rotor wings spin.
	for r in rotor_refs:
		if is_instance_valid(r):
			r.rotation.y += delta * 9.0
	# Alive monster breathing.
	if alive and phase in ["animate", "train"]:
		var b := 1.0 + sin(pulse_t * 2.2) * 0.02
		monster_root.scale = Vector3(1.0, b, 1.0) * (1.06 if phase == "train" else 1.0)
	# Camera shake (desktop only; XR owns the camera).
	if shake_t > 0.0 and camera != null and not ARUpgradeKit.is_xr_active():
		shake_t = maxf(shake_t - delta * 0.7, 0.0)
		camera.position = cam_base + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0) * 0.05 * shake_t
	elif camera != null and not ARUpgradeKit.is_xr_active():
		camera.position = cam_base
	# Phase logic.
	match phase:
		"animate":
			if not striking:
				charge += charge_dir * CHARGE_SPEED * delta
				if charge >= 100.0:
					charge = 100.0
					charge_dir = -1.0
				elif charge <= 0.0:
					charge = 0.0
					charge_dir = 1.0
				_update_charge_bar()
			else:
				_strike_process(delta)
		"game":
			match game:
				"smash":
					_smash_process(delta)
				"rings":
					_rings_process(delta)
				"match":
					pass
	_update_hud()


func _update_charge_bar() -> void:
	if charge_bar == null:
		return
	var f := charge / 100.0
	charge_bar.scale = Vector3(1.0, maxf(f, 0.02), 1.0)
	charge_bar.position.y = 0.35 + f * 0.5
	var mat := charge_bar.material_override as StandardMaterial3D
	if mat != null:
		if charge >= 90.0:
			mat.emission = Color(1.0, 0.25, 0.15)
		elif charge >= 60.0:
			mat.emission = Color(1.0, 0.8, 0.2)
		else:
			mat.emission = Color(0.3, 1.0, 0.4)
