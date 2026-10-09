## ControllerSkins.gd - styled controller render models + button legends.
## v0.9.0 permanent feature (wade). Helper (class_name ControllerSkins).
##
## API verified against the real 5.1.0 plugin binary (never assumed):
##   OpenXRFbRenderModel (node): render_model_type property /
##     set_render_model_type(int) / get_render_model_type(),
##     has_render_model_node(), get_render_model_node(),
##     signal openxr_fb_render_model_loaded.
##   Enum: MODEL_CONTROLLER_LEFT / MODEL_CONTROLLER_RIGHT (resolved via
##     ClassDB at runtime; falls back to 0/1 when the plugin is absent).
##   Requires xr/openxr/extensions/meta/render_model=true (project.godot).
##
## What it does, per controller-required game (auto-wired, opt-out via
## no_auto_wire):
##   1. Instances the SYSTEM render model 1:1 over each real controller and
##      parents a cheap game-styled accessory to it (<10k tris, shared
##      materials): wand / blaster / wheel / brush / racket / sword / rod /
##      mallet / torch.
##   2. Graceful fallback: when the system model is unavailable, a clean
##      stylized procedural controller shows instead (deliberate shapes,
##      not a blob).
##   3. Data-driven config: games set `static var controller_config := {...}`
##      (partial dict merged over heuristic defaults) — never hardcoded.
##   4. Button legend content for the intro flow + pause-menu Controls page.
##
## Config schema:
##   {"uses_controllers": true, "skin": "auto",
##    "buttons": {"trigger": "Fire", "grip": "Reload",
##                "thumbstick": "Move", "a": "", "b": "", "x": "", "y": "",
##                "menu": "Pause"}}
## "skin": "auto" picks from the heuristic map below; "none" = render model
## only. "uses_controllers": false = hand-only game, skipped silently.
## NOTE: system-model visuals need Quest 3 device validation.
class_name ControllerSkins
extends RefCounted

## Accessory ids.
const SKINS := ["none", "wand", "blaster", "wheel", "brush", "racket",
	"sword", "rod", "mallet", "torch", "putter"]

## Heuristic accessory per game stem (games override via controller_config).
const SKIN_FOR_STEM := {
	"spell-duel": "wand", "wizard_academy": "wand",
	"laser-tag-ar": "blaster", "sky-defender": "blaster",
	"ar-defender": "blaster", "hw_hayride_shooter": "blaster",
	"hw_zombie_defense": "blaster", "hw_goblin_archery": "blaster",
	"drone-racer": "wheel", "room-racer": "wheel",
	"light-painter": "brush", "graffiti-wall": "brush", "sketch_3d": "brush",
	"beat-blades": "sword", "duel": "sword",
	"ar-fishing": "rod",
	"hw_haunted_maze": "torch",
}

## Heuristic button legends for well-known games (merged over generics).
const BUTTONS_FOR_STEM := {
	"laser-tag-ar": {"trigger": "Fire", "grip": "Reload", "thumbstick": "Move"},
	"spell-duel": {"trigger": "Cast spell", "grip": "Charge", "thumbstick": "Move"},
	"wizard_academy": {"trigger": "Cast", "grip": "Grab potion", "thumbstick": "Move"},
	"ar-fishing": {"trigger": "Cast / Reel", "grip": "Grab", "thumbstick": "Move"},
	"beat-blades": {"trigger": "Dash", "grip": "Grab", "thumbstick": "Move"},
	"duel": {"trigger": "Strike", "grip": "Block", "thumbstick": "Step"},
	"drone-racer": {"trigger": "Boost", "grip": "Brake", "thumbstick": "Steer"},
	"room-racer": {"trigger": "Accelerate", "grip": "Brake", "thumbstick": "Steer"},
	"light-painter": {"trigger": "Paint", "grip": "New stroke", "thumbstick": "Color"},
	"sky-defender": {"trigger": "Shoot", "grip": "Shield", "thumbstick": "Move"},
}

