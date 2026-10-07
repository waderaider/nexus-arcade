## PortalPainterGame.gd - Paint glowing strokes in 3D space.
## The brush cursor follows the mouse at ~2m depth. Hold left mouse to paint
## (spheres spawn along the path), click a color swatch cube to change color,
## click CLEAR to wipe. Strokes auto-save to user://portal_painter.json.
extends Node3D
class_name PortalPainterGame

const SAVE_PATH := "user://portal_painter.json"
const BRUSH_DEPTH := 2.0
const DOT_RADIUS := 0.022
const DOT_SPACING := 0.035
const MAX_POINTS := 4000
const PALETTE := [
	{"name": "Cyan", "color": Color(0.2, 0.9, 1.0)},
	{"name": "Magenta", "color": Color(1.0, 0.25, 0.85)},
	{"name": "Yellow", "color": Color(1.0, 0.9, 0.2)},
	{"name": "Green", "color": Color(0.3, 1.0, 0.4)},
	{"name": "Orange", "color": Color(1.0, 0.55, 0.15)},
	{"name": "White", "color": Color(0.95, 0.95, 1.0)},
]

var _cam: Camera3D
var _cursor: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _mouse_pos := Vector2.ZERO
var _has_mouse := false

var _brush_color := Color(0.2, 0.9, 1.0)
var _brush_name := "Cyan"
var _painting := false
var _strokes: Array = [] # each: {"color": Color, "points": Array[Vector3], "nodes": Array}
var _current_points: Array = []
var _current_nodes: Array = []
var _last_dot := Vector3.ZERO
var _has_last := false
var _dot_count := 0

var _stroke_root: Node3D
var _dot_mesh: SphereMesh
var _mat_cache := {}
var _swatches: Array = [] # {"node","center","color","name"}
var _clear_btn: MeshInstance3D
var _clear_center := Vector3.ZERO

var _hud_label: Label3D
var _help_label: Label3D
var _anchor_timer := 0.0

# v0.7.0 roomscale: room layout cache (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _palette_root: Node3D = null


func _ready() -> void:
	_ensure_camera()
	_build_light_and_floor()
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = DOT_RADIUS
	_dot_mesh.height = DOT_RADIUS * 2.0
	_stroke_root = Node3D.new()
	add_child(_stroke_root)
	_build_cursor()
	# Palette + CLEAR button live under one root so roomscale can move them.
	_palette_root = Node3D.new()
	add_child(_palette_root)
	_build_palette()
	_build_clear_button()
	_build_labels()
	_load_strokes()
	_refresh_hud()
	# AR: restore the saved room anchor in XR; spawn ambient dust motes.
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.apply_anchor(self, "portal-painter_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, -1.5), 2.5, 40)
	_apply_room_layout()


func _process(delta: float) -> void:
	if _has_mouse:
		_update_cursor()
	if _painting and _has_mouse:
		_paint_step()
	_update_anchor_timer(delta)
	if ARUpgradeKit.is_xr_active():
		# XR brush cursor follows the pointer ray at brush depth.
		var cp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, BRUSH_DEPTH)
		cp.y = maxf(cp.y, 0.06)
		_cursor.position = cp
		# XR pinch: alternative paint trigger (mouse path stays intact on desktop).
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			var pr := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
			_press_ray(pr[0], pr[1])
		elif _painting and not ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_end_stroke()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
		_has_mouse = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_mouse_pos = mb.position
		_has_mouse = true
		if mb.pressed:
			_handle_press(mb.position)
		else:
			_end_stroke()


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- setup ---

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 1.6, 0.6)
	add_child(_cam)
	_cam.look_at(Vector3(0.0, 1.4, -1.5), Vector3.UP)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light_and_floor() -> void:
	_add_polish_light_rig()
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	floor_mi.mesh = plane
	floor_mi.material_override = GraphicsPolish.pbr(Color(0.1, 0.11, 0.15), 0.0, 0.9)
	add_child(floor_mi)


