## Laser Mirrors: rotate floating mirror panels so the laser beam bounces
## from the emitter into the receiver. Grab a mirror with pinch (or mouse
## drag) to spin it on Y; the beam re-traces in real time with sparks at
## every bounce. Six levels add mirrors and blocker obstacles. R restarts.
extends Node3D

const BEAM_COLOR := Color(1.0, 0.2, 0.25)
const MAX_BOUNCE := 10
const PANEL_HALF_W := 0.36
const PANEL_HALF_H := 0.46
const RECEIVER_R := 0.30
const GRAB_DIST := 0.65
const POOL_SEGS := 14
const POOL_MARKS := 10

var camera: Camera3D = null
var level_root: Node3D = null
var beam_root: Node3D = null
var seg_holders: Array = []
var mark_pool: Array = []
var mirrors: Array = []
var obstacles: Array = []
var emitter_tip := Vector3.ZERO
var emitter_dir := Vector3.RIGHT
var receiver_pos := Vector3.ZERO
var receiver_mat: StandardMaterial3D = null
var levels: Array = []
var level := 0
var moves := 0
var total_moves := 0
var levels_solved := 0
var state := "playing"
var state_t := 0.0
var grabbed_idx := -1
var prev_pointer := Vector3.ZERO
var spark_t := 0.0
var sim_t := 0.0
var anchor_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "mirror-maze_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_define_levels()
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	beam_root = Node3D.new()
	beam_root.name = "Beam"
	add_child(beam_root)
	_build_beam_pool()
	_build_hud()
	_build_level(0)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 2.2, 40)


func _process(delta: float) -> void:
	sim_t += delta
	anchor_t += delta
	if anchor_t >= 30.0:
		anchor_t = 0.0
		ARUpgradeKit.save_anchor("mirror-maze_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_restart_all()
	GraphicsPolish.pulse_glow(receiver_mat, 1.6, 0.7, sim_t, 2.5)

	var pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var just := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)

	if state == "playing":
		if just:
			_try_grab()
		if grabbed_idx >= 0:
			if pinch:
				_drag_mirror()
			else:
				_release_mirror()
		var res := _trace_beam()
		_draw_beam(res)
		spark_t += delta
		if spark_t >= 0.5:
			spark_t = 0.0
			_spark_bounces(res)
		if bool(res["solved"]):
			_on_solved()
	elif state == "solved":
		state_t += delta
		if state_t >= 3.0:
			_advance()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if state == "solved":
				_advance()
			elif state == "done":
				_restart_all()


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 3.4, 3.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, -0.2), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.3, 0.4)
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
		{
			"emitter": Vector3(-1.5, 1.0, 0.0), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(0.0, 1.0, -1.6),
			"mirrors": [{"pos": Vector3(0, 1, 0), "hint": 45.0}],
			"obstacles": [],
		},
		{
			"emitter": Vector3(-1.6, 1.0, 0.8), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(1.6, 1.0, -0.8),
			"mirrors": [
				{"pos": Vector3(0, 1, 0.8), "hint": 45.0},
				{"pos": Vector3(0, 1, -0.8), "hint": 45.0},
			],
			"obstacles": [],
		},
		{
			"emitter": Vector3(-1.6, 1.0, 0.0), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(0.9, 1.0, 0.0),
			"mirrors": [
				{"pos": Vector3(-0.9, 1, 0.0), "hint": 45.0},
				{"pos": Vector3(-0.9, 1, -1.0), "hint": 45.0},
				{"pos": Vector3(0.9, 1, -1.0), "hint": 135.0},
			],
			"obstacles": [{"pos": Vector3(0.2, 1, 0.0), "size": 0.5}],
		},
		{
			"emitter": Vector3(-1.6, 1.0, 1.2), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(1.0, 1.0, 1.2),
			"mirrors": [
				{"pos": Vector3(-0.4, 1, 1.2), "hint": 45.0},
				{"pos": Vector3(-0.4, 1, -0.2), "hint": 45.0},
				{"pos": Vector3(1.0, 1, -0.2), "hint": 135.0},
			],
			"obstacles": [],
		},
		{
			"emitter": Vector3(-1.6, 1.0, -1.2), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(0.8, 1.0, -1.2),
			"mirrors": [
				{"pos": Vector3(-0.8, 1, -1.2), "hint": 135.0},
				{"pos": Vector3(-0.8, 1, 0.6), "hint": 135.0},
				{"pos": Vector3(0.8, 1, 0.6), "hint": 45.0},
			],
			"obstacles": [
				{"pos": Vector3(0.3, 1, -1.2), "size": 0.5},
				{"pos": Vector3(0.0, 1, -0.4), "size": 0.4},
			],
		},
		{
			"emitter": Vector3(-1.6, 1.0, 1.4), "dir": Vector3(1, 0, 0),
			"receiver": Vector3(1.6, 1.0, -1.0),
			"mirrors": [
				{"pos": Vector3(-1.0, 1, 1.4), "hint": 45.0},
				{"pos": Vector3(-1.0, 1, 0.2), "hint": 45.0},
				{"pos": Vector3(0.4, 1, 0.2), "hint": 45.0},
				{"pos": Vector3(0.4, 1, -1.0), "hint": 45.0},
			],
			"obstacles": [
				{"pos": Vector3(-1.3, 1, 0.8), "size": 0.4},
				{"pos": Vector3(1.0, 1, -0.4), "size": 0.4},
			],
		},
	]


