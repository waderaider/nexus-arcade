## HoloGarden: a virtual garden.
## Six brown soil patches sit on the floor. In plant mode, click an empty
## patch to plant a seed (costs 1 seed; you start with 6). Press W or click
## the mode button to switch to water mode, then click a plant to water it.
## Watered plants grow over time: seed -> sprout (green cone) -> bush
## (bigger cone) -> flower (colored sphere on a stem). Growth pauses when
## the water runs out. Click a mature flower to harvest it for 3 coins; buy
## more seeds at the shop button (B or click) for 2 coins each.
## Seeds/coins/HUD update live, and state is saved to user://holo_garden.cfg.
## Mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D

const SAVE_PATH := "user://holo_garden.cfg"
const PATCH_COUNT := 6
const PATCH_RADIUS := 0.45
const SEED_COST := 1
const SHOP_SEED_PRICE := 2
const HARVEST_COINS := 3
const START_SEEDS := 6
const START_COINS := 3
const WATER_DURATION := 14.0
const STAGE_SPROUT := 4.0
const STAGE_BUSH := 9.0
const STAGE_FLOWER := 15.0
const STATE_EMPTY := 0
const STATE_SEED := 1
const STATE_SPROUT := 2
const STATE_BUSH := 3
const STATE_FLOWER := 4

var camera: Camera3D = null
var seeds := START_SEEDS
var coins := START_COINS
var water_mode := false
var patches: Array = []
var patch_positions: Array = []
var plant_roots: Array = []
var water_rings: Array = []
var hud_label: Label3D = null
var mode_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var _anchor_t := 0.0
var mode_btn_pos := Vector3(-2.6, 0.6, -2.2)
var shop_btn_pos := Vector3(2.6, 0.6, -2.2)
var msg_t := 0.0
var prev_w := false
var prev_b := false
var flower_colors := [
	Color(1.0, 0.3, 0.5),
	Color(1.0, 0.6, 0.1),
	Color(0.9, 0.3, 1.0),
	Color(1.0, 1.0, 0.3),
	Color(0.4, 0.7, 1.0),
]


func _ready() -> void:
	# Restore the persisted garden placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "holo-garden_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_patches()
	_build_buttons()
	_build_hud()
	_load_state()
	_refresh_all_patches()
	_update_hud()
	# Drifting pollen motes over the beds.
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 2.6, 48)


func _process(delta: float) -> void:
	msg_t = maxf(0.0, msg_t - delta)
	# Persist the garden placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("holo-garden_main", global_transform)
	# XR hand: a pinch clicks at the pinch point (mouse clicks still work).
	if ARUpgradeKit.is_xr_active() and camera != null \
			and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if not camera.is_position_behind(pp):
			_handle_click(camera.unproject_position(pp))

	for i in range(PATCH_COUNT):
		var patch: Dictionary = patches[i]
		var state: int = patch["state"]
		if state == STATE_EMPTY or state == STATE_FLOWER:
			continue
		var water_left: float = patch["water"]
		if water_left <= 0.0:
			_set_water_ring(i, false)
			continue
		patch["water"] = water_left - delta
		patch["growth"] = float(patch["growth"]) + delta
		_set_water_ring(i, true)
		_maybe_advance_stage(i)

	var w_down := Input.is_key_pressed(KEY_W)
	if w_down and not prev_w:
		_toggle_mode()
	prev_w = w_down
	var b_down := Input.is_key_pressed(KEY_B)
	if b_down and not prev_b:
		_buy_seed()
	prev_b = b_down


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)


## Hand-tracking hook: true while the user is pinching in XR.
func _pinch_active() -> bool:
	return false


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 5.6, 5.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.4), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	# Three-point rig, but never stack a second key light.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.09, 0.13, 0.10), "matte")
	add_child(floor_inst)


func _solid(color: Color, energy: float = 0.0) -> StandardMaterial3D:
	# Glow for emissive accents (water rings, buttons, blooms),
	# matte PBR for everything solid (soil, seeds, stems, cones).
	if energy > 0.0:
		return GraphicsPolish.glow(color, energy)
	return GraphicsPolish.pbr_preset(color, "matte")


func _build_patches() -> void:
	var xs := [-1.7, 0.0, 1.7]
	var zs := [-1.0, 1.0]
	var idx := 0
	for zi in range(zs.size()):
		for xi in range(xs.size()):
			var pos := Vector3(xs[xi], 0.08, zs[zi])
			patch_positions.append(pos)
			var soil := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = PATCH_RADIUS
			cyl.bottom_radius = PATCH_RADIUS
			cyl.height = 0.16
			soil.mesh = cyl
			soil.material_override = _solid(Color(0.35, 0.22, 0.12))
			soil.position = pos
			add_child(soil)
			var root := Node3D.new()
			root.position = Vector3(pos.x, 0.16, pos.z)
			add_child(root)
			plant_roots.append(root)
			# Water ring: blue glow torus that appears while the patch is wet.
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = PATCH_RADIUS - 0.02
			torus.outer_radius = PATCH_RADIUS + 0.06
			ring.mesh = torus
			ring.material_override = _solid(Color(0.2, 0.6, 1.0), 1.8)
			ring.position = Vector3(pos.x, 0.17, pos.z)
			ring.rotation_degrees.x = 90.0
			ring.visible = false
			add_child(ring)
			water_rings.append(ring)
			patches.append({"state": STATE_EMPTY, "growth": 0.0, "water": 0.0, "color": idx % flower_colors.size()})
			idx += 1


