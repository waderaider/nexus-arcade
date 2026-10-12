class_name AnimFluidity
extends RefCounted
## v0.11.0 (Pixar-Style Animator plan): shared animation-fluidity helpers.
## One code path for anticipation / idle life / head-lead / secondary motion /
## landings — never per-game bespoke. All functions are zero-alloc (static,
## no per-frame allocations); one-shot tweens are used only for discrete
## actions, never for ambient loops. Quest-3-cheap by construction.

## Anticipation: 150ms crouch (scale-y 0.88) + overshoot, THEN the action.
## The discrete action (attack, jump, pop-up, lunge) is always telegraphed.
static func anticipate_then(node: Node3D, action: Callable, windup := 0.15) -> void:
	if node == null or not is_instance_valid(node):
		action.call()
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale:y", node.scale.y * 0.88, windup)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(action)
	tw.tween_property(node, "scale:y", node.scale.y * 1.06, 0.09)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale:y", node.scale.y, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Idle life: nothing player-facing stands perfectly still. Breathing =
## chest/root scale 1±amp at 0.25Hz. Call from _process with the game's clock.
static func breathe(node: Node3D, t: float, phase := 0.0, amp := 0.02) -> void:
	if node == null or not is_instance_valid(node):
		return
	var k := 1.0 + amp * sin(TAU * 0.25 * (t + phase))
	node.scale = Vector3(2.0 - k, k, 2.0 - k)


## Weight shift: root yaw ±0.05 every ~6s + subtle bob. Idle characters only.
static func weight_shift(node: Node3D, t: float, phase := 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	var cyc := (t + phase) / 6.0
	var side := 1.0 if fmod(cyc, 2.0) < 1.0 else -1.0
	var blend := smoothstep(0.0, 0.15, fmod(cyc, 1.0)) \
		* smoothstep(1.0, 0.85, fmod(cyc, 1.0))
	# Applied as a small roll lean (safe on any rig root):
	node.rotation.z = lerpf(node.rotation.z, side * 0.05 * blend, 0.08)


## Head leads: head turns 2-3 frames before the body. head_rate 8/s, body 4/s.
static func head_lead(head: Node3D, body: Node3D, target_yaw: float, delta: float) -> void:
	if head != null and is_instance_valid(head):
		head.rotation.y = lerpf(head.rotation.y, target_yaw,
			minf(1.0, 8.0 * delta))
	if body != null and is_instance_valid(body):
		body.rotation.y = lerpf(body.rotation.y, target_yaw,
			minf(1.0, 4.0 * delta))


## Landing: 120-180ms squash (scale-y 0.88-0.92) + recover. Heavy things
## squash more and recover slower. No pop-to-rest.
static func landing_squash(node: Node3D, heavy := false) -> void:
	if node == null or not is_instance_valid(node):
		return
	var squash_y := 0.86 if heavy else 0.90
	var recover := 0.22 if heavy else 0.14
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(1.12, squash_y, 1.12), 0.06)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "scale", Vector3.ONE, recover)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Blink scheduler: eyes scale-y to 0.1 for 120ms every 2.4-5s (deterministic
## pseudo-random from phase — 10 instances never blink in sync).
static func blink_eyes(eye_l: Node3D, eye_r: Node3D, t: float, phase := 0.0) -> void:
	var cyc := (t + phase) / lerpf(2.4, 5.0, _hash01(phase))
	var blink := fmod(cyc, 1.0)
	var open_k := 1.0
	if blink > 0.94:
		open_k = 0.1
	elif blink > 0.90:
		open_k = lerpf(1.0, 0.1, (blink - 0.90) / 0.04)
	if eye_l != null and is_instance_valid(eye_l):
		eye_l.scale.y = open_k
	if eye_r != null and is_instance_valid(eye_r):
		eye_r.scale.y = open_k


## Ear/tail flick: random 6-14s flicks, 120ms. For goblins, pets, monsters.
static func appendage_flick(part: Node3D, t: float, phase := 0.0) -> void:
	if part == null or not is_instance_valid(part):
		return
	var cyc := (t + phase) / lerpf(6.0, 14.0, _hash01(phase * 1.7))
	var flick := fmod(cyc, 1.0)
	if flick < 0.02:
		part.rotation.z += sin(flick / 0.02 * PI) * 0.02


## Secondary motion: follower lags the target by 2-4 frames (capes, tails,
## antennae, pennant tips). rate ~6/s gives the lag; never a full sim.
static func secondary_lag(follower: Node3D, target_global: Vector3,
		delta: float, rate := 6.0) -> void:
	if follower == null or not is_instance_valid(follower):
		return
	follower.global_position = follower.global_position.lerp(
		target_global, minf(1.0, rate * delta))


## Emissive flicker with per-instance phase (candles, neon, windows, consoles).
## 0 CPU per frame beyond the call; never a real light.
static func emissive_flicker(mat: StandardMaterial3D, t: float, phase := 0.0,
		base := 1.2, amp := 0.5, speed := 7.0) -> void:
	if mat == null:
		return
	# Cheap flame noise: two sines, never synchronized across instances.
	mat.emission_energy_multiplier = base + amp * (
		0.6 * sin(t * speed + phase) + 0.4 * sin(t * speed * 2.7 + phase * 1.3))


static func _hash01(x: float) -> float:
	var s := sin(x * 127.1) * 43758.5453
	return s - floorf(s)
