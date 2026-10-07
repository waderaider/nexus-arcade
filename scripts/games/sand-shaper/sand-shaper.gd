## SandShaper: deformable AR sandbox terrain.
## A 16x16 grid mesh sits on a table in front of you. Hold the left mouse
## button (or pinch in XR) to RAISE terrain under the cursor, right mouse
## button to LOWER it (gaussian falloff brush). A water plane at fixed
## height floods low areas. Goal cards ask you to shape the sand:
## "make an island", "dig a lake", "build a volcano" - a shape-matching
## score compares your heightmap to the target. Confetti on completion.
## G cycles goals, F flattens, T saves terrain, R restarts.
extends Node3D

const GRID := 16
const SIZE := 1.6
const H_MIN := -0.30
const H_MAX := 0.35
const BRUSH_R := 0.25
const BRUSH_RATE := 0.35
const TABLE_Y := 0.75
const GOAL_NAMES := ["make an island", "dig a lake", "build a volcano"]
const MATCH_WIN := 82.0
const SAVE_FILE := "user://sand_shaper.cfg"

var camera: Camera3D = null
var verts := GRID + 1
var heights := PackedFloat32Array()
var targets: Array = []
var terrain: MeshInstance3D = null
var arr_mesh := ArrayMesh.new()
var water_mat: StandardMaterial3D = null
var goal_idx := 0
var goal_done := [false, false, false]
var state := "playing"
var hud_goal: Label3D = null
var hud_match: Label3D = null
var hud_hint: Label3D = null
var hud_msg: Label3D = null
var brush_ring: MeshInstance3D = null
var elapsed := 0.0

# v0.7.0 roomscale: room layout cache (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _ready() -> void:
	if not ARUpgradeKit.apply_anchor(self, "sand-shaper_main"):
		ARUpgradeKit.place_on_table(self, 1.0, TABLE_Y)
	heights.resize(verts * verts)
	heights.fill(0.0)
	_ensure_camera()
	_ensure_env()
	_ensure_light()
	_build_targets()
	_build_terrain()
	_build_water()
	_build_brush()
	_build_hud()
	_load_saved_heights()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, 0.0), 1.6, 30)
	_rebuild_mesh()
	_apply_room_layout()


func _largest_table(tables: Array) -> Dictionary:
	var best: Dictionary = tables[0]
	var best_area := 0.0
	for t in tables:
		var s: Vector3 = t["size"]
		var area := s.x * s.z
		if area > best_area:
			best_area = area
			best = t
	return best


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the shaping table becomes a nature sandbox altar — a miniature enchanted landscape.
	var _morph_table := RoomKit.get_anchors("TABLE")
	if not _morph_table.is_empty():
		RoomKit.morph(_morph_table[0], "nature")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	if _room_tables.is_empty():
		return
	# Set the sandbox tray on the largest detected table, centered, base on
	# the tabletop (fallback when no table: keep the floating placement).
	var t := _largest_table(_room_tables)
	var tpos: Vector3 = t["position"]
	var tsize: Vector3 = t["size"]
	global_position = Vector3(tpos.x, tpos.y + tsize.y * 0.5, tpos.z)


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.7, 2.6)
		cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.38, 0.5)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _build_targets() -> void:
	targets.clear()
	for g in range(3):
		var t := PackedFloat32Array()
		t.resize(verts * verts)
		for j in range(verts):
			for i in range(verts):
				var x := (i / float(GRID) - 0.5) * SIZE
				var z := (j / float(GRID) - 0.5) * SIZE
				var r := Vector2(x, z).length()
				var h := 0.0
				if g == 0:  # island: smooth bump
					h = 0.30 * exp(-pow(r / 0.50, 2.0))
				elif g == 1:  # lake: smooth depression
					h = -0.25 * exp(-pow(r / 0.55, 2.0))
				else:  # volcano: cone with crater
					h = 0.32 * maxf(0.0, 1.0 - r / 0.60) - 0.18 * exp(-pow(r / 0.20, 2.0))
				t[j * verts + i] = clampf(h, H_MIN, H_MAX)
		targets.append(t)


