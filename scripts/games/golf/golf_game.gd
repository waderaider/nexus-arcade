## GolfGame.gd - main controller for Gravity Golf: Home Course.
## Sets up the course, ball, club, audio, and hole-in-one celebration.
extends Node3D
class_name GolfGame

var hole_data: GolfHoleData
var ball: GolfBall
var audio: GolfAudio
var celebration: HoleInOneCelebration
var club: GolfClub

var strokes := 0
var _hole_in_one_pending := false
var _anchor_timer := 0.0
# v0.7.0 RoomKit: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
# Course visual refs, so the hole can be re-seated on open floor.
var _green_node: MeshInstance3D = null
var _cup_node: MeshInstance3D = null
var _pole_node: MeshInstance3D = null
var _flag_node: MeshInstance3D = null
var _tee_node: MeshInstance3D = null
var _well_node: Node3D = null
var _portals_node: Node3D = null
var _obstacle_nodes: Array = []

func _ready() -> void:
	_setup_hole()
	_add_polish_light_rig()
	_build_course_visuals()
	_setup_ball()
	_setup_audio()
	_setup_club()
	_setup_celebration()
	_setup_ui()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 0.6, -0.1), 2.5, 30)
	ARUpgradeKit.apply_anchor(self, "golf_main")
	_apply_room_layout() # v0.7.0: seat the hole on open floor, cache walls

func _add_polish_light_rig() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)

func _process(delta: float) -> void:
	# Persist the course anchor every 30s so the hole stays put between sessions.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("golf_main", global_transform)
	# XR hand putt: pinch near the ball putts it toward the cup (mouse/club swing still works).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_try_pinch_putt()
	_room_bounce_ball() # v0.7.0: real wall planes stop the ball leaving the room

func _try_pinch_putt() -> void:
	if ball == null or not is_instance_valid(ball) or ball.is_holed:
		return
	if club == null or not is_instance_valid(club):
		return
	if club.global_position.distance_to(ball.global_position) > 0.35:
		return
	var dir := hole_data.cup_pos - ball.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	ball.set_velocity(dir * 2.5 + Vector3.UP * 0.4)
	_on_club_struck()

func _setup_hole() -> void:
	hole_data = GolfHoleData.new()
	hole_data.tee_pos = Vector3(0, 0.1, -2.0)
	hole_data.cup_pos = Vector3(0, 0.0, 1.8)
	hole_data.green_top_y = 0.0
	hole_data.ball_radius = 0.05
	hole_data.cup_radius = 0.09
	hole_data.play_rect = Rect2(-1.5, -2.8, 3.0, 5.6)
	# One obstacle: a small block in the middle.
	hole_data.obstacles.append(AABB(Vector3(-0.3, 0.0, -0.4), Vector3(0.6, 0.3, 0.3)))

