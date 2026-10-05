## star_map.gd - AR planetarium projected on the ceiling.
## Inverted sky dome with ~200 emissive stars on the upper hemisphere,
## 3 constellations (Orion, Big Dipper, Cassiopeia) with toggleable lines,
## 5 demo planets with name labels. Click a star/planet for a fact.
extends Node3D
class_name StarMapGame

const SKY_R := 19.0
const STAR_COUNT := 180
const PLANETS := [
	{"name": "Mercury", "color": Color(0.7, 0.65, 0.6), "fact": "Closest to the Sun; a year is only 88 days."},
	{"name": "Venus", "color": Color(0.95, 0.85, 0.6), "fact": "Hottest planet: thick CO2 atmosphere, ~465 C."},
	{"name": "Earth", "color": Color(0.3, 0.5, 1.0), "fact": "Home. The only known world with life."},
	{"name": "Mars", "color": Color(0.9, 0.35, 0.2), "fact": "The Red Planet; hosts Olympus Mons, the tallest volcano."},
	{"name": "Jupiter", "color": Color(0.9, 0.7, 0.5), "fact": "Largest planet; the Great Red Spot is a giant storm."},
]
const CONSTELLATIONS := [
	{
		"name": "Orion",
		"stars": [
			["Betelgeuse", Vector3(-3.0, 14.0, -12.0), "Red supergiant; one of the largest known stars."],
			["Bellatrix", Vector3(3.0, 13.5, -12.0), "Blue giant, the Hunter's left shoulder."],
			["Alnitak", Vector3(-1.2, 10.6, -13.0), "Eastern star of Orion's Belt."],
			["Alnilam", Vector3(0.0, 11.0, -13.0), "Center of Orion's Belt; a blue supergiant."],
			["Mintaka", Vector3(1.2, 11.4, -13.0), "Western star of Orion's Belt."],
			["Saiph", Vector3(-2.5, 8.2, -12.5), "The Hunter's right knee."],
			["Rigel", Vector3(2.5, 8.0, -12.5), "Blue-white supergiant; Orion's brightest star."],
		],
		"lines": [[0, 2], [1, 4], [2, 3], [3, 4], [2, 5], [4, 6]],
	},
	{
		"name": "Big Dipper",
		"stars": [
			["Dubhe", Vector3(14.0, 12.0, -8.0), "Front of the bowl; points toward Polaris."],
			["Merak", Vector3(14.5, 9.5, -8.5), "The other 'pointer star' to Polaris."],
			["Phecda", Vector3(11.5, 9.0, -9.5), "Bottom of the bowl."],
			["Megrez", Vector3(10.5, 11.0, -9.5), "Joins bowl to handle; faintest dipper star."],
			["Alioth", Vector3(7.5, 12.0, -9.0), "Brightest star of Ursa Major."],
			["Mizar", Vector3(4.8, 12.6, -8.6), "Famous double star with Alcor."],
			["Alkaid", Vector3(2.2, 13.2, -8.2), "Tip of the handle."],
		],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5], [5, 6]],
	},
	{
		"name": "Cassiopeia",
		"stars": [
			["Caph", Vector3(-13.0, 11.0, -6.0), "White star at the right tip of the W."],
			["Schedar", Vector3(-10.5, 13.5, -6.5), "Orange giant; the Queen's breast."],
			["Gamma Cas", Vector3(-8.0, 11.5, -7.0), "Variable blue star at the W's center."],
			["Ruchbah", Vector3(-5.5, 13.8, -7.5), "Eclipsing binary in the W."],
			["Segin", Vector3(-3.0, 11.8, -8.0), "Left tip of the W."],
		],
		"lines": [[0, 1], [1, 2], [2, 3], [3, 4]],
	},
]

var _cam: Camera3D = null
var _sky: Node3D = null
var _line_nodes: Array[MeshInstance3D] = []
var _lines_visible := true
var _star_points: Array = [] ## {pos: Vector3, radius: float, name: String, fact: String}
var _planet_points: Array = [] ## {pos: Vector3, radius: float, name: String, fact: String}
var _info: Label3D = null
var _toggle_collider: StaticBody3D = null
var _toggle_label: Label3D = null
var _rng := RandomNumberGenerator.new()
var _anchor_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	_ensure_camera()
	_build_light()
	_sky = Node3D.new()
	_sky.name = "Sky"
	add_child(_sky)
	_build_dome()
	_build_background_stars()
	_build_constellations()
	_build_planets()
	_build_toggle_button()
	_build_hud()
	# AR: restore the saved anchor for the sky in XR; drifting cosmic dust.
	if ARUpgradeKit.is_xr_active():
		ARUpgradeKit.apply_anchor(_sky, "star-map_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 6.0, 0), 8.0, 60)


func _process(delta: float) -> void:
	if _sky != null:
		_sky.rotation.y += 0.02 * delta
	_update_anchor_timer(delta)
	# XR pinch selects stars/planets via the pointer ray (mouse keeps working).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		var pr := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		_pick_at(pr[0], pr[1])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)


func _pinch_active() -> bool:
	# Hand-tracking hook: right-hand pinch, XR only (desktop keeps mouse).
	return ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


# ---------------------------------------------------------------- build

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 2.2, 4.0)
	_cam.rotation_degrees = Vector3(-35, 0, 0)


func _add_polish_light_rig() -> void:
	# Three-point light rig, but only when the scene has no key light yet.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_light() -> void:
	_add_polish_light_rig()
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.45)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)


