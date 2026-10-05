## PinchBlaster.gd - right-hand pinch / trigger shooting with mouse fallback.
## (Port of Unity's PinchBlaster.cs.) Raycasts and damages SwarmEnemy hits,
## with a tracer flash. Input scheme:
##   Mouse left click  -> shoot (Wave/Rest phases; Build phase places turrets)
##   Mouse right click -> shoot always
##   XR trigger_click  -> shoot (Wave/Rest) from camera forward
extends Node3D
class_name PinchBlaster

const COOLDOWN := 0.22
const DAMAGE := 2.0
const MAX_RANGE := 30.0

var director: SwarmDirector

var _cooldown := 0.0
var _tracer: MeshInstance3D
var _tracer_imm: ImmediateMesh
var _tracer_life := 0.0


func _ready() -> void:
	_tracer_imm = ImmediateMesh.new()
	_tracer = MeshInstance3D.new()
	_tracer.mesh = _tracer_imm
	_tracer.material_override = SwarmEnemy.neon_mat(Color(0.2, 0.95, 1.0))
	_tracer.visible = false
	add_child(_tracer)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var in_build := director != null and director.phase == SwarmDirector.Phase.BUILD
	if mb.button_index == MOUSE_BUTTON_LEFT and not in_build:
		shoot_from_screen(mb.position)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		shoot_from_screen(mb.position)


func _process(delta: float) -> void:
	_cooldown -= delta
	if _tracer_life > 0.0:
		_tracer_life -= delta
		if _tracer_life <= 0.0 and _tracer != null:
			_tracer.visible = false

	# XR trigger hold-to-fire (mirrors Unity's pinch hold-to-fire).
	if _cooldown <= 0.0 and _xr_trigger_held():
		var in_build := director != null and director.phase == SwarmDirector.Phase.BUILD
		if not in_build:
			shoot_forward()
			_cooldown = COOLDOWN


## True when the OpenXR trigger action exists and is currently held.
func _xr_trigger_held() -> bool:
	if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
		return true
	if InputMap.has_action("trigger") and Input.get_action_strength("trigger") > 0.75:
		return true
	return false


## Shoot a ray from the camera through a screen point (mouse aiming).
func shoot_from_screen(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	_fire_ray(origin, dir)


## Shoot straight ahead from the camera (XR aiming).
func shoot_forward() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	_fire_ray(origin, dir)


func _fire_ray(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * MAX_RANGE)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)

	var end := origin + dir * MAX_RANGE
	if not hit.is_empty():
		end = hit["position"]
		var collider: Object = hit["collider"]
		if collider is SwarmEnemy:
			(collider as SwarmEnemy).take_damage(DAMAGE)
			SwarmEnemy.spawn_pop(get_parent(), hit["position"], Color(0.2, 0.95, 1.0), 1.5)

	_draw_tracer(origin, end)


func _draw_tracer(from_world: Vector3, to_world: Vector3) -> void:
	_tracer_imm.clear_surfaces()
	_tracer_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	_tracer_imm.surface_add_vertex(_tracer.to_local(from_world))
	_tracer_imm.surface_add_vertex(_tracer.to_local(to_world))
	_tracer_imm.surface_end()
	_tracer.visible = true
	_tracer_life = 0.06
