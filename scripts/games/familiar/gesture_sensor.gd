## GestureSensor.gd - hand-gesture recogniser.
## Ports GestureSensor.cs. Emits gesture names over the `gesture` signal:
## "wave", "point", "thumbsup", "pet", "feed" (quick tap near the creature),
## "loudpinch" (sharp double-tap, used to wake the creature).
## Driven by XR hand tracking (LeftHand/RightHand under XROrigin3D), with a
## mouse fallback for desktop: mouse position = hand tip, click = pinch.
extends Node3D
class_name GestureSensor

signal gesture(gesture_name: String)

var pet_target: Node3D
var creature_root: Node3D

class HandState:
	var last_pos := Vector3.INF
	var vel := Vector3.ZERO
	var has_pos := false
	var last_pinch := 0.0
	var pinch_press_time := -99.0
	var was_pinching := false
	var last_x_sign := 0.0
	var x_flips := 0
	var flip_window := 0.0
	var wave_cd := 0.0
	var point_cd := 0.0
	var thumb_cd := 0.0
	var pet_cd := 0.0
	var feed_cd := 0.0
	var loud_cd := 0.0
	var point_hold := 0.0
	var thumb_hold := 0.0
	var pet_dwell := 0.0
	var click_count := 0
	var click_window := 0.0

var _states := {"left": HandState.new(), "right": HandState.new()}
var _mouse_pressed := false
var _last_click_time := -99.0

func _ready() -> void:
	set_process_input(true)

func get_best_hand_tip() -> Vector3:
	# XR hands first.
	var xr := _find_xr_origin()
	var best := Vector3.INF
	var best_d := INF
	if xr:
		for hand_name in ["LeftHand", "RightHand"]:
			var hand := xr.get_node_or_null(hand_name) as Node3D
			if hand and hand.visible:
				var d := global_position.distance_to(hand.global_position)
				if d < best_d:
					best_d = d
					best = hand.global_position
	if best != Vector3.INF:
		return best
	# Desktop fallback: mouse raycast onto the ground plane.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var mouse := get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(mouse)
		var dir := cam.project_ray_normal(mouse)
		if absf(dir.y) > 0.001:
			var t := -from.y / dir.y
			if t > 0.0:
				return from + dir * t + Vector3(0, 0.1, 0)
	return Vector3.INF

func _find_xr_origin() -> Node3D:
	var root := get_tree().current_scene
	if root:
		return root.get_node_or_null("XROrigin3D") as Node3D
	return null

func _process(delta: float) -> void:
	# Feed "left"/"right" from XR hands; mouse drives "right" on desktop.
	var xr := _find_xr_origin()
	var right_hand: Node3D = null
	var left_hand: Node3D = null
	if xr:
		right_hand = xr.get_node_or_null("RightHand") as Node3D
		left_hand = xr.get_node_or_null("LeftHand") as Node3D
	if right_hand and right_hand.visible:
		_check_hand("right", right_hand.global_position, 0.0, delta)
	elif left_hand and left_hand.visible:
		_check_hand("left", left_hand.global_position, 0.0, delta)
		_check_hand("right", Vector3.INF, 0.0, delta)
	else:
		# Desktop: mouse position as the hand tip.
		var tip := get_best_hand_tip()
		var pinch := 1.0 if _mouse_pressed else 0.0
		_check_hand("right", tip, pinch, delta)
		_check_hand("left", Vector3.INF, 0.0, delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_pressed = mb.pressed
			if mb.pressed:
				var now := Time.get_ticks_msec() / 1000.0
				if now - _last_click_time < 0.4:
					(_states["right"] as HandState).loud_cd = 1.5
					gesture.emit("loudpinch")
				_last_click_time = now

func _check_hand(which: String, tip: Vector3, pinch: float, delta: float) -> void:
	var st: HandState = _states[which]
	if tip == Vector3.INF:
		st.has_pos = false
		return

	# Tip velocity.
	if st.has_pos:
		var v := (tip - st.last_pos) / maxf(delta, 0.0001)
		st.vel = st.vel.lerp(v, 0.5)
	st.last_pos = tip
	st.has_pos = true
	var speed := st.vel.length()
	var pinching := pinch > 0.7

	# ---- loud pinch: sharp press from open (wake-up) ----
	if st.loud_cd <= 0.0 and st.last_pinch < 0.2 and pinch > 0.8:
		_emit(st, "loudpinch", "loud_cd", 1.5)

	# ---- feed: quick tap near the creature ----
	if not st.was_pinching and pinching:
		st.pinch_press_time = Time.get_ticks_msec() / 1000.0
	if st.was_pinching and not pinching and st.feed_cd <= 0.0:
		var held := Time.get_ticks_msec() / 1000.0 - st.pinch_press_time
		if held < 0.7 and creature_root:
			if tip.distance_to(creature_root.global_position) < 0.45:
				_emit(st, "feed", "feed_cd", 2.0)
	st.was_pinching = pinching
	st.last_pinch = pinch

	# ---- wave: x-velocity oscillation ----
	if st.wave_cd <= 0.0 and speed > 0.35:
		var sign := signf(st.vel.x)
		if sign != 0.0:
			if st.last_x_sign != 0.0 and sign != st.last_x_sign:
				st.x_flips += 1
				st.flip_window = 1.2
				if st.x_flips >= 3:
					_emit(st, "wave", "wave_cd", 2.5)
					st.x_flips = 0
			st.last_x_sign = sign
	st.flip_window -= delta
	if st.flip_window <= 0.0:
		st.x_flips = 0
		st.last_x_sign = 0.0

	# ---- point: hand held still and raised ----
	var point_pose := speed < 0.15 and tip.y > 0.6
	st.point_hold = st.point_hold + delta if point_pose else 0.0
	if st.point_cd <= 0.0 and st.point_hold > 0.5:
		_emit(st, "point", "point_cd", 2.0)

	# ---- thumbs-up: hand still and high ----
	var thumb_pose := speed < 0.15 and tip.y > 0.9
	st.thumb_hold = st.thumb_hold + delta if thumb_pose else 0.0
	if st.thumb_cd <= 0.0 and st.thumb_hold > 0.5:
		_emit(st, "thumbsup", "thumb_cd", 2.0)

	# ---- pet: hand slow + close to head ----
	if pet_target and st.pet_cd <= 0.0:
		var d := tip.distance_to(pet_target.global_position)
		st.pet_dwell = st.pet_dwell + delta if (d < 0.2 and speed < 0.35) else 0.0
		if st.pet_dwell > 0.8:
			_emit(st, "pet", "pet_cd", 3.0)

	# Cooldown decay.
	st.wave_cd -= delta
	st.point_cd -= delta
	st.thumb_cd -= delta
	st.pet_cd -= delta
	st.feed_cd -= delta
	st.loud_cd -= delta

func _emit(st: HandState, gesture_name: String, cd_field: String, cd_value: float) -> void:
	st.set(cd_field, cd_value)
	gesture.emit(gesture_name)
