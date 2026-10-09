## MinigolfHole.gd - base class for NEXUS GREENS holes.
## Each hole is a self-contained scene instance with a defined footprint.
## Subclasses (or data-driven builders) override the course geometry queries.
## The ball calls these every physics frame - keep them allocation-free.
extends Node3D
class_name MinigolfHole

## Hole metadata (set by subclass/data).
var hole_number := 1
var hole_name := "Untitled"
var par := 2
var zone := "greens"  # greens | tinkerworks | skyreef

## Ball state owned by the hole.
var strokes := 0

## --- Course queries (override in subclass) ---

func tee_position() -> Vector3:
	if has_meta("tee"):
		return to_global(get_meta("tee"))
	return global_position + Vector3(0, 0.05, 0)


func cup_position() -> Vector3:
	if has_meta("cup"):
		return to_global(get_meta("cup"))
	return global_position + Vector3(0, 0.0, 1.0)


func cup_radius() -> float:
	return float(get_meta("cup_radius", 0.054))


func drop_position() -> Vector3:
	# Where the ball re-enters after a hazard (+1 stroke). Never the tee.
	return tee_position()


## Ground sample: {hit: bool, height: float, normal: Vector3, surface: String}.
## Default: flat felt plane at local y=0.
func ground_at(pos: Vector3) -> Dictionary:
	var local := to_local(pos)
	return {
		"hit": true,
		"height": global_position.y,
		"surface": "felt",
		"normal": Vector3.UP,
	}


## Rail collision: returns [new_pos, new_vel, did_hit, impact_speed].
## Default: rectangular boundary from get_play_rect().
func collide_rails(pos: Vector3, vel: Vector3, radius: float) -> Array:
	var r := get_play_rect()  # Rect2 in world XZ
	var hit := false
	var impact := 0.0
	var rest := 0.72
	if pos.x < r.position.x + radius:
		impact = absf(vel.x); pos.x = r.position.x + radius; vel.x = absf(vel.x) * rest; hit = true
	elif pos.x > r.end.x - radius:
		impact = absf(vel.x); pos.x = r.end.x - radius; vel.x = -absf(vel.x) * rest; hit = true
	if pos.z < r.position.y + radius:
		impact = maxf(impact, absf(vel.z)); pos.z = r.position.y + radius; vel.z = absf(vel.z) * rest; hit = true
	elif pos.z > r.end.y - radius:
		impact = maxf(impact, absf(vel.z)); pos.z = r.end.y - radius; vel.z = -absf(vel.z) * rest; hit = true
	return [pos, vel, hit, impact]


func get_play_rect() -> Rect2:
	if has_meta("size"):
		var size: Vector2 = get_meta("size")
		var c := global_position
		return Rect2(c.x - size.x / 2.0, c.z - size.y / 2.0, size.x, size.y)
	var c := global_position
	return Rect2(c.x - 0.8, c.z - 0.8, 1.6, 1.6)


## Obstacle collision: returns [new_pos, new_vel, did_hit, impact_speed].
## Subclasses append AABBs or custom colliders.
func collide_obstacles(pos: Vector3, vel: Vector3, radius: float) -> Array:
	var hit_any := false
	var impact := 0.0
	for ob in _obstacle_aabbs():
		var res := _resolve_aabb(pos, vel, ob, radius)
		pos = res[0]
		vel = res[1]
		if res[2]:
			hit_any = true
			impact = maxf(impact, res[3])
	return [pos, vel, hit_any, impact]


# --- AR mode: real-room geometry (RoomKit) ---

## Real wall planes registered by MinigolfARMode: [{point, normal, width, height}].
var room_planes: Array = []
## Real furniture obstacles: [{position: Vector3 center, size: Vector3}].
var room_obstacles: Array = []


## Registered mechanic nodes (duck-typed: _mechanic_tick(hole, ball, delta)).
var _mechanics: Array = []
var _ball_ref: MinigolfBall = null


## Register a trick-mechanic node (called by MinigolfMechanics).
func register_mechanic(node: Node) -> void:
	_mechanics.append(node)


## Set the active ball (called by the game on hole start).
func set_ball(ball: MinigolfBall) -> void:
	_ball_ref = ball


func _physics_process(delta: float) -> void:
	# Tick all registered mechanics.
	for m in _mechanics:
		if is_instance_valid(m) and m.has_method("_mechanic_tick"):
			m._mechanic_tick(self, _ball_ref, delta)


