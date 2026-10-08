## Wizard Academy: a magic-school progression game for NEXUS ARCADE.
## Great-hall environment built from real Kenney castle-kit models (walls,
## pillars, doorway, banners, towers), floating candles, house tables.
## Gameplay: 3 class lessons (Charms: pinch-hold levitation; Potions: pour
## ingredients in recipe order; Defense: palm-out shield blocks), then a timed
## EXAMS gauntlet mixing all three, then gesture DUELS vs an AI wizard
## (circle=fireball, zigzag=lightning, flick=shield - the Spell Duel language).
## Grades O/E/A/T and house points persist in user://nexus_wizard.cfg.
## Desktop: mouse click/drag/hold. XR: right-hand pinch. R restarts the lesson.
extends Node3D

const SAVE_PATH := "user://nexus_wizard.cfg"
const MODEL_DIR := "res://assets/models/wizard_academy/"
const GRADES := ["T", "A", "E", "O"]
const GRADE_NAMES := {"T": "Troll", "A": "Acceptable", "E": "Exceeds", "O": "Outstanding"}
const HOUSE_NAMES := ["Emberfox", "Tidewhale", "Stormowl", "Thornbadger"]
const HOUSE_COLORS := [Color(0.85, 0.28, 0.14), Color(0.20, 0.45, 0.92), Color(0.30, 0.72, 0.72), Color(0.32, 0.68, 0.30)]
const HOUSE_SIGILS := ["F", "W", "O", "B"]
const LESSON_POINTS := {"T": 2, "A": 10, "E": 20, "O": 30}
const EXAM_POINTS := {"T": 5, "A": 20, "E": 35, "O": 50}
const CHEST_POS := Vector3(0.0, 1.35, 2.3)

var camera: Camera3D = null
var elapsed := 0.0
var _model_cache := {}

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)

# --- persistence ---
var house := 0
var house_points := [0, 0, 0, 0]
var best_grades := {"charms": "-", "potions": "-", "defense": "-", "exams": "-"}
var duel_wins := 0

# --- mode / input state ---
var _mode := "menu"
var _last_lesson := "menu"
# Test hook: when true, _pointer_pos() returns _dbg_pointer (headless tests).
var _dbg_pointer := Vector3.ZERO
var _dbg_pointer_on := false
var _prev_press := false
var _grab_depth := 2.2
var buttons: Array = []
var hover_id := ""

# --- station roots ---
var menu_root: Node3D = null
var charms_root: Node3D = null
var potions_root: Node3D = null
var defense_root: Node3D = null
var duel_root: Node3D = null

# --- hud ---
var hud_label: Label3D = null
var msg_label: Label3D = null
var hint_label: Label3D = null

# --- charms ---
var charm_orb: MeshInstance3D = null
var charm_ring: MeshInstance3D = null
var charm_ring_mat: StandardMaterial3D = null
var charm_bar: MeshInstance3D = null
var charm_orb_mat: StandardMaterial3D = null
var charm_grabbed := false
var charm_hold := 0.0
var charm_need := 3.0
var charm_total := 3
var charm_done := 0
var charm_t0 := 0.0
const CHARM_HOME := Vector3(0.0, 1.0, 0.8)
const CHARM_TARGET := Vector3(0.0, 1.75, 0.8)

# --- potions ---
var cauldron_liquid_mat: StandardMaterial3D = null
var cauldron_liquid: MeshInstance3D = null
var cauldron_pos := Vector3(0.0, 0.0, -0.4)
var bottles: Array = []
var recipe: Array = []
var recipe_idx := 0
var recipe_label: Label3D = null
var held_bottle := -1
var pour_t := 0.0
var potion_mistakes := 0
var potion_t0 := 0.0
const BOTTLE_NAMES := ["Moondew", "Firepepper", "Starshroom"]
const BOTTLE_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.30, 0.12), Color(0.65, 0.30, 1.0)]
const BOTTLE_HOME := [Vector3(1.55, 1.02, -0.4), Vector3(2.20, 1.02, -0.4), Vector3(2.85, 1.02, -0.4)]
# v0.9.1: real potion bottles from the Quaternius fantasyprops megakit (CC0),
# staged in assets/models/wizard_academy/. Primitive build stays as fallback.
const BOTTLE_MODELS := ["Potion_1", "Potion_2", "Potion_4"]
const BOTTLE_MODEL_SCALE := 2.2

# --- defense ---
var shield_bubble: MeshInstance3D = null
var shield_mat: StandardMaterial3D = null
var projectiles: Array = []
var def_spawn_t := 0.0
var def_total := 8
var def_spawned := 0
var def_blocked := 0
var def_t0 := 0.0

# --- exams ---
var exam_steps: Array = []
var exam_idx := 0
var exam_timer := 0.0
var exam_score := 0.0
const EXAM_TIME := 110.0

# --- duel ---
var duel_wizard: Node3D = null
var duel_hat_mat: StandardMaterial3D = null
var duel_staff_tip: MeshInstance3D = null
var p_hp := 100.0
var ai_hp := 100.0
var duel_fireballs: Array = []
var duel_bolts: Array = []
var duel_path: Array = []
var duel_drawing := false
var duel_path_t0 := 0.0
var duel_cast_cd := 0.0
var duel_ai_t := 2.5
var duel_phase := 0.0
var duel_gesture_cursor: MeshInstance3D = null
var duel_gesture_im := ImmediateMesh.new()
var duel_shield_t := 0.0
var duel_shield_bubble: MeshInstance3D = null
var duel_p_hp_fg: MeshInstance3D = null
var duel_ai_hp_fg: MeshInstance3D = null
const DUEL_GESTURE_WINDOW := 0.6
const DUEL_CAST_CD := 0.8


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "wizard_academy_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_save()
	_build_hall()
	_build_menu()
	_build_charms()
	_build_potions()
	_build_defense()
	_build_duel()
	_build_hud()
	_set_mode("menu")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 2.2, -1.5), 3.5, 50)
	_apply_room_layout()


## v0.7.0: potion station rests on the largest real table; the spell chart
## (recipe board) is pinned to the largest real wall. Guarded; fallback keeps
## the default great-hall layout.
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): table -> arcane potion altar (potions brew on the big table)
	_morph_anchors("TABLE", "arcane", 1)
	var best := {}
	var best_a := 0.0
	for t_v in _room_tables:
		var t: Dictionary = t_v
		var a: float = (t["size"] as Vector3).x * (t["size"] as Vector3).z
		if a > best_a:
			best_a = a
			best = t
	if not best.is_empty():
		var tp: Vector3 = best["position"]
		var top_y: float = tp.y + (best["size"] as Vector3).y * 0.5
		potions_root.position = to_local(Vector3(tp.x, top_y, tp.z))
	var bw := {}
	var ba := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var wa: float = (w["size"] as Vector2).x * (w["size"] as Vector2).y
		if wa > ba:
			ba = wa
			bw = w
	if not bw.is_empty() and recipe_label != null:
		var n: Vector3 = bw["normal"]
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
		var fw: Vector3 = (bw["position"] as Vector3) + n * 0.06
		fw.y = 1.9
		recipe_label.top_level = true
		recipe_label.global_position = fw
		var c := _room_bounds.get_center()
		var d := Vector2(c.x - fw.x, c.y - fw.z)
		recipe_label.rotation.y = atan2(d.x, d.y) if d.length() > 0.05 else 0.0


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.7, 3.4)
		cam.look_at(Vector3(0.0, 1.25, -1.5), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.60)
	env.ambient_light_energy = 0.75
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.12)
	env.fog_density = 0.018
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.85)


# ---------------------------------------------------------------- models ---
func _model(model_name: String) -> Node3D:
	if _model_cache.has(model_name):
		var ps: PackedScene = _model_cache[model_name]
		if ps != null:
			return ps.instantiate() as Node3D
		_model_cache.erase(model_name)
	var path := MODEL_DIR + model_name + ".fbx"
	if not ResourceLoader.exists(path):
		push_warning("[wizard] missing model: " + path)
		return null
	var ps2 := load(path) as PackedScene
	if ps2 == null:
		push_warning("[wizard] failed to load: " + path)
		return null
	_model_cache[model_name] = ps2
	return ps2.instantiate() as Node3D


func _find_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_meshes(c, out)


func _model_size(model_name: String) -> Vector3:
	var inst := _model(model_name)
	if inst == null:
		return Vector3(2.0, 2.0, 2.0)
	var meshes: Array = []
	_find_meshes(inst, meshes)
	var box := AABB()
	var started := false
	for mi in meshes:
		var ta: AABB = (mi as Node3D).transform * (mi as MeshInstance3D).get_aabb()
		if not started:
			box = ta
			started = true
		else:
			box = box.merge(ta)
	inst.free()
	if not started:
		return Vector3(2.0, 2.0, 2.0)
	return box.size


func _recolor_contains(root: Node, substr: String, color: Color, glow_energy: float = 0.0) -> void:
	var meshes: Array = []
	_find_meshes(root, meshes)
	var mat: StandardMaterial3D
	if glow_energy > 0.0:
		mat = GraphicsPolish.glow(color, glow_energy)
	else:
		mat = GraphicsPolish.pbr_preset(color, "matte")
	for mi in meshes:
		if (mi as Node).name.to_lower().find(substr.to_lower()) >= 0:
			(mi as MeshInstance3D).material_override = mat


