## plant_doctor.gd - Plant Doctor for NEXUS ARCADE.
## Point the camera at a real houseplant, CAPTURE the shot (pinch/click),
## and the photo lands on a floating 3D panel. HONESTY RULE: the game never
## claims AI identification - the USER picks the species from 6 visual 3D
## cards (each with a small procedural plant model). Then an AR care-plan
## card appears with real, mainstream-consensus care facts, a Holo Garden
## virtual twin grows in an AR pot next to the panel (scale-in animation +
## sparkles, spatially anchored), and a per-species water reminder is
## persisted to user://nexus_plant_care.cfg with due/overdue status on
## reopen. Multiple plants supported via "New plant"; a shelf shows the
## diagnosed collection. NO-CAMERA fallback: "Manual mode" skips capture
## and goes straight to the species picker (fully usable on desktop).
extends Node3D
class_name PlantDoctorGame

enum Step { CAPTURE, PICK, CARE }

const CARE_FILE := "user://nexus_plant_care.cfg"
const DAY := 86400

## Real, mainstream-consensus care facts. {name, latin, light, water,
## humidity, tip, interval_days}.
const SPECIES := [
	{
		"name": "Monstera", "latin": "Monstera deliciosa",
		"light": "Bright indirect",
		"water": "Every 1-2 weeks (top 2 in dry)",
		"humidity": "High (50-65%)",
		"tip": "Fenestrations appear with more light; give it a moss pole to climb.",
		"days": 10,
	},
	{
		"name": "Fiddle-Leaf Fig", "latin": "Ficus lyrata",
		"light": "Bright indirect (hates moving)",
		"water": "Every 7-10 days (top 2 in dry)",
		"humidity": "Average (40-50%)",
		"tip": "Pick a bright spot and leave it alone - it drops leaves when stressed.",
		"days": 9,
	},
	{
		"name": "Snake Plant", "latin": "Dracaena trifasciata",
		"light": "Low to bright indirect",
		"water": "Every 2-4 weeks (let dry fully)",
		"humidity": "Low / average",
		"tip": "Nearly unkillable - overwatering is the only real danger.",
		"days": 21,
	},
	{
		"name": "Pothos", "latin": "Epipremnum aureum",
		"light": "Low to bright indirect",
		"water": "Every 1-2 weeks (top 1 in dry)",
		"humidity": "Average",
		"tip": "Cuttings root in water in ~2 weeks - free new plants.",
		"days": 10,
	},
	{
		"name": "Peace Lily", "latin": "Spathiphyllum",
		"light": "Low to medium indirect",
		"water": "Weekly (droops when thirsty)",
		"humidity": "High (50%+)",
		"tip": "It droops dramatically when thirsty and perks up within hours of watering.",
		"days": 7,
	},
	{
		"name": "Cactus", "latin": "Cactaceae",
		"light": "Full direct sun",
		"water": "Every 3-4 weeks (dry fully)",
		"humidity": "Low",
		"tip": "Terracotta pot + gritty cactus mix = no rot. Water deeply but rarely.",
		"days": 25,
	},
]

const CARD_W := 0.62
const CARD_H := 0.85

var _cam: Camera3D = null
var _step: int = Step.CAPTURE
var _step_root: Node3D = null ## rebuilt per step
var _shelf_root: Node3D = null ## persistent collection shelf
var _buttons := {} ## StaticBody3D -> String
var _photo: Image = null
var _picked := -1
var _plants: Array = [] ## {species, name, diagnosed, last_watered, interval}
var _anchor_timer := 0.0
var _twin_grow_t := 0.0
var _twin: Node3D = null
var _status_label: Label3D = null
# v0.7.0 ROOMKIT: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_table_top_y := -1.0 ## real tabletop height, -1 = unknown


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "plant_doctor_main")
	_ensure_camera()
	_build_light()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, -1.0), 2.5, 40)
	_load_care()
	_build_shelf()
	_show_step(Step.CAPTURE)
	_apply_room_layout()


