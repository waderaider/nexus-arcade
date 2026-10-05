## SwarmCore (port of Unity's Core.cs) - the player's crystal: emissive cyan
## octahedron on a glowing base ring. Enemies fly toward aim_point(). Damage
## flashes red; HP 0 emits core_destroyed.
extends Node3D
class_name SwarmCore

signal core_destroyed

const MAX_HP := 100.0
const HOVER_HEIGHT := 0.45

var hp := MAX_HP

var _mat: StandardMaterial3D
var _crystal: MeshInstance3D
var _flash := 0.0
var _bob_phase := 0.0


## Where enemies aim: the hovering crystal, not the floor point.
func aim_point() -> Vector3:
	return global_position + Vector3(0.0, HOVER_HEIGHT, 0.0)


func _ready() -> void:
	_bob_phase = randf() * 10.0

	_crystal = MeshInstance3D.new()
	_crystal.mesh = SwarmEnemy.make_octahedron(0.28)
	_mat = SwarmEnemy.neon_mat(Color(0.2, 0.95, 1.0))
	_crystal.material_override = _mat
	_crystal.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
	add_child(_crystal)

	var ring := MeshInstance3D.new()
	ring.mesh = WallPortal.make_ring(0.3, 0.42, 36)
	ring.material_override = SwarmEnemy.neon_mat(Color(0.2, 0.95, 1.0))
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 0.02, 0.0)
	add_child(ring)


func _process(delta: float) -> void:
	if _crystal != null:
		_crystal.rotation.y += deg_to_rad(60.0) * delta
		_crystal.position.y = HOVER_HEIGHT + sin(Time.get_ticks_msec() / 1000.0 * 2.0 + _bob_phase) * 0.05

	if _flash > 0.0 and _mat != null:
		_flash -= delta
		if _flash <= 0.0:
			_mat.albedo_color = Color(0.2, 0.95, 1.0)


func damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_flash = 0.4
	if _mat != null:
		_mat.albedo_color = Color(1.0, 0.1, 0.1)
	if hp <= 0.0:
		SwarmEnemy.spawn_pop(get_parent(), aim_point(), Color(0.2, 0.95, 1.0), 5.0)
		core_destroyed.emit()
