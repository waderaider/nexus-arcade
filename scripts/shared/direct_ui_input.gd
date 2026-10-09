extends Node3D
class_name DirectUIInput
## DirectUIInput.gd — belt-and-suspenders UI input fallback (v0.9.3).
##
## Runs EVERY frame, independent of XRUIPointer signals and of any signal
## connections: for each live controller it raycasts from the raw
## XRController3D pose against the target quad (the same
## XRUIPointer.ray_to_viewport plane math), drives hover via motion_cb and
## injects a click on the raw trigger rising edge; hands do the same via the
## shared static XRUIPointer.hand_ray() + pinch rising edge.
##
## It draws its OWN bright-yellow beams from the raw tracker poses, so the
## user always sees where they're pointing even if XRUIPointer is fully dead
## (no signals, stale node refs, thin lasers — the v0.9.2 photo state).
##
## Both paths stay live simultaneously; click dedupe lives in the click_cb
## target (hub.inject_click / PauseExit._inject_click — one 120ms / 8px
## window), never here. Desktop mouse is untouched: this node only runs
## when xr_mode is set by its host.
##
## Hosts: NexusHub (launcher panel) and PauseExit (exit quad / pause quad,
## switched via set_target()). process_mode is ALWAYS so pause menus work
## under a paused tree.

const BEAM_RADIUS := 0.010
const BEAM_ENERGY := 5.0
const DOT_RADIUS := 0.024
const DOT_ENERGY := 5.0
const MAX_SOURCES := 4  # 2 controllers + 2 hands

## Set by the host every frame from get_viewport().use_xr (same contract as
## XRUIPointer.xr_mode).
var xr_mode := false

var _viewport: SubViewport = null
var _quad: MeshInstance3D = null
var _origin: Node3D = null
var _motion_cb := Callable()
var _click_cb := Callable()

var _beams: Array[MeshInstance3D] = []
var _dots: Array[MeshInstance3D] = []
var _beam_mat: StandardMaterial3D = null
var _dot_mat: StandardMaterial3D = null
var _prev_pressed := {}  # source key -> bool (rising-edge state)
var _beam_drawn_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_beam_pool()


## Wire the target quad + viewport and the host's inject callbacks.
## `origin` may be null — XROrigin3D is discovered automatically then.
func configure(
	p_viewport: SubViewport, p_quad: MeshInstance3D, p_origin: Node3D,
	motion_cb: Callable, click_cb: Callable
) -> void:
	_viewport = p_viewport
	_quad = p_quad
	_origin = p_origin
	_motion_cb = motion_cb
	_click_cb = click_cb


## Switch the target quad/viewport without re-wiring callbacks
## (PauseExit swaps between its exit-button quad and pause-overlay quad).
func set_target(p_viewport: SubViewport, p_quad: MeshInstance3D) -> void:
	_viewport = p_viewport
	_quad = p_quad


## Unix-ms of the last frame a fallback beam was actually drawn (0 = never).
func last_beam_drawn_msec() -> int:
	return _beam_drawn_msec


## True when at least one fallback beam is currently drawn.
func any_beam_visible() -> bool:
	for b in _beams:
		if is_instance_valid(b) and b.visible:
			return true
	return false


func _build_beam_pool() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.albedo_color = Color(1.0, 0.85, 0.1)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(1.0, 0.85, 0.1)
	_beam_mat.emission_energy_multiplier = BEAM_ENERGY
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = Color(1.0, 0.95, 0.3)
	_dot_mat.emission_enabled = true
	_dot_mat.emission = Color(1.0, 0.95, 0.3)
	_dot_mat.emission_energy_multiplier = DOT_ENERGY
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_RADIUS
	cyl.bottom_radius = BEAM_RADIUS
	cyl.height = 1.0
	var sph := SphereMesh.new()
	sph.radius = DOT_RADIUS
	sph.height = DOT_RADIUS * 2.0
	for i in MAX_SOURCES:
		var beam := MeshInstance3D.new()
		beam.name = "FallbackBeam%d" % i
		beam.mesh = cyl
		beam.material_override = _beam_mat
		beam.visible = false
		add_child(beam)
		_beams.append(beam)
		var dot := MeshInstance3D.new()
		dot.name = "FallbackDot%d" % i
		dot.mesh = sph
		dot.material_override = _dot_mat
		dot.visible = false
		add_child(dot)
		_dots.append(dot)


