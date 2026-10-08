## sky_traffic.gd - Realtime AR airplane viewer.
## Polls the free adsb.lol API every 15s and places live aircraft on a
## sky dome at their true bearing / distance / altitude. Features:
## glow path trails (last 10 positions), callsign labels for the 8 nearest,
## pinch-select info cards, face-north calibration, 4 city presets,
## day/night dome toggle, offline-tolerant polling.
extends Node3D
class_name SkyTrafficGame

const POLL_INTERVAL := 15.0
const API_URL := "https://api.adsb.lol/v2/point/%f/%f/60"
const DOME_RADIUS := 40.0
const KM_TO_M := 2.0 ## 1 km of real distance = 2 m on the dome
const MAX_DOME_R := 38.0
const CONFIG_FILE := "user://nexus_config.cfg"
const TRAIL_POINTS := 10
const LABEL_COUNT := 8

const CITIES := [
	{"name": "San Diego", "lat": 32.7157, "lon": -117.1611},
	{"name": "Los Angeles", "lat": 34.0522, "lon": -118.2437},
	{"name": "New York", "lat": 40.7128, "lon": -74.0060},
	{"name": "London", "lat": 51.5074, "lon": -0.1278},
]

var _cam: Camera3D = null
var _http: HTTPRequest = null
var _dome: Node3D = null ## rotated by calibration so local -Z = north
var _dome_mesh: MeshInstance3D = null
var _stars: GPUParticles3D = null
var _hud: Label3D = null
var _status: Label3D = null
var _calib_prompt: Label3D = null
var _info_card: Label3D = null
var _info_bg: MeshInstance3D = null
var _buttons := {} ## StaticBody3D -> String action
var _city := 0
var _lat := 32.7157
var _lon := -117.1611
var _calibrated := false
var _heading_offset := 0.0
var _night := true
var _poll_timer := 0.0
var _poll_inflight := false
var _aircraft := {} ## hex -> Dictionary record
var _selected_hex := ""
var _missed := {} ## hex -> missed poll count
# v0.9.1: engine-roar-by-distance (the deferred v0.9.0 wow) — the nearest
# plane rumbles on a looping 3D player, volume/pitch mapped to real distance.
const ROAR_MAX_KM := 20.0
var _roar_player: AudioStreamPlayer3D = null
# v0.7.0 ROOMKIT: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _has_room := false


func _ready() -> void:
	_load_config()
	_ensure_camera()
	_build_light()
	_build_dome()
	_build_ui()
	_build_hud()
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_poll_done)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 6.0, 0), 12.0, 30)
	_build_roar()
	_update_status("Connecting to sky data...")
	_poll() ## first poll immediately
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
	# MORPH-B (v0.7.0): windows -> air-traffic observation windows
	_morph_anchors("WINDOW", "scifi", 2)
	_has_room = true
	# ROOMKIT: center the sky dome on the real room's floor center so the
	# viewing area is framed on the play space, not a fixed origin.
	var c := _room_bounds.get_center()
	_dome.position = Vector3(c.x, 0.0, c.y)
	_build_room_frame(c)


