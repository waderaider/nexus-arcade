class_name MorphSkins
extends RefCounted
## MorphSkins.gd - reusable "furniture morph" skin library for NEXUS ARCADE.
##
## RoomKit.morph() loads this script dynamically and calls:
##   build(skin_name, anchor) -> Node3D   (origin-centered on the anchor)
##   play_morph_sound(parent)             (one-shot generated chime)
##   skin_names() -> PackedStringArray
##
## Design: every skin is a shell/aura AROUND the furniture cuboid —
## passthrough still shows the real object underneath. Each skin builds:
##   (1) translucent glowing shell (BoxMesh, padding ~0.06 m, emissive)
##   (2) 4-8 themed prop meshes (simple primitives, each < 200 tris)
##   (3) one GPUParticles3D system (< 40 particles)
##   (4) one OmniLight3D (small range, no shadows)
## Total per skin ~12-16 nodes. Quest-3-performant: no shadows, unshaded
## particle quads, cheap materials, tween-driven animation (no _process).
##
## Animation wiring: build() tags animated nodes with metadata
## ("anim": "orbit"/"bob"/"flicker"/"sway"/"pulse") and connects the root's
## ready signal; _on_skin_ready() creates looping tweens once in the tree.
## Headless-safe: without a tree, ready never fires and no tween is made.


const PADDING := 0.06  # shell padding in meters (total per axis)

# Shared soft-dot texture for all particle systems (generated once).
static var _dot_tex: Texture2D = null


# ------------------------------------------------------------------ contract

## Build a morph skin as an origin-centered Node3D. RoomKit positions and
## rotates the returned node at the anchor. Returns null for unknown
## skin_name. Never crashes on malformed anchor dicts.
static func build(skin_name: String, anchor: Dictionary) -> Node3D:
	var key := skin_name.to_lower()
	if not (key in skin_names()):
		return null
	var s := _anchor_size(anchor)
	var root := Node3D.new()
	root.name = "MorphSkin_" + key
	match key:
		"scifi":
			_build_scifi(root, s)
		"arcane":
			_build_arcane(root, s)
		"lava":
			_build_lava(root, s)
		"underwater":
			_build_underwater(root, s)
		"haunted":
			_build_haunted(root, s)
		"candy":
			_build_candy(root, s)
		"neon":
			_build_neon(root, s)
		"nature":
			_build_nature(root, s)
	# Wire looping tweens once the node enters the tree (headless: no-op).
	root.ready.connect(_on_skin_ready.bind(root))
	return root


