## HwDoorDash - "Door Dash": three haunted doors on a wall. Knock (pinch near
## a door, or click it) to trick-or-treat: candy (+1) or trick (-1). Most
## candy in 90 seconds wins. R restarts; hold pinch 1s on the end screen.
extends Node3D

const ROUND_TIME := 90.0
const DOOR_XS := [-1.4, 0.0, 1.4]
const DOOR_Y := 1.15
const WALL_Z := -2.6
const KNOCK_RADIUS := 0.85
const COOLDOWN := 1.5
const CANDY_CHANCE := 0.70

const ST_PLAY := 0
const ST_OVER := 1

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var knocks := 0
var doors: Array = []
var _time := 0.0
var hud_label: Label3D = null
var help_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var knock_player: AudioStreamPlayer = null
var candy_player: AudioStreamPlayer = null
var trick_player: AudioStreamPlayer = null
var win_player: AudioStreamPlayer = null
var _anchor_timer := 0.0
var _pinch_hold := 0.0

## RoomKit v0.7.0: cached room layout + fake wall refs (retired on real walls).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2.0, -2.0, 4.0, 4.0)
var _fake_wall: MeshInstance3D = null
var _door_title: Label3D = null
var _flank_pumpkins: Array = []


func _ready() -> void:
	_add_light_rig()
	_ensure_fallback_camera()
	_build_wall()
	_build_hud()
	knock_player = _make_player(_make_tone(220.0, 0.12, 0.60))
	candy_player = _make_player(_make_tone(1320.0, 0.25, 0.50))
	trick_player = _make_player(_make_tone(110.0, 0.50, 0.60))
	win_player = _make_player(_make_tone(880.0, 0.50, 0.50))
	ARUpgradeKit.apply_anchor(self, "hw_door_dash_main")
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.snap_to_floor(self)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, -1.8), 2.2, 30)
	_apply_room_layout()


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 1.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.3, -2.6), Vector3.UP)
	camera.current = true


func _build_wall() -> void:
	# Haunted wall.
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(4.8, 2.8, 0.2)
	wall.mesh = wb
	wall.position = Vector3(0.0, 1.4, WALL_Z - 0.15)
	wall.material_override = GraphicsPolish.pbr(Color(0.13, 0.10, 0.16), 0.0, 0.9)
	add_child(wall)
	_fake_wall = wall
	# Title.
	var title := GraphicsPolish.make_label("TRICK OR TREAT!", 56, Color(1.0, 0.6, 0.15))
	title.position = Vector3(0.0, 2.65, WALL_Z + 0.1)
	add_child(title)
	_door_title = title
	# Floor strip.
	var floor_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_inst.mesh = plane
	floor_inst.position = Vector3(0.0, -0.02, -1.0)
	floor_inst.material_override = GraphicsPolish.pbr(Color(0.07, 0.06, 0.08), 0.0, 0.95)
	add_child(floor_inst)
	# The three doors.
	var hues := [Color(0.45, 0.20, 0.55), Color(0.55, 0.28, 0.15), Color(0.20, 0.30, 0.55)]
	for i in range(3):
		_make_door(i, DOOR_XS[i], hues[i])
	# Pumpkins flanking the wall.
	for px in [-2.2, 2.2]:
		var p := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.20
		ps.height = 0.40
		p.mesh = ps
		p.position = Vector3(px, 0.20, WALL_Z + 0.5)
		p.material_override = GraphicsPolish.glow(Color(1.0, 0.55, 0.10), 1.2)
		add_child(p)
		_flank_pumpkins.append(p)
	GraphicsPolish.make_point_light(self, Vector3(0.0, 2.0, WALL_Z + 1.0), Color(1.0, 0.6, 0.2), 0.8, 5.0)


