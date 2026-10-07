## HwZombieDefense - "Zombie Defense": zombies shamble in from the room edges
## toward you. Point and pinch-tap (or click) to zap them before they reach
## you. Survive 90 seconds. You have 3 hearts; each zombie that reaches you
## costs one heart. +10 score per zap. R restarts; hold pinch 1s on the end
## screen to play again.
extends Node3D

const ROUND_TIME := 90.0
const START_HEARTS := 3
const BASE_SPAWN := 2.4
const SPAWN_RADIUS := 3.1
const PICK_RADIUS := 0.5
const REACH_DIST := 0.55
const ZAP_SCORE := 10

const ST_PLAY := 0
const ST_OVER := 1

# v0.7.0 KayKit: animated skeleton zombies + gravemarker props
# (CC0, KayKit Character Pack Skeletons + Halloween Bits).
const MODEL_DIR := "res://assets/models/hw_zombie_defense/"
const ZOMBIE_MODELS := [
	"res://assets/models/hw_zombie_defense/Skeleton_Minion.glb",
	"res://assets/models/hw_zombie_defense/Skeleton_Rogue.glb",
	"res://assets/models/hw_zombie_defense/Skeleton_Mage.glb",
]
const GRAVE_MODELS := [
	"res://assets/models/hw_zombie_defense/gravemarker_A.gltf",
	"res://assets/models/hw_zombie_defense/gravestone.gltf",
]
const ZOMBIE_MODEL_SCALE := 0.8 # models are 2.17m tall; zombies ~1.74m

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var elapsed := 0.0
var score := 0
var hearts := START_HEARTS
var zombies: Array = []
var spawn_timer := 1.2
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var lantern_mat: StandardMaterial3D = null
var zap_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var hurt_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var lose_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0

# v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_ready := false
var _barricades: Array = [] # tombstones, repositioned as barricades at furniture


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_arena()
	_build_hud()
	zap_player = _make_player(_make_tone(1250.0, 0.14, 0.5))
	miss_player = _make_player(_make_tone(300.0, 0.10, 0.30))
	hurt_player = _make_player(_make_tone(150.0, 0.40, 0.60))
	win_player = _make_player(_make_tone(880.0, 0.50, 0.50))
	lose_player = _make_player(_make_tone(190.0, 0.80, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_zombie_defense_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, -1.0), 2.5, 36)
	_apply_room_layout() # v0.7.0: zombies emerge from real walls, barricades at furniture (no-op w/o room data).


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
	camera.position = Vector3(0.0, 1.7, 2.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -2.5), Vector3.UP)
	camera.current = true


func _build_arena() -> void:
	# Dark ground.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.02, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.06, 0.07, 0.05), 0.0, 0.95)
	add_child(floor_inst)
	# Jack-o-lantern beside the player.
	var lantern := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 0.22
	ls.height = 0.44
	lantern.mesh = ls
	lantern.position = Vector3(1.1, 0.22, 0.6)
	lantern_mat = GraphicsPolish.glow(Color(1.0, 0.55, 0.1), 1.6)
	lantern.material_override = lantern_mat
	add_child(lantern)
	GraphicsPolish.make_point_light(self, Vector3(1.1, 0.5, 0.6), Color(1.0, 0.55, 0.15), 1.2, 4.0)
	# Crooked tombstones for atmosphere (v0.7.0 KayKit models, procedural fallback).
	var stone_mat := GraphicsPolish.pbr(Color(0.45, 0.45, 0.48), 0.0, 0.9)
	for i in range(5):
		var a := -2.0 + float(i) * 1.0
		var stone_pos := Vector3(sin(a) * 2.3, 0.0, -cos(a) * 2.3 - 0.5)
		var marker := ModelLib.spawn(GRAVE_MODELS[i % GRAVE_MODELS.size()], self, stone_pos)
		if marker != null:
			marker.scale = Vector3.ONE * (0.7 if i % 2 == 0 else 0.55)
			marker.rotation.z = randf_range(-0.12, 0.12)
			marker.rotation.y = randf() * TAU
			_barricades.append(marker)
		else:
			var stone := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.4, 0.65, 0.12)
			stone.mesh = sb
			stone.position = stone_pos + Vector3(0.0, 0.3, 0.0)
			stone.rotation.z = randf_range(-0.12, 0.12)
			stone.material_override = stone_mat
			add_child(stone)
			_barricades.append(stone) # v0.7.0: tracked so they can become furniture barricades


