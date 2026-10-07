## Holo Chef: AR cooking game on a kitchen counter anchored to a real table.
## Timed customer orders across 3 recipes (cheeseburger, veggie soup, garden
## salad). Gesture cooking: CHOP with a downward hand slam over the cutting
## board, STIR the soup pot with circular motion, FLIP the patty with a quick
## flick over the pan, TOSS the salad, then plate to serve. Correct order of
## operations earns a presentation bonus; each dish scores 1-3 stars and coins.
## Desktop: mouse does every gesture (slam mouse down to chop, draw circles to
## stir, flick fast to flip/toss, click plate to serve). XR: hand pointer with
## the same velocity patterns, XR-gated so desktop never double-fires.
## Kenney "Food Kit" CC0 models for every ingredient, tool and vessel.
## R restarts the shift. Coins/best persist in user://nexus_chef.cfg.
extends Node3D

const MODEL_DIR := "res://assets/models/holo_chef/"
const SAVE_PATH := "user://nexus_chef.cfg"
const TABLE_H := 0.75
const TOP_Y := 0.06

const RECIPES := [
	{
		"name": "Cheeseburger", "time": 95.0, "result": "burger-cheese",
		"steps": [
			{"action": "chop", "ingredient": "tomato", "label": "Chop the tomato", "count": 4},
			{"action": "chop", "ingredient": "cabbage", "label": "Chop the lettuce", "count": 4},
			{"action": "flip", "ingredient": "meat-patty", "label": "Flip the patty x2", "count": 2},
			{"action": "serve", "label": "Serve it up!", "count": 1},
		],
	},
	{
		"name": "Veggie Soup", "time": 80.0, "result": "bowl-soup",
		"steps": [
			{"action": "chop", "ingredient": "carrot", "label": "Chop the carrot", "count": 4},
			{"action": "chop", "ingredient": "onion", "label": "Chop the onion", "count": 4},
			{"action": "stir", "label": "Stir the soup (2 rounds)", "count": 2},
			{"action": "serve", "label": "Serve it up!", "count": 1},
		],
	},
	{
		"name": "Garden Salad", "time": 65.0, "result": "salad",
		"steps": [
			{"action": "chop", "ingredient": "tomato", "label": "Chop the tomato", "count": 3},
			{"action": "chop", "ingredient": "carrot", "label": "Chop the carrot", "count": 3},
			{"action": "chop", "ingredient": "broccoli", "label": "Chop the broccoli", "count": 3},
			{"action": "toss", "label": "Toss the salad x2", "count": 2},
			{"action": "serve", "label": "Serve it up!", "count": 1},
		],
	},
]

var camera: Camera3D = null
var counter: Node3D = null
var board_pos := Vector3.ZERO
var pan_pos := Vector3.ZERO
var pot_pos := Vector3.ZERO
var plate_pos := Vector3.ZERO
var knife: Node3D = null
var spatula: Node3D = null
var spoon: Node3D = null
var station_rings := {}
var state := "intro"
var order_idx := 0
var step_idx := 0
var step_progress := 0
var time_left := 0.0
var order_time := 1.0
var mistakes := 0
var coins := 0
var stars_total := 0
var best_stars := 0
var shifts_done := 0
var msg := ""
var msg_t := 0.0
var hud_label: Label3D = null
var step_label: Label3D = null
var msg_label: Label3D = null
var card_panel: Node3D = null
var card_labels: Array = []
var timer_bar: MeshInstance3D = null
var timer_bar_bg: MeshInstance3D = null
var active_ingredient: Node3D = null
var patty: Node3D = null
var steam: GPUParticles3D = null
var sizzle_t := 0.0
var chop_cool := 0.0
var flip_cool := 0.0
var stir_angle := 0.0
var stir_prev_angle := 0.0
var stir_active := false
var pointer_prev := Vector3.ZERO
var pointer_vel := Vector3.ZERO
var pointer_init := false
var mouse_prev := Vector2.ZERO
var mouse_vel := Vector2.ZERO
var mouse_init := false
var prev_pinch := false
var pulse_t := 0.0
var save_t := 0.0

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_card_wall: Dictionary = {}


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "holo_chef_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	counter = Node3D.new()
	counter.name = "Counter"
	add_child(counter)
	ARUpgradeKit.place_on_table(counter, 1.0, TABLE_H)
	_build_kitchen()
	_build_restaurant_dressing()
	_build_stations()
	_build_tools()
	_build_hud()
	_load_save()
	_show_order_card()
	GraphicsPolish.spawn_ambient_motes(self, counter.position + Vector3(0, 0.8, 0), 1.6, 26)
	_apply_room_layout()


