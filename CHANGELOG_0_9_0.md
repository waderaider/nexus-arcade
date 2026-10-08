# NEXUS ARCADE v0.9.0 — "Everything comes alive"

## Launcher 2.1
- **Key-art cards for every game** — each game now has its own stylized cover
  card (category gradient + game art motif) instead of a text button.
- **Spotlight row** — a featured game rotates daily at the top of the menu;
  tap PLAY to jump straight in.
- **4 category skins** — GAMES glow neon magenta/cyan, UTILITIES go clean
  holographic blue, CREATE gets warm studio tones, THEMES go Halloween
  purple/pumpkin. Tabs, cards, and launch transitions all follow the skin.
- New utility: **Mano Mágica** — a 60-second guided tour that teaches your
  hands pinch, grab, throw, sculpt, conduct, and pet with perfect haptic +
  audio feedback. The onboarding every other game assumes.
- New: **Depth FX toggle** in the menu footer — virtual objects can now hide
  *behind* your real couch, walls, and hands (environment-depth occlusion).

## Every game now has sound, juice, and an exit — automatically
- **Music in every game**: each game's genre soundtrack now actually plays on
  launch (previously mapped but silent). Intensity layers: explore → tense →
  combat mixing follows the action.
- **3-second title cards**: every launch opens with the game's name, its
  description, and a haptic fanfare. Pull the trigger to skip.
- **Pause menu everywhere (ship-blocker fix)**: the controller **menu button**
  (or Esc) now pauses ANY game — Resume, Restart Game, Quit to Hub. A small
  floating pause button sits top-right of your view in every game, and it all
  works with controller laser, hand pinch, or gaze dwell.
- **Game feel pass**: hit-stop freezes on big impacts, pickups squash-and-
  stretch, scores pop, interactive objects glow so you know what to touch.

## Your room reacts
- **Passthrough color grading**: Halloween games tint your real room haunted
  green, underwater games go deep teal — the room itself gets art direction.
- **Passthrough FX**: dragon fire now scorches your real walls (fading burn
  marks), splashes ripple across your real floor, glowing portals anchor to
  walls, and creatures can climb out from behind your furniture.
- **Controller skins**: in controller games your real controllers show 1:1
  with game-styled grips — wands, blasters, racing wheels, paintbrushes,
  swords, and more. A **Controls** legend shows on game start (dismiss with
  trigger) and re-opens from the pause menu.

## Hands are first-class
- Grab/throw physics with real release velocity, two-hand pinch-to-scale in
  creative apps, and simultaneous hands+controllers (grab a controller
  mid-hand-game — it just works).
- **Body tracking**: Skeleton Dance can now mirror your real body (falls back
  to hands when tracking is unavailable).

## Under the hood
- Morph-skin lights pooled (4 max) — whole-room transforms stay in perf budget.
- Export targets Android SDK 34 (Meta's required range for immersive apps).
- New CI check warns on untextured default-gray meshes (goes strict after the
  art pass).

## Games removed in v0.9.0
wade's permanent quality bar: boring games get cut outright, not merged or
parked. 22 games didn't earn their slot; their useful props were recycled
into surviving games (dungeon/Halloween dressing).

- Portal Ball — thin Pong variant, no hook
- Gravity Pong — Pong needs a twist to earn its slot
- AR Bowling — competent but flat
- Tower Topple — AR Jenga; thin, no physics drama
- Zero-G Hoops — throw-ball-at-hoop; zero-G feel never delivered
- Holo Chess — chess isn't a demo-booth wow
- Portal Maze — no reason to exist beyond the maze
- Time Pilot — unclear hook
- Portal Painter — redundant with Light Painter (the stronger twin survives)
- Familiar — unclear identity, no room integration
- Holo Notes — low-wow utility
- Mind Palace — thin mnemonic utility
- AR Workout — thin target-punching; not amazing
- AR Measure — tape-measure utility; useful but boring, not a wow
- Ghost Catch — catch-game cull: not amazing on its own merits
- Bat Catch — catch-game cull: not amazing on its own merits
- Spider Catch — catch-game cull: not amazing on its own merits
- Candy Run — one-note catch loop
- Door Dash — thin luck game (knock → candy or trick)
- Eyeball Pong — an eyeball skin is not a gameplay twist
- Grave Digger — thin luck game (dig → candy or skeleton)
- Pumpkin Bowling — competent but flat (same bar as AR Bowling)

**75 experiences remain** (down from 97), every one of them with working
music, title card, pause/exit, and controller skins.

---
*As always: fully offline, no accounts, no ads. Quest 3 only. Never
claimed Quest-tested by anyone but wade's headset.*
