## Dragon Ranch: your pet dragon Ember lives in an anchored nest in your room.
## Care loop: FEED (click/pinch food on the offering stone - Ember hops over
## and munches), PLAY (flick the glowing ball - Ember fetches it back), TRAIN
## (tap the training orb, then guide Ember's flight through golden rings with
## your hand), PET (hold on Ember for hearts), TRICK (double-tap Ember or F:
## spin + fire breath). Stats (happiness/hunger/energy) tick live; earn XP for
## care to grow Baby -> Juvenile -> Adult (bigger, recolored, stronger fire).
## Everything persists in user://nexus_dragon.cfg.
## Ember is a hand-built low-poly dragon in the Kenney style (kenney.nl has no
## 3D creature pack - the Animal Pack is 2D sprites): PBR scale materials,
## emissive eyes, glowing wing membranes, back spikes, horns, spade tail, and
## procedural fire-breath particles. Nest dressing uses Kenney Nature Kit CC0
## models (rocks, grass, flowers, mushrooms) and Food Kit models for meals.
## Desktop: mouse for everything. XR: pinch/hand pointer, XR-gated.
## R: reset ranch. Headless-safe throughout.
extends Node3D

const MODEL_DIR := "res://assets/models/dragon_ranch/"
const SAVE_PATH := "user://nexus_dragon.cfg"
const FOODS := ["apple", "meat-raw", "fish", "strawberry", "carrot"]

const STAGES := [
	{"name": "Baby", "scale": 1.0, "body": Color(0.45, 0.80, 0.40),
		"belly": Color(0.96, 0.89, 0.70), "wing": Color(1.0, 0.55, 0.25), "xp_need": 100},
	{"name": "Juvenile", "scale": 1.42, "body": Color(0.25, 0.68, 0.55),
		"belly": Color(0.97, 0.90, 0.72), "wing": Color(1.0, 0.45, 0.30), "xp_need": 260},
	{"name": "Adult", "scale": 1.9, "body": Color(0.16, 0.48, 0.36),
		"belly": Color(0.99, 0.86, 0.55), "wing": Color(1.0, 0.32, 0.18), "xp_need": 999999},
]

var camera: Camera3D = null
var ranch: Node3D = null
var nest_center := Vector3.ZERO
var dragon: Node3D = null
var dragon_home := Vector3.ZERO
var body_mat: StandardMaterial3D = null
var belly_mat: StandardMaterial3D = null
var wing_mat: StandardMaterial3D = null
var eye_mat: StandardMaterial3D = null
var horn_mat: StandardMaterial3D = null
var body_node: Node3D = null
var head: Node3D = null
var jaw: Node3D = null
var eye_l: MeshInstance3D = null
var eye_r: MeshInstance3D = null
var wing_l: Node3D = null
var wing_r: Node3D = null
var tail_segs: Array = []
var fire: GPUParticles3D = null
var fire_light: OmniLight3D = null
var mouth: Node3D = null
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var ball_flying := false
var ball_home := Vector3.ZERO
var food_items: Array = []
var food_timers: Array = []
var rings: Array = []
var train_orb: MeshInstance3D = null
var state := "idle"
var state_t := 0.0
var fly_tween: Tween = null
# v0.9.0: Quaternius animated Dragon.fbx hero (Adult stage), flap shaping state.
var dragon_hero: Node3D = null
var _flap_lag := 0.0
var _prev_yaw := 0.0
# Stats.
var dragon_name := "Ember"
var stage_idx := 0
var xp := 0
var happiness := 70.0
var hunger := 30.0
var energy := 90.0
var coins := 0
var stat_t := 0.0
var save_t := 0.0
# Interaction.
var pointer_prev := Vector3.ZERO
var pointer_vel := Vector3.ZERO
var pointer_init := false
var pet_hold := 0.0
var pet_cool := 0.0
var trick_cool := 0.0
var last_tap_t := -10.0
var blink_t := 2.0
var train_time := 0.0
var rings_done := 0
var pulse_t := 0.0
var msg := ""
var msg_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var bar_happy: MeshInstance3D = null
var bar_hunger: MeshInstance3D = null
var bar_energy: MeshInstance3D = null
var offering_stone: Node3D = null

# v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_ready := false


func _ready() -> void:
	ranch = Node3D.new()
	ranch.name = "Ranch"
	add_child(ranch)
	if not ARUpgradeKit.apply_anchor(self, "dragon_ranch_main"):
		ranch.position = Vector3(0.75, 0.0, -1.25)
	nest_center = ranch.position
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_save()
	_build_ground()
	_build_nest()
	_build_dragon()
	_apply_stage(false)
	_build_offerings()
	_build_ball()
	_build_train_orb()
	_build_hud()
	_set_msg("Welcome back to the ranch!", 2.5)
	GraphicsPolish.spawn_ambient_motes(self, nest_center + Vector3(0, 0.8, 0), 2.2, 36)
	_apply_room_layout() # v0.7.0: perch on furniture, feeding station on a table (no-op w/o room data).
	# v0.9.0: per-game SFX map (AudioKit contract) + explore intensity.
	ArtKit.register_game_sfx(self, {
		"munch": "pop", "feed_yum": "heal", "throw": "whoosh", "fetch": "success",
		"trick": "fanfare", "fire": "explosion", "land": "thud", "grow": "powerup",
		"pet": "sparkle", "ring": "coin",
	})
	ArtKit.set_intensity(self, 0)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.35, 1.55, 0.55)
	add_child(camera)
	camera.look_at(nest_center + Vector3(0, 0.35, 0), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.12)
	env.fog_density = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)
	# Warm nest glow + cool moon fill.
	GraphicsPolish.make_point_light(ranch, Vector3(0, 0.6, 0), Color(1.0, 0.55, 0.25), 1.2, 4.0)


