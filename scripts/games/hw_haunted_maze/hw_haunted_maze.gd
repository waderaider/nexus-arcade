## HwHauntedMaze - "Haunted Maze": a walk-through hedge maze on your floor.
## Collect 5 glowing tokens while a ghoul patrols the paths, then reach
## the exit. Touching the ghoul costs a life (3 lives). WASD/arrows to
## walk, hold the mouse button to steer, or pinch-hold in XR. 90 seconds.
extends Node3D

const ROUND_TIME := 90.0
const CELL := 0.42
const MAZE_N := 9
const PLAYER_SPEED := 1.5
const GHOUL_SPEED := 1.05
const ST_PLAY := 0
const ST_OVER := 1

# Hand-verified: every open cell connects to the start.
const MAP := [
	"#########",
	"#...#...#",
	"#.###.#.#",
	"#.#...#.#",
	"#.#.###.#",
	"#...#...#",
	"###.#.#.#",
	"#.....#.#",
	"#########",
]
const START_CELL := Vector2i(1, 1)
const EXIT_CELL := Vector2i(7, 7)
const TOKEN_CELLS := [Vector2i(1, 7), Vector2i(3, 4), Vector2i(7, 1), Vector2i(5, 6), Vector2i(2, 5)]
const PATROL := [Vector2i(1, 5), Vector2i(1, 7), Vector2i(3, 7), Vector2i(5, 7), Vector2i(5, 5)]

# v0.7.0 KayKit: real wall/prop models (CC0, KayKit Dungeon Remastered +
# Halloween Bits). KayKit wall is 4x4x1m; maze cells are 0.42m.
const MODEL_DIR := "res://assets/models/hw_haunted_maze/"
const WALL_MODEL_SCALE := Vector3(0.105, 0.1375, 0.42)
const LAMP_CELLS := [Vector2i(2, 2), Vector2i(4, 4), Vector2i(6, 6)]
const GRAVE_CELL := Vector2i(7, 6)

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var lives := 3
var tokens_left := 5
var elapsed := 0.0
var origin := Vector3(-CELL * 4.0, 0.0, -CELL * 4.0)
var player: Node3D = null
var player_glow: StandardMaterial3D = null
var ghoul: Node3D = null
var ghoul_idx := 0
var ghoul_dir := 1
var tokens: Array = [] # dicts: node, mat, cell, taken
var exit_ring: MeshInstance3D = null
var exit_mat: StandardMaterial3D = null
var move_target := Vector3.ZERO
var has_target := false
var invuln := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var token_player: AudioStreamPlayer = null
var hurt_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null

## RoomKit v0.7.0: cached room layout (world space; converted to local at use).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_floor()
	_build_hedges()
	_build_decor() # v0.7.0 KayKit: lantern posts + gravemarker (model only)
	_build_tokens()
	_build_exit()
	_build_player()
	_build_ghoul()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, "hw_haunted_maze_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 0.8, 0.0), 2.2, 40)
	token_player = _make_player(_make_tone(920.0, 0.12, 0.5))
	hurt_player = _make_player(_make_tone(130.0, 0.30, 0.6))
	win_player = _make_player(_make_tone(880.0, 0.45, 0.55))
	end_player = _make_player(_make_tone(330.0, 0.5, 0.5))
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
	camera.position = Vector3(0.0, 3.9, 2.3)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.4), Vector3.UP)
	camera.current = true


func _cell_center(cell: Vector2i) -> Vector3:
	return origin + Vector3(float(cell.y) * CELL, 0.0, float(cell.x) * CELL)


func _cell_of(pos: Vector3) -> Vector2i:
	var lx := int(floor((pos.x - origin.x) / CELL))
	var lz := int(floor((pos.z - origin.z) / CELL))
	return Vector2i(clampi(lz, 0, MAZE_N - 1), clampi(lx, 0, MAZE_N - 1))


func _is_wall(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAZE_N or cell.y < 0 or cell.y >= MAZE_N:
		return true
	return (MAP[cell.x] as String).substr(cell.y, 1) == "#"


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL * MAZE_N + 0.6, CELL * MAZE_N + 0.6)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.02, 0.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.10, 0.08, 0.06), 0.0, 0.95)
	add_child(floor_inst)


