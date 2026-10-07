## SpellDuel: gesture spellcasting duel vs an AI wizard.
## Draw gestures with the pointer (hold the mouse button, or pinch in XR):
##   CIRCLE motion            -> fireball (projectile at the AI wizard)
##   ZIGZAG motion            -> lightning (instant line damage)
##   fast straight FLICK/PUSH -> force shield (blocks for 3s)
## Gesture recognition tracks the pointer path over 0.6s windows and
## classifies by closure, curvature and direction changes. The AI wizard
## strafes and fires back. Deplete its HP to win.
## Score = wins * 100 + style points. R restarts.
extends Node3D

const AI_MAX_HP := 100.0
const PLAYER_MAX_HP := 100.0
const GESTURE_WINDOW := 0.6
const CAST_COOLDOWN := 0.8
const FIREBALL_DMG := 22.0
const LIGHTNING_DMG := 14.0
const AI_FIREBALL_DMG := 12.0
const SHIELD_TIME := 3.0
const AI_CAST_MIN := 2.0
const AI_CAST_MAX := 3.4
const FIREBALL_SPEED := 6.0
const PLAYER_POS := Vector3(0.0, 1.3, 1.2)

var camera: Camera3D = null
var ai_hp := AI_MAX_HP
var player_hp := PLAYER_MAX_HP
var wins := 0
var style_score := 0.0
var state := "playing"
var wizard: Node3D = null
var wizard_mat: StandardMaterial3D = null
var wizard_hat_mat: StandardMaterial3D = null
var staff_tip: MeshInstance3D = null
var player_marker: MeshInstance3D = null
var shield_bubble: MeshInstance3D = null
var shield_mat: StandardMaterial3D = null
var shield_t := 0.0
var player_hp_fg: MeshInstance3D = null
var ai_hp_fg: MeshInstance3D = null
var hud_label: Label3D = null
var hint_label: Label3D = null
var msg_label: Label3D = null
var gesture_cursor: MeshInstance3D = null
var gesture_line: MeshInstance3D = null
var gesture_im := ImmediateMesh.new()
var drawing := false
var path: Array = []
var path_t0 := 0.0
var cast_cd := 0.0
var fireballs: Array = []
var bolts: Array = []
var ai_cast_t := 2.5
var ai_phase := 0.0
var elapsed := 0.0

# v0.7.0 RoomKit: the AI wizard holds the real far wall; fireballs bounce
# off real wall planes. Cached; default layout without room data.
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _wizard_base_z := -3.0
var _ai_x_range := 1.3


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	_place_wizard_at_wall()
	# v0.7.0 MORPH: rug becomes the arcane duel circle.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_rugs := RoomKit.get_anchors("RUG")
		if not _morph_rugs.is_empty():
			RoomKit.morph(_morph_rugs[0], "arcane")


## The AI wizard duels from the real far wall; its strafe fits the wall width.
func _place_wizard_at_wall() -> void:
	var best: Dictionary = _room_walls[0]
	for w in _room_walls:
		if float(w["position"].z) < float(best["position"].z):
			best = w
	var n: Vector3 = best["normal"]
	var side := signf((Vector3(0, 1.2, 1.2) - best["position"]).dot(n))
	if side == 0.0:
		side = 1.0
	_wizard_base_z = clampf(float(best["position"].z) + n.z * side * 0.6, -4.5, -1.5)
	_ai_x_range = clampf(float(best["size"].x) * 0.5 - 0.3, 1.0, 2.5)
	if wizard != null and is_instance_valid(wizard):
		wizard.position = to_local(Vector3(0.0, 0.0, _wizard_base_z))


## Normal-sign agnostic wall reflection.
func _bounce_walls(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		var d: float = (pos - w["position"]).dot(n)
		if absf(d) < radius and vel.dot(n) * signf(d) < 0.0:
			vel = vel - 2.0 * vel.dot(n) * n
	return vel


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "spell-duel_main")
	_ensure_camera()
	_ensure_env()
	_ensure_light()
	_build_arena()
	_build_wizard()
	_build_player()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -1.0), 2.2, 40)
	_reset()
	_apply_room_layout()


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.7, 3.4)
		cam.look_at(Vector3(0.0, 1.2, -1.0), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.55)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _build_arena() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.12), "matte")
	add_child(floor_inst)
	# Duel ring circle.
	for i in range(24):
		var a := TAU * i / 24.0
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.06
		dot.mesh = sm
		dot.material_override = GraphicsPolish.glow(Color(0.5, 0.3, 1.0), 1.2)
		dot.position = Vector3(cos(a) * 2.2, 0.02, -0.8 + sin(a) * 2.2)
		add_child(dot)


