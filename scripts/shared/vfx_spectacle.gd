## VFX.gd — NEXUS ARCADE spectacle kit (v0.11.0, VFX Artist pass).
##
## One static call per "holy crap" moment. Pure spectacle craft: timing,
## color, scale, choreography. Distinct from the Tech-Demo Engineer (their
## tier plan: ~/workspace/design/CYCLE_V0110_BUILDER_NOTES.md).
##
## Design rules (Quest 3, 72fps):
##  - GPU-light: GPUParticles3D only, capped counts, scaled by the graphics
##    quality multiplier (GraphicsPolish.scaled_amount: Low 0.4 … Ultra 1.2).
##  - Emissive sprites / unshaded mesh tricks over expensive sims.
##  - Real OmniLight3D only for strobes/flickers, always time-boxed <1.5s.
##  - Every effect is fire-and-forget and self-freeing (timers + tweens).
##  - No audio (AudioKit is the caller's job); haptics included where the
##    impact is physical (stomp, breach, celebrate).
##  - Headless-safe: node/tween/timer building only, never XR hardware.
##
## Perf contract: each public effect lists its transient cost
## (particle systems / meshes / lights / particles). The canonical numbers
## were measured headless (tests/test_vfx_counts.gd) — see
## ~/workspace/design/VFX_V0110.md for the table.
##
## Builder API (this is the call list — wire these into game scripts):
##   VFX.celebrate(parent, pos, title, accent, tier)  # 0=ace 1=win 2=small
##   VFX.portal_burst(parent, pos, color, radius)     # portal open/traverse
##   VFX.goal(parent, pos, accent)                    # NULL-G winning goal
##   VFX.stomp(parent, pos, radius)                   # KAIJU stomp
##   VFX.rune_forge(parent, pos, element, glyph)      # RUNEWRIGHT rune lock
##   VFX.holo_deploy(parent, pos, color, radius)      # WAR TABLE deployment
##   VFX.console_breach(parent, pos)                  # STARSHIP BRIDGE damage
##   VFX.alarm_sweep(parent, pos, color)              # PHANTOM THIEF alert
##   VFX.loop_reset(parent, pos, radius)              # CHRONO HEIST loop reset
##   VFX.castle_crash(parent, pos, size)              # SIEGE ENGINEER smash
##   VFX.manifest(parent, pos)                        # SPECTRAL FILES ghost
##   VFX.epoch_flash(parent, pos, biome)              # TERRAFORM god moment
extends RefCounted
class_name VFX

const GOLD := Color(1.0, 0.84, 0.30)
const WHITE := Color(1.0, 1.0, 1.0)

static var _slowmo_active := false


# ------------------------------------------------------------------ core ---

## Universal celebration. tier 0 = jaw-dropping (hole-in-one, match win):
## camera flash, double shockwave, triple confetti cannons, 2-light strobe,
## optional title banner. tier 1 = single cannon + shockwave. tier 2 = spark
## pop. Cost(t0): 3 particle systems (~180), 3 meshes, 2 lights (1.2 s).
static func celebrate(parent: Node, pos: Vector3, title: String = "",
		accent: Color = GOLD, tier: int = 0) -> void:
	if tier <= 0:
		camera_flash(parent, accent, 0.30)
		shockwave(parent, pos, accent, 2.4, 0.7)
		_later(parent, 0.10, func() -> void: shockwave(parent, pos, WHITE, 1.6, 0.55))
		confetti_cannons(parent, pos, [accent, WHITE, Color(0.35, 0.85, 1.0)], 60)
		light_strobe(parent, pos, accent, Color(0.35, 0.9, 1.0), 1.2)
		Haptics.play_sequence("fanfare", "both")
	elif tier == 1:
		camera_flash(parent, accent, 0.18)
		shockwave(parent, pos, accent, 1.6, 0.6)
		confetti_cannons(parent, pos, [accent, WHITE], 50)
		Haptics.play_sequence("levelup", "both")
	else:
		camera_flash(parent, accent, 0.10)
		GraphicsPolish.spawn_sparks(parent, pos, accent, 20)
		Haptics.confirm("both")
	if title != "":
		_banner(parent, pos + Vector3(0, 0.85, 0), title, accent)