# ---------------------------------------------------------------- room layout

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: default behavior unchanged
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): plants -> triage glow on the patients themselves
	_morph_anchors("PLANT", "nature", 2)
	_seat_shelf_on_table()


## ROOMKIT: rest the plant shelf on the largest detected tabletop so the
## pots sit on a real surface instead of floating at a fixed spot.
func _seat_shelf_on_table() -> void:
	var t := _largest_table()
	if t.is_empty() or _shelf_root == null:
		return
	var top: Vector3 = t["position"]
	var size: Vector3 = t["size"]
	# Only use sane table-like surfaces: big enough, waist height.
	if size.x * size.z < 0.6 or top.y + size.y * 0.5 < 0.35 or top.y + size.y * 0.5 > 1.3:
		return
	_room_table_top_y = top.y + size.y * 0.5
	_shelf_root.position = Vector3(top.x, _room_table_top_y, top.z)


func _largest_table() -> Dictionary:
	var best := {}
	var best_area := 0.0
	for t_v in _room_tables:
		var t: Dictionary = t_v
		var size: Vector3 = t["size"]
		var area := size.x * size.z
		if area > best_area:
			best_area = area
			best = t
	return best


func _process(delta: float) -> void:
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("plant_doctor_main", global_transform)
	# Twin grow animation: scale-in with sparkles handled on spawn.
	if _twin != null and _twin_grow_t < 1.0:
		_twin_grow_t = minf(_twin_grow_t + delta * 1.2, 1.0)
		var e := _ease_out_back(_twin_grow_t)
		_twin.scale = Vector3.ONE * maxf(e, 0.01)
	# Pinch = click. Mouse clicks stay on _unhandled_input; the gate below
	# keeps the kit's mouse fallback from double-triggering.
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var hp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		_raycast_tap(hp, Vector3(0, 0, -1))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_go_back()


func _ease_out_back(t: float) -> float:
	var c := 1.70158
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


# ---------------------------------------------------------------- setup

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 1.6, 2.6)
	_cam.look_at(Vector3(0, 1.2, -1.0), Vector3.UP)


func _build_light() -> void:
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.5)
	env.ambient_light_energy = 0.9
	amb.environment = env
	add_child(amb)


# ---------------------------------------------------------------- steps

func _clear_step() -> void:
	if _step_root != null and is_instance_valid(_step_root):
		_step_root.queue_free()
	_step_root = null
	# Drop stale button colliders; the shelf buttons are rebuilt separately.
	var gone: Array = []
	for sb in _buttons.keys():
		if not is_instance_valid(sb):
			gone.append(sb)
	for sb in gone:
		_buttons.erase(sb)


func _show_step(step: int) -> void:
	_clear_step()
	_twin = null
	_step = step
	_step_root = Node3D.new()
	_step_root.name = "StepRoot"
	add_child(_step_root)
	match step:
		Step.CAPTURE:
			_build_capture_step()
		Step.PICK:
			_build_pick_step()
		Step.CARE:
			_build_care_step()


func _go_back() -> void:
	if _step == Step.CARE:
		_show_step(Step.PICK)
	elif _step == Step.PICK:
		_show_step(Step.CAPTURE)


