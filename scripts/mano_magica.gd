## ManoMagica.gd - NEXUS ARCADE utility: "MANO MÁGICA" guided hand-tracking tour.
## v0.9.0 (TECH_DEMO_PLAN S3-shared). Six 10-second lessons — pinch, grab,
## throw, sculpt, conduct, pet a creature — each with haptic + audio feedback.
## Doubles as the onboarding tour for every other game's gesture vocabulary.
##
## Built on the v0.9.0 shared APIs: XRUIPointer.grab_state /
## throw_release_velocity / two_hand_pinch_distance, Haptics vocabulary,
## AudioKit SFX + play_stinger, JuiceFX.scale_pop / combo_popup.
## Desktop fallback: mouse buttons emulate pinches (left = right hand,
## right = left hand) so the tour is smoke-testable without a headset.
extends Node3D

const LESSON_TIME := 10.0
const RIGHT := 2  # XRUIPointer.HAND_RIGHT_SIDE
const LEFT := 1   # XRUIPointer.HAND_LEFT_SIDE

const LESSONS := [
	{"id": "pinch", "title": "PINCH",
		"hint": "Touch your thumb and index finger together.\nA pinch selects things everywhere in NEXUS."},
	{"id": "grab", "title": "GRAB",
		"hint": "Pinch ON the glowing orb and hold it.\nGrabbed things follow your hand."},
	{"id": "throw", "title": "THROW",
		"hint": "Swing your hand and LET GO!\nRelease speed becomes throw speed."},
	{"id": "sculpt", "title": "SCULPT",
		"hint": "Pinch-drag across the clay to shape it.\nFeel the texture ticks as you carve."},
	{"id": "conduct", "title": "CONDUCT",
		"hint": "Wave your hand like a conductor's baton.\nFaster waves = more music!"},
	{"id": "pet", "title": "PET",
		"hint": "Gently move your hand over the creature.\nSlow and soft — it likes that."},
]

var _lesson := 0
var _lesson_t := 0.0
var _done := false
var _title: Label3D
var _hint: Label3D
var _progress: Label3D
var _stage: Node3D  # per-lesson props live here
# Lesson state.
var _flower: Node3D = null
var _orb: MeshInstance3D = null
var _orb_vel := Vector3.ZERO
var _orb_free := false
var _grab_hold_t := 0.0
var _clay: MeshInstance3D = null
var _sculpt_dist := 0.0
var _last_sculpt_pt := Vector3.ZERO
var _conduct_t := 0.0
var _last_baton := Vector3.ZERO
var _creature: Node3D = null
var _pets := 0
var _pet_cool := 0.0
var _desktop_hist := {}  # side -> Array of [t, pos] (mouse fallback)


func _ready() -> void:
	_build_stage()
	_start_lesson(0)
	var br := get_node_or_null("/root/BugReporter")
	if br != null and br.has_method("add_breadcrumb"):
		br.add_breadcrumb("mano_magica_start")


func _process(delta: float) -> void:
	if _done:
		return
	_lesson_t += delta
	_pet_cool = maxf(0.0, _pet_cool - delta)
	_update_progress()
	match String(LESSONS[_lesson]["id"]):
		"pinch":
			_lesson_pinch()
		"grab":
			_lesson_grab(delta)
		"throw":
			_lesson_throw(delta)
		"sculpt":
			_lesson_sculpt()
		"conduct":
			_lesson_conduct(delta)
		"pet":
			_lesson_pet()
	if _lesson_t >= LESSON_TIME:
		_lesson_failed()


# ------------------------------------------------------------ lessons ---

func _lesson_pinch() -> void:
	for side in [LEFT, RIGHT]:
		var pt: Variant = _pinch_point(side)
		if pt != null:
			_bloom_flower(pt)
			Haptics.texture_tick()
			AudioKit.play_sfx("pop")
			_lesson_success("Beautiful pinch!")
			return