## v0.7.0: rest the counter on the largest real table and tape the recipe
## card to the nearest real wall. All guarded; fallback keeps the default.
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
	# MORPH-B (v0.7.0): plants -> living herb garden; storage -> pantry vault
	_morph_anchors("PLANT", "nature", 2)
	_morph_anchors("STORAGE", "candy", 1)
	var best := {}
	var best_a := 0.0
	for t_v in _room_tables:
		var t: Dictionary = t_v
		var a: float = (t["size"] as Vector3).x * (t["size"] as Vector3).z
		if a > best_a:
			best_a = a
			best = t
	if not best.is_empty():
		var tp: Vector3 = to_local(best["position"])
		counter.position.x = tp.x
		counter.position.z = tp.z
	var bw := {}
	var bd := 1e9
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var dd: float = (to_local(w["position"]) - counter.position).length()
		if dd < bd:
			bd = dd
			bw = w
	_room_card_wall = bw
	_mount_card()


func _mount_card() -> void:
	if _room_card_wall.is_empty() or card_panel == null or not is_instance_valid(card_panel):
		return
	var n: Vector3 = _room_card_wall["normal"]
	n.y = 0.0
	n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
	var fw: Vector3 = (_room_card_wall["position"] as Vector3) + n * 0.06
	fw.y = 1.5
	card_panel.position = to_local(fw)
	var c := _room_bounds.get_center()
	var d := Vector2(c.x - fw.x, c.y - fw.z)
	card_panel.rotation.y = atan2(d.x, d.y) if d.length() > 0.05 else 0.0


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.55, 0.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, TABLE_H, -1.0), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.38, 0.34)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.07, 0.06)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _spawn_model(file: String, parent: Node, pos: Vector3, scl: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scl
	parent.add_child(holder)
	var ps: PackedScene = load(MODEL_DIR + file + ".glb")
	if ps != null:
		var inst: Node3D = ps.instantiate()
		holder.add_child(inst)
	return holder


func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


func _build_kitchen() -> void:
	# Counter body + warm wood top.
	_box(counter, Vector3(0, -0.32, 0), Vector3(1.8, 0.64, 0.85),
		GraphicsPolish.pbr_preset(Color(0.30, 0.22, 0.15), "matte"))
	_box(counter, Vector3(0, TOP_Y - 0.02, 0), Vector3(1.9, 0.05, 0.95),
		GraphicsPolish.pbr(Color(0.55, 0.38, 0.24), 0.05, 0.5))
	# Backsplash wall with tile stripes.
	_box(counter, Vector3(0, 0.55, -0.55), Vector3(1.9, 0.9, 0.06),
		GraphicsPolish.pbr_preset(Color(0.12, 0.14, 0.16), "matte"))
	for i in 6:
		_box(counter, Vector3(-0.75 + float(i) * 0.3, 0.55, -0.515), Vector3(0.26, 0.8, 0.02),
			GraphicsPolish.pbr_preset(Color(0.16, 0.19, 0.22), "plastic"))
	# Shelf with dressing bottles.
	_box(counter, Vector3(0.55, 0.78, -0.5), Vector3(0.9, 0.04, 0.22),
		GraphicsPolish.pbr(Color(0.4, 0.28, 0.18), 0.05, 0.6))
	_spawn_model("bottle-ketchup", counter, Vector3(0.32, 0.80, -0.5), 0.9)
	_spawn_model("shaker-salt", counter, Vector3(0.55, 0.80, -0.5), 0.9)
	_spawn_model("shaker-pepper", counter, Vector3(0.72, 0.80, -0.5), 0.9)
	_spawn_model("mug", counter, Vector3(-0.62, TOP_Y, -0.32), 1.0)
	# Warm pendant lights over the counter.
	for i in 3:
		var lx := -0.55 + float(i) * 0.55
		GraphicsPolish.make_point_light(counter, Vector3(lx, 1.05, 0.1), Color(1.0, 0.75, 0.45), 0.9, 2.5)
		_box(counter, Vector3(lx, 1.15, 0.1), Vector3(0.16, 0.1, 0.16),
			GraphicsPolish.glow(Color(1.0, 0.8, 0.5), 1.6))


## v0.7.0 KayKit: restaurant dressing around the cooking counter — side
## counter, stove and a dining set, all CC0. Pure ambiance at floor level;
## the gameplay counter and station positions are untouched.
func _build_restaurant_dressing() -> void:
	var dir := "res://assets/models/holo_chef/"
	var side := ModelLib.spawn(dir + "kitchencounter_straight_A.gltf", self, Vector3(-2.6, 0, -1.8))
	if side != null:
		side.scale = Vector3.ONE * 0.7
		side.rotation.y = 0.3
	var stove := ModelLib.spawn(dir + "stove_single.gltf", self, Vector3(2.6, 0, -1.8))
	if stove != null:
		stove.scale = Vector3.ONE * 0.6
		stove.rotation.y = -0.3
	var table := ModelLib.spawn(dir + "table_round_A.gltf", self, Vector3(2.7, 0, 1.3))
	if table != null:
		table.scale = Vector3.ONE * 0.55
	for i in 2:
		var chair := ModelLib.spawn(dir + "chair_A.gltf", self,
			Vector3(2.7, 0, 2.45) if i == 0 else Vector3(1.7, 0, 1.3))
		if chair != null:
			chair.rotation.y = PI if i == 0 else PI * 0.5


func _build_stations() -> void:
	board_pos = Vector3(-0.60, TOP_Y, 0.05)
	pan_pos = Vector3(-0.20, TOP_Y, 0.05)
	pot_pos = Vector3(0.22, TOP_Y, 0.02)
	plate_pos = Vector3(0.62, TOP_Y, 0.05)
	# Cutting board (Kenney).
	_spawn_model("cutting-board", counter, board_pos, 1.4)
	# Stove burner + frying pan (Kenney).
	var burner := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.13
	bc.bottom_radius = 0.15
	bc.height = 0.03
	burner.mesh = bc
	burner.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.08, 0.1), "metal")
	burner.position = pan_pos + Vector3(0, 0.015, 0)
	counter.add_child(burner)
	var coil := MeshInstance3D.new()
	var cc := TorusMesh.new()
	cc.inner_radius = 0.07
	cc.outer_radius = 0.10
	coil.mesh = cc
	coil.material_override = GraphicsPolish.glow(Color(1.0, 0.35, 0.1), 1.8)
	coil.position = pan_pos + Vector3(0, 0.035, 0)
	coil.rotation_degrees.x = 90
	counter.add_child(coil)
	_spawn_model("frying-pan", counter, pan_pos + Vector3(0, 0.03, 0), 1.2)
	# Soup pot (Kenney) + steam.
	_spawn_model("pot-stew", counter, pot_pos, 1.25)
	steam = _make_steam()
	steam.position = pot_pos + Vector3(0, 0.22, 0)
	counter.add_child(steam)
	# Plating plate (Kenney).
	_spawn_model("plate-dinner", counter, plate_pos, 1.3)
	# Station highlight rings.
	for key in ["board", "pan", "pot", "plate"]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.19
		ring.mesh = tm
		ring.material_override = GraphicsPolish.glow(Color(0.3, 1.0, 0.5), 1.4)
		ring.rotation_degrees.x = 90
		ring.visible = false
		counter.add_child(ring)
		station_rings[key] = ring
	station_rings["board"].position = board_pos + Vector3(0, 0.01, 0)
	station_rings["pan"].position = pan_pos + Vector3(0, 0.01, 0)
	station_rings["pot"].position = pot_pos + Vector3(0, 0.01, 0)
	station_rings["plate"].position = plate_pos + Vector3(0, 0.01, 0)


