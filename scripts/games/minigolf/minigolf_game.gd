## MinigolfGame.gd - NEXUS GREENS main controller.
## 18-hole roomscale minigolf: room-perimeter course loop, stroke play vs par 54,
## zone medals, Legends Board persistence, pass-and-play.
## Design: ~/workspace/design/minigolf/MINIGOLF_GAME_DESIGN.md
extends Node3D
class_name MinigolfGame

signal hole_completed(hole_number: int, strokes: int)
signal round_completed(total_strokes: int)

const SAVE_PATH := "user://nexus_greens_save.cfg"
const TOTAL_HOLES := 18
const PAR_TOTAL := 54

## Hole registry: ordered list of {number, name, par, zone, scene}.
## Scenes live in scenes/minigolf/holes/hole_XX.tscn (built by the coordinator).
var _holes: Array = []
var _current_hole_idx := 0
var _current_hole: MinigolfHole = null
var _ball: MinigolfBall = null
var _club: Node3D = null  # MinigolfClub (controller-tracked; built after API Guru)
var _celebration: Node = null

# Scoring.
var _strokes: Array = []       # strokes per hole, indexed 0..17
var _aces: Array = []          # hole numbers with hole-in-one
var _round_start_unix := 0.0
var _legends_best := 0         # best 18-hole total (persisted)
var _legends_aces := 0         # lifetime aces (persisted)

# Pass-and-play.
var _players: Array = []       # [{name, color, strokes: Array}]
var _player_idx := 0

var _seater: MinigolfSeater = null

# Power-ups (Game Design §7): one held token at a time, per-hole.
var _held_token_kind := ""
var _held_token_node: MinigolfPowerup = null
var _token_spawned_this_hole := false


## Play mode: "vr" (floating course) or "ar" (real-room course).
## wade's ship-blocker (2026-10-09): AR mode builds the course from the
## player's real room via RoomKit anchors.
var _mode := "vr"
var _mode_selected := false


func _ready() -> void:
	_build_hole_registry()
	_seater = MinigolfSeater.new()
	add_child(_seater)
	_load_legends()
	_round_start_unix = Time.get_unix_time_from_system()
	_show_mode_select()
	_telemetry_round_start()


## Mode-select screen: VR Course vs AR Room Golf. Simple 2D, laser+trigger.
## AR is offered only when RoomKit has room data; otherwise it's shown
## greyed with a "scan your room" hint.
func _show_mode_select() -> void:
	var ar_state := MinigolfARMode.scan_state()
	var ui := MinigolfUI.build_mode_select(ar_state)
	add_child(ui)
	ui.mode_chosen.connect(_on_mode_chosen)


func _on_mode_chosen(mode: String) -> void:
	_mode = mode
	_mode_selected = true
	if _mode == "ar":
		MinigolfARMode.enable_depth_occlusion()
		GameplayTelemetry.log_event("minigolf_ar_mode", {"scan": "ready"})
	else:
		GameplayTelemetry.log_event("minigolf_vr_mode", {})
	_start_hole(0)


func _build_hole_registry() -> void:
	# name, par, zone — matches the Game Designer §2 spec.
	var defs := [
		[1, "First Tee", 2, "greens"],
		[2, "The Gentle Dogleg", 2, "greens"],
		[3, "Potted Trouble", 2, "greens"],
		[4, "The Brass Rail", 3, "greens"],
		[5, "Water Hazard", 2, "greens"],
		[6, "The Captain's Loop", 3, "greens"],
		[7, "Gear Grinder", 3, "tinkerworks"],
		[8, "Piston Alley", 3, "tinkerworks"],
		[9, "The Copper Tube", 3, "tinkerworks"],
		[10, "Conveyor Cross", 4, "tinkerworks"],
		[11, "Steam Vent Saloon", 3, "tinkerworks"],
		[12, "The Big Loop", 3, "tinkerworks"],
		[13, "Trade Winds", 3, "skyreef"],
		[14, "Gull Gates", 3, "skyreef"],
		[15, "The Rope Bridge", 4, "skyreef"],
		[16, "Coral Maze", 4, "skyreef"],
		[17, "The Storm Cell", 4, "skyreef"],
		[18, "The Skyfall Finale", 4, "skyreef"],
	]
	for d in defs:
		_holes.append({
			"number": d[0],
			"name": d[1],
			"par": d[2],
			"zone": d[3],
			"scene": "res://scenes/minigolf/holes/hole_%02d.tscn" % d[0],
		})
		_strokes.append(0)


