## Runewright.gd - NEXUS ARCADE v0.11.0: RUNEWRIGHT.
## Draw runes in mid-air to forge custom spells, then defend your couch-fort
## from the wave. Gesture crafting: trace one rune per slot
## (SHAPE x ELEMENT x MODIFIER = 125 real combos). Spells are named on
## discovery ("Stormlance of Seeking") and recorded in your spellbook.
## Tower defense: animated monsters stream toward your couch; you cast from
## your hands. Between waves, refine your spellbook.
##
## Enemies: Quaternius animatedmonster (CC0 1.0), fully animated. Runes are
## procedural trail meshes; everything else is original.
extends Node3D
class_name RunewrightGame

const MDIR := "res://assets/models/shared_monsters/"
const SAVE_PATH := "user://nexus_arcade.cfg"
const RESAMPLE_N := 32
const MATCH_THRESHOLD := 0.42
const FORT_HP := 100.0
const MAX_WAVE := 5

const SHAPES := ["circle", "line", "triangle", "zigzag", "square"]
const SHAPE_NOUN := {"circle": "Bolt", "line": "Lance", "triangle": "Nova", "zigzag": "Chain", "square": "Ward"}
const ELEM_ADJ := {"circle": "Ember", "line": "Storm", "triangle": "Frost", "zigzag": "Gale", "square": "Stone"}
const ELEM_NAME := {"circle": "Fire", "line": "Lightning", "triangle": "Frost", "zigzag": "Wind", "square": "Stone"}
const MOD_SUFFIX := {"circle": "of Splitting", "line": "of Piercing", "triangle": "of Ruin", "zigzag": "of Seeking", "square": "of the Mountain"}
const ELEM_COLOR := {
	"circle": Color(1.0, 0.45, 0.1), "line": Color(0.5, 0.8, 1.0),
	"triangle": Color(0.6, 0.9, 1.0), "zigzag": Color(0.6, 1.0, 0.7),
	"square": Color(0.85, 0.7, 0.4),
}

var controller_config := {
	"uses_controllers": true,
	"skin": "none",
	"buttons": {
		"trigger": "Trace rune (hold) / Cast armed spell (tap)",
		"grip": "Clear current rune",
		"thumbstick": "—",
		"menu": "Pause",
	},
}

var _origin: Node3D
var _controllers := {}
# Tracing.
var _tracing := false
var _trace_src := ""       # "hand_left" | "hand_right" | "ctl_left" | "ctl_right"
var _trace_pts: Array = [] # Array[Vector3] world
var _trace_plane := Plane()
var _trail_mesh: ImmediateMesh
var _trail: MeshInstance3D
var _press_prev := {}
var _grip_prev := {}
# Spell state.
var _slots := ["", "", ""]       # shape, element, modifier rune names
var _slot_idx := 0
var _orbs: Array = []            # orb nodes per slot
var _orb_labels: Array = []
var _armed := {}                 # forged spell dict
var _spellbook := {}             # name -> count
var _circle_center := Vector3.ZERO
# Combat.
var _enemies: Array = []
var _projectiles: Array = []
var _proj_pool: Array = []
var _fort_hp := FORT_HP
var _fort_pos := Vector3.ZERO
var _fort_ring: MeshInstance3D
var _ward_hp := 0.0
var _ward_node: MeshInstance3D
var _wave := 0
var _wave_state := "forge"   # forge | fighting | refine | done
var _wave_t := 0.0
var _spawn_queue: Array = []
var _spawn_acc := 0.0
var _score := 0
var _hud: Label3D
var _spell_label: Label3D
var _announce: Label3D
var _announce_t := 0.0
var _game_over := false
var _templates := {}
# v0.11.0 (Animator) ambient elements:
var _trail_embers: Array = []    # (a) pooled lingering embers on rune trails
var _ward_mats: Array = []       # (b) ward totem materials for breathe pulse
var _cast_wind := 0.0            # (e) orb flutter timer after a cast


func _ready() -> void:
	_origin = _find_origin()
	_find_controllers()
	_build_templates()
	ArtKit.register_game_sfx(self, {
		"trace": "sparkle", "forge": "powerup", "discover": "fanfare",
		"cast": "zap", "boom": "explosion", "hit": "hit", "die": "thud",
		"win": "fanfare", "lose": "fail", "wave": "countdown",
		"ward": "heal", "clear": "ui_back",
	})
	ArtKit.set_intensity(self, 1)
	_load_spellbook()
	if RoomKit.is_available():
		await RoomKit.refresh()
	_setup_arena()
	_build_trail()
	_build_rune_ambient()
	_build_hud()
	_telemetry("rune_start", {})
	_announce_text("RUNEWRIGHT\nThe air remembers the old wardens' runes.\nTrace them. Combine them. Name what you make.", 4.5)
	JuiceFX.title_card("RUNEWRIGHT", "Draw runes. Invent spells. Hold the fort.", Color(0.4, 0.9, 0.7))


# ---------------------------------------------------------------- setup ---

func _find_origin() -> Node3D:
	var f := get_tree().root.find_children("*", "XROrigin3D", true, false)
	return f[0] as Node3D if not f.is_empty() else null


func _find_controllers() -> void:
	_controllers.clear()
	if _origin == null:
		return
	for side in ["left", "right"]:
		var n := _origin.get_node_or_null("LeftController" if side == "left" else "RightController")
		if n != null:
			_controllers[side] = n


