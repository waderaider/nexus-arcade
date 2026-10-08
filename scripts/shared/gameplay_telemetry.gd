## GameplayTelemetry.gd — gameplay-event telemetry autoload (autoload: GameplayTelemetry).
##
## Permanent system (2026-10-08): batched, low-overhead gameplay events POSTed
## to the SAME crash-log relay as BugReporter (POST /report). Payloads are
## tiny; events batch in memory and flush every 60s + on game end + on app
## close. Network is fully async — gameplay NEVER blocks on telemetry.
##
## PRIVACY (permanent rule): gameplay events ONLY — game names, durations,
## counts, input methods, error context. NEVER logged: personal data,
## audio/video, room-scan data, or identifiers beyond device model + app
## version (already present in crash reports).
##
## Event names/fields are documented in TELEMETRY.md (project root) for the
## weekly analysis job. Naming is designed so a digest can answer:
##   - which games get quit in <30s (feeds the cull rule)
##   - which games get replayed (game_start with via="restart")
##   - where players pause/quit (pause_open counts, game_end.exit)
##   - hands vs controllers vs gaze usage (input_method)
##
## Usage (autoload name "GameplayTelemetry"):
##   GameplayTelemetry.game_start("Gravity Golf", "launcher", 0)
##   GameplayTelemetry.game_end("quit_to_hub")
##   GameplayTelemetry.event("pause_open", {"game": "Gravity Golf"})
##   GameplayTelemetry.note_input_method("controllers")
##   GameplayTelemetry.error("Gravity Golf", "scene load failed", "res://...")
extends Node

const FLUSH_INTERVAL := 60.0
const MAX_EVENTS := 300
const MANIFEST_URL := "https://raw.githubusercontent.com/waderaider/nexus-arcade/main/version.json"

var _events: Array[Dictionary] = []
var _session_id := ""
var _report_url := ""
var _http: HTTPRequest = null
var _config_http: HTTPRequest = null
var _flush_timer := 0.0
var _flushing := false
var _ready_done := false

# Current game-session state (owned here so ends are idempotent).
var _game := ""
var _game_index := -1
var _game_start_unix := 0.0
var _game_via := ""
var _input_method := ""


func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_id = _new_session_id()
	_http = HTTPRequest.new()
	_http.name = "GameplayTelemetryHTTP"
	add_child(_http)
	_http.request_completed.connect(_on_flush_completed)
	_config_http = HTTPRequest.new()
	_config_http.name = "GameplayTelemetryConfigHTTP"
	add_child(_config_http)
	_config_http.request_completed.connect(_on_config_completed)
	_fetch_remote_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		game_end("app_close")
		_flush_now()


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL:
		_flush_timer = 0.0
		_flush_now()


func _new_session_id() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d%02d%02d%02d_%d" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"], randi() % 100000]


# ------------------------------------------------------------------ API ---

## Start a gameplay session. If one is already open it is auto-ended first
## with exit=<via> (defensive: hub paths always end explicitly, but a missed
## end must never corrupt durations).
func game_start(game_name: String, via: String = "launcher", index: int = -1) -> void:
	if _game != "":
		game_end(via)
	_game = game_name
	_game_index = index
	_game_via = via
	_game_start_unix = Time.get_unix_time_from_system()
	_input_method = ""
	event("game_start", {"game": game_name, "via": via, "index": index})


## End the current gameplay session. No-op when none is open (idempotent).
func game_end(exit: String) -> void:
	if _game == "":
		return
	var dur := Time.get_unix_time_from_system() - _game_start_unix
	event("game_end", {
		"game": _game,
		"index": _game_index,
		"duration_s": snappedf(dur, 0.1),
		"exit": exit,
		"input_method": _input_method,
	})
	_game = ""
	_game_index = -1
	_input_method = ""
	_flush_now()


## Queue a generic gameplay event. Fields are merged with t (unix time).
func event(event_name: String, fields: Dictionary = {}) -> void:
	var e := {"t": Time.get_unix_time_from_system(), "name": event_name}
	for k in fields.keys():
		e[str(k)] = fields[k]
	_events.append(e)
	while _events.size() > MAX_EVENTS:
		_events.remove_at(0)


## Record the first input method used in the current game session.
## method: "controllers" | "hands" | "gaze" | "mouse". First wins per session.
func note_input_method(method: String) -> void:
	if _game == "" or _input_method != "":
		return
	_input_method = method
	event("input_method", {"game": _game, "method": method})


## Error breadcrumb with game context (mirrors BugReporter.log_error usage).
func error(game_name: String, message: String, context: String = "") -> void:
	var fields := {"game": game_name, "message": message.left(160)}
	if context != "":
		fields["context"] = context.left(160)
	event("error", fields)


# ----------------------------------------------------------------- flush ---

## POST the current batch to the relay. Tiny payloads, async, never blocking.
## Events stay in memory when offline or URL-less (ring buffer, oldest dropped).
func _flush_now() -> void:
	if _flushing or _events.is_empty() or _report_url == "":
		return
	_flushing = true
	var payload := {
		"app": str(ProjectSettings.get_setting("application/config/name", "NEXUS ARCADE")),
		"kind": "gameplay_telemetry",
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"version_code": int(ProjectSettings.get_setting("application/config/version_code", 0)),
		"device": OS.get_model_name(),
		"platform": OS.get_name(),
		"headset": _detect_headset(),
		"session_id": _session_id,
		"timestamp": _iso_now(),
		"events": _events.duplicate(),
	}
	_events.clear()
	var body := JSON.stringify(payload)
	_http.request(_report_url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, body)


func _on_flush_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_flushing = false
	if not (result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300):
		# Offline/failed: events for this batch are dropped (telemetry is
		# ephemeral by design; crashes still persist via BugReporter).
		pass


func _fetch_remote_config() -> void:
	if _config_http == null:
		return
	if _config_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_config_http.request(MANIFEST_URL)


func _on_config_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		_report_url = str((data as Dictionary).get("report_url", "")).strip_edges()


func _detect_headset() -> String:
	for iface in XRServer.get_interfaces():
		var d: Dictionary = iface
		if str(d.get("name", "")).to_lower().find("openxr") >= 0:
			return "OpenXR"
	return "none"


func _iso_now() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"]]
