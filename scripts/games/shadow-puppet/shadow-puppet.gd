## Shadow Puppets: hand-puppet shadow theater.
## A backlit screen anchors in the room; your hand casts a blob shadow on it.
## Puppet shapes: pinch = bird (flap by tapping the pinch), pinch-hold = dog,
## two hands pinching = butterfly. Desktop fallback: mouse moves the shadow,
## click/tap = bird (flaps while held), hold > 0.6s = dog, both mouse buttons =
## butterfly. Story mode: prompts appear ("make the bird fly over the
## mountain!") and the audience scores you by matching your shadow to the
## glowing target zones. Score = applause meter 0-100. Silly and charming.
## R restarts. Theater placement persists via anchor.
extends Node3D

const SCREEN_POS := Vector3(0.0, 1.55, -1.9)
const SCREEN_W := 2.6
const SCREEN_H := 1.9
const DOG_HOLD_TIME := 0.6
const PROMPTS := [
	{"text": "Make the BIRD flap over the mountain!", "type": "bird", "zone": Vector2(0.75, 0.55), "hold": 1.2},
	{"text": "The DOG sits by the lake. Hold still!", "type": "dog", "zone": Vector2(-0.7, -0.55), "hold": 1.6},
	{"text": "The BUTTERFLY dances in the flowers!", "type": "butterfly", "zone": Vector2(0.1, 0.1), "hold": 1.4},
	{"text": "Fly the BIRD home to the nest!", "type": "bird", "zone": Vector2(-0.85, 0.35), "hold": 1.2},
]

var camera: Camera3D = null
var screen: MeshInstance3D = null
var screen_mat: StandardMaterial3D = null
var puppet: Node3D = null
var bird_parts: Array = []
var dog_parts: Array = []
var fly_parts: Array = []
var wing_l: MeshInstance3D = null
var wing_r: MeshInstance3D = null
var fly_wing_l: MeshInstance3D = null
var fly_wing_r: MeshInstance3D = null
var target_ring: MeshInstance3D = null
var target_mat: StandardMaterial3D = null
var applause_bar: MeshInstance3D = null
var prompt_idx := 0
var hold_t := 0.0
var applause := 0
var state := "playing"
var msg := ""
var msg_t := 0.0
var puppet_type := "bird"
var flap_t := 0.0
var flapping := false
var shadow_pos := Vector2.ZERO
var hud_label: Label3D = null
var prompt_label: Label3D = null
var help_label: Label3D = null
var pulse_t := 0.0
var press_t := 0.0
var pressing := false
var both_press := false

# --- v0.7.0 RoomKit: cached room layout (walls/tables/furniture/bounds) ---
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _theater: Node3D = null # container for screen + frame + scenery (re-based to local)


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "shadow-puppet_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_theater = Node3D.new()
	_theater.name = "Theater"
	add_child(_theater)
	_build_theater()
	_build_puppet()
	# Re-base theater pieces to container-local coords so the whole theater
	# can be mounted on a real wall as one rigid group (v0.7.0 RoomKit).
	for n in _theater.get_children():
		(n as Node3D).position -= SCREEN_POS
	_theater.position = SCREEN_POS
	_build_hud()
	_show_prompt()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -1.0), 2.0, 25)
	_apply_room_layout()


## Screen center in world space (follows the wall-mounted theater).
func _screen_pos() -> Vector3:
	return _theater.global_position if _theater != null else SCREEN_POS


