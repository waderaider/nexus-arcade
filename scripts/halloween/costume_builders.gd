## HalloweenCostumes - procedural Halloween costume builders for NEXUS ARCADE.
## 30 static build_<id>() -> Node3D functions, each returning a Node3D of
## procedural meshes (PBR via GraphicsPolish, >=1 glow accent each),
## positioned relative to the anchor marker origin it attaches to.
## all_costumes() returns the catalog: id, display name, anchor marker name,
## and a Callable to the builder. All procedural, no external assets.
## Headless-safe: builds nodes/materials only.
class_name HalloweenCostumes
extends RefCounted


# ---------------------------------------------------------------- helpers ---

static func _mi(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	return mi


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	return c


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


static func _add(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := _mi(mesh, mat, pos, rot_deg, scl)
	root.add_child(mi)
	return mi


# --------------------------------------------------------------- builders ---

## 1. Witch Hat (HeadTop): black cone + wide brim + purple glow band.
static func build_witch_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "WitchHat"
	var black := GraphicsPolish.pbr_preset(Color(0.08, 0.06, 0.12), "matte")
	var band := GraphicsPolish.glow(Color(0.65, 0.25, 1.0), 1.8)
	_add(root, _cyl(0.34, 0.34, 0.04), black, Vector3(0, 0.02, 0))
	_add(root, _cyl(0.02, 0.22, 0.44), black, Vector3(0, 0.26, 0))
	_add(root, _torus(0.20, 0.235), band, Vector3(0, 0.07, 0))
	_add(root, _sphere(0.03), band, Vector3(0.10, 0.10, 0.10))
	root.rotation_degrees = Vector3(0, 0, 7)
	return root


## 2. Vampire (Torso): cape on the back + collar + fangs reaching the Face.
static func build_vampire_cape() -> Node3D:
	var root := Node3D.new()
	root.name = "VampireCape"
	var black := GraphicsPolish.pbr_preset(Color(0.10, 0.08, 0.14), "matte")
	var red := GraphicsPolish.pbr(Color(0.55, 0.06, 0.10), 0.1, 0.6)
	var glow_red := GraphicsPolish.glow(Color(1.0, 0.15, 0.15), 1.6)
	var white := GraphicsPolish.pbr_preset(Color(0.95, 0.95, 0.95), "plastic")
	# Cape: black outer, red lining, hanging down the back.
	_add(root, _box(0.62, 0.80, 0.06), black, Vector3(0, -0.25, -0.32), Vector3(6, 0, 0))
	_add(root, _box(0.54, 0.72, 0.02), red, Vector3(0, -0.25, -0.285), Vector3(6, 0, 0))
	# High collar spikes.
	_add(root, _box(0.10, 0.28, 0.04), black, Vector3(-0.16, 0.16, -0.20), Vector3(-18, 0, -14))
	_add(root, _box(0.10, 0.28, 0.04), black, Vector3(0.16, 0.16, -0.20), Vector3(-18, 0, 14))
	# Medallion glow.
	_add(root, _sphere(0.035), glow_red, Vector3(0, 0.02, 0.06))
	# Fangs: offset from Torso marker up to the Face (Face = Torso + (0,0.46,0.06)).
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.012, 0.001, 0.06), white, Vector3(0.045 * side, 0.40, 0.075), Vector3(180, 0, 0))
	return root


## 3. Pumpkin Head (Head): orange shell + glowing carved face + stem.
static func build_pumpkin_head() -> Node3D:
	var root := Node3D.new()
	root.name = "PumpkinHead"
	var orange := GraphicsPolish.pbr(Color(0.95, 0.45, 0.08), 0.0, 0.55)
	var dark_orange := GraphicsPolish.pbr(Color(0.75, 0.32, 0.05), 0.0, 0.7)
	var face_glow := GraphicsPolish.glow(Color(1.0, 0.75, 0.15), 2.2)
	var stem_mat := GraphicsPolish.pbr_preset(Color(0.25, 0.45, 0.15), "matte")
	_add(root, _sphere(0.30), orange, Vector3.ZERO)
	# Ridges.
	for a in [0.0, 60.0, 120.0]:
		_add(root, _torus(0.28, 0.30), dark_orange, Vector3.ZERO, Vector3(0, a, 0), Vector3(1, 1, 1))
	# Carved glowing face.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.001, 0.05, 0.02), face_glow, Vector3(0.11 * side, 0.07, 0.27), Vector3(90, 0, 0))
	_add(root, _cyl(0.001, 0.035, 0.02), face_glow, Vector3(0, -0.02, 0.29), Vector3(90, 0, 0))
	_add(root, _box(0.20, 0.05, 0.02), face_glow, Vector3(0, -0.14, 0.26))
	_add(root, _cyl(0.03, 0.05, 0.12), stem_mat, Vector3(0, 0.34, 0))
	return root


## 4. Ghost (Head): draped white sheet cone + dark eyes.
static func build_ghost_sheet() -> Node3D:
	var root := Node3D.new()
	root.name = "GhostSheet"
	var sheet := GraphicsPolish.pbr_preset(Color(0.94, 0.94, 0.97), "matte")
	var dark := GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.08), "matte")
	var shimmer := GraphicsPolish.glow(Color(0.85, 0.92, 1.0), 0.8)
	_add(root, _cyl(0.10, 0.40, 0.72), sheet, Vector3(0, 0.10, 0))
	_add(root, _cyl(0.38, 0.46, 0.18), sheet, Vector3(0, -0.30, 0))
	# Wavy hem blobs.
	for i in range(5):
		var a := TAU * float(i) / 5.0
		_add(root, _sphere(0.07), sheet, Vector3(cos(a) * 0.40, -0.38, sin(a) * 0.40))
	# Dark hollow eyes + mouth.
	for side in [-1.0, 1.0]:
		_add(root, _sphere(0.055), dark, Vector3(0.10 * side, 0.10, 0.26))
	_add(root, _sphere(0.045), dark, Vector3(0, -0.08, 0.29), Vector3.ZERO, Vector3(1, 1.4, 0.6))
	# Faint spectral shimmer.
	_add(root, _sphere(0.02), shimmer, Vector3(0.18, 0.30, 0.10))
	return root


