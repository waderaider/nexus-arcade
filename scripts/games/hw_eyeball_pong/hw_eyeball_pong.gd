## HwEyeballPong - "Eyeball Pong": pong versus a ghost AI, played with a
## giant eyeball. Your paddle follows your hand (mouse on desktop); pinch
## (or click) for a smash. First to 7 wins. R restarts; hold pinch 1s on the
## end screen to play again.
extends Node3D

const X_HALF := 1.2
const Y_MIN := 0.55
const Y_MAX := 2.05
const FIELD_Z := -2.0
const BALL_R := 0.09
const PADDLE_W := 0.42
const WIN_SCORE := 7
const BASE_SPEED := 1.7
const MAX_SPEED := 4.6
const GHOST_SPEED := 2.0

const ST_SERVE := 0
const ST_PLAY := 1
const ST_OVER := 2

var camera: Camera3D = null
var state := ST_SERVE
var player_score := 0
var ghost_score := 0
var ball: Node3D = null
var ball_vel := Vector2.ZERO
var player_paddle: MeshInstance3D = null
var ghost_root: Node3D = null
var player_mat: StandardMaterial3D = null
var ghost_mat: StandardMaterial3D = null
var player_x := 0.0
var ghost_x := 0.0
var ghost_err := 0.0
var serve_timer := 1.0
var serve_dir := 1.0
var smash_armed := false
var smash_cooldown := 0.0
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var paddle_player: AudioStreamPlayer = null
var wall_player: AudioStreamPlayer = null
var score_player: AudioStreamPlayer = null
var smash_player: AudioStreamPlayer = null
var lose_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0

## RoomKit v0.7.0: cached room layout (world space; converted to local at use).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_field()
	_build_hud()
	paddle_player = _make_player(_make_tone(500.0, 0.10, 0.50))
	wall_player = _make_player(_make_tone(350.0, 0.08, 0.40))
	score_player = _make_player(_make_tone(760.0, 0.30, 0.50))
	smash_player = _make_player(_make_tone(1400.0, 0.20, 0.60))
	lose_player = _make_player(_make_tone(180.0, 0.60, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_eyeball_pong_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.3, -1.8), 2.2, 30)
	_serve(1.0)
	_apply_room_layout()


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.35, 0.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.30, -2.0), Vector3.UP)
	camera.current = true


