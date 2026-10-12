## KaijuSiege.gd - NEXUS ARCADE v0.11.0: KAIJU SIEGE.
## You ARE the kaiju. A procedural city rises from your floor at
## ankle-to-knee scale; stomp it flat (body-tracked feet, controller-slam
## fallback), tail-swipe by spinning, and breathe atomic fire (both
## triggers). The military escalates across 5 waves. Scoring rewards
## destruction STYLE (collateral combos), not just volume.
##
## Room-aware: the city grid fits the real room bounds; buildings avoid real
## furniture (RoomKit) — the couch becomes a mountain range the military
## hides behind. Original design; buildings: Quaternius downtowncitymegakit
## (CC0 1.0); military fliers: Quaternius animatedmonster (CC0 1.0).
extends Node3D
class_name KaijuSiegeGame

const BDIR := "res://assets/models/kaiju_siege/buildings/"
const MDIR := "res://assets/models/shared_monsters/"
const GRID := 5
const CELL := 0.85
const STOMP_R := 0.75
const SWIPE_R := 1.35
const BREATH_LEN := 6.0
const BREATH_W := 0.9
const MAX_WAVE := 5

var controller_config := {
	"uses_controllers": true,
	"skin": "none",
	"buttons": {
		"trigger": "Atomic breath (hold BOTH)",
		"grip": "Slam controller down = stomp",
		"thumbstick": "—",
		"menu": "Pause",
	},
}

var _origin: Node3D
var _controllers := {}
var _city: Node3D
var _buildings: Array = []   # {node, hp, state, pos: Vector3, score_val}
var _mountains: Array = []
var _military: Array = []     # {kind, node, hp, pos, vel, fire_cd, anim}
var _pellets: Array = []      # pooled enemy shots {node, vel, life}
var _pellet_pool: Array = []
var _debris: GPUParticles3D
var _smoke: GPUParticles3D
var _breath_fx: GPUParticles3D
var _wave := 0
var _wave_state := "intro"    # intro | fighting | cleared | done
var _wave_pause := 0.0
var _hp := 100.0
var _breath := 100.0
var _breathing := false
var _score := 0
var _combo := 0
var _combo_t := 0.0
var _destroyed := 0
var _feet_prev := {}
var _ctl_prev := {}
var _stomp_cd := 0.0
var _yaw_prev := 0.0
var _spin_acc := 0.0
var _swipe_cd := 0.0
var _hud_hp: Label3D
var _hud_wave: Label3D
var _hud_score: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _shake := 0.0
var _base_origin_pos := Vector3.ZERO
var _game_over := false
var _mic_loud := 0.0
# v0.11.0 (Animator) ambient elements:
var _traffic: MultiMeshInstance3D = null  # (a) civilian cars, panic swerve
var _traffic_t := 0.0
var _pigeons: Array = []                  # (b) pooled pigeon bursts
var _smoke_cols: Array = []               # (c) 2 rubble smoke columns
var _helis: Array = []                    # (d) 2 searchlight helicopters
var _win_mats: Array = []                 # (e) building window materials


func _ready() -> void:
	_origin = _find_origin()
	_find_controllers()
	if _origin != null:
		_base_origin_pos = _origin.position
	ArtKit.register_game_sfx(self, {
		"stomp": "explosion", "breath": "engine_roar", "boom": "explosion",
		"shot": "laser", "hit": "hit", "win": "fanfare", "lose": "fail",
		"wave": "countdown", "roar": "buzzer", "crumble": "thud",
	})
	ArtKit.set_intensity(self, 2)
	_build_hud()
	_build_particles()
	if RoomKit.is_available():
		await RoomKit.refresh()
	_build_city()
	_build_kaiju_ambient()
	_announce_text("KAIJU SIEGE\nThe city rose from your floor as a dare.\nStomp like they paid to watch.", 4.0)
	JuiceFX.title_card("KAIJU SIEGE", "You ARE the monster. The city is a dare.", Color(1.0, 0.35, 0.1))
	_telemetry("kaiju_start", {})
	_start_wave(1)


# ---------------------------------------------------------------- setup ---

