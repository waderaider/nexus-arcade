## holo-dungeon.gd - "Holo Dungeon": roguelike dungeon crawler.
## Procedurally generates a 5x5 grid of dark-stone rooms on the floor with
## random interior wall blocks (path between start and stairs is guaranteed).
## The player is a glowing capsule; click an adjacent walkable tile to move.
## Red-sphere enemies wander and attack when adjacent; click one while
## adjacent to fight it (HP bars float above enemies). Gold chests grant gold
## when clicked while adjacent. The glowing stairs tile descends a depth
## (regenerates harder). Permadeath: HP 0 ends the run; the run counter is
## persisted in user://holo_dungeon.cfg. Desktop/mouse driven;
## _pinch_active() is the XR hand-tracking hook.
extends Node3D

const GRID := 5
const TILE := 1.0
const SAVE_PATH := "user://holo_dungeon.cfg"
const WALL_ATTEMPTS := 40
const WALL_COUNT := 6
const ENEMY_WANDER_TIME := 1.2
const ENEMY_ATTACK_TIME := 1.5

var camera: Camera3D = null
var dungeon_root: Node3D = null
var player_node: MeshInstance3D = null
var player_mat: StandardMaterial3D = null
var walkable: Array = [] # walkable[x][z] bool
var player_pos := Vector2i(0, 0)
var player_hp := 100
var player_max_hp := 100
var player_dmg := 15
var gold := 0
var depth := 1
var run_number := 1
var state := "play" # play | dead
var enemies: Array = [] # Dictionaries: node, hp, max_hp, dmg, tile, bar_bg, bar_fg, wander_t, attack_t, reward
var chests: Array = [] # Dictionaries: node, mat, tile, opened
var stairs_tile := Vector2i(4, 4)
var stairs_mat: StandardMaterial3D = null
var hurt_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var move_player: AudioStreamPlayer = null
var attack_player: AudioStreamPlayer = null
var pickup_player: AudioStreamPlayer = null
var hurt_snd: AudioStreamPlayer = null
var down_player: AudioStreamPlayer = null
var death_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _click_consumed := false


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_load_run()
	_build_hud()
	move_player = _make_player(_make_tone(520.0, 0.08, 0.4))
	attack_player = _make_player(_make_tone(880.0, 0.12, 0.5))
	pickup_player = _make_player(_make_tone(1320.0, 0.15, 0.5))
	hurt_snd = _make_player(_make_tone(160.0, 0.25, 0.55))
	down_player = _make_player(_make_tone(330.0, 0.3, 0.5))
	death_player = _make_player(_make_tone(98.0, 0.6, 0.6))
	_new_run()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 3.0)


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
		_save_anchor()
	if state == "dead":
		if Input.is_key_pressed(KEY_R):
			_new_run()
		return
	if Input.is_key_pressed(KEY_R):
		_new_run()
		return

	hurt_t = maxf(0.0, hurt_t - delta * 3.0)
	if player_mat != null:
		player_mat.emission = Color(0.2, 0.9, 1.0).lerp(Color(1.0, 0.2, 0.2), hurt_t)

	# Enemies wander and attack.
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var node: MeshInstance3D = e["node"]
		if not is_instance_valid(node):
			enemies.remove_at(i)
			continue
		var et: Vector2i = e["tile"]
		var wt := float(e["wander_t"]) - delta
		if wt <= 0.0:
			wt = ENEMY_WANDER_TIME
			var options: Array = []
			for d in _dirs():
				var nt: Vector2i = et + d
				if _is_walkable(nt) and not _tile_has_enemy(nt) and nt != player_pos:
					options.append(nt)
			if not options.is_empty():
				var ntile: Vector2i = options[randi() % options.size()]
				e["tile"] = ntile
				node.position = _tile_to_world(ntile) + Vector3(0.0, 0.45, 0.0)
		else:
			e["wander_t"] = wt
		# Attack when adjacent to the player.
		if _manhattan(et, player_pos) == 1:
			var at := float(e["attack_t"]) - delta
			if at <= 0.0:
				e["attack_t"] = ENEMY_ATTACK_TIME
				_damage_player(int(e["dmg"]))
				if state == "dead":
					return
			else:
				e["attack_t"] = at
		else:
			e["attack_t"] = 0.0
		node.rotation.y += delta * 1.5

	# Stairs pulse.
	if stairs_mat != null:
		stairs_mat.emission_energy_multiplier = 1.2 + sin(Time.get_ticks_msec() / 300.0) * 0.8

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click_consumed = true
			if state == "dead":
				_new_run()
			else:
				_handle_click(mb.position)


