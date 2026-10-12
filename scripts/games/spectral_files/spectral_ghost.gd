## SpectralGhost.gd - the entity for SPECTRAL FILES.
## One of 6 ghost types, each with a 3-evidence signature and distinct
## behavior. Haunts your real furniture, manifests, throws your objects,
## flickers your lights — and hunts when angered.
class_name SpectralGhost
extends Node3D

signal event_throw
signal event_flicker
signal caught_player
signal manifest_changed(visible: bool)

const MODEL_DIR := "res://assets/models/spectral/"

const TYPES := {
	"Wraith": {"evidence": ["EMF5", "SPIRIT", "FLICKER"], "model": "sheet_ghost.glb",
		"speed": 1.7, "throw_rate": 0.15, "manifest_rate": 0.55, "shy": false, "hunt_speed": 1.6},
	"Poltergeist": {"evidence": ["THROW", "EMF5", "PHOTO"], "model": "ghost_slime.glb",
		"speed": 1.0, "throw_rate": 1.0, "manifest_rate": 0.45, "shy": false, "hunt_speed": 1.5},
	"Shade": {"evidence": ["FREEZE", "PHOTO", "FLICKER"], "model": "ghost_skeleton.glb",
		"speed": 0.9, "throw_rate": 0.2, "manifest_rate": 0.4, "shy": true, "hunt_speed": 1.4},
	"Revenant": {"evidence": ["FREEZE", "EMF5", "THROW"], "model": "ghost_dragon.glb",
		"speed": 0.8, "throw_rate": 0.5, "manifest_rate": 0.4, "shy": false, "hunt_speed": 2.3},
	"Phantom": {"evidence": ["PHOTO", "SPIRIT", "FREEZE"], "model": "sheet_ghost.glb",
		"speed": 1.2, "throw_rate": 0.3, "manifest_rate": 0.95, "shy": false, "hunt_speed": 1.7},
	"Banshee": {"evidence": ["SPIRIT", "FLICKER", "THROW"], "model": "ghost_bat.glb",
		"speed": 1.4, "throw_rate": 0.6, "manifest_rate": 0.6, "shy": false, "hunt_speed": 1.9, "scream": true},
}

var ghost_type := "Wraith"
var cfg := {}
var haunts: Array[Vector3] = []
var state := "lurk"  # lurk | manifest | hunt
var anger := 0.0

var _model: Node3D
var _haunt_idx := 0
var _move_t := 0.0
var _move_from := Vector3.ZERO
var _move_to := Vector3.ZERO
var _move_dur := 1.0
var _manifest_t := 0.0
var _manifest_cd := 8.0
var _throw_cd := 12.0
var _flicker_cd := 20.0
var _hunt_t := 0.0
var _bob := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_type: String, p_haunts: Array[Vector3], start: Vector3) -> void:
	ghost_type = p_type
	cfg = TYPES[p_type]
	haunts = p_haunts
	_rng.randomize()
	_load_model()
	global_position = start
	_move_to = start
	visible = false


func _load_model() -> void:
	var ps: PackedScene = load(MODEL_DIR + str(cfg["model"])) as PackedScene
	if ps == null:
		return
	_model = ps.instantiate() as Node3D
	add_child(_model)
	# Normalize to ~1.6m tall.
	var box := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m: AABB = (mi as MeshInstance3D).get_aabb()
		var lt: Transform3D = (mi as MeshInstance3D).transform
		for cx in [m.position.x, m.position.x + m.size.x]:
			for cy in [m.position.y, m.position.y + m.size.y]:
				for cz in [m.position.z, m.position.z + m.size.z]:
					var c: Vector3 = lt * Vector3(cx, cy, cz)
					if first:
						box = AABB(c, Vector3.ZERO)
						first = false
					else:
						box = box.expand(c)
	if box.size.y > 0.01:
		var s := 1.6 / box.size.y
		_model.scale = Vector3(s, s, s)
		_model.position.y = -box.position.y * s


func evidence() -> Array:
	return cfg["evidence"]


func is_manifesting() -> bool:
	return state == "manifest" or state == "hunt"


func start_hunt() -> void:
	state = "hunt"
	_hunt_t = 0.0
	visible = true
	manifest_changed.emit(true)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("sting")
	Haptics.play_sequence("heartbeat")


func calm() -> void:
	state = "lurk"
	visible = false
	manifest_changed.emit(false)
	anger = 0.0
	_manifest_cd = 10.0


func tick(dt: float, player_pos: Vector3) -> void:
	_bob += dt
	match state:
		"lurk":
			_tick_lurk(dt, player_pos)
		"manifest":
			_tick_manifest(dt, player_pos)
		"hunt":
			_tick_hunt(dt, player_pos)
	_face_player(player_pos)


## Animator: telegraph — true in the 1s before a throw (shelf tremble).
func throw_soon() -> bool:
	return state == "lurk" and _throw_cd < 1.0 and _throw_cd > 0.0


func _tick_lurk(dt: float, player_pos: Vector3) -> void:
	_move_t += dt
	if _move_t >= _move_dur:
		_move_t = 0.0
		_move_from = global_position
		_haunt_idx = _rng.randi_range(0, haunts.size() - 1)
		_move_to = haunts[_haunt_idx]
		_move_dur = _rng.randf_range(6.0, 14.0) / float(cfg["speed"])
	var t := clampf(_move_t / maxf(_move_dur, 0.01), 0.0, 1.0)
	global_position = _move_from.lerp(_move_to, t * t * (3.0 - 2.0 * t))
	_manifest_cd -= dt
	_throw_cd -= dt
	_flicker_cd -= dt
	var shy_ok := not bool(cfg.get("shy", false)) or global_position.distance_to(player_pos) > 2.5
	if _manifest_cd <= 0.0 and shy_ok:
		_begin_manifest()
	elif _throw_cd <= 0.0:
		_throw_cd = _rng.randf_range(10.0, 26.0) / maxf(float(cfg["throw_rate"]), 0.05)
		event_throw.emit()
	elif _flicker_cd <= 0.0:
		_flicker_cd = _rng.randf_range(22.0, 45.0)
		event_flicker.emit()


func _begin_manifest() -> void:
	state = "manifest"
	_manifest_t = 0.0
	visible = true
	manifest_changed.emit(true)


func _tick_manifest(dt: float, player_pos: Vector3) -> void:
	_manifest_t += dt
	# Spooky flicker while visible.
	visible = fmod(_manifest_t * 9.0, 1.0) > 0.12
	var dur := 5.5 * float(cfg["manifest_rate"]) + 2.0
	if _manifest_t >= dur:
		state = "lurk"
		visible = false
		manifest_changed.emit(false)
		_manifest_cd = _rng.randf_range(12.0, 26.0) / maxf(float(cfg["manifest_rate"]), 0.2)


func _tick_hunt(dt: float, player_pos: Vector3) -> void:
	_hunt_t += dt
	visible = fmod(_hunt_t * 13.0, 1.0) > 0.08
	var to: Vector3 = player_pos - global_position
	to.y = clampf(to.y, -0.5, 0.5)
	var d := to.length()
	if d > 0.05:
		var spd: float = cfg["hunt_speed"]
		global_position += to.normalized() * minf(spd * dt, d)
	if d < 0.9:
		caught_player.emit()
	# The hunt burns out after 25s if the player evades.
	if _hunt_t > 25.0:
		calm()


func _face_player(player_pos: Vector3) -> void:
	var d: Vector3 = player_pos - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		var target := atan2(-d.x, -d.z)
		rotation.y = lerp_angle(rotation.y, target, 0.08)
	position.y += sin(_bob * 2.2) * 0.0006
