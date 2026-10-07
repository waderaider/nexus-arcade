## ARWorkoutGame.gd - "AR Workout": fitness target-punching game.
## Glowing target spheres spawn at random positions around the player (within
## ~3m, varied heights). Click a target to punch it: it bursts into particles,
## +10 pts plus a combo bonus. 60-second timer, live calorie estimate
## (hits * 0.5 kcal). Miss-clicks do nothing. End screen shows totals; R
## restarts.
## Upgraded: glow target/burst materials, three-point light rig, spark juice
## on hits, ambient motes, styled HUD label, XR pinch punching at the hand
## pointer, room-clamped target spawns, spatial anchor persistence.
## Desktop/mouse driven; _pinch_active() is the XR punch hook.
extends Node3D
class_name ARWorkoutGame

const GAME_TIME := 60.0
const MAX_TARGETS := 5
const COMBO_WINDOW := 2.5
const HIT_RADIUS_PX := 60.0

var camera: Camera3D = null
var time_left := GAME_TIME
var running := true
var score := 0
var hits := 0
var combo := 0
var max_combo := 0
var combo_timer := 0.0
var targets: Array = [] # Dictionaries: node, mat, bob_phase
var bursts: Array = [] # Dictionaries: node, vel, t
var spawn_timer := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var end_label: Label3D = null
var _anchor_timer := 0.0
# v0.7.0 ROOMKIT: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _has_room := false


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, "ar-workout_main")
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.4, 0.5), 2.5, 35)
	for i in range(MAX_TARGETS):
		_spawn_target()
	_apply_room_layout()


# ---------------------------------------------------------------- room layout

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: default behavior unchanged
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): rug -> glowing workout mat (exercise zone)
	_morph_anchors("RUG", "neon", 1)
	_has_room = true
	_update_hud()


