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

	var flag := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.25, 0.15, 0.01)
	flag.mesh = fbox
	var fmat := GraphicsPolish.glow(Color(1.0, 0.2, 0.2), 1.2)
	flag.material_override = fmat
	flag.position = Vector3(hole_data.cup_pos.x + 0.13, 0.72, hole_data.cup_pos.z)
	add_child(flag)

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

	# Gravity well.
	var well := GravityWell.new()
	well.position = Vector3(0.7, 0.0, 0.3)
	well.radius = 0.8
	well.strength = 2.5
	add_child(well)
	hole_data.wells.append(well)

	# Portals.
	var portals := PortalPair.new()
	add_child(portals)
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
