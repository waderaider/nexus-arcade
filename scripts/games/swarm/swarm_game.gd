## SwarmGame.gd - scene entry point for "Swarm Protocol".
## (Port of Unity's SwarmBootstrap.cs.) Sets up a fallback camera/light/floor
## for desktop testing, the Core, HUD labels, wall portals, the wave director,
## and the pinch blaster. Portals ring the play area; the Core sits in front
## of the player. Never crashes when XR/room data is missing.
extends Node3D
class_name SwarmGame

const PORTAL_COUNT := 4
const PORTAL_RADIUS := 2.4
const PORTAL_HEIGHT := 1.6

var director: SwarmDirector
var core: SwarmCore
var blaster: PinchBlaster
var portals: Array[WallPortal] = []

var _anchor_timer := 0.0


func _ready() -> void:
	_ensure_fallback_camera()
	_ensure_light()
	_build_floor()
	core = _create_core()
	ARUpgradeKit.apply_anchor(core, "swarm_main")
	_create_portals()
	var labels := _create_hud()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, 0.0), 2.5)

	director = SwarmDirector.new()
	add_child(director)
	director.core = core
	director.portals = portals
	director.phase_label = labels[0]
	director.score_label = labels[1]
	director.wave_label = labels[2]
	director.core_label = labels[3]
	director.game_over.connect(_on_game_over_fx)

	blaster = PinchBlaster.new()
	add_child(blaster)
	blaster.director = director


func _process(delta: float) -> void:
	# Persist the core anchor every 30s so the arena stays put between sessions.
	_anchor_timer += delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if is_instance_valid(core):
			ARUpgradeKit.save_anchor("swarm_main", core.global_transform)
	# XR hand shooting: right-hand pinch fires from the camera forward.
	# Mouse clicks still shoot via PinchBlaster's own input handler.
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		if blaster != null:
			blaster.shoot_forward()


func _on_game_over_fx(_score: int) -> void:
	if is_instance_valid(core):
		GraphicsPolish.spawn_confetti(self, core.global_position + Vector3(0.0, 1.0, 0.0))


## Desktop/editor fallback: a camera so the scene is playable without XR.
func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		return
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, -2.8)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.8, 0.8), Vector3.UP)
	cam.current = true


func _ensure_light() -> void:
	# Polish light rig, guarded so we never double up on scene lights.
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.7)


## Invisible-unless-desktop floor: gives turret placement raycasts something
## to hit and grounds the scene visually outside passthrough.
func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	shape.shape = plane
	body.add_child(shape)
	add_child(body)

	var visual := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12.0, 12.0)
	visual.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.07, 0.12, 1.0)
	visual.material_override = mat
	visual.position = Vector3(0.0, -0.01, 0.0)
	add_child(visual)


func _create_core() -> SwarmCore:
	var c := SwarmCore.new()
	add_child(c)
	c.position = ARUpgradeKit.clamp_to_room(Vector3(0.0, 0.0, 1.0))
	return c


func _create_portals() -> void:
	var center := Vector3(0.0, PORTAL_HEIGHT, 0.0)
	for i in range(PORTAL_COUNT):
		var a := i * TAU / PORTAL_COUNT
		var pos := Vector3(cos(a) * PORTAL_RADIUS, PORTAL_HEIGHT, sin(a) * PORTAL_RADIUS)
		var portal := WallPortal.new()
		add_child(portal)
		portal.position = pos
		portal.look_at(center, Vector3.UP)
		portals.append(portal)


## Four billboarded HUD labels floating above the core. Returns
## [phase, score, wave, core] labels for the director.
func _create_hud() -> Array[Label3D]:
	var base := core.position + Vector3(0.0, 1.05, 0.0)
	var defs := [
		["PREPARE", base + Vector3(0.0, 0.42, 0.0), Color(0.4, 0.9, 1.0)],
		["SCORE 0", base + Vector3(0.0, 0.28, 0.0), Color(1.0, 1.0, 1.0)],
		["WAVE 0", base + Vector3(0.0, 0.14, 0.0), Color(1.0, 0.8, 0.2)],
		["CORE HP 100", base, Color(0.2, 1.0, 0.4)],
	]
	var labels: Array[Label3D] = []
	for d in defs:
		var label := GraphicsPolish.make_label(d[0], 64, d[2])
		label.position = d[1]
		label.pixel_size = 0.005
		label.no_depth_test = true
		add_child(label)
		labels.append(label)
	return labels