## v0.11.0 (Animator): 5 cheap ambient elements.
## (a) traffic (b) pigeon bursts (c) rubble smoke (d) heli searchlights
## (e) window blackout as you advance. All 1-draw / pooled / 0-alloc.
func _build_kaiju_ambient() -> void:
	# (a) Civilian traffic: 16 tiny cars on street lanes, 1 MultiMesh draw.
	_traffic = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var car := BoxMesh.new()
	car.size = Vector3(0.09, 0.045, 0.05)
	car.material = GraphicsPolish.pbr(Color(0.85, 0.85, 0.9), 0.2, 0.5)
	mm.mesh = car
	mm.instance_count = 16
	_traffic.multimesh = mm
	_traffic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_city.add_child(_traffic)
	# (c) Two smoke columns that relocate to fresh rubble.
	for i in 2:
		var col := GPUParticles3D.new()
		col.amount = 24
		col.lifetime = 3.0
		col.preprocess = 3.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.15
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 0.25
		pm.initial_velocity_max = 0.5
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.12
		pm.scale_max = 0.3
		pm.color = Color(0.25, 0.24, 0.23, 0.55)
		col.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.3)
		var qm := GraphicsPolish.glow(Color(0.3, 0.29, 0.28), 0.4)
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad.material = qm
		col.draw_pass_1 = quad
		col.position = Vector3(0, -5, 0)  # parked underground until rubble
		_city.add_child(col)
		col.emitting = true
		_smoke_cols.append(col)
	# (d) Two helicopters with sweeping searchlight cones.
	for i in 2:
		var heli := Node3D.new()
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.07, 0.07)
		body.mesh = bm
		body.material_override = GraphicsPolish.pbr(Color(0.15, 0.16, 0.18), 0.3, 0.6)
		heli.add_child(body)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.22
		cm.height = 1.6
		cone.mesh = cm
		var cmat := GraphicsPolish.glow(Color(1.0, 0.95, 0.7), 0.8)
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.albedo_color.a = 0.30
		cone.material_override = cmat
		cone.position = Vector3(0, -0.85, 0)
		heli.add_child(cone)
		heli.position = Vector3(0, 3.2, 0)
		_city.add_child(heli)
		_helis.append({"node": heli, "cone": cone, "phase": float(i) * PI,
			"r": 2.6 + float(i) * 0.7})
	# (e) Collect window materials for the blackout pass.
	for b in _buildings:
		var holder: Node3D = b["holder"]
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
				_win_mats.append({"mat": m, "pos": b["pos"], "k": 1.0})


## (b) Pigeon burst: 8 quads erupt off a rooftop, flap (scale-x), fade.
func _pigeon_burst(at: Vector3) -> void:
	for i in 8:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.07, 0.04)
		q.mesh = qm
		q.material_override = GraphicsPolish.pbr(Color(0.2, 0.2, 0.22), 0.0, 0.9)
		_city.add_child(q)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 1.4), randf_range(-1, 1)).normalized()
		_pigeons.append({"node": q, "vel": dir * randf_range(0.8, 1.6),
			"life": randf_range(1.2, 1.8), "phase": randf() * TAU})
		q.position = at


func _find_origin() -> Node3D:
	var f := get_tree().root.find_children("*", "XROrigin3D", true, false)
	return f[0] as Node3D if not f.is_empty() else null


func _find_controllers() -> void:
	_controllers.clear()
	if _origin == null:
		return
	for side in ["left", "right"]:
		var n := _origin.get_node_or_null("LeftController" if side == "left" else "RightController")
		if n != null:
			_controllers[side] = n


func _head_pos() -> Vector3:
	var h := _head()
	if h != null:
		return h.global_position
	return Vector3.ZERO


func _head() -> Node3D:
	if _origin != null:
		var c := _origin.get_node_or_null("XRCamera3D")
		if c != null:
			return c
	return null


func _room_center() -> Vector3:
	var b := RoomKit.room_bounds()
	return Vector3(b.position.x + b.size.x * 0.5, 0, b.position.y + b.size.y * 0.5)


func _furniture_blocks() -> Array:
	# World-space AABBs of furniture the city must avoid.
	var out := []
	for f in RoomKit.get_furniture():
		var p: Vector3 = f["position"]
		var s: Vector3 = f["size"]
		out.append(AABB(p - s * 0.5, s))
	for t in RoomKit.get_tables():
		var p2: Vector3 = t["position"]
		var s2: Vector3 = t["size"]
		out.append(AABB(p2 - s2 * 0.5, s2))
	return out


func _build_city() -> void:
	_city = Node3D.new()
	_city.name = "City"
	get_tree().current_scene.add_child(_city)
	var center := _room_center()
	var blocks := _furniture_blocks()
	# City ground slab (cracked asphalt look: dark + emissive cracks skip).
	var slab := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GRID * CELL + 0.6, GRID * CELL + 0.6)
	slab.mesh = pm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.09, 0.10, 0.13)
	smat.roughness = 0.95
	slab.material_override = smat
	slab.position = center + Vector3(0, 0.005, 0)
	_city.add_child(slab)
	# Street grid lines.
	_draw_streets(center)
	# 10 building slots, skipping furniture blocks; couch -> mountains.
	var variants := _building_variants()
	var placed := 0
	for gx in range(GRID):
		for gz in range(GRID):
			if placed >= 10:
				break
			var bp := center + Vector3((gx - GRID / 2.0 + 0.5) * CELL, 0, (gz - GRID / 2.0 + 0.5) * CELL)
			var blocked := false
			for box in blocks:
				if (box as AABB).has_point(Vector3(bp.x, 0.3, bp.z)):
					blocked = true
					break
			if blocked:
				continue
			_spawn_building(variants[placed % variants.size()], bp, placed)
			placed += 1
	# Mountains on the couch / big furniture.
	for box in blocks:
		var b: AABB = box
		if b.size.x * b.size.z > 1.2:
			_spawn_mountain(Vector3(b.position.x - b.size.x * 0.2, 0, b.position.z))
			_spawn_mountain(Vector3(b.position.x + b.size.x * 0.25, 0, b.position.z + 0.2))