## Camera flash: gold/white quad 0.35 m in front of the HMD, quick
## in-out. Zero discomfort risk (no FOV change, no camera motion).
## Cost: 1 quad, ~0.4 s.
static func camera_flash(parent: Node, color: Color, peak: float = 0.30,
		hold: float = 0.05, fade: float = 0.30) -> void:
	var cam := _camera(parent)
	if cam == null:
		return
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	q.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.no_depth_test = true
	q.material_override = mat
	q.position = Vector3(0, 0, -0.35)
	cam.add_child(q)
	var tw := parent.create_tween() if parent.is_inside_tree() else null
	if tw == null:
		q.queue_free()
		return
	tw.tween_property(mat, "albedo_color:a", peak, hold)
	tw.tween_property(mat, "albedo_color:a", 0.0, fade)
	tw.tween_callback(q.queue_free)


## Expanding torus shockwave. Cost: 1 mesh, <0.8 s.
static func shockwave(parent: Node, pos: Vector3, color: Color,
		max_radius: float = 2.0, dur: float = 0.7) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.34
	tm.rings = 32
	tm.ring_segments = 8
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	parent.add_child(ring)
	ring.global_position = pos
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), dur)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(ring.queue_free)


## N confetti cannons fanned from `pos`, one color each.
## Cost: N particle systems (default 3 × 60), 2.2 s self-freeing.
static func confetti_cannons(parent: Node, pos: Vector3, colors: Array, per: int = 60) -> void:
	var n := maxi(colors.size(), 1)
	for i in n:
		var c: Color = colors[i] if i < colors.size() else WHITE
		var off := Vector3((float(i) - float(n - 1) * 0.5) * 0.5, 0.05, 0.0)
		_confetti_burst(parent, pos + off, c, per, float(i) * 0.06)


## Two pooled omni lights strobing at ~6 Hz, time-boxed. The only real
## lights in the kit — everything else is emissive. Cost: 2 lights.
static func light_strobe(parent: Node, pos: Vector3, c1: Color, c2: Color, dur: float = 1.2) -> void:
	for i in 2:
		var light := OmniLight3D.new()
		light.light_color = c1 if i == 0 else c2
		light.light_energy = 0.0
		light.omni_range = 4.0
		light.shadow_enabled = false
		parent.add_child(light)
		light.global_position = pos + Vector3(0.5 if i == 0 else -0.5, 0.8, 0)
		var tw := light.create_tween()
		var steps := int(dur / 0.16)
		for k in steps:
			tw.tween_property(light, "light_energy", 3.0, 0.08)
			tw.tween_property(light, "light_energy", 0.2, 0.08)
		tw.tween_callback(light.queue_free)


## Portal open / traverse: imploding spark swirl + expanding ring + disc
## flash. Cost: 1 particle system (36), 2 meshes.
static func portal_burst(parent: Node, pos: Vector3, color: Color, radius: float = 0.5) -> void:
	# Imploding swirl: high damping + inward bias reads as "sucked through".
	var p := GPUParticles3D.new()
	p.amount = GraphicsPolish.scaled_amount(36)
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius * 1.6
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.5
	mat.damping_max = 4.0
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.color = color
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = GraphicsPolish.glow(color, 2.2)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(parent, p, 1.6)
	# Disc flash + expanding ring.
	var disc := MeshInstance3D.new()
	var dm := QuadMesh.new()
	dm.size = Vector2(radius * 2.2, radius * 2.2)
	disc.mesh = dm
	var dmat := GraphicsPolish.glow(color, 2.5)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color.a = 0.85
	disc.material_override = dmat
	parent.add_child(disc)
	disc.global_position = pos
	_face_camera(disc)
	var tw := disc.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dmat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(disc, "scale", Vector3.ONE * 1.6, 0.45)
	tw.chain().tween_callback(disc.queue_free)
	shockwave(parent, pos, color, radius * 3.0, 0.6)


