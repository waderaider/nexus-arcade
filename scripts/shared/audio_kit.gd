## AudioKit.gd - procedural audio autoload for NEXUS ARCADE v0.8.0.
## Every SFX and music loop is synthesized at build time by tools/gen_audio.py
## (numpy/scipy; zero licensed assets, zero legal risk). SFX are preloaded once
## into a small pool; music loops stream from disk one at a time so they never
## all sit in RAM. Volumes persist in user://nexus_settings.cfg [audio].
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SETTINGS_PATH := "user://nexus_settings.cfg"
const POOL_SIZE := 8
const DUCK_DB := 5.0      # how far the music dips during an SFX burst
const DUCK_WINDOW := 0.6  # >=3 SFX inside this window counts as a burst
const DUCK_HOLD := 0.6    # seconds to hold the duck after a burst

const SFX_NAMES: Array[String] = [
	"ui_click", "ui_hover", "ui_back", "success", "fail", "pop", "coin",
	"whoosh", "explosion", "splash", "laser", "thud", "sparkle",
	"countdown", "whistle", "buzzer", "powerup", "jump", "land", "shoot",
	"hit", "heal", "unlock", "door", "chest", "bubble", "zap", "fanfare",
	"notify", "error",
]

const GENRES: Array[String] = [
	"chiptune", "horror", "tropical", "western", "underwater", "epic",
	"lofi", "carnival", "scifi", "folk", "menu_theme",
]

## Per-game music genre, keyed by scene file stem (source of truth: the
## CAT_GAMES / CAT_UTILITIES / CAT_CREATE / CAT_THEMES lists in hub.gd).
const GENRE_FOR_SCENE := {
	# -- CAT_GAMES --
	"golf": "folk", "swarm": "scifi", "duel": "epic",
	"beat-blades": "chiptune", "portal-ball": "scifi",
	"laser-tag-ar": "scifi", "gravity-pong": "chiptune",
	"ar-bowling": "folk", "time-pilot": "scifi", "room-racer": "scifi",
	"ar-defender": "scifi", "sky-defender": "epic", "drone-racer": "scifi",
	"tower-topple": "folk", "spell-duel": "epic", "rhythm-boxer": "chiptune",
	"marble-run": "lofi", "ar-darts": "carnival", "zero-g-hoops": "scifi",
	"ar-fishing": "underwater", "mirror-maze": "scifi",
	"gravity-glove": "scifi", "time-freeze": "scifi", "portal-maze": "scifi",
	"air-drums": "chiptune", "shadow-puppet": "carnival",
	"holo-chess": "lofi", "starforge": "epic", "holo-dungeon": "horror",
	"ar-escape-room": "horror", "ar-billiards": "lofi",
	"holo_chef": "folk", "dragon_ranch": "epic",
	"wizard_academy": "epic", "holo_farm": "folk", "mech_pilot": "scifi",
	"deep_dive": "underwater", "ar_detective": "lofi",
	"sky_pirates": "tropical", "monster_lab": "horror", "myth_zoo": "epic",
	"qr_hunt": "western",
	# -- CAT_UTILITIES --
	"ar-measure": "lofi", "holo-notes": "lofi", "star-map": "scifi",
	"sky_traffic": "lofi", "eye_spy": "lofi", "plant_doctor": "folk",
	"ar-workout": "chiptune", "holo-pets": "folk", "mind-palace": "lofi",
	"ar-dj": "lofi", "familiar": "epic", "couch_morph": "scifi",
	# -- CAT_CREATE --
	"portal-painter": "lofi", "light-painter": "chiptune",
	"holo-piano": "lofi", "holo-theremin": "scifi",
	"graffiti-wall": "chiptune", "ar-karaoke": "carnival",
	"sand-shaper": "lofi", "clay-shaper": "folk", "sketch_3d": "lofi",
	"holo-garden": "folk", "zero-g-sandbox": "scifi",
	"holo-aquarium": "underwater",
	# -- CAT_THEMES (halloween) --
	"hw_pumpkin_smash": "horror", "hw_ghost_catch": "horror",
	"hw_candy_run": "horror", "hw_haunted_maze": "horror",
	"hw_web_slingshot": "horror", "hw_potion_mix": "horror",
	"hw_zombie_defense": "horror", "hw_bat_catch": "horror",
	"hw_door_dash": "horror", "hw_skeleton_dance": "horror",
	"hw_eyeball_pong": "horror", "hw_broom_flight": "horror",
	"hw_monster_mash": "horror", "hw_candy_stack": "horror",
	"hw_mummy_wrap": "horror", "hw_bat_dodge": "horror",
	"hw_pumpkin_carve": "horror", "hw_portrait_gallery": "horror",
	"hw_spider_catch": "horror", "hw_werewolf_howl": "horror",
	"hw_grave_digger": "horror", "hw_hayride_shooter": "horror",
	"hw_apple_bobbing": "horror", "hw_phantom_piano": "horror",
	"hw_goblin_archery": "horror", "hw_mirror_maze": "horror",
	"hw_pumpkin_bowling": "horror", "hw_hat_toss": "horror",
	"hw_monster_feed": "horror", "hw_midnight_survival": "horror",
}

