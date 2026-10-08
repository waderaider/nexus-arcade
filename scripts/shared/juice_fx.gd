## JuiceFX.gd - game-feel juice autoload for NEXUS ARCADE (autoload: JuiceFX).
## v0.9.0 shared-systems build (TECH_DEMO_PLAN §3a-bis).
##
## The missing APIs every game needs, centralized so the global auto-wirer
## (hub.gd _load_game) can apply them opt-out:
##   hit_stop(frames)        - 2-3 frame freeze on impacts/catches
##   squash_stretch(node)    - deform pop on pickup/landing
##   scale_pop(node)         - 120ms overshoot pop for score events
##   title_card(title, subtitle) - 3s intro sting (skippable), called by the
##                                 auto-wirer with the game's display name
##   affordance_pass(root)   - emissive pulse on nodes tagged meta "interactive"
##   combo_popup(pos, text)  - floating combo text with scale pop
## Plus: exit_transition(), combo_counter().
##
## All helpers are headless-safe: they only build nodes/tweens, never require
## XR hardware. NOTE: feel/timing needs validation on real Quest 3 hardware.
extends Node

const TITLE_CARD_TIME := 3.0
const _SQUASH := 0.7


var _active_card: CanvasLayer = null
var _card_timer: SceneTreeTimer = null
var _skip_was_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Skip the active title card on the first fresh press of any skip input:
	# controller trigger (either hand), mouse click, or the H key.
	if _active_card == null or not is_instance_valid(_active_card):
		_active_card = null
		return
	var down := _skip_down()
	if down and not _skip_was_down:
		dismiss_title_card()
	_skip_was_down = down


func _skip_down() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if Input.is_key_pressed(KEY_H):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	for c in tree.root.find_children("*", "XRController3D", true, false):
		if XRUIPointer.trigger_pressed(c as XRController3D):
			return true
	return false


## Freeze the game for N physics frames (hit-stop). Restores time_scale
## even if called rapidly (no stacking). Fire-and-forget.
func hit_stop(frames: int = 3) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		Engine.time_scale = 1.0
		return
	var f := maxi(frames, 1)
	for i in f:
		await tree.physics_frame
		if Engine.time_scale >= 1.0:
			return  # someone else already restored it
	Engine.time_scale = 1.0


## Squash-and-stretch deform on pickup/landing: squash along `axis`, then
## spring back with overshoot. Two tweens, ~0.45s total.
func squash_stretch(node: Node3D, axis: Vector3 = Vector3.UP, squash: float = _SQUASH) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Vector3 = node.scale
	var sq := axis.normalized()
	var squash_scale := Vector3.ONE.lerp(sq, squash) \
		+ (Vector3.ONE - sq) * ((1.0 - squash) * 0.5 + 1.0)
	# Clamp the stretch ring so it stays tasteful.
	squash_scale = squash_scale.min(Vector3(1.6, 1.6, 1.6))
	if not node.is_inside_tree():
		return
	node.scale = base * squash_scale
	var tw := node.create_tween()
	tw.set_parallel(false)
	tw.tween_property(node, "scale", base * Vector3(1.12, 1.12, 1.12), 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, 0.3)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## 120ms overshoot pop for score events. Pairs with UIKit.score_popup().
func scale_pop(node: Node3D, amount: float = 1.25) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var base: Vector3 = node.scale
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base * amount, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)


## 3-second intro sting: big title + subtitle on a dimmed CanvasLayer,
## haptic fanfare + a soft light pulse. Skippable with trigger/click/H.
## Attaches to the current scene root (the launched game).
func title_card(title: String, subtitle: String = "", accent: Color = Color(0.2, 0.9, 1.0)) -> void:
	dismiss_title_card()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var layer := CanvasLayer.new()
	layer.name = "JuiceTitleCard"
	layer.layer = 90
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	# Accent sweep bar.
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(560, 10)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(bar)
	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 84)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title_label.add_theme_constant_override("outline_size", 10)
	vbox.add_child(title_label)
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 34)
		sub.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(1100, 0)
		vbox.add_child(sub)
	var skip := Label.new()
	skip.text = "pull trigger / click to skip"
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.add_theme_font_size_override("font_size", 24)
	skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	vbox.add_child(skip)
	# Entrance: bar sweeps in, title pops.
	layer.modulate.a = 0.0
	var tw := layer.create_tween()
	tw.set_parallel(true)
	tw.tween_property(layer, "modulate:a", 1.0, 0.35)
	tw.tween_property(bar, "scale:x", 1.0, 0.5).from(Vector2(0.05, 1.0))\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Fanfare haptic + sting SFX.
	Haptics.play_sequence("fanfare")
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_sfx("fanfare", 1.0, -4.0)
	_active_card = layer
	_card_timer = tree.create_timer(TITLE_CARD_TIME)
	_card_timer.timeout.connect(_on_card_timeout)


