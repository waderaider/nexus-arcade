## Mech Pilot: first-person mech combat in a room-scale AR arena.
## You pilot a combat mech from the cockpit (frame, arms and arm-cannon visible
## at the screen edges). Hand-throttle: push your hand forward/back to move,
## yaw your hand to turn. Fast hand thrust = mech fist jab. Pinch-hold charges
## the arm cannon, release to fire an energy blast.
## Missions: (1) destroy 8 rogue drones, (2) defend the beacon for 60s,
## (3) kill the armored walker (hit its glowing core for 3x damage).
## Desktop: drag mouse = throttle/turn, click = jab, hold E + release = blast,
## W/S/A/D also drive. R restarts. Best score persists to user://nexus_mech.cfg.
extends Node3D

const MOVE_SPEED := 1.7
const TURN_SPEED := 1.7
const PUNCH_RANGE := 1.9
const PUNCH_HALF_ANGLE := 0.55
const PUNCH_COOLDOWN := 0.8
const PUNCH_DAMAGE := 2
const BLAST_SPEED := 9.0
const BLAST_COST := 22.0
const BLAST_DAMAGE := 2
const ENERGY_REGEN := 14.0
const DRONE_HP := 2
const DRONES_TO_KILL := 8
const MAX_DRONES_ALIVE := 3
const DEFEND_TIME := 60.0
const BEACON_HP := 100.0
const BOSS_HP := 24
const DRONE_BOLT_DAMAGE := 8.0
const BOSS_SLAM_DAMAGE := 16.0
const BEST_FILE := "user://nexus_mech.cfg"

var camera: Camera3D = null
var cam_base_pos := Vector3(0.0, 1.6, 0.0)
var cockpit: Node3D = null
var arm_l: Node3D = null
var arm_r: Node3D = null
var arm_l_base := Vector3.ZERO
var arm_r_base := Vector3.ZERO
var cannon_charge_glow: MeshInstance3D = null
var cannon_charge_mat: StandardMaterial3D = null

var drones: Array = []
var projectiles: Array = []
var shockwaves: Array = []

var mission := 0  # 0 = briefing, 1..3 = missions
var phase := "brief"
var brief_text := ""
var brief_t := 0.0
var drones_destroyed := 0
var defend_t := 0.0
var beacon: Node3D = null
var beacon_hp := BEACON_HP
var beacon_core_mat: StandardMaterial3D = null
var boss: Dictionary = {}

var health := 100.0
var energy := 100.0
var score := 0
var best := 0
var punch_cd := 0.0
var charging := false
var charge := 0.0
var shake := 0.0
var msg := ""
var msg_t := 0.0
var pulse_t := 0.0
var drone_spawn_t := 0.0
var wave_num := 0
var defense_failed := false

# Desktop input state.
var dragging := false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var prev_space := false
var prev_e := false
# XR input state.
var xr_prev_hand := Vector3.ZERO
var xr_hand_vel := Vector3.ZERO
var xr_has_prev := false
var xr_prev_pinch := false

var hud_health_bar: MeshInstance3D = null
var hud_energy_bar: MeshInstance3D = null
var hud_health_bg: MeshInstance3D = null
var hud_energy_bg: MeshInstance3D = null
var hud_mission: Label3D = null
var hud_score: Label3D = null
var hud_msg: Label3D = null
var hud_help: Label3D = null
var hud_bars: Node3D = null

var _model_cache := {}


func _load_model(file_name: String) -> Node3D:
	var path := "res://assets/models/mech_pilot/" + file_name + ".fbx"
	if _model_cache.has(path):
		var cached: PackedScene = _model_cache[path]
		if cached != null and is_instance_valid(cached):
			return cached.instantiate() as Node3D
		_model_cache.erase(path)
	if not ResourceLoader.exists(path):
		push_warning("[mech_pilot] missing model: " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[mech_pilot] failed to load: " + path)
		return null
	_model_cache[path] = ps
	return ps.instantiate() as Node3D


func _recolor(root: Node, albedo: Color, metallic: float = 0.0, roughness: float = 0.55, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> void:
	if root == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "mech_pilot_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_best()
	_build_arena()
	_build_cockpit()
	_build_hud()
	_start_brief("MECH PILOT // SYSTEMS ONLINE\nMission 1: Destroy 8 rogue drones", 3.0, 1)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, 0.0), 2.5, 40)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		cam_base_pos = camera.position
		return
	camera = Camera3D.new()
	camera.position = cam_base_pos
	add_child(camera)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.32, 0.45)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.03, 0.05, 0.09)
	env.fog_depth_begin = 4.0
	env.fog_depth_end = 14.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 1.0)


