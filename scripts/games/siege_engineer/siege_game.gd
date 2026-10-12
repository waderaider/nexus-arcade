## SiegeGame.gd - SIEGE ENGINEER: build trebuchets on your real table,
## then loose at procedural floor castles. 12-castle campaign, rigid-body
## destruction (~48 bricks capped), range is set by YOUR build choices.
extends Node3D
class_name SiegeGame

## v0.11.0: combat pause profile — hands are always busy; the floating
## pause glyph hides and the menu button needs a 0.45s hold.
static var pause_profile := "combat"

const STEM := "siege_engineer"
const TOTAL_CASTLES := 12
const SAVE_PATH := "user://siege_engineer.cfg"

var controller_config := {
	"buttons": {
		"trigger": "Grab part / pull lever",
		"grip": "Grab (alt hand)",
		"thumbstick": "—",
	}
}

var _state := "build"  # build | flight | assess | campaign_done
var _castle_idx := 0
var _shots := 0

var _builder: SiegeBuilder
var _castle: SiegeCastle
var _table_top := Vector3(0, 0.85, -1.1)
var _castle_center := Vector3(0, 0, -6.0)
var _projectile: RigidBody3D = null
var _flight_t := 0.0
var _landing_marker: MeshInstance3D
var _aim_handle: MeshInstance3D

var _xr := false
var _hands := {}
var _trig_prev := {}
var _aim_held := -1
var _test_btn: MeshInstance3D
var _test_cd := 0.0

var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _birds: MultiMeshInstance3D = null  # animator: tower-circling birds
var _bird_phase: Array = []  # preallocated phases (zero-alloc tick)
var _crew: Array = []  # animator: [node, phase, home_pos]
var _flicker: Array = []  # animator: [mat, base, amp, speed, phase]
var _amb_t := 0.0
var _amb_xf := Transform3D.IDENTITY  # reused bird transform (zero-alloc)


func _ready() -> void:
	_register_sfx()
	_find_xr()
	_find_table()
	_builder = SiegeBuilder.new()
	add_child(_builder)
	_builder.build(_table_top, Vector3(1.4, 0.08, 0.9))
	_builder.fired.connect(_on_fired)
	_builder.test_done.connect(_on_test_done)
	_castle = SiegeCastle.new()
	add_child(_castle)
	_build_aim_handle()
	_build_test_button()
	_build_landing_marker()
	_build_hud()
	_load_progress()
	_start_castle(_castle_idx)
	_build_ambient()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_intensity(1)  # audio director §4d: tense build
	_announce_text("SIEGE ENGINEER\nThat castle insulted your ancestors for 300 years.\nBuild the trebuchet. Loose. Grin.", 3.5)
	JuiceFX.title_card("SIEGE ENGINEER", "Twelve castles. One grudge. Your table.", Color(0.85, 0.45, 0.15))


func _register_sfx() -> void:
	if get_node_or_null("/root/AudioKit") == null:
		return
	var d := "res://assets/audio/sfx/"
	AudioKit.set_active_scene(STEM)
	AudioKit.register_game_sfx(STEM, {
		"snap": d + "siege_snap.wav",
		"collapse": d + "siege_collapse.wav",
		"launch": d + "siege_launch.wav",
		"hit": d + "siege_hit.wav",
		"win": d + "siege_win.wav",
	})


func _find_xr() -> void:
	if get_node_or_null("/root/ARUpgradeKit") != null and ARUpgradeKit.is_xr_active():
		var found := get_tree().root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			_xr = true
			var origin := found[0] as Node3D
			_hands[0] = origin.get_node_or_null("LeftController")
			_hands[1] = origin.get_node_or_null("RightController")


func _find_table() -> void:
	var best_size := 0.0
	if get_node_or_null("/root/RoomKit") != null and RoomKit.has_room_data():
		for t in RoomKit.get_tables():
			var s: Vector3 = t["size"]
			if s.x * s.z > best_size and s.y > 0.5:
				best_size = s.x * s.z
				_table_top = (t["position"] as Vector3) + Vector3(0, s.y * 0.5, 0)
	if best_size <= 0.0:
		_spawn_fallback_table()


func _spawn_fallback_table() -> void:
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.4, 0.08, 0.9)
	top.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.28, 0.16)
	m.roughness = 0.85
	top.material_override = m
	top.position = _table_top - Vector3(0, 0.04, 0)
	add_child(top)
	for sx in [-0.6, 0.6]:
		for sz in [-0.35, 0.35]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.07, 0.81, 0.07)
			leg.mesh = lm
			leg.material_override = m
			leg.position = _table_top + Vector3(sx, -0.45, sz)
			add_child(leg)


