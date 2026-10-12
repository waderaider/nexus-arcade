## PhantomThief.gd - NEXUS ARCADE v0.11.0: PHANTOM THIEF.
## A stealth heist in YOUR house. Guards (animated knights) patrol
## waypoints derived from the real room layout; laser grids span real
## doorways; crouching behind your real couch is real cover (depth
## occlusion hides you; the game also models it). Steal 3 artifacts and
## exfiltrate. Detection = guards converge; break line-of-sight behind
## real furniture to cool off.
##
## Guards: Quaternius knightcharacter (CC0 1.0), animated. Lasers and
## artifacts are procedural (line meshes / emissive crystals).
extends Node3D
class_name PhantomThiefGame

const KNIGHT := "res://assets/models/phantom_thief/knight.glb"
const GUARD_COUNT := 5
const VIEW_DIST := 4.2
const VIEW_ANGLE := 0.62   # radians half-angle (~35 deg)
const CROUCH_Y := 0.95
const LASER_TRIP_DIST := 0.16

var controller_config := {
	"uses_controllers": true,
	"skin": "none",
	"buttons": {
		"trigger": "Grab artifact",
		"grip": "—",
		"thumbstick": "—",
		"menu": "Pause",
	},
}

var _origin: Node3D
var _controllers := {}
var _guards: Array = []     # {node, anim, waypoints, wi, state, alert, detect, scan_t, cone}
var _lasers: Array = []      # {node, plane_pos, normal, tripped_cd}
var _artifacts: Array = []   # {node, taken}
var _exit_marker: Node3D
var _exit_pos := Vector3.ZERO
var _heat := 0.0
var _alarm := false
var _alarm_t := 0.0
var _stolen := 0
var _game_over := false
var _hud: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _trig_prev := {}
var _furniture: Array = []
var _walls: Array = []
var _mission_t := 0.0
# v0.11.0 (Animator) ambient elements:
var _laser_mats: Array = []      # (b) laser-grid materials for hum shimmer
var _guard_phase := {}          # (a) per-guard idle phase (node -> float)


func _ready() -> void:
	_origin = _find_origin()
	_find_controllers()
	ArtKit.register_game_sfx(self, {
		"grab": "coin", "alarm": "buzzer", "laser": "zap", "win": "fanfare",
		"lose": "fail", "spot": "notify", "unlock": "unlock", "step": "thud",
		"cool": "heal",
	})
	ArtKit.set_intensity(self, 1)
	if RoomKit.is_available():
		await RoomKit.refresh()
	_cache_room()
	_build_hud()
	_spawn_guards()
	_build_lasers()
	_place_artifacts()
	_place_exit()
	_announce_text("PHANTOM THIEF\nThe Verano Collection moves tonight — through your house.\nYour couch is cover. Your hallway is the plan.", 4.5)
	JuiceFX.title_card("PHANTOM THIEF", "Three artifacts. Your house. Leave no trace.", Color(0.6, 0.3, 0.9))
	_telemetry("thief_start", {"guards": _guards.size()})


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


func _cache_room() -> void:
	_furniture = RoomKit.get_furniture()
	_walls = RoomKit.get_walls()


func _room_center() -> Vector3:
	var b := RoomKit.room_bounds()
	return Vector3(b.position.x + b.size.x * 0.5, 0, b.position.y + b.size.y * 0.5)


func _waypoints() -> Array:
	# Patrol routes from real furniture + room corners: every player's heist
	# is architecturally unique.
	var pts: Array = []
	for f in _furniture:
		var p: Vector3 = f["position"]
		pts.append(Vector3(p.x, 0, p.z))
	var b := RoomKit.room_bounds()
	var corners := [
		Vector3(b.position.x + 0.4, 0, b.position.y + 0.4),
		Vector3(b.end.x - 0.4, 0, b.position.y + 0.4),
		Vector3(b.position.x + 0.4, 0, b.end.y - 0.4),
		Vector3(b.end.x - 0.4, 0, b.end.y - 0.4),
	]
	pts.append_array(corners)
	if pts.is_empty():
		var c := _room_center()
		pts = [c + Vector3(1, 0, 1), c + Vector3(-1, 0, 1), c + Vector3(0, 0, -1.2)]
	return pts


