## SiegeBuilder.gd - trebuchet build phase for SIEGE ENGINEER.
## Snap wooden beams, counterweights and slings onto a build plate on your
## real table. Structural test topples bad builds (comedy included). Pull
## the release lever to loose.
class_name SiegeBuilder
extends Node3D

signal fired(launch: Dictionary)
signal test_done(sturdy: bool)

const BEAMS := [
	{"name": "Short Arm", "len": 1.3, "ratio": 2.0},
	{"name": "Long Arm", "len": 1.9, "ratio": 3.2},
	{"name": "War Arm", "len": 2.5, "ratio": 4.5},
]
const WEIGHTS := [
	{"name": "Light Stones", "mass": 20.0, "size": 0.22},
	{"name": "Iron Blocks", "mass": 45.0, "size": 0.28},
	{"name": "Lead Pig", "mass": 80.0, "size": 0.34},
]

var plate_yaw := 0.0
var beam_idx := -1
var weight_idx := -1
var sling_on := false
var tested_ok := false

var _plate: Node3D
var _arm_group: Node3D
var _beam_mesh: MeshInstance3D
var _weight_mesh: MeshInstance3D
var _sling_mesh: MeshInstance3D
var _lever: MeshInstance3D
var _lever_pulled := false
var _tray_parts: Array = []  # {kind, idx, node, home}
var _hud: Label3D
var _held := {}  # hand_id -> part dict
var _wood_mat: StandardMaterial3D
var _dark_wood: StandardMaterial3D


func build(table_top: Vector3, table_size: Vector3) -> void:
	_make_mats()
	# Build plate.
	_plate = Node3D.new()
	_plate.position = table_top + Vector3(0, 0.02, 0)
	add_child(_plate)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.0, 0.04, 0.75)
	plate.mesh = pm
	plate.material_override = _dark_wood
	_plate.add_child(plate)
	# Pre-built base frame: two A-frames + axle.
	for sx in [-0.28, 0.28]:
		for sz in [-0.12, 0.12]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.06, 0.7, 0.06)
			leg.mesh = lm
			leg.position = Vector3(sx, 0.37, sz)
			leg.rotation.x = -0.35 if sz < 0 else 0.35
			leg.material_override = _wood_mat
			_plate.add_child(leg)
	var axle := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.035
	am.bottom_radius = 0.035
	am.height = 0.66
	axle.mesh = am
	axle.rotation.z = PI / 2.0
	axle.position = Vector3(0, 0.68, 0)
	axle.material_override = _dark_wood
	_plate.add_child(axle)
	# Arm group (pivot at axle).
	_arm_group = Node3D.new()
	_arm_group.position = Vector3(0, 0.68, 0)
	_arm_group.rotation.z = -0.9  # resting: long end down-forward
	_plate.add_child(_arm_group)
	# Release lever.
	_lever = MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.05, 0.3, 0.05)
	_lever.mesh = vm
	_lever.material_override = _glow(Color(1.0, 0.25, 0.2))
	_lever.position = Vector3(0.42, 0.17, 0.28)
	_plate.add_child(_lever)
	_lever.set_meta("grabbable", "lever")
	# Parts tray (beside the plate, on the table).
	_build_tray(table_top)
	# HUD.
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.no_depth_test = true
	_hud.font_size = 64
	_hud.pixel_size = 0.004
	_hud.position = table_top + Vector3(0, 1.0, 0)
	_hud.modulate = Color(1, 0.95, 0.8)
	_hud.outline_modulate = Color(0, 0, 0)
	_hud.outline_size = 10
	add_child(_hud)
	_refresh_hud()


func _make_mats() -> void:
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.55, 0.38, 0.22)
	_wood_mat.roughness = 0.85
	_dark_wood = StandardMaterial3D.new()
	_dark_wood.albedo_color = Color(0.35, 0.24, 0.14)
	_dark_wood.roughness = 0.9


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.8
	return m


func _build_tray(table_top: Vector3) -> void:
	var tray_x := 0.85
	for i in BEAMS.size():
		_tray_parts.append(_make_part("beam", i, Vector3(tray_x, table_top.y + 0.06, 0.35 - i * 0.22)))
	for i in WEIGHTS.size():
		_tray_parts.append(_make_part("weight", i, Vector3(tray_x, table_top.y + 0.06, -0.35 - i * 0.22)))
	_tray_parts.append(_make_part("sling", 0, Vector3(tray_x, table_top.y + 0.06, -1.05)))


