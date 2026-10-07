## BugReporter.gd — automatic crash/error log reporter for NEXUS ARCADE.
##
## Autoload singleton (see REPORTING_INTEGRATION.md). Session logging, crash
## detection via a clean-exit flag (no OS hooks needed), breadcrumbs, and
## user-consented log upload to Brio's report endpoint.
##
## PRIVACY — logs contain ONLY: game events, caught errors with context,
## device model, headset type, and app version. NEVER logged: hand-tracking
## raw data, camera frames, player location, or any personally identifying
## information.
##
## Usage (autoload name "BugReporter"):
##   BugReporter.session_start("gravity_golf")
##   BugReporter.log("Ball launched")
##   BugReporter.log_error("Null club reference", "swing()")
##   BugReporter.add_breadcrumb("update_checked")
##   BugReporter.session_end()
##   var crash: Dictionary = BugReporter.prompt_if_crash_pending()
##   # ... user picks Send / Keep local ...
##   BugReporter.send_report("optional user note")   # or BugReporter.acknowledge_crash()
extends Node

signal report_sent(success: bool)

const APP_FALLBACK_NAME := "NEXUS ARCADE"
const LOG_DIR := "user://logs/"
const PENDING_DIR := "user://logs/pending/"
const FLAG_FILE := "user://logs/.clean_exit"
const LAST_GAME_FILE := "user://logs/.last_game"
const MAX_SESSIONS := 10
const MAX_BREADCRUMBS := 30
const LOG_TAIL_LINES := 200
const CRASH_TAIL_LINES := 50
const EARLY_LINE_CAP := 100
const MANIFEST_URL := "https://raw.githubusercontent.com/waderaider/nexus-arcade/main/version.json"

var _log_file: FileAccess = null
var _session_path := ""
var _session_game := ""
var _breadcrumbs: Array[String] = []
var _early_lines: Array[String] = []
var _pending_crash: Dictionary = {}
var _report_url := ""
var _http: HTTPRequest = null
var _config_http: HTTPRequest = null
var _last_report_json := ""
var _retry_path := ""
var _ready_done := false


func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	_ensure_dirs()
	_http = HTTPRequest.new()
	_http.name = "BugReporterHTTP"
	add_child(_http)
	_http.request_completed.connect(_on_report_completed)
	_config_http = HTTPRequest.new()
	_config_http.name = "BugReporterConfigHTTP"
	add_child(_config_http)
	_config_http.request_completed.connect(_on_config_completed)
	_check_previous_crash()
	fetch_remote_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		session_end()


# ---------------------------------------------------------------- sessions ---

## Start a logging session (call with the game/scene name, e.g. on hub _load_game).
func session_start(game_name: String) -> void:
	if _log_file != null:
		_write_line("WARN", "session_start while a session was open; closing previous session")
		_close_session_file()
	_write_flag("0")
	_write_last_game(game_name)
	_session_game = game_name
	var stamp := _timestamp()
	_session_path = LOG_DIR + "session_" + stamp + ".log"
	var counter := 0
	while FileAccess.file_exists(_session_path):
		counter += 1
		_session_path = LOG_DIR + "session_" + stamp + "_" + str(counter) + ".log"
	_log_file = FileAccess.open(_session_path, FileAccess.WRITE)
	_write_header(game_name)
	for line in _early_lines:
		_write_raw(line)
	_early_lines.clear()
	if not _pending_crash.is_empty():
		_write_line("CRASH", "CRASH_DETECTED game=%s detected_at=%s" % [str(_pending_crash.get("game", "?")), str(_pending_crash.get("detected_at", "?"))])
		var tail: PackedStringArray = _pending_crash.get("prev_tail", PackedStringArray())
		_write_line("CRASH", "---- previous session tail (%d lines) ----" % tail.size())
		for tline in tail:
			_write_raw("  " + tline)
		_write_line("CRASH", "---- end previous tail ----")
	_prune_old_sessions()
	add_breadcrumb("session_start:" + game_name)
	_write_line("INFO", "session_start game=" + game_name)


