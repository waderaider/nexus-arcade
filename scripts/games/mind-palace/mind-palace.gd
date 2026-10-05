## mind-palace.gd -- NEXUS ARCADE utility: memory-palace mnemonic trainer.
## Click the floor to drop mnemonic anchors (key/book/apple/clock/star);
## each anchor auto-links the next word from the built-in word list.
## Press Q for quiz mode (5 rounds, clickable 3D word buttons), C to clear.
## Upgraded: PBR anchor/floor/button materials, glow center marker, spark
## bursts on anchor placement, confetti on correct quiz answers, ambient
## motes, styled labels, XR pinch anchor placement, room-clamped placement,
## spatial anchor persistence. (The shadowed key light already exists, so the
## polish light rig is skipped by its no-duplicate guard.)
extends Node3D
class_name MindPalaceGame

const WORDS: PackedStringArray = [
	"apple", "bridge", "cloud", "dragon", "ember",
	"forest", "glacier", "harp", "island", "jewel",
	"key", "lantern", "mountain", "nebula", "ocean",
	"piano", "quill", "river", "sun", "tiger",
]

const ANCHOR_DEFS: Array = [
	{"name": "key", "kind": "box", "color": Color(1.0, 0.80, 0.10)},
	{"name": "book", "kind": "box", "color": Color(0.80, 0.12, 0.12)},
	{"name": "apple", "kind": "sphere", "color": Color(0.90, 0.15, 0.18)},
	{"name": "clock", "kind": "cylinder", "color": Color(0.94, 0.94, 0.94)},
	{"name": "star", "kind": "sphere", "color": Color(1.00, 0.88, 0.20)},
]

const FLOOR_HALF := 3.5
const QUIZ_ROUNDS := 5


class PalaceAnchor extends Node3D:
	var word: String = ""
	var visual: MeshInstance3D = null
	var word_label: Label3D = null
	var pulse: float = 0.0


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


var cam: Camera3D = null
var type_idx := 0
var next_word_idx := 0
var anchors: Array = []  # Array[PalaceAnchor]
var _time := 0.0
var _prev_keys := {}
var _anchor_timer := 0.0

var quiz_active := false
var quiz_round := 0
var quiz_score := 0
var quiz_anchor: PalaceAnchor = null
var _feedback_t := 0.0
var _notice := ""
var _notice_t := 0.0
var _summary := ""
var _summary_t := 0.0

var hud: Label3D = null
var help_label: Label3D = null
var quiz_panel: Node3D = null
var question_label: Label3D = null
var feedback_label: Label3D = null
var button_nodes: Array = []  # Array[MeshInstance3D]
var button_words: Array = []  # Array[String]


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "mind-palace_main")
	_build_environment()
	# Upgraded lighting: three-point rig, added only if no key light exists
	# (the environment builder above already adds a shadowed sun, so this is
	# a no-op by design).
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self)
	_build_ui()
	_build_quiz_panel()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.2, 0), 3.0, 40)


func _build_environment() -> void:
	# Fallback camera if the scene provides none (null-check XR assumptions).
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 2.6, 4.8)
		add_child(cam)
		cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.55)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)

	# Floor: large dark slab.
	var floor_mi := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(FLOOR_HALF * 2.0, 0.1, FLOOR_HALF * 2.0)
	floor_mi.mesh = floor_box
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.13, 0.22), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)

	# Faint center marker.
	var marker := MeshInstance3D.new()
	var mring := TorusMesh.new()
	mring.inner_radius = 0.28
	mring.outer_radius = 0.34
	marker.mesh = mring
	marker.material_override = GraphicsPolish.glow(Color(0.3, 0.7, 1.0), 0.8)
	marker.position = Vector3(0.0, 0.02, 0.0)
	add_child(marker)


func _make_label(text: String, pos: Vector3, size: float, color: Color) -> Label3D:
	var l := GraphicsPolish.make_label(text, 48, color)
	l.position = pos
	l.pixel_size = size
	add_child(l)
	return l


func _build_ui() -> void:
	hud = _make_label("", Vector3(-3.4, 2.7, -1.0), 0.006, Color(0.85, 0.95, 1.0))
	help_label = _make_label(
		"Click floor: place anchor\nTab / 1-5: anchor type\nQ: quiz mode   C: clear",
		Vector3(3.4, 2.7, -1.0), 0.006, Color(0.65, 0.75, 0.9))
	_update_hud()