func _build_arena() -> void:
	# Floor plate.
	var floor_inst := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(9.0, 9.0)
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.07, 0.08, 0.10), 0.6, 0.45)
	floor_inst.position = Vector3(0.0, 0.0, 0.0)
	add_child(floor_inst)
	# Glowing grid lines for the mech-bay look.
	for i in range(-3, 4):
		for axis in 2:
			var line := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.03, 0.012, 9.0) if axis == 0 else Vector3(9.0, 0.012, 0.03)
			line.mesh = lbox
			line.material_override = GraphicsPolish.glow(Color(0.1, 0.55, 0.8), 0.9)
			line.position = Vector3(float(i) * 1.25, 0.008, 0.0)
			add_child(line)
	# Corner machines + crates + cogs as bay dressing.
	var machine_spots := [
		Vector3(-2.9, 0.0, -2.9), Vector3(2.9, 0.0, -2.9),
		Vector3(-2.9, 0.0, 2.9), Vector3(2.9, 0.0, 2.9),
	]
	var mi := 0
	for spot in machine_spots:
		var m: Node3D = _load_model("machine" if mi % 2 == 0 else "machine-fortified")
		if m != null:
			_recolor(m, Color(0.22, 0.24, 0.28), 0.7, 0.4)
			m.position = spot
			m.rotation.y = deg_to_rad(45.0 + float(mi) * 90.0)
			m.scale = Vector3.ONE * 1.4
			add_child(m)
		mi += 1
	var crate_spots := [Vector3(-2.2, 0.0, -1.2), Vector3(2.3, 0.0, -0.8), Vector3(1.8, 0.0, 2.4)]
	for spot in crate_spots:
		var c: Node3D = _load_model("crate-small")
		if c != null:
			_recolor(c, Color(0.35, 0.28, 0.16), 0.1, 0.7)
			c.position = spot + Vector3(0, 0.22, 0)
			c.rotation.y = randf_range(0.0, TAU)
			add_child(c)
	# Hazard pillars with warning glow.
	for k in 4:
		var ang := deg_to_rad(45.0 + float(k) * 90.0)
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.18, 2.6, 0.18)
		pillar.mesh = pbox
		pillar.material_override = GraphicsPolish.pbr(Color(0.16, 0.16, 0.18), 0.5, 0.5)
		pillar.position = Vector3(cos(ang) * 3.6, 1.3, sin(ang) * 3.6)
		add_child(pillar)
		var strip := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.20, 0.08, 0.20)
		strip.mesh = sbox
		strip.material_override = GraphicsPolish.glow(Color(1.0, 0.45, 0.1), 1.6)
		strip.position = Vector3(cos(ang) * 3.6, 2.35, sin(ang) * 3.6)
		add_child(strip)
	GraphicsPolish.make_point_light(self, Vector3(0, 3.2, 0), Color(0.5, 0.75, 1.0), 1.2, 9.0)


func _build_cockpit() -> void:
	if camera == null:
		return
	cockpit = Node3D.new()
	camera.add_child(cockpit)
	var dark_metal := GraphicsPolish.pbr(Color(0.09, 0.10, 0.13), 0.7, 0.35)
	# Canopy frame: top bar and side struts at the screen edges.
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(1.5, 0.07, 0.06)
	top.mesh = top_box
	top.material_override = dark_metal
	top.position = Vector3(0.0, 0.52, -0.85)
	cockpit.add_child(top)
	for side in [-1.0, 1.0]:
		var strut := MeshInstance3D.new()
		var strut_box := BoxMesh.new()
		strut_box.size = Vector3(0.06, 1.05, 0.06)
		strut.mesh = strut_box
		strut.material_override = dark_metal
		strut.position = Vector3(side * 0.72, 0.0, -0.85)
		strut.rotation.z = deg_to_rad(side * -6.0)
		cockpit.add_child(strut)
		var strip := MeshInstance3D.new()
		var strip_box := BoxMesh.new()
		strip_box.size = Vector3(0.015, 0.9, 0.015)
		strip.mesh = strip_box
		strip.material_override = GraphicsPolish.glow(Color(0.15, 0.8, 1.0), 1.8)
		strip.position = Vector3(side * 0.685, 0.0, -0.82)
		strip.rotation.z = deg_to_rad(side * -6.0)
		cockpit.add_child(strip)
	# Console: Kenney machine + screen across the bottom.
	var console: Node3D = _load_model("machine")
	if console != null:
		_recolor(console, Color(0.14, 0.15, 0.18), 0.6, 0.4)
		console.position = Vector3(0.0, -0.62, -0.95)
		console.scale = Vector3.ONE * 0.55
		cockpit.add_child(console)
	var screen: Node3D = _load_model("screen-panel-wide")
	if screen != null:
		_recolor(screen, Color(0.10, 0.12, 0.14), 0.4, 0.4, Color(0.2, 0.9, 1.0), 0.8)
		screen.position = Vector3(0.0, -0.38, -0.92)
		screen.scale = Vector3.ONE * 0.5
		cockpit.add_child(screen)
	# Mech arms at the screen edges (Kenney robot arms, scaled up).
	arm_l = _load_model("robot-arm-a")
	if arm_l != null:
		_recolor(arm_l, Color(0.30, 0.32, 0.36), 0.75, 0.35, Color(1.0, 0.5, 0.1), 0.35)
		arm_l_base = Vector3(-0.62, -0.42, -0.75)
		arm_l.position = arm_l_base
		arm_l.rotation_degrees = Vector3(-12, 18, 8)
		arm_l.scale = Vector3.ONE * 1.5
		cockpit.add_child(arm_l)
	arm_r = _load_model("robot-arm-b")
	if arm_r != null:
		_recolor(arm_r, Color(0.30, 0.32, 0.36), 0.75, 0.35, Color(1.0, 0.5, 0.1), 0.35)
		arm_r_base = Vector3(0.62, -0.42, -0.75)
		arm_r.position = arm_r_base
		arm_r.rotation_degrees = Vector3(-12, -18, -8)
		arm_r.scale = Vector3.ONE * 1.5
		cockpit.add_child(arm_r)
		# Arm cannon on the right fist.
		var cannon: Node3D = _load_model("blaster-e")
		if cannon != null:
			_recolor(cannon, Color(0.18, 0.20, 0.24), 0.8, 0.3, Color(0.2, 0.8, 1.0), 0.6)
			cannon.position = Vector3(0.0, -0.35, -0.25)
			cannon.rotation_degrees = Vector3(-90, 0, 0)
			cannon.scale = Vector3.ONE * 0.9
			arm_r.add_child(cannon)
		# Charge glow at the cannon tip.
		cannon_charge_mat = GraphicsPolish.glow(Color(0.3, 0.9, 1.0), 0.4)
		cannon_charge_glow = MeshInstance3D.new()
		var csph := SphereMesh.new()
		csph.radius = 0.035
		csph.height = 0.07
		cannon_charge_glow.mesh = csph
		cannon_charge_glow.material_override = cannon_charge_mat
		cannon_charge_glow.position = Vector3(0.0, -0.35, -0.62)
		arm_r.add_child(cannon_charge_glow)


