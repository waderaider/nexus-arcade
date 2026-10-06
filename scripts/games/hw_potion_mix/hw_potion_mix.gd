## HwPotionMix - "Potion Mix": a witch's brewing table.
## Three bubbling cauldrons each show a 3-ingredient recipe as colored
## dots. Pick an ingredient vial (click, or pinch in XR), then pick a
## cauldron to pour. Pour in the shown order: a correct pour scores
## progress, a wrong one resets that cauldron. 30 points per finished
## potion. 75-second rounds with score + restart.
extends Node3D

const ROUND_TIME := 75.0
const TABLE_POS := Vector3(0.0, 0.0, -1.1)
const ST_PLAY := 0
const ST_OVER := 1

const INGREDIENTS := [
	Color(1.0, 0.20, 0.20), # 0 ember red
	Color(0.20, 1.0, 0.30), # 1 venom green
	Color(0.30, 0.50, 1.0), # 2 moon blue
	Color(0.70, 0.30, 1.0), # 3 shadow purple
	Color(1.0, 0.85, 0.20), # 4 sun yellow
]
const ING_NAMES := ["Ember", "Venom", "Moon", "Shadow", "Sun"]

var camera: Camera3D = null
var state := ST_PLAY
var time_left := ROUND_TIME
var score := 0
var brewed := 0
var elapsed := 0.0
var bubble_timer := 0.0
var pots: Array = [] # dicts: node, liquid_mat, recipe(Array), progress, dots(Array of MeshInstance3D), base_x
var vials: Array = [] # dicts: node, liquid_mat, index
var selected_vial := -1
var sel_ring: MeshInstance3D = null
var hud_label: Label3D = null
var msg_label: Label3D = null
var msg_timer := 0.0
var anchor_timer := 0.0
var pinch_hold := 0.0
var pour_player: AudioStreamPlayer = null
var fizz_player: AudioStreamPlayer = null
var brew_player: AudioStreamPlayer = null
var end_player: AudioStreamPlayer = null
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_add_light_rig()
	_ensure_fallback_camera()
	_build_table()
	_build_pots()
	_build_vials()
	_build_sel_ring()
	_build_hud()
	ARUpgradeKit.apply_anchor(self, "hw_potion_mix_main")
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.2, -1.1), 1.8, 30)
	pour_player = _make_player(_make_tone(500.0, 0.12, 0.5))
	fizz_player = _make_player(_make_tone(160.0, 0.25, 0.55))
	brew_player = _make_player(_make_tone(840.0, 0.35, 0.55))
	end_player = _make_player(_make_tone(660.0, 0.5, 0.5))


func _add_light_rig() -> void:
	for child in get_children():
		if child is DirectionalLight3D:
			return
	GraphicsPolish.make_light_rig(self)


func _ensure_fallback_camera() -> void:
	if get_viewport().get_camera_3d() != null:
		camera = get_viewport().get_camera_3d()
		return
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.8, 1.2)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.75, -1.1), Vector3.UP)
	camera.current = true


func _build_table() -> void:
	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(2.4, 0.08, 1.0)
	top.mesh = top_box
	top.position = TABLE_POS + Vector3(0.0, 0.72, 0.0)
	top.material_override = GraphicsPolish.pbr(Color(0.35, 0.20, 0.10), 0.05, 0.7)
	add_child(top)
	var leg_mat := GraphicsPolish.pbr(Color(0.25, 0.14, 0.07), 0.05, 0.8)
	for lx in [-1.1, 1.1]:
		for lz in [-0.42, 0.42]:
			var leg := MeshInstance3D.new()
			var leg_box := BoxMesh.new()
			leg_box.size = Vector3(0.08, 0.72, 0.08)
			leg.mesh = leg_box
			leg.position = TABLE_POS + Vector3(lx, 0.36, lz)
			leg.material_override = leg_mat
			add_child(leg)


