## GraffitiWall: spray-paint wall in AR.
## A wall plane faces you. Hold the mouse button (or pinch in XR) to spray
## paint particles onto the wall at the ray hit point; the spray leaves
## persistent decal dots. Shake your hand fast (or press C) to cycle
## colors. Stencil shapes - star and heart - are selectable via HUD keys
## 1/2/3 (1 = freeform spray). Score = wall coverage %.
## T saves the artwork anchor. R clears the wall and restarts.
extends Node3D

const WALL_W := 4.0
const WALL_H := 2.4
const WALL_Z := -2.2
const DECAL_SIZE := 0.07
const DECAL_CAP := 1800
const CELLS_X := 40
const CELLS_Y := 24
const SAVE_FILE := "user://graffiti_wall.cfg"
const PALETTE := [
	Color(1.0, 0.25, 0.25), Color(1.0, 0.55, 0.1), Color(1.0, 0.9, 0.2),
	Color(0.3, 1.0, 0.4), Color(0.25, 0.9, 1.0), Color(0.35, 0.45, 1.0),
	Color(0.75, 0.35, 1.0), Color(1.0, 0.4, 0.8), Color(1.0, 1.0, 1.0),
]
const STENCIL_NAMES := ["Freeform", "Star", "Heart"]

var camera: Camera3D = null
var wall: MeshInstance3D = null
var decals: Array = []
var painted := PackedByteArray()
var painted_count := 0
var color_idx := 0
var stencil := 0
var spray_fx: GPUParticles3D = null
var spray_mat: StandardMaterial3D = null
var hud_score: Label3D = null
var hud_mode: Label3D = null
var hud_hint: Label3D = null
var hud_msg: Label3D = null
var swatch: MeshInstance3D = null
var swatch_mat: StandardMaterial3D = null
var spray_tick := 0.0
var star_pts: Array = []
var heart_pts: Array = []
var milestones := [false, false, false, false]
var shake_hist: Array = []
var shake_cd := 0.0
var elapsed := 0.0


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "graffiti-wall_main")
	_ensure_camera()
	_ensure_env()
	_ensure_light()
	_build_shapes()
	_build_wall()
	_build_spray_fx()
	_build_hud()
	painted.resize(CELLS_X * CELLS_Y)
	painted.fill(0)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.5), 2.0, 30)


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.6, 2.6)
		cam.look_at(Vector3(0.0, 1.5, -2.2), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.55)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _build_shapes() -> void:
	star_pts.clear()
	for k in range(10):
		var a := -PI / 2.0 + k * PI / 5.0
		var r := 1.0 if k % 2 == 0 else 0.45
		star_pts.append(Vector2(cos(a), sin(a)) * r)
	heart_pts.clear()
	for k in range(40):
		var t := TAU * k / 40.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		heart_pts.append(Vector2(x, -y) / 17.0)


func _build_wall() -> void:
	wall = MeshInstance3D.new()
	wall.name = "Wall"
	var pm := PlaneMesh.new()
	pm.size = Vector2(WALL_W, WALL_H)
	wall.mesh = pm
	wall.material_override = GraphicsPolish.pbr_preset(Color(0.82, 0.82, 0.86), "matte")
	wall.position = Vector3(0.0, 1.5, WALL_Z)
	add_child(wall)
	# Frame.
	var frame_mat := GraphicsPolish.pbr_preset(Color(0.15, 0.15, 0.2), "metal")
	for sx in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, WALL_H + 0.2, 0.08)
		edge.mesh = bm
		edge.material_override = frame_mat
		edge.position = Vector3(sx * (WALL_W / 2 + 0.05), 1.5, WALL_Z)
		add_child(edge)
	for sy in [-1.0, 1.0]:
		var edge2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(WALL_W + 0.2, 0.1, 0.08)
		edge2.mesh = bm2
		edge2.material_override = frame_mat
		edge2.position = Vector3(0.0, 1.5 + sy * (WALL_H / 2 + 0.05), WALL_Z)
		add_child(edge2)


func _build_spray_fx() -> void:
	spray_fx = GPUParticles3D.new()
	spray_fx.amount = 48
	spray_fx.lifetime = 0.45
	spray_fx.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 9.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.015
	mat.scale_max = 0.035
	mat.color = PALETTE[color_idx]
	spray_fx.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	spray_mat = GraphicsPolish.glow(PALETTE[color_idx], 1.2)
	quad.material = spray_mat
	spray_fx.draw_pass_1 = quad
	add_child(spray_fx)


func _build_hud() -> void:
	hud_score = GraphicsPolish.make_label("", 56, Color(1, 1, 1))
	hud_score.position = Vector3(0.0, 3.05, -1.8)
	add_child(hud_score)
	hud_mode = GraphicsPolish.make_label("", 44, Color(1.0, 0.9, 0.4))
	hud_mode.position = Vector3(0.0, 2.78, -1.8)
	add_child(hud_mode)
	hud_hint = GraphicsPolish.make_label("Hold LMB/pinch: spray  C/shake: color  1/2/3: stencil  T: save", 32, Color(0.8, 0.9, 1.0))
	hud_hint.position = Vector3(0.0, 0.35, 0.6)
	add_child(hud_hint)
	hud_msg = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.3))
	hud_msg.position = Vector3(0.0, 2.2, -1.6)
	add_child(hud_msg)
	swatch = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	swatch.mesh = sm
	swatch_mat = GraphicsPolish.glow(PALETTE[color_idx], 1.8)
	swatch.material_override = swatch_mat
	swatch.position = Vector3(1.9, 2.9, -1.8)
	add_child(swatch)


