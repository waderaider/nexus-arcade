## ar-billiards.gd -- NEXUS ARCADE: pool on your table.
## A felt table anchors to a table-height surface in front of the player.
## 6 object balls + cue ball with circle-collision physics on the plane,
## cushion bounces, and corner pockets. Aim with the hand ray (or mouse),
## pinch-drag back (or mouse-drag) and release to shoot -- power follows the
## drag distance. Pocket all 6 in the fewest shots to win.
## R (or click after a win) re-racks.
extends Node3D

const TABLE_X := 2.0
const TABLE_Z := 1.0
const BALL_R := 0.045
const POCKET_R := 0.10
const HX := 0.97 - BALL_R # inner cushion bounds (local x)
const HZ := 0.47 - BALL_R # inner cushion bounds (local z)
const MAX_POWER := 3.0
const FRICTION := 1.1
const TABLE_Y := 0.75

var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}

var state := "aim" # "aim" | "rolling" | "win"
var shots := 0
var table_root: Node3D = null
var balls: Array = [] # {node, p: Vector2, v: Vector2, sunk, cue}
var cue_idx := 0
var cue_respot := false

var aiming := false
var press_pt := Vector2.ZERO
var aim_dir := Vector2(0, -1)
var power := 0.0
var cue_pivot: Node3D = null
var guide_mat: StandardMaterial3D = null
var pocket_mat: StandardMaterial3D = null

var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null


func _ready() -> void:
	_build_camera()
	_build_environment()
	GraphicsPolish.make_light_rig(self)
	_build_table()
	_build_balls()
	_build_cue_stick()
	_build_ui()
	ARUpgradeKit.place_on_table(table_root, 1.2, TABLE_Y)
	ARUpgradeKit.apply_anchor(table_root, "ar-billiards_main")
	_reset()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.2, 0.4), 2.0, 30)


func _build_camera() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			return
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 2.0, 2.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.7, 0.2), Vector3.UP)


func _build_environment() -> void:
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.50, 0.60)
	env.ambient_light_energy = 0.8
	amb.environment = env
	add_child(amb)

	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.0, 0.1, 8.0)
	floor_mi.mesh = fb
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.12, 0.18), "matte")
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _box(sx: float, sy: float, sz: float, color: Color, pos: Vector3, preset := "matte") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, sy, sz)
	mi.mesh = bm
	mi.material_override = GraphicsPolish.pbr_preset(color, preset)
	mi.position = pos
	table_root.add_child(mi)
	return mi


func _build_table() -> void:
	table_root = Node3D.new()
	table_root.name = "TableRoot"
	add_child(table_root)

	# Felt bed.
	_box(TABLE_X, 0.08, TABLE_Z, Color(0.10, 0.45, 0.20), Vector3(0, 0, 0))
	# Wooden rim under the felt.
	_box(TABLE_X + 0.12, 0.05, TABLE_Z + 0.12, Color(0.30, 0.18, 0.10), Vector3(0, -0.055, 0))
	# Cushions.
	var cush := Color(0.07, 0.34, 0.15)
	_box(TABLE_X, 0.10, 0.06, cush, Vector3(0, 0.03, 0.50))
	_box(TABLE_X, 0.10, 0.06, cush, Vector3(0, 0.03, -0.50))
	_box(0.06, 0.10, TABLE_Z, cush, Vector3(1.00, 0.03, 0))
	_box(0.06, 0.10, TABLE_Z, cush, Vector3(-1.00, 0.03, 0))

	# Corner pockets: dark glowing holes.
	pocket_mat = GraphicsPolish.glow(Color(0.02, 0.02, 0.03), 0.4)
	for px in [-0.93, 0.93]:
		for pz in [-0.43, 0.43]:
			var pk := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = POCKET_R
			cm.bottom_radius = POCKET_R
			cm.height = 0.02
			pk.mesh = cm
			pk.material_override = pocket_mat
			pk.position = Vector3(px, 0.045, pz)
			table_root.add_child(pk)


