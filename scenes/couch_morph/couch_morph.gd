extends Node3D
## Couch Morph — NEXUS ARCADE v0.7.0 showcase experience.
##
## Wraps the player's real couch (RoomKit cuboid anchor) in one of three
## selectable "aura" skins — Spaceship Bridge, Lava Island, Pirate Ship —
## plus the "Couch Defense" mini-game (zap incoming attackers with the
## controller ray or mouse).
##
## HONEST LIMITATION (designed around, not hidden): passthrough still shows
## the real couch underneath. Skins are translucent shells + themed props +
## particles + lights arranged around the cuboid anchor, so the couch reads
## as transformed without re-rendering it.
##
## Self-contained: all visuals built in code, own input handling (controller
## ray + desktop mouse fallback), guarded RoomKit reads only, virtual couch
## pedestal when no room data. Quest-friendly: no shadow casting on props,
## modest particle counts, unshaded emissive materials where possible.
##
## Headless/test hooks (used by the automated test, harmless in game):
##   _apply_couch(cuboid), _apply_skin(name), _spawn_attacker(),
##   _kill_attacker(area, at), _on_attacker_reached(area), _reset_game().

const FALLBACK_COUCH_POS := Vector3(0.0, 0.45, -1.6)
const FALLBACK_COUCH_SIZE := Vector3(2.0, 0.9, 0.9)
const PICK_MASK := 2
const RAY_LEN := 4.0
const LASER_LEN := 3.0
const TRIGGER_EDGE := 0.7
const ATTACKER_SPEED := 0.8
const ATTACKER_RADIUS := 0.12
const HIT_DIST := 0.6
const MAX_LIVES := 3
const KILLS_PER_WAVE := 8
const SPAWN_BASE := 2.2
const SPAWN_MIN := 0.7
const SPAWN_STEP := 0.15
const MAX_ATTACKERS := 24
const SKIN_NAMES := ["spaceship", "lava", "pirate"]
const SKIN_TITLES := {"spaceship": "Spaceship", "lava": "Lava Island", "pirate": "Pirate Ship"}
const SKIN_COLORS := {
	"spaceship": Color(0.25, 0.5, 1.0),
	"lava": Color(1.0, 0.35, 0.08),
	"pirate": Color(0.55, 0.38, 0.2),
}

var _couch: Dictionary = {}
var _couch_center := Vector3.ZERO
var _couch_size := Vector3.ONE
var _walls: Array = []
var _setup_done := false

var _couch_root: Node3D
var _skins_root: Node3D
var _skins: Dictionary = {}
var _active_skin := ""
var _shell_mat: StandardMaterial3D = null
var _shell_base_emission := Color.BLACK
var _nav_lights: Array = []
var _skin_buttons: Dictionary = {}

var _attackers_root: Node3D
var _attackers: Array = []
var _score := 0
var _lives := MAX_LIVES
var _kills := 0
var _wave := 1
var _game_active := false
var _spawn_timer := 0.0

var _hud_root: Node3D
var _score_label: Label3D
var _lives_label: Label3D
var _wave_label: Label3D
var _overlay: Node3D
var _overlay_score: Label3D

var _fx_root: Node3D
var _burst: GPUParticles3D
var _popups: Array = []
var _popup_idx := 0
var _flash_tween: Tween = null

var _sfx: AudioStreamPlayer
var _zap_stream: AudioStreamWAV
var _thump_stream: AudioStreamWAV

var _controllers: Array = []
var _rigs: Dictionary = {} # XRController3D -> {laser, dot, prev}
var _scan_cd := 0.0
var _mouse_pos := Vector2(-1, -1)
var _mouse_laser: MeshInstance3D
var _mouse_dot: MeshInstance3D


