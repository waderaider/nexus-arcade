extends Node3D
## HwBatDodge - "Bat Dodge": a bat swarm dives at you.
## Dodge with your head/hands (camera-relative lateral movement).
## In XR your head moves the camera; on desktop use A/D or arrow keys
## (W/S for height). Survive 60s — near-misses score, hits cost hearts.
## R restarts; pinch-hold 1s on the results screen restarts.

const ROUND_LENGTH := 60.0
const HEARTS_START := 3
const HIT_RADIUS := 0.42
const GRAZE_RADIUS := 1.15
const INVULN_TIME := 1.2

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var round_time := 0.0
var spawn_timer := 1.0
var hearts := HEARTS_START
var near_misses := 0
var score := 0
var invuln := 0.0
var bats: Array = [] # dicts: node, wl, wr, vel, speed, closest, flap
var hud_label: Label3D = null
var msg_label: Label3D = null
var hearts_label: Label3D = null
var hit_player: AudioStreamPlayer = null
var graze_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0
var won := false


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	_build_moon()
	_build_hud()
	hit_player = _make_player(_make_tone(150.0, 0.3, 0.6))
	graze_player = _make_player(_make_tone(1050.0, 0.09, 0.45))
	win_player = _make_player(_make_tone(880.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_bat_dodge_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.6, -2.0), 3.0, 50)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 2.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, -4.0), Vector3.UP)
	camera.current = true


func _build_moon() -> void:
	# Big spooky moon backdrop.
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 1.4
	ms.height = 2.8
	moon.mesh = ms
	moon.position = Vector3(0.0, 3.2, -12.0)
	moon.material_override = GraphicsPolish.glow(Color(0.95, 0.93, 0.80), 1.1)
	add_child(moon)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.5, -6.0), Color(0.7, 0.6, 1.0), 0.7, 8.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("BAT DODGE", 44, Color(0.9, 0.7, 1.0))
	hud_label.position = Vector3(-2.7, 2.7, -0.4)
	add_child(hud_label)
	hearts_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.35, 0.35))
	hearts_label.position = Vector3(2.4, 2.7, -0.4)
	add_child(hearts_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.2, -2.0)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("DODGE! Move: head (XR) or A/D + W/S (desktop). Near-miss = +100.  R: restart", 28, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.35, -0.4)
	add_child(help)


func _cam_pos() -> Vector3:
	if camera != null:
		return camera.global_position
	return Vector3(0.0, 1.6, 2.6)


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_bat_dodge_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			restart_hold += delta
			if restart_hold >= 1.0:
				_reset_game()
				return
		else:
			restart_hold = 0.0
		return
	round_time += delta
	if invuln > 0.0:
		invuln -= delta
	if not ARUpgradeKit.is_xr_active():
		_move_camera_desktop(delta)
	# Spawn bats faster as time goes on.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var k := round_time / ROUND_LENGTH
		spawn_timer = lerpf(1.2, 0.45, k)
		_spawn_bat(lerpf(3.0, 6.0, k))
	_step_bats(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	if round_time >= ROUND_LENGTH:
		_game_over(true)
	_update_hud()


func _move_camera_desktop(delta: float) -> void:
	if camera == null:
		return
	var mx := 0.0
	var my := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mx -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mx += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		my += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		my -= 1.0
	camera.position.x = clampf(camera.position.x + mx * 2.4 * delta, -1.6, 1.6)
	camera.position.y = clampf(camera.position.y + my * 1.8 * delta, 0.8, 2.6)


func _spawn_bat(speed: float) -> void:
	var cp := _cam_pos()
	var node := Node3D.new()
	node.position = cp + Vector3(randf_range(-3.0, 3.0), randf_range(-0.5, 2.2), -7.0)
	# Body.
	var body := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.11
	bs.height = 0.22
	body.mesh = bs
	body.material_override = GraphicsPolish.pbr(Color(0.08, 0.06, 0.12), 0.0, 0.7)
	node.add_child(body)
	# Glowing red eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.025
		es.height = 0.05
		eye.mesh = es
		eye.material_override = GraphicsPolish.glow(Color(1.0, 0.15, 0.1), 2.5)
		eye.position = Vector3(side * 0.05, 0.04, -0.08)
		node.add_child(eye)
	# Flapping wings.
	var wl := _make_wing(-1.0)
	var wr := _make_wing(1.0)
	node.add_child(wl)
	node.add_child(wr)
	add_child(node)
	var target := cp + Vector3(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), 0.0)
	var vel := (target - node.position).normalized() * speed
	bats.append({
		"node": node, "wl": wl, "wr": wr, "vel": vel,
		"speed": speed, "closest": 999.0, "flap": randf() * TAU,
	})


