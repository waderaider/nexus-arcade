## StarshipBridge.gd - NEXUS ARCADE v0.11.0: STARSHIP BRIDGE.
## Your room becomes a starship bridge: helm at your desk, tactical on your
## wall, engineering at your couch (real RoomKit anchors, graceful
## fallbacks). Three scripted acts — ESCAPE, ESCORT, LAST STAND — with
## walk-between-stations play. Damage = red flicker + console sparks.
## Offline voice commands were cut per API discipline (RISKY); orders run
## through big console buttons instead.
##
## Exterior ships: CraftPix battle-spaceships + Quaternius spaceships
## (royalty-free / CC0 1.0). Consoles are cheap emissive quads, built in code.
extends Node3D
class_name StarshipBridgeGame

const SHIP_DIR := "res://assets/models/starship_bridge/"
const ACTS := ["ESCAPE", "ESCORT", "LAST STAND"]

var controller_config := {
	"uses_controllers": true,
	"skin": "none",
	"buttons": {
		"trigger": "Fire / press console",
		"grip": "Grab",
		"thumbstick": "Helm throttle",
		"menu": "Pause",
	},
}

var _origin: Node3D
var _controllers := {}
var _stations := {}        # name -> {pos: Vector3, root: Node3D}
var _act := 0
var _act_t := 0.0
var _act_state := "brief"  # brief | play | done
var _hull := 100.0
var _throttle := 0.0
var _helm_steer := Vector2.ZERO
var _viewport_stars: Array = []
var _viewport_root: Node3D
var _asteroids: Array = []
var _enemies: Array = []
var _friendlies: Array = []
var _shots: Array = []
var _power := {"weapons": 34, "shields": 33, "engines": 33}
var _power_nodes := {}
var _shield := 50.0
var _trig_prev := {}
var _red_flash: ColorRect
var _flash_t := 0.0
var _sparks: GPUParticles3D
var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _game_over := false
# v0.11.0 (Animator) ambient elements:
var _battle_fx: Array = []        # (a) exterior battle flashes
var _cap_ships: Array = []        # (a) drifting capital-ship silhouettes
var _console_mats: Array = []     # (b) screen materials for flicker
var _alert_dust: GPUParticles3D = null  # (c) dust in red-alert light
var _crew_sprites: Array = []     # (d) viewscreen crew silhouettes
var _escort_target: Node3D
var _escort_hp := 100.0
var _spawn_acc := 0.0


func _ready() -> void:
	_origin = _find_origin()
	_find_controllers()
	ArtKit.register_game_sfx(self, {
		"fire": "laser", "boom": "explosion", "hit": "hit", "alarm": "buzzer",
		"win": "fanfare", "lose": "fail", "jump": "whoosh", "power": "powerup",
		"select": "ui_click", "shield": "sparkle",
	})
	ArtKit.set_intensity(self, 1)
	if RoomKit.is_available():
		await RoomKit.refresh()
	_build_room()
	_build_flash()
	_build_particles()
	_build_bridge_ambient()
	_build_hud()
	_telemetry("bridge_start", {})
	_start_act(0)


# ---------------------------------------------------------------- setup ---

func _find_origin() -> Node3D:
	var f := get_tree().root.find_children("*", "XROrigin3D", true, false)
	return f[0] as Node3D if not f.is_empty() else null


func _find_controllers() -> void:
	_controllers.clear()
	if _origin == null:
		return
	for side in ["left", "right"]:
		var n := _origin.get_node_or_null("LeftController" if side == "left" else "RightController")
		if n != null:
			_controllers[side] = n


func _head_pos() -> Vector3:
	if _origin != null:
		var c := _origin.get_node_or_null("XRCamera3D") as Camera3D
		if c != null:
			return c.global_position
	return Vector3(0, 1.6, 0)


