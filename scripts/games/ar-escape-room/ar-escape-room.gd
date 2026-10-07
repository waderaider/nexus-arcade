## ar-escape-room.gd -- NEXUS ARCADE: puzzle escape room.
## A locked exit door with 3 locks. Three puzzles hide around the room:
##  (1) a note with a 3-digit keypad code fragment (count the books),
##  (2) red/green/blue keys inserted into matching door slots in order,
##  (3) a riddle answered by typing on 3D letter buttons.
## Each solved puzzle opens one lock; all 3 slide the door open.
## Wrong attempts shake. R or the RESTART button resets. Timer included.
extends Node3D

const CODE := "753"
const RIDDLE_ANSWER := "KEYBOARD"
const SLOT_COLORS := ["red", "green", "blue"]
const SLOT_TINTS := {
	"red": Color(1.0, 0.28, 0.28),
	"green": Color(0.30, 1.0, 0.40),
	"blue": Color(0.35, 0.60, 1.0),
}
const PUZZLE_NAMES := ["KEYPAD", "KEYS", "RIDDLE"]


var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}
var _anchor_t := 0.0

# Game state.
var locks := [false, false, false]
var slots_filled := [false, false, false]
var held_key := ""
var entry := ""
var guess := ""
var won := false
var _elapsed := 0.0
var _notify_t := 0.0

# Nodes.
var door: MeshInstance3D = null
var door_glow: MeshInstance3D = null
var door_light: SpotLight3D = null
var lock_mats: Array = []
var key_nodes := {}
var key_home := {}
var slot_nodes: Array = []
var win_label: Label3D = null

# Interactables: Array of {"id": String, "node": Node3D, "r": float}.
var interactables: Array = []

# Clue panel.
var panel_root: Node3D = null
var panel_title: Label3D = null
var panel_body: Label3D = null
var panel_content: Node3D = null
var panel_buttons: Array = []  # {"id": String, "node": MeshInstance3D, "r": float}
var panel_mode := ""
var close_btn := {}  # {"node": MeshInstance3D, "r": float}, persistent child of panel_root
var guess_label: Label3D = null
var entry_label: Label3D = null

# Shakes: Array of {"node": Node3D, "t": float, "dur": float, "base": Vector3}.
var shakes: Array = []

# HUD.
var hud_main: Label3D = null
var hud_help: Label3D = null
var notify_label: Label3D = null

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var note_paper: MeshInstance3D = null
var note_label: Label3D = null
var note_hit_node: Node3D = null
var scroll_node: Node3D = null
var scroll_label: Label3D = null


func _ready() -> void:
	# Restore the persisted room placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "ar-escape-room_main")
	_build_environment()
	_dress_dungeon() # v0.7.0 KayKit set dressing (null-safe)
	_build_door()
	_build_clues()
	_build_panel()
	_build_ui()
	# Three-point light rig, unless the scene already has a key light.
	var _has_dir := false
	for c in get_children():
		if c is DirectionalLight3D:
			_has_dir = true
	if not _has_dir:
		GraphicsPolish.make_light_rig(self, 1.1)
	# Dust motes drifting through the room.
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.6, 0.0), 2.8, 40)
	_apply_room_layout()


## v0.7.0: hide the blue key behind the biggest real furniture piece, and
## tape the note poster + riddle scroll to real walls. Guarded; fallback
## keeps the default staged room.
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): screens/tv -> mission clue terminals
	_morph_anchors("SCREEN", "scifi", 1)
	_morph_anchors("TV", "scifi", 1)
	var f := _largest_cuboid(_room_furniture)
	if not f.is_empty() and key_nodes.has("blue"):
		var fp: Vector3 = f["position"]
		var fs: Vector3 = f["size"]
		var c := _room_bounds.get_center()
		var away := Vector2(fp.x - c.x, fp.z - c.y)
		away = away.normalized() if away.length() > 0.05 else Vector2(0, 1)
		var dist := maxf(fs.x, fs.z) * 0.5 + 0.35
		var bk := key_nodes["blue"] as Node3D
		bk.position = to_local(Vector3(fp.x + away.x * dist, 0.12, fp.z + away.y * dist))
		key_home["blue"] = bk.position
	var sorted_walls := _room_walls.duplicate()
	sorted_walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["size"] as Vector2).x * (a["size"] as Vector2).y > (b["size"] as Vector2).x * (b["size"] as Vector2).y)
	if not sorted_walls.is_empty():
		_mount_poster(sorted_walls[0], 1.5)
		if sorted_walls.size() > 1:
			_mount_scroll(sorted_walls[1], 1.2)


