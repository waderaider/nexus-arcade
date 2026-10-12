## WarTableGame.gd - NEXUS ARCADE v0.11.0: WAR TABLE.
## Coffee-table RTS: a holographic battlefield anchors to the player's real
## table (RoomKit cuboid; graceful floating-table fallback). Pinch-drag (or
## trigger-drag) squads, finger-drawn attack paths, grip-press raises
## terrain hills. 3-minute skirmishes vs an escalating AI commander, fog of
## war lifted by scout drones, and units knocked off the table edge tumble
## to the real floor. Original design; no licensed assets.
##
## Units: CraftPix medieval-people (royalty-free) as tiny tabletop armies.
## Props: Quaternius fantasypropsmegakit (CC0 1.0).
extends Node3D
class_name WarTableGame

const MATCH_TIME := 180.0
const SCOUT_R := 0.42
const SELECT_R := 0.15
const COMBAT_TICK := 0.22
const AI_TICK := 3.0
const MAX_HILLS := 3
const HILL_COOLDOWN := 12.0
const HILL_R := 0.13

const CLASSES := {
	"infantry": {"hp": 34.0, "dmg": 7.0, "range": 0.095, "speed": 0.150},
	"archer": {"hp": 20.0, "dmg": 5.0, "range": 0.300, "speed": 0.115},
	"commander": {"hp": 95.0, "dmg": 10.0, "range": 0.130, "speed": 0.100},
}
const MODELS := {
	"player": {"infantry": "peasant_1.glb", "archer": "peasant_3.glb", "commander": "king.glb"},
	"enemy": {"infantry": "peasant_2.glb", "archer": "peasant_4.glb", "commander": "queen.glb"},
}
const UNIT_DIR := "res://assets/models/war_table/units/"
const PROP_DIR := "res://assets/models/war_table/props/"

## Legend for the auto-wired controls intro (controller_skins).
var controller_config := {
	"uses_controllers": true,
	"skin": "none",
	"buttons": {
		"trigger": "Pinch/drag: select + order troops",
		"grip": "Fist-press: raise terrain hill",
		"thumbstick": "—",
		"menu": "Pause",
	},
}

var _field: Node3D            # battlefield root, sits on the table top
var _field_w := 1.4
var _field_d := 0.9
var _units: Array = []        # Array[Dictionary]
var _hills: Array = []        # Array[Dictionary] {pos: Vector2, node}
var _hill_cd := 0.0
var _drones: Array = []       # scout drones (Node3D)
var _selected: Array = []     # selected unit dicts
var _sel_ring: MeshInstance3D
var _path_line: MeshInstance3D
var _path_mesh: ImmediateMesh
var _dragging := false
var _drag_side := ""          # "hand_left" | "hand_right" | "ctl_left" | "ctl_right"
var _drag_path: Array = []    # Array[Vector2]
var _drag_point := Vector2.ZERO
var _grip_prev := {}
var _trig_prev := {}
var _pinch_prev := {"left": false, "right": false}
var _origin: Node3D
var _controllers := {}
var _time_left := MATCH_TIME
var _match_over := false
var _combat_acc := 0.0
var _ai_acc := 0.0
var _reinf_at := [60.0, 120.0]
var _ember_field: Node3D = null   # v0.11.0 ambient (a): follows hot zones
var _hot_spot := Vector3.ZERO      # latest combat centroid (field-local)
var _pennants: Array = []          # v0.11.0 ambient (b): {node, phase}
var _hud_timer: Label3D
var _hud_score: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _telemetry_done := false


func _ready() -> void:
	_origin = _find_origin()
	_find_controllers()
	ArtKit.register_game_sfx(self, {
		"select": "ui_click", "order": "ui_hover", "hit": "hit",
		"die": "thud", "horn": "countdown", "win": "fanfare",
		"lose": "fail", "boom": "explosion", "hill": "powerup",
	})
	ArtKit.set_intensity(self, 1)
	_build_selection_visuals()
	_build_hud()
	if RoomKit.is_available():
		await RoomKit.refresh()
	_setup_battlefield()
	_spawn_armies()
	_spawn_drones()
	_build_ambient()
	_announce_text("WAR TABLE\nTheir last campaign, still being fought.\nGive them the ending history denied them.", 4.0)
	JuiceFX.title_card("WAR TABLE", "Their last campaign. Your table. Three minutes.", Color(0.2, 0.6, 1.0))
	_telemetry("war_table_start", {})


