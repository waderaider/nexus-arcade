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

func _add_polish_light_rig() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)

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
