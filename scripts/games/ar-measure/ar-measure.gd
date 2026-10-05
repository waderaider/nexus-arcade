## ar_measure.gd - Measure distances in 3D space.
## Click two points (raycast on floor/walls, else a fixed-depth plane) to
## draw a measurement line with a distance label. Up to 8 measurements
## listed in the HUD. "Clear" removes all; "Room" mode: click 4 floor
## corners to get width x depth and area. ESC / right-click cancels.
## Upgraded: PBR/glow materials, three-point light rig, spark + ambient-mote
## juice, XR pinch point placement, spatial anchor persistence, room clamping.
extends Node3D
class_name ARMeasureGame

const MAX_MEASUREMENTS := 8
const LINE_THICK := 0.025

enum Mode { MEASURE, ROOM }

var _cam: Camera3D = null
var _mode: int = Mode.MEASURE
var _pending: Array[Vector3] = [] ## in-progress measure points
var _room_corners: Array[Vector3] = [] ## in-progress room corners
var _measurements: Array = [] ## {a, b, dist, nodes: Array}
var _room_nodes: Array[Node] = []
var _room_result: Label3D = null
var _hud: Label3D = null
var _markers: Array[Node3D] = []
var _buttons := {} ## StaticBody3D -> String
var _anchor_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "ar-measure_main")
	_ensure_camera()
	_build_light()
	_build_room()
	_build_buttons()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, 0), 3.0, 40)


func _process(delta: float) -> void:
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("ar-measure_main", global_transform)
	# Hand interaction: right-hand pinch drops a point at the hand pointer.
	# Mouse clicks stay on _unhandled_input; the mouse-press gate keeps the
	# kit's mouse fallback from double-triggering.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var hp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if _mode == Mode.MEASURE:
			_add_measure_point(hp)
		else:
			_add_room_corner(hp)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_pending()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_cancel_pending()


func _pinch_active() -> bool:
	return false


# ---------------------------------------------------------------- build

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 3.2, 5.5)
	_cam.look_at(Vector3(0, 0.8, -1.0), Vector3.UP)


func _build_light() -> void:
	# Upgraded three-point light rig; never add a second key light.
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.ambient_light_energy = 0.9
	amb.environment = env
	add_child(amb)


func _build_room() -> void:
	## Floor.
	_add_static_box(Vector3(0, -0.1, 0), Vector3(12, 0.2, 12), Color(0.18, 0.2, 0.26))
	## Back wall.
	_add_static_box(Vector3(0, 2.5, -6), Vector3(12, 5.0, 0.2), Color(0.22, 0.24, 0.32))
	## Left wall.
	_add_static_box(Vector3(-6, 2.5, 0), Vector3(0.2, 5.0, 12), Color(0.2, 0.22, 0.3))


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var sb := StaticBody3D.new()
	add_child(sb)
	sb.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(color, "matte")
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)


func _build_buttons() -> void:
	_make_button("clear", "Clear", Vector3(-1.5, 1.2, 2.8), Color(0.85, 0.35, 0.3))
	_make_button("room", "Room mode", Vector3(1.5, 1.2, 2.8), Color(0.3, 0.6, 0.9))


func _make_button(action: String, text: String, pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.6, 0.15)
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
	bs.size = Vector3(2.2, 0.6, 0.15)
	cs.shape = bs
	sb.add_child(cs)
	var label := GraphicsPolish.make_label(text, 48, Color.WHITE)
	label.position = Vector3(0, 0, 0.1)
	label.pixel_size = 0.011
	root.add_child(label)
	_buttons[sb] = action


func _build_hud() -> void:
	_hud = GraphicsPolish.make_label("", 48, Color.WHITE)
	_hud.position = Vector3(0, 3.6, 2.2)
	_hud.pixel_size = 0.01
	add_child(_hud)
	_room_result = Label3D.new()
	_room_result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_room_result.position = Vector3(0, 2.9, 2.2)
	_room_result.pixel_size = 0.012
	_room_result.outline_size = 8
	_room_result.modulate = Color(0.6, 1.0, 0.8)
	add_child(_room_result)
	var help := GraphicsPolish.make_label("Left-click 2 points to measure | Right-click / ESC cancels", 40, Color(0.8, 0.85, 1.0))
	help.position = Vector3(0, 0.5, 2.8)
	help.pixel_size = 0.008
	add_child(help)
	_update_hud()


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var point := Vector3.ZERO
	if not hit.is_empty():
		var collider := hit.get("collider") as Object
		if collider is StaticBody3D and _buttons.has(collider):
			_do_button(_buttons[collider] as String)
			return
		point = hit["position"]
	else:
		## Fallback: intersect a plane 4 m in front of the camera.
		var fwd := -_cam.global_transform.basis.z
		var plane := Plane(fwd, from.dot(fwd) + 4.0)
		var p = plane.intersects_ray(from, dir)
		if p == null:
			return
		point = p
	if _mode == Mode.MEASURE:
		_add_measure_point(point)
	else:
		_add_room_corner(point)