func _build_room() -> void:
	# --- Helm: desk anchor (or first table, or fallback) ---
	var helm_pos := _head_pos() + Vector3(0, -0.75, -1.1)
	var helm_yaw := 0.0
	var desks := RoomKit.get_furniture_by_label("desk")
	var tables := RoomKit.get_tables()
	var anchor: Dictionary = desks[0] if not desks.is_empty() else (tables[0] if not tables.is_empty() else {})
	if not anchor.is_empty():
		helm_pos = RoomKit.cuboid_top(anchor) + Vector3(0, 0.02, 0)
		helm_yaw = float(anchor.get("yaw", 0.0))
	_stations["helm"] = {"pos": helm_pos, "root": _build_console(helm_pos, helm_yaw, "HELM", Color(0.2, 0.7, 1.0))}
	# --- Tactical: largest wall ---
	var tac_pos := _head_pos() + Vector3(-1.8, 0.1, -1.8)
	var tac_yaw := 0.785
	var walls := RoomKit.get_walls()
	if not walls.is_empty():
		var best: Dictionary = walls[0]
		var ba := 0.0
		for w in walls:
			var a: float = (w["size"] as Vector2).x * (w["size"] as Vector2).y
			if a > ba:
				ba = a
				best = w
		var wp: Vector3 = best["position"]
		var n: Vector3 = best["normal"]
		tac_pos = Vector3(wp.x, 1.5, wp.z) + n * 0.06
		tac_yaw = atan2(n.x, n.z)
	_stations["tactical"] = {"pos": tac_pos, "root": _build_console(tac_pos, tac_yaw, "TACTICAL", Color(1.0, 0.35, 0.3))}
	# --- Engineering: couch (or fallback) ---
	var eng_pos := _head_pos() + Vector3(1.6, -0.9, 0.6)
	var couch := RoomKit.get_couch()
	if couch.is_empty():
		var beds := RoomKit.get_furniture_by_label("bed")
		if not beds.is_empty():
			couch = beds[0]
	if not couch.is_empty():
		eng_pos = RoomKit.cuboid_top(couch) + Vector3(0, 0.03, 0)
	_stations["engineering"] = {"pos": eng_pos, "root": _build_console(eng_pos, 0.0, "ENGINEERING", Color(1.0, 0.7, 0.2))}
	# --- Viewports: starfield windows on up to 2 walls ---
	_build_viewports(walls)


func _build_console(pos: Vector3, yaw: float, title: String, accent: Color) -> Node3D:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	# Console body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.12, 0.55)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.10, 0.12, 0.16)
	bmat.metallic = 0.6
	bmat.roughness = 0.4
	body.material_override = bmat
	body.position = Vector3(0, -0.06, 0)
	root.add_child(body)
	# Emissive screen.
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 0.42)
	scr.mesh = qm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.02, 0.05, 0.08)
	smat.emission_enabled = true
	smat.emission = accent
	smat.emission_energy_multiplier = 0.9
	scr.material_override = smat
	scr.position = Vector3(0, 0.06, -0.1)
	scr.rotation.x = -0.5
	root.add_child(scr)
	# Title label.
	var l := Label3D.new()
	l.text = title
	l.font_size = 72
	l.modulate = accent
	l.position = Vector3(0, 0.32, -0.12)
	l.rotation.x = -0.5
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root.add_child(l)
	root.set_meta("accent", accent)
	root.set_meta("screen", scr)
	root.set_meta("title", title)
	return root


func _build_viewports(walls: Array) -> void:
	_viewport_root = Node3D.new()
	get_tree().current_scene.add_child(_viewport_root)
	var spots: Array = []
	for w in walls:
		var wp: Vector3 = w["position"]
		var n: Vector3 = w["normal"]
		if (w["size"] as Vector2).x > 2.0:
			spots.append({"pos": Vector3(wp.x, 1.7, wp.z) + n * 0.05, "yaw": atan2(n.x, n.z)})
		if spots.size() >= 2:
			break
	if spots.is_empty():
		var hp := _head_pos()
		spots = [
			{"pos": hp + Vector3(0, 0.2, -2.6), "yaw": 0.0},
			{"pos": hp + Vector3(-2.4, 0.2, -1.2), "yaw": 0.6},
		]
	for s in spots:
		_build_viewport(s["pos"], s["yaw"])
	# Distant capital ships drifting past the windows.
	for f in ["frigate_01.glb", "frigate_03.glb", "corvette_02.glb"]:
		var ps: PackedScene = load(SHIP_DIR + f) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		var hp2 := _head_pos()
		inst.position = hp2 + Vector3(randf_range(-6, 6), randf_range(1, 3), randf_range(-9, -6))
		inst.scale = Vector3.ONE * 1.6
		_viewport_root.add_child(inst)
		_viewport_stars.append({"node": inst, "speed": randf_range(0.05, 0.15)})