func _glow_material(color: Color) -> StandardMaterial3D:
	if _mat_cache.has(color):
		return _mat_cache[color]
	var mat := GraphicsPolish.glow(color, 1.6)
	_mat_cache[color] = mat
	return mat


func _build_cursor() -> void:
	_cursor = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	_cursor.mesh = s
	_cursor_mat = GraphicsPolish.glow(_brush_color, 2.0)
	_cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor.material_override = _cursor_mat
	_cursor.position = Vector3(0, 1.4, -1.4)
	add_child(_cursor)


func _make_label(text: String, pos: Vector3, font_size: int = 48, parent: Node = null) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = pos
	(parent if parent != null else self).add_child(label)
	return label


func _build_palette() -> void:
	_make_label("COLORS", Vector3(-1.6, 2.15, -1.5), 56, _palette_root)
	for i in range(PALETTE.size()):
		var entry: Dictionary = PALETTE[i]
		var center := ARUpgradeKit.clamp_to_room(Vector3(-1.6, 1.85 - i * 0.26, -1.5))
		var cube := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.15, 0.15, 0.15)
		cube.mesh = bm
		cube.material_override = _glow_material(entry["color"])
		cube.position = center
		_palette_root.add_child(cube)
		_make_label(entry["name"], center + Vector3(0.32, 0.0, 0.0), 36, _palette_root)
		_swatches.append({"node": cube, "center": center,
				"color": entry["color"], "name": entry["name"]})


func _build_clear_button() -> void:
	_clear_center = ARUpgradeKit.clamp_to_room(Vector3(1.6, 1.0, -1.5))
	_clear_btn = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.44, 0.18, 0.1)
	_clear_btn.mesh = bm
	_clear_btn.material_override = GraphicsPolish.glow(Color(0.75, 0.2, 0.2), 0.9)
	_clear_btn.position = _clear_center
	_palette_root.add_child(_clear_btn)
	var label := Label3D.new()
	label.text = "CLEAR"
	label.font_size = 64
	label.pixel_size = 0.006
	label.no_depth_test = true
	label.position = _clear_center + Vector3(0, 0, 0.06)
	_palette_root.add_child(label)


func _build_labels() -> void:
	_hud_label = _make_label("", Vector3(0.0, 2.45, -1.7), 56)
	_help_label = _make_label(
			"Portal Painter - hold LEFT MOUSE and move to paint in 3D.\nClick a color cube to change color. Click CLEAR to wipe.\nStrokes auto-save and reload next visit.",
			Vector3(0.0, 0.55, -1.9), 40)


# ---------------------------------------------------------------- roomscale ---

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
	# v0.7.0 MORPH-C: the largest table becomes an arcane painting altar — the artist paints beside the morphed palette station.
	var _morph_table := RoomKit.get_anchors("TABLE")
	if not _morph_table.is_empty():
		RoomKit.morph(_morph_table[0], "arcane")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	if _palette_root == null or _room_tables.is_empty():
		return
	# Float the palette + CLEAR cluster beside the largest detected table,
	# at standing height above its tabletop.
	var t := _largest_table(_room_tables)
	var tpos: Vector3 = t["position"]
	var tsize: Vector3 = t["size"]
	var top_y := tpos.y + tsize.y * 0.5
	_palette_root.global_position = Vector3(
		tpos.x + tsize.x * 0.5 + 0.55 + 1.6,
		maxf(top_y - 0.4, 0.7),
		tpos.z + 1.5)


# ---------------------------------------------------------------- painting ---

func _mouse_ray(screen_pos: Vector2) -> Array:
	return [_cam.project_ray_origin(screen_pos), _cam.project_ray_normal(screen_pos)]