# ------------------------------------------------------- new-game VFX ---

## NULL-G LEAGUE winning goal: brief slow-mo, goal-ring shockwave, ribbon
## confetti at the ring, camera flash. Call when the disc crosses the ring.
## Cost: 1 particle system (50), 2 meshes + time_scale 0.3 for 0.6 s.
static func goal(parent: Node, pos: Vector3, accent: Color = Color(0.3, 0.9, 1.0)) -> void:
	_slowmo(0.3, 0.6)
	camera_flash(parent, accent, 0.22)
	shockwave(parent, pos, accent, 3.0, 0.8)
	confetti_cannons(parent, pos, [accent, WHITE, GOLD], 50)
	Haptics.play_sequence("fanfare", "both")


## KAIJU SIEGE stomp: dust ring burst, ground shockwave, tumbling debris
## chunks, sub-bass rumble. `radius` = stomp footprint in meters.
## Cost: 1 particle system (48), 9 meshes, 1.1 s.
static func stomp(parent: Node, pos: Vector3, radius: float = 1.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = GraphicsPolish.scaled_amount(48)
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius * 0.5
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 75.0
	mat.initial_velocity_min = 2.0 * radius
	mat.initial_velocity_max = 4.5 * radius
	mat.gravity = Vector3(0, -7.0, 0)
	mat.damping_min = 1.5
	mat.damping_max = 2.5
	mat.scale_min = 0.08
	mat.scale_max = 0.22
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.68, 0.58, 0.95))
	grad.set_color(1, Color(0.45, 0.40, 0.35, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	quad.material = _puff_mat(Color(0.65, 0.60, 0.52))
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(parent, p, 2.0)
	shockwave(parent, pos, Color(0.9, 0.75, 0.55), radius * 3.5, 0.6)
	_debris_chunks(parent, pos, 8, radius, Color(0.42, 0.38, 0.34))
	Haptics.sub_bass(0.5)


## RUNEWRIGHT rune lock: the traced rune ignites — ring + spokes scale in
## with an emissive flash, element burst, glyph pops overhead.
## Cost: 1 particle system (30), 5 meshes, 1 label, 1.4 s.
static func rune_forge(parent: Node, pos: Vector3, element: Color, glyph: String = "✦") -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.30
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = GraphicsPolish.glow(element, 2.4)
	ring.rotation_degrees.x = 90.0
	root.add_child(ring)
	for i in 3:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.52, 0.03, 0.03)
		spoke.mesh = bm
		spoke.material_override = GraphicsPolish.glow(element, 2.0)
		spoke.rotation.y = TAU * float(i) / 3.0
		root.add_child(spoke)
	root.scale = Vector3.ONE * 0.2
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE * 1.15, 0.28)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "rotation:y", TAU * 0.5, 1.4)
	tw.chain().tween_interval(0.5)
	tw.tween_property(root, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(root.queue_free)
	GraphicsPolish.spawn_sparks(root, Vector3.ZERO, element, 30)
	var gl := GraphicsPolish.make_label(glyph, 96, WHITE)
	gl.outline_modulate = element
	parent.add_child(gl)
	gl.global_position = pos + Vector3(0, 0.45, 0)
	var gtw := gl.create_tween()
	gtw.set_parallel(true)
	gtw.tween_property(gl, "scale", Vector3.ONE * 1.3, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gtw.tween_property(gl, "modulate:a", 0.0, 0.9).set_delay(0.5)
	gtw.chain().tween_callback(gl.queue_free)
	Haptics.confirm("both")


## WAR TABLE deployment: a holo scan-beam column rises from the table,
## ring shockwave, sparkle shower — the army materializes.
## Cost: 1 particle system (24), 3 meshes, 1.2 s.
static func holo_deploy(parent: Node, pos: Vector3, color: Color = Color(0.3, 0.9, 1.0),
		radius: float = 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.55
	cm.bottom_radius = radius * 0.75
	cm.height = 1.6
	cm.radial_segments = 24
	beam.mesh = cm
	var bmat := GraphicsPolish.glow(color, 1.6)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color.a = 0.45
	beam.material_override = bmat
	beam.position.y = 0.8
	root.add_child(beam)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "scale", Vector3(0.15, 1.0, 0.15), 0.5)\
		.from(Vector3(1.6, 0.05, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bmat, "albedo_color:a", 0.0, 0.6).set_delay(0.6)
	tw.chain().tween_callback(root.queue_free)
	shockwave(parent, pos, color, radius * 2.2, 0.6)
	GraphicsPolish.spawn_sparks(parent, pos + Vector3(0, 0.6, 0), color, 24)


## STARSHIP BRIDGE console breach: spark fountain, rising smoke puffs,
## red alert strobe on one time-boxed omni. Call on hull/console damage.
## Cost: 2 particle systems (42), 1 light (0.9 s).
static func console_breach(parent: Node, pos: Vector3) -> void:
	var sparks := GPUParticles3D.new()
	sparks.amount = GraphicsPolish.scaled_amount(30)
	sparks.lifetime = 0.7
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 35.0
	sm.initial_velocity_min = 2.5
	sm.initial_velocity_max = 6.0
	sm.gravity = Vector3(0, -9.0, 0)
	sm.scale_min = 0.02
	sm.scale_max = 0.06
	sm.color = Color(1.0, 0.6, 0.15)
	sparks.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	sq.material = GraphicsPolish.glow(Color(1.0, 0.6, 0.15), 2.4)
	sparks.draw_pass_1 = sq
	parent.add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true
	_free_later(parent, sparks, 1.6)
	var smoke := GPUParticles3D.new()
	smoke.amount = GraphicsPolish.scaled_amount(12)
	smoke.lifetime = 1.6
	smoke.one_shot = true
	smoke.explosiveness = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(0.15, 0.15, 0.17, 0.8))
	sgrad.set_color(1, Color(0.1, 0.1, 0.12, 0.0))
	var sramp := GradientTexture1D.new()
	sramp.gradient = sgrad
	pm.color_ramp = sramp
	smoke.process_material = pm
	var pq := QuadMesh.new()
	pq.size = Vector2(0.2, 0.2)
	pq.material = _puff_mat(Color(0.14, 0.14, 0.16))
	smoke.draw_pass_1 = pq
	parent.add_child(smoke)
	smoke.global_position = pos + Vector3(0, 0.15, 0)
	smoke.emitting = true
	_free_later(parent, smoke, 2.6)
	var alert := OmniLight3D.new()
	alert.light_color = Color(1.0, 0.12, 0.10)
	alert.light_energy = 0.0
	alert.omni_range = 5.0
	alert.shadow_enabled = false
	parent.add_child(alert)
	alert.global_position = pos + Vector3(0, 0.6, 0)
	var atw := alert.create_tween()
	for k in 5:
		atw.tween_property(alert, "light_energy", 2.5, 0.09)
		atw.tween_property(alert, "light_energy", 0.1, 0.09)
	atw.tween_callback(alert.queue_free)
	Haptics.impact(0.8)


## PHANTOM THIEF guard alert: twin expanding alarm rings + ping sparks
## at the guard's position. Cost: 1 particle system (16), 2 meshes.
static func alarm_sweep(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.15, 0.10)) -> void:
	shockwave(parent, pos, color, 2.5, 0.8)
	_later(parent, 0.18, func() -> void: shockwave(parent, pos, color, 3.5, 0.8))
	GraphicsPolish.spawn_sparks(parent, pos + Vector3(0, 1.2, 0), color, 16)
	Haptics.deny()


## CHRONO HEIST loop reset: three concentric time-ripple rings, a pale
## desaturating flash, paradox-static sparks. The "cooperate with yourself"
## beat lands here.
## Cost: 1 particle system (24), 3 meshes, 1 flash quad.
static func loop_reset(parent: Node, pos: Vector3, radius: float = 3.0) -> void:
	var pale := Color(0.75, 0.85, 1.0)
	for i in 3:
		var r: float = radius * (0.5 + 0.25 * float(i))
		var d: float = float(i) * 0.15
		_later(parent, d, func() -> void: shockwave(parent, pos, pale, r, 0.9))
	camera_flash(parent, pale, 0.35, 0.10, 0.45)
	GraphicsPolish.spawn_sparks(parent, pos + Vector3(0, 1.0, 0), Color(0.5, 0.8, 1.0), 24)
	Haptics.play_sequence("tick_tock", "both")


## SIEGE ENGINEER castle smash: tumbling brick chunks, dust cloud, ground
## ring. `size` scales the destruction footprint.
## Cost: 2 particle systems (54), 11 meshes, 1.4 s.
static func castle_crash(parent: Node, pos: Vector3, size: float = 1.0) -> void:
	var dust := GPUParticles3D.new()
	dust.amount = GraphicsPolish.scaled_amount(30)
	dust.lifetime = 1.1
	dust.one_shot = true
	dust.explosiveness = 0.85
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dm.emission_sphere_radius = 0.4 * size
	dm.direction = Vector3(0, 1, 0)
	dm.spread = 65.0
	dm.initial_velocity_min = 1.5 * size
	dm.initial_velocity_max = 4.0 * size
	dm.gravity = Vector3(0, -4.0, 0)
	dm.damping_min = 1.2
	dm.damping_max = 2.0
	dm.scale_min = 0.10
	dm.scale_max = 0.28
	var dgrad := Gradient.new()
	dgrad.set_color(0, Color(0.72, 0.66, 0.58, 0.9))
	dgrad.set_color(1, Color(0.55, 0.50, 0.44, 0.0))
	var dramp := GradientTexture1D.new()
	dramp.gradient = dgrad
	dm.color_ramp = dramp
	dust.process_material = dm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.2, 0.2)
	dq.material = _puff_mat(Color(0.66, 0.60, 0.53))
	dust.draw_pass_1 = dq
	parent.add_child(dust)
	dust.global_position = pos
	dust.emitting = true
	_free_later(parent, dust, 2.2)
	GraphicsPolish.spawn_sparks(parent, pos, Color(1.0, 0.75, 0.4), 24)
	shockwave(parent, pos, Color(0.85, 0.72, 0.55), size * 3.0, 0.7)
	_debris_chunks(parent, pos, 10, size, Color(0.55, 0.48, 0.40))
	Haptics.sub_bass(0.6)


