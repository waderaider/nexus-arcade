## SpectralGame.gd - SPECTRAL FILES: Phasmophobia in your own home.
## EMF reader, thermal view, spirit box and camera on your controllers.
## The ghost has a real position in your room, knocks objects off your
## shelves, and hides behind your couch (depth occlusion). Identify 1 of
## 6 ghost types in 10 minutes — guess wrong and it hunts.
extends Node3D
class_name SpectralGame

## v0.11.0: combat pause profile — hands are always busy; the floating
## pause glyph hides and the menu button needs a 0.45s hold.
static var pause_profile := "combat"

const STEM := "spectral_files"
const HUNT_SECS := 600.0
const EVIDENCE_KINDS := ["EMF5", "FREEZE", "SPIRIT", "PHOTO", "THROW", "FLICKER"]

var controller_config := {
	"buttons": {
		"trigger": "Use tool / take photo",
		"grip": "Cycle tool",
		"thumbstick": "—",
	}
}

var _state := "hunt"  # hunt | won | lost
var _time_left := HUNT_SECS
var _ghost: SpectralGhost
var _tools: SpectralTools
var _evidence := {}
var _ghost_type := ""
var _guessed := false

var _xr := false
var _cam: Camera3D = null
var _hand_r: Node3D = null
var _hand_l: Node3D = null
var _trig_prev := {}
var _grip_prev := {}

var _props: Array[RigidBody3D] = []
var _cold_spots: Array = []  # [{pos, node, age}]
var _cold_t := 0.0
var _journal: Node3D
var _ev_labels := {}
var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _hunt_warned := false
var _demo_t := 0.0
var _demo_stage := 0
var _wisps: Array = []  # animator: [mesh, mat, phase] cold-breath fog
var _flicker: Array = []  # animator: [mat, base, amp, speed, phase]
var _amb_t := 0.0
var _tremble_mesh: MeshInstance3D = null  # animator: pre-knock telegraph
var _tremble_home := Vector3.ZERO
var _puff_cd := {}  # animator: prop instance_id -> cooldown


func _ready() -> void:
	_register_sfx()
	_find_xr()
	_pick_ghost()
	_build_haunts_and_props()
	_build_ghost()
	_build_tools()
	_build_journal()
	_build_hud()
	_build_lighting()
	_build_ambient()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_intensity(1)  # audio director §4d: tense investigation
	_announce_text("SPECTRAL FILES\nCase file #7 is your own address.\nEMF, thermal, spirit box, camera. Name it before it hunts.", 4.0)
	JuiceFX.title_card("SPECTRAL FILES", "Case file #7: your address. Identify it. Ten minutes.", Color(0.55, 0.25, 0.95))


func _register_sfx() -> void:
	if get_node_or_null("/root/AudioKit") == null:
		return
	var d := "res://assets/audio/sfx/"
	AudioKit.set_active_scene(STEM)
	AudioKit.register_game_sfx(STEM, {
		"emf": d + "spectral_emf.wav",
		"static": d + "spectral_static.wav",
		"shutter": d + "spectral_shutter.wav",
		"sting": d + "spectral_sting.wav",
		"knock": d + "spectral_knock.wav",
	})


func _find_xr() -> void:
	if get_node_or_null("/root/ARUpgradeKit") != null and ARUpgradeKit.is_xr_active():
		var found := get_tree().root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			_xr = true
			var origin := found[0] as Node3D
			_cam = origin.get_node_or_null("XRCamera3D") as Camera3D
			_hand_r = origin.get_node_or_null("RightController")
			_hand_l = origin.get_node_or_null("LeftController")
	if not _xr:
		_hand_r = Node3D.new()
		(_hand_r as Node3D).position = Vector3(0.3, 1.3, 0.5)
		add_child(_hand_r)
		_hand_l = Node3D.new()
		(_hand_l as Node3D).position = Vector3(-0.3, 1.3, 0.5)
		add_child(_hand_l)


func _head_pos() -> Vector3:
	if _xr and _cam != null:
		return _cam.global_position
	return Vector3(0, 1.6, 1.2)


func _pick_ghost() -> void:
	var keys := SpectralGhost.TYPES.keys()
	_ghost_type = keys[randi() % keys.size()]
	for k in EVIDENCE_KINDS:
		_evidence[k] = false


