## ar-dj.gd -- NEXUS ARCADE: virtual DJ setup for Quest 3.
## Two turntables (drag to scratch, click disc to play/stop), a mixer with
## 3 vertical gain sliders and a crossfader, plus a loop-visual toggle.
## Both loops are synthesized in code (AudioStreamWAV): Deck A = 4/4 kick,
## Deck B = offbeat hats + bass. Scratching pitch-shifts playback.
extends Node3D
class_name ARDJGame

const BPM := 128.0
const MIX_RATE := 22050
const BEAT := 60.0 / BPM          # 0.46875 s
const LOOP_LEN := BEAT * 4.0      # 1.875 s
const DISC_RPM := 33.33

const DECK_X := 1.15
const DISC_Y := 1.06              # disc top surface plane
const TABLE_TOP := 0.90

const SLIDER_Z_MIN := -0.20
const SLIDER_Z_MAX := 0.50
const FADER_X_MAX := 0.30
const FADER_Z := 0.55


class DJDeck:
	var side: String = "A"
	var center := Vector3.ZERO
	var disc: MeshInstance3D = null
	var rim_mat: StandardMaterial3D = null
	var loop_ring: MeshInstance3D = null
	var loop_mat: StandardMaterial3D = null
	var loop_btn: MeshInstance3D = null
	var loop_on := false
	var playing := false
	var player: AudioStreamPlayer = null
	var status_label: Label3D = null
	var scratch_omega := 0.0      # extra angular velocity from scratching
	var beat_flash := 0.0
	var last_beat := -1


class Picker:
	static func ray(cam: Camera3D, screen_pos: Vector2) -> Array:
		return [cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)]

	static func sphere_hit(o: Vector3, d: Vector3, c: Vector3, r: float) -> bool:
		var oc: Vector3 = o - c
		var b: float = oc.dot(d)
		var cc: float = oc.dot(oc) - r * r
		var disc: float = b * b - cc
		if disc <= 0.0:
			return false
		return (-b - sqrt(disc)) > 0.0

	static func plane_y(o: Vector3, d: Vector3, y: float) -> Array:
		# Returns [hit: bool, point: Vector3].
		if absf(d.y) < 0.0001:
			return [false, Vector3.ZERO]
		var t := (y - o.y) / d.y
		if t <= 0.0:
			return [false, Vector3.ZERO]
		return [true, o + d * t]


var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}

var deck_a: DJDeck = null
var deck_b: DJDeck = null

# Mixer state.
var gain_a := 0.8
var gain_b := 0.8
var master := 0.9
var fader := 0.0               # -1 (A) .. +1 (B)
var knob_gain_a: MeshInstance3D = null
var knob_gain_b: MeshInstance3D = null
var knob_master: MeshInstance3D = null
var fader_knob: MeshInstance3D = null

# Drag interaction state.
var _drag_kind := ""           # "", "disc_a", "disc_b", "loop_a", "loop_b", "fader", "gain_a", "gain_b", "master"
var _press_pos := Vector2.ZERO

var hud: Label3D = null
var help_label: Label3D = null
var _anchor_timer := 0.0
var _click_consumed := false


func _ready() -> void:
	_add_light_rig()
	_build_environment()
	_build_table()
	deck_a = _build_deck("A", Vector3(-DECK_X, 0.0, 0.0), _synth_kick_loop())
	deck_b = _build_deck("B", Vector3(DECK_X, 0.0, 0.0), _synth_hat_bass_loop())
	_build_mixer()
	_build_ui()
	_apply_volumes()
	# Restore the DJ table's saved room anchor; otherwise place it in front of
	# the player at table height when running in XR.
	if not ARUpgradeKit.apply_anchor(self, "ar-dj_main") and ARUpgradeKit.is_xr_active():
		ARUpgradeKit.place_on_table(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 2.0)