func _building_variants() -> Array:
	# 10 slots: 3 staged meshes x scale profiles + 1 procedural tower.
	return [
		{"file": "Building_Small_1.gltf", "s": Vector3(0.55, 0.55, 0.55)},
		{"file": "Building_Medium_2_001.gltf", "s": Vector3(0.5, 0.5, 0.5)},
		{"file": "Building_Large_2.gltf", "s": Vector3(0.45, 0.45, 0.45)},
		{"file": "Building_Small_1.gltf", "s": Vector3(0.45, 1.1, 0.45)},
		{"file": "Building_Medium_2_001.gltf", "s": Vector3(0.75, 0.4, 0.75)},
		{"file": "Building_Large_2.gltf", "s": Vector3(0.35, 0.8, 0.35)},
		{"file": "PROC_TOWER", "s": Vector3(1, 1, 1)},
		{"file": "Building_Small_1.gltf", "s": Vector3(0.6, 0.75, 0.6)},
		{"file": "Building_Medium_2_001.gltf", "s": Vector3(0.4, 0.9, 0.4)},
		{"file": "Building_Large_2.gltf", "s": Vector3(0.55, 0.55, 0.55)},
	]


func _spawn_building(v: Dictionary, pos: Vector3, idx: int) -> void:
	var root := Node3D.new()
	_city.add_child(root)
	root.position = pos
	root.rotation.y = randf() * TAU
	var mesh_holder := Node3D.new()
	root.add_child(mesh_holder)
	if str(v["file"]) == "PROC_TOWER":
		mesh_holder.add_child(_make_proc_tower())
	else:
		var ps: PackedScene = load(BDIR + str(v["file"])) as PackedScene
		if ps == null:
			root.queue_free()
			return
		var inst := ps.instantiate() as Node3D
		mesh_holder.add_child(inst)
	mesh_holder.scale = v["s"]
	_buildings.append({"node": root, "holder": mesh_holder, "hp": 3.0,
		"state": 0, "pos": pos, "score_val": 100 + idx * 15, "smoke_on": false})


func _make_proc_tower() -> Node3D:
	# Procedural skyscraper: dark mass + emissive window grid texture.
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 3.2, 1.0)
	mi.mesh = bm
	var img := Image.create(32, 96, false, Image.FORMAT_RGB8)
	for y in range(96):
		for x in range(32):
			var lit := (x % 4 != 3) and (y % 6 != 5) and randf() < 0.75
			img.set_pixel(x, y, Color(1.0, 0.85, 0.4) if lit else Color(0.05, 0.06, 0.09))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_texture = tex
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 1.4
	mat.uv1_scale = Vector3(2, 2, 2)
	mi.material_override = mat
	mi.position = Vector3(0, 1.6, 0)
	return mi


func _make_rubble() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.28)
	mat.roughness = 1.0
	for i in range(6):
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.15, 0.35), randf_range(0.08, 0.2), randf_range(0.15, 0.35))
		b.mesh = bm
		b.material_override = mat
		b.position = Vector3(randf_range(-0.2, 0.2), randf_range(0.02, 0.12), randf_range(-0.2, 0.2))
		b.rotation = Vector3(randf() * 0.6, randf() * TAU, randf() * 0.6)
		root.add_child(b)
	return root


func _spawn_mountain(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = randf_range(0.35, 0.55)
	cm.height = randf_range(0.5, 0.9)
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.27, 0.24)
	mat.roughness = 1.0
	m.material_override = mat
	m.position = pos + Vector3(0, cm.height * 0.5, 0)
	_city.add_child(m)
	_mountains.append(m)


func _draw_streets(center: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mm := MeshInstance3D.new()
	mm.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.75, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.75, 0.2)
	mat.emission_energy_multiplier = 0.8
	mm.material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := GRID * CELL * 0.5
	for i in range(GRID + 1):
		var o := -half + i * CELL
		im.surface_add_vertex(center + Vector3(o, 0.01, -half))
		im.surface_add_vertex(center + Vector3(o, 0.01, half))
		im.surface_add_vertex(center + Vector3(-half, 0.01, o))
		im.surface_add_vertex(center + Vector3(half, 0.01, o))
	im.surface_end()
	_city.add_child(mm)


func _build_particles() -> void:
	_debris = _make_burst(Color(0.55, 0.5, 0.45), 42, 0.5)
	_smoke = _make_burst(Color(0.25, 0.25, 0.28, 0.8), 30, 1.4)
	_breath_fx = _make_burst(Color(1.0, 0.55, 0.15), 64, 0.35)
	_breath_fx.amount_ratio = 0.0