func _spawn_model(file: String, parent: Node, pos: Vector3, scl: float = 1.0, rot_y: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scl
	holder.rotation.y = rot_y
	parent.add_child(holder)
	var ps: PackedScene = load(MODEL_DIR + file + ".glb")
	if ps != null:
		var inst: Node3D = ps.instantiate()
		holder.add_child(inst)
	return holder


func _part(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.scale = scl
	m.rotation = rot
	parent.add_child(m)
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	return c


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 12
	return c


# ------------------------------------------------------------------ scenery

func _build_ground() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.7
	cm.bottom_radius = 1.7
	cm.height = 0.03
	disc.mesh = cm
	disc.material_override = GraphicsPolish.pbr(Color(0.16, 0.30, 0.16), 0.0, 0.9)
	disc.position = Vector3(0, -0.015, 0)
	ranch.add_child(disc)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.66
	tm.outer_radius = 1.74
	rim.mesh = tm
	rim.material_override = GraphicsPolish.glow(Color(0.3, 0.9, 0.5), 0.7)
	rim.rotation_degrees.x = 90
	rim.position = Vector3(0, 0.005, 0)
	ranch.add_child(rim)


func _build_nest() -> void:
	# Ring of small rocks forming the nest bowl.
	for i in 9:
		var a := TAU * float(i) / 9.0
		var rp := Vector3(cos(a) * 0.55, 0.03, sin(a) * 0.55)
		_spawn_model("rock_smallA" if i % 2 == 0 else "rock_smallB", ranch, rp, 1.6, a)
	# Soft glowing nest pad.
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.42
	pm.bottom_radius = 0.48
	pm.height = 0.10
	pad.mesh = pm
	pad.material_override = GraphicsPolish.pbr(Color(0.55, 0.40, 0.22), 0.0, 0.9)
	pad.position = Vector3(0, 0.05, 0)
	ranch.add_child(pad)
	var pad_rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.44
	tm.outer_radius = 0.50
	pad_rim.mesh = tm
	pad_rim.material_override = GraphicsPolish.glow(Color(1.0, 0.6, 0.25), 1.0)
	pad_rim.rotation_degrees.x = 90
	pad_rim.position = Vector3(0, 0.10, 0)
	ranch.add_child(pad_rim)
	# Dressing: grass, flowers, mushrooms, one big rock, a pine.
	var spots := [0.9, 1.5, 2.2, 2.9, 3.6, 4.3, 5.1, 5.8]
	for i in spots.size():
		var a: float = spots[i]
		var d := 0.85 + 0.25 * float(i % 3)
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d)
		_spawn_model("grass_large" if i % 2 == 0 else "grass", ranch, p, 1.4, a * 2.0)
	_spawn_model("flower_redA", ranch, Vector3(1.05, 0.0, 0.35), 1.2)
	_spawn_model("flower_yellowA", ranch, Vector3(-0.95, 0.0, 0.55), 1.2)
	_spawn_model("flower_purpleA", ranch, Vector3(0.25, 0.0, -1.05), 1.2)
	_spawn_model("mushroom_red", ranch, Vector3(-0.75, 0.0, -0.7), 1.3)
	_spawn_model("mushroom_tan", ranch, Vector3(1.15, 0.0, -0.5), 1.1)
	_spawn_model("rock_largeA", ranch, Vector3(-1.35, 0.0, -0.9), 1.8, 0.6)
	_spawn_model("tree_pineSmallA", ranch, Vector3(1.5, 0.0, 1.1), 1.6, 2.0)
	# Unhatched sibling egg, softly glowing.
	var egg := _part(ranch, _sphere(0.09), GraphicsPolish.glow(Color(1.0, 0.75, 0.45), 0.9),
		Vector3(0.62, 0.09, 0.42), Vector3(1.0, 1.35, 1.0))
	egg.name = "Egg"


func _build_offerings() -> void:
	# Flat offering stone with today's meals.
	offering_stone = _spawn_model("rock_smallFlatA", ranch, Vector3(-0.85, 0.02, 0.75), 2.2)
	for i in FOODS.size():
		var slot := Node3D.new()
		slot.position = Vector3(-1.15 + float(i) * 0.15, 0.10, 0.75)
		ranch.add_child(slot)
		food_items.append(slot)
		food_timers.append(0.0)
		_respawn_food(i, true)


func _respawn_food(i: int, instant: bool = false) -> void:
	var slot: Node3D = food_items[i]
	for c in slot.get_children():
		c.queue_free()
	var m := _spawn_model(FOODS[i], slot, Vector3.ZERO, 0.85)
	if not instant:
		m.scale = Vector3.ONE * 0.01
		var tw := create_tween()
		tw.tween_property(m, "scale", Vector3.ONE * 0.85, 0.4).set_trans(Tween.TRANS_BACK)


## Largest cuboid (by floor area) in the given RoomKit list, or {}.
func _room_largest(list: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_a := 0.0
	for t_v in list:
		var t: Dictionary = t_v
		var s: Vector3 = t["size"]
		if s.x * s.z > best_a:
			best_a = s.x * s.z
			best = t
	return best


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): bed -> dragon lair (haunted nest for Ember)
	_morph_anchors("BED", "haunted", 1)
	_room_ready = true
	# Feeding station goes on the biggest real table top.
	var table := _room_largest(_room_tables)
	if not table.is_empty():
		var top: Vector3 = (table["position"] as Vector3) + Vector3(0, (table["size"] as Vector3).y * 0.5, 0)
		var sl := ranch.to_local(top)
		if offering_stone != null:
			offering_stone.position = sl + Vector3(0, -0.02, 0)
		for i in food_items.size():
			(food_items[i] as Node3D).position = sl + Vector3(-0.30 + float(i) * 0.15, 0.10, 0.0)
	# Ember perches on the biggest furniture piece.
	var furn := _room_largest(_room_furniture)
	if not furn.is_empty() and dragon != null:
		var perch: Vector3 = (furn["position"] as Vector3) + Vector3(0, (furn["size"] as Vector3).y * 0.5 + 0.12, 0)
		dragon_home = ranch.to_local(perch)
		if state == "idle":
			dragon.position = dragon_home


# ------------------------------------------------------------------- dragon

func _build_dragon() -> void:
	dragon = Node3D.new()
	dragon.name = "Ember"
	ranch.add_child(dragon)
	dragon_home = Vector3(0, 0.10, 0)
	dragon.position = dragon_home
	# Stage-tinted materials (recolored on growth).
	body_mat = GraphicsPolish.pbr(Color(0.45, 0.80, 0.40), 0.15, 0.55)
	belly_mat = GraphicsPolish.pbr(Color(0.96, 0.89, 0.70), 0.0, 0.7)
	wing_mat = GraphicsPolish.glow(Color(1.0, 0.55, 0.25), 0.9)
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	eye_mat = GraphicsPolish.glow(Color(1.0, 0.85, 0.25), 2.2)
	horn_mat = GraphicsPolish.pbr(Color(0.92, 0.85, 0.70), 0.1, 0.4)
	var spike_mat := GraphicsPolish.pbr(Color(0.95, 0.80, 0.45), 0.3, 0.4)
	# Body + belly.
	body_node = Node3D.new()
	dragon.add_child(body_node)
	_part(body_node, _sphere(0.5), body_mat, Vector3(0, 0.20, 0), Vector3(0.30, 0.26, 0.42))
	_part(body_node, _sphere(0.5), belly_mat, Vector3(0, 0.175, 0.045), Vector3(0.23, 0.19, 0.33))
	# Neck.
	_part(body_node, _cyl(0.05, 0.078, 0.22), body_mat, Vector3(0, 0.33, 0.15), Vector3.ONE, Vector3(0.42, 0, 0))
	# Head.
	head = Node3D.new()
	head.position = Vector3(0, 0.44, 0.235)
	body_node.add_child(head)
	_part(head, _sphere(0.5), body_mat, Vector3.ZERO, Vector3(0.115, 0.105, 0.125))
	_part(head, _sphere(0.5), belly_mat, Vector3(0, -0.045, 0.03), Vector3(0.085, 0.06, 0.10))
	# Snout + jaw.
	var snout := _part(head, _cyl(0.038, 0.052, 0.11), body_mat, Vector3(0, -0.01, 0.105), Vector3.ONE, Vector3(1.35, 0, 0))
	snout.name = "Snout"
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.055, 0.06)
	head.add_child(jaw)
	_part(jaw, _sphere(0.5), belly_mat, Vector3(0, 0, 0.045), Vector3(0.07, 0.035, 0.10))
	# Nostrils.
	_part(head, _sphere(0.008), GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.06), "matte"),
		Vector3(0.025, 0.015, 0.155))
	_part(head, _sphere(0.008), GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.06), "matte"),
		Vector3(-0.025, 0.015, 0.155))
	# Glowing eyes.
	eye_l = _part(head, _sphere(0.024), eye_mat, Vector3(0.058, 0.035, 0.085))
	eye_r = _part(head, _sphere(0.024), eye_mat, Vector3(-0.058, 0.035, 0.085))
	# Horns sweeping back.
	_part(head, _cone(0.020, 0.10), horn_mat, Vector3(0.05, 0.10, -0.03), Vector3.ONE, Vector3(-0.7, 0, -0.25))
	_part(head, _cone(0.020, 0.10), horn_mat, Vector3(-0.05, 0.10, -0.03), Vector3.ONE, Vector3(-0.7, 0, 0.25))
	# Back spikes: neck to tail.
	var spike_z := [0.10, 0.03, -0.04, -0.11, -0.17, -0.22]
	for i in spike_z.size():
		var sz: float = spike_z[i]
		var sh := 0.055 - float(i) * 0.005
		_part(body_node, _cone(0.018, sh), spike_mat, Vector3(0, 0.315 - float(i) * 0.012, sz))
	# Legs: front pair + back pair, with feet and toe claws.
	_build_leg(Vector3(0.095, 0.0, 0.13), 1.0)
	_build_leg(Vector3(-0.095, 0.0, 0.13), 1.0)
	_build_leg(Vector3(0.105, 0.0, -0.12), 1.25)
	_build_leg(Vector3(-0.105, 0.0, -0.12), 1.25)
	# Tail: tapering segments + spade tip.
	var tz := [-0.24, -0.33, -0.41]
	var ts := [0.075, 0.058, 0.042]
	for i in 3:
		var seg := _part(body_node, _sphere(0.5), body_mat, Vector3(0, 0.20 + float(i) * 0.025, tz[i]),
			Vector3(ts[i] * 2.0, ts[i] * 1.7, ts[i] * 2.4))
		tail_segs.append(seg)
	_part(body_node, _cone(0.05, 0.10), spike_mat, Vector3(0, 0.29, -0.50),
		Vector3(1.0, 0.35, 1.4), Vector3(1.9, 0, 0))
	# Wings.
	wing_r = _build_wing(1.0)
	wing_l = _build_wing(-1.0)
	# v0.9.0: Quaternius animated Dragon.fbx hero for the Adult stage (CC0).
	# Ember's hand-built body stays for Baby/Juvenile; the hero model is the
	# growth reward. Anims: Dragon_Flying / Dragon_Attack / Dragon_Hit / Death.
	dragon_hero = ArtKit.spawn_model(MODEL_DIR + "Dragon.fbx", dragon, Vector3(0, 0.02, 0), 0.24)
	if dragon_hero != null:
		dragon_hero.visible = false
		dragon_hero.rotation.y = PI # FBX faces -Z; Ember faces +Z.
	# Fire breath emitter at the mouth (child of dragon so stage swaps don't hide it).
	mouth = Node3D.new()
	mouth.position = Vector3(0, 0.42, 0.36)
	dragon.add_child(mouth)
	fire = GPUParticles3D.new()
	fire.amount = 64
	fire.lifetime = 0.7
	fire.preprocess = 0.0
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.02
	fm.direction = Vector3(0, 0.25, 1)
	fm.spread = 16.0
	fm.initial_velocity_min = 1.6
	fm.initial_velocity_max = 3.2
	fm.gravity = Vector3(0, 1.2, 0)
	fm.scale_min = 0.05
	fm.scale_max = 0.13
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.4))
	grad.add_point(0.5, Color(1.0, 0.45, 0.15))
	grad.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	fm.color_ramp = ramp
	fire.process_material = fm
	var fq := QuadMesh.new()
	fq.size = Vector2(0.12, 0.12)
	fq.material = GraphicsPolish.glow(Color(1.0, 0.6, 0.2), 2.0)
	fire.draw_pass_1 = fq
	fire.emitting = false
	mouth.add_child(fire)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.5, 0.2)
	fire_light.light_energy = 0.0
	fire_light.omni_range = 2.5
	mouth.add_child(fire_light)