func _build_wizard() -> void:
	wizard = Node3D.new()
	wizard.name = "Wizard"
	wizard.position = Vector3(0.0, 0.0, -3.0)
	add_child(wizard)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.3
	body.mesh = cap
	wizard_mat = GraphicsPolish.pbr_preset(Color(0.45, 0.2, 0.8), "plastic")
	body.material_override = wizard_mat
	body.position = Vector3(0.0, 1.0, 0.0)
	wizard.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	head.mesh = hm
	head.material_override = GraphicsPolish.pbr(Color(0.9, 0.75, 0.6), 0.0, 0.6)
	head.position = Vector3(0.0, 1.85, 0.0)
	wizard.add_child(head)
	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.26
	cone.height = 0.55
	hat.mesh = cone
	wizard_hat_mat = GraphicsPolish.glow(Color(0.6, 0.25, 1.0), 1.4)
	hat.material_override = wizard_hat_mat
	hat.position = Vector3(0.0, 2.2, 0.0)
	wizard.add_child(hat)
	var staff := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.4
	staff.mesh = cyl
	staff.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
	staff.position = Vector3(0.45, 1.1, 0.0)
	wizard.add_child(staff)
	staff_tip = MeshInstance3D.new()
	var tipm := SphereMesh.new()
	tipm.radius = 0.07
	tipm.height = 0.14
	staff_tip.mesh = tipm
	staff_tip.material_override = GraphicsPolish.glow(Color(1.0, 0.4, 0.8), 2.0)
	staff_tip.position = Vector3(0.45, 1.85, 0.0)
	wizard.add_child(staff_tip)
	ai_hp_fg = _make_hp_bar(wizard, Vector3(0.0, 2.65, 0.0), Color(1.0, 0.25, 0.25))


func _build_player() -> void:
	player_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.3
	player_marker.mesh = ring
	player_marker.material_override = GraphicsPolish.glow(Color(0.3, 0.9, 1.0), 1.6)
	player_marker.position = Vector3(PLAYER_POS.x, 0.03, PLAYER_POS.z)
	add_child(player_marker)
	player_hp_fg = _make_hp_bar(self, Vector3(PLAYER_POS.x, 2.1, PLAYER_POS.z), Color(0.25, 1.0, 0.4))
	shield_bubble = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	shield_bubble.mesh = sm
	shield_mat = GraphicsPolish.pbr_preset(Color(0.4, 0.9, 1.0), "glass")
	shield_bubble.material_override = shield_mat
	shield_bubble.position = PLAYER_POS
	shield_bubble.visible = false
	add_child(shield_bubble)
	# Gesture drawing cursor.
	gesture_cursor = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.035
	cm.height = 0.07
	gesture_cursor.mesh = cm
	gesture_cursor.material_override = GraphicsPolish.glow(Color(1.0, 0.9, 0.3), 2.0)
	gesture_cursor.visible = false
	add_child(gesture_cursor)
	gesture_cursor.add_child(GraphicsPolish.make_trail(Color(1.0, 0.85, 0.3), 0.05))
	gesture_line = MeshInstance3D.new()
	gesture_line.mesh = gesture_im
	gesture_line.material_override = GraphicsPolish.glow(Color(1.0, 0.85, 0.3), 1.6)
	add_child(gesture_line)


