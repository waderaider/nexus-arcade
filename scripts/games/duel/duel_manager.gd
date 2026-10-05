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
	_spawn_opponent()
	_announce("NEON DUEL", 2.0)
	_start_match()


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
		var flat_fwd: Vector3 = -_head.global_transform.basis.z
		flat_fwd.y = 0
		if flat_fwd.length() < 0.01:
			flat_fwd = Vector3.FORWARD
		_opponent.global_position = ARUpgradeKit.clamp_to_room(
			_head.global_position + flat_fwd.normalized() * 2.0)
		_opponent.initialize(_head)
	_opponent.set_difficulty(difficulty)


func _process(delta: float) -> void:
	_billboard_hud()
	_update_announce(delta)

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
	_countdown()


func _start_round() -> void:
	player_score = 0
	opponent_score = 0
	is_fighting = false
	_reset_round_positions()
	_refresh_hud()
	_countdown()


func _reset_round_positions() -> void:
	if _head and is_instance_valid(_opponent):
		var flat_fwd: Vector3 = -_head.global_transform.basis.z
		flat_fwd.y = 0
		if flat_fwd.length() < 0.01:
			flat_fwd = Vector3.FORWARD
		_opponent.global_position = ARUpgradeKit.clamp_to_room(
			_head.global_position + flat_fwd.normalized() * 2.0)
		_opponent.visible = true
		_opponent.initialize(_head)


func _countdown() -> void:
	if _countdown_active:
		return
	_countdown_active = true
	for step in ["3", "2", "1", "FIGHT!"]:
		_announce(step, 0.75)
		await get_tree().create_timer(0.7).timeout
	_countdown_active = false
	is_fighting = true


## Player's blade landed on the opponent.
func on_player_hit(headshot: bool) -> void:
	if not is_fighting or match_over:
		return
	player_score += 1
	_report_player_success(1.5 if headshot else 1.0)
	_announce("HEADSHOT!" if headshot else _pick_praise(), 0.8)
	_burst_fx(_opponent.head_center, Color(0.2, 0.9, 1.0), 10)
	_refresh_hud()
	_check_round_end()


## Opponent's blade reached the player's torso.
func on_player_hurt() -> void:
	if not is_fighting or match_over:
		return
	opponent_score += 1
	_report_player_setback(1.0)
	_announce("HIT!", 0.8)
	_refresh_hud()
	_check_round_end()


## Buckler parried the opponent's blade: no score, small difficulty reward.
func on_player_block() -> void:
	if not is_fighting or match_over:
		return
	_report_player_success(0.4)
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
		await get_tree().create_timer(1.8).timeout
		if not match_over:
			_start_round()


func _end_match(player_won: bool) -> void:
	match_over = true
	is_fighting = false
	if player_won:
		wins_total += 1
		_save_records()
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
	var t := get_tree().create_timer(1.2)
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


func _billboard_hud() -> void:
	if _head == null:
		return
	var head_pos: Vector3 = _head.global_position
	var fwd: Vector3 = -_head.global_transform.basis.z
	_score_label.global_position = head_pos + fwd * 1.4 + Vector3.UP * 0.42
	_score_label.look_at(head_pos, Vector3.UP)
	_announce_label.global_position = head_pos + fwd * 1.6
	_announce_label.look_at(head_pos, Vector3.UP)


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
