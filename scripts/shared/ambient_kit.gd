class_name AmbientKit
extends RefCounted
## AmbientKit — Pixar-Style Animator's cheap ambient-life helpers (v0.11.0).
## Quest-3-cheap only: capped GPUParticles3D (additive, unlit), MultiMesh quad
## fields (1 draw call), emissive flicker (0 extra draws), vertex-shader sway.
## BANNED here: real lights, per-frame allocations in tick paths, morphs.
## All helpers are static; games own their node lifetimes.

## Capped ambient dust emitter: slow drifting motes, additive + unlit.
## count <= 64 per the animator guardrails.
static func dust(parent: Node3D, pos: Vector3, count := 24,
		color := Color(0.75, 0.85, 1.0, 0.45), size := 0.02,
		drift := 0.12, up := 0.03) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = mini(count, 64)
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.local_coords = true
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.0, 0.6, 1.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, up, 0)
	pm.initial_velocity_min = drift * 0.4
	pm.initial_velocity_max = drift
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.4
	pm.color = color
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.disable_fog = true
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	return p


## One-shot pooled burst (impact dust, paradox crackle, landing puffs).
## Transient: auto-frees after it finishes. Rare + capped = within budget.
static func burst(parent: Node, pos: Vector3, count := 16,
		color := Color(1, 1, 1, 0.8), speed := 2.5, size := 0.03,
		lifetime := 0.9) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var tree := (parent as Node).get_tree()
	if tree == null:
		return
	var p := GPUParticles3D.new()
	p.amount = mini(count, 64)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, -1.2, 0)
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = ramp
	pm.color_ramp = grad_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	if p is Node3D:
		(p as Node3D).global_position = pos
	p.emitting = true
	_free_later(p, lifetime + 0.4)


static func _free_later(n: Node, delay: float) -> void:
	var tree := n.get_tree()
	if tree == null:
		n.queue_free()
		return
	await tree.create_timer(delay).timeout
	if is_instance_valid(n):
		n.queue_free()


## MultiMesh quad field: 1 draw call for birds / sprinkles / specks.
## Caller owns the matrices (update with zero-alloc loops).
static func quad_field(count: int, quad_size: float, color: Color,
		additive := true, alpha := 1.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, alpha)
	mat.disable_fog = true
	quad.material = mat
	mm.mesh = quad
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	for i in count:
		mm.set_instance_color(i, color)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -50, 0)))
	return mmi


## Organic flicker 0..1: layered sines, never in sync across phases.
static func flicker_value(t: float, phase: float, speed := 1.0) -> float:
	var a := sin(t * speed * 7.3 + phase)
	var b := sin(t * speed * 13.7 + phase * 1.71)
	var c := sin(t * speed * 3.1 + phase * 0.63)
	return clampf(0.62 + 0.38 * (0.55 * a + 0.3 * b + 0.15 * c), 0.0, 1.0)


## Tick a prebuilt flicker list: each entry = [material, base, amp, speed, phase].
## Zero-alloc: the array and its sub-arrays are built once at setup.
static func tick_flicker(entries: Array, t: float, dread := 0.0) -> void:
	for e in entries:
		var m := e[0] as StandardMaterial3D
		if m == null:
			continue
		var v := flicker_value(t, float(e[4]), float(e[3]))
		if dread > 0.0:
			# Hunted: scramble the phase so flames desync = dread.
			v = flicker_value(t * 3.7, float(e[4]) * 7.0 + t * 2.0, float(e[3]))
			v = lerpf(v, 0.25, dread * 0.5)
		m.emission_energy_multiplier = float(e[1]) + float(e[2]) * v


## Breath overlay 0..1 for idle life (0.25Hz per the animator spec).
static func breath_value(t: float, phase := 0.0) -> float:
	return 0.5 + 0.5 * sin(t * TAU * 0.25 + phase)
