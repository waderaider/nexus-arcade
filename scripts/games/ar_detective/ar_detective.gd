## AR Detective: a noir crime scene materializes in your room.
## SCAN: pinch/tap-collect 6 glowing clues (hint cards + haptic tick).
## ANALYZE: drag clue cards onto the evidence board in causal order.
## INTERROGATE: 3 hologram suspects answer 2 questions each; flag the lie
## that contradicts a clue. ACCUSE: name the culprit. 3 cases, escalating.
## Progress persists in user://nexus_detective.cfg.
## Desktop: click/tap + click-drag. XR: pinch tap + pinch-drag. R restarts case.
extends Node3D

const SAVE_PATH := "user://nexus_detective.cfg"
const PROPS := "res://assets/models/ar_detective/props/"
const CHARS := "res://assets/models/ar_detective/characters/"

const CLUE_MODELS := {
	"axe": "tool-axe.glb",
	"bottle": "bottle.glb",
	"chest": "chest.glb",
	"crate": "box.glb",
	"hammer": "tool-hammer.glb",
	"letter": "craft:letter",
	"key": "craft:key",
}

const CASES := [
	{
		"title": "CASE 1: The Midnight Gallery",
		"brief": "The Star Sapphire vanished from the gallery at midnight.\nSix clues. One liar. Find the truth.",
		"clues": [
			{"m": "letter", "name": "Threatening Letter", "hint": "Typed note: 'The sapphire leaves tonight \u2014 or the gallery burns.' No signature."},
			{"m": "bottle", "name": "Laudanum Bottle", "hint": "Bitter-almond smell. Half the night guard's cocoa was drugged."},
			{"m": "key", "name": "Brass Gallery Key", "hint": "A fresh-cut copy. The original never left the director's desk."},
			{"m": "chest", "name": "Jewel Chest", "hint": "Lock picked clean \u2014 not a scratch. A professional job."},
			{"m": "crate", "name": "Packing Crate", "hint": "Straw still warm. The sapphire left inside a 'porcelain' shipment."},
			{"m": "axe", "name": "Fire Axe", "hint": "Dust on the handle, untouched for months. The skylight was never forced."},
		],
		"order": [0, 2, 1, 3, 4, 5],
		"suspects": [
			{"name": "Vera Kline", "role": "Curator", "model": "character-female-a.glb",
				"q": [
					{"q": "Where were you at midnight?", "a": "Locking the east wing. The logbook proves it."},
					{"q": "Who had key copies?", "a": "Only the director... and our locksmith."},
				], "lie": -1, "lie_hint": ""},
			{"name": "Otto Marsh", "role": "Night Guard", "model": "character-male-b.glb",
				"q": [
					{"q": "Did you drink anything on shift?", "a": "Just my cocoa. Tasted perfectly fine."},
					{"q": "Hear anything unusual?", "a": "A scrape near the skylight, around one."},
				], "lie": 0, "lie_hint": "The laudanum bottle proves his cocoa was drugged \u2014 he lied about tasting nothing."},
			{"name": "Ilsa Brandt", "role": "Locksmith", "model": "character-female-c.glb",
				"q": [
					{"q": "Did you cut a key recently?", "a": "One \u2014 for the director, on Tuesday."},
					{"q": "Recognize this copy?", "a": "Not my cut. Someone used one of my blanks."},
				], "lie": -1, "lie_hint": ""},
		],
		"culprit": 1,
		"motive": "Marsh drugged his own cocoa, walked out with the sapphire in a porcelain crate, and staged the skylight.",
	},
	{
		"title": "CASE 2: The Poisoned Toast",
		"brief": "A founder drops dead at the gala toast. The wine was poisoned \u2014\nbut the bottle was sealed. Six clues. One liar.",
		"clues": [
			{"m": "bottle", "name": "Reserve Wine Bottle", "hint": "Bitter almonds under the bouquet. Cyanide in the '61 reserve."},
			{"m": "letter", "name": "Seating Chart", "hint": "The victim's glass was reassigned at the last minute \u2014 in different ink."},
			{"m": "key", "name": "Cellar Key", "hint": "Found in the victim's pocket... yet the cellar was locked from the outside."},
			{"m": "chest", "name": "Strongbox", "hint": "A new will inside names a different heir. Signed yesterday."},
			{"m": "crate", "name": "Ice Crate", "hint": "Meltwater and glass dust: the poison vial rode in with the ice delivery."},
			{"m": "hammer", "name": "Silver Hammer", "hint": "Used to smash the victim's glass afterward \u2014 a 'clean-up'."},
		],
		"order": [1, 4, 0, 2, 3, 5],
		"suspects": [
			{"name": "Edwin Voss", "role": "Business Partner", "model": "character-male-c.glb",
				"q": [
					{"q": "Why was the will changed?", "a": "I didn't change it \u2014 the victim did, yesterday."},
					{"q": "Where were you at the toast?", "a": "At the podium. In front of everyone."},
				], "lie": -1, "lie_hint": ""},
			{"name": "Clara Reyes", "role": "Sommelier", "model": "character-female-d.glb",
				"q": [
					{"q": "Did the ice delivery come through you?", "a": "No \u2014 the caterer handled all the ice."},
					{"q": "Did you taste the wine?", "a": "Every bottle, as always. It was clean at pouring."},
				], "lie": 0, "lie_hint": "The ice crate's manifest bears her signature \u2014 she lied about the ice."},
			{"name": "Jonas Pike", "role": "Caterer", "model": "character-male-d.glb",
				"q": [
					{"q": "Who ordered extra ice?", "a": "The sommelier. Said the cellar was warm."},
					{"q": "See anyone near the glasses?", "a": "Only staff. And Mr. Voss at the podium."},
				], "lie": -1, "lie_hint": ""},
		],
		"culprit": 1,
		"motive": "Reyes slipped the vial into the ice, swapped the seating chart, and smashed the glass to hide the residue.",
	},
	{
		"title": "CASE 3: The Drowned Alibi",
		"brief": "A captain found dead on dry sand at high tide. The sea is lying \u2014\nor someone is. Six clues. One liar.",
		"clues": [
			{"m": "axe", "name": "Boat Hook Axe", "hint": "Blood on the blade matches the victim. Wiped \u2014 but missed the grain."},
			{"m": "bottle", "name": "Rum Bottle", "hint": "Two glasses poured. The victim never drank."},
			{"m": "key", "name": "Harbor Master's Key", "hint": "Opens the impound locker \u2014 where the ledger vanished from."},
			{"m": "chest", "name": "Captain's Chest", "hint": "Empty. The smuggling ledger is gone."},
			{"m": "crate", "name": "Tackle Box", "hint": "Fishhooks bent into lockpicks. Someone has done this before."},
			{"m": "letter", "name": "Tide Table", "hint": "High tide 11:40 PM. The 'drowning' happened at 11:15 \u2014 on dry sand."},
		],
		"order": [3, 2, 5, 4, 0, 1],
		"suspects": [
			{"name": "Silas Wren", "role": "Harbor Master", "model": "character-male-e.glb",
				"q": [
					{"q": "Where is the smuggling ledger?", "a": "Impounded. Sealed in my locker."},
					{"q": "What was the tide that night?", "a": "High near half eleven. Near enough."},
				], "lie": 0, "lie_hint": "The captain's chest is empty and the locker was opened \u2014 the ledger was never 'sealed' inside."},
			{"name": "Mara Quinn", "role": "Smuggler", "model": "character-female-e.glb",
				"q": [
					{"q": "Did you know the victim?", "a": "Owed him money. Paid him in full Tuesday."},
					{"q": "Where was your boat?", "a": "Moored at pier nine, all night."},
				], "lie": -1, "lie_hint": ""},
			{"name": "Tom Beck", "role": "Deckhand", "model": "character-male-f.glb",
				"q": [
					{"q": "Hear the fight?", "a": "Shouting near the lockers, half ten."},
					{"q": "Have you seen the axe?", "a": "Back in the rack by midnight. I swear it."},
				], "lie": -1, "lie_hint": ""},
		],
		"culprit": 0,
		"motive": "Wren stole the ledger, killed the captain with the boat axe, and staged a drowning the tide disproves.",
	},
]

