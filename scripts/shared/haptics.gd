## Haptics.gd - shared controller vibration helper for NEXUS ARCADE.
## Best-effort haptic pulses through the project's OpenXR action map
## (which already binds a "haptic" action to both hands' haptic outputs).
## Fully guarded: no-ops on desktop, on hand-tracking-only sessions
## (no controllers to vibrate), and if the OpenXR haptic API is absent.
##
## v0.9.0: consistent haptic VOCABULARY (TECH_DEMO_PLAN §3a-bis):
##   confirm()       - UI accept: short 120Hz blip
##   deny()          - error: double 80Hz buzz
##   impact(force01) - thump scaled by force (amplitude + duration)
##   texture_tick()  - 30ms 200Hz tick for drag/paint/strum (call per
##                     finger-travel distance, not per frame)
##   sub_bass(dur)   - 35Hz rumble for whale events / explosions
##   heartbeat(n)    - horror two-thump pattern, n times
##   play_sequence(name) - named [amplitude, duration, pause, freq] patterns
## Legacy pulse()/tick()/thump() are unchanged.
## NOTE: pulse timing/feel needs validation on real Quest 3 hardware.
extends RefCounted
class_name Haptics

## Named haptic sequences: Array of [amplitude, duration_s, pause_s, freq_hz].
const SEQUENCES := {
	"fanfare": [[0.7, 0.08, 0.05, 120.0], [0.7, 0.08, 0.05, 140.0], [1.0, 0.18, 0.0, 160.0]],
	"levelup": [[0.5, 0.06, 0.04, 100.0], [0.7, 0.06, 0.04, 130.0], [0.9, 0.12, 0.0, 160.0]],
	"error": [[0.8, 0.1, 0.06, 80.0], [0.8, 0.1, 0.0, 80.0]],
	"heartbeat": [[0.9, 0.09, 0.06, 55.0], [0.6, 0.12, 0.32, 55.0]],
	"rumble": [[1.0, 0.8, 0.0, 35.0]],
	"tick_tock": [[0.4, 0.04, 0.5, 200.0], [0.4, 0.04, 0.0, 200.0]],
}

static var _action_map: Resource = null
static var _haptic_action: Resource = null
static var _looked_up := false


static func _get_haptic_action() -> Resource:
	if _looked_up:
		return _haptic_action
	_looked_up = true
	if not ARUpgradeKit.is_xr_active():
		return null
	if not ResourceLoader.exists("res://openxr_action_map.tres"):
		return null
	_action_map = load("res://openxr_action_map.tres")
	if _action_map == null or not _action_map.has_method("get_action"):
		return null
	var actions: Array = _action_map.get_actions()
	for a in actions:
		if a != null and String(a.resource_name) == "haptic":
			_haptic_action = a
			break
	return _haptic_action


## Low-level fire. `hand`: "left", "right", or "both" (default).
static func _fire(hand: String, strength: float, duration: float, freq: float = 80.0) -> void:
	var action := _get_haptic_action()
	if action == null:
		return
	var s := clampf(strength, 0.0, 1.0)
	var d := clampf(duration, 0.01, 1.5)
	var f := clampf(freq, 20.0, 300.0)
	if not action.has_method("trigger_haptic_pulse"):
		return
	# godot-openxr signature: (on_hand: String, duration, frequency, amplitude).
	var hands: Array[String] = []
	if hand == "left" or hand == "both":
		hands.append("left_hand")
	if hand == "right" or hand == "both":
		hands.append("right_hand")
	if hands.is_empty():
		hands.append("right_hand")
	for h in hands:
		var err: Variant = action.call("trigger_haptic_pulse", h, d, f, s)
		if err != null:
			break  # signature mismatch: don't spam the second hand


## Fire a short vibration pulse. strength 0.0-1.0, duration in seconds.
## Safe to call anywhere; silently does nothing when haptics unavailable.
static func pulse(strength: float = 0.7, duration: float = 0.12, hand: String = "both") -> void:
	_fire(hand, strength, duration, 80.0)


## Convenience: light UI tick.
static func tick(hand: String = "both") -> void:
	_fire(hand, 0.35, 0.05, 120.0)


## Convenience: strong impact thump.
static func thump(hand: String = "both") -> void:
	_fire(hand, 1.0, 0.25, 60.0)


# ------------------------------------------------------- vocabulary ---

## UI accept: short 120Hz blip, 0.06s.
static func confirm(hand: String = "both") -> void:
	_fire(hand, 0.5, 0.06, 120.0)


## Error: double buzz (2x 80Hz, 0.1s, 60ms gap). Fire-and-forget.
static func deny(hand: String = "both") -> void:
	_fire(hand, 0.8, 0.1, 80.0)
	_later(0.16, func() -> void: _fire(hand, 0.8, 0.1, 80.0))


## Impact thump scaled by force 0..1: amplitude 0.3+0.7f, duration 0.08+0.2f.
static func impact(force01: float, hand: String = "both") -> void:
	var f := clampf(force01, 0.0, 1.0)
	_fire(hand, 0.3 + 0.7 * f, 0.08 + 0.2 * f, 60.0)


## 30ms 200Hz tick for drag/paint/strum. Call per finger-travel distance,
## NOT per frame (a game should accumulate distance and tick on threshold).
static func texture_tick(hand: String = "both") -> void:
	_fire(hand, 0.3, 0.03, 200.0)


## Low-frequency rumble (35Hz, high amplitude) for whale events,
## explosions, meteor rumble.
static func sub_bass(duration: float = 0.8, hand: String = "both") -> void:
	_fire(hand, 1.0, duration, 35.0)


## Horror two-thump pattern, `times` repetitions.
static func heartbeat(times: int = 2, hand: String = "both") -> void:
	for i in maxi(times, 1):
		var base := float(i) * 0.55
		_later(base, func() -> void: _fire(hand, 0.9, 0.09, 55.0))
		_later(base + 0.15, func() -> void: _fire(hand, 0.6, 0.12, 55.0))


## Play a named sequence from SEQUENCES (array of
## [amplitude, duration, pause, freq]). Fire-and-forget.
static func play_sequence(seq_name: String, hand: String = "both") -> void:
	if not SEQUENCES.has(seq_name):
		push_warning("Haptics: unknown sequence '" + seq_name + "'")
		return
	var t := 0.0
	for step in (SEQUENCES[seq_name] as Array):
		var amp := float(step[0])
		var dur := float(step[1])
		var pause := float(step[2])
		var freq := float(step[3]) if step.size() > 3 else 80.0
		_later(t, func() -> void: _fire(hand, amp, dur, freq))
		t += dur + pause


## Schedule a callable after `delay` seconds (tree-timer based; static-safe).
static func _later(delay: float, fn: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if delay <= 0.0:
		fn.call()
		return
	var timer := tree.create_timer(delay)
	timer.timeout.connect(fn)
