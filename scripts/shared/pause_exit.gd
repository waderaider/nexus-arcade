## PauseExit.gd - GLOBAL pause/exit autoload for NEXUS ARCADE (autoload: PauseExit).
## v0.9.0 ship-blocker: every surviving game gets a working Exit/Quit-to-
## launcher WITHOUT per-game code. Attached by the hub auto-wirer
## (hub.gd _autowire_game) on every game launch — same opt-out flag
## (`static var no_auto_wire := true`). Never active in the hub itself.
##
## What the player gets in every game:
##   1. Controller menu button (or Esc on desktop) -> pause overlay.
##      Overlay: Resume | Restart Game | Quit to Hub. get_tree().paused
##      actually freezes gameplay; AudioKit intensity ducks to 0 on pause
##      and restores on resume.
##   2. A small floating pause button, pinned top-right of the view in every
##      game scene. Tapping it opens the SAME overlay (never quits directly
##      — no accidental exits).
## Input: reuses the v0.8.0 XRUIPointer rigs (controller laser + hand pinch)
## driving real 2D Buttons in SubViewports, plus a camera-center gaze dwell
## fallback (1.2s) — the same three paths as the launcher. No fourth input
## system was built.
##
## Headless-safe: everything is guarded; with no XR runtime the overlay and
## exit button still work via mouse + Esc. NOTE: pause feel must be sanity-
## checked on Quest 3 (never claimed tested here).
extends Node

const EXIT_VP := Vector2i(256, 256)
const EXIT_QUAD := Vector2(0.15, 0.15)
const PAUSE_VP := Vector2i(1200, 800)
const PAUSE_QUAD := Vector2(1.6, 1.07)
const PAUSE_DIST := 1.8
const GAZE_DWELL := 1.2

var _game: Node = null
var _on_quit_cb := Callable()
var _on_restart_cb := Callable()
var _paused := false
var _pre_intensity := 0

var _xr_origin: Node3D = null
var _controllers: Array[XRController3D] = []
var _menu_prev := {}

# Exit button rig.
var _exit_root: Node3D = null
var _exit_vp: SubViewport = null
var _exit_quad: MeshInstance3D = null
var _exit_pointers: Array[XRUIPointer] = []
# Pause overlay rig.
var _pause_root: Node3D = null
var _pause_vp: SubViewport = null
var _pause_quad: MeshInstance3D = null
var _pause_pointers: Array[XRUIPointer] = []
var _pause_title: Label = null
# Legend / Controls page state.
var _overlay_vbox: VBoxContainer = null
var _overlay_page := "menu"  # "menu" | "controls"
var _intro_open := false
var _legend_cfg := {}
var _legend_game := ""
var _trigger_prev := {}

# Gaze fallback state (per quad).
var _gaze_dwell := 0.0
var _gaze_hover: Control = null
var _gaze_target := ""  # "exit" or "pause"


func _ready() -> void:
	# Must keep polling the menu button + driving pointers while the tree
	# is paused (the overlay itself lives under a paused tree).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Attach to a launched game. Called by the hub auto-wirer (opt-out via
## no_auto_wire). `on_quit`/`on_restart` come from the hub so this file
## never hard-codes launcher paths.
func attach_to_game(game: Node, on_quit: Callable, on_restart: Callable) -> void:
	if _game != null and is_instance_valid(_game):
		detach()
	_game = game
	_on_quit_cb = on_quit
	_on_restart_cb = on_restart
	_paused = false
	_discover_xr()
	_build_exit_button()
	_build_overlay()
	_exit_root.visible = true
	_pause_root.visible = false
	_update_pointer_visibility()
	if is_instance_valid(_game):
		_game.tree_exiting.connect(_on_game_exiting.bind(_game))


func detach() -> void:
	if _paused:
		_set_paused(false)
	_game = null
	_on_quit_cb = Callable()
	_on_restart_cb = Callable()
	if is_instance_valid(_exit_root):
		_exit_root.visible = false
	if is_instance_valid(_pause_root):
		_pause_root.visible = false
	_update_pointer_visibility()


