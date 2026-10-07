## laser-tag-ar.gd - "Laser Tag AR": room-scale laser tag arena.
## Semi-transparent cyan barrier boxes line the walls. 3 AI bots wander the
## room and fire red laser beams at the player. Click/tap to fire your own
## yellow laser from the camera toward the click point. Tagging a bot is
## +100 and respawns it elsewhere. Getting tagged costs 1 of 3 lives with a
## red flash. Reach 1000 points within 60 seconds for victory; run out of
## time or lives and it is game over. Desktop/mouse driven; _pinch_active()
## is the XR hand-tracking hook.
extends Node3D

const ROOM_HALF := 5.0
const BOT_COUNT := 3
const GAME_TIME := 60.0
const WIN_SCORE := 1000
const TAG_SCORE := 100
const BEAM_LIFE := 0.22
const SHOT_COOLDOWN := 0.25
const BOT_SPEED := 1.4
const BOT_TAG_CHANCE := 0.45
const PLAYER_REACH := 14.0
# v0.7.0 KayKit: adventurer bodies for the bots (cycled per spawn).
const BOT_MODELS := ["Rogue.glb", "Rogue_Hooded.glb"]

var camera: Camera3D = null
var state := "play" # play | win | lose
var score := 0
var lives := 3
var time_left := GAME_TIME
var shot_cd := 0.0
var bots: Array = [] # Dictionaries: node, visor_mat, target, speed, shoot_timer
var beams: Array = [] # Dictionaries: node, mat, t, max_t
var flash_t := 0.0
var flash_mat: StandardMaterial3D = null
var score_label: Label3D = null
var lives_label: Label3D = null
var timer_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var fire_player: AudioStreamPlayer = null
var tag_player: AudioStreamPlayer = null
var hurt_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _click_consumed := false

# v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_ready := false
var _barriers: Array = []
var _wall_spawn_idx := 0


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_floor()
	_build_barriers()
	_build_hud()
	for i in range(BOT_COUNT):
		_spawn_bot()
	fire_player = _make_player(_make_tone(2200.0, 0.09, 0.5))
	tag_player = _make_player(_make_tone(660.0, 0.18, 0.55))
	hurt_player = _make_player(_make_tone(140.0, 0.3, 0.6))
	end_player = _make_player(_make_tone(392.0, 0.5, 0.5))
	ARUpgradeKit.apply_anchor(self, "laser-tag-ar_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 4.0)
	_apply_room_layout() # v0.7.0: arena follows real room layout (no-op w/o room data).


func _process(delta: float) -> void:
	_poll_pinch()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("laser-tag-ar_main", global_transform)
	if state != "play":
		if Input.is_key_pressed(KEY_R):
			_restart()
		return
	if Input.is_key_pressed(KEY_R):
		_restart()
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_end_game("lose", "TIME UP")
		return
	shot_cd = maxf(0.0, shot_cd - delta)

	# Bots wander and shoot.
	for b in bots:
		var bd: Dictionary = b
		var node: MeshInstance3D = bd["node"]
		if not is_instance_valid(node):
			continue
		var target: Vector3 = bd["target"]
		var to: Vector3 = target - node.position
		to.y = 0.0
		if to.length() < 0.3:
			bd["target"] = _random_room_point()
		else:
			# AILib: seek the waypoint with a wander drift (bots stay floor-level).
			var step_v := AILib.follow(node, target, delta, float(bd["speed"]))
			step_v.y = 0.0
			node.position += step_v + AILib.wander(node, delta, 0.35)
			if _room_ready:
				# Keep bots inside the real room bounds.
				node.position.x = clampf(node.position.x, _room_bounds.position.x + 0.3, _room_bounds.position.x + _room_bounds.size.x - 0.3)
				node.position.z = clampf(node.position.z, _room_bounds.position.y + 0.3, _room_bounds.position.y + _room_bounds.size.y - 0.3)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.z) + PI, delta * 4.0)
		var st := float(bd["shoot_timer"]) - delta
		if st <= 0.0:
			bd["shoot_timer"] = randf_range(2.0, 4.0)
			_bot_shoot(bd)
		else:
			bd["shoot_timer"] = st

	# Fade laser beams.
	for i in range(beams.size() - 1, -1, -1):
		var bm: Dictionary = beams[i]
		var bnode: MeshInstance3D = bm["node"]
		var t := float(bm["t"]) - delta
		if not is_instance_valid(bnode) or t <= 0.0:
			if is_instance_valid(bnode):
				bnode.queue_free()
			beams.remove_at(i)
			continue
		bm["t"] = t
		var bmat: StandardMaterial3D = bm["mat"]
		bmat.emission_energy_multiplier = 3.0 * (t / BEAM_LIFE)

	# Hit flash decay.
	flash_t = maxf(0.0, flash_t - delta * 2.5)
	if flash_mat != null:
		var c := flash_mat.albedo_color
		c.a = 0.45 * flash_t
		flash_mat.albedo_color = c

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click_consumed = true
			if state == "play":
				_player_shoot(mb.position)
			else:
				_restart()


