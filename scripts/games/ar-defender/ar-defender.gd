## ARDefenderGame.gd - Tower defense played on your floor.
## Red enemies march the glowing path toward your base in waves. Click empty
## floor to build a tower (50 energy, regenerates over time); click a tower to
## upgrade it (75 energy, +damage/+range). Towers auto-fire at the nearest
## enemy in range. Lose a life per enemy that reaches the base; 0 lives = over.
extends Node3D
class_name ARDefenderGame

const TOWER_COST := 50.0
const UPGRADE_COST := 75.0
const ENERGY_MAX := 250.0
const ENERGY_REGEN := 9.0
const START_LIVES := 10
const START_ENERGY := 120.0

var waypoints: Array = [
	Vector3(-2.6, 0, -1.4), Vector3(2.6, 0, -1.4), Vector3(2.6, 0, 0.2),
	Vector3(-2.6, 0, 0.2), Vector3(-2.6, 0, 1.8), Vector3(2.6, 0, 1.8),
]
var _base_pos := Vector3(2.6, 0, 1.8)

var _cam: Camera3D
var _towers: Array = [] # {"node","head","head_mat","pos","range","damage","timer","level","cooldown"}
var _enemies: Array = [] # {"node","pos","hp","max_hp","speed","wp","dead"}
var _projectiles: Array = [] # {"node","target","speed","damage"}

var _wave := 1
var _phase := "build" # "build" | "wave" | "over"
var _build_timer := 4.0
var _spawn_left := 0
var _spawn_timer := 0.0
var _wave_count := 0
var _wave_hp := 0.0
var _wave_speed := 0.0

var _lives := START_LIVES
var _energy := START_ENERGY
var _score := 0

var _hud_label: Label3D
var _msg_label: Label3D
var _help_label: Label3D
var _msg_timer := 0.0
var _anchor_timer := 0.0

var _tower_base_mesh: CylinderMesh
var _tower_head_mesh: BoxMesh
var _tower_base_mat: StandardMaterial3D
var _head_mat_1: StandardMaterial3D
var _head_mat_2: StandardMaterial3D
var _enemy_mesh: SphereMesh
var _enemy_mat: StandardMaterial3D
var _proj_mesh: SphereMesh
var _proj_mat: StandardMaterial3D


func _ready() -> void:
	_ensure_camera()
	_build_light_and_floor()
	_build_materials()
	_build_path()
	_build_base()
	_build_labels()
	_say("Wave 1 incoming - build towers!")
	# AR: restore the saved room anchor in XR; ambient dust motes over the board.
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.apply_anchor(self, "ar-defender_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.0, 0), 3.0, 50)


func _process(delta: float) -> void:
	_update_anchor_timer(delta)
	# XR pinch: build/upgrade via the pointer ray (mouse clicks keep working).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		if _phase == "over":
			_reset_game()
		else:
			_xr_pinch_click()
	if _phase == "over":
		return
	_energy = minf(_energy + ENERGY_REGEN * delta, ENERGY_MAX)
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""
	_update_waves(delta)
	_update_enemies(delta)
	_update_towers(delta)
	_update_projectiles(delta)
	_cleanup_dead()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R and _phase == "over":
			_reset_game()


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- setup ---

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 4.6, -0.6)
	add_child(_cam)
	_cam.look_at(Vector3(0.0, 0.0, 0.6), Vector3.UP)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light_and_floor() -> void:
	_add_polish_light_rig()
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 18.0)
	floor_mi.mesh = plane
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.1, 0.11, 0.14), "matte")
	add_child(floor_mi)


func _glow(color: Color, energy: float = 1.2) -> StandardMaterial3D:
	return GraphicsPolish.glow(color, energy)


func _build_materials() -> void:
	_tower_base_mesh = CylinderMesh.new()
	_tower_base_mesh.top_radius = 0.14
	_tower_base_mesh.bottom_radius = 0.17
	_tower_base_mesh.height = 0.34
	_tower_head_mesh = BoxMesh.new()
	_tower_head_mesh.size = Vector3(0.2, 0.14, 0.2)
	_tower_base_mat = GraphicsPolish.pbr_preset(Color(0.35, 0.4, 0.5), "metal")
	_head_mat_1 = _glow(Color(0.2, 0.9, 1.0))
	_head_mat_2 = _glow(Color(1.0, 0.9, 0.2), 1.6)
	_enemy_mesh = SphereMesh.new()
	_enemy_mesh.radius = 0.16
	_enemy_mesh.height = 0.32
	_enemy_mat = _glow(Color(1.0, 0.25, 0.2), 1.1)
	_proj_mesh = SphereMesh.new()
	_proj_mesh.radius = 0.045
	_proj_mesh.height = 0.09
	_proj_mat = _glow(Color(1.0, 0.95, 0.3), 2.0)


