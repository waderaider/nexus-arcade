## ArBowlingGame - "AR Bowling": bowling in your hallway.
## Press and drag the mouse to aim, release to throw. Throw speed follows the
## drag power, lateral aim follows the drag direction. The ball uses simple
## custom physics (velocity integration + friction, no PhysicsServer). Pins
## tip over and slide on contact and can knock each other down. Full 10-frame
## scoring with strikes/spares, a scorecard HUD, and a fresh rack each frame.
## Lane edges are gutters: a guttered ball falls off and scores 0.
## Desktop/mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D

const LANE_HALF := 0.62
const BALL_RADIUS := 0.16
const PIN_RADIUS := 0.10
const BALL_START := Vector3(0.0, 0.16, 1.2)
const HEAD_PIN_Z := -11.0
const PIN_DZ := 0.34
const PIN_DX := 0.24
const MIN_SPEED := 4.0
const MAX_SPEED := 12.5
const FRICTION := 0.45
const PAST_PINS_Z := -14.5

const ST_READY := 0
const ST_AIMING := 1
const ST_ROLLING := 2
const ST_SETTLE := 3
const ST_OVER := 4

var camera: Camera3D = null
var state := ST_READY
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var ball_vy := 0.0
var guttered := false
var roll_timer := 0.0
var aim_arrow: MeshInstance3D = null
var aim_mat: StandardMaterial3D = null
var press_pos := Vector2.ZERO
var cur_mouse := Vector2.ZERO
var pins: Array = [] # dicts: node, mat, standing, vel, tip_angle, tip_axis
var pins_before_throw := 10
var frames: Array = [] # 10 arrays of throw pin-counts
var frame_idx := 0
var settle_timer := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var knock_player: AudioStreamPlayer = null
var strike_player: AudioStreamPlayer = null
var gutter_player: AudioStreamPlayer = null
var throw_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_aiming := false


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_lane()
	_build_ball()
	_build_aim_arrow()
	_build_hud()
	for i in range(10):
		frames.append([])
	_reset_rack()
	_ready_ball()
	knock_player = _make_player(_make_tone(320.0, 0.12, 0.6))
	strike_player = _make_player(_make_tone(880.0, 0.35, 0.55))
	gutter_player = _make_player(_make_tone(120.0, 0.45, 0.55))
	throw_player = _make_player(_make_tone(430.0, 0.18, 0.4))
	# Restore the lane's saved room anchor; in XR keep it on the floor.
	ARUpgradeKit.apply_anchor(self, "ar-bowling_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -6.0), 3.0)
	RoomKit.refresh() # v0.7.0: cache room walls for wall bounces (safe no-op w/o XR).
	# v0.7.0 MORPH: rug becomes the neon approach carpet (glow runway).
	if RoomKit.is_available() and RoomKit.has_room_data():
		if not has_meta("_morphs_applied"):
			set_meta("_morphs_applied", true)
			var _morph_rugs := RoomKit.get_anchors("RUG")
			if not _morph_rugs.is_empty():
				RoomKit.morph(_morph_rugs[0], "neon")


func _add_light_rig() -> void:
	# Three-point light rig; skipped if a directional light already exists.
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _process(delta: float) -> void:
	_poll_pinch()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("ar-bowling_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_AIMING:
		_update_aim()
	if state == ST_ROLLING or state == ST_SETTLE:
		roll_timer += delta
		_step_ball(delta)
		if state == ST_ROLLING:
			_check_pin_hits()
			_check_throw_end()
		elif state == ST_SETTLE:
			settle_timer -= delta
			if settle_timer <= 0.0:
				_resolve_throw()
	_step_pins(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and state != ST_OVER and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and state == ST_READY:
				state = ST_AIMING
				press_pos = mb.position
				cur_mouse = mb.position
			elif not mb.pressed and state == ST_AIMING:
				_release_throw(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cur_mouse = mm.position


## Hand-tracking hook: XR pinch aims and releases the throw (mouse still works).
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _pointer_screen_pos() -> Vector2:
	var wp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if camera != null:
		return camera.unproject_position(wp)
	return cur_mouse


func _poll_pinch() -> void:
	# Pinch-and-hold aims the throw; releasing the pinch throws.
	var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	if state == ST_READY and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		state = ST_AIMING
		_pinch_aiming = true
		press_pos = _pointer_screen_pos()
		cur_mouse = press_pos
	elif state == ST_AIMING and _pinch_aiming:
		cur_mouse = _pointer_screen_pos()
		if not pinching:
			_pinch_aiming = false
			_release_throw(cur_mouse)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.4, 5.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.2, -10.0), Vector3.UP)
	camera.current = true


func _mat(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if emission > 0.0:
		return GraphicsPolish.glow(color, emission)
	return GraphicsPolish.pbr(color, 0.25, 0.5)


func _build_lane() -> void:
	# Wooden lane surface.
	var lane := MeshInstance3D.new()
	var lane_box := BoxMesh.new()
	lane_box.size = Vector3(LANE_HALF * 2.0 + 0.16, 0.1, 18.0)
	lane.mesh = lane_box
	lane.position = Vector3(0.0, -0.05, -7.0)
	lane.material_override = _mat(Color(0.55, 0.38, 0.20))
	add_child(lane)
	# Gutter strips on both edges.
	for side in [-1.0, 1.0]:
		var gut := MeshInstance3D.new()
		var gut_box := BoxMesh.new()
		gut_box.size = Vector3(0.28, 0.06, 18.0)
		gut.mesh = gut_box
		gut.position = Vector3(side * (LANE_HALF + 0.22), -0.08, -7.0)
		gut.material_override = _mat(Color(0.10, 0.10, 0.12))
		add_child(gut)
	# Dark pit backstop behind the pins.
	var pit := MeshInstance3D.new()
	var pit_box := BoxMesh.new()
	pit_box.size = Vector3(3.0, 2.0, 0.3)
	pit.mesh = pit_box
	pit.position = Vector3(0.0, 0.8, -16.2)
	pit.material_override = _mat(Color(0.05, 0.05, 0.07))
	add_child(pit)
	# Floor around the lane.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 24.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.11, -6.0)
	floor_inst.material_override = _mat(Color(0.07, 0.07, 0.10))
	add_child(floor_inst)


func _build_ball() -> void:
	ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	ball.mesh = sphere
	ball.material_override = _mat(Color(0.15, 0.25, 0.75), 0.35)
	ball.position = BALL_START
	add_child(ball)
	ball.add_child(GraphicsPolish.make_trail(Color(0.4, 0.7, 1.0), 0.06))


func _build_aim_arrow() -> void:
	aim_arrow = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.02, 1.0)
	aim_arrow.mesh = box
	aim_mat = _mat(Color(0.2, 0.95, 1.0), 1.6)
	aim_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	aim_arrow.material_override = aim_mat
	aim_arrow.visible = false
	add_child(aim_arrow)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("AR BOWLING", 44, Color(1, 1, 1))
	hud_label.position = Vector3(-3.6, 3.3, -2.0)
	add_child(hud_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-3.6, 2.55, -2.0)
	help_label.pixel_size = 0.0034
	help_label.font_size = 30
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help_label.text = "Press + drag mouse to aim, release to throw | R: new game"
	add_child(help_label)
	msg_label = Label3D.new()
	msg_label.position = Vector3(0.0, 2.4, -6.0)
	msg_label.pixel_size = 0.008
	msg_label.font_size = 96
	msg_label.outline_size = 10
	msg_label.modulate = Color(1.0, 0.85, 0.3)
	msg_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	var lines: Array = []
	lines.append("AR BOWLING   Frame %d/10   Score: %d" % [mini(frame_idx + 1, 10), _total_score()])
	var marks: Array = []
	for fi in range(10):
		marks.append("%d:[%s]" % [fi + 1, _frame_marks(fi)])
	lines.append(" ".join(marks))
	var cum := _frame_scores()
	var cs: Array = []
	for fi in range(10):
		cs.append(str(cum[fi]))
	lines.append(" ".join(cs))
	hud_label.text = "\n".join(lines)


func _show_msg(text: String, duration: float = 1.8) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ---------------------------------------------------------------- pins ----

func _reset_rack() -> void:
	for p_v in pins:
		var p: Dictionary = p_v
		var node: MeshInstance3D = p["node"]
		if is_instance_valid(node):
			node.queue_free()
	pins.clear()
	for row in range(4):
		for j in range(row + 1):
			var x := (float(j) - float(row) * 0.5) * PIN_DX
			var z := HEAD_PIN_Z - float(row) * PIN_DZ
			_spawn_pin(Vector3(x, 0.19, z))


func _spawn_pin(pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = PIN_RADIUS
	cyl.height = 0.38
	node.mesh = cyl
	node.position = pos
	var mat := _mat(Color(0.94, 0.94, 0.96))
	node.material_override = mat
	add_child(node)
	pins.append({
		"node": node, "mat": mat, "standing": true,
		"vel": Vector3.ZERO, "tip_angle": 0.0,
		"tip_axis": Vector3.RIGHT,
	})


func _step_pins(delta: float) -> void:
	for p_v in pins:
		var p: Dictionary = p_v
		if bool(p["standing"]):
			continue
		var node: MeshInstance3D = p["node"]
		if not is_instance_valid(node):
			continue
		# Slide along the lane floor.
		var vel: Vector3 = p["vel"]
		if vel.length_squared() > 0.0004:
			node.position += vel * delta
			node.position.y = 0.10
			vel *= maxf(0.0, 1.0 - 2.2 * delta)
			p["vel"] = vel
		# Tip over toward flat.
		var tip := float(p["tip_angle"])
		if tip < PI * 0.5:
			var step := minf(delta * 7.0, PI * 0.5 - tip)
			node.rotate((p["tip_axis"] as Vector3).normalized(), step)
			p["tip_angle"] = tip + step
		# A sliding pin can knock standing pins down.
		if vel.length() > 0.6:
			_pin_hits_pins(p)


func _check_pin_hits() -> void:
	if guttered:
		return
	for p_v in pins:
		var p: Dictionary = p_v
		if not bool(p["standing"]):
			continue
		var node: MeshInstance3D = p["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(ball.position.x - node.position.x, ball.position.z - node.position.z).length()
		if d < BALL_RADIUS + PIN_RADIUS + 0.02 and ball.position.y < 0.6:
			var dir := Vector3(node.position.x - ball.position.x, 0.0, node.position.z - ball.position.z)
			if dir.length_squared() < 0.0001:
				dir = Vector3(0.0, 0.0, -1.0)
			dir = dir.normalized()
			_knock_pin(p, dir * ball_vel.length() * 0.9 + ball_vel * 0.5)
			ball_vel *= 0.93
			if knock_player != null:
				knock_player.play()


func _pin_hits_pins(mover: Dictionary) -> void:
	var mnode: MeshInstance3D = mover["node"]
	if not is_instance_valid(mnode):
		return
	var mvel: Vector3 = mover["vel"]
	for p_v in pins:
		var p: Dictionary = p_v
		if not bool(p["standing"]) or p == mover:
			continue
		var node: MeshInstance3D = p["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(mnode.position.x - node.position.x, mnode.position.z - node.position.z).length()
		if d < PIN_RADIUS * 2.0 + 0.06:
			var dir := Vector3(node.position.x - mnode.position.x, 0.0, node.position.z - mnode.position.z)
			if dir.length_squared() < 0.0001:
				dir = Vector3(0.0, 0.0, -1.0)
			dir = dir.normalized()
			_knock_pin(p, dir * mvel.length() * 0.75)
			if knock_player != null:
				knock_player.play()


func _knock_pin(p: Dictionary, vel: Vector3) -> void:
	p["standing"] = false
	p["vel"] = vel
	var pnode: MeshInstance3D = p["node"]
	if is_instance_valid(pnode):
		GraphicsPolish.spawn_sparks(self, pnode.position + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.9, 0.5), 12)
	var flat := Vector3(vel.x, 0.0, vel.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	p["tip_axis"] = Vector3(flat.z, 0.0, -flat.x).normalized()


# ---------------------------------------------------------------- ball ----

func _ready_ball() -> void:
	ball.position = BALL_START
	ball.rotation = Vector3.ZERO
	ball_vel = Vector3.ZERO
	ball_vy = 0.0
	guttered = false
	roll_timer = 0.0
	state = ST_READY
	aim_arrow.visible = false


func _update_aim() -> void:
	var drag := cur_mouse - press_pos
	var power := clampf(drag.y / 350.0, 0.0, 1.0)
	var lateral := clampf(drag.x / 300.0, -1.0, 1.0) * 0.55
	var dir := Vector3(lateral, 0.0, -1.0).normalized()
	var length := 0.6 + power * 2.4
	aim_arrow.visible = true
	aim_arrow.position = BALL_START + dir * (length * 0.5 + 0.3)
	aim_arrow.position.y = 0.06
	aim_arrow.rotation.y = atan2(-dir.x, -dir.z)
	aim_arrow.scale = Vector3(1.0, 1.0, length)


func _release_throw(release_pos: Vector2) -> void:
	aim_arrow.visible = false
	var drag := release_pos - press_pos
	var power := clampf(drag.y / 350.0, 0.0, 1.0)
	if power < 0.06:
		# Too weak: treat as a cancelled aim.
		state = ST_READY
		return
	var lateral := clampf(drag.x / 300.0, -1.0, 1.0) * 0.55
	var speed := lerpf(MIN_SPEED, MAX_SPEED, power)
	ball_vel = Vector3(lateral * speed, 0.0, -speed)
	pins_before_throw = 0
	for p_v in pins:
		var p: Dictionary = p_v
		if bool(p["standing"]):
			pins_before_throw += 1
	state = ST_ROLLING
	if throw_player != null:
		throw_player.play()


func _step_ball(delta: float) -> void:
	if guttered:
		ball_vy -= 12.0 * delta
		ball.position += ball_vel * delta
		ball.position.y += ball_vy * delta
	else:
		if absf(ball.position.x) > LANE_HALF + 0.02 and ball.position.z < 0.5:
			guttered = true
			ball_vy = 0.0
			if gutter_player != null:
				gutter_player.play()
			_show_msg("GUTTER!")
		_room_wall_bounce() # v0.7.0: bounce off real room walls (no-op w/o room data).
		# Friction.
		ball_vel *= maxf(0.0, 1.0 - FRICTION * delta)
		ball.position += ball_vel * delta
		ball.position.y = BALL_RADIUS
		# Roll the ball visually.
		var planar := Vector2(ball_vel.x, ball_vel.z).length()
		if planar > 0.01:
			var axis := Vector3.UP.cross(ball_vel).normalized()
			ball.rotate(axis, planar / BALL_RADIUS * delta)


## RoomKit (v0.7.0): reflect the ball off real room wall planes, in world
## space. The plane test is normal-sign agnostic (bounce(n) == bounce(-n)),
## so it works regardless of the anchor's facing convention. No-op on
## desktop / without room data; lane and gutter logic are unchanged.
func _room_wall_bounce() -> void:
	if not (RoomKit.is_available() and RoomKit.has_room_data()):
		return
	var gp: Vector3 = ball.global_position
	var wvel: Vector3 = global_transform.basis * ball_vel
	for w_v in RoomKit.get_walls():
		var w: Dictionary = w_v
		var n: Vector3 = (w["normal"] as Vector3).normalized()
		if absf(n.y) > 0.5:
			continue # not a vertical wall
		var dist: float = (gp - (w["position"] as Vector3)).dot(n)
		if absf(dist) >= BALL_RADIUS:
			continue
		var vn := wvel.dot(n)
		if (dist > 0.0 and vn < 0.0) or (dist < 0.0 and vn > 0.0):
			wvel = wvel.bounce(n)
			gp += n * (-signf(dist) * (BALL_RADIUS - absf(dist) + 0.005))
	ball.global_position = gp
	ball_vel = global_transform.basis.inverse() * wvel


func _check_throw_end() -> void:
	var planar := Vector2(ball_vel.x, ball_vel.z).length()
	if guttered:
		if ball.position.z < PAST_PINS_Z or ball.position.y < -2.0:
			state = ST_SETTLE
			settle_timer = 1.2
	elif ball.position.z < PAST_PINS_Z or (roll_timer > 1.0 and planar < 0.35):
		state = ST_SETTLE
		settle_timer = 1.6


func _resolve_throw() -> void:
	var standing_now := 0
	for p_v in pins:
		var p: Dictionary = p_v
		if bool(p["standing"]):
			standing_now += 1
	var knocked := pins_before_throw - standing_now
	# Clear dead wood.
	for i in range(pins.size() - 1, -1, -1):
		var p: Dictionary = pins[i]
		if not bool(p["standing"]):
			var node: MeshInstance3D = p["node"]
			if is_instance_valid(node):
				node.queue_free()
			pins.remove_at(i)
	_record_throw(knocked)


# -------------------------------------------------------------- scoring ----

func _record_throw(knocked: int) -> void:
	var ft: Array = frames[frame_idx]
	ft.append(knocked)
	if frame_idx < 9:
		if ft.size() == 1 and knocked == 10:
			_show_msg("STRIKE!")
			GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.0, HEAD_PIN_Z), 70)
			if strike_player != null:
				strike_player.play()
			_next_frame()
		elif ft.size() == 2:
			if int(ft[0]) + int(ft[1]) == 10:
				_show_msg("SPARE!")
			_next_frame()
		else:
			_ready_ball() # second ball at the remaining pins
	else:
		_tenth_frame_next()


func _tenth_frame_next() -> void:
	var ft: Array = frames[9]
	if ft.size() >= 3:
		_game_over()
		return
	if ft.size() == 2:
		if int(ft[0]) == 10 or int(ft[0]) + int(ft[1]) == 10:
			if pins.is_empty():
				_reset_rack()
			_ready_ball()
		else:
			_game_over()
	elif ft.size() == 1:
		if int(ft[0]) == 10:
			_reset_rack()
		_ready_ball()


func _next_frame() -> void:
	frame_idx += 1
	if frame_idx > 9:
		_game_over()
		return
	_reset_rack()
	_ready_ball()


func _game_over() -> void:
	state = ST_OVER
	aim_arrow.visible = false
	_show_msg("GAME OVER\nFinal Score: %d\nPress R for new game" % _total_score(), 600.0)


func _reset_game() -> void:
	for p_v in pins:
		var p: Dictionary = p_v
		var node: MeshInstance3D = p["node"]
		if is_instance_valid(node):
			node.queue_free()
	pins.clear()
	frames.clear()
	for i in range(10):
		frames.append([])
	frame_idx = 0
	_reset_rack()
	_ready_ball()
	_show_msg("")
	ARUpgradeKit.save_anchor("ar-bowling_main", global_transform)


func _flat_rolls() -> Array:
	var rolls: Array = []
	for f_v in frames:
		var f: Array = f_v
		for t_v in f:
			rolls.append(int(t_v))
	while rolls.size() < 21:
		rolls.append(0)
	return rolls


func _total_score() -> int:
	var rolls := _flat_rolls()
	var score := 0
	var r := 0
	for f in range(10):
		if rolls[r] == 10:
			score += 10 + int(rolls[r + 1]) + int(rolls[r + 2])
			r += 1
		elif int(rolls[r]) + int(rolls[r + 1]) == 10:
			score += 10 + int(rolls[r + 2])
			r += 2
		else:
			score += int(rolls[r]) + int(rolls[r + 1])
			r += 2
	return score


func _frame_scores() -> Array:
	var rolls := _flat_rolls()
	var out: Array = []
	var score := 0
	var r := 0
	for f in range(10):
		if rolls[r] == 10:
			score += 10 + int(rolls[r + 1]) + int(rolls[r + 2])
			r += 1
		elif int(rolls[r]) + int(rolls[r + 1]) == 10:
			score += 10 + int(rolls[r + 2])
			r += 2
		else:
			score += int(rolls[r]) + int(rolls[r + 1])
			r += 2
		out.append(score)
	return out


func _pin_str(k: int) -> String:
	return "-" if k == 0 else str(k)


func _frame_marks(fi: int) -> String:
	var ft: Array = frames[fi]
	var parts: Array = []
	if fi < 9:
		if ft.size() >= 1:
			parts.append("X" if int(ft[0]) == 10 else _pin_str(int(ft[0])))
		if ft.size() >= 2:
			if int(ft[0]) + int(ft[1]) == 10:
				parts.append("/")
			else:
				parts.append(_pin_str(int(ft[1])))
	else:
		if ft.size() >= 1:
			parts.append("X" if int(ft[0]) == 10 else _pin_str(int(ft[0])))
		if ft.size() >= 2:
			if int(ft[0]) == 10:
				parts.append("X" if int(ft[1]) == 10 else _pin_str(int(ft[1])))
			elif int(ft[0]) + int(ft[1]) == 10:
				parts.append("/")
			else:
				parts.append(_pin_str(int(ft[1])))
		if ft.size() >= 3:
			if int(ft[1]) == 10:
				parts.append("X" if int(ft[2]) == 10 else _pin_str(int(ft[2])))
			elif int(ft[0]) == 10:
				parts.append("/" if int(ft[1]) + int(ft[2]) == 10 else _pin_str(int(ft[2])))
			else:
				parts.append("X" if int(ft[2]) == 10 else _pin_str(int(ft[2])))
	return " ".join(parts)


# ---------------------------------------------------------------- audio ----

func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (knock / strike / gutter / throw).
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
