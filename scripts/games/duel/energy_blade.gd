## EnergyBlade.gd - procedural energy blade for Neon Duel.
## Ports EnergyBlade.cs: hilt + emissive blade + idle hum + clash FX.
## Root sits at the grip; the blade extends along local +Y.
## Blade visuals are emissive (no lights needed). Includes a ribbon trail.
extends Node3D
class_name EnergyBlade

var blade_length := 0.85
var blade_color := Color(0.2, 0.9, 1.0)

var base_position: Vector3:
	get: return _blade_pivot.global_position if _blade_pivot else global_position
var tip_position: Vector3:
	get: return base_position + global_transform.basis.y * blade_length
var tip_velocity := Vector3.ZERO

var _blade_pivot: Node3D
var _prev_tip := Vector3.ZERO
var _blade_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _flash := 0.0
var _base_emission := 2.2

var _hum: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _clash_clip: AudioStreamWAV

# Trail: ring buffer of recent (base, tip) pairs, drawn as an ImmediateMesh ribbon.
const TRAIL_POINTS := 18
var _trail_buf: Array = []
var _trail_mesh: ImmediateMesh
var _trail_mi: MeshInstance3D
var _trail_mat: StandardMaterial3D


static func create(blade_color: Color, length := 0.85, hilt_length := 0.24) -> EnergyBlade:
	var blade := EnergyBlade.new()
	blade.blade_color = blade_color
	blade.blade_length = length
	blade._build(hilt_length)
	return blade


func _build(hilt_length: float) -> void:
	# --- Hilt: grip cylinder + pommel + emitter shroud ---
	var hilt := MeshInstance3D.new()
	var hcyl := CylinderMesh.new()
	hcyl.top_radius = 0.025
	hcyl.bottom_radius = 0.025
	hcyl.height = hilt_length
	hilt.mesh = hcyl
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.12, 0.12, 0.14)
	hmat.metallic = 0.85
	hmat.roughness = 0.4
	hilt.material_override = hmat
	add_child(hilt)

	# Grip rings.
	for i in range(3):
		var ring := MeshInstance3D.new()
		var rcyl := CylinderMesh.new()
		rcyl.top_radius = 0.028
		rcyl.bottom_radius = 0.028
		rcyl.height = 0.018
		ring.mesh = rcyl
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.05, 0.05, 0.06)
		rmat.metallic = 0.4
		rmat.roughness = 0.7
		ring.material_override = rmat
		ring.position = Vector3(0, -hilt_length * 0.28 + i * hilt_length * 0.22, 0)
		add_child(ring)

	# Emitter shroud.
	var emitter := MeshInstance3D.new()
	var ecyl := CylinderMesh.new()
	ecyl.top_radius = 0.035
	ecyl.bottom_radius = 0.03
	ecyl.height = 0.03
	emitter.mesh = ecyl
	var emat := StandardMaterial3D.new()
	emat.albedo_color = blade_color
	emat.emission_enabled = true
	emat.emission = blade_color
	emat.emission_energy_multiplier = 1.6
	emitter.material_override = emat
	emitter.position = Vector3(0, hilt_length * 0.5 + 0.015, 0)
	add_child(emitter)

	var blade_base := hilt_length * 0.5 + 0.03

	# --- Blade pivot; blade extends +Y ---
	_blade_pivot = Node3D.new()
	_blade_pivot.name = "BladePivot"
	_blade_pivot.position = Vector3(0, blade_base, 0)
	add_child(_blade_pivot)

	# Outer glow slab.
	var outer := MeshInstance3D.new()
	var obox := BoxMesh.new()
	obox.size = Vector3(0.05, blade_length, 0.05)
	outer.mesh = obox
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = blade_color
	_blade_mat.emission_enabled = true
	_blade_mat.emission = blade_color
	_blade_mat.emission_energy_multiplier = _base_emission
	outer.material_override = _blade_mat
	outer.position = Vector3(0, blade_length * 0.5, 0)
	_blade_pivot.add_child(outer)

	# White-hot core.
	var core := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(0.022, blade_length * 0.98, 0.022)
	core.mesh = cbox
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color.WHITE
	_core_mat.emission_enabled = true
	_core_mat.emission = Color.WHITE
	_core_mat.emission_energy_multiplier = 4.0
	core.material_override = _core_mat
	core.position = Vector3(0, blade_length * 0.5, 0)
	_blade_pivot.add_child(core)

	# Pointed tip: 4-sided pyramid (rotated cone).
	var tip := MeshInstance3D.new()
	var tcone := CylinderMesh.new()
	tcone.top_radius = 0.0
	tcone.bottom_radius = 0.036
	tcone.height = 0.12
	tcone.radial_segments = 4
	tip.mesh = tcone
	tip.material_override = _blade_mat
	tip.position = Vector3(0, blade_length + 0.06, 0)
	tip.rotation.y = deg_to_rad(45.0)
	_blade_pivot.add_child(tip)

	# --- Audio: procedural hum loop + clash one-shots ---
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "Hum"
	_hum.max_distance = 6.0
	_hum.stream = _make_hum_loop()
	# Autoplay (not play()) - _build runs before the node enters the tree.
	_hum.autoplay = true
	add_child(_hum)

	_sfx = AudioStreamPlayer3D.new()
	_sfx.name = "BladeSFX"
	_sfx.max_distance = 12.0
	add_child(_sfx)
	_clash_clip = _make_clash_clip()

	# --- Trail ribbon ---
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.albedo_color = blade_color
	_trail_mat.emission_enabled = true
	_trail_mat.emission = blade_color
	_trail_mat.emission_energy_multiplier = 1.8
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mesh = ImmediateMesh.new()
	_trail_mi = MeshInstance3D.new()
	_trail_mi.mesh = _trail_mesh
	_trail_mi.material_override = _trail_mat
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_mi)

	_prev_tip = tip_position