## 5. Skeleton (Torso): ribcage bones + spine + glowing amulet.
static func build_skeleton_suit() -> Node3D:
	var root := Node3D.new()
	root.name = "SkeletonSuit"
	var bone := GraphicsPolish.pbr_preset(Color(0.90, 0.87, 0.80), "matte")
	var amulet := GraphicsPolish.glow(Color(0.30, 1.0, 0.45), 1.8)
	# Ribs: stacked tori across the chest.
	for i in range(4):
		var y := 0.12 - float(i) * 0.11
		var r := 0.185 - float(i) * 0.012
		_add(root, _torus(r - 0.025, r), bone, Vector3(0, y, 0.03))
	# Sternum + spine.
	_add(root, _box(0.045, 0.42, 0.03), bone, Vector3(0, -0.02, 0.20))
	_add(root, _box(0.04, 0.45, 0.04), bone, Vector3(0, -0.05, -0.02))
	# Collar bones.
	for side in [-1.0, 1.0]:
		_add(root, _box(0.16, 0.03, 0.03), bone, Vector3(0.11 * side, 0.20, 0.12), Vector3(0, 0, -10 * side))
	# Glowing amulet at the sternum.
	_add(root, _sphere(0.035), amulet, Vector3(0, 0.10, 0.22))
	return root


## 6. Werewolf (Head): furry ears + snout + brow.
static func build_werewolf_ears() -> Node3D:
	var root := Node3D.new()
	root.name = "WerewolfEars"
	var fur := GraphicsPolish.pbr_preset(Color(0.35, 0.28, 0.22), "matte")
	var inner := GraphicsPolish.pbr_preset(Color(0.75, 0.45, 0.40), "matte")
	var snout_mat := GraphicsPolish.pbr_preset(Color(0.42, 0.34, 0.26), "rubber")
	var nose := GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.05), "rubber")
	var eye_glow := GraphicsPolish.glow(Color(1.0, 0.65, 0.10), 1.6)
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.005, 0.10, 0.24), fur, Vector3(0.15 * side, 0.28, 0), Vector3(0, 0, -14 * side))
		_add(root, _cyl(0.003, 0.05, 0.12), inner, Vector3(0.145 * side, 0.27, 0.03), Vector3(0, 0, -14 * side))
		# Heavy brow over the eyes.
		_add(root, _box(0.12, 0.04, 0.05), fur, Vector3(0.09 * side, 0.10, 0.22), Vector3(0, 0, -8 * side))
		_add(root, _sphere(0.02), eye_glow, Vector3(0.09 * side, 0.07, 0.245))
	# Snout + nose.
	_add(root, _box(0.17, 0.11, 0.13), snout_mat, Vector3(0, -0.08, 0.25))
	_add(root, _sphere(0.035), nose, Vector3(0, -0.05, 0.32))
	return root


## 7. Devil (HeadTop): red horns with glowing tips + forehead gem.
static func build_devil_horns() -> Node3D:
	var root := Node3D.new()
	root.name = "DevilHorns"
	var red := GraphicsPolish.pbr(Color(0.65, 0.08, 0.10), 0.15, 0.5)
	var tip := GraphicsPolish.glow(Color(1.0, 0.30, 0.10), 2.0)
	var gem := GraphicsPolish.glow(Color(1.0, 0.15, 0.30), 1.8)
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.015, 0.07, 0.26), red, Vector3(0.15 * side, 0.12, 0), Vector3(0, 0, -38 * side))
		_add(root, _sphere(0.028), tip, Vector3(0.245 * side, 0.225, 0))
	# Forehead gem (Head center is 0.34 below HeadTop marker).
	_add(root, _sphere(0.03), gem, Vector3(0, -0.26, 0.20), Vector3.ZERO, Vector3(1, 1.3, 0.6))
	return root


## 8. Angel (HeadTop): floating gold glowing halo.
static func build_angel_halo() -> Node3D:
	var root := Node3D.new()
	root.name = "AngelHalo"
	var gold := GraphicsPolish.pbr(Color(0.95, 0.75, 0.25), 0.9, 0.25)
	var halo_glow := GraphicsPolish.glow(Color(1.0, 0.85, 0.40), 1.8)
	_add(root, _torus(0.13, 0.175), halo_glow, Vector3(0, 0.30, 0), Vector3(8, 0, 6))
	_add(root, _torus(0.145, 0.16), gold, Vector3(0, 0.30, 0.004), Vector3(8, 0, 6))
	# Sparkles.
	for i in range(3):
		var a := TAU * float(i) / 3.0 + 0.5
		_add(root, _sphere(0.018), halo_glow, Vector3(cos(a) * 0.155, 0.30 + sin(a) * 0.155 * 0.14, sin(a) * 0.155))
	return root


