## ChronoRecorder.gd - time-loop recording + ghost replay for CHRONO HEIST.
## Records head + hand transforms every physics frame plus interaction
## events; ghosts replay them translucently in later loops.
class_name ChronoRecorder
extends Node

const HZ := 60.0

var frames: Array = []  # [{h: Transform3D, l: Transform3D, r: Transform3D}]
var events: Array = []  # [{t: float, obj: String, action: String}]
var loop_time := 0.0
var recording := false


func start() -> void:
	frames.clear()
	events.clear()
	loop_time = 0.0
	recording = true


func record_frame(head: Transform3D, lh: Transform3D, rh: Transform3D, dt: float) -> void:
	if not recording:
		return
	loop_time += dt
	frames.append({"h": head, "l": lh, "r": rh})
	if frames.size() > int(HZ * 65.0):
		frames.remove_at(0)


func log_event(obj_id: String, action: String) -> void:
	if not recording:
		return
	events.append({"t": loop_time, "obj": obj_id, "action": action})


func stop() -> Dictionary:
	recording = false
	return {"frames": frames.duplicate(), "events": events.duplicate(), "dur": loop_time}


## ChronoGhost: translucent replay of one recorded loop.
class ChronoGhost:
	extends Node3D
	var data: Dictionary = {}
	var ghost_t := 0.0
	var loop_idx := 0
	var _body: MeshInstance3D
	var _head: MeshInstance3D
	var _hand_l: MeshInstance3D
	var _hand_r: MeshInstance3D
	var _pulse := 0.0
	var _mat: StandardMaterial3D  # animator: shimmer pulse

	func setup(p_data: Dictionary, p_loop_idx: int) -> void:
		data = p_data
		loop_idx = p_loop_idx
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.9, 1.0, 0.32)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat = mat  # animator shimmer
		_body = MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.19
		cap.height = 1.0
		_body.mesh = cap
		_body.material_override = mat
		add_child(_body)
		_head = MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.14
		sph.height = 0.28
		_head.mesh = sph
		_head.material_override = mat
		add_child(_head)
		_hand_l = _make_hand(mat)
		_hand_r = _make_hand(mat)
		var lbl := Label3D.new()
		lbl.text = "YOU · LOOP %d" % (loop_idx + 1)
		lbl.font_size = 48
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(0.5, 0.95, 1.0, 0.8)
		lbl.position = Vector3(0, 1.95, 0)
		add_child(lbl)

	func _make_hand(mat: Material) -> MeshInstance3D:
		var h := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.07
		sph.height = 0.14
		h.mesh = sph
		h.material_override = mat
		add_child(h)
		return h

	func tick(t: float, delta: float) -> Array:
		# Returns interaction events whose time was just crossed.
		ghost_t = t
		_pulse += delta
		# Animator: ghost recordings shimmer — additive opacity pulse.
		if _mat != null:
			_mat.albedo_color.a = 0.26 + 0.12 * (0.5 + 0.5 * sin(_pulse * 3.0))
		var fr: Array = data.get("frames", [])
		var fired: Array = []
		if fr.is_empty():
			visible = false
			return fired
		visible = true
		var idx := clampi(int(t * ChronoRecorder.HZ), 0, fr.size() - 1)
		var f: Dictionary = fr[idx]
		var ht: Transform3D = f["h"]
		var lt: Transform3D = f["l"]
		var rt: Transform3D = f["r"]
		_head.global_transform = ht
		_hand_l.global_transform = lt
		_hand_r.global_transform = rt
		var hip := ht.origin - Vector3(0, 0.85, 0)
		_body.global_position = hip
		var yaw := (ht.basis * Vector3(0, 0, -1))
		_body.rotation.y = atan2(-yaw.x, -yaw.z)
		var s := 1.0 + 0.02 * sin(_pulse * 6.0)
		_body.scale = Vector3(s, 1.0, s)
		for e in (data.get("events", []) as Array):
			var et := float((e as Dictionary)["t"])
			if et > ghost_t - delta and et <= ghost_t:
				fired.append(e)
		return fired

	func head_pos() -> Vector3:
		return _head.global_position if is_instance_valid(_head) else global_position + Vector3(0, 1.6, 0)

	func hand_pos_l() -> Vector3:
		return _hand_l.global_position if is_instance_valid(_hand_l) else global_position

	func flash_paradox() -> void:
		if is_instance_valid(_body):
			_body.scale = Vector3(1.15, 0.9, 1.15)