func _process(delta: float) -> void:
	var tip := tip_position
	var dt := maxf(delta, 0.0001)
	tip_velocity = (tip - _prev_tip) / dt
	_prev_tip = tip

	# Clash flash decay.
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		_blade_mat.emission_energy_multiplier = _base_emission + _flash * 6.0
		_core_mat.emission_energy_multiplier = 4.0 + _flash * 8.0

	_update_trail()


## Impact feedback at a world point: flash + synthesized metallic ping.
func clash() -> void:
	_flash = 1.0
	if _sfx and _clash_clip:
		_sfx.stream = _clash_clip
		_sfx.pitch_scale = randf_range(0.92, 1.1)
		_sfx.play()


func set_hum(freq_hz: float, volume: float) -> void:
	# Hum volume only; pitch tracks swing speed via pitch_scale on the player blade.
	if _hum:
		_hum.volume_db = linear_to_db(clampf(volume, 0.001, 1.0))
		_hum.pitch_scale = clampf(freq_hz / 95.0, 0.5, 4.0)


func _update_trail() -> void:
	var speed := tip_velocity.length()
	# Only lay down trail points while the blade is moving.
	if speed > 1.2:
		_trail_buf.push_back([base_position, tip_position])
		if _trail_buf.size() > TRAIL_POINTS:
			_trail_buf.pop_front()
	elif _trail_buf.size() > 0:
		_trail_buf.pop_front()

	_trail_mesh.clear_surfaces()
	if _trail_buf.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_buf.size()
	for i in range(n):
		var pair: Array = _trail_buf[i]
		var alpha := float(i) / float(n - 1)
		_trail_mesh.surface_set_color(Color(blade_color, alpha * 0.55))
		# ImmediateMesh uses local coords: convert to the blade root's space.
		var local_base: Vector3 = to_local(pair[0])
		var local_tip: Vector3 = to_local(pair[1])
		_trail_mesh.surface_add_vertex(local_base)
		_trail_mesh.surface_add_vertex(local_tip)
	_trail_mesh.surface_end()


func _make_hum_loop() -> AudioStreamWAV:
	# 2s loop of 95 Hz (190 whole cycles -> loops cleanly) + soft 2nd harmonic.
	var sr := 22050
	var freq := 95.0
	var length := int(sr * 2.0)
	var data := PackedByteArray()
	data.resize(length * 2)
	var phase := 0.0
	for i in range(length):
		phase += TAU * freq / sr
		if phase > TAU:
			phase -= TAU
		var s := (sin(phase) * 0.7 + sin(phase * 2.02) * 0.3) * 0.045
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = length
	return wav


func _make_clash_clip() -> AudioStreamWAV:
	# 0.28s metallic ping: stacked detuned harmonics + noise, exp decay.
	var sr := 22050
	var length := int(sr * 0.28)
	var data := PackedByteArray()
	data.resize(length * 2)
	var freqs := [1244.0, 1866.0, 2794.0, 4150.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in range(length):
		var t := float(i) / sr
		var env := exp(-t * 16.0)
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t) * 0.22
		v += (rng.randf() * 2.0 - 1.0) * 0.3
		v *= env * 0.55
		var iv := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, iv)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav
