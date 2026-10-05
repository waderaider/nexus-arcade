## WallPortal.gd - glowing enemy spawn portal: emissive ring + swirling disc.
## (Port of Unity's WallPortal.cs.) Pulses and rotates; spawn_enemy() births a
## SwarmEnemy just in front of it. make_ring() is shared with SwarmCore.
extends Node3D
class_name WallPortal

var _disc: MeshInstance3D
var _pulse := 0.0


## Flat annulus mesh in the XY plane facing +Z (mirrors Unity's BuildRing).
static func make_ring(inner: float, outer: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in range(segments):
		var a0 := i * TAU / segments
		var a1 := (i + 1) * TAU / segments
		var i0 := Vector3(cos(a0) * inner, sin(a0) * inner, 0.0)
		var o0 := Vector3(cos(a0) * outer, sin(a0) * outer, 0.0)
		var i1 := Vector3(cos(a1) * inner, sin(a1) * inner, 0.0)
		var o1 := Vector3(cos(a1) * outer, sin(a1) * outer, 0.0)
		verts.append(i0)
		verts.append(o0)
		verts.append(i1)
		verts.append(o0)
		verts.append(o1)
		verts.append(i1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ready() -> void:
	_pulse = randf() * 10.0
	var ring := MeshInstance3D.new()
	ring.mesh = WallPortal.make_ring(0.32, 0.45, 40)
	ring.material_override = SwarmEnemy.neon_mat(Color(1.0, 0.2, 0.9))
	add_child(ring)

	_disc = MeshInstance3D.new()
	_disc.mesh = WallPortal.make_ring(0.02, 0.3, 32)
	var dmat := SwarmEnemy.neon_mat(Color(0.5, 0.05, 0.7))
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color.a = 0.7
	_disc.material_override = dmat
	_disc.position = Vector3(0.0, 0.0, -0.02)
	add_child(_disc)


func _process(delta: float) -> void:
	_pulse += delta
	var s := 1.0 + sin(_pulse * 4.0) * 0.08
	scale = Vector3.ONE * s
	if _disc != null:
		_disc.rotation.z += deg_to_rad(120.0) * delta


## Spawn a wave-scaled enemy just in front of the portal (toward -Z).
func spawn_enemy(wave: int, difficulty: float, core: SwarmCore, director: SwarmDirector) -> SwarmEnemy:
	var enemy := SwarmEnemy.new()
	get_parent().add_child(enemy)
	var fwd := -global_transform.basis.z
	enemy.global_position = global_position + fwd * 0.5
	enemy.setup(core, director, wave, difficulty)
	SwarmEnemy.spawn_pop(get_parent(), enemy.global_position, Color(1.0, 0.3, 0.9), 2.0)
	return enemy
