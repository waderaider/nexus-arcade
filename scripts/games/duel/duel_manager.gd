## DuelManager.gd - match controller for Neon Duel.
## Ports DuelManager.cs + HitDetection.cs: countdown, first-to-3-hits rounds,
## best-of-3 rounds, adaptive difficulty, HUD labels, blade-vs-blade clashes,
## spark bursts, win/loss persistence (user://nexus_arcade.cfg).
## Everything is built procedurally; the duel.tscn root only needs this script.
extends Node3D
class_name DuelManager

const HITS_TO_WIN_ROUND := 3
const ROUNDS_TO_WIN_MATCH := 2
const ARENA_RADIUS := 2.2
const SAVE_PATH := "user://nexus_arcade.cfg"

var player_score := 0
var opponent_score := 0
var player_rounds := 0
var opponent_rounds := 0
var current_round := 1
var wins_total := 0
var losses_total := 0
var is_fighting := false
var match_over := false

var difficulty := 0.5

var _opponent: DuelOpponent
var _player: PlayerBlade
var _head: Node3D
var _arena_ring: MeshInstance3D
var _score_label: Label3D
var _announce_label: Label3D
var _announce_timer := 0.0
var _countdown_active := false

var _player_hit_cooldown := 0.0
var _opp_hit_cooldown := 0.0
var _clash_cooldown := 0.0
var _record_cooldown := 0.0
var _hit_stop_active := false

# v0.11.0: combat pause profile — the floating ❚❚ hides while fighting and
# the menu button needs a 0.45s hold (PauseExit reads these statics).
static var pause_profile := "combat"

# v0.11.0 onboarding: 3-step practice-dummy beat before FIGHT (~20s,
# skippable via trigger). Kills the confusion-driven pause-spam.
var _onboarding := false
var _onboard_step := 0  # 1 = swing, 2 = parry, 3 = rules/FIGHT
var _dummy: DuelOpponent = null
var _onboard_nag_t := 0.0

# v0.11.0 teaching feedback: round-1 hint ribbon + blocked/whiff coaching.
var _hint_label: Label3D = null
var _hint_hit_done := false
var _hint_parry_done := false
var _consec_blocked := 0
var _unanswered_hits := 0