## Hand-tracking hook: XR pinch taps tiles/enemies/chests (mouse still works).
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _poll_pinch() -> void:
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if _click_consumed:
		_click_consumed = false
		return
	if pinched and camera != null and state == "play":
		var wp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		_handle_click(camera.unproject_position(wp))


func _save_anchor() -> void:
	if dungeon_root != null and is_instance_valid(dungeon_root):
		ARUpgradeKit.save_anchor("holo-dungeon_main", dungeon_root.global_transform)


func _dirs() -> Array:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _tile_to_world(t: Vector2i) -> Vector3:
	return Vector3((float(t.x) - float(GRID - 1) / 2.0) * TILE, 0.0, (float(t.y) - float(GRID - 1) / 2.0) * TILE)


func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < GRID and t.y >= 0 and t.y < GRID


func _is_walkable(t: Vector2i) -> bool:
	return _in_bounds(t) and bool(walkable[t.x][t.y])


func _tile_has_enemy(t: Vector2i) -> bool:
	for e in enemies:
		var ed: Dictionary = e
		if ed["tile"] == t:
			return true
	return false


func _enemy_at(t: Vector2i) -> Dictionary:
	for e in enemies:
		var ed: Dictionary = e
		if ed["tile"] == t:
			return ed
	return {}


func _chest_at(t: Vector2i) -> Dictionary:
	for c in chests:
		var cd: Dictionary = c
		if cd["tile"] == t and not bool(cd["opened"]):
			return cd
	return {}


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 7.0, 5.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.4), Vector3.UP)
	camera.current = true


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001 or dir.y > 0.0:
		return Vector2i(-1, -1)
	var t := -origin.y / dir.y
	var p: Vector3 = origin + dir * t
	var gx := int(round(p.x / TILE + float(GRID - 1) / 2.0))
	var gz := int(round(p.z / TILE + float(GRID - 1) / 2.0))
	return Vector2i(gx, gz)


func _handle_click(screen_pos: Vector2) -> void:
	var tile := _screen_to_tile(screen_pos)
	if not _in_bounds(tile):
		return
	# Attack enemy.
	var e := _enemy_at(tile)
	if not e.is_empty():
		if _manhattan(player_pos, tile) == 1:
			_attack_enemy(e)
		return
	# Loot chest.
	var c := _chest_at(tile)
	if not c.is_empty():
		if _manhattan(player_pos, tile) == 1:
			_loot_chest(c)
		return
	# Descend stairs.
	if tile == stairs_tile:
		if _manhattan(player_pos, tile) == 1:
			_descend()
		return
	# Move to adjacent walkable tile.
	if _manhattan(player_pos, tile) == 1 and _is_walkable(tile) and not _tile_has_enemy(tile):
		player_pos = tile
		player_node.position = _tile_to_world(tile) + Vector3(0.0, 0.6, 0.0)
		if move_player != null:
			move_player.play()


func _attack_enemy(e: Dictionary) -> void:
	var node: MeshInstance3D = e["node"]
	if not is_instance_valid(node):
		return
	if attack_player != null:
		attack_player.play()
	var hp := int(e["hp"]) - player_dmg
	e["hp"] = hp
	_update_enemy_bar(e)
	if hp <= 0:
		var reward := int(e["reward"])
		gold += reward
		GraphicsPolish.spawn_sparks(dungeon_root, node.position, Color(1.0, 0.3, 0.2), 24)
		node.queue_free()
		enemies.erase(e)
		if pickup_player != null:
			pickup_player.play()


func _update_enemy_bar(e: Dictionary) -> void:
	var fg: MeshInstance3D = e["bar_fg"]
	if not is_instance_valid(fg):
		return
	var frac := clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
	fg.scale.x = frac
	fg.position.x = -0.3 * (1.0 - frac)


func _loot_chest(c: Dictionary) -> void:
	c["opened"] = true
	var mat: StandardMaterial3D = c["mat"]
	mat.albedo_color = Color(0.35, 0.30, 0.20)
	mat.emission_enabled = false
	var reward := 25 + 10 * (depth - 1) + randi() % 20
	gold += reward
	var cnode: MeshInstance3D = c["node"]
	if is_instance_valid(cnode):
		GraphicsPolish.spawn_sparks(dungeon_root, cnode.position, Color(1.0, 0.85, 0.3), 20)
	if pickup_player != null:
		pickup_player.play()


func _damage_player(amount: int) -> void:
	player_hp -= amount
	hurt_t = 1.0
	if hurt_snd != null:
		hurt_snd.play()
	if player_hp <= 0:
		player_hp = 0
		_on_death()