func _start_hole(idx: int) -> void:
	_current_hole_idx = idx
	var def: Dictionary = _holes[idx]
	# Free previous hole.
	if _current_hole != null and is_instance_valid(_current_hole):
		_current_hole.queue_free()
		_current_hole = null
	# Build the hole from the catalog spec (data-driven; no .tscn files).
	# MinigolfHoleBuilder constructs visuals + physics; MinigolfMechanics
	# adds the hole's trick features.
	var spec: Dictionary = MinigolfHoleCatalog.holes()[idx]
	_current_hole = MinigolfHoleBuilder.build(spec)
	if spec.has("extras"):
		MinigolfMechanics.build_extras(_current_hole, str(spec["extras"]))
	_current_hole.hole_number = def["number"]
	_current_hole.hole_name = def["name"]
	_current_hole.par = def["par"]
	_current_hole.zone = def["zone"]
	# Seat it: VR mode uses the room-perimeter seater; AR mode lays the hole
	# on the real floor and adapts it to the room's walls + furniture.
	if _mode == "ar":
		var ar_seat: Transform3D = _ar_seat_for_hole(idx, def)
		_current_hole.transform = ar_seat
		add_child(_current_hole)
		var adapt := MinigolfARMode.adapt_hole(_current_hole, def)
		_current_hole.set_meta("ar_notes", adapt["notes"])
		_telemetry_ar_adapt(def, adapt)
	else:
		var seat: Transform3D = _seater.seat_for_hole(idx, def)
		_current_hole.transform = seat
		add_child(_current_hole)
	_current_hole.on_hole_start()
	# Power-up token for this hole (Game Design §7 token table).
	_spawn_hole_token(def)
	# Ball.
	_ensure_ball()
	_ball.configure(_current_hole)
	_current_hole.set_ball(_ball)
	_ball.holed.connect(_on_ball_holed)
	_ball.hazard_drop.connect(_on_hazard_drop.bind(def))
	# Zone transition sting on zone boundaries.
	if idx in [0, 6, 12]:
		_play_zone_sting(def["zone"])
	_telemetry_hole_start(def)


## AR seating: lay holes on the real floor in a serpentine path through
## the room bounds, so the player physically walks the course.
func _ar_seat_for_hole(idx: int, _def: Dictionary) -> Transform3D:
	var bounds := RoomKit.room_bounds()
	if bounds.size.x <= 0.0:
		# No room data after all — fall back to the VR seater position.
		return _seater.seat_for_hole(idx, _def)
	var cols := 3
	var rows := 6
	var col: int = idx % cols
	var row: int = idx / cols
	# Serpentine: alternate direction per row.
	if row % 2 == 1:
		col = cols - 1 - col
	var fx: float = (float(col) + 0.5) / float(cols)
	var fz: float = (float(row) + 0.5) / float(rows)
	var x: float = bounds.position.x + fx * bounds.size.x
	var z: float = bounds.position.y + fz * bounds.size.y
	# Face the next hole (or the room center on the last).
	var yaw := 0.0
	if idx < TOTAL_HOLES - 1:
		var ncol: int = (idx + 1) % cols
		var nrow: int = (idx + 1) / cols
		if nrow % 2 == 1:
			ncol = cols - 1 - ncol
		var nx: float = bounds.position.x + (float(ncol) + 0.5) / float(cols) * bounds.size.x
		var nz: float = bounds.position.y + (float(nrow) + 0.5) / float(rows) * bounds.size.y
		yaw = atan2(nx - x, nz - z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.0, z))


func _telemetry_ar_adapt(def: Dictionary, adapt: Dictionary) -> void:
	GameplayTelemetry.log_event("minigolf_ar_adapt", {
		"hole": def["number"],
		"wall_banks": adapt.get("wall_banks", 0),
		"furniture": adapt.get("furniture_obstacles", 0),
		"tunnels": (adapt.get("tunnels", []) as Array).size(),
		"fallback": adapt.get("fallback", false),
	})


