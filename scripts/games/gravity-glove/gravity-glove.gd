## Gravity Glove: fling debris with a gravity glove. Floating junk drifts
## in the play volume - pinch-grab a piece (it sticks to your hand), then
## throw it by releasing with hand velocity. Thrown debris curves toward
## nearby target magnets thanks to the glove assist. Knock every target orb
## off its pedestal to win. Score is throws used. R restarts.
extends Node3D

const DEBRIS_COUNT := 8
const TARGET_COUNT := 5
const GRAB_DIST := 0.45
const ASSIST_DIST := 0.95
const ASSIST_FORCE := 7.0
const THROW_MAX := 9.0
const BOUND := 1.6
const Y_LO := 0.4
const Y_HI := 2.0
const POINTER_Y := 1.2

var camera: Camera3D = null
var debris: Array = []
var targets: Array = []
var grabbed_idx := -1
var throws := 0
var knocked := 0
var state := "playing"
var pointer_hist: Array = []
var sim_t := 0.0
var anchor_t := 0.0
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var glove_mat: StandardMaterial3D = null

# v0.7.0 RoomKit: debris rests on real table surfaces, target orbs mount
# along a real wall face, and thrown debris bounces off real wall planes.
# Cached; the default layout is untouched without XR room data.
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): rug -> glowing gravity arena (aura marks the target drop zone)
	_morph_anchors("RUG", "scifi", 1)
	_room_place_props()


## Debris rests on real table tops; target orbs line the widest wall face.
func _room_place_props() -> void:
	if not _room_tables.is_empty():
		for i in debris.size():
			var d: Dictionary = debris[i]
			var n: MeshInstance3D = d["node"]
			var t: Dictionary = _room_tables[i % _room_tables.size()]
			var tp: Vector3 = t["position"]
			var ts: Vector3 = t["size"]
			var spot := Vector3(
				tp.x + randf_range(-ts.x * 0.3, ts.x * 0.3),
				tp.y + ts.y * 0.5 + 0.06,
				tp.z + randf_range(-ts.z * 0.3, ts.z * 0.3))
			n.position = to_local(spot)
			d["vel"] = Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
	if not _room_walls.is_empty() and not targets.is_empty():
		var best: Dictionary = _room_walls[0]
		for w in _room_walls:
			if float(w["size"].x) > float(best["size"].x):
				best = w
		var nrm: Vector3 = best["normal"]
		var c := Vector3(_room_bounds.get_center().x, 0.0, _room_bounds.get_center().y)
		var side := signf((c - best["position"]).dot(nrm))
		if side == 0.0:
			side = 1.0
		var right := nrm.cross(Vector3.UP).normalized()
		if right.length() < 0.01:
			right = Vector3.RIGHT
		var base: Vector3 = best["position"] + nrm * side * 0.5
		var span := minf(float(best["size"].x) - 0.6, 2.4)
		for i in targets.size():
			var td: Dictionary = targets[i]
			var x := (float(i) / maxf(float(targets.size() - 1), 1.0) - 0.5) * span
			var lp := to_local(Vector3(base.x + right.x * x, 0.0, base.z + right.z * x))
			var ped: MeshInstance3D = td["ped"]
			var orb: MeshInstance3D = td["orb"]
			var ring: MeshInstance3D = td["ring"]
			ped.position = lp + Vector3(0, 0.4, 0)
			orb.position = lp + Vector3(0, 0.98, 0)
			ring.position = lp + Vector3(0, 0.82, 0)
			td["home"] = orb.position


## Normal-sign agnostic wall reflection.
func _bounce_walls(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		var d: float = (pos - w["position"]).dot(n)
		if absf(d) < radius and vel.dot(n) * signf(d) < 0.0:
			vel = vel - 2.0 * vel.dot(n) * n
	return vel


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "gravity-glove_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_build_debris()
	_build_targets()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, 0.0), 2.0, 40)
	_apply_room_layout()


