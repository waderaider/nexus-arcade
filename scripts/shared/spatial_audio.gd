class_name SpatialAudio
extends Node3D
## SpatialAudio — shared "spatial 3D audio" plumbing for NEXUS ARCADE and
## MARIGOLD (v0.11.0 / v0.7.0). wade's permanent rule: every game gets
## Dolby-Atmos-STYLE spatial audio — sounds positioned as objects in 3D
## space. We ship the EFFECT, never the trademark: in-game and in copy it
## is always called "spatial 3D audio".
##
## VERIFIED PATH (2026-10-12, against the real binaries):
## - Meta XR Audio is NOT exposed by godot_openxr_vendors v5.1.0 (binary
##   strings checked on the arm64 + x86_64 release .so — zero XR-Audio
##   symbols). A native Meta XR Audio GDExtension is a possible future
##   upgrade; it is NOT this pass.
## - Godot 4.7.2's built-in 3D audio server IS the real path, property by
##   property: AudioStreamPlayer3D attenuation models, max_distance,
##   per-voice attenuation_filter_cutoff_hz/db (occlusion muffle),
##   doppler_tracking, area_mask; Area3D reverb_bus_* zones;
##   AudioServer runtime bus creation + AudioEffectReverb. No
##   AudioOccluder class exists — occlusion is a manual raycast.
## - Identical engine code runs on Quest (Android) and Windows, so the PC
##   builds get the SAME spatial mix with zero separate implementation.
##
## USAGE — no autoload registration needed. Drop ONE SpatialAudio node into
## a game/chapter scene (top level), then one-liners from anywhere:
##   SpatialAudio.play("duel_clash", hit_pos)                 # occluded+reverbed
##   SpatialAudio.play("traffic_pass", jet_pos, 1.0, 0.0, {"doppler": true})
##   SpatialAudio.play_stream(voice_clip, mouth_pos)          # preloaded stream
##   SpatialAudio.music_at("baile", stage_pos) -> player      # world-anchored
##   SpatialAudio.reverb_zone("cave", center, 8.0, SpatialAudio.CAVE)
##   SpatialAudio.clear_zones()
##
## The static `instance` is the scene's node; calls before _ready are
## safe no-ops. Per-project stream naming is handled by `stream_resolver`
## (NEXUS default: res://assets/audio/sfx/<name>.wav).

## Reverb presets: [room_size, damping, wet, predelay_msec].
const CAVE := [0.95, 0.20, 0.60, 40.0]
const CATHEDRAL := [1.00, 0.15, 0.65, 60.0]
const ARENA := [0.85, 0.40, 0.45, 30.0]
const HALL := [0.70, 0.55, 0.35, 20.0]
const ROOM := [0.45, 0.60, 0.25, 12.0]
const FOREST := [0.50, 0.70, 0.20, 10.0]
const STREET := [0.35, 0.80, 0.15, 5.0]

const POOL_SIZE := 8          # positional one-shot voices (round-robin steal)
const CLEAN_CUTOFF_HZ := 20000.0   # attenuation lowpass when path is clear
const OCCLUDED_CUTOFF_HZ := 800.0  # muffled through walls
const OCCLUDED_CUT_DB := -10.0     # extra volume drop when occluded

static var instance: SpatialAudio = null
## Resolve an SFX name to a stream. Override per project if naming differs.
static var stream_resolver: Callable = func(sfx_name: String) -> AudioStream:
	if ResourceLoader.exists("res://assets/audio/sfx/" + sfx_name + ".wav"):
		return load("res://assets/audio/sfx/" + sfx_name + ".wav") as AudioStream
	return null
