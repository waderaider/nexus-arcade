## VisualFX.gd - shared visual upgrade kit for NEXUS ARCADE (autoload: VisualFX).
## 10 opt-in upgrades, all tuned for Quest 3 mobile GPU (GL Compatibility):
## no SSAO, no volumetric fog, no heavy post. Cheap wins only.
## Usage: VisualFX.apply_aces(world) / VisualFX.burst(self, pos, Color.RED) ...
## NOTE: visual quality needs validation on real Quest 3 hardware (never
## Quest-tested here); everything is headless-safe (node building only).
extends Node


## (a) ACES tonemapping + tuned ambient on the game's WorldEnvironment.
## Safe on the Compatibility renderer; subtle so passthrough AR stays readable.
func apply_aces(world: WorldEnvironment) -> void:
	if world == null or world.environment == null:
		return
	var env := world.environment
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.55


## (b) Subtle glow: enable/raise bloom modestly (supported on Compatibility 4.4+).
func subtle_glow(world: WorldEnvironment, intensity: float = 0.5) -> void:
	if world == null or world.environment == null:
		return
	var env := world.environment
	env.glow_enabled = true
	env.glow_intensity = clampf(intensity, 0.1, 1.0)
	env.glow_strength = 0.9
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT


## (c) Mobile-sane shadow config for a DirectionalLight3D:
## 2 cascade splits, capped distance, slight blur. Cheap on Quest.
func configure_shadows(sun: DirectionalLight3D, max_distance: float = 30.0) -> void:
	if sun == null:
		return
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = maxf(max_distance, 5.0)
	sun.shadow_blur = 1.0
	sun.shadow_opacity = 0.85


## (d) One-shot particle explosion. Low counts; frees itself.
## Thin wrapper over GraphicsPolish.spawn_sparks so both kits stay in sync.
func burst(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.6, 0.15), amount: int = 24) -> GPUParticles3D:
	return GraphicsPolish.spawn_sparks(parent, pos, color, mini(amount, 48))


## (e) Cheap PBR pass: walk all MeshInstance3Ds, tame roughness toward ~0.5,
## keep metallic sane, and enable vertex-color albedo where the mesh carries
## vertex colors but the material ignores them. Returns meshes touched.
func pbr_pass(node: Node) -> int:
	if node == null:
		return 0
	var touched := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mesh := mi.mesh
		var has_vcol := _mesh_has_vertex_color(mesh)
		var mat := mi.material_override as StandardMaterial3D
		if mat == null and mesh != null and mesh.get_surface_count() > 0:
			mat = mesh.surface_get_material(0) as StandardMaterial3D
		if mat == null:
			# No material at all: give it a sane default PBR.
			var fresh := GraphicsPolish.pbr(Color(0.75, 0.78, 0.82), 0.0, 0.55)
			fresh.vertex_color_use_as_albedo = has_vcol
			mi.material_override = fresh
			touched += 1
		else:
			var dup := mat.duplicate() as StandardMaterial3D
			var changed := false
			if dup.roughness >= 0.95:
				dup.roughness = 0.55
				changed = true
			if dup.metallic > 0.2 and dup.metallic < 0.85:
				# Mid metallics usually look wrong without env reflections; tame.
				dup.metallic = 0.2
				changed = true
			if has_vcol and not dup.vertex_color_use_as_albedo:
				dup.vertex_color_use_as_albedo = true
				changed = true
			if changed:
				mi.material_override = dup
				touched += 1
	return touched


func _mesh_has_vertex_color(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_COLOR:
		return false
	var col_variant: Variant = arrays[Mesh.ARRAY_COLOR]
	if col_variant is PackedColorArray:
		return (col_variant as PackedColorArray).size() > 0
	return false


## (f) Distance fog on the WorldEnvironment (standard exponential fog;
## volumetric fog is NOT supported on the Compatibility renderer, so we
## deliberately do not touch it).
func enable_fog(world: WorldEnvironment, density: float = 0.015) -> void:
	if world == null or world.environment == null:
		return
	var env := world.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = clampf(density, 0.001, 0.08)
	env.fog_light_color = Color(0.5, 0.56, 0.66)
	env.fog_sky_affect = 0.4


## (g) Cheap vignette: TextureRect with a generated radial gradient overlay.
## Add to a CanvasLayer/Control; mouse clicks pass through.
func vignette(parent: Control, amount: float = 0.45) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.add_point(0.62, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, clampf(amount, 0.0, 0.9)))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.name = "VisualFXVignette"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


## (h) Ambient floating dust motes (looping, subtle).
## Reuses GraphicsPolish.spawn_ambient_motes.
func ambient_dust(parent: Node3D, radius: float = 2.5, amount: int = 36) -> GPUParticles3D:
	return GraphicsPolish.spawn_ambient_motes(parent, Vector3.ZERO, radius, mini(amount, 60))


## (i) Animated sky: cheap drifting-gradient shader sky, no textures.
## WARNING: for VR-style scenes only - it replaces the background, so do NOT
## use in passthrough AR games (it would hide the real room).
func animated_sky(world: WorldEnvironment, top := Color(0.10, 0.16, 0.34), horizon := Color(0.42, 0.24, 0.36)) -> void:
	if world == null or world.environment == null:
		return
	var env := world.environment
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 top_color : source_color = vec3(%s);
uniform vec3 horizon_color : source_color = vec3(%s);
void sky() {
	float h = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	float drift = sin(TIME * 0.06 + EYEDIR.x * 2.0 + EYEDIR.z * 1.3) * 0.035;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h + drift, 0.0, 1.0), 1.25));
	COLOR = col;
}
""" % [_col3(top), _col3(horizon)]
	sm.shader = sh
	var sky := Sky.new()
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5


func _col3(c: Color) -> String:
	return "%.3f, %.3f, %.3f" % [c.r, c.g, c.b]


## (j) Emissive pulse accent on a node: duplicates materials (never mutates
## shared ones), enables emission, and loops a gentle energy pulse via tween.
func glow_accent(node: Node3D, color: Color = Color(0.4, 0.9, 1.0), base: float = 1.2, amp: float = 0.8, speed: float = 2.0) -> void:
	if node == null:
		return
	var targets: Array = []
	if node is MeshInstance3D:
		targets.append(node)
	targets.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for child in targets:
		var mi := child as MeshInstance3D
		var smat: StandardMaterial3D
		if mi.material_override is StandardMaterial3D:
			smat = (mi.material_override as StandardMaterial3D).duplicate()
		else:
			smat = GraphicsPolish.pbr(Color(0.8, 0.8, 0.85), 0.0, 0.5)
		smat.emission_enabled = true
		smat.emission = color
		smat.emission_energy_multiplier = base
		mi.material_override = smat
		if node.is_inside_tree():
			var tw := node.create_tween()
			tw.set_loops()
			var half := 1.0 / maxf(speed, 0.1)
			tw.tween_property(smat, "emission_energy_multiplier", base + amp, half).set_trans(Tween.TRANS_SINE)
			tw.tween_property(smat, "emission_energy_multiplier", base, half).set_trans(Tween.TRANS_SINE)