## Hand-tracking hook: XR pinch fires the blaster (mouse still works).
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _poll_pinch() -> void:
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if _click_consumed:
		_click_consumed = false
		return
	if pinched and camera != null and state == "play":
		var wp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		_player_shoot(camera.unproject_position(wp))


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		_attach_flash()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 0.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.4, 4.0), Vector3.UP)
	camera.current = true
	_attach_flash()


func _attach_flash() -> void:
	if camera == null:
		return
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 3.0)
	quad.mesh = plane
	flash_mat = GraphicsPolish.glow(Color(1.0, 0.1, 0.1), 1.0)
	flash_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.0)
	flash_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.no_depth_test = true
	quad.material_override = flash_mat
	quad.position = Vector3(0.0, 0.0, -0.6)
	camera.add_child(quad)


func _room_center3() -> Vector3:
	var c := _room_bounds.get_center()
	return Vector3(c.x, 0.0, c.y)


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_ready = true
	# Barriers line the real walls instead of the default 5m box.
	if not _room_walls.is_empty():
		for b_v in _barriers:
			(b_v as Node).queue_free()
		_barriers.clear()
		var mat := GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 0.8)
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.2, 0.9, 1.0, 0.22)
		for w_v in _room_walls:
			var w: Dictionary = w_v
			var n: Vector3 = (w["normal"] as Vector3).normalized()
			var wall := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3((w["size"] as Vector2).x, 3.0, 0.15)
			wall.mesh = box
			wall.position = to_local(w["position"] as Vector3)
			wall.rotation.y = atan2(n.x, n.z)
			wall.material_override = mat
			add_child(wall)
			_barriers.append(wall)
	# v0.7.0 MORPH: TV becomes the match scoreboard; storage becomes the ammo cache vault.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_tvs := RoomKit.get_anchors("TV")
		if not _morph_tvs.is_empty():
			RoomKit.morph(_morph_tvs[0], "scifi")
		var _morph_storage := RoomKit.get_anchors("STORAGE")
		if not _morph_storage.is_empty():
			RoomKit.morph(_morph_storage[0], "scifi")


func _add_light_rig() -> void:
	# Three-point light rig; skipped if a directional light already exists.
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROOM_HALF * 2.0 + 1.0, ROOM_HALF * 2.0 + 1.0)
	floor_inst.mesh = plane
	var mat := GraphicsPolish.pbr_preset(Color(0.07, 0.07, 0.10), "matte")
	floor_inst.material_override = mat
	add_child(floor_inst)


func _build_barriers() -> void:
	var mat := GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 0.8)
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.9, 1.0, 0.22)
	var defs: Array = [
		[Vector3(0.0, 1.5, -ROOM_HALF), Vector3(ROOM_HALF * 2.0, 3.0, 0.15)],
		[Vector3(0.0, 1.5, ROOM_HALF), Vector3(ROOM_HALF * 2.0, 3.0, 0.15)],
		[Vector3(-ROOM_HALF, 1.5, 0.0), Vector3(0.15, 3.0, ROOM_HALF * 2.0)],
		[Vector3(ROOM_HALF, 1.5, 0.0), Vector3(0.15, 3.0, ROOM_HALF * 2.0)],
	]
	for d in defs:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = d[1]
		wall.mesh = box
		wall.position = d[0]
		wall.material_override = mat
		add_child(wall)
		_barriers.append(wall) # v0.7.0: tracked so room walls can replace them


