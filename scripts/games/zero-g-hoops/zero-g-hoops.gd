## Zero-G Hoops: zero-gravity basketball.
## Balls drift slowly in a room-volume play area; a glowing hoop floats
## anchored across the room. Desktop: click a ball to grab it, drag, and
## release to launch (flick velocity). XR: pinch to grab the ball nearest your
## pointer, release to throw with your hand's velocity. Zero-G: no gravity,
## slight drag, walls bounce. Score baskets before the shot clock runs out;
## 10 rounds. No rim contact = SWISH bonus + confetti. R restarts.
extends Node3D

const BALL_R := 0.12
const HOOP_R := 0.34
const HOOP_POS := Vector3(0.0, 1.7, -2.3)
const BOUNDS_X := 3.0
const BOUNDS_Y_LO := 0.15
const BOUNDS_Y_HI := 3.0
const BOUNDS_Z_LO := -3.0
const BOUNDS_Z_HI := 2.5
const SHOT_CLOCK := 20.0
const ROUNDS := 10
const DRAG := 0.12

var camera: Camera3D = null
var hoop: Node3D = null
var rim_mat: StandardMaterial3D = null
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var ball_held := false
var rim_touched := false
var prev_ball_z := 0.0
var round_num := 1
var clock := SHOT_CLOCK
var score := 0
var swishes := 0
var state := "playing"
var msg := ""
var msg_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var pulse_t := 0.0
var grab_start := Vector2.ZERO
var grab_time := 0.0
var grab_point := Vector3.ZERO
var xr_prev := Vector3.ZERO
var xr_vel := Vector3.ZERO
var bob_t := 0.0
# v0.7.0 RoomKit: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _hoop_base: Vector3 = HOOP_POS
var _hoop_face := 1.0 # +1: hoop front faces +Z (default); -1: faces -Z


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "zero-g-hoops_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_build_hoop()
	_build_hud()
	_new_round()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 3.0, 40)
	_apply_room_layout() # v0.7.0: hoop on real walls, room-bounded volume


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 2.6)
	add_child(camera)
	camera.look_at(HOOP_POS, Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.3, 0.5)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _build_hoop() -> void:
	hoop = Node3D.new()
	hoop.position = HOOP_POS
	add_child(hoop)
	# Backboard.
	var bb := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.1, 0.75, 0.05)
	bb.mesh = bmesh
	bb.material_override = GraphicsPolish.pbr_preset(Color(0.15, 0.5, 0.8), "glass")
	bb.position = Vector3(0.0, 0.35, -0.12)
	hoop.add_child(bb)
	# Rim.
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = HOOP_R - 0.045
	torus.outer_radius = HOOP_R
	rim.mesh = torus
	rim_mat = GraphicsPolish.glow(Color(1.0, 0.45, 0.1), 2.4)
	rim.material_override = rim_mat
	hoop.add_child(rim)
	# Net: cone of glowing strands.
	var net := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = HOOP_R
	cone.bottom_radius = HOOP_R * 0.55
	cone.height = 0.35
	net.mesh = cone
	net.material_override = GraphicsPolish.pbr_preset(Color(0.95, 0.95, 1.0), "matte")
	net.position.y = -0.2
	hoop.add_child(net)
	GraphicsPolish.make_point_light(hoop, Vector3(0, 0.4, 0.6), Color(1.0, 0.7, 0.4), 0.9, 3.5)


