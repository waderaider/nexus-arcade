## HwSkeletonDance - "Skeleton Dance": a skeleton dances on the beat and
## strikes poses. Mirror its poses by moving your hands onto the two glowing
## target orbs before the beat window closes. +100 per matched pose, 90s.
## Desktop: the mouse steers a hand-pair (offset left/right). R restarts;
## hold pinch 1s on the end screen to play again.
extends Node3D

const ROUND_TIME := 90.0
const BEAT := 1.6
const WINDOW := 1.3
const MATCH_RADIUS := 0.32
const POSE_SCORE := 100
const ORB_Z := -1.9

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var poses_hit := 0
var poses_total := 0
var skel: Node3D = null
var shoulder_l: Node3D = null
var shoulder_r: Node3D = null
var hand_l: Node3D = null
var hand_r: Node3D = null
var arm_l: MeshInstance3D = null
var arm_r: MeshInstance3D = null
var orb_l: MeshInstance3D = null
var orb_r: MeshInstance3D = null
var orb_mat_l: StandardMaterial3D = null
var orb_mat_r: StandardMaterial3D = null
var eye_mat: StandardMaterial3D = null
var beat_ring: MeshInstance3D = null
var beat_ring_mat: StandardMaterial3D = null
var beat_timer := 0.0
var window_timer := 0.0
var matched := false
var pose_idx := 0
var poses: Array = []
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var tick_player: AudioStreamPlayer = null
var match_player: AudioStreamPlayer = null
var miss_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	poses = [
		[Vector3(-0.70, 0.60, 0.0), Vector3(0.70, 0.60, 0.0)],
		[Vector3(-0.95, 0.10, 0.0), Vector3(0.95, 0.10, 0.0)],
		[Vector3(-0.55, -0.45, 0.0), Vector3(0.55, -0.45, 0.0)],
		[Vector3(-0.75, 0.35, 0.30), Vector3(0.75, 0.35, 0.30)],
		[Vector3(-0.45, 0.75, 0.15), Vector3(0.45, 0.75, 0.15)],
	]
	_build_skeleton()
	_build_stage()
	_build_hud()
	tick_player = _make_player(_make_tone(600.0, 0.08, 0.40))
	match_player = _make_player(_make_tone(1040.0, 0.25, 0.50))
	miss_player = _make_player(_make_tone(240.0, 0.20, 0.40))
	win_player = _make_player(_make_tone(880.0, 0.50, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_skeleton_dance_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -2.0), 2.2, 30)
	_next_beat()


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
	camera.position = Vector3(0.0, 1.6, 1.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.4, -2.2), Vector3.UP)
	camera.current = true


func _bone_mat() -> StandardMaterial3D:
	return GraphicsPolish.pbr(Color(0.88, 0.86, 0.80), 0.05, 0.55)


