## MinigolfBall.gd - AAA minigolf ball with custom integrator.
## Built for NEXUS GREENS (flagship). Lessons from Gravity Golf's GolfBall:
## custom integrator beats RigidBody for minigolf (deterministic lip-outs,
## funnel assist, per-surface friction, zero tunneling).
##
## Feel spec (Game Designer §3, non-negotiable):
## - Rolling friction per surface; slope gravity from surface normal.
## - Lip-outs: rim collision with restitution above ~1.6 m/s rim speed.
## - Cup capture: 6cm funnel assist below speed threshold.
## - Ball never floats: continuous ground-contact check.
## - Signals drive juice/audio/haptics with zero frame delay.
extends Node3D
class_name MinigolfBall

signal holed
signal bounced(strength: float, surface: String)
signal rim_out
signal hazard_drop(kind: String)
signal speed_changed(speed: float)

const GRAVITY := 9.81
const RESTITUTION_RAIL := 0.72
const RESTITUTION_RIM := 0.55
const LIP_OUT_SPEED := 1.6      # above this rim speed, ball can lip out
const CAPTURE_SPEED := 1.4      # must be slower than this to drop
const FUNNEL_RADIUS := 0.06     # cup capture assist radius (m)
const STOP_EPSILON := 0.05

# Per-surface rolling friction (velocity retained per second).
const FRICTION := {
	"felt": 0.55,
	"wood": 0.32,
	"brass": 0.22,
	"sand": 1.6,
	"stone": 0.45,
	"rope": 0.5,
}

var velocity := Vector3.ZERO
var is_holed := false
var is_in_play := false
var current_surface := "felt"

var _hole: MinigolfHole = null
var _radius := 0.02135  # real golf ball
var _last_speed := -1.0

@onready var _mesh: MeshInstance3D = $BallMesh


func configure(hole: MinigolfHole) -> void:
	_hole = hole
	is_holed = false
	is_in_play = false
	velocity = Vector3.ZERO
	reset_to_tee()


func launch(vel: Vector3) -> void:
	velocity = vel
	is_in_play = true


func reset_to_tee() -> void:
	if _hole == null:
		return
	is_holed = false
	is_in_play = false
	velocity = Vector3.ZERO
	global_position = _hole.tee_position()


func drop_at(pos: Vector3) -> void:
	is_holed = false
	velocity = Vector3.ZERO
	global_position = pos
	is_in_play = true


func _physics_process(delta: float) -> void:
	if _hole == null or is_holed or not is_in_play:
		return

	var pos := global_position
	var vel := velocity

	# Gravity (for slopes, ramps, airborne moments).
	vel.y -= GRAVITY * delta

	# Wind zones push the ball (Sky Reef).
	vel += _hole.wind_at(pos) * delta

	# Cup-vacuum power-up: 3s gentle suction within 1.5m (respects lip-out —
	# the speed threshold in _check_cup_capture still applies).
	if has_meta("vacuum_time") and float(get_meta("vacuum_time")) > 0.0:
		set_meta("vacuum_time", float(get_meta("vacuum_time")) - delta)
		var to_cup: Vector3 = _hole.cup_position() - pos
		to_cup.y = 0.0
		var cup_dist: float = to_cup.length()
		if cup_dist < 1.5 and cup_dist > 0.05:
			vel += to_cup.normalized() * 0.9 * delta

	# Integrate.
	pos += vel * delta

	# Ground contact: sample the hole's heightfield.
	var ground := _hole.ground_at(pos)
	if ground.hit:
		current_surface = ground.surface
		var rest_y: float = ground.height + _radius
		if pos.y <= rest_y:
			pos.y = rest_y
			if vel.y < -0.9:
				# Hard landing bounce.
				bounced.emit(-vel.y, current_surface)
				vel.y = -vel.y * 0.35
			elif vel.y < 0.0:
				vel.y = 0.0
			# Slope gravity: accelerate along the surface tangent.
			var n: Vector3 = ground.normal
			var slope := Vector3(n.x, 0.0, n.z) * (-GRAVITY * delta)
			vel += slope
			# Rolling friction.
			var fr: float = FRICTION.get(current_surface, 0.55)
			var h := Vector3(vel.x, 0.0, vel.z)
			h *= maxf(0.0, 1.0 - fr * delta)
			if h.length() < STOP_EPSILON:
				h = Vector3.ZERO
			vel.x = h.x
			vel.z = h.z
	else:
		# Airborne: no friction, still collide with walls.
		current_surface = "air"

	# Rail/wall collisions (hole-defined segments).
	var rail_hit := _hole.collide_rails(pos, vel, _radius)
	pos = rail_hit[0]
	vel = rail_hit[1]
	if rail_hit[2]:
		bounced.emit(rail_hit[3], "rail")

	# Obstacle collisions (AABBs + special).
	var ob_hit := _hole.collide_obstacles(pos, vel, _radius)
	pos = ob_hit[0]
	vel = ob_hit[1]
	if ob_hit[2]:
		bounced.emit(ob_hit[3], "obstacle")

	# AR mode: real-room geometry — walls as bank planes, furniture as obstacles.
	if not _hole.room_planes.is_empty():
		var rp_hit := _hole.collide_room_planes(pos, vel, _radius)
		pos = rp_hit[0]
		vel = rp_hit[1]
		if rp_hit[2]:
			bounced.emit(rp_hit[3], "wall")
	if not _hole.room_obstacles.is_empty():
		var ro_hit := _hole.collide_room_obstacles(pos, vel, _radius)
		pos = ro_hit[0]
		vel = ro_hit[1]
		if ro_hit[2]:
			# Soft banks (couch): kill energy, muffled whump.
			if _hole.get_meta("soft_banks", false):
				vel *= 0.25
				bounced.emit(ro_hit[3] * 0.4, "soft")
			else:
				bounced.emit(ro_hit[3], "furniture")

	# Hazard check (water, sand pit, cloud gap...).
	var hazard: String = _hole.hazard_at(pos)
	if hazard != "":
		hazard_drop.emit(hazard)
		return  # hole re-places the ball via drop_at()

	# Cup logic: funnel assist + lip-outs.
	_handle_cup(pos, vel, delta)
	if is_holed:
		return

	# Roll the visual mesh.
	_roll_visual(vel, delta)

	global_position = pos
	velocity = vel

	var speed := Vector2(vel.x, vel.z).length()
	if absf(speed - _last_speed) > 0.1:
		_last_speed = speed
		speed_changed.emit(speed)


