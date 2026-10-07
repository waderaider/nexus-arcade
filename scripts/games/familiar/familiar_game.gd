## FamiliarGame.gd - boots the Familiar scene: creature + brain, toy ball,
## gesture sensor, and a small HUD (name / mood / bond bar).
## Ports FamiliarBootstrap.cs. The scene file is scenes/familiar/familiar.tscn.
extends Node3D
class_name FamiliarGame

var brain: CreatureBrain
var body: CreatureBody
var toy: ToyBall
var gestures: GestureSensor

var _hud_root: Node3D
var _name_label: Label3D
var _mood_label: Label3D
var _bond_fill: MeshInstance3D
var _bond_back: MeshInstance3D
var _creature: Node3D
var _anchor_timer := 0.0
# v0.7.0 ROOMKIT: cached room layout (never queried per-frame).
var _room_walls: Array = []
var _room_tables: Array = []
var _room_furniture: Array = []
var _room_bounds: Rect2 = Rect2(-2, -2, 4, 4)
var _has_room := false
var _sit_timer := 40.0
# RoomKit (v0.7.0): couch peek-a-boo state.
var _hide_timer := 55.0
var _peek_timer := 0.0
var _hiding := false

const PET_NAME := "Mochi"
const STAGE_NAMES := ["Egg", "Sprout", "Wisp", "Guardian"]
const STATE_NAMES := ["idle", "curious", "playful", "sleepy"]

func _ready() -> void:
	_add_polish_light_rig()
	var spawn := _resolve_spawn()

	var creature := Node3D.new()
	creature.name = "FamiliarCreature"
	creature.position = spawn
	add_child(creature)
	_creature = creature
	body = CreatureBody.new()
	creature.add_child(body)
	brain = CreatureBrain.new()
	creature.add_child(brain)

	toy = ToyBall.new()
	toy.name = "ToyBall"
	add_child(toy)
	toy.add_child(GraphicsPolish.make_trail(Color(1.0, 0.6, 0.9), 0.03))

	gestures = GestureSensor.new()
	gestures.name = "GestureSensor"
	add_child(gestures)

	# Wire everything up (brain.setup connects the gesture signal).
	brain.setup(body, toy, gestures)
	gestures.pet_target = body.head_anchor
	gestures.creature_root = creature

	_build_hud(spawn)
	GraphicsPolish.spawn_ambient_motes(self, spawn + Vector3(0, 0.6, 0), 1.5, 30)
	ARUpgradeKit.apply_anchor(creature, "familiar_main")
	_apply_room_layout()
	_build_pet_corner(spawn) # v0.7.0 KayKit set dressing (null-safe)


# ---------------------------------------------------------------- room layout

func _apply_room_layout() -> void:
	if not RoomKit.is_available():
		return # intentional fallback: default behavior unchanged
	await RoomKit.refresh()
	if not RoomKit.has_room_data():
		return
	_room_walls = RoomKit.get_walls()
	_room_tables = RoomKit.get_tables()
	_room_furniture = RoomKit.get_furniture()
	_room_bounds = RoomKit.room_bounds()
	# MORPH-B (v0.7.0): bed -> cloud nest where the familiar rests
	_morph_anchors("BED", "nature", 1)
	_has_room = true


## ROOMKIT: keep Mochi on the real floor - clamped inside the room bounds
## and pushed away from real wall planes.
func _clamp_to_room(p: Vector3) -> Vector3:
	var safe := _room_bounds.grow(-0.2)
	p.x = clampf(p.x, safe.position.x, safe.position.x + safe.size.x)
	p.z = clampf(p.z, safe.position.y, safe.position.y + safe.size.y)
	p.y = maxf(p.y, 0.02)
	for w_v in _room_walls:
		var w: Dictionary = w_v
		var n: Vector3 = w["normal"]
		var d: float = (p - w["position"]).dot(n)
		if absf(d) < 0.35:
			var s := signf(d)
			p += n * (s if s != 0.0 else 1.0) * (0.35 - absf(d))
	return p


## ROOMKIT: a cozy sit spot on top of the largest piece of furniture.
func _sit_spot() -> Vector3:
	var best := {}
	var best_area := 0.0
	for f_v in _room_furniture:
		var f: Dictionary = f_v
		var s: Vector3 = f["size"]
		if s.x * s.z > best_area:
			best_area = s.x * s.z
			best = f
	if best.is_empty():
		return Vector3.ZERO
	var fp: Vector3 = best["position"]
	var fs: Vector3 = best["size"]
	return Vector3(fp.x, fp.y + fs.y * 0.5 + 0.02, fp.z)


## ROOMKIT (v0.7.0): floor spot behind the real couch (far side from room
## center), or Vector3.INF when there is no couch.
func _couch_hide_spot() -> Vector3:
	var couch := RoomKit.get_couch()
	if couch.is_empty():
		return Vector3.INF
	var cp: Vector3 = couch["position"]
	var cs: Vector3 = couch["size"]
	var rc := _room_bounds.get_center()
	var away := Vector2(cp.x - rc.x, cp.z - rc.y)
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var clearance := maxf(cs.x, cs.z) * 0.5 + 0.45
	return _clamp_to_room(Vector3(cp.x + away.x * clearance, 0.02, cp.z + away.y * clearance))


