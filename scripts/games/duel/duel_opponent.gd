## DuelOpponent.gd - floating duelist drone for Neon Duel.
## Ports DuelOpponent.cs: procedural robed figure (cone robe, emissive visor,
## energy blade) that strafes around the player, telegraphs attacks, and
## LEARNS: it keeps the player's last 40 attacks in a (direction, height)
## histogram, guards the predicted zone and strikes the least-guarded zone.
## Difficulty adapts to the match score (set by DuelManager).
extends Node3D
class_name DuelOpponent

enum State { ORBIT, TELEGRAPH, ATTACK, RECOVER, BLOCK, HIT_STUN, DEFEATED }

# Pattern-learning buckets. Dir (from opponent's view of the incoming blade):
# 0=Left 1=Right 2=High 3=Low. Height (tip vs body center): 0=Head 1=Torso 2=Low.
const DIR_BUCKETS := 4
const HEIGHT_BUCKETS := 3
const HISTORY_MAX := 40

var current_state: State = State.ORBIT
var is_attacking: bool:
	get: return current_state == State.ATTACK
var is_vulnerable: bool:
	get: return current_state in [State.ORBIT, State.TELEGRAPH, State.RECOVER]

var body_center: Vector3:
	get: return global_position
var body_radius := 0.38
var body_half_height := 0.55
var head_center: Vector3:
	get: return global_position + Vector3.UP * 0.62
var head_radius := 0.22
var blade_base: Vector3:
	get: return _blade.base_position if _blade else global_position
var blade_tip: Vector3:
	get: return _blade.tip_position if _blade else global_position

var difficulty := 0.5

var _state_timer := 0.0
var _player_head: Node3D

var _blade: EnergyBlade
var _blade_mount: Node3D
var _visor_mat: StandardMaterial3D
var _visor_flash := 0.0
var _accent := Color(1.0, 0.28, 0.12)

var _orbit_angle := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 2.0
var _bob_phase := 0.0
var _attack_timer := 2.0
var _next_block_time := 0.0
var _lunge_target := Vector3.ZERO

# Learning state.
var _history: Array = []  # of [dir, height, dt]
var _histogram := []      # [DIR_BUCKETS][HEIGHT_BUCKETS] ints
var _last_player_attack_time := -10.0

# Blade mount poses.
var _mount_pos_target := Vector3(0.38, -0.05, 0.15)
var _mount_rot_target := Vector3.ZERO  # euler degrees


static func create(accent: Color) -> DuelOpponent:
	var opp := DuelOpponent.new()
	opp._accent = accent
	opp._build(accent)
	return opp


func initialize(player_head: Node3D) -> void:
	_player_head = player_head
	var d: Vector3 = player_head.global_position - global_position
	d.y = 0
	if d.length() > 0.001:
		_orbit_angle = atan2(d.z, d.x) + PI


func set_difficulty(d: float) -> void:
	difficulty = clampf(d, 0.15, 0.95)


# ---------------------------------------------------------- learning
func record_player_attack(dir_bucket: int, height_bucket: int) -> void:
	dir_bucket = clampi(dir_bucket, 0, DIR_BUCKETS - 1)
	height_bucket = clampi(height_bucket, 0, HEIGHT_BUCKETS - 1)
	var now := Time.get_ticks_msec() / 1000.0
	var dt: float = now - _last_player_attack_time
	_last_player_attack_time = now
	_history.push_back([dir_bucket, height_bucket, dt])
	_histogram[dir_bucket][height_bucket] += 1
	if _history.size() > HISTORY_MAX:
		var old: Array = _history.pop_front()
		_histogram[old[0]][old[1]] = maxi(0, _histogram[old[0]][old[1]] - 1)


## Most frequent zone = where the player likely guards next.
func predict_guard_zone() -> Array:
	var best := -1
	var bd := 1
	var bh := 1
	for d in range(DIR_BUCKETS):
		for h in range(HEIGHT_BUCKETS):
			if _histogram[d][h] > best:
				best = _histogram[d][h]
				bd = d
				bh = h
	return [bd, bh]


## Least frequent zone = presumed least-guarded; attack there.
func choose_attack_zone() -> Array:
	var best := 1 << 30
	var bd := 0
	var bh := 1
	for d in range(DIR_BUCKETS):
		for h in range(HEIGHT_BUCKETS):
			if _histogram[d][h] < best:
				best = _histogram[d][h]
				bd = d
				bh = h
	return [bd, bh]


func average_player_cadence() -> float:
	if _history.is_empty():
		return 1.2
	var sum := 0.0
	for r in _history:
		sum += r[2]
	return clampf(sum / _history.size(), 0.4, 3.0)