func _largest_cuboid(items: Array) -> Dictionary:
	var best := {}
	var best_v := 0.0
	for f_v in items:
		var f: Dictionary = f_v
		var s: Vector3 = f["size"]
		var v := s.x * s.y * s.z
		if v > best_v:
			best_v = v
			best = f
	return best


func _wall_face(w: Dictionary, height: float) -> Vector3:
	var n: Vector3 = w["normal"]
	n.y = 0.0
	if n.length() < 0.01:
		n = Vector3(0, 0, 1)
	n = n.normalized()
	var fw: Vector3 = (w["position"] as Vector3) + n * 0.07
	fw.y = height
	return fw


func _wall_yaw(fw: Vector3) -> float:
	var c := _room_bounds.get_center()
	var d := Vector2(c.x - fw.x, c.y - fw.z)
	return atan2(d.x, d.y) if d.length() > 0.05 else 0.0


func _mount_poster(w: Dictionary, height: float) -> void:
	if note_paper == null:
		return
	var fw := _wall_face(w, height)
	var yaw := _wall_yaw(fw)
	note_paper.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), to_local(fw))
	if note_label != null:
		note_label.position = to_local(fw + Vector3(0, 0.32, 0))
		note_label.rotation.y = yaw
	if note_hit_node != null:
		note_hit_node.position = to_local(fw)


func _mount_scroll(w: Dictionary, height: float) -> void:
	if scroll_node == null:
		return
	var fw := _wall_face(w, height)
	var yaw := _wall_yaw(fw)
	scroll_node.position = to_local(fw)
	scroll_node.rotation = Vector3(0, yaw, PI * 0.5)
	if scroll_label != null:
		scroll_label.position = to_local(fw + Vector3(0, 0.35, 0))
		scroll_label.rotation.y = yaw


func _mat(color: Color, rough: float = 0.6, emission: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := GraphicsPolish.pbr(color, 0.0, rough)
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.2
	return m


func _box(size: Vector3, color: Color, pos: Vector3, parent: Node3D, rough: float = 0.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, color: Color, pixel: float = 0.007, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 8
	(parent if parent != null else self).add_child(l)
	return l


func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 1.75, 3.1)
		add_child(cam)
		cam.look_at(Vector3(0.0, 1.15, -1.2), Vector3.UP)

	var amb := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.10)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.45, 0.55)
	e.ambient_light_energy = 0.8
	amb.environment = e
	add_child(amb)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 2.6, 0.0)
	lamp.light_energy = 1.1
	lamp.omni_range = 9.0
	add_child(lamp)

	var wall_mat := _mat(Color(0.16, 0.17, 0.26), 0.95)
	var floor_mat := _mat(Color(0.13, 0.11, 0.15), 0.95)

	_box(Vector3(6.4, 0.1, 6.4), Color(0.13, 0.11, 0.15), Vector3(0, -0.05, 0), self).material_override = floor_mat
	# Back wall (door wall).
	_box(Vector3(6.4, 3.2, 0.2), Color(0.16, 0.17, 0.26), Vector3(0, 1.6, -3.05), self).material_override = wall_mat
	# Side + front walls.
	_box(Vector3(0.2, 3.2, 6.4), Color(0.14, 0.15, 0.23), Vector3(-3.05, 1.6, 0), self)
	_box(Vector3(0.2, 3.2, 6.4), Color(0.14, 0.15, 0.23), Vector3(3.05, 1.6, 0), self)
	_box(Vector3(6.4, 3.2, 0.2), Color(0.12, 0.13, 0.20), Vector3(0, 1.6, 3.05), self)
	# Ceiling.
	_box(Vector3(6.4, 0.1, 6.4), Color(0.10, 0.10, 0.16), Vector3(0, 3.15, 0), self)

	# Two paintings for flavor.
	_box(Vector3(0.08, 0.9, 1.3), Color(0.45, 0.25, 0.55), Vector3(-2.92, 1.8, 0.6), self)
	_box(Vector3(0.08, 0.7, 1.0), Color(0.20, 0.45, 0.55), Vector3(2.92, 1.7, -0.8), self)


