## Holo Farm: a cozy farm sim on your floor for NEXUS ARCADE.
## 3x3 anchored plots (expandable to 4x4) using real Kenney nature-kit models:
## tilled dirt rows, 4-stage corn, leafy carrot/pumpkin vines, mature crops,
## fences and gate. Loop: pinch to till, pick a seed (pumpkin/carrot/corn),
## plant, water with a pour-hold gesture (growth runs on real, accelerated
## time while watered), harvest with a grab, sell at the market stall.
## Upgrades: more plots, auto-watering sprinkler, crow-scaring scarecrow.
## Day/night cycle lighting, butterflies, harvest confetti, haptic ticks.
## Coins, inventory, upgrades and crop states persist in user://nexus_farm.cfg.
## Desktop: click / click-hold. XR: right-hand pinch / pinch-hold. R reseeds help.
extends Node3D

const SAVE_PATH := "user://nexus_farm.cfg"
const MODEL_DIR := "res://assets/models/holo_farm/"
const DAY_LENGTH := 150.0
const STAGE_TIME := 20.0
const WATER_TIME := 45.0
const WATER_HOLD := 1.2
const CROP_ORDER := ["pumpkin", "carrot", "corn"]
const CROP_PRICE := {"pumpkin": 25, "carrot": 18, "corn": 12}
const CROP_COLOR := {"pumpkin": Color(1.0, 0.55, 0.10), "carrot": Color(1.0, 0.45, 0.12), "corn": Color(1.0, 0.85, 0.25)}
const GRID_CENTER := Vector3(0.0, 0.0, -0.5)

var camera: Camera3D = null
var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var elapsed := 0.0
var _model_cache := {}

# --- persistence ---
var coins := 40
var inv := {"pumpkin": 0, "carrot": 0, "corn": 0}
var up_plots16 := false
var up_sprinkler := false
var up_scarecrow := false
var seed := "pumpkin"
var day_t := 20.0

# --- input ---
var _prev_press := false
var hover_id := ""
var buttons: Array = []

# --- farm ---
var farm_root: Node3D = null
var plots: Array = []
var plot_spacing := 1.15
var stall_pos := Vector3(3.4, 0.0, -1.2)
var shop_sign_pos := Vector3(-3.4, 0.0, -0.2)
var shop_panel: Node3D = null
var shop_open := false
var sprinkler_node: Node3D = null
var sprinkler_head: Node3D = null
var sprinkler_t := 0.0
var scarecrow_node: Node3D = null
var windmill_blades: Node3D = null
var lantern: OmniLight3D = null
var water_hold_plot := -1
var water_hold_t := 0.0

# --- critters ---
var butterflies: Array = []
var crows: Array = []
var crow_timer := 35.0

# --- hud ---
var hud_label: Label3D = null
var msg_label: Label3D = null
var hint_label: Label3D = null
var _msg := ""
var _msg_t := 0.0
var _save_t := 0.0


func _ready() -> void:
	ARUpgradeKit.apply_anchor(self, "holo_farm_main")
	_ensure_camera()
	_ensure_environment()
	_ensure_light()
	_load_save()
	_build_farm()
	_build_plots()
	_build_stall()
	_build_shop()
	_build_seed_buttons()
	_build_critters()
	_build_hud()
	_apply_upgrades_visual()
	GraphicsPolish.spawn_ambient_motes(self, Vector3(0.0, 1.5, -0.5), 4.0, 40)


func _ensure_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		add_child(cam)
		cam.position = Vector3(0.0, 1.75, 3.3)
		cam.look_at(Vector3(0.0, 0.8, -0.8), Vector3.UP)
		cam.current = true
	camera = cam


func _ensure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.75)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.60, 0.72, 0.88)
	env.fog_density = 0.008
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _ensure_light() -> void:
	for c in get_children():
		if c is DirectionalLight3D:
			sun = c
			return
	sun = GraphicsPolish.make_light_rig(self, 1.15)


# ---------------------------------------------------------------- models ---
func _model(model_name: String) -> Node3D:
	if _model_cache.has(model_name):
		var ps: PackedScene = _model_cache[model_name]
		if ps != null:
			return ps.instantiate() as Node3D
		_model_cache.erase(model_name)
	var path := MODEL_DIR + model_name + ".fbx"
	if not ResourceLoader.exists(path):
		push_warning("[farm] missing model: " + path)
		return null
	var ps2 := load(path) as PackedScene
	if ps2 == null:
		push_warning("[farm] failed to load: " + path)
		return null
	_model_cache[model_name] = ps2
	return ps2.instantiate() as Node3D


func _find_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_meshes(c, out)


func _tint_soil(soil: Node3D, watered: bool) -> void:
	var meshes: Array = []
	_find_meshes(soil, meshes)
	var col := Color(0.30, 0.19, 0.11) if watered else Color(0.45, 0.32, 0.19)
	for mi in meshes:
		(mi as MeshInstance3D).material_override = GraphicsPolish.pbr_preset(col, "matte")


# ------------------------------------------------------------- persistence ---
func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	coins = int(cfg.get_value("farm", "coins", 40))
	for k in inv.keys():
		inv[k] = int(cfg.get_value("farm", "inv_" + str(k), 0))
	up_plots16 = bool(cfg.get_value("farm", "up_plots16", false))
	up_sprinkler = bool(cfg.get_value("farm", "up_sprinkler", false))
	up_scarecrow = bool(cfg.get_value("farm", "up_scarecrow", false))
	seed = str(cfg.get_value("farm", "seed", "pumpkin"))
	day_t = float(cfg.get_value("farm", "day_t", 20.0))
	_saved_plots = cfg.get_value("farm", "plots", [])


var _saved_plots: Array = []


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("farm", "coins", coins)
	for k in inv.keys():
		cfg.set_value("farm", "inv_" + str(k), inv[k])
	cfg.set_value("farm", "up_plots16", up_plots16)
	cfg.set_value("farm", "up_sprinkler", up_sprinkler)
	cfg.set_value("farm", "up_scarecrow", up_scarecrow)
	cfg.set_value("farm", "seed", seed)
	cfg.set_value("farm", "day_t", day_t)
	var parr: Array = []
	for p in plots:
		var pd: Dictionary = p
		parr.append([pd["state"], pd["crop"], pd["stage"], pd["growth_t"], pd["water_t"]])
	cfg.set_value("farm", "plots", parr)
	cfg.save(SAVE_PATH)


