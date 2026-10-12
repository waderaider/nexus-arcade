## TerraformGame.gd - TERRAFORM: god-game on your coffee table.
## Sculpt terrain with hand presses, paint biomes, seed species, fast-forward
## epochs, unleash disasters. The planet persists between sessions and keeps
## evolving slightly while you're away.
extends Node3D
class_name TerraformGame

## v0.11.0: combat pause profile — hands are always busy; the floating
## pause glyph hides and the menu button needs a 0.45s hold.
static var pause_profile := "combat"

const STEM := "terraform"
const SAVE_PATH := "user://terraform_save.cfg"
const MODEL_DIR := "res://assets/models/terraform/"

const TOOLS := ["RAISE", "LOWER", "PAINT", "SEED", "EPOCH", "DISASTER"]
const BIOMES := ["grass", "desert", "ice"]
const FAUNA := ["fauna_rabbit", "fauna_deer_1", "fauna_squirrel", "fauna_boar"]
const DISASTERS := ["METEOR", "FLOOD", "VOLCANO"]

var controller_config := {
	"buttons": {
		"trigger": "Use tool (hold to sculpt)",
		"grip": "Next tool",
		"thumbstick": "—",
	}
}

var _world: TerraformWorld
var _sim: TerraformSim
var _tool := 0
var _biome := 0
var _seed_fauna := false
var _fauna_kind := 0
var _disaster := 0
var _disaster_int_t := 0.0  # audio director §4d: intensity decay timer
var _birds: MultiMeshInstance3D = null  # animator: wildlife specks
var _fish: MultiMeshInstance3D = null
var _cities: MultiMeshInstance3D = null  # animator: city lights
var _city_mat: StandardMaterial3D = null
var _speck_phase: Array = []  # preallocated (zero-alloc tick)
var _flicker: Array = []  # animator: [mat, base, amp, speed, phase]
var _rain: GPUParticles3D = null  # animator: flood rain streaks
var _rain_t := 0.0
var _sentience_celebrated := false  # vfx: epoch_flash once
var _amb_t := 0.0
var _amb_xf := Transform3D.IDENTITY  # reused (zero-alloc)

var _xr := false
var _hands := {}
var _trig_prev := {}
var _grip_prev := {}
var _tool_acc := 0.0
var _sfx_cd := 0.0

var _table_top := Vector3(0, 0.85, -1.0)
var _palette: Array = []  # [{tool, node}]
var _flora_mm := {}  # kind -> MultiMeshInstance3D
var _flora_models := {}
var _fauna_nodes := {}  # sim index -> Node3D
var _fauna_models := {}
var _flora_t := 0.0
var _save_t := 0.0
var _epoch_t := 0.0

var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _sentient_announced := false
var _ice_announced := false
var _demo_t := 0.0
var _demo_stage := 0


func _ready() -> void:
	_register_sfx()
	_find_xr()
	_find_table()
	_world = TerraformWorld.new()
	add_child(_world)
	_world.position = _table_top + Vector3(0, 0.06, 0)
	_world.build()
	_sim = TerraformSim.new()
	add_child(_sim)
	_sim.setup(_world)
	_load_models()
	_build_flora_multimeshes()
	_build_palette()
	_build_hud()
	_load_save()
	_build_ambient()
	_announce_text("TERRAFORM\nThe seed-ship Cradle carried one living world.\nSculpt it. Seed it. Survive what you create.", 4.0)
	JuiceFX.title_card("TERRAFORM", "One living world. Your table. Answer for what you make.", Color(0.25, 0.8, 0.45))
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.set_intensity(0)  # audio director §4d: calm explore


func _register_sfx() -> void:
	if get_node_or_null("/root/AudioKit") == null:
		return
	var d := "res://assets/audio/sfx/"
	AudioKit.set_active_scene(STEM)
	AudioKit.register_game_sfx(STEM, {
		"sculpt": d + "terra_sculpt.wav",
		"paint": d + "terra_paint.wav",
		"seed": d + "terra_seed.wav",
		"disaster": d + "terra_disaster.wav",
		"epoch": d + "terra_epoch.wav",
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
	var best := 0.0
	if get_node_or_null("/root/RoomKit") != null and RoomKit.has_room_data():
		for t in RoomKit.get_tables():
			var s: Vector3 = t["size"]
			if s.x * s.z > best and s.y > 0.4:
				best = s.x * s.z
				_table_top = (t["position"] as Vector3) + Vector3(0, s.y * 0.5 + 0.01, 0)


func _load_models() -> void:
	for m in ["flora_bush_1", "flora_flower_1", "flora_grass_1", "flora_mushroom_1"]:
		_flora_models[m] = _first_mesh(m + ".glb")
	for m in FAUNA:
		_fauna_models[m] = m + ".glb"


func _first_mesh(glb: String) -> Mesh:
	var ps: PackedScene = load(MODEL_DIR + glb) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	inst.queue_free()
	return mesh


func _build_flora_multimeshes() -> void:
	for kind in _flora_models.keys():
		var mesh: Mesh = _flora_models[kind]
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 90
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_world.add_child(mmi)
		_flora_mm[kind] = mmi
		for i in 90:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -10, 0)))


