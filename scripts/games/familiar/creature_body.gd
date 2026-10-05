## CreatureBody.gd - procedural glowing blob creature ("Mochi").
## Ports CreatureBody.cs: squashed-sphere body, emissive eyes, cone ears,
## wagging tail; squash-and-stretch idle; hop (or hover) locomotion;
## mood colour lerp; sleep "Z" labels; dance / spin / eat / nuzzle one-shots.
extends Node3D
class_name CreatureBody

enum Stage { EGG, SPROUT, WISP, GUARDIAN }
enum Mood { NEUTRAL, HAPPY, CURIOUS, PLAYFUL, SLEEPY }

var head_anchor: Node3D

var _body_visual: MeshInstance3D
var _body_mat: StandardMaterial3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _ear_l: MeshInstance3D
var _ear_r: MeshInstance3D
var _tail: MeshInstance3D

var _stage: int = Stage.EGG
var _mood: int = Mood.NEUTRAL
var _target_color := Color(1.0, 0.94, 0.80)
var _base_scale := 0.20

# Locomotion.
var _move_target := Vector3.ZERO
var _moving := false
var _hop_phase := 0.0
var _face_yaw := 0.0
var _spin_angle := 0.0

# One-shot animation timers.
var _dance_timer := 0.0
var _spin_timer := 0.0
var _squash_timer := 0.0
var _nuzzle_timer := 0.0
var _celebrate_timer := 0.0
var _sleeping := false
var _sleep_z_timer := 0.0
var _z_labels: Array[Label3D] = []
var _eye_size := 0.10

func _ready() -> void:
	_build_visuals()

# ------------------------------------------------------------------ build

func _make_mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	m.roughness = 0.55
	return m

