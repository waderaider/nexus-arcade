## Sky Pirates: captain an airship (Kenney ship hull + balloon + propellers)
## in a cloudy sky arena. Hand-steer: tilt hand to bank/turn, push forward
## for speed (mouse-drag equivalent on desktop). Pinch/click to fire cannons
## at 3 enemy sky-ship types with HP bars. Boarding: flick/tap BOARD when
## close, then smash 5 crates to capture. Loot gold, upgrade hull/cannons/
## sails between waves. 5 waves + sky-kraken boss. Gold + best wave persist
## in user://nexus_pirates.cfg. R restarts the run.
extends Node3D

const SAVE_PATH := "user://nexus_pirates.cfg"
const MODELS := "res://assets/models/sky_pirates/"

const WAVES := [
	["sloop", "sloop"],
	["sloop", "sloop", "sloop"],
	["sloop", "frigate", "frigate"],
	["frigate", "frigate", "galleon"],
	["frigate", "galleon", "galleon"],
	["kraken"],
]

const ENEMY_TYPES := {
	"sloop": {"model": "ship-pirate-small.glb", "hp": 30.0, "speed": 9.5, "dmg": 6.0, "gold": 12, "reload": 3.4},
	"frigate": {"model": "ship-pirate-medium.glb", "hp": 65.0, "speed": 7.5, "dmg": 10.0, "gold": 24, "reload": 2.8},
	"galleon": {"model": "ship-pirate-large.glb", "hp": 130.0, "speed": 5.5, "dmg": 16.0, "gold": 44, "reload": 2.4},
}

const UPGRADE_DEFS := [
	{"name": "HULL", "desc": "+30 max hull", "cost": 40, "max": 3},
	{"name": "CANNONS", "desc": "+5 cannon damage", "cost": 50, "max": 3},
	{"name": "SAILS", "desc": "+20% top speed", "cost": 40, "max": 3},
]

const BALL_SPEED := 30.0
const GRAVITY := 7.0
const ARENA_R := 65.0

var camera: Camera3D = null
var xr_mode := false
var state := "menu" # menu, upgrade, combat, victory, gameover
var wave_idx := 0
var gold := 0
var gold_bank := 0
var best_wave := 0
var upg := [0, 0, 0]

var ship: Node3D = null
var ship_vel := Vector3.ZERO
var heading := 0.0
var throttle := 0.35
var turn_input := 0.0
var hull_hp := 100.0
var max_hull := 100.0
var cannon_dmg := 12.0
var top_speed := 14.0
var fire_cd := 0.0
var muzzle_side := 1.0
var props: Array = []
var balloon: MeshInstance3D = null

var enemies: Array = []
var balls: Array = []
var coins: Array = []
var clouds: Array = []
var islands: Array = []

var boarding := false
var board_target := -1
var board_crates: Array = []
var board_smashed := 0
var board_t := 0.0
var board_btn: Node3D = null
var grapple_line: MeshInstance3D = null

var kraken: Node3D = null
var kraken_hp := 0.0
var kraken_max := 420.0
var kraken_tents: Array = []
var kraken_cd := 0.0
var kraken_whip := -1
var kraken_whip_t := 0.0

var hud_root: Node3D = null
var hud_gold: Label3D = null
var hud_wave: Label3D = null
var hud_hp_bg: MeshInstance3D = null
var hud_hp_fg: MeshInstance3D = null
var hud_boss_bg: MeshInstance3D = null
var hud_boss_fg: MeshInstance3D = null
var hud_help: Label3D = null
var msg_label: Label3D = null
var panel_root: Node3D = null
var menu_root: Node3D = null

var taps := {}
var msg := ""
var msg_t := 0.0
var pulse_t := 0.0
var shake := 0.0
var pressing := false
var press_pos := Vector2.ZERO
var press_time := 0
var press_moved := 0.0
var drag_steer := false
var prev_pinch := false
var xr_pointer_prev := Vector3.ZERO
var xr_pointer_vel := Vector3.ZERO
var cam_base := Vector3.ZERO


static var _model_cache := {}


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "sky_pirates_main")
	xr_mode = ARUpgradeKit.is_xr_active()
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_progress()
	_build_sky()
	_build_player_ship()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 6, -10), 8.0, 50)
	_show_menu()


func _load_model(path: String) -> Node3D:
	if _model_cache.has(path):
		var ps: PackedScene = _model_cache[path]
		if ps != null:
			return ps.instantiate() as Node3D
		_model_cache.erase(path)
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path) as PackedScene
	if loaded == null:
		return null
	_model_cache[path] = loaded
	return loaded.instantiate() as Node3D


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0, 9.5, 12)
	add_child(camera)
	camera.look_at(Vector3(0, 6, -6), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.38, 0.78)
	sky_mat.sky_horizon_color = Color(0.62, 0.82, 0.98)
	sky_mat.ground_bottom_color = Color(0.35, 0.55, 0.85)
	sky_mat.ground_horizon_color = Color(0.75, 0.88, 1.0)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.78, 0.95)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -32, 0)
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.light_energy = 0.6
	fill.position = Vector3(0, 20, 10)
	fill.omni_range = 60.0
	add_child(fill)


func _build_sky() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.88)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.82, 0.88, 0.97, 0.9)
	shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Puffy cloud clusters: 3-5 squashed spheres each.
	for i in 46:
		var cluster := Node3D.new()
		cluster.position = Vector3(rng.randf_range(-70, 70), rng.randf_range(-8, 26), rng.randf_range(-70, 70))
		add_child(cluster)
		var puffs := rng.randi_range(3, 5)
		for p in puffs:
			var puff := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r := rng.randf_range(1.6, 3.4)
			sm.radius = r
			sm.height = r * 1.2
			puff.mesh = sm
			puff.material_override = cloud_mat if p % 2 == 0 else shade_mat
			puff.position = Vector3(rng.randf_range(-3.2, 3.2), rng.randf_range(-0.8, 0.8), rng.randf_range(-2.2, 2.2))
			puff.scale = Vector3(1.0, 0.62, 0.85)
			cluster.add_child(puff)
		cluster.set_meta("drift", rng.randf_range(0.4, 1.2))
		clouds.append(cluster)
	# Sea of clouds far below.
	var sea := MeshInstance3D.new()
	var seaplane := PlaneMesh.new()
	seaplane.size = Vector2(400, 400)
	sea.mesh = seaplane
	sea.material_override = shade_mat
	sea.position = Vector3(0, -22, 0)
	add_child(sea)
	# Distant floating islands: kenney rocks + grass + palm.
	var rock_names := ["rocks-a.glb", "rocks-b.glb", "rocks-c.glb"]
	for i in 6:
		var isl := Node3D.new()
		var ang := TAU * float(i) / 6.0 + 0.35
		isl.position = Vector3(cos(ang) * rng.randf_range(42, 62), rng.randf_range(-4, 14), sin(ang) * rng.randf_range(42, 62))
		add_child(isl)
		var rock := _load_model(MODELS + rock_names[i % 3])
		if rock != null:
			rock.scale = Vector3.ONE * rng.randf_range(2.2, 3.4)
			isl.add_child(rock)
		var grass := _load_model(MODELS + "patch-grass.glb")
		if grass != null:
			grass.position = Vector3(0, 1.6, 0)
			grass.scale = Vector3.ONE * 2.4
			isl.add_child(grass)
		if i % 2 == 0:
			var palm := _load_model(MODELS + "palm-straight.glb")
			if palm != null:
				palm.position = Vector3(rng.randf_range(-1.5, 1.5), 1.8, rng.randf_range(-1.5, 1.5))
				palm.scale = Vector3.ONE * 1.4
				isl.add_child(palm)
		isl.set_meta("bob_phase", rng.randf() * TAU)
		islands.append(isl)


