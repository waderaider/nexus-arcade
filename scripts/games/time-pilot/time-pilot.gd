## time-pilot.gd -- NEXUS ARCADE: time-manipulation shooter for Quest 3.
## Red diamond enemies fly toward the player shooting slow orange bullets.
## The cyan player ship follows the mouse. Hold click / pinch for TIME SLOW
## (time_scale 0.25 + blue vignette); double-click triggers TIME STOP for 2s
## (10s cooldown). Auto-fire targets the nearest enemy. Dodging bullets in
## slow-mo builds the focus meter (full focus = double score). 3 lives,
## escalating waves, game-over screen, click / R to restart.
extends Node3D

const PLAYER_Z := 2.6
const SLOW_FACTOR := 0.25
const STOP_TIME := 2.0
const STOP_COOLDOWN := 10.0
const HOLD_TO_SLOW := 0.22     # seconds of press before slow-mo engages
const DOUBLE_CLICK := 0.35

const PLAYER_BULLET_SPEED := 16.0
const FIRE_INTERVAL := 0.22
const ENEMY_BULLET_SPEED := 5.5
const PLAYER_R := 0.45
const ENEMY_R := 0.55


class Enemy:
	var node: MeshInstance3D = null
	var hp := 1
	var speed := 1.8
	var drift_phase := 0.0
	var drift_amp := 0.6
	var shoot_cd := 2.0


class Bullet:
	var node: MeshInstance3D = null
	var vel := Vector3.ZERO
	var from_player := true
	var life := 4.0
	var min_d := 999.0   # closest approach to the player (enemy bullets)


var cam: Camera3D = null
var _time := 0.0        # scaled game time
var _rtime := 0.0       # unscaled real time (input, cooldowns)
var _prev_keys := {}

var _state := "playing"   # "playing" | "gameover"

var _player: MeshInstance3D = null
var _player_mat: StandardMaterial3D = null
var _player_target := Vector3(0.0, 1.8, PLAYER_Z)
var _invuln := 0.0

var _enemies: Array = []   # Enemy
var _bullets: Array = []   # Bullet
var _stars: Array = []

var _score := 0
var _wave := 0
var _lives := 3
var _focus := 0.0
var _spawn_queue := 0
var _spawn_timer := 0.0
var _wave_banner_t := 0.0
var _fire_timer := 0.0

# Time powers.
var _pressing := false
var _press_start := 0.0
var _last_press := -10.0
var _slow_active := false
var _stop_active := false
var _stop_t := 0.0
var _stop_cd := 0.0
var _mouse_pos := Vector2(640.0, 400.0)

var _hud: Label3D = null
var _banner: Label3D = null
var _over_node: Node3D = null
var _vignette: ColorRect = null
var _flash: ColorRect = null
var _flash_t := 0.0
var _anchor_t := 0.0

# v0.7.0 RoomKit: waves emerge from real wall faces; bullets interact with
# real wall planes. Cached; empty without XR room data.
var _room_walls: Array = []
var _room_tables: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)


func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return  # intentional floating-space fallback: keep default layout
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_bounds = RoomKit.room_bounds()
	# v0.7.0 MORPH: TV becomes the retro CRT mission-briefing screen.
	if not has_meta("_morphs_applied"):
		set_meta("_morphs_applied", true)
		var _morph_tvs := RoomKit.get_anchors("TV")
		if not _morph_tvs.is_empty():
			RoomKit.morph(_morph_tvs[0], "neon")


## Normal-sign agnostic wall reflection.
func _bounce_walls(pos: Vector3, vel: Vector3, radius: float) -> Vector3:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		var d: float = (pos - w["position"]).dot(n)
		if absf(d) < radius and vel.dot(n) * signf(d) < 0.0:
			vel = vel - 2.0 * vel.dot(n) * n
	return vel