func _spawn_ball() -> void:
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_R
	sphere.height = BALL_R * 2.0
	ball.mesh = sphere
	ball.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.4)
	# v0.7.0: drift near the room center when the room is scanned.
	var bc := Vector2(0.0, 1.2)
	if not _room_walls.is_empty():
		bc = _room_bounds.get_center()
	ball.position = Vector3(bc.x + randf_range(-0.8, 0.8), randf_range(1.2, 1.9), bc.y + randf_range(-0.8, 0.8))
	ball.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.2), 0.04))
	add_child(ball)
	ball_vel = Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.5, -0.1))
	ball_held = false
	rim_touched = false
	prev_ball_z = ball.position.z


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.8, 2.9, 0.0)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(1.0, 0.7, 0.3))
	msg_label.position = Vector3(0.0, 2.6, -2.0)
	msg_label.pixel_size = 0.009
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("", 30, Color(0.8, 0.82, 0.92))
	help_label.position = Vector3(-2.8, 2.62, 0.0)
	help_label.pixel_size = 0.004
	add_child(help_label)


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Score %d   Round %d/%d   Clock %.0f" % [score, round_num, ROUNDS, maxf(clock, 0.0)]
	if help_label != null:
		if ARUpgradeKit.is_xr_active():
			help_label.text = "Pinch ball to grab, flick to shoot | R: restart"
		else:
			help_label.text = "Click-drag-FLICK ball to shoot | R: restart"
	if msg_label != null:
		msg_label.text = msg


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _new_round() -> void:
	clock = SHOT_CLOCK
	_place_hoop() # v0.7.0: each round mounts the hoop on a (different) wall
	_spawn_ball()
	_set_msg("Round %d — shoot!" % round_num, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if state != "playing" or ball == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_grab(mb.position)
			elif ball_held:
				_release_ball(mb.position)


func _screen_to_ball_plane(screen_pos: Vector2, plane_z: float) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.z) < 0.0001:
		return ball.global_position
	var t := (plane_z - origin.z) / dir.z
	if t < 0.0:
		return ball.global_position
	return origin + dir * t


func _try_grab(screen_pos: Vector2) -> void:
	if camera == null or ball == null:
		return
	if camera.is_position_behind(ball.global_position):
		return
	var d: float = camera.unproject_position(ball.global_position).distance_to(screen_pos)
	if d < 70.0:
		ball_held = true
		ball_vel = Vector3.ZERO
		grab_start = screen_pos
		grab_time = 0.0
		grab_point = ball.global_position


func _release_ball(screen_pos: Vector2) -> void:
	ball_held = false
	var flick: Vector2 = grab_start - screen_pos
	var speed := clampf(flick.length() * 0.018, 0.0, 9.0)
	if speed < 0.8 or grab_time <= 0.0:
		ball_vel = Vector3(0, 0.3, -0.5)
		return
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var right := basis.x
	var up := basis.y
	ball_vel = fwd * speed + right * (flick.x * 0.008) + up * (-flick.y * 0.008)
	rim_touched = false


func _process(delta: float) -> void:
	pulse_t += delta
	bob_t += delta
	if rim_mat != null:
		GraphicsPolish.pulse_glow(rim_mat, 2.4, 0.8, pulse_t, 2.0)
	if hoop != null:
		hoop.global_position.y = _hoop_base.y + sin(bob_t * 1.3) * 0.08
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if Input.is_key_pressed(KEY_R):
		_restart()
	if state != "playing":
		return
	clock -= delta
	if clock <= 0.0:
		_end_round("Shot clock expired!")
		return
	if ball == null:
		return
	# Held ball follows the pointer.
	if ball_held and not ARUpgradeKit.is_xr_active():
		grab_time += delta
		ball.global_position = _screen_to_ball_plane(get_viewport().get_mouse_position(), ball.global_position.z)
		prev_ball_z = ball.global_position.z
	# XR grab: pinch near the ball, release with hand velocity.
	if ARUpgradeKit.is_xr_active():
		var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if pinching and not ball_held:
			if pp.distance_to(ball.global_position) < 0.55:
				ball_held = true
				rim_touched = false
				xr_prev = pp
				xr_vel = Vector3.ZERO
		elif pinching and ball_held:
			if delta > 0.0:
				xr_vel = xr_vel.lerp((pp - xr_prev) / delta, 0.5)
			xr_prev = pp
			ball.global_position = pp
			prev_ball_z = pp.z
		elif not pinching and ball_held:
			ball_held = false
			if xr_vel.length() > 0.6:
				ball_vel = xr_vel.limit_length(9.0)
			else:
				ball_vel = Vector3(0, 0.3, -0.5)
	if not ball_held:
		_move_ball(delta)
	_update_hud()