## Animator ambient-life set (v0.11.0): castle pennants (in siege_castle),
## tower-circling birds, build-area dust, crew fidgets, campfire smoke.
func _build_ambient() -> void:
	# Dust motes in the build-area light.
	AmbientKit.dust(self, _table_top + Vector3(0, 0.55, 0), 20,
		Color(1.0, 0.9, 0.7, 0.35), 0.018, 0.08, 0.02)
	# Birds circling the castle towers: 8-instance MultiMesh, 1 draw.
	_birds = AmbientKit.quad_field(8, 0.4, Color(0.12, 0.1, 0.12, 0.9), false, 1.0)
	add_child(_birds)
	for i in 8:
		_bird_phase.append(randf() * TAU)
	# Tiny crew fidgets at the trebuchet (medieval-people, shared idle driver).
	for i in 2:
		var path := "res://assets/models/war_table/units/peasant_%d.glb" % (1 + i)
		if ResourceLoader.exists(path):
			var crew := (load(path) as PackedScene).instantiate() as Node3D
			crew.scale = Vector3.ONE * 0.3
			var home := _table_top + Vector3(-0.45 + 0.9 * i, 0.02, 0.32)
			crew.position = home
			crew.rotation.y = randf() * TAU
			add_child(crew)
			_crew.append([crew, randf() * TAU, home])
	# Courtyard campfire: stones + flickering fire + smoke (16 particles).
	_build_campfire(_castle_center + Vector3(2.6, 0, 1.8))


func _build_campfire(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.35, 0.33, 0.3)
	stone_mat.roughness = 0.95
	for i in 5:
		var st := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		st.mesh = sm
		st.material_override = stone_mat
		st.position = Vector3(cos(TAU * i / 5.0), 0.05, sin(TAU * i / 5.0)) * 0.22
		root.add_child(st)
	# Fire: emissive quad pair (crossed), flicker via tick_flicker.
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.albedo_color = Color(1.0, 0.45, 0.1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.4, 0.08)
	fire_mat.emission_energy_multiplier = 2.5
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for i in 2:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.34)
		f.mesh = q
		f.material_override = fire_mat
		f.position = Vector3(0, 0.22, 0)
		f.rotation.y = PI * 0.5 * i
		root.add_child(f)
	_flicker.append([fire_mat, 2.5, 1.2, 9.0, randf() * TAU])
	# Smoke: 1 capped emitter, slow rise.
	AmbientKit.dust(root, Vector3(0, 0.5, 0), 16,
		Color(0.25, 0.24, 0.23, 0.5), 0.09, 0.05, 0.35)


func _process(delta: float) -> void:
	_amb_t += delta
	AmbientKit.tick_flicker(_flicker, _amb_t)
	# Birds: circle the towers, flap via scale-x (2-frame feel), phase-offset.
	if _birds != null and is_instance_valid(_birds):
		var mm := _birds.multimesh
		var cc := _castle_center
		for i in 8:
			var ph := float(_bird_phase[i])
			var ang := _amb_t * 0.35 + ph
			var r := 2.6 + 0.5 * sin(ph * 3.0)
			var p := Vector3(cc.x + cos(ang) * r, 4.2 + 0.6 * sin(_amb_t * 0.5 + ph), cc.z + sin(ang) * r)
			var flap := 1.0 + 0.35 * sin(_amb_t * 9.0 + ph * 5.0)
			_amb_xf = Transform3D(Basis.from_scale(Vector3(flap, 1.0, 1.0)).rotated(Vector3.UP, -ang), p)
			mm.set_instance_transform(i, _amb_xf)
	# Crew fidgets: weight shifts + head turns (shared idle driver).
	for c in _crew:
		var n := c[0] as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var ph := float(c[1])
		var home := c[2] as Vector3
		n.position = home + Vector3(0.02 * sin(_amb_t * 0.9 + ph), 0, 0.015 * cos(_amb_t * 0.7 + ph))
		n.rotation.y += sin(_amb_t * 0.4 + ph * 2.0) * 0.15 * delta


func _build_aim_handle() -> void:
	_aim_handle = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.07
	hm.height = 0.14
	_aim_handle.mesh = hm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.8, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.8, 1.0)
	m.emission_energy_multiplier = 1.8
	_aim_handle.material_override = m
	_aim_handle.position = _table_top + Vector3(0.62, 0.1, 0)
	add_child(_aim_handle)
	var lbl := Label3D.new()
	lbl.text = "AIM"
	lbl.font_size = 40
	lbl.pixel_size = 0.003
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = _aim_handle.position + Vector3(0, 0.16, 0)
	add_child(lbl)


