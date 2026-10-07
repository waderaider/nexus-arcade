## Time Freeze: action puzzles with time control. Hazards (sweeping laser
## bars, patrolling sentries) move on loops while a goal orb waits across
## the room. Pinch-HOLD (or mouse-hold) to freeze time - everything stops
## under a blue tint - then drag the player puck along a safe path. Release
## to unfreeze: the puck launches with your drag flick and physics plays
## out. Reach the goal without touching hazards. 8 levels; score is levels
## cleared plus time-frozen efficiency. R restarts.
extends Node3D

const PLAY_Y := 0.15
const PUCK_R := 0.12
const GOAL_R := 0.32
const FREEZE_BUDGET := 12.0
const DRAG_SPEED := 2.4
const BOUND := 1.6

var camera: Camera3D = null
var level_root: Node3D = null
var puck: MeshInstance3D = null
var puck_mat: StandardMaterial3D = null
var puck_vel := Vector3.ZERO
var start_pad: MeshInstance3D = null
var goal: MeshInstance3D = null
var goal_mat: StandardMaterial3D = null
var goal_pos := Vector3.ZERO
var start_pos := Vector3.ZERO
var hazards: Array = []
var levels: Array = []
var level := 0
var levels_cleared := 0
var state := "playing"
var state_t := 0.0
var frozen := false
var was_frozen := false
var freeze_left := FREEZE_BUDGET
var freeze_used_total := 0.0
var drag_hist: Array = []
var overlay: ColorRect = null
var freeze_label: Label3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var bar_fill: MeshInstance3D = null
var sim_t := 0.0
var anchor_t := 0.0

# v0.7.0 RoomKit: level layouts scale to the real room and the puck is
# clamped to the real room bounds. Cached; default layout without room data.
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_center := Vector3.ZERO
var _room_scale := 1.0


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): windows -> time-frozen star vistas (the freeze extends outside)
	_morph_anchors("WINDOW", "scifi", 2)
	var c := _room_bounds.get_center()
	_room_center = Vector3(c.x, 0.0, c.y)
	_room_scale = clampf(minf(_room_bounds.size.x, _room_bounds.size.y) / (BOUND * 2.0), 1.0, 2.6)
	_build_level(level)  # rebuild the current level on the room-fitted layout


## Map a level-design coordinate into the real room (identity when no data).
func _room_point(p: Vector3) -> Vector3:
	if _room_walls.is_empty():
		return p
	var v := p * _room_scale
	v.y = p.y
	return _room_center + v


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "time-freeze_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_define_levels()
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	_build_overlay()
	_build_hud()
	_build_level(0)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 2.2, 40)
	_apply_room_layout()


