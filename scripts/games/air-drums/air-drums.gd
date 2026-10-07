## Air Drums: virtual drum kit in an arc around the player.
## Four drums (snare, tom, floor tom, kick) plus two cymbals (hi-hat, crash)
## float in an arc. In XR, strike with your hands: a fast downward hand motion
## through a drum head registers a hit, with volume scaled by strike speed.
## On desktop, click a drum to hit it. Follow-the-pattern mode shows a beat
## sequence on the HUD - hit the right drums in order to build score and combo.
## Wrong drum breaks the combo. Finishing a sequence spawns a harder one.
## R restarts the pattern and score.
extends Node3D

const STRIKE_SPEED := 1.2
const DRUM_COOLDOWN := 0.12
const PATTERN_LEN := 8

var camera: Camera3D = null
var drums: Array[Dictionary] = []
var pattern: Array[int] = []
var pattern_pos := 0
var score := 0
var combo := 0
var best_combo := 0
var level := 1
var hud_label: Label3D = null
var pattern_label: Label3D = null
var msg_label: Label3D = null
var _pulse_t := 0.0
var _anchor_t := 0.0
var prev_right := Vector3.ZERO
var prev_left := Vector3.ZERO
var have_prev := false
var msg_t := 0.0
var _audio_player: AudioStreamPlayer = null
var _audio_gen: AudioStreamGenerator = null
const AUDIO_RATE := 22050

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "air-drums_main")
	_ensure_fallback_camera()
	_ensure_light()
	_ensure_environment()
	_build_kit()
	_build_hud()
	_setup_audio()
	_new_pattern()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, -0.6), 2.5, 40)
	_apply_room_layout()


## v0.7.0: arrange the drum kit around the largest real table (else the
## room center); pattern/message HUD follows the kit. Guarded; fallback
## keeps the default arc layout.
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
	# MORPH-B (v0.7.0): table -> neon drum-rig stage (kit already seats on the big table)
	_morph_anchors("TABLE", "neon", 1)
	var cx := 0.0
	var cz := -0.9
	var best_a := 0.0
	for t_v in _room_tables:
		var t: Dictionary = t_v
		var a: float = (t["size"] as Vector3).x * (t["size"] as Vector3).z
		if a > best_a:
			best_a = a
			var lp: Vector3 = to_local(t["position"])
			cx = lp.x
			cz = lp.z
	if best_a <= 0.0:
		var c := _room_bounds.get_center()
		var lc: Vector3 = to_local(Vector3(c.x, 0.0, c.y))
		cx = lc.x
		cz = lc.z
	var delta := Vector3(cx, 0.0, cz) - Vector3(0.0, 0.0, -0.9)
	for d_v in drums:
		var d: Dictionary = d_v
		d["pos"] = (d["pos"] as Vector3) + delta
		(d["node"] as Node3D).position += delta
	if pattern_label != null:
		pattern_label.position += delta
	if msg_label != null:
		msg_label.position += delta