func _build_hedges() -> void:
	var hedge_mat := GraphicsPolish.pbr(Color(0.10, 0.35, 0.12), 0.0, 0.9)
	var trim_mat := GraphicsPolish.glow(Color(0.6, 0.2, 0.9), 0.7)
	for i in range(MAZE_N):
		for j in range(MAZE_N):
			if (MAP[i] as String).substr(j, 1) != "#":
				continue
			# v0.7.0 KayKit: real stone wall segment; null falls back to the hedge box.
			var wall_model := ModelLib.spawn(MODEL_DIR + "wall.glb", self, _cell_center(Vector2i(i, j)))
			if wall_model != null:
				wall_model.scale = WALL_MODEL_SCALE
			else:
				var h := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(CELL, 0.55, CELL)
				h.mesh = box
				h.position = _cell_center(Vector2i(i, j)) + Vector3(0.0, 0.275, 0.0)
				h.material_override = hedge_mat
				add_child(h)
			var trim := MeshInstance3D.new()
			var trim_box := BoxMesh.new()
			trim_box.size = Vector3(CELL * 0.96, 0.05, CELL * 0.96)
			trim.mesh = trim_box
			trim.position = _cell_center(Vector2i(i, j)) + Vector3(0.0, 0.57, 0.0)
			trim.material_override = trim_mat
			add_child(trim)


## v0.7.0 KayKit: lantern posts on solid wall cells + a gravemarker near
## the exit. Decor only: silently skipped when a model fails to load.
func _build_decor() -> void:
	for cell in LAMP_CELLS:
		var lamp := ModelLib.spawn(MODEL_DIR + "post_lantern.gltf", self, _cell_center(cell))
		if lamp != null:
			lamp.scale = Vector3.ONE * 0.35
			lamp.rotation.y = randf() * TAU
	var grave := ModelLib.spawn(MODEL_DIR + "gravemarker_A.gltf", self, _cell_center(GRAVE_CELL))
	if grave != null:
		grave.scale = Vector3.ONE * 0.5
		grave.rotation.y = randf() * TAU


func _build_tokens() -> void:
	for cell in TOKEN_CELLS:
		var node := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.18
		node.mesh = sphere
		node.position = _cell_center(cell) + Vector3(0.0, 0.35, 0.0)
		var mat := GraphicsPolish.glow(Color(1.0, 0.8, 0.2), 1.8)
		node.material_override = mat
		add_child(node)
		tokens.append({"node": node, "mat": mat, "cell": cell, "taken": false})


func _build_exit() -> void:
	exit_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.30
	exit_ring.mesh = torus
	exit_ring.rotation.x = PI * 0.5
	exit_ring.position = _cell_center(EXIT_CELL) + Vector3(0.0, 0.06, 0.0)
	exit_mat = GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 1.4)
	exit_ring.material_override = exit_mat
	add_child(exit_ring)
	var lbl := GraphicsPolish.make_label("EXIT", 48, Color(0.4, 1.0, 0.5))
	lbl.position = _cell_center(EXIT_CELL) + Vector3(0.0, 0.75, 0.0)
	add_child(lbl)


func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.30
	body.mesh = sphere
	body.scale = Vector3(1.0, 0.9, 1.0)
	body.position = Vector3(0.0, 0.16, 0.0)
	player_glow = GraphicsPolish.glow(Color(1.0, 0.5, 0.1), 1.5)
	body.material_override = player_glow
	player.add_child(body)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.02
	stem_mesh.bottom_radius = 0.03
	stem_mesh.height = 0.08
	stem.mesh = stem_mesh
	stem.position = Vector3(0.0, 0.32, 0.0)
	stem.material_override = GraphicsPolish.pbr(Color(0.25, 0.35, 0.12), 0.0, 0.9)
	player.add_child(stem)
	player.position = _cell_center(START_CELL)