func _build_skeleton() -> void:
	skel = Node3D.new()
	skel.position = Vector3(0.0, 0.0, -2.2)
	add_child(skel)
	var bone := _bone_mat()
	# Pelvis + spine.
	var pelvis := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.30, 0.15, 0.18)
	pelvis.mesh = pb
	pelvis.position = Vector3(0.0, 1.00, 0.0)
	pelvis.material_override = bone
	skel.add_child(pelvis)
	var spine := MeshInstance3D.new()
	var sc := CapsuleMesh.new()
	sc.radius = 0.05
	sc.height = 0.40
	spine.mesh = sc
	spine.position = Vector3(0.0, 1.28, 0.0)
	spine.material_override = bone
	skel.add_child(spine)
	# Ribcage: three tori.
	var rib_r := [0.24, 0.21, 0.17]
	for i in range(3):
		var rib := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rib_r[i] - 0.03
		tm.outer_radius = rib_r[i]
		rib.mesh = tm
		rib.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		rib.position = Vector3(0.0, 1.30 + float(i) * 0.11, 0.0)
		rib.material_override = bone
		skel.add_child(rib)
	# Skull + jaw + glowing eyes.
	var skull := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.16
	ss.height = 0.32
	skull.mesh = ss
	skull.position = Vector3(0.0, 1.78, 0.0)
	skull.material_override = bone
	skel.add_child(skull)
	var jaw := MeshInstance3D.new()
	var jb := BoxMesh.new()
	jb.size = Vector3(0.16, 0.08, 0.12)
	jaw.mesh = jb
	jaw.position = Vector3(0.0, 1.63, -0.04)
	jaw.material_override = bone
	skel.add_child(jaw)
	eye_mat = GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 2.4)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.035
		es.height = 0.07
		eye.mesh = es
		eye.position = Vector3(ex, 1.80, -0.13)
		eye.material_override = eye_mat
		skel.add_child(eye)
	# Legs (simple, they bounce with the beat).
	for lx in [-0.12, 0.12]:
		var leg := MeshInstance3D.new()
		var lc := CapsuleMesh.new()
		lc.radius = 0.06
		lc.height = 0.85
		leg.mesh = lc
		leg.position = Vector3(lx, 0.50, 0.0)
		leg.material_override = bone
		skel.add_child(leg)
	# Shoulders, hands, stretchy arms.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.30, 1.52, 0.0)
		skel.add_child(shoulder)
		var hand := Node3D.new()
		hand.position = Vector3(side * 0.70, 0.60, 0.0)
		skel.add_child(hand)
		var palm := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.07
		ps.height = 0.14
		palm.mesh = ps
		palm.material_override = bone
		hand.add_child(palm)
		var arm := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(0.09, 0.09, 1.0)
		arm.mesh = ab
		arm.material_override = bone
		skel.add_child(arm)
		if side < 0.0:
			shoulder_l = shoulder
			hand_l = hand
			arm_l = arm
		else:
			shoulder_r = shoulder
			hand_r = hand
			arm_r = arm
	# Target orbs (glowing pose targets).
	orb_mat_l = GraphicsPolish.glow(Color(0.3, 1.0, 0.5), 2.0)
	orb_mat_r = GraphicsPolish.glow(Color(0.3, 1.0, 0.5), 2.0)
	orb_l = _make_orb(orb_mat_l)
	orb_r = _make_orb(orb_mat_r)
	skel.add_child(orb_l)
	skel.add_child(orb_r)


func _make_orb(mat: StandardMaterial3D) -> MeshInstance3D:
	var orb := MeshInstance3D.new()
	var os := SphereMesh.new()
	os.radius = 0.09
	os.height = 0.18
	orb.mesh = os
	orb.material_override = mat
	orb.visible = false
	return orb


func _build_stage() -> void:
	# Floor disc under the skeleton.
	var disc := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 1.1
	dc.bottom_radius = 1.2
	dc.height = 0.06
	disc.mesh = dc
	disc.position = Vector3(0.0, 0.03, -2.2)
	disc.material_override = GraphicsPolish.pbr(Color(0.10, 0.08, 0.14), 0.2, 0.6)
	add_child(disc)
	# Beat ring that pulses each beat.
	beat_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.33
	beat_ring.mesh = tm
	beat_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	beat_ring.position = Vector3(0.0, 0.08, -2.2)
	beat_ring_mat = GraphicsPolish.glow(Color(1.0, 0.5, 0.9), 1.6)
	beat_ring.material_override = beat_ring_mat
	add_child(beat_ring)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.2, -2.2), Color(0.7, 1.0, 0.7), 0.9, 4.0)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("SKELETON DANCE", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.4, 2.9, -1.2)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Move BOTH hands onto the glowing orbs on the beat!  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.4, 2.35, -1.2)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 2.1, -2.0)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "SKELETON DANCE\nTime: %ds   Score: %d   Poses: %d/%d" % [int(ceil(time_left)), score, poses_hit, poses_total]


func _show_msg(text: String) -> void:
	if msg_label != null:
		msg_label.text = text


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_skeleton_dance_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if eye_mat != null:
		GraphicsPolish.pulse_glow(eye_mat, 2.0, 1.0, _time, 4.0)
	# Beat ring pulse.
	if beat_ring_mat != null:
		var bp := 1.0 - clampf(beat_timer / BEAT, 0.0, 1.0)
		beat_ring_mat.emission_energy_multiplier = 1.0 + 1.6 * bp
		beat_ring.scale = Vector3.ONE * (1.0 + 0.12 * bp)
	_animate_skeleton(delta)
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
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	beat_timer -= delta
	if beat_timer <= 0.0:
		_next_beat()
	if window_timer > 0.0 and not matched:
		window_timer -= delta
		_pulse_orbs()
		_check_match()
		if window_timer <= 0.0 and not matched:
			orb_l.visible = false
			orb_r.visible = false
			if miss_player != null:
				miss_player.play()
	_update_hud()


