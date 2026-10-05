## ar-karaoke.gd -- NEXUS ARCADE: karaoke stage for Quest 3.
## Lyrics float in 3D space (Label3D), the current line is highlighted and
## words light up on a synthesized beat timeline (no real audio input).
## Hold click / pinch to "sing": hitting word timing windows scores
## Perfect / Good / Miss with a combo multiplier and a final S/A/B/C grade.
## Three built-in lyric sets; pick with 1/2/3 keys or by clicking a song card.
extends Node3D

const WORD_BASE := 0.20        # seconds per word, base
const WORD_PER_CHAR := 0.05    # extra seconds per character
const WORD_GAP := 0.06
const LINE_GAP := 1.0
const PERFECT_WINDOW := 0.15   # |sing_start - word_start| for Perfect

const LYRIC_Y := 2.45
const LINE_SPACING := 0.78
const WORD_PX := 0.0115

const COL_UPCOMING := Color(1.0, 1.0, 1.0)
const COL_FUTURE := Color(0.45, 0.48, 0.60)
const COL_CURRENT := Color(1.0, 0.85, 0.25)
const COL_PERFECT := Color(0.35, 1.0, 0.45)
const COL_GOOD := Color(0.35, 0.85, 1.0)
const COL_MISS := Color(0.55, 0.22, 0.22)


var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}
var _anchor_t := 0.0

var _state := "select"          # "select" | "playing" | "results"
var _songs: Array = []
var _song_idx := 0
var _words: Array = []          # word dicts: line, wi, text, start, end, judged, sung, sing_start, label
var _total_dur := 1.0
var _song_time := 0.0
var _cur_line := 0

var _singing := false
var _space_held := false

var _score := 0
var _combo := 0
var _max_combo := 0
var _perfects := 0
var _goods := 0
var _misses := 0

var _hud: Label3D = null
var _title_label: Label3D = null
var _popup: Label3D = null
var _popup_t := 0.0
var _prog_bg: MeshInstance3D = null
var _prog_fill: MeshInstance3D = null
var _prog_label: Label3D = null
var _pitch_marker: MeshInstance3D = null
var _mic: MeshInstance3D = null
var _mic_mat: StandardMaterial3D = null
var _disco: MeshInstance3D = null
var _cards: Array = []          # card MeshInstance3D per song
var _results_node: Node3D = null

var _blip: AudioStreamPlayer = null


func _ready() -> void:
	# Restore the persisted stage placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "ar-karaoke_main")
	_songs = _build_songs()
	_build_environment()
	_build_song_cards()
	_build_ui()
	_blip = AudioStreamPlayer.new()
	add_child(_blip)
	# Stage dust motes.
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 2.2, -1.2), 3.0, 50)
	# Three-point light rig, unless the scene already has a key light.
	var _has_dir := false
	for c in get_children():
		if c is DirectionalLight3D:
			_has_dir = true
	if not _has_dir:
		GraphicsPolish.make_light_rig(self, 1.0)


# ------------------------------------------------------------------ songs

