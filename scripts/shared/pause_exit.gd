## PauseExit.gd - GLOBAL pause/exit autoload for NEXUS ARCADE (autoload: PauseExit).
## v0.9.0 ship-blocker: every surviving game gets a working Exit/Quit-to-
## launcher WITHOUT per-game code. Attached by the hub auto-wirer
## (hub.gd _autowire_game) on every game launch — same opt-out flag
## (`static var no_auto_wire := true`). Never active in the hub itself.
##
## v0.11.0 (wade 2026-10-12, SHIP-BLOCKER): the pause menu is a plain flat 2D
## GRID of game cards — the grid IS the game picker (direct jump), with
## Prev/Next game buttons in a compact header row and the big red EXIT TO
## LAUNCHER at the bottom. Panel: placed ONCE per open, then 100% STATIC in
## world space (the v0.9.3 continuous-recenter is dead by direct order).
## The floating ❚❚ exit button stays head-locked (deliberate exception —
## hand/pinch users need an on-screen affordance; a static button is useless
## the moment the user turns around mid-game).
##
## v0.11.0 Neon Duel pause-spam fixes (telemetry-driven):
##   - pause_open telemetry gains a `via` field (menu_hold/exit_button/esc)
##   - combat-profile games (static var pause_profile := "combat") hide the
##     floating ❚❚ while fighting and require a 0.45s menu-button HOLD to
##     pause (fill ring on the ❚❚ quad; taps ignored; Esc stays instant)
##   - the ❚❚ button is hover-armed: clicks are ignored unless the ray
##     dwelled >= 250ms on it (kills accidental trigger-squeeze opens)
##   - per-game `static var exit_button_corner` moves the ❚❚
##     (top_right/top_left/bottom_right/bottom_left)
##
## v0.11.0 settings (wade's direct order): the action row gains a Settings
## button — one tap to input/gaze/hand/tooltips/graphics options. Every
## option changes real behavior (GameSettings); no placebo toggles.
##
## Input: reuses the v0.8.0 XRUIPointer rigs (controller laser + hand pinch)
## driving real 2D Buttons in SubViewports, plus a camera-center gaze dwell
## fallback (GameSettings.gaze_dwell, default 1.2s) — the same three paths as
## the launcher. The input_method setting can prefer controllers or hands.
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
const HOLD_TO_PAUSE_MSEC := 450
const EXIT_ARM_DWELL := 0.25  # hover-arm dwell before ❚❚ accepts clicks (s)

const COL_ACCENT := Color(0.0, 0.941, 1.0)   # #00F0FF
const COL_PANEL := Color(0.071, 0.094, 0.169) # #12182B
const COL_DIM := Color(0.561, 0.639, 0.749)   # #8FA3BF
const COL_DARK_TEXT := Color(0.0, 0.075, 0.094)

var _game: Node = null
var _on_quit_cb := Callable()
var _on_restart_cb := Callable()
var _paused := false
var _pre_intensity := 0

# v0.11.0: game identity + game-picker grid context (set by the hub).
var _game_name := ""
var _nav_names: PackedStringArray = PackedStringArray()
var _nav_colors: Array = []
var _nav_index := -1
var _on_switch_cb := Callable()  # delta-based Prev/Next (hub wraps around)
var _on_goto_cb := Callable()    # absolute-index direct jump (grid cards)

# v0.11.0: per-game pause profile (read from the game script's static vars).
var _pause_profile := ""         # "combat" = hide ❚❚ + hold-to-pause
var _exit_corner := "top_right"  # or top_left / bottom_right / bottom_left

var _xr_origin: Node3D = null
var _controllers: Array[XRController3D] = []
var _menu_prev := {}
var _menu_hold_start := {}  # controller id -> press-start msec (combat hold)

# Exit button rig.
var _exit_root: Node3D = null
var _exit_vp: SubViewport = null
var _exit_quad: MeshInstance3D = null
var _exit_btn: Button = null
var _hold_ring: Control = null
var _exit_pointers: Array[XRUIPointer] = []
var _exit_dwell := 0.0  # hover-arm dwell accumulator
# Pause overlay rig.
var _pause_root: Node3D = null
var _pause_vp: SubViewport = null
var _pause_quad: MeshInstance3D = null
var _pause_pointers: Array[XRUIPointer] = []
# Legend / Controls / Settings page state.
var _overlay_vbox: VBoxContainer = null
var _overlay_page := "menu"  # "menu" | "controls" | "settings"
var _intro_open := false
var _legend_cfg := {}
var _legend_game := ""
var _trigger_prev := {}
# Grid scroll state (hold-to-repeat, launcher pattern).
var _grid_scroll: ScrollContainer = null
var _scroll_dir := 0
var _scroll_accum := 0.0

# Gaze fallback state (per quad).
var _gaze_dwell := 0.0
var _gaze_hover: Control = null
var _gaze_target := ""  # "exit" or "pause"

# v0.9.3: belt-and-suspenders fallback input (independent of the XRUIPointer
# signal rigs above). Target switches between the exit-button quad and the
# pause-overlay quad via _direct_set_target().
var _direct: DirectUIInput = null
var _direct_vp: SubViewport = null
var _last_click_msec := 0
var _last_click_pos := Vector2.INF


