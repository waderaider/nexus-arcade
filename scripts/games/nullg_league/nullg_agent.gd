## NullGAgent.gd - AI teammate/opponent for NULL-G LEAGUE.
## Steering agent: chase disc, carry to goal, support carrier, mark carrier.
## Also drives the player autopilot in headless/desktop (no-XR) sessions.
class_name NullGAgent
extends Node3D

const MAX_SPEED := 4.6
const ACCEL := 9.0
const GRAB_RADIUS := 0.85
const SHOOT_RANGE := 3.2
const THROW_SPEED := 9.5

var team := 0
var skill := 0.5  # 0..1 scales reaction + max speed
var vel := Vector3.ZERO
var has_disc := false
var throw_request := Vector3.INF  # set to a target point to request a throw
var grab_cooldown := 0.0

var avatar: NullGAvatar
var arena := Rect2(-2, -2, 4, 4)
var y_min := 0.3
var y_max := 2.8

var _think_t := 0.0
var _role := "chase"  # chase | carry | support | mark
var _idle_t := 0.0
var _breath_phase := 0.0


func setup(p_team: int, color: Color, p_skill: float, p_arena: Rect2) -> void:
	team = p_team
	skill = p_skill
	arena = p_arena
	avatar = NullGAvatar.make(color)
	add_child(avatar)
	_breath_phase = randf() * TAU  # animator: never in sync


func _process(delta: float) -> void:
	# Animator idle life: breathing overlay on the avatar (0.25Hz).
	_idle_t += delta
	if avatar != null and is_instance_valid(avatar):
		var b := 0.98 + 0.04 * AmbientKit.breath_value(_idle_t, _breath_phase)
		avatar.scale = Vector3(b, 2.0 - b, b)


## ctx: {disc_pos, disc_vel, disc_free, disc_holder_team, goal_pos,
##        carrier (Node3D or null), player_pos, player_has_disc}
func think(dt: float, ctx: Dictionary) -> void:
	_think_t -= dt
	grab_cooldown = maxf(0.0, grab_cooldown - dt)
	var disc_pos: Vector3 = ctx["disc_pos"]
	var goal_pos: Vector3 = ctx["goal_pos"]
	var target := disc_pos
	if has_disc:
		_role = "carry"
		var to_goal: Vector3 = goal_pos - global_position
		if to_goal.length() < SHOOT_RANGE:
			throw_request = goal_pos
			target = global_position  # hold still, aim
		else:
			# Approach to a shooting pocket offset from the ring.
			var side := Vector3(1.2 * (1.0 if team == 0 else -1.0), 0.2, 0.8)
			target = goal_pos + side
	elif bool(ctx["disc_free"]):
		_role = "chase"
		# Intercept: lead the disc, with skill-based error.
		var dist := global_position.distance_to(disc_pos)
		var lead := clampf(dist / 7.0, 0.0, 0.8) * (0.4 + 0.6 * skill)
		target = disc_pos + (ctx["disc_vel"] as Vector3) * lead
	else:
		var holder_team := int(ctx["disc_holder_team"])
		var carrier: Node3D = ctx["carrier"] as Node3D
		if holder_team == team:
			_role = "support"
			# Spread to the weak side between disc and goal.
			var mid := (disc_pos + goal_pos) * 0.5
			var flank := 1.6 if (hash(name) % 2 == 0) else -1.6
			target = mid + Vector3(flank, 0.3, -flank * 0.5)
		else:
			_role = "mark"
			target = (carrier.global_position + disc_pos) * 0.5 if carrier != null else disc_pos
	# Keep inside the arena with a soft margin.
	target.x = clampf(target.x, arena.position.x + 0.5, arena.position.x + arena.size.x - 0.5)
	target.z = clampf(target.z, arena.position.y + 0.5, arena.position.y + arena.size.y - 0.5)
	target.y = clampf(target.y, y_min + 0.3, y_max - 0.3)
	var desired := (target - global_position)
	var spd := MAX_SPEED * (0.55 + 0.45 * skill)
	if desired.length() > 0.05:
		desired = desired.normalized() * minf(spd, desired.length() * 2.0)
	else:
		desired = Vector3.ZERO
	vel = vel.lerp(desired, 1.0 - exp(-3.0 * dt))
	global_position += vel * dt
	_bounce()
	if avatar != null:
		avatar.steer_look(vel, vel.length(), dt)


func _bounce() -> void:
	var p := global_position
	if p.x < arena.position.x + 0.3:
		p.x = arena.position.x + 0.3
		vel.x = absf(vel.x) * 0.7
	elif p.x > arena.position.x + arena.size.x - 0.3:
		p.x = arena.position.x + arena.size.x - 0.3
		vel.x = -absf(vel.x) * 0.7
	if p.z < arena.position.y + 0.3:
		p.z = arena.position.y + 0.3
		vel.z = absf(vel.z) * 0.7
	elif p.z > arena.position.y + arena.size.y - 0.3:
		p.z = arena.position.y + arena.size.y - 0.3
		vel.z = -absf(vel.z) * 0.7
	if p.y < y_min + 0.2:
		p.y = y_min + 0.2
		vel.y = absf(vel.y) * 0.7
	elif p.y > y_max - 0.2:
		p.y = y_max - 0.2
		vel.y = -absf(vel.y) * 0.7
	global_position = p


func hash(s: String) -> int:
	var h := 0
	for c in s:
		h = (h * 31 + c.unicode_at(0)) % 1000003
	return h
