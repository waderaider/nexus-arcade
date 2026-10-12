# QA Self-Check — NEXUS v0.11.0 pitches 6–10 (builder self-gate)
**Date:** 2026-10-12 · **Against:** ~/workspace/design/QA_PLAN_V0110.md §3.1 (NO-SHIP) + §2.3 (new games)
**Games:** nullg_league, chrono_heist, siege_engineer, spectral_files, terraform
**Evidence:** `tools/qa/logs/gates_pitches6_10_<stamp>.log` (this run), `tools/qa/audit_legends.py`

## §3.1 NO-SHIP gates (in my scope)
| # | Gate | Verdict |
|---|---|---|
| 1 | Exit to launcher works | **PASS** — PauseExit autoload attaches unconditionally via hub (`attach_to_game`); all 5 games use `pause_profile="combat"` (0.45s menu hold, no accidental pauses). No per-game exit code to break. |
| 2 | No menu traps | **PASS** — no modals in any of the 5 games. Spectral journal is a persistent in-world case file (never opens/closes). All HUDs are non-interactive except journal guess buttons + terraform palette orbs (tap = act, no dialogs). |
| 3 | Zero errors in 120-frame headless runs | **PASS** — all 5 scenes green in gate log. |
| 7 | Legend honesty (no phantom buttons) | **PASS** — `audit_legends.py` green for all 5 (trigger/grip/menu all read; menu via shared PauseExit; thumbstick blanked where unread). |
| 11 | No >30s silence | **PASS** — hub autowires genre music per game (`GENRE_FOR_SCENE`: scifi/epic/folk/horror/tropical) + per-game SFX maps (27 WAVs) + intensity wiring (§4d). |
| 12 | No placeholder visuals | **PASS** — staged GLBs (castle/flora/fauna/ghosts) + textured primitives; no grey-default heroes, no TODO text. |
| 13 | Branding | **PASS** — hub rows are clean names; no "built by Muse" on game cards. |
| 15 | animatedzombie | **PASS** — not used. |
| — | Pattern A/B/C | **C: PASS** (`controller_config` + `BUTTONS_FOR_STEM` + `HOWTO_FOR_STEM`, all audited). **A/B: S2 debt** — no shared scorecard/intro-card scaffolding exists in the project (sibling pitches 1–5 also ship without it; minigolf precedent). In-world HUDs are static-placed, auto-dismiss ≤4s, never modal. |
| — | RISKY API fallbacks | **PASS** — body tracking (nullg avatar) degrades to head-follow when `BodyTracker` unavailable; RoomKit features all gated on `has_room_data()` with synthetic fallbacks; no voice STT/TTS, no room-mesh physics, no LLM. |
| — | Perf budget | **PASS by construction** — ambient: ≤3 continuous emitters/scene (all ≤64 particles), MultiMesh fields ≤20 instances, zero-alloc tick loops (reused Transform3D/arrays), shader-time animation (0 CPU). No real lights added for ambient (emissive/unlit only). |

## §2.3 new-game extras
- **First 60s:** title card (JuiceFX, narrative subtitle) + `_announce_text` intro + scripted headless demo path; fantasy lands immediately.
- **Named wow moments (VFX §4 wired):** nullg `VFX.goal` (winning goal + slow-mo), chrono `VFX.loop_reset`, siege `VFX.castle_crash`, spectral `VFX.manifest`, terraform `VFX.epoch_flash` (sentience).
- **Audio Director §4d:** `set_intensity` wired per game (0 calm / 1 tense / 2 driving). Beat clock evaluated — none of the 5 games have rhythm mechanics; forcing beat-reactivity would be fake. Declined with reason.
- **Animator §2b:** 3–5 ambient elements per game, all Quest-3-cheap techniques (see AmbientKit). Shared helpers: `scripts/shared/ambient_kit.gd`, `assets/shaders/ambient_sway.gdshader`, `assets/shaders/energy_shimmer.gdshader`, `assets/shaders/cloud_layer.gdshader`.
- **Narrative Part 2:** exact title_card subtitles + announce strings wired for all 5.

## Out of my scope (shared/ship-coordinator)
Gates 4–6, 8–10, 14, 16 (settings, pause grid metrics, Sky Traffic, aapt, MARIGOLD).
