## BodyTracker.gd - shared body-tracking helper for NEXUS ARCADE.
## v0.9.0 (AI_API_ROADMAP #3). Verified against the 5.1.0 plugin binary and
## Godot 4.7's XRBodyTracker class:
##   - the vendor plugin registers a Godot XRBodyTracker via the
##     OpenXRFbBodyTrackingExtension node (one class handles XR_FB_body_tracking
##     and XR_META_body_tracking_full_body)
##   - joint data: XRBodyTracker.get_joint_flags(joint) /
##     get_joint_transform(joint), joints JOINT_ROOT..JOINT_MAX (87)
##   - flags: JOINT_FLAG_POSITION_VALID=4, JOINT_FLAG_POSITION_TRACKED=8
##   - trackers live under XRServer.TRACKER_BODY
##
## BodyTracker (static): find the tracker, read smoothed joint poses.
## BodyPoseMirror (Node3D, same file): copy the player's pose onto an
## avatar rig each frame — the Skeleton Dance showcase pattern.
##
## Noise tolerance: every joint is exponentially smoothed (configurable
## alpha), only joints with POSITION_VALID|POSITION_TRACKED are used, and
## when no body data is available the mirror falls back to hands-only
## (two hand spheres) instead of freezing or erroring.
## NOTE: joint accuracy is estimate-grade on Quest 3 — design dances
## tolerant of noise. Device verification required.
class_name BodyTracker
extends RefCounted

## Smoothing for joint positions (0 = frozen, 1 = raw). 0.35 tracks motion
## while visibly damping estimate jitter.
const SMOOTH_ALPHA := 0.35
## Joints below this confidence weight are ignored for the frame.
const POS_FLAGS := 12  # JOINT_FLAG_POSITION_VALID | JOINT_FLAG_POSITION_TRACKED

static var _ext_node: Node = null
static var _smoothed: Dictionary = {}  # joint int -> Vector3 (tracking space)


## True when a live body tracker with joint data is available.
static func is_available() -> bool:
	return get_tracker() != null


## The XRBodyTracker registered by the vendor plugin (or null headless).
static func get_tracker() -> XRBodyTracker:
	if not ClassDB.class_exists("XRBodyTracker"):
		return null
	_ensure_extension()
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_BODY)
	for t in trackers.values():
		if t is XRBodyTracker:
			return t as XRBodyTracker
	return null


## Smoothed world-space position of a joint (JOINT_* constant). Returns
## null when the joint is untracked this frame. `origin` maps tracking
## space to world (XROrigin3D); found automatically when omitted.
static func joint_position(joint: int, origin: Node3D = null) -> Variant:
	var tracker := get_tracker()
	if tracker == null or not tracker.has_tracking_data:
		return null
	var flags: int = tracker.get_joint_flags(joint)
	if (flags & POS_FLAGS) != POS_FLAGS:
		return null
	var local: Transform3D = tracker.get_joint_transform(joint)
	var o := _origin(origin)
	var world: Vector3 = (o * local).origin
	var prev: Vector3 = _smoothed.get(joint, world)
	var smoothed := prev.lerp(world, SMOOTH_ALPHA)
	_smoothed[joint] = smoothed
	return smoothed


## Convenience: head + both wrists + hips (the joints a dance mirror needs).
## Returns {"head": v3|null, "l_hand": v3|null, "r_hand": v3|null,
##          "hips": v3|null, "tracked": bool}.
static func dance_joints(origin: Node3D = null) -> Dictionary:
	return {
		"head": joint_position(XRBodyTracker.JOINT_HEAD, origin),
		"l_hand": joint_position(XRBodyTracker.JOINT_LEFT_WRIST, origin),
		"r_hand": joint_position(XRBodyTracker.JOINT_RIGHT_WRIST, origin),
		"hips": joint_position(XRBodyTracker.JOINT_HIPS, origin),
		"tracked": is_available(),
	}


