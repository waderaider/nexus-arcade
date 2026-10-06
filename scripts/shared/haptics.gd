## Haptics.gd - shared controller vibration helper for NEXUS ARCADE.
## Best-effort haptic pulses through the project's OpenXR action map
## (which already binds a "haptic" action to both hands' haptic outputs).
## Fully guarded: no-ops on desktop, on hand-tracking-only sessions
## (no controllers to vibrate), and if the OpenXR haptic API is absent.
## NOTE: pulse timing/feel needs validation on real Quest 3 hardware.
extends RefCounted
class_name Haptics

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


## Fire a short vibration pulse. strength 0.0-1.0, duration in seconds.
## Safe to call anywhere; silently does nothing when haptics unavailable.
static func pulse(strength: float = 0.7, duration: float = 0.12) -> void:
	var action := _get_haptic_action()
	if action == null:
		return
	var s := clampf(strength, 0.0, 1.0)
	var d := clampf(duration, 0.01, 1.0)
	# godot-openxr OpenXRAction haptic API. Guarded: if the method or
	# signature differs on the running plugin version, this is skipped.
	if action.has_method("trigger_haptic_pulse"):
		# Preferred signature: (on_hand: String, duration, frequency, amplitude)
		var err := action.call("trigger_haptic_pulse", "right_hand", d, 80.0, s)
		if err != null:
			action.call("trigger_haptic_pulse", "left_hand", d, 80.0, s)


## Convenience: light UI tick.
static func tick() -> void:
	pulse(0.35, 0.05)


## Convenience: strong impact thump.
static func thump() -> void:
	pulse(1.0, 0.25)