func _build_palette() -> void:
	for i in TOOLS.size():
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.05, 0.1)
		b.mesh = bm
		b.material_override = _btn_mat(false)
		var ang := -0.9 + i * 0.36
		b.position = _table_top + Vector3(sin(ang) * 0.85, 0.35, cos(ang) * 0.85 - 0.2)
		add_child(b)
		var lbl := Label3D.new()
		lbl.text = TOOLS[i]
		lbl.font_size = 36
		lbl.pixel_size = 0.0025
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.position = b.position + Vector3(0, 0.08, 0)
		add_child(lbl)
		_palette.append({"tool": i, "node": b, "label": lbl})
	_refresh_palette()


func _btn_mat(active: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := Color(0.2, 0.7, 1.0) if active else Color(0.16, 0.2, 0.28)
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6 if active else 0.5
	return m


func _refresh_palette() -> void:
	for e in _palette:
		(e["node"] as MeshInstance3D).material_override = _btn_mat(int(e["tool"]) == _tool)
		var extra := ""
		if _tool == 2:
			extra = "\n" + BIOMES[_biome]
		elif _tool == 3:
			extra = "\n" + ("fauna" if _seed_fauna else "flora")
		elif _tool == 5:
			extra = "\n" + DISASTERS[_disaster]
		(e["label"] as Label3D).text = TOOLS[int(e["tool"])] + extra


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.font_size = 60
	_hud.pixel_size = 0.004
	_hud.position = _table_top + Vector3(0, 1.15, 0)
	_hud.modulate = Color(0.85, 1.0, 0.9)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.no_depth_test = true
	_announce.font_size = 100
	_announce.pixel_size = 0.004
	_announce.modulate = Color(0.9, 1.0, 0.85)
	_announce.outline_modulate = Color(0, 0, 0)
	_announce.outline_size = 14
	_announce.visible = false
	add_child(_announce)


func _announce_text(t: String, dur := 3.0) -> void:
	_announce.text = t
	_announce.visible = true
	_announce_t = dur
	_announce.position = _table_top + Vector3(0, 1.5, 0)


func _update_hud() -> void:
	_hud.text = "EPOCH %d · %s\nAnimals %d/25 · Green %.0f%%\n%s%s" % [
		_sim.epochs, "⏩ FAST" if _sim.fast_forward else TOOLS[_tool],
		_sim.animals.size(), _sim.veg_coverage() * 100.0,
		"◈ SENTIENT!" if _sim.sentient else "◈ birth sentience",
		" · survived ice age" if _sim.ice_age_survived else ""]


# ------------------------------------------------------------------ loop ---

func _physics_process(delta: float) -> void:
	if _announce_t > 0:
		_announce_t -= delta
		if _announce_t <= 0:
			_announce.visible = false
	_sfx_cd = maxf(0.0, _sfx_cd - delta)
	# Audio director §4d: disaster intensity decays back to calm.
	if _disaster_int_t > 0.0:
		_disaster_int_t -= delta
		if _disaster_int_t <= 0.0 and get_node_or_null("/root/AudioKit") != null:
			AudioKit.set_intensity(0)
	_sim.tick(delta)
	_world.tick(delta)
	_tick_input(delta)
	# VFX artist: signature god moment — sentience achieved.
	if _sim.sentient and not _sentience_celebrated:
		_sentience_celebrated = true
		_announce_text("🧠 SENTIENCE\nThey look up at you.", 4.0)
		VFX.epoch_flash(self, _world.position + Vector3(0, 0.9, 0), Color(0.3, 0.9, 0.4))
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("levelup")
		Haptics.play_sequence("fanfare")
	_tick_flora(delta)
	_tick_fauna()
	_tick_epoch(delta)
	_save_t += delta
	if _save_t > 20.0:
		_save_t = 0.0
		_save_game()
	_update_hud()
	_check_milestones()
	if not _xr:
		_tick_demo(delta)


func _check_milestones() -> void:
	if _sim.sentient and not _sentient_announced:
		_sentient_announced = true
		_announce_text("◈ SENTIENCE ◈\nThey look up at you.", 6.0)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("levelup")
		Haptics.play_sequence("fanfare")
	if _sim.ice_age_survived and not _ice_announced:
		_ice_announced = true
		_announce_text("Your world survived\nthe ICE AGE.", 5.0)
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("success")


func _tick_input(_delta: float) -> void:
	if not _xr:
		return
	for i in [0, 1]:
		var ctl := _hands.get(i) as XRController3D
		if ctl == null or not is_instance_valid(ctl):
			continue
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var trig: bool = XRUIPointer.trigger_pressed(ctl)
		var was_t := bool(_trig_prev.get(i, false))
		_trig_prev[i] = trig
		var hp: Vector3 = ctl.global_position
		if trig and not was_t:
			GameplayTelemetry.note_input_method("controllers")
			if not _try_palette_press(hp):
				_use_tool_edge(hp)
		if trig and was_t:
			_tool_acc += _delta
			if _tool_acc > 0.08 and _tool in [0, 1]:
				_tool_acc = 0.0
				_apply_hold_tool(ctl)
		var grip: bool = ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
		var was_g := bool(_grip_prev.get(i, false))
		_grip_prev[i] = grip
		if grip and not was_g:
			_cycle_tool()


func _try_palette_press(hp: Vector3) -> bool:
	for e in _palette:
		var node := e["node"] as MeshInstance3D
		if hp.distance_to(node.global_position) < 0.16:
			var t := int(e["tool"])
			if t == _tool:
				_cycle_submode()
			else:
				_tool = t
				_refresh_palette()
			Haptics.tick()
			if get_node_or_null("/root/AudioKit") != null:
				AudioKit.play_sfx("ui_click")
			return true
	return false


## Re-pressing the active tool's button cycles its sub-mode.
func _cycle_submode() -> void:
	match _tool:
		2:
			_biome = (_biome + 1) % BIOMES.size()
		3:
			_seed_fauna = not _seed_fauna
		5:
			_disaster = (_disaster + 1) % DISASTERS.size()
	_refresh_palette()


func _cycle_tool() -> void:
	_tool = (_tool + 1) % TOOLS.size()
	# Tool sub-modes cycle on re-select via grip too.
	_refresh_palette()
	Haptics.tick()


func _tool_point(ctl: Node3D) -> Vector3:
	# Ray from the controller onto the terrain (world-local).
	var o: Vector3 = _world.to_local(ctl.global_position)
	var d: Vector3 = (_world.global_transform.basis.inverse()
		* (ctl.global_transform.basis * Vector3(0, 0, -1))).normalized()
	for t in range(1, 41):
		var tt := float(t) * 0.05
		var p := o + d * tt
		if Vector2(p.x, p.z).length() > TerraformWorld.RADIUS:
			continue
		if p.y <= _world.height_at(p) + 0.02:
			return p
	return Vector3.INF


func _use_tool_edge(hp: Vector3) -> void:
	match _tool:
		2:  # PAINT cycles biome on double duty: tap paints, grip+tap handled by cycle
			pass
		3:
			_seed_at(hp)
		4:
			_sim.fast_forward = true
			_epoch_t = 12.0
			if get_node_or_null("/root/AudioKit") != null:
				AudioKit.play_game_sfx("epoch")
			_announce_text("⏩ EPOCHS FLY PAST...", 3.0)
		5:
			_unleash(hp)


func _apply_hold_tool(ctl: Node3D) -> void:
	var p := _tool_point(ctl)
	if p == Vector3.INF:
		return
	match _tool:
		0:
			if _world.sculpt(p, 0.1, 0.012):
				_sculpt_fx()
		1:
			if _world.sculpt(p, 0.1, -0.012):
				_sculpt_fx()
		2:
			if _world.paint_at(p, 0.09, _biome):
				if _sfx_cd <= 0.0:
					_sfx_cd = 0.6
					if get_node_or_null("/root/AudioKit") != null:
						AudioKit.play_game_sfx("paint")
				Haptics.texture_tick()


func _sculpt_fx() -> void:
	if _sfx_cd <= 0.0:
		_sfx_cd = 0.7
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_game_sfx("sculpt")
	Haptics.texture_tick()


func _seed_at(hp: Vector3) -> void:
	# Seed at the terrain point under the hand.
	var p := _world.to_local(hp)
	p.y = _world.height_at(p)
	if _seed_fauna:
		var kind: String = FAUNA[_fauna_kind % FAUNA.size()]
		_fauna_kind += 1
		if _sim.seed_species(p, kind):
			_announce_text(kind.get_file().get_basename().capitalize() + " roams!", 1.5)
	else:
		if _sim.seed_flora(p):
			_announce_text("Life takes root.", 1.5)
		else:
			return
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("seed")
	Haptics.confirm()


func _unleash(hp: Vector3) -> void:
	var p := _world.to_local(hp)
	p.y = _world.height_at(p)
	match _disaster:
		0:
			_sim.disaster_meteor(p)
			_announce_text("☄ METEOR STRIKE", 2.5)
		1:
			_sim.disaster_flood()
			_announce_text("🌊 THE FLOOD", 2.5)
			# Animator: rain streaks during the flood (capped, 8s).
			if _rain != null:
				_rain.emitting = true
				_rain_t = 8.0
		2:
			_sim.disaster_volcano(p)
			_announce_text("🌋 ERUPTION", 2.5)
			# Animator: volcano smoke + lava glow pulse at the crater.
			AmbientKit.dust(_world, p + Vector3(0, 0.18, 0), 24,
				Color(0.3, 0.28, 0.27, 0.5), 0.06, 0.05, 0.4)
			var crater := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.055
			cm.bottom_radius = 0.075
			cm.height = 0.025
			crater.mesh = cm
			var lmat := StandardMaterial3D.new()
			lmat.albedo_color = Color(1, 0.3, 0.05)
			lmat.emission_enabled = true
			lmat.emission = Color(1, 0.25, 0.03)
			lmat.emission_energy_multiplier = 2.0
			crater.material_override = lmat
			crater.position = p + Vector3(0, 0.035, 0)
			_world.add_child(crater)
			_flicker.append([lmat, 2.0, 1.5, 6.0, randf() * TAU])
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("disaster")
		AudioKit.set_intensity(1)  # audio director §4d: disaster driving
		_disaster_int_t = 6.0
	Haptics.sub_bass(1.0)


## Animator ambient-life set (v0.11.0): cloud layer, city lights (industrial
## epoch), wildlife specks (birds/fish), volcano smoke + lava glow (on
## eruption), flood rain streaks.
func _build_ambient() -> void:
	# Cloud layer: 2 scrolling alpha quads at different speeds, 0 CPU.
	var cloud_shader := load("res://assets/shaders/cloud_layer.gdshader") as Shader
	for i in 2:
		var cl := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.7, 1.7)
		cl.mesh = pm
		var cmat := ShaderMaterial.new()
		cmat.shader = cloud_shader
		cmat.set_shader_parameter("scroll_speed", 0.028 + 0.02 * i)
		cmat.set_shader_parameter("coverage", 0.42 + 0.1 * i)
		cmat.set_shader_parameter("alpha", 0.5 - 0.12 * i)
		cl.material_override = cmat
		cl.rotation.x = -PI / 2.0
		cl.position = Vector3(0, 0.78 + 0.24 * i, 0)
		_world.add_child(cl)
	# City lights: <=24 emissive specks on land, fade in at industrial epoch.
	_cities = AmbientKit.quad_field(20, 0.035, Color(1.0, 0.8, 0.4), false, 1.0)
	_world.add_child(_cities)
	_city_mat = StandardMaterial3D.new()
	_city_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_city_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_city_mat.emission_enabled = true
	_city_mat.emission = Color(1.0, 0.75, 0.35)
	_city_mat.emission_energy_multiplier = 0.0
	(_cities.multimesh.mesh as QuadMesh).material = _city_mat
	var placed := 0
	var tries := 0
	while placed < 20 and tries < 200:
		tries += 1
		var p := Vector3(randf_range(-0.55, 0.55), 0, randf_range(-0.55, 0.55))
		if _world.height_at(p) > 0.06:
			p.y = _world.height_at(p) + 0.025
			_cities.multimesh.set_instance_transform(placed, Transform3D(Basis(), p))
			placed += 1
	# Wildlife specks: birds over forests, fish shadows in oceans.
	_birds = AmbientKit.quad_field(12, 0.05, Color(0.1, 0.1, 0.12, 0.85), false, 1.0)
	_world.add_child(_birds)
	_fish = AmbientKit.quad_field(8, 0.07, Color(0.05, 0.12, 0.2, 0.7), false, 1.0)
	_world.add_child(_fish)
	for i in 20:
		_speck_phase.append(randf() * TAU)
	# Flood rain: 1 capped streak emitter, off until a flood.
	_rain = _make_rain()
	_world.add_child(_rain)


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.1
	p.preprocess = 1.1
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.local_coords = true
	p.position = Vector3(0, 1.3, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.1, 0.7)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.gravity = Vector3(0, -3.5, 0)
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 2.5
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.6, 0.75, 1.0, 0.5)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = false
	return p