func _spawn_guards() -> void:
	var ps: PackedScene = load(KNIGHT) as PackedScene
	if ps == null:
		return
	var pts := _waypoints()
	for i in range(GUARD_COUNT):
		var inst := ps.instantiate() as Node3D
		get_tree().current_scene.add_child(inst)
		inst.scale = Vector3.ONE * 1.05
		var start: Vector3 = pts[(i * 2) % pts.size()]
		inst.position = start
		var ap := _find_anim(inst)
		_play_named(ap, "Walking")
		# Vision cone visual (translucent).
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = tan(VIEW_ANGLE) * VIEW_DIST
		cm.height = VIEW_DIST
		cone.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.albedo_color = Color(1.0, 0.85, 0.2, 0.10)
		cone.material_override = cmat
		# Lay the cone forward: cylinder Y-axis -> guard forward (-Z local).
		cone.rotation.x = -PI * 0.5
		cone.position = Vector3(0, 1.45, -VIEW_DIST * 0.5)
		inst.add_child(cone)
		# Guard route: strided slice of the waypoint ring.
		var route: Array = []
		for k in range(4):
			route.append(pts[(i + k * 2) % pts.size()])
		# v0.11.0 ambient (e): cape sway — best-effort node lookup.
		var cape: Node3D = null
		for cn in inst.find_children("*", "MeshInstance3D", true, false):
			if "cape" in (cn as Node).name.to_lower():
				cape = cn as Node3D
				break
		_guards.append({"node": inst, "anim": ap, "route": route, "ri": 0,
			"state": "patrol", "alert": 0.0, "detect": 0.0, "scan_t": 0.0,
			"cone": cone, "speed": 0.55, "cape": cape})


func _find_anim(node: Node) -> AnimationPlayer:
	var found := node.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


func _play_named(ap: AnimationPlayer, want: String) -> void:
	if ap == null:
		return
	for a in ap.get_animation_list():
		if str(a).to_lower().contains(want.to_lower()):
			if ap.current_animation != a:
				ap.play(a)
			return


func _build_lasers() -> void:
	var doors := RoomKit.get_anchors("door")
	var spots: Array = []
	for d in doors:
		var p: Vector3 = d["position"]
		spots.append({"pos": Vector3(p.x, 1.1, p.z), "yaw": float(d.get("yaw", 0.0)), "w": minf(float((d["size"] as Vector3).x), 1.4)})
	if spots.size() < 2:
		# Fallback: two doorway-style grids on the room edge.
		var b := RoomKit.room_bounds()
		spots.append({"pos": Vector3(b.position.x + b.size.x * 0.5, 1.1, b.position.y + 0.25), "yaw": 0.0, "w": 1.1})
		spots.append({"pos": Vector3(b.position.x + b.size.x * 0.5, 1.1, b.end.y - 0.25), "yaw": 0.0, "w": 1.1})
	for s in spots:
		_build_laser_grid(s["pos"], s["yaw"], s["w"])


func _build_laser_grid(pos: Vector3, yaw: float, w: float) -> void:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.1)
	mat.emission_energy_multiplier = 4.0
	# v0.11.0 ambient (b): hum shimmer on the laser grid.
	_laser_mats.append({"mat": mat, "phase": randf() * TAU})
	for i in range(3):
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.015, 0.015)
		beam.mesh = bm
		beam.material_override = mat
		beam.position = Vector3(0, -0.5 + i * 0.5, 0)
		root.add_child(beam)
	# Emitter posts.
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, 1.3, 0.06)
		post.mesh = pm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.15, 0.15, 0.18)
		pmat.metallic = 0.6
		post.material_override = pmat
		post.position = Vector3(sx * w * 0.5, -0.45, 0)
		root.add_child(post)
	_lasers.append({"node": root, "cd": 0.0})


func _place_artifacts() -> void:
	var pedestals: Array = []
	for s in RoomKit.get_storage():
		var p: Vector3 = s["position"]
		var sz: Vector3 = s["size"]
		pedestals.append(Vector3(p.x, p.y + sz.y * 0.5 + 0.12, p.z))
	if pedestals.size() < 3:
		var b := RoomKit.room_bounds()
		var c := _room_center()
		pedestals.append_array([
			Vector3(b.position.x + 0.5, 1.1, b.position.y + 0.5),
			Vector3(b.end.x - 0.5, 1.1, b.end.y - 0.5),
			Vector3(c.x, 1.1, c.z - 1.0),
		])
	var colors := [Color(1.0, 0.3, 0.9), Color(0.3, 1.0, 0.8), Color(1.0, 0.8, 0.2)]
	for i in range(3):
		var a := MeshInstance3D.new()
		var om := PrismMesh.new()
		om.size = Vector3(0.14, 0.22, 0.14)
		a.mesh = om
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = colors[i]
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 2.5
		a.material_override = mat
		get_tree().current_scene.add_child(a)
		a.position = pedestals[i % pedestals.size()]
		_artifacts.append({"node": a, "taken": false, "base_y": a.position.y, "ph": randf() * TAU})
		# v0.11.0 ambient (c): dust motes hanging in the case light.
		AmbientLife.dust(a, 12, Vector3(0.35, 0.5, 0.35))