# ------------------------------------------------------------- setup ----

func _find_origin() -> Node3D:
	var f := get_tree().root.find_children("*", "XROrigin3D", true, false)
	if not f.is_empty():
		return f[0] as Node3D
	return null


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
	return Vector3(0, 1.6, 0.6)


func _setup_battlefield() -> void:
	_field = Node3D.new()
	_field.name = "Battlefield"
	var placed := false
	if RoomKit.has_room_data():
		var tables := RoomKit.get_tables()
		if not tables.is_empty():
			var best: Dictionary = tables[0]
			var best_a := 0.0
			for t in tables:
				var s: Vector3 = t["size"]
				var a: float = s.x * s.z
				if a > best_a:
					best_a = a
					best = t
			var size: Vector3 = best["size"]
			_field_w = clampf(size.x, 0.6, 2.2)
			_field_d = clampf(size.z, 0.6, 2.2)
			var top: Vector3 = RoomKit.cuboid_top(best)
			get_tree().current_scene.add_child(_field)
			_field.global_position = top + Vector3(0, 0.015, 0)
			placed = true
	if not placed:
		# Floating war-table fallback: a holo slab 0.85 m in front of the
		# player at table height, yaw-aligned to the head.
		var hp: Vector3 = _head_pos()
		var yaw := 0.0
		if _origin != null:
			var c := _origin.get_node_or_null("XRCamera3D") as Camera3D
			if c != null:
				var cf := -c.global_transform.basis.z
				cf.y = 0
				if cf.length() > 0.05:
					yaw = atan2(-cf.x, -cf.z)
		get_tree().current_scene.add_child(_field)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		_field.global_position = Vector3(hp.x, 0.86, hp.z) + fwd * 0.85
		_field.global_rotation.y = yaw
		_build_fallback_slab()
	# Hologram terrain plane.
	var plane := PlaneMesh.new()
	plane.size = Vector2(_field_w, _field_d)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.05, 0.35, 0.55, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.7, 1.0)
	mat.emission_energy_multiplier = 0.7
	mi.material_override = mat
	mi.position = Vector3(0, 0.002, 0)
	_field.add_child(mi)
	# Grid lines (cheap: one LineMesh via ImmediateMesh).
	_draw_grid()
	# Fog-of-war shroud over the enemy half.
	var fog := MeshInstance3D.new()
	var fplane := PlaneMesh.new()
	fplane.size = Vector2(_field_w * 0.52, _field_d)
	fog.mesh = fplane
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(0.02, 0.02, 0.06, 0.72)
	fog.material_override = fmat
	fog.position = Vector3(-_field_w * 0.24, 0.02, 0)
	fog.name = "FogShroud"
	_field.add_child(fog)
	# Battlefield dressing: banners + crates at the corners.
	_place_props()


func _build_fallback_slab() -> void:
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_field_w + 0.1, 0.04, _field_d + 0.1)
	slab.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.16, 0.24)
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.25, 0.4)
	mat.emission_energy_multiplier = 0.5
	slab.material_override = mat
	slab.position = Vector3(0, -0.025, 0)
	_field.add_child(slab)


func _draw_grid() -> void:
	var im := ImmediateMesh.new()
	var mm := MeshInstance3D.new()
	mm.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var nx := 15
	var nz := 10
	for i in range(nx + 1):
		var x := -_field_w * 0.5 + _field_w * float(i) / float(nx)
		im.surface_add_vertex(Vector3(x, 0.004, -_field_d * 0.5))
		im.surface_add_vertex(Vector3(x, 0.004, _field_d * 0.5))
	for j in range(nz + 1):
		var z := -_field_d * 0.5 + _field_d * float(j) / float(nz)
		im.surface_add_vertex(Vector3(-_field_w * 0.5, 0.004, z))
		im.surface_add_vertex(Vector3(_field_w * 0.5, 0.004, z))
	im.surface_end()
	_field.add_child(mm)


