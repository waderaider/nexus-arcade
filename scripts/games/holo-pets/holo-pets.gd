## holo-pets.gd -- NEXUS ARCADE: virtual pet in your room.
## A cute procedural creature with decaying stats (Hunger/Happiness/Energy).
## Click the pet to pet it, the food bowl to feed, the toy ball to play.
## The pet hops, wanders, chases the ball, and droops its ears when sad.
## Press R to reset.
extends Node3D
class_name HoloPetsGame

const WANDER_RADIUS := 2.4
const BAR_LEN := 15


class Picker:
	static func ray(cam: Camera3D, screen_pos: Vector2) -> Array:
		return [cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)]

	static func sphere_hit(o: Vector3, d: Vector3, c: Vector3, r: float) -> bool:
		var oc: Vector3 = o - c
		var b: float = oc.dot(d)
		var cc: float = oc.dot(oc) - r * r
		var disc: float = b * b - cc
		if disc <= 0.0:
			return false
		return (-b - sqrt(disc)) > 0.0


var cam: Camera3D = null
var _time := 0.0
var _prev_keys := {}
var _anchor_timer := 0.0
var _click_consumed := false

# Pet parts.
var pet_root: Node3D = null
var body: MeshInstance3D = null
var ear_l: MeshInstance3D = null
var ear_r: MeshInstance3D = null
var body_mat: StandardMaterial3D = null

# Stats 0..100.
var hunger := 100.0
var happiness := 100.0
var energy := 100.0

# Behaviour state.
var wander_target := Vector3.ZERO
var wander_idle := 0.0
var hop_phase := 0.0
var moving := false
var chasing := false
var wiggle_t := 0.0
var ear_droop := 0.0
var feed_flash_t := 0.0
# RoomKit (v0.7.0): couch-nap state.
var _napping := false
var _nap_y := 0.0

# Props.
var bowl: MeshInstance3D = null
var bowl_mat: StandardMaterial3D = null
var bowl_pos := Vector3(1.6, 0.0, 0.7)
var ball: MeshInstance3D = null
var ball_pos := Vector3(-1.5, 0.12, 0.9)
var ball_vel := Vector3.ZERO
var ball_active := false

# UI.
var stats_label: Label3D = null
var mood_label: Label3D = null
var help_label: Label3D = null
var name_label: Label3D = null


func _ready() -> void:
	_add_light_rig()
	_build_environment()
	_build_pet()
	_build_props()
	_build_ui()
	ARUpgradeKit.apply_anchor(pet_root, "holo-pets_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.0, 0.0), 2.5)
	RoomKit.refresh() # v0.7.0: cache room layout for hiding spots (safe no-op w/o XR).
	_apply_room_layout() # v0.7.0 MORPH-B: morph the pet's couch den.
	_pick_wander_target()


func _add_light_rig() -> void:
	# Three-point light rig; skipped if a directional light already exists.
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 2.6, 4.8)
		add_child(cam)
		cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)

	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.45, 0.60)
	env.ambient_light_energy = 0.7
	amb.environment = env
	add_child(amb)

	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(8.0, 0.1, 8.0)
	floor_mi.mesh = fb
	var fmat := GraphicsPolish.pbr_preset(Color(0.12, 0.14, 0.24), "matte")
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0.0, -0.05, 0.0)
	add_child(floor_mi)