func _ready() -> void:
	# Must keep polling the menu button + driving pointers while the tree
	# is paused (the overlay itself lives under a paused tree).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_direct = DirectUIInput.new()
	_direct.name = "PauseDirectInput"
	add_child(_direct)
	_direct.configure(null, null, null, _direct_moved, _direct_clicked)


## Attach to a launched game. Called by the hub auto-wirer (opt-out via
## no_auto_wire). `on_quit`/`on_restart` come from the hub so this file
## never hard-codes launcher paths. `game_name` feeds telemetry + the
## grid header. Per-game static vars `pause_profile` / `exit_button_corner`
## are read here (same pattern as controller_skins' controller_config).
func attach_to_game(game: Node, on_quit: Callable, on_restart: Callable, game_name: String = "") -> void:
	if _game != null and is_instance_valid(_game):
		detach()
	_game = game
	_game_name = game_name
	_on_quit_cb = on_quit
	_on_restart_cb = on_restart
	_paused = false
	_pause_profile = ""
	_exit_corner = "top_right"
	_exit_dwell = 0.0
	_menu_hold_start.clear()
	var scr := game.get_script() as GDScript
	if scr != null:
		var pp: Variant = scr.get("pause_profile")
		if pp != null and str(pp) != "":
			_pause_profile = str(pp)
		var ec: Variant = scr.get("exit_button_corner")
		if ec != null and str(ec) != "":
			_exit_corner = str(ec)
	_discover_xr()
	_build_exit_button()
	_build_overlay()
	_exit_root.visible = _pause_profile != "combat"
	_pause_root.visible = false
	_direct_set_target(_exit_vp, _exit_quad)
	_direct.source_filter = GameSettings.input_method
	_update_pointer_visibility()
	if is_instance_valid(_game):
		_game.tree_exiting.connect(_on_game_exiting.bind(_game))


## v0.11.0: ordered game names + accent colors + current index + hub
## navigation callables. `on_switch` takes a delta (-1/+1, hub wraps);
## `on_goto` takes an absolute index (grid direct jump). Both route through
## the hub's _load_game so autowiring, music, BugReporter session,
## PauseExit re-attach and telemetry run exactly as a launcher launch.
func set_game_nav(names: PackedStringArray, colors: Array, index: int,
		on_switch: Callable, on_goto: Callable) -> void:
	_nav_names = names
	_nav_colors = colors
	_nav_index = index
	_on_switch_cb = on_switch
	_on_goto_cb = on_goto


func detach() -> void:
	if _paused:
		_set_paused(false)
	_game = null
	_game_name = ""
	_on_quit_cb = Callable()
	_on_restart_cb = Callable()
	_on_switch_cb = Callable()
	_on_goto_cb = Callable()
	_nav_index = -1
	_pause_profile = ""
	_exit_corner = "top_right"
	_exit_dwell = 0.0
	_menu_hold_start.clear()
	_hide_hold_ring()
	_direct_set_target(null, null)
	if is_instance_valid(_exit_root):
		_exit_root.visible = false
	if is_instance_valid(_pause_root):
		_pause_root.visible = false
	_update_pointer_visibility()


func is_game_active() -> bool:
	return _game != null and is_instance_valid(_game)


func is_paused() -> bool:
	return _paused


## v0.11.0: `via` attributes the pause source for telemetry
## ("menu_hold" / "exit_button" / "esc") — the hardware verification gate
## for the Neon Duel pause-spam fix. Menu-button opens are always hold
## opens (QA §1.3); there is no bare-edge menu path anymore.
func toggle_pause(via: String = "menu_hold") -> void:
	if not is_game_active():
		return
	_set_paused(not _paused, via)


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
	if _direct != null and is_instance_valid(_direct):
		_direct.xr_mode = xr
	_poll_menu_button()
	_position_exit_button()
	_update_pointer_visibility()
	_process_gaze(delta)
	_process_scroll_repeat(delta)
	_process_exit_dwell(delta)


func _input(event: InputEvent) -> void:
	if not is_game_active():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if _intro_open:
				dismiss_intro_legend()
			else:
				toggle_pause("esc")  # v0.11.0: Esc stays instant, attributed
			get_viewport().set_input_as_handled()
			return
	# Desktop fallback: forward the real mouse into whichever quad is up.
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var gt := get_node_or_null("/root/GameplayTelemetry")
			if gt != null:
				gt.note_input_method("mouse")
		if _paused and _pause_root.visible:
			_forward_mouse(event, _pause_quad, _pause_vp)
		elif not _paused and _exit_root.visible:
			_forward_mouse(event, _exit_quad, _exit_vp)


