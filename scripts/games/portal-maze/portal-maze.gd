## Portal Maze: walk-through portal time trial.
## Six glowing portal rings are anchored around the room. In setup, pinch (hold
## left mouse on desktop) near a portal to grab it and drag it to a new spot;
## Space/click starts the run. Then walk (or push your hand ray) through the
## portals in order - the next one pulses bright. The timer starts on the first
## portal and stops on the sixth. Score = total time; best time is persisted.
## R restarts to setup. XR: pinch to nudge portals, body proximity works.
extends Node3D

const PORTAL_COUNT := 6
const RING_RADIUS := 2.2
const RING_Y := 1.4
const TRIGGER_DIST := 0.55
const GRAB_DIST := 0.6

var camera: Camera3D = null
var portals: Array[MeshInstance3D] = []
var portal_mats: Array[StandardMaterial3D] = []
var portal_done: Array[bool] = []
var state := "setup"
var next_idx := 0
var run_time := 0.0
var best_time := -1.0
var grabbed := -1
var hud_label: Label3D = null
var msg_label: Label3D = null
var help_label: Label3D = null
var _pulse_t := 0.0
var _anchor_t := 0.0


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "portal-maze_main")
	_ensure_fallback_camera()
	_ensure_light()
	_ensure_environment()
	_load_best()
	_build_portals()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.4, 0.0), 3.0, 40)


func _process(delta: float) -> void:
	_pulse_t += delta
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("portal-maze_main", global_transform)

	var xr := ARUpgradeKit.is_xr_active()
	var pinch := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)

	if state == "setup":
		if pinch:
			_setup_drag(xr)
		else:
			grabbed = -1
		if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_LEFT):
			_start_run()
	elif state == "playing":
		run_time += delta
		_check_portal_trigger(xr)
	elif state == "win":
		pass

	if Input.is_key_pressed(KEY_R):
		_to_setup()

	_update_pulses()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == "setup":
			_start_run()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and state == "setup":
			_start_run()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_SPACE and state == "setup":
				_start_run()


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.7, 3.4)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	camera.current = true


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.9)


func _ensure_environment() -> void:
	for c in get_children():
		if c is WorldEnvironment:
			return
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.42)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _build_portals() -> void:
	var colors: Array[Color] = [
		Color(0.2, 0.9, 1.0), Color(0.4, 1.0, 0.5), Color(1.0, 0.85, 0.3),
		Color(1.0, 0.5, 0.2), Color(1.0, 0.35, 0.7), Color(0.7, 0.4, 1.0),
	]
	for i in range(PORTAL_COUNT):
		var ang := TAU * float(i) / float(PORTAL_COUNT)
		var inst := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.5
		inst.mesh = torus
		var mat := GraphicsPolish.glow(colors[i], 1.6)
		inst.material_override = mat
		inst.position = Vector3(cos(ang) * RING_RADIUS, RING_Y, sin(ang) * RING_RADIUS)
		inst.look_at(Vector3(0.0, RING_Y, 0.0), Vector3.UP)
		add_child(inst)
		# Number tag above each ring.
		var tag := GraphicsPolish.make_label(str(i + 1), 96, Color.WHITE)
		tag.position = inst.position + Vector3(0.0, 0.85, 0.0)
		add_child(tag)
		# Faint disc showing the trigger plane.
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.height = 0.02
		disc.mesh = cyl
		var dmat := GraphicsPolish.glow(colors[i], 0.35)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.albedo_color = Color(colors[i].r, colors[i].g, colors[i].b, 0.25)
		disc.material_override = dmat
		inst.add_child(disc)
		portals.append(inst)
		portal_mats.append(mat)
		portal_done.append(false)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.5))
	hud_label.position = Vector3(-2.4, 2.6, 0.6)
	hud_label.pixel_size = 0.008
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.5, 1.0, 0.9))
	msg_label.position = Vector3(0.0, 2.3, -1.0)
	add_child(msg_label)
	help_label = GraphicsPolish.make_label("", 36, Color(0.75, 0.8, 0.9))
	help_label.position = Vector3(0.0, 0.5, 1.2)
	help_label.pixel_size = 0.004
	add_child(help_label)
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	var best_txt := "--" if best_time < 0.0 else _fmt_time(best_time)
	match state:
		"setup":
			hud_label.text = "PORTAL MAZE - setup"
			if help_label != null:
				help_label.text = "Hold LMB / pinch near a ring to drag it | Space / click to start | R: reset"
			if msg_label != null:
				msg_label.text = "Arrange the portals, then start!"
		"playing":
			hud_label.text = "Portal %d/%d   %s   Best: %s" % [next_idx + 1, PORTAL_COUNT, _fmt_time(run_time), best_txt]
			if help_label != null:
				help_label.text = "Walk or push your hand through portal %d | R: restart" % (next_idx + 1)
			if msg_label != null:
				msg_label.text = ""
		"win":
			hud_label.text = "FINISHED! %s   Best: %s" % [_fmt_time(run_time), best_txt]
			if help_label != null:
				help_label.text = "R: run again | Space: back to setup"
			if msg_label != null:
				msg_label.text = "TIME TRIAL COMPLETE!"


