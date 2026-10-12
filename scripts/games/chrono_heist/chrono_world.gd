## ChronoWorld.gd - the vault room overlay for CHRONO HEIST.
## Safe on your wall, keycard pedestal, reader slot, loot, exit zone,
## laser tripwires. Graceful fallback when no room data exists.
## All state changes go through methods so ghosts can mime them safely.
class_name ChronoWorld
extends Node3D

signal keycard_slotted
signal safe_opened
signal loot_secured
signal escaped

const GRAB_DIST := 0.35

var keycard_slotted_in := false
var safe_unlocked := false
var safe_open := false
var loot_in_exit := false

var _keycard: MeshInstance3D
var _keycard_home := Vector3.ZERO
var _reader_slot := Vector3.ZERO
var _safe_door: MeshInstance3D
var _safe_handle: MeshInstance3D
var _handle_grab_offset := 0.0
var _loot: MeshInstance3D
var _loot_home := Vector3.ZERO
var _exit_pos := Vector3.ZERO
var _exit_r := 0.6
var _wall := {}  # picked wall dict (animator: camera mounts)
var _tripwires: Array = []  # [{a: Vector3, b: Vector3, node: MeshInstance3D}]
var _trip_active := false
var _grabbables := {}  # id -> MeshInstance3D
var _held := {}  # hand_id -> obj_id
var _hand_vel := {}  # hand_id -> Vector3


func build() -> void:
	_wall = _pick_wall()
	_build_safe(_wall)
	_build_pedestal_and_keycard(_wall)
	_build_exit(_wall)
	_build_tripwires(_wall)
	_build_lighting()


## Animator ambient hooks.
func safe_world_pos() -> Vector3:
	return _safe_handle.global_position if is_instance_valid(_safe_handle) else Vector3(0, 1.2, -2.4)


func wall_dict() -> Dictionary:
	return _wall


func _pick_wall() -> Dictionary:
	if get_node_or_null("/root/RoomKit") != null and RoomKit.has_room_data():
		var walls := RoomKit.get_walls()
		if not walls.is_empty():
			var w: Dictionary = walls[0]
			for cand in walls:
				if float((cand["size"] as Vector2).x) > float((w["size"] as Vector2).x):
					w = cand
			return w
	return {"position": Vector3(0, 1.4, -2.5), "size": Vector2(4, 2.6), "normal": Vector3(0, 0, 1)}


func _wall_basis(wall: Dictionary) -> Basis:
	var n: Vector3 = (wall["normal"] as Vector3).normalized()
	return Basis.looking_at(n, Vector3.UP)


func _build_safe(wall: Dictionary) -> void:
	var basis := _wall_basis(wall)
	var n: Vector3 = (wall["normal"] as Vector3).normalized()
	var center: Vector3 = (wall["position"] as Vector3) + n * 0.28
	center.y = 1.35
	var root := Node3D.new()
	root.position = center
	root.basis = basis
	add_child(root)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.28, 0.33)
	steel.metallic = 0.7
	steel.roughness = 0.4
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.9, 0.4)
	body.mesh = bm
	body.material_override = steel
	root.add_child(body)
	# Door (hinged on the left edge).
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.35, 0, 0.21)
	root.add_child(hinge)
	_safe_door = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.7, 0.9, 0.06)
	_safe_door.mesh = dm
	_safe_door.position = Vector3(0.35, 0, 0)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.35, 0.38, 0.44)
	dmat.metallic = 0.8
	dmat.roughness = 0.3
	_safe_door.material_override = dmat
	hinge.add_child(_safe_door)
	hinge.set_meta("hinge", true)
	root.set_meta("hinge_node", hinge)
	# Handle (grabbable).
	_safe_handle = MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.05
	hm.outer_radius = 0.08
	_safe_handle.mesh = hm
	_safe_handle.position = Vector3(0.55, 0, 0.06)
	_safe_handle.material_override = _glow_mat(Color(1.0, 0.8, 0.2))
	hinge.add_child(_safe_handle)
	_grabbables["handle"] = _safe_handle
	# Reader slot pedestal next to the safe.
	var reader := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.18, 0.3, 0.18)
	reader.mesh = rm
	reader.material_override = steel
	reader.position = center + Vector3(0.65, -0.55, 0)
	reader.basis = basis
	add_child(reader)
	var slot := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.12, 0.02, 0.03)
	slot.mesh = sm
	slot.material_override = _glow_mat(Color(0.2, 1.0, 0.4))
	slot.position = reader.position + Vector3(0, 0.16, 0)
	slot.basis = basis
	add_child(slot)
	_reader_slot = slot.position
	# Loot inside the safe (revealed when opened).
	_loot = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.11
	lm.height = 0.22
	_loot.mesh = lm
	_loot.material_override = _glow_mat(Color(1.0, 0.8, 0.15))
	_loot_home = center + n * 0.05
	_loot_home.y = 1.15
	_loot.position = _loot_home
	_loot.visible = false
	add_child(_loot)
	_grabbables["loot"] = _loot


