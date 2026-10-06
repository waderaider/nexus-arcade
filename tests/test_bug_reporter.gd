extends SceneTree
## Self-test for BugReporter (scripts/shared/bug_reporter.gd).
##
## Run from the project directory:
##   ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path ~/workspace/godot-nexus-arcade -s tests/test_bug_reporter.gd
##
## Simulates a crashed previous session, then verifies detection, logging,
## report building, pending-save fallback, and acknowledgement. Cleans up
## everything it creates in user:// (backing up pre-existing flag files).

const LOG_DIR := "user://logs/"
const PENDING_DIR := "user://logs/pending/"
const FLAG_FILE := "user://logs/.clean_exit"
const LAST_GAME_FILE := "user://logs/.last_game"

var _failures := 0
var _had_flag := false
var _had_last_game := false
var _flag_backup := ""
var _last_game_backup := ""


func _check(cond: bool, name: String) -> void:
	if cond:
		print("PASS: ", name)
	else:
		_failures += 1
		printerr("FAIL: ", name)


func _session_logs() -> Array:
	var out := []
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("session_") and f.ends_with(".log"):
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _pending_jsons() -> Array:
	var out := []
	var dir := DirAccess.open(PENDING_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _init() -> void:
	var BRScript: GDScript = load("res://scripts/shared/bug_reporter.gd")
	_check(BRScript != null, "bug_reporter.gd loads")

	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	DirAccess.make_dir_recursive_absolute(PENDING_DIR)

	# Back up any real flag state.
	if FileAccess.file_exists(FLAG_FILE):
		_had_flag = true
		_flag_backup = FileAccess.get_file_as_string(FLAG_FILE)
	if FileAccess.file_exists(LAST_GAME_FILE):
		_had_last_game = true
		_last_game_backup = FileAccess.get_file_as_string(LAST_GAME_FILE)

	var logs_before := _session_logs()
	var pending_before := _pending_jsons()

	# --- Simulate a crashed previous session --------------------------------
	var fake_log := LOG_DIR + "session_20000101_000000.log"
	var ff := FileAccess.open(fake_log, FileAccess.WRITE)
	for i in range(60):
		ff.store_line("[20000101_000000] INFO fake line %d" % i)
	ff.close()
	var wf := FileAccess.open(FLAG_FILE, FileAccess.WRITE)
	wf.store_string("0")
	wf.close()
	var wg := FileAccess.open(LAST_GAME_FILE, FileAccess.WRITE)
	wg.store_string("test_crash_game")
	wg.close()

	# Fresh instance detects the crash on _ready.
	# NOTE: in a SceneTree script's _init, _ready() is deferred until the first
	# frame (which never runs before quit()), so invoke it explicitly here.
	# In the real app the engine calls _ready() exactly once (autoload).
	var br: Node = BRScript.new()
	root.add_child(br)
	br._ready()

	var crash: Dictionary = br.prompt_if_crash_pending()
	_check(not crash.is_empty(), "crash detected after dirty flag")
	_check(str(crash.get("game", "")) == "test_crash_game", "crashed game identified")
	_check(str(crash.get("log_path", "")).ends_with("session_20000101_000000.log"), "previous log path recorded")

	# New session records the crash.
	br.session_start("hub_test")
	_check(FileAccess.file_exists(LOG_DIR + "session_20000101_000000.log"), "fake previous log still on disk")
	var new_log := ""
	for f in _session_logs():
		if not f in logs_before and f != "session_20000101_000000.log":
			new_log = f
	_check(new_log != "", "new session log created")
	if new_log != "":
		var text := FileAccess.get_file_as_string(LOG_DIR + new_log)
		_check(text.find("CRASH_DETECTED") >= 0, "new log contains CRASH_DETECTED")
		_check(text.find("fake line 59") >= 0, "new log contains previous session tail")

	# Logging + breadcrumbs.
	br.log("hello test")
	br.log_error("boom", "test_ctx")
	br.add_breadcrumb("test_crumb")
	_check(true, "log/log_error/breadcrumb calls do not error")

	# Report structure.
	var report: Dictionary = br.build_report("user note here")
	for key in ["app", "version", "device", "game", "crashed", "log_tail", "breadcrumbs"]:
		_check(report.has(key), "report has key: " + key)
	_check(bool(report.get("crashed", false)) == true, "report marks crashed=true")
	_check(str(report.get("user_note", "")) == "user note here", "report carries user note")
	_check((report.get("breadcrumbs", []) as Array).size() > 0, "report has breadcrumbs")

	# No report URL configured -> saved to pending, returns false.
	var sent: bool = br.send_report("note")
	_check(sent == false, "send_report returns false with no URL")
	_check(br.get_pending_count() >= pending_before.size() + 1, "report saved to pending/")

	# Acknowledge clears the prompt.
	br.acknowledge_crash()
	_check(br.prompt_if_crash_pending().is_empty(), "acknowledge clears crash prompt")

	br.session_end()
	_check(FileAccess.get_file_as_string(FLAG_FILE).strip_edges() == "1", "clean flag written on session_end")

	# --- Cleanup -------------------------------------------------------------
	for f in _session_logs():
		if not (f in logs_before):
			DirAccess.remove_absolute(LOG_DIR + f)
	for f in _pending_jsons():
		if not (f in pending_before):
			DirAccess.remove_absolute(PENDING_DIR + f)
	if _had_flag:
		var rf := FileAccess.open(FLAG_FILE, FileAccess.WRITE)
		rf.store_string(_flag_backup)
		rf.close()
	else:
		if FileAccess.file_exists(FLAG_FILE):
			DirAccess.remove_absolute(FLAG_FILE)
	if _had_last_game:
		var rg := FileAccess.open(LAST_GAME_FILE, FileAccess.WRITE)
		rg.store_string(_last_game_backup)
		rg.close()
	else:
		if FileAccess.file_exists(LAST_GAME_FILE):
			DirAccess.remove_absolute(LAST_GAME_FILE)
	_check(_session_logs() == logs_before, "test session logs cleaned up")
	_check(_pending_jsons() == pending_before, "test pending reports cleaned up")

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("FAILURES: ", _failures)
	quit(_failures)
