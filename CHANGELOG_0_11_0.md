# NEXUS ARCADE v0.11.0 — "The FEEL update"

**Release date:** 2026-10-12 · **Type:** major upgrades + 10 new AAA games
**Games:** 80 (75 − 5 culls + 10 new) · **NOT Quest-tested** (standing rule)

## 10 NEW GAMES

1. **War Table** — Command tiny armies on your real coffee table - pinch-drag RTS.
2. **Kaiju Siege** — You ARE the kaiju - stomp a city that rises from your floor.
3. **Starship Bridge** — Your room is a starship bridge: helm, tactical, engineering.
4. **Phantom Thief** — Stealth heist in your own house - steal 3 artifacts unseen.
5. **Runewright** — Draw runes mid-air to forge spells; defend your couch-fort.
6. **Null-G League** — Zero-G disc sport in your room: wall push-offs, mid-air catches, 3v3.
7. **Chrono Heist** — 60-second time-loop bank job — your crew is recordings of you.
8. **Siege Engineer** — Build trebuchets on your table, smash castles on your floor.
9. **Spectral Files** — Ghost hunt in your own home: EMF, thermal, spirit box, camera.
10. **Terraform** — God-game on your coffee table: sculpt, seed, survive epochs.

All 10 ship with honest control legends (no phantom buttons), juice wiring
(SFX + haptics + JuiceFX), named wow moments, and room-degrade fallbacks.

## NEON DUEL PAUSE-SPAM FIX (telemetry-driven ship-blocker)

- Universal **0.45s menu-button HOLD** to open pause (fill ring on the ❚❚
  button); sub-threshold taps ignored. Applies to EVERY game, not just
  combat — the pause-spam fix is universal (QA §3.1.8).
- `pause_open` telemetry now carries **`via`** ∈ {menu_hold, exit_button, esc}
  — the next digest can finally split accidental ❚❚ taps from menu brushes.
- Floating ❚❚/II requires **250ms hover-dwell** before accepting clicks
  (kills accidental trigger-squeeze opens); hidden while fighting in combat
  profile, reappears at round end.
- Duel countdown uses `create_timer(0.7, false)` — pausing mid-countdown
  freezes it (was running while paused).
- **Honest legends:** duel + beat-blades phantom rows blanked; 8 more
  phantom trigger/grip rows found by the ship-pass audit and blanked
  (ar-fishing, drone-racer, laser-tag-ar, light-painter, sky-defender,
  spell-duel, wizard_academy, kaiju_siege-grip) — all are pinch/motion
  driven; the HOWTO rows describe the real controls.
- Neon Duel: 3-step practice-dummy onboarding before FIGHT (~20s,
  skippable), round-1 hint ribbon, honest HOWTO legend.

## PAUSE MENU = PLAIN FLAT 2D GRID (wade's order)

- Pause is now a grid of game cards (5 columns, 80 games, scrollable with
  hold-repeat ▲/▼) — the grid IS the game picker: cards jump directly.