func _build_dome() -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SKY_R + 1.0
	sm.height = (SKY_R + 1.0) * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	dome.mesh = sm
	var mat := GraphicsPolish.pbr(Color(0.02, 0.03, 0.09), 0.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT ## inside visible
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dome.material_override = mat
	_sky.add_child(dome)


func _star_material(tint: Color) -> StandardMaterial3D:
	return GraphicsPolish.glow(tint, 1.6)


func _add_star(pos: Vector3, radius: float, tint: Color, star_name: String, fact: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _star_material(tint)
	mi.position = pos
	_sky.add_child(mi)
	_star_points.append({"pos": pos, "radius": radius, "name": star_name, "fact": fact})


func _build_background_stars() -> void:
	var tints := [Color.WHITE, Color(1.0, 0.95, 0.8), Color(0.8, 0.9, 1.0)]
	for i in STAR_COUNT:
		var theta := _rng.randf_range(0.0, TAU)
		var phi := _rng.randf_range(0.05, PI * 0.48) ## upper hemisphere
		var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
		var pos := dir * SKY_R
		var r := _rng.randf_range(0.06, 0.16)
		_add_star(pos, r, tints[i % 3], "Star #%d" % (1000 + i),
			"A distant sun, roughly %d light years away." % _rng.randi_range(4, 9000))


func _build_constellations() -> void:
	for con in CONSTELLATIONS:
		var pts: Array = []
		for s in con["stars"]:
			var pos: Vector3 = (s[1] as Vector3).normalized() * SKY_R
			pts.append(pos)
			_add_star(pos, 0.22, Color(1.0, 1.0, 0.95), s[0], s[2])
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for seg in con["lines"]:
			var a: Vector3 = pts[seg[0]]
			var b: Vector3 = pts[seg[1]]
			im.surface_add_vertex(a)
			im.surface_add_vertex(b)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = GraphicsPolish.glow(Color(0.3, 1.0, 1.0), 1.2)
		_sky.add_child(mi)
		_line_nodes.append(mi)


func _build_planets() -> void:
	var i := 0
	for p in PLANETS:
		var angle := -0.9 + i * 0.45
		var pos := Vector3(sin(angle) * 7.0, 2.6 + i * 0.35, -cos(angle) * 7.0 - 2.0)
		var r := 0.35 + i * 0.08
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		mi.mesh = sm
		var pc: Color = p["color"]
		var mat := GraphicsPolish.pbr(pc, 0.1, 0.6)
		mat.emission_enabled = true
		mat.emission = pc * 0.35
		mi.material_override = mat
		mi.position = pos
		add_child(mi) ## planets stay fixed; not part of rotating sky
		var label := Label3D.new()
		label.text = p["name"]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = pos + Vector3(0, r + 0.35, 0)
		label.pixel_size = 0.008
		label.outline_size = 6
		add_child(label)
		_planet_points.append({"pos": pos, "radius": r, "name": p["name"], "fact": p["fact"]})
		i += 1


func _build_toggle_button() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0.6, 3.2)
	if ARUpgradeKit.is_xr_active():
		root.position = ARUpgradeKit.clamp_to_room(root.position)
	add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.55, 0.2)
	mi.mesh = bm
	var mat := GraphicsPolish.pbr(Color(0.15, 0.7, 0.8), 0.2, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.7, 0.8) * 0.4
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 0.55, 0.2)
	cs.shape = bs
	sb.add_child(cs)
	_toggle_collider = sb
	_toggle_label = Label3D.new()
	_toggle_label.position = Vector3(0, 0, 0.15)
	_toggle_label.pixel_size = 0.01
	_toggle_label.outline_size = 8
	root.add_child(_toggle_label)
	_update_toggle_label()


func _build_hud() -> void:
	_info = GraphicsPolish.make_label("Click a star or planet for info", 56)
	_info.position = Vector3(0, 4.4, 2.6)
	_info.pixel_size = 0.01
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.width = 500.0
	add_child(_info)
	var help := Label3D.new()
	help.text = "Sky rotates slowly  |  Toggle hides constellation lines"
	help.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	help.position = Vector3(0, 0.1, 3.2)
	help.pixel_size = 0.008
	help.modulate = Color(0.75, 0.85, 1.0)
	add_child(help)


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	_pick_at(from, dir)


func _update_anchor_timer(delta: float) -> void:
	# Persist the room anchor every 30s while in XR (desktop: no-op).
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if ARUpgradeKit.is_xr_active() and _sky != null:
			ARUpgradeKit.save_anchor("star-map_main", _sky.global_transform)


func _pick_at(from: Vector3, dir: Vector3) -> void:
	## Toggle button first (physics pick).
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.get("collider") == _toggle_collider:
		_lines_visible = not _lines_visible
		for ln in _line_nodes:
			ln.visible = _lines_visible
		_update_toggle_label()
		return
	## Analytic ray-sphere pick for planets, then stars.
	var best_name := ""
	var best_fact := ""
	var best_t := INF
	for p in _planet_points:
		var t := _ray_sphere_t(from, dir, p["pos"], float(p["radius"]) * 1.6)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_name = p["name"]
			best_fact = p["fact"]
	if best_name.is_empty():
		for s in _star_points:
			## Account for sky rotation: star positions live under _sky.
			var wp: Vector3 = _sky.to_global(s["pos"])
			var t := _ray_sphere_t(from, dir, wp, float(s["radius"]) * 2.5)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_name = s["name"]
				best_fact = s["fact"]
	if not best_name.is_empty():
		_info.text = "%s\n%s" % [best_name, best_fact]


func _ray_sphere_t(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc := center - origin
	var t := oc.dot(dir)
	if t < 0.0:
		return -1.0
	var d2 := oc.length_squared() - t * t
	if d2 > radius * radius:
		return -1.0
	return t


func _update_toggle_label() -> void:
	if _toggle_label != null:
		_toggle_label.text = "Lines: ON" if _lines_visible else "Lines: OFF"
