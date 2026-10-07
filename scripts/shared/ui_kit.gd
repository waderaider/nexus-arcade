## UIKit.gd - shared UI upgrade kit for NEXUS ARCADE (autoload: UIKit).
## 10 opt-in UI helpers: HUD, popups, sounds, haptics, loading, toasts,
## hints, pause menu, big-font theme, settings row with persistence.
## Usage: UIKit.make_hud(panel) / UIKit.toast(panel, "Nice!") ...
## Headless-safe: builds Controls only; tree/tween use is guarded.
extends Node

const SETTINGS_PATH := "user://nexus_arcade_settings.cfg"


## (a) HUD: score label top-left, health label top-right, big fonts.
## Returns {"root": Control, "score": Label, "health": Label}.
func make_hud(parent: Control) -> Dictionary:
	var root := Control.new()
	root.name = "UIKitHUD"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var score := Label.new()
	score.name = "ScoreLabel"
	score.text = "SCORE 0"
	score.add_theme_font_size_override("font_size", 44)
	score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	score.add_theme_constant_override("outline_size", 8)
	score.set_anchors_preset(Control.PRESET_TOP_LEFT)
	score.position = Vector2(24, 16)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(score)
	var health := Label.new()
	health.name = "HealthLabel"
	health.text = "HP 100"
	health.add_theme_font_size_override("font_size", 44)
	health.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	health.add_theme_constant_override("outline_size", 8)
	health.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	health.position = Vector2(-260, 16)
	health.size = Vector2(236, 60)
	health.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health)
	return {"root": root, "score": score, "health": health}


## (b) Floating "+100" popup. pos: Vector3 -> Label3D in world, Vector2 -> Label on canvas.
func score_popup(parent: Node, pos: Variant, text: String, color: Color = Color(1.0, 0.9, 0.3)) -> void:
	if pos is Vector3:
		var l3d := GraphicsPolish.make_label(text, 72, color)
		(parent as Node3D).add_child(l3d)
		l3d.position = pos
		if l3d.is_inside_tree():
			var tw := l3d.create_tween()
			tw.set_parallel(true)
			tw.tween_property(l3d, "position:y", l3d.position.y + 0.6, 0.9).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(l3d, "modulate:a", 0.0, 0.9)
			tw.chain().tween_callback(l3d.queue_free)
	elif pos is Vector2 and parent is Control:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 6)
		l.position = pos
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(parent as Control).add_child(l)
		if l.is_inside_tree():
			var tw := l.create_tween()
			tw.set_parallel(true)
			tw.tween_property(l, "position:y", l.position.y - 70.0, 0.9).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(l, "modulate:a", 0.0, 0.9)
			tw.chain().tween_callback(l.queue_free)


## (c) Click sound: short generated blip, no audio assets needed.
## Returns the player (auto-frees after playing when inside a tree).
func click_sound(parent: Node = null, freq: float = 880.0, dur: float = 0.07) -> AudioStreamPlayer:
	var rate := 22050
	var n := maxi(int(rate * dur), 1)
	var data := PackedByteArray()
	data.resize(n)
	for i in range(n):
		var t := float(i) / rate
		var env := 1.0 - float(i) / float(n)
		data[i] = clampi(int(128.0 + 100.0 * env * sin(TAU * freq * t)), 0, 255)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	var player := AudioStreamPlayer.new()
	player.stream = wav
	var host: Node = parent if parent != null else self
	if host.is_inside_tree():
		host.add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
	return player


## (d) UI haptic pulse via the shared Haptics helper. Honors the persisted
## haptics toggle from settings_row().
func ui_haptic(kind: String = "tick") -> void:
	if not _haptics_enabled():
		return
	match kind:
		"tick":
			Haptics.tick()
		"thump":
			Haptics.thump()
		_:
			Haptics.pulse(0.6, 0.1)


func _haptics_enabled() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return true
	return bool(cfg.get_value("haptics", "enabled", true))


