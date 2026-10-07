## zero_g_sandbox.gd - Zero-g physics playground.
## Spawn 8 physics objects, grab and fling them with the mouse,
## toggle gravity, spawn more, reset. Collision flashes tint objects.
extends Node3D
class_name ZeroGSandboxGame

const MAX_OBJECTS := 24
const GRAB_PLANE_OFFSET := 0.0
const FLING_SCALE := 1.6
const FLASH_TIME := 0.25

var _cam: Camera3D = null
var _bodies: Array[RigidBody3D] = []
var _grabbed: RigidBody3D = null
var _drag_target := Vector3.ZERO
var _drag_velocity := Vector3.ZERO
var _dragging := false
var _zero_g := false
var _flash := {} ## body -> [time_left, base_color]
var _hud: Label3D = null
var _button_actions := {} ## StaticBody3D -> String
var _rng := RandomNumberGenerator.new()
var _anchor_timer := 0.0

# v0.7.0 roomscale: room layout cache (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _ready() -> void:
	_rng.randomize()
	_ensure_camera()
	_build_light()
	_build_floor()
	for i in 8:
		_spawn_object()
	_build_buttons()
	_build_hud()
	_update_hud()
	# AR: restore the saved room anchor in XR; drifting dust motes suit zero-g.
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.apply_anchor(self, "zero-g-sandbox_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 2.5, 0), 3.0, 50)
	_apply_room_layout()


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the TV becomes the scifi mission-briefing screen for the sandbox.
	var _morph_tv := RoomKit.get_anchors("TV")
	if not _morph_tv.is_empty():
		RoomKit.morph(_morph_tv[0], "scifi")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	var bx := _room_bounds.position.x
	var bz := _room_bounds.position.y
	var sx := _room_bounds.size.x
	var sz := _room_bounds.size.y
	# Pull any out-of-bounds bodies back into the real room footprint.
	for b in _bodies:
		if is_instance_valid(b):
			var p: Vector3 = (b as RigidBody3D).global_position
			p.x = clampf(p.x, bx + 0.5, bx + sx - 0.5)
			p.z = clampf(p.z, bz + 0.5, bz + sz - 0.5)
			(b as RigidBody3D).global_position = p
	# Keep the button row + HUD inside the room.
	var zrow := clampf(-3.5, bz + 0.8, bz + sz - 0.8)
	for child in get_children():
		var n3 := child as Node3D
		if n3 != null and n3.name.begins_with("Btn_"):
			n3.position = Vector3(
				clampf(n3.position.x, bx + 1.0, bx + sx - 1.0), n3.position.y, zrow)
	if _hud != null:
		_hud.position = Vector3(bx + sx * 0.5, 4.6, zrow)


func _process(delta: float) -> void:
	_update_anchor_timer(delta)
	# XR pinch: grab/fling bodies and press buttons via the pointer ray.
	if ARUpgradeKit.is_xr_active():
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			_xr_grab()
		elif _dragging and not ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_release_grab()
		if _dragging and is_instance_valid(_grabbed):
			_drag_target = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.5)
	if _dragging and is_instance_valid(_grabbed):
		var prev := _grabbed.global_position
		_grabbed.global_position = _grabbed.global_position.lerp(_drag_target, 0.4)
		if delta > 0.0:
			var v := (_grabbed.global_position - prev) / delta
			_drag_velocity = _drag_velocity.lerp(v, 0.5)
	_update_flashes(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_click(mb.position)
			else:
				_release_grab()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and _cam != null:
			_drag_target = _plane_point(mm.position)


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- build

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 5.5, 9.5)
	_cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light() -> void:
	_add_polish_light_rig()
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.8
	amb.environment = env
	add_child(amb)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	mi.mesh = pm
	mi.material_override = GraphicsPolish.pbr(Color(0.16, 0.18, 0.24), 0.0, 0.9)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	body.add_child(cs)


func _spawn_object() -> void:
	if _bodies.size() >= MAX_OBJECTS:
		return
	var is_box := _rng.randf() > 0.5
	var size := _rng.randf_range(0.35, 0.7)
	var rb := RigidBody3D.new()
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	add_child(rb)
	var mi := MeshInstance3D.new()
	var base := Color(_rng.randf_range(0.3, 1.0), _rng.randf_range(0.3, 1.0), _rng.randf_range(0.3, 1.0))
	mi.material_override = GraphicsPolish.pbr(base, 0.15, 0.5)
	var cs := CollisionShape3D.new()
	if is_box:
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size, size)
		mi.mesh = bm
		var bs := BoxShape3D.new()
		bs.size = Vector3(size, size, size)
		cs.shape = bs
	else:
		var sm := SphereMesh.new()
		sm.radius = size * 0.5
		sm.height = size
		mi.mesh = sm
		var ss := SphereShape3D.new()
		ss.radius = size * 0.5
		cs.shape = ss
	rb.add_child(mi)
	rb.add_child(cs)
	# Spawn inside the real room footprint when roomscale data is available.
	var spawn_x := _rng.randf_range(_room_bounds.position.x + 0.6,
		_room_bounds.position.x + _room_bounds.size.x - 0.6)
	var spawn_z := _rng.randf_range(_room_bounds.position.y + 0.6,
		_room_bounds.position.y + _room_bounds.size.y - 0.6)
	rb.position = Vector3(spawn_x, _rng.randf_range(2.0, 5.0), spawn_z)
	rb.set_meta("mesh", mi)
	rb.set_meta("base_color", base)
	rb.gravity_scale = 0.0 if _zero_g else 1.0
	if _zero_g:
		rb.apply_central_impulse(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.4), _rng.randf_range(-0.4, 0.4)) * rb.mass)
	rb.body_entered.connect(_on_body_hit.bind(rb))
	_bodies.append(rb)
	_update_hud()