# v0.7.0 RoomKit: real room layout (cached; empty without XR room data).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _ready() -> void:
	_load_records()
	_head = _find_head()
	_add_polish_light_rig()
	_build_arena_ring()
	ARUpgradeKit.apply_anchor(_arena_ring, "duel_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0, 1.0, 0), 2.0)
	_build_hud()
	_player = PlayerBlade.new()
	_player.name = "PlayerBlade"
	add_child(_player)
	_announce("NEON DUEL", 2.0)
	# v0.11.0 Audio Director T1: per-game SFX map (duel_* family).
	var d := "res://assets/audio/sfx/"
	AudioKit.register_game_sfx("duel", {
		"swing": d + "duel_swing.wav", "clash": d + "duel_clash.wav",
		"parry": d + "duel_parry.wav", "block": d + "duel_block.wav",
		"hit": d + "duel_hit.wav",
	})
	AudioKit.set_active_scene("duel")
	AudioKit.set_intensity(0)  # onboarding/menu: calm
	_start_onboarding()  # v0.11.0: 3-step practice beat, then _start_match()
	_apply_room_layout()


## v0.7.0 RoomKit wiring (headless-safe: fallbacks keep the default layout).
func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	_fit_arena_to_room()
	# Re-seat the opponent against the real wall if the fight hasn't started.
	if not is_fighting and not match_over and _opponent != null and is_instance_valid(_opponent):
		_reset_round_positions()
	# v0.7.0 MORPH: rug becomes the neon duel-arena circle; TV becomes the scoreboard.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_rugs := RoomKit.get_anchors("RUG")
		if not _morph_rugs.is_empty():
			RoomKit.morph(_morph_rugs[0], "neon")
		var _morph_tvs := RoomKit.get_anchors("TV")
		if not _morph_tvs.is_empty():
			RoomKit.morph(_morph_tvs[0], "neon")


## Fit the arena ring inside the real room; opponent spawns against walls.
func _fit_arena_to_room() -> void:
	var c := _room_bounds.get_center()
	var r := clampf(minf(_room_bounds.size.x, _room_bounds.size.y) * 0.5 - 0.2, 1.0, ARENA_RADIUS)
	if _arena_ring != null and is_instance_valid(_arena_ring):
		_arena_ring.position = Vector3(c.x, 0.02, c.y)
		_arena_ring.scale = Vector3.ONE * (r / ARENA_RADIUS)


## Opponent spawns backed against the wall the player faces (wall spawn);
## falls back to 2 m ahead of the head when no room data exists.
func _room_opponent_spawn() -> Vector3:
	var flat_fwd: Vector3 = -_head.global_transform.basis.z
	flat_fwd.y = 0
	if flat_fwd.length() < 0.01:
		flat_fwd = Vector3.FORWARD
	flat_fwd = flat_fwd.normalized()
	var fallback: Vector3 = _head.global_position + flat_fwd * 2.0
	if _room_walls.is_empty():
		return ARUpgradeKit.clamp_to_room(fallback)
	# Nearest wall to the fallback point = the wall the player faces.
	var best: Dictionary = _room_walls[0]
	var bd := 1e9
	for w in _room_walls:
		var d: float = (w["position"] - fallback).length()
		if d < bd:
			bd = d
			best = w
	var n: Vector3 = best["normal"]
	var side := signf((_head.global_position - best["position"]).dot(n))
	if side == 0.0:
		side = 1.0
	var p: Vector3 = best["position"] + n * side * 0.8
	p.y = 0.0
	return p


func _add_polish_light_rig() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _spawn_opponent() -> void:
	_opponent = DuelOpponent.create(Color(1.0, 0.28, 0.12))
	_opponent.name = "DuelOpponent"
	add_child(_opponent)
	if _head:
		_opponent.global_position = _room_opponent_spawn()
		_opponent.initialize(_head)
	_opponent.set_difficulty(difficulty)


func _process(delta: float) -> void:
	_billboard_hud()
	_update_announce(delta)

	# v0.11.0 onboarding: the practice beat runs instead of combat.
	if _onboarding:
		_update_onboarding(delta)
		return

	# Rematch: press R / click / XR right-hand pinch after the match ends.
	if match_over and (Input.is_key_pressed(KEY_R) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or (ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT))):
		_start_match()

	if not is_fighting or match_over:
		return
	if _opponent == null or _player == null or _head == null:
		return

	_player_hit_cooldown -= delta
	_opp_hit_cooldown -= delta
	_clash_cooldown -= delta
	_record_cooldown -= delta

	_record_player_attacks()
	_check_player_blade_vs_opponent()
	_check_blade_clash()
	_check_opponent_blade_vs_player()


# ---------------------------------------------------------- onboarding
## v0.11.0 (ship-blocker): 3-step practice-dummy beat before FIGHT.
## Step 1: swing to strike (one registered hit; POWER flash teaches the
##   3 m/s speed gate). Step 2: raise the off forearm — the dummy swings
##   slowly until one PARRIED!. Step 3: rules ("first to 3") -> FIGHT.
## ~20s total, skippable any time via trigger/pinch/click.
func _start_onboarding() -> void:
	_onboarding = true
	_onboard_step = 0
	is_fighting = false
	match_over = false
	_dummy = DuelOpponent.create(Color(0.35, 0.85, 1.0))
	_dummy.name = "TrainingDummy"
	_dummy.passive = true
	add_child(_dummy)
	if _head != null:
		var fwd: Vector3 = -_head.global_transform.basis.z
		fwd.y = 0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		var dp: Vector3 = _head.global_position + fwd.normalized() * 1.8
		dp.y = 0.0
		_dummy.global_position = dp
		_dummy.initialize(_head)
	_opponent = _dummy  # hit/parry checks run against the dummy
	_onboard_step = 1
	_onboard_nag_t = 0.0
	_announce("PRACTICE DUMMY\nSwing your %s hand — FAST!" % _blade_word(), 30.0)