## ROOMKIT (v0.7.0): pop-out spot in front of the couch (room-center side).
func _couch_peek_spot() -> Vector3:
	var couch := RoomKit.get_couch()
	if couch.is_empty():
		return _clamp_to_room(Vector3(0.0, 0.02, 0.0))
	var cp: Vector3 = couch["position"]
	var cs: Vector3 = couch["size"]
	var rc := _room_bounds.get_center()
	var toward := Vector2(rc.x - cp.x, rc.y - cp.z)
	if toward.length() < 0.05:
		toward = Vector2(-1.0, 0.0)
	toward = toward.normalized()
	var clearance := maxf(cs.x, cs.z) * 0.5 + 0.6
	return _clamp_to_room(Vector3(cp.x + toward.x * clearance, 0.02, cp.z + toward.y * clearance))

func _add_polish_light_rig() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


## v0.7.0 KayKit set dressing: Mochi's pet corner near the spawn point -
## a stool, a food dish, and a toy chest. Guarded - null spawns are
## skipped, never crash.
func _build_pet_corner(spawn: Vector3) -> void:
	var dir := "res://assets/models/familiar/"
	ModelLib.spawn(dir + "stool.glb", self, spawn + Vector3(0.90, 0.0, 0.40))
	ModelLib.spawn(dir + "chest.glb", self, spawn + Vector3(-0.90, 0.0, 0.60))
	ModelLib.spawn(dir + "plate_small.glb", self, spawn + Vector3(0.90, 0.02, 1.10))

func _resolve_spawn() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = Vector3(0, 0, -1)
		fwd = fwd.normalized()
		var pos := cam.global_position + fwd * 1.2
		pos.y = maxf(0.02, pos.y - 0.9)
		return ARUpgradeKit.clamp_to_room(pos)
	return ARUpgradeKit.clamp_to_room(Vector3(0, 0.02, 1.2))

func _make_label(text: String, font_size: int) -> Label3D:
	var l := GraphicsPolish.make_label(text, font_size)
	l.no_depth_test = true
	return l

func _make_bar(color: Color, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = GraphicsPolish.glow(color, 1.2)
	return mi

func _build_hud(spawn: Vector3) -> void:
	_hud_root = Node3D.new()
	_hud_root.name = "FamiliarHUD"
	_hud_root.position = spawn + Vector3(0, 0.75, 0)
	add_child(_hud_root)

	_name_label = _make_label(PET_NAME, 96)
	_name_label.position = Vector3(0, 0.12, 0)
	_hud_root.add_child(_name_label)

	_mood_label = _make_label("curious", 64)
	_hud_root.add_child(_mood_label)

	_bond_back = _make_bar(Color(0.1, 0.1, 0.12), Vector3(0.4, 0.03, 0.01))
	_bond_back.position = Vector3(0, -0.12, 0)
	_hud_root.add_child(_bond_back)

	_bond_fill = _make_bar(Color(1.0, 0.45, 0.75), Vector3(0.001, 0.032, 0.012))
	_bond_fill.position = Vector3(0, -0.12, 0)
	_hud_root.add_child(_bond_fill)

func _process(_delta: float) -> void:
	# Persist the creature anchor every 30s so Mochi stays put between sessions.
	_anchor_timer += _delta
	if _anchor_timer >= 30.0:
		_anchor_timer = 0.0
		if is_instance_valid(_creature):
			ARUpgradeKit.save_anchor("familiar_main", _creature.global_transform)
	# XR hand interaction: right-hand pinch pets the creature
	# (mouse/touch gestures still work through the GestureSensor).
	if ARUpgradeKit.is_xr_active() and ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		if gestures != null:
			gestures.gesture.emit("pet")
	if not _hud_root or not brain:
		return
	# ROOMKIT: Mochi walks the real floor - clamp into the room every frame.
	if _has_room and is_instance_valid(_creature):
		_creature.position = _clamp_to_room(_creature.position)
		# ROOMKIT: every so often, hop up and sit on the furniture.
		_sit_timer -= _delta
		if _sit_timer <= 0.0:
			_sit_timer = 75.0
			if not _room_furniture.is_empty() and brain.state == 0: # IDLE
				body.hop_to(_sit_spot())
		# ROOMKIT (v0.7.0): couch peek-a-boo — hide behind the real couch,
		# then pop back out with a happy dance.
		if not _hiding:
			_hide_timer -= _delta
			if _hide_timer <= 0.0:
				_hide_timer = 90.0
				var hide := _couch_hide_spot()
				if hide != Vector3.INF and brain.state == 0: # IDLE
					_hiding = true
					_peek_timer = 4.0
					body.hop_to(hide)
		else:
			_peek_timer -= _delta
			if _peek_timer <= 0.0:
				_hiding = false
				body.hop_to(_couch_peek_spot())
				body.dance()
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Face the whole HUD toward the camera (labels billboard themselves).
		var to_cam: Vector3 = cam.global_position - _hud_root.global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.01:
			_hud_root.rotation.y = atan2(-to_cam.x, -to_cam.z) + PI
	var stage_name: String = STAGE_NAMES[clampi(brain.evo_stage, 0, 3)]
	var state_name: String = STATE_NAMES[clampi(brain.state, 0, 3)]
	_mood_label.text = "%s  ·  %s" % [state_name, stage_name]
	var frac := clampf(brain.bond_xp / brain.next_threshold(), 0.0, 1.0)
	_bond_fill.scale.x = maxf(0.001, frac)
	_bond_fill.position.x = -0.2 + 0.2 * frac
## MORPH-B (v0.7.0): morph up to `count` furniture anchors of a semantic
## label with a MorphSkins theme skin. RoomKit parents the skin node into
## the scene itself; missing anchors are a silent no-op (fallback untouched).
func _morph_anchors(label: String, skin: String, count: int = 1) -> void:
	var anchors: Array = RoomKit.get_anchors(label)
	var n := mini(count, anchors.size())
	for i in n:
		RoomKit.morph(anchors[i], skin)