func _build_quiz_panel() -> void:
	quiz_panel = Node3D.new()
	add_child(quiz_panel)
	quiz_panel.visible = false

	question_label = Label3D.new()
	question_label.position = Vector3(0.0, 1.85, 2.2)
	question_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	question_label.pixel_size = 0.007
	question_label.modulate = Color(1.0, 0.95, 0.6)
	question_label.outline_size = 8
	quiz_panel.add_child(question_label)

	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0.0, 0.75, 2.2)
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.pixel_size = 0.007
	feedback_label.outline_size = 8
	quiz_panel.add_child(feedback_label)

	for i in 3:
		var bx := (float(i) - 1.0) * 1.35
		var btn := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.15, 0.36, 0.16)
		btn.mesh = bm
		var bmat := GraphicsPolish.pbr_preset(Color(0.16, 0.35, 0.65), "plastic")
		bmat.emission_enabled = true
		bmat.emission = Color(0.1, 0.25, 0.55)
		bmat.emission_energy_multiplier = 0.6
		btn.material_override = bmat
		btn.position = Vector3(bx, 1.3, 2.2)
		quiz_panel.add_child(btn)
		button_nodes.append(btn)
		button_words.append("")

		var bl := Label3D.new()
		bl.position = Vector3(bx, 1.3, 2.32)
		bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bl.pixel_size = 0.008
		bl.modulate = Color.WHITE
		bl.outline_size = 10
		quiz_panel.add_child(bl)
		btn.set_meta("label", bl)


func _process(delta: float) -> void:
	_time += delta
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("mind-palace_main", global_transform)
	# Hand interaction: right-hand pinch drops an anchor at the hand pointer
	# (floor-projected). Mouse clicks stay on _unhandled_input; the
	# mouse-press gate keeps the kit's mouse fallback from double-triggering.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hand_place_anchor()
	_poll_keys()

	# Anchor pulse animation.
	for a in anchors:
		var anchor: PalaceAnchor = a
		if anchor.pulse > 0.0:
			anchor.pulse = maxf(0.0, anchor.pulse - delta * 0.7)
			var s := 1.0 + 0.45 * sin(_time * 9.0) * anchor.pulse
			anchor.visual.scale = Vector3(s, s, s)
		elif anchor.visual.scale.x != 1.0:
			anchor.visual.scale = Vector3.ONE

	# Quiz answer feedback timer.
	if quiz_active and _feedback_t > 0.0:
		_feedback_t -= delta
		if _feedback_t <= 0.0:
			_next_quiz_round()

	if _notice_t > 0.0:
		_notice_t -= delta
	if _summary_t > 0.0:
		_summary_t -= delta
		if _summary_t <= 0.0:
			_summary = ""

	_update_hud()


## XR path: drop an anchor at the hand pointer, projected onto the floor and
## clamped to the room.
func _hand_place_anchor() -> void:
	if quiz_active:
		return
	var p := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	p = ARUpgradeKit.clamp_to_room(p)
	p.y = 0.0
	_place_anchor(p)


func _poll_keys() -> void:
	# Discrete actions via edge detection on Input.is_key_pressed.
	var keys := [KEY_TAB, KEY_Q, KEY_C, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
	for k in keys:
		var down := Input.is_key_pressed(k)
		var was: bool = _prev_keys.get(k, false)
		if down and not was:
			_on_key(k)
		_prev_keys[k] = down


func _on_key(keycode: int) -> void:
	match keycode:
		KEY_TAB:
			type_idx = (type_idx + 1) % ANCHOR_DEFS.size()
		KEY_Q:
			if quiz_active:
				_end_quiz()
			else:
				_start_quiz()
		KEY_C:
			_clear_anchors()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			type_idx = keycode - KEY_1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)
	elif event is InputEventMouseMotion:
		pass  # Reserved for future hover highlighting.


func _handle_click(screen_pos: Vector2) -> void:
	if cam == null:
		return
	var r: Array = Picker.ray(cam, screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]

	if quiz_active:
		# Clickable 3D word buttons (ray-sphere test).
		for i in button_nodes.size():
			var btn: MeshInstance3D = button_nodes[i]
			if Picker.sphere_hit(o, d, btn.global_position, 0.62):
				_answer_quiz(i)
				return
		return

	# Floor plane click -> place anchor.
	if absf(d.y) < 0.0001 or d.y > 0.0:
		return
	var t := -o.y / d.y
	if t <= 0.0:
		return
	var p: Vector3 = o + d * t
	if absf(p.x) > FLOOR_HALF or absf(p.z) > FLOOR_HALF:
		return
	_place_anchor(p)


func _make_anchor_visual(kind: String, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := GraphicsPolish.pbr_preset(color, "plastic")
	match kind:
		"box":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.30, 0.30, 0.30)
			mi.mesh = bm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.18
			sm.height = 0.36
			mi.mesh = sm
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.15
			cm.bottom_radius = 0.15
			cm.height = 0.32
			mi.mesh = cm
	mi.material_override = mat
	return mi