func _room_center3() -> Vector3:
	var c := _room_bounds.get_center()
	return Vector3(c.x, 0.0, c.y)


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the door is the haunted breach gate zombies pour through; windows show haunted vistas.
	var _morph0_door := RoomKit.get_anchors("DOOR")
	if not _morph0_door.is_empty():
		RoomKit.morph(_morph0_door[0], "haunted")
	var _morph1_window := RoomKit.get_anchors("WINDOW")
	if not _morph1_window.is_empty():
		RoomKit.morph(_morph1_window[0], "haunted")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_ready = true
	# Barricades: ring the tombstones around real furniture pieces.
	var furn := _room_tables + _room_furniture
	if not furn.is_empty():
		for i in _barricades.size():
			var f: Dictionary = furn[i % furn.size()]
			var c: Vector3 = f["position"]
			var s: Vector3 = f["size"]
			var ring_a := TAU * float(i) / float(_barricades.size())
			var bp := c + Vector3(cos(ring_a), 0.0, sin(ring_a)) * (maxf(s.x, s.z) * 0.5 + 0.45)
			# Procedural stones are centered (y=0.3); KayKit models sit on the floor (y=0).
			var bnode := _barricades[i] as Node3D
			if bnode != null:
				bp.y = 0.3 if bnode is MeshInstance3D else 0.0
				bnode.position = to_local(bp)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("ZOMBIE DEFENSE", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.3, 2.6, -1.6)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Click / pinch to zap zombies - don't let them reach you!  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.3, 2.05, -1.6)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.9, -2.6)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	var hp := ""
	for i in range(hearts):
		hp += "#"
	hud_label.text = "ZOMBIE DEFENSE\nTime: %ds   Score: %d\nHP: %s" % [int(ceil(time_left)), score, hp]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_zombie_defense_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if lantern_mat != null:
		GraphicsPolish.pulse_glow(lantern_mat, 1.4, 0.8, _time, 3.0)
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_pinch_hold += delta
			if _pinch_hold >= 1.0:
				_pinch_hold = 0.0
				_reset_game()
		else:
			_pinch_hold = 0.0
		_update_hud()
		return
	# ST_PLAY.
	elapsed += delta
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over(true)
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(0.8, BASE_SPAWN - elapsed * 0.015)
		_spawn_zombie()
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
			or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
		_zap()
	_step_zombies(delta)
	_update_hud()


func _spawn_zombie() -> void:
	var root := Node3D.new()
	# With room data zombies emerge from real wall faces (or lurk behind
	# furniture); otherwise spawn across the front 270-degree arc as before.
	var spawn_pos: Vector3
	if _room_ready and not _room_walls.is_empty() and randf() < 0.7:
		var w: Dictionary = _room_walls[randi() % _room_walls.size()]
		var inward: Vector3 = _room_center3() - (w["position"] as Vector3)
		inward.y = 0.0
		spawn_pos = to_local((w["position"] as Vector3) + inward.normalized() * 0.6)
		spawn_pos.y = 0.0
	elif _room_ready and not _room_furniture.is_empty() and randf() < 0.5:
		var f: Dictionary = _room_furniture[randi() % _room_furniture.size()]
		var fs: Vector3 = f["size"]
		var away: Vector3 = (f["position"] as Vector3) - _room_center3()
		away.y = 0.0
		var lp := to_local((f["position"] as Vector3) + away.normalized() * (maxf(fs.x, fs.z) * 0.5 + 0.4))
		spawn_pos = Vector3(lp.x, 0.0, lp.z)
	else:
		var a := randf_range(-2.35, 2.35)
		spawn_pos = Vector3(sin(a) * SPAWN_RADIUS, 0.0, -cos(a) * SPAWN_RADIUS - 0.5)
	root.position = spawn_pos
	add_child(root)
	root.look_at(Vector3(0.0, 0.0, -0.5), Vector3.UP)
	var arms: Array = []
	# v0.7.0 KayKit: real animated skeleton zombie; procedural shambler is the fallback.
	var zmodel := ModelLib.spawn(ZOMBIE_MODELS[randi() % ZOMBIE_MODELS.size()], root, Vector3.ZERO)
	if zmodel != null:
		zmodel.scale = Vector3.ONE * ZOMBIE_MODEL_SCALE
		_play_model_anim(zmodel, "Walking_A")
	else:
		var skin := GraphicsPolish.pbr(Color(0.38, 0.62, 0.30), 0.0, 0.8)
		var cloth := GraphicsPolish.pbr(Color(0.16, 0.14, 0.20), 0.0, 0.9)
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 0.9
		body.mesh = cap
		body.position = Vector3(0.0, 0.75, 0.0)
		body.material_override = cloth
		root.add_child(body)
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.20
		hs.height = 0.40
		head.mesh = hs
		head.position = Vector3(0.0, 1.42, 0.0)
		head.material_override = skin
		root.add_child(head)
		for ex in [-0.08, 0.08]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.045
			es.height = 0.09
			eye.mesh = es
			eye.position = Vector3(ex, 1.47, -0.16)
			eye.material_override = GraphicsPolish.glow(Color(1.0, 0.15, 0.10), 2.2)
			root.add_child(eye)
		for ax in [-0.30, 0.30]:
			var arm := MeshInstance3D.new()
			var ac := CapsuleMesh.new()
			ac.radius = 0.07
			ac.height = 0.55
			arm.mesh = ac
			arm.position = Vector3(ax, 1.05, -0.30)
			arm.rotation_degrees = Vector3(75.0, 0.0, 0.0)
			arm.material_override = skin
			root.add_child(arm)
			arms.append(arm)
	zombies.append({
		"node": root,
		"speed": randf_range(0.35, 0.55) * (1.0 + elapsed / 75.0),
		"phase": randf() * TAU,
		"arms": arms,
	})


