extends Node3D
## HwMonsterMash - "Monster Mash": Halloween rhythm game.
## Monsters pop up on a 120 BPM beat; pinch or click them in time.
## Timing judged PERFECT / GOOD / OK by monster age; combo multiplies score.
## 90 second song. R restarts; pinch-hold 1s on the results screen restarts.

const SONG_LENGTH := 90.0
const BEAT := 0.5 # 120 BPM
const MONSTER_LIFE := 1.0
const HIT_RADIUS := 0.24

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var song_time := 0.0
var next_beat := 0.0
var beat_count := 0
var beat_flash := 1.0
var score := 0
var combo := 0
var best_combo := 0
var hits := 0
var misses := 0
var monsters: Array = [] # dicts: node, body_mat, ring_mat, age, hit
var hud_label: Label3D = null
var msg_label: Label3D = null
var beat_ball: MeshInstance3D = null
var beat_mat: StandardMaterial3D = null
var mouse_pos := Vector2.ZERO
var tick_player: AudioStreamPlayer = null
var hit_player: AudioStreamPlayer = null
var perfect_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0

## RoomKit v0.7.0: cached room layout + extra spawn points (game-local).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _room_spawn_extra: Array = []
# v0.7.0 KayKit: skeleton dancers flanking the stage (ambient set dressing).
var _skeleton_dancers: Array = [] # dicts: node, base_y, phase

const SPAWN_POINTS := [
	Vector3(-1.25, 1.15, -2.0), Vector3(-0.62, 1.45, -2.2),
	Vector3(0.0, 1.15, -2.0), Vector3(0.62, 1.45, -2.2),
	Vector3(1.25, 1.15, -2.0),
]
const MONSTER_COLORS := [
	Color(0.35, 0.85, 0.30), Color(0.65, 0.35, 0.95),
	Color(0.95, 0.50, 0.15), Color(0.25, 0.60, 0.95),
	Color(0.95, 0.30, 0.45),
]


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	mouse_pos = get_viewport().get_visible_rect().size * 0.5
	_build_stage()
	_build_skeleton_dancers() # v0.7.0 KayKit set dressing (null-safe)
	_build_hud()
	tick_player = _make_player(_make_tone(140.0, 0.09, 0.55))
	hit_player = _make_player(_make_tone(620.0, 0.10, 0.55))
	perfect_player = _make_player(_make_tone(940.0, 0.16, 0.55))
	miss_player = _make_player(_make_tone(170.0, 0.22, 0.5))
	win_player = _make_player(_make_tone(780.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_monster_mash_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -2.0), 2.5, 50)
	_apply_room_layout()


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 2.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.15, -2.0), Vector3.UP)
	camera.current = true


func _build_stage() -> void:
	# Spooky floor disc.
	var floor_inst := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.04
	floor_inst.mesh = disc
	floor_inst.position = Vector3(0.0, 0.0, -2.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.10, 0.08, 0.14), 0.1, 0.7)
	add_child(floor_inst)
	# Beat indicator ball pulsing overhead.
	beat_ball = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.12
	bs.height = 0.24
	beat_ball.mesh = bs
	beat_ball.position = Vector3(0.0, 2.35, -2.0)
	beat_mat = GraphicsPolish.glow(Color(1.0, 0.45, 0.1), 1.8)
	beat_ball.material_override = beat_mat
	add_child(beat_ball)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.0, -1.2), Color(1.0, 0.55, 0.2), 0.9, 5.0)