func _place_props() -> void:
	var spots := [
		Vector2(-_field_w * 0.46, -_field_d * 0.42), Vector2(_field_w * 0.46, -_field_d * 0.42),
		Vector2(-_field_w * 0.46, _field_d * 0.42), Vector2(_field_w * 0.46, _field_d * 0.42),
	]
	var files := ["Banner_1.gltf", "Banner_2.gltf", "Barrel.gltf", "Crate_Wooden.gltf"]
	for i in range(spots.size()):
		var ps: PackedScene = load(PROP_DIR + files[i % files.size()]) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		_field.add_child(inst)
		inst.position = Vector3(spots[i].x, 0.0, spots[i].y)
		inst.scale = Vector3.ONE * 0.12
		if i >= 2:
			inst.rotation.y = PI


func _spawn_drones() -> void:
	for i in range(2):
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.02
		sm.height = 0.04
		d.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.4, 1.0, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 1.0, 0.9)
		mat.emission_energy_multiplier = 3.0
		d.material_override = mat
		_field.add_child(d)
		# v0.11.0 ambient (c): scout-drone light cone sweeping the fog.
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.09
		cm.height = 0.22
		cone.mesh = cm
		var cmat := GraphicsPolish.glow(Color(0.5, 1.0, 0.9), 0.7)
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.albedo_color.a = 0.35
		cone.material_override = cmat
		cone.position = Vector3(0, -0.12, 0)
		d.add_child(cone)
		_drones.append({"node": d, "cone": cone, "phase": float(i) * PI})


## v0.11.0 (Animator): 5 cheap ambient elements.
## (a) ember motes over the hot zone · (d) dust in the projector beams.
## (b) commander pennants and (c) drone light cones are added at spawn.
func _build_ambient() -> void:
	_hot_spot = Vector3.ZERO
	_ember_field = AmbientLife.embers(_field, 20, Vector3(0.5, 0.35, 0.4),
		Color(1.0, 0.45, 0.1), Color(1.0, 0.8, 0.35))
	_ember_field.position = _hot_spot + Vector3(0, 0.05, 0)
	# Projector beams: dust hanging in the light above the table.
	var dust := AmbientLife.dust(_field, 24, Vector3(0.8, 0.8, 0.6))
	dust.position = Vector3(0, 0.55, 0)


func _build_selection_visuals() -> void:
	_sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.06
	_sel_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.5
	_sel_ring.material_override = mat
	_sel_ring.visible = false
	add_child(_sel_ring)
	_path_mesh = ImmediateMesh.new()
	_path_line = MeshInstance3D.new()
	_path_line.mesh = _path_mesh
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(1.0, 0.9, 0.3)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.85, 0.2)
	pmat.emission_energy_multiplier = 2.0
	_path_line.material_override = pmat
	_path_line.visible = false
	add_child(_path_line)


func _build_hud() -> void:
	_hud_timer = _make_label(Vector3(0, 0.55, 0), 64, Color(1, 1, 1))
	_hud_score = _make_label(Vector3(0, 0.44, 0), 48, Color(0.7, 0.95, 1.0))
	_announce = _make_label(Vector3(0, 0.72, 0), 96, Color(1.0, 0.9, 0.3))