func _process(delta: float) -> void:
	_amb_t += delta
	# Wildlife specks: birds circle high, fish glide low (phase-offset).
	if _birds != null and is_instance_valid(_birds):
		var mm := _birds.multimesh
		for i in 12:
			var ph := float(_speck_phase[i])
			var ang := _amb_t * 0.5 + ph
			var r := 0.45 + 0.18 * sin(ph * 2.0)
			var pos := Vector3(cos(ang) * r, 0.72 + 0.1 * sin(_amb_t * 0.6 + ph), sin(ang) * r)
			var flap := 1.0 + 0.4 * sin(_amb_t * 10.0 + ph * 6.0)
			_amb_xf = Transform3D(Basis.from_scale(Vector3(flap, 1.0, 1.0)), pos)
			mm.set_instance_transform(i, _amb_xf)
	if _fish != null and is_instance_valid(_fish):
		var fm := _fish.multimesh
		for i in 8:
			var ph := float(_speck_phase[12 + i])
			var ang := -_amb_t * 0.3 + ph
			var r := 0.3 + 0.12 * sin(ph * 3.0)
			var pos := Vector3(cos(ang) * r, 0.035, sin(ang) * r)
			_amb_xf = Transform3D(Basis.from_scale(Vector3.ONE).rotated(Vector3.UP, -ang), pos)
			fm.set_instance_transform(i, _amb_xf)
	# City lights fade in at the industrial epoch (epochs >= 2).
	if _city_mat != null and _sim != null:
		var target := 2.2 if _sim.epochs >= 2 else 0.0
		var cur := _city_mat.emission_energy_multiplier
		_city_mat.emission_energy_multiplier = lerpf(cur, target, minf(1.0, delta * 0.8))
	# Flood rain runs 8s.
	if _rain_t > 0.0:
		_rain_t -= delta
		if _rain_t <= 0.0 and _rain != null:
			_rain.emitting = false
	AmbientKit.tick_flicker(_flicker, _amb_t)


