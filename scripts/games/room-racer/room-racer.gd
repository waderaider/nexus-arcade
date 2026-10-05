## RoomRacerGame.gd - Floor-projected oval hover-car race against an AI car.
## Steer with A/D or Left/Right arrows (or move the mouse left/right), hold
## W/Up for boost. First to complete 3 laps wins. R or click restarts.
extends Node3D
class_name RoomRacerGame

const RX := 2.4
const RZ := 1.6
const CENTER := Vector3(0.0, 0.0, 0.9)
const LAPS_TO_WIN := 3
const BASE_SPEED := 0.55 # rad/s
const BOOST_MULT := 1.9
const LAT_WIDTH := 0.22

var _cam: Camera3D
var _mouse_x := 0.0
var _has_mouse := false

var _phase := 0 # 0 = countdown, 1 = racing, 2 = done
var _countdown := 2.5
var _race_time := 0.0
var _winner := ""

var _player := {}
var _ai := {}

var _hud_label: Label3D
var _ai_label: Label3D
var _help_label: Label3D
var _msg_label: Label3D
var _track_center := CENTER
var _anchor_timer := 0.0


func _ready() -> void:
	_ensure_camera()
	_build_light_and_floor()
	_track_center = ARUpgradeKit.clamp_to_room(CENTER)
	_build_track()
	_player = _make_car(Color(0.2, 0.9, 1.0), "YOU")
	_ai = _make_car(Color(1.0, 0.55, 0.15), "AI")
	_build_labels()
	_reset_race()
	# AR: restore the saved room anchor in XR sessions.
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.apply_anchor(self, "room-racer_main")


func _process(delta: float) -> void:
	_update_anchor_timer(delta)
	# XR pinch restarts a finished race (mouse click / R keep working on desktop).
	if _phase == 2 and ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_reset_race()
	if _phase == 0:
		_countdown -= delta
		_msg_label.text = "GO in %d..." % int(ceil(_countdown))
		if _countdown <= 0.0:
			_phase = 1
			_race_time = 0.0
			_player["lap_start"] = 0.0
			_ai["lap_start"] = 0.0
			_msg_label.text = "GO!"
	elif _phase == 1:
		_race_time += delta
		_update_player(delta)
		_update_ai(delta)
		_msg_label.text = ""
		_refresh_hud()
	if Input.is_key_pressed(KEY_R) and _phase == 2:
		_reset_race()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_x = (event as InputEventMouseMotion).position.x
		_has_mouse = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _phase == 2:
				_reset_race()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_R and _phase == 2:
			_reset_race()


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- setup ---

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 4.8, 4.6)
	add_child(_cam)
	_cam.look_at(CENTER, Vector3.UP)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light_and_floor() -> void:
	_add_polish_light_rig()
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 16.0)
	floor_mi.mesh = plane
	floor_mi.material_override = GraphicsPolish.pbr_preset(Color(0.09, 0.1, 0.13), "matte")
	add_child(floor_mi)


func _build_track() -> void:
	var torus := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.72
	tm.outer_radius = 2.28
	tm.rings = 64
	tm.ring_segments = 12
	torus.mesh = tm
	torus.scale = Vector3(1.2, 0.1, 0.8)
	torus.position = _track_center + Vector3(0, 0.02, 0)
	var tmat := GraphicsPolish.pbr(Color(0.16, 0.17, 0.22), 0.3, 0.4)
	tmat.emission_enabled = true
	tmat.emission = Color(0.05, 0.12, 0.18)
	tmat.emission_energy_multiplier = 0.6
	torus.material_override = tmat
	add_child(torus)
	# Start/finish line across the track at angle 0.
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.75, 0.03, 0.14)
	line.mesh = lm
	line.material_override = GraphicsPolish.glow(Color(0.95, 0.95, 0.95), 0.8)
	line.position = _track_point(0.0, 0.0) + Vector3(0, 0.02, 0)
	add_child(line)


func _make_car(color: Color, tag: String) -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.09, 0.4)
	body.mesh = bm
	var bmat := GraphicsPolish.pbr(color, 0.6, 0.3)
	bmat.emission_enabled = true
	bmat.emission = color
	bmat.emission_energy_multiplier = 1.2
	body.material_override = bmat
	body.position = Vector3(0, 0.12, 0)
	root.add_child(body)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.09
	gm.height = 0.05
	glow.mesh = gm
	glow.material_override = bmat
	glow.position = Vector3(0, 0.045, 0)
	root.add_child(glow)
	var label := Label3D.new()
	label.text = tag
	label.font_size = 48
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 0.42, 0)
	root.add_child(label)
	var trail := GraphicsPolish.make_trail(color, 0.06)
	trail.position = Vector3(0, 0.08, -0.2)
	root.add_child(trail)
	add_child(root)
	return {"node": root, "angle": 0.0, "lat": 0.0, "lap": 1,
			"lap_start": 0.0, "best": -1.0, "finished": false, "finish_time": 0.0}


func _make_label(text: String, pos: Vector3, font_size: int = 56) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = pos
	add_child(label)
	return label