## Thin glowing rectangle on the floor marking the room's real bounds.
func _build_room_frame(center: Vector2) -> void:
	var frame := Node3D.new()
	frame.name = "RoomFrame"
	add_child(frame)
	var w := _room_bounds.size.x
	var d := _room_bounds.size.y
	var mat := GraphicsPolish.glow(Color(0.3, 0.8, 1.0), 1.2)
	for seg in [
		[Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5)],
		[Vector3(w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, d * 0.5)],
		[Vector3(w * 0.5, 0, d * 0.5), Vector3(-w * 0.5, 0, d * 0.5)],
		[Vector3(-w * 0.5, 0, d * 0.5), Vector3(-w * 0.5, 0, -d * 0.5)],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var length: float = (seg[0] as Vector3).distance_to(seg[1])
		bm.size = Vector3(0.04, 0.02, maxf(length, 0.01))
		mi.mesh = bm
		mi.material_override = mat
		mi.position = ((seg[0] as Vector3) + (seg[1] as Vector3)) * 0.5
		var dir3: Vector3 = (seg[1] as Vector3) - (seg[0] as Vector3)
		mi.rotation.y = atan2(dir3.x, dir3.z)
		frame.add_child(mi)
	frame.position = Vector3(center.x, 0.03, center.y)


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL and not _poll_inflight:
		_poll_timer = 0.0
		_poll()
	# Smoothly glide markers toward their targets between polls.
	for hex in _aircraft.keys():
		var rec: Dictionary = _aircraft[hex]
		var node: Node3D = rec["node"]
		if is_instance_valid(node):
			node.position = node.position.lerp(rec["target"], minf(1.0, delta * 2.0))
	# Pinch interactions (XR-gated inside the kit; mouse handled below).
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if pinched and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_on_pinch()
	_update_roar()


## v0.9.1: looping engine-roar player. The stream is duplicated so the
## loop points don't leak into AudioKit's shared one-shot pool voice.
func _build_roar() -> void:
	var src := load("res://assets/audio/sfx/engine_roar.wav") as AudioStreamWAV
	if src == null:
		return
	var stream := src.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_roar_player = AudioStreamPlayer3D.new()
	_roar_player.stream = stream
	_roar_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_roar_player.max_distance = 60.0
	add_child(_roar_player)


## v0.9.1: point the roar at the nearest aircraft; volume and pitch follow
## its real distance. Silent when the sky is empty or everything is far.
func _update_roar() -> void:
	if _roar_player == null:
		return
	var best: Dictionary = {}
	var best_d := ROAR_MAX_KM
	for hex in _aircraft.keys():
		var rec: Dictionary = _aircraft[hex]
		var d := float(rec.get("dist", 999.0))
		if d < best_d:
			best_d = d
			best = rec
	if best.is_empty():
		if _roar_player.playing:
			_roar_player.stop()
		return
	var node: Node3D = best.get("node")
	if node == null or not is_instance_valid(node):
		return
	_roar_player.global_position = node.global_position
	var t := clampf(best_d / ROAR_MAX_KM, 0.0, 1.0)
	_roar_player.volume_db = lerpf(-8.0, -30.0, t)
	_roar_player.pitch_scale = lerpf(0.92, 1.06, t)
	if not _roar_player.playing:
		_roar_player.play()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_H:
			get_tree().reload_current_scene()


# ---------------------------------------------------------------- setup

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 1.6, 0)


func _build_light() -> void:
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		var key := GraphicsPolish.make_light_rig(self, 0.7)
		key.shadow_enabled = false
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.55)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	amb.environment = env
	add_child(amb)


func _build_dome() -> void:
	_dome = Node3D.new()
	_dome.name = "SkyDome"
	add_child(_dome)
	_dome.rotation.y = _heading_offset
	# Gradient sky shell (inverted sphere, unshaded).
	_dome_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = DOME_RADIUS
	sph.height = DOME_RADIUS * 2.0
	sph.radial_segments = 32
	sph.rings = 16
	_dome_mesh.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT ## see inside
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.02, 0.07, 0.92))
	grad.set_color(1, Color(0.05, 0.08, 0.22, 0.55))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 1.0)
	gtex.fill_to = Vector2(0.5, 0.0)
	mat.albedo_texture = gtex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_mesh.material_override = mat
	_dome.add_child(_dome_mesh)
	# Star field (night mode).
	_stars = GPUParticles3D.new()
	_stars.amount = 220
	_stars.lifetime = 100000.0
	_stars.preprocess = 100000.0
	_stars.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = DOME_RADIUS * 0.92
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.06
	pm.scale_max = 0.16
	pm.color = Color(1, 1, 1, 0.9)
	_stars.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1, 1, 1)
	smat.emission_enabled = true
	smat.emission = Color(1, 1, 1)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_stars.draw_pass_1 = quad
	_stars.material_override = smat
	_dome.add_child(_stars)
	_apply_night()