func _make_tappable(node: Node3D, tap_id: String, kind: String, data: Variant, radius: float) -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	shape.shape = sp
	area.add_child(shape)
	node.add_child(area)
	area.set_meta("tap_id", tap_id)
	taps[tap_id] = {"node": node, "kind": kind, "data": data}


func _ray_pick(origin: Vector3, dir: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	if space == null:
		return ""
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ""
	var col: Object = hit.get("collider")
	if col != null and col.has_meta("tap_id"):
		return str(col.get_meta("tap_id"))
	return ""


func _screen_pick(screen_pos: Vector2) -> String:
	if camera == null:
		return ""
	return _ray_pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _build_player_ship() -> void:
	ship = Node3D.new()
	ship.position = Vector3(0, 6, 0)
	add_child(ship)
	var hull := _load_model(MODELS + "ship-pirate-medium.glb")
	if hull != null:
		ship.add_child(hull)
	# Balloon envelope: big striped gasbag (uniform sphere so bands fit).
	balloon = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 2.6
	bs.height = 5.2
	balloon.mesh = bs
	balloon.material_override = GraphicsPolish.pbr_preset(Color(0.72, 0.12, 0.14), "plastic")
	balloon.position = Vector3(0, 8.6, -0.4)
	ship.add_child(balloon)
	# Cream latitude bands hugging the sphere.
	var band_offsets := [-1.45, 0.0, 1.45]
	for bo in band_offsets:
		var cross_r := sqrt(maxf(2.6 * 2.6 - bo * bo, 0.2))
		var band := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = cross_r + 0.02
		tor.outer_radius = cross_r + 0.16
		band.mesh = tor
		band.material_override = GraphicsPolish.pbr_preset(Color(0.94, 0.90, 0.78), "matte")
		band.position = Vector3(0, 8.6 + bo, -0.4)
		ship.add_child(band)
	# Ropes from balloon to deck corners (ship-local coords).
	var rope_mat := GraphicsPolish.pbr_preset(Color(0.35, 0.25, 0.15), "matte")
	var deck := [Vector3(1.7, 1.4, 2.0), Vector3(-1.7, 1.4, 2.0), Vector3(1.7, 1.4, -2.6), Vector3(-1.7, 1.4, -2.6)]
	for cp in deck:
		var top := Vector3(cp.x * 0.45, 6.9, -0.4 + cp.z * 0.25)
		var dir: Vector3 = (top - cp).normalized()
		var rope := MeshInstance3D.new()
		var cb := CylinderMesh.new()
		cb.top_radius = 0.03
		cb.bottom_radius = 0.03
		cb.height = top.distance_to(cp)
		rope.mesh = cb
		rope.material_override = rope_mat
		rope.position = (top + cp) * 0.5
		var axis := Vector3.UP.cross(dir)
		if axis.length() < 0.001:
			axis = Vector3.RIGHT
		rope.basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		ship.add_child(rope)
	# Deck cannons (visual) + pirate flag.
	for side in [-1.0, 1.0]:
		var cannon := _load_model(MODELS + "cannon.glb")
		if cannon != null:
			cannon.position = Vector3(side * 1.5, 1.15, -1.2)
			cannon.rotation.y = PI if side < 0.0 else 0.0
			ship.add_child(cannon)
	var flag := _load_model(MODELS + "flag-pirate.glb")
	if flag != null:
		flag.position = Vector3(0, 11.0, -0.4)
		flag.scale = Vector3.ONE * 1.3
		ship.add_child(flag)
	# Twin propellers at the stern.
	for side in [-1.0, 1.0]:
		var prop := Node3D.new()
		prop.position = Vector3(side * 2.6, 2.2, 3.6)
		ship.add_child(prop)
		var hub := MeshInstance3D.new()
		var hb := CylinderMesh.new()
		hb.top_radius = 0.09
		hb.bottom_radius = 0.09
		hb.height = 0.3
		hub.mesh = hb
		hub.material_override = GraphicsPolish.pbr_preset(Color(0.15, 0.15, 0.18), "metal")
		hub.rotation_degrees.x = 90.0
		prop.add_child(hub)
		for b in 2:
			var blade := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.16, 1.7, 0.05)
			blade.mesh = bb
			blade.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.38, 0.20), "matte")
			blade.rotation.z = deg_to_rad(float(b) * 90.0)
			prop.add_child(blade)
		props.append(prop)
	# Warm deck lantern light.
	GraphicsPolish.make_point_light(ship, Vector3(0, 3.0, 0), Color(1.0, 0.75, 0.45), 1.2, 9.0)


func _build_hud() -> void:
	hud_root = Node3D.new()
	add_child(hud_root)
	hud_gold = GraphicsPolish.make_label("", 44, Color(1.0, 0.85, 0.35))
	hud_gold.position = Vector3(-0.85, 0.62, -1.4)
	hud_gold.pixel_size = 0.0035
	hud_root.add_child(hud_gold)
	hud_wave = GraphicsPolish.make_label("", 40, Color(0.75, 0.9, 1.0))
	hud_wave.position = Vector3(0.85, 0.62, -1.4)
	hud_wave.pixel_size = 0.0035
	hud_root.add_child(hud_wave)
	# Hull HP bar (billboarded boxes).
	hud_hp_bg = MeshInstance3D.new()
	var hbb := BoxMesh.new()
	hbb.size = Vector3(0.9, 0.09, 0.01)
	hud_hp_bg.mesh = hbb
	var bgm := StandardMaterial3D.new()
	bgm.albedo_color = Color(0.1, 0.1, 0.12)
	bgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hud_hp_bg.material_override = bgm
	hud_hp_bg.position = Vector3(0, 0.50, -1.4)
	hud_root.add_child(hud_hp_bg)
	hud_hp_fg = MeshInstance3D.new()
	var hfb := BoxMesh.new()
	hfb.size = Vector3(0.88, 0.07, 0.012)
	hud_hp_fg.mesh = hfb
	var fgm := StandardMaterial3D.new()
	fgm.albedo_color = Color(0.25, 0.9, 0.35)
	fgm.emission_enabled = true
	fgm.emission = Color(0.25, 0.9, 0.35)
	fgm.emission_energy_multiplier = 1.2
	fgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hud_hp_fg.material_override = fgm
	hud_hp_fg.position = Vector3(0, 0.50, -1.4)
	hud_root.add_child(hud_hp_fg)
	# Boss bar (hidden unless kraken).
	hud_boss_bg = MeshInstance3D.new()
	var bbb := BoxMesh.new()
	bbb.size = Vector3(1.4, 0.10, 0.01)
	hud_boss_bg.mesh = bbb
	var bbgm := StandardMaterial3D.new()
	bbgm.albedo_color = Color(0.08, 0.05, 0.10)
	bbgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hud_boss_bg.material_override = bbgm
	hud_boss_bg.position = Vector3(0, 0.78, -1.4)
	hud_boss_bg.visible = false
	hud_root.add_child(hud_boss_bg)
	hud_boss_fg = MeshInstance3D.new()
	var bfb := BoxMesh.new()
	bfb.size = Vector3(1.38, 0.08, 0.012)
	hud_boss_fg.mesh = bfb
	var bfgm := StandardMaterial3D.new()
	bfgm.albedo_color = Color(0.75, 0.15, 0.55)
	bfgm.emission_enabled = true
	bfgm.emission = Color(0.75, 0.15, 0.55)
	bfgm.emission_energy_multiplier = 1.4
	bfgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hud_boss_fg.material_override = bfgm
	hud_boss_fg.position = Vector3(0, 0.78, -1.4)
	hud_boss_fg.visible = false
	hud_root.add_child(hud_boss_fg)
	msg_label = GraphicsPolish.make_label("", 52, Color(1.0, 0.9, 0.6))
	msg_label.position = Vector3(0, 0.28, -1.4)
	msg_label.pixel_size = 0.004
	hud_root.add_child(msg_label)
	hud_help = GraphicsPolish.make_label("", 30, Color(0.85, 0.9, 1.0))
	hud_help.position = Vector3(0, -0.52, -1.4)
	hud_help.pixel_size = 0.0032
	hud_root.add_child(hud_help)
	_update_hud()


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	if msg_label != null:
		msg_label.text = text


