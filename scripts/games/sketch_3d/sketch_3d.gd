## sketch_3d.gd - Sketch to 3D: draw on paper, hold it up to the camera (or draw
## on the in-game canvas when no camera is available), and extrude the sketch
## into a rotating 3D relief on a pedestal. Edge map via CameraVision.sobel_edges;
## relief is a 48x48 displaced grid with clay/copper/neon PBR materials and a glow
## rim. Creations persist in user://sketch_gallery (edge PNG + metadata cfg) and
## the gallery wall re-extrudes any saved sketch on selection.
extends Node3D
class_name Sketch3DGame

const GRID := 48 ## quads per side of the relief mesh
const RELIEF_SIZE := 1.6 ## relief width/depth in meters
const RELIEF_HEIGHT := 0.38 ## max extrusion height in meters
const CANVAS_PX := 256 ## drawing canvas resolution
const EDGE_W := 64 ## edge-map width used for extrusion
const EDGE_W_HIRES := 128 ## edge-map width stored in the gallery
const BLANK_THRESHOLD := 0.12 ## min edge brightness to count as a sketch
const GALLERY_DIR := "user://sketch_gallery"
const GALLERY_CFG := "user://sketch_gallery/gallery.cfg"
const ANCHOR_NAME := "sketch_3d_main"
const SPIN_SPEED := 0.55
const SPARKLE_EVERY := 1.4
const STROKE_RADIUS := 5

enum State { INPUT, RESULT }

var _cam: Camera3D = null
var _camera_mode := false
var _state: int = State.INPUT
var _mat_key := "clay"
var _sketch_count := 0
var _save_seq := 0

var _result_root: Node3D = null
var _relief: MeshInstance3D = null
var _rim_nodes: Array[MeshInstance3D] = []
var _result_pop := false

var _easel: Node3D = null
var _canvas_body: StaticBody3D = null
var _canvas_img: Image = null
var _canvas_tex: ImageTexture = null
var _drawing := false
var _last_px := Vector2i(-1, -1)

var _buttons := {} ## StaticBody3D -> String action
var _button_roots := {} ## String action -> Node3D
var _button_bodies := {} ## String action -> StaticBody3D
var _gallery_actions: Array[String] = []

var _title: Label3D = null
var _status: Label3D = null
var _help: Label3D = null

var _current_edges: Image = null
var _current_hires: Image = null
var _current_name := ""

var _gallery: Array = [] ## {ts, seq, name, date, file}
var _gallery_root: Node3D = null
var _gallery_empty_label: Label3D = null

var _anchor_timer := 0.0
var _sparkle_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	_camera_mode = ARCamera.is_available()
	if _camera_mode:
		ARCamera.request_permission()
	_ensure_camera()
	_build_light()
	_build_room()
	_build_pedestal()
	_build_easel()
	_build_buttons()
	_build_hud()
	_build_gallery_wall()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, 0), 3.0, 40)
	_load_gallery()
	_rebuild_gallery_wall()
	_set_state(State.INPUT)


func _process(delta: float) -> void:
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	if _state == State.RESULT and _result_root != null and _result_root.visible:
		_result_root.rotation.y += delta * SPIN_SPEED
		_sparkle_timer += delta
		if _sparkle_timer >= SPARKLE_EVERY:
			_sparkle_timer = 0.0
			GraphicsPolish.spawn_sparks(self, _result_root.global_position + Vector3(0, 0.25, 0), Color(1.0, 0.85, 0.45), 10)
	if _result_pop and _result_root != null:
		GraphicsPolish.ease_scale(_result_root, Vector3.ONE, 6.0, delta)
		if _result_root.scale.distance_to(Vector3.ONE) < 0.02:
			_result_root.scale = Vector3.ONE
			_result_pop = false
	# Hand interaction: right-hand pinch selects buttons / gallery panels.
	# Mouse clicks stay on _unhandled_input; the mouse-press gate keeps the
	# kit's mouse fallback from double-triggering.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		_raycast_click(ray[0], ray[1])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_click(mb.position)
			else:
				_drawing = false
	elif event is InputEventMouseMotion:
		if _drawing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_draw_at_screen((event as InputEventMouseMotion).position)


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
	# Warm accent over the pedestal so the relief reads well.
	GraphicsPolish.make_point_light(self, Vector3(0, 2.8, -0.6), Color(1.0, 0.85, 0.7), 0.9, 5.0)