func _build_path() -> void:
	var path_mat := _glow(Color(0.25, 1.0, 0.45), 1.0)
	for i in range(waypoints.size() - 1):
		var a: Vector3 = waypoints[i]
		var b: Vector3 = waypoints[i + 1]
		var d := b - a
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(d.length(), 0.03, 0.5)
		strip.mesh = bm
		strip.material_override = path_mat
		strip.position = Vector3((a.x + b.x) * 0.5, 0.03, (a.z + b.z) * 0.5)
		strip.rotation.y = -atan2(d.z, d.x)
		add_child(strip)
	# Spawn portal marker.
	var portal := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.4
	portal.mesh = tm
	portal.material_override = _glow(Color(1.0, 0.3, 0.3), 1.4)
	portal.position = waypoints[0] + Vector3(0, 0.45, 0)
	portal.rotation.x = PI * 0.5
	add_child(portal)


func _build_base() -> void:
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.55
	cm.height = 0.15
	base.mesh = cm
	base.material_override = _glow(Color(0.3, 0.5, 1.0), 1.0)
	base.position = _base_pos + Vector3(0, 0.075, 0)
	add_child(base)
	var label := Label3D.new()
	label.text = "BASE"
	label.font_size = 56
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = _base_pos + Vector3(0, 0.75, 0)
	add_child(label)


func _make_label(text: String, pos: Vector3, font_size: int = 56) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = pos
	add_child(label)
	return label


func _build_labels() -> void:
	_hud_label = _make_label("", Vector3(0.0, 2.7, -2.4), 60)
	_msg_label = _make_label("", Vector3(0.0, 2.25, -2.4), 52)
	_help_label = _make_label(
			"AR Defender - click empty floor to build a tower (50 energy).\nClick a tower to upgrade it (75). Towers auto-fire.\nKeep enemies off the blue base! R restarts after game over.",
			Vector3(-3.4, 1.7, 1.2), 40)


func _say(text: String, hold: float = 2.5) -> void:
	_msg_label.text = text
	_msg_timer = hold


# ---------------------------------------------------------------- input ---

func _handle_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	if _phase == "over":
		_reset_game()
		return
	var origin := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return
	var t := -origin.y / dir.y
	if t < 0.0:
		return
	_click_at_world(origin + dir * t)


func _xr_pinch_click() -> void:
	# XR alternative to _handle_click: pinch shoots the pointer ray at the floor.
	if _cam == null:
		return
	var pr := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var origin: Vector3 = pr[0]
	var dir: Vector3 = pr[1]
	if absf(dir.y) < 0.0001:
		return
	var t := -origin.y / dir.y
	if t < 0.0:
		return
	_click_at_world(ARUpgradeKit.clamp_to_room(origin + dir * t))


func _click_at_world(p: Vector3) -> void:
	p.y = 0.0
	var tw := _tower_near(p, 0.45)
	if not tw.is_empty():
		_try_upgrade(tw)
		return
	if _dist_to_path(p) < 0.55:
		_say("Too close to the path!")
		return
	if p.distance_to(_base_pos) < 0.9:
		_say("Too close to the base!")
		return
	if _energy < TOWER_COST:
		_say("Need 50 energy!")
		return
	_place_tower(p)


func _tower_near(p: Vector3, radius: float) -> Dictionary:
	for tw in _towers:
		if p.distance_to(tw["pos"]) <= radius:
			return tw
	return {}


func _dist_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _dist_to_path(p: Vector3) -> float:
	var best := 1e9
	for i in range(waypoints.size() - 1):
		best = minf(best, _dist_point_segment(p, waypoints[i], waypoints[i + 1]))
	return best


# ---------------------------------------------------------------- towers ---