func _update_onboarding(delta: float) -> void:
	# Skippable via trigger / pinch / click (desktop).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_finish_onboarding()
		return
	_player_hit_cooldown -= delta
	_opp_hit_cooldown -= delta
	_clash_cooldown -= delta
	_record_cooldown -= delta
	# The standard hit/parry checks run against the dummy; the onboarding
	# branches in on_player_hit/on_player_block/on_player_hurt advance steps.
	_record_player_attacks()
	_check_player_blade_vs_opponent()
	_check_blade_clash()
	_check_opponent_blade_vs_player()
	# Nag loop on step 2 until the parry lands.
	if _onboard_step == 2:
		_onboard_nag_t += delta
		if _onboard_nag_t > 6.0:
			_onboard_nag_t = 0.0
			_announce("Raise your %s forearm!" % _buckler_word(), 2.0)


## Step 1 complete -> step 2: the dummy starts its slow training swing.
func _advance_to_parry_step() -> void:
	_onboard_step = 2
	_onboard_nag_t = 0.0
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.training_swing = true
	_announce("NOW BLOCK!\nRaise your %s forearm!" % _buckler_word(), 30.0)


## Steps complete -> the real match (spawns the adaptive red opponent).
func _finish_onboarding() -> void:
	_onboarding = false
	_onboard_step = 0
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.queue_free()
	_dummy = null
	_opponent = null
	_spawn_opponent()
	_announce("FIRST TO 3 HITS\nFIGHT!", 2.0)
	AudioKit.set_intensity(2)  # v0.11.0: combat intensity on FIGHT
	_start_match()


func _blade_word() -> String:
	return "LEFT" if GameSettings.dominant_hand == "left" else "RIGHT"


func _buckler_word() -> String:
	return "RIGHT" if GameSettings.dominant_hand == "left" else "LEFT"


# ---------------------------------------------------------- match flow
func _start_match() -> void:
	player_score = 0
	opponent_score = 0
	player_rounds = 0
	opponent_rounds = 0
	current_round = 1
	match_over = false
	is_fighting = false
	if _arena_ring != null:
		ARUpgradeKit.save_anchor("duel_main", _arena_ring.global_transform)
	_reset_round_positions()
	_refresh_hud()
	_show_hint_ribbon()
	_countdown()


func _start_round() -> void:
	player_score = 0
	opponent_score = 0
	is_fighting = false
	_reset_round_positions()
	_refresh_hud()
	_show_hint_ribbon()
	_countdown()


## v0.11.0: round-1 controls recap ribbon. Visible during round 1 until the
## player has landed one hit AND one parry (then it has done its job).
func _show_hint_ribbon() -> void:
	_hint_hit_done = false
	_hint_parry_done = false
	if _hint_label != null:
		_hint_label.text = "%s hand: blade · %s forearm: parry · Fast swings score" % [
			_blade_word(), _buckler_word()]
		_hint_label.visible = (current_round == 1)


func _update_hint_ribbon() -> void:
	if _hint_label != null and _hint_hit_done and _hint_parry_done:
		_hint_label.visible = false


func _reset_round_positions() -> void:
	if _head and is_instance_valid(_opponent):
		_opponent.global_position = _room_opponent_spawn()
		_opponent.visible = true
		_opponent.initialize(_head)


func _countdown() -> void:
	if _countdown_active:
		return
	_countdown_active = true
	AudioKit.stinger("countdown")  # v0.11.0 T1
	for step in ["3", "2", "1", "FIGHT!"]:
		_announce(step, 0.75)
		await get_tree().create_timer(0.7, false).timeout
	_countdown_active = false
	is_fighting = true