func _build_haunts_and_props() -> void:
	var haunts: Array[Vector3] = []
	if get_node_or_null("/root/RoomKit") != null and RoomKit.has_room_data():
		for f in RoomKit.get_furniture():
			var p: Vector3 = f["position"]
			haunts.append(Vector3(p.x, 0.0, p.z))
			if haunts.size() >= 5:
				break
	if haunts.is_empty():
		var c := Vector3.ZERO
		for a in [0.0, 1.25, 2.5, 3.75, 5.0]:
			haunts.append(c + Vector3(cos(a) * 2.2, 0, sin(a) * 2.2))
	# Props: throwable clutter on/near the haunts.
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.5, 0.42, 0.3)
	pmat.roughness = 0.8
	for i in mini(6, haunts.size() * 2):
		var rb := RigidBody3D.new()
		rb.mass = 0.4
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.16, 0.09)
		mi.mesh = bm
		mi.material_override = pmat
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.12, 0.16, 0.09)
		cs.shape = bs
		rb.add_child(cs)
		add_child(rb)
		var h: Vector3 = haunts[i % haunts.size()]
		rb.position = h + Vector3(0.3 * (i % 2), 0.9, -0.2 * (i % 3))
		_props.append(rb)
	_haunts_cache = haunts


var _haunts_cache: Array[Vector3] = []


func _build_ghost() -> void:
	_ghost = SpectralGhost.new()
	add_child(_ghost)
	_ghost.setup(_ghost_type, _haunts_cache, _haunts_cache[0])
	_ghost.event_throw.connect(_on_ghost_throw)
	_ghost.event_flicker.connect(_on_ghost_flicker)
	_ghost.caught_player.connect(_on_caught)
	_ghost.manifest_changed.connect(_on_manifest_changed)


## Animator ambient-life set (v0.11.0): cold-breath wisps (proximity-faded),
## dust motes riding the ghost, pre-knock shelf tremble (telegraph),
## candle flames that desync when hunted, landing dust puffs.
func _build_ambient() -> void:
	# Cold-breath fog wisps: 3 additive quads parented to the ghost.
	for i in 3:
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.35)
		w.mesh = q
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		wm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		wm.albedo_color = Color(0.65, 0.85, 1.0, 0.0)
		wm.disable_fog = true
		w.material_override = wm
		w.position = Vector3(0.3 * (i - 1), 1.1 + 0.15 * (i % 2), 0.25)
		_ghost.add_child(w)
		_wisps.append([w, wm, randf() * TAU])
	# Dust motes drifting along the ghost's path (rides the ghost).
	AmbientKit.dust(_ghost, Vector3.ZERO, 20, Color(0.7, 0.85, 1.0, 0.35), 0.02, 0.1, 0.0)
	# Landing dust puffs: props report their landings (cooldown-gated).
	for p in _props:
		p.body_entered.connect(_on_prop_landed.bind(p))
	# Two candles on haunts: flames desync when hunted (dread).
	for i in mini(2, _haunts_cache.size()):
		_build_candle(_haunts_cache[i] + Vector3(0.45 * (i * 2 - 1), 0.0, 0.3))


func _build_candle(ground: Vector3) -> void:
	var root := Node3D.new()
	root.position = ground + Vector3(0, 0.78, 0)
	add_child(root)
	var wax := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.035
	cyl.height = 0.12
	wax.mesh = cyl
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.92, 0.88, 0.8)
	wax.material_override = wm
	wax.position = Vector3(0, 0.06, 0)
	root.add_child(wax)
	var flame := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.1)
	flame.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.6, 0.15)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 2.2
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame.material_override = fm
	flame.position = Vector3(0, 0.17, 0)
	root.add_child(flame)
	_flicker.append([fm, 2.2, 1.1, 8.0, randf() * TAU])


func _on_prop_landed(_body: Node, prop: RigidBody3D) -> void:
	var id := prop.get_instance_id()
	if float(_puff_cd.get(id, 0.0)) > _amb_t:
		return
	_puff_cd[id] = _amb_t + 1.5
	if is_instance_valid(prop) and prop.linear_velocity.length() > 1.2:
		AmbientKit.burst(self, prop.global_position, 10, Color(0.7, 0.68, 0.62, 0.6), 1.2, 0.03, 0.7)


