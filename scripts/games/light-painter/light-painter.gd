## light-painter.gd -- NEXUS ARCADE: 3D light painting.
## Your pointer leaves a glowing trail; pinch-hold (or hold left mouse) to
## paint a persistent 3D ribbon stroke in the air, release to end the stroke.
## XR: second-hand pinch cycles the paint color, double second-hand pinch
## clears the canvas. Desktop: C cycles color, X clears.
## Strokes persist across sessions in the anchor file.
## Score = total painted length; the gallery rating grows with it.
extends Node3D

const MIN_POINT_DIST := 0.02
const MAX_POINTS := 800
const RIBBON_WIDTH := 0.035
const SAVE_SECTION := "light_painter"

var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}

var cursor: MeshInstance3D = null
var cursor_mat: StandardMaterial3D = null
var cursor_trail: GPUParticles3D = null

var strokes: Array = [] # each: {node, points: PackedVector3Array, color, length}
var painting := false
var cur_points := PackedVector3Array()
var cur_node: MeshInstance3D = null
var cur_mat: StandardMaterial3D = null
var cur_length := 0.0

var palette: Array = [
	Color(0.2, 0.9, 1.0), Color(1.0, 0.35, 0.6), Color(0.5, 1.0, 0.3),
	Color(1.0, 0.85, 0.2), Color(0.7, 0.4, 1.0), Color(1.0, 1.0, 1.0),
]
var color_idx := 0
var _last_left_pinch_t := -10.0
var _anchor_timer := 0.0

var hud_label: Label3D = null
var help_label: Label3D = null

# v0.7.0 roomscale: room layout cache (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _has_room_layout := false


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "light-painter_main")
	_build_camera()
	_build_environment()
	GraphicsPolish.make_light_rig(self)
	_build_cursor()
	_build_ui()
	_load_strokes()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.3, -1), 2.0, 30)
	_apply_room_layout()


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the work table becomes a neon light-bench and the rug becomes the neon light-stage arena.
	var _morph0_table := RoomKit.get_anchors("TABLE")
	if not _morph0_table.is_empty():
		RoomKit.morph(_morph0_table[0], "neon")
	var _morph1_rug := RoomKit.get_anchors("RUG")
	if not _morph1_rug.is_empty():
		RoomKit.morph(_morph1_rug[0], "neon")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	_has_room_layout = true
	if _room_walls.is_empty():
		return
	# Pin the HUD panels to the face of the largest real wall.
	var w := _largest_wall(_room_walls)
	var wpos: Vector3 = w["position"]
	var n: Vector3 = (w["normal"] as Vector3).normalized()
	if absf(n.y) > 0.5:
		return
	var face: Vector3 = wpos + n * 0.06
	var up := clampf(wpos.y + (w["size"] as Vector2).y * 0.5 - 0.55, 1.6, 2.6)
	if hud_label != null:
		hud_label.position = to_local(face + Vector3(0, up - wpos.y, 0))
	if help_label != null:
		help_label.position = to_local(face + Vector3(0, up - wpos.y - 0.55, 0))


func _build_camera() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			return
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 2.6)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, -1.0), Vector3.UP)


func _build_environment() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.55)
	env.ambient_light_energy = 0.6
	amb.environment = env
	add_child(amb)

	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.0, 0.1, 8.0)
	floor_mi.mesh = fb
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.09, 0.16), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _build_cursor() -> void:
	cursor = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	cursor.mesh = sm
	cursor_mat = GraphicsPolish.glow(palette[color_idx], 2.2)
	cursor.material_override = cursor_mat
	add_child(cursor)
	cursor_trail = GraphicsPolish.make_trail(palette[color_idx], 0.05)
	cursor.add_child(cursor_trail)
	GraphicsPolish.make_point_light(cursor, Vector3.ZERO, palette[color_idx], 0.8, 2.5)


