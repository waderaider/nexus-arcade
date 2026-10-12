## TerraformSim.gd - the living ecosystem for TERRAFORM.
## Coarse 24x24 cellular sim ticked at 2Hz: vegetation spread, grazing
## herds, temperature drift, ice ages. Disasters are tools AND threats.
class_name TerraformSim
extends Node

const G := 24  # sim grid resolution
const TICK_HZ := 2.0
const MAX_ANIMALS := 28

var world: TerraformWorld
var fast_forward := false

var veg := PackedFloat32Array()      # 0..1 per cell
var temp := 0.55                     # global 0..1 (0.5 = temperate)
var epochs := 0
var epoch_t := 0.0
var sentient := false
var ice_age_survived := false
var ice_age_active := false

var animals: Array = []  # [{pos: Vector3, kind: String, hunger: float, age: float}]

var _tick_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _ice_t := 0.0


func setup(w: TerraformWorld) -> void:
	world = w
	_rng.randomize()
	veg.resize(G * G)
	veg.fill(0.0)


func cell_of(p: Vector3) -> int:
	var gx := clampi(int((p.x / TerraformWorld.RADIUS * 0.5 + 0.5) * G), 0, G - 1)
	var gz := clampi(int((p.z / TerraformWorld.RADIUS * 0.5 + 0.5) * G), 0, G - 1)
	return gz * G + gx


func cell_center(c: int) -> Vector3:
	var cx := float(c % G) / float(G - 1) * 2.0 - 1.0
	var cz := float(c / G) / float(G - 1) * 2.0 - 1.0
	var p := Vector3(cx * TerraformWorld.RADIUS, 0, cz * TerraformWorld.RADIUS)
	p.y = world.height_at(p)
	return p


func cell_habitable(c: int) -> bool:
	var p := cell_center(c)
	var h := p.y
	if h < TerraformWorld.WATER_LEVEL + 0.01:
		return false
	var b := world.biome_at(p)
	return b in [0, 1]  # grass or desert


func tick(dt: float) -> void:
	var rate := 12.0 if fast_forward else 1.0
	_tick_acc += dt * rate
	var step := 1.0 / TICK_HZ
	var n := 0
	while _tick_acc >= step and n < 40:
		_tick_acc -= step
		_sim_step(step)
		n += 1
	# Epoch clock: one epoch per 90 sim-seconds (7.5s in fast-forward).
	epoch_t += dt * rate
	if epoch_t >= 90.0:
		epoch_t = 0.0
		epochs += 1
		_maybe_ice_age()
	if not sentient and animals.size() >= 25 and epochs >= 2:
		sentient = true


func _sim_step(dt: float) -> void:
	# Vegetation growth + spread.
	var spread := PackedFloat32Array()
	spread.resize(G * G)
	for c in G * G:
		var v: float = veg[c]
		if v <= 0.01 and v < 0.4:
			# Colonize from neighbors.
			var nb := _neighbor_veg(c)
			if nb > 0.5 and cell_habitable(c) and _rng.randf() < 0.06 * dt * TICK_HZ:
				spread[c] = 0.05
		elif v > 0.0:
			var growth := 0.0
			if cell_habitable(c) and temp > 0.25:
				growth = 0.02 * v * (1.0 - v)
			if ice_age_active:
				growth -= 0.05 * v
			spread[c] = clampf(v + growth * dt * TICK_HZ, 0.0, 1.0)
	for c in G * G:
		if spread[c] > 0.0:
			veg[c] = spread[c]
	# Animals.
	for i in range(animals.size() - 1, -1, -1):
		var a: Dictionary = animals[i]
		a["age"] = float(a["age"]) + dt
		var p: Vector3 = a["pos"]
		# Wander.
		var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		if dir.length() > 0.01:
			p += dir.normalized() * 0.05 * dt * TICK_HZ
		var rr := Vector2(p.x, p.z).length()
		if rr > TerraformWorld.RADIUS * 0.92:
			p *= (TerraformWorld.RADIUS * 0.92) / rr
		p.y = world.height_at(p)
		a["pos"] = p
		# Graze.
		var c := cell_of(p)
		var eaten: float = veg[c]
		if eaten > 0.05:
			veg[c] = maxf(0.0, eaten - 0.25 * dt * TICK_HZ)
			a["hunger"] = 0.0
		else:
			a["hunger"] = float(a["hunger"]) + dt * 0.05
		# Reproduce / die.
		if float(a["hunger"]) > 1.0 or float(a["age"]) > 240.0:
			animals.remove_at(i)
		elif eaten > 0.5 and animals.size() < MAX_ANIMALS and _rng.randf() < 0.02 * dt * TICK_HZ:
			animals.append({"pos": p + Vector3(0.05, 0, 0.05), "kind": a["kind"],
				"hunger": 0.0, "age": 0.0})


func _neighbor_veg(c: int) -> float:
	var x := c % G
	var z := c / G
	var m := 0.0
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var nx: int = x + d[0]
		var nz: int = z + d[1]
		if nx >= 0 and nx < G and nz >= 0 and nz < G:
			m = maxf(m, veg[nz * G + nx])
	return m


func seed_species(p: Vector3, kind: String) -> bool:
	if animals.size() >= MAX_ANIMALS:
		return false
	var c := cell_of(p)
	if not cell_habitable(c):
		return false
	animals.append({"pos": p, "kind": kind, "hunger": 0.0, "age": 0.0})
	veg[c] = maxf(veg[c], 0.3)
	return true


func seed_flora(p: Vector3) -> bool:
	var c := cell_of(p)
	if not cell_habitable(c):
		return false
	veg[c] = minf(1.0, veg[c] + 0.4)
	return true


func disaster_meteor(p: Vector3) -> void:
	world.crater(p, 0.16, 0.12)
	var c0 := cell_of(p)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := c0 % G + dx
			var z := c0 / G + dz
			if x >= 0 and x < G and z >= 0 and z < G:
				veg[z * G + x] = 0.0
	for i in range(animals.size() - 1, -1, -1):
		var a: Dictionary = animals[i]
		if (a["pos"] as Vector3).distance_to(p) < 0.25:
			animals.remove_at(i)


func disaster_flood() -> void:
	for c in G * G:
		veg[c] *= 0.4


func disaster_volcano(p: Vector3) -> void:
	# Raise a cone and scorch it.
	for ring in range(1, 5):
		world.sculpt(p, 0.05 * ring, 0.02 * (5 - ring))
	world.paint_at(p, 0.14, 3)
	disaster_meteor(p)


func _maybe_ice_age() -> void:
	if ice_age_active:
		ice_age_active = false
		temp = 0.55
		ice_age_survived = true
	elif _rng.randf() < 0.35 and epochs >= 1:
		ice_age_active = true
		temp = 0.18
		_ice_t = 0.0


func veg_coverage() -> float:
	var s := 0.0
	for c in G * G:
		if veg[c] > 0.3:
			s += 1.0
	return s / float(G * G)