func _place_exit() -> void:
	_exit_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.35
	tm.outer_radius = 0.45
	_exit_marker.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.5
	_exit_marker.material_override = mat
	get_tree().current_scene.add_child(_exit_marker)
	var doors := RoomKit.get_anchors("door")
	if not doors.is_empty():
		var p: Vector3 = (doors[0] as Dictionary)["position"]
		_exit_pos = Vector3(p.x, 0.03, p.z)
	else:
		var b := RoomKit.room_bounds()
		_exit_pos = Vector3(b.position.x + b.size.x * 0.5, 0.03, b.end.y - 0.4)
	_exit_marker.position = _exit_pos
	_exit_marker.visible = false
	var l := Label3D.new()
	l.text = "EXFIL"
	l.font_size = 64
	l.modulate = Color(0.4, 1.0, 0.5)
	l.position = _exit_pos + Vector3(0, 0.5, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	get_tree().current_scene.add_child(l)
	l.visible = false
	_exit_marker.set_meta("label", l)


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.font_size = 52
	_hud.modulate = Color(0.9, 0.95, 1.0)
	_hud.outline_size = 10
	add_child(_hud)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.font_size = 92
	_announce.modulate = Color(1.0, 0.85, 0.3)
	_announce.outline_size = 14
	add_child(_announce)


# ---------------------------------------------------------------- loop ---

## v0.11.0 (Animator): guard idle life, laser shimmer, artifact idle.
func _update_thief_ambient(delta: float, t: float) -> void:
	# (a) Guard idle life: at waypoints they pause-scan — head leads the
	# turn, sword taps. (The FBX walk anim runs; this adds the *decision*.)
	for g in _guards:
		var node: Node3D = g["node"]
		if not is_instance_valid(node):
			continue
		var key := node.get_instance_id()
		if not _guard_phase.has(key):
			_guard_phase[key] = randf() * TAU
		var ph: float = _guard_phase[key]
		if str(g["state"]) == "patrol":
			# Sword tap: subtle bob synced to the scan pause.
			var scan: float = float(g["scan_t"])
			node.position.y = absf(sin(scan * 2.4 + ph)) * 0.012
			# Look-around at waypoints: yaw wander, head-lead feel via
			# rotation lag (body turns slower than the scan).
			node.rotation.y += sin(scan * 0.7 + ph) * 0.12 * delta
		# (e) Cape sway: lags the guard's motion (secondary motion).
		var cape_n: Node3D = g.get("cape")
		if cape_n != null and is_instance_valid(cape_n):
			cape_n.rotation.x = 0.12 + 0.08 * sin(t * 2.6 + ph)
	# (b) Laser-grid hum shimmer: subtle emissive flicker, phase-offset.
	for lm in _laser_mats:
		AnimFluidity.emissive_flicker(lm["mat"], t, float(lm["phase"]), 4.0, 0.5, 11.0)
	# (d) Artifacts idle: slow rotation + inner glow breathing.
	for a in _artifacts:
		if bool(a["taken"]):
			continue
		var an: MeshInstance3D = a["node"]
		if not is_instance_valid(an):
			continue
		an.rotation.y += 0.5 * delta
		var am := an.material_override as StandardMaterial3D
		if am != null:
			am.emission_energy_multiplier = 2.5 + 0.7 * sin(t * 1.8 + float(a["ph"]))


func _process(delta: float) -> void:
	if _game_over:
		return
	_update_thief_ambient(delta, Time.get_ticks_msec() / 1000.0)
	_mission_t += delta
	_update_guards(delta)
	_update_lasers(delta)
	_update_artifacts(delta)
	_poll_grab()
	_update_heat(delta)
	if _announce_t > 0.0:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce.text = ""
	_update_hud()
	_check_exfil()


func _update_guards(delta: float) -> void:
	var hp := _head_pos()
	var crouched := hp.y < CROUCH_Y
	for g in _guards:
		var node: Node3D = g["node"]
		if not is_instance_valid(node):
			continue
		var sees := _guard_sees(g, hp, crouched)
		if sees:
			g["detect"] = minf(1.0, float(g["detect"]) + delta * (0.9 if not crouched else 0.45))
		else:
			g["detect"] = maxf(0.0, float(g["detect"]) - delta * 0.5)
		if float(g["detect"]) >= 1.0 and g["state"] != "chase":
			g["state"] = "chase"
			_raise_alarm("SPOTTED!")
			_play_named(g["anim"], "Run")
		match str(g["state"]):
			"patrol":
				_play_named(g["anim"], "Walking")
				_patrol_move(g, delta, 0.55)
				# Scan pause at each waypoint.
				g["scan_t"] = float(g["scan_t"]) + delta
			"chase":
				_play_named(g["anim"], "Run")
				_chase_move(g, hp, delta, 1.35)
				if node.position.distance_to(Vector3(hp.x, 0, hp.z)) < 0.7:
					_add_heat(20.0 * delta)
					if _heat >= 100.0:
						_defeat("Caught by the guard.")
						return
				if float(g["detect"]) <= 0.05 and not _alarm:
					g["state"] = "patrol"
					_play_named(g["anim"], "Walking")
		# Cone color shifts with suspicion.
		var cone: MeshInstance3D = g["cone"]
		var cm := cone.material_override as StandardMaterial3D
		if cm != null:
			var d: float = g["detect"]
			cm.albedo_color = Color(1.0, 0.85 - d * 0.7, 0.2, 0.10 + d * 0.14)


func _guard_sees(g: Dictionary, hp: Vector3, crouched: bool) -> bool:
	var node: Node3D = g["node"]
	var gp: Vector3 = node.position + Vector3(0, 1.5, 0)
	var to: Vector3 = hp - gp
	var dist := to.length()
	var max_d := VIEW_DIST * (0.55 if crouched else 1.0)
	if dist > max_d:
		return false
	var fwd := -node.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var flat := Vector3(to.x, 0, to.z).normalized()
	if fwd.dot(flat) < cos(VIEW_ANGLE):
		return false
	# Real-furniture cover: couch (or any tall furniture) between guard and
	# player blocks sight — crouching behind the couch is real cover.
	if _segment_blocked(gp, hp):
		return false
	return true


func _segment_blocked(a: Vector3, b: Vector3) -> bool:
	for f in _furniture:
		var p: Vector3 = f["position"]
		var s: Vector3 = f["size"]
		if s.y < 0.55:
			continue  # low furniture doesn't block sight
		var box := AABB(p - s * 0.5, s)
		if _seg_aabb(a, b, box):
			return true
	return false


func _seg_aabb(a: Vector3, b: Vector3, box: AABB) -> bool:
	# Slab test, XZ + Y.
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in [0, 1, 2]:
		var aa: float = a[axis]
		var dd: float = d[axis]
		var mn: float = box.position[axis]
		var mx: float = box.position[axis] + box.size[axis]
		if absf(dd) < 0.00001:
			if aa < mn or aa > mx:
				return false
		else:
			var t1 := (mn - aa) / dd
			var t2 := (mx - aa) / dd
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
			if tmin > tmax:
				return false
	return true


func _patrol_move(g: Dictionary, delta: float, speed: float) -> void:
	var node: Node3D = g["node"]
	var route: Array = g["route"]
	if route.is_empty():
		return
	var tgt: Vector3 = route[int(g["ri"]) % route.size()]
	var to := tgt - node.position
	to.y = 0
	if to.length() < 0.25:
		g["ri"] = (int(g["ri"]) + 1) % route.size()
		return
	node.position += to.normalized() * speed * delta
	node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.z), 0.12)