func _build_leg(base: Vector3, scl: float) -> void:
	var leg := Node3D.new()
	leg.position = base
	body_node.add_child(leg)
	_part(leg, _cyl(0.032 * scl, 0.040 * scl, 0.13 * scl), body_mat, Vector3(0, 0.10, 0))
	_part(leg, _sphere(0.5), body_mat, Vector3(0, 0.035, 0.015), Vector3(0.055 * scl, 0.035 * scl, 0.075 * scl))
	for t in 3:
		_part(leg, _cone(0.010 * scl, 0.03 * scl), horn_mat,
			Vector3((float(t) - 1.0) * 0.028 * scl, 0.02, 0.055 * scl), Vector3.ONE, Vector3(1.2, 0, 0))


func _build_wing(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.10 * side, 0.30, 0.02)
	body_node.add_child(pivot)
	var arm_mat := body_mat
	# Arm struts.
	_part(pivot, _cyl(0.012, 0.016, 0.24), arm_mat, Vector3(0.11 * side, 0.06, 0), Vector3.ONE, Vector3(0, 0, side * -1.05))
	_part(pivot, _cyl(0.008, 0.011, 0.22), arm_mat, Vector3(0.30 * side, 0.10, -0.01), Vector3.ONE, Vector3(0, 0.15 * side, side * -1.25))
	# Membrane: bat-wing triangle fan, scalloped trailing edge.
	var s := side
	var v := PackedVector3Array([
		Vector3(0.02 * s, 0.02, 0.02), Vector3(0.22 * s, 0.13, 0.0), Vector3(0.06 * s, -0.05, -0.01),
		Vector3(0.22 * s, 0.13, 0.0), Vector3(0.40 * s, 0.09, -0.03), Vector3(0.20 * s, -0.02, -0.03),
		Vector3(0.40 * s, 0.09, -0.03), Vector3(0.33 * s, -0.07, -0.05), Vector3(0.20 * s, -0.02, -0.03),
		Vector3(0.33 * s, -0.07, -0.05), Vector3(0.27 * s, -0.03, -0.05), Vector3(0.20 * s, -0.02, -0.03),
		Vector3(0.20 * s, -0.02, -0.03), Vector3(0.13 * s, -0.10, -0.04), Vector3(0.06 * s, -0.05, -0.01),
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mem := MeshInstance3D.new()
	mem.mesh = mesh
	mem.material_override = wing_mat
	pivot.add_child(mem)
	# Finger struts to membrane edge.
	_part(pivot, _cyl(0.006, 0.008, 0.20), arm_mat, Vector3(0.31 * s, 0.02, -0.02), Vector3.ONE, Vector3(0, 0.1 * s, s * -1.35))
	pivot.rotation.z = side * -0.35
	return pivot


func _apply_stage(announce: bool) -> void:
	var st: Dictionary = STAGES[stage_idx]
	body_mat.albedo_color = st["body"]
	body_mat.emission_enabled = false
	belly_mat.albedo_color = st["belly"]
	wing_mat.albedo_color = st["wing"]
	wing_mat.emission = st["wing"]
	var target := Vector3.ONE * float(st["scale"])
	var adult := stage_idx >= 2 and dragon_hero != null
	# v0.9.0: Adult stage swaps the hand-built body for the animated hero.
	if dragon_hero != null:
		dragon_hero.visible = adult
		body_node.visible = not adult
		wing_l.visible = not adult
		wing_r.visible = not adult
		if adult:
			mouth.position = Vector3(0, 0.95, 1.05)
			ArtKit.play_anim(dragon_hero, ["flying", "fly", "swim", "idle"], 0.7)
		else:
			mouth.position = Vector3(0, 0.42, 0.36)
			ArtKit.stop_anim(dragon_hero)
	if announce:
		var tw := create_tween()
		tw.tween_property(dragon, "scale", target * 1.12, 0.35).set_trans(Tween.TRANS_BACK)
		tw.tween_property(dragon, "scale", target, 0.3)
		GraphicsPolish.spawn_confetti(self, ranch.to_global(dragon.position) + Vector3(0, 0.6, 0), 60)
		_set_msg("%s grew into a %s!" % [dragon_name, st["name"]], 3.0)
		Haptics.thump()
		ArtKit.game_sfx(self, "grow")
		if adult:
			ArtKit.combo_popup(self, ranch.to_global(dragon.position) + Vector3(0, 1.2, 0), "TRUE FORM!")
	else:
		dragon.scale = target


func _gain_xp(n: int) -> void:
	xp += n
	var st: Dictionary = STAGES[stage_idx]
	if xp >= int(st["xp_need"]) and stage_idx < STAGES.size() - 1:
		stage_idx += 1
		_apply_stage(true)
		_save()


# ------------------------------------------------------------------ props

func _build_ball() -> void:
	ball = MeshInstance3D.new()
	ball.mesh = _sphere(0.06)
	ball.material_override = GraphicsPolish.glow(Color(0.35, 0.9, 1.0), 1.8)
	ball_home = Vector3(0.85, 0.07, 0.55)
	ball.position = ball_home
	ranch.add_child(ball)
	ball.add_child(GraphicsPolish.make_trail(Color(0.35, 0.9, 1.0), 0.04))


func _build_train_orb() -> void:
	train_orb = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.13
	train_orb.mesh = tm
	train_orb.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.3), 1.6)
	train_orb.position = Vector3(-0.9, 0.75, 0.35)
	ranch.add_child(train_orb)
	var lbl := GraphicsPolish.make_label("TRAIN", 40, Color(1.0, 0.85, 0.4))
	lbl.position = Vector3(-0.9, 1.0, 0.35)
	lbl.pixel_size = 0.0035
	ranch.add_child(lbl)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color(1, 1, 1))
	hud_label.position = nest_center + Vector3(-1.35, 1.75, -0.3)
	hud_label.pixel_size = 0.005
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 60, Color(1.0, 0.85, 0.5))
	msg_label.position = nest_center + Vector3(0, 2.05, -0.6)
	msg_label.pixel_size = 0.006
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("", 34, Color(0.75, 0.82, 0.92))
	help_label.position = nest_center + Vector3(-1.35, 1.5, -0.3)
	help_label.pixel_size = 0.0038
	add_child(help_label)
	# Stat bars.
	var bx := nest_center + Vector3(-1.35, 1.28, -0.3)
	bar_happy = _bar(bx, Color(1.0, 0.45, 0.65))
	bar_hunger = _bar(bx + Vector3(0, -0.09, 0), Color(1.0, 0.7, 0.3))
	bar_energy = _bar(bx + Vector3(0, -0.18, 0), Color(0.45, 0.85, 1.0))
	_update_hud()