func _build_ui() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(0.9, 0.95, 1.0))
	hud_label.position = Vector3(-2.8, 2.5, -1.0)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label(
		"Hold pinch / left mouse: paint\nXR: 2nd-hand pinch: color, double: clear\nDesktop: C: color, X: clear",
		48, Color(0.7, 0.8, 1.0))
	help_label.position = Vector3(2.8, 2.5, -1.0)
	add_child(help_label)


func _largest_wall(walls: Array) -> Dictionary:
	var best: Dictionary = walls[0]
	var best_area := 0.0
	for w in walls:
		var s: Vector2 = w["size"]
		var area := s.x * s.y
		if area > best_area:
			best_area = area
			best = w
	return best


func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	_update_cursor()
	_poll_paint()
	_poll_gestures()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		_save_strokes()
	_update_ui()
	GraphicsPolish.pulse_glow(cursor_mat, 1.8, 0.8, _time, 4.0)


func _poll_keys() -> void:
	_key_edge(KEY_C, _cycle_color)
	_key_edge(KEY_X, _clear_canvas)


func _key_edge(keycode: int, action: Callable) -> void:
	var down := Input.is_key_pressed(keycode)
	var was: bool = _prev_keys.get(keycode, false)
	if down and not was:
		action.call()
	_prev_keys[keycode] = down


func _cursor_target() -> Vector3:
	var p: Vector3
	if ARUpgradeKit.is_xr_active():
		p = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.2)
	elif cam == null:
		p = global_position + Vector3(0, 1.2, -1)
	else:
		var mp := get_viewport().get_mouse_position()
		var ro := cam.project_ray_origin(mp)
		var rd := cam.project_ray_normal(mp)
		p = ro + rd * 1.2
	if _has_room_layout:
		# Keep the paint volume inside the real room footprint.
		var lp := to_local(p)
		lp.x = clampf(lp.x, _room_bounds.position.x + 0.3, _room_bounds.position.x + _room_bounds.size.x - 0.3)
		lp.z = clampf(lp.z, _room_bounds.position.y + 0.3, _room_bounds.position.y + _room_bounds.size.y - 0.3)
		p = to_global(lp)
	return p


func _update_cursor() -> void:
	cursor.global_position = _cursor_target()


func _poll_paint() -> void:
	var held := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	if held and not painting:
		_begin_stroke()
	elif not held and painting:
		_end_stroke()
	if painting:
		var p: Vector3 = cursor.global_position
		if cur_points.is_empty() or cur_points[cur_points.size() - 1].distance_to(p) >= MIN_POINT_DIST:
			if cur_points.size() > 0:
				cur_length += cur_points[cur_points.size() - 1].distance_to(p)
			cur_points.append(p)
			if cur_points.size() > MAX_POINTS:
				cur_points.remove_at(0)
			_rebuild_ribbon()


func _poll_gestures() -> void:
	# Two-hand gestures are XR-only (desktop uses C/X keys).
	if not ARUpgradeKit.is_xr_active():
		return
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_left_pinch_t < 0.5:
			_clear_canvas()
			_last_left_pinch_t = -10.0
		else:
			_cycle_color()
			_last_left_pinch_t = now


func _begin_stroke() -> void:
	painting = true
	cur_points = PackedVector3Array()
	cur_length = 0.0
	cur_mat = GraphicsPolish.glow(palette[color_idx], 1.8)
	cur_node = MeshInstance3D.new()
	cur_node.material_override = cur_mat
	add_child(cur_node)


func _end_stroke() -> void:
	painting = false
	if cur_points.size() >= 2:
		strokes.append({"node": cur_node, "points": cur_points,
			"color": palette[color_idx], "length": cur_length})
		_save_strokes()
	else:
		cur_node.queue_free()
	cur_node = null
	cur_points = PackedVector3Array()


func _rebuild_ribbon() -> void:
	if cur_node == null or cur_points.size() < 2:
		return
	cur_node.mesh = _ribbon_mesh(cur_points, RIBBON_WIDTH)