# ---------------------------------------------------------- blocking
## Called by the manager before applying a player hit. Returns true when the
## opponent intercepts the blade (hit negated -> clash).
func try_block(tip_pos: Vector3, tip_vel: Vector3, dir_bucket: int, height_bucket: int) -> bool:
	if current_state in [State.DEFEATED, State.HIT_STUN, State.BLOCK]:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_block_time:
		return false

	var to_opp: Vector3 = body_center - tip_pos
	var dist := to_opp.length()
	if dist > 1.6:
		return false
	var closing: float = tip_vel.dot(to_opp / maxf(dist, 0.001))
	var threshold := lerpf(3.4, 1.7, difficulty)
	if closing < threshold:
		return false

	var zone: Array = predict_guard_zone()
	var zone_match: bool = int(zone[0]) == dir_bucket and int(zone[1]) == height_bucket
	var chance: float = lerpf(0.55, 0.95, difficulty) if zone_match else difficulty * 0.35
	if randf() > chance:
		return false

	_next_block_time = now + lerpf(1.3, 0.65, difficulty)
	_enter_state(State.BLOCK, 0.42)
	_mount_pos_target = Vector3(0, 0.08, 0.38)
	_mount_rot_target = Vector3(0, 0, 90)  # blade horizontal across body
	_visor_flash = 1.0
	_blade.set_hum(160.0, 0.6)
	return true


func on_hit() -> void:
	if current_state == State.DEFEATED:
		return
	_enter_state(State.HIT_STUN, 0.35)
	_visor_flash = 1.0
	# Small knockback away from the player.
	if _player_head:
		var away: Vector3 = global_position - _player_head.global_position
		away.y = 0
		if away.length() > 0.001:
			global_position += away.normalized() * 0.12
	_blade.set_hum(70.0, 0.5)


func defeat() -> void:
	_enter_state(State.DEFEATED, 1.4)
	_blade.set_hum(45.0, 0.3)


func clash_blade() -> void:
	if _blade:
		_blade.clash()


# ---------------------------------------------------------- build
func _build(accent: Color) -> void:
	# Histogram storage.
	for d in range(DIR_BUCKETS):
		var row := []
		for h in range(HEIGHT_BUCKETS):
			row.append(0)
		_histogram.append(row)

	var robe_mat := StandardMaterial3D.new()
	robe_mat.albedo_color = Color(0.10, 0.08, 0.16)
	robe_mat.metallic = 0.2
	robe_mat.roughness = 0.6
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.03, 0.03, 0.04)
	dark_mat.metallic = 0.6
	dark_mat.roughness = 0.5

	# Robe: cone, wide at the bottom.
	var robe := MeshInstance3D.new()
	robe.name = "Robe"
	var rcone := CylinderMesh.new()
	rcone.top_radius = 0.16
	rcone.bottom_radius = 0.45
	rcone.height = 1.3
	rcone.radial_segments = 14
	robe.mesh = rcone
	robe.material_override = robe_mat
	robe.position = Vector3(0, -0.15, 0)
	add_child(robe)

	# Sash / trim ring.
	var trim := MeshInstance3D.new()
	trim.name = "Trim"
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.36
	tcyl.bottom_radius = 0.36
	tcyl.height = 0.03
	trim.mesh = tcyl
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = accent
	tmat.emission_enabled = true
	tmat.emission = accent
	tmat.emission_energy_multiplier = 1.4
	trim.material_override = tmat
	trim.position = Vector3(0, -0.42, 0)
	add_child(trim)

	# Head.
	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	head.mesh = sphere
	head.material_override = dark_mat
	head.position = Vector3(0, 0.62, 0)
	add_child(head)

	# Emissive visor (telegraphs attacks by flashing).
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	var vbox := BoxMesh.new()
	vbox.size = Vector3(0.20, 0.07, 0.05)
	visor.mesh = vbox
	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = accent
	_visor_mat.emission_enabled = true
	_visor_mat.emission = accent
	_visor_mat.emission_energy_multiplier = 2.5
	visor.material_override = _visor_mat
	visor.position = Vector3(0, 0.63, 0.145)
	add_child(visor)

	# Hover glow ring.
	var glow := MeshInstance3D.new()
	glow.name = "HoverGlow"
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 0.475
	gcyl.bottom_radius = 0.475
	gcyl.height = 0.015
	glow.mesh = gcyl
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = accent
	gmat.emission_enabled = true
	gmat.emission = accent
	gmat.emission_energy_multiplier = 2.0
	glow.material_override = gmat
	glow.position = Vector3(0, -0.84, 0)
	add_child(glow)

	# Blade on a mount so we can pose it per-state.
	_blade_mount = Node3D.new()
	_blade_mount.name = "BladeMount"
	_blade_mount.position = _mount_pos_target
	add_child(_blade_mount)
	_blade = EnergyBlade.create(accent, 0.8)
	_blade_mount.add_child(_blade)
	_blade.set_hum(80.0, 0.4)