func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := GraphicsPolish.pbr(color, 0.15, 0.45)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_pet() -> void:
	pet_root = Node3D.new()
	pet_root.position = Vector3(0.0, 0.0, -0.5)
	add_child(pet_root)

	# Body.
	var bs := SphereMesh.new()
	bs.radius = 0.25
	bs.height = 0.5
	body_mat = GraphicsPolish.pbr_preset(Color(0.55, 0.85, 1.0), "plastic")
	body = MeshInstance3D.new()
	body.mesh = bs
	body.material_override = body_mat
	body.position = Vector3(0.0, 0.35, 0.0)
	pet_root.add_child(body)

	# Eyes (two small dark spheres, facing +Z toward the camera).
	var es := SphereMesh.new()
	es.radius = 0.05
	es.height = 0.1
	_part(es, Color(0.08, 0.08, 0.10), Vector3(-0.10, 0.42, 0.20), pet_root)
	_part(es, Color(0.08, 0.08, 0.10), Vector3(0.10, 0.42, 0.20), pet_root)
	# Eye glints.
	var gs := SphereMesh.new()
	gs.radius = 0.016
	gs.height = 0.032
	_part(gs, Color(1, 1, 1), Vector3(-0.085, 0.435, 0.245), pet_root)
	_part(gs, Color(1, 1, 1), Vector3(0.115, 0.435, 0.245), pet_root)

	# Ears (cones via CylinderMesh with zero top radius).
	var em := CylinderMesh.new()
	em.top_radius = 0.015
	em.bottom_radius = 0.09
	em.height = 0.24
	ear_l = _part(em, Color(0.45, 0.75, 0.95), Vector3(-0.15, 0.66, 0.0), pet_root)
	ear_r = _part(em, Color(0.45, 0.75, 0.95), Vector3(0.15, 0.66, 0.0), pet_root)
	ear_l.rotation.z = 0.15
	ear_r.rotation.z = -0.15

	# Feet.
	var fs := SphereMesh.new()
	fs.radius = 0.07
	fs.height = 0.14
	_part(fs, Color(0.35, 0.60, 0.80), Vector3(-0.13, 0.07, 0.12), pet_root)
	_part(fs, Color(0.35, 0.60, 0.80), Vector3(0.13, 0.07, 0.12), pet_root)
	_part(fs, Color(0.35, 0.60, 0.80), Vector3(-0.13, 0.07, -0.12), pet_root)
	_part(fs, Color(0.35, 0.60, 0.80), Vector3(0.13, 0.07, -0.12), pet_root)

	name_label = GraphicsPolish.make_label("Wisp", 72, Color(0.75, 0.92, 1.0))
	name_label.position = Vector3(0.0, 1.05, 0.0)
	pet_root.add_child(name_label)


func _build_props() -> void:
	# Food bowl: torus on the floor with kibble bits.
	var tm := TorusMesh.new()
	tm.inner_radius = 0.14
	tm.outer_radius = 0.24
	bowl_mat = GraphicsPolish.pbr_preset(Color(0.95, 0.45, 0.20), "plastic")
	bowl = MeshInstance3D.new()
	bowl.mesh = tm
	bowl.material_override = bowl_mat
	bowl.position = bowl_pos + Vector3(0.0, 0.06, 0.0)
	add_child(bowl)
	var ks := SphereMesh.new()
	ks.radius = 0.035
	ks.height = 0.07
	for i in 4:
		var a := float(i) / 4.0 * TAU
		_part(ks, Color(0.55, 0.35, 0.18), bowl_pos + Vector3(cos(a) * 0.08, 0.06, sin(a) * 0.08), self)

	var bl := Label3D.new()
	bl.text = "FOOD"
	bl.position = bowl_pos + Vector3(0.0, 0.55, 0.0)
	bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bl.pixel_size = 0.006
	bl.modulate = Color(1.0, 0.75, 0.5)
	bl.outline_size = 8
	add_child(bl)

	# Toy ball.
	var bm := SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	ball = _part(bm, Color(1.0, 0.85, 0.25), ball_pos, self)
	ball.add_child(GraphicsPolish.make_trail(Color(1.0, 0.85, 0.25)))
	var tl := Label3D.new()
	tl.text = "TOY"
	tl.position = Vector3(-1.5, 0.55, 0.9)
	tl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tl.pixel_size = 0.006
	tl.modulate = Color(1.0, 0.9, 0.5)
	tl.outline_size = 8
	add_child(tl)