func _update_hud() -> void:
	if hud_gold != null:
		hud_gold.text = "GOLD %d" % gold
	if hud_wave != null:
		if state == "combat":
			hud_wave.text = "WAVE %d/6" % (wave_idx + 1)
		else:
			hud_wave.text = ""
	if hud_hp_fg != null:
		var f := clampf(hull_hp / maxf(max_hull, 1.0), 0.0, 1.0)
		hud_hp_fg.scale.x = maxf(f, 0.001)
		hud_hp_fg.position.x = -0.44 * (1.0 - f)
	if hud_help != null:
		if xr_mode:
			hud_help.text = "Tilt hand: steer | Push forward: speed | Pinch: fire | Flick: board"
		else:
			hud_help.text = "Drag: steer/push | Click: fire cannons | R: restart"


func _panel_card(text: String, pos: Vector3, size: Vector2, color: Color, tap_id: String, kind: String, data: Variant, fsize: int = 30) -> Node3D:
	var card := Node3D.new()
	card.position = pos
	panel_root.add_child(card)
	var bg := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(size.x, size.y, 0.03)
	bg.mesh = bb
	bg.material_override = GraphicsPolish.pbr_preset(Color(0.06, 0.08, 0.13), "matte")
	card.add_child(bg)
	var edge := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(size.x + 0.04, size.y + 0.04, 0.02)
	edge.mesh = eb
	edge.material_override = GraphicsPolish.glow(color, 1.0)
	edge.position.z = -0.008
	card.add_child(edge)
	var lbl := GraphicsPolish.make_label(text, fsize, Color(0.95, 0.97, 1.0))
	lbl.position = Vector3(0, 0, 0.04)
	lbl.pixel_size = 0.0036
	card.add_child(lbl)
	_make_tappable(card, tap_id, kind, data, maxf(size.x, size.y) * 0.62)
	return card


func _clear_panel() -> void:
	if panel_root != null and is_instance_valid(panel_root):
		panel_root.queue_free()
	panel_root = null
	for k in taps.keys():
		if str(k).begins_with("up_") or str(k) == "nextwave" or str(k) == "setsail" or str(k) == "retry":
			taps.erase(k)


func _panel_in_front(dist: float = 3.2, height: float = 0.0) -> Vector3:
	if camera == null:
		return Vector3(0, 6, -6)
	var t := camera.global_transform
	return t.origin + (-t.basis.z) * dist + Vector3(0, height, 0)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		gold_bank = int(cfg.get_value("pirates", "gold", 0))
		best_wave = int(cfg.get_value("pirates", "best_wave", 0))


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("pirates", "gold", gold_bank)
	cfg.set_value("pirates", "best_wave", best_wave)
	cfg.save(SAVE_PATH)


func _show_menu() -> void:
	state = "menu"
	_clear_panel()
	panel_root = Node3D.new()
	panel_root.position = _panel_in_front(3.4, 0.4)
	add_child(panel_root)
	if camera != null:
		panel_root.look_at(camera.global_position, Vector3.UP)
	_panel_card("SKY PIRATES", Vector3(0, 0.85, 0), Vector2(2.2, 0.42), Color(0.9, 0.6, 0.15), "mtitle", "noop", 0, 54)
	_panel_card("Banked gold: %d   Best wave: %d/6" % [gold_bank, best_wave], Vector3(0, 0.28, 0), Vector2(2.2, 0.30), Color(0.4, 0.6, 0.9), "msub", "noop", 0, 28)
	_panel_card("SET SAIL  \u25b8", Vector3(0, -0.35, 0), Vector2(1.5, 0.40), Color(0.15, 0.55, 0.25), "setsail", "setsail", 0, 40)


func _start_run() -> void:
	Haptics.tick()
	gold = 0
	wave_idx = 0
	upg = [0, 0, 0]
	max_hull = 100.0
	hull_hp = max_hull
	cannon_dmg = 12.0
	top_speed = 14.0
	throttle = 0.35
	ship.position = Vector3(0, 6, 0)
	heading = 0.0
	_clear_enemies()
	_show_upgrade()


func _show_upgrade() -> void:
	state = "upgrade"
	_clear_panel()
	_clear_board_btn()
	panel_root = Node3D.new()
	panel_root.position = _panel_in_front(3.4, 0.3)
	add_child(panel_root)
	if camera != null:
		panel_root.look_at(camera.global_position, Vector3.UP)
	_panel_card("WAVE %d/6 \u2014 OUTFIT YOUR SHIP" % (wave_idx + 1), Vector3(0, 1.05, 0), Vector2(2.6, 0.36), Color(0.9, 0.6, 0.15), "utitle", "noop", 0, 34)
	_panel_card("Gold: %d" % gold, Vector3(0, 0.62, 0), Vector2(1.4, 0.28), Color(1.0, 0.85, 0.35), "ugold", "noop", 0, 32)
	for i in 3:
		var ud: Dictionary = UPGRADE_DEFS[i]
		var lvl: int = upg[i]
		var maxed := lvl >= int(ud["max"])
		var text := "%s  Lv%d/%d\n%s \u2014 %d gold" % [str(ud["name"]), lvl, int(ud["max"]), str(ud["desc"]), int(ud["cost"])]
		if maxed:
			text = "%s  MAXED" % str(ud["name"])
		var col := Color(0.35, 0.65, 1.0) if not maxed else Color(0.4, 0.4, 0.45)
		_panel_card(text, Vector3(-1.05 + float(i) * 1.05, 0.05, 0), Vector2(0.95, 0.42), col, "up_%d" % i, "upgrade", i, 26)
	var nxt := "SAIL INTO WAVE %d \u25b8" % (wave_idx + 1)
	if wave_idx >= WAVES.size() - 1:
		nxt = "FACE THE SKY KRAKEN \u25b8"
	_panel_card(nxt, Vector3(0, -0.62, 0), Vector2(2.2, 0.40), Color(0.75, 0.2, 0.2), "nextwave", "nextwave", 0, 34)


