## holo_piano.gd - Virtual piano: 2 octaves (C4-B5), 14 white + 10 black keys.
## Click keys with the mouse or play the computer keyboard (A W S E D F
## T G Y H U J K = C4..C5 chromatic). Notes are synthesized in code as
## 22050 Hz 8-bit sine WAVs (equal temperament, A4=440).
extends Node3D
class_name HoloPianoGame

const RATE := 22050
const NORMAL_DUR := 1.2
const SUSTAIN_DUR := 2.8
const WHITE_W := 0.5
const WHITE_D := 2.0
const KEY_HEIGHT := 0.3

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
## Computer-key map: A W S E D F T G Y H U J K -> chromatic C4..C5.
const KEYMAP := [KEY_A, KEY_W, KEY_S, KEY_E, KEY_D, KEY_F, KEY_T, KEY_G, KEY_Y, KEY_H, KEY_U, KEY_J, KEY_K]

var _cam: Camera3D = null
var _keys := {} ## midi -> {node, y0, press, collider}
var _tones := {} ## midi -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _sustain := false
var _last_note: Label3D = null
var _sustain_label: Label3D = null
var _sustain_btn_collider: StaticBody3D = null
var _key_prev := {}
var _anchor_timer := 0.0

## RoomKit v0.7.0: cached room layout (world space; converted to local at use).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _room_anchored := false
var _fake_table: MeshInstance3D = null
var _help_label: Label3D = null


func _ready() -> void:
	_ensure_camera()
	_build_light()
	_build_table()
	_build_keys()
	_build_sustain_button()
	_build_hud()
	for k in KEYMAP:
		_key_prev[k] = false
	# AR: restore the saved anchor in XR; first run lands the piano on a table.
	if ARUpgradeKit.is_xr_active():
		_room_anchored = ARUpgradeKit.apply_anchor(self, "holo-piano_main")
		if not _room_anchored:
			ARUpgradeKit.place_on_table(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, 0.4), 4.0, 40)
	_apply_room_layout()


func _process(delta: float) -> void:
	_update_key_animations(delta)
	_poll_keyboard()
	_update_anchor_timer(delta)
	# XR pinch plays the key under the pointer ray (mouse/keyboard keep working).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_xr_pinch_play()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- build

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 5.2, 7.5)
	_cam.look_at(Vector3(0, 0.2, 0.3), Vector3.UP)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light() -> void:
	_add_polish_light_rig()
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.ambient_light_energy = 0.9
	amb.environment = env
	add_child(amb)


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9.0, 0.4, 4.0)
	table.mesh = bm
	table.material_override = GraphicsPolish.pbr(Color(0.23, 0.16, 0.11), 0.05, 0.7)
	table.position = Vector3(0, -0.35, 0.4)
	add_child(table)
	_fake_table = table


func _build_keys() -> void:
	var total_w := 14.0 * WHITE_W
	var x0 := -total_w * 0.5
	var white_steps: Array[int] = [0, 2, 4, 5, 7, 9, 11] ## semitone offsets within an octave
	for oct in 2:
		for wi in 7:
			var idx := oct * 7 + wi
			var midi := 60 + oct * 12 + white_steps[wi]
			var x := x0 + idx * WHITE_W + WHITE_W * 0.5
			_make_key(midi, Vector3(x, KEY_HEIGHT * 0.5, 0.4), Vector3(WHITE_W * 0.94, KEY_HEIGHT, WHITE_D), Color(0.95, 0.95, 0.97), false)
	## Black keys after white indices 0(C),1(D),3(F),4(G),5(A) per octave.
	var black_after: Array[int] = [0, 1, 3, 4, 5]
	var black_off: Array[int] = [1, 3, 6, 8, 10]
	for oct in 2:
		for bi in 5:
			var wi := black_after[bi]
			var idx := oct * 7 + wi
			var midi := 60 + oct * 12 + black_off[bi]
			var x := x0 + idx * WHITE_W + WHITE_W
			_make_key(midi, Vector3(x, KEY_HEIGHT * 0.5 + 0.16, -0.1), Vector3(0.3, KEY_HEIGHT + 0.32, 1.2), Color(0.08, 0.08, 0.1), true)
	_synth_all_tones()


func _make_key(midi: int, pos: Vector3, size: Vector3, color: Color, black: bool) -> void:
	var root := Node3D.new()
	root.name = "Key_%d" % midi
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := GraphicsPolish.pbr(color, 0.0, 0.35) if not black else GraphicsPolish.pbr_preset(color, "rubber")
	if not black:
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.5, 0.8)
		mat.emission_energy_multiplier = 0.15
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	_keys[midi] = {"node": root, "y0": pos.y, "press": 0.0, "collider": sb}


func _build_sustain_button() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0.25, 2.6)
	add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.5, 0.5)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr(Color(0.2, 0.5, 0.8), 0.2, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.9) * 0.4
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 0.5, 0.5)
	cs.shape = bs
	sb.add_child(cs)
	_sustain_btn_collider = sb
	_sustain_label = Label3D.new()
	_sustain_label.position = Vector3(0, 0, 0.3)
	_sustain_label.pixel_size = 0.01
	_sustain_label.outline_size = 8
	root.add_child(_sustain_label)
	_update_sustain_label()


func _build_hud() -> void:
	_last_note = GraphicsPolish.make_label("Play a key", 64)
	_last_note.position = Vector3(0, 3.4, -0.5)
	_last_note.pixel_size = 0.014
	add_child(_last_note)
	var help := Label3D.new()
	help.text = "Click keys or press A W S E D F T G Y H U J K (C4..C5)"
	help.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help.position = Vector3(0, 2.85, -0.5)
	help.pixel_size = 0.009
	help.modulate = Color(0.8, 0.85, 1.0)
	add_child(help)
	_help_label = help


