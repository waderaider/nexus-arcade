## Drone Racer: hand-guided drone racing through checkpoint rings.
## A glowing quadcopter follows your pointer hand (XR) or your mouse (desktop,
## projected onto a flight plane). Fly it through 8 pulsing checkpoint rings in
## order, 3 laps against the clock. Pinch (hold left mouse on desktop) for a
## boost with spark juice. Score = total race time; best lap time is persisted.
## The drone leaves a glowing trail; the next ring pulses bright. R restarts.
extends Node3D

const RING_COUNT := 8
const RING_Y := 1.35
const RING_TRACK_R := 2.4
const CHECK_DIST := 0.6
const DRONE_SPEED := 3.2
const BOOST_MULT := 2.1
const LAPS := 3
const FLIGHT_Y := 1.35

var camera: Camera3D = null
var drone: Node3D = null
var rotors: Array[MeshInstance3D] = []
var drone_light: OmniLight3D = null
var rings: Array[MeshInstance3D] = []
var ring_mats: Array[StandardMaterial3D] = []
var state := "playing"
var next_ring := 0
var lap := 1
var race_time := 0.0
var lap_start := 0.0
var lap_times: Array[float] = []
var best_lap := -1.0
var drone_vel := Vector3.ZERO
var hud_label: Label3D = null
var msg_label: Label3D = null
var _pulse_t := 0.0
var _anchor_t := 0.0
var _rotor_t := 0.0
var mouse_pos := Vector2.ZERO


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "drone-racer_main")
	_ensure_fallback_camera()
	_ensure_light()
	_ensure_environment()
	_load_best()
	_build_rings()
	_build_drone()
	_build_hud()
	_reset_race()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.35, 0.0), 3.2, 40)


func _process(delta: float) -> void:
	_pulse_t += delta
	_anchor_t += delta
	_rotor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("drone-racer_main", global_transform)

	var xr := ARUpgradeKit.is_xr_active()
	var boost := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)

	if state == "playing":
		race_time += delta
		_fly_drone(delta, xr, boost)
		_check_checkpoint()

	_spin_rotors(delta, boost)
	_update_pulses()
	_update_hud()

	if Input.is_key_pressed(KEY_R):
		_reset_race()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 2.6, 4.6)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
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
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.25, 0.42)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _build_rings() -> void:
	var colors: Array[Color] = [
		Color(0.2, 0.9, 1.0), Color(0.3, 1.0, 0.6), Color(1.0, 0.9, 0.3),
		Color(1.0, 0.6, 0.2), Color(1.0, 0.35, 0.6), Color(0.8, 0.4, 1.0),
		Color(0.4, 0.6, 1.0), Color(0.5, 1.0, 0.9),
	]
	for i in range(RING_COUNT):
		var ang := TAU * float(i) / float(RING_COUNT)
		var inst := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.55
		inst.mesh = torus
		var mat := GraphicsPolish.glow(colors[i], 1.4)
		inst.material_override = mat
		var y := RING_Y + sin(ang * 2.0) * 0.25
		inst.position = Vector3(cos(ang) * RING_TRACK_R, y, sin(ang) * RING_TRACK_R)
		add_child(inst)
		inst.look_at(Vector3(0.0, y, 0.0), Vector3.UP)
		var tag := GraphicsPolish.make_label(str(i + 1), 96, Color.WHITE)
		tag.position = inst.position + Vector3(0.0, 0.9, 0.0)
		add_child(tag)
		rings.append(inst)
		ring_mats.append(mat)


func _build_drone() -> void:
	drone = Node3D.new()
	drone.position = Vector3(0.0, FLIGHT_Y, 1.6)
	add_child(drone)
	# Body.
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.12, 0.34)
	body.mesh = box
	body.material_override = GraphicsPolish.glow(Color(0.2, 0.7, 1.0), 1.6)
	drone.add_child(body)
	# Eye light on the front.
	drone_light = GraphicsPolish.make_point_light(drone, Vector3(0, 0.1, 0), Color(0.3, 0.8, 1.0), 1.2, 3.0)
	# Four spinning rotors on arms.
	var arm_offsets: Array[Vector3] = [
		Vector3(0.24, 0.08, 0.24), Vector3(-0.24, 0.08, 0.24),
		Vector3(0.24, 0.08, -0.24), Vector3(-0.24, 0.08, -0.24),
	]
	for off in arm_offsets:
		var rotor := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.14
		disc.bottom_radius = 0.14
		disc.height = 0.02
		rotor.mesh = disc
		rotor.material_override = GraphicsPolish.glow(Color(0.7, 0.95, 1.0), 0.8)
		rotor.position = off
		drone.add_child(rotor)
		rotors.append(rotor)
	# Glowing trail.
	drone.add_child(GraphicsPolish.make_trail(Color(0.3, 0.8, 1.0), 0.06))


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.9, 0.5))
	hud_label.position = Vector3(-2.4, 2.7, 1.2)
	hud_label.pixel_size = 0.008
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(0.5, 1.0, 0.85))
	msg_label.position = Vector3(0.0, 2.2, -1.2)
	add_child(msg_label)
	var help := GraphicsPolish.make_label("Move mouse / hand to steer | Hold LMB / pinch: boost | Fly through glowing rings | R: restart", 36, Color(0.75, 0.8, 0.9))
	help.position = Vector3(0.0, 0.45, 2.0)
	help.pixel_size = 0.004
	add_child(help)
	_update_hud()


