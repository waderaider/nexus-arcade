## MinigolfClub.gd - XR controller-tracked putter for NEXUS GREENS.
## Velocity via VERIFIED path (AI/API Guru 2026-10-09, MINIGOLF_API_NOTES.md):
##   XRController3D.get_tracker() -> get_pose("aim") -> XRPose.linear_velocity
## The aim pose sits at the controller tip, so its linear velocity IS the
## clubhead velocity (no cross products). Confidence-gated per frame.
## Feel spec: Game Designer §3. Power: peak downswing speed -> ball launch
## with face-angle influence. Address mode projects the aim line.
extends Node3D
class_name MinigolfClub

signal struck(power01: float)

const WINDOW := 0.25          # velocity history (s)
const STRIKE_RANGE := 0.30    # head-to-ball distance for contact (m)
const MIN_HEAD_SPEED := 0.4   # below this = address/tap, no strike (m/s)
const MAX_HEAD_SPEED := 8.0   # full controlled stroke (m/s)
const ADDRESS_DIST := 0.25    # ball within this = address candidate (m)
const ADDRESS_STILL := 0.15   # head speed below this = "still" (m/s)
const ADDRESS_TIME := 0.4     # still duration to enter address (s)
const STRIKE_COOLDOWN := 0.45

var _game: MinigolfGame = null
var _ball: MinigolfBall = null
var _controller: XRController3D = null
var _samples: Array = []  # [time_sec, speed]
var _cooldown := 0.0
var _address_timer := 0.0
var _in_address := false
var _aim_line: MeshInstance3D = null
var _head_marker: Marker3D = null
var _addr_pos := Vector3.ZERO  # club-head pos when address was entered
var _last_rumble := 0.0  # backswing haptic curve state


func setup(game: MinigolfGame, ball: MinigolfBall) -> void:
	_game = game
	_ball = ball


func _ready() -> void:
	_controller = _find_right_controller()
	_build_aim_line()
	# The putter visual comes from controller_skins ("putter" skin);
	# find its head marker for strike distance checks.
	if _controller != null:
		_head_marker = _controller.find_child("ClubHead", true, false)


func _find_right_controller() -> XRController3D:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var origins := tree.root.find_children("*", "XROrigin3D", true, false)
	if origins.is_empty():
		return null
	return (origins[0] as Node3D).get_node_or_null("RightController") as XRController3D


func _build_aim_line() -> void:
	# Dotted predicted path (first 2m + first bank), shown in address mode.
	_aim_line = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	_aim_line.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_line.material_override = mat
	_aim_line.visible = false
	# Top-level so it doesn't inherit club rotation.
	_aim_line.top_level = true
	add_child(_aim_line)


func _process(_delta: float) -> void:
	_cooldown -= _delta
	if _ball == null or not is_instance_valid(_ball) or _ball.is_holed:
		_set_address(false)
		return

	var now := Time.get_ticks_msec() / 1000.0
	var head_pos := _club_head_pos()
	var head_speed := _sample_velocity(now)  # -1 when untracked
	if head_pos == Vector3.INF or head_speed < 0.0:
		_set_address(false)
		return

	var to_ball: float = head_pos.distance_to(_ball.global_position)

	# Address mode: close + still.
	if to_ball < ADDRESS_DIST and head_speed < ADDRESS_STILL and not _ball.is_in_play:
		_address_timer += _delta
		if _address_timer >= ADDRESS_TIME:
			_set_address(true, head_pos)
	else:
		_address_timer = 0.0
		# Leaving address on backswing (head moving away fast).
		if _in_address and head_speed > 0.8:
			_set_address(false)

	if _in_address:
		_update_aim_line(head_pos)

	# Backswing haptic curve (Game Design v2.0: power is FELT, never metered).
	# When the head draws back from address, intensify a rumble with draw
	# length so players feel the power loading through their hands.
	if _in_address and not _ball.is_in_play:
		var draw_len: float = head_pos.distance_to(_addr_pos)
		if draw_len > 0.05:
			var curve: float = clampf((draw_len - 0.05) / 0.45, 0.0, 1.0)
			if curve > _last_rumble + 0.15:
				_last_rumble = curve
				Haptics.play_sequence("backswing_rumble", "right")

	# Strike: head near ball + moving fast enough.
	if _cooldown <= 0.0 and to_ball < STRIKE_RANGE and head_speed > MIN_HEAD_SPEED:
		_strike(head_speed, head_pos)


func _club_head_pos() -> Vector3:
	if _head_marker != null and is_instance_valid(_head_marker):
		return _head_marker.global_position
	if _controller != null and is_instance_valid(_controller):
		# Fallback: 0.9m in front-down of the controller.
		return _controller.global_position + Vector3(0, -0.63, -0.87)
	return Vector3.INF


## Club-head world position for power-up collect checks.
func get_club_head_global() -> Vector3:
	return _club_head_pos()