## Power-up tokens (Game Design §7): spawn the hole's token (once per round),
## one held at a time, no carrying between holes.
func _spawn_hole_token(def: Dictionary) -> void:
	# Clear any held token from the previous hole.
	_held_token_kind = ""
	_held_token_node = null
	_token_spawned_this_hole = false
	var token_kind := str(MinigolfHoleCatalog.holes()[_current_hole_idx].get("token", ""))
	if token_kind == "":
		return
	_token_spawned_this_hole = true
	var tee: Vector3 = _current_hole.tee_position()
	# Brass base pad beside the tee (token floats 0.55m above pad).
	var spawn_pos: Vector3 = _current_hole.to_local(tee) + Vector3(0.35, 0, 0.2)
	_held_token_node = MinigolfPowerup.spawn(_current_hole, self, token_kind, spawn_pos)
	GameplayTelemetry.log_event("minigolf_token_spawn", {
		"hole": def["number"], "kind": token_kind,
	})


func on_token_collected(kind: String) -> void:
	_held_token_kind = kind
	GameplayTelemetry.log_event("minigolf_token_collect", {
		"hole": _holes[_current_hole_idx]["number"], "kind": kind,
	})


## Trigger squeeze: activate the held token (Game Design §7: one verb).
func _try_activate_token() -> bool:
	if _held_token_kind == "" or _held_token_node == null:
		return false
	if not is_instance_valid(_held_token_node) or _held_token_node.collected == false:
		return false
	_held_token_node.activate(_ball, _current_hole)
	GameplayTelemetry.log_event("minigolf_token_activate", {
		"hole": _holes[_current_hole_idx]["number"], "kind": _held_token_kind,
	})
	_held_token_kind = ""
	_held_token_node = null
	return true


func _unhandled_input(event: InputEvent) -> void:
	# Trigger squeeze activates the held power-up token.
	if event.is_action_pressed("trigger_click"):
		_try_activate_token()


func _process(_delta: float) -> void:
	if _mode != "ar" or _current_hole == null or _ball == null:
		return
	_check_guardian_boundary()
	_check_lost_ball(_delta)


# AR safety: guardian is the course boundary (room_bounds shrunk 0.4m).
# Crossing it freezes the ball with a "Back inside the ropes" prompt.
var _guardian_shrunk := Rect2()
var _ball_frozen := false
var _lost_timer := 0.0


func _check_guardian_boundary() -> void:
	if _guardian_shrunk.size.x <= 0.0:
		var rb := RoomKit.room_bounds()
		_guardian_shrunk = Rect2(
			rb.position + Vector2(0.4, 0.4),
			rb.size - Vector2(0.8, 0.8))
	var bp := _ball.global_position
	var inside := _guardian_shrunk.has_point(Vector2(bp.x, bp.z))
	if not inside and not _ball_frozen:
		_ball_frozen = true
		_ball.velocity = Vector3.ZERO
		_show_rope_prompt(true)
		GameplayTelemetry.log_event("minigolf_guardian_exit", {})
	elif inside and _ball_frozen:
		_ball_frozen = false
		_show_rope_prompt(false)


func _show_rope_prompt(show: bool) -> void:
	# Floor prompt: "Back inside the ropes". (UI layer hook.)
	if show:
		AudioKit.play_sfx("ui_back")


## AR safety: a ball ending under/behind furniture (out of reach/sight)
## auto-returns to the drop point after 3s, no stroke penalty.
func _check_lost_ball(delta: float) -> void:
	if _ball.is_holed or not _ball.is_in_play:
		_lost_timer = 0.0
		return
	# Lost = ball is inside a furniture cuboid footprint and nearly stopped,
	# or ball hasn't moved and isn't visible (simplified: inside furniture).
	var lost := false
	var bp := _ball.global_position
	for ob in _current_hole.room_obstacles:
		var c: Vector3 = ob["position"]
		var s: Vector3 = ob["size"]
		if absf(bp.x - c.x) < s.x / 2.0 and absf(bp.z - c.z) < s.z / 2.0:
			if bp.y < c.y + s.y / 2.0:
				lost = true
				break
	if lost:
		_lost_timer += delta
		if _lost_timer >= 3.0:
			_lost_timer = 0.0
			_ball.drop_at(_current_hole.drop_position())
			AudioKit.play_sfx("mg_tee_pop")
			GameplayTelemetry.log_event("minigolf_ball_returned", {
				"hole": _holes[_current_hole_idx]["number"],
			})
	else:
		_lost_timer = 0.0