## SPECTRAL FILES manifestation: cold mist blooms, a cold-blue flicker on
## one time-boxed omni, apparition pulse ring + disc flash. Horror is
## lighting, not polys.
## Cost: 1 particle system (24), 1 light (0.9 s), 2 meshes.
static func manifest(parent: Node, pos: Vector3) -> void:
	var mist := GPUParticles3D.new()
	mist.amount = GraphicsPolish.scaled_amount(24)
	mist.lifetime = 2.0
	mist.one_shot = true
	mist.explosiveness = 0.6
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mm.emission_sphere_radius = 0.35
	mm.direction = Vector3(0, 1, 0)
	mm.spread = 40.0
	mm.initial_velocity_min = 0.2
	mm.initial_velocity_max = 0.7
	mm.gravity = Vector3(0, 0.35, 0)
	mm.scale_min = 0.10
	mm.scale_max = 0.30
	var mgrad := Gradient.new()
	mgrad.set_color(0, Color(0.65, 0.80, 0.95, 0.55))
	mgrad.set_color(1, Color(0.55, 0.70, 0.90, 0.0))
	var mramp := GradientTexture1D.new()
	mramp.gradient = mgrad
	mm.color_ramp = mramp
	mist.process_material = mm
	var mq := QuadMesh.new()
	mq.size = Vector2(0.2, 0.2)
	mq.material = _puff_mat(Color(0.60, 0.75, 0.90))
	mist.draw_pass_1 = mq
	parent.add_child(mist)
	mist.global_position = pos
	mist.emitting = true
	_free_later(parent, mist, 3.0)
	var cold := OmniLight3D.new()
	cold.light_color = Color(0.45, 0.65, 1.0)
	cold.light_energy = 0.0
	cold.omni_range = 4.0
	cold.shadow_enabled = false
	parent.add_child(cold)
	cold.global_position = pos + Vector3(0, 1.0, 0)
	var ctw := cold.create_tween()
	for k in 6:
		ctw.tween_property(cold, "light_energy", 2.0 if k % 2 == 0 else 0.15, 0.07)
	ctw.tween_property(cold, "light_energy", 1.2, 0.2)
	ctw.tween_property(cold, "light_energy", 0.0, 0.4)
	ctw.tween_callback(cold.queue_free)
	shockwave(parent, pos, Color(0.55, 0.75, 1.0), 2.2, 0.9)
	Haptics.play_sequence("heartbeat", "both")


