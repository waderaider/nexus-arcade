## AILib.gd - shared AI upgrade kit for NEXUS ARCADE (autoload: AILib).
## 10 opt-in AI helpers. Steering functions return DISPLACEMENT vectors
## (already scaled by delta) in the agent's PARENT coordinate space - just
## add them to the agent's position:  agent.position += AILib.follow(...).
## Usage: AILib.wander(self, delta, 2.0) / AILib.new_fsm({...}) ...
## Headless-safe: pure math + node metas, no XR or rendering required.
extends Node


## Tiny state machine. States: Dictionary of String -> Callable(delta).
## Optional "enter_<state>" Callables fire on transition (receive old state).
class AIFSM extends RefCounted:
	var states: Dictionary = {}
	var current: String = ""

	func _init(p_states: Dictionary, start: String = "") -> void:
		states = p_states
		if start != "" and states.has(start):
			current = start
		elif not states.is_empty():
			current = String(states.keys()[0])

	func change(next: String) -> bool:
		if not states.has(next) or next == current:
			return false
		var old := current
		current = next
		if states.has("enter_" + current):
			(states["enter_" + current] as Callable).call(old)
		return true

	func update(delta: float) -> void:
		if states.has(current):
			(states[current] as Callable).call(delta)


var _wins := 0
var _deaths := 0
var _board: Dictionary = {}


## (a) Wander: smooth random steering. Returns displacement vector.
func wander(agent: Node3D, delta: float, speed: float, turn: float = 2.5) -> Vector3:
	if agent == null or delta <= 0.0:
		return Vector3.ZERO
	var a := float(agent.get_meta("_ailib_wander_a", randf() * TAU))
	a += randf_range(-1.0, 1.0) * turn * delta
	agent.set_meta("_ailib_wander_a", a)
	var fwd := -agent.transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	var dir := fwd.normalized() * 0.6 + Vector3(cos(a), 0.0, sin(a)) * 0.7
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	return dir.normalized() * speed * delta


## (b) Follow: seek a target position. Flee: run from a threat position.
## Both return displacement vectors.
func follow(agent: Node3D, target_pos: Vector3, delta: float, speed: float) -> Vector3:
	if agent == null or delta <= 0.0:
		return Vector3.ZERO
	var to: Vector3 = target_pos - agent.position
	var dist := to.length()
	if dist < 0.02:
		return Vector3.ZERO
	return to / dist * speed * delta


func flee(agent: Node3D, threat_pos: Vector3, delta: float, speed: float) -> Vector3:
	if agent == null or delta <= 0.0:
		return Vector3.ZERO
	var away: Vector3 = agent.position - threat_pos
	var dist := away.length()
	if dist < 0.02:
		away = Vector3.RIGHT
	return away.normalized() * speed * delta


## (c) Boids-lite flocking: separation + alignment + cohesion.
## neighbors: Array of Node3D. Caps work at max_n nearest. Returns displacement.
func flock(agent: Node3D, neighbors: Array, delta: float, radius: float = 2.5, max_n: int = 6) -> Vector3:
	if agent == null or delta <= 0.0 or neighbors.is_empty():
		return Vector3.ZERO
	var scored: Array = []
	for nb in neighbors:
		if nb == agent or not (nb is Node3D):
			continue
		var n3d := nb as Node3D
		var dist: float = agent.position.distance_to(n3d.position)
		if dist < radius and dist > 0.0001:
			scored.append([dist, n3d])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var count := mini(scored.size(), maxi(max_n, 1))
	if count == 0:
		return Vector3.ZERO
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	for i in range(count):
		var nb: Node3D = scored[i][1]
		var offset: Vector3 = agent.position - nb.position
		var dist: float = float(scored[i][0])
		sep += offset.normalized() / maxf(dist, 0.2)
		ali += -nb.transform.basis.z
		coh += nb.position
	ali = ali / float(count)
	coh = coh / float(count) - agent.position
	var steer := sep * 1.6 + ali * 0.5 + coh * 0.4
	if steer.length() > 2.0:
		steer = steer.normalized() * 2.0
	return steer * delta


