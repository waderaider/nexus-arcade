## RhythmBoxer: punch incoming orbs on the beat.
## Orbs fly toward you on a metronome; the BPM escalates as you survive.
## PUNCH = a fast hand motion through an orb's zone (XR hand velocity),
## or a mouse click on an orb at the right time (desktop fallback).
## Timing windows: PERFECT (<=0.10s) / GOOD (<=0.22s) / MISS.
## A miss costs HP; combos multiply your score. HP hits 0 = game over.
## Score and max combo are tracked. R restarts.
extends Node3D

const SPAWN_Z := -9.0
const HIT_Z := -1.6
const ORB_R := 0.16
const PERFECT_WINDOW := 0.10
const GOOD_WINDOW := 0.22
const PUNCH_SPEED := 2.0
const START_BPM := 90.0
const MAX_BPM := 150.0
const BPM_STEP := 5.0
const TRAVEL_BEATS := 4.0
const START_HP := 100.0
const MISS_DMG := 8.0

var camera: Camera3D = null
var bpm := START_BPM
var beat_interval := 60.0 / START_BPM
var next_beat := 0.0
var beats := 0
var elapsed := 0.0
var state := "playing"
var score := 0
var combo := 0
var max_combo := 0
var hp := START_HP
var orbs: Array = []
var hud_score: Label3D = null
var hud_combo: Label3D = null
var hud_bpm: Label3D = null
var hud_msg: Label3D = null
var hp_fg: MeshInstance3D = null
var beat_ring: MeshInstance3D = null
var beat_ring_mat: StandardMaterial3D = null
var ring_pulse := 0.0
var glove_l: MeshInstance3D = null
var glove_r: MeshInstance3D = null
var prev_l := Vector3.ZERO
var prev_r := Vector3.ZERO
var punch_cd_l := 0.0
var punch_cd_r := 0.0
var orb_colors := [Color(1.0, 0.4, 0.4), Color(0.4, 1.0, 0.6), Color(0.4, 0.7, 1.0), Color(1.0, 0.9, 0.3)]
# v0.7.0 RoomKit: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "rhythm-boxer_main")
	_ensure_camera()
	_ensure_env()
	_ensure_light()
	_build_arena()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -3.0), 2.5, 40)
	_reset()
	_apply_room_layout() # v0.7.0: orbs fly in from real wall faces


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.6, 3.2)
		cam.look_at(Vector3(0.0, 1.4, -2.0), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.35, 0.35)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _build_arena() -> void:
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_inst.mesh = plane
	floor_inst.material_override = GraphicsPolish.pbr_preset(Color(0.06, 0.04, 0.05), "matte")
	add_child(floor_inst)
	# Two glowing lane guides from spawn to the hit zone.
	for sx in [-1.2, 1.2]:
		var lane := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, SPAWN_Z * -1.0 + HIT_Z)
		lane.mesh = bm
		lane.material_override = GraphicsPolish.glow(Color(1.0, 0.4, 0.4), 1.2)
		lane.position = Vector3(sx, 1.4, (SPAWN_Z + HIT_Z) / 2.0)
		add_child(lane)
	# Beat ring at the hit zone.
	beat_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	beat_ring.mesh = tm
	beat_ring_mat = GraphicsPolish.glow(Color(1.0, 0.5, 0.2), 1.6)
	beat_ring.material_override = beat_ring_mat
	beat_ring.position = Vector3(0.0, 1.4, HIT_Z)
	add_child(beat_ring)
	# Gloves.
	glove_l = _make_glove(Color(0.3, 0.8, 1.0))
	glove_r = _make_glove(Color(1.0, 0.5, 0.3))


func _make_glove(color: Color) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	g.mesh = sm
	g.material_override = GraphicsPolish.glow(color, 1.8)
	add_child(g)
	g.add_child(GraphicsPolish.make_trail(color, 0.06))
	return g


func _build_hud() -> void:
	hud_score = GraphicsPolish.make_label("", 56, Color(1, 1, 1))
	hud_score.position = Vector3(0.0, 2.9, -1.6)
	add_child(hud_score)
	hud_combo = GraphicsPolish.make_label("", 48, Color(1.0, 0.85, 0.3))
	hud_combo.position = Vector3(0.0, 2.55, -1.6)
	add_child(hud_combo)
	hud_bpm = GraphicsPolish.make_label("", 40, Color(0.7, 0.9, 1.0))
	hud_bpm.position = Vector3(0.0, 0.5, -1.2)
	add_child(hud_bpm)
	hud_msg = GraphicsPolish.make_label("", 84, Color(1.0, 0.4, 0.4))
	hud_msg.position = Vector3(0.0, 1.9, -1.4)
	add_child(hud_msg)
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(2.2, 0.16, 0.02)
	bg.mesh = bgm
	var bgmat := GraphicsPolish.pbr(Color(0.08, 0.08, 0.08), 0.0, 0.8)
	bgmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bgmat
	bg.position = Vector3(0.0, 3.25, -1.6)
	add_child(bg)
	hp_fg = MeshInstance3D.new()
	var fgm := BoxMesh.new()
	fgm.size = Vector3(2.1, 0.1, 0.03)
	hp_fg.mesh = fgm
	var fmat := GraphicsPolish.glow(Color(0.3, 1.0, 0.4), 1.4)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hp_fg.material_override = fmat
	hp_fg.position = Vector3(0.0, 3.25, -1.6)
	add_child(hp_fg)