func _build_pots() -> void:
	for i in range(3):
		var x := -0.75 + float(i) * 0.75
		var root := Node3D.new()
		root.position = TABLE_POS + Vector3(x, 0.76, -0.15)
		add_child(root)
		# Iron pot body.
		var pot := MeshInstance3D.new()
		var pot_mesh := SphereMesh.new()
		pot_mesh.radius = 0.22
		pot_mesh.height = 0.44
		pot.mesh = pot_mesh
		pot.scale = Vector3(1.0, 0.8, 1.0)
		pot.position = Vector3(0.0, 0.16, 0.0)
		pot.material_override = GraphicsPolish.pbr(Color(0.08, 0.08, 0.10), 0.6, 0.45)
		root.add_child(pot)
		# Rim.
		var rim := MeshInstance3D.new()
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.17
		rim_mesh.outer_radius = 0.22
		rim.mesh = rim_mesh
		rim.rotation.x = PI * 0.5
		rim.position = Vector3(0.0, 0.30, 0.0)
		rim.material_override = GraphicsPolish.pbr(Color(0.12, 0.12, 0.14), 0.7, 0.4)
		root.add_child(rim)
		# Bubbling liquid surface.
		var liquid := MeshInstance3D.new()
		var liquid_mesh := CylinderMesh.new()
		liquid_mesh.top_radius = 0.16
		liquid_mesh.bottom_radius = 0.16
		liquid_mesh.height = 0.03
		liquid.mesh = liquid_mesh
		liquid.position = Vector3(0.0, 0.30, 0.0)
		var liquid_mat := GraphicsPolish.glow(Color(0.2, 0.9, 0.3), 1.6)
		liquid.material_override = liquid_mat
		root.add_child(liquid)
		# Fire glow beneath the pot.
		GraphicsPolish.make_point_light(root, Vector3(0.0, 0.05, 0.0), Color(1.0, 0.45, 0.1), 0.7, 1.6)
		# Steam wisps.
		GraphicsPolish.spawn_ambient_motes(root, Vector3(0.0, 0.55, 0.0), 0.14, 10)
		# Recipe dots floating above the pot.
		var dots: Array = []
		for d in range(3):
			var dot := MeshInstance3D.new()
			var dot_mesh := SphereMesh.new()
			dot_mesh.radius = 0.045
			dot_mesh.height = 0.09
			dot.mesh = dot_mesh
			dot.position = Vector3(-0.12 + float(d) * 0.12, 0.62, 0.0)
			dot.material_override = GraphicsPolish.glow(Color(0.5, 0.5, 0.5), 1.4)
			root.add_child(dot)
			dots.append(dot)
		var pot_dict := {
			"node": root, "liquid_mat": liquid_mat, "recipe": [],
			"progress": 0, "dots": dots,
		}
		pots.append(pot_dict)
		_new_recipe(pot_dict)


func _new_recipe(pot: Dictionary) -> void:
	var recipe: Array = []
	for i in range(3):
		recipe.append(rng.randi_range(0, INGREDIENTS.size() - 1))
	pot["recipe"] = recipe
	pot["progress"] = 0
	_refresh_dots(pot)
	# Reset the liquid to a neutral brew color.
	var lm: StandardMaterial3D = pot["liquid_mat"]
	lm.albedo_color = Color(0.2, 0.9, 0.3)
	lm.emission = Color(0.2, 0.9, 0.3)


func _refresh_dots(pot: Dictionary) -> void:
	var recipe: Array = pot["recipe"]
	var progress := int(pot["progress"])
	var dots: Array = pot["dots"]
	for i in range(dots.size()):
		var dot: MeshInstance3D = dots[i]
		var col: Color = INGREDIENTS[int(recipe[i])]
		if i < progress:
			# Done step: small and dim.
			dot.scale = Vector3(0.6, 0.6, 0.6)
			dot.material_override = GraphicsPolish.glow(col.darkened(0.55), 0.6)
		else:
			dot.scale = Vector3.ONE
			dot.material_override = GraphicsPolish.glow(col, 1.6)


func _build_vials() -> void:
	for i in range(INGREDIENTS.size()):
		var x := -0.8 + float(i) * 0.4
		var root := Node3D.new()
		root.position = TABLE_POS + Vector3(x, 0.76, 0.32)
		add_child(root)
		# Glass vial.
		var glass := MeshInstance3D.new()
		var glass_mesh := CylinderMesh.new()
		glass_mesh.top_radius = 0.05
		glass_mesh.bottom_radius = 0.05
		glass_mesh.height = 0.17
		glass.mesh = glass_mesh
		glass.position = Vector3(0.0, 0.085, 0.0)
		glass.material_override = GraphicsPolish.pbr_preset(Color(0.8, 0.9, 1.0), "glass")
		root.add_child(glass)
		# Colored liquid inside.
		var liquid := MeshInstance3D.new()
		var liquid_mesh := CylinderMesh.new()
		liquid_mesh.top_radius = 0.038
		liquid_mesh.bottom_radius = 0.038
		liquid_mesh.height = 0.10
		liquid.mesh = liquid_mesh
		liquid.position = Vector3(0.0, 0.06, 0.0)
		var col: Color = INGREDIENTS[i]
		var liquid_mat := GraphicsPolish.glow(col, 1.5)
		liquid.material_override = liquid_mat
		root.add_child(liquid)
		# Cork.
		var cork := MeshInstance3D.new()
		var cork_mesh := CylinderMesh.new()
		cork_mesh.top_radius = 0.03
		cork_mesh.bottom_radius = 0.03
		cork_mesh.height = 0.04
		cork.mesh = cork_mesh
		cork.position = Vector3(0.0, 0.19, 0.0)
		cork.material_override = GraphicsPolish.pbr(Color(0.55, 0.38, 0.20), 0.0, 0.9)
		root.add_child(cork)
		# Floating name tag.
		var tag := GraphicsPolish.make_label(ING_NAMES[i], 30, col.lightened(0.2))
		tag.position = Vector3(0.0, 0.38, 0.0)
		root.add_child(tag)
		vials.append({"node": root, "liquid_mat": liquid_mat, "index": i, "base_y": 0.76})


