class_name StarforgeGame
extends Node3D
## Starforge Command - tabletop space RTS.
## Left-click / tap the board to spawn a Fighter (25 resources);
## right-click spawns a Cruiser (50 resources). Units auto-fight.
## Destroy the enemy base to win; lose your base and it's over.
## Ported from Unity StarforgeBootstrap / FleetController / AIAdmiral.

const BOARD_W := 1.2
const BOARD_D := 0.8
const BOARD_POS := Vector3(0.0, 1.0, -1.3)
const HOVER := 0.035
const FIGHTER_COST := 25
const CRUISER_COST := 50
const PLAYER_CAP := 8
const RESOURCE_TICK := 2.0
const AI_DIFFICULTY := 0.5

var player_units: Array[StarforgeUnit] = []
var enemy_units: Array[StarforgeUnit] = []
var player_base: StarforgeBuilding = null
var enemy_base: StarforgeBuilding = null
var player_resources := 50.0
var is_over := false

var _board: Node3D = null
var _ai_resources := 40.0
var _ai_build_timer := 5.0
var _ai_wave_timer := 18.0
var _think_timer := 0.0
var _stats_label: Label3D = null
var _banner_label: Label3D = null
var _rng := RandomNumberGenerator.new()
var _anchor_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	_add_polish_light_rig()
	_build_board()
	ARUpgradeKit.apply_anchor(_board, "starforge_main")
	_build_bases()
	_build_shipyard_marker()
	_build_ui()
	GraphicsPolish.spawn_ambient_motes(self, BOARD_POS + Vector3(0, 0.3, 0), 1.2, 40)
	# Opening player fleet.
	for i in 3:
		spawn_unit(StarforgeUnit.Side.PLAYER, StarforgeUnit.UnitType.FIGHTER,
			board_to_world(0.16 + i * 0.05, 0.35 + i * 0.12), true)


func _add_polish_light_rig() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


# ---------------------------------------------------------------- board ---

func _build_board() -> void:
	_board = Node3D.new()
	_board.name = "Board"
	_board.position = BOARD_POS
	add_child(_board)

	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BOARD_W, 0.02, BOARD_D)
	slab.mesh = box
	var smat := GraphicsPolish.pbr(Color(0.05, 0.07, 0.12), 0.3, 0.5)
	slab.material_override = smat
	slab.position = Vector3(0, -0.011, 0)
	_board.add_child(slab)

	var rim := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(BOARD_W + 0.03, 0.012, BOARD_D + 0.03)
	rim.mesh = rbox
	rim.material_override = _emissive_mat(Color(0.1, 0.5, 0.8), 0.8)
	rim.position = Vector3(0, -0.014, 0)
	_board.add_child(rim)

	var gmat := _emissive_mat(Color(0.2, 0.8, 1.0), 0.6)
	var cols := 12
	var rows := 8
	for i in cols + 1:
		var x := -BOARD_W / 2.0 + BOARD_W * i / cols
		_add_grid_bar(gmat, Vector3(0.004, 0.002, BOARD_D), Vector3(x, 0.002, 0))
	for j in rows + 1:
		var z := -BOARD_D / 2.0 + BOARD_D * j / rows
		_add_grid_bar(gmat, Vector3(BOARD_W, 0.002, 0.004), Vector3(0, 0.002, z))


func _add_grid_bar(mat: Material, size: Vector3, pos: Vector3) -> void:
	var bar := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	bar.mesh = b
	bar.material_override = mat
	bar.position = pos
	_board.add_child(bar)


func _emissive_mat(c: Color, energy: float) -> StandardMaterial3D:
	return GraphicsPolish.glow(c, energy)


func _board_local(u: float, v: float) -> Vector3:
	return Vector3(lerpf(-BOARD_W / 2.0, BOARD_W / 2.0, u), 0.0,
		lerpf(-BOARD_D / 2.0, BOARD_D / 2.0, v))


## Board-space lookup: u, v in 0..1 across width/depth, at hover height.
func board_to_world(u: float, v: float) -> Vector3:
	return _board.to_global(_board_local(u, v) + Vector3(0, HOVER, 0))


## Project an arbitrary world point onto the board surface, clamped.
func project_to_board(world: Vector3) -> Vector3:
	var local := _board.to_local(world)
	local.x = clampf(local.x, -BOARD_W / 2.0, BOARD_W / 2.0)
	local.z = clampf(local.z, -BOARD_D / 2.0, BOARD_D / 2.0)
	local.y = HOVER
	return _board.to_global(local)