func _build_level(idx: int) -> void:
	for c in level_root.get_children():
		c.queue_free()
	mirrors.clear()
	obstacles.clear()
	grabbed_idx = -1
	moves = 0
	state = "playing"
	state_t = 0.0
	var lv: Dictionary = levels[idx]
	var epos: Vector3 = lv["emitter"]
	var edir: Vector3 = (lv["dir"] as Vector3).normalized()
	emitter_tip = epos + edir * 0.18
	emitter_dir = edir
	receiver_pos = lv["receiver"]
	# Emitter: dark housing + red nozzle + red light.
	var hous := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.28, 0.28, 0.28)
	hous.mesh = hb
	hous.material_override = GraphicsPolish.pbr_preset(Color(0.12, 0.12, 0.15), "metal")
	hous.position = epos
	level_root.add_child(hous)
	var holder := Node3D.new()
	holder.position = epos
	level_root.add_child(holder)
	holder.look_at(epos + edir)
	var nozzle := MeshInstance3D.new()
	var nc := CylinderMesh.new()
	nc.top_radius = 0.06
	nc.bottom_radius = 0.09
	nc.height = 0.22
	nozzle.mesh = nc
	nozzle.rotation_degrees = Vector3(90, 0, 0)
	nozzle.position = Vector3(0, 0, -0.18)
	nozzle.material_override = GraphicsPolish.glow(Color(1.0, 0.2, 0.2), 2.0)
	holder.add_child(nozzle)
	GraphicsPolish.make_point_light(level_root, epos, Color(1.0, 0.25, 0.25), 0.9, 3.0)
	# Receiver: base + pulsing gold dish.
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.20
	bc.bottom_radius = 0.24
	bc.height = 0.5
	base.mesh = bc
	base.material_override = GraphicsPolish.pbr(Color(0.15, 0.15, 0.18), 0.3, 0.5)
	base.position = receiver_pos + Vector3(0, -0.35, 0)
	level_root.add_child(base)
	var dish := MeshInstance3D.new()
	var ds := SphereMesh.new()
	ds.radius = RECEIVER_R
	ds.height = RECEIVER_R * 2.0
	dish.mesh = ds
	receiver_mat = GraphicsPolish.glow(Color(1.0, 0.75, 0.2), 1.8)
	dish.material_override = receiver_mat
	dish.position = receiver_pos
	level_root.add_child(dish)
	GraphicsPolish.make_point_light(level_root, receiver_pos, Color(1.0, 0.7, 0.25), 0.8, 3.0)
	# Mirrors: metal panel + glowing frame, starting off-solution.
	for m in lv["mirrors"]:
		var md: Dictionary = m
		var mp: Vector3 = md["pos"]
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(PANEL_HALF_W * 2.0 + 0.08, PANEL_HALF_H * 2.0 + 0.08, 0.03)
		frame.mesh = fb
		frame.material_override = GraphicsPolish.glow(Color(0.25, 0.8, 1.0), 1.2)
		frame.position = mp
		frame.position.z -= 0.0
		level_root.add_child(frame)
		var panel := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(PANEL_HALF_W * 2.0, PANEL_HALF_H * 2.0, 0.05)
		panel.mesh = pb
		panel.material_override = GraphicsPolish.pbr(Color(0.75, 0.85, 0.95), 0.95, 0.08)
		panel.position = mp + Vector3(0, 0, 0.015)
		level_root.add_child(panel)
		var pivot := Node3D.new()
		pivot.position = mp
		level_root.add_child(pivot)
		frame.reparent(pivot)
		panel.reparent(pivot)
		frame.position = Vector3(0, 0, 0)
		panel.position = Vector3(0, 0, 0.015)
		pivot.rotation.y = deg_to_rad(float(md["hint"]) + 65.0)
		mirrors.append({"node": pivot, "frame": frame, "hint": float(md["hint"])})
	# Obstacles: dark blocks that swallow the beam.
	for o in lv["obstacles"]:
		var od: Dictionary = o
		var op: Vector3 = od["pos"]
		var size: float = float(od["size"])
		var blk := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(size, 1.0, size)
		blk.mesh = bb
		blk.material_override = GraphicsPolish.pbr(Color(0.08, 0.05, 0.08), 0.2, 0.7)
		blk.position = op
		level_root.add_child(blk)
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(size + 0.04, 0.06, size + 0.04)
		edge.mesh = eb
		edge.material_override = GraphicsPolish.glow(Color(1.0, 0.2, 0.4), 1.2)
		edge.position = op + Vector3(0, 0.5, 0)
		level_root.add_child(edge)
		obstacles.append({"pos": op, "rad": size * 0.62})