## Enemy spawn point on a real wall face (the wall furthest "up-field",
## i.e. smallest z, so waves still stream in from deep field).
func _room_wall_spawn() -> Vector3:
	var best: Dictionary = _room_walls[0]
	for w in _room_walls:
		if float(w["position"].z) < float(best["position"].z):
			best = w
	var n: Vector3 = best["normal"]
	var sz: Vector2 = best["size"]
	var c: Vector3 = best["position"]
	var right := n.cross(Vector3.UP).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	var p := c + right * randf_range(-sz.x * 0.4, sz.x * 0.4)
	p.y = clampf(c.y + randf_range(-sz.y * 0.3, sz.y * 0.3), 0.8, 3.6)
	var side := signf((Vector3(0, 1.8, PLAYER_Z) - c).dot(n))
	if side == 0.0:
		side = 1.0
	p += n * side * 0.6
	return to_local(p)


## Impact FX where a bullet strikes a real wall plane; "" when none near.
func _room_bullet_wall_hit(pos: Vector3) -> bool:
	for w in _room_walls:
		var n: Vector3 = w["normal"]
		if absf((pos - w["position"]).dot(n)) < 0.18:
			GraphicsPolish.spawn_sparks(self, pos, Color(0.5, 0.8, 1.0), 10)
			return true
	return false


func _ready() -> void:
	# Restore the persisted playfield placement (no-op when no anchor was saved).
	ARUpgradeKit.apply_anchor(self, "time-pilot_main")
	_build_environment()
	_build_player()
	_build_overlay()
	_reset_game()
	# Engine trail on the player ship.
	_player.add_child(GraphicsPolish.make_trail(Color(0.3, 0.95, 1.0), 0.07))
	# Three-point light rig, unless the scene already has a key light.
	var _has_dir := false
	for c in get_children():
		if c is DirectionalLight3D:
			_has_dir = true
	if not _has_dir:
		GraphicsPolish.make_light_rig(self, 1.1)
	_apply_room_layout()


# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	for child in get_children():
		if child is Camera3D:
			cam = child
			break
	if cam == null:
		cam = Camera3D.new()
		cam.position = Vector3(0.0, 2.2, 6.6)
		add_child(cam)
		cam.look_at(Vector3(0.0, 1.7, -3.0), Vector3.UP)

	# (Key light comes from the GraphicsPolish light rig in _ready.)

	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.60)
	env.ambient_light_energy = 0.6
	amb.environment = env
	add_child(amb)

	# Starfield: small emissive boxes drifting toward the camera.
	var smat := GraphicsPolish.glow(Color(0.85, 0.92, 1.0), 1.2)
	for i in 150:
		var st := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.03, 0.09)
		bm.size = Vector3(s, s, s)
		st.mesh = bm
		st.material_override = smat
		st.position = Vector3(randf_range(-9.0, 9.0), randf_range(-1.0, 6.0), randf_range(-22.0, 4.0))
		add_child(st)
		_stars.append(st)


func _mat(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := GraphicsPolish.glow(emission, energy)
	m.albedo_color = color
	m.roughness = 0.4
	return m


func _build_player() -> void:
	# Cyan wedge-ish ship: flat body + nose + twin wings + cockpit.
	_player = MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.55, 0.16, 0.85)
	_player.mesh = body
	_player_mat = _mat(Color(0.1, 0.7, 0.9), Color(0.1, 0.75, 1.0), 1.4)
	_player.material_override = _player_mat
	_player.position = _player_target
	add_child(_player)

	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.30, 0.12, 0.35)
	nose.mesh = nm
	nose.material_override = _player_mat
	nose.position = Vector3(0.0, 0.0, -0.55)
	nose.rotation.y = PI * 0.25
	_player.add_child(nose)

	for wx in [-0.42, 0.42]:
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.34, 0.06, 0.5)
		wing.mesh = wm
		wing.material_override = _player_mat
		wing.position = Vector3(wx, 0.0, 0.22)
		wing.rotation.y = -signf(wx) * 0.35
		_player.add_child(wing)

	var cock := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.11
	cm.height = 0.22
	cock.mesh = cm
	cock.material_override = _mat(Color(0.9, 1.0, 1.0), Color(0.7, 0.95, 1.0), 1.8)
	cock.position = Vector3(0.0, 0.14, -0.05)
	_player.add_child(cock)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.25, 0.55, 1.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_vignette)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.15, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

	_hud = GraphicsPolish.make_label("", 64, Color(0.8, 0.95, 1.0))
	_hud.position = Vector3(-4.4, 4.1, -3.0)
	_hud.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_hud.rotation_degrees = Vector3(0.0, 12.0, 0.0)
	_hud.pixel_size = 0.0075
	add_child(_hud)

	_banner = GraphicsPolish.make_label("", 96, Color(1.0, 0.85, 0.4))
	_banner.position = Vector3(0.0, 3.2, -3.0)
	_banner.pixel_size = 0.014
	add_child(_banner)