func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.6
	p.preprocess = 1.6
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.08
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.5
	mat.gravity = Vector3(0, 0.35, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.12
	mat.color = Color(1, 1, 1, 0.35)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(1, 1, 1, 0.4)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qm
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _build_tools() -> void:
	knife = _spawn_model("cooking-knife-chopping", counter, board_pos + Vector3(0.12, 0.16, 0), 1.2)
	knife.rotation_degrees = Vector3(0, 0, -35)
	spatula = _spawn_model("cooking-spatula", counter, pan_pos + Vector3(0.14, 0.12, 0), 1.1)
	spatula.rotation_degrees = Vector3(0, 0, -50)
	spoon = _spawn_model("cooking-spoon", counter, pot_pos + Vector3(0.12, 0.18, 0), 1.1)
	spoon.rotation_degrees = Vector3(20, 0, -40)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 52, Color(1, 1, 1))
	hud_label.position = counter.position + Vector3(-1.15, 1.55, 0.1)
	hud_label.pixel_size = 0.005
	add_child(hud_label)
	step_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.5))
	step_label.position = counter.position + Vector3(0, 1.75, -0.2)
	step_label.pixel_size = 0.007
	add_child(step_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.4))
	msg_label.position = counter.position + Vector3(0, 1.35, -0.2)
	msg_label.pixel_size = 0.008
	add_child(msg_label)
	# Timer bar.
	timer_bar_bg = _box(self, counter.position + Vector3(0, 1.95, -0.2), Vector3(1.3, 0.045, 0.02),
		GraphicsPolish.pbr_preset(Color(0.1, 0.1, 0.12), "matte"))
	timer_bar = _box(self, counter.position + Vector3(0, 1.95, -0.19), Vector3(1.26, 0.03, 0.02),
		GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 1.2))
	_update_hud()


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		coins = int(cfg.get_value("chef", "coins", 0))
		best_stars = int(cfg.get_value("chef", "best_stars", 0))
		shifts_done = int(cfg.get_value("chef", "shifts", 0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("chef", "coins", coins)
	cfg.set_value("chef", "best_stars", best_stars)
	cfg.set_value("chef", "shifts", shifts_done)
	cfg.save(SAVE_PATH)


# ---------------------------------------------------------------- order flow

func _recipe() -> Dictionary:
	return RECIPES[order_idx]


func _step() -> Dictionary:
	return RECIPES[order_idx]["steps"][step_idx]


func _show_order_card() -> void:
	state = "intro"
	_clear_card()
	card_panel = Node3D.new()
	card_panel.position = counter.position + Vector3(0, 0.95, 0.15)
	add_child(card_panel)
	_mount_card() # v0.7.0: re-tape the card to the real wall when room data is cached
	var panel := _box(card_panel, Vector3.ZERO, Vector3(1.05, 0.72, 0.03),
		GraphicsPolish.pbr_preset(Color(0.09, 0.10, 0.13), "matte"))
	panel.name = "Panel"
	var title: Label3D = GraphicsPolish.make_label("ORDER %d/3: %s" % [order_idx + 1, _recipe()["name"]], 54, Color(1.0, 0.85, 0.4))
	title.position = Vector3(0, 0.27, 0.03)
	title.pixel_size = 0.004
	card_panel.add_child(title)
	var steps: Array = _recipe()["steps"]
	for i in steps.size():
		var l: Label3D = GraphicsPolish.make_label("- " + str(steps[i]["label"]), 44, Color(0.9, 0.92, 0.95))
		l.position = Vector3(-0.42, 0.12 - float(i) * 0.11, 0.03)
		l.pixel_size = 0.0032
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		card_panel.add_child(l)
		card_labels.append(l)
	var hint: Label3D = GraphicsPolish.make_label("Click / pinch to start  (%ds)" % int(_recipe()["time"]), 40, Color(0.6, 1.0, 0.7))
	hint.position = Vector3(0, -0.29, 0.03)
	hint.pixel_size = 0.0032
	card_panel.add_child(hint)
	_set_step_text("")


func _clear_card() -> void:
	for l in card_labels:
		if is_instance_valid(l):
			l.queue_free()
	card_labels.clear()
	if card_panel != null and is_instance_valid(card_panel):
		card_panel.queue_free()
	card_panel = null


func _start_cooking() -> void:
	_clear_card()
	state = "cook"
	step_idx = 0
	step_progress = 0
	mistakes = 0
	order_time = float(_recipe()["time"])
	time_left = order_time
	_begin_step()
	_set_msg("Order up!", 1.2)


func _begin_step() -> void:
	_clear_step_props()
	step_progress = 0
	stir_angle = 0.0
	stir_active = false
	var s := _step()
	_highlight_station(_station_for(s["action"]), true)
	match s["action"]:
		"chop":
			active_ingredient = _spawn_model(s["ingredient"], counter, board_pos + Vector3(0, 0.10, 0), 1.6)
		"flip":
			patty = _spawn_model(s["ingredient"], counter, pan_pos + Vector3(0, 0.09, 0), 1.5)
	_set_step_text(str(s["label"]))
	_update_card_checks()


func _station_for(action: String) -> String:
	match action:
		"chop":
			return "board"
		"flip":
			return "pan"
		"stir":
			return "pot"
		"toss", "serve":
			return "plate"
	return "board"


func _highlight_station(key: String, on: bool) -> void:
	for k in station_rings.keys():
		station_rings[k].visible = (k == key and on)


func _clear_step_props() -> void:
	_highlight_station("", false)
	if active_ingredient != null and is_instance_valid(active_ingredient):
		active_ingredient.queue_free()
	active_ingredient = null
	if patty != null and is_instance_valid(patty):
		patty.queue_free()
	patty = null


func _update_card_checks() -> void:
	# Card is hidden while cooking; checks show on the step label instead.
	pass


func _set_step_text(t: String) -> void:
	if step_label != null:
		step_label.text = t


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	if msg_label != null:
		msg_label.text = msg


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Coins %d   Stars %d   Best %d" % [coins, stars_total, best_stars]
	if timer_bar != null and order_time > 0.0:
		var frac := clampf(time_left / order_time, 0.0, 1.0)
		timer_bar.scale.x = maxf(frac, 0.001)
		timer_bar.position.x = counter.position.x - (1.26 * (1.0 - frac)) * 0.5
		var c := Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac)
		timer_bar.material_override = GraphicsPolish.glow(c, 1.2)


# ---------------------------------------------------------------- gestures

func _pointer_world() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.1)
	if camera == null:
		return counter.position + Vector3(0, 0.5, 0)
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var top_y := counter.position.y + TOP_Y
	if absf(dir.y) < 0.001:
		return pointer_prev
	var t := (top_y - origin.y) / dir.y
	if t < 0.0:
		return pointer_prev
	return origin + dir * t