func _build_test_button() -> void:
	_test_btn = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.06, 0.14)
	_test_btn.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.6, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.6, 0.1)
	m.emission_energy_multiplier = 1.5
	_test_btn.material_override = m
	_test_btn.position = _table_top + Vector3(-0.62, 0.06, 0)
	add_child(_test_btn)
	var lbl := Label3D.new()
	lbl.text = "TEST BUILD"
	lbl.font_size = 40
	lbl.pixel_size = 0.003
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = _test_btn.position + Vector3(0, 0.16, 0)
	add_child(lbl)


func _build_landing_marker() -> void:
	_landing_marker = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.28
	tor.outer_radius = 0.34
	_landing_marker.mesh = tor
	_landing_marker.rotation = Vector3(PI / 2.0, 0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.5, 0.1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.emission_energy_multiplier = 1.5
	_landing_marker.material_override = m
	add_child(_landing_marker)
	_update_landing_marker()


func _update_landing_marker() -> void:
	var r := _builder.predicted_range()
	var yaw: float = _builder.plate_yaw
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	_landing_marker.position = Vector3(_table_top.x, 0.03, _table_top.z) + dir * r


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.font_size = 64
	_hud.pixel_size = 0.004
	_hud.position = _table_top + Vector3(0, 1.45, 0)
	_hud.modulate = Color(1, 0.95, 0.8)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.no_depth_test = true
	_announce.font_size = 110
	_announce.pixel_size = 0.004
	_announce.modulate = Color(1.0, 0.85, 0.4)
	_announce.outline_modulate = Color(0, 0, 0)
	_announce.outline_size = 14
	_announce.visible = false
	add_child(_announce)
	_update_hud()


func _announce_text(t: String, dur := 2.5) -> void:
	_announce.text = t
	_announce.visible = true
	_announce_t = dur
	_announce.position = _table_top + Vector3(0, 1.9, 0)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_castle_idx = clampi(int(cfg.get_value("siege", "castle", 0)), 0, TOTAL_CASTLES - 1)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("siege", "castle", _castle_idx)
	cfg.save(SAVE_PATH)


func _update_hud() -> void:
	_hud.text = "CASTLE %d/%d · SHOTS %d" % [_castle_idx + 1, TOTAL_CASTLES, _shots]


func _start_castle(idx: int) -> void:
	_castle_idx = idx
	_shots = 0
	var dist := minf(9.0, 5.0 + idx * 0.4)
	_castle_center = Vector3(_table_top.x, 0, _table_top.z - dist)
	_castle.clear()
	_castle.build(idx, _castle_center)
	# Aim the plate at the castle.
	var to: Vector3 = _castle_center - _table_top
	_builder.set_aim(atan2(to.x, to.z))
	_update_landing_marker()
	_update_hud()
	_state = "build"


func _on_test_done(ok: bool) -> void:
	_announce_text("STURDY! Ready to loose." if ok else "IT COLLAPSED!\nRebuild, engineer.", 2.5)
	_update_landing_marker()


func _on_fired(launch: Dictionary) -> void:
	if _state != "build":
		return
	if not _builder.tested_ok:
		_announce_text("UNTESTED BUILD!\nFiring anyway...", 2.0)
	_state = "flight"
	_flight_t = 0.0
	_shots += 1
	_spawn_projectile(float(launch["v0"]), float(launch["yaw"]))
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("launch")
		AudioKit.set_intensity(2)  # audio director §4d: combat/driving
	Haptics.sub_bass(0.5)
	_update_hud()


func _spawn_projectile(v0: float, yaw: float) -> void:
	if is_instance_valid(_projectile):
		_projectile.queue_free()
	_projectile = RigidBody3D.new()
	_projectile.mass = 4.0
	_projectile.contact_monitor = true
	_projectile.max_contacts_reported = 4
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.32)
	m.roughness = 0.9
	mi.material_override = m
	_projectile.add_child(mi)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.12
	cs.shape = ss
	_projectile.add_child(cs)
	add_child(_projectile)
	_projectile.position = _table_top + Vector3(0, 1.3, 0)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	# 45-degree launch.
	_projectile.linear_velocity = (dir * v0 + Vector3(0, v0, 0)).normalized() * v0
	_projectile.body_entered.connect(_on_projectile_hit)


func _on_projectile_hit(_body: Node) -> void:
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("hit")
	Haptics.impact(0.7)


# ------------------------------------------------------------------ loop ---