# ------------------------------------------------------------ farm build ---
func _build_farm() -> void:
	farm_root = Node3D.new()
	farm_root.name = "Farm"
	add_child(farm_root)
	# Grass disc the farm sits on.
	var grass := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 5.2
	gcyl.bottom_radius = 5.2
	gcyl.height = 0.08
	grass.mesh = gcyl
	grass.material_override = GraphicsPolish.pbr_preset(Color(0.32, 0.58, 0.28), "matte")
	grass.position = Vector3(0.0, -0.04, -0.5)
	farm_root.add_child(grass)
	# Fence perimeter (Kenney), gate at the front.
	var fence_n := 9
	for i in fence_n:
		var t := float(i) / float(fence_n - 1)
		for zside in [-1.0, 1.0]:
			var f := _model("fence_simple")
			if f != null:
				f.position = Vector3(lerpf(-4.4, 4.4, t), 0.0, -0.5 + zside * 4.4)
				farm_root.add_child(f)
	for xside in [-1.0, 1.0]:
		for i in fence_n:
			var t := float(i) / float(fence_n - 1)
			var f2 := _model("fence_simple")
			if f2 != null:
				f2.position = Vector3(xside * 4.4, 0.0, lerpf(-4.9, 3.9, t))
				f2.rotation.y = PI * 0.5
				farm_root.add_child(f2)
	for cx in [-4.4, 4.4]:
		for cz in [-4.9, 3.9]:
			var cor := _model("fence_corner")
			if cor != null:
				cor.position = Vector3(cx, 0.0, cz)
				farm_root.add_child(cor)
	var gate := _model("fence_gate")
	if gate != null:
		gate.position = Vector3(0.0, 0.0, 3.9)
		farm_root.add_child(gate)
	# Windmill (primitive-built): tapered tower + spinning blades.
	var wm := Node3D.new()
	wm.position = Vector3(-3.6, 0.0, -3.6)
	farm_root.add_child(wm)
	var tower := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.28
	tcyl.bottom_radius = 0.55
	tcyl.height = 3.2
	tower.mesh = tcyl
	tower.material_override = GraphicsPolish.pbr_preset(Color(0.72, 0.68, 0.62), "matte")
	tower.position = Vector3(0.0, 1.6, 0.0)
	wm.add_child(tower)
	var capm := MeshInstance3D.new()
	var ccone := CylinderMesh.new()
	ccone.top_radius = 0.02
	ccone.bottom_radius = 0.42
	ccone.height = 0.6
	capm.mesh = ccone
	capm.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.25, 0.15), "matte")
	capm.position = Vector3(0.0, 3.45, 0.0)
	wm.add_child(capm)
	windmill_blades = Node3D.new()
	windmill_blades.position = Vector3(0.0, 3.1, 0.42)
	wm.add_child(windmill_blades)
	for b in 4:
		var blade := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(0.22, 1.5, 0.04)
		blade.mesh = bbox
		blade.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.80, 0.70), "matte")
		blade.position = Vector3(0.0, 0.75, 0.0)
		var pivot := Node3D.new()
		pivot.rotation.z = float(b) * PI * 0.5
		pivot.add_child(blade)
		windmill_blades.add_child(pivot)
	# Decorative trees + rocks.
	for td in [[-4.6, -1.5, 1.2], [4.7, 0.5, 1.4], [2.8, -4.4, 1.0]]:
		_make_tree(Vector3(td[0], 0.0, td[1]), float(td[2]))
	for rd in [[-2.5, 2.8], [3.0, 2.5]]:
		var rock := MeshInstance3D.new()
		var rsm := SphereMesh.new()
		rsm.radius = 0.22
		rsm.height = 0.44
		rock.mesh = rsm
		rock.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.55, 0.58), "matte")
		rock.scale = Vector3(1.3, 0.7, 1.0)
		rock.position = Vector3(rd[0], 0.08, rd[1])
		farm_root.add_child(rock)


func _make_tree(pos: Vector3, s: float) -> void:
	var t := Node3D.new()
	t.position = pos
	t.scale = Vector3.ONE * s
	farm_root.add_child(t)
	var trunk := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.09
	tcyl.bottom_radius = 0.13
	tcyl.height = 0.9
	trunk.mesh = tcyl
	trunk.material_override = GraphicsPolish.pbr_preset(Color(0.40, 0.28, 0.16), "matte")
	trunk.position = Vector3(0.0, 0.45, 0.0)
	t.add_child(trunk)
	for li in 3:
		var leaf := MeshInstance3D.new()
		var lcone := CylinderMesh.new()
		lcone.top_radius = 0.02
		lcone.bottom_radius = 0.75 - float(li) * 0.16
		lcone.height = 0.8
		leaf.mesh = lcone
		leaf.material_override = GraphicsPolish.pbr_preset(Color(0.25, 0.52, 0.26), "matte")
		leaf.position = Vector3(0.0, 1.15 + float(li) * 0.55, 0.0)
		t.add_child(leaf)


# ------------------------------------------------------------------- plots ---
func _grid_size() -> int:
	return 4 if up_plots16 else 3


func _build_plots() -> void:
	for p in plots:
		var pd: Dictionary = p
		if is_instance_valid((pd["node"] as Node)):
			(pd["node"] as Node).queue_free()
	plots.clear()
	var n := _grid_size()
	plot_spacing = 1.05 if up_plots16 else 1.15
	var idx := 0
	for gz in n:
		for gx in n:
			var node := Node3D.new()
			var px: float = GRID_CENTER.x + (float(gx) - float(n - 1) * 0.5) * plot_spacing
			var pz: float = GRID_CENTER.z + (float(gz) - float(n - 1) * 0.5) * plot_spacing
			node.position = Vector3(px, 0.0, pz)
			farm_root.add_child(node)
			var soil := _model("crops_dirtSingle")
			if soil != null:
				node.add_child(soil)
			var holder := Node3D.new()
			node.add_child(holder)
			var pd := {
				"node": node, "idx": idx, "state": "untilled", "crop": "",
				"stage": 0, "growth_t": 0.0, "water_t": 0.0,
				"soil": soil, "holder": holder, "watered": false,
			}
			plots.append(pd)
			idx += 1
	# Restore saved states.
	for i in mini(_saved_plots.size(), plots.size()):
		var s: Array = _saved_plots[i]
		var pd2: Dictionary = plots[i]
		pd2["state"] = str(s[0])
		pd2["crop"] = str(s[1])
		pd2["stage"] = int(s[2])
		pd2["growth_t"] = float(s[3])
		pd2["water_t"] = float(s[4])
		_refresh_plot_visual(pd2)