func _descend() -> void:
	depth += 1
	GraphicsPolish.spawn_confetti(dungeon_root, _tile_to_world(stairs_tile) + Vector3(0.0, 0.5, 0.0), 40)
	player_hp = mini(player_max_hp, player_hp + player_max_hp / 4)
	if down_player != null:
		down_player.play()
	_generate_dungeon()


func _on_death() -> void:
	state = "dead"
	run_number += 1
	_save_run()
	if death_player != null:
		death_player.play()
	msg_label.text = "RUN OVER\nRun #%d complete\nDepth %d | Gold %d\nClick or press R for Run #%d" % [run_number - 1, depth, gold, run_number]


func _new_run() -> void:
	_save_anchor()
	depth = 1
	gold = 0
	player_hp = player_max_hp
	state = "play"
	msg_label.text = ""
	_generate_dungeon()


func _generate_dungeon() -> void:
	if is_instance_valid(dungeon_root):
		dungeon_root.queue_free()
	enemies.clear()
	chests.clear()
	dungeon_root = Node3D.new()
	add_child(dungeon_root)
	stairs_tile = Vector2i(GRID - 1, GRID - 1)
	player_pos = Vector2i(0, 0)

	# Random wall blocks, guaranteeing a path from start to stairs.
	for attempt in range(WALL_ATTEMPTS):
		_init_walkable()
		var placed := 0
		var guard := 0
		while placed < WALL_COUNT and guard < 200:
			guard += 1
			var t := Vector2i(randi() % GRID, randi() % GRID)
			if t == player_pos or t == stairs_tile or not bool(walkable[t.x][t.y]):
				continue
			walkable[t.x][t.y] = false
			placed += 1
		if _bfs_reachable():
			break

	_build_tiles()
	_build_stairs()
	_build_player()
	_spawn_enemies()
	_spawn_chests()
	# Room-aware placement: keep the dungeon on the floor, inside the room,
	# and restore its saved spatial anchor if one exists.
	ARUpgradeKit.apply_anchor(dungeon_root, "holo-dungeon_main")
	ARUpgradeKit.snap_to_floor(dungeon_root)
	dungeon_root.position = ARUpgradeKit.clamp_to_room(dungeon_root.position)
	_update_hud()


func _init_walkable() -> void:
	walkable.clear()
	for x in range(GRID):
		var col: Array = []
		for z in range(GRID):
			col.append(true)
		walkable.append(col)


func _bfs_reachable() -> bool:
	var seen: Array = []
	for x in range(GRID):
		var col: Array = []
		for z in range(GRID):
			col.append(false)
		seen.append(col)
	var queue: Array = [player_pos]
	seen[player_pos.x][player_pos.y] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == stairs_tile:
			return true
		for d in _dirs():
			var nt: Vector2i = cur + d
			if _in_bounds(nt) and bool(walkable[nt.x][nt.y]) and not bool(seen[nt.x][nt.y]):
				seen[nt.x][nt.y] = true
				queue.append(nt)
	return false


func _build_tiles() -> void:
	for x in range(GRID):
		for z in range(GRID):
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(TILE * 0.96, 0.08, TILE * 0.96)
			tile.mesh = box
			var shade := 0.13 + randf() * 0.05
			var mat: StandardMaterial3D
			if x == 0 and z == 0:
				mat = GraphicsPolish.glow(Color(0.1, 0.3, 0.4), 0.4)
			else:
				mat = GraphicsPolish.pbr_preset(Color(shade, shade, shade + 0.02), "matte")
			tile.material_override = mat
			tile.position = _tile_to_world(Vector2i(x, z)) + Vector3(0.0, -0.04, 0.0)
			dungeon_root.add_child(tile)
			if not bool(walkable[x][z]):
				var wall := MeshInstance3D.new()
				var wbox := BoxMesh.new()
				wbox.size = Vector3(TILE * 0.96, 0.9, TILE * 0.96)
				wall.mesh = wbox
				var wmat := GraphicsPolish.pbr_preset(Color(0.22, 0.21, 0.24), "matte")
				wall.material_override = wmat
				wall.position = _tile_to_world(Vector2i(x, z)) + Vector3(0.0, 0.45, 0.0)
				dungeon_root.add_child(wall)


func _build_stairs() -> void:
	var tile := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TILE * 0.7, 0.12, TILE * 0.7)
	tile.mesh = box
	stairs_mat = GraphicsPolish.glow(Color(1.0, 0.8, 0.25), 1.5)
	tile.material_override = stairs_mat
	tile.position = _tile_to_world(stairs_tile) + Vector3(0.0, 0.06, 0.0)
	dungeon_root.add_child(tile)