func _build_room() -> void:
	_add_static_box(Vector3(0, -0.1, 0), Vector3(12, 0.2, 12), Color(0.18, 0.2, 0.26))
	_add_static_box(Vector3(0, 2.5, -6), Vector3(12, 5.0, 0.2), Color(0.22, 0.24, 0.32))
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


func _build_pedestal() -> void:
	var ped_root := Node3D.new()
	ped_root.position = Vector3(0, 0, -0.6)
	add_child(ped_root)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.62
	cm.height = 1.0
	mi.mesh = cm
	mi.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.26, 0.33), "plastic")
	mi.position = Vector3(0, 0.5, 0)
	ped_root.add_child(mi)
	# Glowing ring on the pedestal top.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.035
	tm.outer_radius = 0.52
	ring.mesh = tm
	ring.material_override = GraphicsPolish.glow(Color(1.0, 0.75, 0.35), 1.4)
	ring.position = Vector3(0, 1.01, 0)
	ped_root.add_child(ring)
	# Rotating result group floats above the pedestal.
	_result_root = Node3D.new()
	_result_root.position = Vector3(0, 1.55, -0.6)
	_result_root.visible = false
	add_child(_result_root)
	var plabel := GraphicsPolish.make_label("YOUR SKETCH, IN 3D", 40, Color(1.0, 0.9, 0.6))
	plabel.position = Vector3(0, 2.35, -0.6)
	plabel.pixel_size = 0.008
	add_child(plabel)


func _build_easel() -> void:
	_easel = Node3D.new()
	_easel.position = Vector3(-2.35, 1.35, 0.7)
	_easel.rotation_degrees = Vector3(-6, 20, 0)
	add_child(_easel)
	# Wooden frame behind the canvas.
	var frame := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(1.36, 1.36, 0.06)
	frame.mesh = fbm
	frame.material_override = GraphicsPolish.pbr_preset(Color(0.4, 0.27, 0.16), "matte")
	frame.position = Vector3(0, 0, -0.02)
	_easel.add_child(frame)
	# The drawable canvas.
	_canvas_img = Image.create(CANVAS_PX, CANVAS_PX, false, Image.FORMAT_RGB8)
	_canvas_img.fill(Color.WHITE)
	_canvas_tex = ImageTexture.create_from_image(_canvas_img)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 1.2)
	quad.mesh = qm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_texture = _canvas_tex
	cmat.roughness = 0.9
	quad.material_override = cmat
	_easel.add_child(quad)
	_canvas_body = StaticBody3D.new()
	_easel.add_child(_canvas_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 1.3, 0.12)
	cs.shape = bs
	_canvas_body.add_child(cs)
	var clabel := GraphicsPolish.make_label("DRAW HERE", 40, Color(1, 1, 1))
	clabel.position = Vector3(0, 0.88, 0.05)
	clabel.pixel_size = 0.008
	_easel.add_child(clabel)


func _build_buttons() -> void:
	# INPUT, camera mode.
	_make_button("capture", "CAPTURE & EXTRUDE", Vector3(0, 1.15, 2.8), Color(0.25, 0.75, 0.45), 3.6)
	# INPUT, canvas mode.
	_make_button("extrude", "EXTRUDE", Vector3(-1.3, 1.0, 2.8), Color(0.25, 0.75, 0.45), 2.2)
	_make_button("clear", "Clear", Vector3(1.3, 1.0, 2.8), Color(0.6, 0.65, 0.75), 2.2)
	# RESULT.
	_make_button("recapture", "Recapture", Vector3(-2.5, 1.0, 2.8), Color(0.35, 0.6, 0.95), 2.2)
	_make_button("save", "Save to gallery", Vector3(0, 1.0, 2.8), Color(0.95, 0.7, 0.25), 2.8)
	_make_button("new", "New sketch", Vector3(2.5, 1.0, 2.8), Color(0.85, 0.4, 0.5), 2.2)
	_make_button("mat_clay", "Clay", Vector3(-1.7, 0.32, 2.8), Color(0.72, 0.44, 0.3), 1.5)
	_make_button("mat_copper", "Copper", Vector3(0, 0.32, 2.8), Color(0.75, 0.38, 0.2), 1.7)
	_make_button("mat_neon", "Neon", Vector3(1.7, 0.32, 2.8), Color(0.15, 0.85, 1.0), 1.5)