var sfx_volume := 0.8
var music_volume := 0.8
var sfx_enabled := true
var music_enabled := true

var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _music: AudioStreamPlayer
var _current_genre := ""
var _sfx_times: Array[float] = []
var _duck_until := 0.0
var _duck_level := 0.0


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "AudioKitMusic"
	add_child(_music)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "AudioKitSFX%d" % i
		add_child(p)
		_pool.append(p)
	_load_settings()
	for n in SFX_NAMES:
		var path := SFX_DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_sfx[n] = load(path)
		else:
			push_warning("AudioKit: missing SFX " + path)


func _process(_delta: float) -> void:
	if _music == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var target := DUCK_DB if now < _duck_until else 0.0
	_duck_level = lerpf(_duck_level, target, 0.25)
	_music.volume_db = _vol_db(music_volume) - _duck_level


## Play a named SFX (see SFX_NAMES). Pitch and extra dB are optional.
func play_sfx(sfx_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not sfx_enabled:
		return
	if not _sfx.has(sfx_name):
		push_warning("AudioKit: unknown SFX '" + sfx_name + "'")
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = _sfx[sfx_name]
	p.pitch_scale = pitch
	p.volume_db = _vol_db(sfx_volume) + volume_db
	p.play()
	_note_sfx_burst()


func _note_sfx_burst() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_sfx_times.append(now)
	while not _sfx_times.is_empty() and now - _sfx_times[0] > DUCK_WINDOW:
		_sfx_times.pop_front()
	if _sfx_times.size() >= 3:
		_duck_until = now + DUCK_HOLD


## Play a music genre loop (see GENRES). No-op if already playing it.
func play_music(genre: String) -> void:
	if not genre in GENRES:
		push_warning("AudioKit: unknown genre '" + genre + "'")
		return
	if genre == _current_genre and _music.playing:
		return
	_current_genre = genre
	if not music_enabled:
		return
	var path := MUSIC_DIR + genre + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("AudioKit: missing music " + path)
		return
	_music.stream = load(path)
	_music.volume_db = _vol_db(music_volume)
	_music.play()


func stop_music() -> void:
	_music.stop()
	_current_genre = ""


## Convenience: pick the mapped genre from a scene file stem ("holo_chef").
func play_music_for_scene(scene_key: String) -> void:
	play_music(GENRE_FOR_SCENE.get(scene_key, "lofi"))


func genre_for_scene(scene_key: String) -> String:
	return GENRE_FOR_SCENE.get(scene_key, "lofi")


func current_genre() -> String:
	return _current_genre


# -- volume API (persisted; wire these to the settings row) --
func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	if _music.playing:
		_music.volume_db = _vol_db(music_volume) - _duck_level
	_save_settings()


func set_sfx_enabled(b: bool) -> void:
	sfx_enabled = b
	_save_settings()


func set_music_enabled(b: bool) -> void:
	music_enabled = b
	if not b:
		_music.stop()
	elif _music.stream != null:
		_music.volume_db = _vol_db(music_volume)
		_music.play()
	_save_settings()


func get_sfx_volume() -> float:
	return sfx_volume


func get_music_volume() -> float:
	return music_volume


func is_sfx_enabled() -> bool:
	return sfx_enabled


func is_music_enabled() -> bool:
	return music_enabled


func _vol_db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", 0.8)), 0.0, 1.0)
	sfx_enabled = bool(cfg.get_value("audio", "sfx_enabled", true))
	music_enabled = bool(cfg.get_value("audio", "music_enabled", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep other sections (e.g. [room]) intact
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.save(SETTINGS_PATH)