## v0.7.0 KayKit set dressing: real dungeon props as room flavor (chests,
## barrels, lit wall torches). Every spawn is guarded - a null return from
## ModelLib.spawn (missing model) simply skips that prop, leaving the
## procedural room intact.
func _dress_dungeon() -> void:
	var dir := "res://assets/models/ar-escape-room/"
	# Lit torches flanking the exit door.
	for tx in [-1.05, 1.05]:
		ModelLib.spawn(dir + "torch_mounted.glb", self, Vector3(tx, 1.55, -2.90))
	# Treasure chest tucked into the front-left corner.
	ModelLib.spawn(dir + "chest.glb", self, Vector3(-2.45, 0.0, 2.35))
	# Barrel against the restart-button wall.
	ModelLib.spawn(dir + "barrel_large.glb", self, Vector3(2.50, 0.0, -2.35))
	# Candle shelf against the left wall.
	ModelLib.spawn(dir + "shelf_small.glb", self, Vector3(-2.80, 0.0, -2.20))


func _build_door() -> void:
	# Frame behind the door.
	_box(Vector3(1.6, 2.6, 0.12), Color(0.10, 0.08, 0.10), Vector3(0, 1.3, -2.97), self)

	# The exit door itself.
	door = _box(Vector3(1.3, 2.3, 0.16), Color(0.42, 0.26, 0.14), Vector3(0, 1.15, -2.88), self, 0.6)
	_label("EXIT", Vector3(0, 0.35, 0.10), Color(0.95, 0.85, 0.60), 0.012, door)

	# Glow revealed when the door slides open.
	door_glow = MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(1.3, 2.3, 0.04)
	door_glow.mesh = gb
	door_glow.material_override = _mat(Color(1, 1, 1), 0.4, Color(1.0, 0.98, 0.92))
	door_glow.position = Vector3(0, 1.15, -2.94)
	door_glow.visible = false
	add_child(door_glow)

	door_light = SpotLight3D.new()
	door_light.position = Vector3(0, 1.6, -2.7)
	door_light.rotation_degrees = Vector3(25, 0, 0)
	door_light.light_energy = 0.0
	door_light.spot_range = 6.0
	add_child(door_light)

	# 3 lock indicators above the door slots.
	lock_mats.clear()
	for i in 3:
		var lm := _mat(Color(0.35, 0.35, 0.40), 0.4)
		lock_mats.append(lm)
		var li := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.22, 0.22, 0.10)
		li.mesh = lb
		li.material_override = lm
		li.position = Vector3(-0.36 + float(i) * 0.36, 1.98, -2.78)
		add_child(li)
		_label(str(i + 1), Vector3(-0.36 + float(i) * 0.36, 2.20, -2.80), Color(0.8, 0.85, 0.95), 0.006)
	_label("LOCKS", Vector3(0, 2.42, -2.80), Color(0.85, 0.80, 0.60), 0.008)

	# Keypad on the wall beside the door.
	_box(Vector3(0.45, 0.55, 0.12), Color(0.12, 0.13, 0.18), Vector3(1.35, 1.45, -2.93), self)
	_label("CODE", Vector3(1.35, 1.78, -2.90), Color(0.70, 0.80, 1.0), 0.007)
	var keypad_hit := MeshInstance3D.new()
	keypad_hit.position = Vector3(1.35, 1.45, -2.90)
	add_child(keypad_hit)
	_add_interactable("keypad", keypad_hit, 0.45)

	# 3 key slots on the door (colors shuffled: red, green, blue).
	slot_nodes.clear()
	for i in 3:
		var col: Color = SLOT_TINTS[SLOT_COLORS[i]]
		# Colored plate showing which key belongs here.
		_box(Vector3(0.34, 0.20, 0.03), col, Vector3(-0.36 + float(i) * 0.36, 1.15, -2.795), self, 0.4)
		var slot := _box(Vector3(0.30, 0.12, 0.12), Color(0.08, 0.08, 0.10),
			Vector3(-0.36 + float(i) * 0.36, 1.15, -2.76), self)
		slot_nodes.append(slot)
		_add_interactable("slot_%d" % (i + 1), slot, 0.30)
		_label(str(i + 1), Vector3(-0.36 + float(i) * 0.36, 1.36, -2.78), Color(0.9, 0.9, 0.9), 0.006)

	# Door itself is clickable (status message).
	_add_interactable("door", door, 0.9)

	win_label = GraphicsPolish.make_label("", 96, Color(0.55, 1.0, 0.65))
	win_label.position = Vector3(0, 2.6, -2.5)
	win_label.pixel_size = 0.016
	add_child(win_label)