func _buy_upgrade(i: int) -> void:
	var ud: Dictionary = UPGRADE_DEFS[i]
	if upg[i] >= int(ud["max"]):
		_set_msg("Already maxed", 1.5)
		return
	var cost := int(ud["cost"])
	if gold < cost:
		_set_msg("Need %d gold (have %d)" % [cost, gold], 2.0)
		Haptics.tick()
		return
	gold -= cost
	upg[i] += 1
	Haptics.thump()
	GraphicsPolish.spawn_sparks(self, panel_root.global_position, Color(1.0, 0.85, 0.3), 20)
	match i:
		0:
			max_hull += 30.0
			hull_hp = minf(hull_hp + 30.0, max_hull)
		1:
			cannon_dmg += 5.0
		2:
			top_speed *= 1.2
	_update_hud()
	_show_upgrade()


func _start_wave() -> void:
	Haptics.tick()
	_clear_panel()
	state = "combat"
	_update_hud()
	var wave: Array = WAVES[wave_idx]
	if wave[0] == "kraken":
		_set_msg("THE SKY KRAKEN RISES", 4.0)
		_spawn_kraken()
	else:
		_set_msg("WAVE %d \u2014 %d ships sighted!" % [wave_idx + 1, wave.size()], 3.5)
		for t in wave:
			_spawn_enemy(str(t))


func _spawn_enemy(etype: String) -> void:
	var def: Dictionary = ENEMY_TYPES[etype]
	var root := Node3D.new()
	var ang := randf() * TAU
	var dist := randf_range(38.0, 52.0)
	root.position = ship.position + Vector3(cos(ang) * dist, randf_range(-2.0, 4.0), sin(ang) * dist)
	add_child(root)
	var hull := _load_model(MODELS + str(def["model"]))
	if hull != null:
		root.add_child(hull)
	# Small dark balloon so it reads as a sky-ship.
	var bal := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 1.7
	bs.height = 3.8
	bal.mesh = bs
	bal.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.22, 0.30), "plastic")
	bal.position = Vector3(0, 6.8, 0)
	root.add_child(bal)
	# HP bar (billboarded).
	var bar_bg := MeshInstance3D.new()
	var bbb := BoxMesh.new()
	bbb.size = Vector3(2.2, 0.22, 0.02)
	bar_bg.mesh = bbb
	var bgm := StandardMaterial3D.new()
	bgm.albedo_color = Color(0.08, 0.08, 0.10)
	bgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_bg.material_override = bgm
	bar_bg.position = Vector3(0, 9.6, 0)
	root.add_child(bar_bg)
	var bar_fg := MeshInstance3D.new()
	var bfb := BoxMesh.new()
	bfb.size = Vector3(2.16, 0.18, 0.025)
	bar_fg.mesh = bfb
	var fgm := StandardMaterial3D.new()
	fgm.albedo_color = Color(0.9, 0.25, 0.25)
	fgm.emission_enabled = true
	fgm.emission = Color(0.9, 0.25, 0.25)
	fgm.emission_energy_multiplier = 1.2
	fgm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bar_fg.material_override = fgm
	bar_fg.position = Vector3(0, 9.6, 0)
	root.add_child(bar_fg)
	# Muzzle flash light (flashed on fire).
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 0.0
	flash.omni_range = 12.0
	flash.position = Vector3(0, 2.0, -3.0)
	root.add_child(flash)
	var e := {
		"node": root, "type": etype, "hp": float(def["hp"]), "max_hp": float(def["hp"]),
		"speed": float(def["speed"]), "dmg": float(def["dmg"]), "gold": int(def["gold"]),
		"reload": float(def["reload"]), "fire_t": randf_range(1.0, 2.5),
		"orbit_dir": 1.0 if randf() > 0.5 else -1.0, "orbit_a": randf() * TAU,
		"bar_fg": bar_fg, "flash": flash, "state": "fight", "die_t": 0.0, "vel": Vector3.ZERO,
	}
	enemies.append(e)


func _clear_enemies() -> void:
	for e in enemies:
		var n: Node3D = e["node"]
		if is_instance_valid(n):
			n.queue_free()
	enemies.clear()
	for b in balls:
		if is_instance_valid(b["node"]):
			(b["node"] as Node3D).queue_free()
	balls.clear()
	for c in coins:
		if is_instance_valid(c["node"]):
			(c["node"] as Node3D).queue_free()
	coins.clear()
	_clear_kraken()


func _clear_kraken() -> void:
	if kraken != null and is_instance_valid(kraken):
		kraken.queue_free()
	kraken = null
	kraken_tents.clear()
	kraken_hp = 0.0
	if hud_boss_bg != null:
		hud_boss_bg.visible = false
	if hud_boss_fg != null:
		hud_boss_fg.visible = false


func _ship_forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _fire_cannon() -> void:
	if state != "combat" or fire_cd > 0.0 or boarding:
		return
	fire_cd = 0.45
	muzzle_side = -muzzle_side
	# Aim: nearest enemy in the forward hemisphere, with a little lead.
	var best := -1
	var best_score := 1e9
	var fwd := _ship_forward()
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if e["state"] != "fight":
			continue
		var to: Vector3 = (e["node"] as Node3D).global_position - ship.global_position
		var dist := to.length()
		if dist > 48.0:
			continue
		if fwd.dot(to.normalized()) < 0.25:
			continue
		var score := dist - 8.0 * (1.0 if fwd.dot(to.normalized()) > 0.9 else 0.0)
		if score < best_score:
			best_score = score
			best = i
	var target := ship.global_position + fwd * 26.0
	if best >= 0:
		var en: Node3D = (enemies[best] as Dictionary)["node"]
		var ep: Vector3 = en.global_position
		var dist := ship.global_position.distance_to(ep)
		target = ep + (enemies[best] as Dictionary)["vel"] * (dist / BALL_SPEED) * 0.7
		target.y += dist * 0.06 # lob up a touch at range
	var muzzle := ship.global_position + fwd * 3.2 + Vector3(muzzle_side * 1.5, 1.6, 0).rotated(Vector3.UP, heading)
	var dir: Vector3 = (target - muzzle).normalized()
	_spawn_ball(muzzle, dir * BALL_SPEED, true, cannon_dmg)
	# Muzzle smoke + flash.
	GraphicsPolish.spawn_sparks(self, muzzle, Color(0.75, 0.72, 0.68), 10)
	GraphicsPolish.spawn_sparks(self, muzzle, Color(1.0, 0.65, 0.25), 8)
	Haptics.pulse(0.5, 0.08)


func _spawn_ball(pos: Vector3, vel: Vector3, from_player: bool, dmg: float) -> void:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	n.mesh = sm
	n.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.2) if from_player else Color(0.7, 0.2, 0.8), 1.6)
	n.position = pos
	add_child(n)
	n.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.25) if from_player else Color(0.7, 0.3, 0.9), 0.10))
	balls.append({"node": n, "vel": vel, "from_player": from_player, "dmg": dmg, "life": 4.0})


func _damage_enemy(i: int, dmg: float, hit_pos: Vector3) -> void:
	var e: Dictionary = enemies[i]
	if e["state"] != "fight":
		return
	e["hp"] = float(e["hp"]) - dmg
	Haptics.pulse(0.7, 0.1)
	GraphicsPolish.spawn_sparks(self, hit_pos, Color(1.0, 0.7, 0.25), 22)
	GraphicsPolish.spawn_sparks(self, hit_pos, Color(0.5, 0.5, 0.55), 12)
	var f := clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
	var fg := e["bar_fg"] as MeshInstance3D
	fg.scale.x = maxf(f, 0.001)
	fg.position.x = -1.08 * (1.0 - f)
	if float(e["hp"]) <= 0.0:
		_kill_enemy(i)