func is_game_active() -> bool:
	return _game != null and is_instance_valid(_game)


func is_paused() -> bool:
	return _paused


func toggle_pause() -> void:
	if not is_game_active():
		return
	_set_paused(not _paused)


func _on_game_exiting(g: Node) -> void:
	# Restart re-attaches the NEW game synchronously; only detach when the
	# exiting node is the one we're actually attached to.
	if g == _game:
		detach()


# ------------------------------------------------------------------ loop ---

func _process(delta: float) -> void:
	if not is_game_active():
		return
	var xr := get_viewport().use_xr
	for p in _exit_pointers + _pause_pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
	_poll_menu_button()
	_position_exit_button()
	_update_pointer_visibility()
	_process_gaze(delta)


func _input(event: InputEvent) -> void:
	if not is_game_active():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if _intro_open:
				dismiss_intro_legend()
			else:
				toggle_pause()
			get_viewport().set_input_as_handled()
			return
	# Desktop fallback: forward the real mouse into whichever quad is up.
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if _paused and _pause_root.visible:
			_forward_mouse(event, _pause_quad, _pause_vp)
		elif not _paused and _exit_root.visible:
			_forward_mouse(event, _exit_quad, _exit_vp)


func _poll_menu_button() -> void:
	if not get_viewport().use_xr:
		return
	for ctl in _controllers:
		if ctl == null or not is_instance_valid(ctl):
			continue
		# get_tracker() returns the configured NAME (never null) — liveness
		# must go through XRServer (v0.8.0 root-cause lesson).
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var id := ctl.get_instance_id()
		var now: bool = ctl.is_button_pressed("menu_button")
		if now and not bool(_menu_prev.get(id, false)):
			if _intro_open:
				dismiss_intro_legend()
			else:
				toggle_pause()
		_menu_prev[id] = now
		# Intro legend dismisses on any trigger press too.
		if _intro_open:
			var trig := XRUIPointer.trigger_pressed(ctl)
			if trig and not bool(_trigger_prev.get(id, false)):
				dismiss_intro_legend()
			_trigger_prev[id] = trig


func _update_pointer_visibility() -> void:
	var show_exit := is_game_active() and not _paused and not _intro_open
	var show_pause := is_game_active() and (_paused or _intro_open)
	for p in _exit_pointers:
		if is_instance_valid(p):
			p.visible = show_exit
	for p in _pause_pointers:
		if is_instance_valid(p):
			p.visible = show_pause


# ------------------------------------------------------------ pause state ---

func _set_paused(p: bool) -> void:
	if p == _paused or not is_game_active():
		return
	_paused = p
	get_tree().paused = p
	var ak := get_node_or_null("/root/AudioKit")
	if p:
		_build_menu_page()  # always open on the menu page, never Controls
		if ak != null:
			_pre_intensity = AudioKit.intensity()
			AudioKit.set_intensity(0)
		_place_overlay()
		if _pause_title != null:
			_pause_title.text = "PAUSED"
	else:
		if ak != null:
			AudioKit.set_intensity(_pre_intensity)
	_pause_root.visible = p
	_exit_root.visible = not p
	_gaze_dwell = 0.0
	_gaze_hover = null
	_update_pointer_visibility()
	if p:
		Haptics.confirm()
	else:
		Haptics.tick()


func _on_resume() -> void:
	_set_paused(false)


func _on_restart() -> void:
	var cb := _on_restart_cb
	_set_paused(false)
	detach()  # the hub's _load_game re-attaches the fresh game instance
	if cb.is_valid():
		cb.call()


func _on_quit() -> void:
	var cb := _on_quit_cb
	_set_paused(false)
	detach()
	if cb.is_valid():
		cb.call()


# ------------------------------------------------------------------ build ---