func _process(delta: float) -> void:
	sim_t += delta
	anchor_t += delta
	if anchor_t >= 30.0:
		anchor_t = 0.0
		ARUpgradeKit.save_anchor("gravity-glove_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_restart()
	GraphicsPolish.pulse_glow(glove_mat, 1.2, 0.6, sim_t, 3.0)

	var pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var just := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	var pointer := _pointer_pos()
	pointer_hist.append({"p": pointer, "t": sim_t})
	while pointer_hist.size() > 10:
		pointer_hist.pop_front()

	if state == "playing":
		if just and grabbed_idx < 0:
			_try_grab(pointer)
		if grabbed_idx >= 0:
			if pinch:
				_hold_debris(pointer)
			else:
				_throw_debris()
		_move_debris(delta)
		_move_orbs(delta)
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == "win":
			_restart()


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.4, 3.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -0.4), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.05)
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


func _debris_mesh(kind: int) -> Mesh:
	match kind % 3:
		0:
			var b := BoxMesh.new()
			b.size = Vector3(0.16, 0.16, 0.16)
			return b
		1:
			var s := SphereMesh.new()
			s.radius = 0.11
			s.height = 0.22
			return s
		_:
			var c := CylinderMesh.new()
			c.top_radius = 0.09
			c.bottom_radius = 0.09
			c.height = 0.18
			return c


func _build_debris() -> void:
	var colors := [Color(0.3, 0.9, 0.9), Color(0.8, 0.4, 1.0), Color(1.0, 0.6, 0.25),
		Color(0.4, 1.0, 0.5), Color(1.0, 0.4, 0.6), Color(0.5, 0.7, 1.0)]
	for i in DEBRIS_COUNT:
		var inst := MeshInstance3D.new()
		inst.mesh = _debris_mesh(i)
		inst.material_override = GraphicsPolish.pbr_preset(colors[i % colors.size()], "plastic")
		inst.position = Vector3(randf_range(-1.4, 1.4), randf_range(0.7, 1.8), randf_range(-1.2, 1.2))
		add_child(inst)
		debris.append({
			"node": inst,
			"vel": Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4)),
			"spin": Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), 0),
			"trail": null,
		})


func _build_targets() -> void:
	for i in TARGET_COUNT:
		var x := -1.2 + float(i) * 0.6
		var ped := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.10
		pc.bottom_radius = 0.14
		pc.height = 0.8
		ped.mesh = pc
		ped.material_override = GraphicsPolish.pbr_preset(Color(0.2, 0.22, 0.3), "metal")
		ped.position = Vector3(x, 0.4, -1.3)
		add_child(ped)
		var orb := MeshInstance3D.new()
		var os := SphereMesh.new()
		os.radius = 0.14
		os.height = 0.28
		orb.mesh = os
		var omat := GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.8)
		orb.material_override = omat
		orb.position = Vector3(x, 0.98, -1.3)
		add_child(orb)
		# Magnet ring under each orb - the glove assist homes in on these.
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.16
		t.outer_radius = 0.22
		ring.mesh = t
		ring.material_override = GraphicsPolish.glow(Color(0.5, 0.3, 1.0), 1.4)
		ring.position = Vector3(x, 0.82, -1.3)
		add_child(ring)
		targets.append({
			"ped": ped, "orb": orb, "mat": omat, "ring": ring,
			"home": Vector3(x, 0.98, -1.3),
			"vel": Vector3.ZERO, "knocked": false,
			"phase": randf() * TAU,
		})
	glove_mat = GraphicsPolish.glow(Color(0.5, 0.3, 1.0), 1.5)
	GraphicsPolish.make_point_light(self, Vector3(0, 1.6, -1.3), Color(1.0, 0.6, 0.3), 0.8, 4.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.95, 0.8))
	hud_label.position = Vector3(-2.2, 2.6, 0.8)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.6, 1.0, 0.7))
	msg_label.position = Vector3(0.0, 2.2, -1.4)
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("Pinch / click a debris chunk to grab - release with a flick to throw - orbs curve toward magnets - knock all 5 off - R: restart", 30, Color(0.7, 0.75, 0.85))
	help_label.position = Vector3(0.0, 0.3, 1.8)
	add_child(help_label)