## v0.7.0: mount the projection screen on the largest real wall, facing
## into the room. Guarded; fallback keeps the default floating theater.
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
	# MORPH-B (v0.7.0): lamps -> spooky theater footlights around the puppet stage
	_morph_anchors("LAMP", "haunted", 2)
	var best := {}
	var best_a := 0.0
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var a: float = (w["size"] as Vector2).x * (w["size"] as Vector2).y
		if a > best_a:
			best_a = a
			best = w
	if best.is_empty() or _theater == null:
		return
	var n: Vector3 = best["normal"]
	n.y = 0.0
	n = n.normalized() if n.length() > 0.01 else Vector3(0, 0, 1)
	var fw: Vector3 = (best["position"] as Vector3) + n * 0.10
	var c := _room_bounds.get_center()
	var d := Vector2(c.x - fw.x, c.y - fw.z)
	_theater.global_position = Vector3(fw.x, 1.55, fw.z)
	_theater.rotation.y = atan2(d.x, d.y) if d.length() > 0.05 else 0.0


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.55, 1.6)
	add_child(camera)
	camera.look_at(_screen_pos(), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.28, 0.4)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.7)


func _dark_blob(radius: float) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	inst.mesh = sphere
	inst.material_override = GraphicsPolish.pbr(Color(0.02, 0.02, 0.03), 0.0, 0.9)
	inst.scale.z = 0.35
	return inst


func _build_theater() -> void:
	# Wooden frame.
	var frame := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(SCREEN_W + 0.24, SCREEN_H + 0.24, 0.08)
	frame.mesh = fbox
	frame.material_override = GraphicsPolish.pbr_preset(Color(0.3, 0.18, 0.1), "matte")
	frame.position = SCREEN_POS + Vector3(0, 0, -0.05)
	_theater.add_child(frame)
	# Backlit screen.
	screen = MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(SCREEN_W, SCREEN_H, 0.05)
	screen.mesh = sbox
	screen_mat = GraphicsPolish.glow(Color(1.0, 0.96, 0.88), 1.1)
	screen.material_override = screen_mat
	screen.position = SCREEN_POS
	_theater.add_child(screen)
	# Curtains on the sides.
	for side in [-1.0, 1.0]:
		var curtain := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.35, SCREEN_H + 0.5, 0.25)
		curtain.mesh = cbox
		curtain.material_override = GraphicsPolish.pbr_preset(Color(0.5, 0.08, 0.12), "matte")
		curtain.position = SCREEN_POS + Vector3(side * (SCREEN_W * 0.5 + 0.28), 0.1, 0.1)
		_theater.add_child(curtain)
	# Scenery silhouettes pasted on the screen: mountain, lake, nest, flowers.
	var mountain := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 0.9
	mountain.mesh = cone
	mountain.material_override = GraphicsPolish.pbr(Color(0.12, 0.14, 0.22), 0.0, 0.9)
	mountain.position = SCREEN_POS + Vector3(0.75, -0.35, 0.045)
	mountain.scale.z = 0.3
	_theater.add_child(mountain)
	var lake := MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.4
	lcyl.bottom_radius = 0.4
	lcyl.height = 0.02
	lake.mesh = lcyl
	lake.material_override = GraphicsPolish.glow(Color(0.25, 0.5, 0.85), 0.5)
	lake.rotation_degrees.x = 90.0
	lake.scale = Vector3(1.0, 0.55, 1.0)
	lake.position = SCREEN_POS + Vector3(-0.7, -0.62, 0.045)
	_theater.add_child(lake)
	var nest := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.14
	torus.outer_radius = 0.24
	nest.mesh = torus
	nest.material_override = GraphicsPolish.pbr(Color(0.35, 0.2, 0.1), 0.0, 0.9)
	nest.position = SCREEN_POS + Vector3(-0.85, 0.05, 0.045)
	_theater.add_child(nest)
	for fx in [-0.15, 0.15, 0.35]:
		var flower := MeshInstance3D.new()
		var fs := SphereMesh.new()
		fs.radius = 0.06
		fs.height = 0.12
		flower.mesh = fs
		flower.material_override = GraphicsPolish.glow(Color(1.0, 0.4, 0.6), 0.8)
		flower.position = SCREEN_POS + Vector3(fx, -0.5, 0.045)
		_theater.add_child(flower)
	# Target ring showing where the shadow should go.
	target_ring = MeshInstance3D.new()
	var tring := TorusMesh.new()
	tring.inner_radius = 0.26
	tring.outer_radius = 0.34
	target_ring.mesh = tring
	target_mat = GraphicsPolish.glow(Color(1.0, 0.85, 0.2), 2.4)
	target_ring.material_override = target_mat
	_theater.add_child(target_ring)
	# Footlight.
	GraphicsPolish.make_point_light(_theater, Vector3(0, -1.2, 0.6), Color(1.0, 0.8, 0.55), 1.0, 4.0)