func _bar(pos: Vector3, size: Vector2, bg_color: Color, fg_color: Color, glow_e: float) -> Array:
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(size.x + 0.012, size.y + 0.012, 0.008)
	bg.mesh = bgm
	bg.material_override = GraphicsPolish.pbr(bg_color, 0.2, 0.6)
	bg.position = pos
	var fg := MeshInstance3D.new()
	var fgm := BoxMesh.new()
	fgm.size = Vector3(size.x, size.y, 0.012)
	fg.mesh = fgm
	fg.material_override = GraphicsPolish.glow(fg_color, glow_e)
	fg.position = pos + Vector3(0, 0, 0.004)
	hud_bars.add_child(bg)
	hud_bars.add_child(fg)
	return [bg, fg, pos, size.x]


func _set_bar(bar: Array, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	var fg: MeshInstance3D = bar[1]
	var pos: Vector3 = bar[2]
	var full_w: float = bar[3]
	fg.scale.x = maxf(frac, 0.001)
	fg.position.x = pos.x - full_w * (1.0 - frac) * 0.5


func _build_hud() -> void:
	if camera == null:
		return
	hud_bars = Node3D.new()
	camera.add_child(hud_bars)
	var bars := _bar(Vector3(-0.52, 0.40, -0.8), Vector2(0.42, 0.035), Color(0.1, 0.1, 0.1), Color(0.2, 1.0, 0.35), 1.4)
	hud_health_bg = bars[0]
	hud_health_bar = bars[1]
	var bars2 := _bar(Vector3(-0.52, 0.345, -0.8), Vector2(0.42, 0.028), Color(0.1, 0.1, 0.1), Color(0.2, 0.85, 1.0), 1.4)
	hud_energy_bg = bars2[0]
	hud_energy_bar = bars2[1]
	var hp_lbl := GraphicsPolish.make_label("HULL", 28, Color(0.7, 1.0, 0.8))
	hp_lbl.position = Vector3(-0.78, 0.40, -0.8)
	hp_lbl.pixel_size = 0.0028
	camera.add_child(hp_lbl)
	var en_lbl := GraphicsPolish.make_label("NRG", 28, Color(0.7, 0.9, 1.0))
	en_lbl.position = Vector3(-0.78, 0.345, -0.8)
	en_lbl.pixel_size = 0.0028
	camera.add_child(en_lbl)
	hud_mission = GraphicsPolish.make_label("", 40, Color(1.0, 0.85, 0.45))
	hud_mission.position = Vector3(0.0, 0.44, -0.85)
	hud_mission.pixel_size = 0.0032
	camera.add_child(hud_mission)
	hud_score = GraphicsPolish.make_label("", 36, Color(0.85, 0.95, 1.0))
	hud_score.position = Vector3(0.62, 0.40, -0.8)
	hud_score.pixel_size = 0.003
	camera.add_child(hud_score)
	hud_msg = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.5))
	hud_msg.position = Vector3(0.0, 0.10, -1.1)
	hud_msg.pixel_size = 0.0042
	camera.add_child(hud_msg)
	hud_help = GraphicsPolish.make_label("", 26, Color(0.7, 0.78, 0.9))
	hud_help.position = Vector3(0.0, -0.52, -0.85)
	hud_help.pixel_size = 0.0026
	camera.add_child(hud_help)
	_update_hud()


func _update_hud() -> void:
	if hud_health_bar != null:
		_set_bar([hud_health_bg, hud_health_bar, Vector3(-0.52, 0.40, -0.8), 0.42], health / 100.0)
	if hud_energy_bar != null:
		_set_bar([hud_energy_bg, hud_energy_bar, Vector3(-0.52, 0.345, -0.8), 0.42], energy / 100.0)
	if hud_score != null:
		hud_score.text = "SCORE %d" % score
	if hud_mission != null:
		match mission:
			0:
				hud_mission.text = "STANDBY"
			1:
				hud_mission.text = "M1: KILL DRONES %d/%d" % [drones_destroyed, DRONES_TO_KILL]
			2:
				hud_mission.text = "M2: DEFEND %ds  BEACON %d%%" % [int(ceil(defend_t)), int(beacon_hp)]
			3:
				var bhp := 0.0
				if not boss.is_empty():
					bhp = float(boss.get("hp", 0.0))
				hud_mission.text = "M3: WALKER HULL %d%%" % int(bhp / BOSS_HP * 100.0)
	if hud_msg != null:
		hud_msg.text = msg
	if hud_help != null:
		if ARUpgradeKit.is_xr_active():
			hud_help.text = "Push hand: throttle | thrust: jab | pinch hold+release: blast"
		else:
			hud_help.text = "Drag: drive | Click: jab | Hold E, release: blast | W/S/A/D drive | R restart"


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _start_brief(text: String, hold: float, next_mission: int) -> void:
	phase = "brief"
	brief_text = text
	brief_t = hold
	mission = -next_mission  # negative = pending mission id
	_set_msg(text, hold + 0.5)


