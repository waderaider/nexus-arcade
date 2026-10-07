## holo-theremin.gd -- NEXUS ARCADE: hand-distance theremin.
## A glowing orb sings: your hand's HEIGHT above the floor sets the pitch,
## horizontal distance from center sets the volume. Pinch (or click / W)
## toggles the waveform: sine, square, saw -- all synthesized in code with
## AudioStreamWAV, no audio files needed.
## Song mode: notes scroll on the HUD; hold the matching pitch to score.
## Desktop fallback: mouse Y = pitch, mouse X = volume. T toggles song mode.
extends Node3D

const BASE_FREQ := 441.0
const SAMPLE_RATE := 44100
const MIN_FREQ := 130.81 # C3
const OCTAVES := 3.0
const MIN_H := 0.2
const MAX_H := 2.0
const VOL_RADIUS := 1.5
const CENTER := Vector3(0, 0, -1.0)

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const WAVE_NAMES := ["sine", "square", "saw"]

# Twinkle Twinkle: [freq, beats].
const SONG := [
	[261.63, 1.0], [261.63, 1.0], [392.00, 1.0], [392.00, 1.0],
	[440.00, 1.0], [440.00, 1.0], [392.00, 2.0],
	[349.23, 1.0], [349.23, 1.0], [329.63, 1.0], [329.63, 1.0],
	[293.66, 1.0], [293.66, 1.0], [261.63, 2.0],
]

var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}

var player: AudioStreamPlayer = null
var waves: Array = []
var wave_idx := 0

var orb: MeshInstance3D = null
var orb_mat: StandardMaterial3D = null
var rings: Array = []

var freq := 440.0
var vol := 0.0
var score := 0
var song_on := true
var song_idx := 0
var note_time := 0.0
var hold_time := 0.0
var songs_done := 0

var hud_label: Label3D = null
var song_label: Label3D = null
var help_label: Label3D = null

## RoomKit v0.7.0: cached room layout (world space; converted to local at use).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _room_anchored := false


func _ready() -> void:
	_room_anchored = ARUpgradeKit.apply_anchor(self, "holo-theremin_main")
	_build_camera()
	_build_environment()
	GraphicsPolish.make_light_rig(self)
	_build_orb()
	_build_rings()
	_build_audio()
	_build_ui()
	GraphicsPolish.spawn_ambient_motes(self, CENTER + Vector3(0, 1.2, 0), 2.0, 30)
	_apply_room_layout()


func _build_camera() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			return
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 1.7, 2.2)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.1, -1.0), Vector3.UP)


func _build_environment() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.40, 0.60)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)

	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.0, 0.1, 8.0)
	floor_mi.mesh = fb
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.09, 0.08, 0.16), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _build_orb() -> void:
	orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	orb.mesh = sm
	orb_mat = GraphicsPolish.glow(Color(0.4, 0.8, 1.0), 2.0)
	orb.material_override = orb_mat
	orb.position = CENTER + Vector3(0, 1.2, 0)
	add_child(orb)
	orb.add_child(GraphicsPolish.make_trail(Color(0.4, 0.8, 1.0), 0.06))
	GraphicsPolish.make_point_light(orb, Vector3.ZERO, Color(0.5, 0.8, 1.0), 1.2, 3.0)


func _build_rings() -> void:
	# Octave guide rings: C3..C6.
	for o in 4:
		var f := MIN_FREQ * pow(2.0, float(o))
		var y := _freq_to_height(f)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.48
		tm.outer_radius = 0.52
		ring.mesh = tm
		ring.material_override = GraphicsPolish.glow(Color(0.5, 0.5, 0.9), 0.8)
		ring.position = CENTER + Vector3(0, y, 0)
		add_child(ring)
		rings.append(ring)
		var lab := GraphicsPolish.make_label(_note_name(f), 48, Color(0.7, 0.7, 1.0))
		lab.position = CENTER + Vector3(0.75, y, 0)
		add_child(lab)