func _build_buttons() -> void:
	_make_button("zero_g", "Zero-G", Vector3(-2.2, 2.4, -3.5), Color(0.2, 0.6, 0.9))
	_make_button("spawn", "Spawn", Vector3(0.0, 2.4, -3.5), Color(0.3, 0.8, 0.4))
	_make_button("reset", "Reset", Vector3(2.2, 2.4, -3.5), Color(0.9, 0.45, 0.2))


func _make_button(action: String, text: String, pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = "Btn_" + action
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 0.15)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr(color, 0.2, 0.4)
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.6, 0.15)
	cs.shape = bs
	sb.add_child(cs)
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(0, 0, 0.1)
	label.pixel_size = 0.012
	label.outline_size = 8
	root.add_child(label)
	_button_actions[sb] = action


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.position = Vector3(0, 4.6, -3.5)
	_hud.pixel_size = 0.012
	_hud.outline_size = 8
	add_child(_hud)
	var help := Label3D.new()
	help.text = "Click-drag an object to grab & fling it"
	help.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help.position = Vector3(0, 3.9, -3.5)
	help.pixel_size = 0.009
	help.modulate = Color(0.8, 0.85, 1.0)
	add_child(help)


func _update_hud() -> void:
	if _hud == null:
		return
	var g := "ZERO-G" if _zero_g else "NORMAL"
	_hud.text = "Objects: %d / %d   Gravity: %s" % [_bodies.size(), MAX_OBJECTS, g]


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var hit := _ray_pick(screen_pos)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D and _button_actions.has(collider):
		_do_button(_button_actions[collider] as String)
		return
	if collider is RigidBody3D:
		var rb := collider as RigidBody3D
		if _bodies.has(rb):
			_grabbed = rb
			_grabbed.freeze = true
			_drag_target = _grabbed.global_position
			_drag_velocity = Vector3.ZERO
			_dragging = true


func _xr_grab() -> void:
	# XR alternative to _on_click: pinch grabs a body (or presses a button)
	# via the pointer ray. Desktop keeps the mouse path.
	if _cam == null:
		return
	var pr := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var from: Vector3 = pr[0]
	var dir: Vector3 = pr[1]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D and _button_actions.has(collider):
		_do_button(_button_actions[collider] as String)
		return
	if collider is RigidBody3D and _bodies.has(collider):
		_grabbed = collider as RigidBody3D
		_grabbed.freeze = true
		_drag_target = _grabbed.global_position
		_drag_velocity = Vector3.ZERO
		_dragging = true


func _release_grab() -> void:
	if not _dragging:
		return
	_dragging = false
	if is_instance_valid(_grabbed):
		_grabbed.freeze = false
		var v := _drag_velocity.limit_length(12.0)
		_grabbed.apply_central_impulse(v * _grabbed.mass * FLING_SCALE)
	_grabbed = null


func _ray_pick(screen_pos: Vector2) -> Dictionary:
	var from := _cam.project_ray_origin(screen_pos)
	var to := from + _cam.project_ray_normal(screen_pos) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _plane_point(screen_pos: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, _grabbed.global_position.y + GRAB_PLANE_OFFSET)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return _drag_target
	return hit


func _do_button(action: String) -> void:
	match action:
		"zero_g":
			_zero_g = not _zero_g
			for b in _bodies:
				if is_instance_valid(b):
					b.gravity_scale = 0.0 if _zero_g else 1.0
					if _zero_g:
						b.apply_central_impulse(Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.3, 0.5), _rng.randf_range(-0.6, 0.6)) * b.mass)
		"spawn":
			_spawn_object()
		"reset":
			_release_grab()
			for b in _bodies:
				if is_instance_valid(b):
					b.queue_free()
			_bodies.clear()
			_flash.clear()
			_zero_g = false
			for i in 8:
				_spawn_object()
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.save_anchor("zero-g-sandbox_main", global_transform)
	_update_hud()


# ---------------------------------------------------------------- fx

func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active():
			ARUpgradeKit.save_anchor("zero-g-sandbox_main", global_transform)

func _on_body_hit(_other: Node, body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	var mi := body.get_meta("mesh") as MeshInstance3D
	if mi == null:
		return
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		return
	var base := body.get_meta("base_color") as Color
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5)
	GraphicsPolish.spawn_sparks(self, body.global_position, Color(1.0, 0.9, 0.5), 16)
	_flash[body] = [FLASH_TIME, base]


func _update_flashes(delta: float) -> void:
	var done: Array = []
	for body in _flash.keys():
		if not is_instance_valid(body):
			done.append(body)
			continue
		var entry: Array = _flash[body]
		entry[0] = float(entry[0]) - delta
		if float(entry[0]) <= 0.0:
			var mi := (body as RigidBody3D).get_meta("mesh") as MeshInstance3D
			if mi != null:
				var mat := mi.material_override as StandardMaterial3D
				if mat != null:
					mat.albedo_color = entry[1] as Color
					mat.emission_enabled = false
			done.append(body)
	for body in done:
		_flash.erase(body)