func _pointer_pos() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return Vector3(0, POINTER_Y, 0)
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	if absf(rd.y) < 0.0001:
		return ro + rd * 2.0
	var t := (POINTER_Y - ro.y) / rd.y
	if t < 0.0:
		return ro + rd * 2.0
	return ro + rd * t


func _hand_velocity() -> Vector3:
	if pointer_hist.size() < 2:
		return Vector3.ZERO
	var first: Dictionary = pointer_hist[0]
	var last: Dictionary = pointer_hist[pointer_hist.size() - 1]
	var dt: float = maxf(float(last["t"]) - float(first["t"]), 0.03)
	var dp: Vector3 = (last["p"] as Vector3) - (first["p"] as Vector3)
	var v := dp / dt
	if v.length() > THROW_MAX:
		v = v.normalized() * THROW_MAX
	return v


func _try_grab(pointer: Vector3) -> void:
	var best := -1
	var best_d := GRAB_DIST
	for i in debris.size():
		var n: MeshInstance3D = debris[i]["node"]
		var d: float = n.position.distance_to(pointer)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		grabbed_idx = best
		debris[best]["vel"] = Vector3.ZERO
		var trail := GraphicsPolish.make_trail(Color(0.6, 0.4, 1.0), 0.07)
		var n2: MeshInstance3D = debris[best]["node"]
		n2.add_child(trail)
		debris[best]["trail"] = trail
		GraphicsPolish.spawn_sparks(self, n2.position, Color(0.6, 0.4, 1.0), 10)


func _hold_debris(pointer: Vector3) -> void:
	var d: Dictionary = debris[grabbed_idx]
	var n: MeshInstance3D = d["node"]
	var p := ARUpgradeKit.clamp_to_room(pointer, 0.15)
	p.y = clampf(p.y, 0.3, 2.1)
	n.position = p


func _throw_debris() -> void:
	var d: Dictionary = debris[grabbed_idx]
	var n: MeshInstance3D = d["node"]
	var v := _hand_velocity()
	if v.length() < 0.4:
		v = Vector3(0, 0.5, -1.5)
	d["vel"] = v
	var trail: GPUParticles3D = d["trail"]
	if trail != null:
		trail.queue_free()
	d["trail"] = null
	throws += 1
	GraphicsPolish.spawn_sparks(self, n.position, Color(0.7, 0.5, 1.0), 10)
	grabbed_idx = -1


func _move_debris(delta: float) -> void:
	for i in debris.size():
		if i == grabbed_idx:
			continue
		var d: Dictionary = debris[i]
		var n: MeshInstance3D = d["node"]
		var v: Vector3 = d["vel"]
		# Gravity-glove assist: curve toward nearby target magnets.
		for t in targets:
			var td: Dictionary = t
			if bool(td["knocked"]):
				continue
			var orb: MeshInstance3D = td["orb"]
			var to: Vector3 = orb.position - n.position
			var dist := to.length()
			if dist < ASSIST_DIST and dist > 0.05:
				v += to.normalized() * ASSIST_FORCE * (1.0 - dist / ASSIST_DIST) * delta
		v *= maxf(0.0, 1.0 - 0.15 * delta)
		var p: Vector3 = n.position + v * delta
		if not _room_walls.is_empty():
			# v0.7.0 RoomKit: debris bounces off real wall planes and stays
			# inside the real room (world-space test, local-space result).
			var bx: Transform3D = n.get_parent().global_transform
			var gp: Vector3 = bx * p
			var gv: Vector3 = bx.basis * v
			var nv: Vector3 = _bounce_walls(gp, gv, 0.12)
			if nv != gv:
				v = bx.basis.inverse() * nv
			var b := _room_bounds.grow(-0.15)
			var cx := clampf(gp.x, b.position.x, b.position.x + b.size.x)
			var cz := clampf(gp.z, b.position.y, b.position.y + b.size.y)
			if cx != gp.x:
				v.x = -v.x
			if cz != gp.z:
				v.z = -v.z
			p = bx.affine_inverse() * Vector3(cx, gp.y, cz)
		else:
			if p.x < -BOUND or p.x > BOUND:
				v.x = -v.x
				p.x = clampf(p.x, -BOUND, BOUND)
			if p.z < -BOUND or p.z > BOUND:
				v.z = -v.z
				p.z = clampf(p.z, -BOUND, BOUND)
		if p.y < Y_LO or p.y > Y_HI:
			v.y = -v.y
			p.y = clampf(p.y, Y_LO, Y_HI)
		n.position = p
		d["vel"] = v
		var sp: Vector3 = d["spin"]
		n.rotation += sp * delta
		_check_orb_hits(n, v)