const SCENE_C := Vector3(0.0, 0.0, -1.7)
const BOARD_POS := Vector3(0.0, 1.5, -3.15)
const SUSPECT_X := [-1.7, 0.0, 1.7]

var camera: Camera3D = null
var case_idx := 0
var solved_count := 0
var phase := "scan"
var case_root: Node3D = null
var clue_nodes: Array = []
var collected := 0
var tokens: Array = []
var slot_of_token := {}
var token_in_slot := [-1, -1, -1, -1, -1, -1]
var slot_nodes: Array = []
var suspects: Array = []
var selected_suspect := -1
var asked := {}
var flag_mode := false
var lie_exposed := false
var accuse_hint_used := false

var hud_title: Label3D = null
var hud_phase: Label3D = null
var msg_label: Label3D = null
var hint_panel: Node3D = null
var hint_label: Label3D = null
var hint_t := 0.0
var dialog_root: Node3D = null
var verify_btn: Node3D = null
var next_btn: Node3D = null
var taps := {}
var msg := ""
var msg_t := 0.0
var pulse_t := 0.0
var intro_t := 0.0
var intro_label: Label3D = null
var done_label: Label3D = null

var pressing := false
var press_pos := Vector2.ZERO
var press_time := 0
var press_moved := 0.0
var drag_token := -1
var prev_pinch := false
var xr_drag_token := -1
var xr_tap_armed := false
var holo_mats: Array = []
var scan_rings: Array = []
var lamp_light: SpotLight3D = null


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "ar_detective_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_progress()
	_build_stage()
	_build_chalk_outline()
	_build_police_tape()
	_build_lamp()
	_build_hud()
	GraphicsPolish.spawn_ambient_motes(self, SCENE_C + Vector3(0, 1.2, 0), 2.2, 40)
	if solved_count >= CASES.size():
		_show_all_done()
	else:
		case_idx = solved_count
		_start_case(case_idx)


func _ensure_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.65, 1.35)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.9, -1.7), Vector3.UP)
	camera.current = true


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.14, 0.17, 0.27)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.06, 0.11)
	env.fog_density = 0.015
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self, 0.35)


static var _model_cache := {}


func _load_model(path: String) -> Node3D:
	if _model_cache.has(path):
		var ps: PackedScene = _model_cache[path]
		if ps != null:
			return ps.instantiate() as Node3D
		_model_cache.erase(path)
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path) as PackedScene
	if loaded == null:
		return null
	_model_cache[path] = loaded
	return loaded.instantiate() as Node3D


func _make_clue_mesh(model_key: String) -> Node3D:
	var fname: String = CLUE_MODELS[model_key]
	if fname.begins_with("craft:"):
		if fname == "craft:letter":
			return _craft_letter()
		return _craft_key()
	var n := _load_model(PROPS + fname)
	if n == null:
		var fb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.3, 0.3)
		fb.mesh = bm
		fb.material_override = GraphicsPolish.glow(Color(1.0, 0.8, 0.2), 1.2)
		return fb
	# Normalize scale: kenney props vary; fit into ~0.45m.
	n.scale = Vector3.ONE * 0.55
	return n


func _craft_letter() -> Node3D:
	var root := Node3D.new()
	var paper_mat := GraphicsPolish.pbr_preset(Color(0.92, 0.88, 0.78), "matte")
	var env := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(0.30, 0.02, 0.20)
	env.mesh = eb
	env.material_override = paper_mat
	root.add_child(env)
	var flap := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.30, 0.015, 0.10)
	flap.mesh = fb
	flap.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.80, 0.70), "matte")
	flap.position = Vector3(0, 0.018, -0.05)
	flap.rotation_degrees.x = -12.0
	root.add_child(flap)
	var seal := MeshInstance3D.new()
	var sb := CylinderMesh.new()
	sb.top_radius = 0.035
	sb.bottom_radius = 0.035
	sb.height = 0.012
	seal.mesh = sb
	seal.material_override = GraphicsPolish.glow(Color(0.65, 0.08, 0.10), 0.8)
	seal.position = Vector3(0, 0.025, 0.02)
	root.add_child(seal)
	return root


func _craft_key() -> Node3D:
	var root := Node3D.new()
	var brass := GraphicsPolish.pbr_preset(Color(0.85, 0.62, 0.25), "metal")
	var bow := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.035
	tor.outer_radius = 0.065
	bow.mesh = tor
	bow.material_override = brass
	bow.rotation_degrees.x = 90.0
	bow.position = Vector3(0, 0.10, 0.14)
	root.add_child(bow)
	var shaft := MeshInstance3D.new()
	var cb := CylinderMesh.new()
	cb.top_radius = 0.018
	cb.bottom_radius = 0.018
	cb.height = 0.26
	shaft.mesh = cb
	shaft.material_override = brass
	shaft.rotation_degrees.x = 90.0
	shaft.position = Vector3(0, 0.10, -0.02)
	root.add_child(shaft)
	for i in 2:
		var tooth := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.02, 0.05, 0.03)
		tooth.mesh = tb
		tooth.material_override = brass
		tooth.position = Vector3(0, 0.075, -0.10 - float(i) * 0.05)
		root.add_child(tooth)
	root.rotation_degrees.x = -90.0
	return root


func _build_stage() -> void:
	# Dark stage rug the crime scene sits on.
	var rug := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(3.6, 0.02, 2.6)
	rug.mesh = rb
	rug.material_override = GraphicsPolish.pbr_preset(Color(0.07, 0.07, 0.10), "matte")
	rug.position = SCENE_C + Vector3(0, 0.005, 0)
	add_child(rug)
	# Faint red crime-scene glow ring.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.55
	tor.outer_radius = 1.62
	ring.mesh = tor
	ring.material_override = GraphicsPolish.glow(Color(0.55, 0.05, 0.08), 0.9)
	ring.rotation_degrees.x = 90.0
	ring.position = SCENE_C + Vector3(0, 0.03, 0)
	add_child(ring)


