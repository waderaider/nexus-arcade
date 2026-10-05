## SwarmEnemy.gd - procedural attack drone: octahedron body, emissive eye, rotor ring.
## (Port of Unity's SwarmEnemy.cs.) Flies toward the Core with a sine wobble.
## HP/speed scale with wave + difficulty. Registers in the "swarm_enemies" group
## so turrets can acquire targets.
extends Area3D
class_name SwarmEnemy

const REACH_DIST := 0.55
const WOBBLE_AMP := 0.35

var core: SwarmCore
var director: SwarmDirector
var hp := 3.0
var speed := 1.2
var damage := 10.0

var _wobble_phase := 0.0
var _flash := 0.0
var _body: MeshInstance3D
var _body_mat: StandardMaterial3D
var _rotor: MeshInstance3D


## Shared neon material helper (mirrors Unity's Procedural.MakeMat).
static func neon_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


## Shared octahedron mesh (mirrors Unity's SwarmEnemy.Octahedron).
static func make_octahedron(radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var top := Vector3(0.0, radius, 0.0)
	var bottom := Vector3(0.0, -radius, 0.0)
	var ring := [
		Vector3(radius, 0.0, 0.0), Vector3(0.0, 0.0, radius),
		Vector3(-radius, 0.0, 0.0), Vector3(0.0, 0.0, -radius),
	]
	for i in range(4):
		var j := (i + 1) % 4
		verts.append(top)
		verts.append(ring[i])
		verts.append(ring[j])
		verts.append(bottom)
		verts.append(ring[j])
		verts.append(ring[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Quick expanding-sphere pop effect used for kills and hits.
static func spawn_pop(parent: Node, pos: Vector3, color: Color, pop_scale := 3.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	mi.mesh = sm
	mi.material_override = SwarmEnemy.neon_mat(color)
	parent.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * pop_scale, 0.25)
	tw.tween_callback(mi.queue_free)


func setup(p_core: SwarmCore, p_director: SwarmDirector, wave: int, difficulty: float) -> void:
	core = p_core
	director = p_director
	hp = 3.0 + wave * 0.6 + difficulty * 2.5
	speed = 1.1 + wave * 0.07 + difficulty * 0.6
	damage = 8.0 + wave * 1.5
	_wobble_phase = randf() * TAU
	scale = Vector3.ONE * (1.0 + wave * 0.03)


func _ready() -> void:
	add_to_group("swarm_enemies")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)
	_build_visuals()


func _physics_process(delta: float) -> void:
	if core == null or not is_instance_valid(core):
		die(false)
		return

	var target := core.aim_point()
	var to_core := target - global_position
	var dist := to_core.length()
	if dist < REACH_DIST:
		core.damage(damage)
		if director != null and is_instance_valid(director):
			director.on_enemy_reached_core(self)
		die(false)
		return

	var dir := to_core / maxf(dist, 0.001)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var wobble := side * (sin(Time.get_ticks_msec() / 1000.0 * 3.0 + _wobble_phase) * WOBBLE_AMP)
	global_position += (dir * speed + wobble) * delta
	if dir.length_squared() > 0.000001:
		look_at(target, Vector3.UP)

	if _rotor != null:
		_rotor.rotation.y += deg_to_rad(720.0) * delta

	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _body_mat != null:
			_body_mat.albedo_color = Color(0.9, 0.2, 0.1)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.08
	if _body_mat != null:
		_body_mat.albedo_color = Color.WHITE
	if hp <= 0.0:
		die(true)


func die(killed: bool) -> void:
	if killed:
		SwarmEnemy.spawn_pop(get_parent(), global_position, Color(1.0, 0.5, 0.0))
		if director != null and is_instance_valid(director):
			director.on_enemy_killed(self)
	else:
		SwarmEnemy.spawn_pop(get_parent(), global_position, Color(1.0, 0.1, 0.1), 2.0)
	queue_free()


func _build_visuals() -> void:
	_body_mat = SwarmEnemy.neon_mat(Color(0.9, 0.2, 0.1))
	_body = MeshInstance3D.new()
	_body.mesh = SwarmEnemy.make_octahedron(0.22)
	_body.material_override = _body_mat
	add_child(_body)

	var eye := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.05
	esm.height = 0.1
	eye.mesh = esm
	eye.material_override = SwarmEnemy.neon_mat(Color(1.0, 0.9, 0.1))
	eye.position = Vector3(0.0, 0.03, -0.16)
	add_child(eye)

	_rotor = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.28
	cm.height = 0.03
	_rotor.mesh = cm
	_rotor.material_override = SwarmEnemy.neon_mat(Color(0.2, 0.2, 0.25))
	_rotor.position = Vector3(0.0, 0.14, 0.0)
	add_child(_rotor)