func _build_terrain() -> void:
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	var mat := GraphicsPolish.pbr(Color(1, 1, 1), 0.0, 0.9)
	mat.vertex_color_use_as_albedo = true
	terrain.material_override = mat
	add_child(terrain)
	# Wooden tray frame.
	var frame_mat := GraphicsPolish.pbr_preset(Color(0.4, 0.26, 0.14), "matte")
	for sx in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.1, SIZE + 0.12)
		edge.mesh = bm
		edge.material_override = frame_mat
		edge.position = Vector3(sx * (SIZE / 2 + 0.03), -0.05, 0.0)
		add_child(edge)
	for sz in [-1.0, 1.0]:
		var edge2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(SIZE + 0.12, 0.1, 0.06)
		edge2.mesh = bm2
		edge2.material_override = frame_mat
		edge2.position = Vector3(0.0, -0.05, sz * (SIZE / 2 + 0.03))
		add_child(edge2)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	water.mesh = pm
	water_mat = GraphicsPolish.pbr_preset(Color(0.15, 0.5, 0.95), "glass")
	water.material_override = water_mat
	water.position = Vector3(0.0, 0.02, 0.0)
	add_child(water)


func _build_brush() -> void:
	brush_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = BRUSH_R - 0.015
	tm.outer_radius = BRUSH_R + 0.015
	brush_ring.mesh = tm
	brush_ring.material_override = GraphicsPolish.glow(Color(1.0, 0.9, 0.3), 1.5)
	brush_ring.visible = false
	add_child(brush_ring)


func _build_hud() -> void:
	hud_goal = GraphicsPolish.make_label("", 52, Color(1.0, 0.95, 0.6))
	hud_goal.position = Vector3(0.0, 2.1, -0.6)
	add_child(hud_goal)
	hud_match = GraphicsPolish.make_label("", 44, Color(0.6, 1.0, 0.8))
	hud_match.position = Vector3(0.0, 1.85, -0.6)
	add_child(hud_match)
	hud_hint = GraphicsPolish.make_label("LMB/pinch: raise  RMB: lower  G: goal  F: flatten  T: save", 32, Color(0.8, 0.9, 1.0))
	hud_hint.position = Vector3(0.0, 0.15, 0.9)
	add_child(hud_hint)
	hud_msg = GraphicsPolish.make_label("", 72, Color(1.0, 0.9, 0.3))
	hud_msg.position = Vector3(0.0, 1.6, -0.6)
	add_child(hud_msg)


func _process(delta: float) -> void:
	elapsed += delta
	if state == "playing":
		_apply_brush(delta)
		var m := _match_score()
		hud_goal.text = "Goal: " + GOAL_NAMES[goal_idx]
		hud_match.text = "Match: %d%%  (need %d%%)" % [int(m), int(MATCH_WIN)]
		if m >= MATCH_WIN:
			_complete_goal()
	GraphicsPolish.pulse_glow(water_mat, 0.6, 0.35, elapsed, 1.2)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_G:
				goal_idx = (goal_idx + 1) % 3
				hud_msg.text = ""
			KEY_F:
				heights.fill(0.0)
				_rebuild_mesh()
			KEY_T:
				_save_terrain()
			KEY_R:
				_reset()


func _reset() -> void:
	heights.fill(0.0)
	goal_idx = 0
	goal_done = [false, false, false]
	state = "playing"
	hud_msg.text = ""
	_rebuild_mesh()


func _terrain_point() -> Variant:
	# Returns the local-space point on the terrain under the pointer, or null.
	var world_hit := Vector3.ZERO
	var have := false
	if ARUpgradeKit.is_xr_active():
		var pp: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.0)
		world_hit = pp
		have = true
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mp)
		var dir := camera.project_ray_normal(mp)
		if absf(dir.y) > 0.0001:
			var t := (global_position.y - origin.y) / dir.y
			if t > 0.0:
				world_hit = origin + dir * t
				have = true
	if not have:
		return null
	var local: Vector3 = to_local(world_hit)
	if absf(local.x) > SIZE / 2 or absf(local.z) > SIZE / 2:
		return null
	return local