func _make_burst(color: Color, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = false
	p.explosiveness = 0.9
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.03
	pm.scale_max = 0.09
	pm.color = color
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.albedo_color = color
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.draw_pass_1 = quad
	p.draw_pass_1.material = qmat
	get_tree().current_scene.add_child(p)
	return p


func _burst(p: GPUParticles3D, pos: Vector3) -> void:
	p.global_position = pos
	p.restart()
	p.emitting = true


func _build_hud() -> void:
	_hud_hp = _make_label(Vector3(-0.5, 0.02, 0), 56, Color(0.4, 1.0, 0.5), false)
	_hud_wave = _make_label(Vector3(0.5, 0.02, 0), 56, Color(1.0, 0.85, 0.3), false)
	_hud_score = _make_label(Vector3(0, 0.02, 0.45), 48, Color(0.8, 0.9, 1.0), false)
	_announce = _make_label(Vector3(0, 1.9, -1.2), 110, Color(1.0, 0.6, 0.15), true)
	# Breath meter bar (3D, above the score).
	var bar_bg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.03, 0.01)
	bar_bg.mesh = bm
	var bgm := StandardMaterial3D.new()
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgm.albedo_color = Color(0.15, 0.1, 0.05)
	bar_bg.material_override = bgm
	add_child(bar_bg)
	bar_bg.position = Vector3(0, 0.02, 0.52)
	var bar_fg := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.48, 0.02, 0.012)
	bar_fg.mesh = fm
	var fgm := StandardMaterial3D.new()
	fgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fgm.albedo_color = Color(1.0, 0.55, 0.1)
	fgm.emission_enabled = true
	fgm.emission = Color(1.0, 0.5, 0.1)
	fgm.emission_energy_multiplier = 2.0
	bar_fg.material_override = fgm
	bar_bg.add_child(bar_fg)
	bar_fg.name = "BreathBar"


func _make_label(offset: Vector3, px: int, color: Color, bill: bool) -> Label3D:
	var l := Label3D.new()
	if bill:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = px
	l.modulate = color
	l.outline_size = 10
	l.position = offset
	add_child(l)
	return l


# ---------------------------------------------------------------- loop ---

func _update_kaiju_ambient(delta: float, t: float) -> void:
	var hp := _head_pos()
	# (a) Traffic: stream along lanes, swerve away from the kaiju (panic).
	if _traffic != null:
		_traffic_t += delta
		for i in 16:
			var lane := float(i % 4)
			var dir := 1.0 if i % 8 < 4 else -1.0
			var x := fmod(_traffic_t * (0.5 + lane * 0.12) * dir + float(i) * 1.7, 7.0) - 3.5
			var z := -1.5 + lane * 1.0
			# Panic swerve: lateral offset grows near the kaiju.
			var to_k: Vector2 = Vector2(x - hp.x, z - hp.z)
			var panic := clampf(1.5 - to_k.length() * 0.4, 0.0, 1.0)
			z += panic * 0.45 * signf(to_k.y + 0.01)
			_traffic.multimesh.set_instance_transform(i, Transform3D(
				Basis(Vector3.UP, PI * 0.5 if dir > 0 else -PI * 0.5),
				Vector3(x, 0.035, z)))
	# (b) Pigeon bursts: fly, flap, fade; pooled (freed at end of life).
	for i in range(_pigeons.size() - 1, -1, -1):
		var pg: Dictionary = _pigeons[i]
		var qn: MeshInstance3D = pg["node"]
		if not is_instance_valid(qn):
			_pigeons.remove_at(i)
			continue
		var life: float = float(pg["life"]) - delta
		pg["life"] = life
		if life <= 0.0:
			qn.queue_free()
			_pigeons.remove_at(i)
			continue
		qn.position += (pg["vel"] as Vector3) * delta
		pg["vel"] = (pg["vel"] as Vector3) * (1.0 - 0.4 * delta)
		# 2-frame flap via scale-x; fade at end of life.
		qn.scale.x = 0.5 + 0.5 * absf(sin(t * 18.0 + float(pg["phase"])))
		var m := qn.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color.a = clampf(life, 0.0, 1.0)
	# (d) Helicopters circle; searchlight cones sweep.
	for h in _helis:
		var hn: Node3D = h["node"]
		var ph: float = float(h["phase"])
		var a := t * 0.35 + ph
		hn.position = Vector3(cos(a) * float(h["r"]), 3.2 + 0.2 * sin(t * 0.8 + ph),
			sin(a) * float(h["r"]))
		var cn: Node3D = h["cone"]
		cn.rotation.y = t * 1.4 + ph
		cn.rotation.x = 0.4 + 0.2 * sin(t * 0.9 + ph)
	# (e) Window blackout: districts near the kaiju flicker out.
	for w in _win_mats:
		var wm := w["mat"] as StandardMaterial3D
		if wm == null:
			continue
		var d: float = (w["pos"] as Vector3).distance_to(Vector3(hp.x, 0, hp.z))
		var want := 1.0 if d > 2.2 else 0.12
		var k: float = lerpf(float(w["k"]), want, minf(1.0, 2.0 * delta))
		w["k"] = k
		# Flicker while dying (desync via position hash).
		var flick := 1.0
		if k < 0.99 and k > 0.13:
			flick = 0.6 + 0.4 * sin(t * 23.0 + (w["pos"] as Vector3).x * 12.0)
		wm.emission_energy_multiplier = 1.4 * k * flick