func _begin_mission(m: int) -> void:
	mission = m
	phase = "play"
	_clear_field()
	match m:
		1:
			drones_destroyed = 0
			drone_spawn_t = 0.0
			_set_msg("MISSION 1: DESTROY 8 ROGUE DRONES", 2.5)
		2:
			defend_t = DEFEND_TIME
			beacon_hp = BEACON_HP
			wave_num = 0
			drone_spawn_t = 0.0
			_build_beacon()
			_set_msg("MISSION 2: DEFEND THE BEACON", 2.5)
		3:
			_spawn_boss()
			_set_msg("MISSION 3: KILL THE ARMORED WALKER", 2.5)
	_update_hud()


func _clear_field() -> void:
	for d in drones:
		var n: Node3D = d.get("node")
		if n != null and is_instance_valid(n):
			n.queue_free()
	drones.clear()
	for p in projectiles:
		var n2: Node3D = p.get("node")
		if n2 != null and is_instance_valid(n2):
			n2.queue_free()
	projectiles.clear()
	for s in shockwaves:
		var n3: Node3D = s.get("node")
		if n3 != null and is_instance_valid(n3):
			n3.queue_free()
	shockwaves.clear()
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()
	beacon = null
	if not boss.is_empty():
		var bn: Node3D = boss.get("node")
		if bn != null and is_instance_valid(bn):
			bn.queue_free()
	boss = {}


func _make_drone() -> Dictionary:
	var root := Node3D.new()
	var body: Node3D = _load_model("box-small")
	if body != null:
		_recolor(body, Color(0.16, 0.17, 0.20), 0.7, 0.35)
		body.scale = Vector3.ONE * 1.7
		root.add_child(body)
	# Spinning rotor.
	var rotor: Node3D = _load_model("cog-a")
	if rotor != null:
		_recolor(rotor, Color(0.25, 0.26, 0.30), 0.8, 0.3)
		rotor.position = Vector3(0, 0.42, 0)
		rotor.scale = Vector3.ONE * 0.9
		root.add_child(rotor)
	# Red sensor eye.
	var eye := MeshInstance3D.new()
	var esph := SphereMesh.new()
	esph.radius = 0.09
	esph.height = 0.18
	eye.mesh = esph
	eye.material_override = GraphicsPolish.glow(Color(1.0, 0.15, 0.1), 2.4)
	eye.position = Vector3(0, 0.05, 0.30)
	root.add_child(eye)
	# Under-glow.
	var uglow := MeshInstance3D.new()
	var usph := SphereMesh.new()
	usph.radius = 0.16
	usph.height = 0.06
	uglow.mesh = usph
	uglow.material_override = GraphicsPolish.glow(Color(1.0, 0.3, 0.1), 1.2)
	uglow.position = Vector3(0, -0.28, 0)
	root.add_child(uglow)
	add_child(root)
	var ang := randf_range(0.0, TAU)
	var r := randf_range(2.4, 3.2)
	root.position = ARUpgradeKit.clamp_to_room(Vector3(cos(ang) * r, randf_range(1.3, 1.9), sin(ang) * r))
	GraphicsPolish.spawn_sparks(self, root.position, Color(1.0, 0.4, 0.1), 10)
	return {"node": root, "hp": DRONE_HP, "rotor": rotor, "eye": eye, "shoot_t": randf_range(1.0, 2.5), "strafe": [-1.0, 1.0][randi() % 2], "orbit_r": r, "ang": ang, "flash": 0.0}


func _spawn_drone_wave(n: int) -> void:
	for i in n:
		if drones.size() < MAX_DRONES_ALIVE + 2:
			drones.append(_make_drone())


func _build_beacon() -> void:
	beacon = Node3D.new()
	beacon.position = Vector3(0.0, 0.0, -2.4)
	add_child(beacon)
	var base: Node3D = _load_model("machine-fortified")
	if base != null:
		_recolor(base, Color(0.20, 0.22, 0.26), 0.7, 0.4)
		base.scale = Vector3.ONE * 1.2
		beacon.add_child(base)
	var pillar := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.16
	pcyl.bottom_radius = 0.22
	pcyl.height = 1.8
	pillar.mesh = pcyl
	pillar.material_override = GraphicsPolish.pbr(Color(0.18, 0.20, 0.24), 0.7, 0.35)
	pillar.position = Vector3(0, 1.15, 0)
	beacon.add_child(pillar)
	beacon_core_mat = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 2.2)
	var core := MeshInstance3D.new()
	var csph := SphereMesh.new()
	csph.radius = 0.22
	csph.height = 0.44
	core.mesh = csph
	core.material_override = beacon_core_mat
	core.position = Vector3(0, 2.25, 0)
	beacon.add_child(core)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	ring.mesh = torus
	ring.material_override = GraphicsPolish.glow(Color(0.2, 0.9, 1.0), 1.4)
	ring.position = Vector3(0, 0.12, 0)
	beacon.add_child(ring)
	GraphicsPolish.make_point_light(beacon, Vector3(0, 2.3, 0), Color(0.3, 0.85, 1.0), 1.4, 5.0)