func _build_capture_step() -> void:
	var cam_ok := ARCamera.is_available()
	var title := GraphicsPolish.make_label("PLANT DOCTOR", 72, Color(0.6, 1.0, 0.7))
	title.position = Vector3(0, 2.3, -1.6)
	_step_root.add_child(title)
	var sub := GraphicsPolish.make_label(
		"Point the camera at your houseplant, then CAPTURE.\nBrio won't guess - YOU pick the species.",
		44, Color(0.85, 0.92, 1.0))
	sub.position = Vector3(0, 1.95, -1.6)
	_step_root.add_child(sub)
	# Viewfinder frame.
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.5, 1.0, 0.04)
	frame.mesh = fm
	var fmat := GraphicsPolish.pbr_preset(Color(0.1, 0.14, 0.12), "matte")
	frame.material_override = fmat
	frame.position = Vector3(0, 1.25, -1.6)
	_step_root.add_child(frame)
	var ring := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.56, 1.06, 0.02)
	ring.mesh = rm
	ring.material_override = GraphicsPolish.glow(Color(0.4, 1.0, 0.55), 0.8)
	ring.position = Vector3(0, 1.25, -1.63)
	_step_root.add_child(ring)
	var vf_label := GraphicsPolish.make_label(
		"Camera ready" if cam_ok else "No camera detected",
		40, Color(0.7, 1.0, 0.8))
	vf_label.position = Vector3(0, 1.25, -1.55)
	vf_label.pixel_size = 0.008
	_step_root.add_child(vf_label)
	if not cam_ok:
		ARCamera.request_permission()
	_make_button("capture", "CAPTURE", Vector3(-0.75, 0.45, -1.2), Color(0.3, 0.8, 0.45))
	_make_button("manual", "MANUAL MODE (no camera)", Vector3(0.95, 0.45, -1.2), Color(0.4, 0.55, 0.9))


func _build_pick_step() -> void:
	var title := GraphicsPolish.make_label("Which plant is this?", 64, Color(0.6, 1.0, 0.7))
	title.position = Vector3(0, 2.35, -1.8)
	_step_root.add_child(title)
	var sub := GraphicsPolish.make_label(
		"Pick the species yourself - Plant Doctor never pretends to identify it.",
		40, Color(0.85, 0.92, 1.0))
	sub.position = Vector3(0, 2.05, -1.8)
	_step_root.add_child(sub)
	# 2 rows x 3 columns of species cards.
	var idx := 0
	for row in 2:
		for col in 3:
			var x := (col - 1) * 0.85
			var y := 1.45 - row * 1.05
			_make_species_card(idx, Vector3(x, y, -1.8))
			idx += 1


func _build_care_step() -> void:
	if _picked < 0 or _picked >= SPECIES.size():
		_show_step(Step.PICK)
		return
	var sp: Dictionary = SPECIES[_picked]
	var title := GraphicsPolish.make_label(sp["name"], 72, Color(0.6, 1.0, 0.7))
	title.position = Vector3(-0.55, 2.3, -1.6)
	_step_root.add_child(title)
	var latin := GraphicsPolish.make_label(sp["latin"], 40, Color(0.75, 0.85, 0.9))
	latin.position = Vector3(-0.55, 2.02, -1.6)
	_step_root.add_child(latin)
	# Care plan card panel (left).
	var panel := _make_panel(Vector3(1.7, 1.9, 0.05), Color(0.09, 0.13, 0.11))
	panel.position = Vector3(-0.55, 1.05, -1.6)
	_step_root.add_child(panel)
	var body := GraphicsPolish.make_label(
		"LIGHT: %s\nWATER: %s\nHUMIDITY: %s\n\nTIP: %s" % [sp["light"], sp["water"], sp["humidity"], sp["tip"]],
		38, Color(0.92, 1.0, 0.94))
	body.position = Vector3(-0.55, 1.05, -1.56)
	body.pixel_size = 0.006
	_step_root.add_child(body)
	# Water reminder status.
	_status_label = GraphicsPolish.make_label("", 44, Color(1.0, 0.9, 0.5))
	_status_label.position = Vector3(-0.55, 0.12, -1.56)
	_status_label.pixel_size = 0.007
	_step_root.add_child(_status_label)
	_update_status_label()
	# Captured photo on a floating panel (right of care card) if we have one.
	var photo_x := 0.55
	if _photo != null:
		var holder := Node3D.new()
		holder.position = Vector3(photo_x, 1.55, -1.6)
		_step_root.add_child(holder)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.8, 0.6)
		var tex := ImageTexture.create_from_image(_photo)
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = tex
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.material = pm
		quad.mesh = qm
		holder.add_child(quad)
		var cap := GraphicsPolish.make_label("Your capture", 36, Color(0.85, 0.92, 1.0))
		cap.position = Vector3(0, -0.4, 0.02)
		cap.pixel_size = 0.006
		holder.add_child(cap)
	# Holo Garden twin: pot + animated plant (right side).
	var twin_anchor := Node3D.new()
	twin_anchor.position = Vector3(1.45, 0.0, -1.4)
	if _room_table_top_y > 0.0:
		# ROOMKIT: the twin pot sits on the real tabletop.
		twin_anchor.position.y = _room_table_top_y
	_step_root.add_child(twin_anchor)
	var pot := _build_pot()
	pot.position = Vector3(0, 0.14, 0)
	twin_anchor.add_child(pot)
	_twin = _build_plant_model(_picked)
	_twin.position = Vector3(0, 0.28, 0)
	_twin.scale = Vector3.ONE * 0.01
	_twin_grow_t = 0.0
	twin_anchor.add_child(_twin)
	GraphicsPolish.spawn_sparks(twin_anchor, Vector3(0, 0.7, 0), Color(0.5, 1.0, 0.6), 40)
	var twin_label := GraphicsPolish.make_label("Your Holo Garden twin", 40, Color(0.7, 1.0, 0.8))
	twin_label.position = Vector3(0, 1.35, 0.05)
	twin_label.pixel_size = 0.007
	twin_anchor.add_child(twin_label)
	# Buttons.
	_make_button("watered", "Watered it!", Vector3(-1.15, 0.45, -1.2), Color(0.35, 0.65, 1.0))
	_make_button("newplant", "New plant", Vector3(0.35, 0.45, -1.2), Color(0.3, 0.8, 0.45))


