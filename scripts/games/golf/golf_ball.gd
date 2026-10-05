## GolfBall.gd - minigolf ball with custom integrator (no RigidBody).
## Ports GolfBall.cs: gravity, ground bounce, rolling friction, bumper
## reflection, obstacle AABB resolution, gravity wells, portal teleport,
## cup capture.
extends Node3D
class_name GolfBall

signal holed
signal bounced(strength: float)
signal portal_used

const GRAVITY := 9.81
const RESTITUTION := 0.7

var velocity := Vector3.ZERO
var is_holed := false

var _hole: GolfHoleData
var _portal_cooldown := 0.0
var _trail: GPUParticles3D

@onready var _mesh: MeshInstance3D = $BallMesh

func _ready() -> void:
	# Trail for juice.
	_trail = GPUParticles3D.new()
	_trail.amount = 24
	_trail.lifetime = 0.5
	_trail.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.02
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.1
	_trail.process_material = mat
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(1, 1, 1, 0.6)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.material = draw_mat
	_trail.draw_pass_1 = quad
	add_child(_trail)

func configure(hole: GolfHoleData) -> void:
	_hole = hole
	is_holed = false
	scale = Vector3.ONE
	reset_to_tee()

func set_velocity(v: Vector3) -> void:
	velocity = v

func reset_to_tee() -> void:
	if _hole == null:
		return
	is_holed = false
	scale = Vector3.ONE
	global_position = _hole.tee_pos
	velocity = Vector3.ZERO
	_portal_cooldown = 0.0

func _physics_process(delta: float) -> void:
	if _hole == null or is_holed:
		return
	_portal_cooldown -= delta

	var pos := global_position
	var vel := velocity
	var rad := _hole.ball_radius

	# Gravity wells pull the ball toward their center (XZ only).
	for well in _hole.wells:
		if not is_instance_valid(well):
			continue
		var to_well: Vector3 = well.global_position - pos
		to_well.y = 0.0
		var dist := to_well.length()
		if dist < well.radius and dist > 0.001:
			vel += to_well.normalized() * (well.strength * (1.0 - dist / well.radius)) * delta

	vel.y -= GRAVITY * delta
	pos += vel * delta

	# Ground plane: bounce once, then roll.
	var rest_y := _hole.green_top_y + rad
	var on_ground := false
	if pos.y <= rest_y:
		pos.y = rest_y
		if absf(vel.y) > 0.6:
			bounced.emit(absf(vel.y))
			vel.y = -vel.y * 0.35
		else:
			vel.y = 0.0
			on_ground = true

	if on_ground:
		var h := Vector3(vel.x, 0.0, vel.z)
		h *= maxf(0.0, 1.0 - 1.4 * delta)
		if h.length() < 0.04:
			h = Vector3.ZERO
		vel.x = h.x
		vel.z = h.z
	else:
		vel *= maxf(0.0, 1.0 - 0.05 * delta)

	# Border bumpers: reflect off the playable rect.
	var r := _hole.play_rect  # Rect2 in XZ (x = min_x, y = min_z, size)
	if pos.x < r.position.x + rad:
		bounced.emit(absf(vel.x)); pos.x = r.position.x + rad; vel.x = absf(vel.x) * RESTITUTION
	if pos.x > r.end.x - rad:
		bounced.emit(absf(vel.x)); pos.x = r.end.x - rad; vel.x = -absf(vel.x) * RESTITUTION
	if pos.z < r.position.y + rad:
		bounced.emit(absf(vel.z)); pos.z = r.position.y + rad; vel.z = absf(vel.z) * RESTITUTION
	if pos.z > r.end.y - rad:
		bounced.emit(absf(vel.z)); pos.z = r.end.y - rad; vel.z = -absf(vel.z) * RESTITUTION

	for ob: AABB in _hole.obstacles:
		var res := _resolve_aabb(pos, vel, ob, rad)
		pos = res[0]
		vel = res[1]

	# Portals.
	if _hole.portals != null and _portal_cooldown <= 0.0:
		var tp := _hole.portals.try_teleport(pos)
		if tp[1]:
			pos = tp[0]
			_portal_cooldown = 0.6
			portal_used.emit()

	# Cup capture: close, slow, and on the ground.
	var flat := Vector2(pos.x - _hole.cup_pos.x, pos.z - _hole.cup_pos.z)
	if on_ground and flat.length() < _hole.cup_radius and vel.length() < 1.4:
		_sink_into_cup()
		return

	# Safety net.
	if pos.y < _hole.green_top_y - 2.0:
		reset_to_tee()
		return

	global_position = pos
	velocity = vel

## AABB resolve that returns corrected [pos, vel].
func _resolve_aabb(pos: Vector3, vel: Vector3, ob: AABB, rad: float) -> Array:
	var closest := ob.get_support(pos)  # not exact; use manual clamp
	closest = Vector3(
		clampf(pos.x, ob.position.x, ob.end.x),
		clampf(pos.y, ob.position.y, ob.end.y),
		clampf(pos.z, ob.position.z, ob.end.z))
	var delta_v: Vector3 = pos - closest
	var dist := delta_v.length()
	if dist >= rad:
		return [pos, vel]
	var n := delta_v / dist if dist > 0.0001 else Vector3.UP
	pos = closest + n * rad
	var vn := vel.dot(n)
	if vn < 0.0:
		bounced.emit(absf(vn))
		vel -= n * (vn * (1.0 + RESTITUTION))
	return [pos, vel]

func _sink_into_cup() -> void:
	is_holed = true
	velocity = Vector3.ZERO
	var target := Vector3(_hole.cup_pos.x, _hole.green_top_y - 0.06, _hole.cup_pos.z)
	var start := global_position
	var t := 0.0
	while t < 0.5:
		t += get_process_delta_time()
		var k := clampf(t / 0.5, 0.0, 1.0)
		global_position = start.lerp(target, k)
		scale = Vector3.ONE * (1.0 - k * 0.8)
		await get_tree().process_frame
	holed.emit()