func _make_button(action: String, text: String, pos: Vector3, color: Color, width: float = 2.2) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.visible = false
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.6, 0.15)
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
	bs.size = Vector3(width, 0.6, 0.15)
	cs.shape = bs
	sb.add_child(cs)
	sb.collision_layer = 0
	var label := GraphicsPolish.make_label(text, 48, Color.WHITE)
	label.position = Vector3(0, 0, 0.1)
	label.pixel_size = 0.011
	root.add_child(label)
	_buttons[sb] = action
	_button_roots[action] = root
	_button_bodies[action] = sb


func _show_buttons(actions: Array) -> void:
	for action in _button_roots:
		var show: bool = action in actions
		(_button_roots[action] as Node3D).visible = show
		(_button_bodies[action] as StaticBody3D).collision_layer = 1 if show else 0


func _build_hud() -> void:
	_title = GraphicsPolish.make_label("SKETCH TO 3D", 72, Color(1.0, 0.9, 0.6))
	_title.position = Vector3(0, 3.5, 1.8)
	_title.pixel_size = 0.01
	add_child(_title)
	_status = GraphicsPolish.make_label("", 44, Color(0.85, 0.95, 1.0))
	_status.position = Vector3(0, 2.95, 1.8)
	_status.pixel_size = 0.008
	add_child(_status)
	_help = GraphicsPolish.make_label("", 40, Color(0.75, 0.8, 0.9))
	_help.position = Vector3(0, 0.42, 2.8)
	_help.pixel_size = 0.008
	add_child(_help)


func _build_gallery_wall() -> void:
	_gallery_root = Node3D.new()
	add_child(_gallery_root)
	var gtitle := GraphicsPolish.make_label("GALLERY - click a frame to re-extrude", 40, Color(1.0, 0.9, 0.6))
	gtitle.position = Vector3(2.4, 2.35, -2.2)
	gtitle.pixel_size = 0.008
	add_child(gtitle)


# ---------------------------------------------------------------- state

func _set_state(s: int) -> void:
	_state = s
	if s == State.INPUT:
		_result_root.visible = false
		if _camera_mode:
			_show_buttons(["capture"])
			_set_canvas_visible(false)
			_help.text = "Draw with a dark marker, hold the paper up to the camera, then CAPTURE & EXTRUDE (or pinch)."
			_set_status("Ready — show the camera your sketch.")
		else:
			_show_buttons(["extrude", "clear"])
			_set_canvas_visible(true)
			_help.text = "Draw on the canvas with the mouse, then press EXTRUDE."
			_set_status("Ready — draw something on the canvas.")
	else:
		_show_buttons(["recapture", "save", "new", "mat_clay", "mat_copper", "mat_neon"])
		_set_canvas_visible(false)
		_result_root.visible = true
		_result_root.scale = Vector3(0.05, 0.05, 0.05)
		_result_pop = true
		_sparkle_timer = 0.0
		_help.text = "Pick a material, save it to the gallery, or start a new sketch."


func _set_canvas_visible(v: bool) -> void:
	_easel.visible = v
	_canvas_body.collision_layer = 1 if v else 0


func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	_raycast_click(_cam.project_ray_origin(screen_pos), _cam.project_ray_normal(screen_pos))


