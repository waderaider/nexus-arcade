## MinigolfARMode.gd - room-aware AR mode for NEXUS GREENS.
## wade's ship-blocker (2026-10-09): alongside VR mode, an AR mode where the
## course is built from the player's REAL room via RoomKit Scene API anchors.
## Holes lay out across the real floor winding around real furniture; real
## walls become bank-shot surfaces; furniture becomes obstacles. Graceful
## fallback to the floating VR course when no room data exists.
## Depth occlusion on: virtual elements hide behind real furniture.
extends RefCounted
class_name MinigolfARMode

# How close a real wall must be to a hole to become a bank surface (m).
const WALL_SNAP_DIST := 1.2
# Furniture within this radius of the hole center becomes an obstacle (m).
const FURNITURE_RADIUS := 2.0
# Minimum clearance under furniture to count as a "tunnel" (m).
const TUNNEL_MIN_CLEARANCE := 0.12


## True when the device has room scan data to build on.
static func is_available() -> bool:
	return RoomKit.is_available() and RoomKit.has_room_data()


## Adapt a hole to the real room. Called at hole start in AR mode.
## Registers real walls as bank planes + nearby furniture as obstacles on
## the hole, and returns adaptation notes for the hole intro card.
## Returns: {wall_banks: int, furniture_obstacles: int, tunnels: Array,
##           notes: Array[String], fallback: bool}
static func adapt_hole(hole: MinigolfHole, _spec: Dictionary) -> Dictionary:
	var result := {
		"wall_banks": 0,
		"furniture_obstacles": 0,
		"tunnels": [],
		"notes": [],
		"fallback": false,
	}
	if not is_available():
		result["fallback"] = true
		(result["notes"] as Array).append("No room scan — floating course.")
		return result

	var center := hole.global_position
	var notes: Array = result["notes"]

	# --- Real walls as bank-shot surfaces ---
	for wall in RoomKit.get_walls():
		var wpos: Vector3 = wall["position"]
		var normal: Vector3 = wall["normal"]
		# Distance from hole center to the wall plane.
		var to_wall: Vector3 = wpos - center
		var dist: float = absf(to_wall.dot(normal))
		if dist > WALL_SNAP_DIST:
			continue
		# Only walls roughly facing the hole (ball can reach them).
		var wsize: Vector2 = wall["size"]
		hole.register_room_plane(wpos, normal, wsize.x, wsize.y)
		result["wall_banks"] = int(result["wall_banks"]) + 1
		notes.append("Bank it off your actual wall!")

	# --- Real furniture as obstacles ---
	for f in RoomKit.get_furniture():
		var fpos: Vector3 = f["position"]
		var fsize: Vector3 = f["size"]
		var flat := Vector2(fpos.x - center.x, fpos.z - center.z)
		if flat.length() > FURNITURE_RADIUS + maxf(fsize.x, fsize.z) / 2.0:
			continue
		# Only furniture that intersects the play plane (not floating shelves).
		var bottom: float = fpos.y - fsize.y / 2.0
		var top: float = fpos.y + fsize.y / 2.0
		if bottom > 0.35:
			continue  # floats above ball height; ignore
		# Register as a physics obstacle.
		hole.register_room_obstacle(fpos, fsize)
		result["furniture_obstacles"] = int(result["furniture_obstacles"]) + 1
		var label := str(f.get("label", "furniture"))
		# Tunnel check: clearance under furniture (e.g. coffee table).
		if bottom >= TUNNEL_MIN_CLEARANCE and bottom <= 0.45:
			(result["tunnels"] as Array).append(label)
			notes.append("Putt under the %s!" % label)
		elif (result["tunnels"] as Array).is_empty():
			notes.append("Around the %s!" % label)

	# --- Tables get special treatment: low ones are tunnels, tall ones walls ---
	for t in RoomKit.get_tables():
		var tpos: Vector3 = t["position"]
		var tsize: Vector3 = t["size"]
		var flat := Vector2(tpos.x - center.x, tpos.z - center.z)
		if flat.length() > FURNITURE_RADIUS + maxf(tsize.x, tsize.z) / 2.0:
			continue
		var top: float = tpos.y + tsize.y / 2.0
		if top < 0.5 and top > TUNNEL_MIN_CLEARANCE:
			if not (result["tunnels"] as Array).has("table"):
				(result["tunnels"] as Array).append("table")
				notes.append("Putt under the table!")

	if int(result["wall_banks"]) == 0 and int(result["furniture_obstacles"]) == 0:
		notes.append("Open floor — pure putting.")

	return result


## Enable depth occlusion for AR mode (virtual hides behind real furniture).
static func enable_depth_occlusion() -> void:
	VisualFX.set_depth_occlusion_enabled(true)


## Disable when leaving AR mode.
static func disable_depth_occlusion() -> void:
	VisualFX.set_depth_occlusion_enabled(false)


## Room-scan onboarding state for the mode-select screen.
## Returns: "ready" | "no_data" | "unavailable"
static func scan_state() -> String:
	if not RoomKit.is_available():
		return "unavailable"
	return "ready" if RoomKit.has_room_data() else "no_data"