func _build_puppet() -> void:
	puppet = Node3D.new()
	add_child(puppet)
	# --- Bird: body blob + flapping wings.
	var body := _dark_blob(0.16)
	bird_parts.append(body)
	puppet.add_child(body)
	wing_l = _dark_blob(0.10)
	wing_l.scale = Vector3(1.6, 0.7, 0.35)
	wing_r = _dark_blob(0.10)
	wing_r.scale = Vector3(1.6, 0.7, 0.35)
	bird_parts.append(wing_l)
	bird_parts.append(wing_r)
	puppet.add_child(wing_l)
	puppet.add_child(wing_r)
	var beak := _dark_blob(0.05)
	bird_parts.append(beak)
	puppet.add_child(beak)
	# --- Dog: chunky blob + ears + snout.
	var dbody := _dark_blob(0.20)
	dog_parts.append(dbody)
	puppet.add_child(dbody)
	for ex in [-0.12, 0.12]:
		var ear := _dark_blob(0.07)
		dog_parts.append(ear)
		puppet.add_child(ear)
	var snout := _dark_blob(0.09)
	snout.scale = Vector3(1.0, 0.7, 0.35)
	dog_parts.append(snout)
	puppet.add_child(snout)
	# --- Butterfly: two big wings.
	fly_wing_l = _dark_blob(0.16)
	fly_wing_l.scale = Vector3(1.1, 1.4, 0.3)
	fly_wing_r = _dark_blob(0.16)
	fly_wing_r.scale = Vector3(1.1, 1.4, 0.3)
	fly_parts.append(fly_wing_l)
	fly_parts.append(fly_wing_r)
	puppet.add_child(fly_wing_l)
	puppet.add_child(fly_wing_r)
	var fbody := _dark_blob(0.06)
	fbody.scale = Vector3(0.6, 2.2, 0.3)
	fly_parts.append(fbody)
	puppet.add_child(fbody)
	# Applause meter bar above the theater.
	applause_bar = MeshInstance3D.new()
	var abar := BoxMesh.new()
	abar.size = Vector3(1.0, 0.08, 0.08)
	applause_bar.mesh = abar
	applause_bar.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.2), 1.8)
	applause_bar.position = SCREEN_POS + Vector3(-1.0, SCREEN_H * 0.5 + 0.35, 0.2)
	_theater.add_child(applause_bar)
	var bar_frame := MeshInstance3D.new()
	var bf := BoxMesh.new()
	bf.size = Vector3(2.1, 0.12, 0.06)
	bar_frame.mesh = bf
	bar_frame.material_override = GraphicsPolish.pbr(Color(0.2, 0.2, 0.25), 0.3, 0.5)
	bar_frame.position = SCREEN_POS + Vector3(0, SCREEN_H * 0.5 + 0.35, 0.2)
	_theater.add_child(bar_frame)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 52, Color(1.0, 0.9, 0.6))
	hud_label.position = Vector3(-2.5, 3.0, -1.0)
	hud_label.pixel_size = 0.006
	add_child(hud_label)
	prompt_label = GraphicsPolish.make_label("", 60, Color(1.0, 1.0, 1.0))
	prompt_label.position = Vector3(0.0, 2.75, -1.8)
	prompt_label.pixel_size = 0.008
	add_child(prompt_label)
	help_label = GraphicsPolish.make_label("", 30, Color(0.8, 0.82, 0.92))
	help_label.position = Vector3(-2.5, 2.72, -1.0)
	help_label.pixel_size = 0.004
	add_child(help_label)