func _build_ghoul() -> void:
	ghoul = Node3D.new()
	add_child(ghoul)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	body.mesh = sphere
	body.position = Vector3(0.0, 0.30, 0.0)
	body.material_override = GraphicsPolish.pbr(Color(0.12, 0.05, 0.16), 0.1, 0.7)
	ghoul.add_child(body)
	var eye_mat := GraphicsPolish.glow(Color(1.0, 0.1, 0.1), 2.2)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 0.36, 0.14)
		eye.material_override = eye_mat
		ghoul.add_child(eye)
	ghoul.position = _cell_center(PATROL[0])
	ghoul_idx = 0
	ghoul_dir = 1


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("HAUNTED MAZE", 44, Color(0.75, 0.5, 1.0))
	hud_label.position = Vector3(-2.9, 2.6, -0.8)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.9, -1.0)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	for tv in tokens:
		var t: Dictionary = tv
		if not bool(t["taken"]):
			GraphicsPolish.pulse_glow(t["mat"], 1.4, 0.8, elapsed * 2.0 + float(tv.hash()) * 0.001)
			(t["node"] as Node3D).rotation.y += delta * 2.0
	GraphicsPolish.pulse_glow(exit_mat, 1.0 if tokens_left > 0 else 1.6, 0.7, elapsed * 2.5)
	GraphicsPolish.pulse_glow(player_glow, 1.2, 0.5, elapsed * 3.0)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			pinch_hold += delta
			if pinch_hold >= 1.0:
				_reset_game()
				return
		else:
			pinch_hold = 0.0
		return
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_haunted_maze_main", global_transform)
	if invuln > 0.0:
		invuln -= delta
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over(false)
		return
	_update_player(delta)
	_update_ghoul(delta)
	_check_tokens()
	_check_ghoul_hit()
	_check_exit()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _update_player(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir.length_squared() > 0.0:
		has_target = false
		_move_player(dir.normalized() * PLAYER_SPEED * delta)
		return
	# Point-and-steer: hold mouse button, or pinch-hold in XR.
	var steering := false
	if ARUpgradeKit.is_xr_active():
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
			move_target = Vector3(pp.x, 0.0, pp.z)
			has_target = true
			steering = true
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		move_target = _mouse_floor_point()
		has_target = true
		steering = true
	if has_target:
		var to := move_target - player.position
		to.y = 0.0
		if to.length() < 0.12:
			has_target = false
		else:
			_move_player(to.normalized() * PLAYER_SPEED * delta)
	if steering:
		player.rotation.y = lerp_angle(player.rotation.y, atan2(dir.x, dir.z) if dir.length_squared() > 0.0 else player.rotation.y, 0.2)


func _move_player(step: Vector3) -> void:
	# Axis-separated collision against the maze grid.
	var p := player.position
	var nx := p + Vector3(step.x, 0.0, 0.0)
	if not _is_wall(_cell_of(nx + Vector3(signf(step.x) * 0.12, 0.0, 0.0))):
		p.x = nx.x
	var nz := p + Vector3(0.0, 0.0, step.z)
	if not _is_wall(_cell_of(nz + Vector3(0.0, 0.0, signf(step.z) * 0.12))):
		p.z = nz.z
	player.position = p


func _mouse_floor_point() -> Vector3:
	if camera == null:
		return player.position
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.001:
		return player.position
	var t := (0.0 - ro.y) / rd.y
	return ro + rd * t


func _update_ghoul(delta: float) -> void:
	var target := _cell_center(PATROL[ghoul_idx])
	var to := target - ghoul.position
	to.y = 0.0
	if to.length() < 0.06:
		ghoul_idx += ghoul_dir
		if ghoul_idx >= PATROL.size():
			ghoul_idx = PATROL.size() - 2
			ghoul_dir = -1
		elif ghoul_idx < 0:
			ghoul_idx = 1
			ghoul_dir = 1
		return
	ghoul.position += to.normalized() * GHOUL_SPEED * delta
	ghoul.rotation.y = lerp_angle(ghoul.rotation.y, atan2(to.x, to.z), clampf(8.0 * delta, 0.0, 1.0))
	ghoul.position.y = 0.05 + 0.05 * sin(elapsed * 3.0)


func _check_tokens() -> void:
	for tv in tokens:
		var t: Dictionary = tv
		if bool(t["taken"]):
			continue
		var node: Node3D = t["node"]
		var d := Vector2(node.position.x - player.position.x, node.position.z - player.position.z).length()
		if d < 0.30:
			t["taken"] = true
			node.visible = false
			tokens_left -= 1
			score += 20
			GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.8, 0.2), 24)
			_show_msg("+20 TOKEN!  %d left" % tokens_left, 1.2)
			if token_player != null:
				token_player.play()


