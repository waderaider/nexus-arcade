## NullGGame.gd - NULL-G LEAGUE: zero-G disc sport in your room.
## You + 2 AI vs 3 AI, 5-minute matches, arena = your real room bounds
## (RoomKit; 4x4m fallback). Push off real walls to launch, grab the disc
## mid-flight, throw through the center-room goal ring. Slow-mo replay of
## the winning goal. Body-tracking capsule avatars.
extends Node3D
class_name NullGGame

## v0.11.0: combat pause profile — hands are always busy; the floating
## pause glyph hides and the menu button needs a 0.45s hold.
static var pause_profile := "combat"

const STEM := "nullg_league"
const MATCH_SECS := 300.0
const RING_R := 0.5
const THRUST := 5.0
const MAX_SPD := 7.0
const BRAKE := 4.0
const GRAB_DIST := 0.8
const SAVE_PATH := "user://nullg_league.cfg"

var controller_config := {
	"buttons": {
		"trigger": "Thrust / Throw disc",
		"grip": "Air brake (grab air)",
		"thumbstick": "—",
	}
}

var _state := "countdown"  # countdown | play | goal | replay | ended
var _state_t := 0.0
var _count := 3
var _time_left := MATCH_SECS
var _score_us := 0
var _score_them := 0
var _last_tick_sec := -1

var _arena := Rect2(-2, -2, 4, 4)
var _y_min := 0.25
var _y_max := 2.9
var _ring_pos := Vector3.ZERO
var _ring_normal := Vector3(0, 0, 1)

var _disc: NullGDisc
var _agents: Array[NullGAgent] = []
var _player_avatar: NullGAvatar

var _xr := false
var _origin: Node3D = null
var _cam: Camera3D = null
var _ctl_l: XRController3D = null
var _ctl_r: XRController3D = null
var _pvel := Vector3.ZERO
var _ctl_hist := {}  # instance_id -> Array[Vector3]
var _hold_ctl: XRController3D = null
var _trig_prev := {}
var _thrust_prev := {}
var _grip_prev := {}
var _bounce_cd := 0.0
var _autopilot: NullGAgent = null  # desktop/headless player stand-in

var _scoreboard: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _replay_disc: MeshInstance3D
var _replay_path: Array[Vector3] = []
var _replay_t := 0.0
var _prev_disc_side := 0.0
var _stall_t := 0.0
var _wins := 0
var _losses := 0
var _arena_edge_mat: StandardMaterial3D = null  # ambient pulse
var _amb_t := 0.0


func _ready() -> void:
	_register_sfx()
	_load_record()
	_find_xr()
	_build_arena()
	_build_ring()
	_build_disc()
	_build_ambient()
	_build_agents()
	_build_hud()
	_announce_text("NULL-G LEAGUE\nThe orbital arenas went dark.\nPush off your walls. This is the league now.", 2.5)
	JuiceFX.title_card("NULL-G LEAGUE", "The arenas went dark. The league went underground.", Color(0.2, 0.9, 1.0))


func _register_sfx() -> void:
	if get_node_or_null("/root/AudioKit") == null:
		return
	var d := "res://assets/audio/sfx/"
	AudioKit.set_active_scene(STEM)
	AudioKit.register_game_sfx(STEM, {
		"throw": d + "nullg_throw.wav",
		"catch": d + "nullg_catch.wav",
		"goal": d + "nullg_goal.wav",
		"wallpush": d + "nullg_wallpush.wav",
		"buzzer": d + "nullg_buzzer.wav",
		"tick": d + "nullg_tick.wav",
	})


func _load_record() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_wins = int(cfg.get_value("league", "wins", 0))
		_losses = int(cfg.get_value("league", "losses", 0))


func _save_record() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("league", "wins", _wins)
	cfg.set_value("league", "losses", _losses)
	cfg.save(SAVE_PATH)


func _find_xr() -> void:
	if get_node_or_null("/root/ARUpgradeKit") != null and ARUpgradeKit.is_xr_active():
		_xr = true
	if not _xr:
		return
	var found := get_tree().root.find_children("*", "XROrigin3D", true, false)
	if found.is_empty():
		_xr = false
		return
	_origin = found[0] as Node3D
	_cam = _origin.get_node_or_null("XRCamera3D") as Camera3D
	_ctl_l = _origin.get_node_or_null("LeftController") as XRController3D
	_ctl_r = _origin.get_node_or_null("RightController") as XRController3D
	if _cam == null:
		_xr = false