## Make sure the vendor extension node exists (it registers the tracker).
## Guarded: no-op when the plugin class is absent.
static func _ensure_extension() -> void:
	if not ClassDB.class_exists("OpenXRFbBodyTrackingExtension"):
		return
	if _ext_node != null and is_instance_valid(_ext_node):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var found := tree.root.find_children("*", "OpenXRFbBodyTrackingExtension", true, false)
	if not found.is_empty():
		_ext_node = found[0]
		return
	var ext: Object = ClassDB.instantiate("OpenXRFbBodyTrackingExtension")
	if ext is Node:
		(ext as Node).name = "BodyTrackerExtension"
		tree.root.add_child.call_deferred(ext as Node)
		_ext_node = ext as Node


static func _origin(preferred: Node3D) -> Transform3D:
	if preferred != null and is_instance_valid(preferred):
		return preferred.global_transform
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var found := tree.root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			return (found[0] as Node3D).global_transform
	return Transform3D.IDENTITY


## BodyPoseMirror: attach to a scene, point `avatar_root` at a rig whose
## children are named joint names ("head", "l_hand", "r_hand", "hips", ...),
## and the avatar mirrors the player. Falls back to hands-only (two glowing
## spheres at the wrist positions, or at the XR hand trackers when even
## body data is absent) so the showcase never shows a frozen body.
class BodyPoseMirror:
	extends Node3D

	## Avatar root: children named "head"/"l_hand"/"r_hand"/"hips" (Node3D)
	## get driven. Optional — without it, only the hand spheres show.
	var avatar_root: Node3D = null
	## World offset applied to the mirrored pose (e.g. place the dancer).
	var pose_offset := Vector3.ZERO
	## Scale applied to the mirrored pose (avatar proportions).
	var pose_scale := 1.0

	var _hands_only := true
	var _l_sphere: MeshInstance3D = null
	var _r_sphere: MeshInstance3D = null

	func _ready() -> void:
		_build_hand_spheres()

	func _process(_delta: float) -> void:
		var j := BodyTracker.dance_joints(self)
		var any := j["head"] != null or j["l_hand"] != null \
			or j["r_hand"] != null or j["hips"] != null
		_hands_only = not any
		if avatar_root != null and is_instance_valid(avatar_root):
			avatar_root.visible = any
		_drive(avatar_root, "head", j["head"])
		_drive(avatar_root, "l_hand", j["l_hand"])
		_drive(avatar_root, "r_hand", j["r_hand"])
		_drive(avatar_root, "hips", j["hips"])
		_update_hand_spheres(j)

	func _drive(root: Node3D, bone: String, pos: Variant) -> void:
		if root == null or pos == null:
			return
		var n := root.get_node_or_null(bone) as Node3D
		if n != null:
			n.global_position = (pos as Vector3) * pose_scale + pose_offset

	func _build_hand_spheres() -> void:
		for side in ["L", "R"]:
			var mi := MeshInstance3D.new()
			mi.name = "MirrorHand" + side
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			mi.mesh = sm
			mi.material_override = GraphicsPolish.glow(
				Color(0.5, 0.95, 1.0) if side == "L" else Color(1.0, 0.6, 0.9), 2.0)
			add_child(mi)
			if side == "L":
				_l_sphere = mi
			else:
				_r_sphere = mi

	func _update_hand_spheres(j: Dictionary) -> void:
		# Hands-only fallback: show the spheres whenever body joints are
		# missing, positioned from body wrists or XR hand trackers.
		var show := _hands_only
		_l_sphere.visible = show
		_r_sphere.visible = show
		if not show:
			return
		var lp: Variant = j["l_hand"]
		var rp: Variant = j["r_hand"]
		if lp == null or rp == null:
			var hands := XRUIPointer.find_hand_trackers()
			var o := BodyTracker._origin(self)
			for side in ["left", "right"]:
				var tr = hands[side]
				if tr != null and (tr as XRHandTracker).has_tracking_data:
					var tip: Transform3D = (tr as XRHandTracker).get_hand_joint_transform(
						XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
					var w: Vector3 = (o * tip).origin
					if side == "left" and lp == null:
						lp = w
					elif side == "right" and rp == null:
						rp = w
		if lp != null:
			_l_sphere.global_position = lp
		if rp != null:
			_r_sphere.global_position = rp
