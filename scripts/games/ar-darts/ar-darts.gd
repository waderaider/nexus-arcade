## AR Darts: dartboard anchored on the wall in front of the player.
## Desktop: click a dart, drag, and flick-release to throw it toward the board
## (drag length = power, drag direction nudges aim). XR: pinch to grab the
## held dart, flick your hand forward and release to throw; the release
## velocity spike launches the dart along your pointer direction.
## Darts fly with slight gravity; score rings 1-20 plus bullseye with real
## dartboard sector order. 3 darts per round, 5 rounds, then game over.
## R restarts. Best score persists via anchor.
extends Node3D

const SECTOR_ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const BOARD_POS := Vector3(0.0, 1.75, -2.6)
const BOARD_R := 0.46
const DOUBLE_LO := 0.30
const DOUBLE_HI := 0.34
const TREBLE_LO := 0.16
const TREBLE_HI := 0.20
const BULL_OUT := 0.062
const BULL_IN := 0.028
const GRAVITY := 4.5
const DARTS_PER_ROUND := 3
const ROUNDS := 5

var camera: Camera3D = null
var board: Node3D = null
var bull_mat: StandardMaterial3D = null
var held_dart: MeshInstance3D = null
var held_dart_visible := true
var dart_flying := false
var dart_pos := Vector3.ZERO
var dart_vel := Vector3.ZERO
var dart_spin := 0.0
var dart_mesh_fly: MeshInstance3D = null
var aiming := false
var aim_start := Vector2.ZERO
var xr_grab := false
var xr_pointer_prev := Vector3.ZERO
var xr_pointer_vel := Vector3.ZERO
var prev_pinch := false
var darts_thrown := 0
var round_num := 1
var score := 0
var best := 0
var state := "playing"
var last_hit := ""
var msg := ""
var msg_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var pulse_t := 0.0


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "ar-darts_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_build_board()
	_build_held_dart()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.0), 2.0, 30)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.65, 1.4)
	add_child(camera)
	camera.look_at(BOARD_POS, Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.32, 0.45)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.1)


func _ring(radius: float, color: Color, z_off: float, energy: float = 0.6) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	inst.mesh = cyl
	inst.material_override = GraphicsPolish.glow(color, energy)
	inst.rotation_degrees.x = 90.0
	inst.position.z = z_off
	return inst


func _build_board() -> void:
	board = Node3D.new()
	board.position = BOARD_POS
	add_child(board)
	# Cabinet backing.
	var back := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(1.25, 1.25, 0.08)
	back.mesh = bbox
	back.material_override = GraphicsPolish.pbr_preset(Color(0.16, 0.10, 0.06), "matte")
	back.position.z = -0.06
	board.add_child(back)
	# Concentric rings, stacked toward the viewer.
	board.add_child(_ring(BOARD_R, Color(0.05, 0.05, 0.06), 0.0))
	board.add_child(_ring(DOUBLE_HI, Color(0.1, 0.55, 0.25), 0.012))
	board.add_child(_ring(DOUBLE_LO, Color(0.92, 0.88, 0.78), 0.024))
	board.add_child(_ring(TREBLE_HI, Color(0.75, 0.15, 0.15), 0.036))
	board.add_child(_ring(TREBLE_LO, Color(0.08, 0.08, 0.09), 0.048))
	board.add_child(_ring(BULL_OUT, Color(0.1, 0.55, 0.25), 0.060))
	bull_mat = GraphicsPolish.glow(Color(0.8, 0.15, 0.15), 2.0)
	var bull := _ring(BULL_IN, Color(0.8, 0.15, 0.15), 0.072)
	bull.material_override = bull_mat
	board.add_child(bull)
	# Radial separators + sector numbers.
	for i in 20:
		var ang := deg_to_rad(float(i) * 18.0 - 9.0)
		var sep := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.012, DOUBLE_HI - BULL_OUT, 0.01)
		sep.mesh = sbox
		sep.material_override = GraphicsPolish.pbr(Color(0.7, 0.7, 0.75), 0.6, 0.4)
		var mid_r := (DOUBLE_HI + BULL_OUT) * 0.5
		sep.position = Vector3(cos(ang + PI * 0.5) * mid_r, sin(ang + PI * 0.5) * mid_r, 0.05)
		sep.rotation.z = ang
		board.add_child(sep)
		var num_ang := deg_to_rad(float(i) * 18.0)
		var lbl := GraphicsPolish.make_label(str(SECTOR_ORDER[i]), 36, Color(1.0, 1.0, 1.0))
		var nr := BOARD_R + 0.09
		lbl.position = Vector3(cos(num_ang + PI * 0.5) * nr, sin(num_ang + PI * 0.5) * nr, 0.02)
		lbl.pixel_size = 0.0035
		board.add_child(lbl)
	GraphicsPolish.make_point_light(board, Vector3(0, 0.6, 0.8), Color(1.0, 0.95, 0.85), 0.8, 3.0)