func _spawn_boss() -> void:
	var root := Node3D.new()
	# Legs: two giant robot arms stomping.
	for side in [-1.0, 1.0]:
		var leg: Node3D = _load_model("robot-arm-b")
		if leg != null:
			_recolor(leg, Color(0.24, 0.16, 0.14), 0.75, 0.4, Color(1.0, 0.3, 0.1), 0.5)
			leg.position = Vector3(side * 0.75, 0.0, 0.0)
			leg.scale = Vector3.ONE * 3.2
			root.add_child(leg)
	# Torso: fortified machine block.
	var torso: Node3D = _load_model("machine-fortified")
	if torso != null:
		_recolor(torso, Color(0.28, 0.18, 0.14), 0.7, 0.4)
		torso.position = Vector3(0, 2.6, 0)
		torso.scale = Vector3(2.2, 1.6, 1.6)
		root.add_child(torso)
	# Shoulder guns.
	for side in [-1.0, 1.0]:
		var gun: Node3D = _load_model("blaster-c")
		if gun != null:
			_recolor(gun, Color(0.15, 0.15, 0.18), 0.8, 0.3, Color(1.0, 0.35, 0.1), 0.7)
			gun.position = Vector3(side * 1.5, 2.7, 0.2)
			gun.rotation_degrees = Vector3(0, 180, 0)
			gun.scale = Vector3.ONE * 1.8
			root.add_child(gun)
	# Weak-point core: glowing sphere on the chest.
	var core_mat := GraphicsPolish.glow(Color(1.0, 0.25, 0.1), 2.6)
	var core := MeshInstance3D.new()
	var csph := SphereMesh.new()
	csph.radius = 0.34
	csph.height = 0.68
	core.mesh = csph
	core.material_override = core_mat
	core.position = Vector3(0, 2.6, 0.85)
	root.add_child(core)
	root.position = Vector3(0.0, 0.0, -3.0)
	add_child(root)
	GraphicsPolish.make_point_light(root, Vector3(0, 2.8, 1.2), Color(1.0, 0.4, 0.15), 1.2, 6.0)
	boss = {"node": root, "hp": BOSS_HP, "core": core, "core_mat": core_mat,
		"slam_t": 3.0, "shot_t": 1.5, "telegraph": 0.0, "stomp_ph": 0.0}


func _player_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.4, 0.0)


func _fire_bolt(from: Vector3, target: Vector3, speed: float, damage: float, color: Color) -> void:
	var root := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.07
	sph.height = 0.14
	root.mesh = sph
	root.material_override = GraphicsPolish.glow(color, 2.2)
	root.position = from
	root.add_child(GraphicsPolish.make_trail(color, 0.04))
	add_child(root)
	var dir: Vector3 = (target - from).normalized()
	projectiles.append({"node": root, "vel": dir * speed, "friendly": false, "life": 4.0, "dmg": damage})


func _fire_blast(power: float) -> void:
	if camera == null or energy < BLAST_COST * 0.4:
		_set_msg("ENERGY LOW", 0.8)
		return
	energy = maxf(0.0, energy - BLAST_COST * (0.4 + 0.6 * power))
	var from: Vector3 = camera.global_position + Vector3(0, -0.15, 0) + (-camera.global_transform.basis.z).normalized() * 0.7
	var root := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09 + 0.08 * power
	sph.height = (0.09 + 0.08 * power) * 2.0
	root.mesh = sph
	root.material_override = GraphicsPolish.glow(Color(0.35, 0.9, 1.0), 2.6)
	root.position = from
	root.add_child(GraphicsPolish.make_trail(Color(0.35, 0.9, 1.0), 0.06))
	add_child(root)
	var dir: Vector3 = (-camera.global_transform.basis.z).normalized()
	projectiles.append({"node": root, "vel": dir * (BLAST_SPEED + 3.0 * power), "friendly": true, "life": 3.0, "dmg": BLAST_DAMAGE + int(power * 2.0)})
	Haptics.pulse(0.5, 0.1)
	_update_hud()


func _do_punch() -> void:
	if punch_cd > 0.0 or phase != "play":
		return
	punch_cd = PUNCH_COOLDOWN
	# Right fist lunges.
	if arm_r != null:
		arm_r.position = arm_r_base + Vector3(0.1, 0.05, -0.55)
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var origin := _player_pos()
	var hit_any := false
	for d in drones:
		var n: Node3D = d.get("node")
		if n == null or not is_instance_valid(n) or bool(d.get("dead", false)):
			continue
		var to: Vector3 = n.global_position - origin
		var dist := to.length()
		if dist < PUNCH_RANGE:
			var ang := fwd.angle_to(Vector3(to.x, 0, to.z).normalized())
			if ang < PUNCH_HALF_ANGLE:
				_damage_drone(d, PUNCH_DAMAGE, n.global_position)
				hit_any = true
	if not boss.is_empty():
		var bn: Node3D = boss.get("node")
		if bn != null and is_instance_valid(bn):
			var to_b: Vector3 = bn.global_position + Vector3(0, 1.6, 0) - origin
			if to_b.length() < PUNCH_RANGE + 1.2:
				_damage_boss(PUNCH_DAMAGE, false)
				hit_any = true
	_spawn_shockwave(origin + fwd * 1.1 + Vector3(0, -0.2, 0), Color(1.0, 0.7, 0.25), 1.6)
	GraphicsPolish.spawn_sparks(self, origin + fwd * 1.2, Color(1.0, 0.75, 0.3), 18)
	shake = maxf(shake, 0.22 if hit_any else 0.1)
	Haptics.thump()
	if hit_any:
		_set_msg("DIRECT HIT!", 0.7)


