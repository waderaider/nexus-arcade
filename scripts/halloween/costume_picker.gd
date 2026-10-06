## CostumePicker - Halloween costume picker for NEXUS ARCADE.
## Instances the Halloween avatar plus a 3D grid of 30 costume cards in two
## rows. Pinch (ARUpgradeKit.pinch_just_pressed) with the pointer ray, or a
## mouse click, selects the nearest card within threshold. Selecting swaps the
## costume on the avatar's anchor marker, plays a confetti poof + tone, and
## persists the costume id to user://nexus_costume.cfg. Restores the saved
## costume on _ready. Anchor save/restore via "halloween_picker".
## Headless-safe: guards camera access, no XR hardware required.
extends Node3D

const AVATAR_SCENE := "res://scenes/halloween/avatar.tscn"
const COSTUME_BUILDERS := preload("res://scripts/halloween/costume_builders.gd")
const COSTUME_FILE := "user://nexus_costume.cfg"
const ANCHOR_NAME := "halloween_picker"
const ANCHOR_INTERVAL := 30.0
const COLS := 15
const CARD_SPACING := 0.34
const SELECT_THRESHOLD := 0.22

var avatar: Node3D = null
var costume_node: Node3D = null
var current_id := ""
var cards: Array = [] # dicts: center (Vector3, local), id, name, node
var _anchor_timer := 0.0
var _tone_player: AudioStreamPlayer = null


func _ready() -> void:
	GraphicsPolish.make_light_rig(self)
	_ensure_fallback_camera()
	_spawn_avatar()
	_build_cards()
	_build_signage()
	_tone_player = _make_player(_make_tone(660.0, 0.16, 0.5))
	ARUpgradeKit.apply_anchor(self, ANCHOR_NAME)
	_restore_costume()


func _process(delta: float) -> void:
	_anchor_timer += delta
	if _anchor_timer >= ANCHOR_INTERVAL:
		_anchor_timer = 0.0
		ARUpgradeKit.save_anchor(ANCHOR_NAME, global_transform)
	if ARUpgradeKit.pinch_just_pressed(self):
		var ray: Array = ARUpgradeKit.pointer_ray(self)
		_select_by_ray(ray[0], ray[1])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var cam := get_viewport().get_camera_3d()
			if cam == null:
				return
			_select_by_ray(cam.project_ray_origin(mb.position), cam.project_ray_normal(mb.position))


# ------------------------------------------------------------------ build ---

func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		return
	var cam := Camera3D.new()
	cam.name = "PickerFallbackCamera"
	cam.position = Vector3(0.0, 1.6, 3.2)
	cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	add_child(cam)


func _spawn_avatar() -> void:
	var scene := load(AVATAR_SCENE) as PackedScene
	if scene == null:
		return
	avatar = scene.instantiate() as Node3D
	avatar.position = Vector3(0.0, 0.0, -0.9)
	add_child(avatar)


func _build_cards() -> void:
	var costumes: Array = COSTUME_BUILDERS.all_costumes()
	var pedestal_mat := GraphicsPolish.pbr_preset(Color(0.16, 0.14, 0.22), "plastic")
	var glow_mat := GraphicsPolish.glow(Color(1.0, 0.55, 0.15), 1.2)
	for i in range(costumes.size()):
		var c: Dictionary = costumes[i]
		var row := i / COLS
		var col := i % COLS
		var center := Vector3((float(col) - float(COLS - 1) / 2.0) * CARD_SPACING, 0.62, 0.10 + float(row) * 0.46)
		var card := Node3D.new()
		card.name = "Card_" + String(c["id"])
		card.position = center
		add_child(card)
		# Pedestal + glowing rim.
		var ped := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.30, 0.05, 0.20)
		ped.mesh = pb
		ped.material_override = pedestal_mat
		card.add_child(ped)
		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.31, 0.015, 0.21)
		rim.mesh = rb
		rim.material_override = glow_mat
		rim.position = Vector3(0, 0.032, 0)
		card.add_child(rim)
		# Name label floating above.
		var label := GraphicsPolish.make_label(String(c["name"]), 40)
		label.position = Vector3(0, 0.17, 0)
		card.add_child(label)
		cards.append({"center": center, "id": String(c["id"]), "name": String(c["name"]), "node": card})


func _build_signage() -> void:
	var title := GraphicsPolish.make_label("COSTUME PICKER", 96, Color(1.0, 0.65, 0.20))
	title.position = Vector3(0.0, 2.35, -0.9)
	add_child(title)
	var hint := GraphicsPolish.make_label("Pinch or click a card to dress the avatar", 48, Color(0.9, 0.9, 1.0))
	hint.position = Vector3(0.0, 2.05, -0.9)
	add_child(hint)


# --------------------------------------------------------------- selection ---

func _select_by_ray(origin: Vector3, dir: Vector3) -> void:
	var best_id := ""
	var best_dist := SELECT_THRESHOLD
	for c in cards:
		var world: Vector3 = global_transform * (c["center"] as Vector3)
		var t := (world - origin).dot(dir)
		if t <= 0.0:
			continue
		var closest := origin + dir * t
		var d := (world - closest).length()
		if d < best_dist:
			best_dist = d
			best_id = String(c["id"])
	if best_id != "" and best_id != current_id:
		_apply_costume(best_id, true)


func _apply_costume(costume_id: String, celebrate: bool) -> void:
	if avatar == null:
		return
	var entry := _find_costume(costume_id)
	if entry.is_empty():
		return
	if costume_node != null and is_instance_valid(costume_node):
		costume_node.queue_free()
		costume_node = null
	var marker := avatar.get_node_or_null(String(entry["anchor"]))
	if marker == null:
		return
	costume_node = (entry["build"] as Callable).call() as Node3D
	marker.add_child(costume_node)
	current_id = costume_id
	_save_costume(costume_id)
	if celebrate:
		GraphicsPolish.spawn_confetti(self, avatar.global_position + Vector3(0.0, 1.2, 0.0), 50)
		if _tone_player != null:
			_tone_player.play()


func _find_costume(costume_id: String) -> Dictionary:
	for c in COSTUME_BUILDERS.all_costumes():
		if String(c["id"]) == costume_id:
			return c
	return {}


# ------------------------------------------------------------- persistence ---

func _save_costume(costume_id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(COSTUME_FILE) # ignore errors; missing file is fine
	cfg.set_value("costume", "id", costume_id)
	cfg.save(COSTUME_FILE)


func _restore_costume() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(COSTUME_FILE) != OK:
		return
	var saved := String(cfg.get_value("costume", "id", ""))
	if saved != "":
		_apply_costume(saved, false)


# ------------------------------------------------------------------- audio ---

func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (selection chime).
func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames_count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(frames_count * 2)
	for i in range(frames_count):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(frames_count)
		var s := sin(TAU * freq * t) * env * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
