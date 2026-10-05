## HoloNotesGame.gd - "Holo Notes": spatial sticky notes (utility).
## Left-click empty space to place a note at that 3D point, click a note to
## cycle its color, drag a note to reposition it, right-click to delete it.
## Notes persist to user://holo_notes.json and reload on start.
## Upgraded: PBR note/floor materials, three-point light rig, spark juice on
## place/delete, styled HUD labels, ambient motes, XR pinch note placement,
## spatial anchor persistence, room-clamped hand placement.
## Desktop/mouse driven; _pinch_active() is the XR hand-tracking hook.
extends Node3D
class_name HoloNotesGame

const PRESETS: Array[String] = [
	"Buy milk",
	"Call mom",
	"Idea: gravity golf 2.0",
	"Fix the portal bug",
	"Water the plants",
	"Meeting at 3pm",
	"Quest build tonight",
	"Read chapter 5",
]
const NOTE_COLORS: Array[Color] = [
	Color(1.0, 0.92, 0.35), # yellow
	Color(1.0, 0.55, 0.72), # pink
	Color(0.55, 1.0, 0.60), # green
	Color(0.50, 0.75, 1.00), # blue
]
const SAVE_PATH := "user://holo_notes.json"
const NOTE_SIZE := Vector3(0.55, 0.38, 0.03)
const PLACE_DISTANCE := 2.2
const HIT_RADIUS_PX := 55.0

var camera: Camera3D = null
var notes: Array = [] # Dictionaries: node, mat, label, color_idx
var preset_index := 0
var dragging := -1
var drag_distance := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var _anchor_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "holo-notes_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, 1.0), 2.5, 35)
	_load_notes()


func _process(delta: float) -> void:
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("holo-notes_main", global_transform)
	# Hand interaction: right-hand pinch places a note at the hand pointer.
	# Mouse stays on _unhandled_input; the mouse-press gate keeps the kit's
	# mouse fallback from double-triggering.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_place_note_hand()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var hit := _note_at(mb.position)
			if hit >= 0:
				dragging = hit
				drag_distance = 0.0
			else:
				_place_note_at_mouse(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if dragging >= 0:
				if drag_distance < 8.0:
					_cycle_note_color(dragging)
				_save_notes()
				dragging = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit_r := _note_at(mb.position)
			if hit_r >= 0:
				_delete_note(hit_r)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging >= 0:
			drag_distance += mm.relative.length()
			_drag_note_to_mouse(dragging, mm.position)


## Voice hook: speech-to-text fills this in on device; empty = not available.
func voice_to_text() -> String:
	return ""


## Hand-tracking hook: true while the user is pinching in XR.
func _pinch_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, -2.8)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 1.5), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	# Upgraded three-point light rig; never add a second key light.
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)


func _build_floor() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.11, 0.14), "matte")
	add_child(floor_inst)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color.WHITE)
	hud_label.position = Vector3(-2.4, 2.5, 1.2)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Left-click: place note | Click note: recolor | Drag: move | Right-click: delete", 32, Color(0.75, 0.80, 0.90))
	help_label.position = Vector3(-2.4, 2.25, 1.2)
	help_label.pixel_size = 0.004
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Holo Notes  -  %d note(s)" % notes.size()


func _mouse_ray(screen_pos: Vector2) -> Array:
	if camera == null:
		return []
	return [camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos)]


## 3D point on the camera-facing plane PLACE_DISTANCE meters out.
func _placement_point(screen_pos: Vector2) -> Vector3:
	var ray := _mouse_ray(screen_pos)
	if ray.is_empty():
		return Vector3(0.0, 1.2, 1.0)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var fwd := -camera.global_transform.basis.z
	var denom := dir.dot(fwd)
	if absf(denom) < 0.0001:
		return origin + dir * PLACE_DISTANCE
	var t := PLACE_DISTANCE / denom
	if t < 0.0:
		t = PLACE_DISTANCE
	var p: Vector3 = origin + dir * t
	p.x = clampf(p.x, -3.0, 3.0)
	p.y = clampf(p.y, 0.35, 2.6)
	p.z = clampf(p.z, -1.0, 4.0)
	return p


func _place_note_at_mouse(screen_pos: Vector2) -> void:
	var pos := _placement_point(screen_pos)
	_create_note(pos, _next_preset_text(), 0)
	GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.9, 0.4), 16)
	_save_notes()
	_update_hud()