## Physics layers the occlusion raycast tests (default: world geometry).
static var occlusion_mask := 1
static var occlusion_enabled := true
## Test/debug: the voice (or music) player used by the last static call.
static var last_player: AudioStreamPlayer3D = null

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_idx := 0
var _zones: Array[Area3D] = []
var _music_players: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	instance = self
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "SpatialVoice%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.unit_size = 4.0
		p.max_distance = 40.0
		p.area_mask = 1          # lets Area3D reverb zones on layer 1 apply
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool.append(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## One-line positional one-shot. Handles occlusion raycast + reverb zones
## automatically. opts: {"occlude": bool, "doppler": bool, "max_distance": float}
static func play(sfx_name: String, pos: Vector3, pitch := 1.0,
		volume_db := 0.0, opts: Dictionary = {}) -> void:
	if instance == null:
		return
	var stream: AudioStream = stream_resolver.call(sfx_name) as AudioStream
	if stream == null:
		push_warning("[SpatialAudio] unknown SFX '%s'" % sfx_name)
		return
	instance._play_voice(stream, pos, pitch, volume_db, opts)


## Positional one-shot from an already-loaded stream (voice clips, etc).
static func play_stream(stream: AudioStream, pos: Vector3, pitch := 1.0,
		volume_db := 0.0, opts: Dictionary = {}) -> void:
	if instance == null or stream == null:
		return
	instance._play_voice(stream, pos, pitch, volume_db, opts)


## World-anchored music bed (e.g. the banda stage in ch5, a jukebox, the
## golf clubhouse speakers). Gentle falloff: full in the room, fading
## across a plaza. Returns the player — keep it and call stop_music(p).
static func music_at(stream: AudioStream, pos: Vector3,
		volume_db := -6.0) -> AudioStreamPlayer3D:
	if instance == null or stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 30.0
	p.max_distance = 60.0
	p.area_mask = 1
	p.volume_db = volume_db
	instance.add_child(p)  # inside the tree before setting global_position
	p.global_position = pos
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w = w.duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.get_data().size() / 2
			stream = w
	p.stream = stream
	instance._music_players.append(p)
	last_player = p
	p.play()
	return p


## Stop a world-anchored music player started by music_at().
static func stop_music(p: AudioStreamPlayer3D) -> void:
	if instance == null or p == null:
		return
	instance._music_players.erase(p)
	p.queue_free()


## Create a reverb zone: sounds inside the sphere pick up the preset's
## room character via the engine's Area3D reverb path. Safe to call
## repeatedly — same name replaces the old zone.
static func reverb_zone(zone_name: String, center: Vector3, radius: float,
		preset: Array) -> void:
	if instance == null:
		return
	instance._make_zone(zone_name, center, radius, preset)


## Remove all reverb zones (call on scene exit).
static func clear_zones() -> void:
	if instance == null:
		return
	for z in instance._zones:
		if is_instance_valid(z):
			z.queue_free()
	instance._zones.clear()


func _play_voice(stream: AudioStream, pos: Vector3, pitch: float,
		volume_db: float, opts: Dictionary) -> void:
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = stream
	p.pitch_scale = pitch
	p.global_position = pos
	if opts.get("max_distance", 0.0) as float > 0.0:
		p.max_distance = opts["max_distance"]
	else:
		p.max_distance = 40.0
	if opts.get("doppler", false) as bool:
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	else:
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	# Occlusion: raycast listener -> source; a wall between them muffles.
	var occluded := false
	if occlusion_enabled and opts.get("occlude", true) as bool:
		occluded = _is_occluded(pos)
	if occluded:
		p.attenuation_filter_cutoff_hz = OCCLUDED_CUTOFF_HZ
		p.volume_db = volume_db + OCCLUDED_CUT_DB
	else:
		p.attenuation_filter_cutoff_hz = CLEAN_CUTOFF_HZ
		p.volume_db = volume_db
	last_player = p
	p.play()


## True when solid geometry blocks the straight line listener -> pos.
func _is_occluded(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var from := cam.global_position
	if from.distance_to(pos) < 0.5:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, pos, occlusion_mask)
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


func _make_zone(zone_name: String, center: Vector3, radius: float,
		preset: Array) -> void:
	for z in _zones:
		if is_instance_valid(z) and z.name == "ReverbZone_" + zone_name:
			z.queue_free()
			_zones.erase(z)
	var bus_name := "SpatialReverb_" + zone_name
	var bus_idx := AudioServer.bus_count
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, bus_name)
		var rev := AudioEffectReverb.new()
		rev.room_size = preset[0]
		rev.damping = preset[1]
		rev.wet = preset[2]
		rev.predelay_msec = preset[3]
		rev.spread = 1.0
		rev.dry = 0.0  # zone bus carries the wet tail only; dry stays on Master
		AudioServer.add_bus_effect(bus_idx, rev)
		AudioServer.set_bus_send(bus_idx, "Master")
	var area := Area3D.new()
	area.name = "ReverbZone_" + zone_name
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	area.collision_layer = 1
	area.collision_mask = 0
	area.monitoring = true
	area.reverb_bus_enabled = true
	area.reverb_bus_name = bus_name
	area.reverb_bus_amount = 0.8
	area.reverb_bus_uniformity = 0.6
	add_child(area)  # inside the tree before setting global_position
	area.global_position = center
	_zones.append(area)