func _place_anchor(p: Vector3) -> void:
	var def: Dictionary = ANCHOR_DEFS[type_idx]
	var word: String = WORDS[next_word_idx % WORDS.size()]
	next_word_idx += 1

	var anchor := PalaceAnchor.new()
	anchor.word = word
	anchor.position = Vector3(p.x, 0.22, p.z)
	anchor.visual = _make_anchor_visual(def["kind"], def["color"])
	anchor.add_child(anchor.visual)

	anchor.word_label = Label3D.new()
	anchor.word_label.text = word
	anchor.word_label.position = Vector3(0.0, 0.48, 0.0)
	anchor.word_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anchor.word_label.pixel_size = 0.007
	anchor.word_label.modulate = Color(1.0, 1.0, 0.85)
	anchor.word_label.outline_size = 10
	anchor.add_child(anchor.word_label)

	anchor.pulse = 1.0  # Brief pop-in pulse.
	add_child(anchor)
	anchors.append(anchor)
	GraphicsPolish.spawn_sparks(self, anchor.position + Vector3(0, 0.2, 0), Color(1.0, 0.9, 0.4), 16)
	_summary = ""
	_summary_t = 0.0


func _clear_anchors() -> void:
	if quiz_active:
		_end_quiz()
	for a in anchors:
		(a as PalaceAnchor).queue_free()
	anchors.clear()
	next_word_idx = 0
	_summary = ""
	_notice = "Cleared."
	_notice_t = 2.0
	# AR: clearing is a reset -> persist the anchor too.
	ARUpgradeKit.save_anchor("mind-palace_main", global_transform)


func _start_quiz() -> void:
	if anchors.size() < 3:
		_notice = "Place at least 3 anchors first (click the floor)."
		_notice_t = 3.0
		return
	quiz_active = true
	quiz_round = 0
	quiz_score = 0
	quiz_panel.visible = true
	_next_quiz_round()


func _end_quiz() -> void:
	if quiz_anchor != null:
		quiz_anchor.pulse = 0.0
		quiz_anchor = null
	quiz_active = false
	_feedback_t = 0.0
	quiz_panel.visible = false


func _next_quiz_round() -> void:
	if quiz_anchor != null:
		quiz_anchor.pulse = 0.0
	if quiz_round >= QUIZ_ROUNDS:
		_summary = "Quiz done! Score: %d / %d (%d rounds)" % [quiz_score, QUIZ_ROUNDS * 10, QUIZ_ROUNDS]
		_summary_t = 12.0
		_end_quiz()
		return
	quiz_round += 1
	var a: PalaceAnchor = anchors[randi() % anchors.size()]
	quiz_anchor = a
	a.pulse = 1.0

	var opts: Array = [a.word]
	while opts.size() < 3:
		var w: String = WORDS[randi() % WORDS.size()]
		if not opts.has(w):
			opts.append(w)
	opts.shuffle()

	for i in 3:
		button_words[i] = opts[i]
		var bl: Label3D = (button_nodes[i] as MeshInstance3D).get_meta("label")
		bl.text = opts[i]

	question_label.text = "Round %d/%d: which word is on the PULSING anchor?" % [quiz_round, QUIZ_ROUNDS]
	feedback_label.text = ""


func _answer_quiz(idx: int) -> void:
	if _feedback_t > 0.0 or quiz_anchor == null:
		return
	var picked: String = button_words[idx]
	if picked == quiz_anchor.word:
		quiz_score += 10
		feedback_label.modulate = Color(0.4, 1.0, 0.5)
		feedback_label.text = "Correct! +10"
		var btn: MeshInstance3D = button_nodes[idx]
		GraphicsPolish.spawn_confetti(self, btn.global_position + Vector3(0, 0.3, 0), 40)
	else:
		quiz_score -= 5
		feedback_label.modulate = Color(1.0, 0.45, 0.45)
		feedback_label.text = "Wrong (%s). -5" % quiz_anchor.word
	_feedback_t = 1.1


func _update_hud() -> void:
	var def: Dictionary = ANCHOR_DEFS[type_idx]
	var lines := PackedStringArray()
	lines.append("MIND PALACE  |  anchors: %d  |  type: %s (Tab/1-5)" % [anchors.size(), def["name"]])
	if quiz_active:
		lines.append("QUIZ round %d/%d  score %d" % [quiz_round, QUIZ_ROUNDS, quiz_score])
	elif _summary != "":
		lines.append(_summary)
	if _notice_t > 0.0:
		lines.append(_notice)
	hud.text = "\n".join(lines)


func _pinch_active() -> bool:
	# Hand-tracking hook: wire to XR hand pinch in a future pass.
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