func _fmt_time(t: float) -> String:
	var mins := int(t) / 60
	var secs := t - float(mins * 60)
	return "%d:%05.2f" % [mins, secs]


func _setup_drag(xr: bool) -> void:
	var hand_pos := _pointer_pos(xr)
	if grabbed < 0:
		# Grab the nearest portal within reach.
		var best := -1
		var best_d := GRAB_DIST
		for i in range(portals.size()):
			var d := portals[i].global_position.distance_to(hand_pos)
			if d < best_d:
				best_d = d
				best = i
		grabbed = best
	if grabbed >= 0:
		var p: Vector3 = ARUpgradeKit.clamp_to_room(hand_pos, 0.4)
		p.y = clampf(p.y, 0.8, 2.2)
		portals[grabbed].global_position = p
		portals[grabbed].look_at(Vector3(0.0, RING_Y, 0.0), Vector3.UP)


func _pointer_pos(xr: bool) -> Vector3:
	if xr:
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 2.2)
	if camera == null:
		return global_position + Vector3(0.0, 1.2, -1.0)
	var mp := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return origin + dir * 2.0
	var t := (RING_Y - origin.y) / dir.y
	return origin + dir * maxf(t, 0.0)


func _start_run() -> void:
	if state != "setup":
		return
	state = "playing"
	next_idx = 0
	run_time = 0.0
	for i in range(PORTAL_COUNT):
		portal_done[i] = false
	grabbed = -1
	ARUpgradeKit.save_anchor("portal-maze_main", global_transform)
	if msg_label != null:
		msg_label.text = "GO!"
	_update_hud()


func _to_setup() -> void:
	state = "setup"
	next_idx = 0
	run_time = 0.0
	grabbed = -1
	for i in range(PORTAL_COUNT):
		portal_done[i] = false
	_update_hud()


func _check_portal_trigger(xr: bool) -> void:
	if next_idx >= PORTAL_COUNT:
		return
	var portal := portals[next_idx]
	var center := portal.global_position
	var hit := false
	# Body proximity: the headset/camera passes through the ring.
	if camera != null and camera.global_position.distance_to(center) < TRIGGER_DIST:
		hit = true
	# Hand ray: the pointer ray crosses the ring disc.
	if not hit:
		var ray: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
		var origin: Vector3 = ray[0]
		var dir: Vector3 = ray[1]
		var normal: Vector3 = (portal.global_transform.basis * Vector3(0, 0, 1)).normalized()
		var denom := dir.dot(normal)
		if absf(denom) > 0.0001:
			var t := (center - origin).dot(normal) / denom
			if t > 0.0:
				var p: Vector3 = origin + dir * t
				if p.distance_to(center) < TRIGGER_DIST:
					hit = true
	if hit:
		_activate_portal(next_idx)


func _activate_portal(i: int) -> void:
	portal_done[i] = true
	GraphicsPolish.spawn_sparks(self, portals[i].global_position, Color(0.5, 1.0, 0.9), 30)
	if i == 0:
		run_time = 0.0
	next_idx += 1
	if next_idx >= PORTAL_COUNT:
		state = "win"
		var new_best := false
		if best_time < 0.0 or run_time < best_time:
			best_time = run_time
			new_best = true
			_save_best()
		ARUpgradeKit.save_anchor("portal-maze_main", global_transform)
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.6, 0.0), 80)
		if msg_label != null:
			msg_label.text = "NEW BEST TIME!" if new_best else "FINISHED!"
	_update_hud()


func _update_pulses() -> void:
	for i in range(PORTAL_COUNT):
		var mat := portal_mats[i]
		if state == "playing" and i == next_idx:
			GraphicsPolish.pulse_glow(mat, 1.8, 1.6, _pulse_t, 3.0)
		elif state == "playing" and i < next_idx:
			mat.emission_energy_multiplier = 0.5
		elif state == "setup":
			GraphicsPolish.pulse_glow(mat, 1.0, 0.7, _pulse_t + float(i), 2.0)
		else:
			mat.emission_energy_multiplier = 1.6


func _best_path() -> String:
	return "user://portal-maze_best.txt"


func _load_best() -> void:
	if not FileAccess.file_exists(_best_path()):
		return
	var f := FileAccess.open(_best_path(), FileAccess.READ)
	if f != null:
		best_time = f.get_float()
		f.close()


func _save_best() -> void:
	var f := FileAccess.open(_best_path(), FileAccess.WRITE)
	if f != null:
		f.store_float(best_time)
		f.close()