func _station_world(key: String) -> Vector3:
	match key:
		"board":
			return counter.to_global(board_pos)
		"pan":
			return counter.to_global(pan_pos)
		"pot":
			return counter.to_global(pot_pos)
		"plate":
			return counter.to_global(plate_pos)
	return counter.position


func _in_zone(p: Vector3, key: String, radius: float) -> bool:
	var c := _station_world(key)
	var d := Vector2(p.x - c.x, p.z - c.z).length()
	return d < radius


func _do_chop() -> void:
	if chop_cool > 0.0:
		return
	chop_cool = 0.35
	Haptics.thump()
	# Knife slam animation.
	if knife != null:
		var tw := create_tween()
		tw.tween_property(knife, "position:y", knife.position.y - 0.10, 0.08)
		tw.tween_property(knife, "position:y", knife.position.y, 0.18)
	var s := _step()
	GraphicsPolish.spawn_sparks(self, _station_world("board") + Vector3(0, 0.12, 0), Color(1.0, 0.9, 0.5), 8)
	step_progress += 1
	if step_progress >= int(s["count"]):
		_chopped_to_vessel(s)
		_advance_step()
	else:
		_set_step_text("%s  (%d/%d)" % [s["label"], step_progress, int(s["count"])])


func _chopped_to_vessel(s: Dictionary) -> void:
	# Chopped chunks fly to the next vessel, then vanish.
	if active_ingredient != null and is_instance_valid(active_ingredient):
		var target := _station_world("pot") if order_idx == 1 else _station_world("plate")
		var chunks := active_ingredient
		active_ingredient = null
		var tw := create_tween().set_parallel(true)
		tw.tween_property(chunks, "global_position", target + Vector3(0, 0.15, 0), 0.5).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(chunks, "scale", Vector3.ONE * 0.4, 0.5)
		tw.chain().tween_callback(chunks.queue_free)