func _recolor_all(root: Node, color: Color, glow_energy: float = 0.0) -> void:
	var meshes: Array = []
	_find_meshes(root, meshes)
	var mat: StandardMaterial3D
	if glow_energy > 0.0:
		mat = GraphicsPolish.glow(color, glow_energy)
	else:
		mat = GraphicsPolish.pbr_preset(color, "matte")
	for mi in meshes:
		(mi as MeshInstance3D).material_override = mat


func _tile_models(parent: Node3D, model_name: String, from_p: Vector3, to_p: Vector3, rot_y_deg: float) -> void:
	var w: float = _model_size(model_name).x
	if w < 0.05:
		w = 2.0
	var length := from_p.distance_to(to_p)
	var n := maxi(1, int(round(length / w)))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var m := _model(model_name)
		if m == null:
			continue
		m.position = from_p.lerp(to_p, t)
		m.rotation.y = deg_to_rad(rot_y_deg)
		parent.add_child(m)


# ------------------------------------------------------------------- hall ---
var candle_flames: Array = []
var candle_t := 0.0

func _build_hall() -> void:
	var hall := Node3D.new()
	hall.name = "GreatHall"
	add_child(hall)
	# Floor + carpet runner.
	var floor_mi := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(13.0, 0.1, 11.0)
	floor_mi.mesh = fbox
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.23, 0.22, 0.28), "matte")
	floor_mi.position = Vector3(0.0, -0.05, -1.0)
	hall.add_child(floor_mi)
	var carpet := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(2.4, 0.12, 7.6)
	carpet.mesh = cbox
	carpet.material_override = GraphicsPolish.pbr_preset(Color(0.45, 0.08, 0.12), "matte")
	carpet.position = Vector3(0.0, 0.01, -1.0)
	hall.add_child(carpet)
	# Walls: back (with doorway gap), sides.
	_tile_models(hall, "wall", Vector3(-6.0, 0.0, -6.0), Vector3(-1.1, 0.0, -6.0), 0.0)
	_tile_models(hall, "wall", Vector3(1.1, 0.0, -6.0), Vector3(6.0, 0.0, -6.0), 0.0)
	_tile_models(hall, "wall", Vector3(-6.0, 0.0, -6.0), Vector3(-6.0, 0.0, 4.0), 90.0)
	_tile_models(hall, "wall", Vector3(6.0, 0.0, -6.0), Vector3(6.0, 0.0, 4.0), 90.0)
	var doorway := _model("wall-doorway")
	if doorway != null:
		doorway.position = Vector3(0.0, 0.0, -6.0)
		hall.add_child(doorway)
	var door := _model("door")
	if door != null:
		door.position = Vector3(0.0, 0.0, -6.35)
		hall.add_child(door)
	var stairs := _model("stairs-stone")
	if stairs != null:
		stairs.position = Vector3(0.0, 0.0, -5.1)
		stairs.rotation.y = PI
		hall.add_child(stairs)
	# Pillars flanking the hall.
	for px in [-4.2, 4.2]:
		for pz in [-4.0, -1.0, 2.0]:
			var pil := _model("wall-pillar")
			if pil != null:
				pil.position = Vector3(px, 0.0, pz)
				hall.add_child(pil)
	# Towers outside the doorway.
	for tx in [-3.4, 3.4]:
		var part_names := ["tower-square-base", "tower-square-mid", "tower-square-top-roof"]
		var y := 0.0
		for pname in part_names:
			var part := _model(pname)
			if part == null:
				continue
			part.position = Vector3(tx, y, -7.6)
			hall.add_child(part)
			y += _model_size(pname).y
	# House banners on the back wall.
	for h in 4:
		var banner := _model("flag-banner-long")
		if banner == null:
			continue
		banner.position = Vector3(-3.0 + float(h) * 2.0, 2.9, -5.82)
		hall.add_child(banner)
		_recolor_all(banner, HOUSE_COLORS[h])
		var sigil := GraphicsPolish.make_label(HOUSE_SIGILS[h], 96, Color(1.0, 0.95, 0.75))
		sigil.position = Vector3(-3.0 + float(h) * 2.0, 2.15, -5.55)
		sigil.pixel_size = 0.006
		hall.add_child(sigil)
	# House tables with plates and goblets.
	for tx in [-2.6, 2.6]:
		var table := Node3D.new()
		table.position = Vector3(tx, 0.0, -1.2)
		hall.add_child(table)
		var top := MeshInstance3D.new()
		var tbox := BoxMesh.new()
		tbox.size = Vector3(3.4, 0.1, 1.0)
		top.mesh = tbox
		top.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
		top.position = Vector3(0.0, 0.78, 0.0)
		table.add_child(top)
		for lx in [-1.5, 1.5]:
			for lz in [-0.4, 0.4]:
				var leg := MeshInstance3D.new()
				var lbox := BoxMesh.new()
				lbox.size = Vector3(0.12, 0.78, 0.12)
				leg.mesh = lbox
				leg.material_override = GraphicsPolish.pbr_preset(Color(0.28, 0.17, 0.09), "matte")
				leg.position = Vector3(lx, 0.39, lz)
				table.add_child(leg)
		for side in [-0.85, 0.85]:
			var bench := MeshInstance3D.new()
			var bbox := BoxMesh.new()
			bbox.size = Vector3(3.0, 0.08, 0.28)
			bench.mesh = bbox
			bench.material_override = GraphicsPolish.pbr_preset(Color(0.30, 0.19, 0.10), "matte")
			bench.position = Vector3(0.0, 0.45, side)
			table.add_child(bench)
		for i in 4:
			var plate := MeshInstance3D.new()
			var pcyl := CylinderMesh.new()
			pcyl.top_radius = 0.11
			pcyl.bottom_radius = 0.09
			pcyl.height = 0.025
			plate.mesh = pcyl
			plate.material_override = GraphicsPolish.pbr(Color(0.92, 0.90, 0.85), 0.1, 0.4)
			plate.position = Vector3(-1.2 + float(i) * 0.8, 0.845, 0.0)
			table.add_child(plate)
			var gob := MeshInstance3D.new()
			var gcyl := CylinderMesh.new()
			gcyl.top_radius = 0.035
			gcyl.bottom_radius = 0.025
			gcyl.height = 0.12
			gob.mesh = gcyl
			gob.material_override = GraphicsPolish.pbr(Color(0.95, 0.75, 0.25), 0.9, 0.3)
			gob.position = Vector3(-1.2 + float(i) * 0.8, 0.90, 0.28)
			table.add_child(gob)
	# Floating candles above the tables and aisle.
	var candle_spots: Array = []
	for tx in [-2.6, 2.6]:
		for i in 4:
			candle_spots.append(Vector3(tx - 1.2 + float(i) * 0.8, 2.1 + float(i % 2) * 0.25, -1.2))
	for i in 4:
		candle_spots.append(Vector3(-0.9 + float(i) * 0.6, 2.5, 0.6))
	for i in candle_spots.size():
		var spot: Vector3 = candle_spots[i]
		var cg := Node3D.new()
		cg.position = spot
		hall.add_child(cg)
		var wax := MeshInstance3D.new()
		var wcyl := CylinderMesh.new()
		wcyl.top_radius = 0.028
		wcyl.bottom_radius = 0.032
		wcyl.height = 0.13
		wax.mesh = wcyl
		wax.material_override = GraphicsPolish.pbr(Color(0.95, 0.90, 0.78), 0.0, 0.6)
		cg.add_child(wax)
		var flame := MeshInstance3D.new()
		var fsm := SphereMesh.new()
		fsm.radius = 0.024
		fsm.height = 0.048
		flame.mesh = fsm
		flame.material_override = GraphicsPolish.glow(Color(1.0, 0.62, 0.18), 2.6)
		flame.position = Vector3(0.0, 0.095, 0.0)
		cg.add_child(flame)
		candle_flames.append({"node": cg, "base_y": spot.y, "phase": float(i) * 0.9})
	if candle_flames.size() >= 3:
		for li in 3:
			var spot2: Vector3 = (candle_flames[li * 4] as Dictionary)["node"].position
			GraphicsPolish.make_point_light(hall, spot2 + Vector3(0, 0.25, 0), Color(1.0, 0.72, 0.40), 0.85, 4.0)
	# Enchanted ceiling: faint drifting star-dots.
	for i in 36:
		var star := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		ssm.radius = 0.02
		ssm.height = 0.04
		star.mesh = ssm
		star.material_override = GraphicsPolish.glow(Color(0.55, 0.65, 1.0), 1.1)
		star.position = Vector3(randf_range(-5.5, 5.5), randf_range(4.2, 5.8), randf_range(-5.5, 3.5))
		hall.add_child(star)
		candle_flames.append({"node": star, "base_y": star.position.y, "phase": randf() * 6.0, "star": true})
	# v0.7.0 KayKit: academy set dressing - shield banners on the side
	# walls, a trophy sword-and-shield on the back wall, a treasure chest,
	# and lit wall torches flanking the stairs. All spawns guarded: a null
	# return from ModelLib.spawn skips that prop, never crashes.
	var kdir := "res://assets/models/wizard_academy/"
	for bx in [-5.8, 5.8]:
		var kb := ModelLib.spawn(kdir + "banner_shield_blue.glb", hall, Vector3(bx, 2.2, -3.0))
		if kb != null:
			kb.rotation.y = signf(bx) * PI * 0.5
	ModelLib.spawn(kdir + "sword_shield.glb", hall, Vector3(4.6, 1.9, -5.85))
	ModelLib.spawn(kdir + "chest_gold.glb", hall, Vector3(3.6, 0.0, 1.6))
	for tx in [-1.3, 1.3]:
		ModelLib.spawn(kdir + "torch_mounted.glb", hall, Vector3(tx, 1.5, -5.90))


