## MinigolfSeater.gd - seats the 18-hole NEXUS GREENS course in the real room.
## Game Designer §1: room-perimeter loop; tee of hole N adjacent to cup of N-1
## so the player walks the loop. Small rooms -> switchback (2x9 rows).
## No room data / headless -> 4x4m default loop.
## RoomKit is queried ONCE (cached); never per-frame.
extends Node
class_name MinigolfSeater

signal layout_updated

const HOLE_SPACING := 1.9   # meters between hole centers along the loop
const LOOP_MARGIN := 0.6    # keep holes this far from walls

var _loop_points: Array = []  # Array[Transform3D], one per hole
var _use_switchback := false


func _ready() -> void:
	RoomKit.refresh()
	_compute_layout()
	# Room data may arrive a frame later; re-seat once if it does.
	await get_tree().process_frame
	await get_tree().process_frame
	if RoomKit.has_room_data():
		_compute_layout()
		layout_updated.emit()


func seat_for_hole(idx: int, _def: Dictionary) -> Transform3D:
	if idx < 0 or idx >= _loop_points.size():
		return Transform3D.IDENTITY
	return _loop_points[idx]


func _compute_layout() -> void:
	var bounds := _room_bounds()  # Rect2 in world XZ
	var w := bounds.size.x
	var h := bounds.size.y
	# Perimeter loop needs room; otherwise switchback rows.
	_use_switchback = w < 3.0 or h < 3.0
	_loop_points.clear()
	if _use_switchback:
		_build_switchback(bounds)
	else:
		_build_perimeter(bounds)


func _room_bounds() -> Rect2:
	# RoomKit cached layout; fallback 4x4m centered on origin.
	if RoomKit.has_room_data():
		var rb: Rect2 = RoomKit.room_bounds()
		if rb.size.x > 1.0 and rb.size.y > 1.0:
			return rb.grow(-LOOP_MARGIN)
	return Rect2(-2.0, -2.0, 4.0, 4.0)


func _build_perimeter(bounds: Rect2) -> void:
	# Walk the rectangle perimeter, placing 18 evenly spaced points.
	var corners := [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]
	var perimeter := 2.0 * (bounds.size.x + bounds.size.y)
	var step := perimeter / 18.0
	var dist := 0.0
	var seg := 0
	for i in 18:
		var target := step * i
		while seg < 4:
			var a: Vector2 = corners[seg]
			var b: Vector2 = corners[(seg + 1) % 4]
			var seg_len := a.distance_to(b)
			if dist + seg_len >= target:
				var t := (target - dist) / seg_len
				var p: Vector2 = a.lerp(b, t)
				var yaw := atan2((b - a).x, (b - a).y)
				_loop_points.append(Transform3D(
					Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)))
				break
			dist += seg_len
			seg += 1


func _build_switchback(bounds: Rect2) -> void:
	# Two parallel rows of 9 along the room's long axis.
	var c := bounds.get_center()
	var row_len := minf(bounds.size.x, 9.0 * HOLE_SPACING)
	var row_gap := minf(bounds.size.y * 0.4, 1.6)
	for i in 18:
		var row := i / 9
		var col := i % 9
		if row == 1:
			col = 8 - col  # snake back
		var x := c.x - row_len / 2.0 + col * (row_len / 8.0)
		var z := c.y + (row_gap / 2.0 if row == 0 else -row_gap / 2.0)
		var yaw := 0.0 if row == 0 else PI
		_loop_points.append(Transform3D(
			Basis(Vector3.UP, yaw), Vector3(x, 0.0, z)))