func _build_player() -> void:
	player_node = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.9
	player_node.mesh = cap
	player_mat = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 1.8)
	player_node.material_override = player_mat
	player_node.position = _tile_to_world(player_pos) + Vector3(0.0, 0.6, 0.0)
	dungeon_root.add_child(player_node)


func _free_tiles_near_start() -> Array:
	var free: Array = []
	for x in range(GRID):
		for z in range(GRID):
			var t := Vector2i(x, z)
			if _is_walkable(t) and t != player_pos and _manhattan(t, player_pos) > 2 and t != stairs_tile and not _tile_has_enemy(t):
				free.append(t)
	return free


func _spawn_enemies() -> void:
	var count := 3 + mini(depth - 1, 2)
	var free := _free_tiles_near_start()
	for i in range(count):
		if free.is_empty():
			break
		var t: Vector2i = free.pop_at(randi() % free.size())
		var node := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		node.mesh = sphere
		var mat := GraphicsPolish.glow(Color(0.9, 0.15, 0.15), 1.6)
		node.material_override = mat
		node.position = _tile_to_world(t) + Vector3(0.0, 0.45, 0.0)
		dungeon_root.add_child(node)
		var hp := 20 + 10 * (depth - 1)
		var bar_bg := MeshInstance3D.new()
		var bgbox := BoxMesh.new()
		bgbox.size = Vector3(0.6, 0.08, 0.03)
		bar_bg.mesh = bgbox
		var bgmat := GraphicsPolish.glow(Color(0.25, 0.05, 0.05), 1.0)
		bar_bg.material_override = bgmat
		bar_bg.position = Vector3(0.0, 0.62, 0.0)
		node.add_child(bar_bg)
		var bar_fg := MeshInstance3D.new()
		var fgbox := BoxMesh.new()
		fgbox.size = Vector3(0.6, 0.08, 0.035)
		bar_fg.mesh = fgbox
		var fgmat := GraphicsPolish.glow(Color(0.2, 0.9, 0.2), 1.0)
		bar_fg.material_override = fgmat
		bar_fg.position = Vector3(0.0, 0.62, 0.0)
		node.add_child(bar_fg)
		enemies.append({
			"node": node,
			"hp": hp,
			"max_hp": hp,
			"dmg": 8 + 2 * (depth - 1),
			"tile": t,
			"bar_bg": bar_bg,
			"bar_fg": bar_fg,
			"wander_t": randf_range(0.2, ENEMY_WANDER_TIME),
			"attack_t": 0.0,
			"reward": 15 + 5 * (depth - 1),
		})


func _spawn_chests() -> void:
	var free := _free_tiles_near_start()
	for i in range(2):
		if free.is_empty():
			break
		var t: Vector2i = free.pop_at(randi() % free.size())
		var node := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.35, 0.5)
		node.mesh = box
		var mat := GraphicsPolish.glow(Color(0.9, 0.65, 0.15), 1.0)
		node.material_override = mat
		node.position = _tile_to_world(t) + Vector3(0.0, 0.2, 0.0)
		dungeon_root.add_child(node)
		chests.append({"node": node, "mat": mat, "tile": t, "opened": false})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("HOLO DUNGEON", 48, Color(1, 1, 1))
	hud_label.position = Vector3(-2.8, 3.4, 1.8)
	add_child(hud_label)
	msg_label = Label3D.new()
	msg_label.position = Vector3(-1.9, 2.4, 1.8)
	msg_label.pixel_size = 0.009
	msg_label.font_size = 60
	msg_label.outline_size = 12
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(msg_label)
	help_label = Label3D.new()
	help_label.position = Vector3(-2.8, 3.08, 1.8)
	help_label.pixel_size = 0.0035
	help_label.font_size = 26
	help_label.outline_size = 8
	help_label.modulate = Color(0.75, 0.80, 0.90)
	help_label.text = "Click an adjacent tile to move | click adjacent enemy to attack | chests = gold | stairs = deeper | R: new run"
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "Depth: %d   Gold: %d   HP: %d/%d   Run #%d" % [depth, gold, player_hp, player_max_hp, run_number]


func _load_run() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		run_number = maxi(1, int(cfg.get_value("dungeon", "run", 1)))


func _save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("dungeon", "run", run_number)
	cfg.save(SAVE_PATH)


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (move / hit / loot / danger).
func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
