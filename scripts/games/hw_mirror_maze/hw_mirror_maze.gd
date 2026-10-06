## HwMirrorMaze - "Mirror Maze" (NEXUS ARCADE Halloween set).
## A haunted mirror maze materializes in the room. Pinch (or click) to step
## forward in the facing direction; hold and drag sideways to turn 90 degrees.
## Reach the glowing green portal to escape. Timed run; R or a 1-second
## pinch-hold generates a fresh maze.
extends Node3D

const GRID := 7
const CELL := 0.6
const WALL_H := 0.95
const ST_PLAY := 0
const ST_OVER := 1
# N, E, S, W facing vectors.
const DIRS: Array = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]

var camera: Camera3D = null
var state := ST_PLAY
var cell_walls: Array = [] # GRID*GRID arrays of [N,E,S,W] bools
var walls_root: Node3D = null
var player_node: Node3D = null
var player_cell := Vector2i(0, 0)
var heading := 1
var moving := false
var move_t := 0.0
var move_from := Vector3.ZERO
var move_to := Vector3.ZERO
var won := false
var elapsed := 0.0
var steps := 0
var dragging := false
var drag_ref := Vector2.ZERO
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var hold_restart := 0.0
var step_player: AudioStreamPlayer = null
var bump_player: AudioStreamPlayer = null
var turn_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_floor()
	walls_root = Node3D.new()
	walls_root.name = "Walls"
	add_child(walls_root)
	_generate_maze()
	_build_walls()
	_build_portal()
	_build_player()
	_build_hud()
	step_player = _make_player(_make_tone(500.0, 0.07, 0.45))
	bump_player = _make_player(_make_tone(140.0, 0.18, 0.55))
	turn_player = _make_player(_make_tone(650.0, 0.06, 0.35))
	win_player = _make_player(_make_tone(880.0, 0.45, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_mirror_maze_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 2.5)


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
	camera.position = Vector3(0.0, 5.6, 3.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.2), Vector3.UP)
	camera.current = true


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_mirror_maze_main", global_transform)
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
	elapsed += delta
	# Pinch (or click) = step forward.
	if not moving and ARUpgradeKit.pinch_just_pressed(self):
		_try_step()
	# Hold + sideways drag = turn.
	var pinching := ARUpgradeKit.pinch_active(self)
	if pinching and not dragging:
		dragging = true
		drag_ref = _pointer_screen()
	elif pinching and dragging:
		var dx := _pointer_screen().x - drag_ref.x
		if dx > 70.0:
			heading = (heading + 1) % 4
			_face_player()
			turn_player.play()
			drag_ref = _pointer_screen()
		elif dx < -70.0:
			heading = (heading + 3) % 4
			_face_player()
			turn_player.play()
			drag_ref = _pointer_screen()
	elif not pinching:
		dragging = false
	# Step animation.
	if moving:
		move_t += delta / 0.28
		var k := minf(1.0, move_t)
		player_node.position = move_from.lerp(move_to, k * k * (3.0 - 2.0 * k))
		if move_t >= 1.0:
			moving = false
			player_node.position = move_to
			if won:
				_win()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()


func _pointer_screen() -> Vector2:
	var wp := ARUpgradeKit.pointer_position(self)
	if camera != null:
		return camera.unproject_position(wp)
	return get_viewport().get_mouse_position()


# ------------------------------------------------------------------- maze --

func _generate_maze() -> void:
	cell_walls.clear()
	for i in range(GRID * GRID):
		cell_walls.append([true, true, true, true])
	var visited: Array = []
	for i in range(GRID * GRID):
		visited.append(false)
	var deltas := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var stack: Array = [Vector2i(0, 0)]
	visited[0] = true
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var nbs: Array = []
		for d_i in range(4):
			var nb: Vector2i = cur + deltas[d_i]
			if nb.x >= 0 and nb.x < GRID and nb.y >= 0 and nb.y < GRID and not visited[nb.y * GRID + nb.x]:
				nbs.append([nb, d_i])
		if nbs.is_empty():
			stack.pop_back()
		else:
			var pick: Array = nbs[randi_range(0, nbs.size() - 1)]
			var nb2: Vector2i = pick[0]
			var d2: int = pick[1]
			var wcur: Array = cell_walls[cur.y * GRID + cur.x]
			var wnb: Array = cell_walls[nb2.y * GRID + nb2.x]
			wcur[d2] = false
			wnb[(d2 + 2) % 4] = false
			visited[nb2.y * GRID + nb2.x] = true
			stack.append(nb2)


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) - 3.0) * CELL, 0.0, (float(c.y) - 3.0) * CELL)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.4, 5.4)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.01, 0.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.08, 0.09, 0.13), 0.0, 0.9)
	add_child(floor_inst)