# ------------------------------------------------------------- persistence ---
func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	house = int(cfg.get_value("wizard", "house", 0))
	for h in 4:
		house_points[h] = int(cfg.get_value("wizard", "points_%d" % h, 0))
	for k in best_grades.keys():
		best_grades[k] = str(cfg.get_value("wizard", "grade_" + k, "-"))
	duel_wins = int(cfg.get_value("wizard", "duel_wins", 0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("wizard", "house", house)
	for h in 4:
		cfg.set_value("wizard", "points_%d" % h, house_points[h])
	for k in best_grades.keys():
		cfg.set_value("wizard", "grade_" + str(k), best_grades[k])
	cfg.set_value("wizard", "duel_wins", duel_wins)
	cfg.save(SAVE_PATH)


func _grade_rank(g: String) -> int:
	return GRADES.find(g)


func _record_grade(lesson: String, grade: String) -> void:
	if _grade_rank(grade) > _grade_rank(str(best_grades[lesson])):
		best_grades[lesson] = grade
	var pts: int = LESSON_POINTS[grade] if lesson != "exams" else EXAM_POINTS[grade]
	house_points[house] += pts
	_save()


# ------------------------------------------------------------------ input ---
func _press_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _mouse_plane(dist: float) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	var fwd := -camera.global_transform.basis.z
	var pp := camera.global_position + fwd * dist
	var denom := d.dot(fwd)
	if absf(denom) < 0.0001:
		return pp
	var t := (pp - o).dot(fwd) / denom
	if t < 0.0:
		return pp
	return o + d * t


func _pointer_pos() -> Vector3:
	if _dbg_pointer_on:
		return _dbg_pointer
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.3)
	return _mouse_plane(_grab_depth)


func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> bool:
	var oc := c - o
	var t := oc.dot(d)
	if t < 0.0:
		return false
	return oc.length_squared() - t * t <= r * r


# ----------------------------------------------------------------- buttons ---
func _clear_buttons() -> void:
	for b in buttons:
		var n: Node = (b as Dictionary)["node"]
		if is_instance_valid(n):
			n.queue_free()
	buttons.clear()
	hover_id = ""


func _add_button(id: String, pos: Vector3, text: String, w: float = 1.15, h: float = 0.30, color: Color = Color(0.16, 0.18, 0.34)) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var bg := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(w, h, 0.07)
	bg.mesh = bbox
	var bgm := GraphicsPolish.pbr_preset(color, "plastic")
	bg.material_override = bgm
	n.add_child(bg)
	var edge := MeshInstance3D.new()
	var ebox := BoxMesh.new()
	ebox.size = Vector3(w + 0.03, h + 0.03, 0.05)
	edge.mesh = ebox
	edge.material_override = GraphicsPolish.glow(Color(0.45, 0.55, 1.0), 0.55)
	edge.position = Vector3(0, 0, -0.012)
	n.add_child(edge)
	var lbl := GraphicsPolish.make_label(text, 44, Color(1.0, 1.0, 1.0))
	lbl.pixel_size = 0.0032
	lbl.position = Vector3(0, 0, 0.045)
	n.add_child(lbl)
	buttons.append({"id": id, "node": n, "bg": bg, "bgm": bgm, "radius": maxf(w, h) * 0.62, "w": w})
	return n


func _update_button_hover() -> void:
	hover_id = ""
	var best_d := 1e9
	var xr := ARUpgradeKit.is_xr_active()
	var hand := Vector3.ZERO
	var ro := Vector3.ZERO
	var rd := Vector3.ZERO
	if xr:
		hand = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.3)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		ro = camera.project_ray_origin(mp)
		rd = camera.project_ray_normal(mp)
	for b in buttons:
		var bd: Dictionary = b
		var n: Node3D = bd["node"]
		if not is_instance_valid(n) or not n.visible:
			continue
		var c := n.global_position
		var r: float = bd["radius"]
		var hit := false
		var d := 1e9
		if xr:
			d = hand.distance_to(c)
			hit = d < r * 1.7
		elif camera != null:
			hit = _ray_sphere(ro, rd, c, r)
			if hit:
				d = ro.distance_to(c)
		if hit and d < best_d:
			best_d = d
			hover_id = str(bd["id"])
	for b in buttons:
		var bd2: Dictionary = b
		var bgm: StandardMaterial3D = bd2["bgm"]
		if str(bd2["id"]) == hover_id:
			bgm.emission_enabled = true
			bgm.emission = Color(0.35, 0.45, 1.0)
			bgm.emission_energy_multiplier = 0.8
		else:
			bgm.emission_enabled = false


func _click_button(id: String) -> void:
	Haptics.tick()
	match id:
		"lesson_charms":
			_last_lesson = "lesson_charms"
			_charms_setup(3.0, 3)
			_set_mode("charms")
		"lesson_potions":
			_last_lesson = "lesson_potions"
			_potions_setup(["Moondew", "Firepepper", "Starshroom"])
			_set_mode("potions")
		"lesson_defense":
			_last_lesson = "lesson_defense"
			_defense_setup(8, 1.5)
			_set_mode("defense")
		"exams":
			_last_lesson = "exams"
			_exams_begin()
			_set_mode("exams")
		"duels":
			_last_lesson = "duels"
			_duel_reset()
			_set_mode("duels")
		"menu":
			_set_mode("menu")
		"again":
			_click_button(_again_target())
		"house_0", "house_1", "house_2", "house_3":
			house = int(id.get_slice("_", 1))
			_save()
			_refresh_menu_info()
			_set_msg("Welcome to house " + HOUSE_NAMES[house] + "!", 2.0)


func _again_target() -> String:
	match _last_lesson:
		"lesson_charms":
			return "lesson_charms"
		"lesson_potions":
			return "lesson_potions"
		"lesson_defense":
			return "lesson_defense"
		"exams":
			return "exams"
		"duels":
			return "duels"
	return "menu"


# -------------------------------------------------------------------- menu ---
func _build_menu() -> void:
	menu_root = Node3D.new()
	menu_root.name = "Menu"
	add_child(menu_root)
	var title := GraphicsPolish.make_label("WIZARD ACADEMY", 110, Color(1.0, 0.85, 0.40))
	title.position = Vector3(0.0, 2.75, 0.9)
	title.pixel_size = 0.006
	menu_root.add_child(title)
	var sub := GraphicsPolish.make_label("School of Spellcraft  -  choose your path, young wizard", 40, Color(0.80, 0.85, 1.0))
	sub.position = Vector3(0.0, 2.42, 0.9)
	sub.pixel_size = 0.004
	menu_root.add_child(sub)
	menu_info_label = GraphicsPolish.make_label("", 36, Color(1.0, 0.95, 0.70))
	menu_info_label.position = Vector3(0.0, 0.62, 0.9)
	menu_info_label.pixel_size = 0.0038
	menu_root.add_child(menu_info_label)


func _refresh_menu_info() -> void:
	if menu_info_label != null:
		menu_info_label.text = _menu_info_text()


var menu_info_label: Label3D = null


func _build_menu_buttons() -> void:
	_add_button("lesson_charms", Vector3(-1.55, 1.95, 0.9), "Charms")
	_add_button("lesson_potions", Vector3(0.0, 1.95, 0.9), "Potions")
	_add_button("lesson_defense", Vector3(1.55, 1.95, 0.9), "Defense")
	_add_button("exams", Vector3(-0.80, 1.52, 0.9), "EXAMS", 1.15, 0.30, Color(0.45, 0.16, 0.10))
	_add_button("duels", Vector3(0.80, 1.52, 0.9), "DUELS", 1.15, 0.30, Color(0.16, 0.30, 0.45))
	for h in 4:
		var pos := Vector3(-1.95 + float(h) * 1.30, 1.02, 0.9)
		var n := _add_button("house_%d" % h, pos, HOUSE_SIGILS[h] + " " + HOUSE_NAMES[h], 1.18, 0.26, HOUSE_COLORS[h].darkened(0.55))
		if h == house:
			var sel := GraphicsPolish.make_label(">", 60, Color(1.0, 0.9, 0.3))
			sel.position = Vector3(-0.72, 0, 0.05)
			sel.pixel_size = 0.004
			n.add_child(sel)


