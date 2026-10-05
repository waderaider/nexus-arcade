## PortalBallGame.gd - "Portal Ball": pong with room portals.
## Left paddle is yours (mouse Y), right paddle is AI (tracks with max speed
## plus a small error wobble). The ball bounces off the top/bottom walls and
## paddles; two glowing torus portals sit on the top and bottom walls and
## teleport the ball to each other, preserving speed and mirroring direction.
## First to 5 wins. Space/click serves, R restarts.
## Upgraded: glow materials via the kit, three-point light rig, ball trail,
## spark bursts on paddle hits and portal jumps, ambient motes, styled HUD
## label, XR pinch serve, spatial anchor persistence.
## Desktop/mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D
class_name PortalBallGame

const PLAY_Z := 1.6
const FIELD_X := 3.0
const TOP_Y := 2.1
const BOT_Y := 0.3
const PADDLE_X := 2.6
const PADDLE_HALF_H := 0.30
const BALL_R := 0.08
const WIN_SCORE := 5
const BASE_SPEED := 2.6
const MAX_SPEED := 6.0

var camera: Camera3D = null
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var ball_speed := BASE_SPEED
var in_play := false
var game_over := false
var player_paddle: MeshInstance3D = null
var ai_paddle: MeshInstance3D = null
var ai_phase := 0.0
var score_p := 0
var score_a := 0
var portal_top := Vector3.ZERO
var portal_bot := Vector3.ZERO
var portal_cooldown := 0.0
var flash_t := 0.0
var hud_label: Label3D = null
var flash_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var _anchor_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "portal-ball_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_arena()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.2, PLAY_Z), 3.0, 35)
	_reset_ball()


func _process(delta: float) -> void:
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("portal-ball_main", global_transform)
	# Hand interaction: right-hand pinch serves (click/space keep working).
	# The mouse-press gate keeps the kit's mouse fallback from
	# double-triggering alongside _unhandled_input.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_try_serve()

	if Input.is_key_pressed(KEY_SPACE):
		_try_serve()
	if Input.is_key_pressed(KEY_R):
		_restart()

	portal_cooldown = maxf(0.0, portal_cooldown - delta)
	flash_t = maxf(0.0, flash_t - delta)
	if flash_label != null:
		flash_label.visible = flash_t > 0.0

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
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, -2.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 1.6), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	# Upgraded three-point light rig; never add a second key light.
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.07, 0.08, 0.11), "matte")
	add_child(floor_inst)


func _glow_box(pos: Vector3, size: Vector3, color: Color, energy: float = 1.5) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	inst.material_override = GraphicsPolish.glow(color, energy)
	inst.position = pos
	add_child(inst)
	return inst


func _build_arena() -> void:
	# Top / bottom walls.
	_glow_box(Vector3(0.0, TOP_Y + 0.06, PLAY_Z), Vector3(FIELD_X * 2.0 + 0.6, 0.12, 0.2), Color(0.25, 0.30, 0.45), 0.4)
	_glow_box(Vector3(0.0, BOT_Y - 0.06, PLAY_Z), Vector3(FIELD_X * 2.0 + 0.6, 0.12, 0.2), Color(0.25, 0.30, 0.45), 0.4)
	# Center line.
	_glow_box(Vector3(0.0, (TOP_Y + BOT_Y) * 0.5, PLAY_Z), Vector3(0.04, TOP_Y - BOT_Y, 0.05), Color(0.5, 0.55, 0.7), 0.6)
	# Paddles.
	player_paddle = _glow_box(Vector3(-PADDLE_X, 1.2, PLAY_Z), Vector3(0.12, PADDLE_HALF_H * 2.0, 0.12), Color(0.2, 0.9, 1.0))
	ai_paddle = _glow_box(Vector3(PADDLE_X, 1.2, PLAY_Z), Vector3(0.12, PADDLE_HALF_H * 2.0, 0.12), Color(1.0, 0.55, 0.2))
	# Ball.
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_R
	sphere.height = BALL_R * 2.0
	ball.mesh = sphere
	ball.material_override = GraphicsPolish.glow(Color.WHITE, 1.2)
	add_child(ball)
	ball.add_child(GraphicsPolish.make_trail(Color(0.4, 0.9, 1.0), 0.05))
	# Portals: glowing tori lying flat on the top/bottom walls.
	portal_top = Vector3(0.0, TOP_Y, PLAY_Z)
	portal_bot = Vector3(0.0, BOT_Y, PLAY_Z)
	_build_portal(portal_top)
	_build_portal(portal_bot)


func _build_portal(pos: Vector3) -> void:
	var inst := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.27
	inst.mesh = torus
	inst.material_override = GraphicsPolish.glow(Color(1.0, 0.3, 1.0), 2.5)
	inst.position = pos
	inst.rotation_degrees.x = 90.0
	add_child(inst)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color.WHITE)
	hud_label.position = Vector3(-2.4, 2.5, 1.2)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	flash_label = Label3D.new()
	flash_label.position = Vector3(0.0, 1.7, PLAY_Z - 0.4)
	flash_label.pixel_size = 0.009
	flash_label.font_size = 64
	flash_label.modulate = Color(1.0, 0.4, 1.0)
	flash_label.outline_size = 10
	flash_label.text = "PORTAL!"
	flash_label.visible = false
	add_child(flash_label)
	msg_label = Label3D.new()
	msg_label.position = Vector3(0.0, 1.2, PLAY_Z - 0.4)
	msg_label.pixel_size = 0.007
	msg_label.font_size = 52
	msg_label.outline_size = 8
	add_child(msg_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-2.4, 2.22, 1.2)
	help_label.pixel_size = 0.004
	help_label.font_size = 30
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.text = "Mouse Y: paddle | Click/Space: serve | R: restart | First to 5 wins"
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "YOU %d  :  %d CPU" % [score_p, score_a]
	if msg_label != null:
		if game_over:
			msg_label.text = "YOU WIN!" if score_p >= WIN_SCORE else "CPU WINS"
		elif not in_play:
			msg_label.text = "Click or press Space to serve"
		else:
			msg_label.text = ""