func _build_viewport(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	_viewport_root.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	# Frame.
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(2.6, 1.7, 0.08)
	frame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.12, 0.14, 0.18)
	fmat.metallic = 0.7
	frame.material_override = fmat
	root.add_child(frame)
	# Starfield: one MultiMesh of emissive quads = 1 draw call.
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = _star_quad()
	stars.instance_count = 140
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(140):
		var t := Transform3D(Basis(), Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.75, 0.75), -0.06))
		stars.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = stars
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.9, 0.95, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.85, 0.92, 1.0)
	smat.emission_energy_multiplier = 2.2
	mmi.material_override = smat
	root.add_child(mmi)
	# Dark space backdrop.
	var bg := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(2.5, 1.6)
	bg.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.008, 0.01, 0.03)
	bg.material_override = bmat
	bg.position = Vector3(0, 0, -0.07)
	root.add_child(bg)
	root.set_meta("stars", mmi)


func _star_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	return q


## v0.11.0 (Animator): 5 cheap ambient elements.
## (a) exterior battle outside the viewports · (b) console flicker ·
## (c) red-alert dust · (d) crew silhouettes · (e) damage spark drips.
func _build_bridge_ambient() -> void:
	# (a) Distant battle flashes + capital-ship silhouettes on the viewports.
	var vp_roots: Array = _viewport_root.get_children() if _viewport_root != null else []
	for vpr in vp_roots:
		if not (vpr is Node3D):
			continue
		for i in 3:
			var fl := MeshInstance3D.new()
			var fq := QuadMesh.new()
			fq.size = Vector2(0.12, 0.12)
			fl.mesh = fq
			var fmat := GraphicsPolish.glow(Color(1.0, 0.7, 0.3), 2.5)
			fl.material_override = fmat
			fl.position = Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), -0.05)
			fl.visible = false
			vpr.add_child(fl)
			_battle_fx.append({"node": fl, "mat": fmat, "phase": randf() * TAU,
				"next": randf_range(1.0, 4.0)})
		for i in 2:
			var ship := MeshInstance3D.new()
			var sq := QuadMesh.new()
			sq.size = Vector2(0.5, 0.12)
			ship.mesh = sq
			ship.material_override = GraphicsPolish.pbr(Color(0.05, 0.06, 0.09), 0.0, 0.9)
			ship.position = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), -0.055)
			vpr.add_child(ship)
			_cap_ships.append({"node": ship, "speed": randf_range(0.02, 0.06),
				"dir": 1.0 if randf() < 0.5 else -1.0})
	# (b) Console screen flicker materials (phase-offset per console).
	for key in _stations.keys():
		var st: Dictionary = _stations[key]
		var root: Node3D = st["root"]
		if root != null and root.has_meta("screen"):
			var scr: MeshInstance3D = root.get_meta("screen")
			var m := scr.material_override as StandardMaterial3D
			if m != null:
				_console_mats.append({"mat": m, "phase": randf() * TAU})
	# (c) Dust motes hanging in the red-alert light.
	_alert_dust = GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, 0), 2.0, 30)
	_alert_dust.visible = false
	# (d) Two crew silhouettes at a distant console (slow 2-frame sway).
	for i in 2:
		var crew := MeshInstance3D.new()
		var cq := QuadMesh.new()
		cq.size = Vector2(0.28, 0.5)
		crew.mesh = cq
		crew.material_override = GraphicsPolish.pbr(Color(0.04, 0.05, 0.08), 0.0, 1.0)
		crew.position = Vector3(-0.9 + float(i) * 0.5, 1.05, -1.9)
		add_child(crew)
		_crew_sprites.append({"node": crew, "phase": float(i) * 2.1})


## (e) Damaged consoles drip sparks (called from the damage path).
func _drip_sparks_from_consoles() -> void:
	for key in _stations.keys():
		var st: Dictionary = _stations[key]
		var root: Node3D = st["root"]
		if root != null:
			GraphicsPolish.spawn_sparks(self, root.position + Vector3(0, 0.1, 0),
				Color(1.0, 0.6, 0.2), 6)


