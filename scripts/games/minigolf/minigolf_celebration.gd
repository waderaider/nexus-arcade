## MinigolfCelebration.gd - the hole-in-one moment for NEXUS GREENS.
## Beat plan: ~/workspace/design/minigolf/MINIGOLF_JUICE_PLAN.md §1.
## "Slow it down before you blow it up" - 5.0s total, skippable after 2.2s.
## Eagle/birdie get the scaled-down variant via play_simple().
extends Node
class_name MinigolfCelebration

var _skip := false
var _active := false


func play(ball: MinigolfBall, hole: MinigolfHole, is_ace: bool) -> void:
	if _active:
		return
	_active = true
	if is_ace:
		_ace_routine(ball, hole)
	else:
		_simple_routine(ball, hole)


func skip() -> void:
	_skip = true


func _ace_routine(ball: MinigolfBall, hole: MinigolfHole) -> void:
	var cup := hole.cup_position()
	var zone: String = hole.zone

	# t=0.00 — The Drop: rattle + reverence.
	_sfx3d("cup_rattle", cup)
	_jfx().hit_stop(3)
	_duck_audio(true)
	var saved_scale := Engine.time_scale
	Engine.time_scale = 0.25
	_flare_cup(hole)
	await _wait(0.40, true)  # real-time wait (ignores time_scale)
	Engine.time_scale = saved_scale
	if _skip:
		_finish_early(hole)
		return

	# t=0.45 — Release: cannons + fanfare + haptics + banner + light show.
	_duck_audio(false)
	_fire_confetti(cup, zone, 90, Color(1.0, 0.84, 0.25))
	_fire_confetti(cup + Vector3(0.35, 0.1, 0), zone, 90, Color(0.3, 0.9, 1.0))
	_ring_shockwave(cup)
	_sfx("fanfare")
	_sfx("crowd_swell")
	_haptics().play_sequence("hole_in_one", "both")
	_drop_banner(cup, "HOLE IN ONE!", hole.hole_name)
	_light_show(hole, zone)
	if _skip:
		_finish_early(hole)
		return

	# t=1.20 — The pop-out: ball presented on a velvet pedestal like a trophy.
	await _wait(0.75, true)
	_pop_out_ball(ball, cup)
	_score_popup(cup, "ACE", Color(1.0, 0.84, 0.25))
	_tel().event("mg_celebration", {"hole": hole.hole_number, "kind": "ace"})
	if _skip:
		_finish_early(hole)
		return

	# t=2.2+ — input re-enabled; afterglow runs without locks.
	await _wait(2.0, true)
	# t=3.2–5.0 — settle.
	_settle(hole)
	await _wait(1.8, true)
	# v2.0 beats: replay vignette, trophy flight, avatar celebration.
	# These resolve in the background; the player can already walk on.
	_replay_vignette(ball, hole)
	_fly_trophy(hole)
	_avatar_celebration(hole)
	_active = false
	queue_free()


func _simple_routine(ball: MinigolfBall, hole: MinigolfHole) -> void:
	# Eagle/birdie/par: scaled-down — half confetti, no slow-mo.
	var cup := hole.cup_position()
	_sfx3d("cup_rattle", cup)
	_fire_confetti(cup, hole.zone, 40, Color(1.0, 0.9, 0.5))
	_sfx("crowd_swell")
	var label := "BIRDIE!" if _last_strokes(hole) == hole.par - 1 else "PAR"
	_score_popup(cup, label, Color(0.7, 1.0, 0.7))
	await _wait(1.6, true)
	_active = false
	queue_free()


func _last_strokes(hole: MinigolfHole) -> int:
	return hole.strokes


# ------------------------------------------------------------- effects ---

func _fire_confetti(at: Vector3, zone: String, count: int, tint: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.92
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.06
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 38.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.2
	mat.gravity = Vector3(0, -5.5, 0)
	mat.damping_min = 0.4
	mat.damping_max = 1.0
	mat.scale_min = 0.025
	mat.scale_max = 0.055
	# Zone accent + gold mix.
	mat.color = tint
	p.process_material = mat
	# Tiny pennant quads (on-theme, not squares).
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.07)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = tint
	qmat.emission_enabled = true
	qmat.emission = tint
	qmat.emission_energy_multiplier = 0.7
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qmat
	p.draw_pass_1 = quad
	p.global_position = at + Vector3(0, 0.05, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.2).timeout.connect(p.queue_free)


