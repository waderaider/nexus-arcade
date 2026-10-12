class_name AmbientLife
extends RefCounted
## v0.11.0 (Pixar-Style Animator plan): shared ambient-life fields.
## MultiMesh instanced quads — 1 draw call per field, ≤48 instances,
## CPU matrix update ~0.05ms. Techniques: butterfly/bee fields, rising
## embers, falling petals, drifting dust, static ground sprinkles.
## Quest-3-cheap: no real lights, no per-frame allocations in the update.

const MODE_BUTTERFLY := 0
const MODE_EMBER := 1
const MODE_PETAL := 2
const MODE_DUST := 3


## A single self-updating ambient field. Add to any game scene; it ticks
## itself and frees with its parent. Zero-alloc update loop.
class DriftField:
	extends Node3D
	var _mm: MultiMeshInstance3D
	var _count := 0
	var _mode := 0
	var _extents := Vector3(2.0, 1.5, 2.0)
	var _t := 0.0
	var _seed: PackedFloat32Array
	var _base_pos: PackedVector3Array
	var _color_a := Color.WHITE
	var _color_b := Color.WHITE
	var _xform := Transform3D.IDENTITY
	var _basis := Basis.IDENTITY

	func _init(mode: int, count: int, extents: Vector3,
			color_a: Color, color_b: Color) -> void:
		_mode = mode
		_count = mini(count, 48)
		_extents = extents
		_color_a = color_a
		_color_b = color_b
		_seed = PackedFloat32Array()
		_seed.resize(_count)
		_base_pos = PackedVector3Array()
		_base_pos.resize(_count)
		for i in _count:
			_seed[i] = randf() * 100.0
			_base_pos[i] = Vector3(
				randf_range(-extents.x, extents.x),
				randf_range(0.1, extents.y),
				randf_range(-extents.z, extents.z))

	func _ready() -> void:
		_mm = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _make_quad()
		mm.instance_count = _count
		_mm.multimesh = mm
		_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mm)

	func _make_quad() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		q.material = GraphicsPolish.glow(Color(1, 1, 1), 1.0)
		return q

	func _process(delta: float) -> void:
		_t += delta
		for i in _count:
			var sd := _seed[i]
			var bp: Vector3 = _base_pos[i]
			var p := bp
			var sc := 1.0
			match _mode:
				MODE_BUTTERFLY:
					# Lissajous wander + wing flap via scale-x (|sin| = 2-frame feel).
					p += Vector3(
						sin(_t * 0.7 + sd) * 0.35,
						sin(_t * 1.1 + sd * 1.7) * 0.18,
						cos(_t * 0.5 + sd * 0.9) * 0.35)
					sc = 0.6 + 0.4 * absf(sin(_t * 9.0 + sd))
					_basis = Basis(Vector3.UP, sd + _t * 0.6).scaled(
						Vector3(sc, 1.0, 1.0))
				MODE_EMBER:
					# Rise + sway, loop back to the floor.
					var rise := fmod(_t * (0.25 + _seed[i] * 0.002) + sd * 0.05, 1.0)
					p = Vector3(
						bp.x + sin(_t * 1.3 + sd) * 0.12,
						0.05 + rise * _extents.y,
						bp.z + cos(_t * 1.1 + sd) * 0.12)
					sc = (1.0 - rise) * 0.9 + 0.1
					_basis = Basis.IDENTITY.scaled(Vector3(sc, sc, sc))
				MODE_PETAL:
					# Fall + sway + tumble.
					var fall := fmod(_t * 0.12 + sd * 0.03, 1.0)
					p = Vector3(
						bp.x + sin(_t * 0.9 + sd) * 0.25,
						_extents.y * (1.0 - fall) + 0.02,
						bp.z + cos(_t * 0.7 + sd) * 0.25)
					_basis = Basis(Vector3.UP, sd + _t * 1.4).rotated(
						Vector3.RIGHT, _t * 0.9 + sd)
				_:
					# MODE_DUST: slow curl drift.
					p += Vector3(
						sin(_t * 0.23 + sd) * 0.3,
						sin(_t * 0.17 + sd * 2.1) * 0.2,
						cos(_t * 0.19 + sd) * 0.3)
					_basis = Basis.IDENTITY
			_xform = Transform3D(_basis, p)
			_mm.multimesh.set_instance_transform(i, _xform)
			_mm.multimesh.set_instance_color(i,
				_color_a.lerp(_color_b, _hash01(sd)))


	func _hash01(x: float) -> float:
		var s := sin(x * 127.1) * 43758.5453
		return s - floorf(s)


## Butterfly/bee field: wandering flapping quads. 1 draw call.
static func butterflies(parent: Node3D, count := 14,
		extents := Vector3(2.5, 1.8, 2.5),
		color_a := Color(1.0, 0.75, 0.25),
		color_b := Color(0.6, 0.9, 1.0)) -> Node3D:
	var f := DriftField.new(MODE_BUTTERFLY, count, extents, color_a, color_b)
	parent.add_child(f)
	return f


## Ember field: rising sparks for battle zones, braziers, candles.
static func embers(parent: Node3D, count := 20,
		extents := Vector3(1.5, 2.0, 1.5),
		color_a := Color(1.0, 0.45, 0.1),
		color_b := Color(1.0, 0.8, 0.3)) -> Node3D:
	var f := DriftField.new(MODE_EMBER, count, extents, color_a, color_b)
	parent.add_child(f)
	return f


## Petal field: falling petals with tumble (celebrations, gardens).
static func petals(parent: Node3D, count := 24,
		extents := Vector3(3.0, 2.5, 3.0),
		color_a := Color(1.0, 0.5, 0.7),
		color_b := Color(1.0, 0.85, 0.4)) -> Node3D:
	var f := DriftField.new(MODE_PETAL, count, extents, color_a, color_b)
	parent.add_child(f)
	return f


## Dust field: slow curl drift for light shafts, projector beams.
static func dust(parent: Node3D, count := 24,
		extents := Vector3(2.0, 1.5, 2.0)) -> Node3D:
	var f := DriftField.new(MODE_DUST, count, extents,
		Color(0.75, 0.85, 1.0, 0.5), Color(1.0, 0.95, 0.8, 0.5))
	parent.add_child(f)
	return f


## Ground-cover sprinkles: STATIC instanced quads over floors (technique 3).
## 1 draw call, 0 CPU — hides flat terrain, the cheapest "floor is alive" trick.
static func sprinkles(parent: Node3D, count := 40,
		extents := Vector2(3.0, 3.0), y := 0.02,
		color_a := Color(0.9, 0.6, 0.3),
		color_b := Color(0.4, 0.8, 0.4)) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := PlaneMesh.new()
	q.size = Vector2(0.05, 0.05)
	q.orientation = PlaneMesh.FACE_Y
	q.material = GraphicsPolish.pbr(Color.WHITE, 0.0, 0.9)
	mm.mesh = q
	count = mini(count, 48)
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in count:
		var t := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3.ONE * rng.randf_range(0.6, 1.4)),
			Vector3(rng.randf_range(-extents.x, extents.x), y,
				rng.randf_range(-extents.y, extents.y)))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, color_a.lerp(color_b, rng.randf()))
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
