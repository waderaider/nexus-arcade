## MinigolfHoleBuilder.gd - data-driven hole construction for NEXUS GREENS.
## Builds a complete hole (visuals + physics + decorations) from a compact spec.
## Special mechanics (gears, conveyors, etc.) attach as dedicated nodes.
## Shared materials across all 18 holes (draw-call discipline).
extends RefCounted
class_name MinigolfHoleBuilder

# Shared materials (created once, reused by all holes).
static var _mat_felt: StandardMaterial3D = null
static var _mat_wood: StandardMaterial3D = null
static var _mat_brass: StandardMaterial3D = null
static var _mat_dark: StandardMaterial3D = null
static var _mat_cup: StandardMaterial3D = null
static var _mats_ready := false


static func _ensure_mats() -> void:
	if _mats_ready:
		return
	_mats_ready = true
	_mat_felt = _pbr(Color(0.13, 0.42, 0.20), 0.0, 0.95)
	_mat_wood = _pbr(Color(0.45, 0.30, 0.16), 0.0, 0.8)
	_mat_brass = _pbr(Color(0.72, 0.53, 0.25), 0.9, 0.35)
	_mat_dark = _pbr(Color(0.06, 0.06, 0.08), 0.2, 0.7)
	_mat_cup = _pbr(Color(0.01, 0.01, 0.01), 0.0, 1.0)


static func _pbr(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


## Build a hole from a spec dict. Returns the MinigolfHole node.
## Spec: {number, name, par, zone, tee: Vector3 (local), cup: Vector3 (local),
##        size: Vector2 (green XZ extents), obstacles: [{pos, size}],
##        hazards: [{kind, pos, size}], rails_height: float}
static func build(spec: Dictionary) -> MinigolfHole:
	_ensure_mats()
	var hole := MinigolfHole.new()
	hole.hole_number = spec.get("number", 1)
	hole.hole_name = spec.get("name", "Untitled")
	hole.par = spec.get("par", 2)
	hole.zone = spec.get("zone", "greens")

	var size: Vector2 = spec.get("size", Vector2(1.6, 2.4))
	var tee: Vector3 = spec.get("tee", Vector3(0, 0, -size.y / 2 + 0.3))
	var cup: Vector3 = spec.get("cup", Vector3(0, 0, size.y / 2 - 0.3))
	hole.set_meta("tee", tee)
	hole.set_meta("cup", cup)
	hole.set_meta("size", size)
	hole.set_meta("cup_radius", 0.054)

	_build_green(hole, size)
	_build_rails(hole, size, float(spec.get("rails_height", 0.12)))
	_build_cup_and_flag(hole, cup, spec.get("zone", "greens"))
	_build_tee_markers(hole, tee, spec.get("zone", "greens"))
	_build_obstacles(hole, spec.get("obstacles", []))
	_build_hazards(hole, spec.get("hazards", []))

	return hole


static func _build_green(hole: MinigolfHole, size: Vector2) -> void:
	var green := MeshInstance3D.new()
	green.name = "Green"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.08, size.y)
	green.mesh = box
	green.material_override = _mat_felt
	green.position = Vector3(0, -0.04, 0)
	hole.add_child(green)
	# Subtle edge trim.
	var trim := MeshInstance3D.new()
	trim.name = "Trim"
	var tbox := BoxMesh.new()
	tbox.size = Vector3(size.x + 0.06, 0.02, size.y + 0.06)
	trim.mesh = tbox
	trim.material_override = _mat_wood
	trim.position = Vector3(0, -0.09, 0)
	hole.add_child(trim)