## TERRAFORM god moment: a sky-beam of biome light, an expanding biome
## wave ring, drifting spore motes, camera flash. Call on epoch advance /
## sentience birth / disaster unleashed.
## Cost: 1 particle system (30), 2 meshes, 1 flash quad.
static func epoch_flash(parent: Node, pos: Vector3, biome: Color = Color(0.3, 0.9, 0.4)) -> void:
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.6
	cm.height = 6.0
	cm.radial_segments = 16
	beam.mesh = cm
	var bmat := GraphicsPolish.glow(biome, 1.8)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color.a = 0.5
	beam.material_override = bmat
	parent.add_child(beam)
	beam.global_position = pos + Vector3(0, 3.0, 0)
	var btw := beam.create_tween()
	btw.set_parallel(true)
	btw.tween_property(beam, "scale", Vector3(1.8, 1.0, 1.8), 0.9)\
		.from(Vector3(0.15, 1.0, 0.15)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	btw.tween_property(bmat, "albedo_color:a", 0.0, 0.8).set_delay(0.5)
	btw.chain().tween_callback(beam.queue_free)
	shockwave(parent, pos, biome, 4.0, 1.1)
	var spores := GPUParticles3D.new()
	spores.amount = GraphicsPolish.scaled_amount(30)
	spores.lifetime = 1.8
	spores.one_shot = true
	spores.explosiveness = 0.7
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.6
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 50.0
	sm.initial_velocity_min = 0.4
	sm.initial_velocity_max = 1.4
	sm.gravity = Vector3(0, 0.4, 0)
	sm.scale_min = 0.02
	sm.scale_max = 0.07
	sm.color = biome
	spores.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	sq.material = GraphicsPolish.glow(biome, 2.0)
	spores.draw_pass_1 = sq
	parent.add_child(spores)
	spores.global_position = pos + Vector3(0, 0.3, 0)
	spores.emitting = true
	_free_later(parent, spores, 2.8)
	camera_flash(parent, biome, 0.15)
	Haptics.play_sequence("levelup", "both")


# -------------------------------------------------------------- helpers ---

## Tumbling brick/debris chunks: unshaded boxes on ballistic arcs, shrink
## out on landing. Cost: `count` meshes, ~1.1 s.
static func _debris_chunks(parent: Node, pos: Vector3, count: int, size: float, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 977.0 + pos.z * 613.0) & 0x7fffffff
	for i in count:
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.06, 0.16) * size
		bm.size = Vector3(s, s * rng.randf_range(0.6, 1.2), s)
		chunk.mesh = bm
		chunk.material_override = GraphicsPolish.pbr(color, 0.0, 0.9)
		parent.add_child(chunk)
		chunk.global_position = pos + Vector3(0, 0.1, 0)
		var a := rng.randf() * TAU
		var dist := rng.randf_range(0.6, 1.8) * size
		var target := pos + Vector3(cos(a) * dist, 0.02, sin(a) * dist)
		var dur := rng.randf_range(0.5, 0.8)
		var tw := chunk.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "global_position", target, dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(chunk, "rotation", Vector3(rng.randf() * 4.0, rng.randf() * 4.0, 0.0), dur)
		tw.chain().tween_property(chunk, "scale", Vector3.ZERO, 0.25)
		tw.tween_callback(chunk.queue_free)