## End the current session cleanly (call on hub _return_to_hub / app close).
func session_end() -> void:
	if _log_file == null:
		return
	_write_line("INFO", "session_end game=" + _session_game)
	_close_session_file()
	_write_flag("1")
	add_breadcrumb("session_end")


## General log line.
func log(msg: String) -> void:
	_write_line("INFO", msg)


## Error log line with optional context (function name, state, etc.).
func log_error(msg: String, context: String = "") -> void:
	var full := msg
	if context != "":
		full += " | context: " + context
	_write_line("ERROR", full)
	add_breadcrumb("error:" + msg.left(80))


## Lightweight breadcrumb ring buffer (last MAX_BREADCRUMBS), dumped into reports.
func add_breadcrumb(event: String) -> void:
	_breadcrumbs.append("[%s] %s" % [_timestamp(), event])
	while _breadcrumbs.size() > MAX_BREADCRUMBS:
		_breadcrumbs.remove_at(0)


# ------------------------------------------------------------- crash state ---

## Returns {game, log_path, detected_at, prev_tail} if the previous session
## crashed, else {}. The hub calls this on _ready to offer the send prompt.
func prompt_if_crash_pending() -> Dictionary:
	return _pending_crash.duplicate()


## Dismiss the crash prompt without sending. Marks the crash as handled so it
## is not offered again.
func acknowledge_crash() -> void:
	_pending_crash.clear()
	_write_flag("1")


## Number of unsent reports saved locally.
func get_pending_count() -> int:
	return _pending_files().size()


# ----------------------------------------------------------------- reports ---

## Build the report dictionary (JSON-serializable).
func build_report(user_note: String = "") -> Dictionary:
	if _log_file != null:
		_log_file.flush()
	var tail := PackedStringArray()
	if _session_path != "" and FileAccess.file_exists(_session_path):
		tail = _tail_lines(_session_path, LOG_TAIL_LINES)
	return {
		"app": str(ProjectSettings.get_setting("application/config/name", APP_FALLBACK_NAME)),
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"version_code": int(ProjectSettings.get_setting("application/config/version_code", 0)),
		"device": OS.get_model_name(),
		"platform": OS.get_name(),
		"headset": _detect_headset(),
		"game": _read_last_game(),
		"crashed": not _pending_crash.is_empty(),
		"user_note": user_note,
		"timestamp": _timestamp(),
		"log_tail": Array(tail),
		"breadcrumbs": _breadcrumbs.duplicate(),
	}


## POST the report as JSON. Returns false (and saves to pending/) when the
## report URL is empty or the request cannot start. Result arrives async via
## the report_sent signal.
func send_report(user_note: String = "") -> bool:
	var json_text := JSON.stringify(build_report(user_note))
	if _report_url == "":
		_save_pending(json_text)
		report_sent.emit(false)
		return false
	_last_report_json = json_text
	_retry_path = ""
	var err := _http.request(_report_url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, json_text)
	if err != OK:
		_save_pending(json_text)
		report_sent.emit(false)
		return false
	return true


## Try sending the oldest locally-saved pending report.
func retry_pending() -> bool:
	if _report_url == "":
		return false
	var files := _pending_files()
	if files.is_empty():
		return false
	files.sort()
	var path: String = files[0]
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return false
	_last_report_json = text
	_retry_path = path
	var err := _http.request(_report_url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, text)
	return err == OK


## Override the report URL manually (remote config normally provides it).
func set_report_url(url: String) -> void:
	_report_url = url.strip_edges()


## Fetch version.json and read the "report_url" field (empty = disabled).
func fetch_remote_config() -> void:
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
		set_report_url(str((data as Dictionary).get("report_url", "")))
		# Config just arrived: flush any reports saved while offline/local-only.
		if _report_url != "":
			retry_pending()


func _on_report_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if ok:
		if _retry_path != "" and FileAccess.file_exists(_retry_path):
			DirAccess.remove_absolute(_retry_path)
		_retry_path = ""
	else:
		if _last_report_json != "":
			_save_pending(_last_report_json)
	_last_report_json = ""
	report_sent.emit(ok)