func _make_door(idx: int, x: float, color: Color) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, DOOR_Y, WALL_Z)
	add_child(root)
	# Frame.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.10, 2.00, 0.12)
	frame.mesh = fb
	frame.material_override = GraphicsPolish.pbr(Color(0.25, 0.16, 0.10), 0.0, 0.85)
	root.add_child(frame)
	# Door panel.
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.90, 1.80, 0.08)
	panel.mesh = pb
	var panel_mat := GraphicsPolish.pbr(color, 0.1, 0.6)
	panel.material_override = panel_mat
	panel.position = Vector3(0.0, 0.0, 0.05)
	root.add_child(panel)
	# Knocker knob.
	var knob := MeshInstance3D.new()
	var ks := SphereMesh.new()
	ks.radius = 0.07
	ks.height = 0.14
	knob.mesh = ks
	knob.position = Vector3(0.28, 0.0, 0.12)
	var knob_mat := GraphicsPolish.glow(Color(1.0, 0.85, 0.3), 1.8)
	knob.material_override = knob_mat
	root.add_child(knob)
	# Number above the door.
	var num := GraphicsPolish.make_label(str(idx + 1), 48, Color(1.0, 1.0, 1.0))
	num.position = Vector3(0.0, 1.25, 0.1)
	root.add_child(num)
	doors.append({
		"root": root, "panel": panel, "panel_mat": panel_mat,
		"knob_mat": knob_mat, "x": x, "cooldown": 0.0, "punch": 0.0,
		"flash": 0.0, "base_color": color,
	})


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("DOOR DASH", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-2.4, 2.9, -1.2)
	add_child(hud_label)
	help_label = GraphicsPolish.make_label("Knock a door: pinch / click it!  Candy +1, Trick -1  R: restart", 26, Color(0.8, 0.85, 0.9))
	help_label.position = Vector3(-2.4, 2.35, -1.2)
	add_child(help_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 1.9, -1.8)
	add_child(msg_label)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "DOOR DASH\nTime: %ds   Candy: %d   Knocks: %d" % [int(ceil(time_left)), score, knocks]


func _show_msg(text: String, duration: float = 1.0, color: Color = Color(1.0, 0.85, 0.3)) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_label.modulate = color
	msg_timer = duration


func _process(delta: float) -> void:
	_time += delta
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_door_dash_main", global_transform)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0 and state == ST_PLAY and msg_label != null:
			msg_label.text = ""
	_step_doors(delta)
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_pinch_hold += delta
			if _pinch_hold >= 1.0:
				_pinch_hold = 0.0
				_reset_game()
		else:
			_pinch_hold = 0.0
		_update_hud()
		return
	# ST_PLAY.
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
			or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
		_try_knock()
	_update_hud()


func _step_doors(delta: float) -> void:
	for d_v in doors:
		var d: Dictionary = d_v
		if float(d["cooldown"]) > 0.0:
			d["cooldown"] = float(d["cooldown"]) - delta
		var root: Node3D = d["root"]
		# Knock punch animation.
		var punch := float(d["punch"])
		if punch > 0.0:
			punch = maxf(0.0, punch - delta * 4.0)
			d["punch"] = punch
		var s := 1.0 + 0.10 * punch
		root.scale = Vector3(s, s, s)
		# Trick flash fades back to the base color.
		var flash := float(d["flash"])
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 2.0)
			d["flash"] = flash
			var mat: StandardMaterial3D = d["panel_mat"]
			var base: Color = d["base_color"]
			mat.albedo_color = base.lerp(Color(1.0, 0.1, 0.1), flash)
		# Knob glow pulse.
		var knob_mat: StandardMaterial3D = d["knob_mat"]
		GraphicsPolish.pulse_glow(knob_mat, 1.5, 0.9, _time + float(d["x"]), 2.5)


func _pointer_ray() -> Array:
	if ARUpgradeKit.is_xr_active():
		return ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if camera == null:
		return [Vector3.ZERO, Vector3(0.0, 0.0, -1.0)]
	var mp := get_viewport().get_mouse_position()
	return [camera.project_ray_origin(mp), camera.project_ray_normal(mp)]


func _try_knock() -> void:
	if state != ST_PLAY:
		return
	var r := _pointer_ray()
	var origin: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var best := -1
	var best_d := KNOCK_RADIUS
	for i in range(doors.size()):
		var d: Dictionary = doors[i]
		var root: Node3D = d["root"]
		var to: Vector3 = root.global_position - origin
		var t := to.dot(dir)
		if t < 0.0 or t > 9.0:
			continue
		var perp := (to - dir * t).length()
		if perp < best_d:
			best_d = perp
			best = i
	if best >= 0:
		_knock_door(doors[best])