func _mouse_move_paddle(screen_pos: Vector2) -> void:
	if camera == null or player_paddle == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.z) < 0.0001:
		return
	var t := (PLAY_Z - origin.z) / dir.z
	if t < 0.0:
		return
	var p: Vector3 = origin + dir * t
	player_paddle.position.y = clampf(p.y, BOT_Y + PADDLE_HALF_H, TOP_Y - PADDLE_HALF_H)


func _ai_move(delta: float) -> void:
	if ai_paddle == null or game_over:
		return
	ai_phase += delta * 1.7
	var target_y := 1.2
	if in_play and ball != null:
		target_y = ball.position.y + sin(ai_phase) * 0.12
	var cur: float = ai_paddle.position.y
	var diff := target_y - cur
	var max_step := 2.4 * delta
	ai_paddle.position.y = cur + clampf(diff, -max_step, max_step)
	ai_paddle.position.y = clampf(ai_paddle.position.y, BOT_Y + PADDLE_HALF_H, TOP_Y - PADDLE_HALF_H)


func _try_serve() -> void:
	if in_play or game_over:
		return
	ball_speed = BASE_SPEED
	var dir_x := 1.0 if randf() < 0.5 else -1.0
	ball_vel = Vector3(dir_x, randf_range(-0.5, 0.5), 0.0).normalized() * ball_speed
	in_play = true
	_update_hud()


func _reset_ball() -> void:
	if ball != null:
		ball.position = Vector3(0.0, (TOP_Y + BOT_Y) * 0.5, PLAY_Z)
	ball_vel = Vector3.ZERO
	in_play = false


func _restart() -> void:
	score_p = 0
	score_a = 0
	game_over = false
	_reset_ball()
	_update_hud()


func _move_ball(delta: float) -> void:
	var pos: Vector3 = ball.position + ball_vel * delta

	# Top / bottom walls.
	if pos.y > TOP_Y - BALL_R:
		pos.y = TOP_Y - BALL_R
		ball_vel.y = -absf(ball_vel.y)
	elif pos.y < BOT_Y + BALL_R:
		pos.y = BOT_Y + BALL_R
		ball_vel.y = absf(ball_vel.y)

	# Paddles.
	if ball_vel.x < 0.0 and pos.x - BALL_R < -PADDLE_X + 0.06 and pos.x > -PADDLE_X - 0.2:
		if absf(pos.y - player_paddle.position.y) < PADDLE_HALF_H + BALL_R:
			pos.x = -PADDLE_X + 0.06 + BALL_R
			_bounce_off_paddle(player_paddle)
	elif ball_vel.x > 0.0 and pos.x + BALL_R > PADDLE_X - 0.06 and pos.x < PADDLE_X + 0.2:
		if absf(pos.y - ai_paddle.position.y) < PADDLE_HALF_H + BALL_R:
			pos.x = PADDLE_X - 0.06 - BALL_R
			_bounce_off_paddle(ai_paddle)

	# Portals.
	if portal_cooldown <= 0.0:
		if pos.distance_to(portal_top) < 0.24:
			pos = portal_bot + Vector3(0.0, -0.22, 0.0)
			ball_vel.y = -absf(ball_vel.y)
			_on_portal()
		elif pos.distance_to(portal_bot) < 0.24:
			pos = portal_top + Vector3(0.0, 0.22, 0.0)
			ball_vel.y = absf(ball_vel.y)
			_on_portal()

	ball.position = pos

	# Scoring.
	if pos.x < -FIELD_X - 0.3:
		score_a += 1
		_reset_ball()
		_check_win()
	elif pos.x > FIELD_X + 0.3:
		score_p += 1
		_reset_ball()
		_check_win()
	_update_hud()


func _bounce_off_paddle(paddle: MeshInstance3D) -> void:
	var dir_x := 1.0 if ball_vel.x < 0.0 else -1.0
	ball_vel.x = dir_x * absf(ball_vel.x)
	ball_vel.y += (ball.position.y - paddle.position.y) * 2.0
	ball_speed = minf(MAX_SPEED, ball_speed + 0.15)
	ball_vel = ball_vel.normalized() * ball_speed
	GraphicsPolish.spawn_sparks(self, ball.position, Color(0.5, 0.9, 1.0), 14)


func _on_portal() -> void:
	portal_cooldown = 0.4
	flash_t = 1.0
	if ball != null:
		GraphicsPolish.spawn_sparks(self, ball.position, Color(1.0, 0.4, 1.0), 24)


func _check_win() -> void:
	if score_p >= WIN_SCORE or score_a >= WIN_SCORE:
		game_over = true
		in_play = false
	_update_hud()
