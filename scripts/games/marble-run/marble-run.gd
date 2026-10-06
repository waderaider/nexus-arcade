## Marble Run: build marble tracks on room geometry.
## A parts palette (ramp, curve, funnel, booster, goal) floats at the side.
## Desktop: keys 1-5 select a part type, click the floor to place it snapped to
## the floor. XR: left-hand pinch cycles the part type, right-hand pinch places
## the part at the pointer position (snapped to floor). Click the big release
## button or press Space to drop a marble from the start pad; parts steer it
## with simple physics. Reach the goal funnel to score 100 + 15 per part used.
## R resets the marble. Layout persists: one anchor per part (marble-run_part_<i>).
extends Node3D

const PART_TYPES := ["ramp", "curve", "funnel", "booster", "goal"]
const PART_COLORS := [Color(0.2, 0.8, 1.0), Color(1.0, 0.6, 0.2), Color(0.7, 0.3, 1.0), Color(1.0, 0.25, 0.3), Color(0.3, 1.0, 0.45)]
const MARBLE_R := 0.11
const START_POS := Vector3(0.0, 0.45, 2.3)
const START_VEL := Vector3(0.0, 0.0, -2.6)
const EFFECT_RADIUS := 1.0
const MAX_PARTS := 30

var camera: Camera3D = null
var selected_type := 0
var parts: Array = []
var part_meshes: Array = []
var palette_nodes: Array = []
var palette_ring: MeshInstance3D = null
var release_button: MeshInstance3D = null
var release_mat: StandardMaterial3D = null
var marble: MeshInstance3D = null
var marble_vel := Vector3.ZERO
var marble_rolling := false
var goal_mat: StandardMaterial3D = null
var score := 0
var best := 0
var state := "build"
var msg := ""
var msg_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var pulse_t := 0.0


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "marble-run_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_build_floor()
	_build_palette()
	_build_release_button()
	_build_marble()
	_restore_layout()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 2.5, 30)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 4.4, 5.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.6), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.42)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.07, 0.08, 0.12), "matte")
	add_child(floor_inst)
	# Start pad: glowing ring marking where the marble drops.
	var pad := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.24
	pad.mesh = torus
	pad.material_override = GraphicsPolish.glow(Color(0.3, 1.0, 0.5), 1.6)
	pad.position = Vector3(START_POS.x, 0.02, START_POS.z)
	add_child(pad)


func _part_mesh(type_idx: int) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	match PART_TYPES[type_idx]:
		"ramp":
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.1, 0.7)
			inst.mesh = box
		"curve":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.18
			torus.outer_radius = 0.4
			inst.mesh = torus
		"funnel":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.4
			cone.bottom_radius = 0.08
			cone.height = 0.3
			inst.mesh = cone
		"booster":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.16
			cyl.bottom_radius = 0.16
			cyl.height = 0.12
			inst.mesh = cyl
		"goal":
			var cyl2 := CylinderMesh.new()
			cyl2.top_radius = 0.42
			cyl2.bottom_radius = 0.42
			cyl2.height = 0.14
			inst.mesh = cyl2
	inst.material_override = GraphicsPolish.glow(PART_COLORS[type_idx], 1.2)
	return inst


func _build_palette() -> void:
	var base_y := 2.1
	for i in PART_TYPES.size():
		var sample := _part_mesh(i)
		sample.position = Vector3(-3.4, base_y - float(i) * 0.62, 0.4)
		sample.scale = Vector3.ONE * 0.8
		add_child(sample)
		palette_nodes.append(sample)
		var lbl := GraphicsPolish.make_label(str(i + 1) + ": " + PART_TYPES[i], 40, Color(0.85, 0.9, 1.0))
		lbl.position = Vector3(-2.9, base_y - float(i) * 0.62 + 0.12, 0.4)
		lbl.pixel_size = 0.004
		add_child(lbl)
	palette_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	palette_ring.mesh = ring
	palette_ring.material_override = GraphicsPolish.glow(Color(1.0, 1.0, 1.0), 2.0)
	add_child(palette_ring)
	_update_palette_ring()


func _update_palette_ring() -> void:
	if palette_ring != null and selected_type < palette_nodes.size():
		var anchor_node: MeshInstance3D = palette_nodes[selected_type]
		palette_ring.position = anchor_node.position
		palette_ring.rotation_degrees = Vector3(0, 0, 0)