func _pocket_centers() -> Array:
	return [Vector2(-0.93, -0.43), Vector2(0.93, -0.43),
		Vector2(-0.93, 0.43), Vector2(0.93, 0.43)]


func _spawn_ball(color: Color, p: Vector2, is_cue: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	mi.mesh = sm
	mi.material_override = GraphicsPolish.pbr_preset(color, "plastic")
	mi.position = Vector3(p.x, 0.04 + BALL_R, p.y)
	table_root.add_child(mi)
	if is_cue:
		mi.add_child(GraphicsPolish.make_trail(Color(1, 1, 1, 0.8), 0.03))
	balls.append({"node": mi, "p": p, "v": Vector2.ZERO,
		"sunk": false, "cue": is_cue, "color": color})


func _build_balls() -> void:
	_spawn_ball(Color(0.95, 0.95, 0.95), Vector2(0, 0.32), true)
	cue_idx = 0
	var cols := [Color(0.9, 0.15, 0.15), Color(0.95, 0.85, 0.15),
		Color(0.15, 0.3, 0.9), Color(0.6, 0.2, 0.8),
		Color(0.95, 0.5, 0.1), Color(0.15, 0.7, 0.3)]
	var spots := [Vector2(0, -0.20), Vector2(-0.055, -0.295), Vector2(0.055, -0.295),
		Vector2(-0.11, -0.39), Vector2(0, -0.39), Vector2(0.11, -0.39)]
	for i in 6:
		_spawn_ball(cols[i], spots[i], false)


func _build_cue_stick() -> void:
	cue_pivot = Node3D.new()
	table_root.add_child(cue_pivot)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.010
	cm.bottom_radius = 0.014
	cm.height = 1.1
	stick.mesh = cm
	stick.rotation.x = PI * 0.5
	stick.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.35, 0.18), "plastic")
	stick.position = Vector3(0, 0, 0.75)
	stick.name = "Stick"
	cue_pivot.add_child(stick)
	var guide := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.012, 0.006, 0.8)
	guide.mesh = gm
	guide_mat = GraphicsPolish.glow(Color(1.0, 0.95, 0.6), 1.4)
	guide.material_override = guide_mat
	guide.position = Vector3(0, 0, -0.55)
	guide.name = "Guide"
	cue_pivot.add_child(guide)
	cue_pivot.visible = false


func _build_ui() -> void:
	hud_label = GraphicsPolish.make_label("", 72, Color(0.9, 1.0, 0.9))
	hud_label.position = Vector3(-2.7, 2.4, 0.6)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 96, Color(1.0, 0.85, 0.4))
	msg_label.position = Vector3(0.0, 2.1, 0.2)
	add_child(msg_label)
	help_label = GraphicsPolish.make_label(
		"Aim with pointer, drag back & release\nto shoot. Power = drag distance.\nR: re-rack",
		48, Color(0.7, 0.8, 1.0))
	help_label.position = Vector3(2.7, 2.4, 0.6)
	add_child(help_label)


func _reset() -> void:
	state = "aim"
	shots = 0
	aiming = false
	cue_respot = false
	msg_label.text = ""
	var spots := [Vector2(0, 0.32), Vector2(0, -0.20), Vector2(-0.055, -0.295),
		Vector2(0.055, -0.295), Vector2(-0.11, -0.39), Vector2(0, -0.39), Vector2(0.11, -0.39)]
	for i in balls.size():
		var b: Dictionary = balls[i]
		b["p"] = spots[i]
		b["v"] = Vector2.ZERO
		b["sunk"] = false
		var n: Node3D = b["node"]
		n.visible = true
		n.position = Vector3(spots[i].x, 0.04 + BALL_R, spots[i].y)
		balls[i] = b
	ARUpgradeKit.save_anchor("ar-billiards_main", table_root.global_transform)


func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	if state == "aim":
		_poll_shoot()
	elif state == "rolling":
		_update_physics(delta)
	_update_ui()
	GraphicsPolish.pulse_glow(pocket_mat, 0.3, 0.25, _time, 2.0)
	GraphicsPolish.pulse_glow(guide_mat, 1.1, 0.6, _time, 5.0)


