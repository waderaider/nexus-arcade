# NEXUS ARCADE — CUT LIST (v0.9.0)

**Date:** 2026-10-08 · **Rule:** wade's permanent quality bar — any game that is boring
(not amazing, not groundbreaking) is REMOVED outright. Not merged, not parked.
Scored all 97 hub entries against "would this wow someone at a demo booth?" using
TECH_DEMO_PLAN.md weakest-15, DESIGN_VISION.md verdicts, and direct code reads.

**Cut:** 22 games · **Survivors:** 75 games

## CUT GAMES (22) — id, title, reason

| id | title | reason |
|---|---|---|
| portal-ball | Portal Ball | Thin Pong variant; weakest-15, no hook. |
| gravity-pong | Gravity Pong | Pong needs a twist to earn its slot; weakest-15. |
| ar-bowling | AR Bowling | Competent but flat; weakest-15. |
| tower-topple | Tower Topple | AR Jenga — thin, no physics drama; weakest-15. |
| zero-g-hoops | Zero-G Hoops | Throw-ball-at-hoop; zero-G feel never delivered; weakest-15. |
| holo-chess | Holo Chess | Chess isn't a demo-booth wow; weakest-15. |
| portal-maze | Portal Maze | No reason to exist beyond the maze; weakest-15. |
| time-pilot | Time Pilot | Unclear hook; weakest-15. |
| portal-painter | Portal Painter | Redundant with Light Painter (the stronger twin survives). |
| familiar | Familiar | Unclear identity, 0 RoomKit usage; weakest-15 ("define or cut"). |
| holo-notes | Holo Notes | Low-wow utility; weakest-15. |
| mind-palace | Mind Palace | Thin mnemonic utility; weakest-15. |
| ar-workout | AR Workout | Thin target-punching; not amazing. |
| ar-measure | AR Measure | Tape-measure utility; useful but boring, not a wow. |
| hw_ghost_catch | Ghost Catch | Catch-game cull: not amazing on its own merits. |
| hw_bat_catch | Bat Catch | Catch-game cull: not amazing on its own merits. |
| hw_spider_catch | Spider Catch | Catch-game cull: not amazing on its own merits. |
| hw_candy_run | Candy Run | One-note catch loop. |
| hw_door_dash | Door Dash | Thin luck game (knock → candy or trick). |
| hw_eyeball_pong | Eyeball Pong | Pong needs a twist; eyeball is a skin, not a twist. |
| hw_grave_digger | Grave Digger | Thin luck game (dig → candy or skeleton). |
| hw_pumpkin_bowling | Pumpkin Bowling | Competent but flat (same bar as AR Bowling). |

## RECYCLED ASSETS (cut game → survivor)

| from (cut) | files | to (survivor) | note |
|---|---|---|---|
| familiar | stool.glb, chest.glb, plate_small.glb (+textures) | holo-dungeon | KayKit Dungeon CC0; dungeon dressing |
| holo-notes | table_small.glb, chair.glb, candle_lit.glb (+textures) | holo-dungeon | KayKit Dungeon CC0; dungeon dressing |
| mind-palace | shelf_small.glb, coin_stack_medium.glb (+textures) | holo-dungeon | KayKit Dungeon CC0; dungeon dressing |
| hw_candy_run | candle_triple.glb, barrel_small.glb (+textures) | hw_haunted_maze | KayKit Dungeon CC0; maze dressing |
| hw_ghost_catch | skull.gltf + skull.bin | hw_haunted_maze | KayKit Halloween Bits CC0; maze dressing |
| hw_bat_catch | Bat.fbx (Quaternius CC0) | — | deleted; myth_zoo already stages the identical file |

ATTRIBUTION.md updated: Game column re-pointed for all moved files; duplicate
rows for deleted duplicate files removed.

## SCENES PENDING REMOVAL (launcher agent — roster sync)

The .tscn wrappers below are now dangling (their scripts are deleted).
`scenes/halloween/` (avatar.tscn, costume_picker.tscn) is SHARED costume infra — keep.

| scene dir |
|---|
| scenes/portal-ball/ |
| scenes/gravity-pong/ |
| scenes/ar-bowling/ |
| scenes/tower-topple/ |
| scenes/zero-g-hoops/ |
| scenes/holo-chess/ |
| scenes/portal-maze/ |
| scenes/time-pilot/ |
| scenes/portal-painter/ |
| scenes/familiar/ |
| scenes/holo-notes/ |
| scenes/mind-palace/ |
| scenes/ar-workout/ |
| scenes/ar-measure/ |
| scenes/hw_ghost_catch/ |
| scenes/hw_bat_catch/ |
| scenes/hw_spider_catch/ |
| scenes/hw_candy_run/ |
| scenes/hw_door_dash/ |
| scenes/hw_eyeball_pong/ |
| scenes/hw_grave_digger/ |
| scenes/hw_pumpkin_bowling/ |

Also update (launcher/systems agents): hub.gd CAT_* lists, hub_extras.gd
(descriptions/favorites/recents/search), AudioKit GENRE_FOR_SCENE stale keys
(harmless if left).