## v0.11.0: the controller menu button requires a 0.45s HOLD to open pause
## (fill ring on the ❚❚ quad); sub-threshold taps are ignored. This
## applies to EVERY profile, not just combat - the pause-spam fix is universal
## (QA_PLAN_V0110 §1.3, NO-SHIP §3.1.8: no bare rising edge anywhere).
## Intro-legend dismissal (tap = dismiss) is unchanged. Unpausing via the
## menu button stays a rising edge (closing is always snappy); Esc stays
## instant. Every open is attributed via="menu_hold" for the digest.
func _poll_menu_button() -> void:
	if not get_viewport().use_xr:
		return
	var hold_to_pause := not _paused and not _intro_open
	for ctl in _controllers:
		if ctl == null or not is_instance_valid(ctl):
			continue
		# get_tracker() returns the configured NAME (never null) — liveness
		# must go through XRServer (v0.8.0 root-cause lesson).
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		var id := ctl.get_instance_id()
		var now: bool = ctl.is_button_pressed("menu_button")
		var was := bool(_menu_prev.get(id, false))
		if hold_to_pause:
			if now and not was:
				_menu_hold_start[id] = Time.get_ticks_msec()
				_show_hold_ring()
			elif now and was:
				var held := int(Time.get_ticks_msec()) - int(_menu_hold_start.get(id, 0))
				_update_hold_ring(clampf(float(held) / float(HOLD_TO_PAUSE_MSEC), 0.0, 1.0))
				if held >= HOLD_TO_PAUSE_MSEC:
					_menu_hold_start.erase(id)
					_hide_hold_ring()
					toggle_pause("menu_hold")
			elif not now and was:
				# Released early: tap ignored (the pause-spam fix).
				_menu_hold_start.erase(id)
				_hide_hold_ring()
		else:
			if now and not was:
				if _intro_open:
					dismiss_intro_legend()
				else:
					toggle_pause("menu_hold")
		_menu_prev[id] = now
		# Intro legend dismisses on any trigger press too.
		if _intro_open:
			var trig := XRUIPointer.trigger_pressed(ctl)
			if trig and not bool(_trigger_prev.get(id, false)):
				dismiss_intro_legend()
			_trigger_prev[id] = trig


## v0.11.0: input_method preference (GameSettings) filters which pointer
## rigs are visible. "auto" = current behavior (everything live).
func _update_pointer_visibility() -> void:
	var show_exit := is_game_active() and not _paused and not _intro_open \
		and _pause_profile != "combat"
	var show_pause := is_game_active() and (_paused or _intro_open)
	var allow_c := GameSettings.allow_controllers()
	var allow_h := GameSettings.allow_hands()
	for p in _exit_pointers:
		if is_instance_valid(p):
			p.visible = show_exit and _pointer_allowed(p, allow_c, allow_h)
	for p in _pause_pointers:
		if is_instance_valid(p):
			p.visible = show_pause and _pointer_allowed(p, allow_c, allow_h)


func _pointer_allowed(p: XRUIPointer, allow_c: bool, allow_h: bool) -> bool:
	if p.controller != null:
		return allow_c
	return allow_h


# ------------------------------------------------------------ pause state ---

func _set_paused(p: bool, via: String = "") -> void:
	if p == _paused or not is_game_active():
		return
	_paused = p
	get_tree().paused = p
	var ak := get_node_or_null("/root/AudioKit")
	if p:
		_build_menu_page()  # always open on the menu page, never Controls/Settings
		if ak != null and ak.has_method("intensity"):
			_pre_intensity = ak.intensity()
			ak.set_intensity(0)
		_place_overlay()
		# v0.11.0: pause_open gains the `via` field (menu_button/exit_button/
		# esc) — the hardware verification gate for the Neon Duel fix.
		var gt := get_node_or_null("/root/GameplayTelemetry")
		if gt != null and _game_name != "":
			gt.event("pause_open", {"game": _game_name, "via": via})
	else:
		if ak != null and ak.has_method("set_intensity"):
			ak.set_intensity(_pre_intensity)
	_pause_root.visible = p
	_exit_root.visible = not p and _pause_profile != "combat"
	if p:
		_direct_set_target(_pause_vp, _pause_quad)
	else:
		_direct_set_target(_exit_vp, _exit_quad)
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


## v0.11.0: hover-armed ❚❚ button. Clicks are ignored unless the pointer ray
## dwelled >= 250ms on the button — this kills the accidental
## trigger-squeeze opens (Neon Duel telemetry: 4 pause-opens in 37s).
func _on_exit_button_pressed() -> void:
	if _exit_dwell < EXIT_ARM_DWELL:
		return
	toggle_pause("exit_button")


## Hover-arm dwell accumulator: only counts while the exit button is up and
## the pointer is actually on it.
func _process_exit_dwell(delta: float) -> void:
	if _paused or not is_instance_valid(_exit_root) or not _exit_root.visible \
			or _exit_vp == null or not is_instance_valid(_exit_vp):
		_exit_dwell = 0.0
		return
	var hovered := _exit_vp.gui_get_hovered_control()
	if hovered != null and hovered == _exit_btn:
		_exit_dwell += delta
	else:
		_exit_dwell = 0.0


# ------------------------------------------------------- hold-to-pause ring ---

func _show_hold_ring() -> void:
	if is_instance_valid(_exit_root):
		_exit_root.visible = true
	if _hold_ring != null and is_instance_valid(_hold_ring):
		_hold_ring.set("progress", 0.0)
		_hold_ring.visible = true
		_hold_ring.queue_redraw()


func _update_hold_ring(prog: float) -> void:
	if _hold_ring != null and is_instance_valid(_hold_ring):
		_hold_ring.set("progress", prog)
		_hold_ring.queue_redraw()


