## SiegeCastle.gd - procedural floor castles for SIEGE ENGINEER.
## Built from CraftPix medieval-house parts (converted to GLB in-house).
## Rigid-body destruction, ~48 active bricks capped, the rest static decor.
## 12-castle campaign layouts are deterministic per castle index.
class_name SiegeCastle
extends Node3D

const MODEL_DIR := "res://assets/models/siege/"
const MAX_RIGID := 48

var castle_idx := 0
var target_toppled := false

var _bricks: Array = []  # [{body: RigidBody3D, home: Vector3, up: Vector3}]
var _target: MeshInstance3D
var _target_home := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func build(idx: int, center: Vector3) -> void:
	castle_idx = idx
	target_toppled = false
	_rng.seed = idx * 7919 + 13
	_bricks.clear()
	var radius := minf(1.8, 1.05 + idx * 0.07)
	var segs := mini(12, 8 + idx / 2)
	var gate_angle := 0.0  # faces the player (player is at -Z of center)
	# Outer wall ring.
	for s in segs:
		var ang := TAU * float(s) / float(segs)
		if absf(wrapf(ang - gate_angle, -PI, PI)) < TAU / float(segs) * 0.6:
			_add_part("castle_gate.glb", center, radius, ang, true, 5.0)
		else:
			var wall: String = ["castle_wall_01.glb", "castle_wall_02.glb", "castle_wall_03.glb"][s % 3]
			_add_part(wall, center, radius, ang, true, 6.0)
	# Corner towers: stacked foundations + roof.
	var sway_shader := load("res://assets/shaders/ambient_sway.gdshader") as Shader
	for k in 4:
		var ang := PI / 4.0 + k * PI / 2.0
		var base := center + Vector3(cos(ang), 0, sin(ang)) * radius * 0.82
		var h := 0.0
		for lvl in 2 + mini(2, idx / 4):
			_add_part("castle_foundation_0%d.glb" % (1 + (k + lvl) % 2),
					base + Vector3(0, h, 0), 0.0, ang, false, 8.0)
			h += 0.85
		_add_part("castle_roof.glb", base + Vector3(0, h + 0.15, 0), 0.0, ang, false, 3.0)
		_add_pennant(_last_body(), sway_shader)
	# Central keep: square of walls + roof + the golden target.
	var keep_r := 0.55
	for s in 4:
		var ang := s * PI / 2.0 + PI / 4.0
		_add_part("castle_wall_0%d.glb" % (1 + s % 3), center, keep_r, ang, true, 6.0)
	_add_part("castle_roof.glb", center + Vector3(0, 1.75, 0), 0.0, 0.3, false, 3.0)
	_add_pennant(_last_body(), sway_shader)
	# Stairs decor near the gate (static).
	for s in [-0.5, 0.5]:
		_add_decor("castle_stairs.glb", center + Vector3(s, 0, -radius - 0.4), 0.0)
	# The golden crown target on the keep (rigid: it topples with the keep).
	_target_home = center + Vector3(0, 2.05, 0)
	var trb := RigidBody3D.new()
	trb.mass = 1.0
	add_child(trb)
	trb.position = _target_home
	_target = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.12
	cm.height = 0.14
	_target.mesh = cm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.2)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.75, 0.15)
	gold.emission_energy_multiplier = 2.5
	gold.metallic = 0.9
	gold.roughness = 0.25
	_target.material_override = gold
	trb.add_child(_target)
	var tcs := CollisionShape3D.new()
	var ts := SphereShape3D.new()
	ts.radius = 0.12
	tcs.shape = ts
	trb.add_child(tcs)
	_target.set_meta("rb", trb)


func _model(path: String) -> Node3D:
	var ps: PackedScene = load(MODEL_DIR + path) as PackedScene
	if ps == null:
		return null
	return ps.instantiate() as Node3D


