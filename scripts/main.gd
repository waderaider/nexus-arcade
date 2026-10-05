extends Node3D
## NEXUS ARCADE - main scene bootstrap.
## Initializes OpenXR, enables Meta passthrough, and shows the smoke-test
## content (a rotating neon "NEXUS" marker). The game hub replaces this
## content once the export pipeline is proven.

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var marker: MeshInstance3D = $SmokeTest/Marker
@onready var status_label: Label3D = $SmokeTest/StatusLabel

var _spin := 0.0


func _ready() -> void:
	var xr_interface: OpenXRInterface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		get_viewport().use_xr = true
		_enable_passthrough(xr_interface)
		status_label.text = "NEXUS ARCADE\nGravity Golf - XR OK"
	else:
		push_warning("OpenXR not available - running in desktop fallback mode")
		status_label.text = "NEXUS ARCADE\nGravity Golf - Desktop (click to putt)"
	# Hide the smoke-test marker; Golf is the main content now.
	marker.visible = false
	$SmokeTest/Ring.visible = false


func _process(delta: float) -> void:
	_spin += delta
	marker.rotation.y = _spin * 0.8
	marker.position.y = 1.4 + sin(_spin * 1.7) * 0.12


func _enable_passthrough(xr_interface: OpenXRInterface) -> void:
	if xr_interface.get_supported_environment_blend_modes().has(
		XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	):
		get_viewport().transparent_bg = true
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		get_viewport().transparent_bg = false
		world_environment.environment.background_mode = Environment.BG_SKY
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
