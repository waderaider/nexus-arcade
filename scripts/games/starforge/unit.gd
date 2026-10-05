class_name StarforgeUnit
extends Node3D
## Starforge Command combat unit: moves, auto-acquires targets, fires tracers.
## Two types: FIGHTER (fast skirmisher) and CRUISER (heavy hitter).
## Ported from Unity Ship.cs (Idle / Move / Attack states, range + cooldown).

enum Side { PLAYER, ENEMY }
enum UnitType { FIGHTER, CRUISER }
enum State { IDLE, MOVE, ATTACK }

signal died(unit: StarforgeUnit)

const STATS := {
	UnitType.FIGHTER: {"hp": 30.0, "speed": 0.28, "range": 0.38, "damage": 6.0, "cooldown": 1.4, "aggro": 0.55},
	UnitType.CRUISER: {"hp": 70.0, "speed": 0.18, "range": 0.45, "damage": 12.0, "cooldown": 2.0, "aggro": 0.60},
}
const COSTS := {UnitType.FIGHTER: 25, UnitType.CRUISER: 50}

var side: int = Side.PLAYER
var unit_type: UnitType = UnitType.FIGHTER
var state: State = State.IDLE
var game: StarforgeGame = null

var hp: float = 30.0
var max_hp: float = 30.0
var speed: float = 0.28
var attack_range: float = 0.38
var damage: float = 6.0
var cooldown: float = 1.4
var aggro_range: float = 0.55

# Untyped on purpose: target may be a StarforgeUnit or a StarforgeBuilding.
var target = null
var move_target: Vector3 = Vector3.ZERO
var has_move_target: bool = false

var _fire_timer: float = 0.0
var _beam_timer: float = 0.0
var _beam: MeshInstance3D = null
var _bob_phase: float = 0.0


func setup(p_side: int, p_type: UnitType, p_game: StarforgeGame) -> void:
	side = p_side
	unit_type = p_type
	game = p_game
	var s: Dictionary = STATS[p_type]
	max_hp = s["hp"]
	hp = max_hp
	speed = s["speed"]
	attack_range = s["range"]
	damage = s["damage"]
	cooldown = s["cooldown"]
	aggro_range = s["aggro"]
	_bob_phase = randf() * TAU
	_build_visuals()


func _build_visuals() -> void:
	var hull_color := Color(0.35, 0.7, 1.0) if side == Side.PLAYER else Color(1.0, 0.4, 0.35)
	var w := 0.035
	var h := 0.022
	var l := 0.075
	if unit_type == UnitType.CRUISER:
		w *= 1.5
		h *= 1.5
		l *= 1.4
	# Elongated octahedron hull (6 verts, 8 tris), like the Unity version.
	var verts := [
		Vector3(0, h, 0), Vector3(0, -h, 0),
		Vector3(w, 0, 0), Vector3(-w, 0, 0),
		Vector3(0, 0, l), Vector3(0, 0, -l),
	]
	var tris := [
		[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
		[1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in tris:
		for vi in tri:
			st.add_vertex(verts[vi])
	st.generate_normals()
	var hull := MeshInstance3D.new()
	hull.mesh = st.commit()
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = hull_color
	hmat.emission_enabled = true
	hmat.emission = hull_color
	hmat.emission_energy_multiplier = 0.35
	hmat.metallic = 0.6
	hmat.roughness = 0.3
	hull.material_override = hmat
	add_child(hull)
	# Engine glow at the stern.
	var engine := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.012
	sph.height = 0.024
	engine.mesh = sph
	var emat := _emissive_mat(Color(1.0, 0.6, 0.2), 2.0)
	engine.material_override = emat
	engine.position = Vector3(0, 0, -l * 0.95)
	add_child(engine)
	# Reused weapon-fire beam.
	_beam = MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.008, 0.008, 1.0)
	_beam.mesh = bb
	var bmat := _emissive_mat(Color(1.0, 0.9, 0.4), 2.0)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = bmat
	_beam.visible = false
	add_child(_beam)


func _emissive_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func is_alive() -> bool:
	return hp > 0.0


func take_damage(amount: float) -> void:
	if not is_alive():
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		died.emit(self)
		queue_free()


func order_move(pos: Vector3) -> void:
	move_target = pos
	has_move_target = true
	target = null
	state = State.MOVE


func order_attack(t) -> void:
	if t == null:
		return
	target = t
	has_move_target = false
	state = State.ATTACK


func _process(delta: float) -> void:
	if game == null or game.is_over:
		return
	_fire_timer -= delta
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0 and _beam != null:
			_beam.visible = false
	match state:
		State.IDLE:
			var foe = game.nearest_hostile(global_position, side, aggro_range)
			if foe != null:
				order_attack(foe)
		State.MOVE:
			if not has_move_target:
				state = State.IDLE
			else:
				_move_toward(move_target, delta)
				if _flat_dist(global_position, move_target) < 0.05:
					has_move_target = false
					state = State.IDLE
		State.ATTACK:
			if target == null or not is_instance_valid(target) or not target.is_alive():
				target = null
				state = State.IDLE
			else:
				var d := _flat_dist(global_position, target.global_position)
				if d > attack_range:
					_move_toward(target.global_position, delta)
				else:
					_face(target.global_position, delta)
					if _fire_timer <= 0.0:
						_fire_timer = cooldown
						_fire_at(target)
	# Gentle hover bob above the board.
	var p := global_position
	p.y = game.hover_height() + sin(Time.get_ticks_msec() / 1000.0 * 3.0 + _bob_phase) * 0.005
	global_position = p


func _move_toward(world: Vector3, delta: float) -> void:
	var to := world - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.001:
		return
	_face(world, delta)
	global_position += to.normalized() * minf(speed * delta, dist)


func _face(world: Vector3, delta: float) -> void:
	var d := world - global_position
	d.y = 0.0
	if d.length_squared() > 0.000001:
		var want := atan2(-d.x, -d.z)
		rotation.y = lerp_angle(rotation.y, want, minf(delta * 8.0, 1.0))


func _flat_dist(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _fire_at(t) -> void:
	if _beam != null:
		var a := global_position
		var b: Vector3 = t.global_position
		var dist := a.distance_to(b)
		if dist > 0.01:
			_beam.global_position = (a + b) * 0.5
			_beam.look_at(b, Vector3.UP)
			_beam.scale = Vector3(1, 1, dist)
			_beam.visible = true
			_beam_timer = 0.12
	t.take_damage(damage)