## 9. Pirate (Head): tricorn hat + skull emblem + eyepatch.
static func build_pirate_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "PirateHat"
	var black := GraphicsPolish.pbr_preset(Color(0.10, 0.08, 0.08), "matte")
	var gold := GraphicsPolish.pbr(Color(0.95, 0.75, 0.25), 0.9, 0.3)
	var white := GraphicsPolish.pbr_preset(Color(0.92, 0.92, 0.90), "matte")
	var glow_gold := GraphicsPolish.glow(Color(1.0, 0.80, 0.30), 1.4)
	# Tricorn: wide brim + crown.
	_add(root, _cyl(0.30, 0.30, 0.05), black, Vector3(0, 0.20, 0))
	_add(root, _cyl(0.17, 0.21, 0.16), black, Vector3(0, 0.30, 0))
	_add(root, _torus(0.185, 0.205), gold, Vector3(0, 0.235, 0))
	# Skull emblem on the crown front.
	_add(root, _sphere(0.05), white, Vector3(0, 0.30, 0.20))
	_add(root, _sphere(0.022), glow_gold, Vector3(-0.02, 0.31, 0.245))
	_add(root, _sphere(0.022), glow_gold, Vector3(0.02, 0.31, 0.245))
	# Eyepatch over the right eye + strap.
	_add(root, _sphere(0.05), black, Vector3(0.09, 0.02, 0.235), Vector3.ZERO, Vector3(1, 1, 0.35))
	_add(root, _box(0.34, 0.025, 0.02), black, Vector3(0, 0.08, 0.21))
	return root


## 10. Ninja (Head): dark hood + glowing eye slit.
static func build_ninja_hood() -> Node3D:
	var root := Node3D.new()
	root.name = "NinjaHood"
	var dark := GraphicsPolish.pbr_preset(Color(0.07, 0.07, 0.09), "matte")
	var slit := GraphicsPolish.glow(Color(1.0, 0.85, 0.20), 1.8)
	var wrap := GraphicsPolish.pbr_preset(Color(0.45, 0.08, 0.08), "matte")
	_add(root, _sphere(0.285), dark, Vector3(0, 0.01, -0.01))
	# Eye slit.
	_add(root, _box(0.22, 0.04, 0.03), slit, Vector3(0, 0.04, 0.265))
	# Head wrap band + knot.
	_add(root, _torus(0.26, 0.285), wrap, Vector3(0, -0.10, 0), Vector3(96, 0, 0))
	_add(root, _box(0.05, 0.12, 0.03), wrap, Vector3(0.24, -0.16, -0.12), Vector3(0, 0, 20))
	return root


## 11. Robot (Head): metal dome + antenna + glowing visor.
static func build_robot_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "RobotHelmet"
	var metal := GraphicsPolish.pbr_preset(Color(0.55, 0.58, 0.62), "metal")
	var dark := GraphicsPolish.pbr_preset(Color(0.12, 0.12, 0.14), "matte")
	var visor := GraphicsPolish.glow(Color(0.20, 0.90, 1.0), 2.0)
	var tip := GraphicsPolish.glow(Color(1.0, 0.20, 0.20), 2.0)
	_add(root, _sphere(0.30), metal, Vector3.ZERO)
	# Glowing visor band.
	_add(root, _box(0.36, 0.10, 0.04), visor, Vector3(0, 0.06, 0.255))
	_add(root, _box(0.40, 0.03, 0.03), dark, Vector3(0, 0.13, 0.26))
	_add(root, _box(0.40, 0.03, 0.03), dark, Vector3(0, -0.01, 0.26))
	# Antenna + tip light.
	_add(root, _cyl(0.012, 0.012, 0.22), metal, Vector3(0.14, 0.40, 0))
	_add(root, _sphere(0.03), tip, Vector3(0.14, 0.53, 0))
	# Ear discs.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.06, 0.06, 0.04), dark, Vector3(0.29 * side, 0.0, 0), Vector3(0, 0, 90))
	# Mouth grill.
	_add(root, _box(0.16, 0.05, 0.02), dark, Vector3(0, -0.14, 0.27))
	return root


## 12. Alien (Head): stalk eyes + antennae + green tint shell.
static func build_alien_antennae() -> Node3D:
	var root := Node3D.new()
	root.name = "AlienAntennae"
	var green := GraphicsPolish.pbr_preset(Color(0.35, 0.85, 0.40), "plastic")
	var tint := GraphicsPolish.pbr_preset(Color(0.40, 0.95, 0.45), "glass")
	var white := GraphicsPolish.pbr_preset(Color(0.95, 0.95, 0.95), "plastic")
	var pupil := GraphicsPolish.glow(Color(0.10, 0.60, 0.20), 1.6)
	# Green tint shell over the head.
	_add(root, _sphere(0.27), tint, Vector3.ZERO)
	# Stalk eyes.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.015, 0.02, 0.20), green, Vector3(0.12 * side, 0.34, 0.04), Vector3(-12, 0, -10 * side))
		_add(root, _sphere(0.055), white, Vector3(0.145 * side, 0.44, 0.06))
		_add(root, _sphere(0.025), pupil, Vector3(0.15 * side, 0.44, 0.11))
	# Rear antennae with glowing orbs.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.010, 0.014, 0.26), green, Vector3(0.10 * side, 0.36, -0.14), Vector3(28, 0, -16 * side))
		_add(root, _sphere(0.03), pupil, Vector3(0.15 * side, 0.48, -0.21))
	return root


