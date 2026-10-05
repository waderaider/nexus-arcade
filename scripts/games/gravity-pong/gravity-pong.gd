## GravityPong: 3D pong with gravity wells.
## The playfield is a floating arena on the XZ plane. Your paddle (cyan box)
## moves with the mouse on the near side; the AI paddle (orange box) defends
## the far side. Two purple torus gravity wells sit mid-field and curve the
## ball's trajectory every frame (acceleration toward the well centers,
## capped so the ball can't be slingshotted to infinity).
## Ball bounces off the side walls; paddles reflect it with speed ramping up
## per hit. First to 7 wins. Click/Space serves (with a 3-2-1 countdown),
## R restarts. Mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D

const FIELD_X := 3.0
const FIELD_HALF_Z := 2.2
const PADDLE_HALF_W := 0.35
const PADDLE_BAND_LO := 1.0
const PADDLE_BAND_HI := 2.2
const BALL_R := 0.09
const WIN_SCORE := 7
const BASE_SPEED := 3.0
const MAX_SPEED := 8.0
const HIT_SPEED_UP := 0.25
const WELL_FORCE := 5.0
const WELL_CAP := 9.0
const WELL_EPS := 0.25
const COUNTDOWN_TIME := 3.0

var camera: Camera3D = null
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var ball_speed := BASE_SPEED
var in_play := false
var game_over := false
var countdown_t := 0.0
var serve_to_player := false
var player_paddle: MeshInstance3D = null
var ai_paddle: MeshInstance3D = null
var ai_phase := 0.0
var score_p := 0
var score_a := 0
var well_a := Vector3(-1.2, 0.0, 0.0)
var well_b := Vector3(1.2, 0.0, 0.0)
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var _anchor_t := 0.0


func _ready() -> void:
	# Restore the persisted arena placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "gravity-pong_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_arena()
	_build_wells()
	_build_hud()
	_reset_ball()


func _process(delta: float) -> void:
	# Persist the arena placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("gravity-pong_main", global_transform)
	# XR hand: a pinch serves just like a click (mouse still works).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_serve()
	if Input.is_key_pressed(KEY_SPACE):
		_try_serve()
	if Input.is_key_pressed(KEY_R):
		_restart()

	if countdown_t > 0.0:
		countdown_t -= delta
		if countdown_t <= 0.0:
			countdown_t = 0.0
			_launch_ball()

	_ai_move(delta)

	if in_play and not game_over:
		_move_ball(delta)

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_serve()
	elif event is InputEventMouseMotion:
		_mouse_move_paddle((event as InputEventMouseMotion).position)


## Hand-tracking hook: true while the user is pinching in XR.
func _pinch_active() -> bool:
	return false


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 5.4, 4.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	# Three-point rig, but never stack a second key light.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _glow_box(pos: Vector3, size: Vector3, color: Color, energy: float = 1.5) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	inst.material_override = GraphicsPolish.glow(color, energy)
	inst.position = pos
	add_child(inst)
	return inst


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.06, 0.07, 0.10), "matte")
	add_child(floor_inst)