func _chalk_piece(size: Vector3, pos: Vector3, rot_z: float) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = GraphicsPolish.glow(Color(0.92, 0.94, 0.97), 0.55)
	m.position = pos
	m.rotation.z = deg_to_rad(rot_z)
	add_child(m)


func _build_chalk_outline() -> void:
	var c := SCENE_C + Vector3(-0.55, 0.035, 0.1)
	# Head ring.
	var head := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.13
	tor.outer_radius = 0.16
	head.mesh = tor
	head.material_override = GraphicsPolish.glow(Color(0.92, 0.94, 0.97), 0.55)
	head.rotation_degrees.x = 90.0
	head.position = c + Vector3(-0.75, 0, 0)
	add_child(head)
	# Torso, arms, legs from chalk bars.
	_chalk_piece(Vector3(0.85, 0.012, 0.30), c + Vector3(0.05, 0, 0), 0.0)
	_chalk_piece(Vector3(0.55, 0.012, 0.09), c + Vector3(-0.05, 0, 0.42), 28.0)
	_chalk_piece(Vector3(0.55, 0.012, 0.09), c + Vector3(-0.05, 0, -0.42), -28.0)
	_chalk_piece(Vector3(0.75, 0.012, 0.11), c + Vector3(0.85, 0, 0.16), 8.0)
	_chalk_piece(Vector3(0.75, 0.012, 0.11), c + Vector3(0.85, 0, -0.16), -8.0)


func _build_police_tape() -> void:
	var post_mat := GraphicsPolish.pbr_preset(Color(0.75, 0.62, 0.10), "metal")
	var tape_mat := GraphicsPolish.glow(Color(0.95, 0.75, 0.05), 0.5)
	var corners := [
		Vector3(-1.7, 0, -2.85), Vector3(1.7, 0, -2.85),
		Vector3(-1.7, 0, -0.55), Vector3(1.7, 0, -0.55),
	]
	for p in corners:
		var post := MeshInstance3D.new()
		var cb := CylinderMesh.new()
		cb.top_radius = 0.02
		cb.bottom_radius = 0.02
		cb.height = 0.95
		post.mesh = cb
		post.material_override = post_mat
		post.position = p + Vector3(0, 0.475, 0)
		add_child(post)
	var spans := [[0, 1], [2, 3], [0, 2], [1, 3]]
	for s in spans:
		var a: Vector3 = corners[s[0]] + Vector3(0, 0.82, 0)
		var b: Vector3 = corners[s[1]] + Vector3(0, 0.82, 0)
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var tape := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(length, 0.09, 0.005)
		tape.mesh = tb
		tape.material_override = tape_mat
		tape.position = mid
		# Long axis (X) along the span direction.
		var tdir: Vector3 = (b - a).normalized()
		var tz := tdir.cross(Vector3.UP).normalized()
		var ty := tz.cross(tdir).normalized()
		tape.basis = Basis(tdir, ty, tz)
		add_child(tape)


func _build_lamp() -> void:
	# Noir desk lamp: heavy base, angled arm, cone shade, warm spotlight.
	var lamp := Node3D.new()
	lamp.position = Vector3(2.05, 0, -0.95)
	add_child(lamp)
	var dark_metal := GraphicsPolish.pbr_preset(Color(0.10, 0.10, 0.12), "metal")
	var base := MeshInstance3D.new()
	var bb := CylinderMesh.new()
	bb.top_radius = 0.16
	bb.bottom_radius = 0.20
	bb.height = 0.06
	base.mesh = bb
	base.material_override = dark_metal
	base.position.y = 0.03
	lamp.add_child(base)
	var arm := MeshInstance3D.new()
	var ab := CylinderMesh.new()
	ab.top_radius = 0.025
	ab.bottom_radius = 0.025
	ab.height = 1.35
	arm.mesh = ab
	arm.material_override = dark_metal
	arm.position = Vector3(-0.28, 0.68, -0.10)
	arm.rotation_degrees = Vector3(0, 0, 24)
	lamp.add_child(arm)
	var shade := MeshInstance3D.new()
	var sb := CylinderMesh.new()
	sb.top_radius = 0.09
	sb.bottom_radius = 0.20
	sb.height = 0.24
	shade.mesh = sb
	shade.material_override = GraphicsPolish.pbr_preset(Color(0.05, 0.12, 0.08), "metal")
	shade.position = Vector3(-0.62, 1.32, -0.22)
	shade.rotation_degrees = Vector3(-38, 0, 30)
	lamp.add_child(shade)
	var bulb := MeshInstance3D.new()
	var bb2 := SphereMesh.new()
	bb2.radius = 0.045
	bb2.height = 0.09
	bulb.mesh = bb2
	bulb.material_override = GraphicsPolish.glow(Color(1.0, 0.75, 0.40), 3.0)
	bulb.position = Vector3(-0.68, 1.24, -0.26)
	lamp.add_child(bulb)
	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color(1.0, 0.72, 0.42)
	lamp_light.light_energy = 3.2
	lamp_light.spot_range = 7.0
	lamp_light.spot_angle = 32.0
	lamp_light.shadow_enabled = true
	lamp_light.position = Vector3(-0.68, 1.24, -0.26)
	lamp.add_child(lamp_light)
	# Aim at the crime scene (spotlights shine along -Z).
	var lamp_target: Vector3 = lamp.to_local(to_global(SCENE_C + Vector3(0, 0.4, 0)))
	lamp_light.basis = Basis.looking_at((lamp_target - lamp_light.position).normalized(), Vector3.UP)
	# Cool cyan rim light from the other side for noir contrast.
	var rim := SpotLight3D.new()
	rim.light_color = Color(0.35, 0.65, 1.0)
	rim.light_energy = 1.1
	rim.spot_range = 8.0
	rim.spot_angle = 40.0
	rim.position = Vector3(-2.4, 2.2, -0.6)
	add_child(rim)
	var rim_target: Vector3 = to_global(SCENE_C + Vector3(0, 0.6, 0))
	rim.basis = Basis.looking_at((rim_target - rim.global_position).normalized(), Vector3.UP)