# ------------------------------------------------------------------ game flow

func _reset_game() -> void:
	for e in _enemies:
		(e as Enemy).node.queue_free()
	for b in _bullets:
		(b as Bullet).node.queue_free()
	_enemies.clear()
	_bullets.clear()
	if _over_node != null:
		_over_node.queue_free()
		_over_node = null
	Engine.time_scale = 1.0
	_score = 0
	_wave = 0
	_lives = 3
	_focus = 0.0
	_slow_active = false
	_stop_active = false
	_stop_cd = 0.0
	_invuln = 0.0
	_fire_timer = 0.0
	_player_target = Vector3(0.0, 1.8, PLAYER_Z)
	_player.position = _player_target
	_state = "playing"
	_next_wave()
	ARUpgradeKit.save_anchor("time-pilot_main", global_transform)


func _next_wave() -> void:
	_wave += 1
	_spawn_queue = 3 + _wave * 2
	_spawn_timer = 1.2
	_banner.text = "WAVE %d" % _wave
	_wave_banner_t = 2.0
	if _wave > 1:
		_score += 250 * (_wave - 1)


func _game_over() -> void:
	_state = "gameover"
	Engine.time_scale = 1.0
	_slow_active = false
	_stop_active = false
	_over_node = Node3D.new()
	add_child(_over_node)
	_mk_over_label("GAME OVER", Vector3(0.0, 2.9, -2.0), 0.028, Color(1.0, 0.3, 0.25))
	_mk_over_label("Score %d   Wave %d" % [_score, _wave], Vector3(0.0, 2.45, -2.0), 0.010, Color(1.0, 1.0, 1.0))
	_mk_over_label("Click or press R to fly again", Vector3(0.0, 2.15, -2.0), 0.008, Color(0.6, 1.0, 0.7))


func _mk_over_label(text: String, pos: Vector3, px: float, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 10
	_over_node.add_child(l)


# ------------------------------------------------------------------ spawning

func _spawn_enemy() -> void:
	var e := Enemy.new()
	e.hp = 2 if _wave >= 4 else 1
	e.speed = 1.6 + float(_wave) * 0.28
	e.drift_phase = randf() * TAU
	e.drift_amp = randf_range(0.3, 0.9)
	e.shoot_cd = randf_range(1.2, 2.4)
	var node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.55, 0.55)
	node.mesh = bm
	node.material_override = _mat(Color(0.9, 0.15, 0.15), Color(1.0, 0.2, 0.15), 1.3)
	# Keep spawns inside the room's x-bounds; z stays deep-field.
	var sp := Vector3(randf_range(-4.2, 4.2), randf_range(0.8, 3.6), -13.0)
	if not _room_walls.is_empty():
		# v0.7.0: enemies emerge from the real far wall face instead.
		sp = _room_wall_spawn()
	else:
		sp = ARUpgradeKit.clamp_to_room(sp)
		sp.z = -13.0
	node.position = sp
	node.rotation = Vector3(0.5, 0.7, PI * 0.25)  # rotated box reads as a diamond
	add_child(node)
	e.node = node
	_enemies.append(e)


