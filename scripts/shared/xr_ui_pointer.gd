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
## trigger press edge. Trigger detection is hardened (see trigger_pressed()):
## the shipped action map types "trigger_click" as boolean and "trigger" as an
## analog float axis, so all three reads are OR-ed — whichever typing the
## active map uses, the press registers.
## Hands: XRHandTracker found by iterating XRServer TRACKER_HAND trackers and
## matching tracker.hand (XRPositionalTracker.TRACKER_HAND_LEFT/RIGHT). NEVER
## by tracker name: "left_hand"/"right_hand" also name the CONTROLLER
## trackers, so XRServer.get_tracker() returns the controller instead and the
## "is XRHandTracker" check fails -> hands never activate.
## Gaze: hub.gd drives a camera-center fallback (reticle + dwell) through
## ray_to_viewport(); this script stays per-source only.

signal xr_clicked(viewport_pos: Vector2)
signal xr_moved(viewport_pos: Vector2)

const TRIGGER_THRESHOLD := 0.7
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

var _hand_tracker: XRHandTracker = null
var _was_pressed := false
var _laser: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _find_cooldown := 0.0


## Hardened trigger-press test for a controller. Treats the trigger as
## pressed if ANY of these read true:
##   1. is_button_pressed("trigger_click") — boolean in the shipped map.
##   2. get_float("trigger") > TRIGGER_THRESHOLD — "trigger" is an analog
##      float axis in the shipped map (Godot's default OpenXR map).
##   3. is_button_pressed("trigger") — covers maps that type "trigger" as a
##      boolean instead.
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
	if controller.get_float("trigger") > TRIGGER_THRESHOLD:
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
	laser_mat.emission_energy_multiplier = 2.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
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
	dot_mat.emission_energy_multiplier = 3.0
	var sph := SphereMesh.new()
	sph.radius = 0.016
	sph.height = 0.032
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
	return _hand_tracker != null and _hand_tracker.has_tracking_data


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


func _hand_state(delta: float) -> Dictionary:
	var res := {
		"active": false,
		"origin": Vector3.ZERO,
		"dir": Vector3(0.0, 0.0, 1.0),
		"pressed": false,
	}
	if _hand_tracker == null:
		_find_cooldown -= delta
		if _find_cooldown <= 0.0:
			_find_cooldown = 1.0
			_hand_tracker = _lookup_hand_tracker()
		if _hand_tracker == null:
			return res
	if not _hand_tracker.has_tracking_data:
		return res
	var tip_flags: int = _hand_tracker.get_hand_joint_flags(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	var need: int = XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID \
		| XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	if (tip_flags & need) == 0:
		return res
	var prox := _hand_tracker.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL)
	var thumb := _hand_tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP)
	var index := _hand_tracker.get_hand_joint_transform(
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	# Joint transforms are in tracking space; the XROrigin3D maps that to world.
	var o := Transform3D.IDENTITY
	if xr_origin != null and is_instance_valid(xr_origin):
		o = xr_origin.global_transform
	var prox_w: Transform3D = o * prox
	var thumb_w: Transform3D = o * thumb
	var index_w: Transform3D = o * index
	res["active"] = true
	res["origin"] = prox_w.origin
	res["dir"] = -prox_w.basis.z.normalized()
	res["pressed"] = thumb_w.origin.distance_to(index_w.origin) < PINCH_THRESHOLD
	return res


func _lookup_hand_tracker() -> XRHandTracker:
	var found := XRUIPointer.find_hand_trackers()
	if hand_side == XRPositionalTracker.TRACKER_HAND_LEFT:
		return found["left"] as XRHandTracker
	return found["right"] as XRHandTracker


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