func _build_field() -> void:
	# Dark backdrop panel for contrast.
	var back := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.2, 2.2)
	back.mesh = pm
	back.position = Vector3(0.0, 1.30, FIELD_Z - 0.15)
	back.material_override = GraphicsPolish.pbr(Color(0.04, 0.05, 0.10), 0.0, 0.9)
	add_child(back)
	# Glowing side rails.
	var rail_mat := GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 1.6)
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.06, Y_MAX - Y_MIN + 0.2, 0.10)
		rail.mesh = rb
		rail.position = Vector3(sx * (X_HALF + 0.03), (Y_MIN + Y_MAX) * 0.5, FIELD_Z)
		rail.material_override = rail_mat
		add_child(rail)
	# Center line.
	var line := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(X_HALF * 2.0, 0.02, 0.02)
	line.mesh = lb
	line.position = Vector3(0.0, (Y_MIN + Y_MAX) * 0.5, FIELD_Z)
	line.material_override = GraphicsPolish.glow(Color(0.5, 0.5, 0.6), 1.0)
	add_child(line)
	# Player paddle (cyan).
	player_paddle = MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(PADDLE_W, 0.07, 0.12)
	player_paddle.mesh = pb
	player_mat = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 1.8)
	player_paddle.material_override = player_mat
	player_paddle.position = Vector3(0.0, Y_MIN + 0.08, FIELD_Z)
	add_child(player_paddle)
	# Ghost paddle: spooky floating ghost at the top.
	ghost_root = Node3D.new()
	ghost_root.position = Vector3(0.0, Y_MAX - 0.08, FIELD_Z)
	add_child(ghost_root)
	ghost_mat = GraphicsPolish.glow(Color(0.95, 0.95, 1.0), 1.3)
	var gpaddle := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(PADDLE_W, 0.07, 0.12)
	gpaddle.mesh = gb
	gpaddle.material_override = ghost_mat
	ghost_root.add_child(gpaddle)
	var gbody := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.14
	gs.height = 0.34
	gbody.mesh = gs
	gbody.scale = Vector3(1.0, 1.4, 0.7)
	gbody.position = Vector3(0.0, 0.22, 0.0)
	var gmat := GraphicsPolish.pbr_preset(Color(0.9, 0.9, 1.0), "glass")
	gbody.material_override = gmat
	ghost_root.add_child(gbody)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.03
		es.height = 0.06
		eye.mesh = es
		eye.position = Vector3(ex, 0.28, -0.09)
		eye.material_override = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 2.0)
		ghost_root.add_child(eye)
	# The eyeball.
	ball = Node3D.new()
	ball.position = Vector3(0.0, 1.30, FIELD_Z)
	add_child(ball)
	var white := MeshInstance3D.new()
	var ws := SphereMesh.new()
	ws.radius = BALL_R
	ws.height = BALL_R * 2.0
	white.mesh = ws
	white.material_override = GraphicsPolish.pbr(Color(0.95, 0.95, 0.92), 0.0, 0.35)
	ball.add_child(white)
	var iris := MeshInstance3D.new()
	var ins := SphereMesh.new()
	ins.radius = 0.045
	ins.height = 0.09
	iris.mesh = ins
	iris.position = Vector3(0.0, 0.0, -0.055)
	iris.material_override = GraphicsPolish.glow(Color(0.2, 0.9, 0.3), 1.8)
	ball.add_child(iris)
	var pupil := MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = 0.022
	ps.height = 0.044
	pupil.mesh = ps
	pupil.position = Vector3(0.0, 0.0, -0.080)
	pupil.material_override = GraphicsPolish.pbr(Color(0.02, 0.02, 0.02), 0.0, 0.4)
	ball.add_child(pupil)
	ball.add_child(GraphicsPolish.make_trail(Color(1.0, 1.0, 1.0), 0.05))


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("EYEBALL PONG", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.4, 2.9, -1.2)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Move hand / mouse to slide paddle - pinch / click to SMASH!  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.4, 2.35, -1.2)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.6, -1.6)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "EYEBALL PONG  (First to %d)\nYou %d : %d Ghost" % [WIN_SCORE, player_score, ghost_score]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_eyeball_pong_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if player_mat != null:
		GraphicsPolish.pulse_glow(player_mat, 1.5, 0.7, _time, 3.0)
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_pinch_hold += delta
			if _pinch_hold >= 1.0:
				_pinch_hold = 0.0
				_reset_game()
		else:
			_pinch_hold = 0.0
		_update_hud()
		return
	_update_player_paddle()
	_update_ghost(delta)
	if smash_cooldown > 0.0:
		smash_cooldown -= delta
	if state == ST_SERVE:
		serve_timer -= delta
		ball.position = Vector3(0.0, 1.30, FIELD_Z)
		if serve_timer <= 0.0:
			state = ST_PLAY
			_show_msg("")
	elif state == ST_PLAY:
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
				or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
			_try_smash()
		_step_ball(delta)
	_update_hud()


func _player_target_x() -> float:
	var x := 0.0
	if ARUpgradeKit.is_xr_active():
		x = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT).x
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mp)
		var dir := camera.project_ray_normal(mp)
		if absf(dir.z) > 0.001:
			var t := (FIELD_Z - origin.z) / dir.z
			if t > 0.0:
				x = (origin + dir * t).x
	return clampf(x, -(X_HALF - PADDLE_W * 0.5), X_HALF - PADDLE_W * 0.5)


func _update_player_paddle() -> void:
	player_x = lerpf(player_x, _player_target_x(), minf(1.0, 14.0 * get_process_delta_time()))
	player_paddle.position.x = player_x


