## Clay Shaper: hand-sculpted clay modeling toy.
## A terracotta clay blob floats anchored in the room on a glowing pedestal.
## Hold pinch (left mouse on desktop) to sculpt where you point: push dents the
## surface inward, smooth relaxes it back toward the original blob, spike pulls
## it outward. Right mouse (left-hand pinch) or T cycles tools. In XR, pinching
## with BOTH hands stretches the whole blob along the axis between your hands;
## holding both pinches for 3s saves the sculpture to a spatial anchor.
## Score = style points earned from total deformation. R resets the clay.
extends Node3D

const SCULPT_RADIUS := 0.32
const PUSH_RATE := 0.35
const SMOOTH_RATE := 2.5
const SPIKE_RATE := 0.30
const STRETCH_RATE := 0.45
const SAVE_HOLD := 3.0
const MOUSE_RAY_PLANE_Y := 1.35

var camera: Camera3D = null
var clay: MeshInstance3D = null
var clay_mesh: ArrayMesh = null
var mesh_template: Array = []
var base_verts: PackedVector3Array = PackedVector3Array()
var base_normals: PackedVector3Array = PackedVector3Array()
var offsets: PackedVector3Array = PackedVector3Array()
var tool_names: Array[String] = ["push", "smooth", "spike"]
var tool_idx := 0
var style_points := 0.0
var both_pinch_t := 0.0
var msg_t := 0.0
var _anchor_t := 0.0
var _pulse_t := 0.0
var ring_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var tool_label: Label3D = null
var msg_label: Label3D = null
var mouse_pos := Vector2.ZERO


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "clay-shaper_main")
	_ensure_fallback_camera()
	_ensure_light()
	_ensure_environment()
	_build_pedestal()
	_build_clay()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.3, 0.0), 2.5, 40)


func _process(delta: float) -> void:
	_pulse_t += delta
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("clay-shaper_main", global_transform)
	if ring_mat != null:
		GraphicsPolish.pulse_glow(ring_mat, 1.2, 0.9, _pulse_t, 2.0)
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0 and msg_label != null:
			msg_label.text = ""

	var xr := ARUpgradeKit.is_xr_active()
	var right_pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var left_pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)

	if xr and right_pinch and left_pinch:
		# Two-hand gesture: stretch the whole blob along the hand axis.
		_stretch_between_hands(delta)
		both_pinch_t += delta
		if both_pinch_t >= SAVE_HOLD:
			both_pinch_t = 0.0
			ARUpgradeKit.save_anchor("clay-shaper_main", global_transform)
			_show_msg("Sculpture saved!")
			GraphicsPolish.spawn_sparks(self, clay.global_position, Color(0.4, 1.0, 0.6), 24)
	else:
		both_pinch_t = 0.0
		if right_pinch:
			var lp := _sculpt_point(xr)
			_sculpt(lp, delta)

	# Tool cycle: left-hand pinch edge (right mouse button on desktop).
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
		_cycle_tool()
	if Input.is_key_pressed(KEY_R):
		_reset_clay()

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pass # Sculpting reads pinch state in _process.
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cycle_tool()
	elif event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_T:
				_cycle_tool()
			elif ke.keycode == KEY_S:
				ARUpgradeKit.save_anchor("clay-shaper_main", global_transform)
				_show_msg("Sculpture saved!")


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 2.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, -0.4), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _ensure_environment() -> void:
	for c in get_children():
		if c is WorldEnvironment:
			return
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.38)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _build_pedestal() -> void:
	var stand := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.42
	cyl.height = 0.72
	stand.mesh = cyl
	stand.material_override = GraphicsPolish.pbr(Color(0.12, 0.13, 0.18), 0.2, 0.6)
	stand.position = Vector3(0.0, 0.36, -0.4)
	add_child(stand)
	# Glowing ring around the pedestal base.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.46
	ring.mesh = torus
	ring_mat = GraphicsPolish.glow(Color(1.0, 0.55, 0.2), 1.4)
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.04, -0.4)
	add_child(ring)