func _plot_center(pd: Dictionary) -> Vector3:
	return (pd["node"] as Node3D).global_position


func _refresh_plot_visual(pd: Dictionary) -> void:
	# Soil swap: tilled rows vs plain dirt.
	var old_soil: Node3D = pd["soil"]
	if old_soil != null and is_instance_valid(old_soil):
		old_soil.queue_free()
	var tilled: bool = str(pd["state"]) != "untilled"
	var soil := _model("crops_dirtRow" if tilled else "crops_dirtSingle")
	pd["soil"] = soil
	if soil != null:
		(pd["node"] as Node3D).add_child(soil)
		if tilled:
			_tint_soil(soil, float(pd["water_t"]) > 0.0)
	# Crop stage model.
	var holder: Node3D = pd["holder"]
	for c in holder.get_children():
		c.queue_free()
	var st: String = pd["state"]
	if st == "growing" or st == "mature":
		var crop: String = pd["crop"]
		var stage: int = pd["stage"]
		var spec := _crop_stage_spec(crop, stage)
		var m := _model(str(spec["model"]))
		if m != null:
			m.scale = Vector3.ONE * float(spec["scale"])
			m.position = Vector3(0.0, float(spec["y"]), 0.0)
			holder.add_child(m)


func _crop_stage_spec(crop: String, stage: int) -> Dictionary:
	match crop:
		"corn":
			return {"model": ["crops_cornStageA", "crops_cornStageB", "crops_cornStageC", "crops_cornStageD"][stage], "scale": 1.0, "y": 0.0}
		"pumpkin":
			var mods := ["crops_leafsStageA", "crops_leafsStageB", "crop_pumpkin", "crop_pumpkin"]
			var scl: float = [1.0, 1.15, 0.55, 1.0][stage]
			return {"model": mods[stage], "scale": scl, "y": 0.0}
		"carrot":
			var mods2 := ["crops_leafsStageA", "crops_leafsStageB", "crop_carrot", "crop_carrot"]
			var scl2: float = [1.0, 1.2, 0.5, 1.0][stage]
			var yoff: float = [0.0, 0.0, -0.06, -0.02][stage]
			return {"model": mods2[stage], "scale": scl2, "y": yoff}
	return {"model": "crops_cornStageA", "scale": 1.0, "y": 0.0}


func _plots_process(delta: float) -> void:
	for pd in plots:
		var d: Dictionary = pd
		var st: String = d["state"]
		if st != "growing":
			continue
		if float(d["water_t"]) > 0.0:
			d["water_t"] = float(d["water_t"]) - delta
			d["growth_t"] = float(d["growth_t"]) + delta
			if float(d["growth_t"]) >= STAGE_TIME:
				d["growth_t"] = 0.0
				d["stage"] = int(d["stage"]) + 1
				if int(d["stage"]) >= 3:
					d["stage"] = 3
					d["state"] = "mature"
					GraphicsPolish.spawn_sparks(self, _plot_center(d) + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.4), 18)
					Haptics.tick()
					_set_msg("%s ready to harvest!" % str(d["crop"]).capitalize(), 1.6)
				_refresh_plot_visual(d)
			# Soil tint follows watering.
			var was: bool = d["watered"]
			var now: bool = float(d["water_t"]) > 0.0
			if was != now:
				d["watered"] = now
				if d["soil"] != null and is_instance_valid(d["soil"]):
					_tint_soil(d["soil"], now)
		elif bool(d["watered"]):
			d["watered"] = false
			if d["soil"] != null and is_instance_valid(d["soil"]):
				_tint_soil(d["soil"], false)


func _interact_plot(pd: Dictionary) -> void:
	var st: String = pd["state"]
	var c := _plot_center(pd)
	match st:
		"untilled":
			pd["state"] = "tilled"
			_refresh_plot_visual(pd)
			GraphicsPolish.spawn_sparks(self, c + Vector3(0, 0.15, 0), Color(0.55, 0.42, 0.28), 12)
			Haptics.tick()
			_set_msg("Tilled! Plant a seed.", 1.2)
		"tilled":
			pd["state"] = "growing"
			pd["crop"] = seed
			pd["stage"] = 0
			pd["growth_t"] = 0.0
			pd["water_t"] = 0.0
			_refresh_plot_visual(pd)
			GraphicsPolish.spawn_sparks(self, c + Vector3(0, 0.25, 0), CROP_COLOR[seed], 14)
			Haptics.tick()
			_set_msg("Planted %s - hold to water!" % seed.capitalize(), 1.6)
			_save()
		"growing":
			# Watering is hold-based; handled in _process. Tap shows progress.
			var pct := int(float(pd["stage"]) / 3.0 * 100.0)
			var w := "watered" if float(pd["water_t"]) > 0.0 else "thirsty - HOLD to water"
			_set_msg("%s %d%% - %s" % [str(pd["crop"]).capitalize(), pct, w], 1.4)
		"mature":
			var crop: String = pd["crop"]
			inv[crop] = int(inv[crop]) + 1
			pd["state"] = "tilled"
			pd["crop"] = ""
			pd["stage"] = 0
			pd["growth_t"] = 0.0
			_refresh_plot_visual(pd)
			GraphicsPolish.spawn_confetti(self, c + Vector3(0, 0.6, 0), 30)
			Haptics.pulse(0.7, 0.12)
			_set_msg("Harvested %s! Sell it at the stall." % crop.capitalize(), 1.8)
			_save()
	_update_hud()


func _water_plot(pd: Dictionary) -> void:
	pd["water_t"] = WATER_TIME
	pd["watered"] = true
	if pd["soil"] != null and is_instance_valid(pd["soil"]):
		_tint_soil(pd["soil"], true)
	var c := _plot_center(pd)
	GraphicsPolish.spawn_sparks(self, c + Vector3(0, 0.5, 0), Color(0.35, 0.65, 1.0), 22)
	Haptics.tick()
	_set_msg("Watered!", 1.0)
	_save()


