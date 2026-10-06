## ARCamera.gd - GDScript wrapper for the ARCamera Android plugin.
## Quest 3 passthrough camera access (Camera2-based). Fully guarded:
## every call is safe on desktop/headless — is_available() returns false
## and capture()/scan_qr() return empty values when the plugin, the
## permission, or the hardware is missing.
extends RefCounted
class_name ARCamera


## The raw plugin singleton, or null when unavailable (desktop/headless).
static func _plugin() -> Object:
	if not Engine.has_singleton("ARCamera"):
		return null
	return Engine.get_singleton("ARCamera")


## True when a real camera frame can be captured right now.
static func is_available() -> bool:
	var p := _plugin()
	if p == null:
		return false
	if not p.has_method("isCameraAvailable"):
		return false
	return bool(p.call("isCameraAvailable"))


## Ask Android for the CAMERA permission (no-op when unavailable).
static func request_permission() -> void:
	var p := _plugin()
	if p != null and p.has_method("requestCameraPermission"):
		p.call("requestCameraPermission")


## Capture one still frame as a Godot Image, or null when unavailable.
static func capture() -> Image:
	var p := _plugin()
	if p == null or not p.has_method("captureFrame"):
		return null
	var bytes: PackedByteArray = p.call("captureFrame")
	if bytes == null or bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		return null
	return img


## Size of the last captured frame (0,0 when none).
static func frame_size() -> Vector2i:
	var p := _plugin()
	if p == null:
		return Vector2i.ZERO
	var w := int(p.call("getFrameWidth")) if p.has_method("getFrameWidth") else 0
	var h := int(p.call("getFrameHeight")) if p.has_method("getFrameHeight") else 0
	return Vector2i(w, h)


## Decode a QR/barcode from a fresh capture. "" when none found/unavailable.
static func scan_qr() -> String:
	var p := _plugin()
	if p == null or not p.has_method("scanQR"):
		return ""
	var s: String = p.call("scanQR")
	return s.strip_edges()
