## SwarmTurret.gd - player-placed defense turret: cylinder base, yawing head,
## emissive barrel. (Port of Unity's SwarmTurret.cs.) Acquires the nearest
## SwarmEnemy in range and fires hitscan shots with a tracer flash.
extends Node3D
class_name SwarmTurret

const RANGE := 7.0
const FIRE_INTERVAL := 0.45
const DAMAGE := 1.2

var _head: Node3D
var _barrel_tip: Node3D
var _tracer: MeshInstance3D
var _tracer_imm: ImmediateMesh
var _tracer_life := 0.0
var _fire_timer := 0.0


## Create a turret at the given position (parent adds it to the scene).
static func place(pos: Vector3) -> SwarmTurret:
	var t := SwarmTurret.new()
	t.position = pos
	return t


func _ready() -> void:
	_build_visuals()
	_tracer_imm = ImmediateMesh.new()
	_tracer = MeshInstance3D.new()
	_tracer.mesh = _tracer_imm
	_tracer.material_override = SwarmEnemy.neon_mat(Color(1.0, 0.95, 0.2))
	_tracer.visible = false
	add_child(_tracer)


func _process(delta: float) -> void:
	if _tracer_life > 0.0:
		_tracer_life -= delta
		if _tracer_life <= 0.0 and _tracer != null:
			_tracer.visible = false

	var target := _acquire_target()
	if target == null or _head == null:
		return

	var to_target := target.global_position - _head.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		var want_yaw := atan2(-to_target.x, -to_target.z)
		_head.rotation.y = lerp_angle(_head.rotation.y, want_yaw, minf(1.0, 10.0 * delta))

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = FIRE_INTERVAL
		_fire(target)


func _acquire_target() -> SwarmEnemy:
	var best: SwarmEnemy = null
	var best_dist := RANGE
	for node in get_tree().get_nodes_in_group("swarm_enemies"):
		if not (node is SwarmEnemy):
			continue
		var enemy := node as SwarmEnemy
		var d := global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _fire(target: SwarmEnemy) -> void:
	target.take_damage(DAMAGE)
	var from := global_position + Vector3(0.0, 0.3, 0.0)
	if _barrel_tip != null:
		from = _barrel_tip.global_position
	_draw_tracer(from, target.global_position)
	SwarmEnemy.spawn_pop(get_parent(), target.global_position, Color(1.0, 0.95, 0.2), 1.5)


func _draw_tracer(from_world: Vector3, to_world: Vector3) -> void:
	_tracer_imm.clear_surfaces()
	_tracer_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	_tracer_imm.surface_add_vertex(_tracer.to_local(from_world))
	_tracer_imm.surface_add_vertex(_tracer.to_local(to_world))
	_tracer_imm.surface_end()
	_tracer.visible = true
	_tracer_life = 0.07


func _build_visuals() -> void:
	var dark := SwarmEnemy.neon_mat(Color(0.15, 0.16, 0.2))
	var glow := SwarmEnemy.neon_mat(Color(0.2, 1.0, 0.4))

	var base := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.14
	bcm.bottom_radius = 0.14
	bcm.height = 0.08
	base.mesh = bcm
	base.material_override = dark
	base.position = Vector3(0.0, 0.04, 0.0)
	add_child(base)

	var column := MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.05
	ccm.bottom_radius = 0.05
	ccm.height = 0.16
	column.mesh = ccm
	column.material_override = dark
	column.position = Vector3(0.0, 0.16, 0.0)
	add_child(column)

	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.28, 0.0)
	add_child(_head)

	var dome := MeshInstance3D.new()
	var dsm := SphereMesh.new()
	dsm.radius = 0.08
	dsm.height = 0.16
	dome.mesh = dsm
	dome.material_override = dark
	_head.add_child(dome)

	var barrel := MeshInstance3D.new()
	var brm := CylinderMesh.new()
	brm.top_radius = 0.025
	brm.bottom_radius = 0.025
	brm.height = 0.35
	barrel.mesh = brm
	barrel.material_override = glow
	barrel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	barrel.position = Vector3(0.0, 0.02, -0.2)
	_head.add_child(barrel)

	_barrel_tip = Node3D.new()
	_barrel_tip.position = Vector3(0.0, 0.02, -0.38)
	_head.add_child(_barrel_tip)