func _apply_night() -> void:
	_dome_mesh.visible = _night
	_stars.visible = _night


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# City preset buttons along the bottom.
	var x := -3.3
	for i in CITIES.size():
		_make_button("city_%d" % i, CITIES[i]["name"], Vector3(x, 0.9, -2.6), Color(0.2, 0.5, 0.9))
		x += 2.2
	_make_button("recal", "Recalibrate N", Vector3(-3.3, 0.25, -2.6), Color(0.9, 0.6, 0.2))
	_make_button("night", "Day/Night", Vector3(-1.1, 0.25, -2.6), Color(0.3, 0.3, 0.7))
	_make_button("hub", "Back to Hub", Vector3(3.3, 0.25, -2.6), Color(0.7, 0.3, 0.3))
	# Calibration prompt (center, big).
	_calib_prompt = GraphicsPolish.make_label("Face NORTH, then PINCH to calibrate", 56, Color(1.0, 0.9, 0.4))
	_calib_prompt.position = Vector3(0, 2.6, -3.0)
	_calib_prompt.pixel_size = 0.012
	add_child(_calib_prompt)
	_calib_prompt.visible = not _calibrated
	# Info card (hidden until a plane is selected).
	_info_bg = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 1.1, 0.06)
	_info_bg.mesh = bm
	_info_bg.material_override = GraphicsPolish.pbr_preset(Color(0.05, 0.08, 0.16), "plastic")
	_info_bg.position = Vector3(2.6, 2.2, -2.8)
	add_child(_info_bg)
	_info_card = GraphicsPolish.make_label("", 40, Color(0.85, 0.95, 1.0))
	_info_card.position = Vector3(2.6, 2.2, -2.76)
	_info_card.pixel_size = 0.008
	add_child(_info_card)
	_info_bg.visible = false
	_info_card.visible = false


func _make_button(action: String, text: String, pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 0.5, 0.12)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr_preset(color, "plastic")
	mat.emission_enabled = true
	mat.emission = color * 0.45
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 0.5, 0.12)
	cs.shape = bs
	sb.add_child(cs)
	var label := GraphicsPolish.make_label(text, 44, Color.WHITE)
	label.position = Vector3(0, 0, 0.08)
	label.pixel_size = 0.009
	root.add_child(label)
	_buttons[sb] = action


func _build_hud() -> void:
	_hud = GraphicsPolish.make_label("SKY TRAFFIC", 52, Color(0.5, 0.9, 1.0))
	_hud.position = Vector3(0, 3.4, -2.8)
	_hud.pixel_size = 0.011
	add_child(_hud)
	_status = GraphicsPolish.make_label("", 40, Color(0.8, 0.85, 1.0))
	_status.position = Vector3(0, 3.0, -2.8)
	_status.pixel_size = 0.008
	add_child(_status)
	var help := GraphicsPolish.make_label("Look at the sky — planes appear where they really are | Pinch a plane for details", 36, Color(0.7, 0.75, 0.9))
	help.position = Vector3(0, 1.55, -2.8)
	help.pixel_size = 0.007
	add_child(help)


func _update_status(text: String) -> void:
	if _status:
		_status.text = text


# ---------------------------------------------------------------- data

func _poll() -> void:
	if _poll_inflight or _http == null:
		return
	_poll_inflight = true
	var url := API_URL % [_lat, _lon]
	var err := _http.request(url)
	if err != OK:
		_poll_inflight = false
		_update_status("Network error — retrying...")


func _on_poll_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_poll_inflight = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_update_status("Waiting for sky data... (retrying)")
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not (json is Dictionary):
		_update_status("Bad sky data — retrying")
		return
	var list: Array = (json as Dictionary).get("ac", [])
	_ingest(list)


