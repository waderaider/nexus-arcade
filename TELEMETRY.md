# NEXUS ARCADE — Gameplay Telemetry

Permanent system (v0.9.2+). The `GameplayTelemetry` autoload
(`scripts/shared/gameplay_telemetry.gd`) batches gameplay events in memory
and POSTs them as tiny JSON payloads to the **same Cloudflare relay** as
crash reports (`POST /report`, `report_url` from `version.json`).

- Flush cadence: every 60s + on every `game_end` + on app close.
- Transport: async `HTTPRequest` — gameplay never blocks on network.
- Offline/URL-less: events stay in a 300-event in-memory ring (oldest dropped).
- Privacy: gameplay events ONLY. No personal data, no audio/video, no room-scan
  data. Identifiers are limited to what crash reports already carry
  (device model, platform, headset type, app version).

## Envelope (every POST)

| Field | Meaning |
|---|---|
| `app` | `"NEXUS ARCADE"` (required by the relay) |
| `kind` | `"gameplay_telemetry"` (distinguishes from crash reports) |
| `version` / `version_code` | app version, e.g. `"0.9.2"` / `11` |
| `device` / `platform` / `headset` | e.g. `"Quest 3"` / `"Android"` / `"OpenXR"` |
| `session_id` | random per app launch, e.g. `"20261008_143022_41793"` |
| `timestamp` | ISO-8601 UTC of the flush |
| `events` | array of event objects (below) |

## Events

Every event object has `t` (unix time, float) and `name` (string), plus
name-specific fields:

| Event `name` | Fields | When |
|---|---|---|
| `game_start` | `game` (string), `via` (`"launcher"`\|`"next"`\|`"prev"`\|`"restart"`), `index` (int, position in the master 75-game list, -1 if unknown) | hub `_load_game`; a new session auto-ends any open one with `exit`=`via` |
| `game_end` | `game`, `index`, `duration_s` (float, 0.1s), `exit` (`"quit_to_hub"`\|`"next"`\|`"prev"`\|`"restart"`\|`"app_close"`), `input_method` (first-used, `""` if none) | quit/switch/restart/close; idempotent |
| `pause_open` | `game` | pause overlay opened (menu button / Esc / floating button) |
| `nav_press` | `game`, `delta` (`-1` prev / `+1` next) | Prev/Next button pressed in the pause menu |
| `input_method` | `game`, `method` (`"controllers"`\|`"hands"`\|`"gaze"`\|`"mouse"`) | first input used in a game session (first wins) |
| `error` | `game`, `message` (≤160 chars), `context` (≤160 chars, optional) | error breadcrumbs with game context (e.g. scene load failure) |

## Weekly-digest queries this supports

- **Quit in <30s** → `game_end` with `duration_s < 30` grouped by `game` (feeds the cull rule objectively).
- **Replayed games** → `game_start` with `via="restart"` counts per `game`.
- **Where players pause/quit** → `pause_open` counts per `game`; `game_end.exit` distribution.
- **Next/Prev adoption** → `nav_press` counts; `game_start` with `via="next"`/`"prev"`.
- **Hands vs controllers vs gaze** → `input_method` / `game_end.input_method` distribution.
- **Error hotspots** → `error` events grouped by `game` + `message`.