func _kill_enemy(i: int) -> void:
	var e: Dictionary = enemies[i]
	e["state"] = "dying"
	e["die_t"] = 2.6
	var n := e["node"] as Node3D
	Haptics.thump()
	GraphicsPolish.spawn_sparks(self, n.global_position + Vector3(0, 2, 0), Color(1.0, 0.6, 0.2), 40)
	GraphicsPolish.spawn_sparks(self, n.global_position, Color(0.4, 0.4, 0.45), 24)
	_set_msg("%s destroyed! +%d gold" % [str(e["type"]).capitalize(), int(e["gold"])], 2.5)
	# Gold coins arc out, then fly to the player.
	for k in 4:
		var coin := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.16
		cm.height = 0.05
		coin.mesh = cm
		coin.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.25), 1.6)
		coin.position = n.global_position + Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1))
		add_child(coin)
		coins.append({"node": coin, "t": 0.0, "value": int(float(e["gold"]) / 4.0) + 1, "arc": Vector3(randf_range(-4, 4), randf_range(3, 6), randf_range(-4, 4))})
	if boarding and board_target == i:
		_end_boarding(false)


func _damage_player(dmg: float, from_pos: Vector3) -> void:
	if state != "combat":
		return
	hull_hp -= dmg
	shake = 0.5
	Haptics.thump()
	GraphicsPolish.spawn_sparks(self, ship.global_position + Vector3(0, 2, 0), Color(1.0, 0.3, 0.2), 18)
	_update_hud()
	if hull_hp <= 0.0:
		_game_over()


func _update_enemies(delta: float) -> void:
	var sp := ship.global_position
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		var n := e["node"] as Node3D
		if not is_instance_valid(n):
			enemies.remove_at(i)
			continue
		if e["state"] == "dying":
			e["die_t"] = float(e["die_t"]) - delta
			n.position.y -= delta * 6.0
			n.rotation.z += delta * 1.4
			n.rotation.x += delta * 0.5
			if float(e["die_t"]) <= 0.0:
				n.queue_free()
				enemies.remove_at(i)
			continue
		if e["state"] == "flee":
			var away: Vector3 = (n.global_position - sp).normalized()
			n.global_position += away * float(e["speed"]) * 1.6 * delta
			if n.global_position.distance_to(sp) > 70.0:
				n.queue_free()
				enemies.remove_at(i)
			continue
		if e["state"] == "boarded":
			continue # held by the grapple
		# Fight: orbit the player at range, firing when able.
		e["orbit_a"] = float(e["orbit_a"]) + delta * 0.25 * float(e["orbit_dir"])
		var want: Vector3 = sp + Vector3(cos(float(e["orbit_a"])) * 21.0, randf_range(-1.0, 1.0), sin(float(e["orbit_a"])) * 21.0)
		var to: Vector3 = want - n.global_position
		var desired: Vector3 = to.normalized() * float(e["speed"])
		var vel: Vector3 = (e["vel"] as Vector3).lerp(desired, clampf(1.6 * delta, 0.0, 1.0))
		e["vel"] = vel
		n.global_position += vel * delta
		if vel.length() > 0.5:
			var yaw := atan2(-vel.x, -vel.z)
			n.rotation.y = lerp_angle(n.rotation.y, yaw, clampf(3.0 * delta, 0.0, 1.0))
		n.rotation.z = lerp_angle(n.rotation.z, -0.15 * float(e["orbit_dir"]), clampf(2.0 * delta, 0.0, 1.0))
		# Fire at the player.
		e["fire_t"] = float(e["fire_t"]) - delta
		var dist := n.global_position.distance_to(sp)
		if float(e["fire_t"]) <= 0.0 and dist < 34.0:
			e["fire_t"] = float(e["reload"]) * randf_range(0.9, 1.2)
			var muzzle: Vector3 = n.global_position + Vector3(0, 2.0, 0)
			var aim: Vector3 = sp + Vector3(0, 2.0, 0) + ship_vel * (dist / 22.0) * 0.5
			var dir: Vector3 = (aim - muzzle).normalized()
			_spawn_ball(muzzle, dir * 22.0, false, float(e["dmg"]))
			var fl := e["flash"] as OmniLight3D
			fl.light_energy = 3.0
			GraphicsPolish.spawn_sparks(self, muzzle, Color(1.0, 0.6, 0.25), 8)


func _update_balls(delta: float) -> void:
	var sp := ship.global_position
	for i in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[i]
		var n := b["node"] as MeshInstance3D
		if not is_instance_valid(n):
			balls.remove_at(i)
			continue
		var vel: Vector3 = b["vel"]
		vel.y -= GRAVITY * delta
		b["vel"] = vel
		n.global_position += vel * delta
		b["life"] = float(b["life"]) - delta
		var dead := float(b["life"]) <= 0.0 or n.global_position.y < -20.0
		if not dead:
			if bool(b["from_player"]):
				for ei in enemies.size():
					var e: Dictionary = enemies[ei]
					if e["state"] != "fight":
						continue
					var en := e["node"] as Node3D
					if n.global_position.distance_to(en.global_position + Vector3(0, 2.5, 0)) < 2.6:
						_damage_enemy(ei, float(b["dmg"]), n.global_position)
						dead = true
						break
				if not dead and kraken != null and is_instance_valid(kraken):
					if n.global_position.distance_to(kraken.global_position + Vector3(0, 2, 0)) < 4.2:
						_damage_kraken(float(b["dmg"]), n.global_position)
						dead = true
			else:
				if n.global_position.distance_to(sp + Vector3(0, 2.5, 0)) < 3.0:
					_damage_player(float(b["dmg"]), n.global_position)
					dead = true
		if dead:
			n.queue_free()
			balls.remove_at(i)


func _update_coins(delta: float) -> void:
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		var n := c["node"] as MeshInstance3D
		if not is_instance_valid(n):
			coins.remove_at(i)
			continue
		c["t"] = float(c["t"]) + delta
		var t: float = c["t"]
		if t < 0.7:
			var arc: Vector3 = c["arc"]
			arc.y -= 12.0 * delta
			c["arc"] = arc
			n.global_position += arc * delta
		else:
			var to: Vector3 = (ship.global_position + Vector3(0, 2, 0)) - n.global_position
			n.global_position += to.normalized() * minf(to.length() * 4.0, 18.0) * delta
			if to.length() < 1.6:
				gold += int(c["value"])
				Haptics.tick()
				GraphicsPolish.spawn_sparks(self, n.global_position, Color(1.0, 0.85, 0.3), 8)
				n.queue_free()
				coins.remove_at(i)
				_update_hud()
				continue
		n.rotation.y += delta * 5.0


func _nearest_enemy() -> int:
	var best := -1
	var best_d := 1e9
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if e["state"] != "fight":
			continue
		var d: float = (e["node"] as Node3D).global_position.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_boarding_prompt() -> void:
	if state != "combat" or boarding:
		_clear_board_btn()
		return
	var bi := _nearest_enemy()
	if bi < 0:
		_clear_board_btn()
		return
	var e: Dictionary = enemies[bi]
	var d: float = (e["node"] as Node3D).global_position.distance_to(ship.global_position)
	if d > 10.0:
		_clear_board_btn()
		return
	# Show the BOARD button near the enemy.
	if board_btn == null or not is_instance_valid(board_btn):
		board_btn = Node3D.new()
		add_child(board_btn)
		var bg := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.1, 0.5, 0.05)
		bg.mesh = bb
		bg.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.10, 0.14), "matte")
		board_btn.add_child(bg)
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(1.16, 0.56, 0.04)
		edge.mesh = eb
		edge.material_override = GraphicsPolish.glow(Color(1.0, 0.6, 0.15), 1.4)
		edge.position.z = -0.008
		board_btn.add_child(edge)
		var lbl := GraphicsPolish.make_label("BOARD! \u2693", 44, Color(1.0, 0.85, 0.4))
		lbl.position = Vector3(0, 0, 0.05)
		lbl.pixel_size = 0.004
		board_btn.add_child(lbl)
		_make_tappable(board_btn, "board_btn", "board", bi, 0.8)
	else:
		# Refresh the tap target's enemy index.
		taps["board_btn"]["data"] = bi
	var en := e["node"] as Node3D
	board_btn.global_position = en.global_position + Vector3(0, 11.5, 0)


