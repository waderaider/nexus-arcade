## TerraformWorld.gd - the living planet for TERRAFORM.
## Table-flat heightfield disc (48x48, ~4.5k tris): sculpt with hand
## presses, paint biomes, vertex-colored. Rebuilds only when dirty.
class_name TerraformWorld
extends Node3D

const N := 48
const RADIUS := 0.6
const WATER_LEVEL := 0.03

# Biome ids: -1 natural, 0 grass, 1 desert, 2 ice, 3 scorched
const BIOME_COLORS := {
	-1: Color(0.3, 0.65, 0.25), 0: Color(0.32, 0.68, 0.26),
	1: Color(0.9, 0.7, 0.35), 2: Color(0.88, 0.93, 1.0), 3: Color(0.22, 0.1, 0.08),
}
const WATER_COLOR := Color(0.15, 0.38, 0.85)
const SAND_COLOR := Color(0.85, 0.75, 0.5)
const ROCK_COLOR := Color(0.45, 0.42, 0.4)

var heights := PackedFloat32Array()
var paint := PackedInt32Array()  # -1 natural or biome id
var moisture := PackedFloat32Array()

var _mesh_inst: MeshInstance3D
var _dirty := true
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 12345
	heights.resize(N * N)
	paint.resize(N * N)
	moisture.resize(N * N)
	paint.fill(-1)
	for j in N:
		for i in N:
			var x := (float(i) / float(N - 1) * 2.0 - 1.0) * RADIUS
			var z := (float(j) / float(N - 1) * 2.0 - 1.0) * RADIUS
			var d := Vector2(x, z).length() / RADIUS
			var h := 0.10 * (1.0 - d * d)
			h += 0.05 * sin(x * 9.0) * cos(z * 7.0)
			h += 0.03 * sin(x * 23.0 + 1.7) * sin(z * 19.0 + 0.6)
			heights[j * N + i] = h if d <= 1.0 else -0.2
	_mesh_inst = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	_mesh_inst.material_override = mat
	add_child(_mesh_inst)
	# Water disc under the terrain.
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = RADIUS
	wm.bottom_radius = RADIUS
	wm.height = 0.02
	water.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = WATER_COLOR
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color.a = 0.85
	wmat.roughness = 0.2
	water.material_override = wmat
	water.position.y = WATER_LEVEL - 0.015
	add_child(water)
	# Table plinth.
	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = RADIUS + 0.06
	pm.bottom_radius = RADIUS + 0.1
	pm.height = 0.12
	plinth.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.24)
	pmat.roughness = 0.6
	plinth.material_override = pmat
	plinth.position.y = -0.09
	add_child(plinth)
	rebuild()


func idx(i: int, j: int) -> int:
	return j * N + i


func local_to_grid(p: Vector3) -> Vector2:
	return Vector2(
		(p.x / RADIUS * 0.5 + 0.5) * float(N - 1),
		(p.z / RADIUS * 0.5 + 0.5) * float(N - 1))


func height_at(p: Vector3) -> float:
	var g := local_to_grid(p)
	var i := clampi(int(round(g.x)), 0, N - 1)
	var j := clampi(int(round(g.y)), 0, N - 1)
	return heights[idx(i, j)]


func biome_at(p: Vector3) -> int:
	var g := local_to_grid(p)
	var i := clampi(int(round(g.x)), 0, N - 1)
	var j := clampi(int(round(g.y)), 0, N - 1)
	var k := idx(i, j)
	var pb := paint[k]
	if pb >= 0:
		return pb
	return natural_biome(k)


func natural_biome(k: int) -> int:
	var h: float = heights[k]
	if h < WATER_LEVEL + 0.015:
		return 0  # treated as grass-ish shore; water drawn by height
	if h > 0.22:
		return 2  # icy peaks... mapped to rock/snow by height shading
	return 0