func _do_flip() -> void:
	if flip_cool > 0.0 or patty == null:
		return
	flip_cool = 0.8
	Haptics.pulse(0.8, 0.15)
	GraphicsPolish.spawn_sparks(self, _station_world("pan") + Vector3(0, 0.15, 0), Color(1.0, 0.6, 0.2), 10)
	# Spatula scoop + patty flip.
	if spatula != null:
		var st := create_tween()
		st.tween_property(spatula, "rotation_degrees:z", -15.0, 0.12)
		st.tween_property(spatula, "rotation_degrees:z", -50.0, 0.2)
	var tw := create_tween()
	tw.tween_property(patty, "position:y", patty.position.y + 0.22, 0.18)
	tw.tween_property(patty, "rotation_degrees:x", patty.rotation_degrees.x + 360.0, 0.36)
	tw.parallel().tween_property(patty, "position:y", patty.position.y, 0.18)
	var s := _step()
	step_progress += 1
	if step_progress >= int(s["count"]):
		# Patty flies to the plate.
		var target := _station_world("plate")
		var pp := patty
		patty = null
		var ftw := create_tween().set_parallel(true)
		ftw.tween_property(pp, "global_position", target + Vector3(0, 0.12, 0), 0.6).set_trans(Tween.TRANS_CUBIC)
		ftw.chain().tween_callback(pp.queue_free)
		_advance_step()
	else:
		_set_step_text("%s  (%d/%d)" % [s["label"], step_progress, int(s["count"])])


