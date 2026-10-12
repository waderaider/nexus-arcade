## NullGAvatar.gd - capsule player avatar for NULL-G LEAGUE.
## Team-colored capsule body + head + glowing waist ring. Cheap (3 draw
## calls), emissive so it reads in passthrough.
class_name NullGAvatar
extends Node3D

var _body: MeshInstance3D
var _head: MeshInstance3D
var _ring: MeshInstance3D
var _base_yaw := 0.0


static func make(team_color: Color) -> NullGAvatar:
	var a := NullGAvatar.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = team_color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 1.2
	mat.roughness = 0.5

	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.20
	cap.height = 1.05
	body.mesh = cap
	body.material_override = mat
	a.add_child(body)
	a._body = body

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	head.mesh = sph
	head.position = Vector3(0, 0.68, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.08, 0.09, 0.12)
	hmat.emission_enabled = true
	hmat.emission = team_color
	hmat.emission_energy_multiplier = 2.2
	head.material_override = hmat
	a.add_child(head)
	a._head = head

	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.22
	tor.outer_radius = 0.27
	ring.mesh = tor
	ring.rotation = Vector3(PI / 2.0, 0, 0)
	ring.position = Vector3(0, 0.05, 0)
	ring.material_override = hmat
	a.add_child(ring)
	a._ring = ring
	return a


## Face a direction (yaw only); lean into velocity for zero-G feel.
func steer_look(dir: Vector3, speed: float, delta: float) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.2:
		var target_yaw := atan2(-flat.x, -flat.z)
		var cur := rotation.y
		var d := wrapf(target_yaw - cur, -PI, PI)
		rotation.y = cur + d * minf(1.0, 6.0 * delta)
	rotation.x = lerpf(rotation.x, clampf(-speed * 0.04, -0.45, 0.45), minf(1.0, 4.0 * delta))