func _build_arena() -> void:
	if get_node_or_null("/root/RoomKit") != null and RoomKit.has_room_data():
		_arena = RoomKit.room_bounds()
		# Clamp silly scans to a sane arena.
		_arena.size.x = clampf(_arena.size.x, 2.5, 12.0)
		_arena.size.y = clampf(_arena.size.y, 2.5, 12.0)
	# Arena edge glow: thin emissive frame on the floor.
	var cx := _arena.position.x + _arena.size.x * 0.5
	var cz := _arena.position.y + _arena.size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.6
	_arena_edge_mat = mat  # ambient: slow boundary glow pulse
	for edge in _arena_edges():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(edge[1], 0.03, edge[2])
		mi.mesh = bm
		mi.position = Vector3(edge[0].x, 0.02, edge[0].y)
		mi.material_override = mat
		add_child(mi)
	_ring_pos = Vector3(cx, 1.7, cz)


func _arena_edges() -> Array:
	var x0 := _arena.position.x
	var z0 := _arena.position.y
	var sx := _arena.size.x
	var sz := _arena.size.y
	var cx := x0 + sx * 0.5
	var cz := z0 + sz * 0.5
	return [
		[Vector2(cx, z0), sx, 0.06], [Vector2(cx, z0 + sz), sx, 0.06],
		[Vector2(x0, cz), 0.06, sz], [Vector2(x0 + sx, cz), 0.06, sz],
	]


func _build_ring() -> void:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = RING_R
	tor.outer_radius = RING_R + 0.07
	ring.mesh = tor
	ring.rotation = Vector3(PI / 2.0, 0, PI / 4.0)
	ring.position = _ring_pos
	# Goal-ring energy shimmer: scrolling stripe shader, 0 CPU.
	var shmat := ShaderMaterial.new()
	shmat.shader = load("res://assets/shaders/energy_shimmer.gdshader")
	shmat.set_shader_parameter("color_a", Color(1.0, 0.62, 0.08))
	shmat.set_shader_parameter("color_b", Color(1.0, 0.95, 0.55))
	shmat.set_shader_parameter("stripes", 28.0)
	shmat.set_shader_parameter("scroll_speed", 1.2)
	ring.material_override = shmat
	add_child(ring)
	_ring_normal = Vector3(0, 0, 1)  # ring plane faces +/- Z after X-rotation
	# Goal shimmer: slow spin for readability.
	var spin := Node3D.new()
	spin.name = "RingSpin"
	add_child(spin)


func _build_disc() -> void:
	_disc = NullGDisc.new()
	_disc.arena = _arena
	_disc.y_min = _y_min
	_disc.y_max = _y_max
	add_child(_disc)
	_reset_disc(Vector3(0, 0, 1.5))


## Animator ambient-life set (v0.11.0): boundary pulse (in _process),
## ice-crystal dust, goal shimmer (in _build_ring), scoreboard light chase.
func _build_ambient() -> void:
	var cx := _arena.position.x + _arena.size.x * 0.5
	var cz := _arena.position.y + _arena.size.y * 0.5
	# Ice-crystal dust drifting in zero-G: 1 capped emitter.
	AmbientKit.dust(self, Vector3(cx, 1.6, cz), 32,
		Color(0.7, 0.9, 1.0, 0.4), 0.02, 0.1, 0.0)
	# Scoreboard light chase: thin bar with the shimmer shader, 0 CPU.
	var chase := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.05, 0.05)
	chase.mesh = bm
	chase.position = _ring_pos + Vector3(0, 0.72, 0)
	var shmat := ShaderMaterial.new()
	shmat.shader = load("res://assets/shaders/energy_shimmer.gdshader")
	shmat.set_shader_parameter("color_a", Color(0.1, 0.8, 1.0))
	shmat.set_shader_parameter("color_b", Color(0.9, 1.0, 1.0))
	shmat.set_shader_parameter("stripes", 10.0)
	shmat.set_shader_parameter("scroll_speed", 3.0)
	shmat.set_shader_parameter("brightness", 1.8)
	chase.material_override = shmat
	add_child(chase)