func _make_key(color_name: String) -> Node3D:
	var col: Color = SLOT_TINTS[color_name]
	var key := Node3D.new()
	# Shaft.
	var shaft := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.07, 0.07, 0.30)
	shaft.mesh = sb
	shaft.material_override = _mat(col, 0.35, col.darkened(0.2))
	key.add_child(shaft)
	# Bow (ring).
	var bow := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.095
	bow.mesh = tm
	bow.material_override = _mat(col, 0.35, col.darkened(0.2))
	bow.position = Vector3(0, 0, 0.21)
	key.add_child(bow)
	# Teeth.
	for tz in [0.02, 0.08]:
		var tooth := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.07, 0.09, 0.05)
		tooth.mesh = tb
		tooth.material_override = _mat(col, 0.35)
		tooth.position = Vector3(0, -0.06, -0.10 + tz)
		key.add_child(tooth)
	return key


func _build_clues() -> void:
	# --- Table with the note ---
	var wood := Color(0.40, 0.28, 0.16)
	_box(Vector3(1.3, 0.09, 0.8), wood, Vector3(-1.9, 0.72, -1.2), self)
	for lx in [-0.55, 0.55]:
		for lz in [-0.30, 0.30]:
			var leg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 0.68
			leg.mesh = cm
			leg.material_override = _mat(wood.darkened(0.15), 0.7)
			leg.position = Vector3(-1.9 + lx, 0.36, -1.2 + lz)
			add_child(leg)
	# The note (paper).
	note_paper = _box(Vector3(0.34, 0.025, 0.44), Color(0.93, 0.90, 0.80), Vector3(-1.9, 0.79, -1.2), self) # v0.7.0: RoomKit may wall-mount this
	note_label = _label("NOTE", Vector3(-1.9, 1.05, -1.2), Color(1.0, 0.95, 0.75), 0.006)
	var note_hit := MeshInstance3D.new()
	note_hit.position = Vector3(-1.9, 0.82, -1.2)
	add_child(note_hit)
	note_hit_node = note_hit
	_add_interactable("note", note_hit, 0.40)

	# --- Shelf with 5 books (the code hint) ---
	_box(Vector3(1.5, 0.07, 0.32), wood.darkened(0.1), Vector3(-2.0, 1.45, -2.88), self)
	var book_cols := [Color(0.75, 0.25, 0.25), Color(0.25, 0.45, 0.75), Color(0.30, 0.65, 0.30),
		Color(0.75, 0.60, 0.25), Color(0.55, 0.35, 0.70)]
	for i in 5:
		_box(Vector3(0.12, 0.40, 0.24), book_cols[i],
			Vector3(-2.55 + float(i) * 0.22, 1.69, -2.88), self)
	_label("BOOKS", Vector3(-2.0, 2.05, -2.86), Color(0.70, 0.75, 0.85), 0.006)

	# --- The three hidden keys ---
	var red_key := _make_key("red")
	red_key.position = Vector3(-1.30, 1.56, -2.88)
	red_key.rotation.y = 0.5
	add_child(red_key)
	var green_key := _make_key("green")
	green_key.position = Vector3(-1.9, 0.12, -1.2)
	green_key.rotation = Vector3(0.3, 0.8, 1.35)
	add_child(green_key)
	# Plant: pot + foliage; blue key hidden behind it.
	var pot := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.24
	pm.bottom_radius = 0.18
	pm.height = 0.36
	pot.mesh = pm
	pot.material_override = _mat(Color(0.55, 0.30, 0.18), 0.8)
	pot.position = Vector3(2.3, 0.18, 1.6)
	add_child(pot)
	var leaf_mat := _mat(Color(0.22, 0.60, 0.28), 0.7)
	for li in 3:
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22 - float(li) * 0.04
		sm.height = sm.radius * 2.0
		leaf.mesh = sm
		leaf.material_override = leaf_mat
		leaf.position = Vector3(2.3, 0.62 + float(li) * 0.22, 1.6)
		add_child(leaf)
	var blue_key := _make_key("blue")
	blue_key.position = Vector3(2.62, 0.10, 1.95)
	blue_key.rotation = Vector3(1.2, 0.4, 0.6)
	add_child(blue_key)

	key_nodes = {"red": red_key, "green": green_key, "blue": blue_key}
	key_home = {
		"red": red_key.position, "green": green_key.position, "blue": blue_key.position,
	}
	_add_interactable("key_red", red_key, 0.30)
	_add_interactable("key_green", green_key, 0.30)
	_add_interactable("key_blue", blue_key, 0.30)

	# --- The riddle scroll ---
	var scroll := MeshInstance3D.new()
	var scm := CylinderMesh.new()
	scm.top_radius = 0.07
	scm.bottom_radius = 0.07
	scm.height = 0.5
	scroll.mesh = scm
	scroll.material_override = _mat(Color(0.90, 0.82, 0.66), 0.8)
	scroll.rotation.z = PI * 0.5
	scroll.position = Vector3(-2.3, 0.09, 1.3)
	add_child(scroll)
	scroll_node = scroll
	scroll_label = _label("SCROLL", Vector3(-2.3, 0.45, 1.3), Color(0.95, 0.88, 0.70), 0.006)
	_add_interactable("scroll", scroll, 0.40)

	# --- RESTART button on the back wall ---
	var rb := _box(Vector3(0.62, 0.32, 0.12), Color(0.70, 0.18, 0.18), Vector3(2.25, 2.15, -2.93), self, 0.4)
	_label("RESTART", Vector3(2.25, 2.15, -2.85), Color(1, 1, 1), 0.007)
	_add_interactable("restart", rb, 0.45)