func _update_ghost(delta: float) -> void:
	# Spooky hover bob.
	ghost_root.position.y = Y_MAX - 0.08 + 0.05 * sin(_time * 3.0)
	var target := 0.0
	if state == ST_PLAY and ball_vel.y > 0.0:
		target = clampf(ball.position.x + ghost_err, -(X_HALF - PADDLE_W * 0.5), X_HALF - PADDLE_W * 0.5)
	ghost_x = move_toward(ghost_x, target, GHOST_SPEED * delta)
	ghost_root.position.x = ghost_x


func _try_smash() -> void:
	if state != ST_PLAY or smash_cooldown > 0.0:
		return
	# Arm a smash if the eyeball is close to the player paddle.
	var d := Vector2(ball.position.x - player_x, ball.position.y - (Y_MIN + 0.08)).length()
	if d < 0.65:
		smash_armed = true
		smash_cooldown = 0.8
		GraphicsPolish.spawn_sparks(self, player_paddle.position, Color(0.2, 0.9, 1.0), 12)


func _step_ball(delta: float) -> void:
	var p := ball.position
	p.x += ball_vel.x * delta
	p.y += ball_vel.y * delta
	# Side walls.
	if p.x < -X_HALF + BALL_R:
		p.x = -X_HALF + BALL_R
		ball_vel.x = absf(ball_vel.x)
		_wall_hit(p)
	elif p.x > X_HALF - BALL_R:
		p.x = X_HALF - BALL_R
		ball_vel.x = -absf(ball_vel.x)
		_wall_hit(p)
	# Player paddle (bottom).
	var py := Y_MIN + 0.08
	if ball_vel.y < 0.0 and p.y - BALL_R <= py + 0.05 and p.y > py - 0.25 \
			and absf(p.x - player_x) <= PADDLE_W * 0.5 + BALL_R:
		_paddle_bounce(p, py, player_x, true)
	# Ghost paddle (top).
	var gy := ghost_root.position.y
	if ball_vel.y > 0.0 and p.y + BALL_R >= gy - 0.05 and p.y < gy + 0.25 \
			and absf(p.x - ghost_x) <= PADDLE_W * 0.5 + BALL_R:
		_paddle_bounce(p, gy, ghost_x, false)
	# Goals.
	if p.y > Y_MAX + 0.25:
		_point_scored(true)
		return
	if p.y < Y_MIN - 0.25:
		_point_scored(false)
		return
	ball.position = p


func _wall_hit(p: Vector3) -> void:
	GraphicsPolish.spawn_sparks(self, p, Color(0.2, 0.9, 1.0), 8)
	if wall_player != null:
		wall_player.play()


func _paddle_bounce(p: Vector3, paddle_y: float, paddle_x: float, is_player: bool) -> void:
	var off := clampf((p.x - paddle_x) / (PADDLE_W * 0.5), -1.0, 1.0)
	if is_player:
		ball_vel.y = absf(ball_vel.y)
	else:
		ball_vel.y = -absf(ball_vel.y)
	ball_vel.x += off * 2.2
	var sp := ball_vel.length() * 1.05
	if is_player and smash_armed:
		sp *= 1.6
		smash_armed = false
		GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.9, 0.2), 30)
		if smash_player != null:
			smash_player.play()
	ball_vel = ball_vel.normalized() * minf(sp, MAX_SPEED)
	# Keep rallies from going flat.
	if absf(ball_vel.y) < 0.6:
		ball_vel.y = 0.6 * signf(ball_vel.y)
		ball_vel = ball_vel.normalized() * minf(sp, MAX_SPEED)
	p.y = paddle_y + (BALL_R + 0.06) * signf(ball_vel.y)
	ball.position = p
	GraphicsPolish.spawn_sparks(self, p, Color(0.6, 1.0, 0.6) if is_player else Color(0.9, 0.9, 1.0), 10)
	if paddle_player != null:
		paddle_player.play()
	if is_player:
		ghost_err = randf_range(-0.18, 0.18)