func _tick_epoch(delta: float) -> void:
	if _epoch_t > 0.0:
		_epoch_t -= delta
		if _epoch_t <= 0.0:
			_sim.fast_forward = false


# ------------------------------------------------------------ flora/fauna ---

func _tick_flora(delta: float) -> void:
	_flora_t += delta
	if _flora_t < 1.5:
		return
	_flora_t = 0.0
	var kinds := _flora_mm.keys()
	var counts := {}
	for k in kinds:
		counts[k] = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for c in TerraformSim.G * TerraformSim.G:
		var v: float = _sim.veg[c]
		if v < 0.35:
			continue
		var kind: String = kinds[c % kinds.size()]
		if int(counts[kind]) >= 90:
			continue
		var p := _sim.cell_center(c)
		p.x += rng.randf_range(-0.02, 0.02)
		p.z += rng.randf_range(-0.02, 0.02)
		var t := Transform3D(Basis().scaled(Vector3.ONE * (0.25 + v * 0.6)), p)
		(_flora_mm[kind] as MultiMeshInstance3D).multimesh.set_instance_transform(int(counts[kind]), t)
		counts[kind] = int(counts[kind]) + 1
	for k in kinds:
		var mm := (_flora_mm[k] as MultiMeshInstance3D).multimesh
		for i in range(int(counts[k]), 90):
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -10, 0)))