func _build_arena() -> void:
	var wall_color := Color(0.25, 0.30, 0.45)
	# Side walls (left/right).
	_glow_box(Vector3(-FIELD_X - 0.08, 0.15, 0.0), Vector3(0.16, 0.3, FIELD_HALF_Z * 2.0 + 0.5), wall_color, 0.4)
	_glow_box(Vector3(FIELD_X + 0.08, 0.15, 0.0), Vector3(0.16, 0.3, FIELD_HALF_Z * 2.0 + 0.5), wall_color, 0.4)
	# End caps behind the goals.
	_glow_box(Vector3(0.0, 0.15, -FIELD_HALF_Z - 0.7), Vector3(FIELD_X * 2.0 + 0.5, 0.3, 0.12), wall_color, 0.4)
	_glow_box(Vector3(0.0, 0.15, FIELD_HALF_Z + 0.7), Vector3(FIELD_X * 2.0 + 0.5, 0.3, 0.12), wall_color, 0.4)
	# Center line.
	_glow_box(Vector3(0.0, 0.02, 0.0), Vector3(FIELD_X * 2.0, 0.04, 0.06), Color(0.5, 0.55, 0.7), 0.6)
	# Paddles.
	player_paddle = _glow_box(Vector3(0.0, 0.12, FIELD_HALF_Z), Vector3(PADDLE_HALF_W * 2.0, 0.24, 0.14), Color(0.2, 0.9, 1.0))
	ai_paddle = _glow_box(Vector3(0.0, 0.12, -FIELD_HALF_Z), Vector3(PADDLE_HALF_W * 2.0, 0.24, 0.14), Color(1.0, 0.55, 0.2))
	# Ball: glowing sphere.
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_R
	sphere.height = BALL_R * 2.0
	ball.mesh = sphere
	ball.material_override = GraphicsPolish.glow(Color.WHITE, 1.4)
	add_child(ball)
	ball.add_child(GraphicsPolish.make_trail(Color(0.4, 0.9, 1.0), 0.06))


func _build_wells() -> void:
	for well_pos in [well_a, well_b]:
		var inst := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.18
		torus.outer_radius = 0.34
		inst.mesh = torus
		inst.material_override = GraphicsPolish.glow(Color(0.7, 0.2, 1.0), 2.5)
		inst.position = Vector3(well_pos.x, 0.12, well_pos.z)
		add_child(inst)
		# Dark core dot marking the center of the well.
		var core := MeshInstance3D.new()
		var cs := SphereMesh.new()
		cs.radius = 0.08
		cs.height = 0.16
		core.mesh = cs
		core.material_override = GraphicsPolish.pbr(Color(0.1, 0.0, 0.15), 0.3, 0.5)
		core.position = Vector3(well_pos.x, 0.12, well_pos.z)
		add_child(core)


func _build_hud() -> void:
	hud_label = Label3D.new()
	hud_label.position = Vector3(-2.9, 2.6, 1.0)
	hud_label.pixel_size = 0.006
	hud_label.font_size = 48
	hud_label.outline_size = 8
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -0.6)
	msg_label.pixel_size = 0.010
	add_child(msg_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-2.9, 2.28, 1.0)
	help_label.pixel_size = 0.004
	help_label.font_size = 30
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.text = "Mouse: paddle | Click/Space: serve | R: restart | First to 7 wins"
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "YOU %d  :  %d CPU" % [score_p, score_a]
	if msg_label != null:
		if game_over:
			msg_label.text = "YOU WIN!" if score_p >= WIN_SCORE else "CPU WINS"
		elif countdown_t > 0.0:
			msg_label.text = str(int(ceil(countdown_t)))
		elif not in_play:
			msg_label.text = "Click or press Space to serve"
		else:
			msg_label.text = ""


func _mouse_move_paddle(screen_pos: Vector2) -> void:
	if camera == null or player_paddle == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := (0.12 - origin.y) / dir.y
	if t < 0.0:
		return
	var p: Vector3 = origin + dir * t
	player_paddle.position.x = clampf(p.x, -FIELD_X + PADDLE_HALF_W, FIELD_X - PADDLE_HALF_W)
	player_paddle.position.z = clampf(p.z, PADDLE_BAND_LO, PADDLE_BAND_HI)


func _ai_move(delta: float) -> void:
	if ai_paddle == null or game_over:
		return
	ai_phase += delta * 1.9
	var target_x := 0.0
	if in_play and ball != null:
		target_x = ball.position.x + sin(ai_phase) * 0.15
	var cur: float = ai_paddle.position.x
	var max_step := 2.8 * delta
	ai_paddle.position.x = cur + clampf(target_x - cur, -max_step, max_step)
	ai_paddle.position.x = clampf(ai_paddle.position.x, -FIELD_X + PADDLE_HALF_W, FIELD_X - PADDLE_HALF_W)