func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_red_flash = ColorRect.new()
	_red_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_red_flash.color = Color(1.0, 0.1, 0.1, 0.0)
	_red_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_red_flash)


func _build_particles() -> void:
	_sparks = GPUParticles3D.new()
	_sparks.amount = 36
	_sparks.lifetime = 0.7
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 45.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.015
	pm.scale_max = 0.05
	pm.color = Color(1.0, 0.7, 0.2)
	_sparks.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_color = Color(1.0, 0.75, 0.25)
	qm.emission_enabled = true
	qm.emission = Color(1.0, 0.7, 0.2)
	qm.emission_energy_multiplier = 3.0
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_sparks.draw_pass_1 = quad
	_sparks.draw_pass_1.material = qm
	get_tree().current_scene.add_child(_sparks)


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.font_size = 52
	_hud.modulate = Color(0.75, 0.92, 1.0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.font_size = 100
	_announce.modulate = Color(0.5, 0.9, 1.0)
	_announce.outline_size = 14
	add_child(_announce)


# ---------------------------------------------------------------- acts ---

func _start_act(n: int) -> void:
	_act = n
	_act_state = "brief"
	_act_t = 4.0
	# v0.11.0 Narrative: the Meridian intro lands once, before Act 1's brief.
	if n == 0:
		_announce_text("STARSHIP BRIDGE\nThe Meridian lost her crew at the Rift.\nHelm, tactical, engineering — all yours.", 4.5)
		JuiceFX.title_card("STARSHIP BRIDGE", "One officer left. Your room is the ship.", Color(0.3, 0.7, 1.0))
	else:
		_announce_text("ACT %d: %s" % [n + 1, ACTS[n]], 3.5)
	ArtKit.game_sfx(self, "jump")
	_telemetry("bridge_act", {"act": n, "name": ACTS[n]})
	if n == 1:
		_spawn_escort()
	elif n == 2:
		_build_power_ui()


func _update_bridge_ambient(delta: float, t: float) -> void:
	# (a) Exterior battle: flashes pop on a randomized cadence; capital
	# ships drift across the viewport.
	for fx in _battle_fx:
		var n: MeshInstance3D = fx["node"]
		if not is_instance_valid(n):
			continue
		var nx: float = float(fx["next"]) - delta
		fx["next"] = nx
		if nx <= 0.0:
			fx["next"] = randf_range(2.0, 7.0)
			n.visible = true
			(fx["mat"] as StandardMaterial3D).emission_energy_multiplier = 3.5
		if n.visible:
			var e := (fx["mat"] as StandardMaterial3D).emission_energy_multiplier
			e = lerpf(e, 0.0, minf(1.0, 5.0 * delta))
			(fx["mat"] as StandardMaterial3D).emission_energy_multiplier = e
			if e < 0.15:
				n.visible = false
	for cs in _cap_ships:
		var sn: MeshInstance3D = cs["node"]
		if is_instance_valid(sn):
			sn.position.x += float(cs["speed"]) * float(cs["dir"]) * delta
			if sn.position.x > 1.3:
				sn.position.x = -1.3
			elif sn.position.x < -1.3:
				sn.position.x = 1.3
	# (b) Console flicker: per-console phase, never in sync.
	for cm in _console_mats:
		AnimFluidity.emissive_flicker(cm["mat"], t, float(cm["phase"]), 0.9, 0.18, 9.0)
	# (c) Red-alert dust: visible only while the alert flash is hot.
	if _alert_dust != null and is_instance_valid(_alert_dust):
		_alert_dust.visible = _flash_t > 0.05
	# (d) Crew silhouettes: slow console-work sway (2-frame feel).
	for cr in _crew_sprites:
		var cn: MeshInstance3D = cr["node"]
		if is_instance_valid(cn):
			cn.rotation.z = sin(t * 1.4 + float(cr["phase"])) * 0.08
			cn.position.y = 1.05 + sin(t * 2.1 + float(cr["phase"])) * 0.02


func _process(delta: float) -> void:
	if _game_over:
		return
	_update_bridge_ambient(delta, Time.get_ticks_msec() / 1000.0)
	if _announce_t > 0.0:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce.text = ""
	if _flash_t > 0.0:
		_flash_t -= delta
		_red_flash.color.a = clampf(_flash_t * 1.4, 0.0, 0.55)
	_update_viewports(delta)
	match _act_state:
		"brief":
			_act_t -= delta
			if _act_t <= 0.0:
				_act_state = "play"
				_announce_text("GO!", 1.2)
		"play":
			match _act:
				0: _act_escape(delta)
				1: _act_escort(delta)
				2: _act_laststand(delta)
	_update_shots(delta)
	_update_hud()
	_check_station_proximity()


func _update_viewports(delta: float) -> void:
	for s in _viewport_stars:
		var node: Node3D = s["node"]
		node.position.x += float(s["speed"]) * delta
		if node.position.x > 9.0:
			node.position.x = -9.0


func _player_station() -> String:
	# Which station the player is standing at (nearest within 1.1 m).
	var hp := _head_pos()
	var best := ""
	var bd := 1.15
	for k in _stations.keys():
		var d: float = hp.distance_to((_stations[k] as Dictionary)["pos"])
		if d < bd:
			bd = d
			best = k
	return best


func _check_station_proximity() -> void:
	pass  # hooks for future per-station prompts; stations are positional


# --- ACT 1: ESCAPE — helm: throttle + steer, dodge asteroids ---
func _act_escape(delta: float) -> void:
	_act_t += delta
	_poll_helm()
	_spawn_acc -= delta
	if _spawn_acc <= 0.0:
		_spawn_acc = randf_range(0.5, 1.1)
		_spawn_asteroid()
	for a in _asteroids.duplicate():
		var node: MeshInstance3D = a["node"]
		node.position.z += (2.2 + _throttle * 3.0) * delta
		node.rotation += Vector3(delta, delta * 0.7, 0)
		if node.position.z > 1.5:
			_recycle_asteroid(a)
			continue
		var hp := _head_pos()
		if node.position.distance_to(hp) < 0.55:
			_recycle_asteroid(a)
			_damage(12.0, "helm")
	if _act_t > 75.0:
		_complete_act()


func _poll_helm() -> void:
	var ctl: XRController3D = _controllers.get("right", _controllers.get("left"))
	if ctl != null and XRServer.get_tracker(ctl.tracker) != null:
		var stick := ctl.get_vector2("thumbstick")
		_throttle = clampf(_throttle + stick.y * -0.8 * get_process_delta_time(), 0.0, 1.0)
		_helm_steer = stick
		var trig := XRUIPointer.trigger_pressed(ctl)
		var key := "helm_boost"
		if trig and not bool(_trig_prev.get(key, false)):
			_throttle = minf(1.0, _throttle + 0.25)
			ArtKit.game_sfx(self, "jump", 1.3)
		_trig_prev[key] = trig


func _spawn_asteroid() -> void:
	var a := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = randf_range(0.18, 0.42)
	sm.height = sm.radius * 2.0
	sm.radial_segments = 7
	sm.rings = 4
	a.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.28, 0.25)
	mat.roughness = 1.0
	a.material_override = mat
	var hp := _head_pos()
	a.position = hp + Vector3(randf_range(-3.5, 3.5), randf_range(-1.2, 1.8), randf_range(-9, -6))
	# Steer away from a dead-center spawn so it stays dodgeable.
	get_tree().current_scene.add_child(a)
	_asteroids.append({"node": a})