func _process(delta: float) -> void:
	sim_t += delta
	anchor_t += delta
	if anchor_t >= 30.0:
		anchor_t = 0.0
		ARUpgradeKit.save_anchor("time-freeze_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_restart_all()
	GraphicsPolish.pulse_glow(goal_mat, 1.6, 0.8, sim_t, 2.5)
	GraphicsPolish.pulse_glow(puck_mat, 1.5, 0.9 if frozen else 0.3, sim_t, 5.0 if frozen else 2.0)

	if state == "playing":
		var want := _want_freeze()
		frozen = want and freeze_left > 0.0
		if frozen and not was_frozen:
			puck_vel = Vector3.ZERO
			drag_hist.clear()
			freeze_label.visible = true
		if not frozen and was_frozen:
			puck_vel = _drag_velocity() * 1.3
			if puck_vel.length() > 3.0:
				puck_vel = puck_vel.normalized() * 3.0
			freeze_label.visible = false
		was_frozen = frozen
		overlay.visible = frozen
		if frozen:
			freeze_left = maxf(freeze_left - delta, 0.0)
			freeze_used_total += delta
			_drag_puck(delta)
		else:
			_move_hazards(delta)
			_move_puck(delta)
			_check_collisions()
	elif state == "cleared":
		state_t += delta
		if state_t >= 2.5:
			_advance()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if state == "cleared":
				_advance()
			elif state == "dead":
				_build_level(level)
			elif state == "done":
				_restart_all()


func _want_freeze() -> bool:
	if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
		return true
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT):
		return true
	return false


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 3.6, 3.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _define_levels() -> void:
	levels = [
		{"start": Vector3(-1.3, PLAY_Y, 0), "goal": Vector3(1.3, PLAY_Y, 0),
			"hazards": [{"type": "sentry", "center": Vector3(0, PLAY_Y, 0), "radius": 0.5, "speed": 0.9, "phase": 0.0}]},
		{"start": Vector3(-1.3, PLAY_Y, -1.0), "goal": Vector3(1.3, PLAY_Y, 1.0),
			"hazards": [
				{"type": "sentry", "center": Vector3(0, PLAY_Y, -0.3), "radius": 0.6, "speed": 1.0, "phase": 0.0},
				{"type": "sentry", "center": Vector3(0, PLAY_Y, 0.6), "radius": 0.5, "speed": 1.2, "phase": 1.5}]},
		{"start": Vector3(-1.3, PLAY_Y, 0), "goal": Vector3(1.3, PLAY_Y, 0),
			"hazards": [{"type": "laser", "center": Vector3(0, PLAY_Y, 0), "length": 1.6, "speed": 0.7, "phase": 0.0}]},
		{"start": Vector3(-1.3, PLAY_Y, -1.2), "goal": Vector3(1.3, PLAY_Y, 1.2),
			"hazards": [
				{"type": "laser", "center": Vector3(0, PLAY_Y, 0), "length": 1.8, "speed": 0.8, "phase": 0.0},
				{"type": "sentry", "center": Vector3(0.6, PLAY_Y, -0.6), "radius": 0.4, "speed": 1.3, "phase": 0.0}]},
		{"start": Vector3(0, PLAY_Y, -1.3), "goal": Vector3(0, PLAY_Y, 1.3),
			"hazards": [
				{"type": "laser", "center": Vector3(-0.5, PLAY_Y, 0), "length": 1.4, "speed": 0.9, "phase": 0.0},
				{"type": "laser", "center": Vector3(0.5, PLAY_Y, 0), "length": 1.4, "speed": 0.9, "phase": 1.57}]},
		{"start": Vector3(-1.3, PLAY_Y, -1.3), "goal": Vector3(1.3, PLAY_Y, 1.3),
			"hazards": [
				{"type": "sentry", "center": Vector3(0, PLAY_Y, 0), "radius": 0.8, "speed": 1.2, "phase": 0.0},
				{"type": "sentry", "center": Vector3(-0.8, PLAY_Y, 0.8), "radius": 0.4, "speed": 1.5, "phase": 0.0},
				{"type": "sentry", "center": Vector3(0.8, PLAY_Y, -0.8), "radius": 0.4, "speed": 1.5, "phase": 2.0}]},
		{"start": Vector3(-1.3, PLAY_Y, 1.3), "goal": Vector3(1.3, PLAY_Y, -1.3),
			"hazards": [
				{"type": "laser", "center": Vector3(0, PLAY_Y, 0.5), "length": 2.0, "speed": 1.0, "phase": 0.0},
				{"type": "laser", "center": Vector3(0, PLAY_Y, -0.5), "length": 2.0, "speed": 1.0, "phase": 1.57},
				{"type": "sentry", "center": Vector3(0, PLAY_Y, 0), "radius": 0.3, "speed": 1.6, "phase": 0.0}]},
		{"start": Vector3(-1.4, PLAY_Y, 0), "goal": Vector3(1.4, PLAY_Y, 0),
			"hazards": [
				{"type": "sentry", "center": Vector3(0, PLAY_Y, 0), "radius": 0.9, "speed": 1.4, "phase": 0.0},
				{"type": "sentry", "center": Vector3(-0.5, PLAY_Y, 0), "radius": 0.5, "speed": 1.8, "phase": 1.0},
				{"type": "laser", "center": Vector3(0.7, PLAY_Y, 0), "length": 1.2, "speed": 1.2, "phase": 0.0},
				{"type": "laser", "center": Vector3(-0.7, PLAY_Y, 0), "length": 1.2, "speed": 1.2, "phase": 1.57}]},
	]