func _make_part(mesh: Mesh, part_name: String, local_pos: Vector3,
		local_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = local_pos
	mi.scale = local_scale
	_body_visual.add_child(mi)
	return mi

func _build_visuals() -> void:
	_body_visual = MeshInstance3D.new()
	_body_visual.name = "Body"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_body_visual.mesh = sphere
	_body_mat = _make_mat(_target_color)
	_body_visual.material_override = _body_mat
	add_child(_body_visual)

	head_anchor = Node3D.new()
	head_anchor.name = "HeadAnchor"
	head_anchor.position = Vector3(0, 0.32, 0)
	_body_visual.add_child(head_anchor)

	_eye_mat = _make_mat(Color.BLACK, 0.15)
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 1.0
	eye_mesh.height = 2.0
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 8
	_eye_l = _make_part(eye_mesh, "EyeL", Vector3(-0.32, 0.22, 0.85),
		Vector3.ONE * 0.16, _eye_mat)
	_eye_r = _make_part(eye_mesh, "EyeR", Vector3(0.32, 0.22, 0.85),
		Vector3.ONE * 0.16, _eye_mat)

	var ear_mat := _make_mat(Color(1.0, 0.95, 0.82))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 1.0
	cone.height = 2.0
	cone.radial_segments = 16
	_ear_l = _make_part(cone, "EarL", Vector3(-0.45, 0.85, 0),
		Vector3(0.22, 0.55, 0.22), ear_mat)
	_ear_r = _make_part(cone, "EarR", Vector3(0.45, 0.85, 0),
		Vector3(0.22, 0.55, 0.22), ear_mat)
	_ear_l.rotation.z = deg_to_rad(12.0)
	_ear_r.rotation.z = deg_to_rad(-12.0)

	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.5
	tail_mesh.bottom_radius = 1.0
	tail_mesh.height = 2.0
	_tail = _make_part(tail_mesh, "Tail", Vector3(0, 0.05, -0.95),
		Vector3(0.18, 0.5, 0.18), ear_mat)
	_tail.rotation.x = deg_to_rad(70.0)

	_apply_stage(Stage.EGG, true)

# ------------------------------------------------------------------ stage

func set_stage(s: int) -> void:
	_apply_stage(s, false)

func _stage_color() -> Color:
	match _stage:
		Stage.EGG:
			return Color(1.0, 0.94, 0.80)
		Stage.SPROUT:
			return Color(0.55, 0.92, 0.60)
		Stage.WISP:
			return Color(0.45, 0.82, 1.0)
		_:
			return Color(1.0, 0.72, 0.35)

func _apply_stage(s: int, instant: bool) -> void:
	_stage = s
	match s:
		Stage.EGG:
			_base_scale = 0.20
			_target_color = Color(1.0, 0.94, 0.80)
			_ear_l.visible = false
			_ear_r.visible = false
			_tail.visible = false
			_set_eye_size(0.10)
			_set_eye_glow(0.0)
		Stage.SPROUT:
			_base_scale = 0.30
			_target_color = Color(0.55, 0.92, 0.60)
			_ear_l.visible = true
			_ear_r.visible = true
			_tail.visible = false
			_set_eye_size(0.16)
			_set_eye_glow(0.15)
		Stage.WISP:
			_base_scale = 0.40
			_target_color = Color(0.45, 0.82, 1.0)
			_ear_l.visible = true
			_ear_r.visible = true
			_tail.visible = true
			_set_eye_size(0.16)
			_set_eye_glow(0.7)
		Stage.GUARDIAN:
			_base_scale = 0.55
			_target_color = Color(1.0, 0.72, 0.35)
			_ear_l.visible = true
			_ear_r.visible = true
			_tail.visible = true
			_set_eye_size(0.18)
			_set_eye_glow(0.4)
	if _body_mat:
		if instant:
			_body_mat.albedo_color = _target_color
		else:
			_celebrate_timer = 1.2
		_set_body_emission(_target_color * (0.7 if _stage == Stage.WISP else 0.0))

func _set_body_emission(c: Color) -> void:
	_body_mat.emission_enabled = true
	_body_mat.emission = _target_color
	_body_mat.emission_energy_multiplier = 0.7 if _stage == Stage.WISP else 0.0

func _set_eye_size(s: float) -> void:
	_eye_size = s
	_eye_l.scale = Vector3.ONE * s
	_eye_r.scale = Vector3.ONE * s

func _set_eye_glow(e: float) -> void:
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color.WHITE
	_eye_mat.emission_energy_multiplier = e

# ------------------------------------------------------------------ mood

func set_mood(m: int) -> void:
	_mood = m
	match m:
		Mood.HAPPY:
			_target_color = _target_color.lerp(Color(1.0, 0.85, 0.5), 0.35)
		Mood.CURIOUS:
			_target_color = _target_color.lerp(Color(0.6, 0.85, 1.0), 0.35)
		Mood.PLAYFUL:
			_target_color = _target_color.lerp(Color(1.0, 0.6, 0.8), 0.35)
		Mood.SLEEPY:
			_target_color = _target_color.lerp(Color(0.55, 0.55, 0.8), 0.35)
		_:
			_target_color = _target_color.lerp(_stage_color(), 0.35)

# ------------------------------------------------------------------ actions

func hop_to(world_target: Vector3) -> void:
	_move_target = world_target
	_moving = true

func look_at_point(world_point: Vector3) -> void:
	var d := world_point - global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		_face_yaw = atan2(d.x, d.z)

func dance() -> void:
	_dance_timer = 3.0

func spin() -> void:
	_spin_timer = 0.7

func eat() -> void:
	_squash_timer = 0.6

func nuzzle() -> void:
	_nuzzle_timer = 1.2

func happy_bounce() -> void:
	_squash_timer = 0.5

func celebrate_evolution() -> void:
	_celebrate_timer = 1.5

func set_sleeping(sleeping: bool) -> void:
	if _sleeping == sleeping:
		return
	_sleeping = sleeping
	if not sleeping:
		_clear_z_labels()

# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0

	# Locomotion.
	var speed := 0.55 if _stage == Stage.GUARDIAN else 0.35
	if _moving:
		var flat := Vector3(_move_target.x - global_position.x, 0.0,
			_move_target.z - global_position.z)
		var dist := flat.length()
		if dist < 0.12:
			_moving = false
		else:
			var step := flat.normalized() * minf(speed * delta, dist)
			global_position += step
			look_at_point(global_position + flat)
			_hop_phase += delta * (3.0 if _stage == Stage.GUARDIAN else 7.0)
	else:
		var snapped := roundf(_hop_phase / PI) * PI
		_hop_phase = lerpf(_hop_phase, snapped, delta * 8.0)

	var guardian := _stage == Stage.GUARDIAN
	var hop_y := 0.0
	var stretch := 0.0
	var squash := 0.0
	if _moving and not guardian:
		var c := absf(sin(_hop_phase))
		hop_y = c * 0.10 * _base_scale / 0.3
		stretch = c * 0.35
		squash = (1.0 - c) * 0.12
	elif guardian:
		hop_y = 0.25 + sin(time * 2.2) * 0.05  # hover

	# Idle breathing squash-and-stretch.
	var breathe := sin(time * 2.4) * 0.05

	# One-shots.
	var spin_y := 0.0
	if _dance_timer > 0.0:
		_dance_timer -= delta
		spin_y += delta * 360.0 * 1.5
		hop_y += absf(sin(time * 9.0)) * 0.08
	if _spin_timer > 0.0:
		_spin_timer -= delta
		spin_y += delta * (360.0 / 0.7)
	if _squash_timer > 0.0:
		_squash_timer -= delta
		squash += sin((_squash_timer / 0.6) * PI) * 0.45
	if _celebrate_timer > 0.0:
		_celebrate_timer -= delta
		spin_y += delta * 240.0
		hop_y += absf(sin(time * 7.0)) * 0.12

	var gp := global_position
	gp.y = maxf(0.02, gp.y)
	global_position = gp

	_spin_angle = fmod(_spin_angle + spin_y, 360.0)
	if _spin_timer <= 0.0 and _dance_timer <= 0.0 and _celebrate_timer <= 0.0:
		_spin_angle = lerp_angle(_spin_angle, 0.0, delta * 6.0)
	rotation.y = _face_yaw + deg_to_rad(_spin_angle)

	var nuzzle := 0.0
	if _nuzzle_timer > 0.0:
		_nuzzle_timer -= delta
		nuzzle = sin((_nuzzle_timer / 1.2) * PI) * 0.15

	_body_visual.position = Vector3(nuzzle, hop_y + _base_scale * 0.95, 0.0)
	_body_visual.scale = Vector3(
		_base_scale * (1.0 + breathe * 0.5 - squash * 0.6),
		_base_scale * (1.0 - breathe + stretch - squash),
		_base_scale * (1.0 + breathe * 0.5 - squash * 0.6))

	# Tail wag.
	if _tail.visible:
		_tail.rotation.y = sin(time * (10.0 if _mood == Mood.HAPPY else 3.0)) * 0.45

	# Mood colour lerp.
	if _body_mat:
		_body_mat.albedo_color = _body_mat.albedo_color.lerp(_target_color, delta * 2.0)

	# Sleep: eyes droop + rising Z labels.
	var eye_sy := 0.25 if _sleeping else 1.0
	_eye_l.scale = Vector3(_eye_size, _eye_size * eye_sy, _eye_size)
	_eye_r.scale = Vector3(_eye_size, _eye_size * eye_sy, _eye_size)
	if _sleeping:
		_sleep_z_timer -= delta
		if _sleep_z_timer <= 0.0:
			_sleep_z_timer = 1.4
			_spawn_z()
		_update_z_labels(delta)

# ------------------------------------------------------------------ sleep Z's

func _spawn_z() -> void:
	var z := Label3D.new()
	z.text = "z"
	z.font_size = 48
	z.modulate = Color(0.7, 0.8, 1.0, 1.0)
	z.outline_size = 0
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	z.position = Vector3(0.15, 0.6 * _base_scale / 0.3 + 0.4, 0)
	add_child(z)
	_z_labels.append(z)

func _update_z_labels(delta: float) -> void:
	for i in range(_z_labels.size() - 1, -1, -1):
		var z := _z_labels[i]
		if not is_instance_valid(z):
			_z_labels.remove_at(i)
			continue
		z.position.y += delta * 0.12
		z.scale *= 1.0 + delta * 0.25
		var c := z.modulate
		c.a -= delta * 0.35
		z.modulate = c
		if c.a <= 0.0 or z.position.y > 1.2:
			z.queue_free()
			_z_labels.remove_at(i)

func _clear_z_labels() -> void:
	for z in _z_labels:
		if is_instance_valid(z):
			z.queue_free()
	_z_labels.clear()
