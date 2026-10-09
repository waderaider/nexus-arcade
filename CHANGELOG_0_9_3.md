# NEXUS ARCADE v0.9.3 — "The launcher rework"

**Release date:** 2026-10-09 · **Type:** launcher-rework cycle (Specialist Rule)
**Crash telemetry:** zero real-device reports, ever — this cycle ships the fix
for that too (compiled-in relay fallback, §Under the hood).

wade's Quest 3 photos proved the v0.9.2 launcher renders but the panel is
absurdly close/huge (giant clipped titles) and NO laser pointer is visible —
he can't select anything. This cycle is the full rework, per the standing
LAUNCHER LAW: one simple 2D panel, one scrollable list, laser + trigger.

## Launcher

- **One 2D panel, one scrollable list:** all 75 experiences in MASTER order
  (the same order the pause menu's Next/Prev walks — "down the list = Next"),
  flat, no dividers, no tabs/categories/spotlight/search/favorites.
- **Each row:** game name as "Name — built by Muse" (permanent branding
  directive) + one-line description, 64px flat rows. Hover = instant row
  bg→accent + dark text swap, no tween.
- **Explicit ▲▼ hold-to-repeat scroll buttons** (robust with injected input).
- **Kept:** version badge, prominent CHECK FOR UPDATES, Room setup button
  (button-only now — no first-run auto-popup).
- **Deleted:** tabs, spotlight hero, key-art cards, search/favorites, depth
  toggle, room auto-popup, hub_extras (aurora shader) attach.
- Flat palette throughout: bg #0A0E1A, panel #12182B, text #E8F4FF, accent
  cyan #00F0FF, magenta sparingly, dim #8FA3BF. Godot default font only.

## Panel placement (the photo bug)

- Fixed quad **1.60×1.00 m at 2.0 m** (distance math verified correct — the
  defect was lifecycle: one-shot placement + a single 0.75 s re-settle,
  then never again).
- **Recenter on every menu open** (live HMD pose, yaw-aligned) + a **0.5 s
  tick guard** while the launcher is visible: pushes the panel back out to
  1.5 m if you walk into it (<0.8 m), recenters if it drifts >30° off-axis.
  Never pulls the panel closer.

## Input — belt and suspenders

- **New `DirectUIInput` fallback** runs every frame, independent of the
  XRUIPointer signal path: raycasts raw controller/hand tracker poses
  against the panel quad, drives hover, injects clicks on raw trigger/pinch
  rising edges — and draws its **own bright-yellow beams** so wade always
  sees where he's pointing even if the primary path is fully dead.
- Both paths stay live simultaneously; a single deduped `inject_click`
  funnel (120 ms / 8 px window) prevents double-firing.
- **Thicker primary lasers** (r 0.004→0.008, energy 2→4) and hit dots.
- **Fixed the boolean-typed trigger accessor** (`get_float("trigger")` leg
  deleted — it never fired on-device).
- **Gaze reticle fixed:** was pinned off the panel surface; now sits on it,
  and reticle/dwell keys on "no beam actually drawn" instead of tracker
  registration (the v0.9.2 state was: no lasers AND no reticle).

## On-screen diagnostics (ship-blocker)

- Plain-words input state ("Controllers: L+R live · Hands: none · Gaze:
  ready"), a **"⚠ NO INPUT SOURCE LIVE" self-test warning** when nothing is
  live, **"Boot: first frame Xs"**, plus a live readout (tracker liveness,
  pointer count, panel distance in meters).
- **"Test connection" button** POSTs a tiny ping to the relay (8 s timeout,
  non-blocking) and shows "Connection: SUCCESS" / "Connection: FAILED".

## Pause menu

- New order top→bottom: **Resume → Controls → Restart Game → ◀ Prev / Next ▶
  → EXIT TO LAUNCHER** (renamed from "Quit to Hub"; red, full-width, bottom,
  unmissable). Nav row moved below Restart — a mis-aimed resume tap can no
  longer yank wade into a different game.
- Pause title shows the current game name (so Restart's target is obvious).
- Same flat accent styling (zero radius), laser+trigger, DirectUIInput wired
  to both the exit-button quad and the pause overlay.

## Under the hood

- **Relay fallback:** `BugReporter` and `GameplayTelemetry` now compile in
  `https://nexus-log-relay.brio-00c.workers.dev/report` as the default
  report URL (POST needs no key — no secret leaked); the remote
  version.json fetch still overrides on success. Prime suspect for zero
  device reports ever arriving.
- **Staged boot:** stage 0 = panel + quad + LOADING (first frame <2 s
  target); stage 1 = list UI + pointers; stage 2 (idle) = music, updater,
  telemetry warmup, crash prompt. AudioKit's 31 synchronous WAV loads are
  now lazy (`_ensure_sfx`). Aurora shader path deleted.
- GameplayTelemetry events unchanged (v0.9.2 contract kept).

## Cull check

No cuts this cycle — launcher only. 75 experiences remain.

## Notes

- Not Quest-tested — wade's headset pass is the gate, as always.
- Version: 0.9.3 / version_code 12 (Android reads export_presets.cfg).
