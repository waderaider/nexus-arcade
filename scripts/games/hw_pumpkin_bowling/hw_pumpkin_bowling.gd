## HwPumpkinBowling - "Pumpkin Bowling" (NEXUS ARCADE Halloween set).
## Roll a jack-o'-lantern pumpkin (drag back and release, or pinch-hold and
## release) down a haunted lane at ghost pins. 60-second round: 10 points per
## ghost, clearing a full rack in one throw is a STRIKE worth +50 x combo.
## R or a 1-second pinch-hold restarts.
extends Node3D

const ROUND_TIME := 60.0
const LANE_HALF := 0.55
const BALL_RADIUS := 0.16
const GHOST_RADIUS := 0.11
const BALL_START := Vector3(0.0, 0.16, 1.4)
const HEAD_PIN_Z := -5.5
const PIN_DZ := 0.32
const PIN_DX := 0.22
const MIN_SPEED := 4.0
const MAX_SPEED := 12.0
const FRICTION := 0.45
const PAST_PINS_Z := -8.6
const ST_READY := 0
const ST_AIMING := 1
const ST_ROLLING := 2
const ST_SETTLE := 3
const ST_OVER := 4

var camera: Camera3D = null
var state := ST_READY
var time_left := ROUND_TIME
var score := 0
var throws := 0
var strike_combo := 0
var ball: MeshInstance3D = null
var ball_vel := Vector3.ZERO
var guttered := false
var roll_timer := 0.0
var aim_arrow: MeshInstance3D = null
var press_pos := Vector2.ZERO
var cur_mouse := Vector2.ZERO
var ghosts: Array = [] # dicts: node, standing, vel, tip_angle, tip_axis
var ghosts_before_throw := 10
var settle_timer := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var pinch_aiming := false
var knock_player: AudioStreamPlayer = null
var strike_player: AudioStreamPlayer = null
var gutter_player: AudioStreamPlayer = null
var throw_player: AudioStreamPlayer = null

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
var _rack_shift_z := 0.0 # slides the pin rack to the room's far end
var _pit_node: MeshInstance3D = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_lane()
	_build_ball()
	_build_aim_arrow()
	_build_hud()
	_reset_rack()
	_ready_ball()
	knock_player = _make_player(_make_tone(320.0, 0.12, 0.6))
	strike_player = _make_player(_make_tone(880.0, 0.35, 0.55))
	gutter_player = _make_player(_make_tone(120.0, 0.45, 0.55))
	throw_player = _make_player(_make_tone(430.0, 0.18, 0.4))
	ARUpgradeKit.apply_anchor(self, "hw_pumpkin_bowling_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -4.0), 3.0)
	_apply_room_layout()


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_known = true
	# Run the lane down the room's long axis, and slide the pin rack to
	# the far end of the real room so throws stay inside the play space.
	# v0.7.0 furniture morphs: the rug becomes an arcane lane carpet the
	# lane aligns to, and the door becomes the haunted gate the ghost
	# pins defend.
	var along_x := _room_bounds.size.x > _room_bounds.size.y * 1.5
	var rug_anchors := RoomKit.get_anchors("RUG")
	if not rug_anchors.is_empty():
		RoomKit.morph(rug_anchors[0], "arcane")
		var rs: Vector3 = rug_anchors[0]["extents"]
		along_x = rs.x > rs.z * 1.5
	var door_anchors := RoomKit.get_anchors("DOOR")
	if not door_anchors.is_empty():
		RoomKit.morph(door_anchors[0], "haunted")
	if along_x:
		rotation.y = PI * 0.5
	var gp := global_position
	var far := _room_bounds.position.y + 0.9
	var axis_p := gp.z
	if along_x:
		far = _room_bounds.position.x + 0.9
		axis_p = gp.x
	_rack_shift_z = far - axis_p - HEAD_PIN_Z
	if _pit_node != null:
		_pit_node.position.z = HEAD_PIN_Z + _rack_shift_z - 2.6
	_reset_rack()
	_ready_ball()


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
	camera.position = Vector3(0.0, 1.7, 3.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.2, -4.5), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_pumpkin_bowling_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self):
			hold_restart += delta
		else:
			hold_restart = 0.0
		if hold_restart >= 1.0:
			_reset_game()
			return
		_update_hud()
		return
	if state == ST_READY or state == ST_AIMING:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_game_over()
			return
	_poll_pinch()
	if state == ST_AIMING:
		_update_aim()
	if state == ST_ROLLING or state == ST_SETTLE:
		roll_timer += delta
		_step_ball(delta)
		if state == ST_ROLLING:
			_check_ghost_hits()
			_check_throw_end()
		elif state == ST_SETTLE:
			settle_timer -= delta
			if settle_timer <= 0.0:
				_resolve_throw()
	_step_ghosts(delta)
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
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
			elif not mb.pressed and state == ST_AIMING and not pinch_aiming:
				_release_throw(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cur_mouse = mm.position


func _pointer_screen() -> Vector2:
	var wp := ARUpgradeKit.pointer_position(self)
	if camera != null:
		return camera.unproject_position(wp)
	return cur_mouse


func _poll_pinch() -> void:
	var pinching := ARUpgradeKit.pinch_active(self)
	if state == ST_READY and ARUpgradeKit.pinch_just_pressed(self):
		state = ST_AIMING
		pinch_aiming = true
		press_pos = _pointer_screen()
		cur_mouse = press_pos
	elif state == ST_AIMING and pinch_aiming:
		cur_mouse = _pointer_screen()
		if not pinching:
			pinch_aiming = false
			_release_throw(cur_mouse)


# ------------------------------------------------------------------ build --

func _build_lane() -> void:
	var lane := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(LANE_HALF * 2.0 + 0.16, 0.08, 10.0)
	lane.mesh = lb
	lane.position = Vector3(0.0, -0.04, -3.4)
	lane.material_override = GraphicsPolish.pbr(Color(0.22, 0.12, 0.28), 0.1, 0.6)
	add_child(lane)
	# Glowing lane edges.
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.05, 0.03, 10.0)
		strip.mesh = sb
		strip.position = Vector3(side * (LANE_HALF + 0.10), 0.02, -3.4)
		strip.material_override = GraphicsPolish.glow(Color(0.65, 0.25, 1.0), 1.4)
		add_child(strip)
	# Backstop.
	var pit := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(3.0, 2.2, 0.3)
	pit.mesh = pb
	pit.position = Vector3(0.0, 0.9, -9.6)
	pit.material_override = GraphicsPolish.pbr(Color(0.05, 0.04, 0.08), 0.0, 0.9)
	add_child(pit)
	_pit_node = pit
	# Floor.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 16.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.09, -3.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.07, 0.06, 0.10), 0.0, 0.9)
	add_child(floor_inst)