func _update_hud() -> void:
	if hud_label != null:
		hud_label.text = "Applause %d/100" % applause
	if prompt_label != null:
		prompt_label.text = msg
	if help_label != null:
		if ARUpgradeKit.is_xr_active():
			help_label.text = "Pinch = bird (tap to flap) | Hold pinch = dog | Both hands = butterfly"
		else:
			help_label.text = "Move mouse = shadow | Click = bird | Hold = dog | Both buttons = butterfly | R: restart"


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	_update_hud()


func _show_prompt() -> void:
	if prompt_idx >= PROMPTS.size():
		_game_over()
		return
	var p: Dictionary = PROMPTS[prompt_idx]
	_set_msg(str(p["text"]), 999.0)
	var zone: Vector2 = p["zone"]
	target_ring.position = Vector3(zone.x, zone.y, 0.06) # v0.7.0: theater-local
	hold_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pressing = mb.pressed
			if mb.pressed:
				press_t = 0.0
				flapping = true
			else:
				flapping = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			both_press = mb.pressed


func _screen_point() -> Vector2:
	# Desktop: project the mouse ray onto the screen plane.
	if camera == null:
		return Vector2.ZERO
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.z) < 0.0001:
		return shadow_pos
	var t := (_screen_pos().z - origin.z) / dir.z
	if t < 0.0:
		return shadow_pos
	var p: Vector3 = origin + dir * t
	var local: Vector3 = p - _screen_pos()
	return Vector2(clampf(local.x, -SCREEN_W * 0.5, SCREEN_W * 0.5), clampf(local.y, -SCREEN_H * 0.5, SCREEN_H * 0.5))


func _process(delta: float) -> void:
	pulse_t += delta
	if target_mat != null:
		GraphicsPolish.pulse_glow(target_mat, 2.4, 1.0, pulse_t, 3.0)
	if screen_mat != null:
		GraphicsPolish.pulse_glow(screen_mat, 1.1, 0.15, pulse_t, 1.2)
	if msg_t < 900.0 and msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0 and state == "playing":
			_show_prompt()
	if Input.is_key_pressed(KEY_R):
		_restart()
	if state != "playing":
		return
	_determine_puppet(delta)
	_move_puppet(delta)
	_score_prompt(delta)
	_update_hud()


func _determine_puppet(delta: float) -> void:
	var xr := ARUpgradeKit.is_xr_active()
	if xr:
		var pl := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_LEFT)
		var pr := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
		if pl and pr:
			puppet_type = "butterfly"
			flapping = true
		elif pr:
			press_t += delta
			puppet_type = "dog" if press_t > DOG_HOLD_TIME else "bird"
			flapping = ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT) or flapping and press_t < DOG_HOLD_TIME
		else:
			press_t = 0.0
			puppet_type = "bird"
			flapping = false
	else:
		if pressing and both_press:
			puppet_type = "butterfly"
			flapping = true
		elif pressing:
			press_t += delta
			puppet_type = "dog" if press_t > DOG_HOLD_TIME else "bird"
		else:
			press_t = 0.0
			puppet_type = "bird"
	for part in bird_parts:
		part.visible = puppet_type == "bird"
	for part in dog_parts:
		part.visible = puppet_type == "dog"
	for part in fly_parts:
		part.visible = puppet_type == "butterfly"


