## MinigolfTheme.gd - zone visual identity for NEXUS GREENS.
## Clubhouse Greens: deep green / cream / brass.
## The Tinkerworks: copper / teal / soot.
## The Sky Reef: coral / sky / sun-gold.
extends RefCounted
class_name MinigolfTheme

static func accent_for(zone: String) -> Color:
	match zone:
		"greens":
			return Color(0.85, 0.70, 0.30)  # brass
		"tinkerworks":
			return Color(0.85, 0.45, 0.20)  # copper
		"skyreef":
			return Color(1.0, 0.45, 0.35)  # coral
	return Color(0.85, 0.70, 0.30)


static func felt_for(zone: String) -> Color:
	match zone:
		"greens":
			return Color(0.13, 0.42, 0.20)
		"tinkerworks":
			return Color(0.16, 0.32, 0.30)  # teal-tinted
		"skyreef":
			return Color(0.20, 0.45, 0.35)  # sea-tinted
	return Color(0.13, 0.42, 0.20)


static func zone_name(zone: String) -> String:
	match zone:
		"greens":
			return "Clubhouse Greens"
		"tinkerworks":
			return "The Tinkerworks"
		"skyreef":
			return "The Sky Reef"
	return zone