func _make_dart_mesh() -> MeshInstance3D:
	var dart := MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.008
	body.bottom_radius = 0.02
	body.height = 0.16
	dart.mesh = body
	dart.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.2, 0.2), "metal")
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.008
	cone.height = 0.05
	tip.mesh = cone
	tip.material_override = GraphicsPolish.pbr(Color(0.9, 0.9, 0.95), 0.9, 0.25)
	tip.position.y = -0.105
	dart.add_child(tip)
	var flight := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.06, 0.05, 0.008)
	flight.mesh = fbox
	flight.material_override = GraphicsPolish.glow(Color(0.3, 0.8, 1.0), 1.2)
	flight.position.y = 0.10
	dart.add_child(flight)
	return dart


func _build_held_dart() -> void:
	held_dart = _make_dart_mesh()
	held_dart.position = Vector3(0.35, 1.15, 0.9)
	held_dart.rotation_degrees = Vector3(-70, 0, 0)
	add_child(held_dart)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.6, 2.9, -1.0)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.4))
	msg_label.position = Vector3(0.0, 2.9, -2.4)
	msg_label.pixel_size = 0.008
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("", 30, Color(0.75, 0.8, 0.9))
	help_label.position = Vector3(-2.6, 2.62, -1.0)
	help_label.pixel_size = 0.004
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		var dart_left := DARTS_PER_ROUND - ((darts_thrown) % DARTS_PER_ROUND)
		hud_label.text = "Score %d   Round %d/%d   Darts %d" % [score, round_num, ROUNDS, dart_left]
	if help_label != null:
		if ARUpgradeKit.is_xr_active():
			help_label.text = "Pinch dart, flick forward, release | R: restart"
		else:
			help_label.text = "Click-drag-FLICK on a dart to throw | R: restart"
	if msg_label != null:
		msg_label.text = msg


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != "playing":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not dart_flying and not aiming:
					aiming = true
					aim_start = mb.position
			else:
				if aiming:
					aiming = false
					_throw_mouse(mb.position)


func _throw_mouse(release_pos: Vector2) -> void:
	if camera == null or dart_flying:
		return
	var flick: Vector2 = aim_start - release_pos
	var power := clampf(flick.length() * 0.022, 0.0, 11.0)
	if power < 1.6:
		_set_msg("Too soft!", 1.0)
		return
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var right := basis.x
	var up := basis.y
	var vel: Vector3 = fwd * power + right * (flick.x * 0.006) + up * (-flick.y * 0.006 + 1.1)
	_launch_dart(held_dart.global_position, vel)


func _launch_dart(from: Vector3, vel: Vector3) -> void:
	dart_flying = true
	dart_pos = from
	dart_vel = vel
	held_dart.visible = false
	if dart_mesh_fly != null and is_instance_valid(dart_mesh_fly):
		dart_mesh_fly.queue_free()
	dart_mesh_fly = _make_dart_mesh()
	add_child(dart_mesh_fly)
	dart_mesh_fly.global_position = from
	dart_mesh_fly.add_child(GraphicsPolish.make_trail(Color(1.0, 0.5, 0.3), 0.03))


func _process(delta: float) -> void:
	pulse_t += delta
	if bull_mat != null:
		GraphicsPolish.pulse_glow(bull_mat, 2.0, 0.9, pulse_t, 2.5)
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if Input.is_key_pressed(KEY_R):
		_restart()
	# XR throwing: grab the dart with a pinch, flick, release.
	if ARUpgradeKit.is_xr_active() and state == "playing" and not dart_flying:
		var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if pinching and not prev_pinch:
			xr_grab = true
			xr_pointer_prev = pp
			xr_pointer_vel = Vector3.ZERO
		elif pinching and xr_grab:
			if delta > 0.0:
				var v: Vector3 = (pp - xr_pointer_prev) / delta
				xr_pointer_vel = xr_pointer_vel.lerp(v, 0.5)
			xr_pointer_prev = pp
			held_dart.global_position = pp
		elif not pinching and prev_pinch and xr_grab:
			xr_grab = false
			if xr_pointer_vel.length() > 1.6:
				var to_board: Vector3 = (BOARD_POS - pp).normalized()
				var vel: Vector3 = to_board * xr_pointer_vel.length() * 0.9 + xr_pointer_vel * 0.35
				_launch_dart(pp, vel)
			else:
				held_dart.position = Vector3(0.35, 1.15, 0.9)
		prev_pinch = pinching
	if dart_flying:
		_move_dart(delta)
	_update_hud()


