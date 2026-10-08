# NEXUS ARCADE v0.9.1 — "The tidy version"

**Release date:** 2026-10-08 · **Type:** light cycle (verification + art fixes only)
**Crash telemetry:** zero real-device reports — no hotfix warranted. Nothing
invented to fill the cycle.

## Verification pass

- **`no_auto_wire` audit:** zero of 75 games opt out of the global auto-wirer,
  so PauseExit attaches on every launch — exit-to-launcher is wired everywhere
  via controller menu button / Esc, the floating on-screen pause button, and
  controller laser + hand pinch + gaze dwell.
- **Structural fix (hub.gd `_autowire_game`):** the old `if _game_opt_out():
  return` fired *before* the PauseExit attach block, so any future opt-out game
  would have silently lost its exit path entirely. PauseExit now attaches
  **unconditionally** — opt-out skips only the title card, affordance pass,
  and controller-skin dressing. The standing rule (every game exits to
  launcher) now holds by construction, not by audit luck.
- **CI gray-primitive audit:** 12 files / 35 findings, warn mode. The five
  art-fix games below are clean except holo-pets' intentional fallback path
  (primitive pet + food bits + toy ball). Remaining findings are untouched
  games — next cycle's problem.

## Art fixes (Design Director's list, staged libraries only)

- **Holo Aquarium** — the 8 primitive wiggle-tail fish are now animated
  Quaternius fish (Fish1/2/3, CC0, `Armature|Swim`), same drop-in pattern as
  Deep Dive. Boids behavior, food pellets, and day/night cycle unchanged.
- **Holo Pets** — Wisp is now a real animated Quaternius Pug (CC0, Idle +
  Jump animations): it idles while lounging, plays Jump while hopping after
  the ball, and droops its whole body when sad. All pet-sim behavior
  (stats, wander, couch naps, furniture hiding) unchanged. Primitive build
  stays as fallback.
- **Wizard Academy** — potion bottles are now real Quaternius fantasyprops
  bottles (Potion_1/2/4, CC0) instead of cylinder assemblies, and the missing
  juice pass landed: grab pop, settle squash on return, brew splash pop on
  the cauldron, wrong-pour shake. (Fixed the missing `T_Trim_Props_*`
  textures so the staged glTFs import with their trim material.)
- **Mummy Wrap** — geometry pass: the bare capsule mummy now ships
  pre-wrapped with 8 static bandage bands + 2 diagonal cross-bands
  (hand-wrapped look, varied tilts). Player-wound rings still stack on top.
- **Werewolf Howl** — werewolf-hero check: it WAS a primitive stack.
  Replaced with the CraftPix wolf (royalty-free, textured). The howl
  head-tilt is now a whole-body rear-back tilt on a pivot at body height.

## Cheap wow (shipped because a build went out anyway)

- **Sky Traffic: engine roar by distance** — the nearest aircraft now rumbles
  on a looping positional player (new 4 s seamless procedural jet-roar loop,
  `assets/audio/sfx/engine_roar.wav`); volume and pitch follow its real
  ADS-B distance. Silent when the sky is empty.

## Cull check

Touched games audited against the permanent bar — none are boring; no cuts
this cycle. 75 experiences remain.

## Notes

- Per-asset licenses verified; ATTRIBUTION.md updated (Quaternius CC0,
  CraftPix royalty-free).
- Quest 3 perf: each swapped model is 1 draw call; no new lights; APK
  budget respected.
- Not Quest-tested — wade's headset pass is the gate, as always.