func _clear_board_btn() -> void:
	if board_btn != null and is_instance_valid(board_btn):
		board_btn.queue_free()
	board_btn = null
	taps.erase("board_btn")


func _start_boarding(i: int) -> void:
	if i < 0 or i >= enemies.size():
		return
	boarding = true
	board_target = i
	board_smashed = 0
	board_t = 20.0
	var e: Dictionary = enemies[i]
	e["state"] = "boarded"
	var en := e["node"] as Node3D
	_clear_board_btn()
	Haptics.thump()
	_set_msg("GRAPPLED! Smash the 5 crates to capture her!", 4.0)
	# Grapple rope between ships.
	grapple_line = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.05
	gm.bottom_radius = 0.05
	grapple_line.mesh = gm
	grapple_line.material_override = GraphicsPolish.pbr_preset(Color(0.4, 0.3, 0.2), "matte")
	add_child(grapple_line)
	# 5 tappable crates on the enemy deck.
	for k in 5:
		var crate := _load_model(MODELS + "crate.glb")
		if crate == null:
			crate = Node3D.new()
		var ang := TAU * float(k) / 5.0
		crate.position = Vector3(cos(ang) * 1.6, 1.6, sin(ang) * 1.6)
		crate.rotation.y = randf() * TAU
		en.add_child(crate)
		_make_tappable(crate, "bcrate_%d" % k, "bcrate", k, 0.7)
		board_crates.append(crate)


func _update_boarding(delta: float) -> void:
	if not boarding:
		return
	if board_target < 0 or board_target >= enemies.size():
		_end_boarding(false)
		return
	var e: Dictionary = enemies[board_target]
	var en := e["node"] as Node3D
	if not is_instance_valid(en):
		_end_boarding(false)
		return
	# Hold the ships together.
	var want: Vector3 = ship.global_position + _ship_forward() * 7.0 + Vector3(0, 1.0, 0)
	en.global_position = en.global_position.lerp(want, clampf(2.0 * delta, 0.0, 1.0))
	# Grapple rope visual.
	if grapple_line != null and is_instance_valid(grapple_line):
		var a: Vector3 = ship.global_position + Vector3(0, 2.5, 0)
		var b: Vector3 = en.global_position + Vector3(0, 2.5, 0)
		var dir: Vector3 = (b - a).normalized()
		grapple_line.position = (a + b) * 0.5
		var axis := Vector3.UP.cross(dir)
		if axis.length() < 0.001:
			axis = Vector3.RIGHT
		grapple_line.basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		(grapple_line.mesh as CylinderMesh).height = a.distance_to(b)
	board_t -= delta
	if board_t <= 0.0:
		_set_msg("They cut the grapple and fled!", 3.0)
		_end_boarding(true)
	elif board_smashed >= 5:
		_capture_ship()


func _smash_crate(k: int) -> void:
	if k < 0 or k >= board_crates.size():
		return
	var crate := board_crates[k] as Node3D
	if crate == null or not is_instance_valid(crate) or crate.visible == false:
		return
	crate.visible = false
	board_smashed += 1
	Haptics.thump()
	GraphicsPolish.spawn_sparks(self, crate.global_position, Color(0.9, 0.7, 0.4), 20)
	taps.erase("bcrate_%d" % k)
	_set_msg("Crates smashed: %d/5" % board_smashed, 1.5)


func _capture_ship() -> void:
	var e: Dictionary = enemies[board_target]
	var bonus := int(e["gold"]) * 2
	gold += bonus
	Haptics.thump()
	GraphicsPolish.spawn_confetti(self, (e["node"] as Node3D).global_position + Vector3(0, 3, 0), 50)
	_set_msg("SHIP CAPTURED! +%d gold prize" % bonus, 4.0)
	(e["node"] as Node3D).queue_free()
	enemies.remove_at(board_target)
	_end_boarding(false)
	_update_hud()


func _end_boarding(fled: bool) -> void:
	if fled and board_target >= 0 and board_target < enemies.size():
		(enemies[board_target] as Dictionary)["state"] = "flee"
	boarding = false
	board_target = -1
	board_crates.clear()
	for k in taps.keys():
		if str(k).begins_with("bcrate_"):
			taps.erase(k)
	if grapple_line != null and is_instance_valid(grapple_line):
		grapple_line.queue_free()
	grapple_line = null


func _spawn_kraken() -> void:
	kraken = Node3D.new()
	kraken.position = ship.global_position + _ship_forward() * 30.0 + Vector3(0, 2.0, 0)
	add_child(kraken)
	var flesh := GraphicsPolish.pbr(Color(0.28, 0.12, 0.38), 0.1, 0.55)
	var body := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 3.0
	bs.height = 6.0
	body.mesh = bs
	body.material_override = flesh
	kraken.add_child(body)
	# Glowing eyes.
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.42
		es.height = 0.84
		eye.mesh = es
		eye.material_override = GraphicsPolish.glow(Color(1.0, 0.15, 0.25), 2.6)
		eye.position = Vector3(side * 1.3, 1.2, -2.5)
		kraken.add_child(eye)
	# Crown spikes.
	for s in 6:
		var spike := MeshInstance3D.new()
		var cb := CylinderMesh.new()
		cb.top_radius = 0.0
		cb.bottom_radius = 0.35
		cb.height = 1.6
		spike.mesh = cb
		spike.material_override = flesh
		var ang := TAU * float(s) / 6.0
		spike.position = Vector3(cos(ang) * 1.8, 2.6, sin(ang) * 1.8)
		spike.rotation = Vector3(0.5 * sin(ang), 0, -0.5 * cos(ang))
		kraken.add_child(spike)
	# 8 tentacles, each 3 segments.
	for t in 8:
		var tent := Node3D.new()
		var ang := TAU * float(t) / 8.0
		tent.position = Vector3(cos(ang) * 2.2, -1.6, sin(ang) * 2.2)
		kraken.add_child(tent)
		var parent := tent
		var segs := []
		for sgi in 3:
			var seg := MeshInstance3D.new()
			var cb2 := CylinderMesh.new()
			cb2.top_radius = 0.34 - float(sgi) * 0.09
			cb2.bottom_radius = 0.28 - float(sgi) * 0.09
			cb2.height = 2.4
			seg.mesh = cb2
			seg.material_override = flesh
			seg.position = Vector3(0, -1.2, 0)
			parent.add_child(seg)
			var joint := Node3D.new()
			joint.position = Vector3(0, -2.4, 0)
			seg.add_child(joint)
			parent = joint
			segs.append(seg)
		# Sucker glow dots on the first segment.
		for d in 4:
			var dot := MeshInstance3D.new()
			var ds := SphereMesh.new()
			ds.radius = 0.10
			ds.height = 0.20
			dot.mesh = ds
			dot.material_override = GraphicsPolish.glow(Color(1.0, 0.35, 0.6), 1.8)
			dot.position = Vector3(0.3 * (1.0 if d % 2 == 0 else -1.0), -0.6 - float(d) * 0.35, 0.28)
			(segs[0] as MeshInstance3D).add_child(dot)
		tent.set_meta("phase", randf() * TAU)
		kraken_tents.append(tent)
	kraken_hp = kraken_max
	kraken_cd = 2.0
	if hud_boss_bg != null:
		hud_boss_bg.visible = true
		hud_boss_fg.visible = true
		hud_boss_fg.scale.x = 1.0
		hud_boss_fg.position.x = 0.0


