## HoloChessGame.gd - Room-scale holographic chess: player (white/cyan hologram)
## vs AI (black/orange hologram). Click one of your pieces to select it (legal
## moves show as green dots), then click a destination to move. The AI replies
## with minimax depth 2 + material evaluation. Capturing the king wins.
extends Node3D
class_name HoloChessGame

const TILE := 0.35
const BOARD_HALF := 1.4
const BOARD_CENTER := Vector3(0.0, 0.0, 1.7)
const TILE_TOP_Y := 0.045
const PIECE_VALUES := {"P": 1.0, "N": 3.0, "B": 3.0, "R": 5.0, "Q": 9.0, "K": 1000.0}
const BACK_RANK := ["R", "N", "B", "Q", "K", "B", "N", "R"]
const INF_VAL := 1e18

var grid: Array = [] # 8x8 of Dictionary {type,color,node} or {}
var current_turn := 0 # 0 = player (white), 1 = AI (black)
var selected := Vector2i(-1, -1)
var game_over := false
var result_text := ""

var _cam: Camera3D
var _mat_white: StandardMaterial3D
var _mat_black: StandardMaterial3D
var _sel_box: MeshInstance3D
var _hint_dots: Array = []
var _captured_by_player: Array = [] # black pieces the player took
var _captured_by_ai: Array = [] # white pieces the AI took

var _turn_label: Label3D
var _cap_label: Label3D
var _help_label: Label3D

var _ai_pending := false
var _ai_timer := 0.0

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _board_root: Node3D = null # container for board + pieces (room-placeable)


func _ready() -> void:
	_ensure_camera()
	_build_light_and_floor()
	_build_materials()
	_board_root = Node3D.new()
	_board_root.name = "Board"
	add_child(_board_root)
	_build_board()
	_build_overlays()
	_build_labels()
	GraphicsPolish.spawn_ambient_motes(self, BOARD_CENTER + Vector3(0, 0.6, 0), 2.0, 30)
	ARUpgradeKit.apply_anchor(self, "holo-chess_main")
	_reset_game()
	_apply_room_layout()


## Tile-top plane height in world space (follows the room-placed board).
func _tile_top_world() -> float:
	if _board_root == null:
		return TILE_TOP_Y
	return _board_root.global_position.y + TILE_TOP_Y * _board_root.scale.y


## v0.7.0: center the board on the largest real table, scaled to fit it,
## with the turn label floating above. Guarded; fallback keeps the floor board.
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): tables -> enchanted arcane war tables under the board
	_morph_anchors("TABLE", "arcane", 1)
	var best := {}
	var best_a := 0.0
	for t_v in _room_tables:
		var t: Dictionary = t_v
		var a: float = (t["size"] as Vector3).x * (t["size"] as Vector3).z
		if a > best_a:
			best_a = a
			best = t
	if best.is_empty() or _board_root == null:
		return
	var tp: Vector3 = best["position"]
	var ts: Vector3 = best["size"]
	var s: float = clampf(minf(ts.x, ts.z) * 0.92 / 2.8, 0.3, 1.0)
	var top_y: float = tp.y + ts.y * 0.5
	_board_root.scale = Vector3.ONE * s
	_board_root.position = to_local(Vector3(tp.x, top_y, tp.z)) - Vector3(BOARD_CENTER.x, 0.05, BOARD_CENTER.z) * s
	if _turn_label != null:
		_turn_label.position = to_local(Vector3(tp.x, top_y + 1.25, tp.z))


func _process(delta: float) -> void:
	if _ai_pending:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_pending = false
			_do_ai_move()
	if game_over and Input.is_key_pressed(KEY_R):
		_reset_game()
	# XR hand selection: right-hand pinch picks up / drops pieces
	# (mouse clicks still work through _unhandled_input).
	if ARUpgradeKit.is_xr_active() and _pinch_active():
		_handle_pinch_select()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R and game_over:
			_reset_game()


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, with mouse fallback via the kit.
	return ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)


func _handle_pinch_select() -> void:
	if _cam == null or game_over:
		return
	if current_turn != 0 or _ai_pending:
		return
	var ray := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if absf(dir.y) < 0.0001:
		return
	var t := (_tile_top_world() - origin.y) / dir.y
	if t < 0.0:
		return
	var sq := _world_to_square(origin + dir * t)
	if sq.x < 0:
		return
	_on_square(sq)


