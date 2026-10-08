## PassthroughFX.gd - passthrough illusions autoload for NEXUS ARCADE
## (autoload: PassthroughFX). v0.9.0 shared-systems build (TECH_DEMO_PLAN §3a-bis).
##
## Cheap quads/decals that make virtual things appear to touch the real world:
##   scorch_decal(pos, normal) - fading burn mark pinned to a real wall/floor
##                               (dragon fire breath, explosion soot); pool of 8
##   splash_ripple(pos)        - expanding ring on the real floor (AR Fishing
##                               catch, Deep Dive breach)
##   wall_portal(pos)         - glowing frame quad anchored to a wall
## Plus: portal_frame_on_wall(wall_dict, color), creature_climb(node, wall_dict).
##
## All helpers are headless-safe (node building only). Scorch/splash are
## unshaded quads: ~1 draw call each. NOTE: placement against real geometry
## needs validation on Quest 3 (RoomKit walls/floors supply pos/normal).
extends Node

const SCORCH_POOL := 8
const SCORCH_FADE_TIME := 60.0

var _scorch_pool: Array[MeshInstance3D] = []
var _scorch_tweens: Array = []  # parallel to _scorch_pool; killed on reuse
var _scorch_idx := 0


## Darkened fading decal quad pinned to a real wall/floor. Pool of 8: the
## oldest scorch is reused when the pool is full. `normal` orients the quad.
func scorch_decal(pos: Vector3, normal: Vector3 = Vector3.UP, size: float = 0.4, parent: Node3D = null) -> MeshInstance3D:
	var host := _host(parent)
	if host == null:
		return null
	var decal: MeshInstance3D
	var slot := -1
	if _scorch_pool.size() < SCORCH_POOL:
		decal = _make_scorch_quad()
		_scorch_pool.append(decal)
		_scorch_tweens.append(null)
		slot = _scorch_pool.size() - 1
	else:
		slot = _scorch_idx
		_scorch_idx = (_scorch_idx + 1) % SCORCH_POOL
		decal = _scorch_pool[slot]
		var old_tw = _scorch_tweens[slot]
		if old_tw != null and is_instance_valid(old_tw):
			(old_tw as Tween).kill()
		_scorch_tweens[slot] = null
	if decal.get_parent() != host:
		if decal.get_parent() != null:
			decal.get_parent().remove_child(decal)
		host.add_child(decal)
	decal.global_position = pos + normal.normalized() * 0.01
	_orient_to_normal(decal, normal)
	var s := maxf(size, 0.1)
	decal.scale = Vector3(s, s, s)
	decal.visible = true
	var mat := decal.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = 0.85
		if decal.is_inside_tree():
			var tw := decal.create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, SCORCH_FADE_TIME)
			_scorch_tweens[slot] = tw
	return decal


## Expanding ring on the real floor at `pos`. One-shot, frees itself.
func splash_ripple(pos: Vector3, color: Color = Color(0.5, 0.9, 1.0), max_radius: float = 0.8, parent: Node3D = null) -> MeshInstance3D:
	var host := _host(parent)
	if host == null:
		return null
	var ring := MeshInstance3D.new()
	ring.name = "SplashRipple"
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	ring.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _ring_texture()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	host.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.02
	ring.rotation = Vector3(-PI * 0.5, 0, 0)  # quad XY -> flat on floor
	ring.scale = Vector3(0.1, 0.1, 0.1)
	if ring.is_inside_tree():
		var tw := ring.create_tween()
		tw.set_parallel(true)
		var d := maxf(max_radius, 0.2)
		tw.tween_property(ring, "scale", Vector3(d, d, d), 0.9)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
		tw.chain().tween_callback(ring.queue_free)
	return ring


## Glowing frame quad (portal look) placed at `pos`, facing `normal`.
## Cheap: 4 emissive edge bars + one translucent inner quad (~5 draw calls).
func wall_portal(pos: Vector3, normal: Vector3 = Vector3.FORWARD, color: Color = Color(0.4, 0.9, 1.0), size: float = 1.0, parent: Node3D = null) -> Node3D:
	var host := _host(parent)
	if host == null:
		return null
	return portal_frame_on_wall({"position": pos, "normal": normal}, color, size, host)