func _poll_keys() -> void:
	var down := Input.is_key_pressed(KEY_R)
	var was: bool = _prev_keys.get(KEY_R, false)
	if down and not was:
		_reset()
	_prev_keys[KEY_R] = down


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == "win":
			_reset()


# --- Aiming & shooting --------------------------------------------------------

func _table_plane_point(o: Vector3, d: Vector3) -> Variant:
	# Intersect the ray with the ball plane in table-local coords.
	var plane_y := table_root.global_position.y + 0.04 + BALL_R
	if absf(d.y) < 0.0001:
		return null
	var t := (plane_y - o.y) / d.y
	if t <= 0.0:
		return null
	var hit: Vector3 = o + d * t
	var local: Vector3 = table_root.global_transform.affine_inverse() * hit
	return Vector2(local.x, local.z)


func _aim_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if cam == null:
		return [Vector3.ZERO, Vector3(0, 0, -1)]
	var mp := get_viewport().get_mouse_position()
	return [cam.project_ray_origin(mp), cam.project_ray_normal(mp)]


func _poll_shoot() -> void:
	var edge := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	var held := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	var cue: Dictionary = balls[cue_idx]

	if edge and not aiming:
		var r := _aim_ray()
		var pt: Variant = _table_plane_point(r[0], r[1])
		if pt != null:
			aiming = true
			press_pt = pt
			var to: Vector2 = (pt - cue["p"]) as Vector2
			aim_dir = to.normalized() if to.length() > 0.05 else Vector2(0, -1)
			power = 0.0

	if aiming and held:
		var r2 := _aim_ray()
		var cur: Variant = _table_plane_point(r2[0], r2[1])
		if cur != null:
			power = clampf(press_pt.distance_to(cur) * 5.0, 0.0, MAX_POWER)
		_show_cue(cue)

	if aiming and not held:
		aiming = false
		cue_pivot.visible = false
		if power >= 0.15:
			cue["v"] = aim_dir * power
			balls[cue_idx] = cue
			shots += 1
			state = "rolling"
			GraphicsPolish.spawn_sparks(table_root,
				Vector3(cue["p"].x, 0.1, cue["p"].y), Color(1, 1, 1), 8)
		power = 0.0


func _show_cue(cue: Dictionary) -> void:
	var cp: Vector2 = cue["p"]
	cue_pivot.position = Vector3(cp.x, 0.04 + BALL_R, cp.y)
	var target := Vector3(cp.x + aim_dir.x, 0.04 + BALL_R, cp.y + aim_dir.y)
	cue_pivot.look_at(table_root.to_global(target), Vector3.UP)
	var stick: Node3D = cue_pivot.get_node("Stick")
	stick.position.z = 0.65 + power * 0.12
	cue_pivot.visible = true


# --- Physics ------------------------------------------------------------------

func _update_physics(delta: float) -> void:
	# Integrate.
	for b in balls:
		var bd: Dictionary = b
		if bd["sunk"]:
			continue
		var v: Vector2 = bd["v"]
		if v.length() > 0.0:
			bd["p"] = (bd["p"] as Vector2) + v * delta
			v *= maxf(0.0, 1.0 - FRICTION * delta)
			if v.length() < 0.02:
				v = Vector2.ZERO
			bd["v"] = v

	_collide_balls()
	_collide_cushions()
	_check_pockets()
	_sync_nodes()

	if _all_stopped():
		state = "aim"
		if cue_respot:
			_respot_cue()
			cue_respot = false
		_check_win()


