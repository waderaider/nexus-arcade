## HwBroomFlight - "Broom Flight": steer a witch on her broom with your hand
## (mouse on desktop) through floating rings. 90 seconds, +10 per ring.
## R restarts; hold pinch 1s on the end screen to play again.
extends Node3D

const ROUND_TIME := 90.0
const WITCH_Z := 0.6
const X_BOUND := 1.5
const Y_MIN := 0.8
const Y_MAX := 2.3
const RING_R := 0.45
const RING_COUNT := 6
const RING_SPACING := 2.6
const RING_SPAWN_Z := -6.0
const RING_SCORE := 10
const BASE_SPEED := 1.6
const MAX_SPEED := 3.2

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var elapsed := 0.0
var score := 0
var rings_hit := 0
var speed := BASE_SPEED
var witch: Node3D = null
var rings: Array = []
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var moon_mat: StandardMaterial3D = null
var ring_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_witch()
	_build_rings()
	_build_sky()
	_build_hud()
	ring_player = _make_player(_make_tone(1180.0, 0.25, 0.50))
	miss_player = _make_player(_make_tone(280.0, 0.15, 0.35))
	win_player = _make_player(_make_tone(880.0, 0.50, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_broom_flight_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -2.0), 3.0, 50)


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 2.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, -3.0), Vector3.UP)
	camera.current = true


func _build_witch() -> void:
	witch = Node3D.new()
	witch.position = Vector3(0.0, 1.5, WITCH_Z)
	add_child(witch)
	var black := GraphicsPolish.pbr(Color(0.08, 0.08, 0.10), 0.1, 0.7)
	var skin := GraphicsPolish.pbr(Color(0.85, 0.65, 0.50), 0.0, 0.6)
	# Broomstick along Z (nose toward -Z).
	var stick := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.035
	sc.bottom_radius = 0.035
	sc.height = 1.4
	stick.mesh = sc
	stick.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	stick.position = Vector3(0.0, 0.0, 0.2)
	stick.material_override = GraphicsPolish.pbr(Color(0.35, 0.22, 0.12), 0.0, 0.8)
	witch.add_child(stick)
	# Bristles fanning out behind.
	var bristles := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.04
	bc.bottom_radius = 0.13
	bc.height = 0.35
	bristles.mesh = bc
	bristles.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bristles.position = Vector3(0.0, 0.0, 0.95)
	bristles.material_override = GraphicsPolish.pbr(Color(0.55, 0.38, 0.18), 0.0, 0.9)
	witch.add_child(bristles)
	# Witch body: dress, head, pointy hat.
	var dress := MeshInstance3D.new()
	var dc := CapsuleMesh.new()
	dc.radius = 0.16
	dc.height = 0.55
	dress.mesh = dc
	dress.position = Vector3(0.0, 0.32, -0.10)
	dress.material_override = black
	witch.add_child(dress)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.26
	head.mesh = hs
	head.position = Vector3(0.0, 0.70, -0.15)
	head.material_override = skin
	witch.add_child(head)
	var brim := MeshInstance3D.new()
	var brc := CylinderMesh.new()
	brc.top_radius = 0.22
	brc.bottom_radius = 0.22
	brc.height = 0.03
	brim.mesh = brc
	brim.position = Vector3(0.0, 0.80, -0.15)
	brim.material_override = black
	witch.add_child(brim)
	var cone := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.0
	cc.bottom_radius = 0.14
	cc.height = 0.32
	cone.mesh = cc
	cone.position = Vector3(0.0, 0.96, -0.13)
	cone.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	cone.material_override = black
	witch.add_child(cone)
	# Hat band glow.
	var band := MeshInstance3D.new()
	var bnd := TorusMesh.new()
	bnd.inner_radius = 0.13
	bnd.outer_radius = 0.15
	band.mesh = bnd
	band.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	band.position = Vector3(0.0, 0.84, -0.14)
	band.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.1), 1.8)
	witch.add_child(band)
	# Magic trail from the bristles.
	var trail := GraphicsPolish.make_trail(Color(1.0, 0.6, 0.15), 0.07)
	trail.position = Vector3(0.0, 0.0, 1.0)
	witch.add_child(trail)


func _build_rings() -> void:
	for i in range(RING_COUNT):
		var node := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = RING_R - 0.06
		tm.outer_radius = RING_R
		node.mesh = tm
		var mat := GraphicsPolish.glow(Color(1.0, 0.55, 0.10), 1.8)
		node.material_override = mat
		add_child(node)
		var ring := {"node": node, "mat": mat, "x": 0.0, "y": 1.5, "z": 0.0, "passed": false, "pop": 0.0}
		rings.append(ring)
		_place_ring(ring, RING_SPAWN_Z - float(i) * RING_SPACING)


func _place_ring(ring: Dictionary, z: float) -> void:
	ring["x"] = randf_range(-1.2, 1.2)
	ring["y"] = randf_range(0.9, 2.2)
	ring["z"] = z
	ring["passed"] = false
	ring["pop"] = 0.0
	var node: MeshInstance3D = ring["node"]
	node.position = Vector3(float(ring["x"]), float(ring["y"]), z)