func _build_pedestal_and_keycard(wall: Dictionary) -> void:
	var n: Vector3 = (wall["normal"] as Vector3).normalized()
	var base: Vector3 = wall["position"] as Vector3
	var spot := base + n * 1.6
	spot.y = 0.0
	var ped := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.16
	pm.bottom_radius = 0.2
	pm.height = 0.95
	ped.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.24)
	pmat.roughness = 0.6
	ped.material_override = pmat
	ped.position = spot + Vector3(0, 0.475, 0)
	add_child(ped)
	_keycard = MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.09, 0.005, 0.14)
	_keycard.mesh = km
	_keycard.material_override = _glow_mat(Color(0.2, 0.9, 1.0))
	_keycard_home = spot + Vector3(0, 0.98, 0)
	_keycard.position = _keycard_home
	add_child(_keycard)
	_grabbables["keycard"] = _keycard


func _build_exit(wall: Dictionary) -> void:
	var n: Vector3 = (wall["normal"] as Vector3).normalized()
	var base: Vector3 = wall["position"] as Vector3
	_exit_pos = base + n * 3.2
	_exit_pos.y = 0.02
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = _exit_r - 0.04
	tor.outer_radius = _exit_r
	ring.mesh = tor
	ring.rotation = Vector3(PI / 2.0, 0, 0)
	ring.position = _exit_pos
	ring.material_override = _glow_mat(Color(0.2, 1.0, 0.4))
	add_child(ring)
	var lbl := Label3D.new()
	lbl.text = "EXIT"
	lbl.font_size = 72
	lbl.pixel_size = 0.005
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = _exit_pos + Vector3(0, 0.5, 0)
	add_child(lbl)


func _build_tripwires(wall: Dictionary) -> void:
	var n: Vector3 = (wall["normal"] as Vector3).normalized()
	var base: Vector3 = wall["position"] as Vector3
	var mid := base + n * 2.4
	var side := n.cross(Vector3.UP).normalized()
	for i in [0.45, 0.95]:
		var a := mid - side * 1.1 + Vector3(0, i, 0)
		var b := mid + side * 1.1 + Vector3(0, i, 0)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var length := a.distance_to(b)
		bm.size = Vector3(length, 0.012, 0.012)
		beam.mesh = bm
		beam.material_override = _glow_mat(Color(1.0, 0.15, 0.15))
		beam.position = (a + b) * 0.5
		# Orient along the segment.
		var dir := (b - a).normalized()
		beam.basis = Basis.looking_at(dir, Vector3.UP)
		beam.visible = false
		add_child(beam)
		_tripwires.append({"a": a, "b": b, "node": beam})


func _build_lighting() -> void:
	var omni := OmniLight3D.new()
	omni.light_color = Color(0.25, 0.4, 0.8)
	omni.light_energy = 0.7
	omni.omni_range = 6.0
	omni.position = Vector3(0, 2.2, 0)
	add_child(omni)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	return m


# ------------------------------------------------------------ interaction ---

func set_tripwires_active(b: bool) -> void:
	_trip_active = b
	for t in _tripwires:
		(t["node"] as MeshInstance3D).visible = b


