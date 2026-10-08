## MoodLUT.gd - passthrough color grading autoload for NEXUS ARCADE
## (autoload: MoodLUT). v0.9.0 shared-systems build (AI_API_ROADMAP #6).
##
## Per-game color grading of the real-world passthrough feed via
## XR_META_passthrough_color_lut (verified against the 5.1.0 plugin binary):
##   OpenXRMetaPassthroughColorLut.create(image, channels) -> LUT resource
##   OpenXRFbPassthroughExtension.set_color_lut(lut) -> bool
##   OpenXRFbPassthroughExtension.get_max_color_lut_resolution() -> int
##
## Moods: "natural" (default identity), "haunted_green", "deep_teal",
## "sunset_gold". apply_mood(mood, fade) crossfades manually by pushing
## intermediate LUTs (~8 steps over the fade) — deterministic, no reliance
## on runtime interpolation semantics.
##
## The auto-wirer (hub.gd) calls apply_for_game(stem, tab): THEMES tab gets
## haunted_green, deep_dive/holo-aquarium get deep_teal, everything else
## natural. Games can call apply_mood() directly for their own mood.
##
## Headless-safe: every plugin call is ClassDB/has_method-guarded; with no
## passthrough extension present this is a silent no-op.
## NOTE: LUT layout (w=res*res,h=res; pixel (r+b*res, g)) and the visual
## result MUST be validated on Quest 3 — cannot verify headless.
extends Node

const LUT_RES := 16  # power of 2, well under typical max (32)
const FADE_STEPS := 8

const MOODS := ["natural", "haunted_green", "deep_teal", "sunset_gold"]

## Scene stems that get the deep-teal underwater grade.
const TEAL_GAMES := ["deep_dive", "holo-aquarium"]

var _current := "natural"
var _lut_cache: Dictionary = {}
var _fading := false


## Crossfade the passthrough feed to `mood` over `fade` seconds.
func apply_mood(mood: String, fade: float = 1.2) -> void:
	if not MOODS.has(mood):
		push_warning("MoodLUT: unknown mood '" + mood + "'")
		return
	if mood == _current and not _fading:
		return
	_fade_to(mood, maxf(fade, 0.0))


## Mood pick for a launched game. Called by the hub auto-wirer.
func apply_for_game(scene_stem: String, tab: int) -> void:
	var mood := "natural"
	if tab == 3:
		mood = "haunted_green"
	elif scene_stem in TEAL_GAMES:
		mood = "deep_teal"
	apply_mood(mood)


## Restore the neutral grade (called on return to hub).
func reset() -> void:
	apply_mood("natural", 0.8)


func current_mood() -> String:
	return _current


# ------------------------------------------------------------------ build ---

func _fade_to(target: String, fade: float) -> void:
	_fading = true
	var from_img := _lut_image(_current)
	var to_img := _lut_image(target)
	if from_img == null or to_img == null:
		# Plugin classes missing (headless/desktop): just track the mood.
		_current = target
		_fading = false
		return
	var steps := FADE_STEPS if fade > 0.05 else 1
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var blended := _blend_images(from_img, to_img, t)
		if not _push_lut(blended):
			break
		if fade > 0.05 and i < steps:
			await (Engine.get_main_loop() as SceneTree).create_timer(fade / steps).timeout
	_current = target
	_fading = false


## Build (and cache) the RGB LUT image for a mood. Layout: width=res*res,
## height=res; the cell for input (r,g,b) sits at pixel (r + b*res, g).
func _lut_image(mood: String) -> Image:
	if _lut_cache.has(mood):
		return _lut_cache[mood]
	if not ClassDB.class_exists("OpenXRMetaPassthroughColorLut"):
		return null
	var res := LUT_RES
	var img := Image.create(res * res, res, false, Image.FORMAT_RGB8)
	for b in res:
		for g in res:
			for r in res:
				var col := _grade(mood, Color(r / float(res - 1), g / float(res - 1), b / float(res - 1)))
				img.set_pixel(r + b * res, g, col)
	_lut_cache[mood] = img
	return img


## Per-mood color transform. Tasteful grades only — never degrade readability.
func _grade(mood: String, c: Color) -> Color:
	match mood:
		"haunted_green":
			return Color(
				clampf(c.r * 0.55 + 0.02, 0.0, 1.0),
				clampf(c.g * 1.12 + 0.03, 0.0, 1.0),
				clampf(c.b * 0.62 + 0.02, 0.0, 1.0))
		"deep_teal":
			var l := 0.35 * c.r + 0.5 * c.g + 0.15 * c.b
			return Color(
				clampf(c.r * 0.52 + l * 0.08, 0.0, 1.0),
				clampf(c.g * 0.94 + l * 0.10, 0.0, 1.0),
				clampf(c.b * 1.08 + l * 0.06, 0.0, 1.0))
		"sunset_gold":
			return Color(
				clampf(c.r * 1.10 + 0.02, 0.0, 1.0),
				clampf(c.g * 0.94 + 0.01, 0.0, 1.0),
				clampf(c.b * 0.68, 0.0, 1.0))
		_:
			return c


func _blend_images(a: Image, b: Image, t: float) -> Image:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var res := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			res.set_pixel(x, y, a.get_pixel(x, y).lerp(b.get_pixel(x, y), t))
	return res


## Create the LUT resource and push it through the passthrough extension.
## Returns false when the plugin path is unavailable (headless/desktop).
func _push_lut(img: Image) -> bool:
	if not ClassDB.class_exists("OpenXRMetaPassthroughColorLut"):
		return false
	# The binary exposes a static create(image, channels) factory
	# (COLOR_LUT_CHANNELS_RGB = 0).
	var lut: RefCounted = null
	if ClassDB.class_has_method("OpenXRMetaPassthroughColorLut", "create"):
		lut = ClassDB.class_call_static("OpenXRMetaPassthroughColorLut", "create", img, 0) as RefCounted
	if lut == null:
		return false
	var ext := _passthrough_ext()
	if ext == null or not ext.has_method("set_color_lut"):
		return false
	var ok: Variant = ext.call("set_color_lut", lut)
	return bool(ok)


## Lazily create (or find) the OpenXRFbPassthroughExtension node.
func _passthrough_ext() -> Node:
	if not ClassDB.class_exists("OpenXRFbPassthroughExtension"):
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var found := tree.root.find_children("*", "OpenXRFbPassthroughExtension", true, false)
	if not found.is_empty():
		return found[0]
	var ext: Object = ClassDB.instantiate("OpenXRFbPassthroughExtension")
	if ext is Node:
		(ext as Node).name = "MoodLUTPassthroughExt"
		tree.root.add_child.call_deferred(ext as Node)
		return ext as Node
	return null