func _head_pos() -> Vector3:
	if _origin != null:
		var c := _origin.get_node_or_null("XRCamera3D") as Camera3D
		if c != null:
			return c.global_position
	return Vector3(0, 1.6, 0)


func _setup_arena() -> void:
	# Fort = the couch (or a fallback ward-stone at room center).
	var couch := RoomKit.get_couch()
	if not couch.is_empty():
		_fort_pos = RoomKit.cuboid_top(couch) + Vector3(0, 0.05, 0)
	else:
		var b := RoomKit.room_bounds()
		_fort_pos = Vector3(b.position.x + b.size.x * 0.5, 0.4, b.position.y + b.size.y * 0.5)
	# Fort ring.
	_fort_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.65
	_fort_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	_fort_ring.material_override = mat
	get_tree().current_scene.add_child(_fort_ring)
	_fort_ring.position = _fort_pos
	var fl := Label3D.new()
	fl.text = "FORT"
	fl.font_size = 56
	fl.modulate = Color(0.5, 0.85, 1.0)
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.position = _fort_pos + Vector3(0, 0.55, 0)
	get_tree().current_scene.add_child(fl)
	# Spell circle: placed once, 0.75 m in front of the player at chest height.
	var hp := _head_pos()
	var fwd := Vector3(0, 0, -1)
	if _origin != null:
		var c := _origin.get_node_or_null("XRCamera3D") as Camera3D
		if c != null:
			fwd = -c.global_transform.basis.z
			fwd.y = 0
			fwd = fwd.normalized()
	_circle_center = hp + fwd * 0.75 + Vector3(0, -0.15, 0)
	_build_spell_circle()
	# Ward bubble (hidden until cast).
	_ward_node = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	_ward_node.mesh = sm
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.5, 0.85, 1.0, 0.22)
	wmat.emission_enabled = true
	wmat.emission = Color(0.5, 0.85, 1.0)
	wmat.emission_energy_multiplier = 1.2
	_ward_node.material_override = wmat
	_ward_node.position = _fort_pos + Vector3(0, 0.45, 0)
	_ward_node.visible = false
	get_tree().current_scene.add_child(_ward_node)