func _build_ball() -> void:
	ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = BALL_RADIUS
	s.height = BALL_RADIUS * 2.0
	ball.mesh = s
	ball.material_override = GraphicsPolish.pbr(Color(0.92, 0.48, 0.08), 0.05, 0.5)
	ball.position = BALL_START
	add_child(ball)
	# Stem.
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.035
	cyl.height = 0.09
	stem.mesh = cyl
	stem.position = Vector3(0.0, BALL_RADIUS + 0.03, 0.0)
	stem.material_override = GraphicsPolish.pbr(Color(0.20, 0.45, 0.15), 0.0, 0.8)
	ball.add_child(stem)
	# Carved glowing face.
	var face := GraphicsPolish.glow(Color(1.0, 0.80, 0.25), 1.8)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.05, 0.07, 0.02)
		eye.mesh = eb
		eye.position = Vector3(side * 0.06, 0.05, BALL_RADIUS - 0.01)
		eye.material_override = face
		ball.add_child(eye)
	var mouth := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.13, 0.045, 0.02)
	mouth.mesh = mb
	mouth.position = Vector3(0.0, -0.045, BALL_RADIUS - 0.01)
	mouth.material_override = face
	ball.add_child(mouth)
	ball.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.15), 0.06))


func _build_aim_arrow() -> void:
	aim_arrow = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.02, 1.0)
	aim_arrow.mesh = box
	aim_arrow.material_override = GraphicsPolish.glow(Color(1.0, 0.6, 0.1), 1.6)
	aim_arrow.visible = false
	add_child(aim_arrow)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("PUMPKIN BOWLING", 44, Color(1.0, 0.7, 0.25))
	hud_label.position = Vector3(-3.3, 2.6, -1.0)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 84, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 2.2, -5.5)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "PUMPKIN BOWLING\nTime: %ds   Score: %d   Strike x%d\nDrag back & release to roll | R: restart" % [int(ceil(time_left)), score, strike_combo]


func _show_msg(text: String, duration: float = 1.8) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ----------------------------------------------------------------- ghosts --

