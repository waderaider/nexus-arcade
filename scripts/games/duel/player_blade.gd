## PlayerBlade.gd - the player's light-blade for Neon Duel.
## Ports PlayerBladeController.cs: follows the right hand (grip at hand
## position, blade along the hand's up vector) plus a parry buckler disc on
## the left forearm. Desktop fallback: mouse raycast for the blade, hold
## Space for the buckler. Blade hum pitch rises with swing speed.
extends Node3D
class_name PlayerBlade

const SWING_HUM_BASE := 95.0
const BUCKLER_RADIUS := 0.16

var blade: EnergyBlade
var blade_active := false
var buckler_active := false
var buckler_position := Vector3.ZERO

var _buckler: MeshInstance3D
var _swing_pitch := SWING_HUM_BASE
var _desktop_depth := 0.7


func _ready() -> void:
	blade = EnergyBlade.create(Color(0.2, 0.9, 1.0))
	blade.name = "PlayerBladeMesh"
	add_child(blade)
	blade.set_hum(SWING_HUM_BASE, 0.5)

	# Parry buckler disc.
	_buckler = MeshInstance3D.new()
	_buckler.name = "ParryBuckler"
	var disc := CylinderMesh.new()
	disc.top_radius = BUCKLER_RADIUS
	disc.bottom_radius = BUCKLER_RADIUS
	disc.height = 0.015
	_buckler.mesh = disc
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.25, 0.85, 1.0)
	bmat.emission_enabled = true
	bmat.emission = Color(0.25, 0.85, 1.0)
	bmat.emission_energy_multiplier = 1.2
	bmat.metallic = 0.9
	bmat.roughness = 0.3
	_buckler.material_override = bmat
	_buckler.visible = false
	add_child(_buckler)


func _process(delta: float) -> void:
	_update_blade(delta)
	_update_buckler()


func _update_blade(delta: float) -> void:
	var right := _get_right_hand()
	if right:
		blade_active = true
		blade.visible = true
		global_position = right.global_position
		# Blade direction = hand up vector (OpenXR: -Y of the hand node).
		var up: Vector3 = -right.global_transform.basis.y
		if up.length() > 0.001:
			# Align local +Y to the hand's up vector.
			var y_axis := up.normalized()
			var x_axis := y_axis.cross(Vector3.FORWARD)
			if x_axis.length() < 0.01:
				x_axis = y_axis.cross(Vector3.RIGHT)
			x_axis = x_axis.normalized()
			var z_axis := x_axis.cross(y_axis).normalized()
			global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), global_position)
	else:
		# Desktop: grip follows the mouse ray at a fixed depth from camera.
		var cam := get_viewport().get_camera_3d()
		if cam:
			var mouse := get_viewport().get_mouse_position()
			var from := cam.project_ray_origin(mouse)
			var dir := cam.project_ray_normal(mouse)
			var grip := from + dir * _desktop_depth
			blade_active = true
			blade.visible = true
			global_position = grip
			# Blade points up, tilted slightly toward where the camera faces.
			var tilt: Vector3 = -cam.global_transform.basis.z
			tilt.y = 0
			var y_axis := (Vector3.UP * 0.85 + tilt.normalized() * 0.35).normalized()
			var x_axis := y_axis.cross(Vector3.RIGHT)
			if x_axis.length() < 0.01:
				x_axis = y_axis.cross(Vector3.FORWARD)
			x_axis = x_axis.normalized()
			var z_axis := x_axis.cross(y_axis).normalized()
			global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), grip)
		else:
			blade_active = false
			blade.visible = false
			return

	# Hum pitch rises with swing speed for feedback.
	var speed := blade.tip_velocity.length()
	var target := SWING_HUM_BASE + clampf(speed * 22.0, 0.0, 160.0)
	_swing_pitch = lerpf(_swing_pitch, target, minf(delta * 8.0, 1.0))
	blade.set_hum(_swing_pitch, 0.5)


func _update_buckler() -> void:
	var left := _get_left_hand()
	if left:
		buckler_active = true
		_buckler.visible = true
		# Sit slightly toward the wrist, facing outward (palm normal ~ -Y of hand).
		var p: Vector3 = left.global_position + left.global_transform.basis.y * 0.07
		buckler_position = p
		_buckler.global_position = p
		var n: Vector3 = -left.global_transform.basis.z
		if n.length() > 0.001:
			_buckler.global_transform = Transform3D(
				Basis.looking_at(n.normalized()), p)
	elif Input.is_key_pressed(KEY_SPACE):
		# Desktop block: disc left of the camera.
		var cam := get_viewport().get_camera_3d()
		if cam:
			buckler_active = true
			_buckler.visible = true
			var p: Vector3 = cam.global_position \
				+ (-cam.global_transform.basis.z) * 0.45 \
				+ (-cam.global_transform.basis.x) * 0.28 \
				+ Vector3.DOWN * 0.15
			buckler_position = p
			_buckler.global_position = p
			_buckler.global_transform = Transform3D(
				Basis.looking_at((-cam.global_transform.basis.z).normalized()), p)
		else:
			buckler_active = false
			_buckler.visible = false
	else:
		buckler_active = false
		_buckler.visible = false


func _get_right_hand() -> Node3D:
	return _get_hand("RightHand")


func _get_left_hand() -> Node3D:
	return _get_hand("LeftHand")


func _get_hand(hand_name: String) -> Node3D:
	var xr := _find_xr_origin()
	if xr:
		var hand := xr.get_node_or_null(hand_name) as Node3D
		if hand and hand.visible:
			return hand
	return null


func _find_xr_origin() -> Node3D:
	var root := get_tree().current_scene
	if root:
		return root.get_node_or_null("XROrigin3D") as Node3D
	return null
