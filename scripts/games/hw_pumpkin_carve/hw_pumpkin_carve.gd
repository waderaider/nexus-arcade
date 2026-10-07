extends Node3D
## HwPumpkinCarve - "Pumpkin Carve": a big pumpkin floats before you.
## Trace the glowing carve dots with your fingertip (pointer ray):
## mouse on desktop, hand pointer in XR. Complete all waypoints of a face
## to carve it, then finish all 3 faces to light the jack-o-lantern.
## 90 seconds. R restarts; pinch-hold 1s on the results screen restarts.

const ROUND_LENGTH := 90.0
const PUMPKIN_RADIUS := 0.55
const TRACE_RADIUS := 0.15
const FACE_YAWS := [0.0, TAU / 3.0, TAU * 2.0 / 3.0]

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var round_time := 0.0
var pumpkin_center := Vector3(0.0, 1.25, -2.0)
var faces: Array = [] # dicts: yaw, waypoints(Array[Vector3]), idx, done, dots(Array)
var faces_done := 0
var inner_light: OmniLight3D = null
var dot_pending_mat: StandardMaterial3D = null
var dot_done_mat: StandardMaterial3D = null
var carve_mat: StandardMaterial3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var mouse_pos := Vector2.ZERO
var trace_player: AudioStreamPlayer = null
var face_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var msg_timer := 0.0
var anchor_timer := 0.0
var restart_hold := 0.0

# RoomKit v0.7.0: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _room_known := false
# pumpkin_center stays the STAGE-LOCAL pumpkin center; the stage node
# carries the room offset so the trace math never changes frames.
var pumpkin_stage: Node3D = null


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	mouse_pos = get_viewport().get_visible_rect().size * 0.5
	dot_pending_mat = GraphicsPolish.glow(Color(1.0, 0.55, 0.1), 2.2)
	dot_done_mat = GraphicsPolish.glow(Color(0.3, 0.9, 0.4), 0.4)
	carve_mat = GraphicsPolish.glow(Color(1.0, 0.62, 0.12), 2.5)
	pumpkin_stage = Node3D.new()
	pumpkin_stage.name = "PumpkinStage"
	add_child(pumpkin_stage)
	_build_pumpkin()
	_build_faces()
	_build_hud()
	trace_player = _make_player(_make_tone(500.0, 0.07, 0.45))
	face_player = _make_player(_make_tone(660.0, 0.25, 0.55))
	win_player = _make_player(_make_tone(880.0, 0.6, 0.5))
	ARUpgradeKit.apply_anchor(self, "hw_pumpkin_carve_main")
	GraphicsPolish.spawn_ambient_motes(self, pumpkin_center, 2.5, 50)
	_apply_room_layout()


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	_room_known = true
	# Float the pumpkin at a clear spot inside the real room.
	var c := _room_bounds.get_center()
	var m := 1.0
	var nx := c.x
	var nz := c.y
	if _room_bounds.size.x > m * 2.0:
		nx = clampf(c.x, _room_bounds.position.x + m, _room_bounds.end.x - m)
	if _room_bounds.size.y > m * 2.0:
		nz = clampf(c.y, _room_bounds.position.y + m, _room_bounds.end.y - m)
	var target := _clear_of_furniture(Vector3(nx, 0.0, nz), 0.9)
	pumpkin_stage.position = Vector3(target.x - pumpkin_center.x, 0.0, target.z - pumpkin_center.z)
	# v0.7.0 furniture morph: the real table becomes a haunted carving
	# altar, and the pumpkin is served on its top face so players carve
	# at real table height.
	var table_anchors := RoomKit.get_anchors("TABLE")
	if not table_anchors.is_empty():
		var tanchor: Dictionary = table_anchors[0]
		RoomKit.morph(tanchor, "haunted")
		var top: Vector3 = RoomKit.cuboid_top(tanchor)
		pumpkin_stage.position = Vector3(
			top.x - pumpkin_center.x, top.y - pumpkin_center.y, top.z - pumpkin_center.z)


func _clear_of_furniture(p: Vector3, clearance: float) -> Vector3:
	for f_v in _room_tables + _room_furniture:
		var f: Dictionary = f_v
		var fp: Vector3 = f["position"]
		var fs: Vector3 = f["size"]
		if absf(p.x - fp.x) < fs.x * 0.5 + clearance and absf(p.z - fp.z) < fs.z * 0.5 + clearance:
			var dx := p.x - fp.x
			var dz := p.z - fp.z
			if absf(dx) > absf(dz):
				var s := signf(dx)
				p.x = fp.x + (s if s != 0.0 else 1.0) * (fs.x * 0.5 + clearance)
			else:
				var s2 := signf(dz)
				p.z = fp.z + (s2 if s2 != 0.0 else 1.0) * (fs.z * 0.5 + clearance)
	return p


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.5, 1.4)
	add_child(camera)
	camera.look_at(pumpkin_center, Vector3.UP)
	camera.current = true