const GENERIC_BUTTONS := {
	"trigger": "Use", "grip": "Grab", "thumbstick": "Move",
	"a": "", "b": "", "x": "", "y": "", "menu": "Pause",
}

const BUTTON_ORDER := ["trigger", "grip", "thumbstick", "a", "b", "x", "y", "menu"]
const BUTTON_LABELS := {
	"trigger": "TRIGGER", "grip": "GRIP", "thumbstick": "THUMBSTICK",
	"a": "A", "b": "B", "x": "X", "y": "Y", "menu": "MENU",
}

static var _applied: Array[Node] = []  # nodes added to controllers (cleared per game)


## Read + merge the effective config for a game node.
static func config_for(game: Node, scene_stem: String) -> Dictionary:
	var cfg := {
		"uses_controllers": true,
		"skin": "auto",
		"buttons": GENERIC_BUTTONS.duplicate(),
	}
	var stem_buttons: Dictionary = BUTTONS_FOR_STEM.get(scene_stem, {})
	for k in stem_buttons:
		(cfg["buttons"] as Dictionary)[k] = stem_buttons[k]
	if game != null:
		var scr := game.get_script() as GDScript
		if scr != null:
			var custom: Variant = scr.get("controller_config")
			if custom is Dictionary:
				for k in (custom as Dictionary):
					if k == "buttons" and (custom as Dictionary)["buttons"] is Dictionary:
						for bk in ((custom as Dictionary)["buttons"] as Dictionary):
							(cfg["buttons"] as Dictionary)[bk] = \
								((custom as Dictionary)["buttons"] as Dictionary)[bk]
					else:
						cfg[k] = (custom as Dictionary)[k]
	if str(cfg.get("skin", "auto")) == "auto":
		cfg["skin"] = str(SKIN_FOR_STEM.get(scene_stem, "none"))
	return cfg


## Apply skins to both controllers for this game. Clears previous game's
## skins first. No-op (after clearing) when uses_controllers == false.
static func apply(game: Node, cfg: Dictionary) -> void:
	clear()
	if not bool(cfg.get("uses_controllers", true)):
		return
	var ctrls := _find_controllers()
	if ctrls.is_empty():
		return
	var skin := str(cfg.get("skin", "none"))
	if not SKINS.has(skin):
		skin = "none"
	for entry in ctrls:
		_apply_to_controller(entry["node"], entry["left"], skin)


## Remove all skin nodes (call on game exit / before re-apply).
static func clear() -> void:
	for n in _applied:
		if is_instance_valid(n):
			n.queue_free()
	_applied.clear()


# ------------------------------------------------------------------ attach ---

## Find the persistent XR controllers: Array of {"node": XRController3D,
## "left": bool}.
static func _find_controllers() -> Array:
	var out := []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return out
	var origins := tree.root.find_children("*", "XROrigin3D", true, false)
	if origins.is_empty():
		return out
	var origin := origins[0] as Node3D
	for spec in [["LeftController", true], ["RightController", false]]:
		var ctl := origin.get_node_or_null(spec[0]) as XRController3D
		if ctl != null:
			out.append({"node": ctl, "left": spec[1]})
	return out