## v0.7.0 KayKit set dressing: two skeleton dancers flank the stage,
## bouncing to the beat. Guarded - missing models simply skip the dancers;
## the procedural stage and monsters are unchanged.
func _build_skeleton_dancers() -> void:
	var dir := "res://assets/models/hw_monster_mash/"
	var defs: Array = [
		{"f": "Skeleton_Minion.glb", "x": -1.90},
		{"f": "Skeleton_Rogue.glb", "x": 1.90},
	]
	for d_v in defs:
		var d: Dictionary = d_v
		var skel := ModelLib.spawn(dir + str(d["f"]), self, Vector3(float(d["x"]), 0.0, -2.0))
		if skel == null:
			continue
		skel.scale = Vector3.ONE * 0.9
		skel.rotation.y = -signf(float(d["x"])) * 0.35 # face the stage
		_skeleton_dancers.append({"node": skel, "base_y": 0.0, "phase": randf() * TAU})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("MONSTER MASH", 44, Color(1.0, 0.75, 0.3))
	hud_label.position = Vector3(-2.7, 2.7, -0.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 96, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.0, -2.0)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("Pinch or CLICK monsters on the beat!  R: restart", 30, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.55, -0.6)
	add_child(help)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY:
			_try_hit()


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_monster_mash_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			restart_hold += delta
			if restart_hold >= 1.0:
				_reset_game()
				return
		else:
			restart_hold = 0.0
		return
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_hit()
	song_time += delta
	beat_flash = maxf(0.0, beat_flash - delta * 4.0)
	while song_time >= next_beat and state == ST_PLAY:
		_on_beat()
		next_beat += BEAT
	# Age monsters, expire the un-hit.
	for i in range(monsters.size() - 1, -1, -1):
		var m: Dictionary = monsters[i]
		if bool(m["hit"]):
			continue
		m["age"] = float(m["age"]) + delta
		var node: MeshInstance3D = m["node"]
		if not is_instance_valid(node):
			monsters.remove_at(i)
			continue
		var age := float(m["age"])
		GraphicsPolish.ease_scale(node, Vector3.ONE, 10.0, delta)
		GraphicsPolish.pulse_glow(m["ring_mat"], 1.2, 1.2, age * 3.0, 6.0)
		node.position.y = (m["base_y"] as float) + sin(age * 9.0) * 0.04
		if age >= MONSTER_LIFE:
			_expire_monster(i, m)
	if beat_ball != null:
		var s := 1.0 + beat_flash * 0.6
		beat_ball.scale = Vector3(s, s, s)
		GraphicsPolish.pulse_glow(beat_mat, 1.4, 1.0, song_time, 4.0)
	# v0.7.0: skeleton dancers bounce and sway to the beat.
	for sd_v in _skeleton_dancers:
		var sd: Dictionary = sd_v
		var sn: Node3D = sd["node"]
		if not is_instance_valid(sn):
			continue
		var t: float = song_time + float(sd["phase"])
		sn.position.y = float(sd["base_y"]) + absf(sin(t * 4.0)) * 0.09
		sn.rotation.z = sin(t * 4.0) * 0.08
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	if song_time >= SONG_LENGTH:
		_game_over()
	_update_hud()


func _on_beat() -> void:
	beat_count += 1
	beat_flash = 1.0
	if tick_player != null:
		tick_player.play()
	_spawn_monster(_pick_spawn())
	if song_time > 45.0 and randf() < 0.3:
		_spawn_monster(_pick_spawn())


func _spawn_monster(pos: Vector3) -> void:
	# Don't double-book a spawn point.
	for m_v in monsters:
		var m: Dictionary = m_v
		if not bool(m["hit"]) and ((m["node"] as MeshInstance3D).position - pos).length() < 0.3:
			return
	var root := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.17
	body.height = 0.34
	root.mesh = body
	var col: Color = MONSTER_COLORS[randi() % MONSTER_COLORS.size()]
	var body_mat := GraphicsPolish.pbr(col, 0.1, 0.55)
	root.material_override = body_mat
	root.position = pos
	root.scale = Vector3.ZERO
	add_child(root)
	# Eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.05
		es.height = 0.1
		eye.mesh = es
		eye.material_override = GraphicsPolish.glow(Color(1, 1, 1), 0.6)
		eye.position = Vector3(side * 0.07, 0.06, 0.13)
		root.add_child(eye)
		var pupil := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.022
		ps.height = 0.044
		pupil.mesh = ps
		pupil.material_override = GraphicsPolish.pbr(Color(0.02, 0.02, 0.03), 0.0, 0.4)
		pupil.position = Vector3(side * 0.07, 0.06, 0.175)
		root.add_child(pupil)
	# Mouth.
	var mouth := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.12, 0.03, 0.02)
	mouth.mesh = mb
	mouth.material_override = GraphicsPolish.pbr(Color(0.05, 0.02, 0.05), 0.0, 0.8)
	mouth.position = Vector3(0.0, -0.07, 0.15)
	root.add_child(mouth)
	# Beat ring under the monster.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.20
	tor.outer_radius = 0.26
	ring.mesh = tor
	var ring_mat := GraphicsPolish.glow(Color(1.0, 0.5, 0.1), 1.6)
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, -0.24, 0.0)
	ring.rotation.x = PI * 0.5
	root.add_child(ring)
	monsters.append({
		"node": root, "body_mat": body_mat, "ring_mat": ring_mat,
		"age": 0.0, "hit": false, "base_y": pos.y,
	})


func _aim_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return [global_position + Vector3(0, 1.2, 0), Vector3(0, 0, -1)]
	var o := camera.project_ray_origin(mouse_pos)
	var d := camera.project_ray_normal(mouse_pos)
	return [o, d.normalized()]


func _ray_point_dist(o: Vector3, d: Vector3, p: Vector3) -> float:
	var t := (p - o).dot(d)
	if t < 0.0:
		return 1e9
	return (o + d * t - p).length()