func sculpt(p: Vector3, radius: float, delta: float) -> bool:
	var g := local_to_grid(p)
	var gr := radius / RADIUS * float(N - 1) * 0.5
	var ci := int(round(g.x))
	var cj := int(round(g.y))
	var touched := false
	var r := int(ceil(gr)) + 1
	for j in range(maxi(0, cj - r), mini(N, cj + r + 1)):
		for i in range(maxi(0, ci - r), mini(N, ci + r + 1)):
			var d := Vector2(i - ci, j - cj).length() / maxf(gr, 0.001)
			if d > 1.0:
				continue
			var fall := (cos(d * PI) + 1.0) * 0.5
			var k := idx(i, j)
			heights[k] = clampf(heights[k] + delta * fall, -0.12, 0.42)
			touched = true
	if touched:
		_dirty = true
	return touched


func paint_at(p: Vector3, radius: float, biome: int) -> bool:
	var g := local_to_grid(p)
	var gr := radius / RADIUS * float(N - 1) * 0.5
	var ci := int(round(g.x))
	var cj := int(round(g.y))
	var touched := false
	var r := int(ceil(gr)) + 1
	for j in range(maxi(0, cj - r), mini(N, cj + r + 1)):
		for i in range(maxi(0, ci - r), mini(N, ci + r + 1)):
			var d := Vector2(i - ci, j - cj).length() / maxf(gr, 0.001)
			if d > 1.0:
				continue
			paint[idx(i, j)] = biome
			touched = true
	if touched:
		_dirty = true
	return touched


func crater(p: Vector3, radius: float, depth: float) -> void:
	var g := local_to_grid(p)
	var gr := radius / RADIUS * float(N - 1) * 0.5
	var ci := int(round(g.x))
	var cj := int(round(g.y))
	var r := int(ceil(gr)) + 1
	for j in range(maxi(0, cj - r), mini(N, cj + r + 1)):
		for i in range(maxi(0, ci - r), mini(N, ci + r + 1)):
			var d := Vector2(i - ci, j - cj).length() / maxf(gr, 0.001)
			if d > 1.0:
				continue
			var k := idx(i, j)
			heights[k] = clampf(heights[k] - depth * (cos(d * PI) + 1.0) * 0.5, -0.12, 0.42)
			if d < 0.7:
				paint[k] = 3  # scorched
	_dirty = true


func vertex_color(k: int) -> Color:
	var h: float = heights[k]
	if h < WATER_LEVEL:
		return WATER_COLOR.darkened(0.15)
	var pb := paint[k]
	var c: Color
	if pb >= 0:
		c = BIOME_COLORS[pb]
	elif h < WATER_LEVEL + 0.03:
		c = SAND_COLOR
	elif h > 0.26:
		c = Color(0.92, 0.94, 1.0)  # snowcaps
	elif h > 0.17:
		c = ROCK_COLOR
	else:
		c = BIOME_COLORS[-1]
	# Moisture darkens greens.
	if pb <= 0 and moisture[k] > 0.5:
		c = c.darkened(0.12)
	return c


func rebuild() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(N * N)
	normals.resize(N * N)
	colors.resize(N * N)
	uvs.resize(N * N)
	var step := 2.0 * RADIUS / float(N - 1)
	for j in N:
		for i in N:
			var k := idx(i, j)
			var x := (float(i) / float(N - 1) * 2.0 - 1.0) * RADIUS
			var z := (float(j) / float(N - 1) * 2.0 - 1.0) * RADIUS
			verts[k] = Vector3(x, heights[k], z)
			uvs[k] = Vector2(float(i) / float(N - 1), float(j) / float(N - 1))
			# Central-difference normal.
			var hl: float = heights[idx(maxi(0, i - 1), j)]
			var hr: float = heights[idx(mini(N - 1, i + 1), j)]
			var hd: float = heights[idx(i, maxi(0, j - 1))]
			var hu: float = heights[idx(i, mini(N - 1, j + 1))]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			normals[k] = n
			colors[k] = vertex_color(k)
	var indices := PackedInt32Array()
	for j in N - 1:
		for i in N - 1:
			var a := idx(i, j)
			var b := idx(i + 1, j)
			var c := idx(i, j + 1)
			var d := idx(i + 1, j + 1)
			indices.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_inst.mesh = mesh
	_dirty = false


func tick(_delta: float) -> void:
	if _dirty:
		rebuild()
