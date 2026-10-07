## RoomKit - v0.7.0 shared module: Meta Scene API (room layout) access.
##
## Thin static wrapper around the godot_openxr_vendors OpenXRFbSceneManager.
## Verified against the plugin binary (headless, Godot 4.7):
##   OpenXRFbSceneManager: create_scene_anchors(), are_scene_anchors_created(),
##     request_scene_capture(), is_scene_capture_supported(),
##     get_anchor_uuids() -> PackedStringArray,
##     get_anchor_node(uuid) -> XRAnchor3D, get_spatial_entity(uuid).
##   OpenXRFbSpatialEntity: COMPONENT_TYPE_BOUNDED_2D=3, BOUNDED_3D=4,
##     SEMANTIC_LABELS=5, ROOM_LAYOUT=6; get_semantic_labels(),
##     get_bounding_box_2d() -> Rect2, get_bounding_box_3d() -> AABB.
##
## Headless-safe: with no XR runtime (or no room data) every getter returns
## a fallback (empty arrays, DEFAULT_BOUNDS) and refresh()/request_capture()
## are silent no-ops. Nothing here ever pushes errors in the fallback path.
##
## Performance: results are cached. The scene is only (re-)queried inside
## refresh(). Call refresh() once (e.g. in _ready), then use the getters.
## Never run scene queries per frame.
class_name RoomKit extends RefCounted

## Default floor extents (meters, world XZ) when no room data is available.
const DEFAULT_BOUNDS := Rect2(-2.0, -2.0, 4.0, 4.0)

static var _mgr: Object = null
static var _hooked := false
static var _refresh_queued := false
static var _walls: Array[Dictionary] = []
static var _tables: Array[Dictionary] = []
static var _furniture: Array[Dictionary] = []
## Generic anchor index: lowercased semantic label -> Array[Dictionary] of
## {position: Vector3 (world center), size: Vector3 (full extents; quads get
## a thin 0.1m depth), yaw: float (radians, world Y), label: String,
## kind: String ("box" or "quad")}.
static var _anchors: Dictionary = {}
static var _bounds := DEFAULT_BOUNDS
static var _has_data := false
static var _comp_2d := -1
static var _comp_3d := -1
static var _bx0 := 0.0
static var _bz0 := 0.0
static var _bx1 := 0.0
static var _bz1 := 0.0
static var _bounds_source := false


## True when XR is running and the Scene API manager can be used.
static func is_available() -> bool:
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		return false
	return _xr_running() and _manager() != null


## True when a room layout has been parsed (see refresh()).
static func has_room_data() -> bool:
	return _has_data


## (Re-)query the room layout and rebuild the caches. Safe no-op when
## XR / the Scene API is unavailable. This is the one call designed to be
## used unguarded; guard all getters with is_available()/has_room_data().
## May finish one frame later when called from a game's _ready() (the
## manager node is added deferred so tree setup is never disturbed).
static func refresh() -> void:
	_has_data = false
	var mgr := _manager()
	if mgr == null or not _xr_running():
		_refresh_queued = false
		return
	var mnode := mgr as Node
	var tree := Engine.get_main_loop() as SceneTree
	if mnode == null or not mnode.is_inside_tree():
		# Manager was added deferred (e.g. refresh() from a game's _ready
		# while the tree was busy): retry once the tree is idle.
		if tree != null and not _refresh_queued:
			_refresh_queued = true
			await tree.process_frame
			_refresh_queued = false
			refresh()
		return
	_refresh_queued = false
	if mgr.has_method("are_scene_anchors_created") and not bool(mgr.are_scene_anchors_created()):
		if mgr.has_method("create_scene_anchors"):
			mgr.create_scene_anchors()
	if not _hooked and mgr.has_signal("openxr_fb_scene_capture_completed"):
		_hooked = true
		mgr.connect("openxr_fb_scene_capture_completed", func() -> void: refresh())
	_parse(mgr)


## Ask the headset to (re-)capture the room. Safe no-op when unsupported.
## Call refresh() again after the capture completes to pick up new data
## (refresh() is also triggered automatically via the capture signal).
static func request_capture() -> void:
	var mgr := _manager()
	if mgr == null:
		return
	if mgr.has_method("is_scene_capture_supported") and bool(mgr.is_scene_capture_supported()):
		if mgr.has_method("request_scene_capture"):
			mgr.request_scene_capture()