func _build_hud() -> void:
	hud_title = GraphicsPolish.make_label("", 52, Color(1.0, 0.85, 0.55))
	hud_title.position = Vector3(-2.75, 2.75, -1.2)
	hud_title.pixel_size = 0.006
	add_child(hud_title)
	hud_phase = GraphicsPolish.make_label("", 40, Color(0.55, 0.85, 1.0))
	hud_phase.position = Vector3(-2.75, 2.48, -1.2)
	hud_phase.pixel_size = 0.005
	add_child(hud_phase)
	msg_label = GraphicsPolish.make_label("", 56, Color(1.0, 0.9, 0.6))
	msg_label.position = Vector3(0.0, 2.55, -2.7)
	msg_label.pixel_size = 0.007
	add_child(msg_label)
	# Hint card panel (right side).
	hint_panel = Node3D.new()
	hint_panel.position = Vector3(2.55, 1.7, -2.1)
	add_child(hint_panel)
	var card := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.15, 0.85, 0.03)
	card.mesh = cb
	card.material_override = GraphicsPolish.pbr_preset(Color(0.06, 0.07, 0.11), "matte")
	hint_panel.add_child(card)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.19, 0.89, 0.02)
	frame.mesh = fb
	frame.material_override = GraphicsPolish.glow(Color(0.45, 0.75, 1.0), 0.8)
	frame.position.z = -0.008
	hint_panel.add_child(frame)
	hint_label = GraphicsPolish.make_label("", 30, Color(0.92, 0.95, 1.0))
	hint_label.position = Vector3(0, 0.05, 0.03)
	hint_label.pixel_size = 0.0038
	hint_panel.add_child(hint_label)
	var htitle := GraphicsPolish.make_label("FIELD NOTES", 30, Color(0.55, 0.85, 1.0))
	htitle.position = Vector3(0, 0.33, 0.03)
	htitle.pixel_size = 0.004
	hint_panel.add_child(htitle)
	hint_panel.visible = false
	intro_label = GraphicsPolish.make_label("", 64, Color(1.0, 0.92, 0.70))
	intro_label.position = Vector3(0.0, 2.0, -2.4)
	intro_label.pixel_size = 0.008
	add_child(intro_label)


func _set_msg(text: String, hold: float) -> void:
	msg = text
	msg_t = hold
	if msg_label != null:
		msg_label.text = text


func _show_hint(title: String, body: String, hold: float = 6.0) -> void:
	if hint_label == null:
		return
	hint_label.text = "%s\n\n%s" % [title, body]
	hint_panel.visible = true
	hint_t = hold


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		solved_count = int(cfg.get_value("detective", "solved", 0))


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("detective", "solved", solved_count)
	cfg.save(SAVE_PATH)


func _clear_case() -> void:
	if case_root != null and is_instance_valid(case_root):
		case_root.queue_free()
	case_root = Node3D.new()
	add_child(case_root)
	clue_nodes.clear()
	tokens.clear()
	slot_of_token.clear()
	token_in_slot = [-1, -1, -1, -1, -1, -1]
	slot_nodes.clear()
	suspects.clear()
	selected_suspect = -1
	asked.clear()
	flag_mode = false
	lie_exposed = false
	accuse_hint_used = false
	collected = 0
	drag_token = -1
	xr_drag_token = -1
	taps.clear()
	holo_mats.clear()
	scan_rings.clear()
	verify_btn = null
	next_btn = null
	if dialog_root != null and is_instance_valid(dialog_root):
		dialog_root.queue_free()
	dialog_root = null
	if done_label != null and is_instance_valid(done_label):
		done_label.queue_free()
	done_label = null


func _make_tappable(node: Node3D, tap_id: String, kind: String, data: Variant, radius: float, y_off: float = 0.0) -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	shape.shape = sp
	area.add_child(shape)
	area.position.y = y_off
	node.add_child(area)
	area.set_meta("tap_id", tap_id)
	taps[tap_id] = {"node": node, "kind": kind, "data": data}


func _ray_pick(origin: Vector3, dir: Vector3) -> String:
	if get_world_3d() == null:
		return ""
	var space := get_world_3d().direct_space_state
	if space == null:
		return ""
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ""
	var col: Object = hit.get("collider")
	if col != null and col.has_meta("tap_id"):
		return str(col.get_meta("tap_id"))
	return ""


func _screen_pick(screen_pos: Vector2) -> String:
	if camera == null:
		return ""
	return _ray_pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _xr_pick() -> String:
	var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	return _ray_pick(r[0], r[1])


func _start_case(idx: int) -> void:
	_clear_case()
	case_idx = idx
	phase = "scan"
	var case: Dictionary = CASES[idx]
	if hud_title != null:
		hud_title.text = str(case["title"])
	_update_phase_hud()
	# Intro card.
	if intro_label != null:
		intro_label.text = "%s\n%s" % [str(case["title"]), str(case["brief"])]
		intro_t = 7.0
		intro_label.visible = true
	_spawn_clues(case)
	_build_board(case)
	_build_suspects(case)
	_set_msg("SCAN: tap the 6 glowing clues", 6.0)


func _spawn_clues(case: Dictionary) -> void:
	var clues: Array = case["clues"]
	var spots := [
		SCENE_C + Vector3(0.85, 0.0, 0.55),
		SCENE_C + Vector3(-1.25, 0.0, -0.55),
		SCENE_C + Vector3(1.25, 0.0, -0.35),
		SCENE_C + Vector3(0.15, 0.0, -0.95),
		SCENE_C + Vector3(-0.85, 0.0, 0.75),
		SCENE_C + Vector3(0.55, 0.0, 0.95),
	]
	for i in clues.size():
		var cd: Dictionary = clues[i]
		var holder := Node3D.new()
		holder.position = spots[i] + Vector3(0, 0.32, 0)
		case_root.add_child(holder)
		var mesh := _make_clue_mesh(str(cd["m"]))
		holder.add_child(mesh)
		# Glow pedestal disc under each clue.
		var disc := MeshInstance3D.new()
		var db := CylinderMesh.new()
		db.top_radius = 0.22
		db.bottom_radius = 0.22
		db.height = 0.015
		disc.mesh = db
		var glow_mat := GraphicsPolish.glow(Color(1.0, 0.75, 0.25), 1.4)
		disc.material_override = glow_mat
		disc.position = Vector3(0, -0.30, 0)
		holder.add_child(disc)
		# Evidence marker number.
		var num := GraphicsPolish.make_label(str(i + 1), 44, Color(1.0, 0.85, 0.3))
		num.position = Vector3(0.0, 0.55, 0.0)
		num.pixel_size = 0.005
		holder.add_child(num)
		holder.set_meta("clue_idx", i)
		holder.set_meta("glow_mat", glow_mat)
		_make_tappable(holder, "clue_%d" % i, "clue", i, 0.42)
		clue_nodes.append(holder)