## Player's blade landed on the opponent.
func on_player_hit(headshot: bool) -> void:
	if _onboarding:
		# Step 1: one registered hit completes the swing lesson.
		if _onboard_step == 1:
			_burst_fx(_dummy.head_center, Color(0.2, 0.9, 1.0), 10)
			_advance_to_parry_step()
		return
	if not is_fighting or match_over:
		return
	_hint_hit_done = true
	_unanswered_hits = 0
	_consec_blocked = 0
	_update_hint_ribbon()
	AudioKit.play_game_sfx("hit")  # v0.11.0 T1
	Haptics.impact(1.0, "both")
	player_score += 1
	_report_player_success(1.5 if headshot else 1.0)
	_announce("HEADSHOT!" if headshot else _pick_praise(), 0.8)
	_burst_fx(_opponent.head_center, Color(0.2, 0.9, 1.0), 10)
	_refresh_hud()
	_check_round_end()


## Opponent's blade reached the player's torso.
func on_player_hurt() -> void:
	if _onboarding:
		# Step 2: taking the slow swing = didn't raise the buckler. Teach.
		if _onboard_step == 2:
			_announce("Ouch! Raise your %s forearm!" % _buckler_word(), 1.5)
		return
	if not is_fighting or match_over:
		return
	# v0.11.0 whiff coaching: 2 unanswered hits -> flash the buckler and say
	# the words (turns silent failure into teaching).
	_unanswered_hits += 1
	if _unanswered_hits >= 2:
		_unanswered_hits = 0
		_announce("RAISE %s ARM TO PARRY!" % _buckler_word(), 1.5)
		if _player != null:
			_player.flash_buckler()
	opponent_score += 1
	_report_player_setback(1.0)
	_announce("HIT!", 0.8)
	_refresh_hud()
	_check_round_end()


## Buckler parried the opponent's blade: no score, small difficulty reward.
func on_player_block() -> void:
	if _onboarding:
		# Step 2 complete -> rules -> FIGHT.
		if _onboard_step == 2:
			if _dummy != null and is_instance_valid(_dummy):
				_burst_fx(_player.buckler_position, Color(0.4, 1.0, 1.0), 20)
			AudioKit.play_game_sfx("parry")  # v0.11.0 T1: parry teaching
			Haptics.impact(0.5, "both")
			_finish_onboarding()
		return
	if not is_fighting or match_over:
		return
	_hint_parry_done = true
	_unanswered_hits = 0
	_update_hint_ribbon()
	_report_player_success(0.4)
	AudioKit.play_game_sfx("block")  # v0.11.0 T1: forearm block
	Haptics.impact(0.6, "both")
	_announce("PARRIED!", 0.7)


func _check_round_end() -> void:
	if player_score >= HITS_TO_WIN_ROUND:
		player_rounds += 1
		_announce("ROUND %d - YOU!" % current_round, 1.6)
	elif opponent_score >= HITS_TO_WIN_ROUND:
		opponent_rounds += 1
		_opponent.defeat()
		_announce("ROUND %d - FOE" % current_round, 1.6)
	else:
		return

	_refresh_hud()
	if player_rounds >= ROUNDS_TO_WIN_MATCH:
		_end_match(true)
	elif opponent_rounds >= ROUNDS_TO_WIN_MATCH:
		_end_match(false)
	else:
		current_round += 1
		is_fighting = false
		await get_tree().create_timer(1.8, false).timeout
		if not match_over:
			_start_round()


func _end_match(player_won: bool) -> void:
	match_over = true
	is_fighting = false
	AudioKit.set_intensity(0)  # v0.11.0 T1: back to calm
	if player_won:
		wins_total += 1
		_save_records()
		AudioKit.stinger("levelup")  # v0.11.0 T1: round-win stinger
		Haptics.play_sequence("levelup")
		_announce("VICTORY!\nPress R or click to rematch", 30.0)
		if _head:
			_burst_fx(_head.global_position + (-_head.global_transform.basis.z) * 1.2,
				Color(0.2, 1.0, 0.3), 40)
	else:
		losses_total += 1
		_save_records()
		if _opponent:
			_opponent.defeat()
		_announce("DEFEAT\nPress R or click to rematch", 30.0)
	_refresh_hud()