func _ensure_ball() -> void:
	if _ball != null and is_instance_valid(_ball):
		return
	_ball = MinigolfBall.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "BallMesh"
	# Real ball mesh (Blender custom) loaded when available; smooth sphere fallback.
	var glb := load("res://assets/minigolf/golf_ball.glb")
	if glb != null:
		var inst: Node3D = (glb as PackedScene).instantiate()
		mesh.add_child(inst)
	else:
		var sph := SphereMesh.new()
		sph.radius = 0.02135
		sph.height = 0.0427
		mesh.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.96, 0.96, 0.96)
		mat.roughness = 0.42
		mesh.material_override = mat
	_ball.add_child(mesh)
	add_child(_ball)


func on_putt(stroke_power: float) -> void:
	# Called by the club on a legal strike.
	if _current_hole == null:
		return
	_current_hole.on_stroke()
	_strokes[_current_hole_idx] += 1
	_telemetry_stroke(stroke_power)


func _on_ball_holed() -> void:
	var def: Dictionary = _holes[_current_hole_idx]
	var strokes: int = _strokes[_current_hole_idx]
	var is_ace := strokes == 1
	if is_ace:
		_aces.append(def["number"])
		_play_celebration(true)
	else:
		_play_celebration(false)
	hole_completed.emit(def["number"], strokes)
	_telemetry_hole_end(def, strokes, is_ace)
	# Advance after the celebration beat.
	await get_tree().create_timer(2.2).timeout
	_next_hole()


func _on_hazard_drop(kind: String, def: Dictionary) -> void:
	# +1 stroke, ball re-placed at the hole's drop point (never the tee).
	_strokes[_current_hole_idx] += 1
	_current_hole.on_stroke()
	_play_hazard_beat(kind)
	_ball.drop_at(_current_hole.drop_position())
	_telemetry_hazard(kind)


func _next_hole() -> void:
	if _current_hole_idx + 1 >= TOTAL_HOLES:
		_finish_round()
	else:
		_start_hole(_current_hole_idx + 1)


func restart_hole() -> void:
	# PauseExit restart path.
	_strokes[_current_hole_idx] = 0
	_start_hole(_current_hole_idx)


func _finish_round() -> void:
	var total := 0
	for s in _strokes:
		total += s
	var vs_par := total - PAR_TOTAL
	_update_legends(total, vs_par)
	_play_round_finale(vs_par)
	round_completed.emit(total)
	_telemetry_round_end(total, vs_par)
	# AR Design §4: offer the Home Tour (bonus AR holes) after hole 18.
	if _mode == "ar" and MinigolfHomeTour.can_offer():
		_offer_home_tour()


## Home Tour offer card: "The Home Tour — 5 bonus holes built on your
## furniture?" Yes/no, laser+trigger. Own scorecard; never touches par-54.
func _offer_home_tour() -> void:
	var matched := MinigolfHomeTour.match_holes()
	GameplayTelemetry.log_event("minigolf_home_tour_offered", {
		"matched": matched.size(),
	})
	var ui := MinigolfUI.build_home_tour_offer(matched)
	add_child(ui)
	ui.tour_chosen.connect(_on_home_tour_chosen.bind(matched))


func _on_home_tour_chosen(accepted: bool, matched: Array) -> void:
	GameplayTelemetry.log_event("minigolf_home_tour_accepted", {
		"accepted": accepted,
	})
	if accepted:
		_start_home_tour(matched)


var _tour_holes: Array = []
var _tour_idx := 0


func _start_home_tour(matched: Array) -> void:
	_tour_holes = matched
	_tour_idx = 0
	_start_tour_hole(0)


