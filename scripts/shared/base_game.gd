## NexusBaseGame.gd - opt-in game template for NEXUS ARCADE.
## Extend this instead of Node3D to get the v0.7.0 shared upgrades for free:
##   extends NexusBaseGame
## What you get in _ready():
##   - VisualFX defaults: ACES tonemap, subtle glow, distance fog, mobile
##     shadow config on the first DirectionalLight3D (all cheap on Quest 3)
##   - UIKit HUD (score + health labels) on a CanvasLayer
##   - Pause menu on the ui_cancel action (Esc / menu button mapping)
## Override game_ready() instead of _ready() for your own setup.
## score/health vars are wired to the HUD via add_score()/set_health().
## NOTE: never Quest-tested here; verify pause/HUD on device.
class_name NexusBaseGame
extends Node3D

## Visual toggles (set before super._ready() runs, i.e. as member defaults).
var use_aces := true
var use_glow := true
var use_fog := true
var fog_density := 0.012
var use_dust := false  # off by default: particle overdraw adds up in AR

var score: int = 0
var health: float = 100.0
var max_health: float = 100.0

var _hud: Dictionary = {}
var _canvas: Control = null
var _paused := false


func _ready() -> void:
	_apply_visual_defaults()
	_build_canvas_hud()
	game_ready()


## Override this in your game instead of _ready().
func game_ready() -> void:
	pass


func _apply_visual_defaults() -> void:
	var world := _find_world()
	if world != null:
		if use_aces:
			VisualFX.apply_aces(world)
		if use_glow:
			VisualFX.subtle_glow(world)
		if use_fog:
			VisualFX.enable_fog(world, fog_density)
		if use_dust:
			VisualFX.ambient_dust(self)
	var sun := _find_sun()
	if sun != null:
		VisualFX.configure_shadows(sun)


func _find_world() -> WorldEnvironment:
	# Type-based (not name-based): works for scene-built and code-built worlds.
	var found := find_children("*", "WorldEnvironment", true, false)
	if found.is_empty():
		return null
	return found[0] as WorldEnvironment


func _find_sun() -> DirectionalLight3D:
	var found := find_children("*", "DirectionalLight3D", true, false)
	if found.is_empty():
		return null
	return found[0] as DirectionalLight3D


func _build_canvas_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NexusBaseHUD"
	add_child(layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_canvas)
	_hud = UIKit.make_hud(_canvas)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud.has("score"):
		(_hud["score"] as Label).text = "SCORE %d" % score
	if _hud.has("health"):
		(_hud["health"] as Label).text = "HP %d" % int(health)


## Score/health API (HUD updates automatically).
func add_score(n: int) -> void:
	score += n
	if _hud.has("score"):
		(_hud["score"] as Label).text = "SCORE %d" % score
	UIKit.ui_haptic("tick")


func set_health(h: float) -> void:
	health = clampf(h, 0.0, max_health)
	_refresh_hud()


func damage(amount: float) -> void:
	set_health(health - amount)
	UIKit.ui_haptic("thump")


func heal(amount: float) -> void:
	set_health(health + amount)


## Pause: ui_cancel action (Esc on desktop; map the XR menu button to it).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if _paused or _canvas == null:
		return
	_paused = true
	UIKit.pause_menu(_canvas, _on_resumed)


func _on_resumed() -> void:
	_paused = false
