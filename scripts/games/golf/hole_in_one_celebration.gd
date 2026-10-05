## HoleInOneCelebration.gd - the Familiar creature crashes the golf course.
## Ports HoleInOneCelebration.cs: on a hole-in-one, a Wisp-stage blob hops in
## beside the cup, pops the ball out, juggles it, dances with confetti,
## shows a "HOLE IN ONE!" banner, then hops away.
extends Node
class_name HoleInOneCelebration

const DURATION := 4.2

var _audio: GolfAudio

func setup(audio: GolfAudio) -> void:
	_audio = audio

func play(ball: GolfBall, cup_pos: Vector3, green_top_y: float) -> void:
	_routine(ball, cup_pos, green_top_y)

func _routine(ball: GolfBall, cup_pos: Vector3, green_top_y: float) -> void:
	if not is_instance_valid(ball):
		return

	# 1. Creature hops in beside the cup.
	var buddy := _make_wisp()
	var spawn := cup_pos + Vector3(0.45, green_top_y, 0.3)
	buddy.global_position = spawn
	add_child(buddy)
	var park_spot := cup_pos + Vector3(0.28, green_top_y, 0.18)
	_hop_to(buddy, park_spot)
	await get_tree().create_timer(0.7).timeout

	# 2. Pop the ball out and juggle it: three happy hops.
	ball.scale = Vector3.ONE
	for i in 3:
		var from: Vector3 = ball.global_position
		var to := cup_pos + Vector3(randf_range(-0.12, 0.12), green_top_y + 0.05, randf_range(-0.12, 0.12))
		_happy_bounce(buddy)
		var t := 0.0
		while t < 0.45:
			t += get_process_delta_time()
			var k := clampf(t / 0.45, 0.0, 1.0)
			var p: Vector3 = from.lerp(to, k)
			p.y += sin(k * PI) * 0.16
			ball.global_position = p
			await get_tree().process_frame
		_spawn_confetti(to, Color(1.0, 0.85, 0.3), 8)

	# 3. Big finish: dance + spin + confetti cannons.
	_dance(buddy)
	for i in 3:
		var p := cup_pos + Vector3(randf_range(-0.4, 0.4), green_top_y + 0.25, randf_range(-0.4, 0.4))
		var c := Color.YELLOW if i == 0 else (Color.CYAN if i == 1 else Color(1.0, 0.45, 0.8))
		_spawn_confetti(p, c, 22)
		if _audio:
			_audio.fanfare()
		await get_tree().create_timer(0.35).timeout

	# 4. Floating banner, then the buddy hops off.
	var banner := _make_banner("HOLE IN ONE!")
	banner.global_position = cup_pos + Vector3.UP * 0.75
	add_child(banner)
	var banner_t := 0.0
	while banner_t < 1.6:
		banner_t += get_process_delta_time()
		banner.global_position += Vector3.UP * get_process_delta_time() * 0.12
		# Face the camera.
		var cam := get_viewport().get_camera_3d()
		if cam:
			var dir: Vector3 = (cam.global_position - banner.global_position).normalized()
			banner.rotation.y = atan2(-dir.x, -dir.z)
		await get_tree().process_frame
	banner.queue_free()

	_hop_to(buddy, spawn + Vector3(0.8, 0, 0.6))
	await get_tree().create_timer(1.0).timeout

	# Shrink away.
	var s := 0.0
	var start_scale: Vector3 = buddy.scale
	while s < 0.5:
		s += get_process_delta_time()
		buddy.scale = start_scale * (1.0 - clampf(s / 0.5, 0.0, 1.0))
		await get_tree().process_frame
	buddy.queue_free()

## Minimal Wisp creature: a glowing blob that can hop/bounce/dance.
func _make_wisp() -> Node3D:
	var root := Node3D.new()
	root.name = "HoleInOneBuddy"
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	body.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.5
	body.material_override = mat
	root.add_child(body)
	# Eyes.
	for x in [-0.05, 0.05]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		eye.mesh = es
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.1, 0.1, 0.15)
		eye.material_override = emat
		eye.position = Vector3(x, 0.05, 0.09)
		root.add_child(eye)
	root.set_meta("vel_y", 0.0)
	return root

func _hop_to(node: Node3D, target: Vector3) -> void:
	# Simple parabolic hop via tween.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "global_position:x", target.x, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "global_position:z", target.z, 0.5).set_trans(Tween.TRANS_SINE)
	var mid := node.global_position.lerp(target, 0.5) + Vector3.UP * 0.25
	tw.tween_property(node, "global_position:y", mid.y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(node, "global_position:y", target.y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _happy_bounce(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.2, 0.8, 1.2), 0.15)
	tw.tween_property(node, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BOUNCE)

func _dance(node: Node3D) -> void:
	var tw := create_tween().set_loops(4)
	tw.tween_property(node, "rotation:y", node.rotation.y + PI, 0.4)
	tw.tween_property(node, "position:y", node.position.y + 0.1, 0.2)
	tw.tween_property(node, "position:y", node.position.y, 0.2)

func _spawn_confetti(at: Vector3, color: Color, count: int) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -4, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.05
	mat.color = color
	p.process_material = mat
	var quad := QuadMesh.new()
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = color
	qmat.emission_enabled = true
	qmat.emission = color
	quad.material = qmat
	p.draw_pass_1 = quad
	p.global_position = at
	add_child(p)
	p.emitting = true
	# Auto-cleanup.
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

func _make_banner(text: String) -> Node3D:
	var root := Node3D.new()
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.002
	label.modulate = Color(1.0, 0.9, 0.2)
	label.outline_size = 12
	label.outline_modulate = Color(0.1, 0.1, 0.1)
	root.add_child(label)
	return root