func _add_interactable(id: String, node: Node3D, r: float) -> void:
	interactables.append({"id": id, "node": node, "r": r})


# ---------------------------------------------------------------- panel ---

func _build_panel() -> void:
	panel_root = Node3D.new()
	panel_root.position = Vector3(0.0, 1.62, -0.35)
	add_child(panel_root)

	var bg := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(2.7, 2.05, 0.06)
	bg.mesh = bbm
	var bgm := GraphicsPolish.pbr_preset(Color(0.05, 0.07, 0.13), "glass")
	bgm.albedo_color = Color(0.05, 0.07, 0.13, 0.94)
	bg.material_override = bgm
	panel_root.add_child(bg)

	panel_title = Label3D.new()
	panel_title.position = Vector3(0, 0.82, 0.05)
	panel_title.pixel_size = 0.009
	panel_title.modulate = Color(1.0, 0.90, 0.60)
	panel_title.outline_size = 8
	panel_root.add_child(panel_title)

	panel_body = Label3D.new()
	panel_body.position = Vector3(0, 0.42, 0.05)
	panel_body.pixel_size = 0.0058
	panel_body.width = 440.0
	panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.modulate = Color(0.88, 0.92, 1.0)
	panel_body.outline_size = 6
	panel_root.add_child(panel_body)

	panel_content = Node3D.new()
	panel_root.add_child(panel_content)

	# CLOSE button lives on panel_root (not panel_content) so _clear_panel
	# never removes it.
	var cb := MeshInstance3D.new()
	var cbb := BoxMesh.new()
	cbb.size = Vector3(0.42, 0.18, 0.06)
	cb.mesh = cbb
	cb.material_override = _mat(Color(0.30, 0.22, 0.16), 0.5)
	cb.position = Vector3(1.02, -0.88, 0.05)
	panel_root.add_child(cb)
	var cl := Label3D.new()
	cl.text = "CLOSE"
	cl.pixel_size = 0.0042
	cl.font_size = 40
	cl.position = Vector3(0, 0, 0.045)
	cl.modulate = Color(0.92, 0.95, 1.0)
	cl.outline_size = 6
	cb.add_child(cl)
	close_btn = {"node": cb, "r": 0.32}
	panel_root.visible = false


func _panel_button(text: String, pos: Vector3, size: Vector2, id: String, font_size: int = 44) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.06)
	mi.mesh = bm
	var m := _mat(Color(0.16, 0.23, 0.36), 0.5)
	if id == "enter" or id == "bksp" or id == "clear":
		m.albedo_color = Color(0.30, 0.22, 0.16)
	mi.material_override = m
	mi.position = pos
	panel_content.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0042
	l.font_size = font_size
	l.position = Vector3(0, 0, 0.045)
	l.modulate = Color(0.92, 0.95, 1.0)
	l.outline_size = 6
	mi.add_child(l)
	panel_buttons.append({"id": id, "node": mi, "r": maxf(size.x, size.y) * 0.75})


func _clear_panel() -> void:
	for child in panel_content.get_children():
		child.queue_free()
	panel_buttons.clear()
	guess_label = null
	entry_label = null