func _chase_move(g: Dictionary, hp: Vector3, delta: float, speed: float) -> void:
	var node: Node3D = g["node"]
	var tgt := Vector3(hp.x, 0, hp.z)
	var to := tgt - node.position
	to.y = 0
	if to.length() > 0.05:
		node.position += to.normalized() * speed * delta
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-to.x, -to.z), 0.2)


func _raise_alarm(why: String) -> void:
	if not _alarm:
		_alarm = true
		_alarm_t = 18.0
		_announce_text("ALARM — " + why, 2.5)
		# v0.11.0 VFX: twin expanding alarm rings + ping sparks.
		VFX.alarm_sweep(self, _head_pos(), Color(1.0, 0.2, 0.15))
		ArtKit.game_sfx(self, "alarm")
		Haptics.heartbeat(3, "both")
		_telemetry("thief_alarm", {"why": why})
		# Every guard converges.
		for g in _guards:
			if str(g["state"]) == "patrol":
				g["state"] = "chase"


func _update_heat(delta: float) -> void:
	if _alarm:
		_alarm_t -= delta
		_add_heat(1.6 * delta)
		if _alarm_t <= 0.0:
			_alarm = false
			_announce_text("...they lost you.", 2.0)
			ArtKit.game_sfx(self, "cool")
			for g in _guards:
				g["state"] = "patrol"
				g["detect"] = 0.0
	else:
		_add_heat(-4.0 * delta)