# ------------------------------------------------------------- market stall ---
func _build_stall() -> void:
	var stall := Node3D.new()
	stall.name = "Stall"
	stall.position = stall_pos
	farm_root.add_child(stall)
	# Counter + posts + striped awning.
	var counter := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(1.7, 0.85, 0.8)
	counter.mesh = cbox
	counter.material_override = GraphicsPolish.pbr_preset(Color(0.45, 0.30, 0.16), "matte")
	counter.position = Vector3(0.0, 0.425, 0.0)
	stall.add_child(counter)
	var ctop := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(1.9, 0.06, 1.0)
	ctop.mesh = tbox
	ctop.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.38, 0.20), "matte")
	ctop.position = Vector3(0.0, 0.88, 0.0)
	stall.add_child(ctop)
	for px in [-0.8, 0.8]:
		for pz in [-0.35, 0.35]:
			var post := MeshInstance3D.new()
			var pbox := BoxMesh.new()
			pbox.size = Vector3(0.09, 2.1, 0.09)
			post.mesh = pbox
			post.material_override = GraphicsPolish.pbr_preset(Color(0.40, 0.27, 0.14), "matte")
			post.position = Vector3(px, 1.05, pz)
			stall.add_child(post)
	# Awning: alternating red/white stripes.
	for i in 7:
		var stripe := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.28, 0.05, 1.15)
		stripe.mesh = sbox
		var col := Color(0.85, 0.18, 0.16) if i % 2 == 0 else Color(0.95, 0.93, 0.88)
		stripe.material_override = GraphicsPolish.pbr_preset(col, "matte")
		stripe.position = Vector3(-0.84 + float(i) * 0.28, 2.12, 0.0)
		stripe.rotation.x = -0.18
		stall.add_child(stripe)
	# Produce crates with real Kenney crops on display.
	for ci in 2:
		var crate := MeshInstance3D.new()
		var kbox := BoxMesh.new()
		kbox.size = Vector3(0.5, 0.22, 0.4)
		crate.mesh = kbox
		crate.material_override = GraphicsPolish.pbr_preset(Color(0.50, 0.34, 0.18), "matte")
		crate.position = Vector3(-0.45 + float(ci) * 0.9, 1.02, 0.0)
		stall.add_child(crate)
	var disp1 := _model("crop_pumpkin")
	if disp1 != null:
		disp1.scale = Vector3.ONE * 0.8
		disp1.position = Vector3(-0.45, 1.22, 0.0)
		stall.add_child(disp1)
	var disp2 := _model("crop_carrot")
	if disp2 != null:
		disp2.scale = Vector3.ONE * 0.9
		disp2.position = Vector3(0.45, 1.24, 0.0)
		stall.add_child(disp2)
	# Warm lantern light (bright at night).
	lantern = GraphicsPolish.make_point_light(stall, Vector3(0, 1.9, 0), Color(1.0, 0.75, 0.45), 0.0, 5.0)
	var sign := GraphicsPolish.make_label("MARKET - click to SELL", 40, Color(1.0, 0.90, 0.55))
	sign.position = Vector3(0.0, 2.55, 0.0)
	sign.pixel_size = 0.004
	stall.add_child(sign)


func _sell_all() -> void:
	var total := 0
	var count := 0
	for k in inv.keys():
		var n: int = inv[k]
		total += n * int(CROP_PRICE[k])
		count += n
		inv[k] = 0
	if count == 0:
		_set_msg("Basket is empty - harvest crops first!", 1.8)
		return
	coins += total
	GraphicsPolish.spawn_confetti(self, stall_pos + Vector3(0, 1.6, 0), 50)
	GraphicsPolish.spawn_sparks(self, stall_pos + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.30), 30)
	Haptics.pulse(0.8, 0.15)
	_set_msg("Sold %d crops for %d coins!" % [count, total], 2.2)
	_save()
	_update_hud()


# ------------------------------------------------------------------ shop ---
func _build_shop() -> void:
	# Signpost.
	var signpost := Node3D.new()
	signpost.name = "ShopSign"
	signpost.position = shop_sign_pos
	farm_root.add_child(signpost)
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.06
	pcyl.bottom_radius = 0.07
	pcyl.height = 1.7
	pole.mesh = pcyl
	pole.material_override = GraphicsPolish.pbr_preset(Color(0.40, 0.28, 0.15), "matte")
	pole.position = Vector3(0.0, 0.85, 0.0)
	signpost.add_child(pole)
	var board := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(1.1, 0.5, 0.08)
	board.mesh = bbox
	board.material_override = GraphicsPolish.pbr_preset(Color(0.48, 0.33, 0.17), "matte")
	board.position = Vector3(0.0, 1.55, 0.0)
	signpost.add_child(board)
	var slabel := GraphicsPolish.make_label("UPGRADES", 44, Color(1.0, 0.92, 0.60))
	slabel.pixel_size = 0.004
	slabel.position = Vector3(0.0, 1.55, 0.06)
	signpost.add_child(slabel)
	# Panel with upgrade buttons (hidden until the sign is clicked).
	shop_panel = Node3D.new()
	shop_panel.position = shop_sign_pos + Vector3(0.0, 0.4, 0.9)
	shop_panel.visible = false
	farm_root.add_child(shop_panel)


func _refresh_shop_panel() -> void:
	for c in shop_panel.get_children():
		c.queue_free()
	buttons = buttons.filter(func(b): return not str((b as Dictionary)["id"]).begins_with("up_"))
	var defs := [
		{"id": "up_plots", "text": "More Plots (4x4)", "cost": 600, "owned": up_plots16},
		{"id": "up_sprinkler", "text": "Sprinkler", "cost": 400, "owned": up_sprinkler},
		{"id": "up_scarecrow", "text": "Scarecrow", "cost": 250, "owned": up_scarecrow},
	]
	for i in defs.size():
		var d: Dictionary = defs[i]
		var label := str(d["text"])
		if bool(d["owned"]):
			label += " - OWNED"
		else:
			label += " - %d coins" % int(d["cost"])
		_add_button(str(d["id"]), Vector3(0.0, 1.5 - float(i) * 0.55, 0.0), label, 1.9, 0.42, Color(0.16, 0.18, 0.34), shop_panel)