func _apply_brush(delta: float) -> void:
	var raising := false
	var lowering := false
	if ARUpgradeKit.is_xr_active():
		raising = ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	else:
		raising = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		lowering = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not raising and not lowering:
		brush_ring.visible = false
		return
	var pt: Variant = _terrain_point()
	if pt == null:
		brush_ring.visible = false
		return
	var local: Vector3 = pt
	brush_ring.visible = true
	brush_ring.position = Vector3(local.x, _height_at(local.x, local.z) + 0.03, local.z)
	var sign := 1.0 if raising else -1.0
	var cell := SIZE / GRID
	for j in range(verts):
		for i in range(verts):
			var x := (i / float(GRID) - 0.5) * SIZE
			var z := (j / float(GRID) - 0.5) * SIZE
			var d := Vector2(x - local.x, z - local.z).length()
			if d < BRUSH_R * 2.0:
				var fall := exp(-pow(d / BRUSH_R, 2.0))
				var idx := j * verts + i
				heights[idx] = clampf(heights[idx] + sign * BRUSH_RATE * fall * delta, H_MIN, H_MAX)
	_rebuild_mesh()


func _height_at(x: float, z: float) -> float:
	var fi := clampf((x / SIZE + 0.5) * GRID, 0.0, float(GRID - 1))
	var fj := clampf((z / SIZE + 0.5) * GRID, 0.0, float(GRID - 1))
	return heights[int(fj) * verts + int(fi)]


func _match_score() -> float:
	var t: PackedFloat32Array = targets[goal_idx]
	var diff := 0.0
	for i in range(heights.size()):
		diff += absf(heights[i] - t[i])
	var mean := diff / heights.size()
	return clampf(1.0 - mean / 0.35, 0.0, 1.0) * 100.0


func _complete_goal() -> void:
	goal_done[goal_idx] = true
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 0.6, 0.0), 70)
	var done_count := 0
	for d in goal_done:
		if d:
			done_count += 1
	if done_count >= 3:
		state = "win"
		hud_msg.text = "ALL GOALS COMPLETE!  (R to play again)"
	else:
		hud_msg.text = "Goal complete!"
		goal_idx = (goal_idx + 1) % 3
		if goal_done[goal_idx]:
			for g in range(3):
				if not goal_done[g]:
					goal_idx = g
					break


func _update_hud() -> void:
	if state == "win":
		hud_goal.text = "Sandbox complete!"
		hud_match.text = ""


func _save_terrain() -> void:
	ARUpgradeKit.save_anchor("sand-shaper_main", global_transform)
	var cfg := ConfigFile.new()
	cfg.set_value("terrain", "goal_idx", goal_idx)
	cfg.set_value("terrain", "heights", heights)
	cfg.save(SAVE_FILE)
	hud_msg.text = "Terrain saved."


func _load_saved_heights() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) != OK:
		return
	var h: Variant = cfg.get_value("terrain", "heights", null)
	if h is PackedFloat32Array and (h as PackedFloat32Array).size() == heights.size():
		heights = h


func _rebuild_mesh() -> void:
	arr_mesh.clear_surfaces()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var cell := SIZE / GRID
	for j in range(verts):
		for i in range(verts):
			var x := (i / float(GRID) - 0.5) * SIZE
			var z := (j / float(GRID) - 0.5) * SIZE
			var h: float = heights[j * verts + i]
			v.append(Vector3(x, h, z))
			var hl: float = heights[j * verts + maxi(i - 1, 0)]
			var hr: float = heights[j * verts + mini(i + 1, GRID)]
			var hd: float = heights[maxi(j - 1, 0) * verts + i]
			var hu: float = heights[mini(j + 1, GRID) * verts + i]
			var normal := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			n.append(normal)
			c.append(_sand_color(h))
	for j in range(GRID):
		for i in range(GRID):
			var a := j * verts + i
			var b := a + 1
			var cc := a + verts
			var d := cc + 1
			idx.append_array([a, cc, b, b, cc, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain.mesh = arr_mesh


func _sand_color(h: float) -> Color:
	# Underwater sand -> beach -> grass -> rock -> snow.
	if h < 0.02:
		return Color(0.55, 0.48, 0.32).lerp(Color(0.76, 0.68, 0.45), clampf((h + 0.3) / 0.32, 0.0, 1.0))
	if h < 0.14:
		return Color(0.76, 0.68, 0.45).lerp(Color(0.35, 0.65, 0.3), (h - 0.02) / 0.12)
	if h < 0.24:
		return Color(0.35, 0.65, 0.3).lerp(Color(0.5, 0.5, 0.52), (h - 0.14) / 0.10)
	return Color(0.5, 0.5, 0.52).lerp(Color(0.95, 0.95, 1.0), clampf((h - 0.24) / 0.11, 0.0, 1.0))