func _build_course_visuals() -> void:
	# Green: a flat box.
	var green := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.2, 0.1, 5.8)
	green.mesh = box
	var gmat := GraphicsPolish.pbr_preset(Color(0.15, 0.45, 0.2), "matte")
	green.material_override = gmat
	green.position = Vector3(0, -0.05, -0.1)
	add_child(green)
	_green_node = green

	# Cup: dark cylinder hole marker + rim.
	var cup := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.02
	cup.mesh = cyl
	var cmat := GraphicsPolish.pbr(Color(0.02, 0.02, 0.02), 0.9, 0.4)
	cup.material_override = cmat
	cup.position = Vector3(hole_data.cup_pos.x, 0.005, hole_data.cup_pos.z)
	add_child(cup)
	_cup_node = cup

	# Flag pole.
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.01
	pcyl.bottom_radius = 0.01
	pcyl.height = 0.8
	pole.mesh = pcyl
	var pmat := GraphicsPolish.pbr(Color(0.9, 0.9, 0.9), 0.9, 0.25)
	pole.material_override = pmat
	pole.position = Vector3(hole_data.cup_pos.x, 0.4, hole_data.cup_pos.z)
	add_child(pole)
	_pole_node = pole

	var flag := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.25, 0.15, 0.01)
	flag.mesh = fbox
	var fmat := GraphicsPolish.glow(Color(1.0, 0.2, 0.2), 1.2)
	flag.material_override = fmat
	flag.position = Vector3(hole_data.cup_pos.x + 0.13, 0.72, hole_data.cup_pos.z)
	add_child(flag)
	_flag_node = flag

	# Tee marker.
	var tee := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.06
	tcyl.bottom_radius = 0.06
	tcyl.height = 0.01
	tee.mesh = tcyl
	var tmat := GraphicsPolish.pbr_preset(Color(0.9, 0.9, 0.9, 0.6), "glass")
	tee.material_override = tmat
	tee.position = Vector3(hole_data.tee_pos.x, 0.005, hole_data.tee_pos.z)
	add_child(tee)
	_tee_node = tee

	# Obstacle visual.
	for ob in hole_data.obstacles:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = ob.size
		m.mesh = b
		var omat := GraphicsPolish.pbr_preset(Color(0.6, 0.4, 0.2), "plastic")
		m.material_override = omat
		m.position = ob.get_center()
		add_child(m)
		_obstacle_nodes.append(m)

	# Gravity well.
	var well := GravityWell.new()
	well.position = Vector3(0.7, 0.0, 0.3)
	well.radius = 0.8
	well.strength = 2.5
	add_child(well)
	_well_node = well
	hole_data.wells.append(well)

	# Portals.
	var portals := PortalPair.new()
	add_child(portals)
	_portals_node = portals
	hole_data.portals = portals

func _setup_ball() -> void:
	ball = GolfBall.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	mesh.mesh = sphere
	var mat := GraphicsPolish.pbr(Color(1, 1, 1), 0.3, 0.35)
	mesh.material_override = mat
	ball.add_child(mesh)
	ball.add_child(GraphicsPolish.make_trail(Color(0.4, 0.9, 1.0), 0.04))
	add_child(ball)
	ball.configure(hole_data)
	ball.holed.connect(_on_ball_holed)
	ball.bounced.connect(_on_ball_bounced)
	ball.portal_used.connect(_on_portal_used)

func _setup_audio() -> void:
	audio = GolfAudio.new()
	add_child(audio)
	audio.bind_ball(ball)

func _setup_club() -> void:
	club = GolfClub.new()
	add_child(club)
	club.bind(ball, audio)
	club.struck.connect(_on_club_struck)

func _setup_celebration() -> void:
	celebration = HoleInOneCelebration.new()
	add_child(celebration)
	celebration.setup(audio)

func _setup_ui() -> void:
	var label := GraphicsPolish.make_label("Strokes: 0", 48)
	label.name = "StrokeLabel"
	label.position = Vector3(0, 1.2, -2.5)
	add_child(label)

func _on_ball_holed() -> void:
	audio.cup()
	if strokes == 1:
		# Hole in one!
		_hole_in_one_pending = true
		celebration.play(ball, hole_data.cup_pos, hole_data.green_top_y)
	_update_stroke_label()
	# Reset after a delay.
	await get_tree().create_timer(5.0).timeout
	if not _hole_in_one_pending:
		ball.reset_to_tee()
		ball.global_position = ARUpgradeKit.clamp_to_room(ball.global_position)
		strokes = 0
		_update_stroke_label()
	_hole_in_one_pending = false

func _on_ball_bounced(strength: float) -> void:
	audio.bounce(strength / 3.0)

func _on_portal_used() -> void:
	audio.portal()

func _on_club_struck() -> void:
	strokes += 1
	_update_stroke_label()
	audio.strike()
	if ball != null and is_instance_valid(ball):
		GraphicsPolish.spawn_sparks(self, ball.global_position, Color(1.0, 0.9, 0.4), 16)

func _update_stroke_label() -> void:
	var label := get_node_or_null("StrokeLabel") as Label3D
	if label:
		label.text = "Strokes: %d" % strokes