func _buy_upgrade(id: String) -> void:
	var cost := 0
	match id:
		"up_plots":
			cost = 600
			if up_plots16:
				return
		"up_sprinkler":
			cost = 400
			if up_sprinkler:
				return
		"up_scarecrow":
			cost = 250
			if up_scarecrow:
				return
	if coins < cost:
		_set_msg("Not enough coins! (%d/%d)" % [coins, cost], 1.8)
		Haptics.pulse(0.4, 0.1)
		return
	coins -= cost
	# Preserve current plot states across the grid rebuild.
	var keep: Array = []
	for p in plots:
		var pd: Dictionary = p
		keep.append([pd["state"], pd["crop"], pd["stage"], pd["growth_t"], pd["water_t"]])
	_saved_plots = keep
	match id:
		"up_plots":
			up_plots16 = true
			_build_plots()
		"up_sprinkler":
			up_sprinkler = true
		"up_scarecrow":
			up_scarecrow = true
	_apply_upgrades_visual()
	GraphicsPolish.spawn_confetti(self, shop_sign_pos + Vector3(0, 1.6, 0.9), 40)
	Haptics.pulse(0.8, 0.15)
	_set_msg("Upgrade purchased!", 1.8)
	_refresh_shop_panel()
	_save()
	_update_hud()


func _apply_upgrades_visual() -> void:
	if up_sprinkler and sprinkler_node == null:
		sprinkler_node = Node3D.new()
		sprinkler_node.position = GRID_CENTER + Vector3(0.0, 0.0, 0.0)
		farm_root.add_child(sprinkler_node)
		var post := MeshInstance3D.new()
		var pcyl := CylinderMesh.new()
		pcyl.top_radius = 0.05
		pcyl.bottom_radius = 0.06
		pcyl.height = 0.7
		post.mesh = pcyl
		post.material_override = GraphicsPolish.pbr(Color(0.55, 0.60, 0.65), 0.8, 0.35)
		post.position = Vector3(0.0, 0.35, 0.0)
		sprinkler_node.add_child(post)
		sprinkler_head = Node3D.new()
		sprinkler_head.position = Vector3(0.0, 0.72, 0.0)
		sprinkler_node.add_child(sprinkler_head)
		for a in 2:
			var arm := MeshInstance3D.new()
			var abox := BoxMesh.new()
			abox.size = Vector3(0.5, 0.04, 0.04)
			arm.mesh = abox
			arm.material_override = GraphicsPolish.pbr(Color(0.30, 0.55, 0.90), 0.6, 0.4)
			arm.position = Vector3(0.25 if a == 0 else -0.25, 0.0, 0.0)
			sprinkler_head.add_child(arm)
	if up_scarecrow and scarecrow_node == null:
		scarecrow_node = Node3D.new()
		scarecrow_node.position = Vector3(1.9, 0.0, -3.4)
		farm_root.add_child(scarecrow_node)
		var pole := MeshInstance3D.new()
		var pcyl2 := CylinderMesh.new()
		pcyl2.top_radius = 0.05
		pcyl2.bottom_radius = 0.06
		pcyl2.height = 1.9
		pole.mesh = pcyl2
		pole.material_override = GraphicsPolish.pbr_preset(Color(0.42, 0.30, 0.16), "matte")
		pole.position = Vector3(0.0, 0.95, 0.0)
		scarecrow_node.add_child(pole)
		var bar := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(1.1, 0.08, 0.08)
		bar.mesh = bbox
		bar.material_override = GraphicsPolish.pbr_preset(Color(0.42, 0.30, 0.16), "matte")
		bar.position = Vector3(0.0, 1.45, 0.0)
		scarecrow_node.add_child(bar)
		# Straw body: shirt + head + hat.
		var shirt := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.55, 0.65, 0.30)
		shirt.mesh = sbox
		shirt.material_override = GraphicsPolish.pbr_preset(Color(0.55, 0.30, 0.20), "matte")
		shirt.position = Vector3(0.0, 1.15, 0.0)
		scarecrow_node.add_child(shirt)
		var head := MeshInstance3D.new()
		var hsm := SphereMesh.new()
		hsm.radius = 0.17
		hsm.height = 0.34
		head.mesh = hsm
		head.material_override = GraphicsPolish.pbr_preset(Color(0.85, 0.72, 0.52), "matte")
		head.position = Vector3(0.0, 1.72, 0.0)
		scarecrow_node.add_child(head)
		for ex in [-0.06, 0.06]:
			var eye := MeshInstance3D.new()
			var esm := SphereMesh.new()
			esm.radius = 0.025
			esm.height = 0.05
			eye.mesh = esm
			eye.material_override = GraphicsPolish.pbr(Color(0.05, 0.05, 0.05), 0.0, 0.5)
			eye.position = Vector3(ex, 1.75, 0.15)
			scarecrow_node.add_child(eye)
		var hat := MeshInstance3D.new()
		var hcone := CylinderMesh.new()
		hcone.top_radius = 0.02
		hcone.bottom_radius = 0.24
		hcone.height = 0.30
		hat.mesh = hcone
		hat.material_override = GraphicsPolish.pbr_preset(Color(0.35, 0.22, 0.12), "matte")
		hat.position = Vector3(0.0, 1.95, 0.0)
		hat.rotation.z = 0.12
		scarecrow_node.add_child(hat)


# ------------------------------------------------------------ seed buttons ---
func _build_seed_buttons() -> void:
	for i in CROP_ORDER.size():
		var crop: String = CROP_ORDER[i]
		var pos := Vector3(-1.5 + float(i) * 1.5, 1.25, 1.35)
		_add_button("seed_" + crop, pos, crop.capitalize(), 1.15, 0.34, CROP_COLOR[crop].darkened(0.45))
	_refresh_seed_selection()


func _refresh_seed_selection() -> void:
	for b in buttons:
		var bd: Dictionary = b
		var id: String = bd["id"]
		if id.begins_with("seed_"):
			var edge: MeshInstance3D = (bd["node"] as Node3D).get_child(1)
			var on: bool = id == "seed_" + seed
			edge.material_override = GraphicsPolish.glow(Color(1.0, 0.9, 0.3) if on else Color(0.45, 0.55, 1.0), 1.4 if on else 0.55)