func _process(delta: float) -> void:
	if _game_over:
		return
	_update_kaiju_ambient(delta, Time.get_ticks_msec() / 1000.0)
	_poll_attacks(delta)
	_update_military(delta)
	_update_pellets(delta)
	_update_breath(delta)
	_update_combo(delta)
	_update_hud(delta)
	_update_shake(delta)
	if _wave_state == "cleared":
		_wave_pause -= delta
		if _wave_pause <= 0.0:
			if _wave >= MAX_WAVE:
				_victory()
			else:
				_start_wave(_wave + 1)
	if _announce_t > 0.0:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce.text = ""


func _poll_attacks(delta: float) -> void:
	if _stomp_cd > 0.0:
		_stomp_cd -= delta
	if _swipe_cd > 0.0:
		_swipe_cd -= delta
	# --- Stomp: body-tracked feet ---
	var stomped := false
	if BodyTracker.is_available():
		for j in [XRBodyTracker.JOINT_LEFT_FOOT, XRBodyTracker.JOINT_RIGHT_FOOT]:
			var p = BodyTracker.joint_position(j, _origin)
			if p == null:
				continue
			var pv: Vector3 = p
			var prev: Vector3 = _feet_prev.get(j, pv)
			var vel: Vector3 = (pv - prev) / maxf(delta, 0.001)
			_feet_prev[j] = pv
			if vel.y < -1.4 and pv.y < 0.30 and _stomp_cd <= 0.0:
				_do_stomp(Vector3(pv.x, 0, pv.z), 1.0)
				stomped = true
				_note_input("body")
	# --- Fallback: controller slam ---
	if not stomped:
		for side in _controllers.keys():
			var ctl: XRController3D = _controllers[side]
			if XRServer.get_tracker(ctl.tracker) == null:
				continue
			var cp: Vector3 = ctl.global_position
			var prev: Vector3 = _ctl_prev.get(side, cp)
			var vel := (cp - prev) / maxf(delta, 0.001)
			_ctl_prev[side] = cp
			if vel.y < -2.2 and _stomp_cd <= 0.0:
				_do_stomp(Vector3(cp.x, 0, cp.z), 0.85)
				_note_input("controllers")
	# --- Tail swipe: fast spin ---
	var h := _head()
	if h != null and _swipe_cd <= 0.0:
		var yaw := h.global_rotation.y
		var dyaw := absf(wrapf(yaw - _yaw_prev, -PI, PI)) / maxf(delta, 0.001)
		_yaw_prev = yaw
		if dyaw > 3.2:
			_spin_acc += delta
			if _spin_acc > 0.28:
				_spin_acc = 0.0
				_do_swipe()
				_note_input("body")
		else:
			_spin_acc = maxf(0.0, _spin_acc - delta * 2.0)
	# --- Atomic breath: both triggers ---
	var tl := _trigger_held("left")
	var tr := _trigger_held("right")
	_breathing = tl and tr and _breath > 1.0 and not _game_over
	if _breathing:
		_note_input("controllers")


func _trigger_held(side: String) -> bool:
	var ctl: XRController3D = _controllers.get(side)
	if ctl == null or XRServer.get_tracker(ctl.tracker) == null:
		return false
	return XRUIPointer.trigger_pressed(ctl)


func _do_stomp(at: Vector3, power: float) -> void:
	_stomp_cd = 0.45
	# v0.11.0 VFX: signature stomp — dust ring + shockwave + debris.
	VFX.stomp(_city, at, 0.6 + 0.5 * power)
	_burst(_debris, at + Vector3(0, 0.15, 0))
	# v0.11.0 ambient (b): pigeons erupt off the nearest standing rooftop.
	var best := Vector3.ZERO
	var best_d := 999.0
	for b in _buildings:
		if int(b["state"]) >= 2:
			continue
		var d: float = (b["pos"] as Vector3).distance_to(at)
		if d < best_d:
			best_d = d
			best = b["pos"]
	if best_d < 3.0:
		_pigeon_burst(best + Vector3(0, 1.1, 0))
	_shake = maxf(_shake, 0.35 * power)
	Haptics.thump("both")
	Haptics.sub_bass(0.5, "both")
	ArtKit.game_sfx(self, "stomp", randf_range(0.85, 1.1))
	_damage_radius(at, STOMP_R * power, 3.0 * power, "STOMP")