func _make_label(offset: Vector3, px: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = px
	l.modulate = color
	l.outline_size = 12
	l.position = offset
	add_child(l)
	return l


# ---------------------------------------------------------------- units ---

func _spawn_armies() -> void:
	var comp := [
		["infantry", 4], ["archer", 3], ["commander", 1],
	]
	for side in ["player", "enemy"]:
		var x0 := _field_w * 0.32 if side == "player" else -_field_w * 0.32
		for entry in comp:
			var cls: String = entry[0]
			for k in range(int(entry[1])):
				var lx := x0 + randf_range(-0.09, 0.09)
				var lz := randf_range(-_field_d * 0.38, _field_d * 0.38)
				_spawn_unit(side, cls, Vector2(lx, lz))
	# v0.11.0 VFX: army materializes — holo scan-beam + shockwave + sparkles.
	VFX.holo_deploy(_field, Vector3(_field_w * 0.32, 0.02, 0), Color(0.25, 0.7, 1.0), 0.6)
	VFX.holo_deploy(_field, Vector3(-_field_w * 0.32, 0.02, 0), Color(1.0, 0.3, 0.25), 0.6)


func _spawn_unit(side: String, cls: String, local: Vector2) -> void:
	var ps: PackedScene = load(UNIT_DIR + str((MODELS[side] as Dictionary)[cls])) as PackedScene
	if ps == null:
		return
	var node := ps.instantiate() as Node3D
	_field.add_child(node)
	var sc := 0.055 if cls != "commander" else 0.075
	node.scale = Vector3.ONE * sc
	# Team tint ring under each unit.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var col := Color(0.25, 0.7, 1.0) if side == "player" else Color(1.0, 0.3, 0.25)
	rmat.albedo_color = col
	rmat.emission_enabled = true
	rmat.emission = col
	rmat.emission_energy_multiplier = 1.6
	ring.material_override = rmat
	ring.position = Vector3(0, 0.06, 0)
	node.add_child(ring)
	# v0.11.0 ambient (b): commander pennant — pole + team-colored flag.
	if cls == "commander":
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.02
		pm.bottom_radius = 0.02
		pm.height = 1.6
		pole.mesh = pm
		pole.position = Vector3(0, 1.1, -0.3)
		node.add_child(pole)
		var flag := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.5, 0.3)
		flag.mesh = qm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = col
		flag.material_override = fmat
		flag.position = Vector3(0.27, 1.75, -0.3)
		node.add_child(flag)
		_pennants.append({"node": flag, "phase": randf() * TAU})
	var cfg: Dictionary = CLASSES[cls]
	var u := {
		"side": side, "cls": cls, "node": node, "ring": ring,
		"pos": local, "hp": float(cfg["hp"]), "max_hp": float(cfg["hp"]),
		"dmg": float(cfg["dmg"]), "range": float(cfg["range"]),
		"speed": float(cfg["speed"]), "alive": true,
		"path": [], "attack_target": null, "bob": randf() * TAU,
	}
	node.position = _local_to_field(local)
	if side == "enemy":
		node.rotation.y = PI * 0.5
	else:
		node.rotation.y = -PI * 0.5
	_units.append(u)