func _build_pumpkin() -> void:
	var p := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = PUMPKIN_RADIUS
	s.height = PUMPKIN_RADIUS * 2.0
	p.mesh = s
	p.scale = Vector3(1.0, 0.85, 1.0)
	p.position = pumpkin_center
	p.material_override = GraphicsPolish.pbr(Color(0.92, 0.45, 0.08), 0.0, 0.55)
	pumpkin_stage.add_child(p)
	# Ribs: a few darker vertical tori for pumpkin shape.
	for i in range(6):
		var rib := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = PUMPKIN_RADIUS * 0.97
		tor.outer_radius = PUMPKIN_RADIUS * 1.0
		rib.mesh = tor
		rib.material_override = GraphicsPolish.pbr(Color(0.75, 0.35, 0.06), 0.0, 0.6)
		rib.position = pumpkin_center
		rib.scale = Vector3(1.0, 0.85, 1.0)
		rib.rotation.y = float(i) * PI / 6.0
		pumpkin_stage.add_child(rib)
	# Stem.
	var stem := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.05
	sc.bottom_radius = 0.08
	sc.height = 0.25
	stem.mesh = sc
	stem.position = pumpkin_center + Vector3(0.0, PUMPKIN_RADIUS * 0.85 + 0.10, 0.0)
	stem.material_override = GraphicsPolish.pbr(Color(0.25, 0.45, 0.15), 0.0, 0.7)
	pumpkin_stage.add_child(stem)
	# Inner jack-o-lantern light (ramps up per carved face).
	inner_light = GraphicsPolish.make_point_light(pumpkin_stage, pumpkin_center, Color(1.0, 0.55, 0.15), 0.0, 3.0)


func _face_point(yaw: float, ha: float, va: float) -> Vector3:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := (fwd + right * tan(ha) + Vector3.UP * tan(va)).normalized()
	return pumpkin_center + dir * (PUMPKIN_RADIUS * 1.04)


func _build_faces() -> void:
	for yaw in FACE_YAWS:
		var waypoints: Array = []
		# Two triangle eyes.
		for ex in [-0.38, 0.38]:
			for k in range(3):
				var a := float(k) * TAU / 3.0
				waypoints.append(_face_point(yaw, ex + 0.13 * cos(a), 0.18 + 0.13 * sin(a)))
		# Zigzag mouth: 5 points.
		for k in range(5):
			var ha := lerpf(-0.45, 0.45, float(k) / 4.0)
			var va := -0.28 + (0.07 if k % 2 == 0 else -0.07)
			waypoints.append(_face_point(yaw, ha, va))
		var dots: Array = []
		for wp_v in waypoints:
			var wp: Vector3 = wp_v
			var dot := MeshInstance3D.new()
			var ds := SphereMesh.new()
			ds.radius = 0.035
			ds.height = 0.07
			dot.mesh = ds
			dot.material_override = dot_pending_mat
			dot.position = wp
			pumpkin_stage.add_child(dot)
			dots.append(dot)
		faces.append({"yaw": yaw, "waypoints": waypoints, "idx": 0, "done": false, "dots": dots})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("PUMPKIN CARVE", 44, Color(1.0, 0.7, 0.25))
	hud_label.position = Vector3(-2.7, 2.7, -0.4)
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 80, Color(1.0, 0.9, 0.4))
	msg_label.position = Vector3(0.0, 2.35, -2.0)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("Trace the GLOWING DOTS with your fingertip!  R: restart", 30, Color(0.8, 0.85, 0.95))
	help.position = Vector3(0.0, 0.35, -0.4)
	add_child(help)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_pos = mb.position


func _aim_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return [pumpkin_center + Vector3(0, 0, 3), Vector3(0, 0, -1)]
	var o := camera.project_ray_origin(mouse_pos)
	var d := camera.project_ray_normal(mouse_pos)
	return [o, d.normalized()]


func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t > 0.0 else -1.0


func _process(delta: float) -> void:
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_pumpkin_carve_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			restart_hold += delta
			if restart_hold >= 1.0:
				_reset_game()
				return
		else:
			restart_hold = 0.0
		return
	round_time += delta
	if round_time >= ROUND_LENGTH:
		_game_over(false)
		return
	_trace_pointer()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _active_face() -> Dictionary:
	for f_v in faces:
		var f: Dictionary = f_v
		if not bool(f["done"]):
			return f
	return {}