func _build_release_button() -> void:
	release_button = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.34
	cyl.height = 0.18
	release_button.mesh = cyl
	release_mat = GraphicsPolish.glow(Color(1.0, 0.3, 0.2), 2.2)
	release_button.material_override = release_mat
	release_button.position = Vector3(3.2, 0.55, 1.6)
	add_child(release_button)
	var lbl := GraphicsPolish.make_label("RELEASE", 48, Color(1.0, 0.95, 0.9))
	lbl.position = Vector3(3.2, 1.05, 1.6)
	lbl.pixel_size = 0.006
	add_child(lbl)


func _build_marble() -> void:
	marble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = MARBLE_R
	sphere.height = MARBLE_R * 2.0
	marble.mesh = sphere
	marble.material_override = GraphicsPolish.glow(Color(1.0, 0.95, 0.8), 1.8)
	marble.position = START_POS
	add_child(marble)
	marble.add_child(GraphicsPolish.make_trail(Color(1.0, 0.8, 0.3), 0.05))


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-3.3, 3.1, 0.6)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(0.4, 1.0, 0.6))
	msg_label.position = Vector3(0.0, 2.6, -1.0)
	msg_label.pixel_size = 0.010
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("", 30, Color(0.75, 0.8, 0.9))
	help_label.position = Vector3(-3.3, 2.78, 0.6)
	help_label.pixel_size = 0.004
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Score %d   Parts %d" % [score, parts.size()]
	if help_label != null:
		var xr := ARUpgradeKit.is_xr_active()
		if xr:
			help_label.text = "L pinch: change part | R pinch: place | R pinch button: release | Selected: " + PART_TYPES[selected_type]
		else:
			help_label.text = "1-5: select | Click floor: place | Click red button/Space: release | R: reset | Selected: " + PART_TYPES[selected_type]
	if msg_label != null:
		msg_label.text = msg


func _place_part(world_pos: Vector3) -> void:
	if parts.size() >= MAX_PARTS:
		_set_msg("Track full!", 1.5)
		return
	var type_idx := selected_type
	var part := Node3D.new()
	part.position = ARUpgradeKit.clamp_to_room(Vector3(world_pos.x, 0.0, world_pos.z))
	ARUpgradeKit.snap_to_floor(part)
	var mesh := _part_mesh(type_idx)
	if PART_TYPES[type_idx] == "curve":
		mesh.rotation_degrees.x = 90.0
		mesh.position.y = 0.12
	elif PART_TYPES[type_idx] == "ramp":
		mesh.position.y = 0.08
		mesh.rotation_degrees.x = -14.0
	elif PART_TYPES[type_idx] == "funnel":
		mesh.position.y = 0.16
	elif PART_TYPES[type_idx] == "booster":
		mesh.position.y = 0.07
	elif PART_TYPES[type_idx] == "goal":
		mesh.position.y = 0.08
	part.add_child(mesh)
	part.set_meta("type", PART_TYPES[type_idx])
	add_child(part)
	parts.append(part)
	part_meshes.append(mesh)
	var idx := parts.size() - 1
	ARUpgradeKit.save_anchor("marble-run_part_%d" % idx, part.global_transform)
	_set_msg(PART_TYPES[type_idx] + " placed", 1.0)
	GraphicsPolish.spawn_sparks(self, part.position + Vector3(0, 0.3, 0), PART_COLORS[type_idx], 10)
	_update_hud()


func _restore_layout() -> void:
	for i in MAX_PARTS:
		var t: Variant = ARUpgradeKit.load_anchor("marble-run_part_%d" % i)
		if t == null:
			break
		var type_name := ""
		# Type is encoded in the anchor order list only if saved during this
		# session; older anchors default to ramp. Rebuild as ramp ring markers.
		type_name = "ramp"
		var part := Node3D.new()
		add_child(part)
		part.global_transform = t as Transform3D
		var mesh := _part_mesh(0)
		mesh.position.y = 0.08
		part.add_child(mesh)
		part.set_meta("type", type_name)
		parts.append(part)
		part_meshes.append(mesh)


func _release_marble() -> void:
	if marble_rolling:
		return
	marble.position = START_POS
	marble_vel = START_VEL
	marble_rolling = true
	state = "rolling"
	_set_msg("", 0.0)
	GraphicsPolish.spawn_sparks(self, START_POS, Color(0.4, 1.0, 0.6), 14)