func _build_board(case: Dictionary) -> void:
	var board := Node3D.new()
	board.position = BOARD_POS
	case_root.add_child(board)
	# Cork board with dark frame.
	var cork := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(2.8, 1.55, 0.06)
	cork.mesh = cb
	cork.material_override = GraphicsPolish.pbr_preset(Color(0.42, 0.28, 0.14), "matte")
	board.add_child(cork)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(2.94, 1.69, 0.04)
	frame.mesh = fb
	frame.material_override = GraphicsPolish.pbr_preset(Color(0.12, 0.08, 0.05), "matte")
	frame.position.z = -0.015
	board.add_child(frame)
	var title := GraphicsPolish.make_label("EVIDENCE BOARD \u2014 arrange in causal order", 34, Color(1.0, 0.9, 0.65))
	title.position = Vector3(0, 0.92, 0.06)
	title.pixel_size = 0.004
	board.add_child(title)
	# 6 numbered slots along the bottom.
	for i in 6:
		var slot := Node3D.new()
		slot.position = Vector3(-1.05 + float(i) * 0.42, -0.42, 0.05)
		board.add_child(slot)
		var plate := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.38, 0.30, 0.02)
		plate.mesh = pb
		plate.material_override = GraphicsPolish.pbr_preset(Color(0.10, 0.12, 0.16), "matte")
		slot.add_child(plate)
		var nl := GraphicsPolish.make_label(str(i + 1), 40, Color(0.55, 0.75, 1.0))
		nl.position = Vector3(0, 0, 0.03)
		nl.pixel_size = 0.004
		slot.add_child(nl)
		slot.set_meta("slot_idx", i)
		slot_nodes.append(slot)
	# 6 draggable clue tokens (shuffled) along the top.
	var clues: Array = case["clues"]
	var order_idx := [0, 1, 2, 3, 4, 5]
	order_idx.shuffle()
	for k in 6:
		var ci: int = order_idx[k]
		var cd: Dictionary = clues[ci]
		var token := Node3D.new()
		token.position = Vector3(-1.05 + float(k) * 0.42, 0.42, 0.05)
		board.add_child(token)
		var card := MeshInstance3D.new()
		var kb := BoxMesh.new()
		kb.size = Vector3(0.38, 0.30, 0.02)
		card.mesh = kb
		card.material_override = GraphicsPolish.pbr_preset(Color(0.16, 0.18, 0.24), "plastic")
		token.add_child(card)
		var edge := MeshInstance3D.new()
		var eb2 := BoxMesh.new()
		eb2.size = Vector3(0.40, 0.32, 0.012)
		edge.mesh = eb2
		edge.material_override = GraphicsPolish.glow(Color(0.35, 0.65, 1.0), 0.7)
		edge.position.z = -0.006
		token.add_child(edge)
		var tl := GraphicsPolish.make_label(str(cd["name"]), 26, Color(1.0, 1.0, 1.0))
		tl.position = Vector3(0, 0.02, 0.03)
		tl.pixel_size = 0.0032
		token.add_child(tl)
		token.set_meta("clue_idx", ci)
		token.set_meta("home", token.position)
		_make_tappable(token, "token_%d" % k, "token", k, 0.30)
		tokens.append(token)
		slot_of_token[k] = -1
	# Verify button.
	verify_btn = Node3D.new()
	verify_btn.position = Vector3(1.75, -0.42, 0.05)
	board.add_child(verify_btn)
	var vb := MeshInstance3D.new()
	var vbb := BoxMesh.new()
	vbb.size = Vector3(0.44, 0.30, 0.03)
	vb.mesh = vbb
	vb.material_override = GraphicsPolish.glow(Color(0.15, 0.55, 0.25), 1.2)
	verify_btn.add_child(vb)
	var vl := GraphicsPolish.make_label("VERIFY", 34, Color(1, 1, 1))
	vl.position = Vector3(0, 0, 0.04)
	vl.pixel_size = 0.004
	verify_btn.add_child(vl)
	_make_tappable(verify_btn, "verify", "verify", 0, 0.34)
	board.visible = false
	board.set_meta("board", true)
	case_root.set_meta("board_node", board)


func _board() -> Node3D:
	if case_root != null and case_root.has_meta("board_node"):
		return case_root.get_meta("board_node") as Node3D
	return null