func _ingest(list: Array) -> void:
	var seen := {}
	var count := 0
	for a in list:
		if not (a is Dictionary):
			continue
		var d: Dictionary = a
		if d.get("lat") == null or d.get("lon") == null:
			continue ## MLAT-incomplete, skip
		var hex: String = str(d.get("hex", ""))
		if hex == "":
			continue
		seen[hex] = true
		_missed.erase(hex)
		count += 1
		var pos := _geo_to_dome(float(d["lat"]), float(d["lon"]), float(d.get("alt_baro", 0.0)))
		if _aircraft.has(hex):
			var rec: Dictionary = _aircraft[hex]
			rec["target"] = pos
			rec["data"] = d
			rec["dist"] = _dist_nm(float(d["lat"]), float(d["lon"]))
			_push_trail(rec, pos)
			_refresh_marker(rec)
		else:
			_aircraft[hex] = _spawn_aircraft(d, pos)
	# Drop aircraft that vanished from the feed (2 missed polls).
	for hex in _aircraft.keys():
		if not seen.has(hex):
			_missed[hex] = int(_missed.get(hex, 0)) + 1
			if _missed[hex] >= 2:
				_despawn(hex)
	_update_labels()
	_update_status("%d aircraft overhead · %s" % [count, CITIES[_city]["name"]])


func _bearing_to(lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(_lat)
	var p2 := deg_to_rad(lat2)
	var dl := deg_to_rad(lon2 - _lon)
	var y := sin(dl) * cos(p2)
	var x := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return rad_to_deg(atan2(y, x)) ## -180..180, 0 = north


func _dist_nm(lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(_lat)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - _lat)
	var dl := deg_to_rad(lon2 - _lon)
	var h := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return 2.0 * 3440.065 * asin(sqrt(h)) ## nautical miles


func _geo_to_dome(lat2: float, lon2: float, alt_ft: float) -> Vector3:
	var bearing := deg_to_rad(_bearing_to(lat2, lon2))
	var dist_m := _dist_nm(lat2, lon2) * 1852.0 * KM_TO_M / 1000.0
	var r := minf(dist_m, MAX_DOME_R)
	var h := clampf(alt_ft * 0.001, 2.0, 35.0)
	# Local -Z = north (dome is rotated by calibration offset).
	return Vector3(sin(bearing) * r, h, -cos(bearing) * r)


func _alt_color(alt_ft: float) -> Color:
	if alt_ft < 5000.0:
		return Color(0.3, 1.0, 0.4) ## low / approach
	if alt_ft < 15000.0:
		return Color(0.3, 0.9, 1.0) ## mid
	if alt_ft < 30000.0:
		return Color(1.0, 0.7, 0.2) ## high
	return Color(1.0, 0.35, 0.75) ## very high


# ---------------------------------------------------------------- markers

func _spawn_aircraft(d: Dictionary, pos: Vector3) -> Dictionary:
	var alt := float(d.get("alt_baro", 0.0))
	var color := _alt_color(alt)
	var root := Node3D.new()
	_dome.add_child(root)
	root.position = pos
	# Stylized plane: fuselage + wings + tail, glow material.
	var mat := GraphicsPolish.glow(color, 1.6)
	var body := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.28, 0.22, 1.1)
	body.mesh = fb
	body.material_override = mat
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.14
	sp.height = 0.28
	nose.mesh = sp
	nose.material_override = mat
	nose.position = Vector3(0, 0, -0.6)
	root.add_child(nose)
	var wing := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(1.7, 0.07, 0.4)
	wing.mesh = wb
	wing.material_override = mat
	wing.position = Vector3(0, 0.02, -0.1)
	root.add_child(wing)
	var tail := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.07, 0.42, 0.3)
	tail.mesh = tb
	tail.material_override = mat
	tail.position = Vector3(0, 0.22, 0.5)
	root.add_child(tail)
	# Halo for long-range visibility.
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.35
	hs.height = 0.7
	halo.mesh = hs
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(color.r, color.g, color.b, 0.28)
	halo.material_override = hmat
	root.add_child(halo)
	# Clickable body.
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.8
	cs.shape = ss
	sb.add_child(cs)
	sb.set_meta("hex", str(d.get("hex", "")))
	# Heading orientation.
	var track := float(d.get("track", 0.0))
	root.rotation.y = -deg_to_rad(track)
	var label := GraphicsPolish.make_label("", 44, Color.WHITE)
	label.pixel_size = 0.011
	label.position = Vector3(0, 0.75, 0)
	root.add_child(label)
	# Path trail (line strip through last positions).
	var trail_root := MeshInstance3D.new()
	_dome.add_child(trail_root)
	var rec := {
		"node": root, "body": sb, "label": label, "halo": halo, "mat": mat,
		"trail": trail_root, "points": [pos] as Array, "target": pos,
		"data": d, "dist": _dist_nm(float(d["lat"]), float(d["lon"])),
		"color": color,
	}
	_refresh_marker(rec)
	return rec


