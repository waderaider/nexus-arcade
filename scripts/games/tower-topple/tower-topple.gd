## tower-topple.gd -- NEXUS ARCADE: AR Jenga on your table.
## A 3-per-layer alternating block tower spawns on a table-height surface.
## Pinch-grab (or click-drag) a block out of the tower, then release it over
## the top to stack it. Every pull and stack makes the tower lean more;
## if the lean passes the limit the tower topples -- game over.
## Score = blocks successfully stacked. Press R (or click after game over)
## to rebuild the tower.
extends Node3D

const LAYER_COUNT := 9
const BLOCK_SIZE := Vector3(0.30, 0.066, 0.10)
const SNAP_RADIUS := 0.22
const COLLAPSE_DEG := 7.0
const TABLE_Y := 0.75

var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}

var state := "playing" # "playing" | "gameover"
var score := 0
var tower_root: Node3D = null
var lean_deg := 0.0
var lean_dir := Vector3(1, 0, 0)
var wobble_t := 0.0
var wobble_amp := 0.0

var blocks: Array = [] # each: {node, layer, slot, mode, vel, spin}
var grabbed: Dictionary = {}
var has_grab := false
var grab_plane_dist := 0.0
var drag_vel := Vector3.ZERO
var drag_prev := Vector3.ZERO

var top_layers := 0 # number of placed cap layers above the base tower
var cap_count := 0 # blocks placed on top total

var score_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var wood_mat: StandardMaterial3D = null
var cap_mat: StandardMaterial3D = null


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "tower-topple_main")
	_build_camera()
	_build_environment()
	GraphicsPolish.make_light_rig(self)
	_build_tower()
	_build_ui()
	_reset()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.2, -1), 2.0, 30)


func _build_camera() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			return
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.9, 1.6)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.8, -1.0), Vector3.UP)


func _build_environment() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.50, 0.65)
	env.ambient_light_energy = 0.8
	amb.environment = env
	add_child(amb)

	# Table surface slab (visual anchor for the tower).
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.6, 0.06, 1.6)
	table.mesh = tm
	table.material_override = GraphicsPolish.pbr_preset(Color(0.32, 0.22, 0.14), "matte")
	table.position = Vector3(0, TABLE_Y - 0.03, -1.0)
	add_child(table)

	# Floor far below for depth.
	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.0, 0.1, 8.0)
	floor_mi.mesh = fb
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.12, 0.20), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _build_tower() -> void:
	tower_root = Node3D.new()
	tower_root.name = "TowerRoot"
	add_child(tower_root)
	wood_mat = GraphicsPolish.pbr_preset(Color(0.85, 0.62, 0.35), "plastic")
	cap_mat = GraphicsPolish.glow(Color(1.0, 0.75, 0.25), 0.9)


func _spawn_block(layer: int, slot: int, pos: Vector3, rot_y: float, is_cap: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = BLOCK_SIZE
	mi.mesh = bm
	mi.material_override = cap_mat if is_cap else wood_mat
	mi.position = pos
	mi.rotation.y = rot_y
	tower_root.add_child(mi)
	blocks.append({
		"node": mi, "layer": layer, "slot": slot,
		"mode": "tower", "vel": Vector3.ZERO, "spin": Vector3.ZERO,
		"is_cap": is_cap,
	})


func _block_pos(layer: int, slot: int, rot_y: float) -> Vector3:
	var y := BLOCK_SIZE.y * 0.5 + float(layer) * BLOCK_SIZE.y
	var off := (float(slot) - 1.0) * BLOCK_SIZE.z
	# In the block's local frame slots spread along local Z.
	var p := Vector3(0, y, off).rotated(Vector3.UP, rot_y)
	return p


func _build_blocks() -> void:
	for b in blocks:
		(b["node"] as Node3D).queue_free()
	blocks.clear()
	top_layers = 0
	cap_count = 0
	for layer in LAYER_COUNT:
		var rot_y := 0.0 if layer % 2 == 0 else PI * 0.5
		for slot in 3:
			_spawn_block(layer, slot, _block_pos(layer, slot, rot_y), rot_y, false)


func _reset() -> void:
	state = "playing"
	score = 0
	lean_deg = 0.0
	lean_dir = Vector3(1, 0, 0)
	wobble_t = 0.0
	has_grab = false
	grabbed = {}
	_build_blocks()
	ARUpgradeKit.place_on_table(tower_root, 1.0, TABLE_Y)
	ARUpgradeKit.save_anchor("tower-topple_main", global_transform)
	msg_label.text = ""


func _build_ui() -> void:
	score_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.6))
	score_label.position = Vector3(-2.6, 2.4, -1.0)
	add_child(score_label)
	msg_label = GraphicsPolish.make_label("", 96, Color(1.0, 0.4, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -1.2)
	add_child(msg_label)
	help_label = GraphicsPolish.make_label(
		"Drag a block OUT of the tower,\nrelease it ON TOP to stack.\nDon't let the tower fall! R: restart",
		48, Color(0.7, 0.8, 1.0))
	help_label.position = Vector3(2.6, 2.4, -1.0)
	add_child(help_label)


func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	if state == "playing":
		_poll_grab(delta)
		_update_falling(delta)
		_update_lean(delta)
	else:
		_update_collapse(delta)
	_update_ui()
	GraphicsPolish.pulse_glow(cap_mat, 0.7, 0.5, _time, 3.0)


func _poll_keys() -> void:
	var down := Input.is_key_pressed(KEY_R)
	var was: bool = _prev_keys.get(KEY_R, false)
	if down and not was:
		_reset()
	_prev_keys[KEY_R] = down


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == "gameover":
			_reset()


func _update_ui() -> void:
	score_label.text = "TOWER TOPPLE\nStacked: %d\nLean: %.1f deg" % [score, lean_deg]
	if state == "gameover" and msg_label.text == "":
		msg_label.text = "TOWER DOWN!\nScore: %d\nClick or R to rebuild" % score


# --- Grabbing -------------------------------------------------------------

func _pointer_ray_screen(screen_pos: Vector2) -> Array:
	if cam == null:
		return [Vector3.ZERO, Vector3(0, 0, -1)]
	return [cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)]