func _apply_hologram(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if holo_mats.is_empty():
			return
		mi.material_override = holo_mats[0]
	for c in node.get_children():
		_apply_hologram(c)


func _build_suspects(case: Dictionary) -> void:
	var holo := StandardMaterial3D.new()
	holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo.albedo_color = Color(0.35, 0.85, 1.0, 0.42)
	holo.emission_enabled = true
	holo.emission = Color(0.30, 0.80, 1.0)
	holo.emission_energy_multiplier = 1.4
	holo_mats.append(holo)
	var sus: Array = case["suspects"]
	for i in sus.size():
		var sd: Dictionary = sus[i]
		var ped := Node3D.new()
		ped.position = Vector3(SUSPECT_X[i], 0.0, -2.55)
		case_root.add_child(ped)
		# Hologram projector base.
		var disc := MeshInstance3D.new()
		var db := CylinderMesh.new()
		db.top_radius = 0.42
		db.bottom_radius = 0.5
		db.height = 0.10
		disc.mesh = db
		disc.material_override = GraphicsPolish.pbr_preset(Color(0.08, 0.10, 0.14), "metal")
		disc.position.y = 0.05
		ped.add_child(disc)
		var glowring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.40
		tor.outer_radius = 0.46
		glowring.mesh = tor
		glowring.material_override = GraphicsPolish.glow(Color(0.3, 0.8, 1.0), 1.6)
		glowring.rotation_degrees.x = 90.0
		glowring.position.y = 0.11
		ped.add_child(glowring)
		# The suspect model, re-materialed as a hologram.
		var model := _load_model(CHARS + str(sd["model"]))
		if model != null:
			model.position.y = 0.10
			ped.add_child(model)
			_apply_hologram(model)
		# Scan ring that sweeps the body.
		var scan := MeshInstance3D.new()
		var stor := TorusMesh.new()
		stor.inner_radius = 0.34
		stor.outer_radius = 0.37
		scan.mesh = stor
		scan.material_override = GraphicsPolish.glow(Color(0.5, 1.0, 1.0), 2.2)
		scan.rotation_degrees.x = 90.0
		scan.position.y = 0.9
		ped.add_child(scan)
		scan_rings.append(scan)
		var plaque := GraphicsPolish.make_label("%s\n%s" % [str(sd["name"]), str(sd["role"])], 30, Color(0.75, 0.92, 1.0))
		plaque.position = Vector3(0, 2.15, 0)
		plaque.pixel_size = 0.004
		ped.add_child(plaque)
		ped.set_meta("suspect_idx", i)
		_make_tappable(ped, "suspect_%d" % i, "suspect", i, 0.85, 1.0)
		suspects.append(ped)
		asked[i] = [false, false]


func _clear_dialog() -> void:
	if dialog_root != null and is_instance_valid(dialog_root):
		dialog_root.queue_free()
	dialog_root = null
	taps.erase("question_0")
	taps.erase("question_1")
	taps.erase("stmt_0")
	taps.erase("stmt_1")
	taps.erase("flaglie")
	taps.erase("accuse_0")
	taps.erase("accuse_1")
	taps.erase("accuse_2")
	taps.erase("dback")
	taps.erase("dname")
	taps.erase("dans")
	taps.erase("atitle")
	taps.erase("fprompt")


func _dialog_card(text: String, pos: Vector3, size: Vector2, color: Color, tap_id: String, kind: String, data: Variant, fsize: int = 28) -> Node3D:
	var card := Node3D.new()
	card.position = pos
	dialog_root.add_child(card)
	var bg := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(size.x, size.y, 0.02)
	bg.mesh = bb
	bg.material_override = GraphicsPolish.pbr_preset(Color(0.05, 0.07, 0.11), "matte")
	card.add_child(bg)
	var edge := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(size.x + 0.03, size.y + 0.03, 0.012)
	edge.mesh = eb
	edge.material_override = GraphicsPolish.glow(color, 0.9)
	edge.position.z = -0.006
	card.add_child(edge)
	var lbl := GraphicsPolish.make_label(text, fsize, Color(0.93, 0.96, 1.0))
	lbl.position = Vector3(0, 0, 0.03)
	lbl.pixel_size = 0.0034
	card.add_child(lbl)
	_make_tappable(card, tap_id, kind, data, maxf(size.x, size.y) * 0.6)
	return card


func _show_suspect_dialog(si: int) -> void:
	_clear_dialog()
	selected_suspect = si
	var case: Dictionary = CASES[case_idx]
	var sd: Dictionary = case["suspects"][si]
	dialog_root = Node3D.new()
	dialog_root.position = Vector3(SUSPECT_X[si], 1.55, -2.05)
	add_child(dialog_root)
	_dialog_card("%s \u2014 %s" % [str(sd["name"]), str(sd["role"])], Vector3(0, 0.78, 0), Vector2(1.5, 0.28), Color(0.3, 0.8, 1.0), "dname", "noop", 0, 30)
	var qa: Array = sd["q"]
	for qi in 2:
		var qd: Dictionary = qa[qi]
		var was_asked: bool = (asked[si] as Array)[qi]
		var label_text := ("\u2713 " if was_asked else "") + str(qd["q"])
		_dialog_card(label_text, Vector3(0, 0.34 - float(qi) * 0.34, 0), Vector2(1.7, 0.28), Color(0.55, 0.75, 1.0), "question_%d" % qi, "question", [si, qi], 26)
	# Answer area.
	var ans := ""
	if (asked[si] as Array)[0]:
		ans += "A: %s\n" % str((qa[0] as Dictionary)["a"])
	if (asked[si] as Array)[1]:
		ans += "A: %s" % str((qa[1] as Dictionary)["a"])
	if ans != "":
		_dialog_card(ans.strip_edges(), Vector3(0, -0.52, 0), Vector2(1.8, 0.42), Color(0.75, 0.65, 0.35), "dans", "noop", 0, 24)
	# Flag-the-lie + back.
	var both_asked: bool = (asked[si] as Array)[0] and (asked[si] as Array)[1]
	if both_asked and not lie_exposed:
		_dialog_card("FLAG THE LIE \u25b8", Vector3(0, -0.98, 0), Vector2(1.1, 0.26), Color(1.0, 0.45, 0.30), "flaglie", "flaglie", si, 28)
	_dialog_card("\u2190 BACK", Vector3(-1.15, -0.98, 0), Vector2(0.55, 0.26), Color(0.5, 0.55, 0.65), "dback", "dback", 0, 28)


func _show_flag_mode(si: int) -> void:
	_clear_dialog()
	flag_mode = true
	var case: Dictionary = CASES[case_idx]
	var sd: Dictionary = case["suspects"][si]
	dialog_root = Node3D.new()
	dialog_root.position = Vector3(SUSPECT_X[si], 1.55, -2.05)
	add_child(dialog_root)
	_dialog_card("Which statement is the LIE?\nTap the one that contradicts the clues.", Vector3(0, 0.72, 0), Vector2(1.8, 0.40), Color(1.0, 0.45, 0.30), "fprompt", "noop", 0, 26)
	var qa: Array = sd["q"]
	for qi in 2:
		var qd: Dictionary = qa[qi]
		_dialog_card(str(qd["a"]), Vector3(0, 0.18 - float(qi) * 0.42, 0), Vector2(1.8, 0.36), Color(0.65, 0.45, 0.30), "stmt_%d" % qi, "stmt", [si, qi], 24)
	_dialog_card("\u2190 BACK", Vector3(0, -0.78, 0), Vector2(0.55, 0.26), Color(0.5, 0.55, 0.65), "dback", "dback", 0, 28)


func _show_accuse_panel() -> void:
	_clear_dialog()
	phase = "accuse"
	_update_phase_hud()
	var case: Dictionary = CASES[case_idx]
	dialog_root = Node3D.new()
	dialog_root.position = Vector3(0.0, 1.45, -1.9)
	add_child(dialog_root)
	_dialog_card("NAME THE CULPRIT", Vector3(0, 0.75, 0), Vector2(1.5, 0.28), Color(1.0, 0.35, 0.25), "atitle", "noop", 0, 30)
	var sus: Array = case["suspects"]
	for i in sus.size():
		var sd: Dictionary = sus[i]
		var tag := ""
		if i == selected_suspect and lie_exposed:
			tag = " \u2014 CAUGHT LYING"
		_dialog_card(str(sd["name"]) + tag, Vector3(0, 0.30 - float(i) * 0.36, 0), Vector2(1.7, 0.30), Color(1.0, 0.55, 0.35), "accuse_%d" % i, "accuse", i, 28)
	_set_msg("ACCUSE: tap a suspect to close the case", 6.0)


func _update_phase_hud() -> void:
	if hud_phase == null:
		return
	var names := {"scan": "1/4 SCAN", "analyze": "2/4 ANALYZE", "interrogate": "3/4 INTERROGATE", "accuse": "4/4 ACCUSE", "solved": "CASE CLOSED"}
	hud_phase.text = str(names.get(phase, phase))


func _on_tap(tap_id: String) -> void:
	if not taps.has(tap_id):
		return
	var info: Dictionary = taps[tap_id]
	var kind := str(info["kind"])
	var data: Variant = info["data"]
	match kind:
		"clue":
			_collect_clue(int(data))
		"token":
			pass # drag handled on press
		"verify":
			_verify_board()
		"suspect":
			if phase == "interrogate" or phase == "accuse":
				Haptics.tick()
				_show_suspect_dialog(int(data))
		"question":
			_ask_question(data as Array)
		"stmt":
			_flag_statement(data as Array)
		"flaglie":
			_show_flag_mode(int(data))
		"dback":
			_clear_dialog()
			selected_suspect = -1
			flag_mode = false
		"accuse":
			_accuse(int(data))
		"nextcase":
			_next_case()
		"noop":
			pass


func _collect_clue(i: int) -> void:
	if phase != "scan":
		return
	var holder: Node3D = clue_nodes[i]
	if holder.get_meta("collected", false):
		return
	holder.set_meta("collected", true)
	collected += 1
	Haptics.tick()
	var pos: Vector3 = holder.global_position
	GraphicsPolish.spawn_sparks(self, pos, Color(1.0, 0.8, 0.3), 18)
	var glow_mat: StandardMaterial3D = holder.get_meta("glow_mat")
	if glow_mat != null:
		glow_mat.albedo_color = Color(0.2, 0.9, 0.4)
		glow_mat.emission = Color(0.2, 0.9, 0.4)
	var case: Dictionary = CASES[case_idx]
	var cd: Dictionary = (case["clues"] as Array)[i]
	_show_hint("CLUE %d/6: %s" % [collected, str(cd["name"])], str(cd["hint"]))
	# Pop animation: bounce the clue.
	holder.scale = Vector3.ONE * 1.35
	if collected >= 6:
		_set_msg("All clues found \u2014 arrange them on the board", 5.0)
		phase = "analyze"
		_update_phase_hud()
		var b := _board()
		if b != null:
			b.visible = true
	else:
		_set_msg("Clue %d of 6 collected" % collected, 2.5)


func _verify_board() -> void:
	if phase != "analyze":
		return
	var case: Dictionary = CASES[case_idx]
	var order: Array = case["order"]
	var wrong := 0
	for slot_i in 6:
		var ti: int = token_in_slot[slot_i]
		if ti < 0:
			wrong += 1
			continue
		var ci: int = tokens[ti].get_meta("clue_idx")
		if int(order[slot_i]) != ci:
			wrong += 1
			# Flash the wrong token red.
			var card := (tokens[ti] as Node3D).get_child(1) as MeshInstance3D
			if card != null:
				card.material_override = GraphicsPolish.glow(Color(1.0, 0.2, 0.2), 1.4)
	if wrong == 0:
		Haptics.thump()
		_set_msg("Timeline correct. The suspects await.", 5.0)
		GraphicsPolish.spawn_confetti(self, BOARD_POS + Vector3(0, 0.6, 0.4), 40)
		phase = "interrogate"
		_update_phase_hud()
		var b := _board()
		if b != null:
			b.visible = false
		_set_msg("INTERROGATE: question each suspect, then flag the lie", 6.0)
	else:
		Haptics.tick()
		_set_msg("%d of 6 out of place. Re-read your field notes." % wrong, 4.0)


func _ask_question(data: Array) -> void:
	var si := int(data[0])
	var qi := int(data[1])
	(asked[si] as Array)[qi] = true
	Haptics.tick()
	var case: Dictionary = CASES[case_idx]
	var qd: Dictionary = ((case["suspects"] as Array)[si] as Dictionary)["q"][qi]
	GraphicsPolish.spawn_sparks(self, (suspects[si] as Node3D).global_position + Vector3(0, 1.4, 0), Color(0.5, 0.9, 1.0), 10)
	_show_suspect_dialog(si)
	var both: bool = (asked[si] as Array)[0] and (asked[si] as Array)[1]
	if both:
		var all_asked := true
		for k in asked.keys():
			if not ((asked[k] as Array)[0] and (asked[k] as Array)[1]):
				all_asked = false
		if all_asked:
			_set_msg("All suspects questioned. Flag the lie, detective.", 5.0)


func _flag_statement(data: Array) -> void:
	var si := int(data[0])
	var qi := int(data[1])
	var case: Dictionary = CASES[case_idx]
	var sd: Dictionary = (case["suspects"] as Array)[si]
	var lie_idx := int(sd["lie"])
	if lie_idx >= 0 and qi == lie_idx:
		lie_exposed = true
		selected_suspect = si
		flag_mode = false
		Haptics.thump()
		GraphicsPolish.spawn_confetti(self, (suspects[si] as Node3D).global_position + Vector3(0, 1.6, 0), 36)
		_show_hint("LIE EXPOSED", str(sd["lie_hint"]) + "\n\n%s is lying. Time to make the accusation." % str(sd["name"]))
		_clear_dialog()
		_show_accuse_panel()
	else:
		Haptics.tick()
		_show_hint("STATEMENT CHECKS OUT", "That one holds up against the evidence. Keep digging \u2014 compare every answer to your field notes.")
		_show_suspect_dialog(si)


func _accuse(si: int) -> void:
	var case: Dictionary = CASES[case_idx]
	if si == int(case["culprit"]):
		_case_solved()
	else:
		Haptics.tick()
		var sd: Dictionary = (case["suspects"] as Array)[si]
		var liar: Dictionary = (case["suspects"] as Array)[int(case["culprit"])]
		var hint_text := "Think again. "
		if lie_exposed:
			hint_text += str(liar["lie_hint"])
		elif not accuse_hint_used:
			accuse_hint_used = true
			hint_text += "Someone's story contradicts the physical evidence \u2014 re-question the suspects and FLAG THE LIE."
		else:
			hint_text += str(liar["lie_hint"])
		_show_hint("WRONG ACCUSATION", "%s walks free... for now.\n\n%s" % [str(sd["name"]), hint_text])
		_show_accuse_panel()


func _case_solved() -> void:
	phase = "solved"
	_update_phase_hud()
	Haptics.thump()
	var case: Dictionary = CASES[case_idx]
	_show_hint("MOTIVE", str(case["motive"]))
	GraphicsPolish.spawn_confetti(self, SCENE_C + Vector3(0, 1.5, 0), 90)
	GraphicsPolish.spawn_sparks(self, SCENE_C + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.3), 30)
	if solved_count < case_idx + 1:
		solved_count = case_idx + 1
		_save_progress()
	# CASE CLOSED stamp.
	var stamp := GraphicsPolish.make_label("CASE CLOSED", 96, Color(1.0, 0.25, 0.2))
	stamp.position = Vector3(0, 1.9, -2.2)
	stamp.pixel_size = 0.011
	stamp.rotation_degrees.z = -8.0
	case_root.add_child(stamp)
	stamp.set_meta("stamp", true)
	_set_msg("Case closed, detective.", 8.0)
	# Next-case button.
	next_btn = Node3D.new()
	next_btn.position = Vector3(0, 0.75, -1.9)
	case_root.add_child(next_btn)
	var nb := MeshInstance3D.new()
	var nbb := BoxMesh.new()
	nbb.size = Vector3(1.3, 0.34, 0.03)
	nb.mesh = nbb
	var is_last := case_idx >= CASES.size() - 1
	nb.material_override = GraphicsPolish.glow(Color(0.15, 0.55, 0.25) if not is_last else Color(0.55, 0.35, 0.1), 1.2)
	next_btn.add_child(nb)
	var nl := GraphicsPolish.make_label("NEXT CASE \u25b8" if not is_last else "FINISH \u25b8", 36, Color(1, 1, 1))
	nl.position = Vector3(0, 0, 0.04)
	nl.pixel_size = 0.0045
	next_btn.add_child(nl)
	_make_tappable(next_btn, "nextcase", "nextcase", 0, 0.5)