func _enemy_shoot(e: Enemy) -> void:
	var b := Bullet.new()
	b.from_player = false
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	node.mesh = sm
	node.material_override = _mat(Color(1.0, 0.55, 0.1), Color(1.0, 0.5, 0.1), 1.8)
	node.position = e.node.position
	add_child(node)
	b.node = node
	var dir: Vector3 = (_player.position - e.node.position).normalized()
	b.vel = dir * ENEMY_BULLET_SPEED
	_bullets.append(b)


func _player_shoot(target: Vector3) -> void:
	var b := Bullet.new()
	b.from_player = true
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	node.mesh = sm
	node.material_override = _mat(Color(0.4, 1.0, 1.0), Color(0.3, 1.0, 1.0), 2.0)
	node.position = _player.position + Vector3(0.0, 0.0, -0.6)
	add_child(node)
	b.node = node
	b.vel = (target - node.position).normalized() * PLAYER_BULLET_SPEED
	_bullets.append(b)


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_d := 1e9
	for e in _enemies:
		var en := e as Enemy
		var d: float = en.node.position.distance_squared_to(_player.position)
		if d < best_d:
			best_d = d
			best = en
	return best


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_mouse_pos = mb.position
		if mb.pressed:
			if _state == "gameover":
				_reset_game()
				return
			if _rtime - _last_press < DOUBLE_CLICK:
				_trigger_time_stop()
				_last_press = -10.0
				_pressing = false
			else:
				_last_press = _rtime
				_press_start = _rtime
				_pressing = true
		else:
			_pressing = false
			_set_slow(false)
	elif event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position


func _poll_keys() -> void:
	var r := Input.is_key_pressed(KEY_R)
	var r_was: bool = _prev_keys.get(KEY_R, false)
	if r and not r_was and _state == "gameover":
		_reset_game()
	_prev_keys[KEY_R] = r

	var f := Input.is_key_pressed(KEY_F)
	var f_was: bool = _prev_keys.get(KEY_F, false)
	if f and not f_was and _state == "playing":
		_trigger_time_stop()
	_prev_keys[KEY_F] = f


func _pinch_active() -> bool:
	# Hand-tracking hook: wire to XR hand pinch in a future pass.
	return false


func _set_slow(on: bool) -> void:
	if _slow_active == on:
		return
	if on and (_stop_active or _state != "playing"):
		return
	_slow_active = on
	if not _stop_active:
		Engine.time_scale = SLOW_FACTOR if on else 1.0


func _trigger_time_stop() -> void:
	if _state != "playing" or _stop_active or _stop_cd > 0.0:
		return
	_stop_active = true
	_stop_t = STOP_TIME
	_stop_cd = STOP_COOLDOWN
	_set_slow(false)
	Engine.time_scale = 1.0
	_banner.text = "TIME STOP!"
	_wave_banner_t = 1.2


# ------------------------------------------------------------------ combat

func _damage_player() -> void:
	if _invuln > 0.0 or _state != "playing":
		return
	_lives -= 1
	_invuln = 1.5
	_focus = 0.0
	_flash_t = 1.0
	GraphicsPolish.spawn_sparks(self, _player.position, Color(1.0, 0.2, 0.2), 24)
	if _lives <= 0:
		_game_over()


func _kill_enemy(e: Enemy) -> void:
	var mult := 2.0 if _focus >= 100.0 else 1.0
	_score += int(100.0 * mult)
	GraphicsPolish.spawn_sparks(self, e.node.position, Color(1.0, 0.45, 0.15), 22)
	e.node.queue_free()
	_enemies.erase(e)