func _pick_block(o: Vector3, d: Vector3) -> int:
	var best := -1
	var best_t := 1e9
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		if b["mode"] != "tower" and b["mode"] != "rest":
			continue
		var n: Node3D = b["node"]
		var c: Vector3 = n.global_position
		var oc: Vector3 = o - c
		var tca: float = oc.dot(d)
		if tca >= 0.0:
			continue
		var d2: float = oc.dot(oc) - tca * tca
		if d2 < 0.16 and -tca < best_t:
			best_t = -tca
			best = i
	return best


func _top_slot_pos() -> Vector3:
	var layer := LAYER_COUNT + top_layers
	var slot := cap_count % 3
	var rot_y := 0.0 if layer % 2 == 0 else PI * 0.5
	var local := _block_pos(layer, slot, rot_y)
	return tower_root.to_global(local)


func _poll_grab(delta: float) -> void:
	var pressed_edge := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	var held := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var xr := ARUpgradeKit.is_xr_active()

	if not has_grab and pressed_edge:
		var o: Vector3
		var d: Vector3
		if xr:
			var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
			o = r[0]
			d = r[1]
		else:
			var r2: Array = _pointer_ray_screen(get_viewport().get_mouse_position())
			o = r2[0]
			d = r2[1]
		var idx := _pick_block(o, d)
		if idx >= 0:
			var b: Dictionary = blocks[idx]
			# Placed cap blocks are the score: never re-grabbable.
			if b["is_cap"]:
				return
			# Keep the top base layer off-limits until stacking begins.
			if cap_count == 0 and int(b["layer"]) >= LAYER_COUNT - 1:
				return
			b["mode"] = "grabbed"
			blocks[idx] = b
			grabbed = b
			has_grab = true
			var n: Node3D = b["node"]
			if not xr and cam != null:
				var to_block: Vector3 = n.global_position - cam.global_position
				grab_plane_dist = to_block.dot(-cam.global_transform.basis.z)
			drag_prev = n.global_position
			drag_vel = Vector3.ZERO
			if not b["is_cap"]:
				lean_deg += randf_range(0.10, 0.30)
				wobble_t = 0.6
				wobble_amp = 0.010
				GraphicsPolish.spawn_sparks(self, n.global_position, Color(1.0, 0.8, 0.4), 10)

	if has_grab and held:
		var target: Vector3
		if xr:
			target = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.0)
		elif cam != null:
			var mp := get_viewport().get_mouse_position()
			var ro := cam.project_ray_origin(mp)
			var rd := cam.project_ray_normal(mp)
			var fwd := -cam.global_transform.basis.z
			var denom := rd.dot(fwd)
			if absf(denom) > 0.001:
				var t: float = grab_plane_dist / denom
				target = ro + rd * t
			else:
				target = (grabbed["node"] as Node3D).global_position
		else:
			target = (grabbed["node"] as Node3D).global_position
		var n2: Node3D = grabbed["node"]
		drag_vel = (target - n2.global_position) / maxf(delta, 0.001)
		n2.global_position = target
		drag_prev = target

	if has_grab and not held:
		_release_grab()