func _damage_kraken(dmg: float, hit_pos: Vector3) -> void:
	if kraken == null or state != "combat":
		return
	kraken_hp -= dmg
	Haptics.pulse(0.7, 0.1)
	GraphicsPolish.spawn_sparks(self, hit_pos, Color(0.9, 0.3, 0.7), 20)
	var f := clampf(kraken_hp / kraken_max, 0.0, 1.0)
	hud_boss_fg.scale.x = maxf(f, 0.001)
	hud_boss_fg.position.x = -0.69 * (1.0 - f)
	if kraken_hp <= 0.0:
		_kill_kraken()


func _kill_kraken() -> void:
	Haptics.thump()
	var kp := kraken.global_position
	GraphicsPolish.spawn_sparks(self, kp, Color(1.0, 0.5, 0.8), 60)
	GraphicsPolish.spawn_sparks(self, kp, Color(1.0, 0.8, 0.3), 40)
	GraphicsPolish.spawn_confetti(self, kp, 80)
	gold += 150
	kraken.queue_free()
	kraken = null
	kraken_tents.clear()
	if hud_boss_bg != null:
		hud_boss_bg.visible = false
		hud_boss_fg.visible = false
	_update_hud()
	_victory()


func _update_kraken(delta: float) -> void:
	if kraken == null or not is_instance_valid(kraken):
		return
	var sp := ship.global_position
	# Drift to keep ~22m from the player, bobbing.
	var to_k: Vector3 = kraken.global_position - sp
	var dist := to_k.length()
	var want: Vector3 = sp + to_k.normalized() * 22.0
	want.y = 8.0 + sin(pulse_t * 0.9) * 1.5
	kraken.global_position = kraken.global_position.lerp(want, clampf(0.5 * delta, 0.0, 1.0))
	kraken.rotation.y = lerp_angle(kraken.rotation.y, atan2(-(sp.x - kraken.global_position.x), -(sp.z - kraken.global_position.z)), clampf(1.5 * delta, 0.0, 1.0))
	# Tentacle idle wave.
	for ti in kraken_tents.size():
		var tent := kraken_tents[ti] as Node3D
		var ph: float = tent.get_meta("phase")
		tent.rotation.x = 0.35 + 0.30 * sin(pulse_t * 1.7 + ph)
		tent.rotation.z = 0.25 * sin(pulse_t * 1.3 + ph * 1.7)
	# Whip attack when close.
	if kraken_whip < 0:
		kraken_cd -= delta
		if kraken_cd <= 0.0 and dist < 26.0:
			kraken_whip = randi() % kraken_tents.size()
			kraken_whip_t = 0.8
			_set_msg("The kraken lashes out!", 1.5)
	else:
		kraken_whip_t -= delta
		var tent := kraken_tents[kraken_whip] as Node3D
		tent.rotation.x = lerpf(tent.rotation.x, -1.1, clampf(8.0 * delta, 0.0, 1.0))
		if kraken_whip_t <= 0.0:
			if dist < 13.0:
				_damage_player(18.0, kraken.global_position)
				ship_vel += (sp - kraken.global_position).normalized() * 8.0
				_set_msg("Tentacle slam! -18 hull", 2.0)
			kraken_whip = -1
			kraken_cd = randf_range(3.0, 4.5)
	# Ink barrage on its own timer.
	_update_kraken_ink(delta, dist)


var _ink_t := 0.0


func _update_kraken_ink(delta: float, dist: float) -> void:
	_ink_t -= delta
	if _ink_t > 0.0 or dist > 40.0:
		return
	_ink_t = 2.6
	var mouth: Vector3 = kraken.global_position + Vector3(0, 0.5, 0)
	for k in 3:
		var aim: Vector3 = ship.global_position + Vector3(0, 2.0, 0) + ship_vel * 0.4 + Vector3(randf_range(-3, 3), randf_range(0, 2), randf_range(-3, 3))
		var dir: Vector3 = (aim - mouth).normalized()
		var n := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		n.mesh = sm
		n.material_override = GraphicsPolish.glow(Color(0.35, 0.08, 0.5), 1.4)
		n.position = mouth
		add_child(n)
		n.add_child(GraphicsPolish.make_trail(Color(0.5, 0.15, 0.7), 0.16))
		balls.append({"node": n, "vel": dir * 18.0, "from_player": false, "dmg": 12.0, "life": 5.0})


func _check_wave_clear() -> void:
	if state != "combat" or boarding:
		return
	for e in enemies:
		if (e as Dictionary)["state"] == "fight" or (e as Dictionary)["state"] == "boarded":
			return
	if kraken != null:
		return
	# Wave cleared.
	if wave_idx + 1 > best_wave:
		best_wave = wave_idx + 1
		_save_progress()
	wave_idx += 1
	_update_hud()
	if wave_idx >= WAVES.size():
		return # victory handled by kraken kill
	_set_msg("Wave %d cleared!" % wave_idx, 3.0)
	_show_upgrade()


func _victory() -> void:
	state = "victory"
	gold_bank += gold
	if best_wave < 6:
		best_wave = 6
	_save_progress()
	_set_msg("", 0.0)
	_clear_panel()
	panel_root = Node3D.new()
	panel_root.position = _panel_in_front(3.4, 0.3)
	add_child(panel_root)
	if camera != null:
		panel_root.look_at(camera.global_position, Vector3.UP)
	_panel_card("SKY LORD OF THE CLOUDS!", Vector3(0, 0.8, 0), Vector2(2.6, 0.42), Color(1.0, 0.8, 0.25), "vtitle", "noop", 0, 44)
	_panel_card("Kraken slain. Prize gold banked: %d\nBank total: %d" % [gold, gold_bank], Vector3(0, 0.15, 0), Vector2(2.4, 0.42), Color(0.5, 0.8, 1.0), "vsub", "noop", 0, 30)
	_panel_card("SAIL AGAIN \u25b8", Vector3(0, -0.5, 0), Vector2(1.6, 0.40), Color(0.15, 0.55, 0.25), "retry", "setsail", 0, 38)
	GraphicsPolish.spawn_confetti(self, ship.global_position + Vector3(0, 4, -4), 120)