func _process(delta: float) -> void:
	_pulse_t += delta
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("air-drums_main", global_transform)
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0 and msg_label != null:
			msg_label.text = ""

	var xr := ARUpgradeKit.is_xr_active()
	if xr:
		_track_hands(delta)

	for d in drums:
		var cd: float = d.get("cooldown", 0.0)
		if cd > 0.0:
			d["cooldown"] = cd - delta
		var mat: StandardMaterial3D = d["mat"]
		var hot: float = d.get("heat", 0.0)
		if hot > 0.0:
			hot = maxf(0.0, hot - delta * 2.0)
			d["heat"] = hot
		var base_e: float = d["base_glow"]
		if d["idx"] == _pattern_current():
			GraphicsPolish.pulse_glow(mat, base_e + 0.8, 1.2, _pulse_t, 3.5)
		else:
			mat.emission_energy_multiplier = base_e + hot * 2.5

	if Input.is_key_pressed(KEY_R):
		_restart()

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var idx := _drum_at_mouse(mb.position)
			if idx >= 0:
				_hit_drum(idx, 0.85)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.55, 1.15)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, -0.9), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _ensure_environment() -> void:
	for c in get_children():
		if c is WorldEnvironment:
			return
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.25, 0.4)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _build_kit() -> void:
	# name, position, radius, head height, color, kind ("drum"/"cymbal"), glow, sound freq
	var defs: Array = [
		["KICK", Vector3(-0.85, 0.55, -0.85), 0.34, Color(1.0, 0.35, 0.2), "drum", 70.0],
		["SNARE", Vector3(-0.30, 0.78, -0.95), 0.27, Color(0.95, 0.85, 0.4), "drum", 160.0],
		["TOM", Vector3(0.30, 0.78, -0.95), 0.27, Color(0.3, 0.8, 1.0), "drum", 120.0],
		["FLOOR", Vector3(0.85, 0.55, -0.85), 0.32, Color(0.55, 1.0, 0.45), "drum", 95.0],
		["HIHAT", Vector3(-0.62, 1.05, -0.75), 0.24, Color(1.0, 0.85, 0.45), "cymbal", 0.0],
		["CRASH", Vector3(0.62, 1.05, -0.75), 0.28, Color(1.0, 0.75, 0.3), "cymbal", 0.0],
	]
	for i in range(defs.size()):
		var def: Array = defs[i]
		var dname: String = def[0]
		var pos: Vector3 = def[1]
		var radius: float = def[2]
		var color: Color = def[3]
		var kind: String = def[4]
		var freq: float = def[5]
		var node := MeshInstance3D.new()
		if kind == "drum":
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			cyl.height = 0.22
			node.mesh = cyl
			node.position = pos - Vector3(0, 0.11, 0)
			# Bright head on top.
			var head := MeshInstance3D.new()
			var hc := CylinderMesh.new()
			hc.top_radius = radius * 0.96
			hc.bottom_radius = radius * 0.96
			hc.height = 0.03
			head.mesh = hc
			head.material_override = GraphicsPolish.glow(Color(0.95, 0.95, 0.98), 0.5)
			head.position = Vector3(0, 0.115, 0)
			node.add_child(head)
		else:
			var plate := CylinderMesh.new()
			plate.top_radius = radius
			plate.bottom_radius = radius * 0.92
			plate.height = 0.035
			node.mesh = plate
			node.position = pos
			# Stand pole.
			var pole := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.02
			pc.bottom_radius = 0.02
			pc.height = 1.0
			pole.mesh = pc
			pole.material_override = GraphicsPolish.pbr(Color(0.3, 0.32, 0.38), 0.8, 0.35)
			pole.position = Vector3(0, -0.5, 0)
			node.add_child(pole)
		var mat := GraphicsPolish.glow(color, 1.2)
		node.material_override = mat
		add_child(node)
		drums.append({
			"idx": i, "name": dname, "node": node, "mat": mat,
			"pos": pos, "radius": radius, "color": color,
			"kind": kind, "freq": freq, "base_glow": 1.2,
			"cooldown": 0.0, "heat": 0.0,
		})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.5))
	hud_label.position = Vector3(-2.2, 2.3, -0.4)
	hud_label.pixel_size = 0.008
	add_child(hud_label)
	pattern_label = GraphicsPolish.make_label("", 56, Color(0.55, 0.95, 1.0))
	pattern_label.position = Vector3(0.0, 2.0, -1.1)
	add_child(pattern_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.6, 0.4))
	msg_label.position = Vector3(0.0, 1.55, -1.1)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("XR: strike down fast through drums | Desktop: click drums | R: restart", 36, Color(0.75, 0.8, 0.9))
	help.position = Vector3(0.0, 0.35, 0.4)
	help.pixel_size = 0.004
	add_child(help)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Score %d   Combo x%d   Lv %d" % [score, combo, level]
	if pattern_label != null:
		if pattern_pos >= pattern.size():
			pattern_label.text = "PATTERN CLEAR!"
		else:
			var seq := "NEXT: "
			for k in range(mini(5, pattern.size() - pattern_pos)):
				var d: Dictionary = drums[pattern[pattern_pos + k]]
				if k > 0:
					seq += " > "
				seq += d["name"]
			pattern_label.text = seq


func _pattern_current() -> int:
	if pattern_pos < pattern.size():
		return pattern[pattern_pos]
	return -1


func _new_pattern() -> void:
	pattern.clear()
	pattern_pos = 0
	var length := PATTERN_LEN + (level - 1) * 2
	for i in range(length):
		pattern.append(randi_range(0, drums.size() - 1))
	_update_hud()


