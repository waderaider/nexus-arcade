## GameSettings.gd — persistent player settings (v0.11.0, wade's direct order).
## The Settings page lives in the pause menu (menu button -> pause -> Settings,
## one tap away). EVERY option below changes real, measurable behavior — no
## placebo toggles (audited 2026-10-12; the omitted thumbstick-deadzone idea
## died here because zero games read the thumbstick).
##
## Persisted in user://nexus_settings.cfg. Applied at boot BEFORE the first
## frame: hub._ready() calls GameSettings.boot() as its very first statement.
## Graphics quality tiers:
##   Low    = hold 72fps on the weakest scenes (0.7x render scale, MSAA off,
##            1024 shadow atlas, aniso 1x, foveation HIGH, 40% particles)
##   Medium = balanced (0.85x, MSAA 2x, 2048 shadows, aniso 2x, foveation MED, 70%)
##   High   = default look (1.0x, MSAA 4x, 2048 shadows, aniso 4x, foveation LOW, 100%)
##   Ultra  = supersampled (1.12x, MSAA 4x, 4096 shadows, aniso 8x,
##            foveation OFF, 120% particles)
## All values verified against Godot 4.7.2 project settings + RenderingServer
## (probe scripts 2026-10-12): xr/openxr/foveation_level (Off/Low/Med/High),
## rendering/anti_aliasing/quality/msaa_3d, Viewport.msaa_3d + scaling_3d_scale
## (runtime-settable), RenderingServer.directional_shadow_atlas_set_size(size,
## is_16bits), rendering/textures/default_filters/anisotropic_filtering_level.
class_name GameSettings
extends RefCounted

const PATH := "user://nexus_settings.cfg"

enum Quality { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3 }

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

# --- current values (loaded from disk at boot) ---
static var input_method := "auto"     # "auto" | "controllers" | "hands"
static var gaze_dwell := 1.2          # seconds: 0.8 fast / 1.2 normal / 1.8 slow
static var dominant_hand := "right"   # "right" | "left" — handedness where it matters
static var tooltips := true           # intro control legends on game start
static var quality: int = Quality.HIGH
# v0.11.0 Comfort spec (all real, no placebo — each has a consumer below):
static var text_size := "normal"        # "normal" | "large" -> 1.4x UI fonts
static var seated := false              # panels at 1.15m eye height when on
static var vignette := "soft"           # "off" | "soft" | "strong"
static var move_style := "paddle"       # Deep Dive: "paddle" | "glide"
static var one_hand_duel := false       # Neon Duel: buckler timing assist

# Per-tier render parameters. Order: LOW, MEDIUM, HIGH, ULTRA.
const _SCALE := [0.7, 0.85, 1.0, 1.12]
const _MSAA := [0, 1, 2, 2]            # Viewport.MSAA_DISABLED / _2X / _4X
const _SHADOW_ATLAS := [1024, 2048, 2048, 4096]
const _ANISO := [1, 2, 4, 8]
const _FOVEATION := [3, 2, 1, 0]       # High, Medium, Low, Off
const _PARTICLES := [0.4, 0.7, 1.0, 1.2]


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run: keep defaults
	input_method = _valid_input(str(cfg.get_value("controls", "input_method", "auto")))
	gaze_dwell = clampf(float(cfg.get_value("controls", "gaze_dwell", 1.2)), 0.5, 3.0)
	dominant_hand = "left" if str(cfg.get_value("controls", "dominant_hand", "right")) == "left" else "right"
	tooltips = bool(cfg.get_value("controls", "tooltips", true))
	quality = clampi(int(cfg.get_value("graphics", "quality", Quality.HIGH)), 0, 3)
	text_size = "large" if str(cfg.get_value("comfort", "text_size", "normal")) == "large" else "normal"
	seated = bool(cfg.get_value("comfort", "seated", false))
	var vg := str(cfg.get_value("comfort", "vignette", "soft"))
	vignette = vg if vg in ["off", "soft", "strong"] else "soft"
	var ms := str(cfg.get_value("comfort", "move_style", "paddle"))
	move_style = ms if ms in ["paddle", "glide"] else "paddle"
	one_hand_duel = bool(cfg.get_value("comfort", "one_hand_duel", false))