# ---------------------------------------------------------- adaptive difficulty
## Simple adaptive driver (replaces Unity's shared AIDirector):
## player doing well -> opponent gets sharper; struggling -> it eases off.
func _report_player_success(weight: float) -> void:
	difficulty = clampf(difficulty + 0.02 * weight, 0.15, 0.95)
	if _opponent:
		_opponent.set_difficulty(difficulty)


func _report_player_setback(weight: float) -> void:
	difficulty = clampf(difficulty - 0.03 * weight, 0.15, 0.95)
	if _opponent:
		_opponent.set_difficulty(difficulty)


# ---------------------------------------------------------- hit detection
func _record_player_attacks() -> void:
	if not _player.blade_active or _record_cooldown > 0.0:
		return
	var tip := _player.blade.tip_position
	var speed := _player.blade.tip_velocity.length()
	if speed < 3.0:
		return
	# v0.11.0: a qualifying swing flashes POWER on the blade (teaches the
	# 3 m/s gate; the onboarding beat's core signal).
	_player.blade.power_flash()
	AudioKit.play_game_sfx("swing")  # v0.11.0 T1: whiff != clash
	if tip.distance_to(_opponent.body_center) > 2.4:
		return
	var zone := _compute_buckets(tip)
	_opponent.record_player_attack(zone[0], zone[1])
	_record_cooldown = 0.25


func _check_player_blade_vs_opponent() -> void:
	if not _player.blade_active or _player_hit_cooldown > 0.0:
		return
	var st := _opponent.current_state
	if st in [DuelOpponent.State.DEFEATED, DuelOpponent.State.HIT_STUN]:
		return

	var p0 := _player.blade.base_position
	var p1 := _player.blade.tip_position

	var body_a := _opponent.body_center + Vector3.UP * _opponent.body_half_height
	var body_b := _opponent.body_center - Vector3.UP * _opponent.body_half_height
	var d_body := _seg_seg_dist(p0, p1, body_a, body_b)
	var d_head := _seg_point_dist(p0, p1, _opponent.head_center)

	var hit_body := d_body < _opponent.body_radius + 0.06
	var hit_head := d_head < _opponent.head_radius + 0.06
	if not hit_body and not hit_head:
		return

	var hit_point := _opponent.head_center if hit_head \
		else Geometry3D.get_closest_point_to_segment(_opponent.body_center, p0, p1)
	var tip_vel := _player.blade.tip_velocity
	var zone := _compute_buckets(_player.blade.tip_position)

	# Opponent may intercept the incoming blade.
	if _opponent.try_block(_player.blade.tip_position, tip_vel, zone[0], zone[1]):
		_player.blade.clash()
		_opponent.clash_blade()
		_burst_fx(hit_point, Color.WHITE, 14)
		_player_hit_cooldown = 0.3
		# v0.11.0 blocked coaching: 3 consecutive blocks -> teach the counter.
		if not _onboarding:
			_consec_blocked += 1
			if _consec_blocked >= 3:
				_consec_blocked = 0
				_announce("BLOCKED — swing around him!", 1.5)
		return

	if _opponent.current_state == DuelOpponent.State.BLOCK:
		return  # mid-block, no damage

	# Clean hit.
	_burst_fx(hit_point, Color(1.0, 0.85, 0.2) if hit_head else Color(1.0, 0.5, 0.1),
		30 if hit_head else 22)
	_player.blade.clash()
	_opponent.on_hit()
	on_player_hit(hit_head)
	_player_hit_cooldown = 0.3
	_hit_stop()