## (e) Loading spinner overlay. Caller dismisses with overlay.hide() (or
## queue_free). Blocks input while visible.
func loading_indicator(parent: Control, text: String = "Loading") -> Control:
	var overlay := Control.new()
	overlay.name = "UIKitLoading"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 48)
	label.text = text
	center.add_child(label)
	parent.add_child(overlay)
	if overlay.is_inside_tree():
		var frames := 0
		var timer := Timer.new()
		timer.wait_time = 0.3
		overlay.add_child(timer)
		timer.timeout.connect(func() -> void:
			if not is_instance_valid(label):
				return
			frames += 1
			label.text = text + ["", ".", "..", "..."][frames % 4]
		)
		timer.start()
	return overlay


## (f) Bottom toast that fades out and frees itself.
func toast(parent: Control, msg: String, duration: float = 2.0) -> void:
	var label := Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.position = Vector2(-400, -140)
	label.size = Vector2(800, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	if label.is_inside_tree():
		var tw := label.create_tween()
		tw.tween_interval(duration)
		tw.tween_property(label, "modulate:a", 0.0, 0.6)
		tw.tween_callback(label.queue_free)


## (g) Contextual tutorial hint box (top-center). Caller dismisses via queue_free.
func tutorial_hint(parent: Control, msg: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "UIKitHint"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-380, 24)
	panel.size = Vector2(760, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 32)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	parent.add_child(panel)
	return panel


## (h) Pause menu overlay: Resume + Quit-to-Hub. Pauses the tree while open.
## on_resume is called when the player resumes.
func pause_menu(parent: Control, on_resume: Callable) -> Control:
	var overlay := Control.new()
	overlay.name = "UIKitPause"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.add_theme_font_size_override("font_size", 40)
	resume_btn.custom_minimum_size = Vector2(320, 80)
	box.add_child(resume_btn)
	var quit_btn := Button.new()
	quit_btn.text = "Quit to Hub"
	quit_btn.add_theme_font_size_override("font_size", 40)
	quit_btn.custom_minimum_size = Vector2(320, 80)
	box.add_child(quit_btn)
	parent.add_child(overlay)
	resume_btn.pressed.connect(func() -> void:
		ui_haptic("tick")
		if overlay.get_tree() != null:
			overlay.get_tree().paused = false
		overlay.queue_free()
		on_resume.call()
	)
	quit_btn.pressed.connect(func() -> void:
		ui_haptic("tick")
		var tree := overlay.get_tree()
		if tree != null:
			tree.paused = false
			tree.change_scene_to_file("res://scenes/main.tscn")
	)
	if parent.is_inside_tree():
		parent.get_tree().paused = true
	return overlay


## (i) Default Theme with large font sizes for Controls (Quest readability).
func big_fonts() -> Theme:
	var t := Theme.new()
	t.default_font_size = 40
	return t


## (j) Settings row: volume slider + haptics toggle, persisted to
## user://nexus_arcade_settings.cfg. Volume applies to the Master bus live.
func settings_row(parent: Control) -> HBoxContainer:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var row := HBoxContainer.new()
	row.name = "UIKitSettings"
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var vol_label := Label.new()
	vol_label.text = "Volume"
	vol_label.add_theme_font_size_override("font_size", 32)
	row.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol := float(cfg.get_value("audio", "volume", 0.8))
	slider.value = vol
	_apply_volume(vol)
	row.add_child(slider)
	var hap := CheckButton.new()
	hap.text = "Haptics"
	hap.add_theme_font_size_override("font_size", 32)
	hap.button_pressed = bool(cfg.get_value("haptics", "enabled", true))
	row.add_child(hap)
	parent.add_child(row)
	slider.value_changed.connect(func(v: float) -> void:
		_apply_volume(v)
		var c := ConfigFile.new()
		c.load(SETTINGS_PATH)
		c.set_value("audio", "volume", v)
		c.save(SETTINGS_PATH)
	)
	hap.toggled.connect(func(on: bool) -> void:
		var c := ConfigFile.new()
		c.load(SETTINGS_PATH)
		c.set_value("haptics", "enabled", on)
		c.save(SETTINGS_PATH)
		if on:
			ui_haptic("tick")
	)
	return row


func _apply_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))
