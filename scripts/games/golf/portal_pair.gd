## PortalPair.gd - linked portal rings that teleport the golf ball.
## Ports PortalPair.cs (TryTeleport API).
extends Node3D
class_name PortalPair

var portal_a: Node3D
var portal_b: Node3D
@export var portal_radius := 0.22

var _t := 0.0

func _ready() -> void:
	portal_a = _make_portal(Color(0.2, 0.9, 1.0))
	portal_a.position = Vector3(-0.8, 0.12, 0.0)
	add_child(portal_a)
	portal_b = _make_portal(Color(1.0, 0.5, 0.2))
	portal_b.position = Vector3(0.8, 0.12, 0.8)
	add_child(portal_b)

func _make_portal(color: Color) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.14
	torus.outer_radius = 0.22
	mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	root.add_child(mesh)
	# Inner disc (the "surface").
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.01
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(color.r, color.g, color.b, 0.5)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.emission_enabled = true
	dmat.emission = color
	disc.material_override = dmat
	root.add_child(disc)
	root.rotation.x = PI / 2.0  # lie flat, facing up
	return root

## Try to teleport pos if inside either portal.
## Returns the (possibly teleported) position and whether a teleport happened.
func try_teleport(pos: Vector3) -> Array:
	for pair in [[portal_a, portal_b], [portal_b, portal_a]]:
		var s: Node3D = pair[0]
		var d: Node3D = pair[1]
		var flat := Vector2(pos.x - s.global_position.x, pos.z - s.global_position.z)
		if flat.length() < portal_radius:
			pos.x = d.global_position.x
			pos.z = d.global_position.z
			pos.y = maxf(pos.y, d.global_position.y + 0.1)
			return [pos, true]
	return [pos, false]

func _process(delta: float) -> void:
	_t += delta
	portal_a.rotate_z(delta * 2.0)
	portal_b.rotate_z(-delta * 2.0)