## 13. Zombie (Torso): torn cloth strips + glowing wound.
static func build_zombie_tatters() -> Node3D:
	var root := Node3D.new()
	root.name = "ZombieTatters"
	var cloth := GraphicsPolish.pbr_preset(Color(0.42, 0.46, 0.36), "matte")
	var cloth2 := GraphicsPolish.pbr_preset(Color(0.35, 0.38, 0.45), "matte")
	var wound := GraphicsPolish.glow(Color(0.45, 1.0, 0.30), 1.7)
	var mats := [cloth, cloth2]
	var i := 0
	for sx in [-0.20, -0.07, 0.07, 0.20]:
		var m: Material = mats[i % 2]
		_add(root, _box(0.09, 0.38, 0.025), m, Vector3(sx, -0.12, 0.14), Vector3(4, 0, (i - 1.5) * 9.0))
		i += 1
	# Shoulder strips.
	for side in [-1.0, 1.0]:
		_add(root, _box(0.10, 0.30, 0.025), cloth2, Vector3(0.24 * side, 0.10, 0.02), Vector3(0, 0, -70 * side))
	# Glowing bite wound.
	_add(root, _sphere(0.04), wound, Vector3(-0.10, 0.02, 0.20), Vector3.ZERO, Vector3(1, 0.7, 0.5))
	return root


## 14. Mummy (Head): wrap bands around the head + torso strips.
static func build_mummy_wraps() -> Node3D:
	var root := Node3D.new()
	root.name = "MummyWraps"
	var wrap := GraphicsPolish.pbr_preset(Color(0.88, 0.84, 0.74), "matte")
	var shadow := GraphicsPolish.pbr_preset(Color(0.72, 0.68, 0.58), "matte")
	var eye_glow := GraphicsPolish.glow(Color(0.85, 0.95, 0.40), 1.2)
	# Bands around the head at varied tilts.
	var ys := [0.16, 0.07, -0.02, -0.11, -0.19]
	var tilts := [6.0, -8.0, 12.0, -5.0, 9.0]
	for i in range(ys.size()):
		_add(root, _torus(0.245, 0.275), wrap if i % 2 == 0 else shadow, Vector3(0, ys[i], 0), Vector3(90 + tilts[i], 0, 0))
	# Glowing eyes peeking through.
	for side in [-1.0, 1.0]:
		_add(root, _sphere(0.022), eye_glow, Vector3(0.08 * side, 0.03, 0.27))
	# Loose wrap ends hanging onto the torso (Head is 0.46 above Torso marker area).
	_add(root, _box(0.08, 0.35, 0.02), wrap, Vector3(0.14, -0.38, 0.16), Vector3(0, 0, 12))
	_add(root, _box(0.08, 0.28, 0.02), shadow, Vector3(-0.12, -0.34, 0.18), Vector3(0, 0, -10))
	return root


## 15. Scarecrow (Head): straw hat + stitched smile + patch.
static func build_scarecrow_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "ScarecrowHat"
	var straw := GraphicsPolish.pbr_preset(Color(0.85, 0.68, 0.32), "matte")
	var dark := GraphicsPolish.pbr_preset(Color(0.20, 0.12, 0.06), "matte")
	var patch := GraphicsPolish.pbr_preset(Color(0.65, 0.15, 0.15), "matte")
	var stitch := GraphicsPolish.glow(Color(1.0, 0.80, 0.30), 0.9)
	_add(root, _cyl(0.32, 0.32, 0.05), straw, Vector3(0, 0.17, 0))
	_add(root, _cyl(0.03, 0.24, 0.28), straw, Vector3(0, 0.33, 0))
	_add(root, _box(0.10, 0.07, 0.02), patch, Vector3(0.10, 0.36, 0.20), Vector3(0, 0, 15))
	# Straw tufts.
	for side in [-1.0, 1.0]:
		_add(root, _box(0.16, 0.03, 0.03), straw, Vector3(0.22 * side, 0.14, 0.05), Vector3(0, 0, -25 * side))
	# Stitched smile: zigzag stitches across the face.
	for i in range(4):
		var x := -0.09 + float(i) * 0.06
		_add(root, _box(0.025, 0.055, 0.015), dark, Vector3(x, -0.13 + (0.02 if i % 2 == 0 else -0.02), 0.265), Vector3(0, 0, 20 * (1 if i % 2 == 0 else -1)))
	_add(root, _sphere(0.018), stitch, Vector3(0, -0.10, 0.28))
	return root


## 16. Plague Doctor (Head): beaked mask + glowing lenses + hat.
static func build_plague_doctor() -> Node3D:
	var root := Node3D.new()
	root.name = "PlagueDoctor"
	var leather := GraphicsPolish.pbr_preset(Color(0.16, 0.13, 0.12), "matte")
	var black := GraphicsPolish.pbr_preset(Color(0.06, 0.06, 0.07), "matte")
	var lens := GraphicsPolish.glow(Color(1.0, 0.70, 0.20), 1.8)
	# Mask + long beak.
	_add(root, _box(0.22, 0.18, 0.12), leather, Vector3(0, -0.01, 0.20))
	_add(root, _cyl(0.012, 0.055, 0.30), leather, Vector3(0, -0.05, 0.38), Vector3(96, 0, 0))
	# Glowing round lenses.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.05, 0.05, 0.03), black, Vector3(0.085 * side, 0.06, 0.245), Vector3(90, 0, 0))
		_add(root, _sphere(0.032), lens, Vector3(0.085 * side, 0.06, 0.26), Vector3.ZERO, Vector3(1, 1, 0.5))
	# Wide-brim hat.
	_add(root, _cyl(0.28, 0.28, 0.04), black, Vector3(0, 0.30, 0))
	_add(root, _cyl(0.13, 0.15, 0.16), black, Vector3(0, 0.40, 0))
	return root