func _game_over() -> void:
	state = "gameover"
	gold_bank += gold / 2 # salvage half
	_save_progress()
	_set_msg("", 0.0)
	_clear_panel()
	_clear_board_btn()
	panel_root = Node3D.new()
	panel_root.position = _panel_in_front(3.4, 0.3)
	add_child(panel_root)
	if camera != null:
		panel_root.look_at(camera.global_position, Vector3.UP)
	_panel_card("SHIP DOWN", Vector3(0, 0.8, 0), Vector2(2.0, 0.42), Color(0.9, 0.25, 0.2), "gtitle", "noop", 0, 52)
	_panel_card("The clouds claim another hull.\nSalvaged %d gold (bank: %d)" % [gold / 2, gold_bank], Vector3(0, 0.15, 0), Vector2(2.2, 0.42), Color(0.7, 0.75, 0.9), "gsub", "noop", 0, 30)
	_panel_card("TRY AGAIN \u25b8", Vector3(0, -0.5, 0), Vector2(1.6, 0.40), Color(0.15, 0.55, 0.25), "retry", "setsail", 0, 38)
	GraphicsPolish.spawn_sparks(self, ship.global_position, Color(1.0, 0.5, 0.2), 60)


func _on_tap(tap_id: String) -> void:
	if not taps.has(tap_id):
		return
	var info: Dictionary = taps[tap_id]
	var kind := str(info["kind"])
	var data: Variant = info["data"]
	match kind:
		"setsail":
			_start_run()
		"upgrade":
			_buy_upgrade(int(data))
		"nextwave":
			_start_wave()
		"board":
			_start_boarding(int(data))
		"bcrate":
			_smash_crate(int(data))
		"noop":
			pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				pressing = true
				press_pos = mb.position
				press_moved = 0.0
				press_time = Time.get_ticks_msec()
				drag_steer = false
			else:
				if pressing:
					# Quick click (no drag) = fire cannons.
					if press_moved < 12.0 and Time.get_ticks_msec() - press_time < 400 and not drag_steer:
						var hit := _screen_pick(mb.position)
						if hit != "":
							_on_tap(hit)
						else:
							_fire_cannon()
					drag_steer = false
				pressing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if pressing and (state == "combat"):
			press_moved += mm.relative.length()
			if press_moved > 14.0:
				drag_steer = true
			if drag_steer:
				# Drag right/left = bank & turn; drag up = push for speed.
				turn_input = clampf((mb_pos_x() - press_pos.x) / 160.0, -1.0, 1.0)
				throttle = clampf(0.35 + (press_pos.y - mb_pos_y()) * 0.004, 0.0, 1.0)


func mb_pos_x() -> float:
	return get_viewport().get_mouse_position().x


func mb_pos_y() -> float:
	return get_viewport().get_mouse_position().y


func _process(delta: float) -> void:
	pulse_t += delta
	if Input.is_key_pressed(KEY_R) and state != "menu":
		_start_run()
		return
	# Keyboard steering fallback.
	if state == "combat" and not xr_mode:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			turn_input = -1.0
		elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			turn_input = 1.0
		elif not drag_steer:
			turn_input = lerpf(turn_input, 0.0, clampf(3.0 * delta, 0.0, 1.0))
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			throttle = minf(throttle + delta * 0.8, 1.0)
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			throttle = maxf(throttle - delta * 0.8, 0.0)
	# XR hand steering (gated so desktop never double-fires).
	if xr_mode and state == "combat" and camera != null:
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.4)
		var local: Vector3 = camera.global_transform.affine_inverse() * pp
		turn_input = clampf((local.x - 0.18) * 2.0, -1.0, 1.0)
		throttle = clampf((-local.z - 1.3) * 1.1, 0.0, 1.0)
	# Ship flight model.
	if state == "combat" or state == "upgrade":
		var turn_rate := 1.1
		heading += turn_input * turn_rate * delta
		var want_speed := throttle * top_speed
		var cur_speed := ship_vel.length()
		cur_speed = lerpf(cur_speed, want_speed, clampf(1.2 * delta, 0.0, 1.0))
		ship_vel = _ship_forward() * cur_speed
		ship_vel.y = sin(pulse_t * 1.4) * 0.35
		ship.global_position += ship_vel * delta
		# Soft arena bound: steer back toward center.
		var flat := Vector2(ship.global_position.x, ship.global_position.z)
		if flat.length() > ARENA_R:
			var to_c: Vector3 = (Vector3.ZERO - ship.global_position)
			to_c.y = 0.0
			var want_yaw := atan2(-to_c.x, -to_c.z)
			heading = lerp_angle(heading, want_yaw, clampf(1.5 * delta, 0.0, 1.0))
		ship.global_position.y = clampf(ship.global_position.y, 2.0, 24.0)
		ship.rotation.y = heading
		ship.rotation.z = lerpf(ship.rotation.z, -turn_input * 0.45, clampf(4.0 * delta, 0.0, 1.0))
		ship.rotation.x = lerpf(ship.rotation.x, (throttle - 0.35) * -0.12, clampf(3.0 * delta, 0.0, 1.0))
	# Propellers + balloon bob.
	for p in props:
		(p as Node3D).rotation.z += delta * (6.0 + throttle * 22.0)
	if balloon != null:
		balloon.position.y = 8.6 + sin(pulse_t * 1.1) * 0.12
	# Clouds drift + wrap.
	for c in clouds:
		var cl := c as Node3D
		cl.position.x += float(cl.get_meta("drift")) * delta
		if cl.position.x > 75.0:
			cl.position.x = -75.0
	# Islands bob.
	for isl in islands:
		var inod := isl as Node3D
		inod.position.y += sin(pulse_t * 0.5 + float(inod.get_meta("bob_phase"))) * delta * 0.25
	# Combat updates.
	if fire_cd > 0.0:
		fire_cd -= delta
	if state == "combat":
		_update_enemies(delta)
		_update_balls(delta)
		_update_coins(delta)
		_update_boarding(delta)
		_update_boarding_prompt()
		_update_kraken(delta)
		_check_wave_clear()
		# XR flick-to-board: fast hand flick while BOARD is available.
		if xr_mode:
			var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
			var pp2 := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.4)
			if delta > 0.0:
				xr_pointer_vel = xr_pointer_vel.lerp((pp2 - xr_pointer_prev) / delta, 0.4)
			xr_pointer_prev = pp2
			if pinching and not prev_pinch:
				press_time = Time.get_ticks_msec()
			elif not pinching and prev_pinch:
				# Quick pinch-tap: fire, or tap a UI card.
				if Time.get_ticks_msec() - press_time < 400:
					var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
					var hit := _ray_pick(r[0], r[1])
					if hit != "":
						_on_tap(hit)
					elif not boarding:
						_fire_cannon()
				if board_btn != null and xr_pointer_vel.length() > 3.0 and not boarding:
					_start_boarding(_nearest_enemy())
			prev_pinch = pinching
	# Camera.
	if camera != null:
		if not xr_mode:
			var behind: Vector3 = ship.global_position + Vector3(sin(heading), 0, cos(heading)) * 10.5 + Vector3(0, 4.2, 0)
			if shake > 0.0:
				behind += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.6
				shake = maxf(shake - delta * 1.8, 0.0)
			camera.global_position = camera.global_position.lerp(behind, clampf(3.5 * delta, 0.0, 1.0))
			camera.look_at(ship.global_position + Vector3(0, 2.5, 0) + _ship_forward() * 4.0, Vector3.UP)
		# HUD glued in front of the camera (both modes).
		hud_root.global_transform = camera.global_transform
	# Muzzle flash decay on enemies.
	for e in enemies:
		var fl := (e as Dictionary)["flash"] as OmniLight3D
		if fl != null and fl.light_energy > 0.0:
			fl.light_energy = maxf(fl.light_energy - delta * 14.0, 0.0)
	# Timers.
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0 and msg_label != null:
			msg_label.text = ""
	_update_hud()
