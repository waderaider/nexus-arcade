## GraphicsPolish.gd - shared graphics upgrade kit for NEXUS ARCADE.
## Static helpers: PBR material factory, emissive glow, light rigs, particle
## juice (sparks/confetti/trails), and styled floating UI labels.
## All helpers are headless-safe: they only build nodes/materials, never
## require XR hardware or a rendering device at parse time.
extends RefCounted
class_name GraphicsPolish


## PBR material factory.
static func pbr(color: Color, metallic: float = 0.0, roughness: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = clampf(metallic, 0.0, 1.0)
	m.roughness = clampf(roughness, 0.05, 1.0)
	return m


## Named PBR presets: "plastic", "metal", "glass", "matte", "rubber", "neon".
static func pbr_preset(color: Color, preset: String = "plastic") -> StandardMaterial3D:
	match preset:
		"metal":
			return pbr(color, 0.9, 0.25)
		"glass":
			var m := pbr(color, 0.1, 0.05)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			return m
		"matte":
			return pbr(color, 0.0, 0.9)
		"rubber":
			return pbr(color, 0.0, 0.75)
		"neon":
			return glow(color, 1.6)
		_:
			return pbr(color, 0.15, 0.45)


## Emissive glow material (unshaded bright + emission).
static func glow(color: Color, intensity: float = 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = intensity
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Soft pulsing glow: call each frame with a phase to animate emission.
static func pulse_glow(mat: StandardMaterial3D, base: float, amp: float, t: float, speed: float = 2.0) -> void:
	if mat == null:
		return
	mat.emission_energy_multiplier = base + amp * (0.5 + 0.5 * sin(t * speed))


## Three-point light rig: key (shadowed), fill, rim. Returns the key light.
static func make_light_rig(parent: Node3D, key_energy: float = 1.2) -> DirectionalLight3D:
	var key := DirectionalLight3D.new()
	key.name = "PolishKeyLight"
	key.light_energy = key_energy
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	parent.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "PolishFillLight"
	fill.light_energy = 0.5
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.position = Vector3(-2.0, 2.0, 2.0)
	fill.omni_range = 8.0
	parent.add_child(fill)

	var rim := SpotLight3D.new()
	rim.name = "PolishRimLight"
	rim.light_energy = 0.8
	rim.light_color = Color(1.0, 0.6, 0.9)
	rim.position = Vector3(2.0, 2.5, -2.0)
	rim.spot_range = 10.0
	parent.add_child(rim)
	return key


## Warm point light for accenting a single object.
static func make_point_light(parent: Node3D, pos: Vector3, color: Color, energy: float = 1.0, light_range: float = 4.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.position = pos
	parent.add_child(l)
	return l


## One-shot spark burst at a position. Frees itself when done.
static func spawn_sparks(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.8, 0.2), amount: int = 24) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	mat.color = color
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var qm := glow(color, 2.0)
	quad.material = qm
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(1.5)
	t.timeout.connect(p.queue_free)
	return p


## Confetti burst (slower, colorful, low gravity).
static func spawn_confetti(parent: Node, pos: Vector3, amount: int = 60) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.0
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -3.0, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	# Color ramp across the rainbow.
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.2, 0.4))
	grad.add_point(0.5, Color(0.2, 1, 0.5))
	grad.set_color(1, Color(0.3, 0.5, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.04)
	quad.material = glow(Color(1, 1, 1), 1.2)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(3.0)
	t.timeout.connect(p.queue_free)
	return p


## Ambient floating dust motes around an area (looping, subtle).
static func spawn_ambient_motes(parent: Node3D, center: Vector3, radius: float = 2.0, amount: int = 40) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.position = center
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.25
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.01
	mat.scale_max = 0.03
	mat.color = Color(0.7, 0.85, 1.0, 0.6)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = glow(Color(0.7, 0.85, 1.0), 1.0)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	return p


## Trail emitter to attach to a moving node (e.g. blades, balls, rackets).
static func make_trail(color: Color = Color(0.4, 0.9, 1.0), width: float = 0.05) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 32
	p.lifetime = 0.45
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3.ZERO
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.1
	mat.gravity = Vector3.ZERO
	mat.scale_min = width * 0.4
	mat.scale_max = width
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.9))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width)
	quad.material = glow(color, 1.8)
	p.draw_pass_1 = quad
	p.emitting = true
	return p


## Styled floating Label3D with outline for readability over passthrough.
static func make_label(text: String, font_size: int = 64, color: Color = Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	return l


## Small helper: ease a node toward a target scale (call in _process).
static func ease_scale(node: Node3D, target: Vector3, speed: float, delta: float) -> void:
	if node == null:
		return
	node.scale = node.scale.lerp(target, clampf(speed * delta, 0.0, 1.0))