func _on_card_timeout() -> void:
	dismiss_title_card()


## Dismiss the active title card (skip input or timeout).
func dismiss_title_card() -> void:
	_card_timer = null
	if _active_card != null and is_instance_valid(_active_card):
		var layer := _active_card
		_active_card = null
		var tw := layer.create_tween()
		tw.tween_property(layer, "modulate:a", 0.0, 0.3)
		tw.tween_callback(layer.queue_free)


## 0.4s fade-to-black sting on game exit (reverse of the title card).
func exit_transition() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var layer := CanvasLayer.new()
	layer.name = "JuiceExit"
	layer.layer = 95
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var tw := layer.create_tween()
	tw.tween_property(dim, "color:a", 0.9, 0.4)
	tw.tween_callback(layer.queue_free)


## Walk `root`; nodes with meta "interactive"=true get a pulsing emissive
## accent (players instantly see what to touch). Non-interactive stays matte.
## Run once per game scene at launch (the auto-wirer does this).
func affordance_pass(root: Node, tag: String = "interactive") -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.has_meta(tag) and bool(n.get_meta(tag)):
			VisualFX.glow_accent(n as Node3D, Color(0.45, 0.95, 1.0), 1.0, 0.6, 2.2)
			count += 1
	return count


## Floating combo/score text with a scale pop. `pos`: Vector3 (world Label3D)
## or Vector2 (canvas Label via UIKit).
func combo_popup(pos: Variant, text: String, color: Color = Color(1.0, 0.85, 0.25)) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	if pos is Vector3 and host is Node3D:
		var l3d := GraphicsPolish.make_label(text, 96, color)
		(host as Node3D).add_child(l3d)
		l3d.position = pos
		scale_pop(l3d, 1.4)
		if l3d.is_inside_tree():
			var tw := l3d.create_tween()
			tw.set_parallel(true)
			tw.tween_property(l3d, "position:y", l3d.position.y + 0.5, 0.8)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(l3d, "modulate:a", 0.0, 0.8)
			tw.chain().tween_callback(l3d.queue_free)
	elif pos is Vector2 and host is Control:
		UIKit.score_popup(host, pos, text, color)


## Persistent combo counter: returns a small helper node; call
## `increment()` on it (it scale-pops + resets after 2.5s idle).
func combo_counter(parent: Node, pos: Variant) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var host: Node = parent if parent != null else (tree.current_scene if tree != null else null)
	if host == null:
		return null
	var label := Label.new() if (pos is Vector2) else null
	var l3d: Label3D = null
	if pos is Vector3 and host is Node3D:
		l3d = GraphicsPolish.make_label("x0", 72, Color(1.0, 0.85, 0.25))
		(host as Node3D).add_child(l3d)
		l3d.position = pos
	elif pos is Vector2 and host is Control:
		label = Label.new()
		label.text = "x0"
		label.add_theme_font_size_override("font_size", 44)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		label.position = pos
		(host as Control).add_child(label)
	else:
		return null
	var helper := ComboCounter.new()
	helper.name = "JuiceComboCounter"
	helper.setup(label, l3d)
	host.add_child(helper)
	return helper


## Tiny self-contained combo state machine (inner class so JuiceFX stays
## one file).
class ComboCounter:
	extends Node
	var _label: Label = null
	var _l3d: Label3D = null
	var _count := 0
	var _idle := 0.0

	func setup(label: Label, l3d: Label3D) -> void:
		_label = label
		_l3d = l3d

	func _process(delta: float) -> void:
		if _count <= 0:
			return
		_idle += delta
		if _idle > 2.5:
			_count = 0
			_idle = 0.0
			_show()

	func increment(amount: int = 1) -> void:
		_count += amount
		_idle = 0.0
		_show()
		if is_instance_valid(_l3d):
			var tree := Engine.get_main_loop() as SceneTree
			var fx: Node = tree.root.get_node_or_null("JuiceFX") if tree != null else null
			if fx != null and fx.has_method("scale_pop"):
				fx.scale_pop(_l3d, 1.35)
		elif is_instance_valid(_label):
			var tw := _label.create_tween()
			tw.tween_property(_label, "scale", Vector2(1.35, 1.35), 0.1)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_label, "scale", Vector2.ONE, 0.2)

	func _show() -> void:
		var t := "x%d" % _count
		if is_instance_valid(_label):
			_label.text = t
		if is_instance_valid(_l3d):
			_l3d.text = t