func _build_songs() -> Array:
	return [
		{
			"title": "Neon Skyway",
			"tag": "Upbeat synth-pop - 118 BPM",
			"lines": [
				["Headlights", "paint", "the", "midnight", "blue"],
				["Engine", "hums", "a", "tune", "for", "you"],
				["We", "chase", "the", "city", "lights", "below"],
				["Where", "the", "neon", "rivers", "flow"],
				["Turn", "it", "up", "and", "let", "it", "go"],
				["The", "skyway", "is", "calling", "home"],
				["Sing", "it", "loud", "into", "the", "night"],
				["Everything", "is", "gonna", "be", "alright"],
			],
		},
		{
			"title": "Gravity Waltz",
			"tag": "Dreamy ballad - 92 BPM",
			"lines": [
				["Slowly", "we", "drift", "above", "the", "ground"],
				["In", "this", "quiet", "we", "are", "found"],
				["Hold", "my", "hand", "and", "close", "your", "eyes"],
				["We", "are", "dancing", "through", "the", "skies"],
				["One", "two", "three", "the", "world", "spins", "slow"],
				["Gravity", "has", "let", "us", "go"],
				["Floating", "free", "in", "silver", "light"],
				["Waltzing", "on", "through", "endless", "night"],
			],
		},
		{
			"title": "Pixel Dawn",
			"tag": "Chiptune energy - 132 BPM",
			"lines": [
				["Boot", "it", "up", "the", "morning", "glows"],
				["Through", "the", "static", "color", "flows"],
				["Every", "pixel", "finds", "its", "place"],
				["Sunrise", "renders", "on", "my", "face"],
				["Press", "start", "on", "a", "brand", "new", "day"],
				["Yesterday", "has", "faded", "away"],
				["High", "score", "dreams", "in", "golden", "hue"],
				["This", "new", "level", "starts", "with", "you"],
			],
		},
	]


func _compute_timeline(song: Dictionary) -> void:
	_words.clear()
	var t := 1.5  # count-in before the first word
	var lines: Array = song["lines"]
	for li in lines.size():
		var line: Array = lines[li]
		for wi in line.size():
			var text: String = line[wi]
			var dur := WORD_BASE + WORD_PER_CHAR * float(text.length())
			_words.append({
				"line": li, "wi": wi, "text": text,
				"start": t, "end": t + dur,
				"judged": false, "sung": false, "sing_start": 0.0,
				"label": null, "result": "",
			})
			t += dur + WORD_GAP
		t += LINE_GAP
	_total_dur = t + 1.0


func _word_width(text: String) -> float:
	return float(text.length()) * WORD_PX * 5.6


# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 2.3, 5.4)
		add_child(cam)
		cam.look_at(Vector3(0.0, 1.9, -1.0), Vector3.UP)

	# (Key light comes from the GraphicsPolish light rig in _ready.)

	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.40, 0.60)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)

	# Stage floor.
	_box(Vector3(10.0, 0.1, 10.0), Color(0.10, 0.08, 0.16), Vector3(0.0, -0.05, 0.0))

	# Backdrop wall.
	_box(Vector3(10.0, 5.0, 0.15), Color(0.07, 0.06, 0.14), Vector3(0.0, 2.5, -4.2))

	# Stage platform.
	_box(Vector3(5.0, 0.25, 3.0), Color(0.16, 0.12, 0.22), Vector3(0.0, 0.125, -1.2))

	# Two spotlight beams (emissive cylinders, tilted).
	for sx in [-2.2, 2.2]:
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.10
		cm.bottom_radius = 0.45
		cm.height = 4.5
		beam.mesh = cm
		var bmat := GraphicsPolish.glow(Color(1.0, 0.8, 0.35), 0.8)
		bmat.albedo_color = Color(1.0, 0.85, 0.4, 0.35)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.material_override = bmat
		beam.position = Vector3(sx * 0.55, 2.4, -1.4)
		beam.rotation_degrees = Vector3(8.0, 0.0, -sx * 6.0)
		add_child(beam)

	# Speaker stacks.
	for sx in [-3.4, 3.4]:
		_box(Vector3(0.9, 1.6, 0.9), Color(0.08, 0.08, 0.10), Vector3(sx, 0.8, -2.6))
		_box(Vector3(0.9, 1.0, 0.9), Color(0.06, 0.06, 0.08), Vector3(sx, 2.1, -2.6))

	# Disco ball.
	_disco = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.35
	dm.height = 0.7
	_disco.mesh = dm
	_disco.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.9, 1.0), "metal")
	_disco.position = Vector3(0.0, 4.3, -1.2)
	add_child(_disco)

	# Mic stand with glowing mic (lights while singing).
	_box(Vector3(0.06, 1.5, 0.06), Color(0.25, 0.25, 0.30), Vector3(2.6, 0.75, 0.6))
	_mic = MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.14
	mm.height = 0.28
	_mic.mesh = mm
	_mic_mat = GraphicsPolish.glow(Color(1.0, 0.4, 0.6), 0.2)
	_mic.material_override = _mic_mat
	_mic.position = Vector3(2.6, 1.62, 0.6)
	add_child(_mic)


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(color, "plastic")
	mi.position = pos
	add_child(mi)
	return mi