- Panels place ONCE per open and stay 100% STATIC — the 0.5s recenter tick
  is dead by design (wade's order).
- Grid measured headless against the real implementation: 581px ≤ 800px
  viewport, ~2 card rows visible, EXIT TO LAUNCHER full-width and unclipped.
- Order: Resume / Controls / Restart Game / **Settings** (new) / Prev-Next
  nav / red EXIT TO LAUNCHER.

## SETTINGS MENU (wade's order — no placebo toggles)

- Menu button → pause → **Settings**, one tap. Every option measurably wired:
- Input method (auto/controllers/hands) gates the input funnel; gaze dwell
  (0.8/1.2/1.8s) drives the gaze fallback timer; dominant hand feeds
  controller skins + Neon Duel blade/buckler assignment; tooltips on/off
  suppresses the intro legend; quality Low/Medium/High/Ultra ACTUALLY
  changes rendering (0.7/0.85/1.0/1.12 resolution scale, MSAA off/2x/4x/4x,
  1024/2048/2048/4096 shadow atlas, foveation High/Med/Low/Off, 40/70/100/
  120% particles). Persisted in ConfigFile, applied at boot.

## TELEMETRY (Headset Specialist)

- `menu_open` boot event in the hub (version + input inventory) with
  immediate flush — menu-only sessions now generate reports (the
  zero-phone-home root cause, both apps).
- `XR_META_headset_id` enabled — real headset model in every relay report
  + on-screen diagnostics.

## JUICE TIERS (§13c)

- **T1** (Neon Duel, Swarm Protocol, AR Defender): full JuiceFX + haptics +
  AudioKit wiring with named wow moments (final-match-point hit-stop + FOV
  punch + slow-mo announce; swarm kill impact + core hit-stop + combo
  popups; defender haptic vocabulary + wave intensity climb).
- **T2** (rhythm-boxer first, then Deep Dive, Sky Traffic, Light Painter,
  wizard_academy, mech_pilot, holo-dungeon, sky_pirates, ar_detective,
  couch_morph): SFX maps + haptics + JuiceFX each.
- **T3**: genre recipes across the long tail (sample-audited 15+).

## PERF GUARDS

- Sky Traffic: MAX_PLANES=12 nearest-aircraft clamp + label LOD (nearest 4
  get info cards) — the unbounded spawn is capped.
- DirectUIInput beams: hover-only gating (no always-on yellow beams).
- Export preset flips: body_tracking=1, render_model=1 (kaiju_siege,
  nullg_league, controller skins use both).

## ART (Design Director)

- **Tier 1:** spell-duel wizard rebuilt on the Quaternius KnightCharacter
  (CC0) + sword/helmet; hw_monster_feed jaw-hinge feeding. (hw_goblin_archery
  Blender hero goblin + all Tier 2 swaps — holo-garden→Kenney, room-racer→
  Quaternius cars, starforge→Quaternius ships, drone-racer Blender body,
  sky-defender downtowncity, holo_farm CraftPix — and the Tier 3 coherence
  pass are NEXT CYCLE, not this one.)

## CULLS (wade's permanent quality bar)

- **Holo Piano** (no game loop; Phantom Piano is the stronger twin),
  **Star Map** (passive screensaver, nothing to DO), **Plant Doctor**
  (utility, not a game), **QR Treasure Hunt** (print-5-QR-codes setup
  friction), **Candy Stack** (one-note loop). Scenes + scripts physically
  removed this ship pass; assets recycled per CUT_LIST.md.
- On watch (next digest adjudicates): Portrait Gallery, Apple Bobbing,
  Holo Theremin.

## Ship-pass fixes (QA gate, 2026-10-12)

- Universal 0.45s menu-button hold (was combat-only — QA §3.1.8 NO-SHIP);
  `via` values menu_hold/exit_button/esc.
- 8 phantom legend rows blanked (see above).
- Culled game scenes/scripts physically deleted.

## Spatial 3D audio (wade's permanent rule — fast-follow, NOT this build)
- Audio Director's spatial pass is DONE and verified: Godot 4.7.2's built-in
  3D audio server is the honest path (Meta XR Audio is NOT exposed by the
  vendor plugin — verified via strings on both .so files). 18/18 headless
  checks green. New `SpatialAudio` helper (scripts/shared/spatial_audio.gd):
  one line per sound, auto occlusion raycast + reverb zones (7 presets).
  Full spec: ~/workspace/design/SPATIAL_AUDIO_V0110.md.
- The per-title wiring (a `SpatialAudio` node per game + the spec's call
  sites) ships as a FAST-FOLLOW — it landed after this build's push and
  spans 80 games. Always called "spatial 3D audio", never Dolby/Atmos/HRTF.
- QA ship-gate additions for the follow-up: eyes-closed direction check,
  wall-muffle occlusion check, reverb zone-transition check, no-2D-regression.

## Known limitations

- Minigold 3D UI still outside the shared 2D input stack (design debt).
- hw_goblin_archery Blender hero goblin + Tier 2/T3 art swaps: next cycle.
- Headless-verified only: 163 scripts parse-clean, main.tscn + all 10 new
  game scenes 120-frame zero errors. **NOT Quest-tested** — wade's headset
  pass + the telemetry digest are the hardware leg.