# ---------------------------------------------------------------- critters ---
func _build_critters() -> void:
	var wing_colors := [Color(1.0, 0.60, 0.20), Color(0.75, 0.45, 1.0), Color(1.0, 0.90, 0.35), Color(0.45, 0.80, 1.0), Color(1.0, 0.45, 0.60)]
	for i in 5:
		var bf := Node3D.new()
		farm_root.add_child(bf)
		var body := MeshInstance3D.new()
		var bcap := CapsuleMesh.new()
		bcap.radius = 0.02
		bcap.height = 0.12
		body.mesh = bcap
		body.material_override = GraphicsPolish.pbr(Color(0.15, 0.12, 0.10), 0.0, 0.6)
		body.rotation.x = PI * 0.5
		bf.add_child(body)
		var wings: Array = []
		for s in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			wbox.size = Vector3(0.14, 0.01, 0.10)
			wing.mesh = wbox
			wing.material_override = GraphicsPolish.glow(wing_colors[i], 0.7)
			wing.position = Vector3(s * 0.07, 0.02, 0.0)
			bf.add_child(wing)
			wings.append(wing)
		butterflies.append({
			"node": bf, "wings": wings, "phase": randf() * TAU,
			"cx": randf_range(-3.0, 3.0), "cz": randf_range(-3.5, 2.5),
			"r": randf_range(0.8, 1.8), "speed": randf_range(0.5, 0.9),
		})


func _butterflies_process() -> void:
	for bf in butterflies:
		var d: Dictionary = bf
		var n: Node3D = d["node"]
		if not is_instance_valid(n):
			continue
		var ph: float = d["phase"]
		var t := elapsed * float(d["speed"]) + ph
		n.position = Vector3(
			float(d["cx"]) + cos(t) * float(d["r"]),
			1.1 + sin(t * 1.7) * 0.35,
			float(d["cz"]) + sin(t * 0.9) * float(d["r"]))
		n.rotation.y = -t
		var flap := sin(elapsed * 18.0 + ph) * 0.9
		var wings: Array = d["wings"]
		(wings[0] as Node3D).rotation.z = flap
		(wings[1] as Node3D).rotation.z = -flap


func _make_crow() -> Node3D:
	var crow := Node3D.new()
	var body := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.11
	bsm.height = 0.22
	body.mesh = bsm
	body.material_override = GraphicsPolish.pbr(Color(0.06, 0.06, 0.08), 0.1, 0.5)
	body.scale = Vector3(1.0, 0.85, 1.35)
	crow.add_child(body)
	var head := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = 0.07
	hsm.height = 0.14
	head.mesh = hsm
	head.material_override = GraphicsPolish.pbr(Color(0.06, 0.06, 0.08), 0.1, 0.5)
	head.position = Vector3(0.0, 0.10, 0.13)
	crow.add_child(head)
	var beak := MeshInstance3D.new()
	var bcone := CylinderMesh.new()
	bcone.top_radius = 0.0
	bcone.bottom_radius = 0.025
	bcone.height = 0.08
	beak.mesh = bcone
	beak.material_override = GraphicsPolish.pbr_preset(Color(0.95, 0.65, 0.15), "matte")
	beak.rotation.x = PI * 0.5
	beak.position = Vector3(0.0, 0.09, 0.22)
	crow.add_child(beak)
	var wings: Array = []
	for s in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(s * 0.08, 0.04, 0.0)
		crow.add_child(piv)
		var wing := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(0.30, 0.02, 0.16)
		wing.mesh = wbox
		wing.material_override = GraphicsPolish.pbr(Color(0.08, 0.08, 0.10), 0.1, 0.5)
		wing.position = Vector3(s * 0.15, 0.0, 0.0)
		piv.add_child(wing)
		wings.append(piv)
	crow.set_meta("wings", wings)
	return crow


func _crow_wings(crow: Node3D) -> Array:
	return crow.get_meta("wings") as Array


func _crows_process(delta: float) -> void:
	# Spawn timer.
	crow_timer -= delta
	if crow_timer <= 0.0:
		crow_timer = randf_range(45.0, 75.0)
		if not up_scarecrow:
			_spawn_crow()
	for i in range(crows.size() - 1, -1, -1):
		var cd: Dictionary = crows[i]
		var n: Node3D = cd["node"]
		if not is_instance_valid(n):
			crows.remove_at(i)
			continue
		var state: String = cd["state"]
		cd["t"] = float(cd["t"]) + delta
		var wings := _crow_wings(n)
		if state == "fly_in":
			var target: Vector3 = cd["target"]
			n.global_position = n.global_position.lerp(target, minf(1.0, delta * 1.2))
			for w in wings:
				(w as Node3D).rotation.z = sin(cd["t"] * 22.0) * 0.7 * (1.0 if (wings.find(w) == 0) else -1.0)
			n.look_at(target, Vector3.UP)
			if n.global_position.distance_to(target) < 0.15:
				cd["state"] = "peck"
				cd["t"] = 0.0
				_set_msg("A crow is after your crops! Grab it!", 2.0)
		elif state == "peck":
			for w in wings:
				(w as Node3D).rotation.z = lerpf((w as Node3D).rotation.z, 0.0, minf(1.0, delta * 5.0))
			# Peck bobbing.
			n.position.y = (cd["base_y"] as float) + absf(sin(cd["t"] * 9.0)) * -0.06
			if int(cd["t"] * 2.0) % 2 == 0 and randf() < 0.06:
				GraphicsPolish.spawn_sparks(self, n.global_position, Color(0.4, 0.35, 0.3), 2)
			if float(cd["t"]) > 15.0:
				# Crow eats the crop.
				var pd: Dictionary = cd["plot"]
				if is_instance_valid(pd["node"]):
					pd["state"] = "tilled"
					pd["crop"] = ""
					pd["stage"] = 0
					pd["growth_t"] = 0.0
					_refresh_plot_visual(pd)
					_set_msg("A crow ate your %s!" % str(cd["crop_name"]).capitalize(), 2.2)
					Haptics.pulse(0.5, 0.15)
				cd["state"] = "fly_out"
				cd["t"] = 0.0
				cd["target"] = n.global_position + Vector3(randf_range(-4.0, 4.0), 3.0, 2.0)
		elif state == "fly_out":
			var target2: Vector3 = cd["target"]
			n.global_position = n.global_position.lerp(target2, minf(1.0, delta * 1.6))
			for w2 in wings:
				(w2 as Node3D).rotation.z = sin(cd["t"] * 24.0) * 0.8 * (1.0 if (wings.find(w2) == 0) else -1.0)
			if n.global_position.distance_to(target2) < 0.6 or float(cd["t"]) > 4.0:
				n.queue_free()
				crows.remove_at(i)