## Real walls as vertical planes (world space):
## {position: Vector3 center, size: Vector2 (width, height),
##  normal: Vector3 normalized plane normal}.
static func get_walls() -> Array[Dictionary]:
	return _walls.duplicate()


## Tables/desks as cuboids (world space):
## {position: Vector3 box center, size: Vector3 full extents}.
static func get_tables() -> Array[Dictionary]:
	return _tables.duplicate()


## Other cuboid anchors (couches, beds, storage, ...):
## {position: Vector3, size: Vector3, label: String}.
static func get_furniture() -> Array[Dictionary]:
	return _furniture.duplicate()


## Furniture whose label contains the given substring (case-insensitive),
## e.g. "couch", "bed", "storage", "screen", "plant".
static func get_furniture_by_label(label: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := label.to_lower()
	for f in _furniture:
		if str(f.get("label", "")).contains(key):
			out.append(f)
	return out


## First couch cuboid, or {} when the room has none.
static func get_couch() -> Dictionary:
	var found := get_furniture_by_label("couch")
	return found[0] if not found.is_empty() else {}


## First bed cuboid, or {} when the room has none.
static func get_bed() -> Dictionary:
	var found := get_furniture_by_label("bed")
	return found[0] if not found.is_empty() else {}


## All storage cuboids (shelves, cabinets, ...), possibly empty.
static func get_storage() -> Array[Dictionary]:
	return get_furniture_by_label("storage")


## Move a Node3D to the top-center of a furniture cuboid (world space),
## e.g. to sit a prop or pet on a couch/table. No-op on empty cuboid.
static func place_on_cuboid(node: Node3D, cuboid: Dictionary, y_offset := 0.0) -> void:
	if cuboid.is_empty() or not is_instance_valid(node):
		return
	var pos: Vector3 = cuboid["position"]
	var size: Vector3 = cuboid["size"]
	node.global_position = Vector3(pos.x, pos.y + size.y * 0.5 + y_offset, pos.z)


## Top-center point of a cuboid (world space); Vector3.ZERO on empty cuboid.
static func cuboid_top(cuboid: Dictionary) -> Vector3:
	if cuboid.is_empty():
		return Vector3.ZERO
	var pos: Vector3 = cuboid["position"]
	var size: Vector3 = cuboid["size"]
	return Vector3(pos.x, pos.y + size.y * 0.5, pos.z)


## Generic anchor query: all anchors whose semantic label contains `label`
## (case-insensitive substring). Covers every Scene API label: "couch",
## "chair", "table", "bed", "storage", "screen"/"tv", "lamp", "plant",
## "door", "window", "wall", "floor", "ceiling", "rug", ...
## Returns Array[Dictionary] of {position: Vector3, size: Vector3,
## yaw: float, label: String, kind: String ("box"/"quad")}. Empty when none.
static func get_anchors(label: String) -> Array[Dictionary]:
	var key := label.to_lower()
	var out: Array[Dictionary] = []
	for stored_key in _anchors.keys():
		if str(stored_key).contains(key) or key.contains(str(stored_key)):
			for a in _anchors[stored_key]:
				out.append(a)
	return out


## Instantiate a skin scene aligned to an anchor cuboid/quad and add it to
## the current scene. `skin` may be a PackedScene or a res:// path String.
## Returns the instance (or null on empty anchor / bad skin).
static func skin_anchor(anchor: Dictionary, skin) -> Node3D:
	if anchor.is_empty():
		return null
	var ps: PackedScene = null
	if skin is PackedScene:
		ps = skin
	elif skin is String and ResourceLoader.exists(skin):
		ps = load(skin) as PackedScene
	if ps == null or not ps.can_instantiate():
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = tree.current_scene if tree != null and tree.current_scene != null else (tree.root if tree != null else null)
	if parent == null:
		inst.queue_free()
		return null
	parent.add_child(inst)
	inst.global_position = anchor["position"]
	inst.global_rotation.y = float(anchor.get("yaw", 0.0))
	return inst


## Apply a themed morph skin to an anchor by name. Skin names:
## "scifi", "arcane", "lava", "underwater", "haunted", "candy",
## "neon", "nature". Returns the skin root node, or null when the
## anchor is empty or the MorphSkins library is unavailable.
## The skin is a shell/aura around the anchor cuboid (passthrough still
## shows the real object underneath) + particles + a short sound.
static func morph(anchor: Dictionary, skin_name: String) -> Node3D:
	if anchor.is_empty():
		return null
	# Dynamic lookup: the MorphSkins library may not exist in older builds.
	const SKIN_SCRIPT := "res://scripts/shared/morph_skins.gd"
	if not ResourceLoader.exists(SKIN_SCRIPT):
		return null
	var ms: GDScript = load(SKIN_SCRIPT) as GDScript
	if ms == null:
		return null
	var node: Node3D = ms.call("build", skin_name.to_lower(), anchor) as Node3D
	if node == null or not is_instance_valid(node):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = tree.current_scene if tree != null and tree.current_scene != null else (tree.root if tree != null else null)
	if parent == null:
		node.queue_free()
		return null
	parent.add_child(node)
	node.global_position = anchor["position"]
	node.global_rotation.y = float(anchor.get("yaw", 0.0))
	ms.call("play_morph_sound", parent)
	return node


## Floor XZ extents in world space; DEFAULT_BOUNDS when unknown.
static func room_bounds() -> Rect2:
	return _bounds


# ------------------------------------------------------------- internal ----

static func _xr_running() -> bool:
	var xr := XRServer.primary_interface
	if xr == null:
		return false
	if xr.has_method("is_initialized") and not xr.is_initialized():
		return false
	return true


## Lazily create the internal SceneManager node on the scene root.
## Untyped on purpose: keeps this script parseable even if the vendor
## plugin is ever disabled (ClassDB lookups instead of direct refs).
static func _manager() -> Object:
	if _mgr != null:
		if is_instance_valid(_mgr):
			return _mgr
		_mgr = null
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var inst: Object = ClassDB.instantiate("OpenXRFbSceneManager")
	if not (inst is Node):
		return null
	(inst as Node).name = "RoomKitSceneManager"
	_mgr = inst
	# Deferred add: always safe, even when refresh() is called from a game's
	# _ready() while the scene tree is busy setting up children (a direct
	# add_child there fails with "parent is busy"). refresh() waits until the
	# manager is actually inside the tree before querying.
	tree.root.add_child.call_deferred(inst)
	return _mgr


static func _component_type(label: String, fallback: int) -> int:
	if ClassDB.class_exists("OpenXRFbSpatialEntity"):
		return ClassDB.class_get_integer_constant("OpenXRFbSpatialEntity", label)
	return fallback


static func _grow_bounds(x: float, z: float) -> void:
	if not _bounds_source:
		_bounds_source = true
		_bx0 = x
		_bz0 = z
		_bx1 = x
		_bz1 = z
		return
	_bx0 = minf(_bx0, x)
	_bz0 = minf(_bz0, z)
	_bx1 = maxf(_bx1, x)
	_bz1 = maxf(_bz1, z)


static func _parse(mgr: Object) -> void:
	_walls.clear()
	_tables.clear()
	_furniture.clear()
	_anchors.clear()
	_bounds = DEFAULT_BOUNDS
	_bounds_source = false
	if _comp_2d < 0:
		_comp_2d = _component_type("COMPONENT_TYPE_BOUNDED_2D", 3)
		_comp_3d = _component_type("COMPONENT_TYPE_BOUNDED_3D", 4)
	var uuids := PackedStringArray()
	if mgr.has_method("get_anchor_uuids"):
		uuids = mgr.get_anchor_uuids()
	var found := 0
	for i in uuids.size():
		var uuid := uuids[i]
		var node: Object = mgr.get_anchor_node(uuid) if mgr.has_method("get_anchor_node") else null
		var ent: Object = mgr.get_spatial_entity(uuid) if mgr.has_method("get_spatial_entity") else null
		if node == null or ent == null or not (node is Node3D):
			continue
		if _parse_entity(node as Node3D, ent):
			found += 1
	if _bounds_source:
		_bounds = Rect2(_bx0, _bz0, _bx1 - _bx0, _bz1 - _bz0)
	_has_data = found > 0


## Classify one spatial entity; returns true when it contributed room data.
static func _parse_entity(node: Node3D, ent: Object) -> bool:
	if not ent.has_method("get_semantic_labels") or not ent.has_method("is_component_supported"):
		return false
	var labels: PackedStringArray = ent.get_semantic_labels()
	var joined := " ".join(labels).to_lower()
	var has_2d := bool(ent.is_component_supported(_comp_2d))
	var has_3d := bool(ent.is_component_supported(_comp_3d))
	var t := node.global_transform
	var yaw := float(t.basis.get_euler().y)
	# Generic anchor index: record every labeled entity so get_anchors()
	# can serve any semantic label (couch, chair, tv/screen, lamp, plant,
	# door, window, rug, ...).
	var primary := str(labels[0]).to_lower() if not labels.is_empty() else "unknown"
	if has_3d and ent.has_method("get_bounding_box_3d"):
		var abox: AABB = ent.get_bounding_box_3d()
		var ascale := t.basis.get_scale()
		var asize := Vector3(abox.size.x * ascale.x, abox.size.y * ascale.y, abox.size.z * ascale.z)
		var acenter: Vector3 = t * abox.get_center()
		_record_anchor(primary, {"position": acenter, "size": asize, "yaw": yaw, "label": primary, "kind": "box"})
	elif has_2d and ent.has_method("get_bounding_box_2d"):
		var qbox: Rect2 = ent.get_bounding_box_2d()
		var qcenter: Vector3 = t * Vector3(qbox.get_center().x, qbox.get_center().y, 0.0)
		_record_anchor(primary, {"position": qcenter, "size": Vector3(qbox.size.x, qbox.size.y, 0.1), "yaw": yaw, "label": primary, "kind": "quad"})
	if joined.contains("wall") and has_2d and ent.has_method("get_bounding_box_2d"):
		var box: Rect2 = ent.get_bounding_box_2d()
		if maxf(box.size.x, box.size.y) < 1.0:
			return false # wall art, not a wall
		var center: Vector3 = t * Vector3(box.get_center().x, box.get_center().y, 0.0)
		var normal: Vector3 = (-t.basis.z).normalized()
		_walls.append({"position": center, "size": box.size, "normal": normal})
		_grow_bounds(center.x, center.z)
		return true
	if joined.contains("floor") and has_2d and ent.has_method("get_bounding_box_2d"):
		var box2: Rect2 = ent.get_bounding_box_2d()
		var corners := [box2.position, box2.position + Vector2(box2.size.x, 0.0),
			box2.position + Vector2(0.0, box2.size.y), box2.position + box2.size]
		for c_v in corners:
			var c: Vector2 = c_v
			var wc: Vector3 = t * Vector3(c.x, c.y, 0.0)
			_grow_bounds(wc.x, wc.z)
		return true
	if (joined.contains("table") or joined.contains("desk")) and has_3d:
		var d := _cuboid(node, ent)
		if d.is_empty():
			return false
		_tables.append(d)
		return true
	if joined.contains("ceiling") or joined.contains("room"):
		return false
	if has_3d and not labels.is_empty():
		var d2 := _cuboid(node, ent)
		if d2.is_empty():
			return false
		d2["label"] = str(labels[0]).to_lower()
		_furniture.append(d2)
		return true
	return false


## World-space cuboid from a BOUNDED_3D entity; {} when unavailable.
static func _cuboid(node: Node3D, ent: Object) -> Dictionary:
	if not ent.has_method("get_bounding_box_3d"):
		return {}
	var box: AABB = ent.get_bounding_box_3d()
	var t := node.global_transform
	var sc := t.basis.get_scale()
	var size := Vector3(box.size.x * sc.x, box.size.y * sc.y, box.size.z * sc.z)
	var center: Vector3 = t * box.get_center()
	return {"position": center, "size": size}


static func _record_anchor(label: String, anchor: Dictionary) -> void:
	if not _anchors.has(label):
		_anchors[label] = []
	(_anchors[label] as Array).append(anchor)