func _make_label(text: String, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 12
	add_child(l)
	return l


func _build_ui() -> void:
	stats_label = _make_label("", Vector3(-3.4, 2.7, -1.0), Color(0.85, 0.95, 1.0))
	mood_label = _make_label("", Vector3(-3.4, 1.9, -1.0), Color(0.5, 1.0, 0.6))
	help_label = _make_label(
		"Click Wisp: pet (+Happiness)\nClick FOOD bowl: feed (+Hunger)\nClick TOY ball: play (+Energy)\nR: reset",
		Vector3(3.4, 2.7, -1.0), Color(0.65, 0.75, 0.9))


func _process(delta: float) -> void:
	_time += delta
	_poll_keys()
	_poll_pinch()
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		_save_anchor()

	# Stat decay.
	hunger = maxf(0.0, hunger - 0.8 * delta)
	happiness = maxf(0.0, happiness - 0.6 * delta)
	energy = maxf(0.0, energy - 0.4 * delta)

	_update_behaviour(delta)
	_update_ball(delta)
	_update_ui()


func _poll_keys() -> void:
	var down := Input.is_key_pressed(KEY_R)
	var was: bool = _prev_keys.get(KEY_R, false)
	if down and not was:
		_reset()
	_prev_keys[KEY_R] = down


func _pick_wander_target() -> void:
	var a := randf() * TAU
	var r := randf_range(0.6, WANDER_RADIUS)
	wander_target = ARUpgradeKit.clamp_to_room(Vector3(cos(a) * r, 0.0, sin(a) * r))
	# RoomKit (v0.7.0): sometimes the pet hides behind real furniture instead.
	if RoomKit.is_available() and RoomKit.has_room_data() and randf() < 0.35:
		var spot := _furniture_hiding_spot()
		if spot != Vector3.INF:
			wander_target = ARUpgradeKit.clamp_to_room(spot)
	# RoomKit (v0.7.0): sometimes the pet naps on the real couch.
	_napping = false
	if RoomKit.is_available() and RoomKit.has_room_data() and randf() < 0.15:
		var couch := RoomKit.get_couch()
		if not couch.is_empty():
			var top := to_local(RoomKit.cuboid_top(couch))
			wander_target = Vector3(top.x, 0.0, top.z)
			_nap_y = top.y
			_napping = true
			wander_idle = randf_range(4.0, 7.0)
			return
	wander_idle = randf_range(1.0, 3.5)


## RoomKit (v0.7.0): a floor spot just outside a random table/furniture
## cuboid (world -> game-local), or Vector3.INF when none is usable.
func _furniture_hiding_spot() -> Vector3:
	var items: Array = RoomKit.get_furniture() + RoomKit.get_tables()
	if items.is_empty():
		return Vector3.INF
	var f: Dictionary = items[randi() % items.size()]
	var wp: Vector3 = f["position"]
	var fs: Vector3 = f["size"]
	var rc := RoomKit.room_bounds().get_center()
	var away := Vector2(wp.x - rc.x, wp.z - rc.y)
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var clearance := maxf(fs.x, fs.z) * 0.5 + 0.35
	var spot := to_local(Vector3(wp.x + away.x * clearance, 0.0, wp.z + away.y * clearance))
	spot.y = 0.0
	return spot


func _update_behaviour(delta: float) -> void:
	var speed := 0.85
	if chasing:
		wander_target = Vector3(ball.position.x, 0.0, ball.position.z)
		speed = 1.7

	var to: Vector3 = wander_target - pet_root.position
	to.y = 0.0
	var dist := to.length()

	if dist > 0.25:
		moving = true
		var dir := to / dist
		pet_root.position += dir * speed * delta
		# Face travel direction (+Z is the face).
		var yaw := atan2(dir.x, dir.z)
		pet_root.rotation.y = lerp_angle(pet_root.rotation.y, yaw, minf(1.0, 8.0 * delta))
		hop_phase += delta * 11.0
		pet_root.position.y = absf(sin(hop_phase)) * 0.16
	else:
		moving = false
		# RoomKit (v0.7.0): rest on the couch top while napping, floor otherwise.
		var rest_y := _nap_y if _napping else 0.0
		pet_root.position.y = lerpf(pet_root.position.y, rest_y, minf(1.0, 8.0 * delta))
		# Curl up while napping.
		var target_squash := 0.72 if _napping else 1.0
		pet_root.scale.y = lerpf(pet_root.scale.y, target_squash, minf(1.0, 6.0 * delta))
		if not chasing:
			wander_idle -= delta
			if wander_idle <= 0.0:
				_napping = false
				pet_root.scale.y = 1.0
				_pick_wander_target()

	# Happy wiggle after being petted.
	if wiggle_t > 0.0:
		wiggle_t -= delta
		pet_root.rotation.z = sin(_time * 28.0) * 0.18 * maxf(0.0, wiggle_t)
	else:
		pet_root.rotation.z = 0.0

	# Ear droop: sad when any stat hits 0.
	var sad := hunger <= 0.0 or happiness <= 0.0 or energy <= 0.0
	ear_droop = lerpf(ear_droop, 1.0 if sad else 0.0, minf(1.0, 4.0 * delta))
	ear_l.rotation.z = lerpf(0.15, 0.95, ear_droop)
	ear_r.rotation.z = lerpf(-0.15, -0.95, ear_droop)
	body_mat.albedo_color = Color(0.55, 0.85, 1.0).lerp(Color(0.45, 0.55, 0.65), ear_droop)

	# Feed flash on the bowl.
	if feed_flash_t > 0.0:
		feed_flash_t -= delta
		var s := 1.0 + 0.5 * maxf(0.0, feed_flash_t)
		bowl.scale = Vector3(s, s, s)
	else:
		bowl.scale = Vector3.ONE


func _update_ball(delta: float) -> void:
	if not ball_active:
		return
	ball_vel.y -= 9.8 * delta
	ball.position += ball_vel * delta
	if ball.position.y < 0.12:
		ball.position.y = 0.12
		if absf(ball_vel.y) > 0.8:
			ball_vel.y = -ball_vel.y * 0.55
			ball_vel.x *= 0.75
			ball_vel.z *= 0.75
		else:
			ball_vel = Vector3.ZERO
			ball_active = false
			chasing = false
			wander_idle = 1.0


func _mood() -> Array:
	if hunger <= 0.0 or happiness <= 0.0 or energy <= 0.0:
		return ["Sad", Color(1.0, 0.45, 0.45)]
	if energy < 25.0:
		return ["Sleepy", Color(0.55, 0.65, 1.0)]
	if hunger < 30.0:
		return ["Hungry", Color(1.0, 0.70, 0.35)]
	if happiness > 70.0 and energy > 70.0:
		return ["Playful", Color(0.55, 1.0, 0.85)]
	if happiness < 40.0:
		return ["Bored", Color(0.85, 0.85, 0.60)]
	return ["Happy", Color(0.50, 1.0, 0.60)]


func _bar(v: float) -> String:
	var filled := int(round(v / 100.0 * float(BAR_LEN)))
	return "[" + "#".repeat(filled) + "-".repeat(BAR_LEN - filled) + "]"


func _update_ui() -> void:
	stats_label.text = "HOLO-PET: Wisp\nHunger    %s %3d\nHappiness %s %3d\nEnergy    %s %3d" % [
		_bar(hunger), int(hunger),
		_bar(happiness), int(happiness),
		_bar(energy), int(energy),
	]
	var m: Array = _mood()
	mood_label.text = "Mood: " + m[0]
	mood_label.modulate = m[1]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click_consumed = true
			_handle_click(mb.position)


func _handle_click(screen_pos: Vector2) -> void:
	if cam == null:
		return
	var r: Array = Picker.ray(cam, screen_pos)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]

	# Toy ball first (smallest target).
	if Picker.sphere_hit(o, d, ball.position, 0.30):
		_throw_ball()
		return
	# Food bowl.
	if Picker.sphere_hit(o, d, bowl.position, 0.50):
		_feed()
		return
	# The pet.
	if Picker.sphere_hit(o, d, pet_root.position + Vector3(0.0, 0.35, 0.0), 0.50):
		_pet()