func _process(delta: float) -> void:
	# Ambient: arena boundary glow pulse (slow, 0.4Hz).
	_amb_t += delta
	if _arena_edge_mat != null:
		_arena_edge_mat.emission_energy_multiplier = 1.6 + 0.5 * sin(_amb_t * TAU * 0.4)


func _reset_disc(toss: Vector3) -> void:
	_disc.toss_to(_ring_pos + Vector3(0, 0.4, 0), toss)
	_prev_disc_side = 0.0
	_stall_t = 0.0


func _build_agents() -> void:
	var cyan := Color(0.15, 0.85, 1.0)
	var magenta := Color(1.0, 0.25, 0.55)
	var cx := _arena.position.x + _arena.size.x * 0.5
	var cz := _arena.position.y + _arena.size.y * 0.5
	var spots := [
		[0, Vector3(cx - 1.5, 1.5, cz + 1.0), 0.55],
		[0, Vector3(cx - 1.5, 1.5, cz - 1.0), 0.5],
		[1, Vector3(cx + 1.5, 1.5, cz + 1.0), 0.55],
		[1, Vector3(cx + 1.5, 1.5, cz - 1.0), 0.5],
		[1, Vector3(cx + 1.5, 1.2, cz), 0.6],
	]
	for i in spots.size():
		var a := NullGAgent.new()
		a.name = "Agent%d" % i
		a.setup(int(spots[i][0]), cyan if int(spots[i][0]) == 0 else magenta,
				float(spots[i][2]), _arena)
		a.position = spots[i][1] as Vector3
		add_child(a)
		_agents.append(a)
	# Player avatar: capsule at the player's body.
	_player_avatar = NullGAvatar.make(cyan)
	add_child(_player_avatar)
	if not _xr:
		_autopilot = NullGAgent.new()
		_autopilot.name = "Autopilot"
		_autopilot.setup(0, cyan, 0.6, _arena)
		_autopilot.position = Vector3(cx - 2.0, 1.5, cz)
		_autopilot.avatar.visible = false  # the capsule avatar covers it
		add_child(_autopilot)


func _build_hud() -> void:
	_scoreboard = Label3D.new()
	_scoreboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_scoreboard.no_depth_test = true
	_scoreboard.font_size = 96
	_scoreboard.pixel_size = 0.004
	_scoreboard.position = _ring_pos + Vector3(0, 1.1, 0)
	_scoreboard.modulate = Color(1, 1, 1)
	_scoreboard.outline_modulate = Color(0, 0, 0)
	_scoreboard.outline_size = 12
	add_child(_scoreboard)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.no_depth_test = true
	_announce.font_size = 128
	_announce.pixel_size = 0.004
	_announce.modulate = Color(1, 0.95, 0.6)
	_announce.outline_modulate = Color(0, 0, 0)
	_announce.outline_size = 16
	_announce.visible = false
	add_child(_announce)
	_update_scoreboard()


func _update_scoreboard() -> void:
	var mm := int(_time_left) / 60
	var ss := int(_time_left) % 60
	_scoreboard.text = "YOU %d : %d OPP\n%d:%02d" % [_score_us, _score_them, mm, ss]


func _announce_text(t: String, dur := 2.0) -> void:
	_announce.text = t
	_announce.visible = true
	_announce_t = dur
	if _xr and _cam != null:
		var fwd := -_cam.global_transform.basis.z
		_announce.global_position = _cam.global_position + fwd * 2.2
	else:
		_announce.global_position = _ring_pos + Vector3(0, 0.2, 2.0)


# ------------------------------------------------------------------ loop ---

func _physics_process(delta: float) -> void:
	match _state:
		"countdown":
			_state_t += delta
			var n := 3 - int(_state_t)
			if n != _count and n >= 0:
				_count = n
				_announce_text("GO!" if n == 0 else str(n), 0.9)
				if get_node_or_null("/root/AudioKit") != null:
					AudioKit.play_game_sfx("tick")
			if _state_t >= 3.2:
				_state = "play"
				_announce.visible = false
				if get_node_or_null("/root/AudioKit") != null:
					AudioKit.set_intensity(2)  # audio director §4d: driving
		"play":
			_time_left -= delta
			_update_scoreboard()
			_tick_clock()
			_tick_player(delta)
			_tick_agents(delta)
			_disc.physics_tick(delta)
			_tick_grab_throw(delta)
			_tick_goal()
			_tick_stall(delta)
			_tick_player_avatar()
			if _time_left <= 0:
				_end_match()
		"goal":
			_state_t += delta
			_tick_agents(delta * 0.15)  # drift in celebration slowdown
			_disc.physics_tick(delta * 0.15)
			if _state_t >= 2.5:
				_state = "play"
				_announce.visible = false
				_reset_disc(Vector3(0, 0, 1.2 if _score_us >= _score_them else -1.2))
		"replay":
			_replay_t += delta
			_tick_replay()
		"ended":
			pass
	if _announce_t > 0:
		_announce_t -= delta
		if _announce_t <= 0:
			_announce.visible = false