func _trace_pointer() -> void:
	var f := _active_face()
	if f.is_empty():
		return
	var ray := _aim_ray()
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	# Trace in the pumpkin stage's frame (identical to world when unmoved).
	var lo: Vector3 = pumpkin_stage.to_local(o) if pumpkin_stage != null else o
	var t := _ray_sphere(lo, d, pumpkin_center, PUMPKIN_RADIUS * 1.15)
	if t < 0.0:
		return
	var hit := lo + d * t
	var wps: Array = f["waypoints"]
	var idx := int(f["idx"])
	if idx >= wps.size():
		return
	var wp: Vector3 = wps[idx]
	if hit.distance_to(wp) < TRACE_RADIUS:
		f["idx"] = idx + 1
		var dots: Array = f["dots"]
		(dots[idx] as MeshInstance3D).material_override = dot_done_mat
		GraphicsPolish.spawn_sparks(self, pumpkin_stage.to_global(wp), Color(1.0, 0.7, 0.2), 8)
		if trace_player != null:
			trace_player.pitch_scale = 0.9 + float(idx) * 0.04
			trace_player.play()
		if int(f["idx"]) >= wps.size():
			_complete_face(f)


func _complete_face(f: Dictionary) -> void:
	f["done"] = true
	faces_done += 1
	var yaw := float(f["yaw"])
	# Light up the carved eyes + mouth.
	for ex in [-0.38, 0.38]:
		_add_carve_glow(_face_point(yaw, ex, 0.18), 0.10)
	for k in range(5):
		var ha := lerpf(-0.45, 0.45, float(k) / 4.0)
		_add_carve_glow(_face_point(yaw, ha, -0.28), 0.07)
	if inner_light != null:
		inner_light.light_energy = 0.9 * float(faces_done)
	_show_msg("FACE %d/3 CARVED!" % faces_done, 1.2)
	GraphicsPolish.spawn_sparks(self, pumpkin_stage.to_global(pumpkin_center + Vector3(0, 0.2, 0)), Color(1.0, 0.6, 0.15), 24)
	if face_player != null:
		face_player.play()
	if faces_done >= 3:
		_game_over(true)


func _add_carve_glow(pos: Vector3, r: float) -> void:
	var g := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	g.mesh = s
	g.scale = Vector3(1.0, 1.0, 0.45)
	g.material_override = carve_mat
	g.position = pos
	pumpkin_stage.add_child(g)
	# Face outward from the pumpkin (stage only translates, so the local
	# outward direction is valid in global space too).
	g.look_at(g.global_position + (pos - pumpkin_center).normalized(), Vector3.UP)


func _show_msg(text: String, duration: float) -> void:
	msg_label.text = text
	msg_timer = duration


func _update_hud() -> void:
	var left := int(maxf(0.0, ROUND_LENGTH - round_time))
	var prog := ""
	var f := _active_face()
	if not f.is_empty():
		var wps: Array = f["waypoints"]
		prog = "Dots: %d/%d" % [int(f["idx"]), wps.size()]
	hud_label.text = "PUMPKIN CARVE\nFaces: %d/3   %s\nTime: %ds" % [faces_done, prog, left]


func _game_over(did_win: bool) -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_pumpkin_carve_main", global_transform)
	if did_win:
		var final := maxi(500, int(3000.0 - round_time * 10.0))
		_show_msg("JACK-O-LANTERN LIT!\nScore: %d\nR: carve again" % final, 600.0)
		GraphicsPolish.spawn_confetti(self, pumpkin_stage.to_global(pumpkin_center + Vector3(0, 1.0, 0)), 90)
		if win_player != null:
			win_player.play()
	else:
		_show_msg("TIME!\n%d/3 faces carved\nR: try again" % faces_done, 600.0)


func _reset_game() -> void:
	# Rebuild faces from scratch.
	for f_v in faces:
		var f: Dictionary = f_v
		var dots: Array = f["dots"]
		for d_v in dots:
			var d: MeshInstance3D = d_v
			if is_instance_valid(d):
				d.queue_free()
	faces.clear()
	# Remove carve glows (children of the pumpkin stage using carve_mat).
	for child in pumpkin_stage.get_children():
		if child is MeshInstance3D and child.material_override == carve_mat:
			child.queue_free()
	if inner_light != null:
		inner_light.light_energy = 0.0
	_build_faces()
	faces_done = 0
	round_time = 0.0
	restart_hold = 0.0
	state = ST_PLAY
	_show_msg("CARVE THE FACES!", 1.2)
	ARUpgradeKit.save_anchor("hw_pumpkin_carve_main", global_transform)


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames_count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames_count * 2)
	for i in range(frames_count):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames_count)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