func _build_ui() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(0.9, 0.95, 1.0))
	hud_label.position = Vector3(-2.8, 2.5, -1.0)
	add_child(hud_label)
	song_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.9, 0.6))
	song_label.position = Vector3(2.8, 2.5, -1.0)
	add_child(song_label)
	help_label = GraphicsPolish.make_label(
		"Hand height: pitch | distance: volume\nPinch / click / W: waveform\nT: song mode on/off",
		48, Color(0.7, 0.8, 1.0))
	help_label.position = Vector3(0.0, 0.35, -1.6)
	add_child(help_label)


func _freq_to_height(f: float) -> float:
	var frac := clampf(log(f / MIN_FREQ) / log(2.0) / OCTAVES, 0.0, 1.0)
	return lerpf(MIN_H, MAX_H, frac)


func _height_to_freq(h: float) -> float:
	var frac := clampf((h - MIN_H) / (MAX_H - MIN_H), 0.0, 1.0)
	return MIN_FREQ * pow(2.0, frac * OCTAVES)


func _note_name(f: float) -> String:
	var midi := int(round(12.0 * log(f / 440.0) / log(2.0))) + 69
	var n: String = NOTE_NAMES[posmod(midi, 12)]
	return "%s%d" % [n, midi / 12 - 1]


# --- Synthesized audio ------------------------------------------------------

func _make_wave(kind: String) -> AudioStreamWAV:
	var per := int(SAMPLE_RATE / BASE_FREQ) # 100 samples per cycle
	var cycles := 100
	var total := per * cycles
	var data := PackedByteArray()
	data.resize(total * 2)
	var amp := 30000.0
	if kind == "square":
		amp = 18000.0
	elif kind == "saw":
		amp = 21000.0
	for i in total:
		var ph := float(i % per) / float(per)
		var v := 0.0
		match kind:
			"sine":
				v = sin(ph * TAU)
			"square":
				v = 1.0 if ph < 0.5 else -1.0
			"saw":
				v = ph * 2.0 - 1.0
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * amp))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = total
	return w


func _build_audio() -> void:
	for kind in WAVE_NAMES:
		waves.append(_make_wave(kind))
	player = AudioStreamPlayer.new()
	player.stream = waves[wave_idx]
	player.volume_db = -60.0
	add_child(player)
	player.play()


func _cycle_waveform() -> void:
	wave_idx = (wave_idx + 1) % waves.size()
	player.stream = waves[wave_idx]
	player.play()
	GraphicsPolish.spawn_sparks(self, orb.global_position, Color(0.5, 1.0, 0.8), 20)
	ARUpgradeKit.save_anchor("holo-theremin_main", global_transform)


# --- Game loop --------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	_poll_waveform_toggle()
	_update_instrument(delta)
	if song_on:
		_update_song(delta)
	_update_ui()
	_update_orb_fx()


func _poll_keys() -> void:
	_key_edge(KEY_W, _cycle_waveform)
	_key_edge(KEY_T, _toggle_song)


func _key_edge(keycode: int, action: Callable) -> void:
	var down := Input.is_key_pressed(keycode)
	var was: bool = _prev_keys.get(keycode, false)
	if down and not was:
		action.call()
	_prev_keys[keycode] = down


func _toggle_song() -> void:
	song_on = not song_on
	if song_on:
		song_idx = 0
		note_time = 0.0
		hold_time = 0.0


func _poll_waveform_toggle() -> void:
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		# On desktop a plain click is not a waveform toggle (mouse already
		# drives pitch/volume); require XR pinch or the W key there.
		if ARUpgradeKit.is_xr_active():
			_cycle_waveform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_cycle_waveform()


func _update_instrument(_delta: float) -> void:
	if ARUpgradeKit.is_xr_active():
		var p := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.2)
		freq = _height_to_freq(p.y)
		var hd := Vector2(p.x - CENTER.x, p.z - CENTER.z).length()
		vol = clampf(1.0 - hd / VOL_RADIUS, 0.0, 1.0)
		orb.global_position = p
	else:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var y_frac := 1.0 - clampf(mp.y / maxf(vs.y, 1.0), 0.0, 1.0)
		freq = MIN_FREQ * pow(2.0, y_frac * OCTAVES)
		vol = clampf(mp.x / maxf(vs.x, 1.0), 0.0, 1.0)
		orb.position = CENTER + Vector3(0, _freq_to_height(freq), 0)
	player.pitch_scale = freq / BASE_FREQ
	player.volume_db = linear_to_db(maxf(vol, 0.001))
	var hue := clampf(log(freq / MIN_FREQ) / log(2.0) / OCTAVES, 0.0, 1.0)
	var c := Color.from_hsv(hue * 0.75, 0.85, 1.0)
	orb_mat.albedo_color = c
	orb_mat.emission = c