func _make_wing(side: float) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.42, 0.22)
	wing.mesh = pm
	wing.material_override = GraphicsPolish.pbr(Color(0.12, 0.08, 0.18), 0.0, 0.8)
	wing.position = Vector3(side * 0.24, 0.02, 0.02)
	wing.rotation.y = PI * 0.5 if side < 0.0 else -PI * 0.5
	return wing


func _step_bats(delta: float) -> void:
	var cp := _cam_pos()
	for i in range(bats.size() - 1, -1, -1):
		var b: Dictionary = bats[i]
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			bats.remove_at(i)
			continue
		# Slight homing toward the player.
		var speed := float(b["speed"])
		var desired := (cp - node.position).normalized() * speed
		var vel: Vector3 = b["vel"]
		vel = vel.lerp(desired, clampf(0.8 * delta, 0.0, 1.0)).normalized() * speed
		b["vel"] = vel
		node.position += vel * delta
		node.look_at(cp, Vector3.UP)
		# Flap wings.
		b["flap"] = float(b["flap"]) + delta * 18.0
		var flap := sin(float(b["flap"]))
		(b["wl"] as MeshInstance3D).rotation.z = 0.25 + flap * 0.7
		(b["wr"] as MeshInstance3D).rotation.z = -0.25 - flap * 0.7
		var d: float = node.position.distance_to(cp)
		b["closest"] = minf(float(b["closest"]), d)
		# Hit?
		if d < HIT_RADIUS and invuln <= 0.0:
			_on_hit(i, node)
			continue
		# Passed the player plane?
		var to_bat: Vector3 = node.position - cp
		if to_bat.z > 0.6 or node.position.distance_to(cp) > 12.0:
			_on_pass(i, b, node)


func _on_hit(i: int, node: Node3D) -> void:
	bats.remove_at(i)
	GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.2, 0.15), 24)
	node.queue_free()
	hearts -= 1
	invuln = INVULN_TIME
	_show_msg("OUCH!  %d hearts left" % maxi(hearts, 0), 1.0)
	if hit_player != null:
		hit_player.play()
	if hearts <= 0:
		_game_over(false)


func _on_pass(i: int, b: Dictionary, node: Node3D) -> void:
	bats.remove_at(i)
	var closest := float(b["closest"])
	node.queue_free()
	if closest < GRAZE_RADIUS:
		near_misses += 1
		var gained := 100
		score += gained
		_show_msg("NEAR MISS! +%d" % gained, 0.7)
		GraphicsPolish.spawn_sparks(self, _cam_pos() + Vector3(0, 0.1, -0.5), Color(0.6, 0.8, 1.0), 10)
		if graze_player != null:
			graze_player.play()


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := int(maxf(0.0, ROUND_LENGTH - round_time))
	hud_label.text = "BAT DODGE\nNear-miss: %d   Score: %d\nSurvive: %ds" % [near_misses, score, left]
	var h := ""
	for i in range(HEARTS_START):
		h += "<3 " if i < hearts else "-- "
	hearts_label.text = h


func _game_over(did_win: bool) -> void:
	state = ST_OVER
	won = did_win
	for b_v in bats:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	bats.clear()
	ARUpgradeKit.save_anchor("hw_bat_dodge_main", global_transform)
	if did_win:
		var bonus := hearts * 500
		score += bonus
		_show_msg("YOU SURVIVED!\nNear-miss: %d  Heart bonus: +%d\nScore: %d\nR: play again" % [near_misses, bonus, score], 600.0)
		GraphicsPolish.spawn_confetti(self, _cam_pos() + Vector3(0, 1.0, -2.0), 90)
		if win_player != null:
			win_player.play()
	else:
		_show_msg("SWARMED!\nSurvived %ds  Score: %d\nR: try again" % [int(round_time), score], 600.0)


func _reset_game() -> void:
	for b_v in bats:
		var b: Dictionary = b_v
		var node: Node3D = b["node"]
		if is_instance_valid(node):
			node.queue_free()
	bats.clear()
	round_time = 0.0
	spawn_timer = 1.0
	hearts = HEARTS_START
	near_misses = 0
	score = 0
	invuln = 0.0
	won = false
	restart_hold = 0.0
	state = ST_PLAY
	_show_msg("DODGE THE SWARM!", 1.2)
	ARUpgradeKit.save_anchor("hw_bat_dodge_main", global_transform)


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames_count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames_count * 2)
	for i in range(frames_count):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames_count)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