func _check_blade_clash() -> void:
	if not _player.blade_active or _clash_cooldown > 0.0:
		return
	var d := _seg_seg_dist(
		_player.blade.base_position, _player.blade.tip_position,
		_opponent.blade_base, _opponent.blade_tip)
	if d > 0.11:
		return
	var mid := (_player.blade.tip_position + _opponent.blade_tip) * 0.5
	_player.blade.clash()
	_opponent.clash_blade()
	_burst_fx(mid, Color.WHITE, 16)
	AudioKit.play_game_sfx("clash")  # v0.11.0 T1
	Haptics.impact(0.8, "both")
	_clash_cooldown = 0.3


func _check_opponent_blade_vs_player() -> void:
	if _opp_hit_cooldown > 0.0:
		return
	if not _opponent.is_attacking:
		return

	var o0 := _opponent.blade_base
	var o1 := _opponent.blade_tip

	# Parry buckler intercepts first.
	if _player.buckler_active:
		var d_buckler := _seg_point_dist(o0, o1, _player.buckler_position)
		if d_buckler < PlayerBlade.BUCKLER_RADIUS + 0.05:
			_burst_fx(_player.buckler_position, Color(0.4, 1.0, 1.0), 20)
			_opponent.clash_blade()
			_opp_hit_cooldown = 0.4
			on_player_block()
			return

	# Torso capsule around the camera.
	var cap_a := _head.global_position + Vector3.DOWN * 0.05
	var cap_b := _head.global_position + Vector3.DOWN * 0.95
	var d := _seg_seg_dist(o0, o1, cap_a, cap_b)
	if d > 0.30 + 0.06:
		return

	var hit_point := Geometry3D.get_closest_point_to_segment(o1, cap_a, cap_b)
	_burst_fx(hit_point, Color(1.0, 0.15, 0.1), 26)
	on_player_hurt()
	_opp_hit_cooldown = 0.6
	_hit_stop()