func _discover_xr() -> void:
	if _xr_origin != null and is_instance_valid(_xr_origin):
		return
	var scene := get_tree().current_scene
	if scene != null:
		_xr_origin = scene.find_child("XROrigin3D", true, false) as Node3D
	if _xr_origin == null:
		var found := get_tree().root.find_children("*", "XROrigin3D", true, false)
		if not found.is_empty():
			_xr_origin = found[0] as Node3D
	_controllers.clear()
	if _xr_origin != null:
		for side in ["LeftController", "RightController"]:
			var ctl := _xr_origin.get_node_or_null(side) as XRController3D
			if ctl != null:
				_controllers.append(ctl)


func _make_quad(vp_size: Vector2i, quad_size: Vector2) -> Array:
	# Returns [Node3D root, SubViewport, MeshInstance3D quad].
	var root := Node3D.new()
	var vp := SubViewport.new()
	vp.size = vp_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = true
	root.add_child(vp)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ui)
	var qm := QuadMesh.new()
	qm.size = quad_size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var vpt := ViewportTexture.new()
	vpt.viewport_path = vp.get_path()
	mat.albedo_texture = vpt
	var quad := MeshInstance3D.new()
	quad.mesh = qm
	quad.material_override = mat
	root.add_child(quad)
	add_child(root)
	return [root, ui, vp, quad]


func _build_exit_button() -> void:
	if _exit_root != null and is_instance_valid(_exit_root):
		return
	_discover_xr()
	var parts := _make_quad(EXIT_VP, EXIT_QUAD)
	_exit_root = parts[0]
	var ui: Control = parts[1]
	_exit_vp = parts[2]
	_exit_quad = parts[3]
	_exit_root.name = "PauseExitButton"
	_exit_root.visible = false
	_exit_root.top_level = true  # positioned manually each frame
	var b := Button.new()
	b.text = "❚❚"
	b.add_theme_font_size_override("font_size", 120)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.18, 0.72)
	sb.set_corner_radius_all(48)
	sb.border_color = Color(0.4, 0.9, 1.0, 0.9)
	sb.set_border_width_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.1, 0.2, 0.34, 0.85)
	b.add_theme_stylebox_override("hover", hov)
	b.pressed.connect(toggle_pause)
	ui.add_child(b)
	_make_pointers(_exit_vp, _exit_quad, _exit_pointers)


func _build_overlay() -> void:
	if _pause_root != null and is_instance_valid(_pause_root):
		return
	_discover_xr()
	var parts := _make_quad(PAUSE_VP, PAUSE_QUAD)
	_pause_root = parts[0]
	var ui: Control = parts[1]
	_pause_vp = parts[2]
	_pause_quad = parts[3]
	_pause_root.name = "PauseExitOverlay"
	_pause_root.visible = false
	_pause_root.top_level = true
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.04, 0.07, 0.13, 0.97)
	psb.set_corner_radius_all(24)
	psb.border_color = Color(0.4, 0.9, 1.0)
	psb.set_border_width_all(4)
	psb.content_margin_left = 60.0
	psb.content_margin_right = 60.0
	psb.content_margin_top = 44.0
	psb.content_margin_bottom = 44.0
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	_overlay_vbox = VBoxContainer.new()
	_overlay_vbox.add_theme_constant_override("separation", 26)
	_overlay_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_overlay_vbox)
	_build_menu_page()
	_make_pointers(_pause_vp, _pause_quad, _pause_pointers)


## (Re)build the pause menu page: Resume | Controls | Restart | Quit.
func _build_menu_page() -> void:
	_overlay_page = "menu"
	_clear_overlay_vbox()
	_pause_title = Label.new()
	_pause_title.text = "PAUSED"
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title.add_theme_font_size_override("font_size", 72)
	_pause_title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_overlay_vbox.add_child(_pause_title)
	var hint := Label.new()
	hint.text = "Menu button / Esc resumes"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 28)
	hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	_overlay_vbox.add_child(hint)
	for spec in [["Resume", _on_resume, Color(0.0, 0.5, 0.3)],
			["Controls", _on_controls, Color(0.1, 0.3, 0.55)],
			["Restart Game", _on_restart, Color(0.5, 0.35, 0.1)],
			["Quit to Hub", _on_quit, Color(0.5, 0.15, 0.15)]]:
		_overlay_vbox.add_child(_overlay_button(spec[0], spec[1], spec[2]))