func _point_scored(player_won: bool) -> void:
	if player_won:
		player_score += 1
		GraphicsPolish.spawn_sparks(self, Vector3(ball.position.x, Y_MAX, FIELD_Z), Color(0.4, 1.0, 0.4), 26)
	else:
		ghost_score += 1
		GraphicsPolish.spawn_sparks(self, Vector3(ball.position.x, Y_MIN, FIELD_Z), Color(1.0, 0.3, 0.3), 26)
	smash_armed = false
	if score_player != null:
		score_player.play()
	if player_score >= WIN_SCORE:
		_game_over(true)
	elif ghost_score >= WIN_SCORE:
		_game_over(false)
	else:
		_show_msg("You %d : %d Ghost" % [player_score, ghost_score])
		_serve(-1.0 if player_won else 1.0)


func _serve(dir: float) -> void:
	state = ST_SERVE
	serve_timer = 1.0
	serve_dir = dir
	ball.position = Vector3(0.0, 1.30, FIELD_Z)
	ball_vel = Vector2(randf_range(-0.5, 0.5), dir).normalized() * BASE_SPEED
	ghost_err = randf_range(-0.18, 0.18)
	_show_msg("Ready...")


func _game_over(player_won: bool) -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_eyeball_pong_main", global_transform)
	if player_won:
		_show_msg("YOU WIN!  %d : %d\nR or hold pinch 1s to play again" % [player_score, ghost_score])
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -1.8), 80)
	else:
		_show_msg("GHOST WINS  %d : %d\nR or hold pinch 1s to retry" % [player_score, ghost_score])
		if lose_player != null:
			lose_player.play()


func _reset_game() -> void:
	player_score = 0
	ghost_score = 0
	player_x = 0.0
	ghost_x = 0.0
	smash_armed = false
	smash_cooldown = 0.0
	_pinch_hold = 0.0
	_serve(1.0)
	ARUpgradeKit.save_anchor("hw_eyeball_pong_main", global_transform)


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

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the table is the haunted pong arena; the TV is the neon scoreboard.
	var _morph0_table := RoomKit.get_anchors("TABLE")
	if not _morph0_table.is_empty():
		RoomKit.morph(_morph0_table[0], "haunted")
	var _morph1_tv := RoomKit.get_anchors("TV")
	if not _morph1_tv.is_empty():
		RoomKit.morph(_morph1_tv[0], "neon")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	if _room_walls.is_empty():
		return
	# Mount the field against the real wall behind it; hang the score HUD
	# on that wall above the field, facing the room.
	var w := _room_back_wall()
	if w.is_empty():
		return
	var wp: Vector3 = w["position"]
	var n: Vector3 = w["normal"]
	var nn := Vector3(n.x, 0.0, n.z)
	if nn.length() < 0.01:
		return
	nn = nn.normalized()
	var face := Vector3(wp.x, 1.30, wp.z) + nn * 0.45
	global_position += face - global_transform * Vector3(0.0, 1.30, FIELD_Z)
	if hud_label != null:
		hud_label.global_position = face + Vector3(0.0, 0.95, 0.0)
		hud_label.global_rotation = Vector3(0.0, atan2(-nn.x, -nn.z), 0.0)


## RoomKit: the wall most directly behind the field (local -z side), else largest.
func _room_back_wall() -> Dictionary:
	var fwd := global_transform.basis * Vector3(0.0, 0.0, 1.0)
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return _room_largest_wall()
	fwd = fwd.normalized()
	var best := {}
	var best_d := -2.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var n: Vector3 = w["normal"]
		var nh := Vector3(n.x, 0.0, n.z)
		if nh.length() < 0.01:
			continue
		var d := nh.normalized().dot(fwd)
		if d > best_d:
			best_d = d
			best = w
	return best


## RoomKit: the wall with the largest face area, or {} when none.
func _room_largest_wall() -> Dictionary:
	var best := {}
	var best_a := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var sz: Vector2 = w["size"]
		var a := sz.x * sz.y
		if a > best_a:
			best_a = a
			best = w
	return best