func _build_spell_circle() -> void:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.position = _circle_center
	# Hologram disc.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.34
	cm.bottom_radius = 0.34
	cm.height = 0.008
	disc.mesh = cm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.3, 0.5, 1.0, 0.28)
	dmat.emission_enabled = true
	dmat.emission = Color(0.35, 0.55, 1.0)
	dmat.emission_energy_multiplier = 1.0
	disc.material_override = dmat
	root.add_child(disc)
	# 3 slot orbs.
	var names := ["SHAPE", "ELEMENT", "MODIFIER"]
	for i in range(3):
		var orb := MeshInstance3D.new()
		var spm := SphereMesh.new()
		spm.radius = 0.055
		spm.height = 0.11
		orb.mesh = spm
		var omat := StandardMaterial3D.new()
		omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		omat.albedo_color = Color(0.25, 0.3, 0.45)
		omat.emission_enabled = true
		omat.emission = Color(0.3, 0.4, 0.7)
		omat.emission_energy_multiplier = 0.8
		orb.material_override = omat
		orb.position = Vector3((i - 1) * 0.22, 0.12, 0)
		root.add_child(orb)
		var lab := Label3D.new()
		lab.text = names[i]
		lab.font_size = 36
		lab.modulate = Color(0.75, 0.85, 1.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3((i - 1) * 0.22, 0.24, 0)
		root.add_child(lab)
		_orbs.append(orb)
		_orb_labels.append(lab)
	_refresh_orbs()


func _refresh_orbs() -> void:
	var slot_names := ["SHAPE", "ELEMENT", "MODIFIER"]
	for i in range(3):
		var orb: MeshInstance3D = _orbs[i]
		var mat := orb.material_override as StandardMaterial3D
		var lab: Label3D = _orb_labels[i]
		if _slots[i] != "":
			var col: Color = ELEM_COLOR[_slots[i]]
			mat.albedo_color = col
			mat.emission = col
			mat.emission_energy_multiplier = 2.2
			lab.text = _slots[i].to_upper()
		elif i == _slot_idx and _wave_state != "fighting":
			mat.albedo_color = Color(1.0, 0.9, 0.4)
			mat.emission = Color(1.0, 0.9, 0.4)
			mat.emission_energy_multiplier = 2.5
			lab.text = slot_names[i] + " ?"
		else:
			mat.albedo_color = Color(0.25, 0.3, 0.45)
			mat.emission = Color(0.3, 0.4, 0.7)
			mat.emission_energy_multiplier = 0.8
			lab.text = slot_names[i]


## v0.11.0 (Animator): 5 cheap ambient elements.
## (a) rune-trail embers · (b) ward totem breathe · (c) enemy anticipation ·
## (d) fort fireflies · (e) spellbook page flutter.
func _build_rune_ambient() -> void:
	# (a) Pooled ember quads that linger where the fingertip traced.
	for i in 24:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.03, 0.03)
		q.mesh = qm
		var m := GraphicsPolish.glow(Color(1.0, 0.6, 0.25), 1.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.material_override = m
		q.visible = false
		add_child(q)
		_trail_embers.append({"node": q, "mat": m, "life": 0.0})
	# (b) Ward totem breathe: collect the ward material for pulsing.
	if _ward_node != null:
		var wm := _ward_node.material_override as StandardMaterial3D
		if wm != null:
			_ward_mats.append({"mat": wm, "phase": 0.0})
	# (d) Fireflies around the fort (12-instance drifting field).
	AmbientLife.butterflies(self, 12, Vector3(1.6, 1.2, 1.6),
		Color(0.7, 1.0, 0.4), Color(1.0, 0.9, 0.4)).position = _fort_pos


## (a) Drop a lingering ember at the traced point (pooled).
func _trail_ember_at(p: Vector3) -> void:
	for e in _trail_embers:
		if float(e["life"]) <= 0.0:
			var qn: MeshInstance3D = e["node"]
			qn.position = p
			qn.visible = true
			e["life"] = 1.4
			return


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 3.0
	_trail.material_override = mat
	get_tree().current_scene.add_child(_trail)
	_trail.visible = false


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hud.font_size = 50
	_hud.modulate = Color(0.85, 0.92, 1.0)
	_hud.outline_size = 10
	add_child(_hud)
	_spell_label = Label3D.new()
	_spell_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_spell_label.font_size = 58
	_spell_label.modulate = Color(1.0, 0.9, 0.5)
	_spell_label.outline_size = 10
	add_child(_spell_label)
	_announce = Label3D.new()
	_announce.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_announce.font_size = 88
	_announce.modulate = Color(0.7, 0.9, 1.0)
	_announce.outline_size = 14
	add_child(_announce)


# ------------------------------------------------------------- tracing ---

func _build_templates() -> void:
	_templates["circle"] = _resample(_circle_pts(), RESAMPLE_N)
	_templates["line"] = _resample(_line_pts(), RESAMPLE_N)
	_templates["triangle"] = _resample(_triangle_pts(), RESAMPLE_N)
	_templates["zigzag"] = _resample(_zigzag_pts(), RESAMPLE_N)
	_templates["square"] = _resample(_square_pts(), RESAMPLE_N)
	for k in _templates.keys():
		_templates[k] = _normalize(_templates[k])


func _circle_pts() -> Array:
	var p := []
	for i in range(33):
		var a := TAU * i / 32.0
		p.append(Vector2(cos(a), sin(a)))
	return p


func _line_pts() -> Array:
	return [Vector2(-1, 0), Vector2(1, 0)]


func _triangle_pts() -> Array:
	return [Vector2(0, 1), Vector2(-0.87, -0.5), Vector2(0.87, -0.5), Vector2(0, 1)]


func _zigzag_pts() -> Array:
	return [Vector2(-1, 0.5), Vector2(-0.33, -0.5), Vector2(0.33, 0.5), Vector2(1, -0.5)]


func _square_pts() -> Array:
	return [Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(-0.7, -0.7)]


func _resample(pts: Array, n: int) -> Array:
	# Arc-length resample to n points.
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector2).distance_to(pts[i - 1])
	if total < 0.0001:
		var dup := []
		for i in range(n):
			dup.append(pts[0])
		return dup
	var step := total / float(n - 1)
	var out := [pts[0]]
	var acc := 0.0
	var i := 1
	while out.size() < n and i < pts.size():
		var d: float = (pts[i] as Vector2).distance_to(pts[i - 1])
		if acc + d >= step:
			var t := (step - acc) / d
			var np: Vector2 = (pts[i - 1] as Vector2).lerp(pts[i], t)
			out.append(np)
			pts[i - 1] = np
			acc = 0.0
		else:
			acc += d
			i += 1
	while out.size() < n:
		out.append(pts[pts.size() - 1])
	return out


func _normalize(pts: Array) -> Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var maxd := 0.001
	for p in pts:
		maxd = maxf(maxd, (p - c).length())
	var out := []
	for p in pts:
		out.append((p - c) / maxd)
	return out


func _match_rune(pts2d: Array) -> String:
	if pts2d.size() < 8:
		return ""
	var q := _normalize(_resample(pts2d, RESAMPLE_N))
	var best := ""
	var bd := MATCH_THRESHOLD
	for k in _templates.keys():
		var t: Array = _templates[k]
		# Try cyclic shifts (closed shapes) + reversal (open shapes).
		for shift in range(0, RESAMPLE_N, 4):
			var d := _mean_dist_shifted(q, t, shift, false)
			if d < bd:
				bd = d
				best = k
			var dr := _mean_dist_shifted(q, t, shift, true)
			if dr < bd:
				bd = dr
				best = k
	return best


func _mean_dist_shifted(q: Array, t: Array, shift: int, rev: bool) -> float:
	var d := 0.0
	var n := q.size()
	for i in range(n):
		var j := (i + shift) % n
		var tp: Vector2 = t[n - 1 - j] if rev else t[j]
		d += (q[i] as Vector2).distance_to(tp)
	return d / float(n)


func _fingertip(side: int) -> Variant:
	# Index fingertip world position (hand-tracking path for rune tracing).
	if _origin == null:
		return null
	var found := XRUIPointer.find_hand_trackers()
	var tr: XRHandTracker = found["left"] if side == XRPositionalTracker.TRACKER_HAND_LEFT else found["right"]
	if tr == null or not tr.has_tracking_data:
		return null
	if not XRUIPointer._joint_ok(tr, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP):
		return null
	var local: Transform3D = tr.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
	var o := XRUIPointer._tracking_to_world(_origin)
	return (o * local).origin