func _menu_info_text() -> String:
	var s := "House %s  -  Points: %d\n" % [HOUSE_NAMES[house], house_points[house]]
	s += "Grades  Charms:%s  Potions:%s  Defense:%s  Exams:%s   Duel wins: %d\n" % [
		best_grades["charms"], best_grades["potions"], best_grades["defense"], best_grades["exams"], duel_wins]
	var lead := 0
	for h in range(4):
		if house_points[h] > house_points[lead]:
			lead = h
	s += "House Cup leader: %s (%d pts)" % [HOUSE_NAMES[lead], house_points[lead]]
	return s


# --------------------------------------------------------------------- hud ---
func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-3.6, 3.05, 0.4)
	hud_label.pixel_size = 0.0045
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 84, Color(1.0, 0.88, 0.45))
	msg_label.position = Vector3(0.0, 2.35, 0.2)
	msg_label.pixel_size = 0.006
	add_child(msg_label)
	hint_label = GraphicsPolish.make_label("", 36, Color(0.78, 0.84, 0.95))
	hint_label.position = Vector3(0.0, 0.55, 1.9)
	hint_label.pixel_size = 0.0038
	add_child(hint_label)


var _msg := ""
var _msg_t := 0.0

func _set_msg(t: String, hold: float) -> void:
	_msg = t
	_msg_t = hold
	if msg_label != null:
		msg_label.text = t


func _update_hud() -> void:
	if hud_label == null:
		return
	var mode_name := _mode.capitalize()
	hud_label.text = "WIZARD ACADEMY  |  %s\nHouse %s - %d pts" % [mode_name, HOUSE_NAMES[house], house_points[house]]
	match _mode:
		"charms":
			hud_label.text += "\nLevitate %d/%d" % [charm_done, charm_total]
		"potions":
			hud_label.text += "\nBrew %d/%d steps" % [recipe_idx, recipe.size()]
		"defense":
			hud_label.text += "\nBlocked %d/%d" % [def_blocked, def_total]
		"exams":
			hud_label.text += "\nExam %d/%d  Time %.0f" % [exam_idx + 1, exam_steps.size(), exam_timer]
		"duels":
			hud_label.text += "\nYou %d  Rival %d" % [int(p_hp), int(ai_hp)]
	if hint_label != null:
		match _mode:
			"menu":
				hint_label.text = "Pick a house, then a lesson  |  Desktop: click  |  XR: pinch"
			"charms":
				hint_label.text = "GRAB the orb (click/pinch), hold it STEADY inside the gold ring"
			"potions":
				hint_label.text = "Grab a bottle, hold it over the cauldron to POUR - follow the recipe order"
			"defense":
				hint_label.text = "HOLD (click/pinch) to raise your shield - move it into the incoming hexes"
			"exams":
				hint_label.text = "Timed gauntlet! Complete each task before the clock runs out"
			"duels":
				hint_label.text = "Draw: CIRCLE=fireball  ZIGZAG=lightning  fast PUSH=shield"


# ------------------------------------------------------------------ charms ---
func _build_charms() -> void:
	charms_root = Node3D.new()
	charms_root.name = "Charms"
	add_child(charms_root)
	# Pedestal.
	var ped := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.22
	pcyl.bottom_radius = 0.30
	pcyl.height = 0.9
	ped.mesh = pcyl
	ped.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.33, 0.42), "matte")
	ped.position = Vector3(CHARM_HOME.x, 0.45, CHARM_HOME.z)
	charms_root.add_child(ped)
	# The levitation orb.
	charm_orb = MeshInstance3D.new()
	var osm := SphereMesh.new()
	osm.radius = 0.11
	osm.height = 0.22
	charm_orb.mesh = osm
	charm_orb_mat = GraphicsPolish.glow(Color(0.35, 0.85, 1.0), 1.8)
	charm_orb.material_override = charm_orb_mat
	charm_orb.position = CHARM_HOME
	charms_root.add_child(charm_orb)
	charm_orb.add_child(GraphicsPolish.make_trail(Color(0.35, 0.85, 1.0), 0.04))
	# Target ring.
	charm_ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.30
	tor.outer_radius = 0.38
	charm_ring.mesh = tor
	charm_ring_mat = GraphicsPolish.glow(Color(1.0, 0.80, 0.25), 1.6)
	charm_ring.material_override = charm_ring_mat
	charm_ring.position = CHARM_TARGET
	charm_ring.rotation.x = PI * 0.5
	charms_root.add_child(charm_ring)
	# Progress bar.
	charm_bar = MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.7, 0.06, 0.02)
	charm_bar.mesh = bbox
	charm_bar.material_override = GraphicsPolish.glow(Color(0.35, 1.0, 0.55), 1.6)
	charm_bar.position = CHARM_TARGET + Vector3(0.0, 0.45, 0.0)
	charms_root.add_child(charm_bar)


func _charms_setup(need: float, total: int) -> void:
	charm_need = need
	charm_total = total
	charm_done = 0
	charm_hold = 0.0
	charm_grabbed = false
	charm_t0 = elapsed
	charm_orb.position = CHARM_HOME
	_update_hud()


func _charms_process(delta: float, press: bool, just_pressed: bool, just_released: bool) -> void:
	var pp := _pointer_pos()
	if just_pressed and not charm_grabbed:
		if charm_orb.global_position.distance_to(pp) < 0.45:
			charm_grabbed = true
			_grab_depth = camera.global_position.distance_to(charm_orb.global_position) if camera != null else 2.2
			Haptics.tick()
	if just_released:
		charm_grabbed = false
	if charm_grabbed and press:
		var target := pp
		target.y = clampf(target.y, 0.8, 2.3)
		target = ARUpgradeKit.clamp_to_room(target, 0.4)
		charm_orb.global_position = charm_orb.global_position.lerp(target, minf(1.0, delta * 10.0))
		var d := charm_orb.position.distance_to(CHARM_TARGET)
		if d < 0.42:
			charm_hold += delta
			GraphicsPolish.pulse_glow(charm_ring_mat, 1.6, 0.9, elapsed, 6.0)
		else:
			charm_hold = maxf(0.0, charm_hold - delta * 0.6)
	else:
		charm_hold = maxf(0.0, charm_hold - delta * 0.6)
		# Gentle idle bob when not held.
		charm_orb.position = charm_orb.position.lerp(CHARM_HOME + Vector3(0, sin(elapsed * 2.0) * 0.05, 0), minf(1.0, delta * 3.0))
	charm_bar.scale.x = clampf(charm_hold / charm_need, 0.02, 1.0)
	GraphicsPolish.pulse_glow(charm_orb_mat, 1.8, 0.6, elapsed, 3.0)
	if charm_hold >= charm_need:
		charm_done += 1
		charm_hold = 0.0
		charm_grabbed = false
		GraphicsPolish.spawn_sparks(self, CHARM_TARGET, Color(1.0, 0.85, 0.35), 26)
		Haptics.pulse(0.8, 0.15)
		_set_msg("Leviosa! %d/%d" % [charm_done, charm_total], 1.4)
		charm_orb.position = CHARM_HOME
		if charm_done >= charm_total:
			_task_complete("charms")


func _charms_grade() -> String:
	var dt := elapsed - charm_t0
	if dt <= 50.0:
		return "O"
	if dt <= 85.0:
		return "E"
	if dt <= 130.0:
		return "A"
	return "T"