func _update_hud() -> void:
	if hud_label == null:
		return
	var best_txt := "--" if best_lap < 0.0 else _fmt_time(best_lap)
	if state == "playing":
		hud_label.text = "Lap %d/%d   %s   Best lap: %s" % [lap, LAPS, _fmt_time(race_time), best_txt]
	elif state == "win":
		hud_label.text = "RACE DONE! %s   Best lap: %s" % [_fmt_time(race_time), best_txt]
	if msg_label != null and state == "playing":
		msg_label.text = "Ring %d/%d" % [next_ring + 1, RING_COUNT]


func _fmt_time(t: float) -> String:
	var mins := int(t) / 60
	var secs := t - float(mins * 60)
	return "%d:%05.2f" % [mins, secs]


func _reset_race() -> void:
	state = "playing"
	next_ring = 0
	lap = 1
	race_time = 0.0
	lap_start = 0.0
	lap_times.clear()
	drone_vel = Vector3.ZERO
	if drone != null:
		drone.position = Vector3(0.0, FLIGHT_Y, 1.6)
	_update_hud()


func _target_point(xr: bool) -> Vector3:
	if xr:
		return ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 2.0)
	if camera == null:
		return drone.global_position
	var origin := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return drone.global_position
	var t := (FLIGHT_Y - origin.y) / dir.y
	var p: Vector3 = origin + dir * maxf(t, 0.0)
	return ARUpgradeKit.clamp_to_room(p, 0.4)


func _fly_drone(delta: float, xr: bool, boost: bool) -> void:
	var target := _target_point(xr)
	var to_target: Vector3 = target - drone.global_position
	var speed := DRONE_SPEED * (BOOST_MULT if boost else 1.0)
	var desired := to_target.normalized() * minf(to_target.length() * 4.0, speed) if to_target.length() > 0.05 else Vector3.ZERO
	drone_vel = drone_vel.lerp(desired, clampf(6.0 * delta, 0.0, 1.0))
	drone.global_position += drone_vel * delta
	drone.global_position.y = clampf(drone.global_position.y, 0.5, 2.4)
	# Bank toward movement.
	if drone_vel.length() > 0.3:
		var fwd := drone_vel.normalized()
		var yaw := atan2(-fwd.x, -fwd.z)
		drone.rotation.y = lerp_angle(drone.rotation.y, yaw, clampf(5.0 * delta, 0.0, 1.0))
		drone.rotation.z = lerp_angle(drone.rotation.z, clampf(-drone_vel.x * 0.08, -0.4, 0.4), clampf(5.0 * delta, 0.0, 1.0))
	if boost:
		GraphicsPolish.spawn_sparks(self, drone.global_position, Color(0.4, 0.9, 1.0), 3)
		if drone_light != null:
			drone_light.light_energy = 2.5
	elif drone_light != null:
		drone_light.light_energy = 1.2


func _spin_rotors(delta: float, boost: bool) -> void:
	var spin := 22.0 * (1.8 if boost else 1.0)
	for r in rotors:
		r.rotation.y += spin * delta


func _check_checkpoint() -> void:
	if next_ring >= RING_COUNT:
		return
	var ring := rings[next_ring]
	if drone.global_position.distance_to(ring.global_position) < CHECK_DIST:
		GraphicsPolish.spawn_sparks(self, ring.global_position, Color(0.6, 1.0, 0.9), 26)
		next_ring += 1
		if next_ring >= RING_COUNT:
			_finish_lap()


func _finish_lap() -> void:
	var lap_time := race_time - lap_start
	lap_times.append(lap_time)
	var new_best := false
	if best_lap < 0.0 or lap_time < best_lap:
		best_lap = lap_time
		new_best = true
		_save_best()
	if lap >= LAPS:
		state = "win"
		ARUpgradeKit.save_anchor("drone-racer_main", global_transform)
		GraphicsPolish.spawn_confetti(self, Vector3(0.0, 1.8, 0.0), 80)
		if msg_label != null:
			msg_label.text = "RACE COMPLETE!" + (" NEW BEST LAP!" if new_best else "")
	else:
		lap += 1
		lap_start = race_time
		next_ring = 0
		if msg_label != null:
			msg_label.text = "LAP %d!" % lap
	_update_hud()


func _update_pulses() -> void:
	for i in range(RING_COUNT):
		var mat := ring_mats[i]
		if state == "playing" and i == next_ring:
			GraphicsPolish.pulse_glow(mat, 1.8, 1.6, _pulse_t, 3.5)
		elif state == "playing" and i < next_ring and lap == LAPS:
			mat.emission_energy_multiplier = 0.6
		else:
			mat.emission_energy_multiplier = 1.4


func _best_path() -> String:
	return "user://drone-racer_best.txt"


func _load_best() -> void:
	if not FileAccess.file_exists(_best_path()):
		return
	var f := FileAccess.open(_best_path(), FileAccess.READ)
	if f != null:
		best_lap = f.get_float()
		f.close()


func _save_best() -> void:
	var f := FileAccess.open(_best_path(), FileAccess.WRITE)
	if f != null:
		f.store_float(best_lap)
		f.close()