func _try_hit() -> void:
	var ray := _aim_ray()
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var best := -1
	var best_d := HIT_RADIUS
	for i in range(monsters.size()):
		var m: Dictionary = monsters[i]
		if bool(m["hit"]):
			continue
		var node: MeshInstance3D = m["node"]
		if not is_instance_valid(node):
			continue
		var dist := _ray_point_dist(o, d, node.global_position)
		if dist < best_d:
			best_d = dist
			best = i
	if best < 0:
		return
	var m: Dictionary = monsters[best]
	var node: MeshInstance3D = m["node"]
	var age := float(m["age"])
	var label := "OK!"
	var base := 80
	var player := hit_player
	if age <= 0.30:
		label = "PERFECT!"
		base = 300
		player = perfect_player
	elif age <= 0.60:
		label = "GOOD!"
		base = 150
	m["hit"] = true
	combo += 1
	best_combo = maxi(best_combo, combo)
	var gained := base + combo * 10
	score += gained
	hits += 1
	_show_msg("%s +%d  (x%d)" % [label, gained, combo], 0.9)
	GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.7, 0.2), 20)
	if player != null:
		player.pitch_scale = 1.0 + minf(combo, 16) * 0.03
		player.play()
	node.queue_free()
	monsters.remove_at(best)


func _expire_monster(i: int, m: Dictionary) -> void:
	var node: MeshInstance3D = m["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(0.5, 0.2, 0.6), 8)
		node.queue_free()
	monsters.remove_at(i)
	if combo > 0:
		_show_msg("MISS!", 0.7)
	combo = 0
	misses += 1
	if miss_player != null:
		miss_player.play()


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := maxf(0.0, SONG_LENGTH - song_time)
	hud_label.text = "MONSTER MASH\nScore: %d   Combo: x%d\nTime: %ds   %d/%d hit" % [
		score, combo, int(left), hits, hits + misses]


func _game_over() -> void:
	state = ST_OVER
	for m_v in monsters:
		var m: Dictionary = m_v
		var node: MeshInstance3D = m["node"]
		if is_instance_valid(node):
			node.queue_free()
	monsters.clear()
	ARUpgradeKit.save_anchor("hw_monster_mash_main", global_transform)
	_show_msg("TIME!\nScore: %d\nBest combo x%d\nR: play again" % [score, best_combo], 600.0)
	if win_player != null:
		win_player.play()
	if score >= 2500:
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -2.0), 80)


func _reset_game() -> void:
	for m_v in monsters:
		var m: Dictionary = m_v
		var node: MeshInstance3D = m["node"]
		if is_instance_valid(node):
			node.queue_free()
	monsters.clear()
	song_time = 0.0
	next_beat = 0.0
	beat_count = 0
	score = 0
	combo = 0
	best_combo = 0
	hits = 0
	misses = 0
	restart_hold = 0.0
	state = ST_PLAY
	_show_msg("GET READY!", 1.2)
	ARUpgradeKit.save_anchor("hw_monster_mash_main", global_transform)


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

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the rug is the neon dance arena; chairs become haunted monster nests.
	var _morph0_rug := RoomKit.get_anchors("RUG")
	if not _morph0_rug.is_empty():
		RoomKit.morph(_morph0_rug[0], "neon")
	var _morph1_chair := RoomKit.get_anchors("CHAIR")
	if not _morph1_chair.is_empty():
		RoomKit.morph(_morph1_chair[0], "haunted")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Monsters emerge from real wall faces and lurk behind real furniture.
	_room_spawn_extra.clear()
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var wp: Vector3 = w["position"]
		var n: Vector3 = w["normal"]
		n.y = 0.0
		if n.length() < 0.01:
			continue
		n = n.normalized()
		var p: Vector3 = to_local(Vector3(wp.x, 0.0, wp.z) + n * 0.5)
		_room_spawn_extra.append(Vector3(p.x, randf_range(1.0, 1.5), p.z))
		if _room_spawn_extra.size() >= 6:
			break
	for f_v in _room_tables + _room_furniture:
		var fs := _room_furniture_lurk(1.15)
		if fs != Vector3.INF:
			_room_spawn_extra.append(fs)
		if _room_spawn_extra.size() >= 10:
			break
	# Center the stage disc on the real room floor.
	var rc := _room_bounds.get_center()
	var cur: Vector3 = global_transform * Vector3(0.0, 0.0, -2.0)
	global_position += Vector3(rc.x - cur.x, 0.0, rc.y - cur.z)


## RoomKit v0.7.0: spawn point — sometimes a real wall face or furniture lurk spot.
func _pick_spawn() -> Vector3:
	if not _room_spawn_extra.is_empty() and randf() < 0.45:
		return _room_spawn_extra[randi() % _room_spawn_extra.size()]
	return SPAWN_POINTS[randi() % SPAWN_POINTS.size()]


## RoomKit: spot behind a random table/furniture cuboid, away from room center.
func _room_furniture_lurk(y: float) -> Vector3:
	var items: Array = _room_tables + _room_furniture
	if items.is_empty():
		return Vector3.INF
	var f: Dictionary = items[randi() % items.size()]
	var wp: Vector3 = f["position"]
	var fs: Vector3 = f["size"]
	var rc := _room_bounds.get_center()
	var away := Vector2(wp.x - rc.x, wp.z - rc.y)
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var clearance := maxf(fs.x, fs.z) * 0.5 + 0.45
	return to_local(Vector3(wp.x + away.x * clearance, y, wp.z + away.y * clearance))