func _ready() -> void:
	_couch_root = Node3D.new()
	_couch_root.name = "CouchRoot"
	add_child(_couch_root)
	_skins_root = Node3D.new()
	_skins_root.name = "Skins"
	add_child(_skins_root)
	_attackers_root = Node3D.new()
	_attackers_root.name = "Attackers"
	add_child(_attackers_root)
	_fx_root = Node3D.new()
	_fx_root.name = "FX"
	add_child(_fx_root)
	_hud_root = Node3D.new()
	_hud_root.name = "HUD"
	add_child(_hud_root)
	_mouse_pos = get_viewport().get_visible_rect().size * 0.5
	_scan_controllers()
	_build_audio()
	_build_fx()
	_build_mouse_aim()
	await _setup_couch()
	_setup_done = true
	_reset_game()


## Guarded RoomKit query: real couch when available, virtual pedestal otherwise.
func _setup_couch() -> void:
	var couch := {}
	if RoomKit.is_available():
		await RoomKit.refresh()
		if RoomKit.has_room_data():
			couch = RoomKit.get_couch()
			_walls = RoomKit.get_walls()
	if couch.is_empty():
		_build_virtual_couch()
		_apply_couch({"position": FALLBACK_COUCH_POS, "size": FALLBACK_COUCH_SIZE})
	else:
		_apply_couch(couch)


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## (Re)build everything couch-dependent around the given cuboid.
## Also used by the headless test with a fake cuboid.
func _apply_couch(cuboid: Dictionary) -> void:
	_couch = cuboid
	_couch_center = cuboid["position"]
	_couch_size = cuboid["size"]
	_clear_children(_skins_root)
	_clear_children(_hud_root)
	_skins.clear()
	_skin_buttons.clear()
	_nav_lights.clear()
	_attackers.clear()
	for a in _attackers_root.get_children():
		_attackers_root.remove_child(a)
		a.queue_free()
	_build_skins()
	_build_skin_buttons()
	_build_hud()
	_build_overlay()
	_apply_skin("spaceship")


## Procedural stand-in couch (base + backrest + 2 arms) + setup prompt.
func _build_virtual_couch() -> void:
	var g := Node3D.new()
	g.name = "VirtualCouch"
	g.position = FALLBACK_COUCH_POS
	_couch_root.add_child(g)
	var fabric := _flat_mat(Color(0.32, 0.34, 0.42), 0.85)
	var dark := _flat_mat(Color(0.22, 0.23, 0.3), 0.9)
	# base 2.0 x 0.5 x 0.9, centered so group origin == cuboid center
	_add_box(g, Vector3(2.0, 0.5, 0.9), Vector3(0, -0.2, 0), fabric)
	# backrest
	_add_box(g, Vector3(2.0, 0.55, 0.22), Vector3(0, 0.175, -0.34), dark)
	# arms
	_add_box(g, Vector3(0.22, 0.35, 0.9), Vector3(-0.89, -0.025, 0), dark)
	_add_box(g, Vector3(0.22, 0.35, 0.9), Vector3(0.89, -0.025, 0), dark)
	# seat cushions
	_add_box(g, Vector3(0.85, 0.12, 0.62), Vector3(-0.45, 0.11, 0.05), fabric)
	_add_box(g, Vector3(0.85, 0.12, 0.62), Vector3(0.45, 0.11, 0.05), fabric)
	var prompt := _make_label(
		"No couch found — add your couch in Quest Space Setup, then reopen Couch Morph",
		32, Color(1.0, 0.95, 0.8))
	prompt.position = FALLBACK_COUCH_POS + Vector3(0, 1.35, 0)
	g.add_child(prompt)


# ------------------------------------------------------------ helpers ----

