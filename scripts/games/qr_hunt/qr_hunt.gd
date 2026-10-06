## qr_hunt.gd - QR Treasure Hunt camera game.
## A 5-clue chain: print the QR codes in assets/qr_codes/, hide them around
## the house, then scan them IN ORDER (real camera via ARCamera.scan_qr() or
## the clearly-labeled DEMO buttons when no camera is available). Each correct
## scan pops open an AR treasure chest with confetti; the 5th scan triggers
## the grand treasure celebration with a golden trophy.
## Interaction: 3D SCAN button via mouse click or XR right-hand pinch.
extends Node3D
class_name QRHuntGame

const MAX_CLUES := 5
const ANCHOR_NAME := "qr_hunt_main"

## Payload prefixes; the full payloads live in the printed QR codes.
const CLUE_PREFIXES: Array[String] = [
	"NEXUS-CLUE-1:",
	"NEXUS-CLUE-2:",
	"NEXUS-CLUE-3:",
	"NEXUS-CLUE-4:",
	"NEXUS-CLUE-5:",
]

## HUD hint shown for each step: which PNG to print and where to hide it.
const CLUE_HINTS: Array[String] = [
	"Print qr_1.png — hide it where the sun rises in the kitchen (the window!)",
	"Print qr_2.png — hide it with the cold keeper of midnight snacks (the fridge!)",
	"Print qr_3.png — hide it behind something flat that shows stories (behind the TV/frame!)",
	"Print qr_4.png — hide it where shoes rest after a long day (the shoe rack!)",
	"Print qr_5.png — hide it where the TREASURE waits!",
]

const HELP_TEXT := """HOW TO PLAY
1. Print assets/qr_codes/qr_sheet.png
   (or qr_1.png ... qr_5.png) and cut them apart.
2. Hide the codes around the house following
   the hint for each clue.
3. Come back here and press SCAN (or the
   DEMO buttons) to scan each code IN ORDER.
4. Find all 5 to claim your AR treasure!"""

var _current := 0 ## index of the next clue to find (0-based)
var _completed := false
var _cam: Camera3D = null
var _buttons := {} ## StaticBody3D -> String action
var _progress_label: Label3D = null
var _hint_label: Label3D = null
var _message_label: Label3D = null
var _help_panel: Node3D = null
var _help_visible := false
var _chest: Node3D = null
var _lid_pivot: Node3D = null
var _coins: Array[Node3D] = []
var _chest_anim := 0.0 ## 0 closed, 1 open
var _chest_hold := 0.0 ## seconds to hold open before closing
var _chest_target := 0.0
var _trophy: Node3D = null
var _trophy_anim := 0.0
var _trophy_mat: StandardMaterial3D = null
var _t := 0.0
var _anchor_timer := 0.0


func _ready() -> void:
	# AR: restore this game's persisted spatial anchor, if one was saved.
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	_ensure_camera()
	_build_environment()
	_build_hud()
	_build_buttons()
	_build_demo_row()
	_build_help_panel()
	_build_chest()
	_build_trophy()
	_update_hud()
	# Ask Android for the camera permission up front (no-op on desktop).
	ARCamera.request_permission()


func _process(delta: float) -> void:
	_t += delta
	# AR: persist the game anchor every 30s so the layout survives restarts.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	# Hand interaction: right-hand pinch activates whatever button the hand
	# pointer is aimed at. The mouse-press gate keeps the kit's mouse
	# fallback from double-triggering.
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var ray := ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		_press_at_ray(ray[0], ray[1])
	_animate_chest(delta)
	_animate_trophy(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(mb.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_help_panel.visible = false
			_help_visible = false


# ---------------------------------------------------------------- build

func _ensure_camera() -> void:
	_cam = get_viewport().get_camera_3d()
	if _cam != null:
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.position = Vector3(0, 3.2, 5.5)
	_cam.look_at(Vector3(0, 0.8, -1.0), Vector3.UP)


func _build_environment() -> void:
	# Three-point light rig; never add a second key light.
	if not get_children().any(func(c: Node) -> bool: return c is DirectionalLight3D):
		GraphicsPolish.make_light_rig(self, 1.0)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.ambient_light_energy = 0.9
	amb.environment = env
	add_child(amb)
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.5, 0), 3.0, 40)


func _build_hud() -> void:
	_progress_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.85, 0.35))
	_progress_label.position = Vector3(0, 3.7, 2.2)
	_progress_label.pixel_size = 0.012
	add_child(_progress_label)
	_hint_label = GraphicsPolish.make_label("", 48, Color(0.85, 0.9, 1.0))
	_hint_label.position = Vector3(0, 3.05, 2.2)
	_hint_label.pixel_size = 0.009
	add_child(_hint_label)
	_message_label = GraphicsPolish.make_label("", 48, Color(0.7, 1.0, 0.7))
	_message_label.position = Vector3(0, 2.45, 2.2)
	_message_label.pixel_size = 0.009
	add_child(_message_label)