func _restart() -> void:
	score = 0
	combo = 0
	best_combo = 0
	level = 1
	_new_pattern()
	_show_msg("Pattern restarted")


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text
	msg_t = 1.6


func _track_hands(delta: float) -> void:
	var r := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.6)
	var l := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_LEFT, 1.6)
	if have_prev and delta > 0.0001:
		_check_strike(prev_right, (r - prev_right) / delta)
		_check_strike(prev_left, (l - prev_left) / delta)
	prev_right = r
	prev_left = l
	have_prev = true


func _check_strike(pos: Vector3, vel: Vector3) -> void:
	if vel.y > -STRIKE_SPEED:
		return
	for i in range(drums.size()):
		var d: Dictionary = drums[i]
		var dp: Vector3 = d["pos"]
		var radius: float = d["radius"]
		var dxz := Vector2(pos.x - dp.x, pos.z - dp.z).length()
		if dxz < radius + 0.08 and pos.y < dp.y + 0.30 and pos.y > dp.y - 0.10:
			if float(d["cooldown"]) <= 0.0:
				var volume := clampf(-vel.y / 4.5, 0.25, 1.0)
				_hit_drum(i, volume)
			break


func _drum_at_mouse(screen_pos: Vector2) -> int:
	if camera == null:
		return -1
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best := -1
	var best_t := 1e9
	for i in range(drums.size()):
		var d: Dictionary = drums[i]
		var dp: Vector3 = d["pos"]
		var radius: float = d["radius"]
		if absf(dir.y) < 0.0001:
			continue
		var t := (dp.y - origin.y) / dir.y
		if t < 0.0 or t > best_t:
			continue
		var p: Vector3 = origin + dir * t
		if Vector2(p.x - dp.x, p.z - dp.z).length() < radius:
			best = i
			best_t = t
	return best


func _hit_drum(idx: int, volume: float) -> void:
	var d: Dictionary = drums[idx]
	d["cooldown"] = DRUM_COOLDOWN
	d["heat"] = 1.0
	var dp: Vector3 = d["pos"]
	var color: Color = d["color"]
	GraphicsPolish.spawn_sparks(self, dp + Vector3(0, 0.15, 0), color, int(8 + volume * 20.0))
	_play_hit(d, volume)
	# Pattern scoring.
	var expected := _pattern_current()
	if expected == idx:
		combo += 1
		best_combo = maxi(best_combo, combo)
		score += 10 * combo * level
		pattern_pos += 1
		if pattern_pos >= pattern.size():
			level += 1
			GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.4, -0.8), 60)
			_show_msg("Level %d!" % level)
			_new_pattern()
	else:
		if combo > 3:
			_show_msg("Combo lost!")
		combo = 0
	_update_hud()


func _setup_audio() -> void:
	# One shared generator stream; hits push synthesized frames into it.
	_audio_gen = AudioStreamGenerator.new()
	_audio_gen.mix_rate = AUDIO_RATE
	_audio_gen.buffer_length = 0.5
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = _audio_gen
	add_child(_audio_player)
	_audio_player.play()


func _play_hit(d: Dictionary, volume: float) -> void:
	if _audio_player == null:
		return
	var kind: String = d["kind"]
	var samples: PackedFloat32Array
	if kind == "cymbal":
		samples = _make_noise_samples(0.5, volume)
	else:
		samples = _make_drum_samples(float(d["freq"]), 0.28, volume)
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in range(samples.size()):
		frames[i] = Vector2(samples[i], samples[i])
	var playback := _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		playback.push_buffer(frames)


func _make_drum_samples(freq: float, dur: float, volume: float) -> PackedFloat32Array:
	var n := int(AUDIO_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var t := float(i) / AUDIO_RATE
		var env := exp(-t * 14.0)
		var tone := sin(TAU * freq * t) * env
		var noise := (rng.randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.35
		samples[i] = clampf((tone + noise) * volume, -1.0, 1.0)
	return samples


func _make_noise_samples(dur: float, volume: float) -> PackedFloat32Array:
	var n := int(AUDIO_RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var t := float(i) / AUDIO_RATE
		var env := exp(-t * 7.0)
		samples[i] = clampf((rng.randf() * 2.0 - 1.0) * env * volume, -1.0, 1.0)
	return samples
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