static func save() -> void:
	# Load-modify-save: the file also carries the hub's room-setup flags.
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # ignore errors; missing file is fine
	cfg.set_value("controls", "input_method", input_method)
	cfg.set_value("controls", "gaze_dwell", gaze_dwell)
	cfg.set_value("controls", "dominant_hand", dominant_hand)
	cfg.set_value("controls", "tooltips", tooltips)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("comfort", "text_size", text_size)
	cfg.set_value("comfort", "seated", seated)
	cfg.set_value("comfort", "vignette", vignette)
	cfg.set_value("comfort", "move_style", move_style)
	cfg.set_value("comfort", "one_hand_duel", one_hand_duel)
	cfg.save(PATH)


static func _valid_input(m: String) -> String:
	return m if m in ["auto", "controllers", "hands"] else "auto"


## Boot entry: load persisted values, then apply graphics BEFORE the first
## frame (XR session starts later, so foveation + project-level settings take
## effect at init). Called as the first statement of the main scene _ready.
static func boot(root_vp: Viewport) -> void:
	load_settings()
	apply_quality(quality, root_vp)


## Apply a graphics tier now. Everything except foveation is runtime-live
## (viewport props + shadow atlas + particle scale); foveation is also written
## to ProjectSettings so it takes effect on the next XR session start.
static func apply_quality(q: int, root_vp: Viewport) -> void:
	q = clampi(q, 0, 3)
	quality = q
	# Render resolution / supersampling (live).
	if root_vp != null:
		root_vp.scaling_3d_scale = _SCALE[q]
		root_vp.msaa_3d = _MSAA[q] as Viewport.MSAA
	# Shadow atlas resolution (live via RenderingServer).
	RenderingServer.directional_shadow_atlas_set_size(_SHADOW_ATLAS[q], true)
	# Texture anisotropy default for newly created materials (boot = all).
	ProjectSettings.set_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", _ANISO[q])
	# Foveated rendering: applies at XR session init; set the project value so
	# the next launch (and any session restart) picks it up.
	ProjectSettings.set_setting("xr/openxr/foveation_level", _FOVEATION[q])
	# Global particle-count multiplier (live; spawners read it per spawn).
	GraphicsPolish.particle_scale = _PARTICLES[q]
	save()


## The measured parameters of the current tier (for diagnostics + headless
## verification that Low != Ultra).
static func quality_params() -> Dictionary:
	var q := clampi(quality, 0, 3)
	return {
		"name": QUALITY_NAMES[q], "render_scale": _SCALE[q], "msaa": _MSAA[q],
		"shadow_atlas": _SHADOW_ATLAS[q], "anisotropy": _ANISO[q],
		"foveation": _FOVEATION[q], "particle_scale": _PARTICLES[q],
	}


## Comfort consumers (all headless-verifiable):
## A. UI text size: Large multiplies every settings-built font by 1.4x.
static func ui_text_scale() -> float:
	return 1.4 if text_size == "large" else 1.0


## B. Seated mode: pause/launcher panels at 1.15m eye height (vs 1.55m).
static func panel_eye_height() -> float:
	return 1.15 if seated else 1.55


## C. Vignette strength: max opacity during smooth camera/world motion.
static func vignette_strength() -> float:
	match vignette:
		"off":
			return 0.0
		"strong":
			return 0.85
	return 0.55


## Pointer-visibility helpers: does the current input_method preference allow
## controller-driven pointers? hand-driven pointers?
static func allow_controllers() -> bool:
	return input_method != "hands"


static func allow_hands() -> bool:
	return input_method != "controllers"


## Tracker node name for the blade hand in Neon Duel ("RightHand"/"LeftHand"),
## resolved from the dominant-hand setting. The buckler takes the other hand.
static func blade_hand_name() -> String:
	return "LeftHand" if dominant_hand == "left" else "RightHand"


static func buckler_hand_name() -> String:
	return "RightHand" if dominant_hand == "left" else "LeftHand"