func _next_case() -> void:
	Haptics.tick()
	if case_idx + 1 < CASES.size():
		_start_case(case_idx + 1)
	else:
		_show_all_done()


func _show_all_done() -> void:
	_clear_case()
	phase = "alldone"
	if hud_title != null:
		hud_title.text = "AR DETECTIVE \u2014 FILE CLOSED"
	_update_phase_hud()
	var done := GraphicsPolish.make_label("ALL 3 CASES SOLVED\nThe city sleeps easier tonight, detective.", 56, Color(1.0, 0.9, 0.6))
	done.position = Vector3(0, 1.8, -2.2)
	done.pixel_size = 0.008
	add_child(done)
	done_label = done
	GraphicsPolish.spawn_confetti(self, SCENE_C + Vector3(0, 1.5, 0), 120)
	next_btn = Node3D.new()
	next_btn.position = Vector3(0, 0.9, -1.9)
	add_child(next_btn)
	var nb := MeshInstance3D.new()
	var nbb := BoxMesh.new()
	nbb.size = Vector3(1.4, 0.34, 0.03)
	nb.mesh = nbb
	nb.material_override = GraphicsPolish.glow(Color(0.15, 0.45, 0.7), 1.2)
	next_btn.add_child(nb)
	var nl := GraphicsPolish.make_label("REPLAY CASE 1", 36, Color(1, 1, 1))
	nl.position = Vector3(0, 0, 0.04)
	nl.pixel_size = 0.0045
	next_btn.add_child(nl)
	_make_tappable(next_btn, "nextcase", "nextcase", 0, 0.5)
	case_idx = -1 # so _next_case() starts case 0
	taps["nextcase"] = {"node": next_btn, "kind": "nextcase", "data": 0}