func _build_beam_pool() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	var mat := GraphicsPolish.glow(BEAM_COLOR, 2.2)
	for i in POOL_SEGS:
		var holder := Node3D.new()
		beam_root.add_child(holder)
		var seg := MeshInstance3D.new()
		seg.mesh = cyl
		seg.material_override = mat
		seg.rotation_degrees = Vector3(90, 0, 0)
		holder.add_child(seg)
		holder.visible = false
		seg_holders.append({"holder": holder, "seg": seg})
	for i in POOL_MARKS:
		var mk := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.05
		s.height = 0.1
		mk.mesh = s
		mk.material_override = GraphicsPolish.glow(Color(1.0, 0.9, 0.4), 2.0)
		beam_root.add_child(mk)
		mk.visible = false
		mark_pool.append(mk)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.95, 0.8))
	hud_label.position = Vector3(-2.2, 2.6, 0.8)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.5, 1.0, 0.6))
	msg_label.position = Vector3(0.0, 2.3, -1.2)
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("Drag a mirror to rotate it - guide the red beam into the gold receiver - R: restart", 30, Color(0.7, 0.75, 0.85))
	help_label.position = Vector3(0.0, 0.35, 1.8)
	add_child(help_label)


func _trace_beam() -> Dictionary:
	var pts := PackedVector3Array()
	var pos := emitter_tip
	var dir := emitter_dir
	pts.append(pos)
	var bounces := 0
	var solved := false
	for i in MAX_BOUNCE:
		var best_t := 8.0
		var hit_kind := 0
		var hit_mirror := -1
		for m in mirrors.size():
			var mn: Node3D = mirrors[m]["node"]
			var mp: Vector3 = mn.global_position
			var n: Vector3 = mn.global_transform.basis.z.normalized()
			var denom := dir.dot(n)
			if absf(denom) < 0.0001:
				continue
			var t := (mp - pos).dot(n) / denom
			if t < 0.02 or t >= best_t:
				continue
			var hp: Vector3 = pos + dir * t
			var local: Vector3 = mn.global_transform.basis.inverse() * (hp - mp)
			if absf(local.x) <= PANEL_HALF_W and absf(local.y) <= PANEL_HALF_H:
				best_t = t
				hit_kind = 1
				hit_mirror = m
		for o in obstacles:
			var od: Dictionary = o
			var oc: Vector3 = od["pos"]
			var orad: float = float(od["rad"])
			var rel: Vector3 = pos - oc
			var b := rel.dot(dir)
			var c := rel.length_squared() - orad * orad
			var disc := b * b - c
			if disc < 0.0:
				continue
			var t := -b - sqrt(disc)
			if t > 0.02 and t < best_t:
				best_t = t
				hit_kind = 2
				hit_mirror = -1
		var rrel: Vector3 = pos - receiver_pos
		var rb := rrel.dot(dir)
		var rc := rrel.length_squared() - RECEIVER_R * RECEIVER_R
		var rdisc := rb * rb - rc
		if rdisc >= 0.0:
			var t := -rb - sqrt(rdisc)
			if t > 0.02 and t < best_t:
				best_t = t
				hit_kind = 3
		var endp: Vector3 = pos + dir * best_t
		pts.append(endp)
		if hit_kind == 1:
			var mn2: Node3D = mirrors[hit_mirror]["node"]
			var n2: Vector3 = mn2.global_transform.basis.z.normalized()
			dir = (dir - 2.0 * dir.dot(n2) * n2).normalized()
			pos = endp + dir * 0.02
			bounces += 1
		elif hit_kind == 3:
			solved = true
			break
		else:
			break
	return {"points": pts, "solved": solved, "bounces": bounces}