func _move_ball(delta: float) -> void:
	# Zero-G: slight drag, no gravity.
	ball_vel *= 1.0 - DRAG * delta
	var pos: Vector3 = ball.global_position + ball_vel * delta
	# Rim collision: torus band around the hoop center.
	var hp: Vector3 = hoop.global_position
	var d2 := Vector2(pos.x - hp.x, pos.y - hp.y).length()
	var dz := absf(pos.z - hp.z)
	if dz < BALL_R + 0.05 and absf(d2 - HOOP_R) < BALL_R + 0.045:
		rim_touched = true
		var n := Vector2(pos.x - hp.x, pos.y - hp.y).normalized()
		var v2 := Vector2(ball_vel.x, ball_vel.y)
		var refl: Vector2 = v2 - 2.0 * v2.dot(n) * n
		ball_vel.x = refl.x * 0.75
		ball_vel.y = refl.y * 0.75
		pos.x = hp.x + n.x * (HOOP_R + (BALL_R + 0.05) * signf(d2 - HOOP_R))
		pos.y = hp.y + n.y * (HOOP_R + (BALL_R + 0.05) * signf(d2 - HOOP_R))
		GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.6, 0.2), 6)
	# Walls bounce (v0.7.0: real wall planes + room bounds when scanned).
	if _room_walls.is_empty():
		if pos.x > BOUNDS_X - BALL_R:
			pos.x = BOUNDS_X - BALL_R
			ball_vel.x = -absf(ball_vel.x) * 0.8
		elif pos.x < -BOUNDS_X + BALL_R:
			pos.x = -BOUNDS_X + BALL_R
			ball_vel.x = absf(ball_vel.x) * 0.8
		if pos.y > BOUNDS_Y_HI - BALL_R:
			pos.y = BOUNDS_Y_HI - BALL_R
			ball_vel.y = -absf(ball_vel.y) * 0.8
		elif pos.y < BOUNDS_Y_LO + BALL_R:
			pos.y = BOUNDS_Y_LO + BALL_R
			ball_vel.y = absf(ball_vel.y) * 0.8
		if pos.z > BOUNDS_Z_HI - BALL_R:
			pos.z = BOUNDS_Z_HI - BALL_R
			ball_vel.z = -absf(ball_vel.z) * 0.8
		elif pos.z < BOUNDS_Z_LO + BALL_R:
			pos.z = BOUNDS_Z_LO + BALL_R
			ball_vel.z = absf(ball_vel.z) * 0.8
	else:
		var wv: Vector3 = global_transform.basis * ball_vel
		wv = _bounce_walls(pos, wv, BALL_R)
		wv = _bounce_furniture(pos, wv, BALL_R)
		ball_vel = global_transform.basis.inverse() * wv
		var r := _room_bounds
		var x0 := r.position.x + BALL_R
		var x1 := r.end.x - BALL_R
		var z0 := r.position.y + BALL_R
		var z1 := r.end.y - BALL_R
		if pos.x < x0:
			pos.x = x0
			ball_vel.x = absf(ball_vel.x) * 0.8
		elif pos.x > x1:
			pos.x = x1
			ball_vel.x = -absf(ball_vel.x) * 0.8
		if pos.z < z0:
			pos.z = z0
			ball_vel.z = absf(ball_vel.z) * 0.8
		elif pos.z > z1:
			pos.z = z1
			ball_vel.z = -absf(ball_vel.z) * 0.8
		if pos.y > BOUNDS_Y_HI - BALL_R:
			pos.y = BOUNDS_Y_HI - BALL_R
			ball_vel.y = -absf(ball_vel.y) * 0.8
		elif pos.y < BOUNDS_Y_LO + BALL_R:
			pos.y = BOUNDS_Y_LO + BALL_R
			ball_vel.y = absf(ball_vel.y) * 0.8
	ball.global_position = pos
	_check_basket(pos)
	prev_ball_z = pos.z