func _update_status_label() -> void:
	if _status_label == null or _picked < 0:
		return
	var today := _today()
	for p in _plants:
		var d: Dictionary = p
		if int(d["species"]) == _picked:
			var due: int = int(d["last_watered"]) + int(d["interval"])
			var left := due - today
			if left > 1:
				_status_label.text = "Water me in %d days" % left
				_status_label.modulate = Color(1.0, 0.9, 0.5)
			elif left == 1:
				_status_label.text = "Water me TOMORROW"
				_status_label.modulate = Color(1.0, 0.75, 0.4)
			elif left == 0:
				_status_label.text = "Water me TODAY"
				_status_label.modulate = Color(1.0, 0.55, 0.3)
			else:
				_status_label.text = "OVERDUE by %d days - thirsty!" % (-left)
				_status_label.modulate = Color(1.0, 0.4, 0.35)
			return


# ---------------------------------------------------------------- shelf

func _build_shelf() -> void:
	if _shelf_root != null and is_instance_valid(_shelf_root):
		_shelf_root.queue_free()
	_shelf_root = Node3D.new()
	_shelf_root.name = "ShelfRoot"
	add_child(_shelf_root)
	var title := GraphicsPolish.make_label("My diagnosed plants", 44, Color(0.8, 0.9, 1.0))
	title.position = Vector3(0, 0.62, 0.9)
	title.pixel_size = 0.007
	_shelf_root.add_child(title)
	var x := 0.0
	var n := mini(_plants.size(), 8)
	if n > 0:
		x = -float(n - 1) * 0.28
	for i in n:
		var d: Dictionary = _plants[i]
		_make_shelf_card(int(d["species"]), Vector3(x, 0.3, 0.9))
		x += 0.56
	if _plants.is_empty():
		var empty := GraphicsPolish.make_label("Nothing diagnosed yet - capture your first plant!", 36, Color(0.6, 0.7, 0.85))
		empty.position = Vector3(0, 0.3, 0.9)
		empty.pixel_size = 0.007
		_shelf_root.add_child(empty)
	# v0.7.0 KayKit: a real wooden shelf plank under the plant-card row, sized
	# to the collection. Falls back to the floating cards when unavailable.
	var plank := ModelLib.spawn("res://assets/models/plant_doctor/shelf_B_large.gltf",
		_shelf_root, Vector3(0, -0.17, 0.9))
	if plank != null:
		var w := clampf(float(maxi(n, 1)) * 0.56 / 2.0, 0.8, 2.6)
		plank.scale = Vector3(w, 1.0, 1.0)


