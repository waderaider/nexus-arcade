## GolfClub.gd - putter that follows the right hand (XR) or mouse (desktop).
## Ports GolfClub.cs: swing detection tracks tip velocity, fast swing near
## the ball strikes it.
extends Node3D
class_name GolfClub

signal struck

const STRIKE_RANGE := 0.25
const MIN_SWING_SPEED := 1.5
const STRIKE_COOLDOWN := 0.5

var _ball: GolfBall
var _audio: GolfAudio
var _visual: Node3D
var _head: MeshInstance3D
var _prev_tip := Vector3.ZERO
var _has_prev := false
var _cooldown := 0.0

func bind(ball: GolfBall, audio: GolfAudio) -> void:
	_ball = ball
	_audio = audio

func _ready() -> void:
	_build_visuals()

func _build_visuals() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	# Shaft: thin cylinder.
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.7
	shaft.mesh = cyl
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.7, 0.7, 0.75)
	smat.metallic = 0.8
	smat.roughness = 0.3
	shaft.material_override = smat
	shaft.position = Vector3(0, 0.35, 0)
	_visual.add_child(shaft)
	# Head: small box at the bottom.
	_head = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.05, 0.04)
	_head.mesh = box
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.2, 0.2, 0.25)
	hmat.metallic = 0.6
	_head.material_override = hmat
	_head.position = Vector3(0, 0.025, 0)
	_visual.add_child(_head)
	# Grip.
	var grip := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 0.018
	gcyl.bottom_radius = 0.018
	gcyl.height = 0.15
	grip.mesh = gcyl
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.15, 0.15)
	grip.material_override = gmat
	grip.position = Vector3(0, 0.65, 0)
	_visual.add_child(grip)

func _process(delta: float) -> void:
	_cooldown -= delta
	if _ball == null or not is_instance_valid(_ball):
		return

	var tip := _get_tip_position()
	if tip == Vector3.INF:
		_visual.visible = false
		_has_prev = false
		return
	_visual.visible = true

	var dt := maxf(delta, 0.0001)
	var hand_vel := (_prev_tip - tip) / dt if _has_prev else Vector3.ZERO
	# Note: velocity direction is tip movement; we want swing speed.
	var swing_speed := hand_vel.length() if _has_prev else 0.0
	_prev_tip = tip
	_has_prev = true

	# Position the club: head at the tip, shaft up.
	global_position = tip
	# Face the ball.
	var to_ball: Vector3 = _ball.global_position - tip
	to_ball.y = 0
	if to_ball.length() > 0.01:
		rotation.y = atan2(-to_ball.x, -to_ball.z)

	# Strike detection: fast swing within range of the ball.
	if _cooldown <= 0.0 and not _ball.is_holed:
		var dist := tip.distance_to(_ball.global_position)
		if dist < STRIKE_RANGE and swing_speed > MIN_SWING_SPEED:
			_strike(hand_vel)

func _get_tip_position() -> Vector3:
	# Try XR hand first (via OpenXR hand tracking).
	var xr_origin := _find_xr_origin()
	if xr_origin:
		var right_hand := xr_origin.get_node_or_null("RightHand")
		if right_hand:
			# Use the hand's palm position as the tip.
			return (right_hand as Node3D).global_position + Vector3(0, -0.05, -0.08)
	# Fallback: mouse raycast onto the green plane (desktop testing).
	var cam := get_viewport().get_camera_3d()
	if cam:
		var mouse := get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(mouse)
		var dir := cam.project_ray_normal(mouse)
		if absf(dir.y) > 0.001:
			var t := -from.y / dir.y
			if t > 0:
				return from + dir * t + Vector3(0, 0.1, 0)
	return Vector3.INF

func _find_xr_origin() -> Node3D:
	var root := get_tree().current_scene
	if root:
		var xr := root.get_node_or_null("XROrigin3D")
		if xr:
			return xr as Node3D
	return null

func _strike(hand_vel: Vector3) -> void:
	_cooldown = STRIKE_COOLDOWN
	# Hit direction: horizontal component of hand velocity.
	var dir := Vector3(hand_vel.x, 0, hand_vel.z)
	if dir.length() < 0.1:
		dir = -global_transform.basis.z
		dir.y = 0
	dir = dir.normalized()
	var power := clampf(hand_vel.length() * 0.8, 1.0, 6.0)
	_ball.set_velocity(dir * power + Vector3.UP * 0.5)
	struck.emit()