# ---------------------------------------------------------------- setup ---

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 2.7, -1.0)
	add_child(_cam)
	_cam.look_at(Vector3(0.0, 0.0, 1.5), Vector3.UP)


func _build_light_and_floor() -> void:
	var has_light := false
	for c in get_children():
		if c is DirectionalLight3D:
			has_light = true
			break
	if not has_light:
		GraphicsPolish.make_light_rig(self, 1.1)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	floor_mi.mesh = plane
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.13, 0.14, 0.18), "matte")
	add_child(floor_mi)


func _holo_material(color: Color) -> StandardMaterial3D:
	var mat := GraphicsPolish.glow(color, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _build_materials() -> void:
	_mat_white = _holo_material(Color(0.65, 0.92, 1.0, 0.72))
	_mat_black = _holo_material(Color(1.0, 0.55, 0.15, 0.72))


func _square_world(f: int, r: int) -> Vector3:
	return Vector3((f - 3.5) * TILE + BOARD_CENTER.x, 0.05,
			(r - 3.5) * TILE + BOARD_CENTER.z)


func _build_board() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(3.0, 0.04, 3.0)
	base.mesh = base_mesh
	base.position = Vector3(BOARD_CENTER.x, 0.02, BOARD_CENTER.z)
	var base_mat := GraphicsPolish.pbr(Color(0.05, 0.07, 0.1), 0.6, 0.4)
	base.material_override = base_mat
	_board_root.add_child(base)
	var cyan_mat := GraphicsPolish.glow(Color(0.16, 0.55, 0.65), 0.9)
	var dark_mat := GraphicsPolish.pbr_preset(Color(0.07, 0.09, 0.13), "matte")
	for f in range(8):
		for r in range(8):
			var tile := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.34, 0.02, 0.34)
			tile.mesh = tm
			tile.position = Vector3((f - 3.5) * TILE + BOARD_CENTER.x, TILE_TOP_Y - 0.01,
					(r - 3.5) * TILE + BOARD_CENTER.z)
			tile.material_override = cyan_mat if (f + r) % 2 == 0 else dark_mat
			_board_root.add_child(tile)


func _build_overlays() -> void:
	var sb := BoxMesh.new()
	sb.size = Vector3(0.36, 0.012, 0.36)
	_sel_box = MeshInstance3D.new()
	_sel_box.mesh = sb
	var smat := GraphicsPolish.glow(Color(1.0, 0.95, 0.2), 1.2)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sel_box.material_override = smat
	_sel_box.visible = false
	_board_root.add_child(_sel_box)
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.03
	dot_mesh.height = 0.06
	var dmat := GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 1.4)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(27):
		var dot := MeshInstance3D.new()
		dot.mesh = dot_mesh
		dot.material_override = dmat
		dot.visible = false
		_board_root.add_child(dot)
		_hint_dots.append(dot)


func _make_label(text: String, pos: Vector3, font_size: int = 64) -> Label3D:
	var label := GraphicsPolish.make_label(text, font_size)
	label.pixel_size = 0.008
	label.no_depth_test = true
	label.position = pos
	add_child(label)
	return label


func _build_labels() -> void:
	_turn_label = _make_label("", Vector3(0.0, 1.25, 3.55), 72)
	_cap_label = _make_label("", Vector3(2.9, 1.5, 1.7), 48)
	_help_label = _make_label("Holo Chess - click a cyan piece, then a green dot to move.\nR restarts after game over. You are White, AI is Orange.",
			Vector3(-2.9, 1.5, 1.7), 40)


# ---------------------------------------------------------------- pieces ---