## 17. Jester (HeadTop): 3-point hat with jingling glow bells.
static func build_jester_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "JesterHat"
	var purple := GraphicsPolish.pbr_preset(Color(0.45, 0.15, 0.65), "matte")
	var red := GraphicsPolish.pbr_preset(Color(0.75, 0.12, 0.18), "matte")
	var green := GraphicsPolish.pbr_preset(Color(0.15, 0.55, 0.25), "matte")
	var bell := GraphicsPolish.glow(Color(1.0, 0.80, 0.25), 2.0)
	_add(root, _torus(0.20, 0.235), purple, Vector3(0, 0.02, 0))
	# Three floppy points.
	_add(root, _cyl(0.01, 0.09, 0.34), purple, Vector3(0, 0.22, 0), Vector3(0, 0, 0))
	_add(root, _cyl(0.01, 0.09, 0.32), red, Vector3(-0.20, 0.16, 0), Vector3(0, 0, 38))
	_add(root, _cyl(0.01, 0.09, 0.32), green, Vector3(0.20, 0.16, 0), Vector3(0, 0, -38))
	# Jingling bells.
	_add(root, _sphere(0.035), bell, Vector3(0, 0.41, 0))
	_add(root, _sphere(0.035), bell, Vector3(-0.325, 0.28, 0))
	_add(root, _sphere(0.035), bell, Vector3(0.325, 0.28, 0))
	return root


## 18. Knight (Head): steel helm + visor slit + red plume.
static func build_knight_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "KnightHelmet"
	var steel := GraphicsPolish.pbr_preset(Color(0.62, 0.64, 0.68), "metal")
	var dark := GraphicsPolish.pbr_preset(Color(0.05, 0.05, 0.06), "matte")
	var plume_mat := GraphicsPolish.pbr_preset(Color(0.75, 0.10, 0.12), "matte")
	var plume_glow := GraphicsPolish.glow(Color(1.0, 0.25, 0.20), 1.2)
	_add(root, _cyl(0.235, 0.26, 0.46), steel, Vector3(0, 0.02, 0))
	_add(root, _sphere(0.235), steel, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	# Visor slit.
	_add(root, _box(0.22, 0.035, 0.03), dark, Vector3(0, 0.07, 0.245))
	# Breath holes.
	for i in range(3):
		_add(root, _sphere(0.015), dark, Vector3(-0.05 + float(i) * 0.05, -0.08, 0.245))
	# Plume fin + glowing tip.
	_add(root, _box(0.05, 0.22, 0.14), plume_mat, Vector3(0, 0.42, -0.02))
	_add(root, _sphere(0.03), plume_glow, Vector3(0, 0.54, -0.02))
	return root


## 19. Astronaut (Head): glass dome + neck ring + glow strip.
static func build_astronaut_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "AstronautHelmet"
	var glass := GraphicsPolish.pbr_preset(Color(0.75, 0.88, 1.0), "glass")
	var white := GraphicsPolish.pbr_preset(Color(0.92, 0.92, 0.94), "plastic")
	var strip := GraphicsPolish.glow(Color(0.40, 0.85, 1.0), 1.8)
	_add(root, _sphere(0.32), glass, Vector3.ZERO)
	# Neck ring.
	_add(root, _torus(0.20, 0.26), white, Vector3(0, -0.20, 0))
	# Backpack hint behind the neck.
	_add(root, _box(0.30, 0.24, 0.10), white, Vector3(0, -0.28, -0.22))
	# Glowing comm strip + side lamp.
	_add(root, _box(0.06, 0.16, 0.03), strip, Vector3(-0.26, 0.02, 0.14), Vector3(0, -30, 0))
	_add(root, _sphere(0.025), strip, Vector3(0.28, 0.10, 0.10))
	# Antenna nub.
	_add(root, _cyl(0.015, 0.015, 0.10), white, Vector3(-0.14, 0.36, -0.10))
	return root


## 20. Deep-Sea Diver (Head): brass helmet + portholes + glow lamp.
static func build_diver_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "DiverHelmet"
	var brass := GraphicsPolish.pbr(Color(0.72, 0.52, 0.20), 0.9, 0.35)
	var dark := GraphicsPolish.pbr_preset(Color(0.05, 0.08, 0.10), "matte")
	var lamp := GraphicsPolish.glow(Color(1.0, 0.90, 0.55), 2.2)
	_add(root, _sphere(0.30), brass, Vector3.ZERO)
	# Front porthole + side portholes.
	_add(root, _cyl(0.075, 0.075, 0.04), dark, Vector3(0, 0.04, 0.285), Vector3(90, 0, 0))
	_add(root, _torus(0.075, 0.095), brass, Vector3(0, 0.04, 0.29))
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.06, 0.06, 0.04), dark, Vector3(0.285 * side, 0.0, 0.02), Vector3(0, 0, 90))
	# Top valve + wheel.
	_add(root, _cyl(0.03, 0.04, 0.08), brass, Vector3(0, 0.33, 0))
	_add(root, _torus(0.045, 0.06), brass, Vector3(0, 0.38, 0), Vector3(90, 0, 0))
	# Glowing forehead lamp.
	_add(root, _sphere(0.035), lamp, Vector3(0, 0.16, 0.285))
	return root