func _knock_door(d: Dictionary) -> void:
	if float(d["cooldown"]) > 0.0:
		return
	d["cooldown"] = COOLDOWN
	d["punch"] = 1.0
	knocks += 1
	var root: Node3D = d["root"]
	if knock_player != null:
		knock_player.play()
	if randf() < CANDY_CHANCE:
		score += 1
		GraphicsPolish.spawn_sparks(self, root.global_position + Vector3(0.0, 0.6, 0.3), Color(1.0, 0.7, 0.2), 22)
		_show_msg("CANDY! +1", 0.9, Color(1.0, 0.8, 0.3))
		if candy_player != null:
			candy_player.play()
	else:
		score = maxi(0, score - 1)
		d["flash"] = 1.0
		GraphicsPolish.spawn_sparks(self, root.global_position + Vector3(0.0, 0.6, 0.3), Color(1.0, 0.1, 0.1), 22)
		_show_msg("TRICK! -1", 0.9, Color(1.0, 0.3, 0.3))
		if trick_player != null:
			trick_player.play()


func _game_over() -> void:
	state = ST_OVER
	ARUpgradeKit.save_anchor("hw_door_dash_main", global_transform)
	var rank := "Spooky Stroller"
	if score >= 25:
		rank = "CANDY CHAMPION!"
	elif score >= 12:
		rank = "Treat Pro"
	_show_msg("TIME UP!\nCandy: %d (%d knocks)\n%s\nR or hold pinch 1s to play again" % [score, knocks, rank], 600.0)
	GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, -1.8), 70)
	if win_player != null:
		win_player.play()


func _reset_game() -> void:
	for d_v in doors:
		var d: Dictionary = d_v
		d["cooldown"] = 0.0
		d["punch"] = 0.0
		d["flash"] = 0.0
		var mat: StandardMaterial3D = d["panel_mat"]
		mat.albedo_color = d["base_color"]
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	knocks = 0
	_pinch_hold = 0.0
	msg_timer = 0.0
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_door_dash_main", global_transform)


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames_count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames_count * 2)
	for i in range(frames_count):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames_count)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

# ---------------------------------------------------------- RoomKit v0.7.0

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	# v0.7.0 MORPH-C: the doors ARE the game — up to two become haunted dungeon gates to dash through; the rug is the arcane start circle.
	var _morph0_door := RoomKit.get_anchors("DOOR")
	for _mi in range(mini(_morph0_door.size(), 2)):
		RoomKit.morph(_morph0_door[_mi], "haunted")
	var _morph1_rug := RoomKit.get_anchors("RUG")
	if not _morph1_rug.is_empty():
		RoomKit.morph(_morph1_rug[0], "arcane")
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	if _room_walls.is_empty() or doors.size() < 3:
		return
	# Mount the three doors on the largest real wall, facing the room.
	var w := _room_largest_wall()
	if w.is_empty():
		return
	var wp: Vector3 = w["position"]
	var n: Vector3 = w["normal"]
	n.y = 0.0
	if n.length() < 0.01:
		return
	n = n.normalized()
	var yaw := atan2(-n.x, -n.z)
	var tangent := Vector3(-n.z, 0.0, n.x)
	var span: float = maxf(minf((w["size"] as Vector2).x - 1.6, 2.8), 1.2)
	for i in doors.size():
		var d: Dictionary = doors[i]
		var root: Node3D = d["root"]
		var face: Vector3 = wp + n * 0.14 + tangent * ((float(i) - 1.0) * span * 0.5)
		face.y = DOOR_Y
		root.global_position = face
		root.global_rotation = Vector3(0.0, yaw, 0.0)
	# The fake wall retires; the title and flanking pumpkins move along.
	if _fake_wall != null:
		_fake_wall.visible = false
	if _door_title != null:
		_door_title.global_position = wp + n * 0.18 + Vector3(0.0, 2.62, 0.0)
		_door_title.global_rotation = Vector3(0.0, yaw, 0.0)
	for pi in _flank_pumpkins.size():
		var pk: MeshInstance3D = _flank_pumpkins[pi]
		var side := -1.0 if pi == 0 else 1.0
		var pp: Vector3 = wp + n * 0.55 + tangent * side * (span * 0.5 + 0.45)
		pp.y = 0.20
		pk.global_position = pp


## RoomKit: the wall with the largest face area, or {} when none.
func _room_largest_wall() -> Dictionary:
	var best := {}
	var best_a := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var sz: Vector2 = w["size"]
		var a := sz.x * sz.y
		if a > best_a:
			best_a = a
			best = w
	return best