func _flat_mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _emissive_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material,
		seg := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = seg
	s.rings = maxi(2, seg / 2)
	s.material = mat
	mi.mesh = s
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.material = mat
	mi.mesh = c
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _make_label(text: String, font_size := 48, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.008
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.no_depth_test = false
	return l


## Translucent aura shell around the couch cuboid; returns the material so the
## game can flash it on hits.
func _make_shell(size: Vector3, tint: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.22)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.4
	return m


## Clickable 3D button: box + label + Area3D (pickable on PICK_MASK).
func _make_button(parent: Node3D, name: String, title: String, pos: Vector3,
		size: Vector3, color: Color) -> Area3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var mat := _emissive_mat(color.darkened(0.35), 0.6)
	b.material = mat
	mi.mesh = b
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var label := _make_label(title, 40, Color.WHITE)
	label.position = pos + Vector3(0, 0, size.z * 0.5 + 0.06)
	parent.add_child(label)
	var area := Area3D.new()
	area.name = name
	area.collision_layer = PICK_MASK
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("skin_button")
	area.set_meta("skin", name)
	area.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size * 1.6 # generous touch target
	cs.shape = shape
	area.add_child(cs)
	parent.add_child(area)
	_skin_buttons[name] = {"area": area, "mesh": mi, "mat": mat,
		"base": color.darkened(0.35)}
	return area


func _make_particles(amount: int, lifetime: float, one_shot: bool,
		draw_radius: float, color: Color, energy: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dm := SphereMesh.new()
	dm.radius = draw_radius
	dm.height = draw_radius * 2.0
	dm.radial_segments = 6
	dm.rings = 3
	dm.material = _emissive_mat(color, energy)
	p.draw_pass_1 = dm
	return p


# -------------------------------------------------------------- skins ----

func _build_skins() -> void:
	for skin_name in SKIN_NAMES:
		var g := Node3D.new()
		g.name = skin_name.capitalize().replace(" ", "")
		g.position = _couch_center
		g.visible = false
		_skins_root.add_child(g)
		_skins[skin_name] = g
		match skin_name:
			"spaceship":
				_build_spaceship(g, _couch_size)
			"lava":
				_build_lava(g, _couch_size)
			"pirate":
				_build_pirate(g, _couch_size)


func _build_spaceship(g: Node3D, s: Vector3) -> void:
	# translucent dark-blue aura shell
	var shell_mat := _make_shell(s, Color(0.1, 0.25, 0.6), Color(0.15, 0.35, 1.0), 0.9)
	_add_box(g, s + Vector3(0.15, 0.15, 0.15), Vector3.ZERO, shell_mat)
	g.set_meta("shell_mat", shell_mat)
	g.set_meta("shell_base", Color(0.15, 0.35, 1.0))
	# console panel floating in front of the couch, angled toward the player
	var console := Node3D.new()
	console.position = Vector3(0, 0.55, s.z * 0.5 + 0.5)
	console.rotation_degrees.x = -18.0
	g.add_child(console)
	_add_box(console, Vector3(0.95, 0.55, 0.09), Vector3.ZERO,
		_flat_mat(Color(0.08, 0.1, 0.16), 0.6))
	var btn_colors := [Color(0.2, 1.0, 0.4), Color(1.0, 0.25, 0.2),
		Color(1.0, 0.85, 0.2), Color(0.25, 0.8, 1.0)]
	var bi := 0
	for row in 2:
		for col in 4:
			var bx := -0.33 + col * 0.22
			var by := 0.12 - row * 0.22
			_add_box(console, Vector3(0.1, 0.06, 0.035),
				Vector3(bx, by, 0.06),
				_emissive_mat(btn_colors[bi % btn_colors.size()], 2.5))
			bi += 1
	# blinking nav lights at the shell's top corners
	var corners := [
		Vector3(-s.x / 2, s.y / 2 + 0.1, -s.z / 2),
		Vector3(s.x / 2, s.y / 2 + 0.1, -s.z / 2),
		Vector3(-s.x / 2, s.y / 2 + 0.1, s.z / 2),
		Vector3(s.x / 2, s.y / 2 + 0.1, s.z / 2),
	]
	for i in corners.size():
		var lm := _emissive_mat(Color(1.0, 0.3, 0.25), 2.0)
		var light_mi := _add_sphere(g, 0.035, corners[i], lm, 8)
		_nav_lights.append({"mesh": light_mi, "mat": lm, "phase": float(i) * PI * 0.5})
	# faint starfield drifting above
	var stars := _make_particles(70, 8.0, false, 0.012, Color(0.8, 0.9, 1.0), 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.6
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	stars.process_material = pm
	stars.position = Vector3(0, 1.7, 0)
	g.add_child(stars)


func _build_lava(g: Node3D, s: Vector3) -> void:
	# emissive orange-red aura shell
	var shell_mat := _make_shell(s, Color(0.6, 0.12, 0.02), Color(1.0, 0.3, 0.05), 1.1)
	_add_box(g, s + Vector3(0.15, 0.15, 0.15), Vector3.ZERO, shell_mat)
	g.set_meta("shell_mat", shell_mat)
	g.set_meta("shell_base", Color(1.0, 0.3, 0.05))
	var base_y := -s.y * 0.5
	var rock_mat := _flat_mat(Color(0.12, 0.1, 0.1), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# 5-7 dark rocks ringing the couch base
	var ring_r := maxf(s.x, s.z) * 0.5 + 0.35
	for i in 7:
		var ang := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var rr := ring_r + rng.randf_range(-0.15, 0.25)
		var rock_r := rng.randf_range(0.1, 0.24)
		var rock := _add_sphere(g,
			rock_r, Vector3(cos(ang) * rr, base_y + rock_r * 0.5, sin(ang) * rr),
			rock_mat, 5)
		rock.scale.y = rng.randf_range(0.6, 1.1)
		rock.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0)
	# glowing lava pools under the couch
	var pool_mat := _emissive_mat(Color(1.0, 0.32, 0.04), 2.2)
	for i in 3:
		var pang := TAU * float(i) / 3.0 + 0.5
		_add_cyl(g, rng.randf_range(0.22, 0.34), 0.02,
			Vector3(cos(pang) * 0.8, base_y + 0.011, sin(pang) * 0.7), pool_mat)
	# ember particles rising around the base
	var embers := _make_particles(40, 2.4, false, 0.025, Color(1.0, 0.45, 0.08), 2.5)
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	epm.emission_ring_axis = Vector3(0, 1, 0)
	epm.emission_ring_radius = ring_r * 0.8
	epm.emission_ring_inner_radius = ring_r * 0.3
	epm.emission_ring_height = 0.05
	epm.direction = Vector3(0, 1, 0)
	epm.spread = 12.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = 1.2
	epm.gravity = Vector3(0, 0.8, 0)
	epm.damping_min = 0.4
	epm.damping_max = 0.8
	epm.scale_min = 0.6
	epm.scale_max = 1.3
	embers.process_material = epm
	embers.position = Vector3(0, base_y + 0.05, 0)
	g.add_child(embers)
	# warm orange light above
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = 1.6
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position = Vector3(0, s.y * 0.5 + 1.0, 0)
	g.add_child(light)


func _build_pirate(g: Node3D, s: Vector3) -> void:
	var top_y := s.y * 0.5
	var wood := _flat_mat(Color(0.45, 0.3, 0.16), 0.9)
	var wood_dark := _flat_mat(Color(0.32, 0.2, 0.1), 0.9)
	# wooden deck planks laid across the couch top
	var plank_count := 6
	var deck_w := s.x + 0.25
	var deck_d := s.z + 0.1
	for i in plank_count:
		var pz := -deck_d * 0.5 + deck_d * (float(i) + 0.5) / float(plank_count)
		_add_box(g, Vector3(deck_w, 0.035, deck_d / float(plank_count) * 0.85),
			Vector3(0, top_y + 0.02, pz), wood if i % 2 == 0 else wood_dark)
	# mast + sail
	_add_cyl(g, 0.045, 2.2, Vector3(0, top_y + 1.1, 0), wood_dark)
	var sail := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 0.85)
	plane.orientation = PlaneMesh.FACE_Z
	plane.material = _flat_mat(Color(0.92, 0.88, 0.8), 0.95)
	sail.mesh = plane
	sail.position = Vector3(0, top_y + 1.55, 0.07)
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(sail)
	# railing posts around the deck edge
	var post_mat := wood_dark
	var posts_x := [-deck_w * 0.5, deck_w * 0.5]
	for px in posts_x:
		for j in 3:
			var pz2 := -deck_d * 0.5 + deck_d * (float(j) + 0.5) / 3.0
			_add_cyl(g, 0.02, 0.28, Vector3(px, top_y + 0.16, pz2), post_mat)
	for j in 2:
		var px2 := -deck_w * 0.25 + deck_w * 0.5 * float(j)
		_add_cyl(g, 0.02, 0.28, Vector3(px2, top_y + 0.16, deck_d * 0.5), post_mat)
		_add_cyl(g, 0.02, 0.28, Vector3(px2, top_y + 0.16, -deck_d * 0.5), post_mat)


func _build_skin_buttons() -> void:
	var row := Node3D.new()
	row.name = "SkinButtons"
	_hud_root.add_child(row)
	var by := _couch_center.y + _couch_size.y * 0.5 + 1.05
	var xs := [-0.95, 0.0, 0.95]
	for i in SKIN_NAMES.size():
		var skin_name: String = SKIN_NAMES[i]
		_make_button(row, skin_name, SKIN_TITLES[skin_name],
			Vector3(_couch_center.x + xs[i], by, _couch_center.z + 0.15),
			Vector3(0.62, 0.2, 0.14), SKIN_COLORS[skin_name])
	# honest-limitation note under the buttons
	var note := _make_label(
		"Passthrough shows your real couch underneath — skins are light auras around it",
		24, Color(0.75, 0.8, 0.9))
	note.position = Vector3(_couch_center.x, by - 0.35, _couch_center.z + 0.15)
	row.add_child(note)


func _apply_skin(skin_name: String) -> void:
	if not _skins.has(skin_name):
		return
	_active_skin = skin_name
	for key in _skins.keys():
		(_skins[key] as Node3D).visible = key == skin_name
		if _skin_buttons.has(key):
			var b: Dictionary = _skin_buttons[key]
			var mat: StandardMaterial3D = b["mat"]
			var base: Color = b["base"]
			if key == skin_name:
				mat.emission = base.lightened(0.5)
				mat.emission_energy_multiplier = 2.0
			else:
				mat.emission = base
				mat.emission_energy_multiplier = 0.6
	var g: Node3D = _skins[skin_name]
	# pirate has no translucent shell — guard the meta lookups
	_shell_mat = (g.get_meta("shell_mat") as StandardMaterial3D) \
		if g.has_meta("shell_mat") else null
	_shell_base_emission = g.get_meta("shell_base") \
		if g.has_meta("shell_base") else Color.BLACK


func _build_hud() -> void:
	_score_label = _make_label("SCORE 0", 56, Color(1.0, 1.0, 1.0))
	_score_label.position = _couch_center + Vector3(0, 2.15, 0)
	_hud_root.add_child(_score_label)
	_lives_label = _make_label("♥♥♥", 56, Color(1.0, 0.35, 0.4))
	_lives_label.position = _couch_center + Vector3(0, 1.9, 0)
	_hud_root.add_child(_lives_label)
	_wave_label = _make_label("WAVE 1", 36, Color(0.7, 0.85, 1.0))
	_wave_label.position = _couch_center + Vector3(0, 1.66, 0)
	_hud_root.add_child(_wave_label)
	var hint := _make_label("Aim with controller ray or mouse — pull trigger / click to zap",
		24, Color(0.7, 0.75, 0.85))
	hint.position = _couch_center + Vector3(0, 1.46, 0)
	_hud_root.add_child(hint)
	_update_hud()


func _update_hud() -> void:
	if _score_label != null:
		_score_label.text = "SCORE %d" % _score
	if _lives_label != null:
		_lives_label.text = "♥".repeat(maxi(_lives, 0)) + "♡".repeat(maxi(MAX_LIVES - _lives, 0))
	if _wave_label != null:
		_wave_label.text = "WAVE %d" % _wave


func _build_overlay() -> void:
	_overlay = Node3D.new()
	_overlay.name = "GameOver"
	_overlay.position = _couch_center + Vector3(0, 1.35, 0.4)
	_overlay.visible = false
	_hud_root.add_child(_overlay)
	var panel_mat := StandardMaterial3D.new()
	panel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel_mat.albedo_color = Color(0.05, 0.06, 0.1, 0.88)
	_add_box(_overlay, Vector3(1.4, 0.95, 0.06), Vector3.ZERO, panel_mat)
	var title := _make_label("GAME OVER", 64, Color(1.0, 0.4, 0.35))
	title.position = Vector3(0, 0.28, 0.05)
	_overlay.add_child(title)
	_overlay_score = _make_label("SCORE 0", 48, Color.WHITE)
	_overlay_score.position = Vector3(0, 0.02, 0.05)
	_overlay.add_child(_overlay_score)
	# "Play again" 3D button
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.6, 0.2, 0.1)
	b.material = _emissive_mat(Color(0.2, 0.7, 0.3), 1.2)
	mi.mesh = b
	mi.position = Vector3(0, -0.28, 0.05)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.add_child(mi)
	var label := _make_label("Play again", 36, Color.WHITE)
	label.position = Vector3(0, -0.28, 0.14)
	_overlay.add_child(label)
	var area := Area3D.new()
	area.name = "PlayAgain"
	area.collision_layer = PICK_MASK
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("play_again")
	area.position = Vector3(0, -0.28, 0.05)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.35, 0.3)
	cs.shape = shape
	area.add_child(cs)
	_overlay.add_child(area)