func _make_shelf_card(species_idx: int, pos: Vector3) -> void:
	var sp: Dictionary = SPECIES[species_idx]
	var root := Node3D.new()
	root.position = pos
	_shelf_root.add_child(root)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.34, 0.06)
	base.mesh = bm
	base.material_override = GraphicsPolish.pbr_preset(Color(0.14, 0.2, 0.16), "plastic")
	root.add_child(base)
	var model := _build_plant_model(species_idx)
	model.scale = Vector3.ONE * 0.32
	model.position = Vector3(0, 0.05, 0.05)
	root.add_child(model)
	var today := _today()
	var status_col := Color(0.4, 1.0, 0.5)
	for p in _plants:
		var d: Dictionary = p
		if int(d["species"]) == species_idx:
			var left: int = int(d["last_watered"]) + int(d["interval"]) - today
			if left <= 0:
				status_col = Color(1.0, 0.4, 0.35)
			elif left <= 2:
				status_col = Color(1.0, 0.8, 0.4)
			break
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	dot.mesh = sm
	dot.material_override = GraphicsPolish.glow(status_col, 1.8)
	dot.position = Vector3(0.2, 0.12, 0.05)
	root.add_child(dot)
	var label := GraphicsPolish.make_label(sp["name"], 32, Color.WHITE)
	label.position = Vector3(0, -0.24, 0.05)
	label.pixel_size = 0.006
	root.add_child(label)


# ---------------------------------------------------------------- cards & plants

func _make_species_card(species_idx: int, pos: Vector3) -> void:
	var sp: Dictionary = SPECIES[species_idx]
	var root := Node3D.new()
	root.position = pos
	_step_root.add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(CARD_W, CARD_H, 0.06)
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(Color(0.12, 0.18, 0.14), "plastic")
	root.add_child(mi)
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(CARD_W + 0.04, CARD_H + 0.04, 0.03)
	edge.mesh = em
	edge.material_override = GraphicsPolish.glow(Color(0.35, 0.85, 0.5), 0.6)
	edge.position = Vector3(0, 0, -0.02)
	root.add_child(edge)
	# Mini 3D plant model on the card.
	var model := _build_plant_model(species_idx)
	model.scale = Vector3.ONE * 0.5
	model.position = Vector3(0, -0.05, 0.06)
	root.add_child(model)
	var label := GraphicsPolish.make_label(sp["name"], 40, Color.WHITE)
	label.position = Vector3(0, -0.36, 0.06)
	label.pixel_size = 0.007
	root.add_child(label)
	# Invisible (dark glass) collider slab in front of the card.
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CARD_W, CARD_H, 0.2)
	cs.shape = bs
	cs.position = Vector3(0, 0, 0.06)
	sb.add_child(cs)
	_buttons[sb] = "pick:%d" % species_idx


func _build_pot() -> Node3D:
	var root := Node3D.new()
	var pot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.15
	cm.height = 0.28
	pot.mesh = cm
	pot.material_override = GraphicsPolish.pbr_preset(Color(0.72, 0.38, 0.22), "matte")
	root.add_child(pot)
	var soil := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.18
	dm.bottom_radius = 0.18
	dm.height = 0.03
	soil.mesh = dm
	soil.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.16, 0.1), "matte")
	soil.position = Vector3(0, 0.13, 0)
	root.add_child(soil)
	return root