func _overlay_button(text: String, cb: Callable, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 96)
	b.add_theme_font_size_override("font_size", 40)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = color
	bsb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", bsb)
	var bhov := bsb.duplicate() as StyleBoxFlat
	bhov.bg_color = color.lightened(0.25)
	b.add_theme_stylebox_override("hover", bhov)
	b.pressed.connect(cb)
	return b


func _clear_overlay_vbox() -> void:
	if _overlay_vbox == null:
		return
	for c in _overlay_vbox.get_children():
		_overlay_vbox.remove_child(c)
		c.queue_free()
	_pause_title = null


## Controls/legend page, shared by the pause menu and the intro flow.
func _show_controls_page(back_label: String, on_back: Callable) -> void:
	_overlay_page = "controls"
	_clear_overlay_vbox()
	# controller_skins.gd exposes class_name ControllerSkins, but loading by
	# path keeps this working even when the editor's global class cache is
	# stale (e.g. fresh clones).
	var skins_scr: GDScript = load("res://scripts/shared/controller_skins.gd")
	_overlay_vbox.add_child(skins_scr.legend_control(_legend_cfg, _legend_game))
	_overlay_vbox.add_child(_overlay_button(back_label, on_back, Color(0.0, 0.5, 0.3)))


func _on_controls() -> void:
	_show_controls_page("Back", _build_menu_page)


## Intro flow: show the button legend on game start (game keeps running
## behind it). Dismiss with trigger / menu button / Esc / the button itself
## / gaze dwell — same input paths as everything else.
func show_controls_intro(cfg: Dictionary, game_name: String) -> void:
	if not is_game_active() or _paused:
		return
	_legend_cfg = cfg
	_legend_game = game_name
	_intro_open = true
	_show_controls_page("Got it!", dismiss_intro_legend)
	_place_overlay()
	_pause_root.visible = true
	_gaze_dwell = 0.0
	_gaze_hover = null
	_update_pointer_visibility()
	Haptics.confirm()


func dismiss_intro_legend() -> void:
	if not _intro_open:
		return
	_intro_open = false
	_pause_root.visible = false
	_build_menu_page()
	_update_pointer_visibility()
	Haptics.tick()
	_make_pointers(_pause_vp, _pause_quad, _pause_pointers)


## One XRUIPointer per input source, wired to inject clicks/motion into the
## given viewport. The v0.8.0 rigs — laser + pinch + (below) gaze.
func _make_pointers(vp: SubViewport, quad: MeshInstance3D, arr: Array[XRUIPointer]) -> void:
	if not arr.is_empty():
		return
	for ctl in _controllers:
		var p := XRUIPointer.new()
		p.controller = ctl
		p.setup(vp, quad, _xr_origin)
		p.xr_clicked.connect(_on_pointer_clicked.bind(vp))
		p.xr_moved.connect(_on_pointer_moved.bind(vp))
		p.visible = false
		add_child(p)
		arr.append(p)
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.hand_side = side
		hp.setup(vp, quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked.bind(vp))
		hp.xr_moved.connect(_on_pointer_moved.bind(vp))
		hp.visible = false
		add_child(hp)
		arr.append(hp)


func _on_pointer_clicked(viewport_pos: Vector2, vp: SubViewport) -> void:
	_inject_click(vp, viewport_pos)


func _on_pointer_moved(viewport_pos: Vector2, vp: SubViewport) -> void:
	if vp == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = viewport_pos
	vp.push_input(ev)


func _inject_click(vp: SubViewport, viewport_pos: Vector2) -> void:
	if vp == null:
		return
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = viewport_pos
		vp.push_input(ev)


# --------------------------------------------------------------- placement ---