func _nearest_prop(from: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := 4.0
	for p in _props:
		if not is_instance_valid(p):
			continue
		var d: float = p.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


func _process(delta: float) -> void:
	_amb_t += delta
	# Cold-breath wisps: fade in as the ghost nears the player, slow drift.
	var gp := _ghost.global_position
	var prox := clampf(1.0 - gp.distance_to(_head_pos()) / 6.0, 0.0, 1.0)
	for w in _wisps:
		var m := w[0] as MeshInstance3D
		var mat := w[1] as StandardMaterial3D
		if m == null or mat == null:
			continue
		var ph := float(w[2])
		var c := mat.albedo_color
		c.a = prox * (0.28 + 0.14 * sin(_amb_t * 1.3 + ph))
		mat.albedo_color = c
		m.position.y = 1.1 + 0.12 * sin(_amb_t * 0.9 + ph * 2.0)
	# Pre-knock telegraph: the target prop trembles for ~1s before the throw.
	if _tremble_mesh == null and _ghost.throw_soon():
		var target := _nearest_prop(gp)
		if target != null:
			_tremble_mesh = target.get_child(0) as MeshInstance3D
			if _tremble_mesh != null:
				_tremble_home = _tremble_mesh.position
	if _tremble_mesh != null:
		if not is_instance_valid(_tremble_mesh):
			_tremble_mesh = null
		else:
			var t := _amb_t * 42.0
			_tremble_mesh.position = _tremble_home + Vector3(sin(t) * 0.008, 0.0, cos(t * 1.31) * 0.008)
	# Flames desync when hunted: dread scrambles the flicker phases.
	var dread := 1.0 if _ghost.state == "hunt" else 0.0
	AmbientKit.tick_flicker(_flicker, _amb_t, dread)


func _build_tools() -> void:
	_tools = SpectralTools.new()
	add_child(_tools)
	_tools.attach_to(_hand_r, _cam)
	_tools.evidence_cb = _on_evidence
	_tools.photo_check = _photo_check


func _build_journal() -> void:
	_journal = Node3D.new()
	_journal.position = Vector3(0.9, 1.35, -0.6)
	add_child(_journal)
	var title := Label3D.new()
	title.text = "CASE FILE"
	title.font_size = 56
	title.pixel_size = 0.0035
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = true
	title.position = Vector3(0, 0.75, 0)
	_journal.add_child(title)
	# Evidence rows.
	for i in EVIDENCE_KINDS.size():
		var row := Label3D.new()
		row.text = "○ " + EVIDENCE_KINDS[i]
		row.font_size = 44
		row.pixel_size = 0.0035
		row.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		row.no_depth_test = true
		row.position = Vector3(0, 0.45 - i * 0.17, 0)
		_journal.add_child(row)
		_ev_labels[EVIDENCE_KINDS[i]] = row
	# Guess buttons: 6 ghost types.
	var keys := SpectralGhost.TYPES.keys()
	for i in keys.size():
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.12, 0.06)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.12, 0.45)
		m.emission_enabled = true
		m.emission = Color(0.45, 0.2, 0.8)
		m.emission_energy_multiplier = 0.9
		b.material_override = m
		b.position = Vector3(0, -0.65 - i * 0.2, 0)
		b.set_meta("guess", keys[i])
		_journal.add_child(b)
		var lbl := Label3D.new()
		lbl.text = str(keys[i]).to_upper()
		lbl.font_size = 40
		lbl.pixel_size = 0.0035
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = b.position + Vector3(0, 0, 0.05)
		_journal.add_child(lbl)


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.font_size = 64
	_hud.pixel_size = 0.004
	_hud.position = Vector3(-0.9, 2.1, -0.6)
	_hud.modulate = Color(0.8, 1.0, 0.85)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.no_depth_test = true
	_announce.font_size = 100
	_announce.pixel_size = 0.004
	_announce.modulate = Color(0.75, 0.95, 1.0)
	_announce.outline_modulate = Color(0, 0, 0)
	_announce.outline_size = 14
	_announce.visible = false
	add_child(_announce)
	_update_hud()


