## NullGDisc.gd - the league disc: Newtonian drift, wall bounces,
## grab/throw, goal-ring crossing detection (owned by the game manager).
class_name NullGDisc
extends Node3D

const RADIUS := 0.16
const RESTITUTION := 0.62
const DRAG := 0.06  # per second, gentle

var vel := Vector3.ZERO
var holder = null          # NullGAgent, or the String "player"
var holder_node: Node3D = null # hand/controller to follow
var last_team := -1           # team of last holder (for own-goal credit)
var arena := Rect2(-2, -2, 4, 4)
var y_min := 0.25
var y_max := 2.9

var _mesh: MeshInstance3D
var _trail: MeshInstance3D
var _trail_pts: Array[Vector3] = []
var trail_enabled := true


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = RADIUS
	sph.height = RADIUS * 2.0
	_mesh.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.95, 1.0)
	mat.emission_energy_multiplier = 2.5
	_mesh.material_override = mat
	# Squash to discus profile.
	_mesh.scale = Vector3(1.0, 0.45, 1.0)
	add_child(_mesh)
	_trail = MeshInstance3D.new()
	add_child(_trail)


func grab(by, by_node: Node3D, team: int) -> void:
	holder = by
	holder_node = by_node
	last_team = team
	vel = Vector3.ZERO
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("catch")


func release(throw_vel: Vector3) -> void:
	holder = null
	holder_node = null
	vel = throw_vel
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("throw")


func is_free() -> bool:
	return holder == null


func toss_to(pos: Vector3, v: Vector3) -> void:
	holder = null
	holder_node = null
	global_position = pos
	vel = v
	_trail_pts.clear()


func physics_tick(delta: float) -> void:
	if holder != null:
		if is_instance_valid(holder_node):
			global_position = holder_node.global_position + Vector3(0, 0.05, 0)
			# Animator: disc-spin fidget while held (alive, not dead).
			rotate_y(delta * 1.5)
		_record_trail()
		return
	global_position += vel * delta
	vel *= maxf(0.0, 1.0 - DRAG * delta)
	_bounce_bounds()
	_record_trail()
	_update_trail_mesh()


func _record_trail() -> void:
	_trail_pts.append(global_position)
	while _trail_pts.size() > 90:
		_trail_pts.remove_at(0)


func _update_trail_mesh() -> void:
	if not trail_enabled or _trail_pts.size() < 4:
		_trail.mesh = null
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, _trail_pts.size(), 3):
		im.surface_set_color(Color(0.3, 0.9, 1.0, 0.5))
		im.surface_add_vertex(to_local(_trail_pts[i]))
	im.surface_end()
	_trail.mesh = im


func _bounce_bounds() -> void:
	var p := global_position
	var bounced := false
	if p.x < arena.position.x + RADIUS:
		p.x = arena.position.x + RADIUS
		vel.x = absf(vel.x) * RESTITUTION
		bounced = true
	elif p.x > arena.position.x + arena.size.x - RADIUS:
		p.x = arena.position.x + arena.size.x - RADIUS
		vel.x = -absf(vel.x) * RESTITUTION
		bounced = true
	if p.z < arena.position.y + RADIUS:
		p.z = arena.position.y + RADIUS
		vel.z = absf(vel.z) * RESTITUTION
		bounced = true
	elif p.z > arena.position.y + arena.size.y - RADIUS:
		p.z = arena.position.y + arena.size.y - RADIUS
		vel.z = -absf(vel.z) * RESTITUTION
		bounced = true
	if p.y < y_min + RADIUS:
		p.y = y_min + RADIUS
		vel.y = absf(vel.y) * RESTITUTION
		bounced = true
	elif p.y > y_max - RADIUS:
		p.y = y_max - RADIUS
		vel.y = -absf(vel.y) * RESTITUTION
		bounced = true
	global_position = p
