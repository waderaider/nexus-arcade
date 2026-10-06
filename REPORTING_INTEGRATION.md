# REPORTING INTEGRATION — BugReporter autoload merge steps

The crash/error log reporter is built and self-tested:
`scripts/shared/bug_reporter.gd` (autoload singleton `BugReporter`) +
`tests/test_bug_reporter.gd` (28/28 passing).

Apply the steps below when the hub is free. Do NOT ship without step 1–3.

---

## 1. project.godot — register the autoload

`project.godot` currently has **no** `[autoload]` section. Add:

```ini
[autoload]

BugReporter="*res://scripts/shared/bug_reporter.gd"
```

Place it as its own section (convention: after `[application]`, before
`[display]` — exact position does not matter).

---

## 2. scripts/hub.gd — 3 call sites

### 2a. Crash prompt on hub `_ready()` (line ~108)

Current:
```gdscript
func _ready() -> void:
	_build_hub()
	_setup_updater()
```

New:
```gdscript
func _ready() -> void:
	_build_hub()
	_setup_updater()
	# Crash reporter: offer to send the previous session's log.
	var crash: Dictionary = BugReporter.prompt_if_crash_pending()
	if not crash.is_empty():
		_show_crash_prompt(crash)
	BugReporter.session_start("hub")
```

### 2b. Session start on `_load_game()` (line ~412)

At the top of `_load_game(scene_path: String, game_name: String)`, add:

```gdscript
	BugReporter.session_start(game_name)
```

### 2c. Session end on `_return_to_hub()` (line ~442)

At the top of `_return_to_hub()`, add:

```gdscript
	BugReporter.session_end()
```

### 2d. Crash prompt dialog (new hub helper)

Adapt to the hub's 3D button style (`_make_tab_button` pattern). Minimal logic:

```gdscript
func _show_crash_prompt(crash: Dictionary) -> void:
	# Build a small 3D panel: "Looks like <game> crashed last time."
	# [Send log to Brio] -> _on_crash_send()   [Keep local] -> _on_crash_keep()
	# Use GraphicsPolish.make_label() for text and the hub's button builder.
	pass  # TODO(merge): implement with hub button style

func _on_crash_send() -> void:
	BugReporter.send_report()  # async; result via BugReporter.report_sent signal

func _on_crash_keep() -> void:
	BugReporter.acknowledge_crash()
```

Optional: after a successful update check (connectivity confirmed), call
`BugReporter.retry_pending()` to flush locally-saved reports, and
`BugReporter.add_breadcrumb("update_checked")` on each check.

---

## 3. version.json — add the report endpoint field

```json
{
  "version": "0.5.0",
  "version_code": 5,
  "apk_url": "https://github.com/waderaider/nexus-arcade/releases/download/v0.5.0/NexusArcade-v0.5.0.apk",
  "changelog": "...",
  "report_url": ""
}
```

**Plan:** ship with `"report_url": ""` (reporting stays local-only).
Brio fills in the real endpoint URL later **via the manifest alone — no app
update needed**. `BugReporter.fetch_remote_config()` reads it on every
launch. Empty string = disabled = reports save to `user://logs/pending/`.

---

## 4. Server contract (for whoever builds the endpoint)

- `POST <report_url>` with `Content-Type: application/json`
- Body fields: `app`, `version`, `version_code`, `device`, `platform`,
  `headset`, `game`, `crashed` (bool), `user_note`, `timestamp`,
  `log_tail` (array of last 200 log lines), `breadcrumbs` (array, last 30)
- Any 2xx response = accepted. Anything else = client keeps it in
  `user://logs/pending/` and retries later.

---

## 5. Self-test (run before pushing)

```bash
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
  --path ~/workspace/godot-nexus-arcade \
  -s tests/test_bug_reporter.gd
```

Expected: `ALL TESTS PASSED` (28 checks, exit 0). The test simulates a
crashed previous session (dirty flag + fake log), verifies detection,
`CRASH_DETECTED` recording, report structure, pending-save fallback, and
acknowledgement — then cleans up everything it created in `user://`.

Also re-run the parse check on the edited hub:
```bash
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --check-only \
  -s ~/workspace/godot-nexus-arcade/scripts/hub.gd
```

---

## 6. Privacy

Logs contain ONLY game events, caught errors, device model, headset type,
and app version. NEVER logged: hand-tracking raw data, camera frames,
player location, or personally identifying information. This is stated in
the file header of `bug_reporter.gd` and must survive the merge.