func _spawn_crow() -> void:
	var candidates: Array = []
	for pd in plots:
		var st: String = (pd as Dictionary)["state"]
		if st == "growing" or st == "mature":
			candidates.append(pd)
	if candidates.is_empty():
		return
	var pd: Dictionary = candidates[randi() % candidates.size()]
	var crow := _make_crow()
	add_child(crow)
	var start := Vector3(randf_range(-5.0, 5.0), 3.2, randf_range(-6.0, -4.0))
	crow.global_position = start
	var target := _plot_center(pd) + Vector3(0.0, 0.55, 0.0)
	crows.append({
		"node": crow, "state": "fly_in", "t": 0.0, "target": target,
		"plot": pd, "base_y": target.y, "crop_name": str(pd["crop"]),
	})


func _shoo_crow(cd: Dictionary) -> void:
	var n: Node3D = cd["node"]
	cd["state"] = "fly_out"
	cd["t"] = 0.0
	cd["target"] = n.global_position + Vector3(randf_range(-3.0, 3.0), 3.0, 3.0)
	GraphicsPolish.spawn_sparks(self, n.global_position, Color(1.0, 1.0, 1.0), 10)
	Haptics.tick()
	_set_msg("Shoo! Crow chased off.", 1.4)


# --------------------------------------------------------------- day cycle ---
func _day_process(delta: float) -> void:
	day_t = fmod(day_t + delta, DAY_LENGTH)
	var e := sin(day_t / DAY_LENGTH * TAU)  # -1..1
	var dayness := smoothstep(-0.10, 0.35, e)
	var env: Environment = world_env.environment
	var night := Color(0.020, 0.030, 0.085)
	var day := Color(0.52, 0.75, 0.95)
	var sky := night.lerp(day, dayness)
	var dusk := 1.0 - minf(1.0, absf(e) * 3.0)
	sky = sky.lerp(Color(1.0, 0.55, 0.30), dusk * 0.45)
	env.background_color = sky
	env.ambient_light_energy = 0.35 + 0.60 * dayness
	env.fog_light_color = sky.lightened(0.1)
	if sun != null:
		sun.light_energy = 0.12 + 1.05 * dayness
		sun.light_color = Color(1.0, 0.55, 0.30).lerp(Color(1.0, 0.96, 0.90), dayness)
		sun.rotation_degrees = Vector3(-lerpf(12.0, 68.0, dayness), -35.0, 0.0)
	if lantern != null:
		lantern.light_energy = (1.0 - dayness) * 1.4


# ------------------------------------------------------------------ input ---
func _press_active() -> bool:
	return ARUpgradeKit.pinch_active(self, ARUpgradeKit.HAND_RIGHT)



func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> bool:
	var oc := c - o
	var t := oc.dot(d)
	if t < 0.0:
		return false
	return oc.length_squared() - t * t <= r * r


func _add_button(id: String, pos: Vector3, text: String, w: float = 1.15, h: float = 0.30, color: Color = Color(0.16, 0.18, 0.34), parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	if parent == null:
		add_child(n)
	else:
		parent.add_child(n)
	var bg := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(w, h, 0.07)
	bg.mesh = bbox
	var bgm := GraphicsPolish.pbr_preset(color, "plastic")
	bg.material_override = bgm
	n.add_child(bg)
	var edge := MeshInstance3D.new()
	var ebox := BoxMesh.new()
	ebox.size = Vector3(w + 0.03, h + 0.03, 0.05)
	edge.mesh = ebox
	edge.material_override = GraphicsPolish.glow(Color(0.45, 0.55, 1.0), 0.55)
	edge.position = Vector3(0, 0, -0.012)
	n.add_child(edge)
	var lbl := GraphicsPolish.make_label(text, 40, Color(1.0, 1.0, 1.0))
	lbl.pixel_size = 0.0032
	lbl.position = Vector3(0, 0, 0.045)
	n.add_child(lbl)
	buttons.append({"id": id, "node": n, "bgm": bgm, "radius": maxf(w, h) * 0.62})
	return n


func _update_button_hover() -> void:
	hover_id = ""
	var best_d := 1e9
	var xr := ARUpgradeKit.is_xr_active()
	var hand := Vector3.ZERO
	var ro := Vector3.ZERO
	var rd := Vector3.ZERO
	if xr:
		hand = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.3)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		ro = camera.project_ray_origin(mp)
		rd = camera.project_ray_normal(mp)
	for b in buttons:
		var bd: Dictionary = b
		var n: Node3D = bd["node"]
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var c := n.global_position
		var r: float = bd["radius"]
		var hit := false
		var d := 1e9
		if xr:
			d = hand.distance_to(c)
			hit = d < r * 1.7
		elif camera != null:
			hit = _ray_sphere(ro, rd, c, r)
			if hit:
				d = ro.distance_to(c)
		if hit and d < best_d:
			best_d = d
			hover_id = str(bd["id"])
	for b in buttons:
		var bd2: Dictionary = b
		if not str(bd2["id"]).begins_with("seed_"):
			continue
		# Seed selection glow handled separately; skip generic hover tint there.


func _click_button(id: String) -> void:
	Haptics.tick()
	if id.begins_with("seed_"):
		seed = id.get_slice("_", 1)
		_refresh_seed_selection()
		_set_msg("Selected %s seeds" % seed.capitalize(), 1.2)
		_save()
	elif id.begins_with("up_"):
		_buy_upgrade(id)


func _toggle_shop() -> void:
	shop_open = not shop_open
	shop_panel.visible = shop_open
	if shop_open:
		_refresh_shop_panel()
		_set_msg("Farm upgrades", 1.4)


# --------------------------------------------------------------------- hud ---
func _build_hud() -> void:
	hud_label = GraphicsPolish.make_label("", 44, Color(1.0, 1.0, 1.0))
	hud_label.position = Vector3(-3.8, 3.0, 0.2)
	hud_label.pixel_size = 0.0045
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(hud_label)
	msg_label = GraphicsPolish.make_label("", 72, Color(1.0, 0.90, 0.45))
	msg_label.position = Vector3(0.0, 2.5, -0.2)
	msg_label.pixel_size = 0.0055
	add_child(msg_label)
	hint_label = GraphicsPolish.make_label("", 36, Color(0.92, 0.96, 1.0))
	hint_label.position = Vector3(0.0, 0.55, 1.9)
	hint_label.pixel_size = 0.0038
	add_child(hint_label)