func _make_hp_bar(parent: Node3D, pos: Vector3, color: Color) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(1.1, 0.12, 0.02)
	bg.mesh = bgm
	var bgmat := GraphicsPolish.pbr(Color(0.1, 0.1, 0.1), 0.0, 0.8)
	bgmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bgmat
	bg.position = pos
	parent.add_child(bg)
	var fg := MeshInstance3D.new()
	var fgm := BoxMesh.new()
	fgm.size = Vector3(1.0, 0.08, 0.03)
	fg.mesh = fgm
	var fmat := GraphicsPolish.glow(color, 1.4)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg.material_override = fmat
	fg.position = pos
	parent.add_child(fg)
	return fg


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 56, Color(1, 1, 1))
	hud_label.position = Vector3(0.0, 2.9, -1.6)
	add_child(hud_label)
	hint_label = GraphicsPolish.make_label("Draw: CIRCLE=fireball  ZIGZAG=lightning  FLICK=shield", 36, Color(0.8, 0.9, 1.0))
	hint_label.position = Vector3(0.0, 0.35, 0.4)
	add_child(hint_label)
	msg_label = GraphicsPolish.make_label("", 84, Color(1.0, 0.9, 0.3))
	msg_label.position = Vector3(0.0, 1.9, -1.2)
	add_child(msg_label)


func _reset() -> void:
	ai_hp = AI_MAX_HP
	player_hp = PLAYER_MAX_HP
	state = "playing"
	shield_t = 0.0
	shield_bubble.visible = false
	path.clear()
	drawing = false
	cast_cd = 0.0
	ai_cast_t = 2.5
	for f in fireballs:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	fireballs.clear()
	for b in bolts:
		if is_instance_valid(b["node"]):
			b["node"].queue_free()
	bolts.clear()
	msg_label.text = ""
	_update_hud()


func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_key_pressed(KEY_R):
		_reset()
	if state == "playing":
		cast_cd = maxf(0.0, cast_cd - delta)
		_update_gesture(delta)
		_update_fireballs(delta)
		_update_bolts(delta)
		_ai_logic(delta)
		if shield_t > 0.0:
			shield_t -= delta
			if shield_t <= 0.0:
				shield_bubble.visible = false
		shield_bubble.visible = shield_t > 0.0
		if ai_hp <= 0.0:
			_win()
		elif player_hp <= 0.0:
			_lose()
	# Juice.
	GraphicsPolish.pulse_glow(wizard_hat_mat, 1.2, 0.8, elapsed, 2.5)
	if shield_bubble.visible:
		GraphicsPolish.pulse_glow(shield_mat, 0.8, 0.5, elapsed, 5.0)
	_update_hud()


func _update_hud() -> void:
	var score := int(wins * 100 + style_score)
	hud_label.text = "YOU %d   WIZARD %d   |   Wins %d   Score %d" % [int(player_hp), int(ai_hp), wins, score]
	if player_hp_fg != null:
		player_hp_fg.scale.x = clampf(player_hp / PLAYER_MAX_HP, 0.01, 1.0)
	if ai_hp_fg != null:
		ai_hp_fg.scale.x = clampf(ai_hp / AI_MAX_HP, 0.01, 1.0)


## Pointer position on the gesture plane (desktop) or the XR hand (XR).
func _gesture_pointer() -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.4)
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var fwd := -camera.global_transform.basis.z
	var plane_p: Vector3 = camera.global_position + fwd * 1.4
	var denom := dir.dot(fwd)
	if absf(denom) < 0.0001:
		return plane_p
	var t := (plane_p - origin).dot(fwd) / denom
	return origin + dir * t


func _is_drawing() -> bool:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _update_gesture(_delta: float) -> void:
	var want := _is_drawing()
	var pt := _gesture_pointer()
	if want and not drawing:
		drawing = true
		path.clear()
		path_t0 = elapsed
		gesture_cursor.visible = true
	if drawing:
		gesture_cursor.position = pt
		if path.is_empty() or path[path.size() - 1].distance_to(pt) > 0.02:
			path.append(pt)
		# Cull samples older than the window.
		while path.size() > 2 and elapsed - path_t0 > GESTURE_WINDOW:
			path.pop_front()
			path_t0 += 1.0 / 30.0
		_draw_path_line()
		# Chained casting: classify each full window while still drawing.
		if elapsed - path_t0 >= GESTURE_WINDOW and path.size() >= 6:
			_cast_from_path()
			path.clear()
			path_t0 = elapsed
	if not want and drawing:
		drawing = false
		gesture_cursor.visible = false
		gesture_im.clear_surfaces()
		if path.size() >= 6:
			_cast_from_path()
		path.clear()


