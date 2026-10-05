## CreatureBrain.gd - the creature's mind: state machine
## (Idle / Curious / Playful / Sleepy), bond XP + evolution stages, and
## learned interaction preferences persisted via a JSON save file.
## Ports CreatureBrain.cs.
extends Node3D
class_name CreatureBrain

enum BrainState { IDLE, CURIOUS, PLAYFUL, SLEEPY }
enum EvoStage { EGG, SPROUT, WISP, GUARDIAN }

signal bond_changed(xp: float, threshold: float)
signal evolved(stage: int)
signal interaction(message: String)

var body: CreatureBody
var toy: ToyBall
var gestures: GestureSensor

var state: int = BrainState.IDLE
var evo_stage: int = EvoStage.EGG
var bond_xp := 0.0
var preferences: Dictionary = {}

const SLEEP_AFTER_SECONDS := 45.0
const SAVE_PATH := "user://familiar_save.json"

# Egg 0 -> Sprout 30 -> Wisp 80 -> Guardian 160
const THRESHOLDS: Array[float] = [0.0, 30.0, 80.0, 160.0]

var _home := Vector3.ZERO
var _state_timer := 0.0
var _wander_timer := 0.0
var _last_interaction := -999.0
var _wander_target := Vector3.ZERO
var _has_wander_target := false

func _ready() -> void:
	_home = global_position
	load_data()
	_apply_stage_visuals()

func setup(p_body: CreatureBody, p_toy: ToyBall, p_gestures: GestureSensor) -> void:
	body = p_body
	toy = p_toy
	gestures = p_gestures
	_home = global_position
	load_data()
	_apply_stage_visuals()
	if gestures and gestures.has_signal("gesture"):
		gestures.gesture.connect(_on_gesture)

func next_threshold() -> float:
	return THRESHOLDS[mini(evo_stage + 1, THRESHOLDS.size() - 1)]

func _process(delta: float) -> void:
	if body == null:
		return
	_state_timer += delta
	match state:
		BrainState.SLEEPY:
			body.set_sleeping(true)
		BrainState.IDLE:
			body.set_sleeping(false)
			_update_idle(delta)
			if Time.get_ticks_msec() / 1000.0 - _last_interaction > SLEEP_AFTER_SECONDS:
				_set_state(BrainState.SLEEPY)
		BrainState.CURIOUS:
			body.set_sleeping(false)
			_update_curious(delta)
		BrainState.PLAYFUL:
			body.set_sleeping(false)
			_update_playful(delta)

# ---------------------------------------------------------------- state logic

func _update_idle(delta: float) -> void:
	_wander_timer -= delta
	if not _has_wander_target and _wander_timer <= 0.0:
		_wander_target = _home + Vector3(randf_range(-0.6, 0.6), 0.0,
			randf_range(-0.6, 0.6))
		_has_wander_target = true
		_wander_timer = randf_range(3.0, 6.0)
	if _has_wander_target:
		body.hop_to(_wander_target)
		var a := Vector2(global_position.x, global_position.z)
		var b := Vector2(_wander_target.x, _wander_target.z)
		if a.distance_to(b) < 0.15:
			_has_wander_target = false

func _update_curious(_delta: float) -> void:
	var hand := _nearest_hand_tip()
	body.hop_to(hand)
	body.set_mood(CreatureBody.Mood.CURIOUS)
	var d := global_position.distance_to(hand)
	if d < 0.45 or _state_timer > 14.0:
		_set_state(BrainState.IDLE)

func _update_playful(_delta: float) -> void:
	if toy == null or not is_instance_valid(toy):
		_set_state(BrainState.IDLE)
		return
	body.hop_to(toy.global_position)
	body.set_mood(CreatureBody.Mood.PLAYFUL)
	var stay := 10.0 + _preference("play") * 6.0
	if _state_timer > stay or global_position.distance_to(toy.global_position) > 4.0:
		_set_state(BrainState.IDLE)

func _set_state(s: int) -> void:
	state = s
	_state_timer = 0.0
	_has_wander_target = false

# ------------------------------------------------------------- interactions