func _local_to_field(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _field_to_local(wp: Vector3) -> Vector2:
	var lp: Vector3 = _field.to_local(wp)
	return Vector2(lp.x, lp.z)


func _unit_alive_count(side: String) -> int:
	var n := 0
	for u in _units:
		if bool(u["alive"]) and str(u["side"]) == side:
			n += 1
	return n


func _commander_alive(side: String) -> bool:
	for u in _units:
		if bool(u["alive"]) and str(u["side"]) == side and str(u["cls"]) == "commander":
			return true
	return false


# ---------------------------------------------------------------- input ---

func _process(delta: float) -> void:
	if _match_over or _field == null:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_end_match(_timeout_winner())
		return
	for t in _reinf_at.duplicate():
		if _time_left <= MATCH_TIME - float(t):
			_reinf_at.erase(t)
			_spawn_reinforcements()
	_poll_input(delta)
	_update_drag(delta)
	_combat_acc += delta
	if _combat_acc >= COMBAT_TICK:
		_combat_acc = 0.0
		_combat_tick()
	_ai_acc += delta
	if _ai_acc >= AI_TICK:
		_ai_acc = 0.0
		_ai_tick()
	_update_units(delta)
	_update_drones(delta)
	_update_fog()
	_update_ambient(delta)
	_update_hud(delta)
	if _hill_cd > 0.0:
		_hill_cd -= delta


func _ray_to_table(origin: Vector3, dir: Vector3) -> Vector2:
	# Intersect the ray with the table-top plane; return field-local Vector2
	# or Vector2(INF, INF) on miss.
	var plane_y := _field.global_position.y
	if absf(dir.y) < 0.0001:
		return Vector2(INF, INF)
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0 or t > 6.0:
		return Vector2(INF, INF)
	var hit := origin + dir * t
	var lp := _field_to_local(hit)
	if absf(lp.x) > _field_w * 0.5 + 0.05 or absf(lp.y) > _field_d * 0.5 + 0.05:
		return Vector2(INF, INF)
	return lp


func _poll_input(delta: float) -> void:
	# Hands (pinch) + controllers (trigger = pinch, grip = fist-press).
	var sources := []
	if _origin != null:
		for side in ["left", "right"]:
			var hr: Dictionary = XRUIPointer.hand_ray(
				XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT,
				_origin)
			if bool(hr["active"]):
				sources.append({"kind": "hand", "side": side,
					"origin": hr["origin"], "dir": hr["dir"],
					"press": bool(hr["pinch"])})
	for side in _controllers.keys():
		var ctl: XRController3D = _controllers[side]
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var pressed := XRUIPointer.trigger_pressed(ctl)
		var grip := ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
		sources.append({"kind": "ctl", "side": side,
			"origin": ctl.global_position,
			"dir": -ctl.global_transform.basis.z.normalized(),
			"press": pressed, "grip": grip, "ctl": ctl})
	for s in sources:
		var key := str(s["kind"]) + "_" + str(s["side"])
		var was: bool = _trig_prev.get(key, false)
		var now: bool = bool(s["press"])
		_trig_prev[key] = now
		if now and not was and not _dragging:
			var lp := _ray_to_table(s["origin"], s["dir"])
			if lp.x != INF:
				_begin_drag(key, lp)
				_note_input("hands" if s["kind"] == "hand" else "controllers")
		if s.get("grip", false) and not bool(_grip_prev.get(key, false)):
			var lp2 := _ray_to_table(s["origin"], s["dir"])
			if lp2.x != INF:
				_try_raise_hill(lp2)
		_grip_prev[key] = bool(s.get("grip", false))


func _begin_drag(key: String, lp: Vector2) -> void:
	_selected.clear()
	for u in _units:
		if not bool(u["alive"]) or str(u["side"]) != "player":
			continue
		if (u["pos"] as Vector2).distance_to(lp) <= SELECT_R:
			_selected.append(u)
	if _selected.is_empty():
		# Nearest single unit within a wider radius still grabs.
		var best = null
		var bd := 0.24
		for u in _units:
			if not bool(u["alive"]) or str(u["side"]) != "player":
				continue
			var d: float = (u["pos"] as Vector2).distance_to(lp)
			if d < bd:
				bd = d
				best = u
		if best != null:
			_selected.append(best)
	if _selected.is_empty():
		return
	_dragging = true
	_drag_side = key
	_drag_path = [lp]
	_drag_point = lp
	ArtKit.game_sfx(self, "select")
	Haptics.tick("both")
	_path_line.visible = true


func _update_drag(delta: float) -> void:
	if not _dragging:
		return
	# Re-derive the current pointer ray for the drag source.
	var src := _drag_source_state()
	if src.is_empty() or not bool(src["press"]):
		_end_drag()
		return
	var lp := _ray_to_table(src["origin"], src["dir"])
	if lp.x == INF:
		return
	_drag_point = lp
	var last: Vector2 = _drag_path[_drag_path.size() - 1]
	if last.distance_to(lp) > 0.03:
		_drag_path.append(lp)
		_redraw_path()
	# Live selection ring at the drag point.
	_sel_ring.visible = true
	_sel_ring.global_position = _field.to_global(_local_to_field(lp)) + Vector3(0, 0.01, 0)


func _drag_source_state() -> Dictionary:
	var parts := _drag_side.split("_")
	if parts.size() != 2:
		return {}
	var kind: String = parts[0]
	var side: String = parts[1]
	if kind == "hand":
		if _origin == null:
			return {}
		var hr: Dictionary = XRUIPointer.hand_ray(
			XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT,
			_origin)
		if not bool(hr["active"]):
			return {}
		return {"origin": hr["origin"], "dir": hr["dir"], "press": bool(hr["pinch"])}
	var ctl: XRController3D = _controllers.get(side)
	if ctl == null or XRServer.get_tracker(ctl.tracker) == null:
		return {}
	return {"origin": ctl.global_position,
		"dir": -ctl.global_transform.basis.z.normalized(),
		"press": XRUIPointer.trigger_pressed(ctl)}


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_path_line.visible = false
	_sel_ring.visible = false
	if _selected.is_empty():
		return
	var path_len := 0.0
	for i in range(1, _drag_path.size()):
		path_len += (_drag_path[i] as Vector2).distance_to(_drag_path[i - 1])
	var order_path: Array = []
	if path_len > 0.25 and _drag_path.size() > 2:
		# Finger-drawn attack path: drop the first point (selection grab).
		order_path = _drag_path.slice(1)
	else:
		order_path = [_drag_point]
	# Attack-move if the order ends near a visible enemy.
	var target = null
	var bd := 0.18
	for u in _units:
		if not bool(u["alive"]) or str(u["side"]) != "enemy":
			continue
		if not _enemy_visible(u):
			continue
		var d: float = (u["pos"] as Vector2).distance_to(_drag_point)
		if d < bd:
			bd = d
			target = u
	for u in _selected:
		u["path"] = order_path.duplicate()
		u["attack_target"] = target
	ArtKit.game_sfx(self, "order")
	Haptics.confirm("both")
	_selected.clear()


func _redraw_path() -> void:
	_path_mesh.clear_surfaces()
	if _drag_path.size() < 2:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _drag_path:
		var wp: Vector3 = _field.to_global(_local_to_field(p)) + Vector3(0, 0.02, 0)
		_path_mesh.surface_add_vertex(_path_line.to_local(wp))
	_path_mesh.surface_end()


func _try_raise_hill(lp: Vector2) -> void:
	if _hill_cd > 0.0 or _hills.size() >= MAX_HILLS:
		Haptics.deny("both")
		return
	_hill_cd = HILL_COOLDOWN
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HILL_R
	sm.height = HILL_R * 0.9
	mound.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 1.2
	mound.material_override = mat
	mound.scale.y = 0.45
	_field.add_child(mound)
	mound.position = _local_to_field(lp) + Vector3(0, 0.01, 0)
	_hills.append({"pos": lp, "node": mound})
	ArtKit.game_sfx(self, "hill")
	Haptics.thump("both")
	_announce_text("TERRAIN RAISED", 1.2)


# ---------------------------------------------------------------- sim ----

func _hill_slow(p: Vector2) -> float:
	for h in _hills:
		if (h["pos"] as Vector2).distance_to(p) < HILL_R:
			return 0.55
	return 1.0


func _enemy_visible(u: Dictionary) -> bool:
	var up: Vector2 = u["pos"]
	for f in _units:
		if not bool(f["alive"]) or str(f["side"]) != "player":
			continue
		if (f["pos"] as Vector2).distance_to(up) <= SCOUT_R:
			return true
	for d in _drones:
		var dp := _field_to_local((d["node"] as Node3D).global_position)
		if dp.distance_to(up) <= SCOUT_R * 0.85:
			return true
	return false


func _nearest_enemy(u: Dictionary, max_d: float) -> Variant:
	var up: Vector2 = u["pos"]
	var foe_side := "enemy" if str(u["side"]) == "player" else "player"
	var best = null
	var bd := max_d
	for e in _units:
		if not bool(e["alive"]) or str(e["side"]) != foe_side:
			continue
		if foe_side == "enemy" and not _enemy_visible(e):
			continue
		var d: float = (e["pos"] as Vector2).distance_to(up)
		if d < bd:
			bd = d
			best = e
	return best


func _combat_tick() -> void:
	for u in _units:
		if not bool(u["alive"]):
			continue
		var foe = _nearest_enemy(u, float(u["range"]) * 1.15)
		if foe == null:
			u["attack_target"] = null
			continue
		u["attack_target"] = foe
		foe["hp"] = float(foe["hp"]) - float(u["dmg"])
		ArtKit.game_sfx(self, "hit", randf_range(0.9, 1.2))
		# Face the target.
		var un: Node3D = u["node"]
		var dir: Vector2 = (foe["pos"] as Vector2) - (u["pos"] as Vector2)
		if dir.length() > 0.001:
			un.rotation.y = lerp_angle(un.rotation.y, atan2(dir.x, dir.y) - PI * 0.5 + PI * 0.5, 0.6)
		if float(foe["hp"]) <= 0.0:
			_kill_unit(foe)


func _kill_unit(u: Dictionary) -> void:
	u["alive"] = false
	ArtKit.game_sfx(self, "die", randf_range(0.85, 1.1))
	# v0.11.0 ambient (a): the ember field drifts to the latest fighting.
	_hot_spot = _local_to_field(u["pos"] as Vector2)
	var node: Node3D = u["node"]
	var near_edge := absf((u["pos"] as Vector2).x) > _field_w * 0.5 - 0.12 \
		or absf((u["pos"] as Vector2).y) > _field_d * 0.5 - 0.12
	if near_edge and randf() < 0.75:
		_tumble_off_table(u)
	else:
		# Fall over on the field, then sink away.
		var tw := create_tween()
		tw.tween_property(node, "rotation:z", 1.35, 0.45).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "position:y", -0.05, 0.8).set_delay(0.4)
		tw.tween_callback(node.queue_free)
	if str(u["cls"]) == "commander":
		_end_match("player" if str(u["side"]) == "enemy" else "enemy")