func _release_grab() -> void:
	has_grab = false
	var n: Node3D = grabbed["node"]
	var slot_pos := _top_slot_pos()
	if n.global_position.distance_to(slot_pos) < SNAP_RADIUS + 0.10:
		# Stack it on top.
		var layer := LAYER_COUNT + top_layers
		var slot := cap_count % 3
		var rot_y := 0.0 if layer % 2 == 0 else PI * 0.5
		var local := _block_pos(layer, slot, rot_y)
		n.position = local
		n.rotation = Vector3(0, rot_y, 0)
		grabbed["mode"] = "tower"
		grabbed["layer"] = layer
		grabbed["slot"] = slot
		grabbed["is_cap"] = true
		n.material_override = cap_mat
		if slot == 2:
			top_layers += 1
		cap_count += 1
		score += 1
		lean_deg += randf_range(0.15, 0.45)
		wobble_t = 0.8
		wobble_amp = 0.016
		GraphicsPolish.spawn_sparks(self, slot_pos, Color(0.4, 1.0, 0.6), 18)
		GraphicsPolish.spawn_confetti(self, slot_pos, 20)
		ARUpgradeKit.save_anchor("tower-topple_main", global_transform)
	else:
		# Dropped: it falls with a little toss.
		grabbed["mode"] = "falling"
		grabbed["vel"] = drag_vel.limit_length(3.0) * 0.4 + Vector3(0, -0.5, 0)
		grabbed["spin"] = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		var gp: Vector3 = n.global_position
		tower_root.remove_child(n)
		add_child(n)
		n.global_position = gp
	grabbed = {}


func _update_falling(delta: float) -> void:
	for b in blocks:
		var bd: Dictionary = b
		if bd["mode"] != "falling":
			continue
		var n: Node3D = bd["node"]
		var v: Vector3 = bd["vel"]
		v.y -= 9.8 * delta
		n.global_position += v * delta
		n.rotation += (bd["spin"] as Vector3) * delta
		bd["vel"] = v
		var table_top := TABLE_Y + 0.02
		if n.global_position.y <= table_top + BLOCK_SIZE.y * 0.5 and v.y < 0.0:
			if absf(v.y) > 1.2:
				v.y = -v.y * 0.35
				v.x *= 0.6
				v.z *= 0.6
				bd["vel"] = v
				n.global_position.y = table_top + BLOCK_SIZE.y * 0.5
			else:
				bd["mode"] = "rest"
				bd["vel"] = Vector3.ZERO
				n.global_position.y = table_top + BLOCK_SIZE.y * 0.5
		if n.global_position.y < TABLE_Y - 0.6:
			# Fell off the table: the tower is doomed.
			_collapse()


func _update_lean(delta: float) -> void:
	if wobble_t > 0.0:
		wobble_t -= delta
		var w: float = sin(_time * 22.0) * wobble_amp * maxf(0.0, wobble_t)
		tower_root.rotation.x = deg_to_rad(lean_deg) * lean_dir.x + w
		tower_root.rotation.z = deg_to_rad(lean_deg) * lean_dir.z + w * 0.7
	else:
		tower_root.rotation.x = lerpf(tower_root.rotation.x, deg_to_rad(lean_deg) * lean_dir.x, minf(1.0, 3.0 * delta))
		tower_root.rotation.z = lerpf(tower_root.rotation.z, deg_to_rad(lean_deg) * lean_dir.z, minf(1.0, 3.0 * delta))
	if lean_deg >= COLLAPSE_DEG:
		_collapse()
	# Any tower block that slipped below the table = collapse.
	for b in blocks:
		var bd: Dictionary = b
		if bd["mode"] != "tower":
			continue
		var n: Node3D = bd["node"]
		if n.global_position.y < TABLE_Y - 0.10:
			_collapse()
			return


func _collapse() -> void:
	if state != "playing":
		return
	state = "gameover"
	has_grab = false
	grabbed = {}
	for b in blocks:
		var bd: Dictionary = b
		var n: Node3D = bd["node"]
		if n.get_parent() == tower_root:
			var gp: Vector3 = n.global_position
			tower_root.remove_child(n)
			add_child(n)
			n.global_position = gp
		bd["mode"] = "falling"
		bd["vel"] = Vector3(randf_range(-1.2, 1.2), randf_range(0.5, 2.0), randf_range(-1.2, 1.2))
		bd["spin"] = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	GraphicsPolish.spawn_confetti(self, tower_root.global_position + Vector3(0, 0.4, 0), 60)
	ARUpgradeKit.save_anchor("tower-topple_main", global_transform)


func _update_collapse(delta: float) -> void:
	for b in blocks:
		var bd: Dictionary = b
		if bd["mode"] != "falling":
			continue
		var n: Node3D = bd["node"]
		var v: Vector3 = bd["vel"]
		v.y -= 9.8 * delta
		n.global_position += v * delta
		n.rotation += (bd["spin"] as Vector3) * delta
		bd["vel"] = v
		if n.global_position.y < -1.5:
			n.queue_free()
			bd["mode"] = "gone"