func _draw_beam(res: Dictionary) -> void:
	var pts: PackedVector3Array = res["points"]
	var nsegs := pts.size() - 1
	for i in seg_holders.size():
		var h: Dictionary = seg_holders[i]
		var holder: Node3D = h["holder"]
		var seg: MeshInstance3D = h["seg"]
		if i < nsegs:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var dist := a.distance_to(b)
			holder.visible = dist > 0.005
			if holder.visible:
				holder.position = (a + b) * 0.5
				holder.look_at(b)
				seg.scale = Vector3(1, dist, 1)
		else:
			holder.visible = false
	var nmarks := maxi(pts.size() - 2, 0)
	for i in mark_pool.size():
		var mk: MeshInstance3D = mark_pool[i]
		if i < nmarks:
			mk.visible = true
			mk.position = pts[i + 1]
			var s := 1.0 + 0.25 * sin(sim_t * 6.0 + float(i))
			mk.scale = Vector3(s, s, s)
		else:
			mk.visible = false


func _spark_bounces(res: Dictionary) -> void:
	var pts: PackedVector3Array = res["points"]
	var n := mini(pts.size() - 2, 3)
	for i in n:
		GraphicsPolish.spawn_sparks(self, pts[i + 1], Color(1.0, 0.8, 0.3), 6)


func _aim_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var mp := get_viewport().get_mouse_position()
	return [camera.project_ray_origin(mp), camera.project_ray_normal(mp)]


func _pointer_pos() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.0001:
		return ro + rd * 2.0
	var t := (1.0 - ro.y) / rd.y
	if t < 0.0:
		return ro + rd * 2.0
	return ro + rd * t


func _try_grab() -> void:
	var ray := _aim_ray()
	var ro: Vector3 = ray[0]
	var rd: Vector3 = (ray[1] as Vector3).normalized()
	var best := -1
	var best_d := GRAB_DIST
	for m in mirrors.size():
		var mn: Node3D = mirrors[m]["node"]
		var mp: Vector3 = mn.global_position
		var t := (mp - ro).dot(rd)
		if t < 0.0:
			continue
		var d: Vector3 = (ro + rd * t) - mp
		if d.length() < best_d:
			best_d = d.length()
			best = m
	if best >= 0:
		grabbed_idx = best
		prev_pointer = _pointer_pos()
		var mn2: Node3D = mirrors[best]["node"]
		GraphicsPolish.spawn_sparks(self, mn2.global_position, Color(0.4, 0.9, 1.0), 8)


func _drag_mirror() -> void:
	if grabbed_idx < 0 or camera == null:
		return
	var cur := _pointer_pos()
	var right: Vector3 = camera.global_transform.basis.x.normalized()
	var dtheta: float = (cur - prev_pointer).dot(right) * 4.0
	prev_pointer = cur
	var mn: Node3D = mirrors[grabbed_idx]["node"]
	mn.rotation.y += dtheta


func _release_mirror() -> void:
	if grabbed_idx >= 0:
		var mn: Node3D = mirrors[grabbed_idx]["node"]
		GraphicsPolish.spawn_sparks(self, mn.global_position, Color(0.4, 1.0, 0.6), 8)
	grabbed_idx = -1
	moves += 1


func _on_solved() -> void:
	state = "solved"
	state_t = 0.0
	levels_solved += 1
	total_moves += moves
	msg_label.text = "Level %d solved in %d moves!" % [level + 1, moves]
	GraphicsPolish.spawn_confetti(self, receiver_pos + Vector3(0, 0.4, 0), 60)
	ARUpgradeKit.save_anchor("mirror-maze_main", global_transform)


func _advance() -> void:
	if level + 1 >= levels.size():
		state = "done"
		msg_label.text = "All 6 levels solved - %d total moves! Click / R to replay" % total_moves
		GraphicsPolish.spawn_confetti(self, Vector3(0, 1.5, 0), 90)
	else:
		level += 1
		_build_level(level)
		msg_label.text = ""


func _update_hud() -> void:
	hud_label.text = "Level %d/6   Moves %d   Solved %d" % [level + 1, moves, levels_solved]
	if state == "playing" and grabbed_idx >= 0:
		msg_label.text = "Rotating mirror..."
	elif state == "playing" and msg_label.text == "Rotating mirror...":
		msg_label.text = ""


func _restart_all() -> void:
	level = 0
	total_moves = 0
	levels_solved = 0
	msg_label.text = ""
	_build_level(0)
	ARUpgradeKit.save_anchor("mirror-maze_main", global_transform)