func _move_dart(delta: float) -> void:
	dart_vel.y -= GRAVITY * delta
	dart_pos += dart_vel * delta
	var prev_z: float = dart_mesh_fly.global_position.z
	dart_mesh_fly.global_position = dart_pos
	if dart_vel.length() > 0.1:
		var dir: Vector3 = dart_vel.normalized()
		dart_mesh_fly.global_transform.basis = Basis.looking_at(dir, Vector3.UP)
	# Crossed the board plane?
	var board_z := BOARD_POS.z
	if prev_z > board_z and dart_pos.z <= board_z:
		_resolve_hit(dart_pos)
		return
	# Hit the floor or flew past.
	if dart_pos.y < 0.02 or dart_pos.z < board_z - 1.5:
		_resolve_hit(dart_pos, true)


func _resolve_hit(pos: Vector3, floor_hit: bool = false) -> void:
	dart_flying = false
	var gained := 0
	var desc := ""
	if floor_hit:
		desc = "MISS"
		GraphicsPolish.spawn_sparks(self, pos, Color(0.6, 0.6, 0.65), 8)
	else:
		var local: Vector3 = board.to_local(pos)
		var r := Vector2(local.x, local.y).length()
		if r > DOUBLE_HI and r <= BOARD_R + 0.04:
			desc = "OFF THE WIRE"
		elif r <= DOUBLE_HI:
			var pts := 0
			var mult := ""
			if r <= BULL_IN:
				pts = 50
				desc = "BULLSEYE! 50"
			elif r <= BULL_OUT:
				pts = 25
				desc = "OUTER BULL 25"
			else:
				var deg := rad_to_deg(atan2(local.x, local.y))
				if deg < 0.0:
					deg += 360.0
				var sector: int = SECTOR_ORDER[int(round(deg / 18.0)) % 20]
				var base := sector
				if r >= TREBLE_LO and r <= TREBLE_HI:
					base *= 3
					mult = "TREBLE "
				elif r >= DOUBLE_LO and r <= DOUBLE_HI:
					base *= 2
					mult = "DOUBLE "
				pts = base
				desc = "%s%d = %d" % [mult, sector, pts]
			gained = pts
			score += pts
			GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.8, 0.3), 16)
			# Stick the dart in the board.
			if dart_mesh_fly != null and is_instance_valid(dart_mesh_fly):
				var stuck := dart_mesh_fly
				stuck.get_parent().remove_child(stuck)
				board.add_child(stuck)
				stuck.set_meta("stuck", true)
				stuck.position = board.to_local(pos)
				stuck.rotation_degrees = Vector3(90, 0, 0)
				dart_mesh_fly = null
		else:
			desc = "MISS"
			GraphicsPolish.spawn_sparks(self, pos, Color(0.6, 0.6, 0.65), 8)
	if dart_mesh_fly != null and is_instance_valid(dart_mesh_fly):
		dart_mesh_fly.queue_free()
		dart_mesh_fly = null
	darts_thrown += 1
	last_hit = desc
	_set_msg(desc, 1.6)
	if darts_thrown >= DARTS_PER_ROUND * ROUNDS:
		_game_over()
	else:
		round_num = darts_thrown / DARTS_PER_ROUND + 1
		held_dart.visible = true
		held_dart.position = Vector3(0.35, 1.15, 0.9)
		held_dart.rotation_degrees = Vector3(-70, 0, 0)
	_update_hud()


func _game_over() -> void:
	state = "gameover"
	if score > best:
		best = score
		ARUpgradeKit.save_anchor("ar-darts_best", global_transform)
	GraphicsPolish.spawn_confetti(self, BOARD_POS + Vector3(0, 0.5, 0.5), 70)
	_set_msg("GAME! Total %d  (Best %d) — R to restart" % [score, best], 60.0)
	_update_hud()


func _restart() -> void:
	darts_thrown = 0
	round_num = 1
	score = 0
	state = "playing"
	dart_flying = false
	aiming = false
	xr_grab = false
	for child in board.get_children():
		if child is MeshInstance3D and child != null and child.get_meta("stuck", false):
			child.queue_free()
	if dart_mesh_fly != null and is_instance_valid(dart_mesh_fly):
		dart_mesh_fly.queue_free()
		dart_mesh_fly = null
	held_dart.visible = true
	held_dart.position = Vector3(0.35, 1.15, 0.9)
	_set_msg("", 0.0)
	_update_hud()