## One-shot confetti burst in a single color (pennant quads).
static func _confetti_burst(parent: Node, pos: Vector3, tint: Color, count: int, delay: float) -> void:
	_later(parent, delay, func() -> void:
		var p := GPUParticles3D.new()
		p.amount = GraphicsPolish.scaled_amount(count)
		p.lifetime = 1.8
		p.one_shot = true
		p.explosiveness = 0.92
		p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.06
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 38.0
		mat.initial_velocity_min = 2.0
		mat.initial_velocity_max = 4.5
		mat.gravity = Vector3(0, -5.0, 0)
		mat.damping_min = 0.4
		mat.damping_max = 1.0
		mat.scale_min = 0.03
		mat.scale_max = 0.07
		mat.color = tint
		p.process_material = mat
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.07)
		var qmat := StandardMaterial3D.new()
		qmat.albedo_color = tint
		qmat.emission_enabled = true
		qmat.emission = tint
		qmat.emission_energy_multiplier = 0.7
		qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = qmat
		p.draw_pass_1 = quad
		parent.add_child(p)
		p.global_position = pos
		p.emitting = true
		_free_later(parent, p, 3.2)
	)


## Big title banner for celebrations (gold Label3D, unfurl + float away).
static func _banner(parent: Node, pos: Vector3, text: String, accent: Color) -> void:
	var label := GraphicsPolish.make_label(text, 128, accent)
	label.outline_size = 16
	parent.add_child(label)
	label.global_position = pos
	_face_camera(label)
	label.scale = Vector3(1, 0.05, 1)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE, 0.45)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_later(parent, 2.6, func() -> void:
		if not is_instance_valid(label):
			return
		var tw2 := label.create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(label, "global_position:y", label.global_position.y + 0.4, 1.2)
		tw2.tween_property(label, "modulate:a", 0.0, 1.2)
		tw2.chain().tween_callback(label.queue_free)
	)