func _next_beat() -> void:
	beat_timer = BEAT
	pose_idx = (pose_idx + 1) % poses.size()
	var pose: Array = poses[pose_idx]
	orb_l.position = pose[0]
	orb_r.position = pose[1]
	orb_l.visible = true
	orb_r.visible = true
	window_timer = WINDOW
	matched = false
	poses_total += 1
	if tick_player != null:
		tick_player.play()


func _pulse_orbs() -> void:
	GraphicsPolish.pulse_glow(orb_mat_l, 1.6, 1.2, _time, 6.0)
	GraphicsPolish.pulse_glow(orb_mat_r, 1.6, 1.2, _time, 6.0)


func _hand_world(hand: int) -> Vector3:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_position(self, hand)
	if camera == null:
		return Vector3.ZERO
	# Desktop: mouse steers a hand-pair spread left/right on the orb plane.
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var p := Vector3(0.0, 1.5, ORB_Z)
	if absf(dir.z) > 0.001:
		var t := (ORB_Z - origin.z) / dir.z
		if t > 0.0:
			p = origin + dir * t
	var off := -0.35 if hand == ARUpgradeKit.HAND_LEFT else 0.35
	return Vector3(p.x + off, p.y, ORB_Z)


func _check_match() -> void:
	var lh := _hand_world(ARUpgradeKit.HAND_LEFT)
	var rh := _hand_world(ARUpgradeKit.HAND_RIGHT)
	if lh.distance_to(orb_l.global_position) < MATCH_RADIUS \
			and rh.distance_to(orb_r.global_position) < MATCH_RADIUS:
		matched = true
		poses_hit += 1
		score += POSE_SCORE
		orb_l.visible = false
		orb_r.visible = false
		GraphicsPolish.spawn_sparks(self, orb_l.global_position, Color(0.4, 1.0, 0.6), 20)
		GraphicsPolish.spawn_sparks(self, orb_r.global_position, Color(0.4, 1.0, 0.6), 20)
		if match_player != null:
			match_player.play()


func _animate_skeleton(delta: float) -> void:
	if skel == null:
		return
	var pose: Array = poses[pose_idx]
	# Bounce + sway on the beat.
	var bp := 1.0 - clampf(beat_timer / BEAT, 0.0, 1.0)
	skel.position.y = 0.10 * bp
	skel.rotation.y = 0.12 * sin(_time * 2.0)
	# Hands dance toward the current pose targets.
	hand_l.position = hand_l.position.lerp(pose[0] as Vector3, minf(1.0, 8.0 * delta))
	hand_r.position = hand_r.position.lerp(pose[1] as Vector3, minf(1.0, 8.0 * delta))
	_layout_arm(arm_l, shoulder_l, hand_l)
	_layout_arm(arm_r, shoulder_r, hand_r)


func _layout_arm(arm: MeshInstance3D, shoulder: Node3D, hand: Node3D) -> void:
	if arm == null or shoulder == null or hand == null:
		return
	var a := shoulder.global_position
	var b := hand.global_position
	var d := b - a
	var len := maxf(d.length(), 0.05)
	arm.global_position = a
	if d.length_squared() > 0.000001:
		var up := Vector3.UP
		if absf(d.normalized().y) > 0.98:
			up = Vector3.FORWARD
		arm.look_at(b, up)
	arm.scale = Vector3(1.0, 1.0, len)


func _game_over() -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_skeleton_dance_main", global_transform)
	orb_l.visible = false
	orb_r.visible = false
	var rank := "Stiff Mover"
	if poses_total > 0:
		var rate := float(poses_hit) / float(maxi(1, poses_total))
		if rate >= 0.8:
			rank = "DANCE LEGEND!"
		elif rate >= 0.5:
			rank = "Groove Ghoul"
	_show_msg("TIME UP!\nScore: %d  (%d/%d poses)\n%s\nR or hold pinch 1s to play again" % [score, poses_hit, poses_total, rank])
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -2.0), 70)
	if win_player != null:
		win_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	poses_hit = 0
	poses_total = 0
	pose_idx = 0
	_pinch_hold = 0.0
	_show_msg("")
	_next_beat()
	ARUpgradeKit.save_anchor("hw_skeleton_dance_main", global_transform)


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
