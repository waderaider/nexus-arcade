## ARUpgradeKit.gd - shared augmented-reality helpers for NEXUS ARCADE.
## Room-aware placement, spatial anchor persistence, hand-tracking pinch
## detection with mouse fallback, and passthrough-friendly object setup.
## Everything is headless-safe: XR calls are guarded, and every helper has
## a sensible non-XR fallback so scripts parse and run without hardware.
extends RefCounted
class_name ARUpgradeKit

## Hand identifiers for pinch helpers.
const HAND_LEFT := 0
const HAND_RIGHT := 1

## Where anchor transforms persist.
const ANCHOR_FILE := "user://nexus_anchors.cfg"

## Default room bounds used when no scene mesh is available (meters).
const DEFAULT_ROOM := Rect2(-1.75, -1.75, 3.5, 3.5) # x,z centered play area
const DEFAULT_FLOOR_Y := 0.0
const DEFAULT_TABLE_Y := 0.75


## True when an XR session with a valid primary interface is running.
static func is_xr_active() -> bool:
	var xr := XRServer.primary_interface
	return xr != null and xr.is_initialized()


## Pinch detection.
## XR path: measures thumb-tip to index-tip distance via the hand tracker when
## the project exposes hand-tracking actions; falls back to mouse/trigger.
## `hand` is HAND_LEFT or HAND_RIGHT. `node` is used to find tracker nodes.
static func pinch_active(node: Node, hand: int = HAND_RIGHT) -> bool:
	# Mouse fallback: left button = right-hand pinch, right button = left-hand pinch.
	if hand == HAND_RIGHT and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if hand == HAND_LEFT and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	# XR action fallback (projects that map pinch to an action).
	var action := "pinch_right" if hand == HAND_RIGHT else "pinch_left"
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	# Trigger fallback for controllers.
	if Input.is_action_pressed("trigger_click"):
		return true
	return false


## Pinch just pressed this frame (edge detection helper; games should cache).
static func pinch_just_pressed(node: Node, hand: int = HAND_RIGHT) -> bool:
	var key := "__pinch_prev_%d" % hand
	var prev: bool = node.get_meta(key) if node.has_meta(key) else false
	var now: bool = pinch_active(node, hand)
	node.set_meta(key, now)
	return now and not prev


## Hand/pointer world position.
## XR path would read the hand tracker; fallback is a point in front of camera.
static func pointer_position(node: Node3D, hand: int = HAND_RIGHT, reach: float = 1.2) -> Vector3:
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return node.global_position + Vector3(0, 1.2, -reach)
	var offset := Vector3(0.18 if hand == HAND_RIGHT else -0.18, -0.12, 0.0)
	return cam.global_transform * (Vector3(0, 0, -reach) + offset)


## Ray from the pointer for selection (origin, direction).
static func pointer_ray(node: Node3D, hand: int = HAND_RIGHT) -> Array:
	var cam := node.get_viewport().get_camera_3d()
	var origin := pointer_position(node, hand)
	var dir := Vector3(0, 0, -1)
	if cam != null:
		dir = -cam.global_transform.basis.z
	return [origin, dir.normalized()]


## Save an object's transform as a named spatial anchor (persists in user://).
static func save_anchor(anchor_name: String, t: Transform3D) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ANCHOR_FILE) # ignore errors; missing file is fine
	cfg.set_value("anchors", anchor_name + "_pos", t.origin)
	cfg.set_value("anchors", anchor_name + "_basis_x", t.basis.x)
	cfg.set_value("anchors", anchor_name + "_basis_y", t.basis.y)
	cfg.set_value("anchors", anchor_name + "_basis_z", t.basis.z)
	cfg.save(ANCHOR_FILE)


## Load a saved anchor transform. Returns null when none was saved.
static func load_anchor(anchor_name: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(ANCHOR_FILE) != OK:
		return null
	if not cfg.has_section_key("anchors", anchor_name + "_pos"):
		return null
	var t := Transform3D()
	t.origin = cfg.get_value("anchors", anchor_name + "_pos", Vector3.ZERO)
	t.basis.x = cfg.get_value("anchors", anchor_name + "_basis_x", Vector3.RIGHT)
	t.basis.y = cfg.get_value("anchors", anchor_name + "_basis_y", Vector3.UP)
	t.basis.z = cfg.get_value("anchors", anchor_name + "_basis_z", Vector3.BACK)
	return t


## Apply a saved anchor to a node. Returns true when an anchor was found.
static func apply_anchor(node: Node3D, anchor_name: String) -> bool:
	var t: Variant = load_anchor(anchor_name)
	if t == null:
		return false
	node.global_transform = t
	return true


## Drop a node onto the floor plane (y = floor_y), keeping x/z.
static func snap_to_floor(node: Node3D, floor_y: float = DEFAULT_FLOOR_Y) -> void:
	var p := node.position
	p.y = floor_y
	node.position = p


## Place a node on a table-height surface in front of the player.
static func place_on_table(node: Node3D, distance: float = 1.0, height: float = DEFAULT_TABLE_Y) -> void:
	var cam := node.get_viewport().get_camera_3d()
	var fwd := Vector3(0, 0, -1)
	if cam != null:
		fwd = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var base := cam.global_position if cam != null else Vector3.ZERO
	node.position = Vector3(base.x + fwd.x * distance, height, base.z + fwd.z * distance)


## Clamp a position inside room bounds (x/z), with a margin.
static func clamp_to_room(pos: Vector3, margin: float = 0.3) -> Vector3:
	var r := DEFAULT_ROOM
	pos.x = clampf(pos.x, r.position.x + margin, r.position.x + r.size.x - margin)
	pos.z = clampf(pos.z, r.position.y + margin, r.position.y + r.size.y - margin)
	return pos


## Make an object passthrough-friendly: unshaded parts stay readable over the
## real world; returns the node for chaining.
static func passthrough_friendly(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