func _update_orb_fx() -> void:
	GraphicsPolish.pulse_glow(orb_mat, 1.6, 0.9, _time, 2.0 + vol * 6.0)
	var s := 1.0 + vol * 0.6
	orb.scale = Vector3(s, s, s)


func _update_song(delta: float) -> void:
	if song_idx >= SONG.size():
		songs_done += 1
		song_idx = 0
		note_time = 0.0
		hold_time = 0.0
		GraphicsPolish.spawn_confetti(self, orb.global_position, 40)
		ARUpgradeKit.save_anchor("holo-theremin_main", global_transform)
		return
	var target: float = SONG[song_idx][0]
	note_time += delta
	if absf(freq - target) / target < 0.05 and vol > 0.05:
		hold_time += delta
	else:
		hold_time = 0.0
	if hold_time >= 0.35:
		score += 1
		song_idx += 1
		note_time = 0.0
		hold_time = 0.0
		GraphicsPolish.spawn_sparks(self, orb.global_position, Color(1.0, 0.9, 0.4), 14)
	elif note_time >= 5.0:
		# Missed the note; move on without scoring.
		song_idx += 1
		note_time = 0.0
		hold_time = 0.0


func _song_text() -> String:
	if not song_on:
		return "SONG MODE: OFF (T)"
	var parts: Array = []
	for k in 5:
		var i := song_idx + k
		if i >= SONG.size():
			break
		var nm := _note_name(SONG[i][0])
		parts.append((">> " if k == 0 else "") + nm)
	return "SONG: Twinkle Twinkle\n" + "\n".join(parts)


func _update_ui() -> void:
	var bar := "|".repeat(int(vol * 12.0)) + "-".repeat(12 - int(vol * 12.0))
	hud_label.text = "HOLO THEREMIN\nWave: %s\nPitch: %.0f Hz (%s)\nVol: [%s]" % [
		WAVE_NAMES[wave_idx], freq, _note_name(freq), bar]
	song_label.text = "%s\n\nMatched: %d\nSongs: %d" % [_song_text(), score, songs_done]

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the rug is the neon performance arena; lamps become arcane lanterns framing the player.
	var _morph0_rug := RoomKit.get_anchors("RUG")
	if not _morph0_rug.is_empty():
		RoomKit.morph(_morph0_rug[0], "neon")
	var _morph1_lamp := RoomKit.get_anchors("LAMP")
	if not _morph1_lamp.is_empty():
		RoomKit.morph(_morph1_lamp[0], "arcane")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Center the play field on the real room floor (skip a restored anchor).
	if not _room_anchored:
		var rc := _room_bounds.get_center()
		var cur: Vector3 = global_transform * Vector3(CENTER.x, 0.0, CENTER.z)
		global_position += Vector3(rc.x - cur.x, 0.0, rc.y - cur.z)
	# Frame the play field with glowing markers at the two largest walls.
	var walls := _room_walls_by_area()
	for i in mini(2, walls.size()):
		var w: Dictionary = walls[i]
		var wp: Vector3 = w["position"]
		var n: Vector3 = w["normal"]
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		m.mesh = sm
		m.material_override = GraphicsPolish.glow(Color(0.5, 0.5, 0.9), 1.6)
		m.position = to_local(Vector3(wp.x, 0.12, wp.z) + n * 0.45)
		add_child(m)


## RoomKit: walls sorted by face area, largest first.
func _room_walls_by_area() -> Array:
	var walls := _room_walls.duplicate()
	walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Vector2 = a["size"]
		var sb: Vector2 = b["size"]
		return sa.x * sa.y > sb.x * sb.y)
	return walls