# ----------------------------------------------------------------- potions ---
func _build_potions() -> void:
	potions_root = Node3D.new()
	potions_root.name = "Potions"
	add_child(potions_root)
	# Cauldron: black body, rim, glowing liquid, fire beneath.
	var body := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.42
	bsm.height = 0.84
	body.mesh = bsm
	body.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.08, 0.10), "matte")
	body.scale = Vector3(1.0, 0.78, 1.0)
	body.position = cauldron_pos + Vector3(0.0, 0.52, 0.0)
	potions_root.add_child(body)
	var rim := MeshInstance3D.new()
	var rtor := TorusMesh.new()
	rtor.inner_radius = 0.36
	rtor.outer_radius = 0.44
	rim.mesh = rtor
	rim.material_override = GraphicsPolish.pbr(Color(0.15, 0.15, 0.18), 0.6, 0.4)
	rim.position = cauldron_pos + Vector3(0.0, 0.82, 0.0)
	rim.rotation.x = PI * 0.5
	potions_root.add_child(rim)
	var liquid := MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.36
	lcyl.bottom_radius = 0.36
	lcyl.height = 0.03
	liquid.mesh = lcyl
	cauldron_liquid_mat = GraphicsPolish.glow(Color(0.25, 0.95, 0.35), 1.4)
	liquid.material_override = cauldron_liquid_mat
	liquid.position = cauldron_pos + Vector3(0.0, 0.80, 0.0)
	potions_root.add_child(liquid)
	cauldron_liquid = liquid
	for a in [0.0, TAU * 0.33, TAU * 0.66]:
		var leg := MeshInstance3D.new()
		var legm := CylinderMesh.new()
		legm.top_radius = 0.04
		legm.bottom_radius = 0.05
		legm.height = 0.25
		leg.mesh = legm
		leg.material_override = GraphicsPolish.pbr(Color(0.10, 0.10, 0.12), 0.5, 0.5)
		leg.position = cauldron_pos + Vector3(cos(a) * 0.30, 0.12, sin(a) * 0.30)
		potions_root.add_child(leg)
	var fire := MeshInstance3D.new()
	var fsm := SphereMesh.new()
	fsm.radius = 0.16
	fsm.height = 0.32
	fire.mesh = fsm
	fire.material_override = GraphicsPolish.glow(Color(1.0, 0.45, 0.10), 2.2)
	fire.scale = Vector3(1.3, 0.6, 1.3)
	fire.position = cauldron_pos + Vector3(0.0, 0.10, 0.0)
	potions_root.add_child(fire)
	GraphicsPolish.make_point_light(potions_root, cauldron_pos + Vector3(0, 1.1, 0), Color(0.35, 1.0, 0.45), 0.9, 3.5)
	# Ingredient shelf + bottles.
	var shelf := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(1.9, 0.08, 0.5)
	shelf.mesh = sbox
	shelf.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
	shelf.position = Vector3(2.2, 0.86, -0.4)
	potions_root.add_child(shelf)
	for lx in [-0.8, 0.8]:
		var sleg := MeshInstance3D.new()
		var slbox := BoxMesh.new()
		slbox.size = Vector3(0.08, 0.86, 0.4)
		sleg.mesh = slbox
		sleg.material_override = GraphicsPolish.pbr_preset(Color(0.30, 0.19, 0.10), "matte")
		sleg.position = Vector3(2.2 + lx, 0.43, -0.4)
		potions_root.add_child(sleg)
	for i in 3:
		var b := Node3D.new()
		b.position = BOTTLE_HOME[i]
		potions_root.add_child(b)
		# v0.9.1: real Quaternius potion bottle; primitive build is fallback.
		var model := ModelLib.spawn(
			"res://assets/models/wizard_academy/" + BOTTLE_MODELS[i] + ".gltf", b, Vector3.ZERO)
		if model != null:
			model.scale = Vector3.ONE * BOTTLE_MODEL_SCALE
		else:
			_build_primitive_bottle(b, i)
		var nlabel := GraphicsPolish.make_label(BOTTLE_NAMES[i], 30, Color(1, 1, 1))
		nlabel.pixel_size = 0.0028
		nlabel.position = Vector3(0.0, 0.34, 0.0)
		b.add_child(nlabel)
		bottles.append({"node": b, "home": BOTTLE_HOME[i]})


## v0.9.1 fallback: the original procedural bottle when the glTF is missing.
func _build_primitive_bottle(b: Node3D, i: int) -> void:
	var glass := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 0.085
	gcyl.bottom_radius = 0.095
	gcyl.height = 0.26
	glass.mesh = gcyl
	glass.material_override = GraphicsPolish.pbr_preset(Color(0.75, 0.80, 0.85), "glass")
	b.add_child(glass)
	var fill := MeshInstance3D.new()
	var fcyl := CylinderMesh.new()
	fcyl.top_radius = 0.070
	fcyl.bottom_radius = 0.080
	fcyl.height = 0.15
	fill.mesh = fcyl
	fill.material_override = GraphicsPolish.glow(BOTTLE_COLORS[i], 1.2)
	fill.position = Vector3(0.0, -0.04, 0.0)
	b.add_child(fill)
	var cork := MeshInstance3D.new()
	var ccyl := CylinderMesh.new()
	ccyl.top_radius = 0.035
	ccyl.bottom_radius = 0.035
	ccyl.height = 0.06
	cork.mesh = ccyl
	cork.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.38, 0.20), "matte")
	cork.position = Vector3(0.0, 0.16, 0.0)
	b.add_child(cork)
	# Recipe board.
	recipe_label = GraphicsPolish.make_label("", 40, Color(1.0, 0.95, 0.70))
	recipe_label.position = Vector3(-2.3, 1.9, -0.4)
	recipe_label.pixel_size = 0.004
	potions_root.add_child(recipe_label)


func _potions_setup(rec: Array) -> void:
	recipe = rec.duplicate()
	recipe_idx = 0
	held_bottle = -1
	pour_t = 0.0
	potion_mistakes = 0
	potion_t0 = elapsed
	for i in bottles.size():
		((bottles[i] as Dictionary)["node"] as Node3D).position = (bottles[i] as Dictionary)["home"]
		((bottles[i] as Dictionary)["node"] as Node3D).rotation = Vector3.ZERO
	_update_recipe_label()
	_update_hud()


func _update_recipe_label() -> void:
	var t := "POTION RECIPE\n"
	for i in recipe.size():
		var mark := "> " if i == recipe_idx else "   "
		var done := "[x] " if i < recipe_idx else "[ ] "
		t += "%s%s%s\n" % [mark, done, str(recipe[i])]
	recipe_label.text = t


func _potions_process(delta: float, press: bool, just_pressed: bool, just_released: bool) -> void:
	var pp := _pointer_pos()
	var mouth := potions_root.to_global(cauldron_pos + Vector3(0.0, 1.0, 0.0)) # v0.7.0: follows the room-placed potion station
	if just_pressed and held_bottle < 0:
		for i in bottles.size():
			var bn: Node3D = (bottles[i] as Dictionary)["node"]
			if bn.global_position.distance_to(pp) < 0.38:
				held_bottle = i
				pour_t = 0.0
				_grab_depth = camera.global_position.distance_to(bn.global_position) if camera != null else 2.2
				Haptics.tick()
				ArtKit.pop(bn, 1.18, 0.2)  # v0.9.1 juice: grab pop
				break
	if just_released and held_bottle >= 0:
		_return_bottle(held_bottle)
		held_bottle = -1
		pour_t = 0.0
	if held_bottle >= 0 and press:
		var bn2: Node3D = (bottles[held_bottle] as Dictionary)["node"]
		var target := pp
		target.y = clampf(target.y, 0.9, 2.4)
		bn2.global_position = bn2.global_position.lerp(ARUpgradeKit.clamp_to_room(target, 0.4), minf(1.0, delta * 10.0))
		if bn2.global_position.distance_to(mouth) < 0.55:
			# Tipping the bottle: rotate toward the cauldron while pouring.
			bn2.rotation.z = lerpf(bn2.rotation.z, 2.1, minf(1.0, delta * 6.0))
			pour_t += delta
			if int(pour_t * 12.0) % 3 == 0:
				GraphicsPolish.spawn_sparks(self, mouth, BOTTLE_COLORS[held_bottle], 3)
			if pour_t >= 1.1:
				_pour_bottle(held_bottle)
				held_bottle = -1
				pour_t = 0.0
		else:
			bn2.rotation.z = lerpf(bn2.rotation.z, 0.0, minf(1.0, delta * 6.0))
	GraphicsPolish.pulse_glow(cauldron_liquid_mat, 1.4, 0.7, elapsed, 2.2)


func _return_bottle(i: int) -> void:
	var bn: Node3D = (bottles[i] as Dictionary)["node"]
	bn.position = (bottles[i] as Dictionary)["home"]
	bn.rotation = Vector3.ZERO
	ArtKit.squash_land(bn)  # v0.9.1 juice: bottle settles onto the shelf