## v0.7.0 KayKit: play a named animation on a spawned model, guarded.
func _play_model_anim(inst: Node, anim_name: String) -> void:
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap := players[0] as AnimationPlayer
	if ap != null and ap.has_animation(anim_name):
		ap.play(anim_name)


func _step_zombies(delta: float) -> void:
	var target := Vector3(0.0, 0.0, -0.5)
	for i in range(zombies.size() - 1, -1, -1):
		var z: Dictionary = zombies[i]
		var node: Node3D = z["node"]
		if not is_instance_valid(node):
			zombies.remove_at(i)
			continue
		var flat := Vector2(target.x - node.position.x, target.z - node.position.z)
		var dist := flat.length()
		if dist < REACH_DIST:
			# Reached the player: lose a heart.
			GraphicsPolish.spawn_sparks(self, node.position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.2, 0.2), 20)
			node.queue_free()
			zombies.remove_at(i)
			hearts -= 1
			if hurt_player != null:
				hurt_player.play()
			if hearts <= 0:
				_game_over(false)
				return
			continue
		var speed: float = z["speed"]
		# AILib: seek the player with a wandering shamble instead of a straight line.
		node.position += AILib.follow(node, target, delta, speed)
		node.position += AILib.wander(node, delta, 0.4)
		# Shamble: bob and sway.
		var phase: float = z["phase"]
		node.position.y = 0.05 * absf(sin(_time * 6.0 + phase))
		node.rotation.z = 0.08 * sin(_time * 3.0 + phase)
		for arm_v in z["arms"]:
			var arm: MeshInstance3D = arm_v
			arm.rotation.x = deg_to_rad(75.0) + 0.25 * sin(_time * 5.0 + phase)


func _pick_zombie(origin: Vector3, dir: Vector3) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in range(zombies.size()):
		var z: Dictionary = zombies[i]
		var node: Node3D = z["node"]
		if not is_instance_valid(node):
			continue
		var to: Vector3 = node.global_position + Vector3(0.0, 0.9, 0.0) - origin
		var t := to.dot(dir)
		if t < 0.0 or t > 9.0:
			continue
		var perp := (to - dir * t).length()
		if perp < best_d:
			best_d = perp
			best = i
	return best


func _zap() -> void:
	if state != ST_PLAY or camera == null:
		return
	var origin: Vector3
	var dir: Vector3
	if ARUpgradeKit.is_xr_active():
		var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		origin = r[0]
		dir = r[1]
	else:
		var mp := get_viewport().get_mouse_position()
		origin = camera.project_ray_origin(mp)
		dir = camera.project_ray_normal(mp)
	var idx := _pick_zombie(origin, dir)
	if idx >= 0:
		var z: Dictionary = zombies[idx]
		var node: Node3D = z["node"]
		GraphicsPolish.spawn_sparks(self, node.global_position + Vector3(0.0, 1.0, 0.0), Color(0.6, 1.0, 0.4), 28)
		node.queue_free()
		zombies.remove_at(idx)
		score += ZAP_SCORE
		if zap_player != null:
			zap_player.play()
	else:
		if miss_player != null:
			miss_player.play()


func _game_over(won: bool) -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_zombie_defense_main", global_transform)
	if won:
		_show_msg("YOU SURVIVED!\nScore: %d\nR or hold pinch 1s to play again" % score)
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -1.5), 80)
		if win_player != null:
			win_player.play()
	else:
		_show_msg("THE HORDE GOT YOU!\nScore: %d\nR or hold pinch 1s to retry" % score)
		if lose_player != null:
			lose_player.play()


func _reset_game() -> void:
	for z_v in zombies:
		var z: Dictionary = z_v
		var node: Node3D = z["node"]
		if is_instance_valid(node):
			node.queue_free()
	zombies.clear()
	state = ST_PLAY
	time_left = ROUND_TIME
	elapsed = 0.0
	score = 0
	hearts = START_HEARTS
	spawn_timer = 1.2
	_pinch_hold = 0.0
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_zombie_defense_main", global_transform)


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