func _build_level(idx: int) -> void:
	for c in level_root.get_children():
		c.queue_free()
	hazards.clear()
	frozen = false
	was_frozen = false
	overlay.visible = false
	freeze_label.visible = false
	freeze_left = FREEZE_BUDGET
	puck_vel = Vector3.ZERO
	state = "playing"
	state_t = 0.0
	var lv: Dictionary = levels[idx]
	start_pos = _room_point(lv["start"])
	goal_pos = _room_point(lv["goal"])
	# Floor grid for readability.
	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.2, 4.2)
	grid.mesh = plane
	grid.material_override = GraphicsPolish.pbr_preset(Color(0.05, 0.06, 0.10), "matte")
	level_root.add_child(grid)
	# Start pad ring.
	start_pad = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.24
	start_pad.mesh = ring
	start_pad.material_override = GraphicsPolish.glow(Color(0.3, 0.9, 1.0), 1.4)
	start_pad.position = start_pos + Vector3(0, 0.02, 0)
	level_root.add_child(start_pad)
	# Player puck with trail.
	puck = MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = PUCK_R
	ps.height = PUCK_R * 2.0
	puck.mesh = ps
	puck_mat = GraphicsPolish.glow(Color(0.35, 0.9, 1.0), 1.6)
	puck.material_override = puck_mat
	puck.position = start_pos
	level_root.add_child(puck)
	puck.add_child(GraphicsPolish.make_trail(Color(0.35, 0.9, 1.0), 0.05))
	# Goal orb.
	goal = MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.2
	gs.height = 0.4
	goal.mesh = gs
	goal_mat = GraphicsPolish.glow(Color(1.0, 0.8, 0.25), 1.8)
	goal.material_override = goal_mat
	goal.position = goal_pos
	level_root.add_child(goal)
	var gring := MeshInstance3D.new()
	var gt := TorusMesh.new()
	gt.inner_radius = GOAL_R - 0.04
	gt.outer_radius = GOAL_R
	gring.mesh = gt
	gring.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.25), 1.2)
	gring.position = goal_pos + Vector3(0, 0.01, 0)
	level_root.add_child(gring)
	GraphicsPolish.make_point_light(level_root, goal_pos + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.3), 0.9, 4.0)
	# Hazards.
	for h in lv["hazards"]:
		_build_hazard(h)
	msg_label.text = ""