func _random_room_point() -> Vector3:
	if _room_ready:
		# Arena bounded by the real room floor extents.
		var m := 1.0
		var x := randf_range(_room_bounds.position.x + m, _room_bounds.position.x + _room_bounds.size.x - m)
		var z := randf_range(_room_bounds.position.y + m, _room_bounds.position.y + _room_bounds.size.y - m)
		return ARUpgradeKit.clamp_to_room(Vector3(x, 0.0, z))
	return ARUpgradeKit.clamp_to_room(Vector3(randf_range(-ROOM_HALF + 1.0, ROOM_HALF - 1.0), 0.0, randf_range(-ROOM_HALF + 1.0, ROOM_HALF - 1.0)))


func _spawn_bot() -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 1.1, 0.45)
	body.mesh = box
	var mat := GraphicsPolish.pbr_preset(Color(0.16, 0.16, 0.18), "metal")
	body.material_override = mat
	var visor := MeshInstance3D.new()
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.4, 0.14, 0.05)
	visor.mesh = vbox
	var vmat := GraphicsPolish.glow(Color(1.0, 0.15, 0.15), 2.5)
	visor.material_override = vmat
	visor.position = Vector3(0.0, 0.25, 0.24)
	body.add_child(visor)
	# v0.7.0 KayKit: real adventurer body rides on the bot node so the AILib
	# steering, hit detection and tagging logic keep working untouched.
	var mfile: String = BOT_MODELS[bots.size() % BOT_MODELS.size()]
	if ModelLib.spawn("res://assets/models/laser-tag-ar/" + mfile, body, Vector3(0, -0.9, 0)) != null:
		body.mesh = null # hide the procedural box; the model is the visual now
		visor.position = Vector3(0.0, 0.62, 0.18) # sit on the model's face
	var p: Vector3
	if not _room_walls.is_empty():
		# Bots spawn at opposite real walls, cycling through them.
		var w: Dictionary = _room_walls[_wall_spawn_idx % _room_walls.size()]
		_wall_spawn_idx += 1
		var inward: Vector3 = _room_center3() - (w["position"] as Vector3)
		inward.y = 0.0
		p = to_local((w["position"] as Vector3) + inward.normalized() * 0.7)
	else:
		p = _random_room_point()
		if camera != null and p.distance_to(camera.global_position) < 3.0:
			p = -p
	p.y = 0.9
	body.position = p
	add_child(body)
	bots.append({
		"node": body,
		"visor_mat": vmat,
		"target": _random_room_point(),
		"speed": BOT_SPEED * randf_range(0.85, 1.2),
		"shoot_timer": randf_range(1.0, 3.0),
	})


func _spawn_beam(from: Vector3, to: Vector3, color: Color, width: float) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, dist)
	beam.mesh = box
	var mat := GraphicsPolish.glow(color, 3.0)
	beam.material_override = mat
	add_child(beam)
	beam.position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	beams.append({"node": beam, "mat": mat, "t": BEAM_LIFE})


func _player_shoot(screen_pos: Vector2) -> void:
	if camera == null or shot_cd > 0.0:
		return
	shot_cd = SHOT_COOLDOWN
	if fire_player != null:
		fire_player.play()
	var origin := camera.global_position
	var dir := camera.project_ray_normal(screen_pos)
	var best: Dictionary = {}
	var best_t := PLAYER_REACH
	for b in bots:
		var bd: Dictionary = b
		var node: MeshInstance3D = bd["node"]
		if not is_instance_valid(node):
			continue
		var center: Vector3 = node.global_position
		var rel: Vector3 = center - origin
		var t := rel.dot(dir)
		if t <= 0.2 or t > best_t:
			continue
		var closest: Vector3 = origin + dir * t
		if closest.distance_to(center) < 0.75:
			best = bd
			best_t = t
	var end_point: Vector3 = origin + dir * PLAYER_REACH
	if not best.is_empty():
		var bnode: MeshInstance3D = best["node"]
		end_point = bnode.global_position
		_spawn_beam(origin + dir * 0.4 + Vector3(0.12, -0.1, 0.0), end_point, Color(1.0, 0.9, 0.2), 0.05)
		_on_bot_tagged(best)
	else:
		_spawn_beam(origin + dir * 0.4 + Vector3(0.12, -0.1, 0.0), end_point, Color(1.0, 0.9, 0.2), 0.05)