## Guarded slow-mo: no-ops if another slow-mo is already active.
static func _slowmo(scale: float, real_sec: float) -> void:
	if _slowmo_active or Engine.time_scale < 1.0:
		return
	_slowmo_active = true
	Engine.time_scale = scale
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		Engine.time_scale = 1.0
		_slowmo_active = false
		return
	var start := Time.get_ticks_msec()
	while _slowmo_active and float(Time.get_ticks_msec() - start) / 1000.0 < real_sec:
		await tree.process_frame
	Engine.time_scale = 1.0
	_slowmo_active = false


## Soft unshaded puff material for dust/smoke/mist sprite quads.
static func _puff_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.75)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


static func _camera(parent: Node) -> Camera3D:
	var vp := parent.get_viewport()
	return vp.get_camera_3d() if vp != null else null


static func _face_camera(n: Node3D) -> void:
	var cam := _camera(n)
	if cam == null:
		return
	var dir: Vector3 = cam.global_position - n.global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		n.rotation.y = atan2(-dir.x, -dir.z)


static func _later(parent: Node, delay: float, fn: Callable) -> void:
	var tree := parent.get_tree()
	if tree == null:
		return
	if delay <= 0.0:
		fn.call()
		return
	tree.create_timer(delay).timeout.connect(fn)


static func _free_later(parent: Node, n: Node, delay: float) -> void:
	_later(parent, delay, func() -> void:
		if is_instance_valid(n):
			n.queue_free()
	)