func _build_hazard(h: Dictionary) -> void:
	var htype: String = h["type"]
	var hc: Vector3 = _room_point(h["center"])  # v0.7.0: hazards fit the real room
	if htype == "sentry":
		var node := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.15
		s.height = 0.3
		node.mesh = s
		node.material_override = GraphicsPolish.glow(Color(1.0, 0.25, 0.3), 1.8)
		node.position = hc
		level_root.add_child(node)
		var danger := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.24
		t.outer_radius = 0.30
		danger.mesh = t
		var dmat := GraphicsPolish.glow(Color(1.0, 0.25, 0.3, 0.45), 1.0)
		danger.material_override = dmat
		node.add_child(danger)
		hazards.append({"type": "sentry", "node": node, "center": hc,
			"radius": float(h["radius"]), "speed": float(h["speed"]), "phase": float(h["phase"])})
	else:
		var pivot := Node3D.new()
		pivot.position = hc
		level_root.add_child(pivot)
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		var length: float = float(h["length"])
		b.size = Vector3(length, 0.09, 0.14)
		bar.mesh = b
		bar.material_override = GraphicsPolish.glow(Color(1.0, 0.2, 0.35), 2.0)
		pivot.add_child(bar)
		var hub := MeshInstance3D.new()
		var hc2 := CylinderMesh.new()
		hc2.top_radius = 0.10
		hc2.bottom_radius = 0.12
		hc2.height = 0.16
		hub.mesh = hc2
		hub.material_override = GraphicsPolish.pbr_preset(Color(0.15, 0.15, 0.18), "metal")
		pivot.add_child(hub)
		hazards.append({"type": "laser", "node": pivot, "center": hc,
			"length": length, "speed": float(h["speed"]), "phase": float(h["phase"])})


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	overlay = ColorRect.new()
	overlay.color = Color(0.25, 0.5, 1.0, 0.28)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	layer.add_child(overlay)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.95, 0.8))
	hud_label.position = Vector3(-2.2, 2.7, 0.8)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.6, 0.9, 1.0))
	msg_label.position = Vector3(0.0, 2.2, -1.2)
	add_child(msg_label)
	freeze_label = GraphicsPolish.make_label("TIME FROZEN", 84, Color(0.5, 0.8, 1.0))
	freeze_label.position = Vector3(0.0, 1.7, -1.6)
	freeze_label.visible = false
	add_child(freeze_label)
	help_label = GraphicsPolish.make_label("Hold click / pinch to FREEZE time - drag the puck while frozen - release to launch - dodge red hazards, reach gold - R: restart", 30, Color(0.7, 0.75, 0.85))
	help_label.position = Vector3(0.0, 0.4, 2.0)
	add_child(help_label)
	# Freeze budget bar.
	var root := Node3D.new()
	root.position = Vector3(0.0, 2.95, -1.0)
	add_child(root)
	var bg := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.6, 0.08, 0.02)
	bg.mesh = b
	bg.material_override = GraphicsPolish.pbr(Color(0.1, 0.1, 0.14), 0.0, 0.8)
	root.add_child(bg)
	bar_fill = MeshInstance3D.new()
	var f := BoxMesh.new()
	f.size = Vector3(1.0, 0.06, 0.02)
	bar_fill.mesh = f
	bar_fill.material_override = GraphicsPolish.glow(Color(0.4, 0.7, 1.0), 1.4)
	root.add_child(bar_fill)
	var cap := GraphicsPolish.make_label("FREEZE", 36, Color(0.7, 0.85, 1.0))
	cap.position = Vector3(0, 0.2, 0)
	root.add_child(cap)


func _pointer_pos() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		var p: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		p.y = PLAY_Y
		return p
	if camera == null:
		return Vector3(0, PLAY_Y, 0)
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.0001:
		return Vector3(ro.x, PLAY_Y, ro.z)
	var t := (PLAY_Y - ro.y) / rd.y
	if t < 0.0:
		return Vector3(ro.x, PLAY_Y, ro.z)
	var p2: Vector3 = ro + rd * t
	return p2


func _drag_puck(delta: float) -> void:
	var target := ARUpgradeKit.clamp_to_room(_pointer_pos(), 0.12)
	target.y = PLAY_Y
	var to: Vector3 = target - puck.position
	var step: float = minf(to.length(), DRAG_SPEED * delta)
	if step > 0.0001:
		puck.position += to.normalized() * step
	drag_hist.append({"p": puck.position, "t": sim_t})
	while drag_hist.size() > 10:
		drag_hist.pop_front()


func _drag_velocity() -> Vector3:
	if drag_hist.size() < 2:
		return Vector3.ZERO
	var first: Dictionary = drag_hist[0]
	var last: Dictionary = drag_hist[drag_hist.size() - 1]
	var dt: float = maxf(float(last["t"]) - float(first["t"]), 0.05)
	var dp: Vector3 = (last["p"] as Vector3) - (first["p"] as Vector3)
	dp.y = 0.0
	return dp / dt


func _move_hazards(delta: float) -> void:
	for h in hazards:
		var hd: Dictionary = h
		hd["phase"] = float(hd["phase"]) + float(hd["speed"]) * delta
		var ph: float = float(hd["phase"])
		if String(hd["type"]) == "sentry":
			var node: MeshInstance3D = hd["node"]
			var c: Vector3 = hd["center"]
			var r: float = float(hd["radius"])
			node.position = c + Vector3(cos(ph) * r, 0, sin(ph) * r)
		else:
			var pivot: Node3D = hd["node"]
			pivot.rotation.y = ph