func _build_lighting() -> void:
	var omni := OmniLight3D.new()
	omni.light_color = Color(0.5, 0.65, 0.9)
	omni.light_energy = 0.5
	omni.omni_range = 8.0
	omni.position = Vector3(0, 2.4, 0)
	add_child(omni)


func _announce_text(t: String, dur := 2.5) -> void:
	_announce.text = t
	_announce.visible = true
	_announce_t = dur
	_announce.global_position = _head_pos() + Vector3(0, 0.3, 0) + _head_fwd() * 1.8


func _head_fwd() -> Vector3:
	if _xr and _cam != null:
		return -_cam.global_transform.basis.z
	return Vector3(0, 0, -1)


func _update_hud() -> void:
	var found := 0
	for k in _evidence.keys():
		if _evidence[k]:
			found += 1
	_hud.text = "%d:%02d\nEVIDENCE %d/6\n[%s]" % [
		int(_time_left) / 60, int(_time_left) % 60, found, _tools.tool_name()]


# ------------------------------------------------------------------ loop ---

func _physics_process(delta: float) -> void:
	if _announce_t > 0:
		_announce_t -= delta
		if _announce_t <= 0:
			_announce.visible = false
	if _state != "hunt":
		return
	_time_left -= delta
	_ghost.tick(delta, _head_pos())
	_tick_tools_input(delta)
	_tick_cold_spots(delta)
	_update_hud()
	if _time_left <= 60.0 and not _hunt_warned:
		_hunt_warned = true
		_announce_text("IT KNOWS YOU'RE HERE", 2.5)
		_ghost.start_hunt()
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.set_intensity(2)  # audio director §4d: hunted
	if _time_left <= 0.0:
		_time_left = 0.0
		if not _guessed:
			_on_caught()  # time out with no guess: it finds you
	if not _xr:
		_tick_demo(delta)


func _tick_tools_input(_delta: float) -> void:
	var hp: Vector3 = _hand_r.global_position if is_instance_valid(_hand_r) else Vector3.ZERO
	var ghost_dist := hp.distance_to(_ghost.global_position)
	_tools.set_ghost_state(ghost_dist, _ghost.anger)
	var in_cold := false
	for c in _cold_spots:
		if hp.distance_to((c as Dictionary)["pos"]) < 1.2:
			in_cold = true
			break
	_tools.tick(_delta, ghost_dist, in_cold)
	if not _xr:
		return
	var ctl := _hand_r as XRController3D
	if ctl == null or not is_instance_valid(ctl):
		return
	if XRServer.get_tracker(ctl.tracker) == null:
		return
	var trig: bool = XRUIPointer.trigger_pressed(ctl)
	var was_t := bool(_trig_prev.get(0, false))
	_trig_prev[0] = trig
	if trig and not was_t:
		GameplayTelemetry.note_input_method("controllers")
		_tools.use()
		_try_journal_press(hp)
	var grip: bool = ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
	var was_g := bool(_grip_prev.get(0, false))
	_grip_prev[0] = grip
	if grip and not was_g:
		_tools.cycle()
		_update_hud()


func _try_journal_press(hp: Vector3) -> void:
	for c in _journal.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.has_meta("guess"):
			continue
		if hp.distance_to(mi.global_position) < 0.22:
			_guess(str(mi.get_meta("guess")))
			return


func _photo_check() -> bool:
	if not _ghost.is_manifesting():
		return false
	var to: Vector3 = _ghost.global_position - _head_pos()
	if to.length() > 7.0:
		return false
	var fwd := _head_fwd()
	return fwd.angle_to(to.normalized()) < 0.6


func _on_evidence(kind: String) -> void:
	if bool(_evidence.get(kind, true)):
		return  # already logged (or unknown kind)
	_evidence[kind] = true
	var lbl: Label3D = _ev_labels[kind]
	lbl.text = "● " + kind
	lbl.modulate = Color(0.4, 1.0, 0.5)
	_announce_text("EVIDENCE: " + kind, 2.0)
	Haptics.confirm()
	var found := 0
	for k in _evidence.keys():
		if _evidence[k]:
			found += 1
	if found >= 3:
		_announce_text("3 EVIDENCE LOGGED\nName the ghost in the case file!", 3.5)