func _reset_rack() -> void:
	for g_v in ghosts:
		var g: Dictionary = g_v
		var node: MeshInstance3D = g["node"]
		if is_instance_valid(node):
			node.queue_free()
	ghosts.clear()
	for row in range(4):
		for j in range(row + 1):
			var x := (float(j) - float(row) * 0.5) * PIN_DX
			var z := HEAD_PIN_Z + _rack_shift_z - float(row) * PIN_DZ
			_spawn_ghost(Vector3(x, 0.0, z))


func _spawn_ghost(pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.position = pos
	var sheet := GraphicsPolish.pbr(Color(0.92, 0.93, 0.97), 0.0, 0.7)
	sheet.emission_enabled = true
	sheet.emission = Color(0.75, 0.78, 0.90)
	sheet.emission_energy_multiplier = 0.35
	# Head.
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = GHOST_RADIUS
	hs.height = GHOST_RADIUS * 2.0
	head.mesh = hs
	head.position = Vector3(0.0, 0.42, 0.0)
	head.material_override = sheet
	node.add_child(head)
	# Sheet body.
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = GHOST_RADIUS
	cyl.bottom_radius = GHOST_RADIUS * 1.25
	cyl.height = 0.34
	body.mesh = cyl
	body.position = Vector3(0.0, 0.19, 0.0)
	body.material_override = sheet
	node.add_child(body)
	# Spooky face.
	var dark := GraphicsPolish.pbr(Color(0.05, 0.05, 0.08), 0.0, 0.9)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.028
		es.height = 0.056
		eye.mesh = es
		eye.position = Vector3(side * 0.045, 0.46, 0.09)
		eye.material_override = dark
		node.add_child(eye)
	var mouth := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.030
	ms.height = 0.075
	mouth.mesh = ms
	mouth.scale = Vector3(1.0, 1.4, 0.6)
	mouth.position = Vector3(0.0, 0.375, 0.095)
	mouth.material_override = dark
	node.add_child(mouth)
	add_child(node)
	ghosts.append({"node": node, "standing": true, "vel": Vector3.ZERO, "tip_angle": 0.0, "tip_axis": Vector3.RIGHT})


func _step_ghosts(delta: float) -> void:
	for g_v in ghosts:
		var g: Dictionary = g_v
		if bool(g["standing"]):
			continue
		var node: MeshInstance3D = g["node"]
		if not is_instance_valid(node):
			continue
		var vel: Vector3 = g["vel"]
		if vel.length_squared() > 0.0004:
			node.position += vel * delta
			node.position.y = 0.0
			vel *= maxf(0.0, 1.0 - 2.2 * delta)
			g["vel"] = vel
		var tip := float(g["tip_angle"])
		if tip < PI * 0.5:
			var step := minf(delta * 7.0, PI * 0.5 - tip)
			node.rotate((g["tip_axis"] as Vector3).normalized(), step)
			g["tip_angle"] = tip + step
		if vel.length() > 0.6:
			_ghost_hits_ghosts(g)


func _check_ghost_hits() -> void:
	if guttered:
		return
	for g_v in ghosts:
		var g: Dictionary = g_v
		if not bool(g["standing"]):
			continue
		var node: MeshInstance3D = g["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(ball.position.x - node.position.x, ball.position.z - node.position.z).length()
		if d < BALL_RADIUS + GHOST_RADIUS + 0.03 and ball.position.y < 0.7:
			var dir := Vector3(node.position.x - ball.position.x, 0.0, node.position.z - ball.position.z)
			if dir.length_squared() < 0.0001:
				dir = Vector3(0.0, 0.0, -1.0)
			dir = dir.normalized()
			_knock_ghost(g, dir * ball_vel.length() * 0.9 + ball_vel * 0.5)
			ball_vel *= 0.93
			knock_player.play()


func _ghost_hits_ghosts(mover: Dictionary) -> void:
	var mnode: MeshInstance3D = mover["node"]
	if not is_instance_valid(mnode):
		return
	var mvel: Vector3 = mover["vel"]
	for g_v in ghosts:
		var g: Dictionary = g_v
		if not bool(g["standing"]) or g == mover:
			continue
		var node: MeshInstance3D = g["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(mnode.position.x - node.position.x, mnode.position.z - node.position.z).length()
		if d < GHOST_RADIUS * 2.0 + 0.06:
			var dir := Vector3(node.position.x - mnode.position.x, 0.0, node.position.z - mnode.position.z)
			if dir.length_squared() < 0.0001:
				dir = Vector3(0.0, 0.0, -1.0)
			dir = dir.normalized()
			_knock_ghost(g, dir * mvel.length() * 0.75)
			knock_player.play()


func _knock_ghost(g: Dictionary, vel: Vector3) -> void:
	g["standing"] = false
	g["vel"] = vel
	var node: MeshInstance3D = g["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, to_local(node.global_position + Vector3(0, 0.4, 0)), Color(0.8, 0.85, 1.0), 12)
	var flat := Vector3(vel.x, 0.0, vel.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	g["tip_axis"] = Vector3(flat.z, 0.0, -flat.x).normalized()


# ------------------------------------------------------------------- ball --

func _ready_ball() -> void:
	ball.position = BALL_START
	ball.rotation = Vector3.ZERO
	ball_vel = Vector3.ZERO
	guttered = false
	roll_timer = 0.0
	state = ST_READY
	aim_arrow.visible = false


func _update_aim() -> void:
	var drag := cur_mouse - press_pos
	var power := clampf(drag.y / 350.0, 0.0, 1.0)
	var lateral := clampf(drag.x / 300.0, -1.0, 1.0) * 0.55
	var dir := Vector3(lateral, 0.0, -1.0).normalized()
	var length := 0.6 + power * 2.2
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
		state = ST_READY
		return
	throws += 1
	var lateral := clampf(drag.x / 300.0, -1.0, 1.0) * 0.55
	var speed := lerpf(MIN_SPEED, MAX_SPEED, power)
	ball_vel = Vector3(lateral * speed, 0.0, -speed)
	ghosts_before_throw = 0
	for g_v in ghosts:
		var g: Dictionary = g_v
		if bool(g["standing"]):
			ghosts_before_throw += 1
	state = ST_ROLLING
	throw_player.play()


func _step_ball(delta: float) -> void:
	ball_vel *= maxf(0.0, 1.0 - FRICTION * delta)
	ball.position += ball_vel * delta
	ball.position.y = BALL_RADIUS
	if absf(ball.position.x) > LANE_HALF + 0.05 and ball.position.z < 0.8 and not guttered:
		guttered = true
		gutter_player.play()
		_show_msg("GUTTER!")
	var planar := Vector2(ball_vel.x, ball_vel.z).length()
	if planar > 0.01:
		var axis := Vector3.UP.cross(ball_vel).normalized()
		ball.rotate(axis, planar / BALL_RADIUS * delta)


func _check_throw_end() -> void:
	var planar := Vector2(ball_vel.x, ball_vel.z).length()
	if ball.position.z < PAST_PINS_Z + _rack_shift_z or (roll_timer > 1.0 and planar < 0.35):
		state = ST_SETTLE
		settle_timer = 1.4


func _resolve_throw() -> void:
	var standing_now := 0
	for g_v in ghosts:
		var g: Dictionary = g_v
		if bool(g["standing"]):
			standing_now += 1
	var knocked := ghosts_before_throw - standing_now
	score += knocked * 10
	for i in range(ghosts.size() - 1, -1, -1):
		var g: Dictionary = ghosts[i]
		if not bool(g["standing"]):
			var node: MeshInstance3D = g["node"]
			if is_instance_valid(node):
				node.queue_free()
			ghosts.remove_at(i)
	if knocked == 10 and ghosts_before_throw == 10:
		strike_combo += 1
		var bonus := 50 * strike_combo
		score += bonus
		_show_msg("STRIKE x%d! +%d" % [strike_combo, bonus], 2.2)
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.0, HEAD_PIN_Z + _rack_shift_z), 70)
		strike_player.play()
	elif knocked > 0:
		strike_combo = 0
		_show_msg("+%d" % (knocked * 10), 1.0)
	else:
		strike_combo = 0
	if ghosts.is_empty():
		_reset_rack()
	_ready_ball()


# ------------------------------------------------------------------- flow --

func _game_over() -> void:
	state = ST_OVER
	aim_arrow.visible = false
	_show_msg("TIME'S UP!\nScore: %d   Throws: %d\nHold pinch 1s or press R" % [score, throws], 600.0)
	ARUpgradeKit.save_anchor("hw_pumpkin_bowling_main", global_transform)


func _reset_game() -> void:
	time_left = ROUND_TIME
	score = 0
	throws = 0
	strike_combo = 0
	hold_restart = 0.0
	_reset_rack()
	_ready_ball()
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_pumpkin_bowling_main", global_transform)


# ------------------------------------------------------------------ audio --

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