func _ribbon_mesh(points: PackedVector3Array, width: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var cam_pos := cam.global_position if cam != null else Vector3(0, 1.6, 3)
	var n := points.size()
	for i in n:
		var p := points[i]
		var a := points[maxi(0, i - 1)]
		var b := points[mini(n - 1, i + 1)]
		var tangent: Vector3 = (b - a)
		if tangent.length() < 0.0001:
			tangent = Vector3(0, 0, 1)
		tangent = tangent.normalized()
		var to_cam: Vector3 = (cam_pos - p).normalized()
		var side: Vector3 = tangent.cross(to_cam)
		if side.length() < 0.001:
			side = tangent.cross(Vector3.UP)
		side = side.normalized() * (width * 0.5)
		verts.append(p + side)
		verts.append(p - side)
		normals.append(to_cam)
		normals.append(to_cam)
		if i > 0:
			var k := i * 2
			indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _cycle_color() -> void:
	color_idx = (color_idx + 1) % palette.size()
	var c: Color = palette[color_idx]
	cursor_mat.albedo_color = c
	cursor_mat.emission = c
	if cursor_trail != null:
		cursor_trail.queue_free()
	cursor_trail = GraphicsPolish.make_trail(c, 0.05)
	cursor.add_child(cursor_trail)
	GraphicsPolish.spawn_sparks(self, cursor.global_position, c, 16)


func _clear_canvas() -> void:
	for s in strokes:
		(s["node"] as Node3D).queue_free()
	strokes.clear()
	if painting and cur_node != null:
		cur_node.queue_free()
		cur_node = null
		cur_points = PackedVector3Array()
		painting = false
	_save_strokes()
	GraphicsPolish.spawn_sparks(self, cursor.global_position, Color(1, 1, 1), 30)


func _total_length() -> float:
	var total := 0.0
	for s in strokes:
		total += float(s["length"])
	return total + cur_length


func _gallery_rating() -> String:
	var total := _total_length()
	var colors := {}
	for s in strokes:
		colors[s["color"]] = true
	var stars := 1
	if total >= 2.0:
		stars = 2
	if total >= 6.0:
		stars = 3
	if total >= 12.0:
		stars = 4
	if total >= 20.0:
		stars = 5
	if colors.size() >= 3 and stars < 5:
		stars += 1
	return "★".repeat(stars) + "☆".repeat(5 - stars)


func _update_ui() -> void:
	hud_label.text = "LIGHT PAINTER\nStrokes: %d\nPainted: %.1f m\nGallery: %s" % [
		strokes.size(), _total_length(), _gallery_rating()]


func _save_strokes() -> void:
	var cfg := ConfigFile.new()
	cfg.load(ARUpgradeKit.ANCHOR_FILE)
	cfg.set_value(SAVE_SECTION, "count", strokes.size())
	for i in strokes.size():
		var s: Dictionary = strokes[i]
		cfg.set_value(SAVE_SECTION, "c%d" % i, s["color"])
		cfg.set_value(SAVE_SECTION, "p%d" % i, s["points"])
	cfg.save(ARUpgradeKit.ANCHOR_FILE)


func _load_strokes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARUpgradeKit.ANCHOR_FILE) != OK:
		return
	var count := int(cfg.get_value(SAVE_SECTION, "count", 0))
	for i in count:
		var c: Color = cfg.get_value(SAVE_SECTION, "c%d" % i, Color.WHITE)
		var pts: PackedVector3Array = cfg.get_value(SAVE_SECTION, "p%d" % i, PackedVector3Array())
		if pts.size() < 2:
			continue
		var mat := GraphicsPolish.glow(c, 1.8)
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon_mesh(pts, RIBBON_WIDTH)
		mi.material_override = mat
		add_child(mi)
		var length := 0.0
		for j in range(1, pts.size()):
			length += pts[j - 1].distance_to(pts[j])
		strokes.append({"node": mi, "points": pts, "color": c, "length": length})