func _build_clay() -> void:
	var proto := SphereMesh.new()
	proto.radial_segments = 40
	proto.rings = 20
	proto.radius = 0.55
	proto.height = 1.1
	var arr: Array = proto.surface_get_arrays(0)
	mesh_template = arr.duplicate()
	base_verts = arr[Mesh.ARRAY_VERTEX]
	base_normals = arr[Mesh.ARRAY_NORMAL]
	offsets = PackedVector3Array()
	offsets.resize(base_verts.size())
	clay_mesh = ArrayMesh.new()
	_rebuild_mesh()
	clay = MeshInstance3D.new()
	clay.mesh = clay_mesh
	clay.material_override = GraphicsPolish.pbr(Color(0.82, 0.44, 0.24), 0.0, 0.85)
	clay.position = Vector3(0.0, 1.35, -0.4)
	add_child(clay)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.85, 0.55))
	hud_label.position = Vector3(-2.2, 2.4, -0.8)
	hud_label.pixel_size = 0.008
	add_child(hud_label)
	tool_label = GraphicsPolish.make_label("", 48, Color(0.7, 0.9, 1.0))
	tool_label.position = Vector3(-2.2, 2.1, -0.8)
	tool_label.pixel_size = 0.006
	add_child(tool_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.5, 1.0, 0.6))
	msg_label.position = Vector3(0.0, 2.1, -0.6)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("Hold LMB / pinch to sculpt | RMB or T: tool | Both-hands pinch: stretch (hold 3s: save) | S: save | R: reset", 36, Color(0.75, 0.8, 0.9))
	help.position = Vector3(0.0, 0.55, 0.6)
	help.pixel_size = 0.004
	add_child(help)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Style points: %d" % int(style_points)
	if tool_label != null:
		tool_label.text = "Tool: %s" % tool_names[tool_idx]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text
	msg_t = 2.5


func _cycle_tool() -> void:
	tool_idx = (tool_idx + 1) % tool_names.size()
	_show_msg("Tool: %s" % tool_names[tool_idx])
	if clay != null:
		GraphicsPolish.spawn_sparks(self, clay.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.7, 0.3), 10)


func _reset_clay() -> void:
	for i in range(offsets.size()):
		offsets[i] = Vector3.ZERO
	if clay != null:
		clay.scale = Vector3.ONE
		_rebuild_mesh()
	style_points = 0.0
	_show_msg("Clay reset")


func _sculpt_point(xr: bool) -> Vector3:
	# Where the sculpting tool touches the clay, in clay-local space.
	if xr:
		return clay.to_local(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.6))
	var gp := _mouse_clay_point()
	return clay.to_local(gp)


func _mouse_clay_point() -> Vector3:
	# Cast the mouse ray; hit the clay sphere, or fall back to the closest
	# surface point on the ray.
	if camera == null:
		return clay.global_position + Vector3(0, 0.55, 0)
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var r := 0.55 * maxf(maxf(clay.scale.x, clay.scale.y), clay.scale.z)
	return _ray_sphere(origin, dir, clay.global_position, r)


func _ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> Vector3:
	var oc: Vector3 = origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		var t := maxf(-b, 0.0)
		var p: Vector3 = origin + dir * t
		var n: Vector3 = p - center
		if n.length() < 0.0001:
			n = Vector3.UP
		return center + n.normalized() * radius
	var thit := -b - sqrt(disc)
	return origin + dir * maxf(thit, 0.0)


func _stretch_between_hands(delta: float) -> void:
	var p1 := clay.to_local(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.6))
	var p2 := clay.to_local(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_LEFT, 1.6))
	var axis: Vector3 = p2 - p1
	if axis.length() < 0.05:
		return
	axis = axis.normalized()
	var ns: Vector3 = clay.scale + axis * STRETCH_RATE * delta
	clay.scale = Vector3(clampf(ns.x, 0.4, 2.2), clampf(ns.y, 0.4, 2.2), clampf(ns.z, 0.4, 2.2))
	style_points += STRETCH_RATE * delta * 120.0


func _sculpt(local_point: Vector3, delta: float) -> void:
	var tool: String = tool_names[tool_idx]
	var moved := false
	for i in range(base_verts.size()):
		var v: Vector3 = base_verts[i] + offsets[i]
		var d := v.distance_to(local_point)
		if d < SCULPT_RADIUS:
			var fall := 1.0 - d / SCULPT_RADIUS
			fall = fall * fall
			match tool:
				"push":
					var push: Vector3 = -base_normals[i] * PUSH_RATE * fall * delta
					offsets[i] += push
					style_points += push.length() * 400.0
					moved = true
				"spike":
					var spike: Vector3 = base_normals[i] * SPIKE_RATE * fall * delta
					offsets[i] += spike
					style_points += spike.length() * 400.0
					moved = true
				"smooth":
					var before: Vector3 = offsets[i]
					offsets[i] = offsets[i].lerp(Vector3.ZERO, clampf(SMOOTH_RATE * fall * delta, 0.0, 1.0))
					style_points += before.distance_to(offsets[i]) * 200.0
					moved = true
	if moved:
		_rebuild_mesh()


func _rebuild_mesh() -> void:
	var verts := PackedVector3Array()
	verts.resize(base_verts.size())
	for i in range(base_verts.size()):
		verts[i] = base_verts[i] + offsets[i]
	var a: Array = mesh_template.duplicate()
	a[Mesh.ARRAY_VERTEX] = verts
	clay_mesh.clear_surfaces()
	clay_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