func _trace_tip(src: String) -> Variant:
	var parts := src.split("_")
	var side: String = parts[1]
	if parts[0] == "hand":
		return _fingertip(XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT)
	var ctl: XRController3D = _controllers.get(side)
	if ctl == null or XRServer.get_tracker(ctl.tracker) == null:
		return null
	return ctl.global_position + (-ctl.global_transform.basis.z * 0.14)


func _poll_trace() -> void:
	var sources := []
	if _origin != null:
		for side in ["left", "right"]:
			var hr: Dictionary = XRUIPointer.hand_ray(
				XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT,
				_origin)
			if bool(hr["active"]):
				sources.append({"id": "hand_" + side, "press": bool(hr["pinch"])})
	for side in _controllers.keys():
		var ctl: XRController3D = _controllers[side]
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		sources.append({"id": "ctl_" + side, "press": XRUIPointer.trigger_pressed(ctl),
			"grip": ctl.is_button_pressed("grip_click") or ctl.is_button_pressed("grip")})
	for s in sources:
		var id: String = s["id"]
		var press: bool = s["press"]
		var was: bool = _press_prev.get(id, false)
		_press_prev[id] = press
		if s.get("grip", false) and not bool(_grip_prev.get(id, false)):
			_clear_slots()
		_grip_prev[id] = bool(s.get("grip", false))
		if press and not was and not _tracing and _wave_state != "fighting":
			var im := "hands" if id.begins_with("hand") else "controllers"
			_note_input(im)
			# Armed + tapping away from the spell circle = begin the wave.
			var tip0 = _trace_tip(id)
			if not _armed.is_empty() and tip0 != null \
					and (tip0 as Vector3).distance_to(_circle_center) > 0.6:
				_try_begin_wave()
			else:
				_begin_trace(id)
		elif press and not was and _wave_state == "fighting" and not _tracing:
			# Tap = cast the armed spell.
			_cast_armed(id)
			_note_input("hands" if id.begins_with("hand") else "controllers")
	if _tracing:
		var tip = _trace_tip(_trace_src)
		if tip == null:
			_cancel_trace()
			return
		var still := bool(_press_prev.get(_trace_src, false))
		if not still:
			_finish_trace()
			return
		var tp: Vector3 = tip
		if _trace_pts.is_empty() or (_trace_pts[_trace_pts.size() - 1] as Vector3).distance_to(tp) > 0.012:
			_trace_pts.append(tp)
			_redraw_trail()
			_trail_ember_at(tp)  # v0.11.0 ambient (a): lingering embers
			ArtKit.game_sfx(self, "trace", 1.0)


func _begin_trace(id: String) -> void:
	var tip = _trace_tip(id)
	if tip == null:
		return
	_tracing = true
	_trace_src = id
	_trace_pts = [tip]
	# Trace plane: faces the player, anchored at the trace start.
	var hp := _head_pos()
	var n: Vector3 = (hp - tip).normalized()
	_trace_plane = Plane(n, n.dot(tip))
	_trail.visible = true
	_redraw_trail()
	Haptics.tick("both")


func _cancel_trace() -> void:
	_tracing = false
	_trace_pts.clear()
	_trail.visible = false


func _redraw_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trace_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _trace_pts:
		_trail_mesh.surface_add_vertex(p)
	_trail_mesh.surface_end()


func _finish_trace() -> void:
	_tracing = false
	_trail.visible = false
	if _trace_pts.size() < 8:
		_trace_pts.clear()
		return
	# Project onto the trace plane -> 2D.
	var pts2d: Array = []
	var n := _trace_plane.normal
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var u := n.cross(up).normalized()
	var v := n.cross(u).normalized()
	var o: Vector3 = n * _trace_plane.d
	for p in _trace_pts:
		pts2d.append(Vector2((p - o).dot(u), (p - o).dot(v)))
	_trace_pts.clear()
	var rune := _match_rune(pts2d)
	if rune == "":
		_announce_text("UNRECOGNIZED — TRY AGAIN", 1.6)
		ArtKit.game_sfx(self, "clear")
		Haptics.deny("both")
		return
	_slots[_slot_idx] = rune
	_slot_idx += 1
	ArtKit.game_sfx(self, "forge")
	Haptics.confirm("both")
	if _slot_idx >= 3:
		_forge_spell()
	else:
		var names := ["SHAPE", "ELEMENT", "MODIFIER"]
		_announce_text("TRACE A RUNE: " + names[_slot_idx], 2.2)
	_refresh_orbs()


func _clear_slots() -> void:
	_slots = ["", "", ""]
	_slot_idx = 0
	_refresh_orbs()
	ArtKit.game_sfx(self, "clear")