func _bar(pos: Vector3, color: Color) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.62, 0.045, 0.02)
	bg.mesh = b
	bg.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.09, 0.11), "matte")
	bg.position = pos
	add_child(bg)
	var fill := MeshInstance3D.new()
	var f := BoxMesh.new()
	f.size = Vector3(0.58, 0.03, 0.02)
	fill.mesh = f
	fill.material_override = GraphicsPolish.glow(color, 1.1)
	fill.position = pos + Vector3(0, 0, 0.012)
	fill.set_meta("base_x", pos.x)
	add_child(fill)
	return fill


func _update_hud() -> void:
	var st: Dictionary = STAGES[stage_idx]
	if hud_label != null:
		hud_label.text = "%s the %s   XP %d   Coins %d" % [dragon_name, st["name"], xp, coins]
	if help_label != null:
		if ARUpgradeKit.is_xr_active():
			help_label.text = "Pinch food to feed | Flick ball to play\nPinch TRAIN orb, guide flight | Hold Ember to pet"
		else:
			help_label.text = "Click food to feed | Flick ball to play\nClick TRAIN orb, guide flight | Hold Ember to pet | F: trick"
	_set_bar(bar_happy, happiness)
	_set_bar(bar_hunger, 100.0 - hunger)
	_set_bar(bar_energy, energy)
	if msg_label != null:
		msg_label.text = msg