func _move_puck(delta: float) -> void:
	puck_vel *= maxf(0.0, 1.0 - 2.0 * delta)
	var p: Vector3 = puck.position + puck_vel * delta
	if not _room_walls.is_empty():
		# v0.7.0: the puck stays inside the real room bounds.
		var b := _room_bounds.grow(-0.15)
		var cx := clampf(p.x, b.position.x, b.position.x + b.size.x)
		var cz := clampf(p.z, b.position.y, b.position.y + b.size.y)
		if cx != p.x:
			puck_vel.x = 0.0
		if cz != p.z:
			puck_vel.z = 0.0
		p.x = cx
		p.z = cz
	else:
		if p.x < -BOUND or p.x > BOUND:
			puck_vel.x = 0.0
			p.x = clampf(p.x, -BOUND, BOUND)
		if p.z < -BOUND or p.z > BOUND:
			puck_vel.z = 0.0
			p.z = clampf(p.z, -BOUND, BOUND)
	p.y = PLAY_Y
	puck.position = p


func _seg_dist(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return pt.distance_to(a)
	var t := clampf((pt - a).dot(ab) / denom, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


func _check_collisions() -> void:
	if puck == null:
		return
	var pp: Vector3 = puck.position
	for h in hazards:
		var hd: Dictionary = h
		if String(hd["type"]) == "sentry":
			var node: MeshInstance3D = hd["node"]
			if pp.distance_to(node.position) < PUCK_R + 0.17:
				_die()
				return
		else:
			var pivot: Node3D = hd["node"]
			var c: Vector3 = hd["center"]
			var half: float = float(hd["length"]) * 0.5
			# Bar endpoints: pivot rotates local +X by phase about Y.
			var ph: float = float(hd["phase"])
			var fwd := Vector3(cos(ph), 0, -sin(ph))
			var a: Vector3 = c - fwd * half
			var b: Vector3 = c + fwd * half
			if _seg_dist(pp, a, b) < PUCK_R + 0.10:
				_die()
				return
	if pp.distance_to(goal_pos) < GOAL_R:
		_cleared()


func _die() -> void:
	state = "dead"
	overlay.visible = false
	freeze_label.visible = false
	frozen = false
	was_frozen = false
	msg_label.text = "Zapped! Click / R to retry"
	GraphicsPolish.spawn_sparks(self, puck.position, Color(1.0, 0.3, 0.3), 30)
	puck.position = start_pos
	puck_vel = Vector3.ZERO


func _cleared() -> void:
	state = "cleared"
	state_t = 0.0
	levels_cleared += 1
	msg_label.text = "Level %d cleared!" % [level + 1]
	GraphicsPolish.spawn_confetti(self, goal_pos + Vector3(0, 0.5, 0), 60)
	ARUpgradeKit.save_anchor("time-freeze_main", global_transform)


func _advance() -> void:
	if level + 1 >= levels.size():
		state = "done"
		msg_label.text = "TIME MASTERED! 8/8 - freeze used %.1fs - Click / R to replay" % freeze_used_total
		GraphicsPolish.spawn_confetti(self, Vector3(0, 1.5, 0), 100)
	else:
		level += 1
		_build_level(level)


func _update_hud() -> void:
	hud_label.text = "Level %d/8   Cleared %d   Frozen %.1fs" % [level + 1, levels_cleared, freeze_used_total]
	if bar_fill != null:
		var frac := freeze_left / FREEZE_BUDGET
		bar_fill.scale.x = maxf(frac, 0.02)
		bar_fill.position.x = -0.8 + 0.8 * frac
		var m := bar_fill.material_override as StandardMaterial3D
		if m != null:
			var c := Color(0.4, 0.7, 1.0) if frac > 0.25 else Color(1.0, 0.4, 0.3)
			m.albedo_color = c
			m.emission = c


func _restart_all() -> void:
	level = 0
	levels_cleared = 0
	freeze_used_total = 0.0
	_build_level(0)
	ARUpgradeKit.save_anchor("time-freeze_main", global_transform)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