## One-shot generated shimmer/chime (~0.6 s). No audio assets required.
static func play_morph_sound(parent: Node) -> void:
	if parent == null:
		return
	var rate := 22050
	var dur := 0.6
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	# Pleasant major chime: C6 E6 G6 C7 with fast attack + exp decay,
	# plus a gentle 5.5 Hz shimmer on each partial.
	var freqs := [1046.5, 1318.5, 1568.0, 2093.0]
	var amps := [0.30, 0.22, 0.18, 0.12]
	for i in range(n):
		var t := float(i) / float(rate)
		var env := exp(-t * 6.0) * minf(1.0, t * 80.0)
		var v := 0.0
		for f in range(freqs.size()):
			var wob := 1.0 + 0.004 * sin(TAU * 5.5 * t + float(f))
			v += amps[f] * sin(TAU * freqs[f] * wob * t)
		v = clampf(v * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	var player := AudioStreamPlayer.new()
	player.name = "MorphShimmer"
	player.stream = stream
	parent.add_child(player)
	if player.is_inside_tree():
		player.finished.connect(player.queue_free)
		player.play()
	else:
		# No scene tree (e.g. headless test): nothing can play through.
		player.free()


## All available skin names, in canonical order.
static func skin_names() -> PackedStringArray:
	return PackedStringArray([
		"scifi", "arcane", "lava", "underwater",
		"haunted", "candy", "neon", "nature",
	])


# ------------------------------------------------------------------ helpers

## Sanitize anchor size: Vector3.ONE fallback for missing/garbage values,
## clamped to sane positive bounds so weird dicts can never crash a build.
static func _anchor_size(anchor: Dictionary) -> Vector3:
	var v: Variant = anchor.get("size", Vector3.ONE)
	if not (v is Vector3):
		return Vector3.ONE
	var s: Vector3 = v
	return Vector3(
		1.0 if not is_finite(s.x) or s.x < 0.05 else minf(s.x, 20.0),
		1.0 if not is_finite(s.y) or s.y < 0.05 else minf(s.y, 20.0),
		1.0 if not is_finite(s.z) or s.z < 0.05 else minf(s.z, 20.0)
	)


## StandardMaterial3D with optional emission and alpha.
static func _mat(color: Color, emission_energy: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := color
	c.a = alpha
	m.albedo_color = c
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m


## (1) Translucent glowing shell around the anchor cuboid.
static func _shell(size: Vector3, color: Color, alpha: float = 0.20, emission_energy: float = 0.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	var bm := BoxMesh.new()
	bm.size = size + Vector3(PADDING, PADDING, PADDING)
	mi.mesh = bm
	var m := _mat(color, emission_energy, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from inside too
	mi.material_override = m
	return mi


## (2a) Simple box prop.
static func _prop_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi


## (2b) Generic primitive prop (sphere / cylinder / torus / plane).
static func _prop_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, emission: float = 0.0, pname: String = "Prop") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = pname
	mi.mesh = mesh
	mi.material_override = _mat(color, emission)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _ball(radius: float, color: Color, emission: float = 0.0, segments: int = 12, rings: int = 6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segments
	sm.rings = rings
	mi.mesh = sm
	mi.material_override = _mat(color, emission)
	return mi


## (3) One particle system. Particles spawn across the anchor volume and
## drift with the given velocity/gravity. Local coords keep them glued to
## the furniture when RoomKit moves the skin node.
static func _particles(color: Color, count: int, box: Vector3, velocity: float, gravity_y: float, lifetime: float = 2.5, psize: float = 0.035) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Particles"
	p.amount = mini(count, 40)
	p.lifetime = lifetime
	p.preprocess = lifetime  # pre-warm so the aura is alive immediately
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box * 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = velocity * 0.6
	pm.initial_velocity_max = velocity
	pm.gravity = Vector3(0, gravity_y, 0)
	pm.damping_min = 0.0
	pm.damping_max = 0.3
	pm.scale_min = psize * 0.7
	pm.scale_max = psize * 1.3
	pm.color = color
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.albedo_texture = _dot_texture()
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.5
	quad.material = m
	p.draw_pass_1 = quad
	return p


## Shared radial-gradient soft-dot texture (generated once, in code).
static func _dot_texture() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex


## (4) Small-range omni light, shadows always off (Quest perf).
static func _light(color: Color, energy: float = 0.8, range_m: float = 3.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "SkinLight"
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	return l


# ------------------------------------------------------- animation wiring

## Called on root.ready: create looping tweens for nodes tagged with
## meta "anim". Headless builds never enter a tree, so this never runs
## there (no _process needed anywhere in this library).
static func _on_skin_ready(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.has_meta("anim"):
			match String(n.get_meta("anim")):
				"orbit":
					_wire_orbit(n as Node3D)
				"bob":
					_wire_bob(n as Node3D)
				"flicker":
					_wire_flicker(n as OmniLight3D)
				"sway":
					_wire_sway(n as Node3D)
				"pulse":
					_wire_pulse(n as OmniLight3D)


## Slow continuous orbit of a pivot node (arcane rune stones).
static func _wire_orbit(pivot: Node3D) -> void:
	if pivot == null or not pivot.is_inside_tree():
		return
	var tm := float(pivot.get_meta("orbit_time", 14.0))
	var tw := pivot.create_tween()
	tw.set_loops()
	tw.tween_property(pivot, "rotation:y", TAU, tm).as_relative()


## Gentle vertical bob around the node's build position.
static func _wire_bob(n: Node3D) -> void:
	if n == null or not n.is_inside_tree():
		return
	var amp := float(n.get_meta("bob_amp", 0.08))
	var tm := float(n.get_meta("bob_time", 2.0))
	var base_y := n.position.y
	var tw := n.create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "position:y", base_y + amp, tm * 0.5)
	tw.tween_property(n, "position:y", base_y - amp, tm * 0.5)


## Random candle-style flicker of a light's energy (haunted).
static func _wire_flicker(light: OmniLight3D) -> void:
	if light == null or not light.is_inside_tree():
		return
	var base := float(light.get_meta("base_energy", light.light_energy))
	var tw := light.create_tween()
	tw.set_loops()
	tw.tween_callback(_apply_flicker.bind(light, base))
	tw.tween_interval(randf_range(0.06, 0.22))


static func _apply_flicker(light: OmniLight3D, base: float) -> void:
	if is_instance_valid(light):
		light.light_energy = base * randf_range(0.55, 1.25)


## Side-to-side sway around the pivot base (underwater seaweed).
static func _wire_sway(n: Node3D) -> void:
	if n == null or not n.is_inside_tree():
		return
	var amp := float(n.get_meta("sway_amp", 0.15))
	var tm := float(n.get_meta("sway_time", 3.0))
	var tw := n.create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "rotation:z", amp, tm * 0.5).as_relative()
	tw.tween_property(n, "rotation:z", -amp, tm * 0.5).as_relative()


## Slow breathing pulse of a light's energy (neon).
static func _wire_pulse(light: OmniLight3D) -> void:
	if light == null or not light.is_inside_tree():
		return
	var base := float(light.get_meta("base_energy", light.light_energy))
	var tw := light.create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(light, "light_energy", base * 1.6, 1.2)
	tw.tween_property(light, "light_energy", base * 0.7, 1.2)


# ------------------------------------------------------------------ skins

## "scifi": cyan/white. Console panels + emissive strips on top,
## holographic emissive frame corners, rising scan-line particles.
static func _build_scifi(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var cyan := Color(0.35, 0.95, 1.0)
	var shell := _shell(s, cyan, 0.18, 0.8)
	root.add_child(shell)
	# Console panels (dark) + emissive strips on top.
	for px in [-0.45 * hx, 0.45 * hx]:
		_prop_box(root, Vector3(px, hy + 0.035, 0), Vector3(0.55, 0.07, 0.32), Color(0.08, 0.10, 0.14))
		_prop_box(root, Vector3(px, hy + 0.078, 0.10), Vector3(0.50, 0.018, 0.05), cyan, 2.5)
	# Holographic frame corners: thin emissive boxes at all 8 corners.
	for cx in [-1.0, 1.0]:
		for cy in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				_prop_box(root,
					Vector3(cx * (hx + 0.03), cy * (hy + 0.03), cz * (hz + 0.03)),
					Vector3(0.05, 0.05, 0.05), cyan, 2.0)
	var parts := _particles(cyan, 32, s, 0.45, 0.0, 2.2, 0.03)
	root.add_child(parts)
	var l := _light(cyan, 0.7, 3.0)
	l.position = Vector3(0, hy + 0.6, 0)
	root.add_child(l)


## "arcane": purple/gold. Orbiting rune stones (octahedron-ish crystals),
## emissive magic-circle rings under the base, purple sparks, gold motes.
static func _build_arcane(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var purple := Color(0.62, 0.25, 0.95)
	var gold := Color(1.0, 0.78, 0.30)
	var shell := _shell(s, purple, 0.16, 0.7)
	root.add_child(shell)
	# Magic circle: two flat emissive torus rings under the base.
	var ring_r := minf(hx, hz) * 0.95 + 0.05
	for rr in [ring_r, ring_r * 0.6]:
		var tor := TorusMesh.new()
		tor.inner_radius = rr - 0.025
		tor.outer_radius = rr + 0.025
		_prop_mesh(root, tor, Vector3(0, -hy - 0.005, 0), gold, 2.2, "MagicRing")
	# Orbit pivot with 5 floating rune stones (4-seg/2-ring sphere = octahedron).
	var pivot := Node3D.new()
	pivot.name = "RuneOrbit"
	pivot.position = Vector3(0, hy + 0.40, 0)
	pivot.set_meta("anim", "orbit")
	pivot.set_meta("orbit_time", 16.0)
	root.add_child(pivot)
	var orb_r := minf(hx, hz) * 0.7 + 0.15
	for i in range(5):
		var a := TAU * float(i) / 5.0
		var stone := _ball(0.05, purple, 2.0, 4, 2)
		stone.name = "RuneStone"
		stone.position = Vector3(cos(a) * orb_r, 0, sin(a) * orb_r)
		pivot.add_child(stone)
	# Two gold motes bobbing above the top face.
	for i in range(2):
		var mote := _ball(0.035, gold, 2.0)
		mote.name = "GoldMote"
		mote.position = Vector3((float(i) - 0.5) * hx, hy + 0.25, (float(i) - 0.5) * hz * 0.5)
		mote.set_meta("anim", "bob")
		mote.set_meta("bob_amp", 0.06)
		mote.set_meta("bob_time", 2.4 + float(i) * 0.5)
		root.add_child(mote)
	var parts := _particles(purple, 26, s, 0.30, -0.05, 2.8, 0.03)
	root.add_child(parts)
	var l := _light(purple, 0.8, 3.0)
	l.position = Vector3(0, hy + 0.5, 0)
	root.add_child(l)


## "lava": orange/red. Emissive crack strips across the shell, ember
## particles rising, dark basalt rocks at the base corners.
static func _build_lava(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var ember := Color(1.0, 0.42, 0.10)
	var shell := _shell(s, Color(0.85, 0.25, 0.08), 0.20, 0.6)
	root.add_child(shell)
	# Emissive cracks: thin glowing strips on the top face + front face.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(5):
		var w := rng.randf_range(0.25, 0.55) * minf(s.x, 1.5)
		var px := rng.randf_range(-hx * 0.6, hx * 0.6)
		var pz := rng.randf_range(-hz * 0.6, hz * 0.6)
		var crack := _prop_box(root, Vector3(px, hy + 0.032, pz),
			Vector3(w, 0.012, 0.03), ember, 3.0)
		crack.rotation.y = rng.randf_range(-0.6, 0.6)
	for i in range(2):
		var px2 := (float(i) - 0.5) * hx * 1.2
		_prop_box(root, Vector3(px2, 0.0, hz + 0.032),
			Vector3(0.4, 0.03, 0.012), ember, 3.0)
	# Basalt rocks: dark low-poly icosphere-ish chunks at base corners.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var rock := _ball(0.12, Color(0.12, 0.10, 0.10), 0.15, 7, 4)
			rock.name = "BasaltRock"
			rock.position = Vector3(cx * (hx + 0.05), -hy + 0.08, cz * (hz + 0.05))
			rock.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0)
			root.add_child(rock)
	var parts := _particles(ember, 36, s, 0.55, 0.05, 2.0, 0.035)
	root.add_child(parts)
	var l := _light(Color(1.0, 0.45, 0.12), 1.0, 3.5)
	l.position = Vector3(0, hy + 0.5, 0)
	root.add_child(l)


## "underwater": deep blue/teal. Rising bubbles, swaying seaweed strands,
## small coral cones, aqua shell.
static func _build_underwater(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var aqua := Color(0.15, 0.65, 0.85)
	var shell := _shell(s, aqua, 0.18, 0.6)
	root.add_child(shell)
	# Seaweed: pivot at the base so sway rotates around the strand root.
	var weed := Color(0.20, 0.65, 0.30)
	for i in range(4):
		var pivot := Node3D.new()
		pivot.name = "Seaweed"
		pivot.position = Vector3((float(i) - 1.5) * hx * 0.45, hy, (float(i % 2) - 0.5) * hz * 0.8)
		pivot.set_meta("anim", "sway")
		pivot.set_meta("sway_amp", 0.18)
		pivot.set_meta("sway_time", 2.6 + float(i) * 0.4)
		root.add_child(pivot)
		var strand := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.55, 0.035)
		strand.mesh = bm
		strand.material_override = _mat(weed, 0.4)
		strand.position = Vector3(0, 0.275, 0)
		pivot.add_child(strand)
	# Coral cones: squat pink cones on the top face.
	for i in range(2):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.22
		_prop_mesh(root, cone,
			Vector3((float(i) - 0.5) * hx * 1.1, hy + 0.11, -hz * 0.4),
			Color(0.95, 0.45, 0.55), 0.8, "Coral")
	var parts := _particles(Color(0.65, 0.90, 1.0), 28, s, 0.40, -0.08, 3.0, 0.04)
	root.add_child(parts)
	var l := _light(Color(0.25, 0.60, 0.95), 0.7, 3.0)
	l.position = Vector3(0, hy + 0.6, 0)
	root.add_child(l)


## "haunted": sickly green/gray. Crooked fence posts, bobbing spirit orbs,
## drifting wisps, flickering pale light.
static func _build_haunted(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var sick := Color(0.55, 0.80, 0.45)
	var shell := _shell(s, Color(0.45, 0.55, 0.42), 0.14, 0.5)
	root.add_child(shell)
	# Crooked fence posts around the perimeter.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var post_spots := [
		Vector3(-hx - 0.15, 0, -hz - 0.15), Vector3(hx + 0.15, 0, -hz - 0.15),
		Vector3(-hx - 0.15, 0, hz + 0.15), Vector3(hx + 0.15, 0, hz + 0.15),
		Vector3(0, 0, -hz - 0.18), Vector3(0, 0, hz + 0.18),
	]
	for spot in post_spots:
		var post := _prop_box(root, Vector3(spot.x, -hy + 0.25, spot.z),
			Vector3(0.05, 0.5, 0.05), Color(0.16, 0.14, 0.12))
		post.rotation.z = rng.randf_range(-0.16, 0.16)
		post.rotation.x = rng.randf_range(-0.10, 0.10)
	# Spirit orbs: pale emissive spheres bobbing above the top.
	for i in range(3):
		var orb := _ball(0.06, Color(0.75, 0.95, 0.70), 1.8)
		orb.name = "SpiritOrb"
		orb.position = Vector3((float(i) - 1.0) * hx * 0.5, hy + 0.30, (float(i % 2) - 0.5) * hz)
		orb.set_meta("anim", "bob")
		orb.set_meta("bob_amp", 0.10)
		orb.set_meta("bob_time", 2.8 + float(i) * 0.6)
		root.add_child(orb)
	var parts := _particles(Color(0.70, 0.85, 0.65), 24, s, 0.12, 0.0, 4.0, 0.05)
	root.add_child(parts)
	var l := _light(Color(0.75, 0.90, 0.65), 0.55, 3.0)
	l.position = Vector3(0, hy + 0.6, 0)
	l.set_meta("anim", "flicker")
	l.set_meta("base_energy", 0.55)
	root.add_child(l)


## "candy": pink/mint. Lollipops (stick + candy top), squashed gumdrops,
## confetti particles, warm pink light.
static func _build_candy(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var shell := _shell(s, Color(1.0, 0.55, 0.75), 0.18, 0.7)
	root.add_child(shell)
	# Lollipops: white stick + bright candy sphere top.
	var candy_cols := [Color(1.0, 0.25, 0.35), Color(0.35, 0.95, 0.65), Color(1.0, 0.85, 0.30)]
	for i in range(3):
		var px := (float(i) - 1.0) * hx * 0.55
		var stick := CylinderMesh.new()
		stick.top_radius = 0.02
		stick.bottom_radius = 0.02
		stick.height = 0.35
		_prop_mesh(root, stick, Vector3(px, hy + 0.175, hz * 0.2),
			Color(0.95, 0.95, 0.95), 0.2, "Stick")
		var top := _ball(0.09, candy_cols[i], 1.2)
		top.name = "Lollipop"
		top.position = Vector3(px, hy + 0.35 + 0.09, hz * 0.2)
		root.add_child(top)
	# Gumdrops: squashed pastel spheres on the top face.
	var gum_cols := [Color(1.0, 0.65, 0.80), Color(0.55, 0.95, 0.75), Color(0.75, 0.80, 1.0)]
	for i in range(3):
		var gum := _ball(0.10, gum_cols[i], 0.6)
		gum.name = "Gumdrop"
		gum.scale.y = 0.65
		gum.position = Vector3((float(i) - 1.0) * hx * 0.6, hy + 0.065, -hz * 0.35)
		root.add_child(gum)
	var parts := _particles(Color(1.0, 0.70, 0.85), 32, s, 0.25, -0.15, 2.6, 0.03)
	root.add_child(parts)
	var l := _light(Color(1.0, 0.55, 0.70), 0.8, 3.0)
	l.position = Vector3(0, hy + 0.6, 0)
	root.add_child(l)


## "neon": magenta/cyan on a near-black shell. Emissive tube edges along
## all 12 box edges, glowing grid plane underneath, pulsing magenta light.
static func _build_neon(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var magenta := Color(1.0, 0.15, 0.75)
	var cyan := Color(0.15, 0.95, 1.0)
	var shell := _shell(s, Color(0.03, 0.03, 0.05), 0.35, 0.4)
	root.add_child(shell)
	# Neon tube edges: 12 thin emissive boxes, alternating magenta/cyan.
	var t := 0.025
	var idx := 0
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var col := magenta if idx % 2 == 0 else cyan
			_prop_box(root, Vector3(0, sy * (hy + 0.03), sz * (hz + 0.03)),
				Vector3(s.x + t, t, t), col, 3.0)
			idx += 1
	for sx in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var col2 := magenta if idx % 2 == 0 else cyan
			_prop_box(root, Vector3(sx * (hx + 0.03), 0, sz2 * (hz + 0.03)),
				Vector3(t, s.y + t, t), col2, 3.0)
			idx += 1
	for sx2 in [-1.0, 1.0]:
		for sy2 in [-1.0, 1.0]:
			var col3 := magenta if idx % 2 == 0 else cyan
			_prop_box(root, Vector3(sx2 * (hx + 0.03), sy2 * (hy + 0.03), 0),
				Vector3(t, t, s.z + t), col3, 3.0)
			idx += 1
	# Grid floor glow: emissive plane just under the base.
	var grid := PlaneMesh.new()
	grid.size = Vector2(s.x + 0.5, s.z + 0.5)
	var gm := _mat(cyan, 1.2, 0.45)
	var glow := _prop_mesh(root, grid, Vector3(0, -hy - 0.02, 0), cyan, 0.0, "GridGlow")
	glow.material_override = gm
	var parts := _particles(magenta, 30, s, 0.35, 0.0, 1.8, 0.025)
	root.add_child(parts)
	var l := _light(magenta, 0.9, 3.5)
	l.position = Vector3(0, hy + 0.5, 0)
	l.set_meta("anim", "pulse")
	l.set_meta("base_energy", 0.9)
	root.add_child(l)


## "nature": greens/browns. Vines climbing the corners, leaf clusters,
## tiny emissive flower dots, firefly particles, soft green light.
static func _build_nature(root: Node3D, s: Vector3) -> void:
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5
	var shell := _shell(s, Color(0.35, 0.70, 0.35), 0.15, 0.5)
	root.add_child(shell)
	# Vines: thin green strands climbing the four vertical corners.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_prop_box(root, Vector3(cx * (hx + 0.02), 0, cz * (hz + 0.02)),
				Vector3(0.03, s.y + 0.10, 0.03), Color(0.25, 0.55, 0.25), 0.3)
	# Leaf clusters: small low-poly green icosphere-ish blobs on top.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var leaf_cols := [Color(0.30, 0.65, 0.28), Color(0.38, 0.72, 0.30), Color(0.25, 0.58, 0.26)]
	for i in range(5):
		var leaf := _ball(0.09, leaf_cols[i % 3], 0.4, 6, 4)
		leaf.name = "LeafCluster"
		leaf.position = Vector3(
			rng.randf_range(-hx * 0.7, hx * 0.7), hy + 0.09,
			rng.randf_range(-hz * 0.7, hz * 0.7))
		root.add_child(leaf)
	# Flower dots: tiny emissive spheres scattered on the top face.
	var flower_cols := [Color(1.0, 0.45, 0.65), Color(1.0, 0.90, 0.40), Color(0.95, 0.95, 1.0), Color(1.0, 0.60, 0.35)]
	for i in range(4):
		var fl := _ball(0.03, flower_cols[i], 1.5, 8, 4)
		fl.name = "Flower"
		fl.position = Vector3(
			rng.randf_range(-hx * 0.8, hx * 0.8), hy + 0.035,
			rng.randf_range(-hz * 0.8, hz * 0.8))
		root.add_child(fl)
	var parts := _particles(Color(0.85, 1.0, 0.45), 24, s, 0.15, 0.0, 3.5, 0.03)
	root.add_child(parts)
	var l := _light(Color(0.55, 0.85, 0.45), 0.6, 3.0)
	l.position = Vector3(0, hy + 0.6, 0)
	root.add_child(l)
