extends Node3D
class_name XRUIPointer
## Laser-pointer input for the NEXUS ARCADE 2D launcher panel.
##
## One instance per input source (left/right controller, left/right hand).
## Each frame it raycasts from the source against the launcher quad using pure
## plane math (no physics bodies needed), forwards hover/click events to the
## panel's SubViewport, and draws a laser + hit dot that stay visible whenever
## the source tracker is active.
##
## Controllers: ray from the XRController3D origin along -Z; click on the
## trigger press edge. Trigger detection uses the two boolean reads
## (is_button_pressed("trigger_click") / is_button_pressed("trigger")) — the
## analog get_float("trigger") leg was WRONG (the shipped map types "trigger"
## as boolean) and is deleted; the wrong accessor never fired on-device.
## Hands: XRHandTracker found by iterating XRServer TRACKER_HAND trackers and
## matching tracker.hand (XRPositionalTracker.TRACKER_HAND_LEFT/RIGHT). NEVER
## by tracker name: "left_hand"/"right_hand" also name the CONTROLLER
## trackers, so XRServer.get_tracker() returns the controller instead and the
## "is XRHandTracker" check fails -> hands never activate.
## Gaze: hub.gd drives a camera-center fallback (reticle + dwell) through
## ray_to_viewport(); this script stays per-source only.

signal xr_clicked(viewport_pos: Vector2)
signal xr_moved(viewport_pos: Vector2)

const PINCH_THRESHOLD := 0.025
const RAY_LENGTH := 3.0

var ui_viewport: SubViewport = null
var ui_quad: MeshInstance3D = null
var xr_origin: Node3D = null
var controller: XRController3D = null
## 0 = controller mode; otherwise XRPositionalTracker.TRACKER_HAND_LEFT/RIGHT.
var hand_side: int = 0
var enabled := true
## Set by the hub every frame from get_viewport().use_xr. When false (desktop /
## headless, or XR not initialized yet) the pointer stays fully inert: it never
## touches tracker objects (XRServer can hold stale entries when OpenXR fails
## to start) and draws nothing.
var xr_mode := false

var _was_pressed := false
var _laser: MeshInstance3D = null
var _dot: MeshInstance3D = null


## Hardened trigger-press test for a controller. The shipped action map types
## BOTH "trigger_click" and "trigger" as booleans, so both boolean reads are
## OR-ed. (v0.9.3 fix: the old third leg — get_float("trigger") > 0.7 — was
## the wrong accessor for a boolean-typed action and never fired on-device.)
## Returns false immediately when there is no tracker (desktop/headless), so
## these action reads never run off-device.
static func trigger_pressed(controller: XRController3D) -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	# NOTE: XRController3D.get_tracker() returns the configured tracker NAME
	# (StringName, never null) — not the live tracker. Liveness MUST go
	# through XRServer.get_tracker(name); a name check here would always pass
	# and the action reads below would run off-device.
	if XRServer.get_tracker(controller.tracker) == null:
		return false
	if controller.is_button_pressed("trigger_click"):
		return true
	return controller.is_button_pressed("trigger")


## All live hand trackers, keyed "left"/"right", found by iterating
## XRServer's TRACKER_HAND trackers and matching tracker.hand. This is the
## ONLY supported hand lookup: the "left_hand"/"right_hand" tracker names
## collide with the controller trackers, so a name lookup returns the
## controller and hands silently never activate.
static func find_hand_trackers() -> Dictionary:
	var res := {"left": null, "right": null}
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_HAND)
	for t in trackers.values():
		if t is XRHandTracker:
			var h: int = (t as XRHandTracker).hand
			if h == XRPositionalTracker.TRACKER_HAND_LEFT:
				res["left"] = t
			elif h == XRPositionalTracker.TRACKER_HAND_RIGHT:
				res["right"] = t
	return res