func _lesson_grab(delta: float) -> void:
	if _orb == null:
		return
	if _orb_free:
		_lesson_grab_reset()
		return
	var held := false
	for side in [LEFT, RIGHT]:
		var st := XRUIPointer.grab_state(side)
		var gpt: Variant = _pinch_point(side)
		if bool(st["active"]) and gpt != null \
				and (gpt as Vector3).distance_to(_orb.global_position) < 0.18:
			XRUIPointer.set_held_node(side, _orb)
			held = true
		elif gpt == null:
			XRUIPointer.set_held_node(side, null)
	if held:
		_grab_hold_t += delta
		Haptics.confirm()
		if _grab_hold_t > 0.12:
			Haptics.texture_tick()
		if _grab_hold_t >= 2.0:
			for side in [LEFT, RIGHT]:
				XRUIPointer.set_held_node(side, null)
			_lesson_success("Got it — you can grab!")
	else:
		_grab_hold_t = 0.0


func _lesson_throw(delta: float) -> void:
	if _orb == null:
		return
	if _orb_free:
		# Orb is flying: let it drift, then celebrate.
		_orb.global_position += _orb_vel * delta
		_orb_vel *= 0.985
		_orb_vel.y -= 1.2 * delta
		if _orb.global_position.y < 0.05:
			_lesson_success("What a throw!")
		return
	# Re-grab with either hand, then release fast.
	for side in [LEFT, RIGHT]:
		var st := XRUIPointer.grab_state(side)
		var gpt: Variant = _pinch_point(side)
		if bool(st["active"]) and gpt != null \
				and (gpt as Vector3).distance_to(_orb.global_position) < 0.2:
			XRUIPointer.set_held_node(side, _orb)
		if not bool(st["active"]) and XRUIPointer.was_released(side):
			var vel := XRUIPointer.throw_release_velocity(side)
			var dvel: Vector3 = _desktop_release_vel(side)
			if dvel.length() > vel.length():
				vel = dvel
			if vel.length() > 1.0:
				_orb_free = true
				_orb_vel = vel
				Haptics.impact(clampf(vel.length() / 4.0, 0.0, 1.0))
				AudioKit.play_sfx("whoosh")
			XRUIPointer.set_held_node(side, null)



func _lesson_sculpt() -> void:
	if _clay == null:
		return
	for side in [LEFT, RIGHT]:
		var pt: Variant = _pinch_point(side)
		if pt == null:
			_last_sculpt_pt = Vector3.ZERO
			continue
		var p: Vector3 = pt
		if p.distance_to(_clay.global_position) < 0.3:
			if _last_sculpt_pt != Vector3.ZERO:
				var d := p.distance_to(_last_sculpt_pt)
				_sculpt_dist += d
				if d > 0.02:
					Haptics.texture_tick()
					AudioKit.play_sfx("pop", 0.7 + minf(_sculpt_dist, 1.0) * 0.5, -12.0)
			_last_sculpt_pt = p
			# Carve: squash the clay toward the pinch.
			var k := 1.0 - minf(_sculpt_dist * 0.15, 0.45)
			_clay.scale = Vector3(1.0 + (1.0 - k) * 0.6, k, 1.0 + (1.0 - k) * 0.6)
	if _sculpt_dist >= 1.2:
		JuiceFX.scale_pop(_clay, 1.3)
		_lesson_success("A masterpiece!")


func _lesson_conduct(delta: float) -> void:
	var pt: Variant = _pinch_point(RIGHT)
	if pt == null:
		pt = _pinch_point(LEFT)
	if pt == null:
		return
	var p: Vector3 = pt
	if _last_baton != Vector3.ZERO:
		var speed := p.distance_to(_last_baton) / maxf(delta, 0.001)
		if speed > 0.6:
			_conduct_t += delta
			Haptics.texture_tick()
			if _conduct_t > 0.25:
				_conduct_t = 0.0
				AudioKit.play_sfx("sparkle", randf_range(0.9, 1.3), -8.0)
				_spawn_note(p)
	_last_baton = p
	# Sustain ~4s of waving total (accumulate via progress instead).
	if _lesson_t >= LESSON_TIME * 0.85 and _conduct_notes() >= 8:
		_lesson_success("Encore! Encore!")


var _notes_spawned := 0

func _conduct_notes() -> int:
	return _notes_spawned