func _part_aabb(node: Node3D) -> AABB:
	# Local-space AABB: the collision shape lives on the body with the
	# model re-zeroed under it, so only local transforms apply.
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: AABB = (mi as MeshInstance3D).get_aabb()
		var lt: Transform3D = (mi as MeshInstance3D).transform
		for cx in [m.position.x, m.position.x + m.size.x]:
			for cy in [m.position.y, m.position.y + m.size.y]:
				for cz in [m.position.z, m.position.z + m.size.z]:
					var c: Vector3 = lt * Vector3(cx, cy, cz)
					if first:
						box = AABB(c, Vector3.ZERO)
						first = false
					else:
						box = box.expand(c)
	if first:
		box = AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 0.5, 0.5))
	return box


## Last brick body added (animator: pennant mount).
func _last_body() -> Node3D:
	if _bricks.is_empty():
		return self
	return _bricks[_bricks.size() - 1]["body"] as Node3D


## Animator: pennant on a pole riding the roof brick (topples with it).
## Flag waves via the shared vertex-shader sway (gust envelope, 0 CPU).
func _add_pennant(mount: Node3D, sway_shader: Shader) -> void:
	if mount == null or sway_shader == null:
		return
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.02
	cyl.height = 0.6
	pole.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.22, 0.12)
	wood.roughness = 0.9
	pole.material_override = wood
	pole.position = Vector3(0, 0.55, 0)
	mount.add_child(pole)
	var flag := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.36, 0.2)
	pm.subdivide_width = 6
	flag.mesh = pm
	var smat := ShaderMaterial.new()
	smat.shader = sway_shader
	smat.set_shader_parameter("albedo_color", Color(0.8, 0.14, 0.18, 1.0))
	smat.set_shader_parameter("sway_amp", 0.05)
	smat.set_shader_parameter("sway_speed", 2.2)
	flag.material_override = smat
	flag.position = Vector3(0.2, 0.72, 0)
	mount.add_child(flag)


func _add_part(model: String, center: Vector3, ring_r: float, ang: float, tangent: bool, mass: float) -> void:
	var node := _model(model)
	if node == null:
		return
	var yaw := ang + PI / 2.0 if tangent else ang
	var pos := center + Vector3(cos(ang), 0, sin(ang)) * ring_r if ring_r > 0.0 else center
	add_child(node)
	node.position = pos
	node.rotation.y = yaw
	var box := _part_aabb(node)
	var shape := BoxShape3D.new()
	shape.size = box.size * 0.95 + Vector3(0.02, 0.02, 0.02)
	if _bricks.size() < MAX_RIGID:
		var rb := RigidBody3D.new()
		rb.mass = mass
		rb.physics_material_override = _brick_phys()
		add_child(rb)
		remove_child(node)
		rb.add_child(node)
		node.position = Vector3.ZERO
		node.rotation = Vector3.ZERO
		rb.position = pos
		rb.rotation.y = yaw
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		_bricks.append({"body": rb, "home": pos, "up": Vector3.UP})
	else:
		var sb := StaticBody3D.new()
		add_child(sb)
		remove_child(node)
		sb.add_child(node)
		node.position = Vector3.ZERO
		sb.position = pos
		sb.rotation.y = yaw
		var cs2 := CollisionShape3D.new()
		cs2.shape = shape
		sb.add_child(cs2)


func _add_decor(model: String, pos: Vector3, yaw: float) -> void:
	var node := _model(model)
	if node == null:
		return
	add_child(node)
	node.position = pos
	node.rotation.y = yaw


func await_sync(_node: Node3D) -> void:
	pass


func _brick_phys() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	return pm


## Fraction of bricks displaced/toppled (0..1). Target toppled = instant win.
func assess() -> Dictionary:
	var displaced := 0
	for b in _bricks:
		var rb: RigidBody3D = b["body"]
		if not is_instance_valid(rb):
			continue
		var moved: Vector3 = rb.global_position - (b["home"] as Vector3)
		var tilt := (rb.global_transform.basis.y - Vector3.UP).length()
		if moved.length() > 0.45 or tilt > 0.75:
			displaced += 1
	var pct := float(displaced) / maxf(1.0, float(_bricks.size()))
	if is_instance_valid(_target):
		var tm: Vector3 = _target.global_position - _target_home
		target_toppled = tm.length() > 0.5
	return {"pct": pct, "displaced": displaced, "total": _bricks.size()}


func target_pos() -> Vector3:
	return _target_home


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_bricks.clear()
	_target = null