func _on_bot_tagged(bd: Dictionary) -> void:
	score += TAG_SCORE
	if tag_player != null:
		tag_player.play()
	var node: MeshInstance3D = bd["node"]
	var p := _random_room_point()
	if camera != null and p.distance_to(camera.global_position) < 3.5:
		p = -p
	p.y = 0.9
	if is_instance_valid(node):
		node.position = p
	bd["target"] = _random_room_point()
	bd["shoot_timer"] = randf_range(2.0, 4.0)
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.9, 0.2), 30)
	if score >= WIN_SCORE:
		_end_game("win", "VICTORY")


func _bot_shoot(bd: Dictionary) -> void:
	var node: MeshInstance3D = bd["node"]
	if not is_instance_valid(node) or camera == null:
		return
	var from: Vector3 = node.global_position + Vector3(0.0, 0.25, 0.0)
	var target: Vector3 = camera.global_position
	var dist := from.distance_to(target)
	if dist > 10.0:
		return
	var aim_error := Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.4), randf_range(-0.5, 0.5))
	_spawn_beam(from, target + aim_error, Color(1.0, 0.15, 0.15), 0.045)
	if randf() < BOT_TAG_CHANCE:
		_on_player_tagged()


func _on_player_tagged() -> void:
	lives -= 1
	flash_t = 1.0
	if camera != null:
		GraphicsPolish.spawn_sparks(self, camera.global_position, Color(1.0, 0.2, 0.2), 24)
	if hurt_player != null:
		hurt_player.play()
	if lives <= 0:
		lives = 0
		_end_game("lose", "TAGGED OUT")


func _end_game(new_state: String, msg: String) -> void:
	state = new_state
	if end_player != null:
		end_player.play()
	if new_state == "win" and camera != null:
		GraphicsPolish.spawn_confetti(self, camera.global_position + Vector3(0.0, 0.5, 1.5), 80)
	msg_label.text = "%s\nScore: %d\nClick or press R to play again" % [msg, score]


func _restart() -> void:
	for b in bots:
		var bd: Dictionary = b
		var node: MeshInstance3D = bd["node"]
		if is_instance_valid(node):
			node.queue_free()
	bots.clear()
	for bm in beams:
		var bmd: Dictionary = bm
		var bnode: MeshInstance3D = bmd["node"]
		if is_instance_valid(bnode):
			bnode.queue_free()
	beams.clear()
	score = 0
	lives = 3
	time_left = GAME_TIME
	shot_cd = 0.0
	flash_t = 0.0
	state = "play"
	msg_label.text = ""
	ARUpgradeKit.save_anchor("laser-tag-ar_main", global_transform)
	for i in range(BOT_COUNT):
		_spawn_bot()


func _build_hud() -> void:
	score_label = GraphicsPolish.make_label("Score: 0 / 1000", 48, Color(1, 1, 1))
	score_label.position = Vector3(-2.6, 2.7, 2.5)
	add_child(score_label)
	lives_label = Label3D.new()
	lives_label.position = Vector3(0.4, 2.7, 2.5)
	lives_label.pixel_size = 0.006
	lives_label.font_size = 48
	lives_label.outline_size = 12
	lives_label.modulate = Color(1.0, 0.5, 0.5)
	add_child(lives_label)
	timer_label = Label3D.new()
	timer_label.position = Vector3(-2.6, 2.42, 2.5)
	timer_label.pixel_size = 0.005
	timer_label.font_size = 40
	timer_label.outline_size = 12
	add_child(timer_label)
	msg_label = Label3D.new()
	msg_label.position = Vector3(-1.7, 1.7, 2.5)
	msg_label.pixel_size = 0.008
	msg_label.font_size = 56
	msg_label.outline_size = 12
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(msg_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-2.6, 2.2, 2.5)
	help_label.pixel_size = 0.0035
	help_label.font_size = 26
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.text = "Click a bot to tag it (+100) | reach %d in 60s | R: restart" % WIN_SCORE
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if score_label == null:
		return
	score_label.text = "Score: %d / %d" % [score, WIN_SCORE]
	lives_label.text = "Lives: %d" % lives
	timer_label.text = "Time: %ds" % int(ceil(time_left))


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone for shots / tags / hits.
func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