func _forge_spell() -> void:
	var shape: String = _slots[0]
	var elem: String = _slots[1]
	var mod: String = _slots[2]
	var spell_name: String = str(ELEM_ADJ[elem]) + str(SHAPE_NOUN[shape]) + " " + str(MOD_SUFFIX[mod])
	_armed = {"name": spell_name, "shape": shape, "elem": elem, "mod": mod,
		"color": ELEM_COLOR[elem]}
	var first := not _spellbook.has(spell_name)
	_spellbook[spell_name] = int(_spellbook.get(spell_name, 0)) + 1
	_save_spellbook()
	if first:
		# v0.11.0 VFX: rune lock — igniting ring + element burst + glyph.
		VFX.rune_forge(self, _circle_center + Vector3(0, 0.1, 0),
			_armed.get("color", Color(0.5, 0.9, 1.0)), "✦")
		_announce_text("NEW SPELL DISCOVERED:\n" + spell_name, 4.0)
		ArtKit.game_sfx(self, "discover")
		ArtKit.stinger(self, "unlock")
		Haptics.play_sequence("fanfare", "both")
	else:
		_announce_text("FORGED: " + spell_name, 2.5)
		ArtKit.game_sfx(self, "forge")
	_telemetry("rune_forge", {"spell": spell_name, "new": first,
		"book_size": _spellbook.size()})
	_slots = ["", "", ""]
	_slot_idx = 0
	_refresh_orbs()
	_refresh_spell_label()


func _refresh_spell_label() -> void:
	if _armed.is_empty():
		_spell_label.text = "TRACE 3 RUNES TO FORGE"
	else:
		_spell_label.text = "ARMED: " + str(_armed["name"])


func _load_spellbook() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var names: Array = cfg.get_value("runewright", "spellbook", [])
		for n in names:
			_spellbook[str(n)] = 1


func _save_spellbook() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("runewright", "spellbook", _spellbook.keys())
	cfg.save(SAVE_PATH)


# -------------------------------------------------------------- casting ---

func _cast_armed(src: String) -> void:
	if _armed.is_empty():
		_announce_text("FORGE A SPELL FIRST", 1.5)
		return
	var tip = _trace_tip(src)
	if tip == null:
		return
	var shape: String = _armed["shape"]
	var elem: String = _armed["elem"]
	var mod: String = _armed["mod"]
	var col: Color = _armed["color"]
	var from: Vector3 = tip
	var dir := Vector3(0, -0.2, -1)
	var h := _head_pos()
	dir = (from - h).normalized()
	if dir.length() < 0.01:
		dir = Vector3(0, -0.2, -1)
	ArtKit.game_sfx(self, "cast", randf_range(0.9, 1.15))
	_cast_wind = 1.2  # v0.11.0 ambient (e): orbs flutter in the cast-wind
	Haptics.pulse(0.7, 0.1, "both")
	_telemetry("rune_cast", {"spell": str(_armed["name"])})
	match shape:
		"circle":  # Bolt: projectile(s)
			var n := 3 if mod == "circle" else 1
			for i in range(n):
				var spread := Vector3.ZERO
				if n > 1:
					spread = Vector3((i - 1) * 0.12, 0, 0)
				_fire_projectile(from, (dir + spread).normalized(), _spell_dmg(elem, mod), col, elem, mod)
		"line":  # Lance: instant beam
			_fire_lance(from, dir, _spell_dmg(elem, mod), col, elem, mod)
		"triangle":  # Nova: AoE at aim point
			var hit := _aim_point(from, dir)
			_fire_nova(hit, _spell_dmg(elem, mod), col, elem, mod)
		"zigzag":  # Chain: jumps between enemies
			_fire_chain(from, _spell_dmg(elem, mod), col, elem, mod)
		"square":  # Ward: shield bubble on the fort
			_raise_ward()


func _spell_dmg(elem: String, mod: String) -> float:
	var d := 12.0
	if elem == "square":  # Stone hits heavy
		d = 16.0
	if mod == "triangle":  # Ruin
		d *= 2.2
	if mod == "square":  # Mountain
		d *= 1.8
	return d


func _aim_point(from: Vector3, dir: Vector3) -> Vector3:
	var best := from + dir * 10.0
	var bd := 1e9
	for e in _enemies:
		var ep: Vector3 = (e["node"] as Node3D).global_position
		var to: Vector3 = ep - from
		var along := to.dot(dir)
		if along < 0.5 or along > 12.0:
			continue
		var perp := (to - dir * along).length()
		if perp < 0.8 and along < bd:
			bd = along
			best = ep
	if bd > 1e8:
		# Fall back to the floor point.
		if absf(dir.y) > 0.05:
			var t := (0.05 - from.y) / dir.y
			if t > 0.0 and t < 14.0:
				best = from + dir * t
	return best


func _fire_projectile(from: Vector3, dir: Vector3, dmg: float, col: Color, elem: String, mod: String) -> void:
	var p: MeshInstance3D
	if _proj_pool.is_empty():
		p = MeshInstance3D.new()
		var spm := SphereMesh.new()
		spm.radius = 0.05
		spm.height = 0.1
		p.mesh = spm
		get_tree().current_scene.add_child(p)
	else:
		p = _proj_pool.pop_back()
		p.visible = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.5
	p.material_override = mat
	var speed := 9.0 * (0.55 if mod == "square" else 1.0)
	_projectiles.append({"node": p, "vel": dir * speed, "dmg": dmg,
		"elem": elem, "mod": mod, "life": 4.0, "homing": mod == "zigzag"})
	p.global_position = from
	ArtKit.game_sfx(self, "cast", 1.2)