func _build_labels() -> void:
	_hud_label = _make_label("", Vector3(-3.1, 1.7, 0.9), 56)
	_ai_label = _make_label("", Vector3(3.1, 1.7, 0.9), 56)
	_msg_label = _make_label("", Vector3(0.0, 2.5, 0.9), 84)
	_help_label = _make_label(
			"Room Racer - A/D or arrows to steer, W/Up to boost.\nMouse left/right also steers. 3 laps wins. R restarts.",
			Vector3(0.0, 0.6, 4.3), 40)


# ---------------------------------------------------------------- racing ---

func _track_point(a: float, lat: float) -> Vector3:
	var p := _track_center + Vector3(RX * cos(a), 0.07, RZ * sin(a))
	var n := Vector3(cos(a) / RX, 0.0, sin(a) / RZ)
	if n.length() > 0.0001:
		p += n.normalized() * lat * LAT_WIDTH
	return p


func _track_tangent(a: float) -> Vector3:
	var t := Vector3(-RX * sin(a), 0.0, RZ * cos(a))
	return t.normalized()


func _place_car(car: Dictionary) -> void:
	var a: float = car["angle"]
	var node := car["node"] as Node3D
	node.position = _track_point(a, float(car["lat"]))
	node.basis = Basis.looking_at(_track_tangent(a))


func _crossed_line(car: Dictionary, prev: float, now: float) -> void:
	if prev > PI * 1.5 and now < PI * 0.5:
		car["lap"] = int(car["lap"]) + 1
		var lap_time := _race_time - float(car["lap_start"])
		car["lap_start"] = _race_time
		if float(car["best"]) < 0.0 or lap_time < float(car["best"]):
			car["best"] = lap_time
		if int(car["lap"]) > LAPS_TO_WIN and not bool(car["finished"]):
			car["finished"] = true
			car["finish_time"] = _race_time
			_on_finish(car)


func _update_player(delta: float) -> void:
	if bool(_player["finished"]):
		return
	var steer := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
	var lat: float = _player["lat"]
	if steer != 0.0:
		lat = clampf(lat + steer * 2.4 * delta, -1.0, 1.0)
	elif _has_mouse:
		var vp := get_viewport().get_visible_rect().size
		if vp.x > 1.0:
			var target := clampf(_mouse_x / vp.x, 0.0, 1.0) * 2.0 - 1.0
			lat = lerpf(lat, target, minf(1.0, delta * 4.0))
	_player["lat"] = lat
	var boost := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var speed := BASE_SPEED * (BOOST_MULT if boost else 1.0) * (1.0 - 0.2 * absf(lat))
	var prev: float = _player["angle"]
	var now := fmod(prev + speed * delta, TAU)
	_player["angle"] = now
	_crossed_line(_player, prev, now)
	_place_car(_player)


func _update_ai(delta: float) -> void:
	if bool(_ai["finished"]):
		return
	var speed := 0.52 + 0.16 * sin(_race_time * 0.6) + 0.05 * sin(_race_time * 1.7)
	_ai["lat"] = 0.45 * sin(_race_time * 0.5)
	var prev: float = _ai["angle"]
	var now := fmod(prev + maxf(speed, 0.2) * delta, TAU)
	_ai["angle"] = now
	_crossed_line(_ai, prev, now)
	_place_car(_ai)


func _on_finish(car: Dictionary) -> void:
	if _phase != 1:
		return
	_phase = 2
	GraphicsPolish.spawn_confetti(self, Vector3(_track_center.x, 1.2, _track_center.z), 80)
	if car == _player:
		_winner = "YOU WIN!"
	else:
		_winner = "AI WINS!"
	_refresh_hud()


func _fmt_time(t: float) -> String:
	if t < 0.0:
		return "--"
	return "%.1fs" % t


func _refresh_hud() -> void:
	var plap: int = mini(int(_player["lap"]), LAPS_TO_WIN)
	_hud_label.text = "YOU  Lap %d/%d\nTime %s\nBest %s" % [plap, LAPS_TO_WIN,
			_fmt_time(_race_time), _fmt_time(float(_player["best"]))]
	var alap: int = mini(int(_ai["lap"]), LAPS_TO_WIN)
	_ai_label.text = "AI  Lap %d/%d\nTime %s\nBest %s" % [alap, LAPS_TO_WIN,
			_fmt_time(_race_time), _fmt_time(float(_ai["best"]))]
	if _phase == 2:
		_msg_label.text = "%s\nYou: %s   AI: %s\nClick or R to race again" % [
				_winner, _fmt_time(float(_player["finish_time"])),
				_fmt_time(float(_ai["finish_time"]))]


func _reset_race() -> void:
	_phase = 0
	_countdown = 2.5
	_race_time = 0.0
	_winner = ""
	for car in [_player, _ai]:
		car["angle"] = 0.0
		car["lat"] = 0.0
		car["lap"] = 1
		car["lap_start"] = 0.0
		car["best"] = -1.0
		car["finished"] = false
		car["finish_time"] = 0.0
		_place_car(car)
	_refresh_hud()
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.save_anchor("room-racer_main", global_transform)


func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active():
			ARUpgradeKit.save_anchor("room-racer_main", global_transform)