func _reset() -> void:
	bpm = START_BPM
	beat_interval = 60.0 / bpm
	beats = 0
	elapsed = 0.0
	next_beat = 1.0
	score = 0
	combo = 0
	max_combo = 0
	hp = START_HP
	state = "playing"
	for o in orbs:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	orbs.clear()
	hud_msg.text = ""


func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_key_pressed(KEY_R):
		_reset()
	if state != "playing":
		return
	while elapsed >= next_beat:
		_on_beat()
		next_beat += beat_interval
	_update_orbs(delta)
	_update_hands(delta)
	_update_gloves()
	ring_pulse = maxf(0.0, ring_pulse - delta * 2.5)
	var s := 1.0 + ring_pulse * 0.6
	beat_ring.scale = Vector3(s, s, s)
	GraphicsPolish.pulse_glow(beat_ring_mat, 1.2, 0.9, elapsed, 3.0)
	hp_fg.scale.x = clampf(hp / START_HP, 0.01, 1.0)
	hud_score.text = "Score %d" % score
	hud_combo.text = "COMBO x%d" % combo if combo > 1 else ""
	hud_bpm.text = "%d BPM" % int(bpm)


func _on_beat() -> void:
	beats += 1
	ring_pulse = 1.0
	if beats % 16 == 0 and bpm < MAX_BPM:
		bpm = minf(MAX_BPM, bpm + BPM_STEP)
		beat_interval = 60.0 / bpm
	_spawn_orb()


func _spawn_orb() -> void:
	var travel := TRAVEL_BEATS * beat_interval
	# Punch lane target (what the hit test uses).
	var tx := randf_range(-1.0, 1.0)
	var ty := randf_range(1.1, 1.7)
	var sx := tx
	var sy := ty
	var sz := SPAWN_Z
	# v0.7.0: fly in from a random wall face the player looks at.
	if not _room_walls.is_empty():
		var cands: Array = []
		for w_v in _room_walls:
			var w: Dictionary = w_v
			if (w["normal"] as Vector3).normalized().z > 0.5:
				cands.append(w)
		if not cands.is_empty():
			var w: Dictionary = cands[randi() % cands.size()]
			var wp: Vector3 = w["position"]
			var wn: Vector3 = (w["normal"] as Vector3).normalized()
			var wsize: Vector2 = w["size"]
			var tangent: Vector3 = wn.cross(Vector3.UP)
			tangent = tangent.normalized() if tangent.length() > 0.01 else Vector3.RIGHT
			var flat_n := Vector3(wn.x, 0.0, wn.z).normalized()
			var sp: Vector3 = wp + tangent * randf_range(-1.0, 1.0) * maxf(wsize.x * 0.5 - 0.4, 0.1) + flat_n * 0.3
			if sp.z < HIT_Z - 0.6:
				sx = sp.x
				sy = clampf(sp.y, 1.0, 1.9)
				sz = sp.z
	var speed := (HIT_Z - sz) / travel
	var col: Color = orb_colors[beats % orb_colors.size()]
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = ORB_R
	sm.height = ORB_R * 2.0
	node.mesh = sm
	node.material_override = GraphicsPolish.glow(col, 2.0)
	node.position = Vector3(sx, sy, sz)
	node.add_child(GraphicsPolish.make_trail(col, 0.08))
	add_child(node)
	orbs.append({
		"node": node,
		"speed": speed,
		"arrival": elapsed + travel,
		"hit": false,
		"x": tx,
		"y": ty,
		"sx": sx,
		"sy": sy,
		"t0": elapsed,
		"travel": travel,
	})


func _update_orbs(delta: float) -> void:
	for i in range(orbs.size() - 1, -1, -1):
		var o: Dictionary = orbs[i]
		var node: MeshInstance3D = o["node"]
		if not is_instance_valid(node):
			orbs.remove_at(i)
			continue
		node.position.z += float(o["speed"]) * delta
		# Converge from the wall spawn point onto the punch lane.
		if o.has("t0"):
			var k := clampf((elapsed - float(o["t0"])) / float(o["travel"]), 0.0, 1.0)
			node.position.x = lerpf(float(o["sx"]), float(o["x"]), k)
			node.position.y = lerpf(float(o["sy"]), float(o["y"]), k)
		if not bool(o["hit"]) and elapsed > float(o["arrival"]) + GOOD_WINDOW:
			_register_miss(o)
			node.queue_free()
			orbs.remove_at(i)