func _fire_lance(from: Vector3, dir: Vector3, dmg: float, col: Color, elem: String, mod: String) -> void:
	var end := from + dir * 12.0
	var best = null
	var bd := 1e9
	for e in _enemies:
		var ep: Vector3 = (e["node"] as Node3D).global_position
		var to: Vector3 = ep - from
		var along := to.dot(dir)
		if along < 0.5 or along > 12.0:
			continue
		if (to - dir * along).length() > 0.5:
			continue
		if along < bd:
			bd = along
			best = e
	if best != null:
		end = (best["node"] as Node3D).global_position
	_hit_enemy(best, dmg, elem, mod)
	_make_beam(from, end, col)


func _fire_nova(at: Vector3, dmg: float, col: Color, elem: String, mod: String) -> void:
	var radius := 1.3 * (1.5 if mod == "triangle" else 1.0) * (1.6 if mod == "square" else 1.0)
	_make_sphere_flash(at, radius, col)
	ArtKit.game_sfx(self, "boom", 0.9)
	Haptics.thump("both")
	for e in _enemies.duplicate():
		var ep: Vector3 = (e["node"] as Node3D).global_position
		if ep.distance_to(at) <= radius:
			_hit_enemy(e, dmg, elem, mod)


func _fire_chain(from: Vector3, dmg: float, col: Color, elem: String, _mod: String) -> void:
	var hit_set := {}
	var origin := from
	for jump in range(3):
		var best = null
		var bd := 2.2 if jump > 0 else 6.0
		for e in _enemies:
			if hit_set.has(e):
				continue
			var d: float = (e["node"] as Node3D).global_position.distance_to(origin)
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		_make_beam(origin, (best["node"] as Node3D).global_position, col)
		_hit_enemy(best, dmg * (1.0 - jump * 0.25), elem, "line")
		hit_set[best] = true
		origin = (best["node"] as Node3D).global_position


func _raise_ward() -> void:
	_ward_hp = 60.0
	_ward_node.visible = true
	ArtKit.game_sfx(self, "ward")
	_announce_text("WARD RAISED", 1.5)
	_telemetry("rune_ward", {})


func _make_beam(a: Vector3, b: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var d := b - a
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = maxf(d.length(), 0.01)
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = (a + b) * 0.5
	var y := d.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, z), mi.global_position)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.02, 1, 0.02), 0.22)
	tw.tween_callback(mi.queue_free)


func _make_sphere_flash(at: Vector3, radius: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.15, 0.3)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


# -------------------------------------------------------------- enemies ---

func _start_wave(n: int) -> void:
	_wave = n
	_wave_state = "fighting"
	_wave_t = 0.0
	_spawn_queue = _wave_comp(n)
	_spawn_acc = 0.5
	_announce_text("WAVE %d — DEFEND THE FORT" % n, 2.5)
	ArtKit.game_sfx(self, "wave")
	_telemetry("rune_wave", {"wave": n})


func _wave_comp(n: int) -> Array:
	var q: Array = []
	match n:
		1:
			q = ["slime", "slime", "slime", "slime"]
		2:
			q = ["slime", "slime", "slime", "skeleton", "skeleton", "bat"]
		3:
			q = ["skeleton", "skeleton", "skeleton", "bat", "bat", "slime", "slime", "slime"]
		4:
			q = ["bat", "bat", "bat", "skeleton", "skeleton", "slime", "slime", "dragon"]
		_:
			q = ["dragon", "skeleton", "skeleton", "skeleton", "bat", "bat", "slime", "slime", "slime", "slime"]
	q.shuffle()
	return q


func _spawn_edge_points() -> Array:
	var b := RoomKit.room_bounds()
	var c := Vector3(b.position.x + b.size.x * 0.5, 0, b.position.y + b.size.y * 0.5)
	var pts: Array = []
	for i in range(8):
		var a := TAU * i / 8.0
		pts.append(c + Vector3(cos(a) * b.size.x * 0.55, 0, sin(a) * b.size.y * 0.55))
	return pts


func _spawn_enemy(kind: String) -> void:
	var ps: PackedScene = load(MDIR + kind + ".glb") as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	var pts := _spawn_edge_points()
	var at: Vector3 = pts[randi() % pts.size()]
	var fly := kind == "bat"
	inst.position = at + Vector3(0, 1.3 if fly else 0.0, 0)
	var sc := 0.8
	var hp := 20.0
	var speed := 0.5
	var anim := "Walk"
	match kind:
		"slime":
			sc = 0.9
			hp = 22.0
			speed = 0.45
			anim = "Walk"
		"skeleton":
			sc = 0.85
			hp = 14.0
			speed = 0.8
			anim = "Running"
		"bat":
			sc = 0.8
			hp = 12.0
			speed = 0.9
			anim = "Flying"
		"dragon":
			sc = 1.15
			hp = 130.0
			speed = 0.35
			anim = "Flying"
	inst.scale = Vector3.ONE * sc
	get_tree().current_scene.add_child(inst)
	_play_anim(inst, anim)
	_enemies.append({"node": inst, "kind": kind, "hp": hp, "max_hp": hp,
		"speed": speed, "slow_t": 0.0, "dot_t": 0.0, "atk_cd": 0.0, "fly": fly})


func _play_anim(node: Node, want: String) -> void:
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		for a in p.get_animation_list():
			if str(a).to_lower().contains(want.to_lower()):
				p.play(a)
				return