func _spawn_shockwave(pos: Vector3, color: Color, max_r: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.55
	ring.mesh = torus
	ring.material_override = GraphicsPolish.glow(color, 1.8)
	ring.position = pos
	add_child(ring)
	shockwaves.append({"node": ring, "t": 0.0, "max_r": max_r})


func _damage_drone(d: Dictionary, dmg: int, at: Vector3) -> void:
	d["hp"] = int(d.get("hp", 1)) - dmg
	d["flash"] = 0.25
	GraphicsPolish.spawn_sparks(self, at, Color(1.0, 0.6, 0.15), 14)
	if int(d.get("hp", 0)) <= 0 and not bool(d.get("dead", false)):
		d["dead"] = true
		var n: Node3D = d.get("node")
		if n != null and is_instance_valid(n):
			GraphicsPolish.spawn_confetti(self, n.global_position, 40)
			GraphicsPolish.spawn_sparks(self, n.global_position, Color(1.0, 0.5, 0.1), 30)
			n.queue_free()
		# Swept out of the drones array by _update_drones (never erase mid-loop).
		drones_destroyed += 1
		score += 100
		shake = maxf(shake, 0.18)
		Haptics.pulse(0.6, 0.12)
		_update_hud()


func _damage_boss(dmg: int, core_hit: bool) -> void:
	if boss.is_empty():
		return
	var dealt := dmg * 3 if core_hit else dmg
	boss["hp"] = float(boss.get("hp", 0.0)) - float(dealt)
	var bn: Node3D = boss.get("node")
	var at: Vector3 = bn.global_position + Vector3(0, 2.4, 0) if bn != null else _player_pos()
	GraphicsPolish.spawn_sparks(self, at, Color(1.0, 0.4, 0.1) if core_hit else Color(1.0, 0.7, 0.2), 20 if core_hit else 10)
	shake = maxf(shake, 0.3 if core_hit else 0.15)
	Haptics.pulse(0.8, 0.15)
	if core_hit:
		_set_msg("CORE HIT! 3x DAMAGE", 0.8)
	if float(boss.get("hp", 0.0)) <= 0.0:
		_kill_boss()


func _kill_boss() -> void:
	var bn: Node3D = boss.get("node")
	if bn != null and is_instance_valid(bn):
		var bp: Vector3 = bn.global_position + Vector3(0, 2.0, 0)
		GraphicsPolish.spawn_confetti(self, bp, 90)
		GraphicsPolish.spawn_sparks(self, bp, Color(1.0, 0.5, 0.1), 60)
		GraphicsPolish.spawn_sparks(self, bp + Vector3(0, 1, 0), Color(1.0, 0.85, 0.3), 40)
		bn.queue_free()
	boss = {}
	score += 1000
	_save_best()
	phase = "victory"
	_set_msg("WALKER DESTROYED!\nSCORE %d  (BEST %d)\nR to play again" % [score, best], 60.0)
	GraphicsPolish.spawn_confetti(self, _player_pos() + Vector3(0, 1, -1), 80)
	_update_hud()


func _hurt_player(dmg: float, from: Vector3) -> void:
	if phase != "play":
		return
	health = maxf(0.0, health - dmg)
	shake = maxf(shake, 0.35)
	Haptics.pulse(0.9, 0.2)
	GraphicsPolish.spawn_sparks(self, _player_pos() + Vector3(0, -0.3, 0), Color(1.0, 0.2, 0.15), 16)
	if health <= 0.0:
		phase = "gameover"
		_save_best()
		_set_msg("MECH DOWN\nSCORE %d  (BEST %d)\nR to retry" % [score, best], 60.0)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_start = mb.position
				drag_cur = mb.position
			else:
				if dragging and drag_start.distance_to(mb.position) < 10.0:
					_do_punch()
				dragging = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			drag_cur = mm.position


func _process(delta: float) -> void:
	pulse_t += delta
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			_set_msg("", 0.0)
	if punch_cd > 0.0:
		punch_cd -= delta
	# Punch arm recovery.
	if arm_r != null and punch_cd < PUNCH_COOLDOWN - 0.25:
		arm_r.position = arm_r.position.lerp(arm_r_base, minf(delta * 8.0, 1.0))
	energy = minf(100.0, energy + ENERGY_REGEN * delta)
	# Briefing advance.
	if phase == "brief":
		brief_t -= delta
		if brief_t <= 0.0:
			_begin_mission(-mission)
		_update_hud()
		return
	if Input.is_key_pressed(KEY_R):
		_restart()
		return
	if phase != "play":
		_update_hud()
		return
	_handle_drive(delta)
	_handle_weapons(delta)
	_update_drones(delta)
	_update_projectiles(delta)
	_update_shockwaves(delta)
	_update_mission(delta)
	_update_shake(delta)
	_update_hud()
	_update_beacon_fx()


func _handle_drive(delta: float) -> void:
	var throttle := 0.0
	var turn := 0.0
	if ARUpgradeKit.is_xr_active() and camera != null:
		var hand: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		var cam_p: Vector3 = camera.global_position
		var rel: Vector3 = hand - cam_p
		if xr_has_prev and delta > 0.0:
			xr_hand_vel = xr_hand_vel.lerp((hand - xr_prev_hand) / delta, 0.4)
		xr_prev_hand = hand
		xr_has_prev = true
		var fwd: Vector3 = -global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var push: float = rel.dot(fwd)
		throttle = clampf((push - 0.12) / 0.4, -1.0, 1.0)
		if absf(throttle) < 0.12:
			throttle = 0.0
		var rel_flat := Vector3(rel.x, 0.0, rel.z)
		if rel_flat.length() > 0.05:
			var yaw_ang := fwd.signed_angle_to(rel_flat.normalized(), Vector3.UP)
			turn = clampf(-yaw_ang * 2.0, -1.0, 1.0)
		# Fast thrust = jab.
		if xr_hand_vel.dot(fwd) > 2.4:
			_do_punch()
			xr_hand_vel = Vector3.ZERO
	else:
		if dragging:
			var dv: Vector2 = drag_start - drag_cur
			throttle = clampf(dv.y / 160.0, -1.0, 1.0)
			turn = clampf(-dv.x / 200.0, -1.0, 1.0)
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			throttle = 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			throttle = -1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			turn = -1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			turn = 1.0
		# Space edge = jab.
		var sp := Input.is_key_pressed(KEY_SPACE)
		if sp and not prev_space:
			_do_punch()
		prev_space = sp
	if throttle != 0.0 or turn != 0.0:
		var fwd2: Vector3 = -global_transform.basis.z
		fwd2.y = 0.0
		fwd2 = fwd2.normalized()
		global_position += fwd2 * throttle * MOVE_SPEED * delta
		rotation.y += turn * TURN_SPEED * delta
		global_position = ARUpgradeKit.clamp_to_room(global_position, 0.4)


func _handle_weapons(delta: float) -> void:
	if ARUpgradeKit.is_xr_active():
		var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
		if pinching:
			charging = true
			charge = minf(1.0, charge + delta * 1.4)
		elif xr_prev_pinch and charging:
			charging = false
			_fire_blast(charge)
			charge = 0.0
		xr_prev_pinch = pinching
	else:
		var e := Input.is_key_pressed(KEY_E)
		if e:
			charging = true
			charge = minf(1.0, charge + delta * 1.4)
		elif prev_e and charging:
			charging = false
			_fire_blast(charge)
			charge = 0.0
		prev_e = e
	if cannon_charge_mat != null:
		GraphicsPolish.pulse_glow(cannon_charge_mat, 0.4 + charge * 2.2, 0.5, pulse_t, 6.0)


func _update_drones(delta: float) -> void:
	var pp := _player_pos()
	var keep: Array = []
	for d in drones:
		var n: Node3D = d.get("node")
		if n == null or not is_instance_valid(n) or bool(d.get("dead", false)):
			continue
		keep.append(d)
		var rotor: Node3D = d.get("rotor")
		if rotor != null:
			rotor.rotation.y += delta * 9.0
		if float(d.get("flash", 0.0)) > 0.0:
			d["flash"] = float(d.get("flash")) - delta
		# Orbit/strafe around the player or the beacon.
		var target := pp
		if mission == 2 and beacon != null and is_instance_valid(beacon):
			target = beacon.global_position + Vector3(0, 1.4, 0)
		var to: Vector3 = n.global_position - target
		to.y = 0.0
		var dist := to.length()
		var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
		var tangent := Vector3(-dir.z, 0, dir.x) * float(d.get("strafe", 1.0))
		var radial := Vector3.ZERO
		if dist > 2.6:
			radial = -dir * 0.8
		elif dist < 1.8:
			radial = dir * 0.8
		n.global_position += (tangent * 1.1 + radial) * delta
		n.global_position.y = 1.55 + sin(pulse_t * 2.2 + float(d.get("ang", 0.0))) * 0.15
		n.global_position = ARUpgradeKit.clamp_to_room(n.global_position, 0.5)
		if dist > 0.05:
			n.rotation.y = atan2(-(target.x - n.global_position.x), -(target.z - n.global_position.z))
		# Shoot at the player or the beacon.
		d["shoot_t"] = float(d.get("shoot_t", 2.0)) - delta
		if float(d.get("shoot_t")) <= 0.0 and dist < 4.5:
			d["shoot_t"] = randf_range(1.6, 3.2)
			_fire_bolt(n.global_position + Vector3(0, -0.1, 0), target, 4.5, DRONE_BOLT_DAMAGE, Color(1.0, 0.3, 0.15))
	drones = keep


func _update_projectiles(delta: float) -> void:
	var pp := _player_pos()
	var keep: Array = []
	for p in projectiles:
		var n: Node3D = p.get("node")
		if n == null or not is_instance_valid(n):
			continue
		p["life"] = float(p.get("life", 1.0)) - delta
		if float(p.get("life")) <= 0.0:
			n.queue_free()
			continue
		n.global_position += (p.get("vel") as Vector3) * delta
		var pos: Vector3 = n.global_position
		var hit := false
		if bool(p.get("friendly", false)):
			for d in drones:
				var dn: Node3D = d.get("node")
				if dn != null and is_instance_valid(dn) and not bool(d.get("dead", false)):
					if pos.distance_to(dn.global_position) < 0.55:
						_damage_drone(d, int(p.get("dmg", 1)), pos)
						hit = true
						break
			if not hit and not boss.is_empty():
				var bn: Node3D = boss.get("node")
				if bn != null and is_instance_valid(bn):
					var core: Node3D = boss.get("core")
					var core_hit := core != null and pos.distance_to(core.global_position) < 0.55
					var body_hit := pos.distance_to(bn.global_position + Vector3(0, 2.2, 0)) < 1.5
					if core_hit or body_hit:
						_damage_boss(int(p.get("dmg", 1)), core_hit)
						hit = true
		else:
			if pos.distance_to(pp) < 0.6:
				_hurt_player(float(p.get("dmg", 5.0)), pos)
				hit = true
			elif mission == 2 and beacon != null and is_instance_valid(beacon):
				if pos.distance_to(beacon.global_position + Vector3(0, 1.6, 0)) < 0.9:
					beacon_hp = maxf(0.0, beacon_hp - float(p.get("dmg", 5.0)))
					GraphicsPolish.spawn_sparks(self, pos, Color(0.3, 0.9, 1.0), 10)
					hit = true
					if beacon_hp <= 0.0:
						_fail_defense()
		if pos.y < 0.02 or pos.y > 6.0 or Vector2(pos.x, pos.z).length() > 5.0:
			hit = true
		if hit:
			GraphicsPolish.spawn_sparks(self, pos, Color(0.5, 0.9, 1.0) if bool(p.get("friendly", false)) else Color(1.0, 0.4, 0.15), 8)
			n.queue_free()
		else:
			keep.append(p)
	projectiles = keep


func _update_shockwaves(delta: float) -> void:
	var keep: Array = []
	for s in shockwaves:
		var n: Node3D = s.get("node")
		if n == null or not is_instance_valid(n):
			continue
		s["t"] = float(s.get("t", 0.0)) + delta * 2.2
		var t: float = s.get("t")
		if t >= 1.0:
			n.queue_free()
			continue
		var r: float = lerpf(0.3, float(s.get("max_r", 1.6)), t)
		n.scale = Vector3(r, 1.0, r)
		var mat := (n as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.8 * (1.0 - t)
		keep.append(s)
	shockwaves = keep


func _update_mission(delta: float) -> void:
	match mission:
		1:
			drone_spawn_t -= delta
			if drone_spawn_t <= 0.0 and drones.size() < MAX_DRONES_ALIVE and drones_destroyed + drones.size() < DRONES_TO_KILL:
				drone_spawn_t = 1.2
				_spawn_drone_wave(1)
			if drones_destroyed >= DRONES_TO_KILL:
				_start_brief("MISSION 1 COMPLETE  +800\nMission 2: Defend the beacon for 60 seconds", 3.0, 2)
				score += 800
		2:
			if defense_failed:
				defense_failed = false
				_set_msg("BEACON DESTROYED — RETRYING MISSION 2", 2.5)
				_begin_mission(2)
				return
			defend_t -= delta
			drone_spawn_t -= delta
			if drone_spawn_t <= 0.0:
				drone_spawn_t = 4.0
				wave_num += 1
				_spawn_drone_wave(mini(2 + wave_num / 2, 4))
			if defend_t <= 0.0:
				score += 1200
				_start_brief("BEACON HELD  +1200\nMission 3: Destroy the armored walker — hit the core!", 3.5, 3)
		3:
			_update_boss(delta)


func _fail_defense() -> void:
	# Deferred: _update_mission picks this up outside the projectile loop.
	defense_failed = true
	if beacon != null and is_instance_valid(beacon):
		GraphicsPolish.spawn_sparks(self, beacon.global_position + Vector3(0, 1.6, 0), Color(1.0, 0.3, 0.1), 50)


func _update_boss(delta: float) -> void:
	if boss.is_empty():
		return
	var bn: Node3D = boss.get("node")
	if bn == null or not is_instance_valid(bn):
		return
	var core_mat: StandardMaterial3D = boss.get("core_mat")
	var pp := _player_pos()
	var to_p: Vector3 = pp - bn.global_position
	to_p.y = 0.0
	var dist := to_p.length()
	# Stomp toward the player.
	boss["stomp_ph"] = float(boss.get("stomp_ph", 0.0)) + delta * 6.0
	bn.position.y = absf(sin(float(boss.get("stomp_ph")))) * 0.12
	if dist > 2.2:
		bn.global_position += to_p.normalized() * 0.85 * delta
		bn.global_position = ARUpgradeKit.clamp_to_room(bn.global_position, 0.8)
	if dist > 0.1:
		bn.rotation.y = atan2(-to_p.x, -to_p.z)
	# Telegraph + slam.
	var tele: float = float(boss.get("telegraph", 0.0))
	if tele > 0.0:
		boss["telegraph"] = tele - delta
		if core_mat != null:
			GraphicsPolish.pulse_glow(core_mat, 3.5, 1.5, pulse_t, 10.0)
		if tele - delta <= 0.0:
			_spawn_shockwave(bn.global_position + Vector3(0, 0.25, 0), Color(1.0, 0.35, 0.1), 3.2)
			shake = maxf(shake, 0.5)
			Haptics.thump()
			if dist < 2.6:
				_hurt_player(BOSS_SLAM_DAMAGE, bn.global_position)
	else:
		boss["slam_t"] = float(boss.get("slam_t", 3.0)) - delta
		if float(boss.get("slam_t")) <= 0.0 and dist < 3.4:
			boss["slam_t"] = randf_range(2.6, 4.0)
			boss["telegraph"] = 0.8
			_set_msg("WALKER INCOMING — DODGE!", 0.9)
	# Spread shot.
	boss["shot_t"] = float(boss.get("shot_t", 1.5)) - delta
	if float(boss.get("shot_t")) <= 0.0 and dist < 5.0:
		boss["shot_t"] = randf_range(1.8, 2.8)
		var base: Vector3 = (pp - (bn.global_position + Vector3(0, 2.6, 0))).normalized()
		for k in [-1, 0, 1]:
			var dir := base.rotated(Vector3.UP, deg_to_rad(float(k) * 10.0))
			var root := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.08
			sph.height = 0.16
			root.mesh = sph
			root.material_override = GraphicsPolish.glow(Color(1.0, 0.35, 0.1), 2.2)
			root.position = bn.global_position + Vector3(0, 2.6, 0) + dir * 1.2
			add_child(root)
			projectiles.append({"node": root, "vel": dir * 5.0, "friendly": false, "life": 4.0, "dmg": 10.0})


func _update_shake(delta: float) -> void:
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 1.6)
	if camera != null:
		var off := Vector3.ZERO
		if shake > 0.0:
			off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.12
		camera.position = cam_base_pos + off


func _update_beacon_fx() -> void:
	if beacon_core_mat != null and beacon != null and is_instance_valid(beacon):
		var urgency := 1.0 - beacon_hp / BEACON_HP
		GraphicsPolish.pulse_glow(beacon_core_mat, 2.2, 0.8 + urgency * 1.5, pulse_t, 2.0 + urgency * 4.0)


func _restart() -> void:
	health = 100.0
	energy = 100.0
	score = 0
	charge = 0.0
	charging = false
	punch_cd = 0.0
	shake = 0.0
	defense_failed = false
	_start_brief("MECH PILOT // SYSTEMS ONLINE\nMission 1: Destroy 8 rogue drones", 3.0, 1)
	_update_hud()


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_FILE) == OK:
		best = int(cfg.get_value("mech", "best_score", 0))


func _save_best() -> void:
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.set_value("mech", "best_score", best)
		cfg.save(BEST_FILE)