func _do_swipe() -> void:
	_swipe_cd = 1.2
	var h := _head()
	var at := Vector3(h.global_position.x, 0, h.global_position.z) if h != null else _room_center()
	_burst(_debris, at + Vector3(0, 0.3, 0))
	_shake = maxf(_shake, 0.3)
	Haptics.impact(0.9, "both")
	ArtKit.game_sfx(self, "boom", 0.8)
	_announce_text("TAIL SWIPE!", 1.0)
	_damage_radius(at, SWIPE_R, 2.0, "SWIPE")


func _update_breath(delta: float) -> void:
	if _breathing:
		_breath = maxf(0.0, _breath - delta * 28.0)
		var h := _head()
		if h != null:
			var origin: Vector3 = h.global_position + Vector3(0, -0.1, 0)
			var dir := -h.global_transform.basis.z
			dir.y = clampf(dir.y - 0.35, -0.8, 0.1)
			dir = dir.normalized()
			_breath_fx.amount_ratio = 1.0
			_breath_fx.global_position = origin + dir * 1.2
			_breath_fx.process_material.direction = dir
			_breath_fx.emitting = true
			# Damage along the cone every frame (scaled by delta).
			_breath_damage(origin, dir, delta)
		if not _breath_fx.emitting:
			ArtKit.game_sfx(self, "breath")
	else:
		_breath = minf(100.0, _breath + delta * 16.0)
		_breath_fx.emitting = false
		_breath_fx.amount_ratio = 0.0


func _breath_damage(origin: Vector3, dir: Vector3, delta: float) -> void:
	var mic_boost := 1.0 + _mic_loud * 0.5
	for b in _buildings:
		if int(b["state"]) >= 2:
			continue
		var bp: Vector3 = b["pos"]
		var to: Vector3 = bp - origin
		var along := to.dot(dir)
		if along < 0.3 or along > BREATH_LEN:
			continue
		var perp := (to - dir * along).length()
		if perp < BREATH_W * (0.5 + along / BREATH_LEN):
			b["hp"] = float(b["hp"]) - delta * 6.0 * mic_boost
			if float(b["hp"]) <= 0.0:
				_destroy_building(b, "ATOMIC BREATH")
	for m in _military:
		var mp: Vector3 = (m["node"] as Node3D).global_position
		var to2: Vector3 = mp - origin
		var along2 := to2.dot(dir)
		if along2 < 0.3 or along2 > BREATH_LEN:
			continue
		var perp2 := (to2 - dir * along2).length()
		if perp2 < BREATH_W:
			_damage_military(m, delta * 30.0)


func _damage_radius(at: Vector3, radius: float, dmg: float, label: String) -> void:
	for b in _buildings:
		if int(b["state"]) >= 2:
			continue
		var bp: Vector3 = b["pos"]
		var d := Vector2(bp.x - at.x, bp.z - at.z).length()
		if d <= radius:
			b["hp"] = float(b["hp"]) - dmg * (1.0 - d / (radius + 0.001) * 0.5)
			if float(b["hp"]) <= 0.0:
				_destroy_building(b, label)
	for m in _military.duplicate():
		var mp: Vector3 = (m["node"] as Node3D).global_position
		if Vector2(mp.x - at.x, mp.z - at.z).length() <= radius:
			_damage_military(m, dmg * 8.0)


func _destroy_building(b: Dictionary, how: String) -> void:
	b["state"] = 2
	b["hp"] = 0.0
	var holder: Node3D = b["holder"]
	_burst(_debris, (b["pos"] as Vector3) + Vector3(0, 0.35, 0))
	_burst(_smoke, (b["pos"] as Vector3) + Vector3(0, 0.5, 0))
	for c in holder.get_children():
		c.queue_free()
	holder.add_child(_make_rubble())
	_destroyed += 1
	# v0.11.0 ambient (c): a smoke column moves to the fresh rubble.
	if not _smoke_cols.is_empty():
		var col: GPUParticles3D = _smoke_cols[_destroyed % _smoke_cols.size()]
		col.position = (b["pos"] as Vector3) + Vector3(0, 0.3, 0)
	# Collateral combo: destructions within 4 s chain the multiplier.
	if _combo_t > 0.0:
		_combo += 1
	else:
		_combo = 1
	_combo_t = 4.0
	var pts := int(float(b["score_val"]) * (1.0 + 0.5 * float(_combo - 1)))
	_score += pts
	if _combo >= 3:
		_announce_text("%s x%d  +%d" % [how, _combo, pts], 1.4)
	ArtKit.game_sfx(self, "crumble", randf_range(0.8, 1.15))
	Haptics.impact(0.6, "both")
	_telemetry("kaiju_destroy", {"how": how, "combo": _combo, "score": _score})