func trip_alarm_at(p: Vector3) -> bool:
	# True when p trips an active wire.
	if not _trip_active:
		return false
	for t in _tripwires:
		var a: Vector3 = t["a"]
		var b: Vector3 = t["b"]
		if _seg_dist(p, a, b) < 0.35:
			return true
	return false


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (a + ab * t - p).length()


func grabbable_near(p: Vector3, max_d := GRAB_DIST) -> String:
	var best := ""
	var best_d := max_d
	for id in _grabbables.keys():
		var node: MeshInstance3D = _grabbables[id]
		if not is_instance_valid(node) or not node.visible:
			continue
		if _held.values().has(id):
			continue
		if id == "keycard" and keycard_slotted_in:
			continue
		if id == "handle" and (safe_open or not safe_unlocked):
			continue
		var d := p.distance_to(node.position)
		if d < best_d:
			best_d = d
			best = id
	return best


func grab(hand_id: int, obj_id: String, hand_node: Node3D) -> bool:
	if obj_id == "" or _held.has(hand_id):
		return false
	_held[hand_id] = obj_id
	_hand_vel[hand_id] = hand_node
	if obj_id == "handle":
		_handle_grab_offset = to_local(hand_node.global_position).y
	return true


func release(hand_id: int, throw_vel: Vector3) -> void:
	if not _held.has(hand_id):
		return
	var obj_id: String = _held[hand_id]
	_held.erase(hand_id)
	if obj_id == "keycard" and not keycard_slotted_in:
		# Slot check: near the reader?
		if _keycard.position.distance_to(_reader_slot) < 0.22:
			slot_keycard()
			return
	if obj_id == "loot" and not loot_in_exit:
		if _loot.position.distance_to(_exit_pos) < _exit_r:
			secure_loot()
			return


func slot_keycard() -> void:
	if keycard_slotted_in:
		return
	keycard_slotted_in = true
	safe_unlocked = true
	_keycard.position = _reader_slot
	_keycard.rotation = Vector3.ZERO
	# Clear any hands holding it.
	for hid in _held.keys():
		if _held[hid] == "keycard":
			_held.erase(hid)
	keycard_slotted.emit()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("keycard")


func pull_handle(hand_y: float) -> void:
	# Called while the handle is held; pulling down opens the safe.
	if safe_open or not safe_unlocked:
		return
	var dy := _handle_grab_offset - hand_y
	if dy > 0.22:
		open_safe()


func open_safe() -> void:
	if safe_open:
		return
	safe_open = true
	for hid in _held.keys():
		if _held[hid] == "handle":
			_held.erase(hid)
	_loot.visible = true
	safe_opened.emit()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("safe")


func secure_loot() -> void:
	if loot_in_exit:
		return
	loot_in_exit = true
	for hid in _held.keys():
		if _held[hid] == "loot":
			_held.erase(hid)
	_loot.position = _exit_pos + Vector3(0, 0.15, 0)
	loot_secured.emit()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("loot")


func check_escape(head_pos: Vector3) -> bool:
	if head_pos.distance_to(_exit_pos) < _exit_r and loot_in_exit:
		escaped.emit()
		return true
	return false


func held_obj(hand_id: int) -> String:
	return str(_held.get(hand_id, ""))


func ghost_event(obj_id: String, action: String) -> void:
	# Ghosts replay recorded interactions; objects only move when they are
	# still in the expected pre-state (otherwise the ghost mimes).
	if action == "slot" and not keycard_slotted_in:
		slot_keycard()
	elif action == "open" and not safe_open and safe_unlocked:
		open_safe()


func update_held() -> void:
	# Held objects follow their hand each frame.
	for hid in _held.keys():
		var hand := _hand_vel.get(hid) as Node3D
		if hand == null or not is_instance_valid(hand):
			continue
		var node := _grabbables.get(_held[hid]) as MeshInstance3D
		if node != null and is_instance_valid(node):
			node.position = to_local(hand.global_position)


func exit_pos() -> Vector3:
	return _exit_pos


func keycard_pos() -> Vector3:
	return _keycard.position if is_instance_valid(_keycard) else _keycard_home


func loot_pos() -> Vector3:
	return _loot.position if is_instance_valid(_loot) else _loot_home