func _draw_path_line() -> void:
	gesture_im.clear_surfaces()
	if path.size() < 2:
		return
	gesture_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in path:
		gesture_im.surface_add_vertex(p)
	gesture_im.surface_end()


func _cast_from_path() -> void:
	if cast_cd > 0.0 or state != "playing":
		return
	var res: Dictionary = _classify(path)
	var kind: String = res["kind"]
	if kind == "none":
		return
	cast_cd = CAST_COOLDOWN
	var style: float = res["style"]
	match kind:
		"fireball":
			_cast_fireball(true)
			style_score += 10.0 + style * 20.0
		"lightning":
			_cast_lightning()
			style_score += 12.0 + style * 18.0
		"shield":
			_activate_shield()
			style_score += 8.0 + style * 10.0


func _classify(pts: Array) -> Dictionary:
	var res := {"kind": "none", "style": 0.0}
	var n: int = pts.size()
	if n < 6:
		return res
	var total := 0.0
	var dir_changes := 0
	var prev_dir := Vector3.ZERO
	var minp: Vector3 = pts[0]
	var maxp: Vector3 = pts[0]
	for i in range(1, n):
		var d: Vector3 = pts[i] - pts[i - 1]
		var dl := d.length()
		total += dl
		if dl > 0.005:
			if prev_dir != Vector3.ZERO and prev_dir.angle_to(d) > deg_to_rad(60.0):
				dir_changes += 1
			prev_dir = d.normalized()
		minp.x = minf(minp.x, pts[i].x)
		minp.y = minf(minp.y, pts[i].y)
		minp.z = minf(minp.z, pts[i].z)
		maxp.x = maxf(maxp.x, pts[i].x)
		maxp.y = maxf(maxp.y, pts[i].y)
		maxp.z = maxf(maxp.z, pts[i].z)
	var closure: float = pts[0].distance_to(pts[n - 1])
	var dur := maxf(elapsed - path_t0, 0.05)
	var speed := total / dur
	var w := maxp.x - minp.x
	var h := maxp.y - minp.y
	var aspect := w / maxf(h, 0.001)
	# PUSH: fast straight flick.
	var push_z: float = pts[n - 1].z - pts[0].z
	if (push_z < -0.35 and speed > 1.2) or (speed > 2.6 and total > 0.5 and dir_changes <= 1):
		res["kind"] = "shield"
		res["style"] = clampf(speed / 4.0, 0.0, 1.0)
		return res
	# CIRCLE: closed loop, roughly square bounds.
	if total < 0.7:
		return res
	if closure / total < 0.30 and total > 0.9 and aspect > 0.45 and aspect < 2.2:
		res["kind"] = "fireball"
		res["style"] = 1.0 - closure / total
		return res
	# ZIGZAG: many sharp direction changes.
	if dir_changes >= 4:
		res["kind"] = "lightning"
		res["style"] = clampf(dir_changes / 8.0, 0.0, 1.0)
		return res
	return res


func _spawn_fireball(from: Vector3, to: Vector3, from_player: bool) -> void:
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	node.mesh = sm
	var col := Color(1.0, 0.55, 0.15) if from_player else Color(1.0, 0.3, 0.75)
	node.material_override = GraphicsPolish.glow(col, 2.2)
	node.position = from
	node.add_child(GraphicsPolish.make_trail(col, 0.07))
	add_child(node)
	var dir := (to - from).normalized()
	fireballs.append({"node": node, "vel": dir * FIREBALL_SPEED, "from_player": from_player})


func _cast_fireball(from_player: bool) -> void:
	_spawn_fireball(PLAYER_POS + Vector3(0, 0.2, 0), wizard.position + Vector3(0, 1.2, 0), true)