func _make_button(action: String, text: String, pos: Vector3, color: Color,
		size := Vector3(2.2, 0.6, 0.15)) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := GraphicsPolish.pbr_preset(color, "plastic")
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mi.material_override = mat
	root.add_child(mi)
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var label := GraphicsPolish.make_label(text, 48, Color.WHITE)
	label.position = Vector3(0, 0, size.z * 0.5 + 0.02)
	label.pixel_size = 0.011
	root.add_child(label)
	_buttons[sb] = action


func _build_buttons() -> void:
	_make_button("scan", "SCAN", Vector3(0, 1.35, 2.8), Color(0.3, 0.75, 0.35),
		Vector3(2.6, 0.8, 0.15))
	_make_button("help", "How to Play", Vector3(-2.4, 1.35, 2.8), Color(0.3, 0.6, 0.9))
	_make_button("reset", "Reset Hunt", Vector3(2.4, 1.35, 2.8), Color(0.85, 0.45, 0.3))


func _build_demo_row() -> void:
	var header := GraphicsPolish.make_label("DEMO (works without a camera)", 40,
		Color(1.0, 0.8, 0.4))
	header.position = Vector3(0, 0.95, 2.8)
	header.pixel_size = 0.008
	add_child(header)
	for i in MAX_CLUES:
		_make_button("demo%d" % (i + 1), "Sim Clue %d" % (i + 1),
			Vector3(-3.0 + i * 1.5, 0.35, 2.8), Color(0.55, 0.5, 0.7),
			Vector3(1.3, 0.45, 0.12))


func _build_help_panel() -> void:
	_help_panel = Node3D.new()
	_help_panel.position = Vector3(0, 2.0, 1.6)
	add_child(_help_panel)
	var bg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.4, 3.2, 0.08)
	bg.mesh = bm
	bg.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.1, 0.16), "matte")
	_help_panel.add_child(bg)
	var label := GraphicsPolish.make_label(HELP_TEXT, 44, Color(0.9, 0.95, 1.0))
	label.position = Vector3(0, 0, 0.06)
	label.pixel_size = 0.0075
	_help_panel.add_child(label)
	_help_panel.visible = false


func _build_chest() -> void:
	# Treasure chest from primitives: wood body, gold trim, glowing gems,
	# hinged lid that pops open, and a pile of coins revealed inside.
	_chest = Node3D.new()
	_chest.position = Vector3(2.1, 0, 0.6)
	add_child(_chest)
	var wood := GraphicsPolish.pbr(Color(0.45, 0.26, 0.13), 0.0, 0.7)
	var gold := GraphicsPolish.pbr(Color(0.95, 0.72, 0.2), 1.0, 0.3)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.0, 0.55, 0.7)
	base.mesh = base_mesh
	base.position = Vector3(0, 0.275, 0)
	base.material_override = wood
	_chest.add_child(base)
	# Gold trim bands around the body.
	for x in [-0.42, 0.42]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.08, 0.57, 0.72)
		band.mesh = band_mesh
		band.position = Vector3(x, 0.275, 0)
		band.material_override = gold
		_chest.add_child(band)
	# Hinged lid: pivot at the back top edge so it rotates open.
	_lid_pivot = Node3D.new()
	_lid_pivot.position = Vector3(0, 0.55, -0.35)
	_chest.add_child(_lid_pivot)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.0, 0.3, 0.7)
	lid.mesh = lid_mesh
	lid.position = Vector3(0, 0.15, 0.35)
	lid.material_override = wood
	_lid_pivot.add_child(lid)
	var lid_trim := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(1.02, 0.08, 0.72)
	lid_trim.mesh = trim_mesh
	lid_trim.position = Vector3(0, 0.02, 0.35)
	lid_trim.material_override = gold
	_lid_pivot.add_child(lid_trim)
	# Glowing gems on the lid front.
	var gem_colors := [Color(1.0, 0.25, 0.3), Color(0.3, 1.0, 0.45), Color(0.35, 0.6, 1.0)]
	for i in 3:
		var gem := MeshInstance3D.new()
		var gem_mesh := SphereMesh.new()
		gem_mesh.radius = 0.07
		gem_mesh.height = 0.14
		gem.mesh = gem_mesh
		gem.position = Vector3(-0.28 + i * 0.28, 0.15, 0.68)
		gem.material_override = GraphicsPolish.glow(gem_colors[i], 2.0)
		_lid_pivot.add_child(gem)
	# Coins hidden inside the chest; they pop up when the lid opens.
	for i in 6:
		var coin := MeshInstance3D.new()
		var coin_mesh := CylinderMesh.new()
		coin_mesh.top_radius = 0.09
		coin_mesh.bottom_radius = 0.09
		coin_mesh.height = 0.03
		coin.mesh = coin_mesh
		coin.position = Vector3(-0.3 + (i % 3) * 0.3, 0.5 + (i / 3) * 0.06, -0.1 + (i % 2) * 0.2)
		coin.rotation = Vector3(0.3, randf() * TAU, 0.2)
		coin.material_override = GraphicsPolish.glow(Color(1.0, 0.82, 0.3), 1.2)
		coin.scale = Vector3.ONE * 0.01
		_chest.add_child(coin)
		_coins.append(coin)
	# Warm golden light inside the chest, brightest when open.
	GraphicsPolish.make_point_light(_chest, Vector3(0, 0.7, 0), Color(1.0, 0.8, 0.4), 0.6, 3.0)