func _pet() -> void:
	happiness = minf(100.0, happiness + 15.0)
	wiggle_t = 0.6
	GraphicsPolish.spawn_sparks(pet_root, Vector3(0.0, 0.6, 0.0), Color(1.0, 0.85, 0.4), 20)


func _feed() -> void:
	hunger = minf(100.0, hunger + 20.0)
	feed_flash_t = 0.6
	GraphicsPolish.spawn_sparks(self, bowl_pos + Vector3(0.0, 0.3, 0.0), Color(0.6, 1.0, 0.5), 16)


func _throw_ball() -> void:
	energy = minf(100.0, energy + 10.0)
	ball_active = true
	chasing = true
	# Woken up by playtime: no more couch nap.
	_napping = false
	pet_root.scale.y = 1.0
	ball_vel = Vector3(randf_range(-1.6, 1.6), randf_range(2.8, 3.6), randf_range(-1.6, 1.6))


func _reset() -> void:
	hunger = 100.0
	happiness = 100.0
	energy = 100.0
	pet_root.position = Vector3(0.0, 0.0, -0.5)
	ball.position = ball_pos
	ball_vel = Vector3.ZERO
	ball_active = false
	chasing = false
	wiggle_t = 0.0
	_save_anchor()
	_pick_wander_target()


func _pinch_active() -> bool:
	# XR hand-tracking pinch (mouse fallback keeps desktop working).
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)


func _poll_pinch() -> void:
	# Pinch is an alternative to the mouse click; consume one trigger per press.
	var pinched := ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT)
	if _click_consumed:
		_click_consumed = false
		return
	if pinched and cam != null:
		var wp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
		_handle_click(cam.unproject_position(wp))


func _save_anchor() -> void:
	if pet_root != null:
		ARUpgradeKit.save_anchor("holo-pets_main", pet_root.global_transform)


## MORPH-B (v0.7.0): the real couch is the pet's home den (it already naps
## there in _pick_wander_target) - morph it with a nature skin so the nap
## spot glows as a cozy nest. Silent no-op without a couch anchor.
func _apply_room_layout() -> void:
	if not RoomKit.is_available() or not RoomKit.has_room_data():
		return
	var couch := RoomKit.get_couch()
	if not couch.is_empty():
		RoomKit.morph(couch, "nature")