## v0.9.1 juice: wrong-pour shake (follow-through after the bottle lands).
func _juice_shake(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tw := create_tween()
	tw.tween_property(node, "rotation:z", 0.30, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", -0.30, 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", 0.15, 0.07).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", 0.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pour_bottle(i: int) -> void:
	var want := str(recipe[recipe_idx])
	var got: String = BOTTLE_NAMES[i]
	var mouth := potions_root.to_global(cauldron_pos + Vector3(0.0, 1.0, 0.0)) # v0.7.0: follows the room-placed potion station
	if got == want:
		GraphicsPolish.spawn_sparks(self, mouth, BOTTLE_COLORS[i], 30)
		Haptics.pulse(0.7, 0.12)
		ArtKit.pop(cauldron_liquid, 1.3, 0.3)  # v0.9.1 juice: brew splash pop
		recipe_idx += 1
		_set_msg("Added %s! (%d/%d)" % [got, recipe_idx, recipe.size()], 1.4)
		_update_recipe_label()
	else:
		potion_mistakes += 1
		GraphicsPolish.spawn_sparks(self, mouth, Color(1.0, 0.15, 0.10), 24)
		Haptics.thump()
		_set_msg("FIZZLE! Recipe wants %s next" % want, 1.8)
	_return_bottle(i)
	if got != want:
		_juice_shake((bottles[i] as Dictionary)["node"] as Node3D)
	_update_hud()
	if recipe_idx >= recipe.size():
		GraphicsPolish.spawn_confetti(self, mouth + Vector3(0, 0.4, 0), 50)
		_set_msg("Potion brewed!", 1.6)
		_task_complete("potions")


func _potions_grade() -> String:
	if potion_mistakes <= 0:
		return "O"
	if potion_mistakes == 1:
		return "E"
	if potion_mistakes == 2:
		return "A"
	return "T"


# ----------------------------------------------------------------- defense ---
func _build_defense() -> void:
	defense_root = Node3D.new()
	defense_root.name = "Defense"
	add_child(defense_root)
	# Shield bubble (hidden until raised).
	shield_bubble = MeshInstance3D.new()
	var ssm := SphereMesh.new()
	ssm.radius = 0.50
	ssm.height = 1.0
	shield_bubble.mesh = ssm
	shield_mat = GraphicsPolish.pbr_preset(Color(0.40, 0.85, 1.0), "glass")
	shield_bubble.material_override = shield_mat
	shield_bubble.visible = false
	add_child(shield_bubble)
	# Training dummy markers where hexes launch from.
	for i in 3:
		var post := MeshInstance3D.new()
		var pcyl := CylinderMesh.new()
		pcyl.top_radius = 0.06
		pcyl.bottom_radius = 0.08
		pcyl.height = 1.6
		post.mesh = pcyl
		post.material_override = GraphicsPolish.pbr_preset(Color(0.30, 0.20, 0.14), "matte")
		post.position = Vector3(-2.2 + float(i) * 2.2, 0.8, -5.2)
		defense_root.add_child(post)


func _defense_setup(count: int, interval: float) -> void:
	def_total = count
	def_spawned = 0
	def_blocked = 0
	def_spawn_t = 0.8
	def_t0 = elapsed
	_def_interval = interval
	shield_bubble.global_position = Vector3(0.0, 1.35, 1.6)
	shield_bubble.visible = false
	for p in projectiles:
		if is_instance_valid((p as Dictionary)["node"]):
			((p as Dictionary)["node"] as Node).queue_free()
	projectiles.clear()
	_update_hud()


var _def_interval := 1.5

func _spawn_hex() -> void:
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	node.mesh = sm
	node.material_override = GraphicsPolish.glow(Color(0.75, 0.25, 1.0), 2.0)
	var sx := randf_range(-2.4, 2.4)
	var sy := randf_range(1.1, 2.1)
	node.position = Vector3(sx, sy, -5.2)
	node.add_child(GraphicsPolish.make_trail(Color(0.75, 0.25, 1.0), 0.05))
	add_child(node)
	var dir := (CHEST_POS - node.position).normalized()
	projectiles.append({"node": node, "vel": dir * 3.4})
	def_spawned += 1


func _defense_process(delta: float, press: bool) -> void:
	var pp := _pointer_pos()
	# Shield follows the pointer while held (palm-out block).
	shield_bubble.visible = press
	if press:
		var sp := pp
		sp.z = clampf(sp.z, 0.6, 2.2)
		sp.y = clampf(sp.y, 0.7, 2.3)
		shield_bubble.global_position = shield_bubble.global_position.lerp(sp, minf(1.0, delta * 12.0))
		GraphicsPolish.pulse_glow(shield_mat, 0.9, 0.5, elapsed, 5.0)
	if def_spawned < def_total:
		def_spawn_t -= delta
		if def_spawn_t <= 0.0:
			def_spawn_t = _def_interval
			_spawn_hex()
	for i in range(projectiles.size() - 1, -1, -1):
		var pd: Dictionary = projectiles[i]
		var node: MeshInstance3D = pd["node"]
		if not is_instance_valid(node):
			projectiles.remove_at(i)
			continue
		node.position += (pd["vel"] as Vector3) * delta
		var p := node.position
		var done := false
		if press and p.distance_to(shield_bubble.global_position) < 0.62:
			def_blocked += 1
			GraphicsPolish.spawn_sparks(self, p, Color(0.45, 0.90, 1.0), 20)
			Haptics.thump()
			_set_msg("Blocked! %d/%d" % [def_blocked, def_total], 1.0)
			done = true
		elif p.distance_to(CHEST_POS) < 0.50:
			GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.20, 0.20), 18)
			Haptics.pulse(1.0, 0.2)
			_set_msg("Hit! Block it with your shield", 1.2)
			done = true
		elif p.z > 3.2:
			done = true
		if done:
			node.queue_free()
			projectiles.remove_at(i)
	_update_hud()
	if def_spawned >= def_total and projectiles.is_empty():
		_task_complete("defense")


func _defense_grade() -> String:
	if def_blocked >= def_total:
		return "O"
	if def_blocked >= 6:
		return "E"
	if def_blocked >= 4:
		return "A"
	return "T"


# ------------------------------------------------------------------- exams ---
func _exams_begin() -> void:
	exam_steps = [
		{"kind": "levitate", "need": 2.0},
		{"kind": "pour", "recipe": _random_recipe(2)},
		{"kind": "block", "count": 3},
		{"kind": "levitate", "need": 2.0},
		{"kind": "pour", "recipe": _random_recipe(2)},
		{"kind": "block", "count": 3},
	]
	exam_idx = 0
	exam_timer = EXAM_TIME
	exam_score = 0.0
	_exam_begin_step()


func _random_recipe(n: int) -> Array:
	var pool := BOTTLE_NAMES.duplicate()
	pool.shuffle()
	return pool.slice(0, n)


func _exam_begin_step() -> void:
	if exam_idx >= exam_steps.size():
		_finish_exams()
		return
	var step: Dictionary = exam_steps[exam_idx]
	_set_msg("EXAM %d/%d" % [exam_idx + 1, exam_steps.size()], 1.6)
	match str(step["kind"]):
		"levitate":
			_charms_setup(float(step["need"]), 1)
			_show_station("charms")
		"pour":
			_potions_setup(step["recipe"])
			_show_station("potions")
		"block":
			_defense_setup(int(step["count"]), 1.3)
			_show_station("defense")


func _exams_process(delta: float, press: bool, just_pressed: bool, just_released: bool) -> void:
	exam_timer -= delta
	_update_hud()
	if exam_timer <= 0.0:
		_finish_exams()
		return
	if exam_idx >= exam_steps.size():
		return
	var step: Dictionary = exam_steps[exam_idx]
	match str(step["kind"]):
		"levitate":
			_charms_process(delta, press, just_pressed, just_released)
		"pour":
			_potions_process(delta, press, just_pressed, just_released)
		"block":
			_defense_process(delta, press)


func _exam_step_done() -> void:
	exam_score += 100.0 / float(exam_steps.size())
	Haptics.pulse(0.8, 0.15)
	exam_idx += 1
	_exam_begin_step()


func _finish_exams() -> void:
	var time_bonus := clampf(exam_timer, 0.0, 30.0) * 0.3
	var total := exam_score + time_bonus
	var grade := "T"
	if total >= 90.0:
		grade = "O"
	elif total >= 70.0:
		grade = "E"
	elif total >= 50.0:
		grade = "A"
	_record_grade("exams", grade)
	_show_grade("EXAMS", grade, "Score %.0f/100" % total)


# ------------------------------------------------------- task completion ---
func _task_complete(kind: String) -> void:
	if _mode == "exams":
		_exam_step_done()
		return
	var grade := "T"
	match kind:
		"charms":
			grade = _charms_grade()
		"potions":
			grade = _potions_grade()
		"defense":
			grade = _defense_grade()
	_record_grade(kind, grade)
	_show_grade(kind.capitalize(), grade, "")


func _show_grade(title: String, grade: String, extra: String) -> void:
	var pts: int = LESSON_POINTS[grade] if title != "EXAMS" else EXAM_POINTS[grade]
	var txt := "%s: %s (%s)  +%d %s points" % [title, grade, GRADE_NAMES[grade], pts, HOUSE_NAMES[house]]
	if extra != "":
		txt += "\n" + extra
	_set_msg(txt, 60.0)
	_clear_buttons()
	_add_button("again", Vector3(-0.75, 1.15, 0.9), "Try Again")
	_add_button("menu", Vector3(0.75, 1.15, 0.9), "Great Hall")
	_mode = "grade"
	_show_station("none")
	_update_hud()
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.0, 0.5), 60)
	Haptics.pulse(0.9, 0.2)