func _check_orb_hits(n: MeshInstance3D, v: Vector3) -> void:
	for t in targets:
		var td: Dictionary = t
		if bool(td["knocked"]):
			continue
		var orb: MeshInstance3D = td["orb"]
		if n.position.distance_to(orb.position) < 0.27:
			td["knocked"] = true
			td["vel"] = v * 0.7 + Vector3(0, 1.6, 0)
			knocked += 1
			GraphicsPolish.spawn_sparks(self, orb.position, Color(1.0, 0.7, 0.25), 24)
			var ring: MeshInstance3D = td["ring"]
			ring.visible = false
			if knocked >= TARGET_COUNT:
				_win()
			else:
				msg_label.text = "Direct hit! %d/%d" % [knocked, TARGET_COUNT]


func _move_orbs(delta: float) -> void:
	for t in targets:
		var td: Dictionary = t
		var orb: MeshInstance3D = td["orb"]
		var omat: StandardMaterial3D = td["mat"]
		if bool(td["knocked"]):
			var v: Vector3 = td["vel"]
			v.y -= 9.8 * delta
			var p: Vector3 = orb.position + v * delta
			if p.y < 0.14:
				p.y = 0.14
				v.y = -v.y * 0.4
				v.x *= 0.7
				v.z *= 0.7
			orb.position = p
			td["vel"] = v
		else:
			var home: Vector3 = td["home"]
			orb.position = home + Vector3(0, sin(sim_t * 2.0 + float(td["phase"])) * 0.03, 0)
			GraphicsPolish.pulse_glow(omat, 1.6, 0.5, sim_t + float(td["phase"]), 2.2)


func _win() -> void:
	state = "win"
	msg_label.text = "All targets down in %d throws! Click / R for more" % throws
	GraphicsPolish.spawn_confetti(self, Vector3(0, 1.4, -1.0), 80)
	ARUpgradeKit.save_anchor("gravity-glove_main", global_transform)


func _update_hud() -> void:
	hud_label.text = "Throws: %d   Targets: %d/%d" % [throws, knocked, TARGET_COUNT]
	if state == "playing" and grabbed_idx >= 0:
		msg_label.text = "Release with a flick to throw!"


func _restart() -> void:
	throws = 0
	knocked = 0
	state = "playing"
	grabbed_idx = -1
	msg_label.text = ""
	for i in debris.size():
		var d: Dictionary = debris[i]
		var n: MeshInstance3D = d["node"]
		n.position = Vector3(randf_range(-1.4, 1.4), randf_range(0.7, 1.8), randf_range(-1.2, 1.2))
		d["vel"] = Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.2), randf_range(-0.4, 0.4))
		var trail: GPUParticles3D = d["trail"]
		if trail != null:
			trail.queue_free()
		d["trail"] = null
	for t in targets:
		var td: Dictionary = t
		var orb: MeshInstance3D = td["orb"]
		orb.position = td["home"]
		td["vel"] = Vector3.ZERO
		td["knocked"] = false
		var ring: MeshInstance3D = td["ring"]
		ring.visible = true
	ARUpgradeKit.save_anchor("gravity-glove_main", global_transform)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