func _place_tower(p: Vector3) -> void:
	_energy -= TOWER_COST
	p = ARUpgradeKit.clamp_to_room(p) # keep towers inside the tracked room
	var root := Node3D.new()
	root.position = Vector3(p.x, 0.0, p.z)
	var base := MeshInstance3D.new()
	base.mesh = _tower_base_mesh
	base.material_override = _tower_base_mat
	base.position = Vector3(0, 0.17, 0)
	root.add_child(base)
	var head := MeshInstance3D.new()
	head.mesh = _tower_head_mesh
	head.material_override = _head_mat_1
	head.position = Vector3(0, 0.42, 0)
	root.add_child(head)
	add_child(root)
	_towers.append({"node": root, "head": head, "head_mesh": head,
			"pos": Vector3(p.x, 0.0, p.z), "range": 2.4, "damage": 1,
			"timer": 0.0, "level": 1, "cooldown": 0.55})
	_play_tone(330.0, 0.12)
	_say("Tower built! Click it again to upgrade (75).")
	GraphicsPolish.spawn_sparks(self, root.position + Vector3(0, 0.5, 0), Color(0.2, 0.9, 1.0), 20)


func _try_upgrade(tw: Dictionary) -> void:
	if int(tw["level"]) >= 3:
		_say("Tower is max level!")
		return
	if _energy < UPGRADE_COST:
		_say("Need 75 energy to upgrade!")
		return
	_energy -= UPGRADE_COST
	tw["level"] = int(tw["level"]) + 1
	tw["damage"] = int(tw["damage"]) + 1
	tw["range"] = float(tw["range"]) + 0.35
	tw["cooldown"] = maxf(0.3, float(tw["cooldown"]) - 0.1)
	var head := tw["head_mesh"] as MeshInstance3D
	head.material_override = _head_mat_2
	head.scale = Vector3(1.25, 1.25, 1.25)
	_play_tone(520.0, 0.12)
	_say("Tower upgraded to level %d!" % int(tw["level"]))