func _prim(mesh: Mesh, mat: Material, pos: Vector3, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	return mi


func _make_piece_node(ptype: String, color: int) -> Node3D:
	var root := Node3D.new()
	var mat: StandardMaterial3D = _mat_white if color == 0 else _mat_black
	var face := 0.0 if color == 0 else PI
	match ptype:
		"P":
			var b := CylinderMesh.new()
			b.top_radius = 0.055
			b.bottom_radius = 0.065
			b.height = 0.07
			root.add_child(_prim(b, mat, Vector3(0, 0.075, 0)))
			var s := SphereMesh.new()
			s.radius = 0.06
			s.height = 0.12
			root.add_child(_prim(s, mat, Vector3(0, 0.17, 0)))
		"R":
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.18, 0.12)
			root.add_child(_prim(b, mat, Vector3(0, 0.14, 0)))
			var t := BoxMesh.new()
			t.size = Vector3(0.155, 0.045, 0.155)
			root.add_child(_prim(t, mat, Vector3(0, 0.25, 0)))
		"N":
			var b := BoxMesh.new()
			b.size = Vector3(0.1, 0.2, 0.1)
			root.add_child(_prim(b, mat, Vector3(0, 0.15, 0), 0.6))
			var h := BoxMesh.new()
			h.size = Vector3(0.1, 0.1, 0.18)
			root.add_child(_prim(h, mat, Vector3(0, 0.28, 0.03), 0.6))
		"B":
			var c := CylinderMesh.new()
			c.top_radius = 0.012
			c.bottom_radius = 0.07
			c.height = 0.24
			root.add_child(_prim(c, mat, Vector3(0, 0.17, 0)))
			var s := SphereMesh.new()
			s.radius = 0.035
			s.height = 0.07
			root.add_child(_prim(s, mat, Vector3(0, 0.32, 0)))
		"Q":
			var b := CylinderMesh.new()
			b.top_radius = 0.05
			b.bottom_radius = 0.065
			b.height = 0.2
			root.add_child(_prim(b, mat, Vector3(0, 0.15, 0)))
			var s := SphereMesh.new()
			s.radius = 0.07
			s.height = 0.14
			root.add_child(_prim(s, mat, Vector3(0, 0.3, 0)))
		"K":
			var b := CylinderMesh.new()
			b.top_radius = 0.05
			b.bottom_radius = 0.065
			b.height = 0.28
			root.add_child(_prim(b, mat, Vector3(0, 0.19, 0)))
			var s := SphereMesh.new()
			s.radius = 0.085
			s.height = 0.17
			root.add_child(_prim(s, mat, Vector3(0, 0.4, 0)))
	root.rotation.y = face
	return root


func _place_piece(ptype: String, color: int, f: int, r: int) -> void:
	var node := _make_piece_node(ptype, color)
	node.position = _square_world(f, r)
	_board_root.add_child(node)
	grid[f][r] = {"type": ptype, "color": color, "node": node}


func _setup_pieces() -> void:
	for f in range(8):
		_place_piece(BACK_RANK[f], 0, f, 0)
		_place_piece("P", 0, f, 1)
		_place_piece("P", 1, f, 6)
		_place_piece(BACK_RANK[f], 1, f, 7)


# ---------------------------------------------------------------- input ---

func _world_to_square(p: Vector3) -> Vector2i:
	var lp: Vector3 = _board_root.to_local(p) if _board_root != null else p
	var f := int(floor((lp.x - BOARD_CENTER.x + BOARD_HALF) / TILE))
	var r := int(floor((lp.z - BOARD_CENTER.z + BOARD_HALF) / TILE))
	if f < 0 or f > 7 or r < 0 or r > 7:
		return Vector2i(-1, -1)
	return Vector2i(f, r)


func _handle_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	if game_over:
		_reset_game()
		return
	if current_turn != 0 or _ai_pending:
		return
	var origin := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := (_tile_top_world() - origin.y) / dir.y
	if t < 0.0:
		return
	var sq := _world_to_square(origin + dir * t)
	if sq.x < 0:
		return
	_on_square(sq)


func _on_square(sq: Vector2i) -> void:
	var cell: Dictionary = grid[sq.x][sq.y]
	if selected.x < 0:
		if not cell.is_empty() and int(cell["color"]) == 0:
			_select(sq)
		return
	if sq == selected:
		_clear_selection()
		return
	var moves: Array = _piece_moves(grid, selected.x, selected.y, grid[selected.x][selected.y])
	if sq in moves:
		_do_player_move(selected, sq)
		return
	if not cell.is_empty() and int(cell["color"]) == 0:
		_select(sq)
	else:
		_clear_selection()


func _select(sq: Vector2i) -> void:
	selected = sq
	_sel_box.visible = true
	_sel_box.position = _square_world(sq.x, sq.y) + Vector3(0, 0.02, 0)
	var moves: Array = _piece_moves(grid, sq.x, sq.y, grid[sq.x][sq.y])
	for i in range(_hint_dots.size()):
		var dot := _hint_dots[i] as MeshInstance3D
		if i < moves.size():
			var m: Vector2i = moves[i]
			dot.visible = true
			dot.position = _square_world(m.x, m.y) + Vector3(0, 0.04, 0)
		else:
			dot.visible = false
	_play_tone(520.0, 0.07)