func _cast_lightning() -> void:
	var a := PLAYER_POS + Vector3(0, 0.3, 0)
	var b := wizard.position + Vector3(0, 1.2, 0)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 12
	for i in range(segs + 1):
		var p := a.lerp(b, i / float(segs))
		if i > 0 and i < segs:
			p += Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.1, 0.1))
		im.surface_add_vertex(p)
	im.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = im
	inst.material_override = GraphicsPolish.glow(Color(0.6, 0.9, 1.0), 2.5)
	add_child(inst)
	bolts.append({"node": inst, "t": 0.18})
	GraphicsPolish.spawn_sparks(self, b, Color(0.6, 0.9, 1.0), 30)
	_damage_ai(LIGHTNING_DMG)


func _activate_shield() -> void:
	shield_t = SHIELD_TIME
	shield_bubble.visible = true
	GraphicsPolish.spawn_sparks(self, PLAYER_POS, Color(0.4, 0.9, 1.0), 20)


func _update_fireballs(delta: float) -> void:
	var wiz_c := wizard.position + Vector3(0, 1.2, 0)
	for i in range(fireballs.size() - 1, -1, -1):
		var f: Dictionary = fireballs[i]
		var node: MeshInstance3D = f["node"]
		if not is_instance_valid(node):
			fireballs.remove_at(i)
			continue
		node.position += f["vel"] * delta
		# v0.7.0 RoomKit: fireballs ricochet off real wall planes.
		if not _room_walls.is_empty():
			var gp: Vector3 = to_global(node.position)
			var gv: Vector3 = global_transform.basis * (f["vel"] as Vector3)
			var nv: Vector3 = _bounce_walls(gp, gv, 0.15)
			if nv != gv:
				f["vel"] = global_transform.basis.inverse() * nv
				GraphicsPolish.spawn_sparks(self, gp, Color(1.0, 0.7, 0.3), 6)
		var p := node.position
		var from_player: bool = f["from_player"]
		if from_player:
			if p.distance_to(wiz_c) < 0.45:
				_damage_ai(FIREBALL_DMG)
				GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.55, 0.15), 28)
				node.queue_free()
				fireballs.remove_at(i)
			elif p.distance_to(wiz_c) > 12.0:
				node.queue_free()
				fireballs.remove_at(i)
		else:
			if shield_t > 0.0 and p.distance_to(PLAYER_POS) < 0.7:
				GraphicsPolish.spawn_sparks(self, p, Color(0.4, 0.9, 1.0), 16)
				node.queue_free()
				fireballs.remove_at(i)
			elif p.distance_to(PLAYER_POS) < 0.4:
				_damage_player(AI_FIREBALL_DMG)
				GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.3, 0.75), 24)
				node.queue_free()
				fireballs.remove_at(i)
			elif p.distance_to(PLAYER_POS) > 12.0:
				node.queue_free()
				fireballs.remove_at(i)


func _update_bolts(delta: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			if is_instance_valid(b["node"]):
				b["node"].queue_free()
			bolts.remove_at(i)


func _ai_logic(delta: float) -> void:
	ai_phase += delta
	wizard.position.x = _ai_x_range * sin(ai_phase * 0.7)
	ai_cast_t -= delta
	if ai_cast_t <= 0.0:
		ai_cast_t = randf_range(AI_CAST_MIN, AI_CAST_MAX)
		GraphicsPolish.spawn_sparks(self, wizard.position + Vector3(0.45, 1.85, 0), Color(1.0, 0.4, 0.8), 10)
		_spawn_fireball(wizard.position + Vector3(0, 1.4, 0), PLAYER_POS, false)


func _damage_ai(dmg: float) -> void:
	ai_hp = maxf(0.0, ai_hp - dmg)


func _damage_player(dmg: float) -> void:
	player_hp = maxf(0.0, player_hp - dmg)
	GraphicsPolish.spawn_sparks(self, PLAYER_POS, Color(1.0, 0.2, 0.2), 12)


func _win() -> void:
	state = "win"
	wins += 1
	style_score += 50.0
	msg_label.text = "VICTORY!  (R for rematch)"
	GraphicsPolish.spawn_confetti(self, wizard.position + Vector3(0, 1.5, 0), 80)
	ARUpgradeKit.save_anchor("spell-duel_main", global_transform)


func _lose() -> void:
	state = "gameover"
	msg_label.text = "DEFEATED  (R to retry)"