func _open_panel(mode: String) -> void:
	_clear_panel()
	panel_mode = mode
	panel_root.visible = true
	match mode:
		"note":
			panel_title.text = "TORN NOTE"
			panel_body.text = "Keypad code:  7 _ 3\n\nThe missing digit is the number of books on the shelf.\n\nCount them carefully!"
		"keypad":
			panel_title.text = "KEYPAD  (Lock 1)"
			panel_body.text = "Enter the 3-digit code, then press ENTER."
			entry = ""
			entry_label = Label3D.new()
			entry_label.position = Vector3(0, 0.18, 0.05)
			entry_label.pixel_size = 0.011
			entry_label.modulate = Color(0.55, 1.0, 0.65)
			entry_label.outline_size = 8
			panel_content.add_child(entry_label)
			_update_entry_label()
			var digits := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
			for i in digits.size():
				var d: String = digits[i]
				var col := float(i % 3)
				var row := float(i / 3)
				_panel_button(d, Vector3(-0.42 + col * 0.42, -0.08 - row * 0.26, 0.05),
					Vector2(0.34, 0.20), "digit_" + d)
			_panel_button("CLEAR", Vector3(-0.42, -0.86, 0.05), Vector2(0.52, 0.18), "clear", 36)
			_panel_button("ENTER", Vector3(0.30, -0.86, 0.05), Vector2(0.52, 0.18), "enter", 36)
		"riddle":
			panel_title.text = "OLD SCROLL  (Lock 3)"
			panel_body.text = "I have keys but open no locks.\nI have space but no room.\nYou can enter, but can't go outside.\n\nWhat am I? Type the answer:"
			guess = ""
			guess_label = Label3D.new()
			guess_label.position = Vector3(0, -0.10, 0.05)
			guess_label.pixel_size = 0.010
			guess_label.modulate = Color(0.55, 1.0, 0.65)
			guess_label.outline_size = 8
			panel_content.add_child(guess_label)
			_update_guess_label()
			var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
			for i in letters.length():
				var ch := letters.substr(i, 1)
				var col := float(i % 7)
				var row := float(i / 7)
				_panel_button(ch, Vector3(-0.84 + col * 0.28, -0.34 - row * 0.21, 0.05),
					Vector2(0.23, 0.17), "letter_" + ch, 40)
			_panel_button("BKSP", Vector3(-0.56, -0.86, 0.05), Vector2(0.50, 0.18), "bksp", 36)
			_panel_button("ENTER", Vector3(0.28, -0.86, 0.05), Vector2(0.50, 0.18), "enter", 36)
		"win":
			panel_title.text = "YOU ESCAPED!"
			panel_body.text = "All 3 locks opened.\n\nEscape time: %s\n\nPress R or RESTART to play again." % _fmt_time(_elapsed)


func _close_panel() -> void:
	_clear_panel()
	panel_root.visible = false
	panel_mode = ""


func _update_entry_label() -> void:
	if entry_label == null:
		return
	if entry.length() == 0:
		entry_label.text = "_ _ _"
	else:
		entry_label.text = " ".join(entry.split(""))


func _update_guess_label() -> void:
	if guess_label == null:
		return
	if guess.length() == 0:
		guess_label.text = "_ _ _ _ _ _ _ _"
	else:
		guess_label.text = " ".join(guess.split(""))


func _handle_panel_button(id: String) -> void:
	if id == "close":
		_close_panel()
		return
	if panel_mode == "keypad":
		if id.begins_with("digit_"):
			if entry.length() < 3:
				entry += id.trim_prefix("digit_")
				_update_entry_label()
		elif id == "clear":
			entry = ""
			_update_entry_label()
		elif id == "enter":
			if entry == CODE:
				_unlock(0)
				_close_panel()
				_notify("CLICK! The keypad lock opens.")
			else:
				_shake(panel_root)
				entry = ""
				_update_entry_label()
				_notify("Wrong code. The keypad buzzes.")
	elif panel_mode == "riddle":
		if id.begins_with("letter_"):
			if guess.length() < 10:
				guess += id.trim_prefix("letter_")
				_update_guess_label()
		elif id == "bksp":
			guess = guess.left(guess.length() - 1) if guess.length() > 0 else ""
			_update_guess_label()
		elif id == "enter":
			if guess == RIDDLE_ANSWER:
				_unlock(2)
				_close_panel()
				_notify("CLICK! The riddle lock opens.")
			else:
				_shake(panel_root)
				guess = ""
				_update_guess_label()
				_notify("Wrong answer. The scroll stays sealed.")


# ---------------------------------------------------------------- logic ----

func _unlock(i: int) -> void:
	if locks[i]:
		return
	locks[i] = true
	var lm: StandardMaterial3D = lock_mats[i]
	lm.albedo_color = Color(0.30, 1.0, 0.45)
	lm.emission_enabled = true
	lm.emission = Color(0.20, 0.90, 0.35)
	GraphicsPolish.spawn_sparks(self, Vector3(-0.36 + float(i) * 0.36, 1.98, -2.70), Color(0.4, 1.0, 0.5), 18)
	if locks[0] and locks[1] and locks[2]:
		_win()