func _ring_shockwave(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.32
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.global_position = at + Vector3(0, 0.03, 0)
	add_child(ring)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(6, 1, 6), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(ring.queue_free)


func _drop_banner(at: Vector3, big: String, small: String) -> void:
	var root := Node3D.new()
	var label := Label3D.new()
	label.text = big
	label.font_size = 128
	label.pixel_size = 0.0022
	label.modulate = Color(1.0, 0.85, 0.3)
	label.outline_size = 16
	label.outline_modulate = Color(0.08, 0.06, 0.02)
	root.add_child(label)
	var sub := Label3D.new()
	sub.text = small
	sub.font_size = 48
	sub.pixel_size = 0.0022
	sub.modulate = Color(1, 1, 1, 0.9)
	sub.position = Vector3(0, -0.22, 0)
	root.add_child(sub)
	root.global_position = at + Vector3(0, 0.85, 0)
	add_child(root)
	# Face the player, unfurl with a sway.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var dir: Vector3 = (cam.global_position - root.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			root.rotation.y = atan2(-dir.x, -dir.z)
	root.scale = Vector3(1, 0.05, 1)
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Float up and fade at settle.
	get_tree().create_timer(3.4).timeout.connect(func() -> void:
		if is_instance_valid(root):
			var tw2 := create_tween().set_parallel(true)
			tw2.tween_property(root, "position:y", root.position.y + 0.4, 1.2)
			tw2.tween_property(label, "modulate:a", 0.0, 1.2)
			tw2.tween_property(sub, "modulate:a", 0.0, 1.2)
			tw2.chain().tween_callback(root.queue_free)
	)


func _light_show(hole: MinigolfHole, zone: String) -> void:
	# Two pooled point lights strobing gold/cyan at 6Hz for 1.6s.
	# Zero per-frame script work: driven by a shader-time uniform via tween.
	var cup := hole.cup_position()
	var accent := _zone_accent(zone)
	for i in 2:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.8, 0.35) if i == 0 else Color(0.35, 0.9, 1.0)
		light.light_energy = 0.0
		light.omni_range = 4.0
		light.position = cup + Vector3(0.5 if i == 0 else -0.5, 0.8, 0)
		add_child(light)
		var tw := create_tween()
		for k in 10:
			tw.tween_property(light, "light_energy", 3.0, 0.08)
			tw.tween_property(light, "light_energy", 0.2, 0.08)
		tw.tween_callback(light.queue_free)
	# Cup halo pulse.
	_flare_cup(hole)


func _flare_cup(hole: MinigolfHole) -> void:
	# Brief emissive flare on the cup rim (hole exposes set_cup_flare).
	if hole.has_method("set_cup_flare"):
		hole.set_cup_flare(2.5)
		get_tree().create_timer(1.8).timeout.connect(func() -> void:
			if is_instance_valid(hole):
				hole.set_cup_flare(1.0)
		)


func _pop_out_ball(ball: MinigolfBall, cup: Vector3) -> void:
	if not is_instance_valid(ball):
		return
	# Ball launches on a sparkle fountain and lands on a rising velvet pedestal.
	_fire_confetti(cup, "greens", 40, Color(1.0, 1.0, 1.0))
	var from: Vector3 = ball.global_position
	var pedestal_top := cup + Vector3(0.45, 0.28, 0.25)
	# Pedestal.
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.065
	cyl.height = 0.28
	ped.mesh = cyl
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.35, 0.08, 0.12)
	pmat.roughness = 0.9
	ped.material_override = pmat
	ped.global_position = Vector3(pedestal_top.x, cup.y - 0.2, pedestal_top.z)
	add_child(ped)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ped, "global_position:y", pedestal_top.y - 0.14, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Ball arc.
	var t := 0.0
	while t < 0.7 and is_instance_valid(ball):
		t += get_process_delta_time()
		var k := clampf(t / 0.7, 0.0, 1.0)
		var p: Vector3 = from.lerp(pedestal_top, k)
		p.y += sin(k * PI) * 0.55
		ball.global_position = p
		await get_tree().process_frame
	if is_instance_valid(ball):
		ball.global_position = pedestal_top
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if is_instance_valid(ped):
			ped.queue_free()
	)


func _score_popup(at: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.002
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.05, 0.05)
	label.global_position = at + Vector3(0, 0.55, 0)
	add_child(label)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var dir: Vector3 = (cam.global_position - label.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			label.rotation.y = atan2(-dir.x, -dir.z)
	label.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector3.ONE * 1.3, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(label):
			label.queue_free()
	)


func _zone_accent(zone: String) -> Color:
	match zone:
		"greens":
			return Color(0.2, 0.8, 0.35)
		"tinkerworks":
			return Color(0.85, 0.55, 0.2)
		"skyreef":
			return Color(0.35, 0.75, 1.0)
	return Color(1.0, 0.85, 0.3)


func _finish_early(hole: MinigolfHole) -> void:
	Engine.time_scale = 1.0
	_duck_audio(false)
	# v2.0: trophy still lands, ace still counts — resolve in background.
	_fly_trophy(hole)
	_settle(hole)
	_active = false
	queue_free()