## Register a real wall as a bank-shot plane (AR mode).
func register_room_plane(point: Vector3, normal: Vector3, width: float, height: float) -> void:
	room_planes.append({
		"point": point, "normal": normal.normalized(),
		"width": width, "height": height,
	})


## Register real furniture as a physics obstacle (AR mode).
func register_room_obstacle(center: Vector3, size: Vector3) -> void:
	room_obstacles.append({"position": center, "size": size})


## Room-plane collision: returns [new_pos, new_vel, did_hit, impact_speed].
## The ball banks off real walls like wooden rails.
func collide_room_planes(pos: Vector3, vel: Vector3, radius: float) -> Array:
	var hit_any := false
	var impact := 0.0
	var rest := 0.72
	for plane in room_planes:
		var pt: Vector3 = plane["point"]
		var n: Vector3 = plane["normal"]
		var d: float = (pos - pt).dot(n)
		# Ball on the room side of the wall, within radius -> push out.
		if d > 0.0 and d < radius:
			# Bounds check: is the contact within the wall's face?
			var rel: Vector3 = pos - pt
			var tangent := n.cross(Vector3.UP).normalized()
			var up := tangent.cross(n).normalized()
			var tx: float = rel.dot(tangent)
			var ty: float = rel.dot(up)
			if absf(tx) > float(plane["width"]) / 2.0:
				continue
			if ty < 0.0 or ty > float(plane["height"]):
				continue
			pos = pos + n * (radius - d)
			var vn := vel.dot(n)
			if vn < 0.0:
				impact = maxf(impact, absf(vn))
				vel -= n * (vn * (1.0 + rest))
				hit_any = true
	return [pos, vel, hit_any, impact]


## Room-obstacle collision (furniture cuboids): same as AABB resolve.
func collide_room_obstacles(pos: Vector3, vel: Vector3, radius: float) -> Array:
	var hit_any := false
	var impact := 0.0
	for ob in room_obstacles:
		var c: Vector3 = ob["position"]
		var s: Vector3 = ob["size"]
		var res := _resolve_aabb(pos, vel, AABB(c - s / 2.0, s), radius)
		pos = res[0]
		vel = res[1]
		if res[2]:
			hit_any = true
			impact = maxf(impact, res[3])
	return [pos, vel, hit_any, impact]


func _obstacle_aabbs() -> Array:
	# Builder-provided AABBs (rails + obstacles), hole-local -> world.
	if has_meta("all_aabbs"):
		var world := []
		for aabb in get_meta("all_aabbs"):
			var a: AABB = aabb
			world.append(AABB(a.position + global_position, a.size))
		return world
	return []


func _resolve_aabb(pos: Vector3, vel: Vector3, ob: AABB, radius: float) -> Array:
	var closest := Vector3(
		clampf(pos.x, ob.position.x, ob.end.x),
		clampf(pos.y, ob.position.y, ob.end.y),
		clampf(pos.z, ob.position.z, ob.end.z))
	var d: Vector3 = pos - closest
	var dist := d.length()
	if dist >= radius:
		return [pos, vel, false, 0.0]
	var n := d / dist if dist > 0.0001 else Vector3.UP
	pos = closest + n * radius
	var vn := vel.dot(n)
	var impact := 0.0
	if vn < 0.0:
		impact = absf(vn)
		vel -= n * (vn * 1.72)  # restitution 0.72
	return [pos, vel, true, impact]


## Hazard at position: "" or a hazard kind ("water", "sand", "cloud", "shaft").
func hazard_at(pos: Vector3) -> String:
	if has_meta("hazards"):
		for hz in get_meta("hazards"):
			var hp: Vector3 = hz["pos"]
			var hs: Vector3 = hz["size"]
			var world_hp := hp + global_position
			if absf(pos.x - world_hp.x) <= hs.x / 2.0 and absf(pos.z - world_hp.z) <= hs.z / 2.0:
				return hz["kind"]
	return ""


## Wind acceleration at position (Sky Reef). Default: none.
func wind_at(_pos: Vector3) -> Vector3:
	return Vector3.ZERO


## --- Lifecycle ---

func on_hole_start() -> void:
	strokes = 0


func on_stroke() -> void:
	strokes += 1


func is_complete() -> bool:
	return false  # game controller tracks ball holed