func _set_msg(t: String, hold: float) -> void:
	_msg = t
	_msg_t = hold
	if msg_label != null:
		msg_label.text = t


func _update_hud() -> void:
	if hud_label == null:
		return
	var basket := "Basket:"
	var empty := true
	for k in CROP_ORDER:
		var n: int = inv[k]
		if n > 0:
			empty = false
			basket += " %d %s" % [n, k]
	if empty:
		basket += " empty"
	var e := sin(day_t / DAY_LENGTH * TAU)
	var tod := "Day" if e > 0.1 else ("Night" if e < -0.1 else "Dusk")
	hud_label.text = "HOLO FARM  |  %s\nCoins: %d   %s\nSeed: %s" % [tod, coins, basket, seed.capitalize()]
	if hint_label != null:
		if ARUpgradeKit.is_xr_active():
			hint_label.text = "Pinch plot: till/plant/harvest  |  HOLD pinch on crop: water  |  Pinch stall: sell"
		else:
			hint_label.text = "Click plot: till/plant/harvest  |  HOLD click on crop: water  |  Click stall: sell, sign: upgrades"


# ----------------------------------------------------------------- process ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_tap()


func _handle_tap() -> void:
	if hover_id != "":
		if hover_id.begins_with("seed_") or hover_id.begins_with("up_"):
			_click_button(hover_id)
			return
	var xr := ARUpgradeKit.is_xr_active()
	var hand := Vector3.ZERO
	var ro := Vector3.ZERO
	var rd := Vector3.ZERO
	if xr:
		hand = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.3)
	elif camera != null:
		var mp := get_viewport().get_mouse_position()
		ro = camera.project_ray_origin(mp)
		rd = camera.project_ray_normal(mp)
	var hit_zone := func(c: Vector3, r: float) -> bool:
		if xr:
			return hand.distance_to(c) < r * 1.5
		return camera != null and _ray_sphere(ro, rd, c, r)
	# Stall click zone.
	if hit_zone.call(stall_pos + Vector3(0, 1.0, 0), 1.3):
		_sell_all()
		return
	# Shop sign click zone.
	if hit_zone.call(shop_sign_pos + Vector3(0, 1.2, 0), 0.9):
		_toggle_shop()
		return
	# Crow shooing.
	for cd in crows:
		var cn: Node3D = (cd as Dictionary)["node"]
		if is_instance_valid(cn) and hit_zone.call(cn.global_position, 0.6):
			_shoo_crow(cd)
			return
	# Plot interaction: nearest plot within radius.
	var best: Dictionary = {}
	var best_d := 0.62
	for pd in plots:
		var c := _plot_center(pd) + Vector3(0, 0.15, 0)
		var d := 1e9
		var ok := false
		if xr:
			d = hand.distance_to(c)
			ok = d < 0.85
		elif camera != null:
			ok = _ray_sphere(ro, rd, c, 0.62)
			if ok:
				d = ro.distance_to(c)
		if ok and d < best_d:
			best_d = d
			best = pd
	if not best.is_empty():
		_interact_plot(best)


func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_key_pressed(KEY_R):
		_set_msg("Holo Farm: grow, harvest, sell, upgrade!", 2.0)
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_set_msg("", 0.0)
	_day_process(delta)
	# Input edges.
	var press := _press_active()
	var just_pressed := press and not _prev_press
	_prev_press = press
	_update_button_hover()
	if just_pressed:
		if ARUpgradeKit.is_xr_active():
			_handle_tap()
		else:
			# Desktop tap already handled via _unhandled_input; still track water-hold start.
			pass
	# Water hold: while pressing on a growing plot.
	if press:
		var xr2 := ARUpgradeKit.is_xr_active()
		var hand2 := Vector3.ZERO
		var ro2 := Vector3.ZERO
		var rd2 := Vector3.ZERO
		if xr2:
			hand2 = ARUpgradeKit.pointer_position(self, ARUpgradeKit.HAND_RIGHT, 1.3)
		elif camera != null:
			var mp2 := get_viewport().get_mouse_position()
			ro2 = camera.project_ray_origin(mp2)
			rd2 = camera.project_ray_normal(mp2)
		var target := -1
		for pd in plots:
			var d: Dictionary = pd
			if str(d["state"]) != "growing":
				continue
			var c := _plot_center(d) + Vector3(0, 0.15, 0)
			var ok := hand2.distance_to(c) < 0.85 if xr2 else (camera != null and _ray_sphere(ro2, rd2, c, 0.62))
			if ok:
				target = int(d["idx"])
				break
		if target >= 0:
			if water_hold_plot != target:
				water_hold_plot = target
				water_hold_t = 0.0
			water_hold_t += delta
			if int(water_hold_t * 10.0) % 4 == 0:
				GraphicsPolish.spawn_sparks(self, _plot_center(plots[target]) + Vector3(0, 0.6, 0), Color(0.35, 0.65, 1.0), 2)
			if water_hold_t >= WATER_HOLD:
				_water_plot(plots[target])
				water_hold_plot = -1
				water_hold_t = 0.0
		else:
			water_hold_plot = -1
			water_hold_t = 0.0
	else:
		water_hold_plot = -1
		water_hold_t = 0.0
	_plots_process(delta)
	_crows_process(delta)
	_butterflies_process()
	if windmill_blades != null:
		windmill_blades.rotation.z += delta * 0.9
	# Sprinkler: spins and auto-waters every 25s.
	if up_sprinkler and sprinkler_head != null:
		sprinkler_head.rotation.y += delta * 2.2
		sprinkler_t += delta
		if sprinkler_t >= 25.0:
			sprinkler_t = 0.0
			for pd in plots:
				var d2: Dictionary = pd
				if str(d2["state"]) == "growing":
					_water_plot(d2)
			GraphicsPolish.spawn_sparks(self, GRID_CENTER + Vector3(0, 1.0, 0), Color(0.35, 0.65, 1.0), 40)
			_set_msg("Sprinkler watered the crops!", 1.6)
	# Periodic save.
	_save_t += delta
	if _save_t >= 20.0:
		_save_t = 0.0
		_save()
	_update_hud()