func _refresh_marker(rec: Dictionary) -> void:
	var d: Dictionary = rec["data"]
	var node: Node3D = rec["node"]
	var track := float(d.get("track", 0.0))
	node.rotation.y = -deg_to_rad(track)
	var new_color := _alt_color(float(d.get("alt_baro", 0.0)))
	rec["color"] = new_color
	# Recolor the glow material shared by all plane parts.
	var m := rec["mat"] as StandardMaterial3D
	if m != null:
		m.albedo_color = new_color
		m.emission = new_color * 1.6


func _push_trail(rec: Dictionary, pos: Vector3) -> void:
	var pts: Array = rec["points"]
	pts.append(pos)
	while pts.size() > TRAIL_POINTS:
		pts.pop_front()
	rec["points"] = pts
	_draw_trail(rec)


func _draw_trail(rec: Dictionary) -> void:
	var pts: Array = rec["points"]
	var mesh_inst: MeshInstance3D = rec["trail"]
	if pts.size() < 2:
		mesh_inst.mesh = null
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = rec["color"]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in pts.size():
		var fade := float(i + 1) / float(pts.size())
		var c: Color = rec["color"]
		im.surface_set_color(Color(c.r, c.g, c.b, 0.15 + 0.75 * fade))
		im.surface_add_vertex(pts[i])
	im.surface_end()
	mesh_inst.mesh = im


func _despawn(hex: String) -> void:
	if _selected_hex == hex:
		_deselect()
	var rec: Dictionary = _aircraft[hex]
	var node: Node3D = rec["node"]
	if is_instance_valid(node):
		node.queue_free()
	var trail: MeshInstance3D = rec["trail"]
	if is_instance_valid(trail):
		trail.queue_free()
	_aircraft.erase(hex)
	_missed.erase(hex)


func _update_labels() -> void:
	# Labels only for the LABEL_COUNT nearest aircraft.
	var keys := _aircraft.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float((_aircraft[a] as Dictionary)["dist"]) < float((_aircraft[b] as Dictionary)["dist"]))
	var shown := 0
	for hex in keys:
		var rec: Dictionary = _aircraft[hex]
		var label: Label3D = rec["label"]
		if shown < LABEL_COUNT:
			var d: Dictionary = rec["data"]
			var cs: String = str(d.get("flight", "")).strip_edges()
			if cs == "":
				cs = str(d.get("hex", ""))
			label.text = "%s\n%d ft · %d kt" % [cs, int(float(d.get("alt_baro", 0.0))), int(float(d.get("gs", 0.0)))]
			label.visible = true
			shown += 1
		else:
			label.visible = false


# ---------------------------------------------------------------- input

func _on_pinch() -> void:
	if not _calibrated:
		_calibrate()
		return
	var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	if ray.size() < 2:
		return
	_cast_select(ray[0], ray[1])


func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	if not _calibrated:
		_calibrate()
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	_cast_select(from, dir)