func _check_ghoul_hit() -> void:
	if invuln > 0.0:
		return
	var d := Vector2(ghoul.position.x - player.position.x, ghoul.position.z - player.position.z).length()
	if d < 0.38:
		lives -= 1
		invuln = 1.5
		GraphicsPolish.spawn_sparks(self, player.position + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.2, 0.2), 26)
		player.position = _cell_center(START_CELL)
		has_target = false
		if hurt_player != null:
			hurt_player.play()
		if lives <= 0:
			_game_over(false)
		else:
			_show_msg("THE GHOUL GOT YOU!  Lives: %d" % lives, 1.5)


func _check_exit() -> void:
	var e := _cell_center(EXIT_CELL)
	var d := Vector2(e.x - player.position.x, e.z - player.position.z).length()
	if d < 0.35:
		if tokens_left > 0:
			return
		score += 100 + int(time_left) * 2
		_game_over(true)


func _game_over(won: bool) -> void:
	state = ST_OVER
	if won:
		_show_msg("ESCAPED!\nScore: %d   Time left: %ds\nPress R or pinch-hold to restart" % [score, int(time_left)], 600.0)
		GraphicsPolish.spawn_confetti(self, player.position + Vector3(0.0, 1.0, 0.0), 80)
		if win_player != null:
			win_player.play()
	else:
		var why := "OUT OF LIVES!" if lives <= 0 else "TIME UP!"
		_show_msg("%s\nScore: %d   Tokens left: %d\nPress R or pinch-hold to restart" % [why, score, tokens_left], 600.0)
		if end_player != null:
			end_player.play()
	ARUpgradeKit.save_anchor("hw_haunted_maze_main", global_transform)


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	lives = 3
	tokens_left = TOKEN_CELLS.size()
	pinch_hold = 0.0
	invuln = 0.0
	has_target = false
	player.position = _cell_center(START_CELL)
	ghoul.position = _cell_center(PATROL[0])
	ghoul_idx = 0
	ghoul_dir = 1
	for tv in tokens:
		var t: Dictionary = tv
		t["taken"] = false
		(t["node"] as Node3D).visible = true
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_haunted_maze_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "HAUNTED MAZE\nTime: %ds   Score: %d   Tokens: %d/5   Lives: %d" % [int(ceil(time_left)), score, TOKEN_CELLS.size() - tokens_left, maxi(lives, 0)]


func _show_msg(text: String, duration: float) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (token / hurt / win / lose).
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
	# v0.7.0 MORPH-C: doors become haunted dungeon gates (maze exits); windows show haunted eerie vistas.
	var _morph0_door := RoomKit.get_anchors("DOOR")
	for _mi in range(mini(_morph0_door.size(), 2)):
		RoomKit.morph(_morph0_door[_mi], "haunted")
	var _morph1_window := RoomKit.get_anchors("WINDOW")
	if not _morph1_window.is_empty():
		RoomKit.morph(_morph1_window[0], "haunted")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Center the maze on the real room floor (maze center is local origin).
	var rc := _room_bounds.get_center()
	global_position += Vector3(rc.x, 0.0, rc.y) - Vector3(global_position.x, 0.0, global_position.z)
	# Shrink the maze uniformly when the room is smaller than the maze grid.
	var fit := minf(_room_bounds.size.x, _room_bounds.size.y) / (CELL * float(MAZE_N) + 0.6)
	if fit < 1.0:
		var s := maxf(fit, 0.45)
		scale = Vector3(s, 1.0, s)