func _collide_balls() -> void:
	for i in balls.size():
		var a: Dictionary = balls[i]
		if a["sunk"]:
			continue
		for j in range(i + 1, balls.size()):
			var b: Dictionary = balls[j]
			if b["sunk"]:
				continue
			var pa: Vector2 = a["p"]
			var pb: Vector2 = b["p"]
			var delta_p: Vector2 = pb - pa
			var dist := delta_p.length()
			if dist <= 0.0001 or dist >= BALL_R * 2.0:
				continue
			var n := delta_p / dist
			# Separate overlap.
			var overlap := BALL_R * 2.0 - dist
			a["p"] = pa - n * (overlap * 0.5)
			b["p"] = pb + n * (overlap * 0.5)
			# Equal-mass elastic: exchange normal velocity components.
			var va: Vector2 = a["v"]
			var vb: Vector2 = b["v"]
			var rel := (va - vb).dot(n)
			if rel > 0.0:
				a["v"] = va - n * rel
				b["v"] = vb + n * rel
				if rel > 1.0:
					var mid := (pa + pb) * 0.5
					GraphicsPolish.spawn_sparks(table_root,
						Vector3(mid.x, 0.1, mid.y), Color(1.0, 0.9, 0.5), 10)


func _collide_cushions() -> void:
	for b in balls:
		var bd: Dictionary = b
		if bd["sunk"]:
			continue
		var p: Vector2 = bd["p"]
		var v: Vector2 = bd["v"]
		if p.x < -HX:
			p.x = -HX
			v.x = absf(v.x) * 0.8
		elif p.x > HX:
			p.x = HX
			v.x = -absf(v.x) * 0.8
		if p.y < -HZ:
			p.y = -HZ
			v.y = absf(v.y) * 0.8
		elif p.y > HZ:
			p.y = HZ
			v.y = -absf(v.y) * 0.8
		bd["p"] = p
		bd["v"] = v


func _check_pockets() -> void:
	for b in balls:
		var bd: Dictionary = b
		if bd["sunk"]:
			continue
		var p: Vector2 = bd["p"]
		for pk in _pocket_centers():
			if p.distance_to(pk) < POCKET_R:
				bd["sunk"] = true
				bd["v"] = Vector2.ZERO
				var n: Node3D = bd["node"]
				n.visible = false
				GraphicsPolish.spawn_sparks(table_root,
					Vector3(p.x, 0.12, p.y), Color(0.4, 1.0, 0.6), 22)
				if bd["cue"]:
					cue_respot = true
					shots += 1 # scratch penalty
				break


func _sync_nodes() -> void:
	for b in balls:
		var bd: Dictionary = b
		if bd["sunk"]:
			continue
		var n: Node3D = bd["node"]
		var p: Vector2 = bd["p"]
		n.position = Vector3(p.x, 0.04 + BALL_R, p.y)


func _all_stopped() -> bool:
	for b in balls:
		var bd: Dictionary = b
		if not bd["sunk"] and (bd["v"] as Vector2).length() > 0.0:
			return false
	return true


func _respot_cue() -> void:
	var spot := Vector2(0, 0.32)
	for b in balls:
		var bd: Dictionary = b
		if bd["cue"] or bd["sunk"]:
			continue
		if (bd["p"] as Vector2).distance_to(spot) < BALL_R * 2.2:
			spot = Vector2(0.25, 0.32)
			break
	var cue: Dictionary = balls[cue_idx]
	cue["p"] = spot
	cue["v"] = Vector2.ZERO
	cue["sunk"] = false
	var n: Node3D = cue["node"]
	n.visible = true
	n.position = Vector3(spot.x, 0.04 + BALL_R, spot.y)
	balls[cue_idx] = cue


func _balls_left() -> int:
	var n := 0
	for b in balls:
		var bd: Dictionary = b
		if not bd["cue"] and not bd["sunk"]:
			n += 1
	return n


func _check_win() -> void:
	if _balls_left() == 0:
		state = "win"
		msg_label.text = "TABLE CLEARED!\n%d shots\nClick or R to re-rack" % shots
		GraphicsPolish.spawn_confetti(table_root, Vector3(0, 0.6, 0), 80)
		ARUpgradeKit.save_anchor("ar-billiards_main", table_root.global_transform)


func _update_ui() -> void:
	hud_label.text = "AR BILLIARDS\nShots: %d\nBalls left: %d" % [shots, _balls_left()]
	if state == "aim" and aiming:
		hud_label.text += "\nPower: %d%%" % int(power / MAX_POWER * 100.0)