func _raycast_click(origin: Vector3, dir: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider is StaticBody3D and _buttons.has(collider):
		Haptics.tick()
		_do_action(String(_buttons[collider]))
		return
	if _state == State.INPUT and not _camera_mode and collider == _canvas_body:
		_drawing = true
		_last_px = Vector2i(-1, -1)
		_stamp_canvas(hit["position"])


func _draw_at_screen(screen_pos: Vector2) -> void:
	if _cam == null or _state != State.INPUT or _camera_mode:
		_drawing = false
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if (hit.get("collider") as Object) == _canvas_body:
		_stamp_canvas(hit["position"])


func _do_action(action: String) -> void:
	if action.begins_with("gallery_"):
		_load_gallery_entry(action)
		return
	match action:
		"capture":
			_capture_and_extrude()
		"extrude":
			_extrude_canvas()
		"clear":
			_clear_canvas()
		"recapture":
			_set_state(State.INPUT)
		"new":
			_clear_canvas()
			_set_state(State.INPUT)
		"save":
			_save_current()
		"mat_clay":
			_set_material("clay")
		"mat_copper":
			_set_material("copper")
		"mat_neon":
			_set_material("neon")


# ---------------------------------------------------------------- canvas drawing

func _stamp_canvas(world_pos: Vector3) -> void:
	var local: Vector3 = _easel.to_local(world_pos)
	var u := local.x / 1.2 + 0.5
	var v := 0.5 - local.y / 1.2
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return
	var px := Vector2i(clampi(int(u * CANVAS_PX), 0, CANVAS_PX - 1), clampi(int(v * CANVAS_PX), 0, CANVAS_PX - 1))
	if _last_px.x >= 0:
		var a := Vector2(_last_px)
		var b := Vector2(px)
		var steps := maxi(int(a.distance_to(b) / 3.0), 1)
		for i in range(steps + 1):
			_stamp_dot(Vector2i((a.lerp(b, float(i) / float(steps))).round()))
	else:
		_stamp_dot(px)
	_last_px = px
	_canvas_tex.update(_canvas_img)


func _stamp_dot(p: Vector2i) -> void:
	var ink := Color(0.08, 0.08, 0.1)
	for dy in range(-STROKE_RADIUS, STROKE_RADIUS + 1):
		for dx in range(-STROKE_RADIUS, STROKE_RADIUS + 1):
			if dx * dx + dy * dy <= STROKE_RADIUS * STROKE_RADIUS:
				var q := p + Vector2i(dx, dy)
				if q.x >= 0 and q.x < CANVAS_PX and q.y >= 0 and q.y < CANVAS_PX:
					_canvas_img.set_pixel(q.x, q.y, ink)


func _clear_canvas() -> void:
	_canvas_img.fill(Color.WHITE)
	_canvas_tex.update(_canvas_img)
	_last_px = Vector2i(-1, -1)
	_set_status("Canvas cleared — draw something new.")


# ---------------------------------------------------------------- extrude pipeline

func _capture_and_extrude() -> void:
	Haptics.pulse(0.8, 0.15)
	if not ARCamera.is_available():
		_set_status("Camera unavailable — draw on the canvas instead.")
		_camera_mode = false
		_set_state(State.INPUT)
		return
	var img := ARCamera.capture()
	if img == null or img.is_empty():
		_set_status("Capture failed — hold the paper steady and try again.")
		return
	var edges := CameraVision.sobel_edges(img, EDGE_W)
	if _edge_peak(edges) < BLANK_THRESHOLD:
		_set_status("Nothing detected — draw bolder lines and try again.")
		return
	_sketch_count += 1
	_extrude(edges, CameraVision.sobel_edges(img, EDGE_W_HIRES), "Sketch %d" % _sketch_count)


func _extrude_canvas() -> void:
	Haptics.pulse(0.8, 0.15)
	var edges := CameraVision.sobel_edges(_canvas_img, EDGE_W)
	if _edge_peak(edges) < BLANK_THRESHOLD:
		_set_status("Canvas looks blank — draw something first!")
		Haptics.tick()
		return
	_sketch_count += 1
	_extrude(edges, CameraVision.sobel_edges(_canvas_img, EDGE_W_HIRES), "Sketch %d" % _sketch_count)


func _edge_peak(edges: Image) -> float:
	var peak := 0.0
	var w := edges.get_width()
	var h := edges.get_height()
	for y in h:
		for x in w:
			peak = maxf(peak, edges.get_pixel(x, y).r)
	return peak


func _extrude(edges: Image, hires: Image, sketch_name: String) -> void:
	_current_edges = edges
	_current_hires = hires
	_current_name = sketch_name
	if _relief == null:
		_relief = MeshInstance3D.new()
		_result_root.add_child(_relief)
	_relief.mesh = _build_relief_mesh(edges)
	_apply_material()
	_build_rim()
	_set_state(State.RESULT)
	_set_status("Extruded '%s' — pick a material, save it, or start a new sketch." % sketch_name)
	GraphicsPolish.spawn_confetti(self, _result_root.global_position + Vector3(0, 0.6, 0), 50)
	Haptics.thump()


func _build_relief_mesh(edges: Image) -> ArrayMesh:
	var w := edges.get_width()
	var h := edges.get_height()
	var n := GRID + 1
	var step := RELIEF_SIZE / float(GRID)
	# Heightfield from edge brightness: edges rise, background stays flat.
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for gy in n:
		var py := clampi(int(round(float(gy) / float(GRID) * float(h - 1))), 0, h - 1)
		for gx in n:
			var px := clampi(int(round(float(gx) / float(GRID) * float(w - 1))), 0, w - 1)
			heights[gy * n + gx] = edges.get_pixel(px, py).r * RELIEF_HEIGHT
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	for gy in n:
		for gx in n:
			var i := gy * n + gx
			var x := (float(gx) / float(GRID) - 0.5) * RELIEF_SIZE
			var z := (float(gy) / float(GRID) - 0.5) * RELIEF_SIZE
			verts[i] = Vector3(x, heights[i], z)
			uvs[i] = Vector2(float(gx) / float(GRID), float(gy) / float(GRID))
			# Analytic heightfield normals: n = normalize(-dh/dx, 1, -dh/dz).
			var x0 := maxi(gx - 1, 0)
			var x1 := mini(gx + 1, GRID)
			var z0 := maxi(gy - 1, 0)
			var z1 := mini(gy + 1, GRID)
			var dhdx := (heights[gy * n + x1] - heights[gy * n + x0]) / (float(x1 - x0) * step)
			var dhdz := (heights[z1 * n + gx] - heights[z0 * n + gx]) / (float(z1 - z0) * step)
			normals[i] = Vector3(-dhdx, 1.0, -dhdz).normalized()
	var idx := PackedInt32Array()
	for gy in GRID:
		for gx in GRID:
			var a := gy * n + gx
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _relief_material() -> StandardMaterial3D:
	match _mat_key:
		"copper":
			var m := GraphicsPolish.pbr(Color(0.75, 0.38, 0.2), 0.95, 0.3)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"neon":
			var m := GraphicsPolish.pbr(Color(0.15, 0.85, 1.0), 0.2, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.15, 0.85, 1.0)
			m.emission_energy_multiplier = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		_:
			var m := GraphicsPolish.pbr(Color(0.72, 0.44, 0.3), 0.05, 0.85)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m


func _rim_tint() -> Color:
	match _mat_key:
		"copper":
			return Color(1.0, 0.55, 0.25)
		"neon":
			return Color(0.2, 0.95, 1.0)
		_:
			return Color(1.0, 0.72, 0.35)


func _apply_material() -> void:
	if _relief != null:
		_relief.material_override = _relief_material()


func _set_material(key: String) -> void:
	_mat_key = key
	_apply_material()
	_build_rim()
	Haptics.tick()
	_set_status("Material: %s — '%s' on the pedestal." % [key.capitalize(), _current_name])


func _build_rim() -> void:
	for r in _rim_nodes:
		if is_instance_valid(r):
			r.queue_free()
	_rim_nodes.clear()
	var tint := _rim_tint()
	var half := RELIEF_SIZE * 0.5 + 0.06
	var thick := 0.07
	for side in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		if side < 2:
			bm.size = Vector3(RELIEF_SIZE + thick * 2.0, thick, thick)
			mi.position = Vector3(0, 0.02, half if side == 0 else -half)
		else:
			bm.size = Vector3(thick, thick, RELIEF_SIZE + thick * 2.0)
			mi.position = Vector3(half if side == 2 else -half, 0.02, 0)
		mi.mesh = bm
		mi.material_override = GraphicsPolish.glow(tint, 1.5)
		_result_root.add_child(mi)
		_rim_nodes.append(mi)


# ---------------------------------------------------------------- gallery

func _save_current() -> void:
	if _current_hires == null:
		_set_status("Nothing to save yet — extrude a sketch first.")
		return
	DirAccess.make_dir_recursive_absolute(GALLERY_DIR)
	_save_seq += 1
	var ts := int(Time.get_unix_time_from_system())
	var fname := "%d_%d.png" % [ts, _save_seq]
	if _current_hires.save_png(GALLERY_DIR + "/" + fname) != OK:
		_set_status("Save failed — storage unavailable.")
		return
	var cfg := ConfigFile.new()
	cfg.load(GALLERY_CFG) # ignore errors; missing file is fine
	var section := "entry_%d_%d" % [ts, _save_seq]
	cfg.set_value(section, "ts", ts)
	cfg.set_value(section, "seq", _save_seq)
	cfg.set_value(section, "name", _current_name)
	cfg.set_value(section, "date", Time.get_datetime_string_from_system())
	cfg.set_value(section, "file", fname)
	cfg.save(GALLERY_CFG)
	_load_gallery()
	_rebuild_gallery_wall()
	_set_status("Saved '%s' to the gallery wall." % _current_name)
	GraphicsPolish.spawn_confetti(self, Vector3(2.4, 1.7, -2.0), 40)
	Haptics.pulse(0.6, 0.12)


func _load_gallery() -> void:
	_gallery.clear()
	var cfg := ConfigFile.new()
	if cfg.load(GALLERY_CFG) != OK:
		return
	for section in cfg.get_sections():
		if not section.begins_with("entry_"):
			continue
		_gallery.append({
			"ts": int(cfg.get_value(section, "ts", 0)),
			"seq": int(cfg.get_value(section, "seq", 0)),
			"name": String(cfg.get_value(section, "name", "Sketch")),
			"date": String(cfg.get_value(section, "date", "")),
			"file": String(cfg.get_value(section, "file", "")),
		})
	_gallery.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["ts"]) > int(b["ts"]))