func _add_heat(d: float) -> void:
	_heat = clampf(_heat + d, 0.0, 100.0)
	if _heat >= 100.0 and not _game_over:
		_defeat("Heat maxed out — the house is locked down.")


func _update_lasers(delta: float) -> void:
	var hp := _head_pos()
	for lz in _lasers:
		lz["cd"] = maxf(0.0, float(lz["cd"]) - delta)
		if float(lz["cd"]) > 0.0:
			continue
		var root: Node3D = lz["node"]
		# Distance from the head to the laser plane (local Z == 0 plane).
		var local: Vector3 = root.to_local(hp)
		if absf(local.z) < LASER_TRIP_DIST and absf(local.x) < 0.75 and local.y > -1.1 and local.y < 0.4:
			lz["cd"] = 3.0
			_add_heat(22.0)
			_raise_alarm("LASER TRIPPED")
			ArtKit.game_sfx(self, "laser")
			Haptics.deny("both")
			_telemetry("thief_laser", {})


func _update_artifacts(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for a in _artifacts:
		if bool(a["taken"]):
			continue
		var node: MeshInstance3D = a["node"]
		node.rotation.y = t * 1.4
		node.position.y = float(a["base_y"]) + sin(t * 2.0 + float(a["ph"])) * 0.03


func _poll_grab() -> void:
	var hp := _head_pos()
	for a in _artifacts:
		if bool(a["taken"]):
			continue
		var node: MeshInstance3D = a["node"]
		if node.global_position.distance_to(hp) > 0.5:
			continue
		# Pinch or trigger grabs it.
		if _grab_pressed():
			a["taken"] = true
			_stolen += 1
			node.queue_free()
			ArtKit.game_sfx(self, "grab")
			ArtKit.game_sfx(self, "unlock")
			Haptics.confirm("both")
			_announce_text("ARTIFACT %d/3 SECURED" % _stolen, 2.2)
			_telemetry("thief_steal", {"count": _stolen})
			if _stolen >= 3:
				_exit_marker.visible = true
				(_exit_marker.get_meta("label") as Label3D).visible = true
				_announce_text("GET TO THE EXFIL RING", 3.5)


func _grab_pressed() -> bool:
	for side in _controllers.keys():
		var ctl: XRController3D = _controllers[side]
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		if XRUIPointer.trigger_pressed(ctl):
			_note_input("controllers")
			return true
	if _origin != null:
		for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
			var hr: Dictionary = XRUIPointer.hand_ray(side, _origin)
			if bool(hr["active"]) and bool(hr["pinch"]):
				_note_input("hands")
				return true
	return false


func _check_exfil() -> void:
	if _stolen < 3 or _game_over:
		return
	var hp := _head_pos()
	if Vector2(hp.x - _exit_pos.x, hp.z - _exit_pos.z).length() < 0.55:
		_victory()


func _victory() -> void:
	_game_over = true
	var bonus := int(maxf(0.0, 600.0 - _mission_t) + (100.0 - _heat) * 5.0)
	_announce_text("HEIST CLEAN — SCORE %d" % bonus, 8.0)
	ArtKit.game_sfx(self, "win")
	ArtKit.stinger(self, "success")
	Haptics.play_sequence("fanfare", "both")
	_telemetry("thief_end", {"result": "victory", "time_s": int(_mission_t), "heat": int(_heat), "score": bonus})


func _defeat(reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	_announce_text("BUSTED — " + reason, 8.0)
	ArtKit.game_sfx(self, "lose")
	ArtKit.stinger(self, "fail")
	_telemetry("thief_end", {"result": "defeat", "reason": reason, "stolen": _stolen})


func _update_hud() -> void:
	var hp := _head_pos()
	_hud.position = hp + Vector3(0, 0.42, -0.8)
	_announce.position = hp + Vector3(0, 0.85, -1.4)
	var heat_bar := ""
	var n := int(_heat / 10.0)
	for i in range(10):
		heat_bar += "█" if i < n else "░"
	_hud.text = "ARTIFACTS %d/3   HEAT\n%s" % [_stolen, heat_bar]


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