func _build_trophy() -> void:
	# Golden grand-prize trophy from primitives; hidden until clue 5 is found.
	_trophy = Node3D.new()
	_trophy.position = Vector3(-2.1, 0, 0.6)
	_trophy.scale = Vector3.ONE * 0.01
	add_child(_trophy)
	_trophy_mat = GraphicsPolish.pbr(Color(0.95, 0.72, 0.2), 1.0, 0.25)
	_trophy_mat.emission_enabled = true
	_trophy_mat.emission = Color(0.95, 0.72, 0.2)
	_trophy_mat.emission_energy_multiplier = 0.8

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.5, 0.15, 0.5)
	base.mesh = base_mesh
	base.position = Vector3(0, 0.075, 0)
	base.material_override = GraphicsPolish.pbr(Color(0.25, 0.14, 0.08), 0.0, 0.7)
	_trophy.add_child(base)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.08
	stem_mesh.bottom_radius = 0.12
	stem_mesh.height = 0.5
	stem.mesh = stem_mesh
	stem.position = Vector3(0, 0.4, 0)
	stem.material_override = _trophy_mat
	_trophy.add_child(stem)
	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.34
	cup_mesh.bottom_radius = 0.12
	cup_mesh.height = 0.5
	cup.mesh = cup_mesh
	cup.position = Vector3(0, 0.9, 0)
	cup.material_override = _trophy_mat
	_trophy.add_child(cup)
	for x in [-0.36, 0.36]:
		var handle := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.03
		torus.outer_radius = 0.14
		handle.mesh = torus
		handle.position = Vector3(x, 0.85, 0)
		handle.rotation = Vector3(0, 0, PI * 0.5)
		handle.material_override = _trophy_mat
		_trophy.add_child(handle)
	var star := MeshInstance3D.new()
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.12
	star_mesh.height = 0.24
	star.mesh = star_mesh
	star.position = Vector3(0, 1.3, 0)
	star.material_override = GraphicsPolish.glow(Color(1.0, 0.9, 0.4), 2.5)
	_trophy.add_child(star)
	var label := GraphicsPolish.make_label("TREASURE!", 64, Color(1.0, 0.85, 0.3))
	label.position = Vector3(0, 1.7, 0)
	label.pixel_size = 0.012
	_trophy.add_child(label)


# ---------------------------------------------------------------- input

func _on_click(screen_pos: Vector2) -> void:
	if _cam == null:
		return
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	_press_at_ray(from, dir)