func _recycle_asteroid(a: Dictionary) -> void:
	(a["node"] as MeshInstance3D).queue_free()
	_asteroids.erase(a)


# --- ACT 2: ESCORT — tactical: aim on the wall display, trigger fires ---
func _spawn_escort() -> void:
	var ps: PackedScene = load(SHIP_DIR + "spaceship_1.glb") as PackedScene
	if ps != null:
		_escort_target = ps.instantiate() as Node3D
		var hp := _head_pos()
		_escort_target.position = hp + Vector3(1.5, 0.4, -5.0)
		_escort_target.scale = Vector3.ONE * 0.8
		get_tree().current_scene.add_child(_escort_target)


func _act_escort(delta: float) -> void:
	_act_t += delta
	_spawn_acc -= delta
	if _spawn_acc <= 0.0:
		_spawn_acc = randf_range(1.2, 2.2)
		_spawn_raider()
	var tac: Dictionary = _stations["tactical"]
	var tac_pos: Vector3 = tac["pos"]
	for e in _enemies.duplicate():
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			_enemies.erase(e)
			continue
		var tgt: Vector3 = _escort_target.global_position if is_instance_valid(_escort_target) else _head_pos()
		var to: Vector3 = tgt - node.position
		node.position += to.normalized() * 1.1 * delta
		node.rotation.y = atan2(to.x, to.z)
		if to.length() < 1.2:
			_enemies.erase(e)
			node.queue_free()
			_escort_hp -= 14.0
			_damage(0.0, "tactical")
			_announce_text("FREIGHTER HIT!", 1.5)
			if _escort_hp <= 0.0:
				_defeat("The freighter was destroyed.")
				return
	# Fire phasers from the tactical station with the trigger.
	var ctl: XRController3D = _controllers.get("right", _controllers.get("left"))
	if ctl != null and XRServer.get_tracker(ctl.tracker) != null:
		var trig := XRUIPointer.trigger_pressed(ctl)
		var key := "tac_fire"
		if trig and not bool(_trig_prev.get(key, false)):
			_fire_phaser(ctl)
			_note_input("controllers")
		_trig_prev[key] = trig
	if _act_t > 100.0 and _enemies.is_empty():
		_complete_act()