func _make_part(kind: String, idx: int, pos: Vector3) -> Dictionary:
	var mi := MeshInstance3D.new()
	if kind == "beam":
		var bm := BoxMesh.new()
		var L: float = BEAMS[idx]["len"]
		bm.size = Vector3(0.09, 0.09, L * 0.45)  # tray-scale model
		mi.mesh = bm
		mi.material_override = _wood_mat
	elif kind == "weight":
		var bm := BoxMesh.new()
		var s: float = WEIGHTS[idx]["size"]
		bm.size = Vector3(s, s, s)
		mi.mesh = bm
		mi.material_override = _dark_wood
	else:  # sling
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.1
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.55, 0.35)
		m.roughness = 0.9
		mi.material_override = m
	mi.position = pos
	mi.set_meta("grabbable", "part")
	add_child(mi)
	var part := {"kind": kind, "idx": idx, "node": mi, "home": pos}
	mi.set_meta("part", part)
	# Floating name tag.
	var lbl := Label3D.new()
	lbl.text = _part_name(kind, idx)
	lbl.font_size = 40
	lbl.pixel_size = 0.003
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = pos + Vector3(0, 0.16, 0)
	add_child(lbl)
	part["label"] = lbl
	return part


func _part_name(kind: String, idx: int) -> String:
	if kind == "beam":
		return BEAMS[idx]["name"]
	if kind == "weight":
		return WEIGHTS[idx]["name"]
	return "Sling"


# ------------------------------------------------------------- interaction ---

## Parts the hand can grab: tray parts + lever.
func grabbable_near(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := 0.3
	for part in _tray_parts:
		var node: MeshInstance3D = part["node"]
		if not is_instance_valid(node) or not node.visible:
			continue
		if _held.values().has(part):
			continue
		var d := p.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = part
	if is_instance_valid(_lever) and p.distance_to(_lever.global_position) < 0.25:
		return {"kind": "lever", "node": _lever}
	return best


func grab(hand_id: int, part: Dictionary) -> bool:
	if part.is_empty() or _held.has(hand_id):
		return false
	_held[hand_id] = part
	return true


func release(hand_id: int, hand_pos: Vector3) -> void:
	if not _held.has(hand_id):
		return
	var part: Dictionary = _held[hand_id]
	_held.erase(hand_id)
	if part.get("kind") == "lever":
		_fire_from_lever()
		return
	# Snap check: beam/weight/sling near the arm?
	var node: MeshInstance3D = part["node"]
	var arm_c := _arm_group.global_position
	if hand_pos.distance_to(arm_c) < 0.45:
		_snap_part(part)
	else:
		node.global_position = hand_pos  # drop where released


func _snap_part(part: Dictionary) -> void:
	var kind := str(part["kind"])
	var idx := int(part["idx"])
	var node: MeshInstance3D = part["node"]
	(node.get_meta("label") as Label3D).visible = false
	node.visible = false  # the arm assembly shows the real thing
	if kind == "beam":
		beam_idx = idx
	elif kind == "weight":
		weight_idx = idx
	else:
		sling_on = true
	tested_ok = false
	_rebuild_arm_visual()
	_refresh_hud()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("snap")
	Haptics.confirm()
	# Return the tray part to its home for re-picking.
	node.position = part["home"] as Vector3
	node.visible = true
	(node.get_meta("label") as Label3D).visible = true


func _rebuild_arm_visual() -> void:
	for c in _arm_group.get_children():
		_arm_group.remove_child(c)
		c.queue_free()
	if beam_idx < 0:
		return
	var spec: Dictionary = BEAMS[beam_idx]
	var L: float = spec["len"]
	var ratio: float = spec["ratio"]
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, L)
	beam.mesh = bm
	var long_end := L * ratio / (ratio + 1.0)
	beam.position = Vector3(0, 0, long_end - L * 0.5)
	beam.material_override = _wood_mat
	_arm_group.add_child(beam)
	_beam_mesh = beam
	if weight_idx >= 0:
		var wspec: Dictionary = WEIGHTS[weight_idx]
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		var s: float = wspec["size"]
		wm.size = Vector3(s, s, s)
		w.mesh = wm
		w.material_override = _dark_wood
		w.position = Vector3(0, -s * 0.5 - 0.05, -(L - long_end) + 0.1)
		_arm_group.add_child(w)
		_weight_mesh = w
	if sling_on:
		var sl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.08
		sl.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.55, 0.35)
		sl.material_override = m
		sl.position = Vector3(0, -0.12, long_end - 0.15)
		_arm_group.add_child(sl)
		_sling_mesh = sl