func _ray_hit(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> bool:
	var oc := center - origin
	var t := oc.dot(dir)
	if t < 0.0:
		return false
	return oc.length_squared() - t * t <= radius * radius


func _update_cursor() -> void:
	if _cam == null:
		return
	var ray := _mouse_ray(_mouse_pos)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var p := origin + dir * BRUSH_DEPTH
	p.y = maxf(p.y, 0.06)
	_cursor.position = p


func _handle_press(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var ray := _mouse_ray(screen_pos)
	_press_ray(ray[0], ray[1])


func _press_ray(origin: Vector3, dir: Vector3) -> void:
	for sw in _swatches:
		# Live node position: the palette cluster may have been relocated.
		var sc: Vector3 = (sw["node"] as MeshInstance3D).global_position
		if _ray_hit(origin, dir, sc, 0.16):
			_brush_color = sw["color"]
			_brush_name = sw["name"]
			_cursor_mat.albedo_color = _brush_color
			_cursor_mat.emission = _brush_color
			_refresh_hud()
			return
	if _ray_hit(origin, dir, _clear_btn.global_position, 0.3):
		_clear_all()
		return
	_painting = true
	_current_points.clear()
	_current_nodes.clear()
	_has_last = false


func _paint_step() -> void:
	var p := _cursor.position
	if _has_last and p.distance_to(_last_dot) < DOT_SPACING:
		return
	_add_dot(p, _brush_color, true)
	_last_dot = p
	_has_last = true


func _add_dot(p: Vector3, color: Color, live: bool) -> void:
	while _dot_count >= MAX_POINTS and not _strokes.is_empty():
		_drop_oldest_stroke()
	var dot := MeshInstance3D.new()
	dot.mesh = _dot_mesh
	dot.material_override = _glow_material(color)
	dot.position = p
	_stroke_root.add_child(dot)
	_dot_count += 1
	if live:
		_current_points.append(p)
		_current_nodes.append(dot)
		_refresh_hud()


func _drop_oldest_stroke() -> void:
	var s: Dictionary = _strokes.pop_front()
	for n in s["nodes"]:
		(n as Node).queue_free()
		_dot_count -= 1


func _end_stroke() -> void:
	if not _painting:
		return
	_painting = false
	if not _current_points.is_empty():
		_strokes.append({"color": _brush_color,
				"points": _current_points.duplicate(),
				"nodes": _current_nodes.duplicate()})
		_save()
	_current_points.clear()
	_current_nodes.clear()
	_has_last = false
	_refresh_hud()


func _clear_all() -> void:
	_strokes.clear()
	for child in _stroke_root.get_children():
		child.queue_free()
	_dot_count = 0
	_current_points.clear()
	_current_nodes.clear()
	_painting = false
	_save()
	_refresh_hud()
	GraphicsPolish.spawn_sparks(self, _clear_center, Color(1.0, 0.5, 0.3), 30)


func _refresh_hud() -> void:
	var total := _dot_count
	_hud_label.text = "Strokes: %d   Dots: %d   Color: %s" % [_strokes.size(), total, _brush_name]


# ---------------------------------------------------------------- persistence ---

func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active():
			ARUpgradeKit.save_anchor("portal-painter_main", global_transform)


func _save() -> void:
	var data := {"strokes": []}
	for s in _strokes:
		var pts: Array = []
		for p in s["points"]:
			pts.append([p.x, p.y, p.z])
		var c: Color = s["color"]
		data["strokes"].append({"c": [c.r, c.g, c.b], "p": pts})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_strokes() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var list: Array = parsed.get("strokes", [])
	for s in list:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var cv: Array = s.get("c", [0.2, 0.9, 1.0])
		var color := Color(cv[0], cv[1], cv[2])
		var nodes: Array = []
		for pv in s.get("p", []):
			if _dot_count >= MAX_POINTS:
				break
			var p := Vector3(pv[0], pv[1], pv[2])
			var dot := MeshInstance3D.new()
			dot.mesh = _dot_mesh
			dot.material_override = _glow_material(color)
			dot.position = p
			_stroke_root.add_child(dot)
			nodes.append(dot)
			_dot_count += 1
		_strokes.append({"color": color, "points": [], "nodes": nodes})