func _on_ghost_throw() -> void:
	# The ghost flings the nearest prop.
	var gp := _ghost.global_position
	var best: RigidBody3D = null
	var best_d := 4.0
	for p in _props:
		if not is_instance_valid(p):
			continue
		var d: float = p.global_position.distance_to(gp)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		best.apply_central_impulse(Vector3(randf_range(-1, 1), 2.2, randf_range(-1, 1)) * 1.6)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_sfx_3d("knock", best.global_position)
		if gp.distance_to(_head_pos()) < 3.5:
			_on_evidence("THROW")


func _on_ghost_flicker() -> void:
	# Lights dip + red pulse; witnessed up close = evidence.
	Haptics.heartbeat(1)
	if _ghost.global_position.distance_to(_head_pos()) < 4.5:
		_on_evidence("FLICKER")
	_announce_text("the lights flicker...", 1.5)


func _on_manifest_changed(vis: bool) -> void:
	if vis:
		# v0.11.0 VFX: manifestation — cold mist + blue flicker + pulse ring.
		VFX.manifest(self, _ghost.global_position)
		Haptics.texture_tick()
		# VFX artist: signature manifestation scare.
		VFX.manifest(self, _ghost.global_position)


func _on_caught() -> void:
	if _state != "hunt":
		return
	_state = "lost"
	_announce_text("IT FOUND YOU", 30.0)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("sting")
		AudioKit.set_intensity(0)
	Haptics.play_sequence("heartbeat")


func _guess(type_name: String) -> void:
	if _guessed or _state != "hunt":
		return
	_guessed = true
	if type_name == _ghost_type:
		_state = "won"
		_announce_text("CASE CLOSED\nIt was a %s!" % _ghost_type.to_upper(), 30.0)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("levelup")
			AudioKit.set_intensity(0)
		Haptics.play_sequence("fanfare")
	else:
		_announce_text("WRONG — IT'S ANGRY", 3.0)
		_ghost.anger = 1.0
		_ghost.start_hunt()
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.set_intensity(2)
		_guessed = false  # the hunt may end; you get another guess


func _tick_cold_spots(delta: float) -> void:
	_cold_t += delta
	if _cold_t >= 6.0:
		_cold_t = 0.0
		# Cold spots bloom where the ghost lingers.
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.9)
		quad.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.5, 0.8, 1.0, 0.35)
		quad.material_override = m
		quad.position = _ghost.global_position + Vector3(0, 0.5, 0)
		quad.rotation.x = -PI / 2.0 + 0.4
		add_child(quad)
		_cold_spots.append({"pos": _ghost.global_position, "node": quad, "age": 0.0})
	for c in _cold_spots:
		var cd := c as Dictionary
		cd["age"] = float(cd["age"]) + delta
		(cd["node"] as MeshInstance3D).visible = _tools.is_thermal_on()
	# Prune old spots.
	while _cold_spots.size() > 6:
		var old: Dictionary = _cold_spots.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()


# ------------------------------------------------- desktop/headless demo ---
# Scripted walk of the evidence path so every system runs headless.

func _tick_demo(delta: float) -> void:
	_demo_t += delta
	var gp := _ghost.global_position
	if _demo_stage == 0 and _demo_t > 2.0:
		_demo_stage = 1
		# Walk the EMF reader up to the ghost -> EMF5.
		_hand_r.position = gp + Vector3(0.4, 1.2, 0.4)
	elif _demo_stage == 1 and _demo_t > 6.0 and bool(_evidence["EMF5"]):
		_demo_stage = 2
		_tools.current = 1  # THERMAL
		_tools._refresh_label()
		_hand_r.position = gp + Vector3(0.3, 0.6, 0.3)
	elif _demo_stage == 2 and _demo_t > 10.0 and bool(_evidence["FREEZE"]):
		_demo_stage = 3
		_tools.current = 2  # SPIRIT BOX
		_tools._refresh_label()
		_hand_r.position = gp + Vector3(0.5, 1.2, 0.5)
		_tools.use()
	elif _demo_stage == 3 and _demo_t > 14.0:
		_demo_stage = 4
		_guess(_ghost_type)  # correct guess -> win