func _lesson_pet() -> void:
	if _creature == null or _pet_cool > 0.0:
		return
	for side in [LEFT, RIGHT]:
		var pt: Variant = _pinch_point(side)
		if pt == null:
			continue
		var p: Vector3 = pt
		if p.distance_to(_creature.global_position) < 0.3:
			_pets += 1
			_pet_cool = 0.8
			Haptics.heartbeat(1)
			AudioKit.play_sfx("heal", 1.2, -6.0)
			JuiceFX.combo_popup(_creature.global_position + Vector3(0, 0.35, 0), "♥")
			JuiceFX.squash_stretch(_creature)
			if _pets >= 3:
				_lesson_success("It loves you!")
			return


# ------------------------------------------------------------- flow ---

func _lesson_success(msg: String) -> void:
	AudioKit.play_stinger("success")
	Haptics.play_sequence("fanfare")
	JuiceFX.combo_popup(Vector3(0, 1.8, -1.2), msg)
	_advance()


func _lesson_failed() -> void:
	AudioKit.play_sfx("ui_back")
	_advance()


func _advance() -> void:
	_clear_stage()
	_lesson += 1
	if _lesson >= LESSONS.size():
		_finale()
		return
	_start_lesson(_lesson)


func _finale() -> void:
	_done = true
	_title.text = "MANO MÁGICA COMPLETE"
	_hint.text = "You speak fluent hand-tracking now.\nEvery NEXUS game understands these gestures."
	_progress.text = ""
	AudioKit.play_stinger("levelup")
	Haptics.play_sequence("levelup")
	JuiceFX.combo_popup(Vector3(0, 1.8, -1.2), "★ HAND MASTER ★")
	# Celebration burst.
	GraphicsPolish.spawn_confetti(self, Vector3(0, 1.6, -1.2), 80)


# ------------------------------------------------------------ stage ---

func _build_stage() -> void:
	_title = GraphicsPolish.make_label("", 96)
	_title.position = Vector3(0, 2.2, -1.6)
	add_child(_title)
	_hint = GraphicsPolish.make_label("", 56)
	_hint.position = Vector3(0, 1.75, -1.6)
	add_child(_hint)
	_progress = GraphicsPolish.make_label("", 44, Color(0.7, 0.85, 1.0))
	_progress.position = Vector3(0, 1.35, -1.6)
	add_child(_progress)
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	# Soft key light so props read well over passthrough.
	var key := DirectionalLight3D.new()
	key.light_energy = 0.7
	key.rotation_degrees = Vector3(-50, -30, 0)
	add_child(key)


func _clear_stage() -> void:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()
	_flower = null
	_orb = null
	_orb_free = false
	_grab_hold_t = 0.0
	_clay = null
	_sculpt_dist = 0.0
	_last_sculpt_pt = Vector3.ZERO
	_conduct_t = 0.0
	_last_baton = Vector3.ZERO
	_notes_spawned = 0
	_creature = null
	_pets = 0
	_pet_cool = 0.0
	for side in [LEFT, RIGHT]:
		XRUIPointer.set_held_node(side, null)


func _start_lesson(idx: int) -> void:
	_lesson_t = 0.0
	var l: Dictionary = LESSONS[idx]
	_title.text = "LESSON %d/%d: %s" % [idx + 1, LESSONS.size(), String(l["title"])]
	_hint.text = String(l["hint"])
	match String(l["id"]):
		"pinch":
			pass  # flower blooms at the pinch point
		"grab", "throw":
			_spawn_orb()
		"sculpt":
			_spawn_clay()
		"conduct":
			pass  # notes spawn at the baton
		"pet":
			_spawn_creature()
	AudioKit.play_sfx("notify")


func _update_progress() -> void:
	var remain := maxf(0.0, LESSON_TIME - _lesson_t)
	_progress.text = "%.0fs — %s" % [remain, "keep going!" if remain > 3.0 else "wrapping up…"]


func _spawn_orb() -> void:
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	_orb.mesh = sm
	_orb.material_override = GraphicsPolish.glow(Color(1.0, 0.75, 0.25), 2.2)
	_orb.position = Vector3(0.25, 1.3, -0.9)
	_orb.set_meta("interactive", true)
	_stage.add_child(_orb)


func _lesson_grab_reset() -> void:
	_orb_free = false
	_orb_vel = Vector3.ZERO
	_orb.position = Vector3(0.25, 1.3, -0.9)