func _add_light_rig() -> void:
	# Three-point light rig; skipped if a directional light already exists.
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 2.6, 4.8)
		add_child(cam)
		cam.look_at(Vector3(0.0, 0.7, 0.0), Vector3.UP)

	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.42, 0.58)
	env.ambient_light_energy = 0.65
	amb.environment = env
	add_child(amb)

	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(9.0, 0.1, 9.0)
	floor_mi.mesh = fb
	var fmat := GraphicsPolish.pbr_preset(Color(0.08, 0.09, 0.16), "matte")
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := GraphicsPolish.pbr(color, 0.2, 0.55)
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build_table() -> void:
	_box(Vector3(3.6, 0.12, 2.2), Color(0.22, 0.16, 0.12), Vector3(0.0, TABLE_TOP - 0.06, 0.0))
	for lx in [-1.6, 1.6]:
		for lz in [-0.9, 0.9]:
			_box(Vector3(0.12, TABLE_TOP - 0.12, 0.12), Color(0.15, 0.11, 0.09), Vector3(lx, (TABLE_TOP - 0.12) / 2.0, lz))


# ------------------------------------------------------------------ audio synth

func _pack_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var spb := StreamPeerBuffer.new()
	for s in samples:
		spb.put_16(int(clampf(s, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = spb.data_array
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


func _synth_kick_loop() -> AudioStreamWAV:
	# Deck A: punchy 4/4 kick drum, one 4-beat loop.
	var n := int(LOOP_LEN * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var s := 0.0
		for b in 4:
			var bt := t - float(b) * BEAT
			if bt >= 0.0 and bt < 0.30:
				s += sin(TAU * 52.0 * bt) * exp(-bt * 26.0)
				s += sin(TAU * 150.0 * bt) * exp(-bt * 70.0) * 0.35
		samples[i] = s * 0.9
	return _pack_wav(samples)


func _synth_hat_bass_loop() -> AudioStreamWAV:
	# Deck B: offbeat hats + offbeat sub bass, one 4-beat loop.
	var n := int(LOOP_LEN * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var s := 0.0
		for b in 4:
			var off := float(b) * BEAT + BEAT * 0.5
			var ht := t - off
			if ht >= 0.0 and ht < 0.09:
				s += (randf() * 2.0 - 1.0) * exp(-ht * 90.0) * 0.45
			if (b == 0 or b == 2):
				var bt := t - off
				if bt >= 0.0 and bt < 0.35:
					s += sin(TAU * 55.0 * bt) * exp(-bt * 9.0) * 0.75
		samples[i] = s * 0.9
	return _pack_wav(samples)


# ------------------------------------------------------------------ decks

func _build_deck(side: String, center: Vector3, stream: AudioStreamWAV) -> DJDeck:
	var deck := DJDeck.new()
	deck.side = side
	deck.center = center

	# Plinth.
	_box(Vector3(0.95, 0.10, 0.95), Color(0.13, 0.14, 0.20), center + Vector3(0.0, TABLE_TOP + 0.05, 0.0))

	# Disc (rotates).
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.40
	dm.bottom_radius = 0.40
	dm.height = 0.05
	disc.mesh = dm
	var dmat := GraphicsPolish.pbr_preset(Color(0.06, 0.06, 0.09), "plastic")
	disc.material_override = dmat
	disc.position = center + Vector3(0.0, DISC_Y - 0.025, 0.0)
	add_child(disc)
	deck.disc = disc

	# Rotation marker stripe (child of disc so it spins).
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.07, 0.06, 0.30)
	stripe.mesh = sm
	var stmat := GraphicsPolish.glow(Color(0.9, 0.9, 0.95), 1.2)
	stripe.material_override = stmat
	stripe.position = Vector3(0.0, 0.0, 0.22)
	disc.add_child(stripe)

	# Center spindle.
	var spin := MeshInstance3D.new()
	var spm := CylinderMesh.new()
	spm.top_radius = 0.05
	spm.bottom_radius = 0.05
	spm.height = 0.09
	spin.mesh = spm
	var spmat := GraphicsPolish.pbr_preset(Color(1.0, 0.8, 0.2), "metal")
	spin.material_override = spmat
	spin.position = center + Vector3(0.0, DISC_Y + 0.01, 0.0)
	add_child(spin)

	# Beat-pulse rim (emissive torus around the disc).
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.40
	rm.outer_radius = 0.45
	rim.mesh = rm
	deck.rim_mat = GraphicsPolish.glow(Color(0.15, 0.45, 1.0), 0.3)
	rim.material_override = deck.rim_mat
	rim.position = center + Vector3(0.0, DISC_Y, 0.0)
	add_child(rim)

	# 4-beat loop visual: pulsing ring, toggled by the loop button.
	var ring := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 0.48
	gm.outer_radius = 0.53
	ring.mesh = gm
	deck.loop_mat = GraphicsPolish.glow(Color(0.1, 0.9, 0.7), 1.2)
	ring.material_override = deck.loop_mat
	ring.position = center + Vector3(0.0, DISC_Y + 0.01, 0.0)
	ring.visible = false
	add_child(ring)
	deck.loop_ring = ring

	# Loop button on the plinth.
	var btn := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.07
	bcm.bottom_radius = 0.07
	bcm.height = 0.05
	btn.mesh = bcm
	var btnmat := GraphicsPolish.pbr_preset(Color(0.15, 0.55, 0.45), "plastic")
	btn.material_override = btnmat
	btn.position = center + Vector3(0.0, TABLE_TOP + 0.12, 0.36)
	add_child(btn)
	deck.loop_btn = btn

	var bl := GraphicsPolish.make_label("LOOP", 56, Color(0.5, 1.0, 0.85))
	bl.position = center + Vector3(0.0, TABLE_TOP + 0.30, 0.36)
	add_child(bl)

	# Deck letter label.
	var dl := Label3D.new()
	dl.text = "DECK " + side
	dl.position = center + Vector3(0.0, TABLE_TOP + 0.30, -0.36)
	dl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dl.pixel_size = 0.006
	dl.modulate = Color(1.0, 1.0, 1.0)
	dl.outline_size = 8
	add_child(dl)
	deck.status_label = dl

	# Audio player.
	deck.player = AudioStreamPlayer.new()
	deck.player.stream = stream
	deck.player.volume_db = -60.0
	add_child(deck.player)

	return deck


# ------------------------------------------------------------------ mixer

func _build_mixer() -> void:
	var mx := 0.0
	var mz := 0.15
	_box(Vector3(0.85, 0.12, 1.05), Color(0.10, 0.11, 0.16), Vector3(mx, TABLE_TOP + 0.06, mz))

	# 3 vertical gain sliders: A (left), MASTER (center), B (right).
	var defs := [
		{"x": -0.28, "name": "GAIN A"},
		{"x": 0.0, "name": "MASTER"},
		{"x": 0.28, "name": "GAIN B"},
	]
	for d in defs:
		var sx: float = d["x"]
		# Slot.
		_box(Vector3(0.05, 0.02, SLIDER_Z_MAX - SLIDER_Z_MIN + 0.08),
			Color(0.03, 0.03, 0.05), Vector3(mx + sx, TABLE_TOP + 0.125, mz + (SLIDER_Z_MIN + SLIDER_Z_MAX) / 2.0))
		# Knob.
		var knob := _box(Vector3(0.12, 0.06, 0.10), Color(0.85, 0.85, 0.9), Vector3(mx + sx, TABLE_TOP + 0.15, mz))
		knob.name = "knob_" + d["name"]
		# Name label.
		var nl := Label3D.new()
		nl.text = d["name"]
		nl.position = Vector3(mx + sx, TABLE_TOP + 0.32, mz - 0.32)
		nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nl.pixel_size = 0.005
		nl.modulate = Color(0.7, 0.8, 1.0)
		nl.outline_size = 8
		add_child(nl)
		match d["name"]:
			"GAIN A":
				knob_gain_a = knob
			"MASTER":
				knob_master = knob
			"GAIN B":
				knob_gain_b = knob
	_layout_slider(knob_gain_a, gain_a, mx - 0.28, mz)
	_layout_slider(knob_gain_b, gain_b, mx + 0.28, mz)
	_layout_slider(knob_master, master, mx, mz)

	# Crossfader: horizontal slot along X at the front of the mixer.
	_box(Vector3(FADER_X_MAX * 2.0 + 0.10, 0.02, 0.06),
		Color(0.03, 0.03, 0.05), Vector3(mx, TABLE_TOP + 0.125, mz + FADER_Z))
	fader_knob = _box(Vector3(0.10, 0.07, 0.12), Color(1.0, 0.55, 0.2), Vector3(mx, TABLE_TOP + 0.15, mz + FADER_Z))
	var fl := Label3D.new()
	fl.text = "XFADE  A <--> B"
	fl.position = Vector3(mx, TABLE_TOP + 0.30, mz + FADER_Z + 0.12)
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.pixel_size = 0.005
	fl.modulate = Color(1.0, 0.75, 0.5)
	fl.outline_size = 8
	add_child(fl)
	_layout_fader()


func _layout_slider(knob: MeshInstance3D, value: float, x: float, mz: float) -> void:
	if knob == null:
		return
	knob.position = Vector3(x, TABLE_TOP + 0.15, mz + lerpf(SLIDER_Z_MIN, SLIDER_Z_MAX, value))


func _layout_fader() -> void:
	fader_knob.position.x = fader * FADER_X_MAX


func _build_ui() -> void:
	hud = GraphicsPolish.make_label("AR-DJ", 64, Color(0.85, 0.95, 1.0))
	hud.position = Vector3(0.0, 2.75, -1.2)
	add_child(hud)

	help_label = Label3D.new()
	help_label.text = "Drag disc: scratch (RPM) | Click disc: play/stop | Drag knobs/fader\nClick LOOP: 4-beat loop visual | A/B keys: toggle decks"
	help_label.position = Vector3(0.0, 2.25, -1.2)
	help_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help_label.pixel_size = 0.0055
	help_label.modulate = Color(0.65, 0.75, 0.9)
	help_label.outline_size = 8
	add_child(help_label)


# ------------------------------------------------------------------ mixing

func _to_db(g: float) -> float:
	if g <= 0.001:
		return -60.0
	return clampf(20.0 * log(g) / log(10.0), -40.0, 0.0)


func _apply_volumes() -> void:
	# Equal-power crossfade between decks, then channel gains and master.
	var xa := cos((fader + 1.0) * PI * 0.25)
	var xb := sin((fader + 1.0) * PI * 0.25)
	deck_a.player.volume_db = _to_db(xa * gain_a * master)
	deck_b.player.volume_db = _to_db(xb * gain_b * master)


func _toggle_deck(deck: DJDeck) -> void:
	deck.playing = not deck.playing
	if deck.playing:
		deck.player.play()
		deck.last_beat = -1
		GraphicsPolish.spawn_sparks(self, deck.center + Vector3(0.0, 1.3, 0.0), Color(0.4, 0.9, 1.0), 28)
	else:
		deck.player.stop()
		deck.scratch_omega = 0.0
		deck.player.pitch_scale = 1.0


func _toggle_loop(deck: DJDeck) -> void:
	deck.loop_on = not deck.loop_on
	deck.loop_ring.visible = deck.loop_on


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_click_consumed = true
			_press_pos = mb.position
			_drag_kind = _pick(mb.position)
		else:
			# Click (not drag) on a disc toggles play/stop.
			if (_drag_kind == "disc_a" or _drag_kind == "disc_b") and (mb.position - _press_pos).length() < 8.0:
				_toggle_deck(deck_a if _drag_kind == "disc_a" else deck_b)
			_drag_kind = ""
	elif event is InputEventMouseMotion and _drag_kind != "":
		_drag(event as InputEventMouseMotion)


func _pick(screen_pos: Vector2) -> String:
	if cam == null:
		return ""
	var r: Array = Picker.ray(cam, screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]

	# Knobs and buttons first (small targets).
	if Picker.sphere_hit(o, d, fader_knob.position, 0.13):
		return "fader"
	if Picker.sphere_hit(o, d, knob_gain_a.position, 0.13):
		return "gain_a"
	if Picker.sphere_hit(o, d, knob_gain_b.position, 0.13):
		return "gain_b"
	if Picker.sphere_hit(o, d, knob_master.position, 0.13):
		return "master"
	if Picker.sphere_hit(o, d, deck_a.loop_btn.position, 0.14):
		_toggle_loop(deck_a)
		return "loop_a"
	if Picker.sphere_hit(o, d, deck_b.loop_btn.position, 0.14):
		_toggle_loop(deck_b)
		return "loop_b"

	# Discs: intersect the disc-top plane, check radial distance.
	var hp: Array = Picker.plane_y(o, d, DISC_Y)
	if hp[0]:
		var p: Vector3 = hp[1]
		for deck in [deck_a, deck_b]:
			var flat := Vector2(p.x - deck.center.x, p.z - deck.center.z)
			if flat.length() < 0.47:
				return "disc_a" if deck == deck_a else "disc_b"
	return ""


func _drag(ev: InputEventMouseMotion) -> void:
	match _drag_kind:
		"disc_a", "disc_b":
			var deck: DJDeck = deck_a if _drag_kind == "disc_a" else deck_b
			# Horizontal drag velocity spins the disc: scratching.
			deck.scratch_omega += ev.relative.x * 0.06
			deck.scratch_omega = clampf(deck.scratch_omega, -14.0, 14.0)
		"fader":
			fader = clampf(fader + ev.relative.x * 0.004, -1.0, 1.0)
			_layout_fader()
			_apply_volumes()
		"gain_a", "gain_b", "master":
			var v := 0.0
			match _drag_kind:
				"gain_a":
					v = gain_a
				"gain_b":
					v = gain_b
				"master":
					v = master
			v = clampf(v + ev.relative.y * 0.003, 0.0, 1.0)
			match _drag_kind:
				"gain_a":
					gain_a = v
					_layout_slider(knob_gain_a, gain_a, -0.28, 0.15)
				"gain_b":
					gain_b = v
					_layout_slider(knob_gain_b, gain_b, 0.28, 0.15)
				"master":
					master = v
					_layout_slider(knob_master, master, 0.0, 0.15)
			_apply_volumes()
		"loop_a", "loop_b":
			pass  # Toggled on press; nothing to drag.


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	_poll_pinch()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("ar-dj_main", global_transform)

	for deck in [deck_a, deck_b]:
		_update_deck(deck, delta)

	_update_hud()


func _poll_keys() -> void:
	for k in [KEY_A, KEY_B]:
		var down := Input.is_key_pressed(k)
		var was: bool = _prev_keys.get(k, false)
		if down and not was:
			_toggle_deck(deck_a if k == KEY_A else deck_b)
		_prev_keys[k] = down


func _update_deck(deck: DJDeck, delta: float) -> void:
	var base_omega := 0.0
	if deck.playing:
		base_omega = TAU * DISC_RPM / 60.0

	# Scratch velocity decays back to zero; pitch follows it.
	deck.scratch_omega = lerpf(deck.scratch_omega, 0.0, minf(1.0, 4.0 * delta))
	var omega := base_omega + deck.scratch_omega
	deck.disc.rotation.y += omega * delta

	if deck.playing:
		deck.player.pitch_scale = clampf(1.0 + deck.scratch_omega * 0.12, 0.25, 3.0)
		# Beat pulse from the actual playback position.
		var pos := deck.player.get_playback_position()
		var beat_idx := int(pos / BEAT)
		if beat_idx != deck.last_beat:
			deck.last_beat = beat_idx
			deck.beat_flash = 1.0

	deck.beat_flash = maxf(0.0, deck.beat_flash - delta * 2.5)
	deck.rim_mat.emission_energy_multiplier = 0.3 + deck.beat_flash * 3.0

	# 4-beat loop ring pulse.
	if deck.loop_on:
		var pulse := 0.5 + 0.5 * sin(TAU * _time / LOOP_LEN)
		deck.loop_mat.emission_energy_multiplier = 0.8 + pulse * 1.6
		var s := 1.0 + pulse * 0.06
		deck.loop_ring.scale = Vector3(s, 1.0, s)

	deck.set_meta("rpm", omega / TAU * 60.0)


func _deck_state(deck: DJDeck) -> String:
	var rpm: float = deck.get_meta("rpm", 0.0)
	var st := "PLAY" if deck.playing else "STOP"
	var lp := " LOOP" if deck.loop_on else ""
	return "Deck %s: %s %4.0f RPM%s" % [deck.side, st, rpm, lp]


func _update_hud() -> void:
	hud.text = "AR-DJ  |  %d BPM  |  XFADE %+.2f  |  GAIN A %.2f  B %.2f  M %.2f\n%s\n%s" % [
		int(BPM), fader, gain_a, gain_b, master,
		_deck_state(deck_a), _deck_state(deck_b),
	]


func _pinch_active() -> bool:
	# XR hand-tracking pinch (mouse fallback keeps desktop working).
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _poll_pinch() -> void:
	# A pinch taps whatever the hand pointer is over: discs toggle play/stop,
	# loop buttons toggle (handled inside _pick).
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if _click_consumed:
		_click_consumed = false
		return
	if pinched and cam != null:
		var wp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		var kind := _pick(cam.unproject_position(wp))
		if kind == "disc_a":
			_toggle_deck(deck_a)
		elif kind == "disc_b":
			_toggle_deck(deck_b)