func _physics_process(delta: float) -> void:
	if _announce_t > 0:
		_announce_t -= delta
		if _announce_t <= 0:
			_announce.visible = false
	_test_cd = maxf(0.0, _test_cd - delta)
	match _state:
		"build":
			if _xr:
				_tick_build_input(delta)
			else:
				_tick_demo_build()
			_builder.update_held()
			_update_aim_handle()
			_update_landing_marker()
		"flight":
			_flight_t += delta
			var done := _flight_t > 7.0
			if is_instance_valid(_projectile) and _projectile.sleeping:
				done = true
			if done:
				_assess_castle()
		"assess":
			pass
		"campaign_done":
			pass


func _tick_build_input(_delta: float) -> void:
	for i in [0, 1]:
		var ctl := _hands.get(i) as XRController3D
		if ctl == null or not is_instance_valid(ctl):
			continue
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var now: bool = XRUIPointer.trigger_pressed(ctl) or ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
		var was := bool(_trig_prev.get(i, false))
		_trig_prev[i] = now
		var hp: Vector3 = ctl.global_position
		if now and not was:
			GameplayTelemetry.note_input_method("controllers")
			if hp.distance_to(_aim_handle.global_position) < 0.25:
				_aim_held = i
			elif hp.distance_to(_test_btn.global_position) < 0.3 and _test_cd <= 0.0:
				_test_cd = 1.0
				_builder.structural_test()
			elif _builder.held_kind(i) == "" :
				var part := _builder.grabbable_near(hp)
				if not part.is_empty() and str(part.get("kind", "")) != "lever":
					_builder.grab(i, part)
					_builder.set_hand_node(i, ctl)
					Haptics.tick()
				elif str(part.get("kind", "")) == "lever":
					_builder.grab(i, part)
					_builder.set_hand_node(i, ctl)
			elif _builder.held_kind(i) == "lever":
				pass  # release below fires it
		elif not now and was:
			if _aim_held == i:
				_aim_held = -1
			elif _builder.held_kind(i) != "":
				_builder.release(i, hp)
	_builder.set_hand_node(0, _hands.get(0))
	_builder.set_hand_node(1, _hands.get(1))


func _update_aim_handle() -> void:
	if _aim_held < 0:
		return
	var ctl := _hands.get(_aim_held) as XRController3D
	if ctl == null or not is_instance_valid(ctl):
		_aim_held = -1
		return
	var d: Vector3 = ctl.global_position - _builder._plate.global_position
	var yaw := atan2(d.x, d.z)
	_builder.set_aim(yaw)
	_update_landing_marker()
	_aim_handle.position = _table_top + Vector3(sin(yaw), 0, cos(yaw)) * 0.62 + Vector3(0, 0.1, 0)


func _assess_castle() -> void:
	_state = "assess"
	var res := _castle.assess()
	var pct: float = res["pct"]
	var need := minf(0.7, 0.5 + _castle_idx * 0.02)
	if bool(res.get("target_toppled", false)):
		_castle_felled("THE CROWN FALLS!")
	elif pct >= need:
		_castle_felled("CASTLE DESTROYED\n%d%% smashed" % int(pct * 100.0))
	else:
		_announce_text("ONLY %d%%\nAdjust and loose again!" % int(pct * 100.0), 2.5)
		_state = "build"
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.set_intensity(1)  # back to tense build


func _castle_felled(msg: String) -> void:
	_announce_text(msg, 3.0)
	# VFX artist: signature castle-crash spectacle.
	VFX.castle_crash(self, _castle_center, 1.0)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("win")
		AudioKit.set_intensity(1)  # celebration settles back to build
	Haptics.play_sequence("fanfare")
	if _castle_idx + 1 >= TOTAL_CASTLES:
		_state = "campaign_done"
		_castle_idx = 0
		_save_progress()
		_announce_text("ALL 12 CASTLES FELLED\nMaster Siege Engineer!", 30.0)
	else:
		_castle_idx += 1
		_save_progress()
		var t := get_tree().create_timer(3.2)
		t.timeout.connect(_start_castle.bind(_castle_idx))


# ------------------------------------------------- desktop/headless demo ---
var _demo_stage := 0
var _demo_t := 0.0


func _tick_demo_build() -> void:
	_demo_t += 1.0 / 60.0
	if _demo_stage == 0 and _demo_t > 1.0:
		_demo_stage = 1
		# Auto-build the best machine.
		_builder.beam_idx = 2
		_builder.weight_idx = 2
		_builder.sling_on = true
		_builder._rebuild_arm_visual()
		_builder.structural_test()
	elif _demo_stage == 1 and _demo_t > 2.0:
		_demo_stage = 2
		_builder.pull_lever()
	elif _demo_stage == 2 and _state == "build" and _demo_t > 9.0:
		# Re-fire if the castle survived the demo shot.
		_demo_t = 1.5
		_demo_stage = 1