func _build_plant_model(species_idx: int) -> Node3D:
	var root := Node3D.new()
	var leaf_green := Color(0.22, 0.62, 0.3)
	var dark_green := Color(0.15, 0.48, 0.24)
	match species_idx:
		0: # Monstera: stem + broad lobed-looking leaves.
			_add_stem(root, 0.4, 0.025, Color(0.3, 0.5, 0.28))
			for i in 5:
				var ang := TAU * float(i) / 5.0
				var leaf := _make_leaf(0.17, 0.03, 0.24, dark_green)
				leaf.position = Vector3(cos(ang) * 0.16, 0.22 + 0.06 * float(i % 2), sin(ang) * 0.16)
				leaf.rotation = Vector3(-0.6, -ang, 0.0)
				root.add_child(leaf)
		1: # Fiddle-Leaf Fig: trunk + big round upright leaves.
			_add_stem(root, 0.55, 0.03, Color(0.45, 0.3, 0.18))
			for i in 6:
				var leaf := _make_leaf(0.15, 0.05, 0.15, leaf_green)
				var ang := TAU * float(i) / 6.0
				leaf.position = Vector3(cos(ang) * 0.13, 0.3 + 0.04 * float(i), sin(ang) * 0.13)
				leaf.rotation = Vector3(-0.35, ang, 0.0)
				root.add_child(leaf)
		2: # Snake Plant: upright blades.
			for i in 7:
				var h := 0.35 + 0.05 * float(i % 3)
				var blade := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.055, h, 0.025)
				blade.mesh = bm
				blade.material_override = GraphicsPolish.pbr_preset(
					leaf_green.lerp(Color(0.5, 0.75, 0.4), float(i % 2) * 0.4), "matte")
				var ang := TAU * float(i) / 7.0
				blade.position = Vector3(cos(ang) * 0.05, h * 0.5, sin(ang) * 0.05)
				blade.rotation = Vector3(0.08 * sin(ang), 0.0, 0.08 * cos(ang))
				root.add_child(blade)
		3: # Pothos: trailing vines with small leaves.
			for v in 3:
				var ang := TAU * float(v) / 3.0
				for l in 4:
					var t := float(l) / 3.0
					var leaf := _make_leaf(0.06, 0.02, 0.085, leaf_green.lerp(Color(0.55, 0.8, 0.35), t * 0.5))
					leaf.position = Vector3(cos(ang) * (0.06 + t * 0.22), 0.28 - t * 0.42, sin(ang) * (0.06 + t * 0.22))
					leaf.rotation = Vector3(-0.5, ang, 0.0)
					root.add_child(leaf)
		4: # Peace Lily: broad oval leaves + one white spathe flower.
			for i in 5:
				var ang := TAU * float(i) / 5.0
				var leaf := _make_leaf(0.1, 0.03, 0.19, dark_green)
				leaf.position = Vector3(cos(ang) * 0.11, 0.24, sin(ang) * 0.11)
				leaf.rotation = Vector3(-0.7, -ang, 0.0)
				root.add_child(leaf)
			var stem := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.012
			sm.bottom_radius = 0.012
			sm.height = 0.35
			stem.mesh = sm
			stem.material_override = GraphicsPolish.pbr_preset(leaf_green, "matte")
			stem.position = Vector3(0, 0.18, 0)
			root.add_child(stem)
			var spathe := _make_leaf(0.07, 0.02, 0.12, Color(0.95, 0.95, 0.9))
			spathe.position = Vector3(0, 0.38, 0.02)
			spathe.rotation = Vector3(-0.5, 0.0, 0.0)
			root.add_child(spathe)
		5: # Cactus: ribbed column + arms + flower.
			var body := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.1
			cm.height = 0.42
			cm.radial_segments = 12
			body.mesh = cm
			body.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.6, 0.3), "matte")
			body.position = Vector3(0, 0.21, 0)
			root.add_child(body)
			for side in [-1.0, 1.0]:
				var arm := MeshInstance3D.new()
				var am := CylinderMesh.new()
				am.top_radius = 0.05
				am.bottom_radius = 0.05
				am.height = 0.2
				arm.mesh = am
				arm.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.6, 0.3), "matte")
				arm.position = Vector3(side * 0.13, 0.3, 0)
				arm.rotation = Vector3(0, 0, side * -0.5)
				root.add_child(arm)
			var flower := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.045
			fm.height = 0.09
			flower.mesh = fm
			flower.material_override = GraphicsPolish.glow(Color(1.0, 0.45, 0.55), 1.2)
			flower.position = Vector3(0, 0.46, 0)
			root.add_child(flower)
		_:
			_add_stem(root, 0.35, 0.025, leaf_green)
	return root


