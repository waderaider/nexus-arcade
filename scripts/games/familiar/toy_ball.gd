## ToyBall.gd - small glowing ball the creature chases in its Playful state.
## Ports ToyBall.cs: bobs gently; any click/tap (pinch) teleports it to a
## spot in front of the player.
extends Node3D
class_name ToyBall

var _ball: MeshInstance3D
var _bob_t := 0.0
var _was_pressed := false

func _ready() -> void:
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_ball.mesh = sphere
	_ball.scale = Vector3.ONE * 0.045
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 1.2
	_ball.material_override = mat
	add_child(_ball)
	_place_in_front_of_player()

func _process(delta: float) -> void:
	_bob_t += delta
	_ball.position = Vector3(0, sin(_bob_t * 2.0) * 0.02, 0)

	# Click rising edge -> respawn near player (pinch stand-in on desktop).
	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not _was_pressed and pressed:
		_place_in_front_of_player()
		_burst()
	_was_pressed = pressed

func _place_in_front_of_player() -> void:
	var cam := get_viewport().get_camera_3d()
	var pos := Vector3(0, 0.3, 0.8)
	if cam:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = Vector3(0, 0, -1)
		fwd = fwd.normalized()
		pos = cam.global_position + fwd * 0.7
		pos.y = maxf(0.05, pos.y - 0.35)
	global_position = pos

func _burst() -> void:
	# Tiny scale pop as feedback for the respawn.
	var tween := create_tween()
	tween.tween_property(_ball, "scale", Vector3.ONE * 0.09, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_ball, "scale", Vector3.ONE * 0.045, 0.18)