# -------------------------------------------------------------------- duel ---
func _build_duel() -> void:
	duel_root = Node3D.new()
	duel_root.name = "Duel"
	add_child(duel_root)
	# Duel ring.
	for i in 24:
		var a := TAU * float(i) / 24.0
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.06
		dot.mesh = sm
		dot.material_override = GraphicsPolish.glow(Color(0.55, 0.35, 1.0), 1.2)
		dot.position = Vector3(cos(a) * 2.2, 0.02, -0.6 + sin(a) * 2.2)
		duel_root.add_child(dot)
	# Rival wizard (primitive-built, house-purple robes).
	duel_wizard = Node3D.new()
	duel_wizard.position = Vector3(0.0, 0.0, -3.0)
	duel_root.add_child(duel_wizard)
	var robe := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.3
	robe.mesh = cap
	robe.material_override = GraphicsPolish.pbr_preset(Color(0.40, 0.18, 0.72), "plastic")
	robe.position = Vector3(0.0, 1.0, 0.0)
	duel_wizard.add_child(robe)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.20
	hm.height = 0.40
	head.mesh = hm
	head.material_override = GraphicsPolish.pbr(Color(0.90, 0.75, 0.60), 0.0, 0.6)
	head.position = Vector3(0.0, 1.85, 0.0)
	duel_wizard.add_child(head)
	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.26
	cone.height = 0.55
	hat.mesh = cone
	duel_hat_mat = GraphicsPolish.glow(Color(0.60, 0.25, 1.0), 1.4)
	hat.material_override = duel_hat_mat
	hat.position = Vector3(0.0, 2.20, 0.0)
	duel_wizard.add_child(hat)
	var staff := MeshInstance3D.new()
	var scyl := CylinderMesh.new()
	scyl.top_radius = 0.03
	scyl.bottom_radius = 0.03
	scyl.height = 1.4
	staff.mesh = scyl
	staff.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
	staff.position = Vector3(0.45, 1.10, 0.0)
	duel_wizard.add_child(staff)
	duel_staff_tip = MeshInstance3D.new()
	var tipm := SphereMesh.new()
	tipm.radius = 0.07
	tipm.height = 0.14
	duel_staff_tip.mesh = tipm
	duel_staff_tip.material_override = GraphicsPolish.glow(Color(1.0, 0.40, 0.80), 2.0)
	duel_staff_tip.position = Vector3(0.45, 1.85, 0.0)
	duel_wizard.add_child(duel_staff_tip)
	duel_ai_hp_fg = _make_bar(duel_wizard, Vector3(0.0, 2.65, 0.0), Color(1.0, 0.25, 0.25))
	# Player marker + shield.
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.30
	marker.mesh = ring
	marker.material_override = GraphicsPolish.glow(Color(0.30, 0.90, 1.0), 1.6)
	marker.position = Vector3(0.0, 0.03, 2.0)
	duel_root.add_child(marker)
	duel_p_hp_fg = _make_bar(self, Vector3(0.0, 2.15, 2.0), Color(0.25, 1.0, 0.40))
	duel_shield_bubble = MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 0.55
	shm.height = 1.10
	duel_shield_bubble.mesh = shm
	duel_shield_bubble.material_override = GraphicsPolish.pbr_preset(Color(0.40, 0.90, 1.0), "glass")
	duel_shield_bubble.position = Vector3(0.0, 1.3, 2.0)
	duel_shield_bubble.visible = false
	add_child(duel_shield_bubble)
	# Gesture cursor + line.
	duel_gesture_cursor = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.035
	cm.height = 0.07
	duel_gesture_cursor.mesh = cm
	duel_gesture_cursor.material_override = GraphicsPolish.glow(Color(1.0, 0.90, 0.30), 2.0)
	duel_gesture_cursor.visible = false
	add_child(duel_gesture_cursor)
	duel_gesture_cursor.add_child(GraphicsPolish.make_trail(Color(1.0, 0.85, 0.30), 0.05))
	var gline := MeshInstance3D.new()
	gline.mesh = duel_gesture_im
	gline.material_override = GraphicsPolish.glow(Color(1.0, 0.85, 0.30), 1.6)
	add_child(gline)


func _make_bar(parent: Node3D, pos: Vector3, color: Color) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(1.1, 0.12, 0.02)
	bg.mesh = bgm
	var bgmat := GraphicsPolish.pbr(Color(0.10, 0.10, 0.10), 0.0, 0.8)
	bgmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bgmat
	bg.position = pos
	parent.add_child(bg)
	var fg := MeshInstance3D.new()
	var fgm := BoxMesh.new()
	fgm.size = Vector3(1.0, 0.08, 0.03)
	fg.mesh = fgm
	var fmat := GraphicsPolish.glow(color, 1.4)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg.material_override = fmat
	fg.position = pos
	parent.add_child(fg)
	return fg


func _duel_reset() -> void:
	p_hp = 100.0
	ai_hp = 100.0
	duel_cast_cd = 0.0
	duel_ai_t = 2.5
	duel_path.clear()
	duel_drawing = false
	duel_shield_t = 0.0
	duel_shield_bubble.visible = false
	for f in duel_fireballs:
		if is_instance_valid((f as Dictionary)["node"]):
			((f as Dictionary)["node"] as Node).queue_free()
	duel_fireballs.clear()
	for b in duel_bolts:
		if is_instance_valid((b as Dictionary)["node"]):
			((b as Dictionary)["node"] as Node).queue_free()
	duel_bolts.clear()
	_set_msg("", 0.0)
	_update_hud()


func _duel_pointer() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.4)
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	var fwd := -camera.global_transform.basis.z
	var pp := camera.global_position + fwd * 1.4
	var denom := d.dot(fwd)
	if absf(denom) < 0.0001:
		return pp
	var t := (pp - o).dot(fwd) / denom
	return o + d * t


func _duel_process(delta: float, press: bool) -> void:
	duel_cast_cd = maxf(0.0, duel_cast_cd - delta)
	_update_duel_gesture(press)
	_update_duel_fireballs(delta)
	_update_duel_bolts(delta)
	_duel_ai(delta)
	if duel_shield_t > 0.0:
		duel_shield_t -= delta
		if duel_shield_t <= 0.0:
			duel_shield_bubble.visible = false
	duel_shield_bubble.visible = duel_shield_t > 0.0
	GraphicsPolish.pulse_glow(duel_hat_mat, 1.2, 0.8, elapsed, 2.5)
	if duel_p_hp_fg != null:
		duel_p_hp_fg.scale.x = clampf(p_hp / 100.0, 0.01, 1.0)
	if duel_ai_hp_fg != null:
		duel_ai_hp_fg.scale.x = clampf(ai_hp / 100.0, 0.01, 1.0)
	_update_hud()
	if ai_hp <= 0.0 and _mode == "duels":
		_duel_win()
	elif p_hp <= 0.0 and _mode == "duels":
		_duel_lose()


func _update_duel_gesture(press: bool) -> void:
	var pt := _duel_pointer()
	if press and not duel_drawing:
		duel_drawing = true
		duel_path.clear()
		duel_path_t0 = elapsed
		duel_gesture_cursor.visible = true
	if duel_drawing:
		duel_gesture_cursor.position = pt
		if duel_path.is_empty() or (duel_path[duel_path.size() - 1] as Vector3).distance_to(pt) > 0.02:
			duel_path.append(pt)
		while duel_path.size() > 2 and elapsed - duel_path_t0 > DUEL_GESTURE_WINDOW:
			duel_path.pop_front()
			duel_path_t0 += 1.0 / 30.0
		_draw_duel_line()
		if elapsed - duel_path_t0 >= DUEL_GESTURE_WINDOW and duel_path.size() >= 6:
			_cast_from_duel_path()
			duel_path.clear()
			duel_path_t0 = elapsed
	if not press and duel_drawing:
		duel_drawing = false
		duel_gesture_cursor.visible = false
		duel_gesture_im.clear_surfaces()
		if duel_path.size() >= 6:
			_cast_from_duel_path()
		duel_path.clear()


func _draw_duel_line() -> void:
	duel_gesture_im.clear_surfaces()
	if duel_path.size() < 2:
		return
	duel_gesture_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in duel_path:
		duel_gesture_im.surface_add_vertex(p)
	duel_gesture_im.surface_end()


func _cast_from_duel_path() -> void:
	if duel_cast_cd > 0.0 or _mode != "duels":
		return
	var res: Dictionary = _classify_duel_path(duel_path)
	var kind: String = res["kind"]
	if kind == "none":
		return
	duel_cast_cd = DUEL_CAST_CD
	Haptics.pulse(0.85, 0.14)
	match kind:
		"fireball":
			_duel_spawn_fireball(Vector3(0.0, 1.5, 2.0), duel_wizard.position + Vector3(0, 1.2, 0), true)
			_set_msg("Fireball!", 0.8)
		"lightning":
			_duel_cast_lightning()
			_set_msg("Lightning!", 0.8)
		"shield":
			duel_shield_t = 3.0
			duel_shield_bubble.visible = true
			GraphicsPolish.spawn_sparks(self, Vector3(0, 1.3, 2.0), Color(0.4, 0.9, 1.0), 20)
			_set_msg("Shield up!", 0.8)


func _classify_duel_path(pts: Array) -> Dictionary:
	var res := {"kind": "none", "style": 0.0}
	var n: int = pts.size()
	if n < 6:
		return res
	var total := 0.0
	var dir_changes := 0
	var prev_dir := Vector3.ZERO
	var minp: Vector3 = pts[0]
	var maxp: Vector3 = pts[0]
	for i in range(1, n):
		var d: Vector3 = (pts[i] as Vector3) - (pts[i - 1] as Vector3)
		var dl := d.length()
		total += dl
		if dl > 0.005:
			if prev_dir != Vector3.ZERO and prev_dir.angle_to(d) > deg_to_rad(60.0):
				dir_changes += 1
			prev_dir = d.normalized()
		var pi: Vector3 = pts[i]
		minp.x = minf(minp.x, pi.x)
		minp.y = minf(minp.y, pi.y)
		maxp.x = maxf(maxp.x, pi.x)
		maxp.y = maxf(maxp.y, pi.y)
	var closure: float = (pts[0] as Vector3).distance_to(pts[n - 1] as Vector3)
	var dur := maxf(elapsed - duel_path_t0, 0.05)
	var speed := total / dur
	var w := maxp.x - minp.x
	var h := maxp.y - minp.y
	var aspect := w / maxf(h, 0.001)
	var push_z: float = (pts[n - 1] as Vector3).z - (pts[0] as Vector3).z
	if (push_z < -0.35 and speed > 1.2) or (speed > 2.6 and total > 0.5 and dir_changes <= 1):
		res["kind"] = "shield"
		res["style"] = clampf(speed / 4.0, 0.0, 1.0)
		return res
	if total < 0.7:
		return res
	if closure / total < 0.30 and total > 0.9 and aspect > 0.45 and aspect < 2.2:
		res["kind"] = "fireball"
		res["style"] = 1.0 - closure / total
		return res
	if dir_changes >= 4:
		res["kind"] = "lightning"
		res["style"] = clampf(dir_changes / 8.0, 0.0, 1.0)
		return res
	return res