func _nearest_enemy(pos: Vector3, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_range
	for e in _enemies:
		if bool(e["dead"]):
			continue
		var d := pos.distance_to(e["pos"])
		if d < best_d:
			best_d = d
			best = e
	return best


func _update_towers(delta: float) -> void:
	for tw in _towers:
		tw["timer"] = float(tw["timer"]) - delta
		var target := _nearest_enemy(tw["pos"], float(tw["range"]))
		if target.is_empty():
			continue
		var head := tw["head"] as Node3D
		var d: Vector3 = (target["pos"] as Vector3) - head.global_position
		if d.length() > 0.01:
			head.rotation.y = atan2(-d.x, -d.z)
		if float(tw["timer"]) <= 0.0:
			tw["timer"] = float(tw["cooldown"])
			_fire(tw, target)


func _fire(tw: Dictionary, target: Dictionary) -> void:
	var bolt := MeshInstance3D.new()
	bolt.mesh = _proj_mesh
	bolt.material_override = _proj_mat
	bolt.position = (tw["head"] as Node3D).global_position
	add_child(bolt)
	_projectiles.append({"node": bolt, "target": target, "speed": 7.0,
			"damage": int(tw["damage"])})
	_play_tone(880.0, 0.05)


# ---------------------------------------------------------------- enemies ---

func _update_waves(delta: float) -> void:
	if _phase == "build":
		_build_timer -= delta
		if _build_timer <= 0.0:
			_start_wave()
	elif _phase == "wave":
		if _spawn_left > 0:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn_enemy()
				_spawn_left -= 1
				_spawn_timer = 0.7
		elif _enemies.is_empty():
			var bonus := 25 * _wave
			_score += bonus
			_say("Wave %d cleared! +%d bonus" % [_wave, bonus])
			_wave += 1
			_phase = "build"
			_build_timer = 5.0


func _start_wave() -> void:
	_phase = "wave"
	_wave_count = 4 + _wave * 2
	_wave_hp = 2.0 + _wave * 1.5
	_wave_speed = minf(0.6 + _wave * 0.12, 1.7)
	_spawn_left = _wave_count
	_spawn_timer = 0.5
	_say("Wave %d - %d enemies incoming!" % [_wave, _wave_count])


func _spawn_enemy() -> void:
	var node := MeshInstance3D.new()
	node.mesh = _enemy_mesh
	node.material_override = _enemy_mat
	var start: Vector3 = waypoints[0]
	node.position = start + Vector3(0, 0.16, 0)
	add_child(node)
	_enemies.append({"node": node, "pos": start, "hp": _wave_hp,
			"max_hp": _wave_hp, "speed": _wave_speed, "wp": 1, "dead": false})


func _update_enemies(delta: float) -> void:
	for e in _enemies:
		if bool(e["dead"]):
			continue
		var wp_index: int = e["wp"]
		if wp_index >= waypoints.size():
			_reached_base(e)
			continue
		var target: Vector3 = waypoints[wp_index]
		var pos: Vector3 = e["pos"]
		var step: float = float(e["speed"]) * delta
		var d := target - pos
		if d.length() <= maxf(step, 0.05):
			e["pos"] = target
			e["wp"] = wp_index + 1
		else:
			e["pos"] = pos + d.normalized() * step
		(e["node"] as Node3D).position = (e["pos"] as Vector3) + Vector3(0, 0.16, 0)


func _reached_base(e: Dictionary) -> void:
	e["dead"] = true
	(e["node"] as Node).queue_free()
	_lives -= 1
	_play_tone(140.0, 0.25)
	if _lives <= 0:
		_lives = 0
		_game_over()
	else:
		_say("Enemy breached the base! Lives: %d" % _lives)


func _hit_enemy(e: Dictionary, damage: int) -> void:
	e["hp"] = float(e["hp"]) - damage
	if float(e["hp"]) <= 0.0 and not bool(e["dead"]):
		e["dead"] = true
		var boom_pos := (e["node"] as Node3D).position
		(e["node"] as Node).queue_free()
		GraphicsPolish.spawn_sparks(self, boom_pos, Color(1.0, 0.4, 0.2), 24)
		var gain := 10 + _wave * 2
		_score += gain
		_energy = minf(_energy + 10.0, ENERGY_MAX)
		_play_tone(180.0, 0.15)


func _cleanup_dead() -> void:
	_enemies = _enemies.filter(func(e: Dictionary) -> bool: return not bool(e["dead"]))


func _update_projectiles(delta: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var pr: Dictionary = _projectiles[i]
		var tgt: Dictionary = pr["target"]
		var bolt := pr["node"] as MeshInstance3D
		if tgt.is_empty() or bool(tgt["dead"]) or not is_instance_valid(tgt["node"]):
			bolt.queue_free()
			_projectiles.remove_at(i)
			continue
		var tp: Vector3 = (tgt["node"] as Node3D).position
		var d := tp - bolt.position
		var step: float = float(pr["speed"]) * delta
		if d.length() <= maxf(step, 0.18):
			_hit_enemy(tgt, int(pr["damage"]))
			bolt.queue_free()
			_projectiles.remove_at(i)
		else:
			bolt.position += d.normalized() * step


# ---------------------------------------------------------------- state ---

func _game_over() -> void:
	_phase = "over"
	_msg_label.text = "GAME OVER\nScore: %d   Wave: %d\nClick or press R to retry" % [_score, _wave]
	_msg_timer = 0.0


func _reset_game() -> void:
	for tw in _towers:
		(tw["node"] as Node).queue_free()
	for e in _enemies:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	for pr in _projectiles:
		if is_instance_valid(pr["node"]):
			(pr["node"] as Node).queue_free()
	_towers.clear()
	_enemies.clear()
	_projectiles.clear()
	_wave = 1
	_phase = "build"
	_build_timer = 4.0
	_spawn_left = 0
	_lives = START_LIVES
	_energy = START_ENERGY
	_score = 0
	_msg_label.text = ""
	_say("Wave 1 incoming - build towers!")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.save_anchor("ar-defender_main", global_transform)


func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active():
			ARUpgradeKit.save_anchor("ar-defender_main", global_transform)


func _refresh_hud() -> void:
	var phase_text := "Next wave in %ds" % int(ceil(_build_timer)) if _phase == "build" else "Fighting!"
	_hud_label.text = "Wave %d (%s)   Lives %d\nEnergy %d/%d   Score %d" % [
			_wave, phase_text, _lives, int(_energy), int(ENERGY_MAX), _score]


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