func _build_buttons() -> void:
	_build_button(mode_btn_pos, Color(0.2, 0.6, 1.0))
	_build_button(shop_btn_pos, Color(1.0, 0.75, 0.2))


func _build_button(pos: Vector3, color: Color) -> void:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.35, 0.5)
	inst.mesh = box
	inst.material_override = _solid(color, 0.8)
	inst.position = pos
	add_child(inst)
	var label := Label3D.new()
	label.position = pos + Vector3(0.0, 0.45, 0.0)
	label.pixel_size = 0.005
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color.WHITE
	add_child(label)
	if pos == mode_btn_pos:
		mode_label = label
	else:
		label.text = "SHOP: 1 seed = 2c (B)"
	_update_mode_label()


func _update_mode_label() -> void:
	if mode_label != null:
		mode_label.text = "MODE: WATER (W)" if water_mode else "MODE: PLANT (W)"


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color(0.9, 1.0, 0.9))
	hud_label.position = Vector3(-2.9, 2.6, 0.6)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	msg_label = Label3D.new()
	msg_label.position = Vector3(0.0, 2.1, -1.4)
	msg_label.pixel_size = 0.007
	msg_label.font_size = 52
	msg_label.modulate = Color(1.0, 0.85, 0.4)
	msg_label.outline_size = 8
	add_child(msg_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-2.9, 2.28, 0.6)
	help_label.pixel_size = 0.004
	help_label.font_size = 30
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.text = "Click patch: plant/water | Click flower: harvest | W: mode | B: buy seed"
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		var mode_name := "WATER" if water_mode else "PLANT"
		hud_label.text = "Seeds %d   Coins %d   Mode %s" % [seeds, coins, mode_name]
	if msg_label != null:
		msg_label.visible = msg_t > 0.0
	if mode_label != null:
		_update_mode_label()


func _flash(text: String) -> void:
	if msg_label != null:
		msg_label.text = text
	msg_t = 1.6
	_update_hud()


func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3(999.0, 0.0, 999.0)
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3(999.0, 0.0, 999.0)
	var t := (0.16 - origin.y) / dir.y
	if t < 0.0:
		return Vector3(999.0, 0.0, 999.0)
	return origin + dir * t


func _handle_click(screen_pos: Vector2) -> void:
	var p := _screen_to_floor(screen_pos)
	if p.x > 900.0:
		return
	# 3D buttons first.
	if Vector2(p.x, p.z).distance_to(Vector2(mode_btn_pos.x, mode_btn_pos.z)) < 0.7:
		_toggle_mode()
		return
	if Vector2(p.x, p.z).distance_to(Vector2(shop_btn_pos.x, shop_btn_pos.z)) < 0.7:
		_buy_seed()
		return
	# Patches.
	for i in range(PATCH_COUNT):
		var pp: Vector3 = patch_positions[i]
		if Vector2(p.x, p.z).distance_to(Vector2(pp.x, pp.z)) < PATCH_RADIUS + 0.15:
			_click_patch(i)
			return


func _click_patch(i: int) -> void:
	var patch: Dictionary = patches[i]
	var state: int = patch["state"]
	if state == STATE_FLOWER:
		_harvest(i)
		return
	if water_mode:
		if state == STATE_EMPTY:
			_flash("Nothing planted here")
			return
		patch["water"] = WATER_DURATION
		_set_water_ring(i, true)
		_flash("Watered!")
		_save_state()
	else:
		if state != STATE_EMPTY:
			_flash("Already growing")
			return
		if seeds < SEED_COST:
			_flash("No seeds! Buy at shop")
			return
		seeds -= SEED_COST
		patch["state"] = STATE_SEED
		patch["growth"] = 0.0
		patch["water"] = 0.0
		_build_plant_mesh(i)
		_flash("Planted!")
		_save_state()
	_update_hud()


func _toggle_mode() -> void:
	water_mode = not water_mode
	_flash("Water mode" if water_mode else "Plant mode")
	_update_hud()


func _buy_seed() -> void:
	if coins < SHOP_SEED_PRICE:
		_flash("Need %d coins for a seed" % SHOP_SEED_PRICE)
		return
	coins -= SHOP_SEED_PRICE
	seeds += 1
	_flash("Bought 1 seed")
	_save_state()
	_update_hud()