## ROSTER_SYNC

Machine-readable survivor ids, one per line (75):

air-drums
ar-billiards
ar-darts
ar-defender
ar-dj
ar-escape-room
ar-fishing
ar-karaoke
ar_detective
beat-blades
clay-shaper
couch_morph
deep_dive
dragon_ranch
drone-racer
duel
eye_spy
golf
graffiti-wall
gravity-glove
holo-aquarium
holo-dungeon
holo-garden
holo-pets
holo-piano
holo-theremin
holo_chef
holo_farm
hw_apple_bobbing
hw_bat_dodge
hw_broom_flight
hw_candy_stack
hw_goblin_archery
hw_hat_toss
hw_haunted_maze
hw_hayride_shooter
hw_midnight_survival
hw_mirror_maze
hw_monster_feed
hw_monster_mash
hw_mummy_wrap
hw_phantom_piano
hw_portrait_gallery
hw_potion_mix
hw_pumpkin_carve
hw_pumpkin_smash
hw_skeleton_dance
hw_web_slingshot
hw_werewolf_howl
hw_zombie_defense
laser-tag-ar
light-painter
mano_magica
marble-run
mech_pilot
mirror-maze
monster_lab
myth_zoo
plant_doctor
qr_hunt
rhythm-boxer
room-racer
sand-shaper
shadow-puppet
sketch_3d
sky-defender
sky_pirates
sky_traffic
spell-duel
star-map
starforge
swarm
time-freeze
wizard_academy
zero-g-sandbox

gravity-golf


---

# NEXUS ARCADE — CUT LIST (v0.11.0)

**Date:** 2026-10-12 · **Rule:** wade's permanent quality bar — any game that is boring
(not amazing, not groundbreaking) is REMOVED outright. Not merged, not parked.
Game Designer scored the 75 survivors against telemetry + the bar; the 5 below
failed. Telemetry note: no quit-in-<30s events this cycle, so these are expert
judgment (telemetry overrules opinion when it exists; it doesn't this week).

**Cut:** 5 games · **Survivors:** 70 games (before the 10 new pitches land = 80)

## CUT GAMES (5) — id, title, reason

| id | title | reason |
|---|---|---|
| holo-piano | Holo Piano | Playable 2-octave synth piano, zero game loop — no score, no progression, no goal. Phantom Piano (Simon-style sequences, 3-strikes run) is the stronger twin. |
| star-map | Star Map | Passive planetarium: ~200 emissive stars, click-for-facts. No gameplay loop; a pleasant screensaver, not a game. Fails "fun in the first 60 seconds" (nothing to DO). |
| plant_doctor | Plant Doctor | Well-built (828 lines) and honest, but a utility not a game: photograph plant → pick species card → read care facts. Precedent: AR Measure cut as "useful but boring, not a wow." |
| qr_hunt | QR Treasure Hunt | Requires printing 5 QR codes and hiding them before the first 60 seconds can even start — setup friction kills it. DEMO mode degrades to tapping labeled buttons. The fantasy is better served by Eye Spy AR, which needs no setup. |
| hw_candy_stack | Candy Stack | Pinch falling candy onto a plate for 90s — one-note dexterity loop with no escalation beyond "taller." Precedent: hw_candy_run cut as "one-note catch loop." |

## RECYCLED ASSETS (cut game → survivor)

| from (cut) | files | to (survivor) | note |
|---|---|---|---|
| holo-piano | synth engine (procedural, in-script) | Phantom Piano | stronger twin keeps the piano fantasy; synth code pattern recyclable for future music toys |
| star-map | constellation star data (~200 entries, in-script) | — | data recyclable into future ceiling-sky scenes; no staged assets |
| plant_doctor | shelf_B_large.gltf (+textures), species-card UI pattern | holo-garden | plant shelf becomes garden dressing; card UI pattern recyclable |
| qr_hunt | clue-chain logic (in-script) | eye_spy | Eye Spy AR owns the no-setup treasure-hunt fantasy; chain logic recyclable |
| hw_candy_stack | candy meshes + pinch-stack physics (in-script) | — | recyclable into future dexterity games; no staged assets |

## SCENES PENDING REMOVAL

The .tscn wrappers below are now dangling (removed from the hub list in v0.11.0).
Scripts + scenes left in-tree this cycle (never loaded; zero perf cost) — physical
deletion deferred to the ship pass.

| scene dir |
|---|
| scenes/holo-piano/ |
| scenes/star-map/ |
| scenes/plant_doctor/ |
| scenes/qr_hunt/ |
| scenes/hw_candy_stack/ |

## KEPT BUT ON WATCH (next telemetry digest adjudicates)

- **Portrait Gallery** — real loop + scoring, but thin on VR-native feel (a screen game in a room).
- **Apple Bobbing** — competent but one-note-adjacent; the dunk-timing twist saves it for now.
- **Holo Theremin** — magical toy, zero loop — survives on "demo-booth wonder" like Light Painter, but the thinnest keep.
- **Mano Mágica** — not a game, kept as functional onboarding infra for hand input.