func _reset_marble() -> void:
	marble_rolling = false
	marble_vel = Vector3.ZERO
	marble.position = START_POS
	state = "build"
	_set_msg("", 0.0)
	_update_hud()


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _screen_dist(world_pos: Vector3, screen_pos: Vector2) -> float:
	if camera == null:
		return 1e9
	if camera.is_position_behind(world_pos):
		return 1e9
	return camera.unproject_position(world_pos).distance_to(screen_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode >= KEY_1 and k.keycode <= KEY_5:
				selected_type = int(k.keycode - KEY_1)
				_update_palette_ring()
				_update_hud()


func _handle_click(screen_pos: Vector2) -> void:
	if camera == null:
		return
	# Palette pick?
	for i in palette_nodes.size():
		var node: MeshInstance3D = palette_nodes[i]
		if _screen_dist(node.global_position, screen_pos) < 60.0:
			selected_type = i
			_update_palette_ring()
			_update_hud()
			return
	# Release button?
	if release_button != null and _screen_dist(release_button.global_position, screen_pos) < 70.0:
		_release_marble()
		return
	# Otherwise place on the floor plane.
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := -origin.y / dir.y
	if t < 0.0:
		return
	var p: Vector3 = origin + dir * t
	_place_part(p)


func _process(delta: float) -> void:
	pulse_t += delta
	if release_mat != null:
		GraphicsPolish.pulse_glow(release_mat, 2.2, 0.8, pulse_t, 3.0)
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	# XR: left-hand pinch cycles part, right-hand pinch places / releases.
	if ARUpgradeKit.is_xr_active():
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
			selected_type = (selected_type + 1) % PART_TYPES.size()
			_update_palette_ring()
			_update_hud()
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
			var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
			if release_button != null and pp.distance_to(release_button.global_position) < 0.6:
				_release_marble()
			else:
				_place_part(pp)
	if Input.is_key_pressed(KEY_SPACE):
		_release_marble()
	if Input.is_key_pressed(KEY_R):
		_reset_marble()
	if marble_rolling:
		_move_marble(delta)
	_update_hud()


func _move_marble(delta: float) -> void:
	marble_vel.y -= 9.8 * delta
	var pos: Vector3 = marble.position + marble_vel * delta
	# Floor contact: roll.
	if pos.y < MARBLE_R:
		pos.y = MARBLE_R
		if marble_vel.y < 0.0:
			marble_vel.y = -marble_vel.y * 0.25
		marble_vel.x *= 1.0 - 0.35 * delta
		marble_vel.z *= 1.0 - 0.35 * delta
	# Part effects.
	for i in parts.size():
		var part: Node3D = parts[i]
		var to_part: Vector3 = part.global_position - pos
		to_part.y = 0.0
		var dist := to_part.length()
		if dist > EFFECT_RADIUS:
			continue
		var ptype: String = part.get_meta("type")
		match ptype:
			"ramp":
				var dir := -part.global_transform.basis.z
				dir.y = 0.0
				marble_vel += dir.normalized() * 4.5 * delta
				marble_vel.y += 1.2 * delta
			"curve":
				var tangent := part.global_transform.basis.x
				tangent.y = 0.0
				var target: Vector3 = (tangent.normalized() * marble_vel.length())
				var hv := Vector3(marble_vel.x, 0.0, marble_vel.z)
				hv = hv.lerp(target, clampf(3.0 * delta, 0.0, 1.0))
				marble_vel.x = hv.x
				marble_vel.z = hv.z
			"funnel":
				marble_vel += to_part.normalized() * 7.0 * delta
				marble_vel *= 1.0 - 0.8 * delta
			"booster":
				if marble_vel.length() < 7.0:
					marble_vel *= 1.0 + 1.6 * delta
				GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.3, 0.3), 2)
			"goal":
				if dist < 0.32:
					_win(pos)
					return
	# Clamp speed.
	if marble_vel.length() > 8.0:
		marble_vel = marble_vel.normalized() * 8.0
	marble.position = pos
	# Lost marble: off the play area.
	if absf(pos.x) > 6.5 or absf(pos.z) > 6.5 or pos.y < -1.0:
		marble_rolling = false
		_set_msg("Marble lost! R to reset", 2.5)
		state = "build"


func _win(pos: Vector3) -> void:
	marble_rolling = false
	state = "build"
	var gained := 100 + 15 * parts.size()
	score += gained
	GraphicsPolish.spawn_confetti(self, pos + Vector3(0, 0.6, 0), 70)
	GraphicsPolish.spawn_sparks(self, pos, Color(0.4, 1.0, 0.5), 24)
	_set_msg("GOAL! +%d" % gained, 3.0)
	ARUpgradeKit.save_anchor("marble-run_main", global_transform)
	marble.position = START_POS
	_update_hud()