func _cast_select(from: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_deselect()
		return
	var collider: Object = hit.get("collider")
	if collider is StaticBody3D:
		var sb := collider as StaticBody3D
		if _buttons.has(sb):
			_do_action(str(_buttons[sb]))
			return
		if sb.has_meta("hex"):
			_select(str(sb.get_meta("hex")))
			return
	_deselect()


func _do_action(action: String) -> void:
	if action.begins_with("city_"):
		var i := int(action.get_slice("_", 1))
		if i >= 0 and i < CITIES.size():
			_city = i
			_lat = float(CITIES[i]["lat"])
			_lon = float(CITIES[i]["lon"])
			_clear_aircraft()
			_save_config()
			_update_status("Switching to %s..." % CITIES[i]["name"])
			_poll_timer = 0.0
			_poll()
	elif action == "recal":
		_calibrated = false
		_calib_prompt.visible = true
		_update_status("Face NORTH, then pinch to calibrate")
	elif action == "night":
		_night = not _night
		_apply_night()
	elif action == "hub":
		get_tree().reload_current_scene()


func _select(hex: String) -> void:
	if not _aircraft.has(hex):
		return
	_selected_hex = hex
	var rec: Dictionary = _aircraft[hex]
	var d: Dictionary = rec["data"]
	var cs: String = str(d.get("flight", "")).strip_edges()
	if cs == "":
		cs = "—"
	_info_card.text = "%s\nType %s · Reg %s\nAlt %d ft · %d kt\nHdg %d° · %.1f NM" % [
		cs, str(d.get("t", "—")), str(d.get("r", "—")),
		int(float(d.get("alt_baro", 0.0))), int(float(d.get("gs", 0.0))),
		int(float(d.get("track", 0.0))), float(rec["dist"]),
	]
	_info_card.visible = true
	_info_bg.visible = true
	GraphicsPolish.spawn_sparks(self, (rec["node"] as Node3D).global_position, Color(0.5, 0.9, 1.0), 12)


func _deselect() -> void:
	_selected_hex = ""
	_info_card.visible = false
	_info_bg.visible = false


func _clear_aircraft() -> void:
	_deselect()
	for hex in _aircraft.keys():
		var rec: Dictionary = _aircraft[hex]
		var node: Node3D = rec["node"]
		if is_instance_valid(node):
			node.queue_free()
		var trail: MeshInstance3D = rec["trail"]
		if is_instance_valid(trail):
			trail.queue_free()
	_aircraft.clear()
	_missed.clear()


# ---------------------------------------------------------------- calibration & config

func _calibrate() -> void:
	# Quest has no compass: the user faces north, we take the camera yaw
	# as the north reference and rotate the dome so local -Z = north.
	var yaw := 0.0
	if _cam != null:
		yaw = _cam.global_rotation.y
	_heading_offset = yaw
	_dome.rotation.y = _heading_offset
	_calibrated = true
	_calib_prompt.visible = false
	_save_config()
	_update_status("Calibrated ✓ — %d aircraft overhead" % _aircraft.size())
	GraphicsPolish.spawn_confetti(self, Vector3(0, 2.5, -2.0), 40)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_FILE) == OK:
		_heading_offset = float(cfg.get_value("sky_traffic", "heading_offset", 0.0))
		_calibrated = bool(cfg.get_value("sky_traffic", "calibrated", false))
		_city = int(cfg.get_value("sky_traffic", "city", 0))
		_city = clampi(_city, 0, CITIES.size() - 1)
		_lat = float(CITIES[_city]["lat"])
		_lon = float(CITIES[_city]["lon"])
		_night = bool(cfg.get_value("sky_traffic", "night", true))


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_FILE) ## keep other sections
	cfg.set_value("sky_traffic", "heading_offset", _heading_offset)
	cfg.set_value("sky_traffic", "calibrated", _calibrated)
	cfg.set_value("sky_traffic", "city", _city)
	cfg.set_value("sky_traffic", "night", _night)
	cfg.save(CONFIG_FILE)
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