## Glowing frame anchored to a RoomKit wall dict
## ({position, size: Vector2, normal}). Centers the frame on the wall.
func portal_frame_on_wall(wall_dict: Dictionary, color: Color = Color(0.4, 0.9, 1.0), size: float = 1.2, parent: Node3D = null) -> Node3D:
	var host := _host(parent)
	if host == null or wall_dict.is_empty():
		return null
	var frame := Node3D.new()
	frame.name = "PassthroughPortal"
	host.add_child(frame)
	var pos: Vector3 = wall_dict.get("position", Vector3.ZERO)
	var normal: Vector3 = wall_dict.get("normal", Vector3.FORWARD)
	frame.global_position = pos + normal.normalized() * 0.03
	_orient_to_normal(frame, normal)
	var s := maxf(size, 0.3)
	var bar := s * 0.08
	var glow := GraphicsPolish.glow(color, 2.2)
	# 4 edge bars (in the frame's local XY plane).
	var edges := [
		[Vector3(0, s * 0.5, 0), Vector3(s + bar, bar, 0.02)],
		[Vector3(0, -s * 0.5, 0), Vector3(s + bar, bar, 0.02)],
		[Vector3(-s * 0.5, 0, 0), Vector3(bar, s + bar, 0.02)],
		[Vector3(s * 0.5, 0, 0), Vector3(bar, s + bar, 0.02)],
	]
	for e in edges:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		mi.mesh = bm
		mi.material_override = glow
		mi.position = e[0]
		frame.add_child(mi)
	# Translucent inner shimmer.
	var inner := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	inner.mesh = q
	var im := StandardMaterial3D.new()
	im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.albedo_color = Color(color.r, color.g, color.b, 0.18)
	im.emission_enabled = true
	im.emission = color
	im.emission_energy_multiplier = 0.8
	inner.material_override = im
	frame.add_child(inner)
	if frame.is_inside_tree():
		var tw := frame.create_tween()
		tw.set_loops()
		tw.tween_property(im, "emission_energy_multiplier", 1.6, 1.1)\
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(im, "emission_energy_multiplier", 0.8, 1.1)\
			.set_trans(Tween.TRANS_SINE)
	return frame


## Animation helper: `node` emerges from behind a wall edge (horror games).
## Starts the node hidden just behind the wall plane, then slides it out
## with a squash pop. `wall_dict` is a RoomKit wall ({position, normal}).
func creature_climb(node: Node3D, wall_dict: Dictionary, out_distance: float = 0.6, duration: float = 1.2) -> void:
	if node == null or not is_instance_valid(node) or wall_dict.is_empty():
		return
	var pos: Vector3 = wall_dict.get("position", Vector3.ZERO)
	var normal: Vector3 = wall_dict.get("normal", Vector3.FORWARD).normalized()
	var hidden_pos := pos - normal * 0.25
	hidden_pos.y = maxf(pos.y - 0.8, 0.15)
	var out_pos := pos + normal * out_distance
	out_pos.y = hidden_pos.y + 0.5
	node.global_position = hidden_pos
	node.visible = true
	if not node.is_inside_tree():
		return
	var tw := node.create_tween()
	tw.set_parallel(false)
	tw.tween_property(node, "global_position", out_pos, duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(node) and Engine.get_main_loop().root.get_node_or_null("JuiceFX") != null:
			(Engine.get_main_loop().root.get_node("JuiceFX") as Node).squash_stretch(node)
	)


# ------------------------------------------------------------------ util ---

func _host(parent: Node3D) -> Node3D:
	if parent != null and is_instance_valid(parent):
		return parent
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var cs: Node = tree.current_scene
	if cs is Node3D:
		return cs as Node3D
	return null


func _orient_to_normal(n: Node3D, normal: Vector3) -> void:
	var nn := normal.normalized()
	if nn.length() < 0.01:
		return
	# QuadMesh faces +Z; rotate +Z onto the normal.
	var z := nn
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.99:
		up = Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	n.global_transform = Transform3D(Basis(x, y, z), n.global_position)


func _make_scorch_quad() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ScorchDecal"
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _scorch_texture()
	mat.albedo_color = Color(0.05, 0.03, 0.02, 0.85)
	mi.material_override = mat
	mi.visible = false
	return mi


var _scorch_tex: Texture2D = null
var _ring_tex: Texture2D = null


func _scorch_texture() -> Texture2D:
	if _scorch_tex != null:
		return _scorch_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.55, Color(1, 1, 1, 0.7))
	g.add_point(0.85, Color(1, 1, 1, 0.15))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_scorch_tex = t
	return t


func _ring_texture() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.62, Color(1, 1, 1, 0))
	g.add_point(0.78, Color(1, 1, 1, 1))
	g.add_point(0.92, Color(1, 1, 1, 0.4))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_ring_tex = t
	return t