func _build_sky() -> void:
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.6
	ms.height = 1.2
	moon.mesh = ms
	moon.position = Vector3(2.8, 3.4, -9.0)
	moon_mat = GraphicsPolish.glow(Color(0.95, 0.95, 0.85), 1.1)
	moon.material_override = moon_mat
	add_child(moon)
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.02, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.05, 0.05, 0.08), 0.0, 0.95)
	add_child(floor_inst)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("BROOM FLIGHT", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.4, 2.9, -1.2)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Steer with your hand / mouse - fly through the rings!  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.4, 2.35, -1.2)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 2.1, -2.2)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "BROOM FLIGHT\nTime: %ds   Score: %d   Rings: %d" % [int(ceil(time_left)), score, rings_hit]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text


func _steer_target() -> Vector3:
	var p := Vector3(0.0, 1.5, WITCH_Z)
	if ARUpgradeKit.is_xr_active():
		var h := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		p = Vector3(h.x, h.y, WITCH_Z)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mp)
		var dir := camera.project_ray_normal(mp)
		if absf(dir.z) > 0.001:
			var t := (WITCH_Z - origin.z) / dir.z
			if t > 0.0:
				var hit := origin + dir * t
				p = Vector3(hit.x, hit.y, WITCH_Z)
	p.x = clampf(p.x, -X_BOUND, X_BOUND)
	p.y = clampf(p.y, Y_MIN, Y_MAX)
	return p


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_broom_flight_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if moon_mat != null:
		GraphicsPolish.pulse_glow(moon_mat, 1.0, 0.25, _time, 1.0)
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_pinch_hold += delta
			if _pinch_hold >= 1.0:
				_pinch_hold = 0.0
				_reset_game()
		else:
			_pinch_hold = 0.0
		_update_hud()
		return
	# ST_PLAY.
	elapsed += delta
	time_left -= delta
	speed = minf(MAX_SPEED, BASE_SPEED + elapsed * 0.018)
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	# Steer the witch toward the hand.
	var target := _steer_target()
	var prev := witch.position
	witch.position = witch.position.lerp(target, minf(1.0, 5.0 * delta))
	witch.position.z = WITCH_Z
	# Banking tilt from lateral velocity.
	var vx := (witch.position.x - prev.x) / maxf(delta, 0.0001)
	witch.rotation.z = clampf(-vx * 0.25, -0.6, 0.6)
	witch.rotation.x = clampf((target.y - witch.position.y) * -0.2, -0.3, 0.3)
	witch.position.y += 0.03 * sin(_time * 5.0)
	_step_rings(delta)
	_update_hud()


func _step_rings(delta: float) -> void:
	for r_v in rings:
		var r: Dictionary = r_v
		var z := float(r["z"]) + speed * delta
		r["z"] = z
		var node: MeshInstance3D = r["node"]
		node.position = Vector3(float(r["x"]), float(r["y"]), z)
		# Ring glow pulse.
		var mat: StandardMaterial3D = r["mat"]
		GraphicsPolish.pulse_glow(mat, 1.5, 0.7, _time + z, 3.0)
		# Hit-pop animation.
		var pop := float(r["pop"])
		if pop > 0.0:
			pop = maxf(0.0, pop - delta * 3.0)
			r["pop"] = pop
			var s := 1.0 + 0.45 * pop
			node.scale = Vector3(s, s, s)
		# Crossing the witch plane: score or miss, then recycle far ahead.
		if not bool(r["passed"]) and z >= WITCH_Z:
			r["passed"] = true
			var d := Vector2(witch.position.x - float(r["x"]), witch.position.y - float(r["y"])).length()
			if d < RING_R:
				score += RING_SCORE
				rings_hit += 1
				r["pop"] = 1.0
				GraphicsPolish.spawn_sparks(self, Vector3(float(r["x"]), float(r["y"]), WITCH_Z), Color(1.0, 0.7, 0.2), 26)
				if ring_player != null:
					ring_player.play()
			else:
				if miss_player != null:
					miss_player.play()
		if z > 2.5:
			_place_ring(r, z - float(RING_COUNT) * RING_SPACING)


func _game_over() -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_broom_flight_main", global_transform)
	var rank := "Apprentice Flyer"
	if rings_hit >= 30:
		rank = "WITCH ACE!"
	elif rings_hit >= 15:
		rank = "Sky Dancer"
	_show_msg("TIME UP!\nRings: %d   Score: %d\n%s\nR or hold pinch 1s to fly again" % [rings_hit, score, rank])
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -1.0), 70)
	if win_player != null:
		win_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	elapsed = 0.0
	score = 0
	rings_hit = 0
	speed = BASE_SPEED
	_pinch_hold = 0.0
	witch.position = Vector3(0.0, 1.5, WITCH_Z)
	for i in range(rings.size()):
		_place_ring(rings[i], RING_SPAWN_Z - float(i) * RING_SPACING)
	_show_msg("")
	ARUpgradeKit.save_anchor("hw_broom_flight_main", global_transform)


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