func _hit_stop() -> void:
	# 60ms hit-stop punch (restored immediately after).
	if _hit_stop_active:
		return
	_hit_stop_active = true
	Engine.time_scale = 0.2
	await get_tree().create_timer(0.06, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false


# ---------------------------------------------------------- buckets + math
func _compute_buckets(tip_pos: Vector3) -> Array:
	var offset: Vector3 = tip_pos - _opponent.body_center
	var right: Vector3 = _opponent.global_transform.basis.x
	var lateral := offset.dot(right)
	var vertical := offset.y
	var dir: int
	if absf(vertical) > absf(lateral) * 1.2:
		dir = 2 if vertical > 0.0 else 3  # High / Low
	else:
		dir = 1 if lateral > 0.0 else 0  # Right / Left (opponent's view)
	var height := 0 if offset.y > 0.35 else (2 if offset.y < -0.25 else 1)
	return [dir, height]


func _seg_point_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


func _seg_seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return (pts[0] as Vector3).distance_to(pts[1] as Vector3)


# ---------------------------------------------------------- FX + HUD
func _burst_fx(pos: Vector3, color: Color, count: int) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.45
	particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -6, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.015
	mat.scale_max = 0.04
	mat.color = color
	particles.process_material = mat

	var draw_mat := GraphicsPolish.glow(color, 3.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	quad.material = draw_mat
	particles.draw_pass_1 = quad

	add_child(particles)
	particles.global_position = pos
	# Free after the burst finishes.
	var t := get_tree().create_timer(1.2, false)
	t.timeout.connect(particles.queue_free)


func _build_hud() -> void:
	_score_label = Label3D.new()
	_score_label.name = "ScoreLabel"
	_score_label.font_size = 64
	_score_label.pixel_size = 0.004
	_score_label.modulate = Color(0.7, 0.95, 1.0)
	_score_label.outline_size = 8
	add_child(_score_label)

	_announce_label = Label3D.new()
	_announce_label.name = "AnnounceLabel"
	_announce_label.font_size = 96
	_announce_label.pixel_size = 0.005
	_announce_label.modulate = Color(1.0, 0.9, 0.4)
	_announce_label.outline_size = 10
	add_child(_announce_label)
	# v0.11.0: round-1 hint ribbon (static in-world Label3D — unaffected by
	# the static-panel rule). Fades after the first hit AND first parry.
	_hint_label = Label3D.new()
	_hint_label.name = "HintRibbon"
	_hint_label.font_size = 48
	_hint_label.pixel_size = 0.004
	_hint_label.modulate = Color(0.75, 0.9, 1.0)
	_hint_label.outline_size = 6
	_hint_label.visible = false
	add_child(_hint_label)


func _billboard_hud() -> void:
	if _head == null:
		return
	var head_pos: Vector3 = _head.global_position
	var fwd: Vector3 = -_head.global_transform.basis.z
	_score_label.global_position = head_pos + fwd * 1.4 + Vector3.UP * 0.42
	_score_label.look_at(head_pos, Vector3.UP)
	_announce_label.global_position = head_pos + fwd * 1.6
	_announce_label.look_at(head_pos, Vector3.UP)
	if _hint_label != null and _hint_label.visible:
		_hint_label.global_position = head_pos + fwd * 1.45 + Vector3.UP * 0.18
		_hint_label.look_at(head_pos, Vector3.UP)


func _update_announce(delta: float) -> void:
	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_label.text = ""


func _announce(text: String, duration: float) -> void:
	_announce_label.text = text
	_announce_timer = duration


func _refresh_hud() -> void:
	_score_label.text = "YOU %d : %d FOE   (round %d)\nRounds %d : %d  |  Wins %d" % [
		player_score, opponent_score, current_round,
		player_rounds, opponent_rounds, wins_total]


func _pick_praise() -> String:
	var p := ["POINT!", "CLEAN HIT!", "STRUCK!", "TOUCHE!"]
	return p[randi() % p.size()]


# ---------------------------------------------------------- setup helpers
func _find_head() -> Node3D:
	var xr := get_node_or_null("XROrigin3D")
	if xr:
		var cam := xr.get_node_or_null("XRCamera3D") as Node3D
		if cam:
			return cam
	var cam3d := get_viewport().get_camera_3d()
	if cam3d:
		return cam3d
	return null


func _build_arena_ring() -> void:
	# Neon ring on the floor + center marker, like DuelBootstrap's arena ring.
	var ring := MeshInstance3D.new()
	ring.name = "ArenaRing"
	_arena_ring = ring
	var pts := 72
	var verts := PackedVector3Array()
	for i in range(pts + 1):
		var a := float(i) / pts * TAU
		verts.push_back(Vector3(cos(a) * ARENA_RADIUS, 0, sin(a) * ARENA_RADIUS))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	var rmat := GraphicsPolish.glow(Color(0.1, 0.9, 1.0), 2.5)
	ring.mesh = amesh
	ring.material_override = rmat
	ring.position = Vector3(0, 0.02, 0)
	add_child(ring)

	# Holographic glass floor disc under the arena.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = ARENA_RADIUS
	disc_mesh.bottom_radius = ARENA_RADIUS
	disc_mesh.height = 0.002
	disc.mesh = disc_mesh
	disc.material_override = GraphicsPolish.pbr_preset(Color(0.1, 0.5, 0.8, 0.5), "glass")
	disc.position = Vector3(0, 0.005, 0)
	add_child(disc)

	var dot := MeshInstance3D.new()
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = 0.06
	dcyl.bottom_radius = 0.06
	dcyl.height = 0.004
	dot.mesh = dcyl
	dot.material_override = rmat
	add_child(dot)


# ---------------------------------------------------------- persistence
func _load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		wins_total = int(cfg.get_value("duel", "wins", 0))
		losses_total = int(cfg.get_value("duel", "losses", 0))


func _save_records() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("duel", "wins", wins_total)
	cfg.set_value("duel", "losses", losses_total)
	cfg.save(SAVE_PATH)