## Sample aim-pose linear velocity. Returns speed (m/s) or -1 if untracked.
func _sample_velocity(now: float) -> float:
	if _controller == null or not is_instance_valid(_controller):
		return -1.0
	var tracker := _controller.get_tracker()
	# NOTE: get_tracker() returns the tracker NAME on this Godot build
	# (StringName), not the tracker — handle both (v0.8.0 lesson).
	var tracker_node: XRPositionalTracker = null
	if tracker is XRPositionalTracker:
		tracker_node = tracker
	elif tracker is StringName or tracker is String:
		tracker_node = XRServer.get_tracker(tracker)
	if tracker_node == null or not tracker_node.has_pose("aim"):
		_samples.clear()
		return -1.0
	var pose: XRPose = tracker_node.get_pose("aim")
	if pose == null or not pose.has_tracking_data:
		return -1.0
	if pose.tracking_confidence < XRPose.XR_TRACKING_CONFIDENCE_HIGH:
		return -1.0
	var speed: float = pose.linear_velocity.length()
	_samples.append([now, speed])
	while not _samples.is_empty() and now - float(_samples[0][0]) > WINDOW:
		_samples.pop_front()
	return speed


func _peak_speed() -> float:
	var peak := 0.0
	for s in _samples:
		peak = maxf(peak, float(s[1]))
	return peak


func _strike(head_speed: float, head_pos: Vector3) -> void:
	_cooldown = STRIKE_COOLDOWN
	_set_address(false)
	# Direction: club-face normal projected on green plane, blended 15%
	# toward head velocity (face angle matters — Game Designer §3).
	var face_dir := -(_controller.global_transform.basis.z if _controller else Vector3.FORWARD)
	face_dir.y = 0.0
	face_dir = face_dir.normalized()
	var vel_dir := Vector3.ZERO
	if _controller != null:
		var tracker := _controller.get_tracker()
		var tn: XRPositionalTracker = tracker if tracker is XRPositionalTracker else null
		if tn != null and tn.has_pose("aim"):
			var p: XRPose = tn.get_pose("aim")
			if p != null:
				vel_dir = Vector3(p.linear_velocity.x, 0, p.linear_velocity.z)
	if vel_dir.length() > 0.2:
		face_dir = (face_dir * 0.85 + vel_dir.normalized() * 0.15).normalized()
	var power01 := clampf(head_speed / MAX_HEAD_SPEED, 0.0, 1.0)
	var ball_speed := clampf(head_speed * 1.4, 0.5, 8.0)
	_ball.launch(face_dir * ball_speed)
	# Feel: haptic + sound + telemetry, same frame.
	_haptics_impact(power01)
	_sfx("club_thock", 0.8 + power01 * 0.5)
	if _game != null:
		_game.on_putt(power01)
	struck.emit(power01)
	_samples.clear()


func _set_address(on: bool, head_pos: Vector3 = Vector3.INF) -> void:
	_in_address = on
	if on and head_pos != Vector3.INF:
		_addr_pos = head_pos
		_last_rumble = 0.0
	if _aim_line != null:
		_aim_line.visible = on


func _update_aim_line(head_pos: Vector3) -> void:
	# Project first 2m of predicted path including first bank.
	if _ball == null or _aim_line == null:
		return
	var hole := _ball._hole
	if hole == null:
		return
	var dir := -global_transform.basis.z
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, -1)
	var pts := PackedVector3Array()
	var p: Vector3 = _ball.global_position + Vector3(0, 0.02, 0)
	var d := dir
	var remaining := 2.0
	var step := 0.12
	var banked := false
	while remaining > 0.0 and pts.size() < 24:
		pts.append(p)
		var np := p + d * step
		# Simple rail reflection using the hole's play rect.
		var r := hole.get_play_rect()
		if not banked and (np.x < r.position.x or np.x > r.end.x or np.z < r.position.y or np.z > r.end.y):
			if np.x < r.position.x or np.x > r.end.x:
				d.x = -d.x
			if np.z < r.position.y or np.z > r.end.y:
				d.z = -d.z
			banked = true
			np = p + d * step
		p = np
		remaining -= step
	var im := _aim_line.mesh as ImmediateMesh
	im.clear_surfaces()
	if pts.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for pt in pts:
			im.surface_set_color(Color(1, 1, 1, 0.6))
			im.surface_add_vertex(pt)
		im.surface_end()
	_aim_line.global_position = Vector3.ZERO


# ------------------------------------------------------------------ shims ---

func _haptics_impact(power01: float) -> void:
	var h := get_node_or_null("/root/Haptics")
	if h != null and h.has_method("impact"):
		h.call("impact", power01, "right")


func _sfx(sfx_name: String, pitch := 1.0) -> void:
	var ak := get_node_or_null("/root/AudioKit")
	if ak != null:
		ak.play_game_sfx(sfx_name, pitch)