func react_to_gesture(gesture: String) -> void:
	if body == null:
		return
	_touch()
	match gesture:
		"pet":
			if state == BrainState.SLEEPY:
				_wake()
			body.nuzzle()
			body.set_mood(CreatureBody.Mood.HAPPY)
			_add_bond(3.0, "pet")
		"feed":
			if state == BrainState.SLEEPY:
				_wake()
			body.eat()
			body.set_mood(CreatureBody.Mood.HAPPY)
			_add_bond(4.0, "feed")
		"wave":
			if state == BrainState.SLEEPY:
				_wake()
			else:
				_set_state(BrainState.CURIOUS)
			body.set_mood(CreatureBody.Mood.CURIOUS)
			_add_bond(1.0, "wave")
		"point":
			body.look_at_point(_nearest_hand_tip())
			body.set_mood(CreatureBody.Mood.CURIOUS)
			_add_bond(0.5, "point")
		"thumbsup":
			if state == BrainState.SLEEPY:
				_wake()
			body.happy_bounce()
			_add_bond(2.0, "thumbsup")
		"loudpinch":
			if state == BrainState.SLEEPY:
				_wake()

func react_to_voice(phrase: String) -> void:
	if body == null:
		return
	_touch()
	match phrase:
		"come here":
			_wake()
			_set_state(BrainState.CURIOUS)
			_add_bond(1.0, "come")
		"dance":
			_wake()
			body.dance()
			body.set_mood(CreatureBody.Mood.PLAYFUL)
			_set_state(BrainState.PLAYFUL)
			_add_bond(2.0, "dance")
		"spin":
			_wake()
			body.spin()
			_add_bond(1.0, "spin")
		"sleep":
			_set_state(BrainState.SLEEPY)
			body.set_mood(CreatureBody.Mood.SLEEPY)
		"wake up":
			_wake()
			body.set_mood(CreatureBody.Mood.HAPPY)

func _wake() -> void:
	if state == BrainState.SLEEPY:
		_set_state(BrainState.IDLE)
		body.set_sleeping(false)
		body.happy_bounce()

func _touch() -> void:
	_last_interaction = Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- bond / xp

func _add_bond(amount: float, interaction_name: String) -> void:
	bond_xp += amount
	_bump_preference(interaction_name, amount * 0.25)
	_evolve_check()
	save_data()
	bond_changed.emit(bond_xp, next_threshold())
	interaction.emit("[Familiar] Bond +%.0f (%s)  xp=%.0f" % [amount, interaction_name, bond_xp])

func _evolve_check() -> void:
	var next := evo_stage
	for i in range(THRESHOLDS.size() - 1, -1, -1):
		if bond_xp >= THRESHOLDS[i]:
			next = i
			break
	if next != evo_stage:
		evo_stage = next
		_apply_stage_visuals()
		body.celebrate_evolution()
		save_data()
		evolved.emit(evo_stage)
		var names := ["Egg", "Sprout", "Wisp", "Guardian"]
		interaction.emit("[Familiar] Evolved into %s!" % names[mini(evo_stage, 3)])

func _apply_stage_visuals() -> void:
	if body:
		body.set_stage(evo_stage)  # enums share the same integer order

# ------------------------------------------------------------- preferences

func _preference(key: String) -> float:
	return float(preferences.get(key, 0.0))

func _bump_preference(key: String, amount: float) -> void:
	if key.is_empty():
		return
	preferences[key] = _preference(key) + amount

func favorite_interaction() -> String:
	var best := "pet"
	var best_v := -1.0
	for k in preferences:
		var v := float(preferences[k])
		if v > best_v:
			best_v = v
			best = k
	return best

# ---------------------------------------------------------------- persistence

func save_data() -> void:
	var data := {
		"xp": bond_xp,
		"stage": evo_stage,
		"prefs": preferences,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	bond_xp = float(parsed.get("xp", 0.0))
	evo_stage = clampi(int(parsed.get("stage", 0)), 0, 3)
	var prefs = parsed.get("prefs", {})
	if typeof(prefs) == TYPE_DICTIONARY:
		preferences = prefs

# ---------------------------------------------------------------- helpers

func _nearest_hand_tip() -> Vector3:
	if gestures and gestures.has_method("get_best_hand_tip"):
		var tip: Vector3 = gestures.get_best_hand_tip()
		if tip != Vector3.INF:
			return tip
	return global_position + -global_transform.basis.z

func _on_gesture(gesture: String) -> void:
	react_to_gesture(gesture)