func _win() -> void:
	won = true
	door_glow.visible = true
	door_light.light_energy = 5.0
	win_label.text = "ESCAPED!"
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, -2.5), 60)
	_open_panel("win")


func _try_slot(i: int) -> void:
	if slots_filled[i]:
		_notify("Slot %d already holds a key." % (i + 1))
		return
	if held_key == "":
		_notify("You need a key first. Search the room!")
		return
	var want: String = SLOT_COLORS[i]
	if held_key != want:
		_shake(slot_nodes[i])
		_notify("Wrong key! Slot %d wants the %s key." % [i + 1, want.to_upper()])
		return
	var filled := 0
	for s in slots_filled:
		if s:
			filled += 1
	if i != filled:
		_shake(slot_nodes[i])
		_notify("The mechanism wants slot %d first!" % (filled + 1))
		return
	# Insert the key.
	var key: Node3D = key_nodes[held_key]
	key.position = (slot_nodes[i] as Node3D).position + Vector3(0, 0, 0.16)
	key.rotation = Vector3.ZERO
	key.visible = true
	slots_filled[i] = true
	held_key = ""
	_notify("The %s key slides into slot %d." % [want.to_upper(), i + 1])
	if slots_filled[0] and slots_filled[1] and slots_filled[2]:
		_unlock(1)
		_notify("CLICK! All keys seated - the key lock opens.")


func _handle_world(id: String) -> void:
	match id:
		"note":
			_open_panel("note")
		"keypad":
			if locks[0]:
				_notify("The keypad lock is already open.")
			else:
				_open_panel("keypad")
		"scroll":
			if locks[2]:
				_notify("The riddle lock is already open.")
			else:
				_open_panel("riddle")
		"key_red", "key_green", "key_blue":
			var cname := id.trim_prefix("key_")
			var key: Node3D = key_nodes[cname]
			if not key.visible:
				return
			if held_key != "":
				_notify("Your hands are full - insert the %s key first." % held_key.to_upper())
				return
			held_key = cname
			key.visible = false
			_notify("Picked up the %s key." % cname.to_upper())
		"slot_1":
			_try_slot(0)
		"slot_2":
			_try_slot(1)
		"slot_3":
			_try_slot(2)
		"door":
			if won:
				return
			var left := 0
			for l in locks:
				if not l:
					left += 1
			_notify("Sealed. %d lock%s still hold%s the door." % [left, "" if left == 1 else "s", "s" if left == 1 else ""])
		"restart":
			_reset()


func _notify(text: String) -> void:
	notify_label.text = text
	_notify_t = 3.0


func _shake(node: Node3D, dur: float = 0.45) -> void:
	for s in shakes:
		if (s as Dictionary)["node"] == node:
			return
	shakes.append({"node": node, "t": dur, "dur": dur, "base": node.position})


func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%02d:%02d" % [m, s]


func _reset() -> void:
	locks = [false, false, false]
	slots_filled = [false, false, false]
	held_key = ""
	entry = ""
	guess = ""
	won = false
	_elapsed = 0.0
	door.position.x = 0.0
	door_glow.visible = false
	door_light.light_energy = 0.0
	win_label.text = ""
	for lm in lock_mats:
		var m: StandardMaterial3D = lm
		m.albedo_color = Color(0.35, 0.35, 0.40)
		m.emission_enabled = false
	for cname in key_nodes.keys():
		var key: Node3D = key_nodes[cname]
		key.position = key_home[cname]
		key.rotation = Vector3.ZERO
		key.visible = true
	# Restore the keys' original tumble rotations.
	(key_nodes["red"] as Node3D).rotation.y = 0.5
	(key_nodes["green"] as Node3D).rotation = Vector3(0.3, 0.8, 1.35)
	(key_nodes["blue"] as Node3D).rotation = Vector3(1.2, 0.4, 0.6)
	shakes.clear()
	_close_panel()
	ARUpgradeKit.save_anchor("ar-escape-room_main", global_transform)
	_notify("Room reset. Find the 3 clues!")


# ------------------------------------------------------------------ UI -----

func _build_ui() -> void:
	hud_main = _label("", Vector3(-2.55, 2.62, -2.2), Color(0.85, 0.95, 1.0))
	hud_help = _label(
		"Click NOTE / KEYPAD / SCROLL\nto inspect. Click keys to grab,\nthen click door slots.\nR or RESTART: reset",
		Vector3(2.55, 2.62, -2.2), Color(0.65, 0.75, 0.9))
	notify_label = _label("", Vector3(0, 2.78, -2.88), Color(1.0, 0.85, 0.55))