func _spawn_raider() -> void:
	var ps: PackedScene = load(SHIP_DIR + "spaceship_3.glb") as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	var hp := _head_pos()
	var ang := randf() * TAU
	inst.position = hp + Vector3(cos(ang) * 7.0, randf_range(0, 2.5), sin(ang) * 7.0 - 2.0)
	inst.scale = Vector3.ONE * 0.7
	_tint_red(inst)
	get_tree().current_scene.add_child(inst)
	_enemies.append({"node": inst, "hp": 20.0})


func _tint_red(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.15, 0.12)
		m.emission_enabled = true
		m.emission = Color(0.8, 0.15, 0.1)
		m.emission_energy_multiplier = 0.7
		(mi as MeshInstance3D).material_override = m


func _fire_phaser(ctl: XRController3D) -> void:
	var from: Vector3 = ctl.global_position
	var dir := -ctl.global_transform.basis.z.normalized()
	# Hit the nearest raider roughly along the aim ray.
	var best = null
	var bd := 0.35  # angular tolerance factor
	for e in _enemies:
		var node: Node3D = e["node"]
		var to: Vector3 = node.global_position - from
		var along := to.dot(dir)
		if along < 1.0 or along > 14.0:
			continue
		var perp := (to - dir * along).length() / along
		if perp < bd:
			bd = perp
			best = e
	_make_beam(from, from + dir * 10.0, Color(0.4, 0.8, 1.0))
	ArtKit.game_sfx(self, "fire", randf_range(0.9, 1.2))
	Haptics.pulse(0.6, 0.08, "right")
	if best != null:
		var bn: Node3D = best["node"]
		best["hp"] = float(best["hp"]) - 10.0
		_make_beam(from, bn.global_position, Color(1.0, 0.6, 0.2))
		if float(best["hp"]) <= 0.0:
			_burst_at(bn.global_position)
			bn.queue_free()
			_enemies.erase(best)
			ArtKit.game_sfx(self, "boom")


func _make_beam(a: Vector3, b: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var d := b - a
	cm.top_radius = 0.015
	cm.bottom_radius = 0.015
	cm.height = d.length()
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.global_rotation = Vector3(PI * 0.5, 0, 0)
	# Orient along d.
	var y := d.normalized()
	var x := y.cross(Vector3.UP).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), mi.global_position)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.01, 1, 0.01), 0.18)
	tw.tween_callback(mi.queue_free)