func _build_walls() -> void:
	var mirror := GraphicsPolish.pbr(Color(0.62, 0.78, 0.95), 0.9, 0.12)
	var edge := GraphicsPolish.glow(Color(0.35, 0.85, 1.0), 1.3)
	for y in range(GRID):
		for x in range(GRID):
			var w: Array = cell_walls[y * GRID + x]
			var c := Vector3((float(x) - 3.0) * CELL, 0.0, (float(y) - 3.0) * CELL)
			if bool(w[0]):
				_add_wall(c + Vector3(0, 0, -CELL * 0.5), true, mirror, edge)
			if bool(w[3]):
				_add_wall(c + Vector3(-CELL * 0.5, 0, 0), false, mirror, edge)
			if y == GRID - 1 and bool(w[2]):
				_add_wall(c + Vector3(0, 0, CELL * 0.5), true, mirror, edge)
			if x == GRID - 1 and bool(w[1]):
				_add_wall(c + Vector3(CELL * 0.5, 0, 0), false, mirror, edge)


func _add_wall(pos: Vector3, along_x: bool, mirror: StandardMaterial3D, edge: StandardMaterial3D) -> void:
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	if along_x:
		box.size = Vector3(CELL + 0.07, WALL_H, 0.07)
	else:
		box.size = Vector3(0.07, WALL_H, CELL + 0.07)
	wall.mesh = box
	wall.position = Vector3(pos.x, WALL_H * 0.5, pos.z)
	wall.material_override = mirror
	walls_root.add_child(wall)
	var strip := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	if along_x:
		sbox.size = Vector3(CELL + 0.07, 0.035, 0.09)
	else:
		sbox.size = Vector3(0.09, 0.035, CELL + 0.07)
	strip.mesh = sbox
	strip.position = Vector3(pos.x, WALL_H + 0.017, pos.z)
	strip.material_override = edge
	walls_root.add_child(strip)


func _build_portal() -> void:
	var exit_c := _cell_pos(Vector2i(GRID - 1, GRID - 1))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.30
	ring.mesh = torus
	ring.position = exit_c + Vector3(0.0, 0.55, 0.0)
	ring.material_override = GraphicsPolish.glow(Color(0.25, 1.0, 0.45), 1.8)
	walls_root.add_child(ring)
	GraphicsPolish.make_point_light(walls_root, exit_c + Vector3(0, 0.8, 0), Color(0.3, 1.0, 0.5), 1.2, 3.0)
	# Start pad.
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.20
	cyl.bottom_radius = 0.20
	cyl.height = 0.02
	pad.mesh = cyl
	pad.position = _cell_pos(Vector2i(0, 0)) + Vector3(0.0, 0.01, 0.0)
	pad.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.2)
	walls_root.add_child(pad)


func _build_player() -> void:
	player_node = Node3D.new()
	player_node.name = "Player"
	add_child(player_node)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.12
	cap.height = 0.38
	body.mesh = cap
	body.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.10), 1.1)
	player_node.add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.16
	nose.mesh = cone
	nose.rotation_degrees.x = -90.0
	nose.position = Vector3(0.0, 0.02, -0.20)
	nose.material_override = GraphicsPolish.glow(Color(1.0, 0.85, 0.30), 1.4)
	player_node.add_child(nose)
	player_node.position = _cell_pos(Vector2i(0, 0)) + Vector3(0.0, 0.25, 0.0)
	_face_player()


func _face_player() -> void:
	var dir: Vector3 = DIRS[heading]
	player_node.rotation.y = atan2(-dir.x, -dir.z)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("MIRROR MAZE", 40, Color(0.65, 0.9, 1.0))
	hud_label.position = Vector3(-3.4, 3.4, 1.2)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.6, 0.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "MIRROR MAZE\nTime: %ds   Steps: %d\nPinch / click: step forward | Hold + drag: turn\nR: new maze" % [int(elapsed), steps]


func _show_msg(text: String, duration: float = 1.0) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


# ------------------------------------------------------------------ play ---

func _try_step() -> void:
	if moving or state != ST_PLAY:
		return
	var dir: Vector3 = DIRS[heading]
	var w: Array = cell_walls[player_cell.y * GRID + player_cell.x]
	if bool(w[heading]):
		bump_player.play()
		_show_msg("Thunk! Dead end.", 0.7)
		return
	player_cell += Vector2i(int(dir.x), int(dir.z))
	move_from = player_node.position
	move_to = _cell_pos(player_cell) + Vector3(0.0, 0.25, 0.0)
	move_t = 0.0
	moving = true
	steps += 1
	step_player.play()
	if player_cell == Vector2i(GRID - 1, GRID - 1):
		won = true


func _win() -> void:
	state = ST_OVER
	won = false
	win_player.play()
	GraphicsPolish.spawn_confetti(self, player_node.position + Vector3(0, 0.8, 0), 70)
	_show_msg("ESCAPED!\nTime: %ds   Steps: %d\nHold pinch 1s or press R for a new maze" % [int(elapsed), steps], 600.0)
	ARUpgradeKit.save_anchor("hw_mirror_maze_main", global_transform)


func _reset_game() -> void:
	for child in walls_root.get_children():
		child.queue_free()
	if is_instance_valid(player_node):
		player_node.queue_free()
	_generate_maze()
	_build_walls()
	_build_portal()
	_build_player()
	player_cell = Vector2i(0, 0)
	heading = 1
	moving = false
	won = false
	elapsed = 0.0
	steps = 0
	hold_restart = 0.0
	state = ST_PLAY
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_mirror_maze_main", global_transform)


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