func _hit_enemy(e: Dictionary, dmg: float, elem: String, mod: String) -> void:
	if e == null or e.is_empty():
		return
	e["hp"] = float(e["hp"]) - dmg
	# Element riders.
	match elem:
		"circle":  # Fire: damage over time
			e["dot_t"] = 3.0
		"triangle":  # Frost: slow
			e["slow_t"] = 4.0
		"zigzag":  # Wind: knockback
			var node: Node3D = e["node"]
			var away: Vector3 = node.global_position - _head_pos()
			away.y = 0
			node.global_position += away.normalized() * 0.5
		"line":  # Lightning: arc to one nearby enemy
			_arc_lightning(e, dmg * 0.5)
		"square":  # Stone: small splash
			_stone_splash(e, dmg * 0.4)
	if mod == "line":  # Piercing handled at fire time; bonus tick here
		e["hp"] = float(e["hp"]) - dmg * 0.25
	ArtKit.game_sfx(self, "hit", randf_range(0.9, 1.2))
	if float(e["hp"]) <= 0.0:
		_kill_enemy(e)


func _arc_lightning(from_e: Dictionary, dmg: float) -> void:
	var fp: Vector3 = (from_e["node"] as Node3D).global_position
	var best = null
	var bd := 2.0
	for e in _enemies:
		if e == from_e:
			continue
		var d: float = (e["node"] as Node3D).global_position.distance_to(fp)
		if d < bd:
			bd = d
			best = e
	if best != null:
		_make_beam(fp, (best["node"] as Node3D).global_position, Color(0.6, 0.85, 1.0))
		best["hp"] = float(best["hp"]) - dmg
		if float(best["hp"]) <= 0.0:
			_kill_enemy(best)


func _stone_splash(center_e: Dictionary, dmg: float) -> void:
	var cp: Vector3 = (center_e["node"] as Node3D).global_position
	for e in _enemies.duplicate():
		if e == center_e:
			continue
		if (e["node"] as Node3D).global_position.distance_to(cp) < 0.7:
			e["hp"] = float(e["hp"]) - dmg
			if float(e["hp"]) <= 0.0:
				_kill_enemy(e)


func _kill_enemy(e: Dictionary) -> void:
	var node: Node3D = e["node"]
	_score += 25 if str(e["kind"]) != "dragon" else 250
	_play_anim(node, "Death")
	ArtKit.game_sfx(self, "die", randf_range(0.85, 1.1))
	_enemies.erase(e)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.5).set_delay(0.4)
	tw.tween_callback(node.queue_free)


func _update_enemies(delta: float) -> void:
	for e in _enemies.duplicate():
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			_enemies.erase(e)
			continue
		# DoT / slow timers.
		if float(e["dot_t"]) > 0.0:
			e["dot_t"] = float(e["dot_t"]) - delta
			e["hp"] = float(e["hp"]) - delta * 4.0
			if float(e["hp"]) <= 0.0:
				_kill_enemy(e)
				continue
		var speed: float = float(e["speed"]) * (0.5 if float(e["slow_t"]) > 0.0 else 1.0)
		if float(e["slow_t"]) > 0.0:
			e["slow_t"] = float(e["slow_t"]) - delta
		var tgt := _fort_pos
		var to: Vector3 = tgt - node.position
		var flat := Vector3(to.x, 0, to.z)
		var dist := flat.length()
		if dist > 0.75:
			var step: Vector3 = flat.normalized() * speed * delta
			# Sine weave so paths feel alive.
			var t := Time.get_ticks_msec() / 1000.0
			var side := Vector3(-flat.z, 0, flat.x).normalized() * sin(t * 2.0 + float(e["atk_cd"])) * 0.15 * delta
			node.position += step + side
			node.position.y = lerpf(node.position.y, 1.3 if bool(e["fly"]) else 0.0, delta * 3.0)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(flat.x, flat.z), 0.1)
		else:
			# Attack the fort (or the ward first).
			e["atk_cd"] = float(e["atk_cd"]) - delta
			if float(e["atk_cd"]) <= 0.0:
				e["atk_cd"] = 1.2
				_play_anim(node, "Attack")
				if _ward_hp > 0.0:
					_ward_hp -= 8.0
					if _ward_hp <= 0.0:
						_ward_node.visible = false
						_announce_text("WARD BROKEN", 1.5)
				else:
					_fort_hp -= 6.0
					Haptics.thump("both")
					ArtKit.game_sfx(self, "hit", 0.7)
					if _fort_hp <= 0.0:
						_fort_hp = 0.0
						_defeat("The fort has fallen.")
						return


func _update_projectiles(delta: float) -> void:
	for p in _projectiles.duplicate():
		var node: MeshInstance3D = p["node"]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_recycle_proj(p)
			continue
		var vel: Vector3 = p["vel"]
		if bool(p["homing"]):
			var best = null
			var bd := 4.0
			for e in _enemies:
				var d: float = (e["node"] as Node3D).global_position.distance_to(node.global_position)
				if d < bd:
					bd = d
					best = e
			if best != null:
				var want: Vector3 = ((best["node"] as Node3D).global_position - node.global_position).normalized() * vel.length()
				vel = vel.lerp(want, delta * 6.0)
				p["vel"] = vel
		node.global_position += vel * delta
		var hit_something := false
		for e in _enemies.duplicate():
			var ep: Vector3 = (e["node"] as Node3D).global_position
			if ep.distance_to(node.global_position) < 0.32:
				_hit_enemy(e, float(p["dmg"]), str(p["elem"]), str(p["mod"]))
				hit_something = true
				if str(p["mod"]) != "line":  # Piercing passes through
					break
		if hit_something and str(p["mod"]) != "line":
			_recycle_proj(p)