func _hide_hold_ring() -> void:
	if _hold_ring != null and is_instance_valid(_hold_ring):
		_hold_ring.visible = false
	# Restore the combat-hidden state when not paused.
	if not _paused and _pause_profile == "combat" and is_instance_valid(_exit_root):
		_exit_root.visible = false

# ------------------------------------------------------------------ build ---

func _discover_xr() -> void:
	if _xr_origin != null and is_instance_valid(_xr_origin):
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
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
	# Returns [Node3D root, Control ui, SubViewport, MeshInstance3D quad].
	var root := Node3D.new()
	var vp := SubViewport.new()
	vp.size = vp_size
	# Stop rendering while hidden (perf); resumes on show.
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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
	sb.set_corner_radius_all(0)
	sb.border_color = Color(0.4, 0.9, 1.0, 0.9)
	sb.set_border_width_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.1, 0.2, 0.34, 0.85)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_exit_button_pressed)  # v0.11.0: hover-armed
	_exit_btn = b
	ui.add_child(b)
	# v0.11.0: hold-to-pause fill ring, drawn over the ❚❚ during a menu-
	# button hold (combat profile). Hidden otherwise.
	_hold_ring = HoldRing.new()
	_hold_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hold_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_ring.visible = false
	ui.add_child(_hold_ring)
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
	psb.set_corner_radius_all(0)
	psb.border_color = Color(0.4, 0.9, 1.0)
	psb.set_border_width_all(4)
	psb.content_margin_left = 40.0
	psb.content_margin_right = 40.0
	psb.content_margin_top = 32.0
	psb.content_margin_bottom = 32.0
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	_overlay_vbox = VBoxContainer.new()
	_overlay_vbox.add_theme_constant_override("separation", 12)
	_overlay_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_overlay_vbox)
	_build_menu_page()
	_make_pointers(_pause_vp, _pause_quad, _pause_pointers)


## (Re)build the pause menu page — v0.11.0 (wade 2026-10-12, SHIP-BLOCKER):
## plain flat 2D grid of game cards. Layout (1200x800 viewport, margins
## L/R 40 T/B 32, VBox separation 12):
##   1. Title row: "❚❚ PAUSED" 56px accent + "— {GameName}" 32px dim
##   2. Action row: Resume / Controls / Restart Game / Settings (new) —
##      expand-fill, min height 88, 36px, flat zero-radius
##   3. Picker header: "◀ Prev" (200x64, 30px) + "JUMP TO A GAME · {N}"
##      (28px, expand-fill) + "Next ▶" (200x64, 30px). Prev/Next are the
##      hardware-verified game-navigation pattern — kept exactly.
##   4. Grid zone (expand-fill): ScrollContainer → GridContainer columns=5,
##      h/v sep 12; cards 196x150 (56x56 color chip + 24px name). Hold-to-
##      repeat ▲/▼ scroll buttons (synthetic clicks can't drag-scroll —
##      same reason as the launcher).
##   5. EXIT TO LAUNCHER: full width x104, 44px, big red (unchanged).
## The grid IS the game picker: cards jump directly; the current-game card
## (4px accent border) resumes. Fit: fixed content 432px -> grid zone 368px
## (>= 2 card rows); 70 games = 14 rows, scroll handles the rest. Total < 800.
func _build_menu_page() -> void:
	_overlay_page = "menu"
	_clear_overlay_vbox()
	# 1. Title row.
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 16)
	var t1 := Label.new()
	t1.text = "❚❚ PAUSED"
	t1.add_theme_font_size_override("font_size", 56)
	t1.add_theme_color_override("font_color", COL_ACCENT)
	title_row.add_child(t1)
	if _game_name != "":
		var t2 := Label.new()
		t2.text = "— " + _game_name  # branding rule: clean names only
		t2.add_theme_font_size_override("font_size", 32)
		t2.add_theme_color_override("font_color", COL_DIM)
		title_row.add_child(t2)
	_overlay_vbox.add_child(title_row)
	# 2. Action row.
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	for spec in [["Resume", _on_resume, Color(0.0, 0.5, 0.3)],
			["Controls", _on_controls, Color(0.1, 0.3, 0.55)],
			["Restart Game", _on_restart, Color(0.5, 0.35, 0.1)],
			["Settings", _on_settings, Color(0.22, 0.24, 0.34)]]:
		var ab := _action_button(spec[0], spec[1], spec[2])
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(ab)
	_overlay_vbox.add_child(actions)
	# 3. Picker header: Prev/Next game + count.
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 16)
	header.add_child(_nav_button("◀ Prev", _on_prev))
	var cap := Label.new()
	cap.text = "JUMP TO A GAME · %d" % _nav_names.size()
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 28)
	cap.add_theme_color_override("font_color", COL_DIM)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(cap)
	header.add_child(_nav_button("Next ▶", _on_next))
	_overlay_vbox.add_child(header)
	# 4. Grid zone: scrollable 5-column card grid + hold-repeat scroll buttons.
	var zone := HBoxContainer.new()
	zone.add_theme_constant_override("separation", 12)
	zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _nav_names.size():
		grid.add_child(_game_card(i))
	scroll.add_child(grid)
	zone.add_child(scroll)
	_grid_scroll = scroll
	var scol := VBoxContainer.new()
	scol.alignment = BoxContainer.ALIGNMENT_CENTER
	scol.add_theme_constant_override("separation", 8)
	scol.add_child(_scroll_button("▲", -1))
	scol.add_child(_scroll_button("▼", 1))
	zone.add_child(scol)
	_overlay_vbox.add_child(zone)
	# 5. EXIT TO LAUNCHER: bottom, red, full-width, unmissable (wade's words).
	_overlay_vbox.add_child(_exit_button())