func _do_button(action: String) -> void:
	match action:
		"clear":
			_clear_all()
		"room":
			_mode = Mode.ROOM if _mode == Mode.MEASURE else Mode.MEASURE
			_cancel_pending()
			_update_hud()


func _cancel_pending() -> void:
	_pending.clear()
	_room_corners.clear()
	_clear_markers()
	_clear_room_nodes()
	_room_result.text = ""
	_update_hud()


# ---------------------------------------------------------------- measure

func _add_measure_point(p: Vector3) -> void:
	# AR: keep points inside the known room bounds.
	p = ARUpgradeKit.clamp_to_room(p)
	if _measurements.size() >= MAX_MEASUREMENTS:
		_cancel_pending()
		return
	_pending.append(p)
	_add_marker(p, Color(1.0, 0.85, 0.3))
	if _pending.size() == 2:
		_finish_measurement(_pending[0], _pending[1])
		_pending.clear()
		_clear_markers()
	_update_hud()


func _finish_measurement(a: Vector3, b: Vector3) -> void:
	var dist := a.distance_to(b)
	var nodes: Array = []
	nodes.append(_make_line(a, b, Color(1.0, 0.85, 0.3)))
	var label := Label3D.new()
	label.text = "%.2f m" % dist
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = (a + b) * 0.5 + Vector3(0, 0.25, 0)
	label.pixel_size = 0.012
	label.outline_size = 10
	add_child(label)
	nodes.append(label)
	_measurements.append({"a": a, "b": b, "dist": dist, "nodes": nodes})
	GraphicsPolish.spawn_sparks(self, (a + b) * 0.5, Color(1.0, 0.85, 0.3), 20)
	_update_hud()


func _make_line(a: Vector3, b: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var length := a.distance_to(b)
	bm.size = Vector3(LINE_THICK, LINE_THICK, maxf(length, 0.001))
	mi.mesh = bm
	mi.material_override = GraphicsPolish.glow(color, 1.6)
	add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at(b)
	return mi


func _add_marker(p: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	mi.mesh = sm
	mi.material_override = GraphicsPolish.glow(color, 2.0)
	mi.position = p
	add_child(mi)
	_markers.append(mi)


func _clear_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()


# ---------------------------------------------------------------- room mode

func _add_room_corner(p: Vector3) -> void:
	# AR: keep corners inside the known room bounds.
	p = ARUpgradeKit.clamp_to_room(p)
	_room_corners.append(Vector3(p.x, 0.05, p.z))
	_add_marker(_room_corners[_room_corners.size() - 1], Color(0.4, 1.0, 0.6))
	if _room_corners.size() == 4:
		_finish_room()
	_update_hud()


func _finish_room() -> void:
	_clear_room_nodes()
	var c := _room_corners
	var minx := minf(minf(c[0].x, c[1].x), minf(c[2].x, c[3].x))
	var maxx := maxf(maxf(c[0].x, c[1].x), maxf(c[2].x, c[3].x))
	var minz := minf(minf(c[0].z, c[1].z), minf(c[2].z, c[3].z))
	var maxz := maxf(maxf(c[0].z, c[1].z), maxf(c[2].z, c[3].z))
	var width := maxx - minx
	var depth := maxz - minz
	var area := width * depth
	var y := 0.08
	var p1 := Vector3(minx, y, minz)
	var p2 := Vector3(maxx, y, minz)
	var p3 := Vector3(maxx, y, maxz)
	var p4 := Vector3(minx, y, maxz)
	for pair in [[p1, p2], [p2, p3], [p3, p4], [p4, p1]]:
		_room_nodes.append(_make_line(pair[0], pair[1], Color(0.4, 1.0, 0.6)))
	var center := Vector3((minx + maxx) * 0.5, y + 0.4, (minz + maxz) * 0.5)
	var label := Label3D.new()
	label.text = "%.2f m x %.2f m" % [width, depth]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = center
	label.pixel_size = 0.014
	label.outline_size = 10
	add_child(label)
	_room_nodes.append(label)
	_room_result.text = "Room: %.2f m x %.2f m  |  Area: %.2f m^2" % [width, depth, area]
	_room_corners.clear()
	_clear_markers()
	_update_hud()


func _clear_room_nodes() -> void:
	for n in _room_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_room_nodes.clear()


# ---------------------------------------------------------------- misc

func _clear_all() -> void:
	for m in _measurements:
		for n in (m as Dictionary)["nodes"]:
			if is_instance_valid(n):
				(n as Node).queue_free()
	_measurements.clear()
	_cancel_pending()


func _update_hud() -> void:
	if _hud == null:
		return
	var lines: Array[String] = []
	if _mode == Mode.ROOM:
		lines.append("[ROOM MODE] Click 4 floor corners (%d/4)" % _room_corners.size())
	else:
		lines.append("[MEASURE] %d/%d" % [_measurements.size(), MAX_MEASUREMENTS])
	for i in _measurements.size():
		lines.append("%d. %.2f m" % [i + 1, float((_measurements[i] as Dictionary)["dist"])])
	_hud.text = "\n".join(lines)