## v0.9.3: the hand ray+pinch core, extracted from the old _hand_state so
## DirectUIInput can run the identical logic independently of this node's
## signals. `hand_side` = XRPositionalTracker.TRACKER_HAND_LEFT/RIGHT;
## `origin` = the XROrigin3D (auto-found when null). Returns
## {"active": bool, "origin": Vector3, "dir": Vector3, "pinch": bool}.
static func hand_ray(hand_side: int, origin: Node3D) -> Dictionary:
	var res := {
		"active": false,
		"origin": Vector3.ZERO,
		"dir": Vector3(0.0, 0.0, 1.0),
		"pinch": false,
	}
	var found := XRUIPointer.find_hand_trackers()
	var tr: XRHandTracker = null
	if hand_side == XRPositionalTracker.TRACKER_HAND_LEFT:
		tr = found["left"] as XRHandTracker
	else:
		tr = found["right"] as XRHandTracker
	if tr == null or not tr.has_tracking_data:
		return res
	if not _joint_ok(tr, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		return res
	var prox := tr.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL)
	var thumb := tr.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index := tr.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	# Joint transforms are in tracking space; the XROrigin3D maps that to world.
	var o := _tracking_to_world(origin)
	var prox_w: Transform3D = o * prox
	var thumb_w: Transform3D = o * thumb
	var index_w: Transform3D = o * index
	res["active"] = true
	res["origin"] = prox_w.origin
	res["dir"] = -prox_w.basis.z.normalized()
	res["pinch"] = thumb_w.origin.distance_to(index_w.origin) < PINCH_THRESHOLD
	return res


func setup(p_viewport: SubViewport, p_quad: MeshInstance3D, p_origin: Node3D) -> void:
	ui_viewport = p_viewport
	ui_quad = p_quad
	xr_origin = p_origin
	_build_visuals()


func _build_visuals() -> void:
	var laser_mat := StandardMaterial3D.new()
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.albedo_color = Color(0.4, 0.95, 1.0)
	laser_mat.emission_enabled = true
	laser_mat.emission = Color(0.4, 0.95, 1.0)
	laser_mat.emission_energy_multiplier = 4.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = 1.0
	_laser = MeshInstance3D.new()
	_laser.name = "Laser"
	_laser.mesh = cyl
	_laser.material_override = laser_mat
	_laser.visible = false
	add_child(_laser)

	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1.0, 1.0, 1.0)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 1.0, 1.0)
	dot_mat.emission_energy_multiplier = 5.0
	var sph := SphereMesh.new()
	sph.radius = 0.024
	sph.height = 0.048
	_dot = MeshInstance3D.new()
	_dot.name = "HitDot"
	_dot.mesh = sph
	_dot.material_override = dot_mat
	_dot.visible = false
	add_child(_dot)


func _process(delta: float) -> void:
	if not xr_mode or not enabled or ui_viewport == null or ui_quad == null \
			or not is_visible_in_tree():
		_set_visuals(false, false)
		_was_pressed = false
		return
	var st: Dictionary
	if hand_side == 0:
		st = _controller_state()
	else:
		st = _hand_state(delta)
	if not bool(st["active"]):
		_set_visuals(false, false)
		_was_pressed = false
		return
	var origin: Vector3 = st["origin"]
	var dir: Vector3 = st["dir"]
	var hit := XRUIPointer.ray_to_viewport(origin, dir, ui_quad, Vector2(ui_viewport.size))
	var hit_ok := bool(hit["hit"])
	var end_point: Vector3 = hit["world"]
	if hit_ok:
		xr_moved.emit(hit["pos"])
	var pressed: bool = bool(st["pressed"]) and hit_ok
	if pressed and not _was_pressed:
		xr_clicked.emit(hit["pos"])
	_was_pressed = pressed
	_update_visuals(origin, end_point, hit_ok)


## True when this source's tracker is currently live (used by the hub to
## decide whether desktop-mouse fallback should stay quiet). Never touches
## tracker objects unless xr_mode is on (see the xr_mode doc comment).
func is_source_live() -> bool:
	if not xr_mode:
		return false
	if hand_side == 0:
		return controller != null and is_instance_valid(controller) \
			and XRServer.get_tracker(controller.tracker) != null
	return _hand_tracker_live()


## v0.9.3: hand liveness for the instance path, via the shared static
## hand_ray (tracker discovery is name-collision-safe there).
func _hand_tracker_live() -> bool:
	var hr := XRUIPointer.hand_ray(hand_side, xr_origin)
	return bool(hr["active"])


## True when this pointer is actually drawing a laser beam right now (laser
## visible AND drawn with non-trivial length). The hub keys the gaze-dwell
## fallback on this — "no beam actually drawn" — instead of tracker
## registration, so a registered-but-useless tracker can't suppress gaze.
func is_beam_visible() -> bool:
	if _laser == null or not _laser.visible:
		return false
	return _laser.global_transform.basis.y.length() > 0.01


