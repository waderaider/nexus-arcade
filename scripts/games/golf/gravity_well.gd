## GravityWell.gd - pulls the golf ball toward its center.
## Ports GravityWell.cs.
extends Node3D
class_name GravityWell

@export var radius := 0.8
@export var strength := 3.0

var _mesh: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.2, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.8
	_mesh.material_override = mat
	_mesh.rotation.x = PI / 2.0
	add_child(_mesh)

func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.z = _t * 1.5
	var s := 1.0 + sin(_t * 3.0) * 0.06
	_mesh.scale = Vector3(s, s, s)
