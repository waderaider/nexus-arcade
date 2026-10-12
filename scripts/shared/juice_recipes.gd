## JuiceRecipes.gd — v0.11.0 T3 genre recipes for the long tail.
## Each recipe is <=5 lines: paste into a game's _ready() and its key event.
## Uses the real APIs: JuiceFX (autoload), Haptics (static class_name),
## AudioKit (autoload). All Quest-3-cheap.
class_name JuiceRecipes


## Combat (duel-likes): swing whoosh + hit-stop + squash + impact.
static func combat_ready(node: Node, stem: String) -> void:
	AudioKit.register_game_sfx(stem, {"swing": "whoosh", "hit": "hit"})
	AudioKit.set_active_scene(stem)
	AudioKit.set_intensity(2)

static func combat_hit(node: Node3D) -> void:
	AudioKit.play_game_sfx("hit")
	JuiceFX.hit_stop(3)
	JuiceFX.squash_stretch(node)
	Haptics.impact(0.7, "both")


## Wave defense (swarm-likes): spawn + die pop + base alarm.
static func wave_ready(node: Node, stem: String) -> void:
	AudioKit.register_game_sfx(stem, {"die": "die", "alarm": "alarm"})
	AudioKit.set_active_scene(stem)
	AudioKit.set_intensity(1)

static func wave_kill(node: Node3D) -> void:
	AudioKit.play_game_sfx("die")
	JuiceFX.scale_pop(node)
	Haptics.tick()


## Racers: boost whoosh + hit-stop kick + sub-bass.
static func racer_ready(node: Node, stem: String) -> void:
	AudioKit.register_game_sfx(stem, {"boost": "boost", "checkpoint": "checkpoint"})
	AudioKit.set_active_scene(stem)
	AudioKit.set_intensity(2)

static func racer_boost() -> void:
	AudioKit.play_game_sfx("boost")
	JuiceFX.hit_stop(2)
	Haptics.sub_bass(0.5, "both")


## Puzzle/casual: soft confirm + gentle pop (never harsh).
static func casual_ready(node: Node, stem: String) -> void:
	AudioKit.register_game_sfx(stem, {"confirm": "confirm"})
	AudioKit.set_active_scene(stem)
	AudioKit.set_intensity(0)

static func casual_confirm(node: Node3D) -> void:
	AudioKit.play_game_sfx("confirm")
	JuiceFX.scale_pop(node, 1.15)
	Haptics.confirm()