## 21. Pharaoh (Head): striped nemes headdress + glowing cobra.
static func build_pharaoh_headdress() -> Node3D:
	var root := Node3D.new()
	root.name = "PharaohHeaddress"
	var gold := GraphicsPolish.pbr(Color(0.90, 0.68, 0.20), 0.85, 0.3)
	var blue := GraphicsPolish.pbr_preset(Color(0.10, 0.20, 0.55), "matte")
	var cobra := GraphicsPolish.glow(Color(1.0, 0.75, 0.20), 2.0)
	# Skull cap.
	_add(root, _sphere(0.27), blue, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
	# Striped side flaps (nemes): alternating gold/blue segments.
	for side in [-1.0, 1.0]:
		for i in range(4):
			var mat: Material = gold if i % 2 == 0 else blue
			_add(root, _box(0.06, 0.11, 0.05), mat, Vector3(0.26 * side, 0.02 - float(i) * 0.105, 0.06), Vector3(0, 0, -6 * side))
	# Back flap.
	for i in range(4):
		var mat: Material = gold if i % 2 == 0 else blue
		_add(root, _box(0.30, 0.11, 0.05), mat, Vector3(0, 0.02 - float(i) * 0.105, -0.24))
	# Forehead band + glowing cobra.
	_add(root, _torus(0.24, 0.265), gold, Vector3(0, 0.10, 0), Vector3(90, 0, 0))
	_add(root, _cyl(0.008, 0.03, 0.10), cobra, Vector3(0, 0.22, 0.25), Vector3(70, 0, 0))
	_add(root, _sphere(0.022), cobra, Vector3(0, 0.26, 0.27))
	return root


## 22. Viking (HeadTop): horned helm.
static func build_viking_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "VikingHelmet"
	var steel := GraphicsPolish.pbr_preset(Color(0.60, 0.62, 0.66), "metal")
	var horn_mat := GraphicsPolish.pbr_preset(Color(0.88, 0.84, 0.72), "matte")
	var glow := GraphicsPolish.glow(Color(0.60, 0.85, 1.0), 1.2)
	# Dome (head center is 0.34 below HeadTop marker).
	_add(root, _sphere(0.26), steel, Vector3(0, -0.28, 0), Vector3.ZERO, Vector3(1, 0.75, 1))
	# Horns.
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.012, 0.06, 0.28), horn_mat, Vector3(0.26 * side, -0.18, 0), Vector3(0, 0, -55 * side))
		_add(root, _sphere(0.018), glow, Vector3(0.375 * side, -0.06, 0))
	# Nose guard.
	_add(root, _box(0.045, 0.20, 0.03), steel, Vector3(0, -0.40, 0.235))
	# Brow band.
	_add(root, _torus(0.245, 0.265), steel, Vector3(0, -0.28, 0), Vector3(90, 0, 0))
	return root