func _focus_mult() -> float:
	return 2.0 if _focus >= 100.0 else 1.0


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_time += delta
	var ud: float = delta / maxf(Engine.time_scale, 0.05)  # unscaled delta
	_rtime += ud
	_poll_keys()
	# Persist the playfield placement every 30s.
	_anchor_t += delta
	if _anchor_t >= 30.0:
		_anchor_t = 0.0
		ARUpgradeKit.save_anchor("time-pilot_main", global_transform)
	# XR hand: a pinch starts a press (hold = slow-mo), like the mouse.
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		if _state == "gameover":
			_reset_game()
		else:
			_press_start = _rtime
			_pressing = true
	if _pressing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
		_pressing = false
		_set_slow(false)

	# Starfield drift (uses scaled time: slows in slow-mo).
	for st in _stars:
		var s := st as MeshInstance3D
		s.position.z += 1.6 * delta
		if s.position.z > 5.0:
			s.position.z = -22.0
			s.position.x = randf_range(-9.0, 9.0)
			s.position.y = randf_range(-1.0, 6.0)

	if _state == "gameover":
		_update_hud()
		return

	_update_time_powers(ud)
	_update_player(ud)
	_update_spawning(delta)
	_update_enemies(delta)
	_update_bullets(delta, ud)
	_update_hud()

	_flash_t = maxf(0.0, _flash_t - ud * 2.0)
	_flash.color = Color(1.0, 0.15, 0.1, _flash_t * 0.45)


func _update_time_powers(ud: float) -> void:
	# Hold-to-slow: press held past the threshold engages slow-mo.
	if _pressing and not _stop_active:
		if _rtime - _press_start > HOLD_TO_SLOW or ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			_set_slow(true)
	if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT) and not _stop_active:
		_set_slow(true)

	# Time stop countdown (real time).
	if _stop_active:
		_stop_t -= ud
		if _stop_t <= 0.0:
			_stop_active = false
	_stop_cd = maxf(0.0, _stop_cd - ud)

	# Vignette overlay.
	var target_a := 0.0
	var tint := Color(0.25, 0.55, 1.0)
	if _stop_active:
		target_a = 0.42 + 0.10 * sin(_rtime * 20.0)
		tint = Color(0.65, 0.85, 1.0)
	elif _slow_active:
		target_a = 0.20 + 0.06 * sin(_rtime * 6.0)
	var c := _vignette.color
	c = c.lerp(Color(tint.r, tint.g, tint.b, target_a), minf(1.0, ud * 8.0))
	_vignette.color = c


func _update_player(ud: float) -> void:
	# Mouse steers the ship on the z = PLAYER_Z plane (unscaled: stays nimble).
	if cam != null:
		var o := cam.project_ray_origin(_mouse_pos)
		var d := cam.project_ray_normal(_mouse_pos)
		if absf(d.z) > 0.0001:
			var t := (PLAYER_Z - o.z) / d.z
			if t > 0.0:
				var p: Vector3 = o + d * t
				_player_target.x = clampf(p.x, -4.6, 4.6)
				_player_target.y = clampf(p.y, 0.35, 3.8)
	var k := 1.0 - exp(-10.0 * ud)
	_player.position = _player.position.lerp(_player_target, k)
	# Bank into turns.
	var vx: float = (_player_target.x - _player.position.x)
	_player.rotation.z = clampf(-vx * 0.6, -0.6, 0.6)

	_invuln = maxf(0.0, _invuln - ud)
	_player_mat.emission_energy_multiplier = 0.4 + 1.0 * absf(sin(_rtime * 8.0)) if _invuln > 0.0 else 1.4

	# Auto-fire at the nearest enemy (unscaled: constant rate even in slow-mo).
	_fire_timer -= ud
	if _fire_timer <= 0.0:
		var target := _nearest_enemy()
		if target != null:
			_player_shoot(target.node.position)
			_fire_timer = FIRE_INTERVAL


func _update_spawning(delta: float) -> void:
	if _spawn_queue > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_enemy()
			_spawn_queue -= 1
			_spawn_timer = randf_range(0.5, 1.1)
	elif _enemies.is_empty():
		_next_wave()
	_wave_banner_t = maxf(0.0, _wave_banner_t - delta)
	if _wave_banner_t <= 0.0 and _banner.text != "":
		_banner.text = ""