func _discover_origin() -> void:
	if _origin != null and is_instance_valid(_origin):
		return
	var tree := get_tree()
	if tree != null and tree.root != null:
		var found := tree.root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			_origin = found[0] as Node3D


func _process(_delta: float) -> void:
	if not xr_mode or _viewport == null or _quad == null \
			or not is_instance_valid(_quad) or not is_visible_in_tree():
		_hide_all()
		return
	_discover_origin()
	# Collect live sources: name-agnostic controller discovery (kills the
	# stale-LeftController/RightController-path failure), then hands.
	var sources: Array = []
	if _origin != null and is_instance_valid(_origin):
		for ctl in _origin.find_children("*", "XRController3D", true, false):
			var c := ctl as XRController3D
			if c == null or not is_instance_valid(c):
				continue
			if XRServer.get_tracker(c.tracker) == null:
				continue
			sources.append({"kind": "ctl", "key": c.get_instance_id(),
					"origin": c.global_transform.origin,
					"dir": -c.global_transform.basis.z.normalized(),
					"pressed": XRUIPointer.trigger_pressed(c)})
			if sources.size() >= MAX_SOURCES:
				break
	if sources.size() < MAX_SOURCES:
		for side_key in ["left", "right"]:
			var side := XRPositionalTracker.TRACKER_HAND_LEFT \
				if side_key == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
			var hr := XRUIPointer.hand_ray(side, _origin)
			if bool(hr["active"]):
				sources.append({"kind": "hand", "key": "hand_" + side_key,
						"origin": hr["origin"], "dir": hr["dir"],
						"pressed": bool(hr["pinch"])})
			if sources.size() >= MAX_SOURCES:
				break
	var vp_size := Vector2(_viewport.size)
	var used := 0
	for src in sources:
		var s: Dictionary = src
		var hit := XRUIPointer.ray_to_viewport(
			s["origin"], s["dir"], _quad, vp_size)
		var hit_ok := bool(hit["hit"])
		var end_point: Vector3 = hit["world"]
		if hit_ok and _motion_cb.is_valid():
			_motion_cb.call(hit["pos"])
		var pressed := bool(s["pressed"]) and hit_ok
		var key: Variant = s["key"]
		var was := bool(_prev_pressed.get(key, false))
		if pressed and not was and _click_cb.is_valid():
			_click_cb.call(hit["pos"])
		_prev_pressed[key] = pressed
		_place_beam(used, s["origin"], end_point, hit_ok)
		used += 1
	# Hide beams whose source went inactive this frame.
	for i in range(used, MAX_SOURCES):
		_beams[i].visible = false
		_dots[i].visible = false
	# Drop rising-edge state for sources that vanished entirely.
	var live_keys := {}
	for src in sources:
		live_keys[(src as Dictionary)["key"]] = true
	for k in _prev_pressed.keys():
		if not live_keys.has(k):
			_prev_pressed.erase(k)


func _place_beam(i: int, from: Vector3, to: Vector3, show_dot: bool) -> void:
	var beam := _beams[i]
	var dot := _dots[i]
	var length := from.distance_to(to)
	if length < 0.001:
		beam.visible = false
		dot.visible = false
		return
	var d := (to - from) / length
	# Orthonormal basis with local +Y along the beam (same math as
	# XRUIPointer._update_visuals).
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var y := d
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	var mid := (from + to) * 0.5
	beam.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3(1.0, length, 1.0)), mid)
	beam.visible = true
	dot.global_position = to
	dot.visible = show_dot
	_beam_drawn_msec = Time.get_ticks_msec()


func _hide_all() -> void:
	for b in _beams:
		if is_instance_valid(b):
			b.visible = false
	for d in _dots:
		if is_instance_valid(d):
			d.visible = false