func _damage_building_visual(b: Dictionary) -> void:
	# State 1: tilt + smoke wisp (called once when hp drops below half).
	if int(b["state"]) != 0 or float(b["hp"]) > 1.5:
		return
	b["state"] = 1
	var node: Node3D = b["node"]
	node.rotation.z = randf_range(-0.09, 0.09)
	node.rotation.x = randf_range(-0.06, 0.06)
	_burst(_smoke, (b["pos"] as Vector3) + Vector3(0, 0.45, 0))
	ArtKit.game_sfx(self, "hit", 0.7)


# -------------------------------------------------------------- military ---

func _start_wave(n: int) -> void:
	_wave = n
	_wave_state = "fighting"
	_announce_text("WAVE %d" % n, 2.2)
	ArtKit.game_sfx(self, "wave")
	var center := _room_center()
	var comp := _wave_comp(n)
	for e in comp:
		if e == "tank":
			_spawn_tank(center)
		elif e == "jet":
			_spawn_flyer("jet", center, 2.6)
		elif e == "gunship":
			_spawn_flyer("gunship", center, 2.0)
	_telemetry("kaiju_wave", {"wave": n})


func _wave_comp(n: int) -> Array:
	match n:
		1: return ["tank", "tank", "tank"]
		2: return ["tank", "tank", "tank", "jet", "jet"]
		3: return ["tank", "tank", "tank", "tank", "jet", "jet", "gunship"]
		4: return ["tank", "tank", "tank", "tank", "tank", "jet", "jet", "jet", "gunship"]
		_: return ["tank", "tank", "tank", "tank", "tank", "tank", "jet", "jet", "jet", "gunship", "gunship"]


func _spawn_tank(center: Vector3) -> void:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.14, 0.22)
	body.mesh = bm
	var tur := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.08
	cm.height = 0.09
	tur.mesh = cm
	tur.position = Vector3(0, 0.11, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.32, 0.22)
	mat.roughness = 0.8
	body.material_override = mat
	tur.material_override = mat
	root.add_child(body)
	root.add_child(tur)
	var ang := randf() * TAU
	var r := GRID * CELL * 0.75
	root.position = center + Vector3(cos(ang) * r, 0.07, sin(ang) * r)
	get_tree().current_scene.add_child(root)
	_military.append({"kind": "tank", "node": root, "hp": 20.0, "fire_cd": randf_range(1.0, 2.5), "speed": 0.35})


func _spawn_flyer(kind: String, center: Vector3, height: float) -> void:
	var file := "bat.glb" if kind == "jet" else "dragon.glb"
	var ps: PackedScene = load(MDIR + file) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	# Military-green tint.
	_tint(inst, Color(0.35, 0.45, 0.3) if kind == "jet" else Color(0.45, 0.35, 0.25))
	var ang := randf() * TAU
	var r := GRID * CELL * 0.7
	inst.position = center + Vector3(cos(ang) * r, height, sin(ang) * r)
	inst.scale = Vector3.ONE * (0.5 if kind == "jet" else 0.7)
	get_tree().current_scene.add_child(inst)
	_play_anim(inst, "Flying")
	_military.append({"kind": kind, "node": inst, "hp": 14.0 if kind == "jet" else 30.0,
		"fire_cd": randf_range(1.5, 3.0), "speed": 1.1 if kind == "jet" else 0.7,
		"ang": ang, "r": r, "h": height})


func _tint(node: Node, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		(mi as MeshInstance3D).material_override = m


func _play_anim(node: Node, anim: String) -> void:
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		for a in p.get_animation_list():
			if str(a).to_lower().contains(anim.to_lower()):
				p.play(a)
				return
		if p.get_animation_list().size() > 0:
			p.play(p.get_animation_list()[0])


func _update_military(delta: float) -> void:
	var h := _head()
	var hp_pos := Vector3(h.global_position.x, 0, h.global_position.z) if h != null else _room_center()
	for m in _military.duplicate():
		var node: Node3D = m["node"]
		if not is_instance_valid(node):
			_military.erase(m)
			continue
		var kind: String = m["kind"]
		if kind == "tank":
			var to: Vector3 = hp_pos - node.position
			to.y = 0
			if to.length() > 0.9:
				node.position += to.normalized() * float(m["speed"]) * delta
				node.rotation.y = atan2(to.x, to.z)
		else:
			m["ang"] = float(m["ang"]) + delta * float(m["speed"]) * 0.5
			var c := _room_center()
			node.position = Vector3(c.x + cos(float(m["ang"])) * float(m["r"]), float(m["h"]) + sin(Time.get_ticks_msec() / 900.0) * 0.15, c.z + sin(float(m["ang"])) * float(m["r"]))
			node.rotation.y = float(m["ang"]) + PI * 0.5
		m["fire_cd"] = float(m["fire_cd"]) - delta
		if float(m["fire_cd"]) <= 0.0:
			m["fire_cd"] = randf_range(2.0, 4.0) - _wave * 0.2
			_fire_pellet(node.global_position + Vector3(0, 0.15, 0), hp_pos)
	if _wave_state == "fighting" and _military.is_empty() and not _game_over:
		_wave_state = "cleared"
		_wave_pause = 3.0
		_score += 250 * _wave
		_announce_text("WAVE %d CLEARED  +%d" % [_wave, 250 * _wave], 2.5)
		ArtKit.game_sfx(self, "win", 1.2)


func _fire_pellet(from: Vector3, target: Vector3) -> void:
	var p: MeshInstance3D
	if _pellet_pool.is_empty():
		p = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.06
		p.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.4, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.1)
		mat.emission_energy_multiplier = 3.0
		p.material_override = mat
		get_tree().current_scene.add_child(p)
	else:
		p = _pellet_pool.pop_back()
		p.visible = true
	var dir: Vector3 = (target + Vector3(0, 1.2, 0) - from).normalized()
	_pellets.append({"node": p, "vel": dir * 3.5, "life": 4.0})
	p.global_position = from
	ArtKit.game_sfx(self, "shot", randf_range(0.9, 1.3))