func _locks_text() -> String:
	var t := ""
	for i in 3:
		t += "[X] " if locks[i] else "[ ] "
	return t.strip_edges()


func _update_hud() -> void:
	var hold := held_key.to_upper() + " KEY" if held_key != "" else "nothing"
	hud_main.text = "ESCAPE ROOM\nTime %s\nLocks %s\nHolding: %s" % [_fmt_time(_elapsed), _locks_text(), hold]


# ----------------------------------------------------------------- loop ----

func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	# Persist the room placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("ar-escape-room_main", global_transform)
	# XR hand: a pinch clicks at the pinch point (mouse clicks still work).
	if ARUpgradeKit.is_xr_active() and cam != null \
			and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		if not cam.is_position_behind(pp):
			_handle_click(cam.unproject_position(pp))
	if not won:
		_elapsed += delta
	else:
		# Slide the door open.
		door.position.x = lerpf(door.position.x, 1.55, minf(1.0, 2.2 * delta))

	# Keys bob gently so players notice them.
	var bob := sin(_time * 2.2) * 0.03
	for cname in key_nodes.keys():
		var key: Node3D = key_nodes[cname]
		if key.visible and held_key != cname and not _key_inserted(key):
			key.position.y = (key_home[cname] as Vector3).y + bob

	# Shakes.
	for i in range(shakes.size() - 1, -1, -1):
		var s: Dictionary = shakes[i]
		s["t"] = float(s["t"]) - delta
		var node: Node3D = s["node"]
		if float(s["t"]) <= 0.0:
			node.position = s["base"]
			shakes.remove_at(i)
		else:
			var k: float = float(s["t"]) / float(s["dur"])
			node.position = (s["base"] as Vector3) + Vector3(
				randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), 0.0) * 0.06 * k

	# Notify fade.
	if _notify_t > 0.0:
		_notify_t -= delta
		if _notify_t <= 0.0:
			notify_label.text = ""

	_update_hud()


func _key_inserted(key: Node3D) -> bool:
	for i in 3:
		if slots_filled[i]:
			var sp: Vector3 = (slot_nodes[i] as Node3D).position + Vector3(0, 0, 0.16)
			if key.position.distance_to(sp) < 0.05:
				return true
	return false


func _poll_keys() -> void:
	var down_r := Input.is_key_pressed(KEY_R)
	var was_r: bool = _prev_keys.get(KEY_R, false)
	if down_r and not was_r:
		_reset()
	_prev_keys[KEY_R] = down_r
	var down_esc := Input.is_key_pressed(KEY_ESCAPE)
	var was_esc: bool = _prev_keys.get(KEY_ESCAPE, false)
	if down_esc and not was_esc and panel_root.visible:
		_close_panel()
	_prev_keys[KEY_ESCAPE] = down_esc


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)


func _handle_click(screen_pos: Vector2) -> void:
	if cam == null:
		return
	var o: Vector3 = cam.project_ray_origin(screen_pos)
	var d: Vector3 = cam.project_ray_normal(screen_pos)

	if panel_root.visible:
		var cb_node: MeshInstance3D = close_btn["node"]
		if _sphere_t(o, d, cb_node.global_position, float(close_btn["r"])) >= 0.0:
			_close_panel()
			return
		var best_id := ""
		var best_d := 1e9
		for b in panel_buttons:
			var bd: Dictionary = b
			var node: MeshInstance3D = bd["node"]
			var t := _sphere_t(o, d, node.global_position, float(bd["r"]))
			if t >= 0.0 and t < best_d:
				best_d = t
				best_id = str(bd["id"])
		if best_id != "":
			_handle_panel_button(best_id)
		return

	var best_w := ""
	var best_wd := 1e9
	for w in interactables:
		var wd: Dictionary = w
		var node: Node3D = wd["node"]
		if node is MeshInstance3D and not (node as MeshInstance3D).visible:
			continue
		var t := _sphere_t(o, d, node.global_position, float(wd["r"]))
		if t >= 0.0 and t < best_wd:
			best_wd = t
			best_w = str(wd["id"])
	if best_w != "":
		_handle_world(best_w)


func _sphere_t(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc: Vector3 = o - c
	var b: float = oc.dot(d)
	var cc: float = oc.dot(oc) - r * r
	var disc: float = b * b - cc
	if disc <= 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t > 0.0 else -1.0


func _pinch_active() -> bool:
	# Hand-tracking hook: wire to XR hand pinch in a future pass.
	return false
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