func _set_bar(b: MeshInstance3D, v: float) -> void:
	if b == null:
		return
	var frac := clampf(v / 100.0, 0.0, 1.0)
	b.scale.x = maxf(frac, 0.001)
	# Keep the left edge anchored while the fill shrinks.
	var base_x := float(b.get_meta("base_x", b.position.x))
	b.position.x = base_x - 0.58 * (1.0 - frac) * 0.5


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


# ------------------------------------------------------------------ save

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		dragon_name = str(cfg.get_value("dragon", "name", "Ember"))
		stage_idx = int(cfg.get_value("dragon", "stage", 0))
		xp = int(cfg.get_value("dragon", "xp", 0))
		happiness = float(cfg.get_value("dragon", "happiness", 70.0))
		hunger = float(cfg.get_value("dragon", "hunger", 30.0))
		energy = float(cfg.get_value("dragon", "energy", 90.0))
		coins = int(cfg.get_value("dragon", "coins", 0))
		stage_idx = clampi(stage_idx, 0, STAGES.size() - 1)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("dragon", "name", dragon_name)
	cfg.set_value("dragon", "stage", stage_idx)
	cfg.set_value("dragon", "xp", xp)
	cfg.set_value("dragon", "happiness", happiness)
	cfg.set_value("dragon", "hunger", hunger)
	cfg.set_value("dragon", "energy", energy)
	cfg.set_value("dragon", "coins", coins)
	cfg.save(SAVE_PATH)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_tap()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_handle_tap()


func _handle_tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var p := pointer_prev
	# Food select.
	for i in food_items.size():
		var slot: Node3D = food_items[i]
		if slot.get_child_count() > 0 and ranch.to_global(slot.position).distance_to(p) < 0.22:
			_feed(i)
			return
	# Train orb.
	if train_orb != null and ranch.to_global(train_orb.position).distance_to(p) < 0.28 and state == "idle":
		_start_training()
		return
	# Dragon: double-tap = trick.
	var dp := ranch.to_global(dragon.position).distance_to(p)
	if dp < 0.45 * float(STAGES[stage_idx]["scale"]):
		if now - last_tap_t < 0.45:
			_do_trick()
		last_tap_t = now


func _pointer_world() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.2)
	if camera == null:
		return nest_center + Vector3(0, 1.0, 0)
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var plane_y := nest_center.y + 1.0
	if absf(dir.y) < 0.001:
		return pointer_prev
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return pointer_prev
	return origin + dir * t


func _process(delta: float) -> void:
	pulse_t += delta
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if trick_cool > 0.0:
		trick_cool -= delta
	if pet_cool > 0.0:
		pet_cool -= delta
	if Input.is_key_pressed(KEY_R):
		_reset_ranch()
	if Input.is_key_pressed(KEY_F):
		_do_trick()
	if Input.is_key_pressed(KEY_T) and state == "idle":
		_start_training()
	_track_pointer(delta)
	# XR tap selection (pinch); desktop uses _unhandled_input clicks.
	if ARUpgradeKit.is_xr_active():
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			_handle_tap()
	_tick_stats(delta)
	_dragon_idle_anim(delta)
	_state_logic(delta)
	_pet_logic(delta)
	_ball_logic(delta)
	_ring_logic(delta)
	_food_respawn(delta)
	_pulse_props()
	save_t += delta
	if save_t > 5.0:
		save_t = 0.0
		_save()
	_update_hud()


func _track_pointer(delta: float) -> void:
	var p := _pointer_world()
	if not pointer_init:
		pointer_prev = p
		pointer_init = true
		pointer_vel = Vector3.ZERO
		return
	if delta > 0.0:
		var v: Vector3 = (p - pointer_prev) / delta
		pointer_vel = pointer_vel.lerp(v, 0.45)
	pointer_prev = p