func _recycle_proj(p: Dictionary) -> void:
	(p["node"] as MeshInstance3D).visible = false
	_proj_pool.append(p["node"])
	_projectiles.erase(p)


# ---------------------------------------------------------------- loop ---

## v0.11.0 (Animator): ember fade + ward breathe + spellbook flutter.
func _update_rune_ambient(delta: float, t: float) -> void:
	# (a) Trail embers fade out over 1.4s.
	for e in _trail_embers:
		var life: float = float(e["life"])
		if life <= 0.0:
			continue
		life -= delta
		e["life"] = life
		var qn: MeshInstance3D = e["node"]
		if life <= 0.0:
			qn.visible = false
			continue
		qn.position.y += 0.06 * delta
		(e["mat"] as StandardMaterial3D).albedo_color.a = clampf(life / 1.4, 0.0, 1.0)
	# (b) Ward totems breathe (emissive pulse, phase-offset).
	for w in _ward_mats:
		AnimFluidity.emissive_flicker(w["mat"], t, float(w["phase"]), 1.6, 0.5, 1.6)
	# (e) Rune orbs flutter in the cast-wind (the spellbook's visible page).
	if _cast_wind > 0.0:
		_cast_wind -= delta
		for i in _orbs.size():
			var orb: MeshInstance3D = _orbs[i]
			if is_instance_valid(orb):
				orb.rotation.z = sin(t * 14.0 + float(i) * 2.1) * 0.18 * _cast_wind
				orb.position.y += sin(t * 17.0 + float(i) * 1.3) * 0.02 * delta * _cast_wind


func _process(delta: float) -> void:
	if _game_over:
		return
	_update_rune_ambient(delta, Time.get_ticks_msec() / 1000.0)
	_poll_trace()
	if _announce_t > 0.0:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce.text = ""
	match _wave_state:
		"forge":
			pass  # trace runes at the circle; start the wave when armed
		"fighting":
			_wave_t += delta
			if not _spawn_queue.is_empty():
				_spawn_acc -= delta
				if _spawn_acc <= 0.0 and _enemies.size() < 14:
					_spawn_acc = 1.4
					_spawn_enemy(_spawn_queue.pop_back())
			_update_enemies(delta)
			_update_projectiles(delta)
			if _spawn_queue.is_empty() and _enemies.is_empty():
				if _wave >= MAX_WAVE:
					_victory()
				else:
					_wave_state = "refine"
					_wave_t = 0.0
					_announce_text("WAVE CLEARED — REFINE YOUR SPELLBOOK", 3.5)
					ArtKit.game_sfx(self, "win", 1.2)
		"refine":
			_wave_t += delta
			if _wave_t > 14.0:
				_start_wave(_wave + 1)
	_update_hud()
	_update_fort_fx(delta)


func _update_fort_fx(delta: float) -> void:
	_fort_ring.rotation.y += delta * 0.6
	var frac := _fort_hp / FORT_HP
	var mat := _fort_ring.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(lerpf(1.0, 0.4, frac), lerpf(0.25, 0.8, frac), 1.0)


func _update_hud() -> void:
	var hp := _head_pos()
	_hud.position = hp + Vector3(0, 0.5, -0.85)
	_spell_label.position = _circle_center + Vector3(0, 0.42, 0)
	_announce.position = hp + Vector3(0, 0.95, -1.5)
	var state_txt := ""
	match _wave_state:
		"forge":
			state_txt = "TRACE 3 RUNES — THEN TAP TRIGGER TO BEGIN" if _armed.is_empty() else "TAP TRIGGER TO START WAVE 1"
		"fighting":
			state_txt = "WAVE %d/5 — ENEMIES %d" % [_wave, _enemies.size() + _spawn_queue.size()]
		"refine":
			state_txt = "REFINE — NEXT WAVE IN %ds" % int(14.0 - _wave_t)
	_hud.text = "FORT %d%%   SCORE %d\n%s" % [int(_fort_hp), _score, state_txt]
	_refresh_spell_label()


func _try_begin_wave() -> void:
	# Tapping trigger while armed during forge/refine starts the next wave.
	if _wave_state == "forge" and not _armed.is_empty():
		_start_wave(1)
	elif _wave_state == "refine":
		_start_wave(_wave + 1)


func _victory() -> void:
	_wave_state = "done"
	_game_over = true
	_score += int(_fort_hp) * 10
	_announce_text("THE FORT STANDS! SCORE %d" % _score, 8.0)
	ArtKit.game_sfx(self, "win")
	ArtKit.stinger(self, "success")
	Haptics.play_sequence("fanfare", "both")
	_telemetry("rune_end", {"result": "victory", "score": _score, "book_size": _spellbook.size()})


func _defeat(reason: String) -> void:
	if _game_over:
		return
	_game_over = true
	_announce_text("OVERRUN — " + reason, 8.0)
	ArtKit.game_sfx(self, "lose")
	ArtKit.stinger(self, "fail")
	_telemetry("rune_end", {"result": "defeat", "reason": reason, "wave": _wave})


func _announce_text(t: String, dur: float) -> void:
	_announce.text = t
	_announce_t = dur



func _note_input(method: String) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.note_input_method(method)


func _telemetry(ev: String, fields: Dictionary) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event(ev, fields)