func _build_sel_ring() -> void:
	sel_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.10
	sel_ring.mesh = torus
	sel_ring.rotation.x = PI * 0.5
	sel_ring.material_override = GraphicsPolish.glow(Color(1.0, 1.0, 0.4), 2.0)
	sel_ring.visible = false
	add_child(sel_ring)


func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("POTION MIX", 44, Color(0.7, 1.0, 0.6))
	hud_label.position = Vector3(-2.6, 2.5, -1.2)
	add_child(hud_label)
	var help := GraphicsPolish.make_label("Pick a vial, then a cauldron - match the recipe dots | R: restart", 26, Color(0.85, 0.85, 0.9))
	help.position = Vector3(-2.6, 1.95, -1.2)
	add_child(help)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.85, 0.3))
	msg_label.position = Vector3(0.0, 2.0, -1.6)
	add_child(msg_label)


func _process(delta: float) -> void:
	elapsed += delta
	for pv in pots:
		var p: Dictionary = pv
		GraphicsPolish.pulse_glow(p["liquid_mat"], 1.3, 0.6, elapsed * 3.0 + float(pv.hash()) * 0.001)
	# Random bubble pops for atmosphere.
	bubble_timer -= delta
	if bubble_timer <= 0.0:
		bubble_timer = rng.randf_range(0.25, 0.6)
		var pot: Dictionary = pots[rng.randi_range(0, pots.size() - 1)]
		var node: Node3D = pot["node"]
		GraphicsPolish.spawn_sparks(self, node.position + Vector3(rng.randf_range(-0.08, 0.08), 0.34, rng.randf_range(-0.08, 0.08)), Color(0.7, 1.0, 0.6), 4)
	if Input.is_key_pressed(KEY_R):
		_reset_game()
		return
	if state == ST_OVER:
		if ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT):
			pinch_hold += delta
			if pinch_hold >= 1.0:
				_reset_game()
				return
		else:
			pinch_hold = 0.0
		return
	anchor_timer += delta
	if anchor_timer >= 30.0:
		anchor_timer = 0.0
		ARUpgradeKit.save_anchor("hw_potion_mix_main", global_transform)
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_game_over()
		return
	_update_selection_visual(delta)
	if ARUpgradeKit.pinch_just_pressed(self, ARUpgradeKit.HAND_RIGHT):
		_pinch_pick()
	if msg_timer > 0.0:
		msg_timer -= delta
		if msg_timer <= 0.0:
			msg_label.text = ""
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == ST_PLAY:
			_click_pick(mb.position)


func _update_selection_visual(delta: float) -> void:
	if selected_vial >= 0 and selected_vial < vials.size():
		var v: Dictionary = vials[selected_vial]
		var node: Node3D = v["node"]
		sel_ring.visible = true
		sel_ring.position = node.position + Vector3(0.0, 0.02 + 0.03 * sin(elapsed * 5.0), 0.0)
		sel_ring.rotation.z += delta * 2.0
	else:
		sel_ring.visible = false


func _click_pick(screen_pos: Vector2) -> void:
	if camera == null:
		return
	var best_kind := ""
	var best_idx := -1
	var best_d := 56.0
	for v in vials:
		var node: Node3D = (v as Dictionary)["node"]
		var sp := camera.unproject_position(node.global_position + Vector3(0.0, 0.1, 0.0))
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best_kind = "vial"
			best_idx = int((v as Dictionary)["index"])
	for i in range(pots.size()):
		var pnode: Node3D = (pots[i] as Dictionary)["node"]
		var sp2 := camera.unproject_position(pnode.global_position + Vector3(0.0, 0.2, 0.0))
		var d2 := sp2.distance_to(screen_pos)
		if d2 < best_d:
			best_d = d2
			best_kind = "pot"
			best_idx = i
	_apply_pick(best_kind, best_idx)


