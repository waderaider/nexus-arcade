## UpdateChecker.gd - Check for updates, download and install new APK versions.
## Fetches a version manifest JSON, compares with current version,
## shows changelog, downloads APK, and triggers Android package installer.
extends Node
class_name UpdateChecker

signal check_completed(has_update: bool, latest_version: String, changelog: String)
signal download_progress(bytes_downloaded: int, bytes_total: int)
signal download_completed(apk_path: String)
signal download_failed(error: String)

# URL to the version manifest JSON. Wade can host this anywhere.
# Format: {"version": "0.2.0", "version_code": 2, "changelog": "...", "apk_url": "https://..."}
const DEFAULT_MANIFEST_URL := "https://raw.githubusercontent.com/waderaider/nexus-arcade/main/version.json"

var manifest_url := DEFAULT_MANIFEST_URL
var current_version := "0.1.0"
var current_version_code := 1

var _http: HTTPRequest
var _download_path := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	# Get current version from project settings.
	var vname: String = ProjectSettings.get_setting("application/config/version", "0.1.0")
	if vname and vname != "":
		current_version = vname
	# Derive the version code from the minor component ("0.8.0" -> 8),
	# matching the version.json convention. Falls back to the default.
	var parts := current_version.split(".")
	if parts.size() >= 2:
		var minor := int(parts[1])
		if minor > 0:
			current_version_code = minor

## Check for updates. Emits check_completed.
func check_for_updates(url: String = "") -> void:
	if url != "":
		manifest_url = url
	var err := _http.request(manifest_url)
	if err != OK:
		check_completed.emit(false, "", "Failed to start update check: %s" % err)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_completed.emit(false, "", "Update check failed (HTTP %d)" % response_code)
		return
	var text := body.get_string_from_utf8()
	var json: Variant = JSON.parse_string(text)
	if json == null or not (json is Dictionary) or not (json as Dictionary).has("version"):
		check_completed.emit(false, "", "Invalid version manifest")
		return
	var data: Dictionary = json
	var latest: String = data["version"]
	var latest_code := int(data.get("version_code", 0))
	var changelog: String = data.get("changelog", "No changelog available.")
	var has_update := _is_newer(latest, latest_code)
	# Store the APK URL for later download.
	set_meta("apk_url", data.get("apk_url", ""))
	set_meta("latest_version", latest)
	check_completed.emit(has_update, latest, changelog)

func _is_newer(latest: String, latest_code: int) -> bool:
	if latest_code > 0 and current_version_code > 0:
		return latest_code > current_version_code
	return _compare_versions(latest, current_version) > 0

func _compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return signi(na - nb)
	return 0

## Download the APK from the manifest's apk_url. Emits download_progress/download_completed.
func download_update() -> void:
	var apk_url: String = get_meta("apk_url", "")
	if apk_url == "":
		download_failed.emit("No download URL in manifest")
		return
	_download_path = OS.get_user_data_dir() + "/nexus-arcade-update.apk"
	# Use a separate HTTPRequest for download to track progress.
	var dl := HTTPRequest.new()
	dl.download_file = _download_path
	add_child(dl)
	dl.request_completed.connect(_on_download_completed.bind(dl))
	var err := dl.request(apk_url)
	if err != OK:
		download_failed.emit("Failed to start download: %s" % err)
		dl.queue_free()

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, dl: HTTPRequest) -> void:
	dl.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_failed.emit("Download failed (HTTP %d)" % response_code)
		return
	if not FileAccess.file_exists(_download_path):
		download_failed.emit("Downloaded file not found")
		return
	download_completed.emit(_download_path)

## Trigger Android package installer for the downloaded APK.
func install_update(apk_path: String) -> bool:
	if not OS.has_feature("android"):
		push_warning("[UpdateChecker] Install only supported on Android")
		return false
	# Use Godot's OS to open the APK - Android will prompt to install.
	# For Quest 3, this triggers the system package installer.
	var err := OS.shell_open("file://" + apk_path)
	if err != OK:
		push_error("[UpdateChecker] Failed to open APK for install: %s" % err)
		return false
	return true