func _label(text: String, pos: Vector3, px: float, color: Color) -> Label3D:
	var l := GraphicsPolish.make_label(text, 64, color)
	l.position = pos
	l.pixel_size = px
	add_child(l)
	return l


# ------------------------------------------------------------------ song select

func _build_song_cards() -> void:
	for i in _songs.size():
		var song: Dictionary = _songs[i]
		var x := (float(i) - 1.0) * 2.4
		var card := _box(Vector3(2.0, 1.15, 0.12),
			Color(0.13, 0.15, 0.24), Vector3(x, 1.9, -1.6))
		card.set_meta("song_idx", i)
		_cards.append(card)
		var tl := _label(str(song["title"]), Vector3(x, 2.15, -1.5), 0.009, Color(1.0, 0.9, 0.6))
		tl.set_meta("card_idx", i)
		var gl := _label(str(song["tag"]), Vector3(x, 1.78, -1.5), 0.006, Color(0.65, 0.75, 0.95))
		gl.set_meta("card_idx", i)
		var kl := _label("Press %d" % (i + 1), Vector3(x, 1.52, -1.5), 0.006, Color(0.5, 1.0, 0.7))
		kl.set_meta("card_idx", i)


func _hide_cards() -> void:
	for c in _cards:
		(c as MeshInstance3D).visible = false
	for child in get_children():
		if child is Label3D and child.has_meta("card_idx"):
			child.visible = false


func _show_cards() -> void:
	for c in _cards:
		(c as MeshInstance3D).visible = true
	for child in get_children():
		if child is Label3D and child.has_meta("card_idx"):
			child.visible = true


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	_title_label = _label("AR KARAOKE", Vector3(0.0, 3.55, -2.2), 0.010, Color(1.0, 0.75, 0.9))
	_title_label.text = "AR KARAOKE - pick a song (1 / 2 / 3)"

	_hud = _label("", Vector3(-3.6, 3.1, -2.2), 0.0065, Color(0.85, 0.95, 1.0))
	_hud.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_hud.rotation_degrees = Vector3(0.0, 18.0, 0.0)

	_popup = _label("", Vector3(0.0, 1.55, -1.2), 0.012, Color(1.0, 1.0, 1.0))
	_popup.modulate.a = 0.0

	# Progress bar.
	_prog_bg = _box(Vector3(3.2, 0.09, 0.05), Color(0.12, 0.12, 0.18), Vector3(0.0, 3.28, -2.2))
	_prog_fill = _box(Vector3(3.1, 0.06, 0.06), Color(0.25, 0.8, 1.0), Vector3(-1.55, 3.28, -2.19))
	_prog_fill.visible = false
	_prog_bg.visible = false
	_prog_label = _label("", Vector3(0.0, 3.10, -2.2), 0.0055, Color(0.7, 0.85, 1.0))
	_prog_label.visible = false

	# Pitch meter: slot + marker.
	_box(Vector3(2.4, 0.07, 0.05), Color(0.12, 0.12, 0.18), Vector3(-2.9, 1.1, -1.4))
	_pitch_marker = MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.09
	pm.height = 0.18
	_pitch_marker.mesh = pm
	_pitch_marker.material_override = GraphicsPolish.glow(Color(1.0, 0.4, 0.7), 1.5)
	_pitch_marker.position = Vector3(-2.9, 1.1, -1.35)
	_pitch_marker.visible = false
	add_child(_pitch_marker)
	var pl := _label("PITCH", Vector3(-2.9, 0.88, -1.4), 0.0055, Color(1.0, 0.6, 0.8))
	pl.name = "pitch_tag"
	pl.visible = false