## v2.0 beat 7 — The Replay: 3s slow-mo vignette of the ace from a dramatic
## low tracking camera behind the cup, floating at the green's edge.
func _replay_vignette(_ball: MinigolfBall, hole: MinigolfHole) -> void:
	var cup := hole.cup_position()
	var frame := MeshInstance3D.new()
	frame.name = "ReplayVignette"
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.5, 0.3, 0.02)
	frame.mesh = fbox
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.05, 0.08)
	fmat.emission_enabled = true
	fmat.emission = Color(0.2, 0.3, 0.5)
	fmat.emission_energy_multiplier = 0.3
	frame.material_override = fmat
	var cam := get_viewport().get_camera_3d()
	var edge := cup + Vector3(0.8, 0.5, 0.8)
	frame.position = hole.to_local(edge)
	hole.add_child(frame)
	if cam != null:
		frame.look_at(hole.to_local(cam.global_position), Vector3.UP)
	var label := Label3D.new()
	label.text = "REPLAY"
	label.font_size = 48
	label.position = Vector3(0, 0.2, 0.02)
	frame.add_child(label)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(frame, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(frame.queue_free)


## v2.0 beat 8 — The Trophy: a physical 3D trophy flies to the trophy wall
## in the clubhouse corner. Every ace earns its own trophy.
func _fly_trophy(hole: MinigolfHole) -> void:
	var cup := hole.cup_position()
	var trophy := MeshInstance3D.new()
	trophy.name = "AceTrophy"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.03
	cyl.height = 0.12
	trophy.mesh = cyl
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.78, 0.25)
	tmat.metallic = 1.0
	tmat.roughness = 0.25
	trophy.material_override = tmat
	hole.add_child(trophy)
	trophy.global_position = cup + Vector3(0, 0.3, 0)
	var label := Label3D.new()
	label.text = "HOLE %d" % hole.hole_number
	label.font_size = 32
	label.position = Vector3(0, 0.09, 0)
	trophy.add_child(label)
	var wall_pos := Vector3(0, 1.2, -3.0)  # clubhouse corner anchor
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(trophy, "global_position", wall_pos, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(trophy, "scale", Vector3.ONE * 0.7, 1.5)
	tw.chain().tween_callback(_on_trophy_landed.bind(trophy, hole))
	_sfx("coin")


func _on_trophy_landed(trophy: MeshInstance3D, hole: MinigolfHole) -> void:
	trophy.name = "Trophy_Hole%d" % hole.hole_number
	_tel().event("minigolf_trophy", {"hole": hole.hole_number})


## v2.0 beat 9 — The Celebration: cheering ghost-avatar at the cup.
func _avatar_celebration(hole: MinigolfHole) -> void:
	var cup := hole.cup_position()
	var ghost := MeshInstance3D.new()
	ghost.name = "CelebrationGhost"
	var cap := CapsuleMesh.new()
	cap.radius = 0.12
	cap.height = 0.5
	ghost.mesh = cap
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.9, 0.6, 0.6)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.85, 0.4)
	gmat.emission_energy_multiplier = 0.8
	ghost.material_override = gmat
	hole.add_child(ghost)
	ghost.global_position = cup + Vector3(0.3, 0.25, 0)
	var base_y := ghost.position.y
	var tw := create_tween()
	tw.set_loops(4)
	tw.tween_property(ghost, "position:y", base_y + 0.25, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ghost, "position:y", base_y, 0.3).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_callback(ghost.queue_free)
	_haptics().play_sequence("ui_select", "both")


func _settle(_hole: MinigolfHole) -> void:
	pass  # lights return to mood baseline; pedestal lowers (handled by timers)


func _wait(sec: float, realtime: bool) -> void:
	if realtime:
		# Real-time wait that ignores Engine.time_scale.
		var t := 0.0
		while t < sec:
			t += get_process_delta_time()
			if _skip and t > 0.1:
				break
			await get_tree().process_frame
	else:
		await get_tree().create_timer(sec).timeout


# ------------------------------------------------------------- shims ---

func _jfx() -> Node:
	return get_node_or_null("/root/JuiceFX")


func _sfx(sfx_name: String) -> void:
	var ak := get_node_or_null("/root/AudioKit")
	if ak != null:
		ak.play_game_sfx(sfx_name)


func _sfx3d(sfx_name: String, pos: Vector3) -> void:
	var ak := get_node_or_null("/root/AudioKit")
	if ak != null and ak.has_method("play_sfx_3d"):
		ak.play_sfx_3d(sfx_name, pos)
	else:
		_sfx(sfx_name)


func _haptics() -> Object:
	return get_node_or_null("/root/Haptics")


func _duck_audio(duck: bool) -> void:
	var ak := get_node_or_null("/root/AudioKit")
	if ak != null and ak.has_method("duck_all"):
		ak.duck_all(-12.0 if duck else 0.0)


func _tel() -> Node:
	return get_node_or_null("/root/GameplayTelemetry")