func hover_height() -> float:
	return _board.global_position.y + HOVER


func board_point_from_screen(screen_pos: Vector2) -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return [false, Vector3.ZERO]
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return [false, Vector3.ZERO]
	var t := (_board.global_position.y - from.y) / dir.y
	if t < 0.0:
		return [false, Vector3.ZERO]
	var hit := from + dir * t
	var local := _board.to_local(hit)
	if absf(local.x) > BOARD_W / 2.0 + 0.05 or absf(local.z) > BOARD_D / 2.0 + 0.05:
		return [false, Vector3.ZERO]
	return [true, hit]


# ---------------------------------------------------------------- setup ---

func _build_bases() -> void:
	player_base = StarforgeBuilding.new()
	_board.add_child(player_base)
	player_base.setup(StarforgeUnit.Side.PLAYER, self)
	player_base.position = _board_local(0.08, 0.5)
	player_base.destroyed.connect(_on_base_destroyed)

	enemy_base = StarforgeBuilding.new()
	_board.add_child(enemy_base)
	enemy_base.setup(StarforgeUnit.Side.ENEMY, self)
	enemy_base.position = _board_local(0.92, 0.5)
	enemy_base.destroyed.connect(_on_base_destroyed)


func _build_shipyard_marker() -> void:
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 0.03
	pad.mesh = cyl
	pad.material_override = _emissive_mat(Color(0.2, 0.9, 0.5), 1.0)
	pad.position = _board_local(0.2, 0.68) + Vector3(0, 0.015, 0)
	_board.add_child(pad)

	var label := Label3D.new()
	label.text = "BUILD"
	label.font_size = 48
	label.pixel_size = 0.002
	label.modulate = Color(0.4, 1.0, 0.6)
	label.outline_size = 6
	label.position = _board_local(0.2, 0.68) + Vector3(0, 0.1, 0)
	_board.add_child(label)


func _build_ui() -> void:
	_stats_label = GraphicsPolish.make_label("", 64, Color(0.7, 1.0, 0.8))
	_stats_label.pixel_size = 0.004
	_stats_label.position = BOARD_POS + Vector3(0, 0.42, 0)
	add_child(_stats_label)

	_banner_label = GraphicsPolish.make_label("", 128)
	_banner_label.pixel_size = 0.006
	_banner_label.position = BOARD_POS + Vector3(0, 0.25, 0)
	_banner_label.visible = false
	add_child(_banner_label)
	_update_stats()


# ---------------------------------------------------------------- input ---

func _unhandled_input(event: InputEvent) -> void:
	if is_over:
		return
	if event is InputEventMouseButton and event.pressed:
		var res := board_point_from_screen(event.position)
		if not res[0]:
			return
		var p: Vector3 = res[1]
		if event.button_index == MOUSE_BUTTON_LEFT:
			try_spawn_fighter(p)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			try_spawn_cruiser(p)
	elif event is InputEventScreenTouch and event.pressed:
		var res := board_point_from_screen(event.position)
		if res[0]:
			try_spawn_fighter(res[1])


func try_spawn_fighter(world_pos: Vector3) -> bool:
	return _try_spawn(StarforgeUnit.UnitType.FIGHTER, world_pos)


func try_spawn_cruiser(world_pos: Vector3) -> bool:
	return _try_spawn(StarforgeUnit.UnitType.CRUISER, world_pos)


func _try_spawn(unit_type: StarforgeUnit.UnitType, world_pos: Vector3) -> bool:
	var cost: int = StarforgeUnit.COSTS[unit_type]
	if player_resources < cost:
		return false
	if player_units.size() >= PLAYER_CAP:
		return false
	player_resources -= cost
	spawn_unit(StarforgeUnit.Side.PLAYER, unit_type, world_pos)
	return true


func spawn_unit(p_side: int, p_type: StarforgeUnit.UnitType,
		world_pos: Vector3, free := false) -> StarforgeUnit:
	var unit := StarforgeUnit.new()
	add_child(unit)
	unit.setup(p_side, p_type, self)
	unit.global_position = project_to_board(world_pos)
	unit.died.connect(_on_unit_died)
	if p_side == StarforgeUnit.Side.PLAYER:
		player_units.append(unit)
	else:
		enemy_units.append(unit)
	return unit


# ---------------------------------------------------------------- combat ---

