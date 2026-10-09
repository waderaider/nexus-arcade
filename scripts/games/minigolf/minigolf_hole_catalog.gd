## MinigolfHoleCatalog.gd - the 18-hole spec for NEXUS GREENS.
## Game Design §2: 18 holes, 3 zones, par 54.
## Each spec builds via MinigolfHoleBuilder; "extras" names a mechanic
## builder function in MinigolfMechanics.
extends RefCounted
class_name MinigolfHoleCatalog

# Token kinds: "spring", "vacuum", "sticky", or "" (none).
static func holes() -> Array:
	return [
		# ---- Zone A: Clubhouse Greens (par 14) ----
		{"number": 1, "name": "First Tee", "par": 2, "zone": "greens",
			"size": Vector2(1.2, 2.0), "token": ""},
		{"number": 2, "name": "The Gentle Dogleg", "par": 2, "zone": "greens",
			"size": Vector2(1.6, 2.2),
			"obstacles": [{"pos": Vector3(0.45, 0.1, 0.3), "size": Vector3(0.7, 0.2, 0.12)}],
			"token": ""},
		{"number": 3, "name": "Potted Trouble", "par": 2, "zone": "greens",
			"size": Vector2(1.8, 2.2), "extras": "potted_trouble", "token": ""},
		{"number": 4, "name": "The Brass Rail", "par": 3, "zone": "greens",
			"size": Vector2(2.0, 2.6), "extras": "brass_rail", "token": "spring"},
		{"number": 5, "name": "Koi Pond", "par": 2, "zone": "greens",
			"size": Vector2(1.8, 2.4), "extras": "koi_pond", "token": ""},
		{"number": 6, "name": "The Captain's Loop", "par": 3, "zone": "greens",
			"size": Vector2(2.2, 2.2), "extras": "captains_loop", "token": ""},
		# ---- Zone B: The Tinkerworks (par 19) ----
		{"number": 7, "name": "Gear Grinder", "par": 3, "zone": "tinkerworks",
			"size": Vector2(2.0, 2.4), "extras": "gear_grinder", "token": ""},
		{"number": 8, "name": "Piston Alley", "par": 3, "zone": "tinkerworks",
			"size": Vector2(1.6, 3.0), "extras": "piston_alley", "token": "spring"},
		{"number": 9, "name": "The Copper Tube", "par": 3, "zone": "tinkerworks",
			"size": Vector2(2.0, 2.6), "extras": "copper_tube", "token": ""},
		{"number": 10, "name": "Conveyor Cross", "par": 4, "zone": "tinkerworks",
			"size": Vector2(2.4, 2.4), "extras": "conveyor_cross", "token": "spring"},
		{"number": 11, "name": "Steam Vent Saloon", "par": 3, "zone": "tinkerworks",
			"size": Vector2(2.0, 2.4), "extras": "steam_vent", "token": "sticky"},
		{"number": 12, "name": "The Big Loop", "par": 3, "zone": "tinkerworks",
			"size": Vector2(1.8, 3.2), "extras": "big_loop", "token": "vacuum"},
		# ---- Zone C: The Sky Reef (par 21) ----
		{"number": 13, "name": "Trade Winds", "par": 3, "zone": "skyreef",
			"size": Vector2(2.4, 2.4), "extras": "trade_winds", "token": ""},
		{"number": 14, "name": "Gull Gates", "par": 3, "zone": "skyreef",
			"size": Vector2(2.2, 2.6), "extras": "gull_gates", "token": ""},
		{"number": 15, "name": "The Rope Bridge", "par": 4, "zone": "skyreef",
			"size": Vector2(1.2, 3.6), "extras": "rope_bridge", "token": "sticky"},
		{"number": 16, "name": "Coral Maze", "par": 4, "zone": "skyreef",
			"size": Vector2(2.6, 2.6), "extras": "coral_maze", "token": ""},
		{"number": 17, "name": "The Storm Cell", "par": 4, "zone": "skyreef",
			"size": Vector2(2.4, 2.6), "extras": "storm_cell", "token": "vacuum"},
		{"number": 18, "name": "The Skyfall Finale", "par": 4, "zone": "skyreef",
			"size": Vector2(2.6, 3.6), "extras": "skyfall_finale", "token": "sticky"},
	]


static func par_total() -> int:
	var t := 0
	for h in holes():
		t += int(h["par"])
	return t
