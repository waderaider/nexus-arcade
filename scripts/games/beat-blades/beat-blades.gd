## BeatBladesGame.gd - "Beat Blades": rhythm slicing game.
## Glowing red/blue notes fly toward the player on a beat grid (default 120
## BPM, +/- keys adjust). Click or swipe across a note while it is inside the
## glowing hit zone to slice it for score + combo. Missing resets the combo.
## Every 8-hit streak raises BPM slightly; 3 misses in a row lowers it.
## Upgraded: glow note/zone materials, three-point light rig, slice sparks,
## note trails, ambient motes, styled HUD label, XR pinch slicing, spatial
## anchor persistence.
## Desktop/mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D
class_name BeatBladesGame

const LANES: Array[float] = [-0.7, 0.0, 0.7]
const ROWS: Array[float] = [1.1, 1.55]
const SPAWN_Z := -7.0
const ZONE_Z := -0.9
const MISS_Z := 1.2
const ZONE_HALF := 0.55
const NOTE_RED := Color(1.0, 0.22, 0.28)
const NOTE_BLUE := Color(0.28, 0.45, 1.0)
const MIN_BPM := 80.0
const MAX_BPM := 165.0

var camera: Camera3D = null
var bpm := 120.0
var beat_timer := 0.0
var notes: Array = [] # Dictionaries: node, mat, speed, sliced
var pops: Array = [] # slice flash effects: node, t
var score := 0
var combo := 0
var max_combo := 0
var hits := 0
var misses := 0
var streak := 0
var miss_streak := 0
var beat_flash := 0.0
var zone_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var help_label: Label3D = null
var tick_player: AudioStreamPlayer = null
var hit_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var _anchor_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "beat-blades_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_zone()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, -3.0), 3.0, 40)
	tick_player = _make_player(_make_tone(1800.0, 0.05, 0.45))
	hit_player = _make_player(_make_tone(990.0, 0.12, 0.55))
	miss_player = _make_player(_make_tone(150.0, 0.25, 0.5))


func _process(delta: float) -> void:
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("beat-blades_main", global_transform)
	# Hand interaction: right-hand pinch slices at the hand pointer.
	# Mouse stays on _unhandled_input; the mouse-press gate keeps the kit's
	# mouse fallback from double-triggering.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and camera != null:
		_try_slice(camera.unproject_position(ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)))

	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		bpm = clampf(bpm + 30.0 * delta, MIN_BPM, MAX_BPM)
	elif Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		bpm = clampf(bpm - 30.0 * delta, MIN_BPM, MAX_BPM)
	if Input.is_key_pressed(KEY_R):
		_reset()

	# Beat grid.
	beat_timer += delta
	var interval := 60.0 / bpm
	while beat_timer >= interval:
		beat_timer -= interval
		_on_beat()

	# Move notes toward the player.
	var speed_now := _travel_speed()
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var node: MeshInstance3D = n["node"]
		if not is_instance_valid(node):
			notes.remove_at(i)
			continue
		node.position.z += float(n["speed"]) * delta
		node.rotate_y(delta * 2.0)
		if node.position.z > MISS_Z:
			node.queue_free()
			notes.remove_at(i)
			_on_miss()

	# Slice flash pops.
	for i in range(pops.size() - 1, -1, -1):
		var p: Dictionary = pops[i]
		var pnode: MeshInstance3D = p["node"]
		var t := float(p["t"]) - delta
		if not is_instance_valid(pnode) or t <= 0.0:
			if is_instance_valid(pnode):
				pnode.queue_free()
			pops.remove_at(i)
			continue
		p["t"] = t
		pops[i] = p
		pnode.scale = Vector3.ONE * (1.0 + (0.18 - t) * 10.0)

	# Beat pulse on the hit zone.
	beat_flash = maxf(0.0, beat_flash - delta * 3.0)
	if zone_mat != null:
		zone_mat.emission_energy_multiplier = 0.6 + beat_flash * 2.5

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_slice(mb.position)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mm := event as InputEventMouseMotion
			_try_slice(mm.position)