func _harvest(i: int) -> void:
	var patch: Dictionary = patches[i]
	patch["state"] = STATE_EMPTY
	patch["growth"] = 0.0
	patch["water"] = 0.0
	patch["color"] = (int(patch["color"]) + 1) % flower_colors.size()
	coins += HARVEST_COINS
	GraphicsPolish.spawn_sparks(self, (plant_roots[i] as Node3D).position + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.85, 0.3), 20)
	_clear_plant_mesh(i)
	_set_water_ring(i, false)
	_flash("+%d coins!" % HARVEST_COINS)
	_save_state()
	_update_hud()


func _maybe_advance_stage(i: int) -> void:
	var patch: Dictionary = patches[i]
	var growth: float = patch["growth"]
	var old_state: int = patch["state"]
	var new_state := old_state
	if growth >= STAGE_FLOWER:
		new_state = STATE_FLOWER
	elif growth >= STAGE_BUSH:
		new_state = STATE_BUSH
	elif growth >= STAGE_SPROUT:
		new_state = STATE_SPROUT
	if new_state != old_state:
		patch["state"] = new_state
		_build_plant_mesh(i)
		if new_state == STATE_FLOWER:
			_flash("A flower bloomed!")
			GraphicsPolish.spawn_confetti(self, (plant_roots[i] as Node3D).position + Vector3(0.0, 0.7, 0.0), 40)
		_save_state()


func _clear_plant_mesh(i: int) -> void:
	var root: Node3D = plant_roots[i]
	for child in root.get_children():
		child.queue_free()


func _set_water_ring(i: int, on: bool) -> void:
	var ring: MeshInstance3D = water_rings[i]
	ring.visible = on


func _build_plant_mesh(i: int) -> void:
	_clear_plant_mesh(i)
	var root: Node3D = plant_roots[i]
	var state: int = patches[i]["state"]
	if state == STATE_EMPTY:
		return
	var green := Color(0.25, 0.8, 0.3)
	if state == STATE_SEED:
		var seed := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		seed.mesh = sm
		seed.material_override = _solid(Color(0.55, 0.4, 0.25))
		seed.position = Vector3(0.0, 0.06, 0.0)
		root.add_child(seed)
	elif state == STATE_SPROUT:
		_add_cone(root, 0.10, 0.30, Vector3(0.0, 0.15, 0.0), green)
	elif state == STATE_BUSH:
		_add_cone(root, 0.22, 0.55, Vector3(0.0, 0.28, 0.0), green)
	elif state == STATE_FLOWER:
		# Stem.
		var stem := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.03
		cm.height = 0.55
		stem.mesh = cm
		stem.material_override = _solid(Color(0.2, 0.6, 0.25))
		stem.position = Vector3(0.0, 0.28, 0.0)
		root.add_child(stem)
		# Colored bloom.
		var bloom := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.16
		bm.height = 0.32
		bloom.mesh = bm
		var fcolor: Color = flower_colors[int(patches[i]["color"])]
		bloom.material_override = _solid(fcolor, 0.9)
		bloom.position = Vector3(0.0, 0.62, 0.0)
		root.add_child(bloom)


func _add_cone(root: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var inst := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.01
	cm.bottom_radius = radius
	cm.height = height
	inst.mesh = cm
	inst.material_override = _solid(color)
	inst.position = pos
	root.add_child(inst)


func _refresh_all_patches() -> void:
	for i in range(PATCH_COUNT):
		_build_plant_mesh(i)
		_set_water_ring(i, float(patches[i]["water"]) > 0.0 and int(patches[i]["state"]) != STATE_EMPTY)


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("garden", "seeds", seeds)
	cfg.set_value("garden", "coins", coins)
	for i in range(PATCH_COUNT):
		var patch: Dictionary = patches[i]
		var prefix := "patch_%d" % i
		cfg.set_value(prefix, "state", int(patch["state"]))
		cfg.set_value(prefix, "growth", float(patch["growth"]))
		cfg.set_value(prefix, "water", float(patch["water"]))
		cfg.set_value(prefix, "color", int(patch["color"]))
	cfg.save(SAVE_PATH)
	ARUpgradeKit.save_anchor("holo-garden_main", global_transform)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	seeds = int(cfg.get_value("garden", "seeds", START_SEEDS))
	coins = int(cfg.get_value("garden", "coins", START_COINS))
	for i in range(PATCH_COUNT):
		var prefix := "patch_%d" % i
		var patch: Dictionary = patches[i]
		patch["state"] = clampi(int(cfg.get_value(prefix, "state", STATE_EMPTY)), STATE_EMPTY, STATE_FLOWER)
		patch["growth"] = float(cfg.get_value(prefix, "growth", 0.0))
		patch["water"] = float(cfg.get_value(prefix, "water", 0.0))
		patch["color"] = int(cfg.get_value(prefix, "color", i % flower_colors.size())) % flower_colors.size()
