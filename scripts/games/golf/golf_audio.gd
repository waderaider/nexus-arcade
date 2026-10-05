## GolfAudio.gd - SFX bank for Gravity Golf.
## Ports GolfAudio.cs: loads 8 WAVs, one-shot + rolling loop tied to ball speed.
extends Node
class_name GolfAudio

const BASE := "res://assets/audio/golf/"

var _clips := {}
var _one_shot: AudioStreamPlayer3D
var _roll: AudioStreamPlayer3D
var _ball: GolfBall

func _ready() -> void:
	_one_shot = AudioStreamPlayer3D.new()
	_one_shot.max_distance = 12.0
	add_child(_one_shot)

	_roll = AudioStreamPlayer3D.new()
	_roll.max_distance = 8.0
	add_child(_roll)

	for n in ["club_hit", "ball_bounce", "ball_roll", "cup_drop",
			"hole_in_one", "cheer", "ui_click", "portal_whoosh"]:
		var s: AudioStream = load(BASE + n + ".wav")
		if s:
			_clips[n] = s
		else:
			push_warning("[GolfAudio] missing clip: " + BASE + n)

	if _clips.has("ball_roll"):
		_roll.stream = _clips["ball_roll"]
		_roll.play()
		_roll.volume_db = -80.0

func bind_ball(ball: GolfBall) -> void:
	_ball = ball

func play(clip_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _clips.has(clip_name):
		return
	_one_shot.stream = _clips[clip_name]
	_one_shot.volume_db = volume_db
	_one_shot.pitch_scale = pitch
	_one_shot.play()

func strike() -> void:
	play("club_hit")

func bounce(strength: float) -> void:
	play("ball_bounce", linear_to_db(clampf(strength, 0.05, 1.0)), randf_range(0.9, 1.15))

func cup() -> void:
	play("cup_drop")

func portal() -> void:
	play("portal_whoosh", -2.0)

func click() -> void:
	play("ui_click", -3.0)

func fanfare() -> void:
	play("hole_in_one")
	# Slight delay for the cheer so it layers nicely.
	await get_tree().create_timer(0.25).timeout
	play("cheer", -2.0)

func _process(delta: float) -> void:
	if _roll == null or _ball == null or not is_instance_valid(_ball):
		return
	var v: Vector3 = _ball.velocity
	var speed := Vector2(v.x, v.z).length()
	var target_db := -80.0
	if not _ball.is_holed and speed >= 0.15:
		target_db = linear_to_db(clampf(speed / 3.0, 0.0, 1.0) * 0.55)
	_roll.volume_db = lerpf(_roll.volume_db, target_db, minf(1.0, delta * 8.0))
	_roll.pitch_scale = 0.85 + clampf(speed / 4.0, 0.0, 1.0) * 0.4