func _show_play_ui(v: bool) -> void:
	_prog_bg.visible = v
	_prog_fill.visible = v
	_prog_label.visible = v
	_pitch_marker.visible = v
	for child in get_children():
		if child is Label3D and child.name == "pitch_tag":
			child.visible = v


# ------------------------------------------------------------------ song flow

func _start_song(idx: int) -> void:
	_song_idx = idx
	var song: Dictionary = _songs[idx]
	_compute_timeline(song)
	_build_lyric_nodes()
	_song_time = 0.0
	_cur_line = 0
	_score = 0
	_combo = 0
	_max_combo = 0
	_perfects = 0
	_goods = 0
	_misses = 0
	_singing = false
	_state = "playing"
	_hide_cards()
	_clear_results()
	_show_play_ui(true)
	_title_label.text = "NOW PLAYING: " + str(song["title"])


func _build_lyric_nodes() -> void:
	# Remove old lyric labels.
	for child in get_children():
		if child is Label3D and child.has_meta("word"):
			child.queue_free()
	var lines: Array = (_songs[_song_idx] as Dictionary)["lines"]
	for li in lines.size():
		var line: Array = lines[li]
		var total := 0.0
		for w in line:
			total += _word_width(str(w)) + WORD_GAP * 4.0
		total -= WORD_GAP * 4.0
		var x := -total / 2.0
		var wi := 0
		for w in _words:
			if int(w["line"]) != li:
				continue
			var text: String = w["text"]
			var l := Label3D.new()
			l.text = text
			l.pixel_size = WORD_PX
			l.modulate = COL_FUTURE
			l.outline_size = 10
			l.set_meta("word", true)
			add_child(l)
			w["label"] = l
			var ww := _word_width(text)
			w["cx"] = x + ww / 2.0
			x += ww + WORD_GAP * 4.0
			wi += 1


func _clear_lyrics() -> void:
	for child in get_children():
		if child is Label3D and child.has_meta("word"):
			child.queue_free()
	_words.clear()


func _clear_results() -> void:
	if _results_node != null:
		_results_node.queue_free()
		_results_node = null


func _finish_song() -> void:
	_state = "results"
	_show_play_ui(false)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 2.6, -1.6), 70)
	var total := _words.size()
	var earned := float(_perfects) + float(_goods) * 0.5
	var acc := earned / float(maxi(total, 1))
	_clear_lyrics()
	var grade := "C"
	var gcol := Color(1.0, 0.6, 0.25)
	if acc >= 0.95:
		grade = "S"
		gcol = Color(1.0, 0.85, 0.25)
	elif acc >= 0.85:
		grade = "A"
		gcol = Color(0.4, 1.0, 0.5)
	elif acc >= 0.70:
		grade = "B"
		gcol = Color(0.4, 0.85, 1.0)
	_results_node = Node3D.new()
	add_child(_results_node)
	var song: Dictionary = _songs[_song_idx]
	_mk_result_label("GRADE: " + grade, Vector3(0.0, 2.9, -1.6), 0.030, gcol)
	_mk_result_label(str(song["title"]), Vector3(0.0, 2.45, -1.6), 0.010, Color(1.0, 1.0, 1.0))
	_mk_result_label("Score %d   Max combo x%d" % [_score, _max_combo], Vector3(0.0, 2.15, -1.6), 0.008, Color(0.85, 0.95, 1.0))
	_mk_result_label("Perfect %d   Good %d   Miss %d   Accuracy %d%%" % [_perfects, _goods, _misses, int(acc * 100.0)], Vector3(0.0, 1.92, -1.6), 0.0075, Color(0.75, 0.85, 1.0))
	_mk_result_label("Click a song card or press 1/2/3 for another song", Vector3(0.0, 1.55, -1.6), 0.0065, Color(0.6, 1.0, 0.7))
	_title_label.text = "AR KARAOKE - pick a song (1 / 2 / 3)"
	_show_cards()
	ARUpgradeKit.save_anchor("ar-karaoke_main", global_transform)