## Hand-tracking hook: true while the user is pinching in XR.
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, -2.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 1.5), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	# Upgraded three-point light rig; never add a second key light.
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.08, 0.12), "matte")
	add_child(floor_inst)


func _build_zone() -> void:
	var zone := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 1.4, 0.06)
	zone.mesh = box
	zone.position = Vector3(0.0, 1.3, ZONE_Z)
	zone_mat = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 0.6)
	zone_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	zone_mat.albedo_color.a = 0.18
	zone.material_override = zone_mat
	add_child(zone)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color.WHITE)
	hud_label.position = Vector3(-2.4, 2.5, 1.2)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Click / swipe notes in the zone to slice | +/- BPM | R: reset", 30, Color(0.75, 0.80, 0.90))
	help_label.position = Vector3(-2.4, 2.22, 1.2)
	help_label.pixel_size = 0.004
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	var total := hits + misses
	var acc := 100.0 * float(hits) / float(maxi(total, 1))
	var mult := 1 + combo / 8
	hud_label.text = "Score: %d   Combo: %d (x%d)   BPM: %d   Acc: %.0f%%" % [score, combo, mult, int(bpm), acc]


## Seconds for a note to travel spawn -> zone = 2 beats at current BPM.
func _travel_speed() -> float:
	return (ZONE_Z - SPAWN_Z) / (2.0 * 60.0 / bpm)


func _on_beat() -> void:
	beat_flash = 1.0
	if tick_player != null:
		tick_player.play()
	if randf() < 0.75:
		_spawn_note()


func _spawn_note() -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.32, 0.32, 0.32)
	node.mesh = box
	var col := NOTE_RED if randf() < 0.5 else NOTE_BLUE
	var mat := GraphicsPolish.glow(col, 2.0)
	node.material_override = mat
	node.add_child(GraphicsPolish.make_trail(col, 0.06))
	node.position = Vector3(LANES[randi() % LANES.size()], ROWS[randi() % ROWS.size()], SPAWN_Z)
	add_child(node)
	notes.append({"node": node, "mat": mat, "speed": _travel_speed()})


func _try_slice(screen_pos: Vector2) -> void:
	if camera == null:
		return
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var node: MeshInstance3D = n["node"]
		if not is_instance_valid(node):
			notes.remove_at(i)
			continue
		if absf(node.position.z - ZONE_Z) > ZONE_HALF:
			continue
		var sp := camera.unproject_position(node.global_position)
		if sp.distance_to(screen_pos) > 70.0:
			continue
		notes.remove_at(i)
		_on_slice_hit(n)


func _on_slice_hit(n: Dictionary) -> void:
	hits += 1
	streak += 1
	miss_streak = 0
	combo += 1
	max_combo = maxi(max_combo, combo)
	var mult := 1 + combo / 8
	score += 100 * mult
	if hit_player != null:
		hit_player.play()
	var node: MeshInstance3D = n["node"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 1.0, 1.0), 20)
		pops.append({"node": node, "t": 0.18})
	# Adaptive difficulty: hot streak speeds things up.
	if streak % 8 == 0:
		bpm = clampf(bpm + 2.0, MIN_BPM, MAX_BPM)


func _on_miss() -> void:
	misses += 1
	combo = 0
	streak = 0
	miss_streak += 1
	if miss_player != null:
		miss_player.play()
	# Adaptive difficulty: struggling slows things down.
	if miss_streak >= 3:
		miss_streak = 0
		bpm = clampf(bpm - 4.0, MIN_BPM, MAX_BPM)


func _reset() -> void:
	for n_v in notes:
		var n: Dictionary = n_v
		var node: MeshInstance3D = n["node"]
		if is_instance_valid(node):
			node.queue_free()
	notes.clear()
	for p_v in pops:
		var p: Dictionary = p_v
		var pnode: MeshInstance3D = p["node"]
		if is_instance_valid(pnode):
			pnode.queue_free()
	pops.clear()
	score = 0
	combo = 0
	max_combo = 0
	hits = 0
	misses = 0
	streak = 0
	miss_streak = 0
	bpm = 120.0
	beat_timer = 0.0


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (tick / hit blip / miss buzz).
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