func _tumble_off_table(u: Dictionary) -> void:
	# Knocked off the table edge: falls to the REAL floor and fades.
	var node: Node3D = u["node"]
	_field.remove_child(node)
	get_tree().current_scene.add_child(node)
	node.global_position = _field.to_global(_local_to_field(u["pos"] as Vector2))
	var tw := create_tween()
	tw.set_parallel(true)
	var floor_y := 0.02
	tw.tween_property(node, "global_position:y", floor_y, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var out_dir := Vector2((u["pos"] as Vector2).x, (u["pos"] as Vector2).y).normalized()
	tw.tween_property(node, "global_position:x", node.global_position.x + out_dir.x * 0.35, 0.7)
	tw.tween_property(node, "global_position:z", node.global_position.z + out_dir.y * 0.35, 0.7)
	tw.tween_property(node, "rotation:x", 2.2, 0.7)
	# v0.11.0 ambient (e): tiny dust puff where the unit hits the real floor.
	tw.chain().tween_callback(_dust_puff_at.bind(
		Vector3(node.global_position.x, 0.03, node.global_position.z)))
	tw.chain().tween_callback(node.queue_free).set_delay(0.4)
	ArtKit.game_sfx(self, "boom", 1.3)


func _dust_puff_at(p: Vector3) -> void:
	GraphicsPolish.spawn_sparks(get_tree().current_scene, p,
		Color(0.75, 0.72, 0.68), 10)


func _ai_tick() -> void:
	if _match_over:
		return
	for u in _units:
		if not bool(u["alive"]) or str(u["side"]) != "enemy":
			continue
		if not (u["path"] as Array).is_empty():
			continue
		if randf() < 0.45:
			continue
		var foe = _nearest_enemy(u, 99.0)
		if foe != null:
			var fp: Vector2 = foe["pos"]
			var jitter := Vector2(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06))
			u["path"] = [fp + jitter]
			u["attack_target"] = foe