func _tick_stats(delta: float) -> void:
	stat_t += delta
	if stat_t < 1.0:
		return
	stat_t = 0.0
	hunger = clampf(hunger + 1.1, 0.0, 100.0)
	happiness = clampf(happiness - 0.7, 0.0, 100.0)
	if state == "sleep":
		energy = clampf(energy + 9.0, 0.0, 100.0)
	else:
		energy = clampf(energy - 0.3, 0.0, 100.0)
	if energy <= 0.0 and state == "idle":
		_go_sleep()
	if hunger > 80.0 and state == "idle":
		_set_msg("%s is hungry! Offer food." % dragon_name, 2.0)
	elif happiness < 20.0 and state == "idle":
		_set_msg("%s wants to play!" % dragon_name, 2.0)


# ------------------------------------------------------------- dragon acts

func _fly_to(target: Vector3, duration: float, arrive_state: String) -> void:
	if fly_tween != null and fly_tween.is_valid():
		fly_tween.kill()
	state = "flying"
	state_t = 0.0
	var from := dragon.position
	fly_tween = create_tween()
	fly_tween.tween_method(_fly_step.bind(from, target), 0.0, 1.0, duration)
	fly_tween.tween_callback(_arrive.bind(arrive_state))


func _fly_step(t: float, from: Vector3, target: Vector3) -> void:
	var pos := from.lerp(target, t)
	pos.y += sin(t * PI) * 0.35
	dragon.position = pos
	if (target - from).length() > 0.05:
		var dir := (target - from)
		dir.y = 0.0
		if dir.length() > 0.01:
			var yaw := atan2(dir.x, dir.z)
			# v0.9.0: bank into turns — roll proportional to yaw change per step.
			var yaw_d := wrapf(yaw - _prev_yaw, -PI, PI)
			_prev_yaw = yaw
			var roll := clampf(-yaw_d * 9.0, -0.6, 0.6)
			dragon.rotation.z = lerpf(dragon.rotation.z, roll, 0.12)
			dragon.rotation.y = lerp_angle(dragon.rotation.y, yaw, 0.2)


func _arrive(next: String) -> void:
	state = next
	state_t = 0.0
	# v0.9.0: landing squash + thud when the dragon touches down.
	ArtKit.squash_stretch(self, dragon)
	ArtKit.game_sfx(self, "land")
	_on_arrive()


func _on_arrive() -> void:
	match state:
		"eat":
			_eat_munch()
		"fetch_grab":
			_grab_ball()
		"fetch_drop":
			_drop_ball()


func _feed(i: int) -> void:
	if state != "idle":
		return
	var slot: Node3D = food_items[i]
	if slot.get_child_count() == 0:
		return
	Haptics.tick()
	_set_msg("Yum!", 1.0)
	ArtKit.game_sfx(self, "feed_yum")
	ArtKit.scale_pop(self, slot)
	state = "to_food"
	var target: Vector3 = slot.position + Vector3(0, 0.05, -0.25)
	_fly_to(target, 0.9, "eat")
	# Remember which food: stash index in meta.
	dragon.set_meta("meal", i)


func _eat_munch() -> void:
	state = "eat"
	state_t = 0.0
	var i: int = int(dragon.get_meta("meal", 0))
	var slot: Node3D = food_items[i]
	var munch_pos := ranch.to_global(slot.position)
	GraphicsPolish.spawn_sparks(self, munch_pos + Vector3(0, 0.1, 0), Color(1.0, 0.85, 0.5), 14)
	Haptics.pulse(0.6, 0.1)
	# Jaw chomps.
	if jaw != null:
		var tw := create_tween()
		for k in 3:
			tw.tween_property(jaw, "rotation_degrees:x", 18.0, 0.12)
			tw.tween_property(jaw, "rotation_degrees:x", 0.0, 0.12)
	# Shrink the food away.
	for c in slot.get_children():
		var tw2 := create_tween()
		tw2.tween_property(c, "scale", Vector3.ONE * 0.01, 0.5)
		tw2.tween_callback(c.queue_free)
	food_timers[i] = 25.0
	hunger = clampf(hunger - 38.0, 0.0, 100.0)
	happiness = clampf(happiness + 8.0, 0.0, 100.0)
	energy = clampf(energy + 6.0, 0.0, 100.0)
	coins += 2
	_gain_xp(10)
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(_back_home)


func _back_home() -> void:
	if state == "eat" or state == "trick":
		_fly_to(dragon_home, 0.9, "idle")


func _throw_ball() -> void:
	if ball_flying or state != "idle":
		return
	ball_flying = true
	state = "fetch_wait"
	state_t = 0.0
	ball_vel = pointer_vel * 0.75 + Vector3(0, 1.6, 0)
	if ball_vel.length() < 2.0:
		ball_vel = Vector3(1.2, 2.2, -1.5)
	Haptics.pulse(0.5, 0.1)
	_set_msg("Fetch!", 1.0)


func _ball_logic(delta: float) -> void:
	if not ball_flying:
		# Flick detection: fast pointer motion over the ball.
		if state == "idle" and pointer_vel.length() > 3.4:
			if ranch.to_global(ball.position).distance_to(pointer_prev) < 0.30:
				_throw_ball()
		return
	ball_vel.y -= 6.0 * delta
	ball.position += ball_vel * delta
	var wp := ranch.to_global(ball.position)
	if ball.position.y < 0.06 and ball_vel.y < 0.0:
		ball.position.y = 0.06
		ball_vel.y = -ball_vel.y * 0.45
		ball_vel.x *= 0.7
		ball_vel.z *= 0.7
		Haptics.tick()
	if ball_vel.length() < 0.6 or state_t > 6.0:
		ball_flying = false
		_fetch_go()
	# Keep inside the ranch area.
	var lp := ball.position
	lp.x = clampf(lp.x, -2.2, 2.2)
	lp.z = clampf(lp.z, -2.6, 1.6)
	ball.position = lp
	if _room_ready and ball.get_parent() == ranch:
		# Fence the ball inside the real room floor extents as well.
		var bw := ranch.to_global(ball.position)
		bw.x = clampf(bw.x, _room_bounds.position.x + 0.4, _room_bounds.position.x + _room_bounds.size.x - 0.4)
		bw.z = clampf(bw.z, _room_bounds.position.y + 0.4, _room_bounds.position.y + _room_bounds.size.y - 0.4)
		ball.position = ranch.to_local(bw)