func _spawn_clay() -> void:
	_clay = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_clay.mesh = sm
	_clay.material_override = GraphicsPolish.pbr(Color(0.75, 0.45, 0.28), 0.0, 0.85)
	_clay.position = Vector3(0, 1.25, -0.9)
	_clay.set_meta("interactive", true)
	_stage.add_child(_clay)


func _spawn_creature() -> void:
	_creature = Node3D.new()
	_creature.position = Vector3(0, 1.25, -0.9)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.3
	body.mesh = sm
	body.material_override = GraphicsPolish.pbr(Color(0.55, 0.8, 1.0), 0.1, 0.5)
	_creature.add_child(body)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var esm := SphereMesh.new()
		esm.radius = 0.035
		esm.height = 0.07
		eye.mesh = esm
		eye.material_override = GraphicsPolish.glow(Color(0.1, 0.1, 0.15), 0.5)
		eye.position = Vector3(ex, 0.05, 0.13)
		_creature.add_child(eye)
	_creature.set_meta("interactive", true)
	_stage.add_child(_creature)
	# Idle bob so it feels alive.
	var tw := _creature.create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(_creature, "position:y", 1.32, 1.2)
	tw.tween_property(_creature, "position:y", 1.18, 1.2)


func _bloom_flower(at: Vector3) -> void:
	_flower = Node3D.new()
	_flower.position = at
	_stage.add_child(_flower)
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = 0.22
	stem.mesh = cm
	stem.material_override = GraphicsPolish.pbr(Color(0.2, 0.6, 0.25), 0.0, 0.7)
	stem.position = Vector3(0, -0.11, 0)
	_flower.add_child(stem)
	for i in 6:
		var petal := MeshInstance3D.new()
		var psm := SphereMesh.new()
		psm.radius = 0.045
		psm.height = 0.09
		petal.mesh = psm
		petal.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.4)
		var a := TAU * float(i) / 6.0
		petal.position = Vector3(cos(a) * 0.075, 0.02, sin(a) * 0.075)
		petal.scale = Vector3(1.0, 0.45, 1.0)
		_flower.add_child(petal)
	_flower.scale = Vector3.ONE * 0.05
	# Bloom: grow with overshoot.
	var twf := _flower.create_tween()
	twf.tween_property(_flower, "scale", Vector3.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_note(at: Vector3) -> void:
	_notes_spawned += 1
	var n := GraphicsPolish.make_label("♪", 72, Color(1.0, 0.85, 0.4))
	_stage.add_child(n)
	n.global_position = at + Vector3(randf_range(-0.1, 0.1), 0.1, 0)
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "position:y", n.position.y + 0.5, 0.9)
	tw.tween_property(n, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(n.queue_free)


# ------------------------------------------------------------- input ---

## Pinch point for a hand: XR hand tracking first, mouse fallback on desktop.
func _pinch_point(side: int) -> Variant:
	var pt: Variant = XRUIPointer.pinch_point(side, null)
	if pt != null:
		return pt
	return _desktop_pinch(side)


func _desktop_pinch(side: int) -> Variant:
	if not _desktop_active():
		return null
	var want_left := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var want_right := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if (side == RIGHT and not want_right) or (side == LEFT and not want_left):
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var p := o + d * 1.2
	# Track for desktop release velocity.
	var now := Time.get_ticks_msec() / 1000.0
	var hist: Array = _desktop_hist.get(side, [])
	hist.append([now, p])
	while not hist.is_empty() and now - float(hist[0][0]) > 0.15:
		hist.pop_front()
	_desktop_hist[side] = hist
	return p


func _desktop_active() -> bool:
	return not get_viewport().use_xr


func _desktop_release_vel(side: int) -> Vector3:
	var hist: Array = _desktop_hist.get(side, [])
	_desktop_hist[side] = []
	if hist.size() < 2:
		return Vector3.ZERO
	var dt := float(hist[hist.size() - 1][0]) - float(hist[0][0])
	if dt < 0.02:
		return Vector3.ZERO
	return ((hist[hist.size() - 1][1] as Vector3) - (hist[0][1] as Vector3)) / dt