static func _build_rails(hole: MinigolfHole, size: Vector2, height: float) -> void:
	# Wooden rails around the perimeter (with a gap at tee entry).
	var rail_t := 0.06
	var y := height / 2.0
	var specs := [
		[Vector3(0, y, -size.y / 2), Vector3(size.x + rail_t * 2, height, rail_t)],
		[Vector3(0, y, size.y / 2), Vector3(size.x + rail_t * 2, height, rail_t)],
		[Vector3(-size.x / 2, y, 0), Vector3(rail_t, height, size.y)],
		[Vector3(size.x / 2, y, 0), Vector3(rail_t, height, size.y)],
	]
	for s in specs:
		var rail := MeshInstance3D.new()
		rail.name = "Rail"
		var box := BoxMesh.new()
		box.size = s[1]
		rail.mesh = box
		rail.material_override = _mat_wood
		rail.position = s[0]
		# Bevel the top edge visually with a brass cap strip.
		hole.add_child(rail)
		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(s[1].x + 0.01, 0.015, s[1].z + 0.01)
		cap.mesh = cbox
		cap.material_override = _mat_brass
		cap.position = s[0] + Vector3(0, height / 2.0 + 0.007, 0)
		hole.add_child(cap)
	# Record rail AABBs for physics.
	var aabbs := []
	for s in specs:
		var pos: Vector3 = s[0]
		var sz: Vector3 = s[1]
		aabbs.append(AABB(pos - sz / 2.0, sz))
	hole.set_meta("rail_aabbs", aabbs)


static func _build_cup_and_flag(hole: MinigolfHole, cup: Vector3, zone: String) -> void:
	# Cup: dark cylinder + brass rim.
	var cup_mesh := MeshInstance3D.new()
	cup_mesh.name = "Cup"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.054
	cyl.bottom_radius = 0.054
	cyl.height = 0.02
	cup_mesh.mesh = cyl
	cup_mesh.material_override = _mat_cup
	cup_mesh.position = cup + Vector3(0, 0.005, 0)
	hole.add_child(cup_mesh)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.054
	tor.outer_radius = 0.064
	rim.mesh = tor
	rim.material_override = _mat_brass
	rim.position = cup + Vector3(0, 0.012, 0)
	hole.add_child(rim)
	# Flagstick: pole + pennant (zone accent color).
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.008
	pcyl.bottom_radius = 0.008
	pcyl.height = 0.75
	pole.mesh = pcyl
	var pmat := _pbr(Color(0.85, 0.85, 0.88), 0.9, 0.3)
	pole.material_override = pmat
	pole.position = cup + Vector3(0, 0.375, 0)
	hole.add_child(pole)
	var flag := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.22, 0.14, 0.005)
	flag.mesh = fbox
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = MinigolfTheme.accent_for(zone)
	fmat.emission_enabled = true
	fmat.emission = MinigolfTheme.accent_for(zone)
	fmat.emission_energy_multiplier = 0.4
	flag.material_override = fmat
	flag.position = cup + Vector3(0.12, 0.65, 0)
	hole.add_child(flag)
	# Store flag for victory wave.
	hole.set_meta("flag", flag)


static func _build_tee_markers(hole: MinigolfHole, tee: Vector3, zone: String) -> void:
	for sx in [-1.0, 1.0]:
		var marker := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.03
		sph.height = 0.06
		marker.mesh = sph
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = MinigolfTheme.accent_for(zone)
		mmat.emission_enabled = true
		mmat.emission = MinigolfTheme.accent_for(zone)
		mmat.emission_energy_multiplier = 0.8
		marker.material_override = mmat
		marker.position = tee + Vector3(sx * 0.12, 0.03, 0)
		hole.add_child(marker)


static func _build_obstacles(hole: MinigolfHole, obstacles: Array) -> void:
	var aabbs := []
	for ob in obstacles:
		var pos: Vector3 = ob["pos"]
		var size: Vector3 = ob["size"]
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _mat_wood
		mesh.position = pos
		hole.add_child(mesh)
		aabbs.append(AABB(pos - size / 2.0, size))
	var existing: Array = hole.get_meta("rail_aabbs", [])
	existing.append_array(aabbs)
	hole.set_meta("all_aabbs", existing)


static func _build_hazards(hole: MinigolfHole, hazards: Array) -> void:
	var list := []
	for hz in hazards:
		list.append(hz)
		# Visual: colored plane marking the hazard.
		var vis := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var sz: Vector3 = hz["size"]
		quad.size = Vector2(sz.x, sz.z)
		vis.mesh = quad
		var hmat := StandardMaterial3D.new()
		var kind: String = hz["kind"]
		var c := Color(0.2, 0.5, 0.9) if kind == "water" else Color(0.85, 0.75, 0.45)
		hmat.albedo_color = Color(c.r, c.g, c.b, 0.75)
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vis.material_override = hmat
		vis.rotation_degrees.x = -90
		vis.position = (hz["pos"] as Vector3) + Vector3(0, 0.005, 0)
		hole.add_child(vis)
	hole.set_meta("hazards", list)