func _check_basket(pos: Vector3) -> void:
	var hp: Vector3 = hoop.global_position
	# Crossing the hoop plane from the front (v0.7.0: front follows _hoop_face).
	if (prev_ball_z - hp.z) * _hoop_face > 0.0 and (pos.z - hp.z) * _hoop_face <= 0.0:
		var d2 := Vector2(pos.x - hp.x, pos.y - hp.y).length()
		if d2 < HOOP_R - BALL_R * 0.4:
			if rim_touched:
				score += 2
				_set_msg("+2 BUCKET", 1.6)
				GraphicsPolish.spawn_sparks(self, hp, Color(1.0, 0.8, 0.3), 20)
			else:
				score += 3
				swishes += 1
				_set_msg("SWISH! +3", 1.8)
				GraphicsPolish.spawn_confetti(self, hp + Vector3(0, 0.3, 0), 50)
			_end_round("")
			return


func _end_round(reason: String) -> void:
	if reason != "":
		_set_msg(reason, 1.6)
	if round_num >= ROUNDS:
		_game_over()
	else:
		round_num += 1
		_new_round()
	_update_hud()


func _game_over() -> void:
	state = "gameover"
	ARUpgradeKit.save_anchor("zero-g-hoops_main", global_transform)
	GraphicsPolish.spawn_confetti(self, Vector3(0, 2.0, -1.0), 80)
	_set_msg("GAME! %d pts, %d swishes — R to restart" % [score, swishes], 60.0)
	_update_hud()


func _restart() -> void:
	score = 0
	swishes = 0
	round_num = 1
	state = "playing"
	_new_round()
	_update_hud()


# ------------------------------------------------- v0.7.0 RoomKit ----
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not is_inside_tree() or not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_place_hoop()
	# v0.7.0 MORPH: windows become space-vista portals around the zero-G court.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_wins := RoomKit.get_anchors("WINDOW")
		if not _morph_wins.is_empty():
			RoomKit.morph(_morph_wins[0], "scifi")


## Mount the hoop on a real wall face (cycles walls each round), facing the room.
func _place_hoop() -> void:
	_hoop_face = 1.0
	_hoop_base = HOOP_POS
	if not _room_walls.is_empty():
		var cands: Array = []
		for w_v in _room_walls:
			var w: Dictionary = w_v
			if absf((w["normal"] as Vector3).normalized().z) > 0.7:
				cands.append(w)
		if not cands.is_empty():
			var w: Dictionary = cands[round_num % cands.size()]
			var wp: Vector3 = w["position"]
			var wn: Vector3 = (w["normal"] as Vector3).normalized()
			_hoop_face = signf(wn.z) if absf(wn.z) > 0.01 else 1.0
			_hoop_base = Vector3(wp.x, 1.7, wp.z) + Vector3(0.0, 0.0, _hoop_face * 0.9)
			_hoop_base.x = clampf(_hoop_base.x, _room_bounds.position.x + 0.5, _room_bounds.end.x - 0.5)
			_hoop_base.z = clampf(_hoop_base.z, _room_bounds.position.y + 0.5, _room_bounds.end.y - 0.5)
	if hoop != null:
		var nrm := Vector3(0.0, 0.0, _hoop_face)
		hoop.global_transform = Transform3D(Basis.looking_at(-nrm, Vector3.UP), _hoop_base)


## Normal-sign agnostic wall reflection (world space).
func _bounce_walls(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		var d: float = (pos - w["position"]).dot(n)
		if absf(d) < radius and vel.dot(n) * signf(d) < 0.0:
			vel = vel - 2.0 * vel.dot(n) * n
	return vel


## Furniture cuboids are solid: reflect the least-penetration axis (world space).
func _bounce_furniture(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for f_v in _room_furniture:
		var f: Dictionary = f_v
		var c: Vector3 = f["position"]
		var s: Vector3 = f["size"]
		var d: Vector3 = pos - c
		var px := s.x * 0.5 + radius - absf(d.x)
		var py := s.y * 0.5 + radius - absf(d.y)
		var pz := s.z * 0.5 + radius - absf(d.z)
		if px > 0.0 and py > 0.0 and pz > 0.0:
			if px <= py and px <= pz and signf(vel.x) == signf(d.x):
				vel.x = -vel.x
			elif py <= px and py <= pz and signf(vel.y) == signf(d.y):
				vel.y = -vel.y
			elif pz <= px and pz <= py and signf(vel.z) == signf(d.z):
				vel.z = -vel.z
	return vel