# --- ACT 3: LAST STAND — engineering: route power at the couch ---
func _build_power_ui() -> void:
	var eng: Dictionary = _stations["engineering"]
	var root: Node3D = eng["root"]
	var y := 0.42
	for k in ["weapons", "shields", "engines"]:
		var row := Node3D.new()
		row.position = Vector3(0, y, 0.05)
		root.add_child(row)
		var lab := Label3D.new()
		lab.text = "%s %d" % [k.to_upper(), _power[k]]
		lab.font_size = 48
		lab.position = Vector3(-0.42, 0, 0)
		row.add_child(lab)
		for bi in range(3):
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.09, 0.09, 0.03)
			b.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.2, 0.5, 0.8) if bi == 1 else Color(0.5, 0.35, 0.15)
			b.material_override = mat
			b.position = Vector3(-0.05 + bi * 0.14, 0, 0)
			row.add_child(b)
			b.set_meta("power_key", k)
			b.set_meta("power_delta", [-10, 0, 10][bi])
		_power_nodes[k] = row
		y -= 0.16


func _act_laststand(delta: float) -> void:
	_act_t += delta
	_poll_power()
	_spawn_acc -= delta
	if _spawn_acc <= 0.0:
		_spawn_acc = maxf(0.8, 2.4 - _act_t * 0.012)
		_spawn_raider()
	for e in _enemies.duplicate():
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			_enemies.erase(e)
			continue
		var hp := _head_pos()
		var to: Vector3 = hp - node.position
		node.position += to.normalized() * (0.9 + (100 - _power["engines"]) * 0.004) * delta
		node.rotation.y = atan2(to.x, to.z)
		if to.length() < 1.4:
			_enemies.erase(e)
			node.queue_free()
			var raw: float = 16.0 * (1.0 - float(_power["shields"]) / 160.0)
			_damage(raw, "engineering")
	# Weapons power auto-fires at raiders.
	var wacc: float = float(get_meta("_wacc", 0.0)) + delta * (0.4 + float(_power["weapons"]) / 60.0)
	set_meta("_wacc", wacc)
	if wacc > 1.0:
		set_meta("_wacc", 0.0)
		_auto_turret()
	# Shield regen.
	_shield = minf(50.0, _shield + delta * (1.0 + _power["shields"] / 40.0))
	if _act_t > 120.0 and _enemies.is_empty():
		_complete_act()


func _poll_power() -> void:
	# Trigger-press a +/- pad on the engineering console while standing there.
	if _player_station() != "engineering":
		return
	for side in _controllers.keys():
		var ctl: XRController3D = _controllers[side]
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var trig := XRUIPointer.trigger_pressed(ctl)
		var key: String = "pow_" + side
		if trig and not bool(_trig_prev.get(key, false)):
			_try_power_press(ctl)
			_note_input("controllers")
		_trig_prev[key] = trig


func _try_power_press(ctl: XRController3D) -> void:
	var eng: Dictionary = _stations["engineering"]
	var root: Node3D = eng["root"]
	var tip: Vector3 = ctl.global_position + (-ctl.global_transform.basis.z * 0.12)
	var best: MeshInstance3D = null
	var bd := 0.12
	for k in _power_nodes.keys():
		for b in (_power_nodes[k] as Node3D).get_children():
			if b is MeshInstance3D and b.has_meta("power_key"):
				var d: float = (b as Node3D).global_position.distance_to(tip)
				if d < bd:
					bd = d
					best = b
	if best == null:
		return
	var k2 := str(best.get_meta("power_key"))
	var d2 := int(best.get_meta("power_delta"))
	_power[k2] = clampi(_power[k2] + d2, 0, 100)
	# Reb alance: keep the total at 100.
	var others := ["weapons", "shields", "engines"]
	others.erase(k2)
	var total: int = _power["weapons"] + _power["shields"] + _power["engines"]
	while total > 100:
		var ok := false
		for o in others:
			if _power[o] > 0:
				_power[o] -= 1
				total -= 1
				ok = true
				break
		if not ok:
			break
	while total < 100:
		_power[others[0]] += 1
		total += 1
	_refresh_power_labels()
	ArtKit.game_sfx(self, "power")
	Haptics.tick("both")


func _refresh_power_labels() -> void:
	for k in _power_nodes.keys():
		var row: Node3D = _power_nodes[k]
		for c in row.get_children():
			if c is Label3D:
				(c as Label3D).text = "%s %d" % [k.to_upper(), _power[k]]