func _clear_selection() -> void:
	selected = Vector2i(-1, -1)
	_sel_box.visible = false
	for dot in _hint_dots:
		(dot as MeshInstance3D).visible = false


# ---------------------------------------------------------------- moves ---

func _in_board(v: int) -> bool:
	return v >= 0 and v < 8


func _is_enemy(g: Array, f: int, r: int, color: int) -> bool:
	var c: Dictionary = g[f][r]
	return not c.is_empty() and int(c["color"]) != color


func _is_empty_cell(g: Array, f: int, r: int) -> bool:
	return (g[f][r] as Dictionary).is_empty()


func _slide(g: Array, f: int, r: int, color: int, dirs: Array) -> Array:
	var moves: Array = []
	for d in dirs:
		var df: int = d[0]
		var dr: int = d[1]
		var nf := f + df
		var nr := r + dr
		while _in_board(nf) and _in_board(nr):
			if _is_empty_cell(g, nf, nr):
				moves.append(Vector2i(nf, nr))
			elif _is_enemy(g, nf, nr, color):
				moves.append(Vector2i(nf, nr))
				break
			else:
				break
			nf += df
			nr += dr
	return moves


func _piece_moves(g: Array, f: int, r: int, p: Dictionary) -> Array:
	var moves: Array = []
	if p.is_empty():
		return moves
	var t: String = p["type"]
	var color: int = int(p["color"])
	var fwd := 1 if color == 0 else -1
	match t:
		"P":
			var nr := r + fwd
			if _in_board(nr) and _is_empty_cell(g, f, nr):
				moves.append(Vector2i(f, nr))
			for df in [-1, 1]:
				var nf: int = f + df
				if _in_board(nf) and _in_board(nr) and _is_enemy(g, nf, nr, color):
					moves.append(Vector2i(nf, nr))
		"N":
			for o in [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]:
				var nf: int = f + o[0]
				var nr: int = r + o[1]
				if _in_board(nf) and _in_board(nr):
					if _is_empty_cell(g, nf, nr) or _is_enemy(g, nf, nr, color):
						moves.append(Vector2i(nf, nr))
		"B":
			moves.append_array(_slide(g, f, r, color, [[1, 1], [1, -1], [-1, 1], [-1, -1]]))
		"R":
			moves.append_array(_slide(g, f, r, color, [[1, 0], [-1, 0], [0, 1], [0, -1]]))
		"Q":
			moves.append_array(_slide(g, f, r, color,
					[[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]))
		"K":
			for df in [-1, 0, 1]:
				for dr in [-1, 0, 1]:
					if df == 0 and dr == 0:
						continue
					var nf: int = f + df
					var nr: int = r + dr
					if _in_board(nf) and _in_board(nr):
						if _is_empty_cell(g, nf, nr) or _is_enemy(g, nf, nr, color):
							moves.append(Vector2i(nf, nr))
	return moves


func _gen_moves_for(g: Array, color: int) -> Array:
	var moves: Array = []
	for f in range(8):
		for r in range(8):
			var p: Dictionary = g[f][r]
			if p.is_empty() or int(p["color"]) != color:
				continue
			for to in _piece_moves(g, f, r, p):
				moves.append([Vector2i(f, r), to])
	return moves


func _copy_grid(g: Array) -> Array:
	var c: Array = []
	for f in range(8):
		c.append(g[f].duplicate())
	return c


func _sim_apply(g: Array, from_sq: Vector2i, to_sq: Vector2i) -> void:
	g[to_sq.x][to_sq.y] = g[from_sq.x][from_sq.y]
	g[from_sq.x][from_sq.y] = {}


func _evaluate(g: Array) -> float:
	# From Black's (AI) perspective: positive favors Black.
	var score := 0.0
	for f in range(8):
		for r in range(8):
			var p: Dictionary = g[f][r]
			if p.is_empty():
				continue
			var v: float = PIECE_VALUES[p["type"]]
			if int(p["color"]) == 1:
				score += v
			else:
				score -= v
	return score


func _min_white_reply(g: Array) -> float:
	var moves := _gen_moves_for(g, 0)
	if moves.is_empty():
		return _evaluate(g)
	var worst := INF_VAL
	for m in moves:
		var sim := _copy_grid(g)
		_sim_apply(sim, m[0], m[1])
		var v := _evaluate(sim)
		if v < worst:
			worst = v
	return worst


func _ai_best_move() -> Array:
	var moves := _gen_moves_for(grid, 1)
	if moves.is_empty():
		return []
	moves.shuffle()
	var best: Array = moves[0]
	var best_val := -INF_VAL
	for m in moves:
		var sim := _copy_grid(grid)
		_sim_apply(sim, m[0], m[1])
		var val := _min_white_reply(sim)
		if val > best_val:
			best_val = val
			best = m
	return best


func _king_alive(color: int) -> bool:
	for f in range(8):
		for r in range(8):
			var p: Dictionary = grid[f][r]
			if not p.is_empty() and p["type"] == "K" and int(p["color"]) == color:
				return true
	return false


func _apply_move(from_sq: Vector2i, to_sq: Vector2i) -> Dictionary:
	var mover: Dictionary = grid[from_sq.x][from_sq.y]
	var victim: Dictionary = grid[to_sq.x][to_sq.y]
	if not victim.is_empty():
		if int(mover["color"]) == 0:
			_captured_by_player.append(victim)
		else:
			_captured_by_ai.append(victim)
		(victim["node"] as Node).queue_free()
		# Capture burst in the capturer's hologram color.
		var burst := Color(0.4, 0.9, 1.0) if int(mover["color"]) == 0 else Color(1.0, 0.55, 0.2)
		GraphicsPolish.spawn_sparks(_board_root, _square_world(to_sq.x, to_sq.y) + Vector3(0, 0.12, 0), burst, 18)
	grid[to_sq.x][to_sq.y] = mover
	grid[from_sq.x][from_sq.y] = {}
	var node := mover["node"] as Node3D
	var tw := node.create_tween()
	tw.tween_property(node, "position", _square_world(to_sq.x, to_sq.y), 0.22)
	_refresh_labels()
	return victim


func _do_player_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_apply_move(from_sq, to_sq)
	_play_tone(660.0, 0.1)
	_clear_selection()
	if not _king_alive(1):
		game_over = true
		result_text = "YOU WIN! Click or press R for a rematch."
	else:
		current_turn = 1
		_ai_pending = true
		_ai_timer = 0.7
	_refresh_labels()


func _do_ai_move() -> void:
	if game_over:
		return
	var m := _ai_best_move()
	if m.is_empty():
		game_over = true
		result_text = "Draw - AI has no moves. Click or press R to replay."
	else:
		_apply_move(m[0], m[1])
		_play_tone(440.0, 0.1)
		if not _king_alive(0):
			game_over = true
			result_text = "AI WINS. Click or press R for a rematch."
	current_turn = 0
	_refresh_labels()


# ---------------------------------------------------------------- state ---

func _reset_game() -> void:
	if not grid.is_empty():
		for f in range(8):
			for r in range(mini(8, (grid[f] as Array).size())):
				var p: Dictionary = (grid[f] as Array)[r]
				if not p.is_empty():
					(p["node"] as Node).queue_free()
		grid.clear()
	for f in range(8):
		var col: Array = []
		for r in range(8):
			col.append({})
		grid.append(col)
	_captured_by_player.clear()
	_captured_by_ai.clear()
	selected = Vector2i(-1, -1)
	current_turn = 0
	game_over = false
	result_text = ""
	_ai_pending = false
	_clear_selection()
	ARUpgradeKit.save_anchor("holo-chess_main", global_transform)
	_setup_pieces()
	_refresh_labels()


func _refresh_labels() -> void:
	if game_over:
		_turn_label.text = result_text
	else:
		_turn_label.text = "Your turn (White)" if current_turn == 0 else "AI thinking..."
	var score := _evaluate(grid)
	_cap_label.text = "You captured: %d\nAI captured: %d\nMaterial: %+d" % [
			_captured_by_player.size(), _captured_by_ai.size(), int(-score)]


func _play_tone(freq: float, dur: float = 0.1) -> void:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var env := 1.0 - float(i) / float(n)
		data[i] = clampi(int(128.0 + 110.0 * env * sin(TAU * freq * t)), 0, 255)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	var player := AudioStreamPlayer3D.new()
	add_child(player)
	player.stream = wav
	player.play()
	player.finished.connect(player.queue_free)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