func _tick_clock() -> void:
	var sec := int(ceil(_time_left))
	if sec <= 10 and sec != _last_tick_sec and sec > 0:
		_last_tick_sec = sec
		if get_node_or_null("/root/AudioKit") != null:
			AudioKit.play_game_sfx("tick")


func _player_head() -> Vector3:
	if _xr and _cam != null:
		return _cam.global_position
	if _autopilot != null:
		return _autopilot.global_position
	return Vector3.ZERO


func _tick_player(delta: float) -> void:
	if not _xr or _origin == null:
		if _autopilot != null:
			_think_autopilot(delta)
		return
	_bounce_cd = maxf(0.0, _bounce_cd - delta)
	var r_trig := _pressed(_ctl_r, "trigger", _thrust_prev)
	var l_trig := _pressed(_ctl_l, "trigger", _thrust_prev)
	var r_grip := _held(_ctl_r, "grip")
	var l_grip := _held(_ctl_l, "grip")
	# Thrust: right trigger -> swim forward (camera).
	if r_trig:
		var fwd := -_cam.global_transform.basis.z
		_pvel += fwd * THRUST * delta
		GameplayTelemetry.note_input_method("controllers")
	# Air brake: left trigger or any grip = grab the air.
	if l_trig or r_grip or l_grip:
		_pvel *= maxf(0.0, 1.0 - BRAKE * delta)
	if _pvel.length() > MAX_SPD:
		_pvel = _pvel.normalized() * MAX_SPD
	_origin.position += _pvel * delta
	_track_ctl(_ctl_l)
	_track_ctl(_ctl_r)
	_bounce_player()


func _pressed(ctl: XRController3D, action: String, prev: Dictionary) -> bool:
	if ctl == null or not is_instance_valid(ctl):
		return false
	if XRServer.get_tracker(ctl.tracker) == null:
		return false
	var now: bool = ctl.is_button_pressed("trigger_click") if action == "trigger" else ctl.is_button_pressed(action)
	var id: int = ctl.get_instance_id()
	var was := bool(prev.get(id, false))
	prev[id] = now
	return now


func _held(ctl: XRController3D, action: String) -> bool:
	if ctl == null or not is_instance_valid(ctl):
		return false
	if XRServer.get_tracker(ctl.tracker) == null:
		return false
	if action == "grip":
		return ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")
	return ctl.is_button_pressed(action)


func _track_ctl(ctl: XRController3D) -> void:
	if ctl == null or not is_instance_valid(ctl):
		return
	var id: int = ctl.get_instance_id()
	var h: Array = _ctl_hist.get(id, [])
	h.append(ctl.global_position)
	while h.size() > 6:
		h.remove_at(0)
	_ctl_hist[id] = h


func _ctl_velocity(ctl: XRController3D) -> Vector3:
	var id: int = ctl.get_instance_id()
	var h: Array = _ctl_hist.get(id, [])
	if h.size() < 2:
		return Vector3.ZERO
	var dt := (h.size() - 1) * (1.0 / 60.0)
	return ((h[h.size() - 1] as Vector3) - (h[0] as Vector3)) / maxf(dt, 0.001)