func _tick_fauna() -> void:
	var seen := {}
	for i in _sim.animals.size():
		seen[i] = true
		var a: Dictionary = _sim.animals[i]
		var node := _fauna_nodes.get(i) as Node3D
		if node == null or not is_instance_valid(node):
			node = _make_fauna_node(str(a["kind"]))
			_world.add_child(node)
			_fauna_nodes[i] = node
		var p: Vector3 = a["pos"]
		var prev: Vector3 = node.position
		node.position = p
		var d: Vector3 = p - prev
		if Vector2(d.x, d.z).length() > 0.001:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-d.x, -d.z), 0.2)
	for k in _fauna_nodes.keys():
		if not seen.has(k):
			var n := _fauna_nodes[k] as Node
			if is_instance_valid(n):
				n.queue_free()
			_fauna_nodes.erase(k)


func _make_fauna_node(kind: String) -> Node3D:
	var n := Node3D.new()
	var ps: PackedScene = load(MODEL_DIR + kind + ".glb") as PackedScene
	if ps != null:
		var inst := ps.instantiate() as Node3D
		inst.scale = Vector3.ONE * 0.12
		n.add_child(inst)
	return n


# --------------------------------------------------------------- save ---

func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("planet", "heights", Array(_world.heights))
	cfg.set_value("planet", "paint", Array(_world.paint))
	cfg.set_value("planet", "epochs", _sim.epochs)
	cfg.set_value("planet", "epoch_t", _sim.epoch_t)
	cfg.set_value("planet", "sentient", _sim.sentient)
	cfg.set_value("planet", "ice_age_survived", _sim.ice_age_survived)
	cfg.set_value("planet", "veg", Array(_sim.veg))
	var an := []
	for a in _sim.animals:
		var ad := a as Dictionary
		an.append([ad["kind"], (ad["pos"] as Vector3).x, (ad["pos"] as Vector3).y, (ad["pos"] as Vector3).z])
	cfg.set_value("planet", "animals", an)
	cfg.set_value("planet", "saved_at", Time.get_unix_time_from_system())
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var h: Array = cfg.get_value("planet", "heights", [])
	if h.size() == TerraformWorld.N * TerraformWorld.N:
		for i in h.size():
			_world.heights[i] = float(h[i])
	var pt: Array = cfg.get_value("planet", "paint", [])
	if pt.size() == TerraformWorld.N * TerraformWorld.N:
		for i in pt.size():
			_world.paint[i] = int(pt[i])
	var vg: Array = cfg.get_value("planet", "veg", [])
	if vg.size() == TerraformSim.G * TerraformSim.G:
		for i in vg.size():
			_sim.veg[i] = float(vg[i])
	_sim.epochs = int(cfg.get_value("planet", "epochs", 0))
	_sim.epoch_t = float(cfg.get_value("planet", "epoch_t", 0.0))
	_sim.sentient = bool(cfg.get_value("planet", "sentient", false))
	_sim.ice_age_survived = bool(cfg.get_value("planet", "ice_age_survived", false))
	_sentient_announced = _sim.sentient
	_ice_announced = _sim.ice_age_survived
	for a in cfg.get_value("planet", "animals", []):
		var ad: Array = a
		_sim.animals.append({"pos": Vector3(float(ad[1]), float(ad[2]), float(ad[3])),
			"kind": str(ad[0]), "hunger": 0.0, "age": 50.0})
	_world.rebuild()
	# While you were away: evolve a little (capped).
	var away := Time.get_unix_time_from_system() - float(cfg.get_value("planet", "saved_at", 0.0))
	if away > 60.0:
		var steps := mini(200, int(away / 3600.0 * 40.0))
		for s in steps:
			_sim._sim_step(0.5)
		_announce_text("While you were away...\n%d seasons passed." % (steps / 4), 4.0)


# ------------------------------------------------- desktop/headless demo ---

func _tick_demo(delta: float) -> void:
	_demo_t += delta
	var c := Vector3.ZERO
	if _demo_stage == 0 and _demo_t > 1.0:
		_demo_stage = 1
		_world.sculpt(c, 0.2, 0.15)
		_world.paint_at(c, 0.25, 0)
	elif _demo_stage == 1 and _demo_t > 2.5:
		_demo_stage = 2
		_sim.seed_flora(c + Vector3(0.1, 0, 0.1))
		_sim.seed_species(c + Vector3(-0.1, 0, 0.1), FAUNA[0])
		_sim.seed_species(c + Vector3(0.15, 0, -0.1), FAUNA[1])
	elif _demo_stage == 2 and _demo_t > 4.0:
		_demo_stage = 3
		_sim.fast_forward = true
		_epoch_t = 6.0
	elif _demo_stage == 3 and _demo_t > 8.0:
		_demo_stage = 4
		_sim.disaster_meteor(c + Vector3(0.2, 0, 0.2))
		_save_game()
	elif _demo_stage == 4 and _demo_t > 10.0:
		_demo_stage = 5
		_load_save()  # round-trip the save