# ------------------------------------------------------------------ FX ----

func _build_fx() -> void:
	# one-shot particle burst reused for every zap kill
	_burst = _make_particles(24, 0.45, true, 0.02, Color(1.0, 0.5, 0.15), 3.0)
	_burst.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -4, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.5, 0.15)
	_burst.process_material = pm
	_burst.emitting = false
	_fx_root.add_child(_burst)
	# small pool of floating "+10" popups
	for i in 5:
		var p := _make_label("+10", 40, Color(1.0, 0.9, 0.4))
		p.visible = false
		_fx_root.add_child(p)
		_popups.append(p)


func _popup(text: String, pos: Vector3) -> void:
	var p: Label3D = _popups[_popup_idx]
	_popup_idx = (_popup_idx + 1) % _popups.size()
	p.text = text
	p.global_position = pos
	p.modulate = Color(1.0, 0.9, 0.4, 1.0)
	p.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position:y", p.position.y + 0.45, 0.7)
	tw.tween_property(p, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(func() -> void: p.visible = false)


func _build_audio() -> void:
	_zap_stream = _make_tone(880.0, 220.0, 0.12, 0.35)
	_thump_stream = _make_tone(120.0, 45.0, 0.28, 0.6)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SFX"
	add_child(_sfx)


func _make_tone(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var f := lerpf(f0, f1, t / dur)
		var env := 1.0 - t / dur
		var s := sin(TAU * f * t) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _play(stream: AudioStreamWAV) -> void:
	if _sfx != null and stream != null:
		_sfx.stream = stream
		_sfx.play()


func _build_mouse_aim() -> void:
	var mat := _emissive_mat(Color(1.0, 0.85, 0.3), 2.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 1.0
	cyl.radial_segments = 6
	_mouse_laser = MeshInstance3D.new()
	_mouse_laser.mesh = cyl
	_mouse_laser.material_override = mat
	_mouse_laser.visible = false
	_mouse_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mouse_laser)
	var sph := SphereMesh.new()
	sph.radius = 0.016
	sph.height = 0.032
	sph.radial_segments = 8
	sph.rings = 4
	_mouse_dot = MeshInstance3D.new()
	_mouse_dot.mesh = sph
	_mouse_dot.material_override = mat
	_mouse_dot.visible = false
	_mouse_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mouse_dot)


# -------------------------------------------------------- couch defense ----

func _spawn_interval() -> float:
	return maxf(SPAWN_MIN, SPAWN_BASE - float(_wave) * SPAWN_STEP)


func _spawn_point() -> Vector3:
	if not _walls.is_empty():
		var w: Dictionary = _walls[randi() % _walls.size()]
		var pos: Vector3 = w["position"]
		var normal: Vector3 = w["normal"]
		return pos - normal * 0.4 + Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), 0)
	var ang := randf() * TAU
	return _couch_center + Vector3(cos(ang) * 3.0, randf_range(0.5, 1.2), sin(ang) * 3.0)