func _update_hands(delta: float) -> void:
	punch_cd_l = maxf(0.0, punch_cd_l - delta)
	punch_cd_r = maxf(0.0, punch_cd_r - delta)
	if not ARUpgradeKit.is_xr_active():
		return
	var pl: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_LEFT, 1.2)
	var pr: Vector3 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.2)
	if prev_l != Vector3.ZERO and punch_cd_l <= 0.0:
		if (pl - prev_l).length() / maxf(delta, 0.001) > PUNCH_SPEED:
			punch_cd_l = 0.3
			_try_punch(pl)
	if prev_r != Vector3.ZERO and punch_cd_r <= 0.0:
		if (pr - prev_r).length() / maxf(delta, 0.001) > PUNCH_SPEED:
			punch_cd_r = 0.3
			_try_punch(pr)
	prev_l = pl
	prev_r = pr


func _update_gloves() -> void:
	if ARUpgradeKit.is_xr_active():
		glove_l.position = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_LEFT, 1.2)
		glove_r.position = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.2)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mp)
		var dir := camera.project_ray_normal(mp)
		if absf(dir.z) > 0.0001:
			var t := (HIT_Z - origin.z) / dir.z
			if t > 0.0:
				glove_r.position = origin + dir * t
		glove_l.position = Vector3(-0.5, 1.3, HIT_Z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == "playing":
			_desktop_punch()


func _desktop_punch() -> void:
	if camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.z) < 0.0001:
		return
	var t := (HIT_Z - origin.z) / dir.z
	if t <= 0.0:
		return
	_try_punch(origin + dir * t)


func _try_punch(punch_pos: Vector3) -> void:
	var best := -1
	var best_dt := GOOD_WINDOW + 1.0
	for i in range(orbs.size()):
		var o: Dictionary = orbs[i]
		if bool(o["hit"]):
			continue
		var d2 := Vector2(float(o["x"]) - punch_pos.x, float(o["y"]) - punch_pos.y).length()
		if d2 > 0.6:
			continue
		var dt := absf(elapsed - float(o["arrival"]))
		if dt < best_dt:
			best_dt = dt
			best = i
	if best < 0:
		return
	if best_dt <= GOOD_WINDOW:
		var o: Dictionary = orbs[best]
		o["hit"] = true
		var node: MeshInstance3D = o["node"]
		var perfect := best_dt <= PERFECT_WINDOW
		combo += 1
		max_combo = maxi(max_combo, combo)
		var mult := 1.0 + minf(combo, 40) / 20.0
		score += int((100 if perfect else 40) * mult)
		GraphicsPolish.spawn_sparks(self, node.position, Color(1.0, 0.9, 0.3) if perfect else Color(0.6, 0.9, 1.0), 30 if perfect else 16)
		var lbl := GraphicsPolish.make_label("PERFECT!" if perfect else "GOOD", 40, Color(1.0, 0.9, 0.3) if perfect else Color(0.7, 0.9, 1.0))
		lbl.position = node.position + Vector3(0, 0.35, 0)
		add_child(lbl)
		var tw := create_tween()
		tw.tween_property(lbl, "position:y", lbl.position.y + 0.4, 0.6)
		tw.tween_callback(lbl.queue_free)
		node.queue_free()
		orbs.remove_at(best)


func _register_miss(o: Dictionary) -> void:
	combo = 0
	hp = maxf(0.0, hp - MISS_DMG)
	var node: MeshInstance3D = o["node"]
	GraphicsPolish.spawn_sparks(self, Vector3(float(o["x"]), float(o["y"]), HIT_Z), Color(1.0, 0.2, 0.2), 14)
	if hp <= 0.0:
		state = "gameover"
		hud_msg.text = "GAME OVER - Score %d  Max combo x%d  (R to retry)" % [score, max_combo]
		ARUpgradeKit.save_anchor("rhythm-boxer_main", global_transform)


# ------------------------------------------------- v0.7.0 RoomKit ----
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not is_inside_tree() or not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	# Orbs spawn from wall faces (picked per-orb in _spawn_orb); nothing else
	# moves: the hit zone and HUD keep their default floating-arena layout.
	# v0.7.0 MORPH: rug becomes the neon boxing-ring canvas.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_rugs := RoomKit.get_anchors("RUG")
		if not _morph_rugs.is_empty():
			RoomKit.morph(_morph_rugs[0], "neon")