func update_held() -> void:
	for hid in _held.keys():
		var part: Dictionary = _held[hid]
		if str(part.get("kind", "")) == "lever":
			continue  # the lever stays put; pulling fires it
		var node: MeshInstance3D = part["node"]
		var hand := part.get("hand_node") as Node3D
		if node != null and is_instance_valid(node) and hand != null and is_instance_valid(hand):
			node.global_position = hand.global_position


func set_hand_node(hand_id: int, hand: Node3D) -> void:
	if _held.has(hand_id):
		(_held[hand_id] as Dictionary)["hand_node"] = hand


func held_kind(hand_id: int) -> String:
	if not _held.has(hand_id):
		return ""
	return str((_held[hand_id] as Dictionary).get("kind", ""))


## Structural test: every slot filled = sturdy. Otherwise the build
## collapses comedically (parts become rigid bodies and tumble).
func structural_test() -> void:
	var ok := beam_idx >= 0 and weight_idx >= 0 and sling_on
	tested_ok = ok
	test_done.emit(ok)
	if ok:
		_refresh_hud()
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_stinger("success")
		Haptics.play_sequence("levelup")
	else:
		_collapse()
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_game_sfx("collapse")
		Haptics.play_sequence("error")


func _collapse() -> void:
	# The arm assembly shakes apart: spawn tumbling rigid debris.
	for c in _arm_group.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var rb := RigidBody3D.new()
		rb.mass = 2.0
		_arm_group.add_child(rb)
		_arm_group.remove_child(mi)
		rb.add_child(mi)
		mi.position = Vector3.ZERO
		rb.global_position = _arm_group.global_position + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))
		rb.linear_velocity = Vector3(randf_range(-1.5, 1.5), 2.0, randf_range(-1.5, 1.5))
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), 0)
		var t := get_tree().create_timer(4.0)
		t.timeout.connect(rb.queue_free)
	beam_idx = -1
	weight_idx = -1
	sling_on = false
	_refresh_hud()


func launch_params() -> Dictionary:
	var v0 := 5.0
	var quality := 0.4
	if beam_idx >= 0 and weight_idx >= 0:
		var ratio: float = BEAMS[beam_idx]["ratio"]
		var mass: float = WEIGHTS[weight_idx]["mass"]
		v0 = minf(11.0, 1.1 * sqrt(mass * ratio))
		quality = 1.0 if sling_on else 0.35
	return {"v0": v0 * quality, "yaw": plate_yaw}


func predicted_range() -> float:
	var v0: float = launch_params()["v0"]
	return v0 * v0 / 9.8


func _fire_from_lever() -> void:
	# The lever fires whatever is built (bad builds dribble).
	fired.emit(launch_params())
	_lever_pulled = true
	_animate_arm()


func pull_lever() -> void:
	_fire_from_lever()


func _animate_arm() -> void:
	var tw := create_tween()
	tw.tween_property(_arm_group, "rotation:z", 0.7, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_arm_group, "rotation:z", -0.9, 0.8).set_trans(Tween.TRANS_SINE)


func set_aim(yaw: float) -> void:
	plate_yaw = yaw
	_plate.rotation.y = yaw
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud == null:
		return
	var parts := []
	parts.append("Arm: " + (BEAMS[beam_idx]["name"] if beam_idx >= 0 else "—"))
	parts.append("Weight: " + (WEIGHTS[weight_idx]["name"] if weight_idx >= 0 else "—"))
	parts.append("Sling: " + ("yes" if sling_on else "—"))
	_hud.text = "SIEGE WORKSHOP\n%s\nRange %.1fm %s" % [
		" · ".join(parts), predicted_range(), "✓ TESTED" if tested_ok else ""]