func _bounce_player() -> void:
	var p := _player_head()
	var bounced := false
	var impact := 0.0
	var x0 := _arena.position.x
	var z0 := _arena.position.y
	if p.x < x0 + 0.25:
		impact = maxf(impact, -_pvel.x)
		_pvel.x = absf(_pvel.x) * 0.75
		bounced = true
	elif p.x > x0 + _arena.size.x - 0.25:
		impact = maxf(impact, _pvel.x)
		_pvel.x = -absf(_pvel.x) * 0.75
		bounced = true
	if p.z < z0 + 0.25:
		impact = maxf(impact, -_pvel.z)
		_pvel.z = absf(_pvel.z) * 0.75
		bounced = true
	elif p.z > z0 + _arena.size.y - 0.25:
		impact = maxf(impact, _pvel.z)
		_pvel.z = -absf(_pvel.z) * 0.75
		bounced = true
	if p.y < _y_min + 0.2:
		impact = maxf(impact, -_pvel.y)
		_pvel.y = absf(_pvel.y) * 0.75
		bounced = true
	elif p.y > _y_max - 0.2:
		impact = maxf(impact, _pvel.y)
		_pvel.y = -absf(_pvel.y) * 0.75
		bounced = true
	if bounced:
		# Clamp the origin so the head stays in the arena.
		var head := _player_head()
		var corr := Vector3.ZERO
		corr.x = clampf(head.x, x0 + 0.25, x0 + _arena.size.x - 0.25) - head.x
		corr.z = clampf(head.z, z0 + 0.25, z0 + _arena.size.y - 0.25) - head.z
		corr.y = clampf(head.y, _y_min + 0.2, _y_max - 0.2) - head.y
		_origin.position += corr
		if impact > 1.6 and _bounce_cd <= 0.0:
			_bounce_cd = 0.5
			if get_node_or_null("/root/AudioKit") != null:
				AudioKit.play_game_sfx("wallpush")
			Haptics.impact(clampf(impact / 6.0, 0.1, 1.0))


func _think_autopilot(delta: float) -> void:
	var ctx := _ai_ctx()
	_autopilot.think(delta, ctx)
	_resolve_agent_disc(_autopilot, delta)


func _ai_ctx() -> Dictionary:
	var carrier: Node3D = null
	var holder_team := -1
	if _disc.holder != null:
		holder_team = _disc.last_team
		if _hold_ctl != null:
			carrier = _ctl_r if _ctl_r != null else null
		elif _disc.holder is NullGAgent:
			carrier = _disc.holder
	return {
		"disc_pos": _disc.global_position,
		"disc_vel": _disc.vel,
		"disc_free": _disc.is_free(),
		"disc_holder_team": holder_team,
		"goal_pos": _ring_pos,
		"carrier": carrier,
		"player_pos": _player_head(),
		"player_has_disc": _hold_ctl != null,
	}


func _tick_agents(delta: float) -> void:
	var ctx := _ai_ctx()
	for a in _agents:
		if not is_instance_valid(a):
			continue
		a.think(delta, ctx)
		_resolve_agent_disc(a, delta)


func _resolve_agent_disc(a: NullGAgent, _delta: float) -> void:
	if a.throw_request != Vector3.INF and a.has_disc:
		var target: Vector3 = a.throw_request
		a.throw_request = Vector3.INF
		a.has_disc = false
		var dir := (target - _disc.global_position)
		if dir.length() < 0.01:
			dir = Vector3(0, 0, 1)
		_disc.release(dir.normalized() * NullGAgent.THROW_SPEED)
		_disc.last_team = a.team
		return
	if _disc.is_free() and a.grab_cooldown <= 0.0:
		if a.global_position.distance_to(_disc.global_position) < NullGAgent.GRAB_RADIUS:
			a.grab_cooldown = 1.0
			a.has_disc = true
			_disc.grab(a, a, a.team)
			if a.team == 1:
				Haptics.tick("both")


func _tick_grab_throw(_delta: float) -> void:
	if not _xr:
		return
	for ctl in [_ctl_l, _ctl_r]:
		if ctl == null or not is_instance_valid(ctl):
			continue
		var id: int = ctl.get_instance_id()
		var now := XRUIPointer.trigger_pressed(ctl)
		var was := bool(_trig_prev.get(id, false))
		_trig_prev[id] = now
		if now and not was and _disc.is_free():
			if ctl.global_position.distance_to(_disc.global_position) < GRAB_DIST:
				_disc.grab("player", ctl, 0)
				_hold_ctl = ctl
				Haptics.confirm()
				GameplayTelemetry.note_input_method("controllers")
		elif not now and was and _hold_ctl == ctl:
			var v := _ctl_velocity(ctl) * 1.3
			if v.length() < 4.0:
				v = v.normalized() * 4.0 if v.length() > 0.01 else -_cam.global_transform.basis.z * 5.0
			if v.length() > 14.0:
				v = v.normalized() * 14.0
			_disc.release(v)
			_disc.last_team = 0
			_hold_ctl = null
			Haptics.impact(0.4)