func _spawn_reinforcements() -> void:
	# The couch is the reinforcement depot; fall back to the enemy table edge.
	var spawn := Vector2(-_field_w * 0.42, 0)
	if RoomKit.has_room_data():
		var couch := RoomKit.get_couch()
		if not couch.is_empty():
			var cp: Vector3 = couch["position"]
			var lp := _field_to_local(cp)
			spawn = Vector2(clampf(lp.x, -_field_w * 0.45, -_field_w * 0.2),
				clampf(lp.y, -_field_d * 0.4, _field_d * 0.4))
	for i in range(3):
		var cls := "infantry" if i < 2 else "archer"
		_spawn_unit("enemy", cls, spawn + Vector2(randf_range(-0.05, 0.05), randf_range(-0.08, 0.08)))
	_announce_text("ENEMY REINFORCEMENTS", 2.0)
	ArtKit.game_sfx(self, "horn")


func _update_units(delta: float) -> void:
	for u in _units:
		if not bool(u["alive"]):
			continue
		var node: Node3D = u["node"]
		# Idle bob.
		u["bob"] = float(u["bob"]) + delta * 3.0
		var path: Array = u["path"]
		if not path.is_empty():
			var wp: Vector2 = path[0]
			var p: Vector2 = u["pos"]
			var d := wp - p
			var dist := d.length()
			var step: float = float(u["speed"]) * _hill_slow(p) * delta
			if dist <= step + 0.01:
				u["pos"] = wp
				path.remove_at(0)
			else:
				u["pos"] = p + d.normalized() * step
				node.rotation.y = lerp_angle(node.rotation.y, atan2(d.x, d.y), 0.25)
			node.position = _local_to_field(u["pos"]) + Vector3(0, 0.008 * sin(float(u["bob"])), 0)
		else:
			node.position = _local_to_field(u["pos"]) + Vector3(0, 0.004 * sin(float(u["bob"])), 0)
		# HP ring pulse when hurt.
		var ring: MeshInstance3D = u["ring"]
		var frac: float = float(u["hp"]) / float(u["max_hp"])
		var rmat := ring.material_override as StandardMaterial3D
		if rmat != null:
			rmat.emission_energy_multiplier = 1.2 + (1.0 - frac) * 2.0