## Exercise zone: real room floor bounds (0.25 m safety margin) minus the
## footprints of tables and furniture, so targets never spawn inside a couch.
func _point_in_exercise_zone(p: Vector3) -> bool:
	var safe := _room_bounds.grow(-0.25)
	if not safe.has_point(Vector2(p.x, p.z)):
		return false
	for f_v in _room_tables + _room_furniture:
		var f: Dictionary = f_v
		var fp: Vector3 = f["position"]
		var fs: Vector3 = f["size"]
		if fp.y + fs.y * 0.5 < 0.5:
			continue # low clutter (rugs etc.): targets float above it
		if absf(p.x - fp.x) <= fs.x * 0.5 + 0.15 and absf(p.z - fp.z) <= fs.z * 0.5 + 0.15:
			return false
	return true


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R):
		_restart()

	if running:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_end_game()
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
		# XR hand interaction: right-hand pinch near a target counts as a
		# punch. Mouse clicks stay on _unhandled_input; the mouse-press gate
		# keeps the kit's mouse fallback from double-triggering.
		var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
		if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_punch_check()

	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("ar-workout_main", global_transform)

	# Gentle bob on targets.
	for t_v in targets:
		var t: Dictionary = t_v
		var node: MeshInstance3D = t["node"]
		if is_instance_valid(node):
			var ph := float(t["bob_phase"]) + delta * 2.0
			t["bob_phase"] = ph
			node.position.y = float(t["base_y"]) + sin(ph) * 0.05

	# Burst particles fly out, shrink, and fade.
	for i in range(bursts.size() - 1, -1, -1):
		var b: Dictionary = bursts[i]
		var bnode: MeshInstance3D = b["node"]
		var t_left := float(b["t"]) - delta
		if not is_instance_valid(bnode) or t_left <= 0.0:
			if is_instance_valid(bnode):
				bnode.queue_free()
			bursts.remove_at(i)
			continue
		b["t"] = t_left
		bursts[i] = b
		bnode.position += (b["vel"] as Vector3) * delta
		bnode.scale = Vector3.ONE * (t_left / 0.5)

	# Keep the arena stocked with targets.
	if running:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and targets.size() < MAX_TARGETS:
			_spawn_target()
			spawn_timer = 0.4

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if running:
				_try_punch(mb.position)


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
	camera.look_at(Vector3(0.0, 1.2, 1.5), Vector3.UP)
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
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.09, 0.10, 0.13), "matte")
	add_child(floor_inst)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 48, Color.WHITE)
	hud_label.position = Vector3(-2.4, 2.5, 1.2)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Click a target to punch it | R: restart", 30, Color(0.75, 0.80, 0.90))
	help_label.position = Vector3(-2.4, 2.22, 1.2)
	help_label.pixel_size = 0.004
	add_child(help_label)
	end_label = Label3D.new()
	end_label.position = Vector3(0.0, 1.5, 0.8)
	end_label.pixel_size = 0.007
	end_label.font_size = 52
	end_label.outline_size = 10
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.visible = false
	add_child(end_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	var kcal := float(hits) * 0.5
	hud_label.text = "Score: %d   Time: %ds   Combo: x%d   kcal: %.1f" % [score, int(ceil(time_left)), combo, kcal]
	if _has_room:
		hud_label.text += "\nZone: %.1f x %.1f m (room-aware)" % [_room_bounds.size.x, _room_bounds.size.y]


func _spawn_target() -> void:
	if camera == null:
		return
	var pos := Vector3.ZERO
	for attempt in range(12):
		pos = Vector3(randf_range(-2.4, 2.4), randf_range(0.7, 1.9), randf_range(-0.4, 2.2))
		# ROOMKIT: keep targets inside the exercise zone (room minus furniture).
		if not _has_room or _point_in_exercise_zone(pos):
			if pos.distance_to(camera.global_position) <= 3.0:
				break
	# AR: keep spawned targets inside the known room bounds.
	pos = ARUpgradeKit.clamp_to_room(pos)
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	node.mesh = sphere
	var col := Color(1.0, 0.55, 0.15) if randf() < 0.5 else Color(0.3, 1.0, 0.5)
	node.material_override = GraphicsPolish.glow(col, 1.8)
	node.position = pos
	add_child(node)
	targets.append({"node": node, "mat": node.material_override, "bob_phase": randf() * TAU, "base_y": pos.y})


func _try_punch(screen_pos: Vector2) -> void:
	if camera == null:
		return
	for i in range(targets.size() - 1, -1, -1):
		var t: Dictionary = targets[i]
		var node: MeshInstance3D = t["node"]
		if not is_instance_valid(node):
			targets.remove_at(i)
			continue
		var sp := camera.unproject_position(node.global_position)
		if sp.distance_to(screen_pos) <= HIT_RADIUS_PX:
			targets.remove_at(i)
			_on_target_hit(node)
			return
	# Miss-click: intentionally does nothing.


func _punch_check() -> void:
	# XR path: a pinch counts as a punch on the nearest target within reach
	# of the hand pointer.
	if camera == null or targets.is_empty():
		return
	var hand_point: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	var best := -1
	var best_d := 0.55
	for i in range(targets.size()):
		var t: Dictionary = targets[i]
		var node: MeshInstance3D = t["node"]
		if not is_instance_valid(node):
			continue
		var d := node.global_position.distance_to(hand_point)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		var t2: Dictionary = targets[best]
		var node2: MeshInstance3D = t2["node"]
		targets.remove_at(best)
		_on_target_hit(node2)


func _on_target_hit(node: MeshInstance3D) -> void:
	hits += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_timer = COMBO_WINDOW
	score += 10 + combo * 2
	_spawn_burst(node.global_position)
	GraphicsPolish.spawn_sparks(self, node.global_position, Color(1.0, 0.85, 0.35), 18)
	node.queue_free()


func _spawn_burst(pos: Vector3) -> void:
	for i in range(7):
		var p := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		p.mesh = sphere
		p.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.3), 2.0)
		p.position = pos
		add_child(p)
		var vel := Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.5), randf_range(-1.5, 1.5))
		bursts.append({"node": p, "vel": vel, "t": 0.5})


func _end_game() -> void:
	running = false
	var kcal := float(hits) * 0.5
	end_label.text = "WORKOUT COMPLETE!\nHits: %d\nMax combo: x%d\nCalories: %.1f kcal\nScore: %d\n\nPress R to restart" % [hits, max_combo, kcal, score]
	end_label.visible = true


func _restart() -> void:
	for t_v in targets:
		var t: Dictionary = t_v
		var node: MeshInstance3D = t["node"]
		if is_instance_valid(node):
			node.queue_free()
	targets.clear()
	for b_v in bursts:
		var b: Dictionary = b_v
		var bnode: MeshInstance3D = b["node"]
		if is_instance_valid(bnode):
			bnode.queue_free()
	bursts.clear()
	time_left = GAME_TIME
	running = true
	score = 0
	hits = 0
	combo = 0
	max_combo = 0
	combo_timer = 0.0
	spawn_timer = 0.0
	end_label.visible = false
	# AR: game reset -> persist the anchor too.
	ARUpgradeKit.save_anchor("ar-workout_main", global_transform)
	for i in range(MAX_TARGETS):
		_spawn_target()
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