func _duel_spawn_fireball(from: Vector3, to: Vector3, from_player: bool) -> void:
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	node.mesh = sm
	var col := Color(1.0, 0.55, 0.15) if from_player else Color(1.0, 0.30, 0.75)
	node.material_override = GraphicsPolish.glow(col, 2.2)
	node.position = from
	node.add_child(GraphicsPolish.make_trail(col, 0.07))
	add_child(node)
	var dir := (to - from).normalized()
	duel_fireballs.append({"node": node, "vel": dir * 6.0, "from_player": from_player})


func _duel_cast_lightning() -> void:
	var a := Vector3(0.0, 1.6, 2.0)
	var b := duel_wizard.position + Vector3(0, 1.2, 0)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 12
	for i in range(segs + 1):
		var p := a.lerp(b, float(i) / float(segs))
		if i > 0 and i < segs:
			p += Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.1, 0.1))
		im.surface_add_vertex(p)
	im.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = im
	inst.material_override = GraphicsPolish.glow(Color(0.6, 0.9, 1.0), 2.5)
	add_child(inst)
	duel_bolts.append({"node": inst, "t": 0.18})
	GraphicsPolish.spawn_sparks(self, b, Color(0.6, 0.9, 1.0), 30)
	ai_hp = maxf(0.0, ai_hp - 14.0)


func _update_duel_fireballs(delta: float) -> void:
	var wiz_c := duel_wizard.position + Vector3(0, 1.2, 0)
	var pc := Vector3(0.0, 1.3, 2.0)
	for i in range(duel_fireballs.size() - 1, -1, -1):
		var f: Dictionary = duel_fireballs[i]
		var node: MeshInstance3D = f["node"]
		if not is_instance_valid(node):
			duel_fireballs.remove_at(i)
			continue
		node.position += (f["vel"] as Vector3) * delta
		var p := node.position
		var from_player: bool = f["from_player"]
		if from_player:
			if p.distance_to(wiz_c) < 0.45:
				ai_hp = maxf(0.0, ai_hp - 22.0)
				GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.55, 0.15), 28)
				Haptics.thump()
				node.queue_free()
				duel_fireballs.remove_at(i)
			elif p.distance_to(wiz_c) > 14.0:
				node.queue_free()
				duel_fireballs.remove_at(i)
		else:
			if duel_shield_t > 0.0 and p.distance_to(pc) < 0.7:
				GraphicsPolish.spawn_sparks(self, p, Color(0.4, 0.9, 1.0), 16)
				node.queue_free()
				duel_fireballs.remove_at(i)
			elif p.distance_to(pc) < 0.4:
				p_hp = maxf(0.0, p_hp - 12.0)
				GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.3, 0.75), 24)
				Haptics.pulse(1.0, 0.2)
				node.queue_free()
				duel_fireballs.remove_at(i)
			elif p.distance_to(pc) > 14.0:
				node.queue_free()
				duel_fireballs.remove_at(i)


func _update_duel_bolts(delta: float) -> void:
	for i in range(duel_bolts.size() - 1, -1, -1):
		var b: Dictionary = duel_bolts[i]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			if is_instance_valid(b["node"]):
				(b["node"] as Node).queue_free()
			duel_bolts.remove_at(i)


func _duel_ai(delta: float) -> void:
	duel_phase += delta
	duel_wizard.position.x = 1.3 * sin(duel_phase * 0.7)
	duel_ai_t -= delta
	if duel_ai_t <= 0.0:
		duel_ai_t = randf_range(2.0, 3.4)
		GraphicsPolish.spawn_sparks(self, duel_wizard.position + Vector3(0.45, 1.85, 0), Color(1.0, 0.4, 0.8), 10)
		_duel_spawn_fireball(duel_wizard.position + Vector3(0, 1.4, 0), Vector3(0.0, 1.3, 2.0), false)


func _duel_cleanup_visuals() -> void:
	for f in duel_fireballs:
		if is_instance_valid((f as Dictionary)["node"]):
			((f as Dictionary)["node"] as Node).queue_free()
	duel_fireballs.clear()
	for b in duel_bolts:
		if is_instance_valid((b as Dictionary)["node"]):
			((b as Dictionary)["node"] as Node).queue_free()
	duel_bolts.clear()
	if duel_shield_bubble != null:
		duel_shield_bubble.visible = false
	if duel_gesture_cursor != null:
		duel_gesture_cursor.visible = false
	duel_drawing = false
	duel_path.clear()
	duel_gesture_im.clear_surfaces()


func _duel_win() -> void:
	_mode = "grade"
	duel_wins += 1
	house_points[house] += 40
	_save()
	_duel_cleanup_visuals()
	_set_msg("VICTORY! The rival yields. +40 %s points" % HOUSE_NAMES[house], 60.0)
	GraphicsPolish.spawn_confetti(self, duel_wizard.position + Vector3(0, 1.5, 0), 80)
	Haptics.pulse(0.9, 0.25)
	_clear_buttons()
	_add_button("again", Vector3(-0.75, 1.15, 0.9), "Rematch")
	_add_button("menu", Vector3(0.75, 1.15, 0.9), "Great Hall")


func _duel_lose() -> void:
	_mode = "grade"
	house_points[house] += 5
	_save()
	_duel_cleanup_visuals()
	_set_msg("DEFEATED... +5 %s points for courage" % HOUSE_NAMES[house], 60.0)
	_clear_buttons()
	_add_button("again", Vector3(-0.75, 1.15, 0.9), "Rematch")
	_add_button("menu", Vector3(0.75, 1.15, 0.9), "Great Hall")


# ------------------------------------------------------------ mode switch ---
func _show_station(which: String) -> void:
	if menu_root != null:
		menu_root.visible = which == "menu"
	if charms_root != null:
		charms_root.visible = which == "charms"
	if potions_root != null:
		potions_root.visible = which == "potions"
	if defense_root != null:
		defense_root.visible = which == "defense"
	if duel_root != null:
		duel_root.visible = which == "duels"
	if shield_bubble != null and which != "defense":
		shield_bubble.visible = false
	# Duel extras live outside duel_root; gate them too.
	var duel_on := which == "duels"
	if duel_shield_bubble != null and not duel_on:
		duel_shield_bubble.visible = false
	if duel_gesture_cursor != null and not duel_on:
		duel_gesture_cursor.visible = false
		duel_drawing = false


func _set_mode(m: String) -> void:
	if _mode == "duels" and m != "duels":
		_duel_cleanup_visuals()
	_mode = m
	_clear_buttons()
	_set_msg("", 0.0)
	match m:
		"menu":
			_show_station("menu")
			_build_menu_buttons()
			_refresh_menu_info()
		"charms":
			_show_station("charms")
		"potions":
			_show_station("potions")
		"defense":
			_show_station("defense")
		"exams":
			_show_station("none")
		"duels":
			_show_station("duels")
			_add_button("menu", Vector3(2.9, 2.6, 0.6), "Flee", 0.8, 0.26, Color(0.40, 0.14, 0.10))
		"grade":
			_show_station("none")
	_update_hud()


# ------------------------------------------------------------------ process ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if hover_id != "" and (_mode == "menu" or _mode == "grade" or _mode == "duels"):
				_click_button(hover_id)


func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_key_pressed(KEY_R):
		_restart_mode()
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_set_msg("", 0.0)
	# Candle flicker + bob.
	candle_t += delta
	for cf in candle_flames:
		var d: Dictionary = cf
		var n: Node3D = d["node"]
		if not is_instance_valid(n):
			continue
		var base_y: float = d["base_y"]
		var ph: float = d["phase"]
		n.position.y = base_y + sin(candle_t * 1.7 + ph) * 0.05
	# Input edges.
	var press := _press_active()
	var just_pressed := press and not _prev_press
	var just_released := not press and _prev_press
	_prev_press = press
	_update_button_hover()
	if just_pressed and hover_id != "" and ARUpgradeKit.is_xr_active():
		_click_button(hover_id)
	# Mode updates.
	match _mode:
		"charms":
			_charms_process(delta, press, just_pressed, just_released)
		"potions":
			_potions_process(delta, press, just_pressed, just_released)
		"defense":
			_defense_process(delta, press)
		"exams":
			_exams_process(delta, press, just_pressed, just_released)
		"duels":
			_duel_process(delta, press)
	_update_hud()


func _restart_mode() -> void:
	match _mode:
		"charms":
			_click_button("lesson_charms")
		"potions":
			_click_button("lesson_potions")
		"defense":
			_click_button("lesson_defense")
		"exams":
			_click_button("exams")
		"duels":
			_click_button("duels")
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