func _do_stir_done() -> void:
	Haptics.tick()
	GraphicsPolish.spawn_sparks(self, _station_world("pot") + Vector3(0, 0.25, 0), Color(1.0, 0.85, 0.4), 12)
	_set_msg("Soup's looking great!", 1.2)
	_advance_step()


func _do_toss() -> void:
	if flip_cool > 0.0:
		return
	flip_cool = 0.8
	Haptics.pulse(0.7, 0.12)
	GraphicsPolish.spawn_sparks(self, _station_world("plate") + Vector3(0, 0.18, 0), Color(0.5, 1.0, 0.5), 12)
	var s := _step()
	step_progress += 1
	if step_progress >= int(s["count"]):
		_advance_step()
	else:
		_set_step_text("%s  (%d/%d)" % [s["label"], step_progress, int(s["count"])])


func _do_serve() -> void:
	Haptics.tick()
	_advance_step()


func _advance_step() -> void:
	step_idx += 1
	if step_idx >= RECIPES[order_idx]["steps"].size():
		_dish_complete()
	else:
		_begin_step()


func _dish_complete() -> void:
	state = "served"
	_clear_step_props()
	_highlight_station("", false)
	var frac := clampf(time_left / order_time, 0.0, 1.0)
	var stars := 1
	if frac > 0.45:
		stars = 3
	elif frac > 0.20:
		stars = 2
	var gained := 10 + stars * 5 + int(time_left * 0.5)
	if mistakes == 0:
		gained += 5
	coins += gained
	stars_total += stars
	# Plated dish reveal.
	var dish := _spawn_model(_recipe()["result"], counter, plate_pos + Vector3(0, 0.10, 0), 1.5)
	dish.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(dish, "scale", Vector3.ONE * 1.5, 0.5).set_trans(Tween.TRANS_BACK)
	GraphicsPolish.spawn_confetti(self, _station_world("plate") + Vector3(0, 0.5, 0), 50)
	var star_str := ""
	for i in stars:
		star_str += "★"
	_set_msg("%s  +%d coins" % [star_str, gained], 3.0)
	_set_step_text("")
	_update_hud()
	_save()
	var t := get_tree().create_timer(3.2)
	t.timeout.connect(_next_order)


func _next_order() -> void:
	if state != "served":
		return
	order_idx += 1
	if order_idx >= RECIPES.size():
		_shift_complete()
	else:
		_show_order_card()


func _shift_complete() -> void:
	state = "shift_done"
	shifts_done += 1
	if stars_total > best_stars:
		best_stars = stars_total
	_save()
	_set_msg("Shift complete! %d stars, %d coins" % [stars_total, coins], 60.0)
	_set_step_text("R to cook again")
	GraphicsPolish.spawn_confetti(self, counter.position + Vector3(0, 1.0, 0), 90)
	_update_hud()


func _restart() -> void:
	order_idx = 0
	stars_total = 0
	_clear_step_props()
	_show_order_card()
	_update_hud()


func _order_failed() -> void:
	state = "served"
	_clear_step_props()
	_set_msg("Order burned! No stars.", 2.5)
	_set_step_text("")
	var t := get_tree().create_timer(2.6)
	t.timeout.connect(_next_order)


# ---------------------------------------------------------------- input

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
	if state == "intro":
		_start_cooking()
		Haptics.tick()
		return
	if state != "cook":
		return
	var s := _step()
	if s["action"] == "serve":
		var p := _pointer_world()
		if _in_zone(p, "plate", 0.28):
			_do_serve()