func _update_pellets(delta: float) -> void:
	var h := _head()
	for p in _pellets.duplicate():
		var node: MeshInstance3D = p["node"]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_recycle_pellet(p)
			continue
		node.global_position += (p["vel"] as Vector3) * delta
		if h != null:
			var d: float = node.global_position.distance_to(h.global_position)
			if d < 0.45:
				_recycle_pellet(p)
				_damage_player(4.0 if _wave < 4 else 6.0)


func _recycle_pellet(p: Dictionary) -> void:
	(p["node"] as MeshInstance3D).visible = false
	_pellet_pool.append(p["node"])
	_pellets.erase(p)


func _damage_military(m: Dictionary, dmg: float) -> void:
	m["hp"] = float(m["hp"]) - dmg
	if float(m["hp"]) <= 0.0:
		var node: Node3D = m["node"]
		_burst(_debris, node.global_position)
		ArtKit.game_sfx(self, "boom", randf_range(0.9, 1.2))
		_score += 50
		_play_anim(node, "Death")
		node.queue_free()
		_military.erase(m)
		_telemetry("kaiju_kill", {"kind": m["kind"]})


func _damage_player(dmg: float) -> void:
	if _game_over:
		return
	_hp -= dmg
	Haptics.impact(clampf(dmg / 10.0, 0.3, 1.0), "both")
	ArtKit.game_sfx(self, "hit", 0.7)
	if _hp <= 0.0:
		_hp = 0.0
		_defeat()


# ---------------------------------------------------------------- meta ---

func _update_combo(delta: float) -> void:
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0


func _update_hud(_delta: float) -> void:
	_hud_hp.text = "HP %d" % int(_hp)
	_hud_wave.text = "WAVE %d/5" % _wave
	_hud_score.text = "SCORE %d   RAZED %d/10" % [_score, _destroyed]
	if _announce_t > 0.0:
		return
	var bar := get_node_or_null("BreathBar") as MeshInstance3D
	if bar != null:
		bar.scale.x = maxf(_breath / 100.0, 0.001)
	# Keep HUD near the player (floor-anchored, static-ish).
	var h := _head()
	if h != null:
		var base := Vector3(h.global_position.x, 0, h.global_position.z)
		_hud_hp.position = base + Vector3(-0.55, 0.03, 0.35)
		_hud_wave.position = base + Vector3(0.55, 0.03, 0.35)
		_hud_score.position = base + Vector3(0, 0.03, 0.55)


func _update_shake(delta: float) -> void:
	if _origin == null:
		return
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 1.8)
		_origin.position = _base_origin_pos + Vector3(
			randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.05
	elif _origin.position != _base_origin_pos:
		_origin.position = _base_origin_pos


func _announce_text(t: String, dur: float) -> void:
	_announce.text = t
	_announce_t = dur


func _victory() -> void:
	_game_over = true
	_wave_state = "done"
	_score += int(_hp) * 10
	_announce_text("CITY RAZED! SCORE %d" % _score, 8.0)
	ArtKit.game_sfx(self, "win")
	ArtKit.stinger(self, "success")
	Haptics.play_sequence("fanfare", "both")
	_telemetry("kaiju_end", {"result": "victory", "score": _score, "razed": _destroyed})


func _defeat() -> void:
	_game_over = true
	_announce_text("KAIJU DOWN — SCORE %d" % _score, 8.0)
	ArtKit.game_sfx(self, "lose")
	ArtKit.stinger(self, "fail")
	_telemetry("kaiju_end", {"result": "defeat", "score": _score, "wave": _wave})



func _note_input(method: String) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.note_input_method(method)


func _telemetry(ev: String, fields: Dictionary) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event(ev, fields)