func _controller_state() -> Dictionary:
	var res := {
		"active": false,
		"origin": Vector3.ZERO,
		"dir": Vector3(0.0, 0.0, 1.0),
		"pressed": false,
	}
	if controller == null or not is_instance_valid(controller):
		return res
	# No live tracker in XRServer (desktop/headless, or controller not
	# tracked) -> pointer stays hidden. (controller.get_tracker() only
	# returns the configured name StringName, so it can't be used here.)
	if XRServer.get_tracker(controller.tracker) == null:
		return res
	res["active"] = true
	var gt := controller.global_transform
	res["origin"] = gt.origin
	res["dir"] = -gt.basis.z.normalized()
	res["pressed"] = XRUIPointer.trigger_pressed(controller)
	return res


func _hand_state(_delta: float) -> Dictionary:
	# v0.9.3: the ray+pinch core is the shared static hand_ray() (used by
	# DirectUIInput too); this just maps it to the per-frame state shape.
	var hr := XRUIPointer.hand_ray(hand_side, xr_origin)
	return {
		"active": bool(hr["active"]),
		"origin": hr["origin"],
		"dir": hr["dir"],
		"pressed": bool(hr["pinch"]),
	}


func _set_visuals(laser_on: bool, dot_on: bool) -> void:
	if _laser != null:
		_laser.visible = laser_on
	if _dot != null:
		_dot.visible = dot_on


func _update_visuals(from: Vector3, to: Vector3, show_dot: bool) -> void:
	if _laser == null or _dot == null:
		return
	var length := from.distance_to(to)
	if length < 0.001:
		_set_visuals(false, false)
		return
	var d := (to - from) / length
	# Build an orthonormal basis with local +Y along the beam.
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var y := d
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	var mid := (from + to) * 0.5
	_laser.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3(1.0, length, 1.0)), mid)
	_laser.visible = true
	_dot.global_position = to
	_dot.visible = show_dot


## Pure-math ray vs. launcher quad. Returns {"hit": bool, "pos": Vector2
## (viewport px), "world": Vector3}. Misses still return a "world" point at
## fixed RAY_LENGTH so the laser has somewhere to go.
static func ray_to_viewport(
	origin: Vector3, dir: Vector3, quad: MeshInstance3D, vp_size: Vector2
) -> Dictionary:
	var res := {
		"hit": false,
		"pos": Vector2.ZERO,
		"world": origin + dir * RAY_LENGTH,
	}
	if quad == null or not is_instance_valid(quad):
		return res
	var qmesh := quad.mesh as QuadMesh
	if qmesh == null or qmesh.size.x <= 0.0 or qmesh.size.y <= 0.0:
		return res
	var qx := quad.global_transform
	var n := qx.basis.z.normalized()
	var denom := dir.dot(n)
	if absf(denom) < 0.00001:
		return res
	var t := (qx.origin - origin).dot(n) / denom
	if t < 0.0:
		return res
	var world := origin + dir * t
	var local: Vector3 = qx.affine_inverse() * world
	var u := local.x / qmesh.size.x + 0.5
	var v := 0.5 - local.y / qmesh.size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		res["world"] = world
		return res
	res["hit"] = true
	res["pos"] = Vector2(u * vp_size.x, v * vp_size.y)
	res["world"] = world
	return res


# --------------------------------- v0.9.0 gesture vocabulary (grab/throw) ---

## Hand sides for the gesture API (match XRPositionalTracker constants).
const HAND_LEFT_SIDE := 1   # XRPositionalTracker.TRACKER_HAND_LEFT
const HAND_RIGHT_SIDE := 2  # XRPositionalTracker.TRACKER_HAND_RIGHT

## Release-velocity tracking: per-hand ring of recent pinch-midpoint samples.
static var _grab_history: Dictionary = {}   # side -> Array of [time_s, Vector3]
static var _grab_was_pinch: Dictionary = {}  # side -> bool
static var _grab_release_vel: Dictionary = {}  # side -> Vector3 (last release)
static var _grab_held: Dictionary = {}  # side -> Node3D (game-attached)
static var _grab_just_released: Dictionary = {}  # side -> bool (edge, cleared on read)

const _GRAB_WINDOW := 0.15  # seconds of history used for release velocity