## XR path: place a note at the hand pointer, clamped to the room.
func _place_note_hand() -> void:
	var p := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	p = ARUpgradeKit.clamp_to_room(p)
	p.y = clampf(p.y, 0.35, 2.6)
	_create_note(p, _next_preset_text(), 0)
	GraphicsPolish.spawn_sparks(self, p, Color(1.0, 0.9, 0.4), 16)
	_save_notes()
	_update_hud()


func _next_preset_text() -> String:
	var text: String = PRESETS[preset_index]
	preset_index = (preset_index + 1) % PRESETS.size()
	return text


func _create_note(pos: Vector3, text: String, color_idx: int) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = NOTE_SIZE
	mesh_inst.mesh = box
	var c: Color = NOTE_COLORS[color_idx % NOTE_COLORS.size()]
	var mat := GraphicsPolish.pbr_preset(c, "plastic")
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.35
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.0032
	label.width = 150.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.0, -0.025)
	label.modulate = Color(0.12, 0.10, 0.05)
	add_child(label) # label is billboarded; keep out of rotated root
	label.global_position = root.global_position + Vector3(0.0, 0.0, -0.025)
	if camera != null:
		root.look_at(camera.global_position, Vector3.UP)
	notes.append({"node": root, "mat": mat, "label": label, "color_idx": color_idx})


func _note_at(screen_pos: Vector2) -> int:
	if camera == null:
		return -1
	for i in range(notes.size()):
		var n: Dictionary = notes[i]
		var node: Node3D = n["node"]
		if not is_instance_valid(node):
			continue
		var sp := camera.unproject_position(node.global_position)
		if sp.distance_to(screen_pos) <= HIT_RADIUS_PX:
			return i
	return -1


func _drag_note_to_mouse(index: int, screen_pos: Vector2) -> void:
	if index < 0 or index >= notes.size():
		return
	var ray := _mouse_ray(screen_pos)
	if ray.is_empty():
		return
	var n: Dictionary = notes[index]
	var node: Node3D = n["node"]
	if not is_instance_valid(node):
		return
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var fwd := -camera.global_transform.basis.z
	var denom := dir.dot(fwd)
	if absf(denom) < 0.0001:
		return
	var t := (node.global_position - origin).dot(fwd) / denom
	if t < 0.0:
		return
	var p: Vector3 = origin + dir * t
	p.x = clampf(p.x, -3.0, 3.0)
	p.y = clampf(p.y, 0.35, 2.6)
	p.z = clampf(p.z, -1.0, 4.0)
	node.global_position = p
	var label: Label3D = n["label"]
	if is_instance_valid(label):
		label.global_position = p + Vector3(0.0, 0.0, -0.025)


func _cycle_note_color(index: int) -> void:
	if index < 0 or index >= notes.size():
		return
	var n: Dictionary = notes[index]
	var next := (int(n["color_idx"]) + 1) % NOTE_COLORS.size()
	n["color_idx"] = next
	var c: Color = NOTE_COLORS[next]
	var mat: StandardMaterial3D = n["mat"]
	mat.albedo_color = c
	mat.emission = c
	notes[index] = n


func _delete_note(index: int) -> void:
	if index < 0 or index >= notes.size():
		return
	var n: Dictionary = notes[index]
	var node: Node3D = n["node"]
	var label: Label3D = n["label"]
	if is_instance_valid(node):
		GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.5, 0.5), 12)
		node.queue_free()
	if is_instance_valid(label):
		label.queue_free()
	notes.remove_at(index)
	dragging = -1
	_save_notes()
	_update_hud()


func _save_notes() -> void:
	var data: Array = []
	for n_v in notes:
		var n: Dictionary = n_v
		var node: Node3D = n["node"]
		if not is_instance_valid(node):
			continue
		var label: Label3D = n["label"]
		data.append({
			"p": [node.global_position.x, node.global_position.y, node.global_position.z],
			"c": int(n["color_idx"]),
			"t": label.text if is_instance_valid(label) else "",
		})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_notes() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		return
	for entry_v in parsed:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var p: Array = entry.get("p", [0.0, 1.2, 1.0])
		if p.size() < 3:
			continue
		_create_note(
			Vector3(float(p[0]), float(p[1]), float(p[2])),
			str(entry.get("t", "Note")),
			int(entry.get("c", 0)) % NOTE_COLORS.size()
		)
	_update_hud()