## One game card: 56x56 accent color chip + 24px name (the color IS the icon —
## no new assets, no key art). Current-game card: 4px accent border; pressing
## it resumes (least surprise — never relaunches the game you're in).
func _game_card(gi: int) -> Button:
	var nm := str(_nav_names[gi])
	var accent := Color(0.3, 0.6, 0.9)
	if gi < _nav_colors.size() and _nav_colors[gi] is Color:
		accent = _nav_colors[gi]
	var b := Button.new()
	b.custom_minimum_size = Vector2(196, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(0)
	if gi == _nav_index:
		sb.border_color = COL_ACCENT
		sb.set_border_width_all(4)
	else:
		sb.border_color = accent.darkened(0.35)
		sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = COL_ACCENT
	b.add_theme_stylebox_override("hover", hov)
	var pr := sb.duplicate() as StyleBoxFlat
	pr.bg_color = COL_ACCENT.darkened(0.2)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	var chip := ColorRect.new()
	chip.color = accent
	chip.custom_minimum_size = Vector2(56, 56)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(chip)
	var lbl := Label.new()
	lbl.text = nm
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.max_lines_visible = 2
	lbl.custom_minimum_size = Vector2(184, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lbl)
	b.add_child(vb)
	# Hover = accent bg + dark text (same visual language as launcher rows).
	b.mouse_entered.connect(
		func() -> void: lbl.add_theme_color_override("font_color", COL_DARK_TEXT))
	b.mouse_exited.connect(
		func() -> void: lbl.add_theme_color_override("font_color", Color.WHITE))
	if gi == _nav_index:
		b.pressed.connect(_on_resume)
	else:
		b.pressed.connect(_on_goto_game.bind(gi))
	return b


## Hold-to-repeat scroll button (launcher pattern): button_down/up (not
## pressed) — injected clicks are press+release in the same frame, so a tap
## is one step and a real hold repeats in _process.
func _scroll_button(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(72, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", COL_ACCENT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(0)
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = COL_ACCENT
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_color_override("font_hover_color", COL_DARK_TEXT)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.button_down.connect(_on_grid_scroll_press.bind(dir))
	b.button_up.connect(_on_grid_scroll_release)
	return b


func _on_grid_scroll_press(dir: int) -> void:
	_scroll_dir = dir
	_scroll_accum = 0.0
	_grid_scroll_step(dir)


func _on_grid_scroll_release() -> void:
	_scroll_dir = 0


func _grid_scroll_step(dir: int) -> void:
	if _grid_scroll == null or not is_instance_valid(_grid_scroll):
		return
	_grid_scroll.scroll_vertical += dir * 162  # card 150 + v-sep 12


func _process_scroll_repeat(delta: float) -> void:
	if _scroll_dir == 0 or not _paused:
		return
	if _grid_scroll == null or not is_instance_valid(_grid_scroll):
		_scroll_dir = 0
		return
	_scroll_accum += delta
	while _scroll_accum >= 0.12:
		_scroll_accum -= 0.12
		_grid_scroll_step(_scroll_dir)

## Big red full-width exit button, pinned to the bottom of the menu.
func _exit_button() -> Button:
	var b := Button.new()
	b.text = "EXIT TO LAUNCHER"
	b.custom_minimum_size = Vector2(0, 104)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.72, 0.12, 0.12)
	bsb.set_corner_radius_all(0)
	bsb.border_color = Color(1.0, 0.3, 0.3)
	bsb.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", bsb)
	var bhov := bsb.duplicate() as StyleBoxFlat
	bhov.bg_color = Color(0.9, 0.18, 0.18)
	b.add_theme_stylebox_override("hover", bhov)
	var bpr := bsb.duplicate() as StyleBoxFlat
	bpr.bg_color = Color(1.0, 0.25, 0.25)
	b.add_theme_stylebox_override("pressed", bpr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_quit)
	return b


## Action-row button: expand-fill, min height 88, 36px, flat zero-radius.
func _action_button(text: String, cb: Callable, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = color
	bsb.set_corner_radius_all(0)
	b.add_theme_stylebox_override("normal", bsb)
	var bhov := bsb.duplicate() as StyleBoxFlat
	bhov.bg_color = color.lightened(0.25)
	b.add_theme_stylebox_override("hover", bhov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


## Compact Prev/Next game button (200x64, 30px) — the hardware-verified
## v0.9.2 pattern, kept exactly per the UI spec.
func _nav_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.12, 0.28, 0.5)
	bsb.set_corner_radius_all(0)
	b.add_theme_stylebox_override("normal", bsb)
	var bhov := bsb.duplicate() as StyleBoxFlat
	bhov.bg_color = Color(0.2, 0.42, 0.72)
	b.add_theme_stylebox_override("hover", bhov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _on_prev() -> void:
	_switch_game(-1)


func _on_next() -> void:
	_switch_game(1)


## Route through the hub's switch path so autowiring, music, BugReporter
## session, PauseExit re-attach and telemetry run exactly as a launcher
## launch does. The hub wraps around at the ends.
func _switch_game(delta: int) -> void:
	var cb := _on_switch_cb
	if not cb.is_valid():
		return
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event("nav_press", {"game": _game_name, "delta": delta})
	_set_paused(false)
	detach()
	cb.call(delta)


## Direct jump from a grid card: same hub guarantees as _switch_game.
## Pressing the current game's card resumes instead (handled in _game_card).
func _on_goto_game(gi: int) -> void:
	var cb := _on_goto_cb
	if not cb.is_valid():
		return
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null and gi >= 0 and gi < _nav_names.size():
		gt.event("nav_press", {"game": _game_name, "delta": 0,
			"jump_to": str(_nav_names[gi])})
	_set_paused(false)
	detach()
	cb.call(gi)


func _clear_overlay_vbox() -> void:
	if _overlay_vbox == null:
		return
	for c in _overlay_vbox.get_children():
		_overlay_vbox.remove_child(c)
		c.queue_free()
	_grid_scroll = null
	_scroll_dir = 0
	_scroll_accum = 0.0


## Controls/legend page, shared by the pause menu and the intro flow.
func _show_controls_page(back_label: String, on_back: Callable) -> void:
	_overlay_page = "controls"
	_clear_overlay_vbox()
	# controller_skins.gd exposes class_name ControllerSkins, but loading by
	# path keeps this working even when the editor's global class cache is
	# stale (e.g. fresh clones).
	var skins_scr: GDScript = load("res://scripts/shared/controller_skins.gd")
	_overlay_vbox.add_child(skins_scr.legend_control(_legend_cfg, _legend_game))
	_overlay_vbox.add_child(_action_button(back_label, on_back, Color(0.0, 0.5, 0.3)))


func _on_controls() -> void:
	_show_controls_page("Back", _build_menu_page)


# ------------------------------------------------------------- settings ---

## v0.11.0 (wade's direct order): Settings page, one tap from the pause menu.
## Every option changes real behavior — audited, no placebo toggles:
##   INPUT = which pointer rigs are live (controllers / hands / auto)
##   GAZE DWELL = camera-dwell select time (0.8 / 1.2 / 1.8 s)
##   DOMINANT HAND = blade/buckler hand swap where handedness matters (duel)
##   TOOL TIPS = intro control legends on game start
##   GRAPHICS = Low/Medium/High/Ultra — render scale, MSAA, shadow atlas,
##     anisotropy, foveation, particle counts (GameSettings.apply_quality).
## Omitted by the no-placebo rule: thumbstick deadzone (zero games read the
## thumbstick), pointer smoothing (no consumer).
func _on_settings() -> void:
	_build_settings_page()


func _build_settings_page() -> void:
	_overlay_page = "settings"
	_clear_overlay_vbox()
	var ts := GameSettings.ui_text_scale()  # v0.11.0 Comfort A: 1.4x fonts
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(52 * ts))
	title.add_theme_color_override("font_color", COL_ACCENT)
	_overlay_vbox.add_child(title)
	var im := 0
	match GameSettings.input_method:
		"controllers":
			im = 0
		"hands":
			im = 1
		_:
			im = 2
	_overlay_vbox.add_child(_seg_row("INPUT",
		PackedStringArray(["Controllers", "Hands", "Auto"]), im, _on_setting_input))
	var gz := 1
	if GameSettings.gaze_dwell <= 0.9:
		gz = 0
	elif GameSettings.gaze_dwell >= 1.6:
		gz = 2
	_overlay_vbox.add_child(_seg_row("GAZE DWELL",
		PackedStringArray(["Fast", "Normal", "Slow"]), gz, _on_setting_gaze))
	_overlay_vbox.add_child(_seg_row("DOMINANT HAND",
		PackedStringArray(["Right", "Left"]),
		0 if GameSettings.dominant_hand == "right" else 1, _on_setting_hand))
	_overlay_vbox.add_child(_seg_row("TOOL TIPS",
		PackedStringArray(["On", "Off"]),
		0 if GameSettings.tooltips else 1, _on_setting_tooltips))
	_overlay_vbox.add_child(_seg_row("GRAPHICS",
		PackedStringArray(["Low", "Medium", "High", "Ultra"]),
		clampi(GameSettings.quality, 0, 3), _on_setting_graphics))
	# v0.11.0 Comfort rows (all real — see GameSettings consumers).
	_overlay_vbox.add_child(_seg_row("TEXT SIZE",
		PackedStringArray(["Normal", "Large"]),
		0 if GameSettings.text_size == "normal" else 1, _on_setting_textsize))
	_overlay_vbox.add_child(_seg_row("SEATED MODE",
		PackedStringArray(["Off", "On"]),
		1 if GameSettings.seated else 0, _on_setting_seated))
	_overlay_vbox.add_child(_seg_row("VIGNETTE",
		PackedStringArray(["Off", "Soft", "Strong"]),
		{"off": 0, "soft": 1, "strong": 2}.get(GameSettings.vignette, 1),
		_on_setting_vignette))
	_overlay_vbox.add_child(_seg_row("DIVE MOVE",
		PackedStringArray(["Paddle", "Glide"]),
		0 if GameSettings.move_style == "paddle" else 1, _on_setting_movestyle))
	_overlay_vbox.add_child(_seg_row("ONE-HAND DUEL",
		PackedStringArray(["Off", "On"]),
		1 if GameSettings.one_hand_duel else 0, _on_setting_onehand))
	var note := Label.new()
	note.text = "Resolution, MSAA and particles apply instantly.\nFoveation finishes applying on next launch."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", int(24 * ts))
	note.add_theme_color_override("font_color", COL_DIM)
	_overlay_vbox.add_child(note)
	var back := _action_button("Back", _build_menu_page, Color(0.0, 0.5, 0.3))
	_overlay_vbox.add_child(back)


## Segmented option row: right-aligned dim label + expand-fill option buttons.
## Selected = accent bg + dark text; the rest = flat dark.
func _seg_row(label_text: String, labels: PackedStringArray, selected: int,
		cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(300, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.add_theme_font_size_override("font_size", int(30 * GameSettings.ui_text_scale()))
	lab.add_theme_color_override("font_color", COL_DIM)
	row.add_child(lab)
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.custom_minimum_size = Vector2(0, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", int(28 * GameSettings.ui_text_scale()))
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(0)
		if i == selected:
			sb.bg_color = COL_ACCENT
			b.add_theme_color_override("font_color", COL_DARK_TEXT)
		else:
			sb.bg_color = Color(0.10, 0.14, 0.22)
			b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", sb)
		var hov := sb.duplicate() as StyleBoxFlat
		hov.bg_color = COL_ACCENT.darkened(0.15) if i != selected else COL_ACCENT
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
	return row


func _on_setting_input(i: int) -> void:
	GameSettings.input_method = ["controllers", "hands", "auto"][clampi(i, 0, 2)]
	GameSettings.save()
	_setting_changed("input_method", GameSettings.input_method)
	_direct.source_filter = GameSettings.input_method
	_update_pointer_visibility()
	Haptics.tick()
	_build_settings_page()


func _on_setting_gaze(i: int) -> void:
	GameSettings.gaze_dwell = [0.8, 1.2, 1.8][clampi(i, 0, 2)]
	GameSettings.save()
	_setting_changed("gaze_dwell", GameSettings.gaze_dwell)
	Haptics.tick()
	_build_settings_page()


func _on_setting_hand(i: int) -> void:
	GameSettings.dominant_hand = ["right", "left"][clampi(i, 0, 1)]
	GameSettings.save()
	_setting_changed("dominant_hand", GameSettings.dominant_hand)
	Haptics.tick()
	_build_settings_page()


func _on_setting_tooltips(i: int) -> void:
	GameSettings.tooltips = (i == 0)
	GameSettings.save()
	_setting_changed("tooltips", GameSettings.tooltips)
	Haptics.tick()
	_build_settings_page()


func _on_setting_graphics(i: int) -> void:
	GameSettings.apply_quality(i, get_viewport())
	_setting_changed("quality", GameSettings.QUALITY_NAMES[clampi(i, 0, 3)])
	Haptics.confirm()
	_build_settings_page()


func _on_setting_textsize(i: int) -> void:
	GameSettings.text_size = ["normal", "large"][clampi(i, 0, 1)]
	GameSettings.save()
	_setting_changed("text_size", GameSettings.text_size)
	Haptics.tick()
	_build_settings_page()


func _on_setting_seated(i: int) -> void:
	GameSettings.seated = (i == 1)
	GameSettings.save()
	_setting_changed("seated", GameSettings.seated)
	Haptics.tick()
	_build_settings_page()


func _on_setting_vignette(i: int) -> void:
	GameSettings.vignette = ["off", "soft", "strong"][clampi(i, 0, 2)]
	GameSettings.save()
	_setting_changed("vignette", GameSettings.vignette)
	Haptics.tick()
	_build_settings_page()


func _on_setting_movestyle(i: int) -> void:
	GameSettings.move_style = ["paddle", "glide"][clampi(i, 0, 1)]
	GameSettings.save()
	_setting_changed("move_style", GameSettings.move_style)
	Haptics.tick()
	_build_settings_page()


func _on_setting_onehand(i: int) -> void:
	GameSettings.one_hand_duel = (i == 1)
	GameSettings.save()
	_setting_changed("one_hand_duel", GameSettings.one_hand_duel)
	Haptics.tick()
	_build_settings_page()


## v0.11.0 Comfort: log comfort-setting changes so the digest sees adoption.
func _setting_changed(key: String, value: Variant) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null and gt.has_method("event"):
		gt.event("settings_changed", {"key": key, "value": value})

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
	_direct_set_target(_pause_vp, _pause_quad)
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
	_direct_set_target(_exit_vp, _exit_quad)
	_update_pointer_visibility()
	Haptics.tick()
	_make_pointers(_pause_vp, _pause_quad, _pause_pointers)


## Switch the DirectUIInput fallback target (exit quad <-> pause quad).
func _direct_set_target(vp: SubViewport, quad: MeshInstance3D) -> void:
	_direct_vp = vp
	if _direct != null and is_instance_valid(_direct):
		_direct.set_target(vp, quad)


func _direct_moved(pos: Vector2) -> void:
	if _direct_vp != null and is_instance_valid(_direct_vp):
		_on_pointer_moved(pos, _direct_vp)


func _direct_clicked(pos: Vector2) -> void:
	if _direct_vp != null and is_instance_valid(_direct_vp):
		_on_pointer_clicked(pos, _direct_vp, null)


## One XRUIPointer per input source, wired to inject clicks/motion into the
## given viewport. The v0.8.0 rigs — laser + pinch + (below) gaze.
func _make_pointers(vp: SubViewport, quad: MeshInstance3D, arr: Array[XRUIPointer]) -> void:
	if not arr.is_empty():
		return
	for ctl in _controllers:
		var p := XRUIPointer.new()
		p.controller = ctl
		p.setup(vp, quad, _xr_origin)
		p.xr_clicked.connect(_on_pointer_clicked.bind(vp, p))
		p.xr_moved.connect(_on_pointer_moved.bind(vp))
		p.visible = false
		add_child(p)
		arr.append(p)
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.hand_side = side
		hp.setup(vp, quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked.bind(vp, hp))
		hp.xr_moved.connect(_on_pointer_moved.bind(vp))
		hp.visible = false
		add_child(hp)
		arr.append(hp)


## v0.9.2: first click in a game session records the input method for
## telemetry (hands vs controllers vs gaze). First method wins per session.
func _note_input_from_pointer(p: XRUIPointer) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt == null:
		return
	if p.controller != null:
		gt.note_input_method("controllers")
	elif p.hand_side != 0:
		gt.note_input_method("hands")


func _on_pointer_clicked(viewport_pos: Vector2, vp: SubViewport, p: XRUIPointer = null) -> void:
	if p != null:
		_note_input_from_pointer(p)
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
	# Dual-path dedupe (XRUIPointer signals + DirectUIInput fallback share
	# this funnel): 120ms / 8px window, same as the hub.
	var now := Time.get_ticks_msec()
	if now - _last_click_msec < 120 and viewport_pos.distance_to(_last_click_pos) < 8.0:
		return
	_last_click_msec = now
	_last_click_pos = viewport_pos
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


## Pin the exit button in view, ~1.1m out, at the per-game corner
## (`static var exit_button_corner`: top_right/top_left/bottom_right/
## bottom_left). top_level so it never inherits game transforms.
## DELIBERATE EXCEPTION to the static-panel rule (wade 2026-10-12): this
## 0.15m affordance stays head-locked because (1) the menu button is
## controller-only — hand/pinch users need an on-screen affordance to reach
## pause at all; (2) a static button is useless the moment the user turns
## around mid-game (Neon Duel has the player spinning).
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
	var sx := 0.42
	var sy := 0.30
	match _exit_corner:
		"top_left":
			sx = -0.42
		"bottom_right":
			sy = -0.30
		"bottom_left":
			sx = -0.42
			sy = -0.30
	_exit_root.global_position = t.origin + fwd * 1.1 + right * sx + up * sy
	# Face the camera.
	var to_cam := (t.origin - _exit_root.global_position).normalized()
	_exit_root.global_transform = Transform3D(Basis.looking_at(to_cam), _exit_root.global_position)


## STATIC PLACEMENT CONTRACT (wade 2026-10-12, SHIP-BLOCKER): this runs ONCE
## per pause-open (call sites: _set_paused(true) and show_controls_intro),
## centered in front of the player's CURRENT head direction at PAUSE_DIST.
## Then the panel NEVER moves — no Timer, no _process code, no off-axis
## check touches _pause_root. Ever. (The v0.9.3 continuous-recenter was
## killed by direct order: wade finds a following panel worse than the
## original face-full-panel defect.) Close (resume) hides it; the next open
## re-anchors to the new head direction, then static again.
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
	# v0.11.0 Comfort B: seated players get the panel at 1.15m eye height.
	if GameSettings.seated:
		target.y = GameSettings.panel_eye_height()
	else:
		target.y = clampf(cp.y, 1.1, 1.75)
	_pause_root.global_position = target
	var to_user := cp - target
	to_user.y = 0.0
	if to_user.length() > 0.05:
		_pause_root.global_rotation = Vector3(0.0, atan2(to_user.x, to_user.z), 0.0)


# ------------------------------------------------------------ gaze fallback ---

## Camera-center gaze with GameSettings.gaze_dwell dwell — same fallback
## contract as the hub. Runs only when no laser/pinch pointer of the active
## set is live.
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
		if _gaze_dwell >= GameSettings.gaze_dwell:
			_gaze_dwell = 0.0
			# v0.9.2: gaze dwell click counts as the gaze input method.
			var gt := get_node_or_null("/root/GameplayTelemetry")
			if gt != null:
				gt.note_input_method("gaze")
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


## v0.11.0: hold-to-pause fill ring drawn over the ❚❚ button during a
## combat-profile menu-button hold. progress 0..1 over HOLD_TO_PAUSE_MSEC.
class HoldRing extends Control:
	var progress := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.40
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 12.0, true)
		var a := TAU * clampf(progress, 0.0, 1.0)
		if a > 0.01:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + a, 64,
				Color(1.0, 0.85, 0.2), 12.0, true)