func _handle_cup(pos: Vector3, vel: Vector3, _delta: float) -> void:
	var cup: Vector3 = _hole.cup_position()
	var flat := Vector2(pos.x - cup.x, pos.z - cup.z)
	var dist := flat.length()
	var rim_r: float = _hole.cup_radius()
	var speed := Vector2(vel.x, vel.z).length()

	if dist > rim_r + _radius + 0.02:
		return

	# Spring-hop anti-cheese: cup capture disabled while airborne.
	# The ball must be rolling on the ground to drop.
	if has_meta("spring_airborne") and bool(get_meta("spring_airborne")):
		if current_surface == "air" or pos.y > cup.y + 0.05:
			return
		remove_meta("spring_airborne")

	# Rim collision: fast balls lip out with restitution.
	if dist > rim_r - _radius and speed > LIP_OUT_SPEED:
		var n := Vector3(flat.x, 0.0, flat.y).normalized()
		var vn := vel.dot(n)
		if vn < 0.0:
			velocity = vel - n * (vn * (1.0 + RESTITUTION_RIM))
			global_position = Vector3(
				cup.x + n.x * (rim_r + _radius),
				pos.y,
				cup.z + n.z * (rim_r + _radius))
			rim_out.emit()
		return

	# Capture: slow + close (with funnel assist pulling toward center).
	if speed < CAPTURE_SPEED and dist < rim_r + FUNNEL_RADIUS:
		_sink_into_cup(cup)


func _sink_into_cup(cup: Vector3) -> void:
	is_holed = true
	is_in_play = false
	velocity = Vector3.ZERO
	var start := global_position
	var target := Vector3(cup.x, _hole.ground_at(cup).height - 0.05, cup.z)
	var t := 0.0
	while t < 0.45:
		t += get_process_delta_time()
		var k := clampf(t / 0.45, 0.0, 1.0)
		var e := k * k  # ease-in: accelerate into the cup
		global_position = start.lerp(target, e)
		# Shrink slightly as it drops.
		var s := 1.0 - e * 0.35
		scale = Vector3(s, s, s)
		await get_tree().process_frame
	scale = Vector3.ONE
	holed.emit()


func _roll_visual(vel: Vector3, delta: float) -> void:
	if _mesh == null:
		return
	var planar := Vector2(vel.x, vel.z)
	var speed := planar.length()
	if speed < 0.01:
		return
	# Roll around the axis perpendicular to motion.
	var axis := Vector3(-planar.y, 0.0, planar.x).normalized()
	_mesh.rotate(axis.normalized(), speed * delta / _radius)