## Pinch midpoint of a hand in world space, or null when the hand isn't
## tracked / not pinching. `origin` = XROrigin3D (auto-found when null).
static func pinch_point(hand_side: int, origin: Node3D = null) -> Variant:
	var tr := _hand_tracker_for(hand_side)
	if tr == null or not tr.has_tracking_data:
		return null
	var thumb := tr.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index := tr.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	if not _joint_ok(tr, XRHandTracker.HAND_JOINT_THUMB_TIP) \
			or not _joint_ok(tr, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		return null
	var o := _tracking_to_world(origin)
	var tw: Vector3 = (o * thumb).origin
	var iw: Vector3 = (o * index).origin
	if tw.distance_to(iw) > PINCH_THRESHOLD * 1.6:
		return null
	return (tw + iw) * 0.5


## Grab state for a hand. Call every frame; the helper tracks pinch history
## internally. Returns {"active": bool (pinching now),
## "grab_point": Vector3 (pinch midpoint, world), "held_node": Node3D|null}.
## Attach a held object with set_held_node(); it follows grab_point while
## active. On release, throw_release_velocity(hand) gives the fling vector.
static func grab_state(hand_side: int, origin: Node3D = null) -> Dictionary:
	var res := {"active": false, "grab_point": Vector3.ZERO, "held_node": null}
	var pt: Variant = pinch_point(hand_side, origin)
	var pinching := pt != null
	var was: bool = bool(_grab_was_pinch.get(hand_side, false))
	_grab_was_pinch[hand_side] = pinching
	var now := Time.get_ticks_msec() / 1000.0
	if pinching:
		var hist: Array = _grab_history.get(hand_side, [])
		hist.append([now, pt])
		while not hist.is_empty() and now - float(hist[0][0]) > _GRAB_WINDOW:
			hist.pop_front()
		_grab_history[hand_side] = hist
		res["active"] = true
		res["grab_point"] = pt
		var held = _grab_held.get(hand_side, null)
		if held != null and is_instance_valid(held):
			res["held_node"] = held
			(held as Node3D).global_position = pt
	elif was:
		# Just released: compute velocity from the history window.
		_grab_release_vel[hand_side] = _velocity_from_history(hand_side)
		_grab_history[hand_side] = []
		_grab_just_released[hand_side] = true
	return res


## True exactly once after a pinch release (edge-triggered; cleared on read).
## Use with throw_release_velocity() to detect "just let go".
static func was_released(hand_side: int) -> bool:
	var r := bool(_grab_just_released.get(hand_side, false))
	_grab_just_released[hand_side] = false
	return r


## Hand velocity at the moment of the last pinch release (world m/s).
## Zero when the hand never grabbed. Kept until the next release.
static func throw_release_velocity(hand_side: int) -> Vector3:
	return _grab_release_vel.get(hand_side, Vector3.ZERO)


## Attach a node to a hand's grab (it follows grab_point while pinching).
static func set_held_node(hand_side: int, node: Node3D) -> void:
	if node == null:
		_grab_held.erase(hand_side)
	else:
		_grab_held[hand_side] = node


## Detach without throwing.
static func release_grab(hand_side: int) -> void:
	_grab_held.erase(hand_side)
	_grab_history[hand_side] = []
	_grab_was_pinch[hand_side] = false


## Distance between the two pinch points (world meters) for two-hand
## scale gestures in CREATE apps. Returns -1.0 unless BOTH hands pinch.
static func two_hand_pinch_distance(origin: Node3D = null) -> float:
	var l: Variant = pinch_point(HAND_LEFT_SIDE, origin)
	var r: Variant = pinch_point(HAND_RIGHT_SIDE, origin)
	if l == null or r == null:
		return -1.0
	return (l as Vector3).distance_to(r as Vector3)


static func _velocity_from_history(hand_side: int) -> Vector3:
	var hist: Array = _grab_history.get(hand_side, [])
	if hist.size() < 2:
		return Vector3.ZERO
	var first: Array = hist[0]
	var last: Array = hist[hist.size() - 1]
	var dt := float(last[0]) - float(first[0])
	if dt < 0.02:
		return Vector3.ZERO
	return ((last[1] as Vector3) - (first[1] as Vector3)) / dt


static func _hand_tracker_for(hand_side: int) -> XRHandTracker:
	var found := XRUIPointer.find_hand_trackers()
	if hand_side == HAND_LEFT_SIDE:
		return found["left"] as XRHandTracker
	return found["right"] as XRHandTracker


static func _joint_ok(tr: XRHandTracker, joint: int) -> bool:
	var flags: int = tr.get_hand_joint_flags(joint)
	var need: int = XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID \
		| XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	return (flags & need) == need


static func _tracking_to_world(origin: Node3D) -> Transform3D:
	if origin != null and is_instance_valid(origin):
		return origin.global_transform
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var found := tree.root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			return (found[0] as Node3D).global_transform
	return Transform3D.IDENTITY