func _move_puppet(delta: float) -> void:
	var xr := ARUpgradeKit.is_xr_active()
	if xr:
		var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		var rel: Vector3 = pp - _screen_pos()
		shadow_pos = Vector2(clampf(rel.x, -SCREEN_W * 0.5, SCREEN_W * 0.5), clampf(rel.y, -SCREEN_H * 0.5, SCREEN_H * 0.5))
	else:
		shadow_pos = _screen_point()
	var base := _screen_pos() + Vector3(shadow_pos.x, shadow_pos.y, 0.06)
	puppet.position = base
	flap_t += delta * (10.0 if flapping else 3.0)
	var flap := sin(flap_t) * (0.7 if flapping else 0.15)
	if puppet_type == "bird":
		var body: MeshInstance3D = bird_parts[0]
		body.position = Vector3.ZERO
		wing_l.position = Vector3(-0.14, 0.05 + flap * 0.08, 0.0)
		wing_l.rotation.z = 0.5 + flap * 0.5
		wing_r.position = Vector3(0.14, 0.05 + flap * 0.08, 0.0)
		wing_r.rotation.z = -0.5 - flap * 0.5
		var beak: MeshInstance3D = bird_parts[3]
		beak.position = Vector3(0.16, 0.02, 0.0)
	elif puppet_type == "dog":
		var dbody: MeshInstance3D = dog_parts[0]
		dbody.position = Vector3.ZERO
		var ear_l: MeshInstance3D = dog_parts[1]
		ear_l.position = Vector3(-0.12, 0.18, 0.0)
		var ear_r: MeshInstance3D = dog_parts[2]
		ear_r.position = Vector3(0.12, 0.18, 0.0)
		var snout: MeshInstance3D = dog_parts[3]
		snout.position = Vector3(0.14, -0.05, 0.0)
	elif puppet_type == "butterfly":
		var open := 0.5 + flap * 0.6
		fly_wing_l.position = Vector3(-0.12 * open - 0.05, 0.0, 0.0)
		fly_wing_l.rotation.z = 0.4 * open
		fly_wing_r.position = Vector3(0.12 * open + 0.05, 0.0, 0.0)
		fly_wing_r.rotation.z = -0.4 * open
		var fbody: MeshInstance3D = fly_parts[2]
		fbody.position = Vector3.ZERO


func _score_prompt(delta: float) -> void:
	if prompt_idx >= PROMPTS.size():
		return
	var p: Dictionary = PROMPTS[prompt_idx]
	var need: String = str(p["type"])
	var zone: Vector2 = p["zone"]
	if puppet_type == need and shadow_pos.distance_to(zone) < 0.34:
		hold_t += delta
		var need_hold: float = float(p["hold"])
		if hold_t >= need_hold:
			applause = mini(applause + 25, 100)
			GraphicsPolish.spawn_confetti(self, _screen_pos() + Vector3(zone.x, zone.y, 0.4), 40)
			GraphicsPolish.spawn_sparks(self, _screen_pos() + Vector3(zone.x, zone.y, 0.3), Color(1.0, 0.85, 0.3), 16)
			prompt_idx += 1
			_set_msg("Bravo! The audience applauds!", 1.6)
			msg_t = 1.6
			ARUpgradeKit.save_anchor("shadow-puppet_main", global_transform)
			_update_applause_bar()
	else:
		hold_t = maxf(hold_t - delta * 2.0, 0.0)


func _update_applause_bar() -> void:
	if applause_bar != null:
		var frac := float(applause) / 100.0
		applause_bar.scale.x = maxf(frac, 0.01)
		applause_bar.position.x = -1.0 + frac * 1.0 # v0.7.0: theater-local


func _game_over() -> void:
	state = "gameover"
	target_ring.visible = false
	GraphicsPolish.spawn_confetti(self, _screen_pos() + Vector3(0, 0.8, 0.5), 80)
	_set_msg("Curtain call! Final applause: %d/100 — R to play again" % applause, 999.0)
	_update_hud()


func _restart() -> void:
	prompt_idx = 0
	hold_t = 0.0
	applause = 0
	state = "playing"
	target_ring.visible = true
	_update_applause_bar()
	_show_prompt()
	_update_hud()
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