static func _apply_to_controller(ctl: XRController3D, left: bool, skin: String) -> void:
	# Fallback procedural model first (visible until the system model loads,
	# or permanently when the plugin is absent).
	var fallback := _fallback_controller()
	fallback.name = "SkinFallback"
	ctl.add_child(fallback)
	_applied.append(fallback)
	# Accessory goes on a mount node; reparented under the system model when
	# it loads so everything tracks 1:1.
	var mount := Node3D.new()
	mount.name = "SkinMount"
	if skin != "none":
		var acc := _build_accessory(skin)
		if acc != null:
			mount.add_child(acc)
	ctl.add_child(mount)
	_applied.append(mount)
	if not ClassDB.class_exists("OpenXRFbRenderModel"):
		return  # headless/desktop: fallback stays
	var rm: Object = ClassDB.instantiate("OpenXRFbRenderModel")
	if not (rm is Node):
		return
	(rm as Node).name = "SkinRenderModel"
	ctl.add_child(rm)
	_applied.append(rm as Node)
	var mtype := _model_type(left)
	if rm.has_method("set_render_model_type"):
		rm.call("set_render_model_type", mtype)
	elif (rm as Node).has_method("set"):
		(rm as Node).set("render_model_type", mtype)
	if (rm as Node).has_signal("openxr_fb_render_model_loaded"):
		(rm as Node).connect("openxr_fb_render_model_loaded",
			_on_model_loaded.bind(rm, mount, fallback))
	else:
		# No load signal (older plugin): try once next frame.
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.process_frame.connect(_on_model_loaded.bind(rm, mount, fallback),
				CONNECT_ONE_SHOT)


static func _on_model_loaded(rm: Node, mount: Node3D, fallback: Node3D) -> void:
	if not is_instance_valid(rm) or not is_instance_valid(mount):
		return
	var has_it := true
	if rm.has_method("has_render_model_node"):
		has_it = bool(rm.call("has_render_model_node"))
	if not has_it:
		return  # system model unavailable: keep the fallback
	if is_instance_valid(fallback):
		fallback.visible = false
	var model_node: Node3D = null
	if rm.has_method("get_render_model_node"):
		model_node = rm.call("get_render_model_node") as Node3D
	if model_node != null and is_instance_valid(model_node):
		# Reparent the accessory mount under the system model: 1:1 tracking.
		if mount.get_parent() != null:
			mount.get_parent().remove_child(mount)
		model_node.add_child(mount)
		mount.transform = Transform3D.IDENTITY


static func _model_type(left: bool) -> int:
	var cname := "MODEL_CONTROLLER_LEFT" if left else "MODEL_CONTROLLER_RIGHT"
	if ClassDB.class_exists("OpenXRFbRenderModel"):
		return ClassDB.class_get_integer_constant("OpenXRFbRenderModel", cname)
	return 0 if left else 1


# ------------------------------------------------------------------ legend ---

## Build the legend Control for the intro flow / Controls page.
## Returns a VBoxContainer with one row per mapped button.
static func legend_control(cfg: Dictionary, game_name: String = "") -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "CONTROLS" if game_name == "" else "CONTROLS — " + game_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	vbox.add_child(title)
	var skin := Label.new()
	skin.text = "Grip style: " + str(cfg.get("skin", "none"))
	skin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skin.add_theme_font_size_override("font_size", 24)
	skin.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	vbox.add_child(skin)
	var buttons: Dictionary = cfg.get("buttons", {})
	for key in BUTTON_ORDER:
		var action := str(buttons.get(key, ""))
		if action == "":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var bl := Label.new()
		bl.text = BUTTON_LABELS.get(key, key.to_upper())
		bl.add_theme_font_size_override("font_size", 30)
		bl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		bl.custom_minimum_size = Vector2(220, 0)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(bl)
		var al := Label.new()
		al.text = action
		al.add_theme_font_size_override("font_size", 30)
		al.add_theme_color_override("font_color", Color.WHITE)
		al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(al)
		vbox.add_child(row)
	var foot := Label.new()
	foot.text = "Menu button pauses anytime"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 24)
	foot.add_theme_color_override("font_color", Color(0.65, 0.72, 0.9))
	vbox.add_child(foot)
	return vbox


# --------------------------------------------------------------- accessories ---

static var _mat_grip: StandardMaterial3D = null
static var _mat_accent: StandardMaterial3D = null
static var _mat_dark: StandardMaterial3D = null