func _rebuild_gallery_wall() -> void:
	for action in _gallery_actions:
		var old_body: Object = _button_bodies.get(action)
		if old_body != null:
			_buttons.erase(old_body)
		_button_bodies.erase(action)
	_gallery_actions.clear()
	for child in _gallery_root.get_children():
		child.queue_free()
	_gallery_empty_label = null
	if _gallery.is_empty():
		_gallery_empty_label = GraphicsPolish.make_label("Gallery is empty — save your first sketch!", 40, Color(0.7, 0.75, 0.85))
		_gallery_empty_label.position = Vector3(2.4, 1.5, -2.2)
		_gallery_empty_label.pixel_size = 0.008
		_gallery_root.add_child(_gallery_empty_label)
		return
	var shown := mini(_gallery.size(), 5)
	for i in shown:
		var e: Dictionary = _gallery[i]
		var img := Image.load_from_file(GALLERY_DIR + "/" + String(e["file"]))
		if img == null or img.is_empty():
			continue
		var x := 2.4 + (float(i) - float(shown - 1) * 0.5) * 0.68
		_make_gallery_panel(e, img, Vector3(x, 1.5, -2.2))


func _make_gallery_panel(e: Dictionary, img: Image, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	_gallery_root.add_child(root)
	var frame := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(0.58, 0.58, 0.05)
	frame.mesh = fbm
	frame.material_override = GraphicsPolish.pbr_preset(Color(0.3, 0.28, 0.24), "plastic")
	root.add_child(frame)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	quad.mesh = qm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_texture = ImageTexture.create_from_image(img)
	tmat.roughness = 0.9
	quad.material_override = tmat
	quad.position = Vector3(0, 0, 0.03)
	root.add_child(quad)
	var nlabel := GraphicsPolish.make_label(String(e["name"]), 32, Color(1, 1, 1))
	nlabel.position = Vector3(0, -0.42, 0.03)
	nlabel.pixel_size = 0.006
	root.add_child(nlabel)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.58, 0.58, 0.1)
	cs.shape = bs
	sb.add_child(cs)
	var action := "gallery_%d_%d" % [int(e["ts"]), int(e["seq"])]
	_buttons[sb] = action
	_button_bodies[action] = sb
	_gallery_actions.append(action)


func _load_gallery_entry(action: String) -> void:
	var parts := action.trim_prefix("gallery_").split("_")
	if parts.size() < 2:
		return
	var want_ts := int(parts[0])
	var want_seq := int(parts[1])
	for e in _gallery:
		var d: Dictionary = e
		if int(d["ts"]) == want_ts and int(d["seq"]) == want_seq:
			var img := Image.load_from_file(GALLERY_DIR + "/" + String(d["file"]))
			if img == null or img.is_empty():
				_set_status("Could not load '%s'." % String(d["name"]))
				return
			Haptics.pulse(0.7, 0.12)
			_extrude(img, img, String(d["name"]))
			return
	_set_status("Gallery entry not found.")