func _camera() -> Camera3D:
	if _xr_origin != null and is_instance_valid(_xr_origin):
		var c := _xr_origin.get_node_or_null("XRCamera3D") as Camera3D
		if c != null:
			return c
	return get_viewport().get_camera_3d()


## Pin the exit button top-right of the view, ~1.1m out. top_level so it
## never inherits game transforms.
func _position_exit_button() -> void:
	if _exit_root == null or not is_instance_valid(_exit_root) or not _exit_root.visible:
		return
	var cam := _camera()
	if cam == null:
		return
	var t := cam.global_transform
	var fwd := -t.basis.z.normalized()
	var right := t.basis.x.normalized()
	var up := t.basis.y.normalized()
	_exit_root.global_position = t.origin + fwd * 1.1 + right * 0.42 + up * 0.3
	# Face the camera.
	var to_cam := (t.origin - _exit_root.global_position).normalized()
	_exit_root.global_transform = Transform3D(Basis.looking_at(to_cam), _exit_root.global_position)


## Yaw-align the pause overlay to the user's view on every open.
func _place_overlay() -> void:
	if _pause_root == null or not is_instance_valid(_pause_root):
		return
	var cam := _camera()
	if cam == null:
		_pause_root.global_position = Vector3(0, 1.6, -1.8)
		_pause_root.global_rotation = Vector3.ZERO
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var target := cp + fwd * PAUSE_DIST
	target.y = clampf(cp.y, 1.1, 1.75)
	_pause_root.global_position = target
	var to_user := cp - target
	to_user.y = 0.0
	if to_user.length() > 0.05:
		_pause_root.global_rotation = Vector3(0.0, atan2(to_user.x, to_user.z), 0.0)


# ------------------------------------------------------------ gaze fallback ---

## Camera-center gaze with 1.2s dwell — same fallback contract as the hub.
## Runs only when no laser/pinch pointer of the active set is live.
func _process_gaze(delta: float) -> void:
	if not get_viewport().use_xr:
		return
	var quad: MeshInstance3D = null
	var vp: SubViewport = null
	var live := false
	if (_paused or _intro_open) and _pause_root.visible:
		quad = _pause_quad
		vp = _pause_vp
		live = _any_pointer_live(_pause_pointers)
		_gaze_target = "pause"
	elif not _paused and _exit_root.visible:
		quad = _exit_quad
		vp = _exit_vp
		live = _any_pointer_live(_exit_pointers)
		_gaze_target = "exit"
	else:
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	if live or quad == null:
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	var cam := _camera()
	if cam == null:
		return
	var size := Vector2(vp.size)
	var hit := XRUIPointer.ray_to_viewport(
		cam.global_position, -cam.global_transform.basis.z.normalized(), quad, size)
	if not bool(hit["hit"]):
		_gaze_dwell = 0.0
		_gaze_hover = null
		return
	_on_pointer_moved(hit["pos"], vp)
	var hovered := vp.gui_get_hovered_control()
	if hovered is Button and hovered == _gaze_hover:
		_gaze_dwell += delta
		if _gaze_dwell >= GAZE_DWELL:
			_gaze_dwell = 0.0
			_inject_click(vp, hit["pos"])
	else:
		_gaze_dwell = 0.0
		_gaze_hover = hovered


func _any_pointer_live(pointers: Array[XRUIPointer]) -> bool:
	for p in pointers:
		if is_instance_valid(p) and p.visible and p.is_source_live():
			return true
	return false


func _forward_mouse(event: InputEvent, quad: MeshInstance3D, vp: SubViewport) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or quad == null or vp == null:
		return
	if not (event is InputEventMouse):
		return
	var me := event as InputEventMouse
	var hit := XRUIPointer.ray_to_viewport(
		cam.project_ray_origin(me.position),
		cam.project_ray_normal(me.position),
		quad, Vector2(vp.size))
	if not bool(hit["hit"]):
		return
	var ev2 := event.duplicate() as InputEventMouse
	ev2.position = hit["pos"]
	vp.push_input(ev2)