func _auto_turret() -> void:
	if _enemies.is_empty():
		return
	var hp := _head_pos()
	var best = null
	var bd := 1e9
	for e in _enemies:
		var d: float = (e["node"] as Node3D).global_position.distance_to(hp)
		if d < bd:
			bd = d
			best = e
	if best == null or bd > 12.0:
		return
	var bn: Node3D = best["node"]
	_make_beam(hp + Vector3(0, 0.3, 0), bn.global_position, Color(1.0, 0.5, 0.15))
	best["hp"] = float(best["hp"]) - (6.0 + _power["weapons"] * 0.08)
	ArtKit.game_sfx(self, "fire", 1.4)
	if float(best["hp"]) <= 0.0:
		_burst_at(bn.global_position)
		bn.queue_free()
		_enemies.erase(best)
		ArtKit.game_sfx(self, "boom", 0.9)


func _update_shots(_delta: float) -> void:
	pass  # beams are tween-driven; kept for symmetry/perf clarity


func _burst_at(pos: Vector3) -> void:
	_sparks.global_position = pos
	_sparks.restart()
	_sparks.emitting = true


# ---------------------------------------------------------------- damage ---

func _damage(raw: float, station_name: String) -> void:
	if _game_over or _act_state != "play":
		return
	var dmg := raw
	if _shield > 0.0 and raw > 0.0:
		var absorbed: float = minf(_shield, dmg * 0.6)
		_shield -= absorbed
		dmg -= absorbed
		ArtKit.game_sfx(self, "shield")
	_hull -= dmg
	_flash_t = 0.6
	Haptics.impact(clampf(dmg / 14.0, 0.3, 1.0), "both")
	ArtKit.game_sfx(self, "hit", 0.8)
	var st: Dictionary = _stations.get(station_name, {})
	if st.has("pos"):
		_sparks.global_position = (st["pos"] as Vector3) + Vector3(0, 0.15, 0)
		_sparks.restart()
		_sparks.emitting = true
		# v0.11.0 VFX: console breach — spark fountain + smoke + strobe.
		VFX.console_breach(self, (st["pos"] as Vector3) + Vector3(0, 0.1, 0))
		# v0.11.0 ambient (e): damaged consoles drip sparks after the hit.
		_drip_sparks_from_consoles()
	if _hull <= 0.0:
		_hull = 0.0
		_defeat("The ship was torn apart.")


func _complete_act() -> void:
	_act_state = "done"
	ArtKit.game_sfx(self, "win")
	ArtKit.stinger(self, "success")
	if _act >= 2:
		_victory()
	else:
		_announce_text("ACT COMPLETE", 2.0)
		_start_act(_act + 1)


func _victory() -> void:
	_game_over = true
	_hull = maxf(_hull, 1.0)
	_announce_text("MISSION COMPLETE — HULL %d%%" % int(_hull), 8.0)
	ArtKit.stinger(self, "success")
	Haptics.play_sequence("fanfare", "both")
	_telemetry("bridge_end", {"result": "victory", "hull": int(_hull)})


func _defeat(reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	_announce_text("MISSION FAILED — " + reason, 8.0)
	ArtKit.game_sfx(self, "lose")
	ArtKit.stinger(self, "fail")
	_telemetry("bridge_end", {"result": "defeat", "act": _act, "reason": reason})


func _update_hud() -> void:
	var hp := _head_pos()
	_hud.position = hp + Vector3(0, 0.55, -0.9)
	_announce.position = hp + Vector3(0, 1.0, -1.6)
	var station := _player_station()
	_hud.text = "ACT %d/3 %s   HULL %d%%   SHIELD %d%%\n[%s]" % [
		_act + 1, ACTS[_act], int(_hull), int(_shield),
		station.to_upper() if station != "" else "— move to a station —"]
	if _act == 1 and is_instance_valid(_escort_target):
		_hud.text += "\nFREIGHTER %d%%" % int(_escort_hp)



func _announce_text(t: String, dur: float) -> void:
	_announce.text = t
	_announce_t = dur


func _note_input(method: String) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.note_input_method(method)


func _telemetry(ev: String, fields: Dictionary) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event(ev, fields)