func nearest_hostile(pos: Vector3, seeker_side: int, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	var units := enemy_units if seeker_side == StarforgeUnit.Side.PLAYER else player_units
	for u in units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var d := pos.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	var base := enemy_base if seeker_side == StarforgeUnit.Side.PLAYER else player_base
	if is_instance_valid(base) and base.is_alive():
		var d := pos.distance_to(base.global_position)
		if d < best_d:
			best_d = d
			best = base
	return best


func _on_unit_died(unit: StarforgeUnit) -> void:
	player_units.erase(unit)
	enemy_units.erase(unit)
	if is_instance_valid(unit):
		var burst := Color(0.4, 0.9, 1.0) if unit.side == StarforgeUnit.Side.PLAYER else Color(1.0, 0.4, 0.2)
		GraphicsPolish.spawn_sparks(self, unit.global_position, burst, 20)


func _on_base_destroyed(building: StarforgeBuilding) -> void:
	if is_over:
		return
	if building == enemy_base:
		_end_game(true)
	elif building == player_base:
		_end_game(false)


func _end_game(won: bool) -> void:
	is_over = true
	_banner_label.text = "VICTORY" if won else "DEFEAT"
	_banner_label.modulate = Color(0.4, 1.0, 0.5) if won else Color(1.0, 0.35, 0.3)
	_banner_label.visible = true


# ---------------------------------------------------------------- update ---

func _process(delta: float) -> void:
	if is_over:
		return
	# Persist the board anchor every 30s so the tabletop stays put between sessions.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if _board != null:
			ARUpgradeKit.save_anchor("starforge_main", _board.global_transform)
	# XR hand spawn: right-hand pinch spawns a fighter where the hand ray meets the board.
	# Mouse clicks / taps still spawn via _unhandled_input.
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var ray := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		var origin: Vector3 = ray[0]
		var dir: Vector3 = ray[1]
		if absf(dir.y) > 0.0001 and _board != null:
			var t := (_board.global_position.y - origin.y) / dir.y
			if t > 0.0:
				try_spawn_fighter(project_to_board(origin + dir * t))
	player_resources += RESOURCE_TICK * delta
	_prune_units()
	_ai_think(delta)
	_update_stats()


func _prune_units() -> void:
	for i in range(player_units.size() - 1, -1, -1):
		var u := player_units[i]
		if not is_instance_valid(u) or not u.is_alive():
			player_units.remove_at(i)
	for i in range(enemy_units.size() - 1, -1, -1):
		var u := enemy_units[i]
		if not is_instance_valid(u) or not u.is_alive():
			enemy_units.remove_at(i)


func _player_base_alive() -> bool:
	return is_instance_valid(player_base) and player_base.is_alive()


func _ai_think(delta: float) -> void:
	var diff := AI_DIFFICULTY
	_ai_resources += (1.2 + diff * 2.2) * delta
	_ai_build_timer -= delta
	_ai_wave_timer -= delta
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = 1.0
	if not is_instance_valid(enemy_base) or not enemy_base.is_alive():
		return

	# Build up to a difficulty-scaled cap.
	var cap := 3 + int(round(diff * 5.0))
	if _ai_build_timer <= 0.0 and enemy_units.size() < cap and _ai_resources >= FIGHTER_COST:
		_ai_build_timer = lerpf(9.0, 4.0, diff)
		_ai_resources -= FIGHTER_COST
		var offset := Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
		spawn_unit(StarforgeUnit.Side.ENEMY, StarforgeUnit.UnitType.FIGHTER,
			enemy_base.global_position + offset)

	# Attack waves at the player base.
	var wave_size := 2 + int(round(diff * 4.0))
	if _ai_wave_timer <= 0.0 and enemy_units.size() >= wave_size and _player_base_alive():
		_ai_wave_timer = lerpf(30.0, 16.0, diff)
		for u in enemy_units:
			if is_instance_valid(u) and u.is_alive() and u.hp > u.max_hp * 0.5:
				u.order_attack(player_base)

	# Retreat critically damaged ships.
	for u in enemy_units:
		if is_instance_valid(u) and u.is_alive() and u.hp < u.max_hp * 0.3:
			u.order_move(project_to_board(enemy_base.global_position))


func _update_stats() -> void:
	if _stats_label == null:
		return
	_stats_label.text = "◈ %d   Fleet %d/%d   Enemy %d" % [
		int(player_resources), player_units.size(), PLAYER_CAP, enemy_units.size()]