func _try_serve() -> void:
	if in_play or game_over or countdown_t > 0.0:
		return
	serve_to_player = randf() < 0.5
	countdown_t = COUNTDOWN_TIME
	ball.position = Vector3(0.0, BALL_R + 0.02, 0.0)
	ball_vel = Vector3.ZERO


func _launch_ball() -> void:
	ball_speed = BASE_SPEED
	var dir_z := 1.0 if serve_to_player else -1.0
	ball_vel = Vector3(randf_range(-0.6, 0.6), 0.0, dir_z).normalized() * ball_speed
	in_play = true


func _reset_ball() -> void:
	if ball != null:
		ball.position = Vector3(0.0, BALL_R + 0.02, 0.0)
	ball_vel = Vector3.ZERO
	in_play = false
	countdown_t = 0.0


func _restart() -> void:
	score_p = 0
	score_a = 0
	game_over = false
	_reset_ball()
	ARUpgradeKit.save_anchor("gravity-pong_main", global_transform)
	_update_hud()


func _well_acceleration(pos: Vector3) -> Vector3:
	var acc := Vector3.ZERO
	for well_pos in [well_a, well_b]:
		var to_well: Vector3 = well_pos - pos
		var dist := maxf(to_well.length(), WELL_EPS)
		var strength := minf(WELL_FORCE / (dist * dist), WELL_CAP)
		acc += to_well.normalized() * strength
	return acc


func _move_ball(delta: float) -> void:
	# Gravity wells curve the velocity each frame; speed is preserved.
	var acc := _well_acceleration(ball.position)
	ball_vel += acc * delta
	if ball_vel.length() > 0.001:
		ball_vel = ball_vel.normalized() * ball_speed

	var pos: Vector3 = ball.position + ball_vel * delta

	# Side walls.
	if pos.x > FIELD_X - BALL_R:
		pos.x = FIELD_X - BALL_R
		ball_vel.x = -absf(ball_vel.x)
	elif pos.x < -FIELD_X + BALL_R:
		pos.x = -FIELD_X + BALL_R
		ball_vel.x = absf(ball_vel.x)

	# Paddles: box collision on the XZ plane.
	if ball_vel.z > 0.0:
		if _hits_paddle(pos, player_paddle):
			pos.z = player_paddle.position.z - 0.07 - BALL_R
			_bounce_off_paddle(player_paddle, -1.0)
	elif ball_vel.z < 0.0:
		if _hits_paddle(pos, ai_paddle):
			pos.z = ai_paddle.position.z + 0.07 + BALL_R
			_bounce_off_paddle(ai_paddle, 1.0)

	ball.position = pos

	# Scoring.
	if pos.z > FIELD_HALF_Z + 0.8:
		score_a += 1
		_reset_ball()
		_check_win()
	elif pos.z < -FIELD_HALF_Z - 0.8:
		score_p += 1
		_reset_ball()
		_check_win()
	_update_hud()


func _hits_paddle(pos: Vector3, paddle: MeshInstance3D) -> bool:
	var dz := absf(pos.z - paddle.position.z)
	var dx := absf(pos.x - paddle.position.x)
	return dz < 0.07 + BALL_R and dx < PADDLE_HALF_W + BALL_R


func _bounce_off_paddle(paddle: MeshInstance3D, dir_z: float) -> void:
	GraphicsPolish.spawn_sparks(self, ball.position, Color(0.5, 0.95, 1.0), 12)
	ball_vel.z = dir_z * absf(ball_vel.z)
	ball_vel.x += (ball.position.x - paddle.position.x) * 2.5
	ball_speed = minf(MAX_SPEED, ball_speed + HIT_SPEED_UP)
	ball_vel = ball_vel.normalized() * ball_speed


func _check_win() -> void:
	if score_p >= WIN_SCORE or score_a >= WIN_SCORE:
		game_over = true
		in_play = false
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.0, 0.0), 60)
	_update_hud()