func _add_stem(parent: Node3D, height: float, radius: float, color: Color) -> void:
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.2
	cm.height = height
	stem.mesh = cm
	stem.material_override = GraphicsPolish.pbr_preset(color, "matte")
	stem.position = Vector3(0, height * 0.5, 0)
	parent.add_child(stem)


func _make_leaf(sx: float, sy: float, sz: float, color: Color) -> MeshInstance3D:
	var leaf := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	leaf.mesh = sm
	leaf.scale = Vector3(sx, sy, sz)
	leaf.material_override = GraphicsPolish.pbr_preset(color, "matte")
	return leaf


func _make_panel(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(color, "plastic")
	return mi


func _make_button(action: String, text: String, pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	_step_root.add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.34, 0.08)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr_preset(color, "plastic")
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 0.34, 0.3)
	cs.shape = bs
	sb.add_child(cs)
	var label := GraphicsPolish.make_label(text, 44, Color.WHITE)
	label.position = Vector3(0, 0, 0.06)
	label.pixel_size = 0.008
	root.add_child(label)
	_buttons[sb] = action


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider is StaticBody3D and _buttons.has(collider):
		_do_button(_buttons[collider] as String)


func _raycast_tap(origin: Vector3, dir: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider is StaticBody3D and _buttons.has(collider):
		_do_button(_buttons[collider] as String)


func _do_button(action: String) -> void:
	if action.begins_with("pick:"):
		_pick_species(int(action.get_slice(":", 1)))
		return
	match action:
		"capture":
			_capture_photo()
		"manual":
			Haptics.tick()
			_photo = null
			_show_step(Step.PICK)
		"watered":
			_mark_watered()
		"newplant":
			Haptics.tick()
			_photo = null
			_picked = -1
			_show_step(Step.CAPTURE)


func _capture_photo() -> void:
	Haptics.pulse(0.8, 0.15)
	if ARCamera.is_available():
		var img := ARCamera.capture()
		if img != null:
			_photo = img
			_show_step(Step.PICK)
			return
	# No camera / capture failed: manual mode with a note, still fully usable.
	_photo = null
	_show_step(Step.PICK)


func _pick_species(idx: int) -> void:
	Haptics.pulse(0.7, 0.12)
	_picked = idx
	GraphicsPolish.spawn_confetti(self, Vector3(0, 1.5, -1.6), 40)
	_register_plant(idx)
	_show_step(Step.CARE)


# ---------------------------------------------------------------- persistence

func _today() -> int:
	return int(Time.get_unix_time_from_system() / DAY)


func _load_care() -> void:
	_plants.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CARE_FILE) != OK:
		return
	var arr: Array = cfg.get_value("plants", "list", [])
	for item in arr:
		if item is Dictionary:
			_plants.append(item)


func _save_care() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("plants", "list", _plants)
	cfg.save(CARE_FILE)


func _register_plant(idx: int) -> void:
	# Already diagnosed? Refresh last_watered so the reminder restarts.
	for p in _plants:
		var d: Dictionary = p
		if int(d["species"]) == idx:
			d["last_watered"] = _today()
			d["diagnosed"] = _today()
			_save_care()
			_build_shelf()
			return
	var sp: Dictionary = SPECIES[idx]
	var today := _today()
	_plants.append({
		"species": idx,
		"name": sp["name"],
		"diagnosed": today,
		"last_watered": today,
		"interval": int(sp["days"]),
	})
	_save_care()
	_build_shelf()


func _mark_watered() -> void:
	Haptics.tick()
	for p in _plants:
		var d: Dictionary = p
		if int(d["species"]) == _picked:
			d["last_watered"] = _today()
			break
	_save_care()
	_update_status_label()
	_build_shelf()
	GraphicsPolish.spawn_sparks(self, Vector3(-0.55, 0.4, -1.4), Color(0.4, 0.8, 1.0), 24)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
