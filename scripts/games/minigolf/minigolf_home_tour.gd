## MinigolfHomeTour.gd - AR-exclusive bonus holes for NEXUS GREENS.
## AR Design §4: "The Home Tour" — 5 holes that cannot exist in VR, each
## requiring a specific piece of the player's real room. Offered after hole
## 18; plays the matched subset (minimum 3). Own scorecard; never touches
## the par-54 Legends Board. No power-up tokens — the room is the trick.
extends RefCounted
class_name MinigolfHomeTour

# Tour hole definitions: name, par, room feature required.
const TOUR_HOLES := [
	{"id": "H1", "name": "Off Your Wall", "par": 2, "feature": "wall_bank"},
	{"id": "H2", "name": "Under the Coffee Table", "par": 2, "feature": "tunnel"},
	{"id": "H3", "name": "Around the Couch", "par": 3, "feature": "soft_obstacle"},
	{"id": "H4", "name": "The Chair Slalom", "par": 3, "feature": "slalom"},
	{"id": "H5", "name": "Kitchen Island Rail", "par": 2, "feature": "counter_bank"},
]


## Match tour holes against the room. Returns the matched subset (ordered).
## Minimum 3 matches to offer the tour.
static func match_holes() -> Array:
	if not MinigolfARMode.is_available():
		return []
	var matched := []
	for h in TOUR_HOLES:
		if _feature_matches(h["feature"]):
			matched.append(h)
	return matched


## True when enough holes matched to offer the tour.
static func can_offer() -> bool:
	return match_holes().size() >= 3


static func _feature_matches(feature: String) -> bool:
	match feature:
		"wall_bank":
			# A real wall >= 2m wide.
			for w in RoomKit.get_walls():
				if (w["size"] as Vector2).x >= 2.0:
					return true
			return false
		"tunnel":
			# A table with >= 0.35m clearance and >= 0.8m span.
			for t in RoomKit.get_tables():
				var pos: Vector3 = t["position"]
				var size: Vector3 = t["size"]
				var clearance: float = pos.y - size.y / 2.0
				var span: float = minf(size.x, size.z)
				if clearance >= 0.35 and span >= 0.8:
					return true
			return false
		"soft_obstacle":
			return not RoomKit.get_couch().is_empty()
		"slalom":
			# 3+ chair/table legs — approximate via furniture count.
			return RoomKit.get_furniture().size() >= 3
		"counter_bank":
			# Storage/counter >= 0.9m tall with a >= 1.5m face.
			for s in RoomKit.get_storage():
				var size: Vector3 = s["size"]
				if size.y >= 0.9 and maxf(size.x, size.z) >= 1.5:
					return true
			return false
	return false


## Build a tour hole node for the given tour hole id.
## Returns a MinigolfHole configured for the room feature.
static func build_tour_hole(tour_def: Dictionary) -> MinigolfHole:
	var spec := {
		"number": 100 + TOUR_HOLES.find(tour_def),
		"name": tour_def["name"],
		"par": tour_def["par"],
		"zone": "greens",
		"size": Vector2(1.6, 2.4),
		"token": "",
	}
	var hole := MinigolfHoleBuilder.build(spec)
	# Adapt to the room (walls + furniture become the hole).
	MinigolfARMode.adapt_hole(hole, spec)
	# Feature-specific setup.
	match tour_def["feature"]:
		"wall_bank", "counter_bank":
			hole.set_meta("tour_feature", "bank")
		"tunnel":
			hole.set_meta("tour_feature", "tunnel")
		"soft_obstacle":
			hole.set_meta("tour_feature", "soft")
			_apply_soft_physics(hole)
		"slalom":
			hole.set_meta("tour_feature", "slalom")
	return hole


## Soft obstacle physics: couch banks kill the ball's energy (muffled whump).
static func _apply_soft_physics(hole: MinigolfHole) -> void:
	hole.set_meta("soft_banks", true)