func _fetch_go() -> void:
	state = "fetch_out"
	_fly_to(ball.position + Vector3(0, 0.05, 0), 0.8, "fetch_grab")


func _grab_ball() -> void:
	ranch.remove_child(ball)
	mouth.add_child(ball)
	ball.position = Vector3(0, -0.02, 0.06)
	ball_vel = Vector3.ZERO
	happiness = clampf(happiness + 6.0, 0.0, 100.0)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_fetch_back)


func _fetch_back() -> void:
	state = "fetch_back"
	var drop := dragon_home + Vector3(0.35, 0.0, 0.35)
	_fly_to(drop, 1.0, "fetch_drop")


func _drop_ball() -> void:
	mouth.remove_child(ball)
	ranch.add_child(ball)
	ball.position = dragon.position + Vector3(0.1, -0.05, 0.1)
	ball.position.y = 0.07
	ball_home = ball.position
	GraphicsPolish.spawn_sparks(self, ranch.to_global(ball.position), Color(0.35, 0.9, 1.0), 10)
	happiness = clampf(happiness + 8.0, 0.0, 100.0)
	energy = clampf(energy - 10.0, 0.0, 100.0)
	coins += 3
	_gain_xp(12)
	_set_msg("Good fetch!", 1.5)
	state = "idle"


func _start_training() -> void:
	if state != "idle":
		return
	_clear_rings()
	state = "train"
	train_time = 30.0
	rings_done = 0
	for i in 5:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.17
		tm.outer_radius = 0.22
		ring.mesh = tm
		ring.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.3), 1.8)
		var a := -0.9 + float(i) * 0.45
		ring.position = Vector3(a * 1.1, 1.05 + float(i % 2) * 0.35 + float(i) * 0.08, -0.7 - float(i) * 0.18)
		ranch.add_child(ring)
		rings.append(ring)
	_set_msg("Guide %s through the rings!" % dragon_name, 2.5)
	Haptics.tick()


func _clear_rings() -> void:
	for r in rings:
		if is_instance_valid(r):
			r.queue_free()
	rings.clear()


func _ring_logic(delta: float) -> void:
	if state != "train":
		return
	train_time -= delta
	# Ember follows the hand pointer with lag.
	var target: Vector3 = ranch.to_local(pointer_prev)
	target.y = clampf(target.y, 0.4, 2.2)
	target.x = clampf(target.x, -1.6, 1.6)
	target.z = clampf(target.z, -2.2, 0.6)
	dragon.position = dragon.position.lerp(target, clampf(2.2 * delta, 0.0, 1.0))
	_dragon_face(target)
	for r in rings:
		if is_instance_valid(r) and r.visible and dragon.position.distance_to(r.position) < 0.30:
			r.visible = false
			rings_done += 1
			GraphicsPolish.spawn_sparks(self, ranch.to_global(r.position), Color(1.0, 0.85, 0.4), 16)
			Haptics.tick()
			happiness = clampf(happiness + 4.0, 0.0, 100.0)
			energy = clampf(energy - 5.0, 0.0, 100.0)
			_gain_xp(8)
			_set_msg("Ring %d/5!" % rings_done, 1.0)
	if rings_done >= 5 or train_time <= 0.0:
		_clear_rings()
		coins += rings_done * 2
		if rings_done >= 5:
			_set_msg("Flight school complete! +%d coins" % (rings_done * 2), 2.5)
			GraphicsPolish.spawn_confetti(self, ranch.to_global(dragon.position) + Vector3(0, 0.4, 0), 40)
		_fly_to(dragon_home, 1.0, "idle")


func _do_trick() -> void:
	if trick_cool > 0.0 or state == "train":
		return
	trick_cool = 5.0
	state = "trick"
	state_t = 0.0
	Haptics.thump()
	# Spin.
	var tw := create_tween()
	tw.tween_property(dragon, "rotation_degrees:y", dragon.rotation_degrees.y + 360.0, 0.9)
	# Fire breath!
	_breathe_fire(1.6 if stage_idx < 2 else 2.6)
	ArtKit.game_sfx(self, "fire")
	ArtKit.h_sub_bass(self, 0.9)
	ArtKit.hit_stop(self, 2)
	# v0.9.0 SIGNATURE ROOM MOVE: the breath scorches YOUR wall — a fading
	# scorch decal pinned to the real room (PassthroughFX contract).
	var wall := ArtKit.largest_wall(_room_walls)
	var wp := ArtKit.wall_point(wall, 0.5, 0.55)
	if not wp.is_empty():
		var mouth_w: Vector3 = ranch.to_global(mouth.position)
		var to_wall: Vector3 = wp["pos"] - mouth_w
		if to_wall.length() < 6.0:
			ArtKit.scorch(self, wp["pos"], wp["normal"], 0.55)
			ArtKit.sfx_3d(self, "fire", wp["pos"])
	happiness = clampf(happiness + 6.0, 0.0, 100.0)
	coins += 2
	_gain_xp(6)
	_set_msg("Fire breath!", 1.5)
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(_back_home)


func _breathe_fire(duration: float) -> void:
	if fire == null:
		return
	fire.emitting = true
	fire.amount = 64 if stage_idx < 2 else 110
	var t := get_tree().create_timer(duration)
	t.timeout.connect(_stop_fire)


func _stop_fire() -> void:
	if fire != null:
		fire.emitting = false
	if fire_light != null:
		fire_light.light_energy = 0.0


func _go_sleep() -> void:
	if state == "sleep":
		return
	_clear_rings()
	_set_msg("%s is tuckered out... (sleeping)" % dragon_name, 3.0)
	_fly_to(dragon_home, 0.8, "sleep")