## (d) FSM factory. Example:
##   var fsm := AILib.new_fsm({"idle": _on_idle, "chase": _on_chase}, "idle")
##   fsm.update(delta)          # in _process
##   fsm.change("chase")        # transitions
func new_fsm(states: Dictionary, start: String = "") -> AIFSM:
	return AIFSM.new(states, start)


## (e) Difficulty scaling. Games report outcomes; difficulty_scale() returns
## 0.5 (player struggling) .. 2.0 (player dominating), 1.0 neutral.
## Multiply enemy hp/speed/count by it.
func report_win() -> void:
	_wins += 1


func report_death() -> void:
	_deaths += 1


func reset_difficulty() -> void:
	_wins = 0
	_deaths = 0


func difficulty_scale() -> float:
	return clampf(1.0 - float(_deaths - _wins) * 0.08, 0.5, 2.0)


## (f) Predictive aim: where to shoot to hit a moving target.
## Returns the aim POINT (fall back: the target's current position).
func predictive_aim(shooter_pos: Vector3, target_pos: Vector3, target_vel: Vector3, proj_speed: float) -> Vector3:
	var to := target_pos - shooter_pos
	var a := target_vel.length_squared() - proj_speed * proj_speed
	var b := 2.0 * to.dot(target_vel)
	var c := to.length_squared()
	var t := -1.0
	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b + sq) / (2.0 * a)
			var t2 := (-b - sq) / (2.0 * a)
			if t1 > 0.0 and (t2 <= 0.0 or t1 < t2):
				t = t1
			elif t2 > 0.0:
				t = t2
	if t <= 0.0:
		return target_pos
	return target_pos + target_vel * t


## (g) Group coordination blackboard: shared key -> Vector3 targets.
## Example: turrets agree on one focus target via set_target("focus", pos).
func set_target(key: String, pos: Vector3) -> void:
	_board[key] = pos


func get_target(key: String) -> Vector3:
	return _board.get(key, Vector3.ZERO)


func has_target(key: String) -> bool:
	return _board.has(key)


func clear_target(key: String) -> void:
	_board.erase(key)


func clear_board() -> void:
	_board.clear()


## (h) Investigate: steer toward a stimulus, slowing to a stop on arrival.
## Returns displacement vector.
func investigate(agent: Node3D, stimulus_pos: Vector3, delta: float, speed: float = 1.2, arrive: float = 0.4) -> Vector3:
	if agent == null or delta <= 0.0:
		return Vector3.ZERO
	var to: Vector3 = stimulus_pos - agent.position
	var dist := to.length()
	if dist < 0.05:
		return Vector3.ZERO
	var sp := speed * clampf(dist / maxf(arrive * 3.0, 0.05), 0.15, 1.0)
	return to / dist * sp * delta


## (i) Player memory: remember where the player was last seen.
func remember_seen(agent: Node3D, pos: Vector3) -> void:
	if agent == null:
		return
	agent.set_meta("_ailib_seen_pos", pos)
	agent.set_meta("_ailib_seen_t", Time.get_ticks_msec() / 1000.0)


func last_seen(agent: Node3D) -> Vector3:
	if agent == null:
		return Vector3.ZERO
	return agent.get_meta("_ailib_seen_pos", Vector3.ZERO)


## Seconds since remember_seen; -1.0 if never seen.
func seen_age(agent: Node3D) -> float:
	if agent == null or not agent.has_meta("_ailib_seen_t"):
		return -1.0
	return Time.get_ticks_msec() / 1000.0 - float(agent.get_meta("_ailib_seen_t"))


## (j) Idle behavior: gentle look-around + bob in place. Bounded oscillation
## (no drift). Call every frame for idle NPCs.
func idle_behavior(agent: Node3D, delta: float, look_speed: float = 0.6, bob: float = 0.025) -> void:
	if agent == null or delta <= 0.0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var seed := float(agent.get_instance_id() % 1000)
	agent.rotation.y += sin(t * 0.7 + seed) * look_speed * delta
	agent.position.y += sin(t * 2.0 + seed) * bob * delta