func _start_tour_hole(idx: int) -> void:
	_tour_idx = idx
	var tour_def: Dictionary = _tour_holes[idx]
	if _current_hole != null and is_instance_valid(_current_hole):
		_current_hole.queue_free()
	_current_hole = MinigolfHomeTour.build_tour_hole(tour_def)
	# Seat on the real floor near the matched feature.
	var seat := _ar_seat_for_hole(idx, tour_def)
	_current_hole.transform = seat
	add_child(_current_hole)
	_current_hole.on_hole_start()
	_ensure_ball()
	_ball.configure(_current_hole)
	_current_hole.set_ball(_ball)
	GameplayTelemetry.log_event("minigolf_home_tour_hole", {
		"tour_id": tour_def["id"], "name": tour_def["name"],
	})


# ------------------------------------------------------------------ juice ---

func _play_celebration(is_ace: bool) -> void:
	# Built by the celebration system (Tech-Demo Engineer §1 beat plan).
	if _celebration != null and is_instance_valid(_celebration):
		_celebration.queue_free()
	_celebration = MinigolfCelebration.new()
	add_child(_celebration)
	_celebration.play(_ball, _current_hole, is_ace)


func _play_hazard_beat(kind: String) -> void:
	# 0.8s splash/fall beat; sound + haptic via shared systems.
	var sfx := "mg_rail_click"
	if "water" in kind or "splash" in kind or "pond" in kind:
		sfx = "mg_splash_hazard"
	elif "wind" in kind or "storm" in kind:
		sfx = "mg_wind_gust"
	AudioKit.play_sfx(sfx)
	Haptics.play_sequence("lip_out")


func _play_zone_sting(zone: String) -> void:
	# Zone transition sting on holes 1/7/13 (zone name unused beyond logging).
	AudioKit.play_stinger("levelup")
	Haptics.tick()


func _play_round_finale(vs_par: int) -> void:
	# Fireworks over hole 18: fanfare + celebration haptics.
	AudioKit.play_sfx("mg_fanfare")
	if vs_par <= 0:
		Haptics.play_sequence("hole_in_one")
	else:
		Haptics.confirm()


# ------------------------------------------------------------------ save ---

func _load_legends() -> void:
	# Legends Board persistence: best 18-hole total + lifetime aces.
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_legends_best = int(cfg.get_value("legends", "best_total", 0))
		_legends_aces = int(cfg.get_value("legends", "total_aces", 0))


func _update_legends(total: int, vs_par: int) -> void:
	# vs_par is reported in telemetry; persistence keeps best + aces.
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep any existing keys
	var best := int(cfg.get_value("legends", "best_total", 0))
	if best == 0 or total < best:
		best = total
		cfg.set_value("legends", "best_total", best)
	_legends_best = best
	_legends_aces = int(cfg.get_value("legends", "total_aces", 0)) + _aces.size()
	cfg.set_value("legends", "total_aces", _legends_aces)
	cfg.save(SAVE_PATH)


# -------------------------------------------------------------- telemetry ---

func _telemetry_round_start() -> void:
	_tel().event("mg_round_start", {"holes": TOTAL_HOLES, "par": PAR_TOTAL})


func _telemetry_hole_start(def: Dictionary) -> void:
	_tel().event("mg_hole_start", {"hole": def["number"], "par": def["par"], "zone": def["zone"]})


func _telemetry_stroke(power: float) -> void:
	_tel().event("mg_stroke", {"hole": _current_hole_idx + 1, "stroke": _strokes[_current_hole_idx], "power": snappedf(power, 0.01)})


func _telemetry_hole_end(def: Dictionary, strokes: int, ace: bool) -> void:
	_tel().event("mg_hole_end", {"hole": def["number"], "strokes": strokes, "par": def["par"], "ace": ace})


func _telemetry_hazard(kind: String) -> void:
	_tel().event("mg_hazard", {"hole": _current_hole_idx + 1, "kind": kind})


func _telemetry_round_end(total: int, vs_par: int) -> void:
	_tel().event("mg_round_end", {"strokes": total, "vs_par": vs_par, "aces": _aces.size()})


func _tel() -> Node:
	return get_node_or_null("/root/GameplayTelemetry")