static func _mats() -> void:
	if _mat_grip != null:
		return
	_mat_grip = GraphicsPolish.pbr(Color(0.13, 0.13, 0.16), 0.0, 0.8)
	_mat_dark = GraphicsPolish.pbr(Color(0.08, 0.09, 0.12), 0.2, 0.5)
	_mat_accent = GraphicsPolish.glow(Color(0.35, 0.9, 1.0), 1.8)


static func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	_mats()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func _cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 10
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 8
	return s


static func _torus(major: float, minor: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = major - minor
	t.outer_radius = major + minor
	t.rings = 12
	t.ring_segments = 6
	return t


## Build the accessory for `skin` id. All < 1500 tris (budget: <10k).
static func _build_accessory(skin: String) -> Node3D:
	_mats()
	var root := Node3D.new()
	root.name = "Accessory_" + skin
	match skin:
		"wand":
			var shaft := _part(_cyl(0.008, 0.016, 0.28), _mat_grip, Vector3(0, 0.02, -0.16))
			shaft.rotation_degrees.x = -12
			root.add_child(shaft)
			var tip := _part(_sph(0.02), _mat_accent, Vector3(0, 0.055, -0.30))
			root.add_child(tip)
			var ring := _part(_torus(0.03, 0.006), _mat_accent, Vector3(0, 0.035, -0.26))
			root.add_child(ring)
		"blaster":
			root.add_child(_part(_box(Vector3(0.05, 0.07, 0.16)), _mat_dark, Vector3(0, 0.03, -0.10)))
			var barrel := _part(_cyl(0.013, 0.013, 0.17), _mat_grip, Vector3(0, 0.045, -0.24))
			barrel.rotation_degrees.x = 90
			root.add_child(barrel)
			root.add_child(_part(_box(Vector3(0.012, 0.02, 0.012)), _mat_accent, Vector3(0, 0.085, -0.06)))
		"wheel":
			root.add_child(_part(_box(Vector3(0.16, 0.03, 0.03)), _mat_grip, Vector3(0, 0.02, -0.12)))
			for sx in [-1.0, 1.0]:
				var grip := _part(_torus(0.035, 0.013), _mat_dark, Vector3(sx * 0.095, 0.02, -0.12))
				grip.rotation_degrees.y = 90
				root.add_child(grip)
			root.add_child(_part(_sph(0.016), _mat_accent, Vector3(0, 0.02, -0.12)))
		"brush":
			var handle := _part(_cyl(0.013, 0.016, 0.14), _mat_grip, Vector3(0, 0.03, -0.08))
			handle.rotation_degrees.x = 78
			root.add_child(handle)
			var tip := _part(_cyl(0.004, 0.02, 0.09), _mat_accent, Vector3(0, 0.075, -0.155))
			tip.rotation_degrees.x = 78
			root.add_child(tip)
		"racket":
			root.add_child(_part(_box(Vector3(0.025, 0.025, 0.14)), _mat_grip, Vector3(0, 0.0, -0.10)))
			var head := _part(_torus(0.075, 0.011), _mat_dark, Vector3(0, 0.0, -0.25))
			root.add_child(head)
			var face := MeshInstance3D.new()
			face.mesh = _cyl(0.068, 0.068, 0.004)
			# Own material instance: the shared accent must stay opaque.
			var fmat := (_mat_accent.duplicate() as StandardMaterial3D)
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fmat.albedo_color.a = 0.35
			face.material_override = fmat
			face.position = Vector3(0, 0.0, -0.25)
			face.rotation_degrees.x = 90
			root.add_child(face)
		"sword":
			root.add_child(_part(_cyl(0.014, 0.017, 0.11), _mat_grip, Vector3(0, 0.02, -0.03)))
			root.add_child(_part(_box(Vector3(0.09, 0.015, 0.03)), _mat_dark, Vector3(0, 0.02, -0.10)))
			var blade := _part(_box(Vector3(0.022, 0.008, 0.36)), _mat_accent, Vector3(0, 0.02, -0.30))
			root.add_child(blade)
		"rod":
			var rod := _part(_cyl(0.006, 0.011, 0.5), _mat_grip, Vector3(0, 0.16, -0.28))
			rod.rotation_degrees.x = -32
			root.add_child(rod)
			var reel := _part(_torus(0.028, 0.01), _mat_dark, Vector3(0, -0.01, -0.10))
			root.add_child(reel)
			root.add_child(_part(_sph(0.012), _mat_accent, Vector3(0, 0.30, -0.47)))
		"mallet":
			var handle := _part(_cyl(0.013, 0.015, 0.2), _mat_grip, Vector3(0, 0.06, -0.10))
			handle.rotation_degrees.x = 70
			root.add_child(handle)
			var head := _part(_cyl(0.045, 0.045, 0.09), _mat_dark, Vector3(0, 0.12, -0.17))
			head.rotation_degrees.z = 90
			root.add_child(head)
			root.add_child(_part(_cyl(0.046, 0.046, 0.012), _mat_accent, Vector3(0.045, 0.12, -0.17)))
		"putter":
			# NEXUS GREENS hero putter (Blender custom, baked PBR).
			# GLB local: head at y~0.03, grip top at y~1.1.
			# Mount: grip at controller origin, head forward-down.
			var putter_glb: PackedScene = load("res://assets/minigolf/putter.glb")
			if putter_glb != null:
				var club: Node3D = putter_glb.instantiate()
				club.rotation_degrees = Vector3(54, 0, 0)
				# Grip (0,1.1,0) rotated -> (0, 0.65, 0.89); shift to origin.
				club.position = Vector3(0, -0.65, -0.89)
				root.add_child(club)
				# Head marker for strike detection (accessory space).
				var head_marker := Marker3D.new()
				head_marker.name = "ClubHead"
				head_marker.position = Vector3(0, -0.63, -0.87)
				root.add_child(head_marker)
			else:
				# Fallback: procedural putter if the GLB is missing.
				var p_shaft := _part(_cyl(0.011, 0.011, 0.8), _mat_grip, Vector3(0, -0.3, -0.35))
				p_shaft.rotation_degrees.x = 54
				root.add_child(p_shaft)
				root.add_child(_part(_box(Vector3(0.1, 0.05, 0.04)), _mat_dark, Vector3(0, -0.63, -0.87)))
		"torch":
			root.add_child(_part(_cyl(0.014, 0.017, 0.16), _mat_grip, Vector3(0, 0.05, -0.08)))
			root.add_child(_part(_cyl(0.035, 0.02, 0.05), _mat_dark, Vector3(0, 0.14, -0.08)))
			root.add_child(_part(_sph(0.028), _mat_accent, Vector3(0, 0.19, -0.08)))
	return root


## Clean stylized fallback controller (~500 tris): body, trigger wedge,
## thumbstick, two face buttons. Deliberate shapes, not a blob.
static func _fallback_controller() -> Node3D:
	_mats()
	var root := Node3D.new()
	root.name = "FallbackController"
	root.add_child(_part(_box(Vector3(0.05, 0.055, 0.115)), _mat_dark, Vector3(0, 0.01, -0.02)))
	var trig := _part(_box(Vector3(0.02, 0.035, 0.02)), _mat_grip, Vector3(0, -0.015, -0.055))
	trig.rotation_degrees.x = 18
	root.add_child(trig)
	root.add_child(_part(_cyl(0.016, 0.02, 0.014), _mat_grip, Vector3(0, 0.045, -0.03)))
	for i in 2:
		var btn := _part(_cyl(0.009, 0.009, 0.008), _mat_accent, Vector3(-0.014 + 0.028 * i, 0.042, -0.062))
		root.add_child(btn)
	var ring := _part(_torus(0.032, 0.007), _mat_dark, Vector3(0, 0.02, -0.075))
	ring.rotation_degrees.x = 90
	root.add_child(ring)
	return root