func _mk_result_label(text: String, pos: Vector3, px: float, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 10
	_results_node.add_child(l)


# ------------------------------------------------------------------ audio blips

func _make_tone(freq: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * float(rate))
	var spb := StreamPeerBuffer.new()
	for i in n:
		var t := float(i) / float(rate)
		var s := sin(TAU * freq * t) * exp(-t * 14.0) * 0.5
		spb.put_16(int(clampf(s, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = spb.data_array
	return wav


func _play_blip(perfect: bool) -> void:
	_blip.stream = _make_tone(880.0 if perfect else 620.0, 0.18)
	_blip.play()


# ------------------------------------------------------------------ pitch stub

func _get_pitch() -> float:
	# Simulated pitch 0..1 (hand-tracking / mic hook goes here later).
	return clampf(0.5 + 0.32 * sin(_song_time * 3.1) + 0.14 * sin(_song_time * 7.7 + 1.3), 0.0, 1.0)


func _pinch_active() -> bool:
	# Hand-tracking hook: wire to XR hand pinch in a future pass.
	return false


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_pos = mb.position
			if _state == "playing":
				_singing = true
		else:
			if _state == "playing":
				_singing = false
			elif (mb.position - _press_pos).length() < 10.0:
				_try_pick_card(mb.position)
	elif event is InputEventMouseMotion:
		pass


var _press_pos := Vector2.ZERO


func _try_pick_card(screen_pos: Vector2) -> void:
	if cam == null:
		return
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	for card in _cards:
		var c := card as MeshInstance3D
		if not c.visible:
			continue
		var oc: Vector3 = o - c.position
		var b := oc.dot(d)
		var cc := oc.dot(oc) - 1.35 * 1.35
		var disc := b * b - cc
		if disc > 0.0 and (-b - sqrt(disc)) > 0.0:
			_start_song(int(c.get_meta("song_idx")))
			return


func _poll_keys() -> void:
	var key_actions := {
		KEY_1: 0, KEY_2: 1, KEY_3: 2,
	}
	for k in key_actions.keys():
		var down := Input.is_key_pressed(k)
		var was: bool = _prev_keys.get(k, false)
		if down and not was:
			if _state == "select" or _state == "results":
				_start_song(int(key_actions[k]))
		_prev_keys[k] = down
	var sp := Input.is_key_pressed(KEY_SPACE)
	var sp_was: bool = _prev_keys.get(KEY_SPACE, false)
	if sp != sp_was:
		_space_held = sp
	_prev_keys[KEY_SPACE] = sp


# ------------------------------------------------------------------ scoring

func _mult() -> float:
	return 1.0 + minf(float(_combo), 20.0) * 0.05


func _judge_word(w: Dictionary) -> void:
	w["judged"] = true
	var label: Label3D = w["label"]
	if not bool(w["sung"]):
		_misses += 1
		_combo = 0
		_set_popup("MISS", Color(1.0, 0.35, 0.3))
		if label != null:
			label.modulate = COL_MISS
		return
	var offset: float = float(w["sing_start"]) - float(w["start"])
	if absf(offset) <= PERFECT_WINDOW:
		_perfects += 1
		_combo += 1
		_score += int(300.0 * _mult())
		_set_popup("PERFECT!", COL_PERFECT)
		GraphicsPolish.spawn_sparks(self, Vector3(0.0, 1.9, -1.2), Color(1.0, 0.9, 0.4), 16)
		if label != null:
			label.modulate = COL_PERFECT
		_play_blip(true)
	else:
		_goods += 1
		_combo += 1
		_score += int(120.0 * _mult())
		_set_popup("GOOD", COL_GOOD)
		if label != null:
			label.modulate = COL_GOOD
		_play_blip(false)
	_max_combo = maxi(_max_combo, _combo)


func _set_popup(text: String, color: Color) -> void:
	_popup.text = text
	_popup.modulate = color
	_popup_t = 1.0


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	# Persist the stage placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("ar-karaoke_main", global_transform)
	# XR hand: a pinch on a song card picks it (mouse clicks still work).
	if _state != "playing" and ARUpgradeKit.is_xr_active() and cam != null \
			and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if not cam.is_position_behind(pp):
			_try_pick_card(cam.unproject_position(pp))
	if _disco != null:
		_disco.rotation.y += delta * 0.8
	_popup_t = maxf(0.0, _popup_t - delta * 1.6)
	var pa := _popup.modulate
	pa.a = clampf(_popup_t, 0.0, 1.0)
	_popup.modulate = pa

	if _state == "playing":
		_update_song(delta)
	_update_hud()


func _update_song(delta: float) -> void:
	_song_time += delta
	# Hold click / SPACE / XR pinch to sing.
	var active: bool = _singing or _space_held or ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)

	# Mark sung words and find the current line.
	_cur_line = 0
	for w in _words:
		var start: float = w["start"]
		var end: float = w["end"]
		if active and not bool(w["judged"]) and _song_time >= start and _song_time <= end:
			if not bool(w["sung"]):
				w["sung"] = true
				w["sing_start"] = _song_time
		if _song_time >= start:
			_cur_line = int(w["line"])
		if not bool(w["judged"]) and _song_time >= end:
			_judge_word(w)

	_update_lyric_look(active)

	# Progress bar.
	var frac := clampf(_song_time / _total_dur, 0.0, 1.0)
	_prog_fill.scale.x = maxf(frac, 0.001)
	_prog_fill.position.x = -1.55 + 3.1 * frac * 0.5
	_prog_label.text = "%d%%  %s" % [int(frac * 100.0), _fmt_time(_song_time)]

	# Pitch meter marker follows the simulated pitch.
	_pitch_marker.position.x = -2.9 - 1.1 + _get_pitch() * 2.2

	# Mic glows while singing.
	_mic_mat.emission_energy_multiplier = 2.2 if active else 0.2

	if _song_time >= _total_dur:
		_finish_song()


func _update_lyric_look(active: bool) -> void:
	for w in _words:
		var label: Label3D = w["label"]
		if label == null:
			continue
		var li: int = int(w["line"])
		var dl := li - _cur_line
		label.visible = absf(float(dl)) <= 2.0
		if not label.visible:
			continue
		label.position = Vector3(float(w["cx"]), LYRIC_Y - float(dl) * LINE_SPACING, -1.6)
		var judged: bool = bool(w["judged"])
		if judged:
			continue  # keep the judgment color
		var start: float = w["start"]
		var end: float = w["end"]
		if dl < 0:
			label.modulate = Color(0.35, 0.38, 0.48, 0.55)
		elif dl > 0:
			label.modulate = COL_FUTURE
		else:
			if _song_time >= start and _song_time <= end:
				# Live word: pulse while its window is open.
				var pulse := 0.5 + 0.5 * sin(_time * 12.0)
				label.modulate = COL_CURRENT.lerp(Color(1.0, 0.4, 0.5), pulse * 0.45 if not active else 0.0)
				var s := 1.0 + pulse * 0.18
				label.scale = Vector3(s, s, s)
			elif _song_time > end:
				label.modulate = COL_MISS
			else:
				label.modulate = COL_UPCOMING
				label.scale = Vector3.ONE


func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%d:%02d" % [m, s]


func _update_hud() -> void:
	if _state == "playing":
		var song: Dictionary = _songs[_song_idx]
		_hud.text = "%s\nScore %d\nCombo x%d (x%.2f)\nP %d  G %d  M %d\nHold click / SPACE to sing" % [
			str(song["title"]), _score, _combo, _mult(),
			_perfects, _goods, _misses,
		]
	else:
		_hud.text = "AR KARAOKE\nPick a song: 1 / 2 / 3\nor click a card"