func _process(delta: float) -> void:
	pulse_t += delta
	if chop_cool > 0.0:
		chop_cool -= delta
	if flip_cool > 0.0:
		flip_cool -= delta
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if Input.is_key_pressed(KEY_R):
		_restart()
	if state == "intro":
		# XR: pinch anywhere to start.
		if ARUpgradeKit.is_xr_active():
			if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
				_start_cooking()
				Haptics.tick()
		_update_hud()
		return
	if state != "cook":
		_update_hud()
		return
	# Timer.
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_order_failed()
		_update_hud()
		return
	_track_pointer(delta)
	_track_mouse_velocity()
	_gesture_logic(delta)
	_tool_follow()
	_pulse_rings()
	# Sizzle while patty is in the pan.
	if patty != null and is_instance_valid(patty):
		sizzle_t -= delta
		if sizzle_t <= 0.0:
			sizzle_t = 0.5
			GraphicsPolish.spawn_sparks(self, _station_world("pan") + Vector3(0, 0.12, 0), Color(1.0, 0.55, 0.15), 5)
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


func _track_mouse_velocity() -> void:
	if ARUpgradeKit.is_xr_active():
		return
	var mp := get_viewport().get_mouse_position()
	if not mouse_init:
		mouse_prev = mp
		mouse_init = true
		return
	mouse_vel = mouse_vel.lerp(mp - mouse_prev, 0.5)
	mouse_prev = mp


func _slam_detected() -> bool:
	if ARUpgradeKit.is_xr_active():
		return pointer_vel.y < -2.0
	return mouse_vel.y > 14.0


func _in_wrong_station(p: Vector3) -> bool:
	for key in ["board", "pan", "pot", "plate"]:
		if key == _station_for(str(_step()["action"])):
			continue
		if _in_zone(p, key, 0.22):
			return true
	return false


func _gesture_logic(delta: float) -> void:
	var s := _step()
	var action := str(s["action"])
	var p := pointer_prev
	match action:
		"chop":
			var slamming := _slam_detected()
			if slamming and _in_zone(p, "board", 0.20):
				_do_chop()
			elif slamming and _in_wrong_station(p):
				mistakes += 1
				chop_cool = 0.5
				_set_msg("Wrong station!", 0.9)
				Haptics.tick()
		"stir":
			if _in_zone(p, "pot", 0.24):
				var c := _station_world("pot")
				var ang := atan2(p.z - c.z, p.x - c.x)
				if stir_active:
					var d := ang - stir_prev_angle
					if d > PI:
						d -= TAU
					elif d < -PI:
						d += TAU
					stir_angle += absf(d)
					var need := float(s["count"]) * TAU
					if stir_angle >= need:
						_do_stir_done()
					else:
						_set_step_text("%s  (%d%%)" % [s["label"], int(100.0 * stir_angle / need)])
				stir_prev_angle = ang
				stir_active = true
				# Spoon follows the hand.
				if spoon != null:
					spoon.global_position = spoon.global_position.lerp(p + Vector3(0, 0.10, 0), 0.35)
			else:
				stir_active = false
		"flip":
			if _in_zone(p, "pan", 0.22) and pointer_vel.length() > 3.2:
				_do_flip()
		"toss":
			if _in_zone(p, "plate", 0.26) and pointer_vel.length() > 3.2:
				_do_toss()
		"serve":
			if ARUpgradeKit.is_xr_active():
				if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) and _in_zone(p, "plate", 0.30):
					_do_serve()
			_set_step_text("Tap / pinch the plate to serve!")


func _tool_follow() -> void:
	if state != "cook":
		return
	var s := _step()
	var action := str(s["action"])
	var p := pointer_prev
	var pc := counter.to_local(p)
	# Active tool glows; tools drift toward the pointer when near their station.
	var tools := {"chop": knife, "flip": spatula, "stir": spoon}
	for key in tools.keys():
		var tool: Node3D = tools[key]
		if tool == null:
			continue
		var is_active: bool = (action == key) or (action == "toss" and key == "flip") or (action == "serve" and key == "flip")
		if is_active and _in_zone(p, _station_for(action), 0.45):
			var target := pc + Vector3(0, 0.14, 0)
			tool.position = tool.position.lerp(target, 0.25)


func _pulse_rings() -> void:
	for k in station_rings.keys():
		var ring: MeshInstance3D = station_rings[k]
		if ring.visible:
			var sc := 1.0 + 0.08 * sin(pulse_t * 5.0)
			ring.scale = Vector3(sc, sc, 1.0)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