# ------------------------------------------------- v0.7.0 RoomKit ----
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not is_inside_tree() or not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# Seat the hole on open floor inside the room, keeping its shape.
	var cup_xz := Vector2(hole_data.cup_pos.x, hole_data.cup_pos.z)
	var shift := Vector3(_open_floor_spot(cup_xz).x - cup_xz.x, 0.0, _open_floor_spot(cup_xz).y - cup_xz.y)
	# Keep the whole play rect inside the room bounds.
	var r := hole_data.play_rect
	r.position += Vector2(shift.x, shift.z)
	var fix := Vector2.ZERO
	if r.position.x < _room_bounds.position.x:
		fix.x = _room_bounds.position.x - r.position.x
	elif r.end.x > _room_bounds.end.x:
		fix.x = _room_bounds.end.x - r.end.x
	if r.position.y < _room_bounds.position.y:
		fix.y = _room_bounds.position.y - r.position.y
	elif r.end.y > _room_bounds.end.y:
		fix.y = _room_bounds.end.y - r.end.y
	shift += Vector3(fix.x, 0.0, fix.y)
	if shift.length() > 0.01:
		hole_data.cup_pos += shift
		hole_data.tee_pos += shift
		hole_data.play_rect.position += Vector2(shift.x, shift.z)
		for i in hole_data.obstacles.size():
			var ob: AABB = hole_data.obstacles[i]
			ob.position += shift
			hole_data.obstacles[i] = ob
		for n in [_green_node, _cup_node, _pole_node, _flag_node, _tee_node, _well_node, _portals_node] + _obstacle_nodes:
			if n != null and is_instance_valid(n):
				(n as Node3D).position += shift
	# Real furniture becomes extra hole obstacles (resolved by GolfBall).
	for f_v in _room_furniture:
		if hole_data.obstacles.size() >= 8:
			break
		var f: Dictionary = f_v
		var c: Vector3 = f["position"]
		var s: Vector3 = f["size"]
		var aabb := AABB(c - s * 0.5, s)
		if aabb.has_point(hole_data.cup_pos) or aabb.has_point(hole_data.tee_pos):
			continue
		hole_data.obstacles.append(aabb)
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = s
		m.mesh = b
		m.material_override = GraphicsPolish.pbr_preset(Color(0.45, 0.32, 0.22), "plastic")
		m.position = c
		add_child(m)
		_obstacle_nodes.append(m)
	# v0.7.0 MORPH: rug becomes the enchanted fairway green (magic circle + glade glow).
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_rugs := RoomKit.get_anchors("RUG")
		if not _morph_rugs.is_empty():
			RoomKit.morph(_morph_rugs[0], "nature")


## Open floor point near `want`: clamped to the room, nudged out of furniture.
func _open_floor_spot(want: Vector2) -> Vector2:
	var p := want
	p.x = clampf(p.x, _room_bounds.position.x + 0.6, _room_bounds.end.x - 0.6)
	p.y = clampf(p.y, _room_bounds.position.y + 0.6, _room_bounds.end.y - 0.6)
	for f_v in _room_furniture:
		var f: Dictionary = f_v
		var c: Vector3 = f["position"]
		var s: Vector3 = f["size"]
		var hx := s.x * 0.5 + 0.6
		var hz := s.z * 0.5 + 0.6
		var dx := p.x - c.x
		var dz := p.y - c.z
		if absf(dx) < hx and absf(dz) < hz:
			if hx - absf(dx) < hz - absf(dz):
				p.x = c.x + (hx if dx >= 0.0 else -hx)
			else:
				p.y = c.z + (hz if dz >= 0.0 else -hz)
			p.x = clampf(p.x, _room_bounds.position.x + 0.6, _room_bounds.end.x - 0.6)
			p.y = clampf(p.y, _room_bounds.position.y + 0.6, _room_bounds.end.y - 0.6)
	return p


## Normal-sign agnostic wall reflection (world space).
func _bounce_walls(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		var d: float = (pos - w["position"]).dot(n)
		if absf(d) < radius and vel.dot(n) * signf(d) < 0.0:
			vel = vel - 2.0 * vel.dot(n) * n
	return vel


func _room_bounce_ball() -> void:
	if _room_walls.is_empty():
		return
	if ball == null or not is_instance_valid(ball) or ball.is_holed:
		return
	var wvel: Vector3 = global_transform.basis * ball.velocity
	wvel = _bounce_walls(ball.global_position, wvel, hole_data.ball_radius)
	ball.velocity = global_transform.basis.inverse() * wvel