func _restart_case() -> void:
	_set_msg("", 0.0)
	if hint_panel != null:
		hint_panel.visible = false
	_start_case(case_idx if case_idx >= 0 else 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				pressing = true
				press_pos = mb.position
				press_moved = 0.0
				press_time = Time.get_ticks_msec()
				drag_token = -1
				if phase == "analyze":
					var hit := _screen_pick(mb.position)
					if hit.begins_with("token_"):
						var ti := int(str(taps[hit]["data"]))
						drag_token = ti
						_reset_token_edge(ti)
						# Lift from slot.
						if slot_of_token.get(ti, -1) >= 0:
							token_in_slot[slot_of_token[ti]] = -1
							slot_of_token[ti] = -1
			else:
				if pressing:
					if drag_token >= 0:
						_drop_token(drag_token)
						drag_token = -1
					elif press_moved < 10.0 and Time.get_ticks_msec() - press_time < 600:
						_on_tap(_screen_pick(mb.position))
				pressing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if pressing:
			press_moved += mm.relative.length()
			if drag_token >= 0 and camera != null:
				_move_token_to_screen(drag_token, mm.position)


func _reset_token_edge(ti: int) -> void:
	if ti < 0 or ti >= tokens.size():
		return
	var edge := (tokens[ti] as Node3D).get_child(1) as MeshInstance3D
	if edge != null:
		edge.material_override = GraphicsPolish.glow(Color(0.35, 0.65, 1.0), 0.7)


func _move_token_to_screen(ti: int, screen_pos: Vector2) -> void:
	var b := _board()
	if b == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var plane_z := (b.global_position + Vector3(0, 0, 0.05)).z
	if absf(dir.z) < 0.0001:
		return
	var t := (plane_z - origin.z) / dir.z
	if t < 0.0:
		return
	var hit := origin + dir * t
	var local: Vector3 = b.to_local(hit)
	local.x = clampf(local.x, -1.25, 1.25)
	local.y = clampf(local.y, -0.60, 0.62)
	local.z = 0.09
	(tokens[ti] as Node3D).position = local


func _drop_token(ti: int) -> void:
	var b := _board()
	var tok := tokens[ti] as Node3D
	if b == null:
		(tok as Node3D).position = tok.get_meta("home")
		return
	# Find nearest slot within snap range.
	var best := -1
	var best_d := 0.30
	for si in 6:
		var sp: Vector3 = (slot_nodes[si] as Node3D).position
		var d: float = Vector2(tok.position.x - sp.x, tok.position.y - sp.y).length()
		if d < best_d:
			best_d = d
			best = si
	if best >= 0:
		# Swap out any token already there.
		var occupant: int = token_in_slot[best]
		if occupant >= 0 and occupant != ti:
			slot_of_token[occupant] = -1
			(tokens[occupant] as Node3D).position = (tokens[occupant] as Node3D).get_meta("home")
		token_in_slot[best] = ti
		slot_of_token[ti] = best
		tok.position = (slot_nodes[best] as Node3D).position + Vector3(0, 0, 0.04)
		Haptics.tick()
	else:
		slot_of_token[ti] = -1
		tok.position = tok.get_meta("home")


func _process(delta: float) -> void:
	pulse_t += delta
	if Input.is_key_pressed(KEY_R):
		_restart_case()
		return
	# Clue glow pulse + collect pop ease.
	for h in clue_nodes:
		var holder := h as Node3D
		if not is_instance_valid(holder):
			continue
		var gm: StandardMaterial3D = holder.get_meta("glow_mat")
		if gm != null and not bool(holder.get_meta("collected", false)):
			GraphicsPolish.pulse_glow(gm, 1.4, 0.8, pulse_t, 3.0)
		GraphicsPolish.ease_scale(holder, Vector3.ONE, 6.0, delta)
		holder.rotation.y += delta * 0.6
	# Hologram flicker + scan rings.
	for i in holo_mats.size():
		var hm: StandardMaterial3D = holo_mats[i]
		hm.emission_energy_multiplier = 1.4 + 0.35 * sin(pulse_t * 9.0 + float(i) * 2.0)
	for i in scan_rings.size():
		var ring := scan_rings[i] as Node3D
		if is_instance_valid(ring):
			ring.position.y = 0.25 + fmod(pulse_t * 0.7 + float(i) * 0.5, 1.7)
	# Lamp subtle flicker.
	if lamp_light != null:
		lamp_light.light_energy = 3.2 + 0.25 * sin(pulse_t * 13.0) * sin(pulse_t * 7.3)
	# Timers.
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0 and msg_label != null:
			msg_label.text = ""
	if hint_t > 0.0:
		hint_t -= delta
		if hint_t <= 0.0 and hint_panel != null:
			hint_panel.visible = false
	if intro_t > 0.0:
		intro_t -= delta
		if intro_t <= 0.0 and intro_label != null:
			intro_label.visible = false
	# XR: pinch tap + pinch-drag tokens (gated so desktop never double-fires).
	if ARUpgradeKit.is_xr_active():
		var pinching := ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)
		if pinching and not prev_pinch:
			xr_drag_token = -1
			if phase == "analyze":
				var hit := _xr_pick()
				if hit.begins_with("token_"):
					xr_drag_token = int(str(taps[hit]["data"]))
					_reset_token_edge(xr_drag_token)
					if slot_of_token.get(xr_drag_token, -1) >= 0:
						token_in_slot[slot_of_token[xr_drag_token]] = -1
						slot_of_token[xr_drag_token] = -1
				else:
					xr_tap_armed = true
			else:
				xr_tap_armed = true
		elif pinching and xr_drag_token >= 0:
			_move_token_to_xr(xr_drag_token)
		elif not pinching and prev_pinch:
			if xr_drag_token >= 0:
				_drop_token(xr_drag_token)
				xr_drag_token = -1
			elif xr_tap_armed:
				_on_tap(_xr_pick())
				xr_tap_armed = false
		prev_pinch = pinching


func _move_token_to_xr(ti: int) -> void:
	var b := _board()
	if b == null:
		return
	var r: Array = ARUpgradeKit.pointer_ray(self, ARUpgradeKit.HAND_RIGHT)
	var origin: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var plane_z := (b.global_position + Vector3(0, 0, 0.05)).z
	if absf(dir.z) < 0.0001:
		return
	var t := (plane_z - origin.z) / dir.z
	if t < 0.0:
		return
	var hit := origin + dir * t
	var local: Vector3 = b.to_local(hit)
	local.x = clampf(local.x, -1.25, 1.25)
	local.y = clampf(local.y, -0.60, 1.25)
	local.z = 0.09
	# XR: allow dragging tokens from the top row down; clamp generous.
	(tokens[ti] as Node3D).position = local