func _update_enemies(delta: float) -> void:
	if _stop_active:
		return  # frozen solid during time stop
	for e in _enemies.duplicate():
		var en := e as Enemy
		var n := en.node
		n.position.z += en.speed * delta
		n.position.x += sin(_time * 2.2 + en.drift_phase) * en.drift_amp * delta
		n.rotation.y += delta * 2.5
		# Passed the player: counts as a dodge if it got close.
		if n.position.z > PLAYER_Z + 2.0:
			var lateral := Vector2(n.position.x - _player.position.x, n.position.y - _player.position.y).length()
			if lateral < 1.1 and _slow_active:
				_focus = minf(100.0, _focus + 12.0)
			n.queue_free()
			_enemies.erase(en)
			continue
		# Shoot at the player.
		en.shoot_cd -= delta
		if en.shoot_cd <= 0.0 and n.position.z > -11.0:
			_enemy_shoot(en)
			en.shoot_cd = randf_range(1.4, 2.6)
		# Ram the player.
		if n.position.distance_to(_player.position) < PLAYER_R + ENEMY_R:
			_kill_enemy(en)
			_damage_player()


func _update_bullets(delta: float, ud: float) -> void:
	for b in _bullets.duplicate():
		var bl := b as Bullet
		var n := bl.node
		if bl.from_player:
			n.position += bl.vel * ud   # player shots ignore slow-mo
		elif not _stop_active:
			n.position += bl.vel * delta  # enemy shots slow down
		bl.life -= ud
		if bl.life <= 0.0 or n.position.z < -16.0 or n.position.z > 8.0 or absf(n.position.x) > 9.0:
			_despawn_bullet(bl, false)
			continue
		# v0.7.0 RoomKit: bullets interact with real wall planes.
		if not _room_walls.is_empty():
			var gp: Vector3 = to_global(n.position)
			if bl.from_player:
				# Player shots burst against the far wall instead of flying on.
				if _room_bullet_wall_hit(gp):
					n.queue_free()
					_bullets.erase(bl)
					continue
			else:
				# Enemy shots ricochet off real walls (normal-sign agnostic).
				var gv: Vector3 = global_transform.basis * bl.vel
				var nv: Vector3 = _bounce_walls(gp, gv, 0.15)
				if nv != gv:
					bl.vel = global_transform.basis.inverse() * nv
					GraphicsPolish.spawn_sparks(self, gp, Color(1.0, 0.6, 0.2), 8)
		if bl.from_player:
			for e in _enemies.duplicate():
				var en := e as Enemy
				if n.position.distance_to(en.node.position) < 0.55:
					en.hp -= 1
					n.queue_free()
					_bullets.erase(bl)
					if en.hp <= 0:
						_kill_enemy(en)
					break
		else:
			var d: float = n.position.distance_to(_player.position)
			bl.min_d = minf(bl.min_d, d)
			if d < PLAYER_R + 0.13:
				_despawn_bullet(bl, false)
				_damage_player()


func _despawn_bullet(bl: Bullet, _count_dodge: bool) -> void:
	# Enemy bullet that flew past close by while slowed: focus reward.
	if not bl.from_player and _slow_active and not _stop_active:
		if bl.min_d < 0.85 and bl.min_d > PLAYER_R + 0.13:
			_focus = minf(100.0, _focus + 10.0)
	bl.node.queue_free()
	_bullets.erase(bl)


func _update_hud() -> void:
	var stop_txt := "READY (double-click / F)"
	if _stop_active:
		stop_txt = "ACTIVE %.1fs" % _stop_t
	elif _stop_cd > 0.0:
		stop_txt = "cooldown %.0fs" % _stop_cd
	var mode := "NORMAL"
	if _stop_active:
		mode = "TIME STOP"
	elif _slow_active:
		mode = "SLOW-MO"
	var focus_bar := ""
	var segs := int(_focus / 10.0)
	for i in 10:
		focus_bar += "#" if i < segs else "-"
	_hud.text = "TIME-PILOT  [%s]\nScore %d   Wave %d   Lives %d\nFocus [%s] %d%%%s\nTime stop: %s\nHold click: slow-mo" % [
		mode, _score, _wave, _lives,
		focus_bar, int(_focus), "  x2 SCORE!" if _focus >= 100.0 else "",
		stop_txt,
	]