func _tick_goal() -> void:
	var d: Vector3 = _disc.global_position - _ring_pos
	var side := signf(d.dot(_ring_normal))
	if _prev_disc_side == 0.0:
		_prev_disc_side = side
		return
	if side != _prev_disc_side and side != 0.0:
		var lateral: Vector3 = d - _ring_normal * d.dot(_ring_normal)
		if lateral.length() < RING_R and _disc.vel.length() > 0.8:
			_on_goal()
	_prev_disc_side = side


func _on_goal() -> void:
	var us := _disc.last_team == 0
	if us:
		_score_us += 1
	else:
		_score_them += 1
	_replay_path = _disc._trail_pts.duplicate()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("goal")
	Haptics.play_sequence("fanfare" if us else "error")
	# VFX artist: signature winning-goal moment (slow-mo handled by state).
	VFX.goal(self, _ring_pos, Color(0.2, 0.9, 1.0) if us else Color(1.0, 0.3, 0.6))
	_announce_text("GOAL!\nYOU %d : %d OPP" % [_score_us, _score_them], 2.4)
	_update_scoreboard()
	_state = "goal"
	_state_t = 0.0
	for a in _agents:
		a.has_disc = false
	_hold_ctl = null


func _tick_stall(delta: float) -> void:
	if _disc.is_free() and _disc.vel.length() < 0.4:
		_stall_t += delta
		if _stall_t > 6.0:
			_reset_disc(Vector3(0, 0, 1.0))
			_announce_text("DISC RESET", 1.2)
	else:
		_stall_t = 0.0


func _tick_player_avatar() -> void:
	if _player_avatar == null:
		return
	var head := _player_head()
	_player_avatar.global_position = Vector3(head.x, 0.02, head.z)
	if _xr and _cam != null:
		var fwd := -_cam.global_transform.basis.z
		_player_avatar.rotation.y = atan2(-fwd.x, -fwd.z)
	# Body-tracking mirror: lift/tilt the capsule from real joints.
	if get_node_or_null("/root/ARUpgradeKit") != null and BodyTracker.is_available():
		var j := BodyTracker.dance_joints(_origin)
		var hips: Variant = j["hips"]
		if hips != null:
			var h := hips as Vector3
			_player_avatar.global_position = Vector3(h.x, 0.02, h.z)


func _end_match() -> void:
	_time_left = 0
	_update_scoreboard()
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("buzzer")
		AudioKit.set_intensity(0)
	var result := "draw"
	if _score_us > _score_them:
		_wins += 1
		result = "win"
	elif _score_us < _score_them:
		_losses += 1
		result = "loss"
	_save_record()
	if not _replay_path.is_empty() and _score_us != _score_them:
		_start_replay()
	else:
		_show_final(result)


func _start_replay() -> void:
	_state = "replay"
	_replay_t = 0.0
	_replay_disc = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	_replay_disc.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	_replay_disc.material_override = mat
	add_child(_replay_disc)
	_disc.visible = false
	_announce_text("WINNING GOAL — REPLAY", 3.6)
	if get_node_or_null("/root/AudioKit") != null:
		AudioKit.play_game_sfx("goal")


func _tick_replay() -> void:
	# 0.3x slow-mo over ~4s.
	var dur := 4.0
	var t := clampf(_replay_t / dur, 0.0, 1.0)
	var n := _replay_path.size()
	if n > 1 and _replay_disc != null:
		var f := t * float(n - 1)
		var i := mini(int(f), n - 2)
		_replay_disc.global_position = (_replay_path[i] as Vector3).lerp(
				_replay_path[i + 1] as Vector3, f - float(i))
	if _replay_t >= dur:
		if is_instance_valid(_replay_disc):
			_replay_disc.queue_free()
		_disc.visible = true
		_show_final("win" if _score_us > _score_them else ("loss" if _score_us < _score_them else "draw"))


func _show_final(result: String) -> void:
	_state = "ended"
	var banner := "DRAW"
	if result == "win":
		banner = "VICTORY!"
	elif result == "loss":
		banner = "DEFEAT"
	_announce_text("%s\nYOU %d : %d OPP\nCareer %dW-%dL" % [banner, _score_us, _score_them, _wins, _losses], 30.0)
