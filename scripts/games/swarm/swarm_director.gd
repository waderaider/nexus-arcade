## SwarmDirector.gd - wave state machine (Build -> Wave -> Rest), spawn budget,
## and energy economy. (Port of Unity's SwarmDirector.cs.)
##   Build: player places turrets (left click / XR trigger), costs energy.
##   Wave:  enemies spawn from wall portals until the budget is spent and all
##          enemies are destroyed.
##   Rest:  breather before the next build phase.
extends Node3D
class_name SwarmDirector

signal wave_started(wave: int)
signal game_over(score: int)

enum Phase { BUILD, WAVE, REST }

const MAX_ENERGY := 150.0
const ENERGY_REGEN := 3.0
const TURRET_COST := 30.0
const MAX_TURRETS := 8
const FIRST_BUILD_TIME := 20.0
const BUILD_TIME := 12.0
const REST_TIME := 6.0
const SPAWN_INTERVAL := 1.2

var phase: int = Phase.BUILD
var wave := 0
var score := 0
var energy := 100.0
var difficulty := 0.0

var core: SwarmCore
var portals: Array[WallPortal] = []

var phase_label: Label3D
var score_label: Label3D
var wave_label: Label3D
var core_label: Label3D

var _phase_timer := FIRST_BUILD_TIME
var _to_spawn := 0
var _spawn_timer := 0.0
var _turret_count := 0
var _game_over := false


func _ready() -> void:
	add_to_group("swarm_director")
	if core != null:
		core.core_destroyed.connect(_on_core_destroyed)


## Voice command: skip the build phase and start the wave now.
func skip_build_phase() -> void:
	if phase == Phase.BUILD and not _game_over:
		_start_wave()


## Called by SwarmEnemy when a turret or the player destroys it.
func on_enemy_killed(_enemy: SwarmEnemy) -> void:
	score += 10 + wave * 2
	energy = minf(MAX_ENERGY, energy + 6.0)


## Called by SwarmEnemy when it reaches the Core.
func on_enemy_reached_core(_enemy: SwarmEnemy) -> void:
	difficulty = minf(1.0, difficulty + 0.02)


func _process(delta: float) -> void:
	if _game_over:
		return

	energy = minf(MAX_ENERGY, energy + ENERGY_REGEN * delta)
	_xr_place_input()

	_phase_timer -= delta
	match phase:
		Phase.BUILD:
			if _phase_timer <= 0.0:
				_start_wave()
		Phase.WAVE:
			_spawn_timer -= delta
			if _to_spawn > 0:
				if _spawn_timer <= 0.0:
					_spawn_one()
					_spawn_timer = SPAWN_INTERVAL
			elif get_tree().get_nodes_in_group("swarm_enemies").is_empty():
				_end_wave()
		Phase.REST:
			if _phase_timer <= 0.0:
				_start_build()

	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if phase != Phase.BUILD:
		return
	# Turret placement ray: from camera through the click point.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.project_ray_origin(mb.position)
	var dir := cam.project_ray_normal(mb.position)
	var point := _pick_place_point(origin, dir)
	_place_turret(point)


## XR: trigger during Build places a turret in front of the camera.
func _xr_place_input() -> void:
	if _game_over or phase != Phase.BUILD:
		return
	var pressed := false
	if InputMap.has_action("trigger_click") and Input.is_action_just_pressed("trigger_click"):
		pressed = true
	if not pressed:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var point := cam.global_position + fwd * 2.2
	point.y = maxf(point.y, 0.05)
	_place_turret(point)


func _pick_place_point(origin: Vector3, dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 10.0)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		p.y = maxf(p.y, 0.05)
		return p
	var fallback := origin + dir * 1.2
	fallback.y = maxf(fallback.y, 0.05)
	return fallback


func _place_turret(point: Vector3) -> void:
	if _turret_count >= MAX_TURRETS:
		return
	if energy < TURRET_COST:
		return
	var turret := SwarmTurret.place(point)
	get_parent().add_child(turret)
	energy -= TURRET_COST
	_turret_count += 1
	SwarmEnemy.spawn_pop(get_parent(), point, Color(0.2, 1.0, 0.4), 2.0)


func _start_build() -> void:
	phase = Phase.BUILD
	_phase_timer = BUILD_TIME


func _start_wave() -> void:
	wave += 1
	phase = Phase.WAVE
	_to_spawn = 4 + wave * 2 + int(round(difficulty * 4.0))
	_spawn_timer = 0.5
	wave_started.emit(wave)


func _end_wave() -> void:
	phase = Phase.REST
	_phase_timer = REST_TIME
	score += 20


func _spawn_one() -> void:
	if portals.is_empty() or core == null:
		_to_spawn = 0
		return
	var portal: WallPortal = portals[randi() % portals.size()]
	if portal == null or not is_instance_valid(portal):
		return
	portal.spawn_enemy(wave, difficulty, core, self)
	_to_spawn -= 1


func _on_core_destroyed() -> void:
	_game_over = true
	game_over.emit(score)
	_refresh_hud()


func _refresh_hud() -> void:
	_set_label(phase_label, _phase_text())
	_set_label(score_label, "SCORE " + str(score))
	_set_label(wave_label, "WAVE " + str(wave))
	if core != null:
		_set_label(core_label, "CORE HP " + str(int(ceil(core.hp))))


func _phase_text() -> String:
	if _game_over:
		return "CORE DESTROYED - GAME OVER (SCORE " + str(score) + ")"
	var t := str(int(ceil(maxf(0.0, _phase_timer)))) + "s"
	match phase:
		Phase.BUILD:
			return "BUILD " + t + " | E " + str(int(round(energy)))
		Phase.WAVE:
			var left := _to_spawn + get_tree().get_nodes_in_group("swarm_enemies").size()
			return "WAVE " + str(wave) + " | LEFT " + str(left)
		_:
			return "REST " + t


static func _set_label(label: Label3D, text: String) -> void:
	if label != null and is_instance_valid(label) and label.text != text:
		label.text = text