func _process(delta: float) -> void:
	elapsed += delta
	shake_cd = maxf(0.0, shake_cd - delta)
	if _is_spraying():
		_spray(delta)
	else:
		spray_fx.emitting = false
	_update_shake(delta)
	var cov := _coverage()
	hud_score.text = "Coverage %d%%" % int(cov)
	hud_mode.text = STENCIL_NAMES[stencil] + " stencil"
	_check_milestones(cov)


func _is_spraying() -> bool:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _wall_hit() -> Variant:
	# Local-space hit point on the wall plane, or null.
	var origin := Vector3.ZERO
	var dir := Vector3(0, 0, -1)
	if ARUpgradeKit.is_xr_active():
		var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		origin = r[0]
		dir = r[1]
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		origin = camera.project_ray_origin(mp)
		dir = camera.project_ray_normal(mp)
	else:
		return null
	if absf(dir.z) < 0.0001:
		return null
	var t := (WALL_Z - origin.z) / dir.z
	if t <= 0.0:
		return null
	var world: Vector3 = origin + dir * t
	var local: Vector3 = wall.to_local(world)
	if absf(local.x) > WALL_W / 2 or absf(local.y) > WALL_H / 2:
		return null
	return local


func _spray(delta: float) -> void:
	var hit: Variant = _wall_hit()
	if hit == null:
		spray_fx.emitting = false
		return
	var local: Vector3 = hit
	spray_fx.position = wall.to_global(local) + Vector3(0, 0, 0.25)
	spray_fx.emitting = true
	spray_tick += delta
	while spray_tick >= 0.03:
		spray_tick -= 0.03
		_stamp_decal(local)


func _stamp_decal(local: Vector3) -> void:
	var offset := Vector2(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
	if stencil == 1:
		offset = star_pts[randi() % star_pts.size()] * 0.28
	elif stencil == 2:
		offset = heart_pts[randi() % heart_pts.size()] * 0.28
	var d := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(DECAL_SIZE, DECAL_SIZE)
	d.mesh = qm
	d.material_override = GraphicsPolish.pbr_preset(PALETTE[color_idx], "matte")
	d.position = Vector3(local.x + offset.x, local.y + offset.y, 0.012)
	d.rotation.z = randf() * TAU
	wall.add_child(d)
	decals.append(d)
	if decals.size() > DECAL_CAP:
		var old: MeshInstance3D = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# Coverage cell.
	var cx := int(clampf((local.x / WALL_W + 0.5) * CELLS_X, 0, CELLS_X - 1))
	var cy := int(clampf((local.y / WALL_H + 0.5) * CELLS_Y, 0, CELLS_Y - 1))
	var ci := cy * CELLS_X + cx
	if painted[ci] == 0:
		painted[ci] = 1
		painted_count += 1


func _coverage() -> float:
	return painted_count / float(CELLS_X * CELLS_Y) * 100.0


func _check_milestones(cov: float) -> void:
	var marks := [25.0, 50.0, 75.0, 100.0]
	for i in range(4):
		if not milestones[i] and cov >= marks[i]:
			milestones[i] = true
			GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, WALL_Z + 0.5), 60)
			hud_msg.text = "%d%% covered!" % int(marks[i])
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_callback(_clear_msg)


func _clear_msg() -> void:
	hud_msg.text = ""


func _update_shake(delta: float) -> void:
	if not ARUpgradeKit.is_xr_active():
		return
	var p: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.4)
	shake_hist.append({"p": p, "t": elapsed})
	while shake_hist.size() > 2 and elapsed - float(shake_hist[0]["t"]) > 0.5:
		shake_hist.pop_front()
	if shake_hist.size() >= 6 and shake_cd <= 0.0:
		var reversals := 0
		var prev := Vector3.ZERO
		for i in range(1, shake_hist.size()):
			var v: Vector3 = shake_hist[i]["p"] - shake_hist[i - 1]["p"]
			if v.length() > 0.01 and prev != Vector3.ZERO:
				if v.normalized().dot(prev.normalized()) < -0.5:
					reversals += 1
			if v.length() > 0.01:
				prev = v
		if reversals >= 4:
			_cycle_color()
			shake_cd = 1.0
			shake_hist.clear()


func _cycle_color() -> void:
	color_idx = (color_idx + 1) % PALETTE.size()
	var col: Color = PALETTE[color_idx]
	swatch_mat.albedo_color = col
	swatch_mat.emission = col
	spray_mat.albedo_color = col
	spray_mat.emission = col
	(spray_fx.process_material as ParticleProcessMaterial).color = col
	GraphicsPolish.spawn_sparks(self, swatch.position, col, 12)


func _save_artwork() -> void:
	ARUpgradeKit.save_anchor("graffiti-wall_main", global_transform)
	var cfg := ConfigFile.new()
	cfg.set_value("art", "coverage", _coverage())
	cfg.set_value("art", "decals", decals.size())
	cfg.set_value("art", "color_idx", color_idx)
	cfg.save(SAVE_FILE)
	hud_msg.text = "Artwork saved."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_C:
				_cycle_color()
			KEY_1:
				stencil = 0
			KEY_2:
				stencil = 1
			KEY_3:
				stencil = 2
			KEY_T:
				_save_artwork()
			KEY_R:
				_reset_wall()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cycle_color()


func _reset_wall() -> void:
	for d in decals:
		if is_instance_valid(d):
			d.queue_free()
	decals.clear()
	painted.fill(0)
	painted_count = 0
	milestones = [false, false, false, false]
	hud_msg.text = ""