# ---------------------------------------------------------------- audio

func _freq_for_midi(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


func _synth_all_tones() -> void:
	for midi in _keys.keys():
		_tones[midi] = _make_tone(_freq_for_midi(midi), NORMAL_DUR)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func _make_tone(freq: float, duration: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n)
	var decay := 2.2 if duration < 2.0 else 1.1
	for i in n:
		var t := float(i) / RATE
		var attack := minf(1.0, t / 0.008)
		var env := attack * exp(-decay * t)
		var s := sin(TAU * freq * t) + 0.25 * sin(TAU * freq * 2.0 * t)
		s *= env * 0.8
		data[i] = clampi(128 + int(s * 110.0), 0, 255)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


func _play_midi(midi: int) -> void:
	if not _tones.has(midi):
		return
	var stream: AudioStreamWAV = _tones[midi]
	if _sustain and midi in _keys:
		stream = _make_tone(_freq_for_midi(midi), SUSTAIN_DUR)
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[0]
	player.stream = stream
	player.play()
	(_keys[midi] as Dictionary)["press"] = 0.22
	var key_node := (_keys[midi] as Dictionary)["node"] as Node3D
	GraphicsPolish.spawn_sparks(self, key_node.global_position + Vector3(0, 0.25, 0), Color(0.4, 0.8, 1.0), 12)
	var octave := midi / 12 - 1
	var note := "%s%d" % [NOTE_NAMES[midi % 12], octave]
	_last_note.text = "%s  (%.2f Hz)" % [note, _freq_for_midi(midi)]


# ---------------------------------------------------------------- input

func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active():
			ARUpgradeKit.save_anchor("holo-piano_main", global_transform)

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var to := from + _cam.project_ray_normal(screen_pos) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider == _sustain_btn_collider:
		_sustain = not _sustain
		_update_sustain_label()
		return
	for midi in _keys.keys():
		if (_keys[midi] as Dictionary)["collider"] == collider:
			_play_midi(midi)
			return


func _xr_pinch_play() -> void:
	# XR alternative to _on_click: pinch plays the key (or sustain button)
	# under the pointer ray. Desktop keeps mouse + computer keyboard.
	if _cam == null:
		return
	var pr := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var from: Vector3 = pr[0]
	var dir: Vector3 = pr[1]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider == _sustain_btn_collider:
		_sustain = not _sustain
		_update_sustain_label()
		return
	for midi in _keys.keys():
		if (_keys[midi] as Dictionary)["collider"] == collider:
			_play_midi(midi)
			return


func _poll_keyboard() -> void:
	for i in KEYMAP.size():
		var code: int = KEYMAP[i]
		var down := Input.is_key_pressed(code)
		var was: bool = _key_prev[code]
		if down and not was:
			_play_midi(60 + i)
		_key_prev[code] = down


func _update_sustain_label() -> void:
	if _sustain_label != null:
		_sustain_label.text = "Sustain: ON" if _sustain else "Sustain: OFF"


func _update_key_animations(delta: float) -> void:
	for midi in _keys.keys():
		var k := _keys[midi] as Dictionary
		var press := float(k["press"])
		if press > 0.0:
			press = maxf(0.0, press - delta)
			k["press"] = press
			var node := k["node"] as Node3D
			var y0 := float(k["y0"])
			node.position.y = y0 - 0.09 * (press / 0.22)

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the table docks the holo keyboard with a scifi skin; the rug is the neon performance stage.
	var _morph0_table := RoomKit.get_anchors("TABLE")
	if not _morph0_table.is_empty():
		RoomKit.morph(_morph0_table[0], "scifi")
	var _morph1_rug := RoomKit.get_anchors("RUG")
	if not _morph1_rug.is_empty():
		RoomKit.morph(_morph1_rug[0], "neon")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Seat the keyboard on the largest real table (skipped when the saved
	# anchor was restored — the anchor already persists the seated pose).
	if not _room_anchored and not _room_tables.is_empty():
		var t: Dictionary = _room_largest_item(_room_tables)
		var tp: Vector3 = t["position"]
		var ts: Vector3 = t["size"]
		global_position = tp + Vector3(0.0, ts.y * 0.5, 0.0)
		if _fake_table != null:
			_fake_table.visible = false
	# Hang the HUD readout on the largest real wall, facing the room.
	if not _room_walls.is_empty() and _last_note != null and _help_label != null:
		var w: Dictionary = _room_largest_wall()
		if not w.is_empty():
			var wp: Vector3 = w["position"]
			var n: Vector3 = w["normal"]
			var yaw := atan2(-n.x, -n.z)
			var face: Vector3 = wp + n * 0.35
			_last_note.global_position = face + Vector3(0.0, 0.95, 0.0)
			_last_note.global_rotation = Vector3(0.0, yaw, 0.0)
			_help_label.global_position = face + Vector3(0.0, 0.40, 0.0)
			_help_label.global_rotation = Vector3(0.0, yaw, 0.0)


## RoomKit: the wall with the largest face area, or {} when none.
func _room_largest_wall() -> Dictionary:
	var best := {}
	var best_a := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var sz: Vector2 = w["size"]
		var a := sz.x * sz.y
		if a > best_a:
			best_a = a
			best = w
	return best


## RoomKit: the table/furniture item with the largest footprint, or {}.
func _room_largest_item(items: Array) -> Dictionary:
	var best := {}
	var best_a := 0.0
	for f_v in items:
		var f: Dictionary = f_v
		var sz: Vector3 = f["size"]
		var a := sz.x * sz.z
		if a > best_a:
			best_a = a
			best = f
	return best