# ---------------------------------------------------------- update
func _process(delta: float) -> void:
	if _player_head == null:
		return

	# Visor flash decay.
	if _visor_flash > 0.0:
		_visor_flash = maxf(0.0, _visor_flash - delta * 4.0)
		_visor_mat.emission = _accent.lerp(Color.WHITE, _visor_flash)
		_visor_mat.emission_energy_multiplier = 2.5 + _visor_flash * 4.0

	# Blade mount pose easing.
	_blade_mount.position = _blade_mount.position.lerp(_mount_pos_target, minf(delta * 8.0, 1.0))
	var target_quat := Quaternion.from_euler(Vector3(
		deg_to_rad(_mount_rot_target.x),
		deg_to_rad(_mount_rot_target.y),
		deg_to_rad(_mount_rot_target.z)))
	_blade_mount.quaternion = _blade_mount.quaternion.slerp(target_quat, minf(delta * 8.0, 1.0))

	# Always face the player (yaw).
	var look: Vector3 = _player_head.global_position - global_position
	look.y = 0
	if look.length() > 0.01:
		var target_yaw := atan2(-look.x, -look.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 6.0, 1.0))

	_bob_phase += delta * 2.2
	var hover_y := 1.35 + sin(_bob_phase) * 0.06

	match current_state:
		State.ORBIT: _update_orbit(delta, hover_y)
		State.TELEGRAPH: _update_telegraph(delta)
		State.ATTACK: _update_attack(delta)
		State.RECOVER: _update_recover(delta, hover_y)
		State.BLOCK: _update_block(delta, hover_y)
		State.HIT_STUN: _update_hit_stun(delta, hover_y)
		State.DEFEATED: _update_defeated(delta)


func _update_orbit(delta: float, hover_y: float) -> void:
	var strafe_speed := lerpf(0.9, 2.0, difficulty)
	_orbit_angle += _strafe_dir * strafe_speed / 2.0 * delta
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_dir *= -1.0
		_strafe_timer = randf_range(1.2, 3.2)

	var player_flat: Vector3 = _player_head.global_position
	player_flat.y = 0
	var desired := player_flat + Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * 2.0
	var move_speed := lerpf(1.2, 2.6, difficulty)
	var target := Vector3(desired.x, hover_y, desired.z)
	global_position = global_position.move_toward(target, move_speed * delta)

	# Rest blade pose.
	_mount_pos_target = Vector3(0.38, -0.05, 0.15)
	_mount_rot_target = Vector3(-12, 0, -8)
	_blade.set_hum(80.0, 0.4)

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_enter_state(State.TELEGRAPH, lerpf(0.55, 0.32, difficulty))
		_visor_flash = 1.0
		_blade.set_hum(170.0, 0.7)


func _update_telegraph(delta: float) -> void:
	# Cock the blade back, hold ground, visor strobing.
	_mount_pos_target = Vector3(0.45, 0.12, -0.28)
	_mount_rot_target = Vector3(35, 0, 12)
	_visor_flash = maxf(_visor_flash, 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 30.0))

	_state_timer -= delta
	if _state_timer <= 0.0:
		# Commit to the lunge: stop ~1.1m from the player, on our side.
		var to_player: Vector3 = _player_head.global_position - global_position
		to_player.y = 0
		to_player = to_player.normalized()
		var pf: Vector3 = _player_head.global_position
		pf.y = 0
		_lunge_target = pf - to_player * 1.1
		_lunge_target.y = _player_head.global_position.y - 0.15
		_enter_state(State.ATTACK, 0.42)
		_blade.set_hum(220.0, 0.8)


func _update_attack(delta: float) -> void:
	# Lunge + blade sweep toward the player.
	global_position = global_position.move_toward(_lunge_target, 7.0 * delta)
	_mount_pos_target = Vector3(0.05, 0.02, 0.42)
	_mount_rot_target = Vector3(80, 0, 0)  # blade forward
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.RECOVER, lerpf(0.9, 0.5, difficulty))
		var cadence := average_player_cadence()
		_attack_timer = lerpf(2.6, 1.25, difficulty) \
			* clampf(cadence / 1.2, 0.7, 1.4) \
			* randf_range(0.85, 1.2)


func _update_recover(delta: float, hover_y: float) -> void:
	_mount_pos_target = Vector3(0.38, -0.05, 0.15)
	_mount_rot_target = Vector3(-12, 0, -8)
	# Drift back out to orbit distance.
	var player_flat: Vector3 = _player_head.global_position
	player_flat.y = 0
	var away: Vector3 = global_position - player_flat
	away.y = 0
	if away.length() < 1.7 and away.length() > 0.001:
		global_position += away.normalized() * 1.2 * delta
	global_position.y = hover_y
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ORBIT, 0.0)


func _update_block(delta: float, hover_y: float) -> void:
	global_position.y = hover_y
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ORBIT, 0.0)


func _update_hit_stun(delta: float, hover_y: float) -> void:
	global_position.y = hover_y
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ORBIT, 0.0)


func _update_defeated(delta: float) -> void:
	# Sink and fade out.
	global_position += Vector3.DOWN * 0.8 * delta
	_state_timer -= delta
	if _state_timer <= 0.0:
		visible = false


func _enter_state(s: State, timer: float) -> void:
	current_state = s
	_state_timer = timer