## 23. Samurai (Head): kabuto + glowing crest + side guards.
static func build_samurai_helmet() -> Node3D:
	var root := Node3D.new()
	root.name = "SamuraiHelmet"
	var dark_steel := GraphicsPolish.pbr(Color(0.18, 0.16, 0.20), 0.85, 0.35)
	var gold := GraphicsPolish.pbr(Color(0.90, 0.68, 0.20), 0.85, 0.3)
	var crest := GraphicsPolish.glow(Color(1.0, 0.80, 0.30), 1.8)
	_add(root, _sphere(0.28), dark_steel, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
	# Glowing crescent crest.
	_add(root, _torus(0.07, 0.10), crest, Vector3(0, 0.30, 0.10), Vector3(90, 0, 0), Vector3(1, 1, 0.5))
	_add(root, _box(0.05, 0.10, 0.04), gold, Vector3(0, 0.22, 0.10))
	# Side guards (fukigaeshi).
	for side in [-1.0, 1.0]:
		_add(root, _box(0.04, 0.22, 0.16), dark_steel, Vector3(0.27 * side, -0.02, 0.0))
		_add(root, _box(0.02, 0.10, 0.10), gold, Vector3(0.295 * side, 0.02, 0.0))
	# Neck guard at the back.
	_add(root, _box(0.34, 0.18, 0.04), dark_steel, Vector3(0, -0.18, -0.24), Vector3(14, 0, 0))
	return root


## 24. Clown (Head): rainbow afro + glowing red nose.
static func build_clown_wig() -> Node3D:
	var root := Node3D.new()
	root.name = "ClownWig"
	var nose := GraphicsPolish.glow(Color(1.0, 0.12, 0.12), 2.0)
	var colors := [
		Color(1.0, 0.20, 0.20), Color(1.0, 0.55, 0.10), Color(1.0, 0.90, 0.20),
		Color(0.25, 0.80, 0.30), Color(0.25, 0.55, 1.0), Color(0.65, 0.30, 1.0),
	]
	var spots := [
		Vector3(0, 0.30, 0), Vector3(-0.18, 0.22, 0.10), Vector3(0.18, 0.22, 0.10),
		Vector3(-0.14, 0.24, -0.14), Vector3(0.14, 0.24, -0.14), Vector3(0, 0.20, -0.20),
	]
	for i in range(spots.size()):
		var mat := GraphicsPolish.pbr_preset(colors[i], "matte")
		_add(root, _sphere(0.13), mat, spots[i])
	# Big glowing red nose on the Face.
	_add(root, _sphere(0.05), nose, Vector3(0, -0.03, 0.30))
	return root


## 25. Cat (Head): ears + inner ears + whiskers + pink nose.
static func build_cat_ears() -> Node3D:
	var root := Node3D.new()
	root.name = "CatEars"
	var fur := GraphicsPolish.pbr_preset(Color(0.30, 0.30, 0.34), "matte")
	var pink := GraphicsPolish.pbr_preset(Color(1.0, 0.60, 0.65), "matte")
	var whisker_mat := GraphicsPolish.pbr_preset(Color(0.95, 0.95, 0.95), "matte")
	var nose_glow := GraphicsPolish.glow(Color(1.0, 0.45, 0.55), 1.4)
	for side in [-1.0, 1.0]:
		_add(root, _cyl(0.008, 0.10, 0.20), fur, Vector3(0.14 * side, 0.30, 0), Vector3(0, 0, -12 * side))
		_add(root, _cyl(0.004, 0.05, 0.10), pink, Vector3(0.135 * side, 0.29, 0.035), Vector3(0, 0, -12 * side))
		# Whiskers.
		for w in range(3):
			var y := 0.02 - float(w) * 0.035
			_add(root, _cyl(0.003, 0.003, 0.16), whisker_mat, Vector3(0.20 * side, y - 0.06, 0.24), Vector3(0, 0, 90 + (w - 1) * 10.0))
	# Pink nose.
	_add(root, _sphere(0.025), nose_glow, Vector3(0, -0.05, 0.275), Vector3.ZERO, Vector3(1.2, 0.8, 0.8))
	return root


## 26. Bat (Back): leather wings with glowing membrane accents.
static func build_bat_wings() -> Node3D:
	var root := Node3D.new()
	root.name = "BatWings"
	var leather := GraphicsPolish.pbr_preset(Color(0.22, 0.12, 0.30), "matte")
	var membrane := GraphicsPolish.glow(Color(0.65, 0.25, 1.0), 0.9)
	var bone := GraphicsPolish.pbr_preset(Color(0.75, 0.70, 0.60), "matte")
	for side in [-1.0, 1.0]:
		# Wing blade.
		_add(root, _box(0.52, 0.36, 0.03), leather, Vector3(0.34 * side, 0.14, -0.08), Vector3(0, -18 * side, -16 * side))
		# Glowing membrane inlay.
		_add(root, _box(0.40, 0.24, 0.015), membrane, Vector3(0.34 * side, 0.13, -0.06), Vector3(0, -18 * side, -16 * side))
		# Finger struts.
		_add(root, _cyl(0.012, 0.012, 0.40), bone, Vector3(0.34 * side, 0.02, -0.07), Vector3(0, -18 * side, -100 * side))
		# Claw tip glow.
		_add(root, _sphere(0.025), membrane, Vector3(0.58 * side, 0.24, -0.14))
	# Shoulder mount.
	_add(root, _box(0.20, 0.10, 0.08), leather, Vector3(0, 0.02, -0.06))
	return root


## 27. Spider Rider (Back): big spider with glowing eyes.
static func build_spider_pack() -> Node3D:
	var root := Node3D.new()
	root.name = "SpiderPack"
	var chitin := GraphicsPolish.pbr_preset(Color(0.08, 0.06, 0.08), "matte")
	var eye_glow := GraphicsPolish.glow(Color(1.0, 0.15, 0.10), 2.2)
	# Body + head (spider faces away from the avatar, -z).
	_add(root, _sphere(0.18), chitin, Vector3(0, 0.12, -0.16))
	_add(root, _sphere(0.10), chitin, Vector3(0, 0.06, -0.32))
	# Glowing eyes on the spider's head.
	for ex in [-0.045, 0.045]:
		_add(root, _sphere(0.028), eye_glow, Vector3(ex, 0.09, -0.40))
	# Eight legs.
	var leg_z := [-0.06, -0.14, -0.22, -0.28]
	for side in [-1.0, 1.0]:
		for i in range(4):
			var z: float = leg_z[i]
			_add(root, _cyl(0.014, 0.008, 0.36), chitin, Vector3(0.24 * side, 0.02, z), Vector3(0, 0, -62 * side))
			_add(root, _sphere(0.016), eye_glow, Vector3(0.40 * side, -0.12, z))
	# Back stripes.
	for i in range(3):
		_add(root, _box(0.05, 0.02, 0.20), eye_glow, Vector3(0, 0.28 - float(i) * 0.05, -0.14))
	return root


## 28. Candy Corn (HeadTop): stacked candy-corn cone hat.
static func build_candycorn_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "CandyCornHat"
	var orange := GraphicsPolish.pbr_preset(Color(1.0, 0.55, 0.10), "plastic")
	var yellow := GraphicsPolish.pbr_preset(Color(1.0, 0.85, 0.25), "plastic")
	var white := GraphicsPolish.pbr_preset(Color(0.98, 0.96, 0.90), "plastic")
	var tip_glow := GraphicsPolish.glow(Color(1.0, 0.90, 0.50), 1.6)
	_add(root, _cyl(0.16, 0.20, 0.16), orange, Vector3(0, 0.10, 0))
	_add(root, _cyl(0.12, 0.16, 0.14), yellow, Vector3(0, 0.25, 0))
	_add(root, _cyl(0.005, 0.12, 0.16), white, Vector3(0, 0.40, 0))
	_add(root, _sphere(0.025), tip_glow, Vector3(0, 0.49, 0))
	# Brim.
	_add(root, _cyl(0.24, 0.24, 0.03), white, Vector3(0, 0.015, 0))
	return root


## 29. Haunted Top Hat (HeadTop): black top hat + purple glow band.
static func build_top_hat() -> Node3D:
	var root := Node3D.new()
	root.name = "HauntedTopHat"
	var black := GraphicsPolish.pbr_preset(Color(0.07, 0.06, 0.08), "matte")
	var band := GraphicsPolish.glow(Color(0.60, 0.20, 1.0), 1.8)
	var buckle := GraphicsPolish.pbr(Color(0.95, 0.75, 0.25), 0.9, 0.3)
	_add(root, _cyl(0.30, 0.30, 0.04), black, Vector3(0, 0.02, 0))
	_add(root, _cyl(0.155, 0.165, 0.30), black, Vector3(0, 0.19, 0))
	_add(root, _cyl(0.165, 0.165, 0.015), black, Vector3(0, 0.345, 0))
	# Haunted purple glow band + gold buckle.
	_add(root, _torus(0.158, 0.185), band, Vector3(0, 0.09, 0))
	_add(root, _box(0.06, 0.06, 0.02), buckle, Vector3(0, 0.09, 0.18))
	# Wisp orb floating beside the hat.
	_add(root, _sphere(0.03), band, Vector3(0.24, 0.30, 0.05))
	return root


## 30. Grim Reaper (Head): dark hood + glowing eyes.
static func build_reaper_hood() -> Node3D:
	var root := Node3D.new()
	root.name = "ReaperHood"
	var shroud := GraphicsPolish.pbr_preset(Color(0.06, 0.06, 0.08), "matte")
	var darkness := GraphicsPolish.pbr_preset(Color(0.0, 0.0, 0.0), "matte")
	var eyes := GraphicsPolish.glow(Color(0.30, 1.0, 0.85), 2.4)
	# Hood shell + pointed peak.
	_add(root, _sphere(0.30), shroud, Vector3(0, 0.02, -0.02))
	_add(root, _cyl(0.005, 0.12, 0.22), shroud, Vector3(0, 0.30, -0.06), Vector3(-14, 0, 0))
	# Dark face void.
	_add(root, _sphere(0.22), darkness, Vector3(0, 0.0, 0.06), Vector3.ZERO, Vector3(1, 1, 0.8))
	# Burning eyes.
	for side in [-1.0, 1.0]:
		_add(root, _sphere(0.035), eyes, Vector3(0.085 * side, 0.04, 0.225))
	# Tattered shroud skirt.
	_add(root, _cyl(0.16, 0.36, 0.34), shroud, Vector3(0, -0.30, -0.02))
	for i in range(4):
		var a := TAU * float(i) / 4.0 + 0.4
		_add(root, _box(0.09, 0.20, 0.02), shroud, Vector3(cos(a) * 0.30, -0.44, sin(a) * 0.30 - 0.02), Vector3(0, 0, (i - 1.5) * 12.0))
	return root


# ---------------------------------------------------------------- catalog ---

static func all_costumes() -> Array:
	return [
		{"id": "witch_hat", "name": "Witch Hat", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_witch_hat")},
		{"id": "vampire_cape", "name": "Vampire", "anchor": "Torso", "build": Callable(HalloweenCostumes, "build_vampire_cape")},
		{"id": "pumpkin_head", "name": "Pumpkin Head", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_pumpkin_head")},
		{"id": "ghost_sheet", "name": "Ghost", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_ghost_sheet")},
		{"id": "skeleton_suit", "name": "Skeleton", "anchor": "Torso", "build": Callable(HalloweenCostumes, "build_skeleton_suit")},
		{"id": "werewolf_ears", "name": "Werewolf", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_werewolf_ears")},
		{"id": "devil_horns", "name": "Devil", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_devil_horns")},
		{"id": "angel_halo", "name": "Angel", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_angel_halo")},
		{"id": "pirate_hat", "name": "Pirate", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_pirate_hat")},
		{"id": "ninja_hood", "name": "Ninja", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_ninja_hood")},
		{"id": "robot_helmet", "name": "Robot", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_robot_helmet")},
		{"id": "alien_antennae", "name": "Alien", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_alien_antennae")},
		{"id": "zombie_tatters", "name": "Zombie", "anchor": "Torso", "build": Callable(HalloweenCostumes, "build_zombie_tatters")},
		{"id": "mummy_wraps", "name": "Mummy", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_mummy_wraps")},
		{"id": "scarecrow_hat", "name": "Scarecrow", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_scarecrow_hat")},
		{"id": "plague_doctor", "name": "Plague Doctor", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_plague_doctor")},
		{"id": "jester_hat", "name": "Jester", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_jester_hat")},
		{"id": "knight_helmet", "name": "Knight", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_knight_helmet")},
		{"id": "astronaut_helmet", "name": "Astronaut", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_astronaut_helmet")},
		{"id": "diver_helmet", "name": "Deep-Sea Diver", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_diver_helmet")},
		{"id": "pharaoh_headdress", "name": "Pharaoh", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_pharaoh_headdress")},
		{"id": "viking_helmet", "name": "Viking", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_viking_helmet")},
		{"id": "samurai_helmet", "name": "Samurai", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_samurai_helmet")},
		{"id": "clown_wig", "name": "Clown", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_clown_wig")},
		{"id": "cat_ears", "name": "Cat", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_cat_ears")},
		{"id": "bat_wings", "name": "Bat", "anchor": "Back", "build": Callable(HalloweenCostumes, "build_bat_wings")},
		{"id": "spider_pack", "name": "Spider Rider", "anchor": "Back", "build": Callable(HalloweenCostumes, "build_spider_pack")},
		{"id": "candycorn_hat", "name": "Candy Corn", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_candycorn_hat")},
		{"id": "top_hat", "name": "Haunted Top Hat", "anchor": "HeadTop", "build": Callable(HalloweenCostumes, "build_top_hat")},
		{"id": "reaper_hood", "name": "Grim Reaper", "anchor": "Head", "build": Callable(HalloweenCostumes, "build_reaper_hood")},
	]
