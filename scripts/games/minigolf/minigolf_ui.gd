## MinigolfUI.gd - UI builders for NEXUS GREENS.
## Simple 2D panels, laser+trigger (launcher spec). Mode select, Home Tour
## offer. Follows ui_kit.gd conventions.
extends RefCounted
class_name MinigolfUI


## Mode-select panel: VR Course vs AR Room Golf.
## ar_state: "ready" | "no_data" | "unavailable".
## Returns a Node3D with a `mode_chosen(mode: String)` signal.
static func build_mode_select(ar_state: String) -> Node3D:
	var panel := ModeSelectPanel.new()
	panel.name = "ModeSelect"
	panel.ar_state = ar_state
	return panel


## Home Tour offer card (AR Design §4). Returns a Node3D with
## `tour_chosen(accepted: bool)` signal.
static func build_home_tour_offer(matched: Array) -> Node3D:
	var panel := HomeTourOfferPanel.new()
	panel.name = "HomeTourOffer"
	panel.matched = matched
	return panel


## Shared button builder: 3D button with laser+trigger click area.
## Connect the returned Area3D's input_event for clicks.
static func make_button(title: String, subtitle: String, enabled: bool) -> Node3D:
	var btn := Node3D.new()
	btn.name = "Button_" + title.left(12)
	var box := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.55, 0.35, 0.04)
	box.mesh = bbox
	var mat := StandardMaterial3D.new()
	if enabled:
		mat.albedo_color = Color(0.12, 0.35, 0.18)
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.5, 0.25)
		mat.emission_energy_multiplier = 0.4
	else:
		mat.albedo_color = Color(0.18, 0.18, 0.20)
	box.material_override = mat
	btn.add_child(box)
	btn.set_meta("enabled", enabled)
	# Title label.
	var label := Label3D.new()
	label.text = title
	label.font_size = 42
	label.position = Vector3(0, 0.06, 0.03)
	btn.add_child(label)
	var sub := Label3D.new()
	sub.text = subtitle
	sub.font_size = 24
	sub.position = Vector3(0, -0.08, 0.03)
	btn.add_child(sub)
	# Click area.
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(0.55, 0.35, 0.12)
	col.shape = cbox
	area.add_child(col)
	btn.add_child(area)
	return btn


## Position a panel 2m in front of the player at eye height, facing them.
static func place_panel(panel: Node3D) -> void:
	var cam := panel.get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	panel.global_position = cam.global_position + fwd * 2.0
	panel.global_position.y = 1.5
	panel.look_at(cam.global_position, Vector3.UP)


class ModeSelectPanel extends Node3D:
	signal mode_chosen(mode: String)

	var ar_state := "ready"
	var _chosen := false

	func _ready() -> void:
		MinigolfUI.place_panel(self)
		_build_buttons()

	func _build_buttons() -> void:
		var vr_btn := MinigolfUI.make_button(
			"VR COURSE",
			"The floating championship course.\n18 holes, 3 zones.", true)
		vr_btn.position = Vector3(-0.35, 0, 0)
		add_child(vr_btn)
		_area(vr_btn).input_event.connect(_on_btn_input.bind("vr", vr_btn))

		var ar_enabled := ar_state == "ready"
		var ar_sub := "Your real room becomes the course.\nWalls, couch, tables as hazards."
		if ar_state == "no_data":
			ar_sub = "Scan your room first\n(Quest Settings > Environment Setup)."
		elif ar_state == "unavailable":
			ar_sub = "Room scanning not available\non this device."
		var ar_btn := MinigolfUI.make_button("AR ROOM GOLF", ar_sub, ar_enabled)
		ar_btn.position = Vector3(0.35, 0, 0)
		add_child(ar_btn)
		if ar_enabled:
			_area(ar_btn).input_event.connect(_on_btn_input.bind("ar", ar_btn))
		elif ar_state == "no_data":
			var scan_btn := MinigolfUI.make_button(
				"SCAN ROOM",
				"Walk your room's perimeter\nwith the headset.", true)
			scan_btn.position = Vector3(0.35, -0.45, 0)
			add_child(scan_btn)
			_area(scan_btn).input_event.connect(_on_scan_input.bind(scan_btn))

	func _area(btn: Node3D) -> Area3D:
		return btn.get_child(3) as Area3D

	func _on_btn_input(_c: Node, event: InputEvent, _p: Vector3, _n: Vector3,
			mode: String, btn: Node3D) -> void:
		if _chosen or not bool(btn.get_meta("enabled", false)):
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_chosen = true
				AudioKit.play_sfx("ui_select")
				Haptics.play_sequence("ui_select", "right")
				mode_chosen.emit(mode)
				queue_free()

	func _on_scan_input(_c: Node, event: InputEvent, _p: Vector3, _n: Vector3,
			_btn: Node3D) -> void:
		if _chosen:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_chosen = true
				AudioKit.play_sfx("ui_select")
				RoomKit.request_capture()
				GameplayTelemetry.log_event("minigolf_scan_requested", {})
				await get_tree().create_timer(3.0).timeout
				RoomKit.refresh()
				if RoomKit.has_room_data():
					ar_state = "ready"
					for child in get_children():
						child.queue_free()
					_chosen = false
					_build_buttons()
				else:
					_chosen = false
					GameplayTelemetry.log_event("minigolf_scan_no_data", {})


class HomeTourOfferPanel extends Node3D:
	signal tour_chosen(accepted: bool)

	var matched: Array = []
	var _chosen := false

	func _ready() -> void:
		MinigolfUI.place_panel(self)
		var yes_btn := MinigolfUI.make_button(
			"YES — HOME TOUR",
			"%d bonus holes on your furniture." % matched.size(), true)
		yes_btn.position = Vector3(-0.35, 0, 0)
		add_child(yes_btn)
		(yes_btn.get_child(3) as Area3D).input_event.connect(
			_on_tour_input.bind(true))
		var no_btn := MinigolfUI.make_button(
			"NO THANKS", "Finish the round.", true)
		no_btn.position = Vector3(0.35, 0, 0)
		add_child(no_btn)
		(no_btn.get_child(3) as Area3D).input_event.connect(
			_on_tour_input.bind(false))

	func _on_tour_input(_c: Node, event: InputEvent, _p: Vector3, _n: Vector3,
			accepted: bool) -> void:
		if _chosen:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_chosen = true
				AudioKit.play_sfx("ui_select")
				Haptics.play_sequence("ui_select", "right")
				tour_chosen.emit(accepted)
				queue_free()