# ------------------------------------------------------------------ internals ---

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	DirAccess.make_dir_recursive_absolute(PENDING_DIR)


func _check_previous_crash() -> void:
	if not FileAccess.file_exists(FLAG_FILE):
		return
	if FileAccess.get_file_as_string(FLAG_FILE).strip_edges() != "0":
		return
	var game := _read_last_game()
	if game == "":
		game = "unknown"
	var prev_log := _latest_session_log()
	var tail := PackedStringArray()
	if prev_log != "" and FileAccess.file_exists(prev_log):
		tail = _tail_lines(prev_log, CRASH_TAIL_LINES)
	_pending_crash = {
		"game": game,
		"log_path": prev_log,
		"detected_at": _timestamp(),
		"prev_tail": tail,
	}
	add_breadcrumb("crash_detected:" + game)


func _latest_session_log() -> String:
	var logs := _session_log_paths()
	if logs.is_empty():
		return ""
	logs.sort()
	return logs[logs.size() - 1]


func _session_log_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("session_") and f.ends_with(".log"):
			out.append(LOG_DIR + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _prune_old_sessions() -> void:
	var logs := _session_log_paths()
	logs.sort()
	while logs.size() > MAX_SESSIONS:
		var oldest: String = logs[0]
		logs.remove_at(0)
		if oldest != _session_path and FileAccess.file_exists(oldest):
			DirAccess.remove_absolute(oldest)


func _pending_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PENDING_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			out.append(PENDING_DIR + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _save_pending(json_text: String) -> void:
	_ensure_dirs()
	var path := PENDING_DIR + "report_" + _timestamp() + ".json"
	var counter := 0
	while FileAccess.file_exists(path):
		counter += 1
		path = PENDING_DIR + "report_" + _timestamp() + "_" + str(counter) + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(json_text)
		f.close()


func _write_flag(value: String) -> void:
	var f := FileAccess.open(FLAG_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(value)
		f.close()


func _write_last_game(game_name: String) -> void:
	var f := FileAccess.open(LAST_GAME_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(game_name)
		f.close()


func _read_last_game() -> String:
	if not FileAccess.file_exists(LAST_GAME_FILE):
		return ""
	return FileAccess.get_file_as_string(LAST_GAME_FILE).strip_edges()


func _write_header(game_name: String) -> void:
	_write_line("INFO", "=== NEXUS ARCADE session ===")
	_write_line("INFO", "app=" + str(ProjectSettings.get_setting("application/config/name", APP_FALLBACK_NAME)))
	_write_line("INFO", "version=" + str(ProjectSettings.get_setting("application/config/version", "0.0.0")))
	_write_line("INFO", "device=" + OS.get_model_name() + " platform=" + OS.get_name() + " headset=" + _detect_headset())
	_write_line("INFO", "first_game=" + game_name)


func _write_line(level: String, msg: String) -> void:
	_write_raw("[%s] %s %s" % [_timestamp(), level, msg])


func _write_raw(line: String) -> void:
	if _log_file != null:
		_log_file.store_line(line)
		# Flush every line: a crash must not lose buffered log data.
		_log_file.flush()
	else:
		_early_lines.append(line)
		while _early_lines.size() > EARLY_LINE_CAP:
			_early_lines.remove_at(0)


func _close_session_file() -> void:
	if _log_file != null:
		_log_file.close()
	_log_file = null


func _tail_lines(path: String, n: int) -> PackedStringArray:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return PackedStringArray()
	var lines := text.split("\n")
	while lines.size() > 0 and lines[lines.size() - 1] == "":
		lines.remove_at(lines.size() - 1)
	var start := maxi(0, lines.size() - n)
	return lines.slice(start)


func _timestamp() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]


func _detect_headset() -> String:
	for iface in XRServer.get_interfaces():
		var d: Dictionary = iface
		if str(d.get("name", "")).to_lower().find("openxr") >= 0:
			return "OpenXR"
	return "none"