func _pinch_pick() -> void:
	if state != ST_PLAY:
		return
	var pp := ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT)
	var best_kind := ""
	var best_idx := -1
	var best_d := 0.55
	for v in vials:
		var node: Node3D = (v as Dictionary)["node"]
		var d := node.global_position.distance_to(pp)
		if d < best_d:
			best_d = d
			best_kind = "vial"
			best_idx = int((v as Dictionary)["index"])
	for i in range(pots.size()):
		var pnode: Node3D = (pots[i] as Dictionary)["node"]
		var d2 := pnode.global_position.distance_to(pp)
		if d2 < best_d:
			best_d = d2
			best_kind = "pot"
			best_idx = i
	_apply_pick(best_kind, best_idx)


func _apply_pick(kind: String, idx: int) -> void:
	if kind == "":
		return
	if kind == "vial":
		if selected_vial == idx:
			selected_vial = -1 # toggle off
		else:
			selected_vial = idx
			_show_msg("%s selected - now pick a cauldron" % ING_NAMES[idx], 1.4)
		if pour_player != null:
			pour_player.play()
	elif kind == "pot":
		if selected_vial < 0:
			_show_msg("Pick a vial first!", 1.2)
			return
		_pour(idx, selected_vial)
		selected_vial = -1


func _pour(pot_idx: int, vial_idx: int) -> void:
	var pot: Dictionary = pots[pot_idx]
	var recipe: Array = pot["recipe"]
	var progress := int(pot["progress"])
	var node: Node3D = pot["node"]
	var col: Color = INGREDIENTS[vial_idx]
	if int(recipe[progress]) == vial_idx:
		pot["progress"] = progress + 1
		_refresh_dots(pot)
		# Blend the brew toward the poured color.
		var lm: StandardMaterial3D = pot["liquid_mat"]
		var mixed: Color = lm.emission.lerp(col, 0.6)
		lm.albedo_color = mixed
		lm.emission = mixed
		GraphicsPolish.spawn_sparks(self, node.position + Vector3(0.0, 0.36, 0.0), col, 20)
		if pour_player != null:
			pour_player.play()
		if int(pot["progress"]) >= 3:
			_finish_potion(pot)
		else:
			_show_msg("Good pour! %d/3" % int(pot["progress"]), 0.9)
	else:
		pot["progress"] = 0
		_refresh_dots(pot)
		GraphicsPolish.spawn_sparks(self, node.position + Vector3(0.0, 0.36, 0.0), Color(1.0, 0.15, 0.1), 22)
		_show_msg("WRONG INGREDIENT! Recipe reset.", 1.4)
		if fizz_player != null:
			fizz_player.play()


func _finish_potion(pot: Dictionary) -> void:
	var node: Node3D = pot["node"]
	score += 30
	brewed += 1
	GraphicsPolish.spawn_confetti(self, node.position + Vector3(0.0, 0.7, 0.0), 45)
	_show_msg("POTION BREWED! +30", 1.4)
	if brew_player != null:
		brew_player.play()
	_new_recipe(pot)


func _game_over() -> void:
	state = ST_OVER
	_show_msg("TIME UP!\nScore: %d   Potions brewed: %d\nPress R or pinch-hold to restart" % [score, brewed], 600.0)
	GraphicsPolish.spawn_confetti(self, TABLE_POS + Vector3(0.0, 1.6, 0.0), 60)
	ARUpgradeKit.save_anchor("hw_potion_mix_main", global_transform)
	if end_player != null:
		end_player.play()


func _reset_game() -> void:
	state = ST_PLAY
	time_left = ROUND_TIME
	score = 0
	brewed = 0
	selected_vial = -1
	pinch_hold = 0.0
	for pv in pots:
		_new_recipe(pv)
	_show_msg("", 0.0)
	ARUpgradeKit.save_anchor("hw_potion_mix_main", global_transform)


func _update_hud() -> void:
	if hud_label == null:
		return
	hud_label.text = "POTION MIX\nTime: %ds   Score: %d   Brewed: %d" % [int(ceil(time_left)), score, brewed]


func _show_msg(text: String, duration: float) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_timer = duration


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Synthesize a short enveloped sine tone (pour / fizz / brew / jingle).
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