func _press_at_ray(from: Vector3, dir: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider is StaticBody3D and _buttons.has(collider):
		_do_button(_buttons[collider] as String)


func _do_button(action: String) -> void:
	Haptics.tick()
	match action:
		"scan":
			_do_scan()
		"help":
			_help_visible = not _help_visible
			_help_panel.visible = _help_visible
		"reset":
			_reset_hunt()
		_:
			if action.begins_with("demo"):
				_simulate_scan(int(action.substr(4)) - 1)


# ---------------------------------------------------------------- game logic

func _do_scan() -> void:
	if _completed:
		_set_message("Hunt complete! Press Reset Hunt to play again.", Color(0.7, 1.0, 0.7))
		return
	if not ARCamera.is_available():
		# Permission was already requested in _ready(); without a camera the
		# DEMO buttons are the playable path.
		_set_message("Camera not available — use the DEMO buttons below to play.",
			Color(1.0, 0.8, 0.4))
		return
	var code := ARCamera.scan_qr()
	if code.is_empty():
		_set_message("No QR code detected — aim at a code and press SCAN again.",
			Color(1.0, 0.8, 0.4))
		Haptics.pulse(0.3, 0.1)
		return
	_handle_payload(code)


func _simulate_scan(clue_index: int) -> void:
	if _completed:
		_set_message("Hunt complete! Press Reset Hunt to play again.", Color(0.7, 1.0, 0.7))
		return
	# Pretend the camera decoded clue (clue_index + 1)'s payload.
	_handle_payload(CLUE_PREFIXES[clue_index] + "SIM")


func _handle_payload(code: String) -> void:
	var found := -1
	for i in MAX_CLUES:
		if code.begins_with(CLUE_PREFIXES[i]):
			found = i
			break
	if found < 0:
		_set_message("That's not a treasure-hunt code — scan a NEXUS clue QR.",
			Color(1.0, 0.8, 0.4))
		Haptics.pulse(0.3, 0.1)
		return
	if found != _current:
		_set_message("That's not the next clue — you need Clue %d of 5." % (_current + 1),
			Color(1.0, 0.8, 0.4))
		Haptics.pulse(0.35, 0.15)
		return
	# Correct clue, in order.
	_current += 1
	var riddle := code.substr(CLUE_PREFIXES[found].length()).strip_edges()
	Haptics.thump()
	_chest_target = 1.0
	_chest_hold = 2.5
	if _current >= MAX_CLUES:
		_completed = true
		_grand_celebration()
	else:
		GraphicsPolish.spawn_confetti(self, _chest.global_position + Vector3(0, 0.8, 0), 60)
		_set_message("Clue %d found! \"%s\"" % [found + 1, riddle], Color(0.7, 1.0, 0.7))
	_update_hud()


func _grand_celebration() -> void:
	_set_message("TREASURE! You found all 5 clues — the AR loot is yours!",
		Color(1.0, 0.85, 0.3))
	GraphicsPolish.spawn_confetti(self, _chest.global_position + Vector3(0, 1.0, 0), 120)
	GraphicsPolish.spawn_confetti(self, _trophy.global_position + Vector3(0, 1.5, 0), 120)
	GraphicsPolish.spawn_sparks(self, _trophy.global_position + Vector3(0, 1.0, 0),
		Color(1.0, 0.85, 0.3), 60)
	_trophy_anim = 0.0001 ## start the scale-in reveal
	Haptics.pulse(1.0, 0.4)


func _reset_hunt() -> void:
	_current = 0
	_completed = false
	_chest_target = 0.0
	_chest_anim = 0.0
	_chest_hold = 0.0
	_trophy_anim = 0.0
	_trophy.scale = Vector3.ONE * 0.01
	_set_message("Hunt reset — hide the codes, then scan Clue 1.", Color(0.85, 0.9, 1.0))
	_update_hud()


func _set_message(text: String, color: Color) -> void:
	_message_label.text = text
	_message_label.modulate = color


func _update_hud() -> void:
	if _completed:
		_progress_label.text = "TREASURE FOUND!  5/5"
	elif _current < MAX_CLUES:
		_progress_label.text = "Clue %d of %d" % [_current + 1, MAX_CLUES]
	if _current < MAX_CLUES and not _completed:
		_hint_label.text = CLUE_HINTS[_current]
	elif _completed:
		_hint_label.text = "All clues found — enjoy your AR loot!"


# ---------------------------------------------------------------- animation

func _animate_chest(delta: float) -> void:
	if _chest_hold > 0.0:
		_chest_hold -= delta
		if _chest_hold <= 0.0:
			_chest_target = 0.0
	_chest_anim = move_toward(_chest_anim, _chest_target, delta * 2.5)
	_lid_pivot.rotation.x = -1.85 * _chest_anim
	var coin_scale := maxf(_chest_anim, 0.01)
	for coin in _coins:
		coin.scale = Vector3.ONE * coin_scale
	# Gentle idle bob so the chest feels alive.
	_chest.position.y = 0.05 * sin(_t * 1.5)


func _animate_trophy(delta: float) -> void:
	if _trophy_anim <= 0.0:
		return
	_trophy_anim = minf(_trophy_anim + delta * 1.2, 1.0)
	var s := 1.0
	if _trophy_anim < 1.0:
		# Overshoot ease for a triumphant pop-in.
		var k := _trophy_anim
		s = 1.0 + 2.5 * pow(1.0 - k, 2.0) * sin(k * PI * 3.0) * (1.0 - k)
	_trophy.scale = Vector3.ONE * maxf(s, 0.01)
	GraphicsPolish.pulse_glow(_trophy_mat, 0.8, 0.6, _t, 2.0)
	_trophy.rotation.y = _t * 0.8