func _spawn_attacker() -> void:
	if _attackers.size() >= MAX_ATTACKERS:
		return
	var area := Area3D.new()
	area.collision_layer = PICK_MASK
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group("attacker")
	# faceted red icosahedron-ish body (low-seg sphere)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = ATTACKER_RADIUS
	sm.height = ATTACKER_RADIUS * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _emissive_mat(Color(1.0, 0.15, 0.1), 2.5)
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = ATTACKER_RADIUS + 0.06 # forgiving touch target
	cs.shape = shape
	area.add_child(cs)
	area.position = _spawn_point()
	area.set_meta("phase", randf() * TAU)
	area.set_meta("mesh", mi)
	_attackers_root.add_child(area)
	_attackers.append(area)


func _update_attackers(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for a in _attackers.duplicate():
		var area := a as Area3D
		if not is_instance_valid(area):
			_attackers.erase(a)
			continue
		var to: Vector3 = _couch_center - area.global_position
		var dist := to.length()
		if dist < HIT_DIST:
			_on_attacker_reached(area)
			continue
		var dir := to / maxf(dist, 0.001)
		area.global_position += dir * ATTACKER_SPEED * delta
		# gentle wobble so the flight path feels alive
		var phase: float = area.get_meta("phase")
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() > 0.01:
			area.global_position += side * sin(t * 4.0 + phase) * 0.25 * delta
		var mesh: MeshInstance3D = area.get_meta("mesh")
		if is_instance_valid(mesh):
			mesh.rotate_y(delta * 3.0)


func _kill_attacker(area: Area3D, at: Vector3) -> void:
	if not is_instance_valid(area) or not _attackers.has(area):
		return
	_attackers.erase(area)
	area.queue_free()
	_score += 10
	_kills += 1
	_wave = 1 + _kills / KILLS_PER_WAVE
	_popup("+10", at)
	_burst.global_position = at
	_burst.restart()
	_play(_zap_stream)
	_update_hud()


func _on_attacker_reached(area: Area3D) -> void:
	if not is_instance_valid(area):
		return
	_attackers.erase(area)
	var pos := area.global_position
	area.queue_free()
	_lives -= 1
	_flash_shell_red()
	_play(_thump_stream)
	_popup("HIT!", pos)
	_update_hud()
	if _lives <= 0:
		_game_over()


func _flash_shell_red() -> void:
	if _shell_mat == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_shell_mat, "emission", Color(1.0, 0.0, 0.0), 0.08)
	_flash_tween.tween_property(_shell_mat, "emission", _shell_base_emission, 0.5)