func _pet_logic(delta: float) -> void:
	if pet_cool > 0.0:
		return
	var pressing := false
	if ARUpgradeKit.is_xr_active():
		pressing = ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	else:
		pressing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var dp := ranch.to_global(dragon.position).distance_to(pointer_prev)
	if pressing and dp < 0.40 * float(STAGES[stage_idx]["scale"]) and state == "idle":
		pet_hold += delta
		if pet_hold >= 1.0:
			pet_hold = 0.0
			pet_cool = 3.0
			happiness = clampf(happiness + 10.0, 0.0, 100.0)
			_gain_xp(5)
			Haptics.tick()
			GraphicsPolish.spawn_sparks(self, ranch.to_global(dragon.position) + Vector3(0, 0.5, 0),
				Color(1.0, 0.5, 0.7), 14)
			_set_msg("%s purrs happily." % dragon_name, 1.5)
	else:
		pet_hold = maxf(pet_hold - delta * 2.0, 0.0)


func _food_respawn(delta: float) -> void:
	for i in food_timers.size():
		if food_timers[i] > 0.0:
			food_timers[i] -= delta
			if food_timers[i] <= 0.0:
				_respawn_food(i)


func _pulse_props() -> void:
	if train_orb != null and is_instance_valid(train_orb):
		train_orb.rotation.y += 0.02
		var s := 1.0 + 0.12 * sin(pulse_t * 3.0)
		train_orb.scale = Vector3.ONE * s
	if fire_light != null and fire != null and fire.emitting:
		fire_light.light_energy = 1.6 + sin(pulse_t * 40.0) * 0.5


func _state_logic(delta: float) -> void:
	state_t += delta
	match state:
		"sleep":
			if energy > 45.0:
				state = "idle"
				_set_msg("%s woke up refreshed!" % dragon_name, 2.0)
				var tw := create_tween()
				tw.tween_property(dragon, "rotation_degrees:z", 0.0, 0.4)
		"fetch_wait":
			pass
		"idle":
			# Face the player when idle.
			_dragon_face(ranch.to_local(pointer_prev) * 0.2)


func _dragon_face(target_local: Vector3) -> void:
	var dir := target_local - dragon.position
	dir.y = 0.0
	if dir.length() > 0.05:
		var yaw := atan2(dir.x, dir.z)
		dragon.rotation.y = lerp_angle(dragon.rotation.y, yaw, 0.06)


# ------------------------------------------------------------- idle animation

func _dragon_idle_anim(delta: float) -> void:
	if dragon == null:
		return
	var flying := state in ["flying", "fetch_out", "fetch_back", "train"]
	# Breathing.
	if body_node != null:
		var b := 1.0 + 0.035 * sin(pulse_t * 2.2)
		body_node.scale = Vector3(1.0, b, 1.0)
	# Tail sway.
	for i in tail_segs.size():
		var seg: MeshInstance3D = tail_segs[i]
		seg.rotation.y = 0.35 * sin(pulse_t * 1.8 + float(i) * 0.7)
	# Wing flap when flying, gentle sway when perched.
	# v0.9.0: shaped (not pure sine) — snappy downstroke, soft upstroke —
	# plus secondary-motion lag so the wings trail the body by a few frames.
	var flap := 0.0
	if flying:
		var s := sin(pulse_t * 11.0)
		flap = signf(s) * pow(abs(s), 0.65) * 0.78
	elif state == "sleep":
		flap = -0.85
	else:
		flap = -0.45 + 0.10 * sin(pulse_t * 1.5)
	_flap_lag = lerpf(_flap_lag, flap, 1.0 - exp(-delta * 9.0))
	if wing_r != null:
		wing_r.rotation.z = -0.35 - _flap_lag * 0.9
	if wing_l != null:
		wing_l.rotation.z = 0.35 + _flap_lag * 0.9
	# v0.9.0: hero dragon animation state follows the action.
	if dragon_hero != null and dragon_hero.visible:
		if state == "trick":
			ArtKit.play_anim(dragon_hero, ["attack"], 1.2)
		elif flying:
			ArtKit.play_anim(dragon_hero, ["flying", "fly"], 1.0)
		elif state == "eat":
			ArtKit.play_anim(dragon_hero, ["attack", "hit"], 0.8)
		else:
			ArtKit.play_anim(dragon_hero, ["flying", "fly"], 0.45)
	# Blink.
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = 2.5 + randf() * 2.5
		if eye_l != null:
			var tw := create_tween()
			tw.tween_property(eye_l, "scale:y", 0.12, 0.07)
			tw.tween_property(eye_l, "scale:y", 1.0, 0.12)
			var tw2 := create_tween()
			tw2.tween_property(eye_r, "scale:y", 0.12, 0.07)
			tw2.tween_property(eye_r, "scale:y", 1.0, 0.12)
	# Sleep pose: tilt on side, slow breath handled by state.
	if state == "sleep":
		dragon.rotation.z = lerpf(dragon.rotation.z, 0.35, 0.04)
		if randf() < delta * 0.7:
			GraphicsPolish.spawn_sparks(self, ranch.to_global(dragon.position) + Vector3(0, 0.55, 0),
				Color(0.6, 0.7, 1.0), 3)
	else:
		dragon.rotation.z = lerpf(dragon.rotation.z, 0.0, 0.08)
	# Head tracks the pointer when idle.
	if head != null and state == "idle":
		var local_p := body_node.to_local(pointer_prev)
		var want_yaw := clampf(atan2(local_p.x - head.position.x, local_p.z - head.position.z) - dragon.rotation.y, -0.7, 0.7)
		head.rotation.y = lerpf(head.rotation.y, want_yaw, 0.08)


func _reset_ranch() -> void:
	happiness = 70.0
	hunger = 30.0
	energy = 90.0
	xp = 0
	stage_idx = 0
	coins = 0
	state = "idle"
	_clear_rings()
	_stop_fire()
	dragon.position = dragon_home
	dragon.rotation = Vector3.ZERO
	_apply_stage(false)
	_save()
	_set_msg("Ranch reset.", 1.5)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
