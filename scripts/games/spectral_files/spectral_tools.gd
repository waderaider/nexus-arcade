## SpectralTools.gd - the ghost-hunting toolkit for SPECTRAL FILES.
## Mounted on the right controller: EMF reader, thermal view, spirit box,
## camera. Grip cycles tools; trigger uses the active one. (Voice STT is a
## RISKY API — the spirit box uses a SAFE proximity sweep instead.)
class_name SpectralTools
extends Node3D

const TOOLS := ["EMF", "THERMAL", "SPIRIT BOX", "CAMERA"]

var current := 0
var evidence_cb := Callable()  # func(kind: String)
var photo_check := Callable()  # func() -> bool

var _mount: Node3D
var _leds: Array[MeshInstance3D] = []
var _label: Label3D
var _screen: Label3D
var _thermal_quad: MeshInstance3D
var _cam: Camera3D = null

var _beep_t := 0.0
var _emf5_t := 0.0
var _freeze_t := 0.0
var _spirit_cd := 0.0
var _sweep_t := 0.0
var _ghost_near := false
var _ghost_anger := 0.0


func tool_name() -> String:
	return TOOLS[current]


func attach_to(hand: Node3D, cam: Camera3D) -> void:
	_cam = cam
	_mount = Node3D.new()
	hand.add_child(_mount)
	_mount.position = Vector3(0, 0.06, -0.12)
	# Device body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.03, 0.16)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.13, 0.16)
	bmat.roughness = 0.5
	body.material_override = bmat
	_mount.add_child(body)
	# 5 EMF LEDs.
	for i in 5:
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.012, 0.012, 0.012)
		led.mesh = lm
		led.position = Vector3(-0.032 + i * 0.016, 0.022, -0.05)
		_mount.add_child(led)
		_leds.append(led)
	# Tool label.
	_label = Label3D.new()
	_label.font_size = 44
	_label.pixel_size = 0.002
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 0.07, 0)
	_mount.add_child(_label)
	# Spirit-box screen.
	_screen = Label3D.new()
	_screen.font_size = 36
	_screen.pixel_size = 0.002
	_screen.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_screen.no_depth_test = true
	_screen.position = Vector3(0, 0.045, 0.02)
	_screen.modulate = Color(0.6, 1.0, 0.7)
	_mount.add_child(_screen)
	_refresh_label()


func cycle() -> void:
	current = (current + 1) % TOOLS.size()
	_sweep_t = 0.0
	_screen.text = ""
	_refresh_label()
	Haptics.tick()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_sfx("ui_click")


func _refresh_label() -> void:
	if _label != null:
		_label.text = TOOLS[current]
	_update_thermal_quad()


func _update_thermal_quad() -> void:
	var want: bool = str(TOOLS[current]) == "THERMAL" and _cam != null
	if want and _thermal_quad == null:
		_thermal_quad = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.6, 1.0)
		_thermal_quad.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.15, 0.35, 0.9, 0.22)
		m.no_depth_test = true
		_thermal_quad.material_override = m
		_cam.add_child(_thermal_quad)
		_thermal_quad.position = Vector3(0, 0, -0.6)
	if _thermal_quad != null:
		_thermal_quad.visible = want


func is_thermal_on() -> bool:
	return TOOLS[current] == "THERMAL"


func set_ghost_state(dist: float, anger: float) -> void:
	_ghost_near = dist < 4.0
	_ghost_anger = anger


func use() -> void:
	match TOOLS[current]:
		"SPIRIT BOX":
			_sweep()
		"CAMERA":
			_snap_photo()
		"THERMAL":
			Haptics.tick()  # toggle is implicit by selection


func _sweep() -> void:
	if _sweep_t > 0.0:
		return
	_sweep_t = 1.4
	_screen.text = "··· SCANNING ···"
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("static")
	Haptics.texture_tick()


func _snap_photo() -> void:
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("shutter")
	Haptics.confirm()
	var hit := false
	if photo_check.is_valid():
		hit = bool(photo_check.call())
	if hit:
		_screen.text = "CAPTURED"
		_note_evidence("PHOTO")
	else:
		_screen.text = "NOTHING THERE"


func _note_evidence(kind: String) -> void:
	if evidence_cb.is_valid():
		evidence_cb.call(kind)


## Per-frame: EMF LEDs + beeps, spirit-box reply timing, freeze watch.
func tick(dt: float, ghost_dist: float, in_cold_spot: bool) -> void:
	_spirit_cd = maxf(0.0, _spirit_cd - dt)
	# --- EMF ---
	var level := clampi(int(6.0 - ghost_dist / 1.5), 0, 5)
	for i in _leds.size():
		var led := _leds[i]
		var on := i < level
		var m := StandardMaterial3D.new()
		var c := Color(0.2, 1.0, 0.3) if i < 3 else (Color(1.0, 0.9, 0.2) if i == 3 else Color(1.0, 0.2, 0.2))
		if on:
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5
		else:
			m.albedo_color = Color(0.1, 0.1, 0.1)
		led.material_override = m
	if level > 0:
		_beep_t -= dt
		if _beep_t <= 0.0:
			_beep_t = lerpf(1.1, 0.12, float(level) / 5.0)
			if get_node_or_null("/root/AudioKit") != null:
				AudioKit.play_game_sfx("emf")
	if level >= 5:
		_emf5_t += dt
		if _emf5_t >= 1.0:
			_emf5_t = -999.0  # fire once
			_note_evidence("EMF5")
	# --- Spirit box reply ---
	if _sweep_t > 0.0:
		_sweep_t -= dt
		if _sweep_t <= 0.0:
			if _ghost_near or _ghost_anger > 0.4:
				_screen.text = "◊ IT SPEAKS ◊"
				_note_evidence("SPIRIT")
			else:
				_screen.text = "— silence —"
	# --- Thermal freeze ---
	if is_thermal_on() and in_cold_spot:
		_freeze_t += dt
		if _freeze_t >= 2.0:
			_freeze_t = -999.0
			_note_evidence("FREEZE")
	elif not is_thermal_on():
		_freeze_t = 0.0