func _game_over() -> void:
	_game_active = false
	for a in _attackers:
		if is_instance_valid(a):
			(a as Area3D).queue_free()
	_attackers.clear()
	_overlay_score.text = "SCORE %d" % _score
	_overlay.visible = true


func _reset_game() -> void:
	for a in _attackers_root.get_children():
		_attackers_root.remove_child(a)
		a.queue_free()
	_attackers.clear()
	_score = 0
	_lives = MAX_LIVES
	_kills = 0
	_wave = 1
	_spawn_timer = 0.0
	_game_active = true
	if _overlay != null:
		_overlay.visible = false
	_update_hud()


# --------------------------------------------------------------- input ----

func _scan_controllers() -> void:
	_controllers = get_tree().root.find_children("*", "XRController3D", true, false)
	for c in _controllers:
		if not _rigs.has(c):
			_rigs[c] = _make_rig()
	# drop rigs for controllers that went away
	for key in _rigs.keys():
		if not is_instance_valid(key) or not _controllers.has(key):
			var rig: Dictionary = _rigs[key]
			(rig["laser"] as MeshInstance3D).queue_free()
			(rig["dot"] as MeshInstance3D).queue_free()
			_rigs.erase(key)


func _make_rig() -> Dictionary:
	var mat := _emissive_mat(Color(0.4, 0.95, 1.0), 2.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 1.0
	cyl.radial_segments = 6
	var laser := MeshInstance3D.new()
	laser.mesh = cyl
	laser.material_override = mat
	laser.visible = false
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(laser)
	var sph := SphereMesh.new()
	sph.radius = 0.016
	sph.height = 0.032
	sph.radial_segments = 8
	sph.rings = 4
	var dot := MeshInstance3D.new()
	dot.mesh = sph
	dot.material_override = mat
	dot.visible = false
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dot)
	return {"laser": laser, "dot": dot, "prev": 0.0}


func _controller_active(c: XRController3D) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	return c.get_tracker() != null


func _aim_ray(origin: Vector3, dir: Vector3) -> Dictionary:
	var res := {"hit": false, "point": origin + dir * LASER_LEN}
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LEN, PICK_MASK)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		res["hit"] = true
		res["point"] = hit["position"]
		res["collider"] = hit["collider"]
	return res


func _place_laser(laser: MeshInstance3D, dot: MeshInstance3D, from: Vector3,
		to: Vector3, show_dot: bool) -> void:
	var length := from.distance_to(to)
	if length < 0.001:
		laser.visible = false
		dot.visible = false
		return
	var d := (to - from) / length
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var y := d
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	laser.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3(1.0, length, 1.0)),
		(from + to) * 0.5)
	laser.visible = true
	dot.global_position = to
	dot.visible = show_dot


func _update_controller_rigs() -> void:
	var any_active := false
	for c in _controllers:
		var ctrl := c as XRController3D
		var rig: Dictionary = _rigs.get(ctrl, {})
		if rig.is_empty() or not _controller_active(ctrl):
			continue
		any_active = true
		var gt := ctrl.global_transform
		var origin: Vector3 = gt.origin
		var dir := -gt.basis.z.normalized()
		var ray := _aim_ray(origin, dir)
		_place_laser(rig["laser"], rig["dot"], origin, ray["point"], bool(ray["hit"]))
		var trig := 0.0
		trig = ctrl.get_float("trigger")
		var pressed := trig >= TRIGGER_EDGE or ctrl.is_button_pressed("trigger_click")
		var was := float(rig["prev"]) >= TRIGGER_EDGE
		if pressed and not was:
			_zap(origin, dir)
		rig["prev"] = trig
	# hide rigs of inactive controllers
	for key in _rigs.keys():
		if not _controller_active(key as XRController3D):
			var rig: Dictionary = _rigs[key]
			(rig["laser"] as MeshInstance3D).visible = false
			(rig["dot"] as MeshInstance3D).visible = false
	_update_mouse_aim(not any_active)


func _update_mouse_aim(desktop_mode: bool) -> void:
	if not desktop_mode or _mouse_pos.x < 0.0:
		_mouse_laser.visible = false
		_mouse_dot.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_mouse_laser.visible = false
		_mouse_dot.visible = false
		return
	var origin := cam.project_ray_origin(_mouse_pos)
	var dir := cam.project_ray_normal(_mouse_pos)
	var ray := _aim_ray(origin, dir)
	_place_laser(_mouse_laser, _mouse_dot, origin, ray["point"], bool(ray["hit"]))


func _zap(origin: Vector3, dir: Vector3) -> void:
	var ray := _aim_ray(origin, dir)
	if not bool(ray["hit"]):
		return
	var col: Object = ray["collider"]
	if not (col is Area3D):
		return
	if col.is_in_group("attacker"):
		_kill_attacker(col, ray["point"])
	elif col.is_in_group("skin_button"):
		_apply_skin(str(col.get_meta("skin")))
	elif col.is_in_group("play_again") and not _game_active:
		_reset_game()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				var origin := cam.project_ray_origin(mb.position)
				var dir := cam.project_ray_normal(mb.position)
				_zap(origin, dir)


func _process(delta: float) -> void:
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = 1.0
		_scan_controllers()
	if not _setup_done:
		return
	# spaceship nav-light blink
	if _active_skin == "spaceship" and not _nav_lights.is_empty():
		var t := Time.get_ticks_msec() / 1000.0
		for n in _nav_lights:
			var d: Dictionary = n
			(d["mat"] as StandardMaterial3D).emission_energy_multiplier = \
				1.6 + 1.4 * sin(t * 5.0 + float(d["phase"]))
	_update_controller_rigs()
	if not _game_active:
		return
	_spawn_timer += delta
	if _spawn_timer >= _spawn_interval():
		_spawn_timer = 0.0
		_spawn_attacker()
	_update_attackers(delta)