func _update_drones(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for d in _drones:
		var node: Node3D = d["node"]
		var ph: float = float(d["phase"])
		var a := t * 0.7 + ph
		var r := maxf(_field_w, _field_d) * 0.62
		node.position = Vector3(cos(a) * r, 0.22 + 0.03 * sin(t * 2.0 + ph), sin(a) * r * 0.75)
		# v0.11.0 ambient (c): the light cone sweeps slowly across the fog.
		var cone: Node3D = d["cone"]
		if cone != null and is_instance_valid(cone):
			cone.rotation.y = t * 0.9 + ph
			cone.rotation.x = 0.35 + 0.15 * sin(t * 0.6 + ph)


## v0.11.0 (Animator): pennant sway (phase-offset) + ember drift to hot spot.
func _update_ambient(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pv in _pennants:
		var pn: Node3D = pv["node"]
		if is_instance_valid(pn):
			var ph: float = float(pv["phase"])
			pn.rotation.y = sin(t * 2.2 + ph) * 0.35
			pn.rotation.z = sin(t * 3.1 + ph * 1.7) * 0.12
	if _ember_field != null and is_instance_valid(_ember_field):
		var want := _hot_spot + Vector3(0, 0.05, 0)
		_ember_field.position = _ember_field.position.lerp(want, minf(1.0, 1.2 * delta))


func _update_fog() -> void:
	for u in _units:
		if not bool(u["alive"]):
			continue
		var node: Node3D = u["node"]
		if str(u["side"]) == "enemy":
			node.visible = _enemy_visible(u)


func _update_hud(_delta: float) -> void:
	var m := int(_time_left) / 60
	var s := int(_time_left) % 60
	_hud_timer.text = "%d:%02d" % [m, s]
	_hud_score.text = "YOU %d  ·  ENEMY %d" % [_unit_alive_count("player"), _unit_alive_count("enemy")]
	if _announce_t > 0.0:
		_announce_t -= _delta
		if _announce_t <= 0.0:
			_announce.text = ""


func _announce_text(t: String, dur: float) -> void:
	_announce.text = t
	_announce_t = dur


func _timeout_winner() -> String:
	var p := _unit_alive_count("player")
	var e := _unit_alive_count("enemy")
	if p == e:
		return "draw"
	return "player" if p > e else "enemy"


func _end_match(winner: String) -> void:
	if _match_over:
		return
	_match_over = true
	_path_line.visible = false
	_sel_ring.visible = false
	if winner == "player":
		_announce_text("VICTORY!", 6.0)
		ArtKit.game_sfx(self, "win")
		ArtKit.stinger(self, "success")
		Haptics.play_sequence("fanfare", "both")
	elif winner == "enemy":
		_announce_text("DEFEAT", 6.0)
		ArtKit.game_sfx(self, "lose")
		ArtKit.stinger(self, "fail")
		Haptics.play_sequence("fail", "both")
	else:
		_announce_text("STALEMATE", 6.0)
		ArtKit.game_sfx(self, "horn")
	_telemetry("war_table_end", {"result": winner,
		"player_left": _unit_alive_count("player"),
		"enemy_left": _unit_alive_count("enemy")})



func _note_input(method: String) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.note_input_method(method)


func _telemetry(ev: String, fields: Dictionary) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event(ev, fields)
