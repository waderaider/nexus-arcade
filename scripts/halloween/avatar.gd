## HalloweenAvatar - stylized friendly 3D character built from primitives.
## Capsule torso, sphere head, capsule limbs, glowing eyes, friendly proportions.
## Slowly rotates on a turntable in _process. Room-placed via ARUpgradeKit
## anchor "halloween_avatar" (saved every 30s). Exposes named Node3D anchor
## markers as children: HeadTop, Face, Torso, Back, Head.
## Headless-safe: builds nodes/materials only, no XR hardware required.
extends Node3D

const SPIN_SPEED := 0.45
const ANCHOR_NAME := "halloween_avatar"
const ANCHOR_INTERVAL := 30.0

var _time := 0.0
var _anchor_timer := 0.0
var _eye_mats: Array[StandardMaterial3D] = []
var markers := {} # String -> Node3D


func _ready() -> void:
	_build_body()
	_build_markers()
	GraphicsPolish.make_light_rig(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 1.6)
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)


func _process(delta: float) -> void:
	_time += delta
	rotate_y(SPIN_SPEED * delta)
	for i in range(_eye_mats.size()):
		GraphicsPolish.pulse_glow(_eye_mats[i], 1.4, 0.5, _time + float(i) * 0.7)
	_anchor_timer += delta
	if _anchor_timer >= ANCHOR_INTERVAL:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)


## Convenience: fetch one of the named costume anchor markers.
func get_marker(marker_name: String) -> Node3D:
	return markers.get(marker_name, null)


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


func _build_body() -> void:
	var skin := GraphicsPolish.pbr_preset(Color(0.45, 0.55, 0.95), "plastic")
	var belly_mat := GraphicsPolish.pbr_preset(Color(0.75, 0.82, 1.0), "matte")
	var limb_mat := GraphicsPolish.pbr_preset(Color(0.38, 0.47, 0.88), "rubber")

	# Torso: capsule.
	var torso := CapsuleMesh.new()
	torso.radius = 0.20
	torso.height = 0.70
	_part(torso, skin, Vector3(0.0, 0.60, 0.0))

	# Belly patch: flattened lighter sphere on the chest front.
	var belly := SphereMesh.new()
	belly.radius = 0.15
	belly.height = 0.30
	var belly_mi := _part(belly, belly_mat, Vector3(0.0, 0.55, 0.10))
	belly_mi.scale = Vector3(0.85, 1.15, 0.55)

	# Head: sphere.
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	_part(head, skin, Vector3(0.0, 1.18, 0.0))

	# Glowing eyes.
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.045
		eye.height = 0.09
		var eye_mat := GraphicsPolish.glow(Color(0.5, 1.0, 0.9), 1.6)
		_eye_mats.append(eye_mat)
		_part(eye, eye_mat, Vector3(0.09 * side, 1.22, 0.20))

	# Blush cheeks.
	var blush := GraphicsPolish.pbr_preset(Color(1.0, 0.55, 0.65), "matte")
	for side in [-1.0, 1.0]:
		var cheek := SphereMesh.new()
		cheek.radius = 0.035
		cheek.height = 0.07
		var c := _part(cheek, blush, Vector3(0.14 * side, 1.12, 0.185))
		c.scale = Vector3(1.0, 0.7, 0.5)

	# Arms: angled capsules + sphere hands.
	for side in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.06
		arm.height = 0.40
		_part(arm, limb_mat, Vector3(0.30 * side, 0.62, 0.0), Vector3(0.0, 0.0, -12.0 * side))
		var hand := SphereMesh.new()
		hand.radius = 0.07
		hand.height = 0.14
		_part(hand, belly_mat, Vector3(0.345 * side, 0.42, 0.0))

	# Legs: short capsules + box feet.
	for side in [-1.0, 1.0]:
		var leg := CapsuleMesh.new()
		leg.radius = 0.08
		leg.height = 0.34
		_part(leg, limb_mat, Vector3(0.11 * side, 0.20, 0.0))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.14, 0.08, 0.24)
		_part(foot, belly_mat, Vector3(0.11 * side, 0.04, 0.05))


func _build_markers() -> void:
	var defs := {
		"HeadTop": Vector3(0.0, 1.52, 0.0),
		"Face": Vector3(0.0, 1.18, 0.30),
		"Torso": Vector3(0.0, 0.72, 0.24),
		"Back": Vector3(0.0, 0.75, -0.26),
		"Head": Vector3(0.0, 1.18, 0.0),
	}
	for marker_name in defs.keys():
		var m := Node3D.new()
		m.name = marker_name
		m.position = defs[marker_name]
		add_child(m)
		markers[marker_name] = m
