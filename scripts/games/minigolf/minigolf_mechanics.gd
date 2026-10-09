## MinigolfMechanics.gd - per-hole trick mechanics for NEXUS GREENS.
## Each build_* function adds visual nodes + a mechanic node to the hole.
## Mechanic nodes implement _mechanic_tick(hole, ball, delta) (duck-typed);
## MinigolfHole calls them each physics frame and they update colliders/effects.
extends RefCounted
class_name MinigolfMechanics


## Dispatch: build the extras for a hole spec.
static func build_extras(hole: MinigolfHole, extras_name: String) -> void:
	match extras_name:
		"potted_trouble":
			_build_potted_trouble(hole)
		"brass_rail":
			_build_brass_rail(hole)
		"koi_pond":
			_build_koi_pond(hole)
		"captains_loop":
			_build_captains_loop(hole)
		"gear_grinder":
			_build_gear_grinder(hole)
		"piston_alley":
			_build_piston_alley(hole)
		"copper_tube":
			_build_copper_tube(hole)
		"conveyor_cross":
			_build_conveyor_cross(hole)
		"steam_vent":
			_build_steam_vent(hole)
		"big_loop":
			_build_big_loop(hole)
		"trade_winds":
			_build_trade_winds(hole)
		"gull_gates":
			_build_gull_gates(hole)
		"rope_bridge":
			_build_rope_bridge(hole)
		"coral_maze":
			_build_coral_maze(hole)
		"storm_cell":
			_build_storm_cell(hole)
		"skyfall_finale":
			_build_skyfall_finale(hole)


# ---------------------------------------------------------------- helpers

static func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.30, 0.16)
	m.roughness = 0.8
	return m


static func _brass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.53, 0.25)
	m.metallic = 0.9
	m.roughness = 0.35
	return m


static func _add_aabb(hole: MinigolfHole, center: Vector3, size: Vector3) -> void:
	var aabbs: Array = hole.get_meta("all_aabbs", [])
	aabbs.append(AABB(center - size / 2.0, size))
	hole.set_meta("all_aabbs", aabbs)


# ---------------------------------------------------------------- hole 3: Potted Trouble

static func _build_potted_trouble(hole: MinigolfHole) -> void:
	# 3 terracotta pots mid-green with 40cm gaps; wobble + clink on graze.
	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.75, 0.35, 0.20)
	pot_mat.roughness = 0.7
	for i in range(3):
		var pot := MeshInstance3D.new()
		pot.name = "Pot%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.07
		cyl.height = 0.22
		pot.mesh = cyl
		pot.material_override = pot_mat
		var px := (i - 1) * 0.42
		pot.position = Vector3(px, 0.11, 0.2)
		hole.add_child(pot)
		_add_aabb(hole, Vector3(px, 0.11, 0.2), Vector3(0.18, 0.22, 0.18))
		# Wobble node: rotates briefly when the ball grazes.
		var wob := _WobbleNode.new()
		wob.target = pot
		hole.add_child(wob)
		hole.register_mechanic(wob)


# ---------------------------------------------------------------- hole 4: The Brass Rail

static func _build_brass_rail(hole: MinigolfHole) -> void:
	# U-shape: sand pit center with a 25cm brass bridge cutting the corner.
	var sand := {"kind": "sand", "pos": Vector3(0, 0, 0.3), "size": Vector3(0.9, 0.02, 0.9)}
	var hazards: Array = hole.get_meta("hazards", [])
	hazards.append(sand)
	hole.set_meta("hazards", hazards)
	# Sand visual.
	var sand_vis := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	sand_vis.mesh = quad
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.75, 0.45)
	sand_vis.material_override = smat
	sand_vis.rotation_degrees.x = -90
	sand_vis.position = Vector3(0, 0.006, 0.3)
	hole.add_child(sand_vis)
	# Brass bridge (25cm wide) over the pit.
	var bridge := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.25, 0.03, 1.0)
	bridge.mesh = bbox
	bridge.material_override = _brass_mat()
	bridge.position = Vector3(0, 0.015, 0.3)
	hole.add_child(bridge)
	hole.set_meta("bridge_rect", Rect2(-0.125, -0.2, 0.25, 1.0))


# ---------------------------------------------------------------- hole 5: Koi Pond

static func _build_koi_pond(hole: MinigolfHole) -> void:
	var water := {"kind": "water", "pos": Vector3(0, 0, 0.2), "size": Vector3(1.6, 0.02, 0.7)}
	var hazards: Array = hole.get_meta("hazards", [])
	hazards.append(water)
	hole.set_meta("hazards", hazards)
	var wvis := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 0.7)
	wvis.mesh = quad
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.2, 0.5, 0.9, 0.8)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wvis.material_override = wmat
	wvis.rotation_degrees.x = -90
	wvis.position = Vector3(0, 0.006, 0.2)
	hole.add_child(wvis)
	# Two stepping-stone bridges (narrow safe lines).
	for sx in [-0.35, 0.35]:
		var stone := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.22, 0.04, 0.8)
		stone.mesh = sbox
		var stmat := StandardMaterial3D.new()
		stmat.albedo_color = Color(0.55, 0.55, 0.58)
		stmat.roughness = 0.9
		stone.material_override = stmat
		stone.position = Vector3(sx, 0.02, 0.2)
		hole.add_child(stone)
	# Koi: 3 small fish that scatter when the ball passes.
	var koi := _KoiNode.new()
	hole.add_child(koi)
	hole.register_mechanic(koi)


# ---------------------------------------------------------------- hole 6: The Captain's Loop

static func _build_captains_loop(hole: MinigolfHole) -> void:
	# Miniature lighthouse center; banked 360° curve around it.
	var lh := MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.12
	lcyl.bottom_radius = 0.16
	lcyl.height = 0.8
	lh.mesh = lcyl
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.92, 0.88, 0.80)
	lh.material_override = lmat
	lh.position = Vector3(0, 0.4, 0)
	hole.add_child(lh)
	_add_aabb(hole, Vector3(0, 0.4, 0), Vector3(0.32, 0.8, 0.32))
	# Sweeping beam: rotating spotlight cone (visual only).
	var beam := _LighthouseBeam.new()
	beam.center = Vector3(0, 0.7, 0)
	hole.add_child(beam)
	hole.register_mechanic(beam)


# ---------------------------------------------------------------- hole 7: Gear Grinder

static func _build_gear_grinder(hole: MinigolfHole) -> void:
	for i in range(2):
		var gear := _GearNode.new()
		gear.radius = 0.28
		gear.speed = 0.9 * (1.0 if i == 0 else -1.0)
		gear.center = Vector3(-0.45 + i * 0.9, 0.06, 0.2)
		hole.add_child(gear)
		hole.register_mechanic(gear)


# ---------------------------------------------------------------- hole 8: Piston Alley

static func _build_piston_alley(hole: MinigolfHole) -> void:
	for i in range(3):
		var piston := _PistonNode.new()
		piston.center = Vector3(0, 0, -0.8 + i * 0.8)
		piston.phase = i * 2.1
		hole.add_child(piston)
		hole.register_mechanic(piston)


# ---------------------------------------------------------------- hole 9: The Copper Tube

static func _build_copper_tube(hole: MinigolfHole) -> void:
	# Transparent copper pipe: entry at tee side, corkscrew up and over,
	# exit near cup. Simplified: entry portal -> timed transit -> exit.
	var tube := _TubeNode.new()
	hole.add_child(tube)
	hole.register_mechanic(tube)


# ---------------------------------------------------------------- hole 10: Conveyor Cross

static func _build_conveyor_cross(hole: MinigolfHole) -> void:
	for i in range(2):
		var belt := _ConveyorNode.new()
		belt.center = Vector3(0, 0.01, -0.5 + i * 1.0)
		belt.direction = 1.0 if i == 0 else -1.0
		belt.length = 2.2
		hole.add_child(belt)
		hole.register_mechanic(belt)


# ---------------------------------------------------------------- hole 11: Steam Vent Saloon

static func _build_steam_vent(hole: MinigolfHole) -> void:
	for i in range(3):
		var vent := _VentNode.new()
		vent.center = Vector3(-0.5 + i * 0.5, 0, 0.3)
		vent.phase = i * 2.4
		hole.add_child(vent)
		hole.register_mechanic(vent)


# ---------------------------------------------------------------- hole 12: The Big Loop

static func _build_big_loop(hole: MinigolfHole) -> void:
	var loop := _LoopNode.new()
	hole.add_child(loop)
	hole.register_mechanic(loop)


# ---------------------------------------------------------------- hole 13: Trade Winds

static func _build_trade_winds(hole: MinigolfHole) -> void:
	var wind := _WindFieldNode.new()
	wind.wind_dir = Vector3(0.7, 0, 0.3).normalized()
	wind.wind_strength = 0.55
	hole.add_child(wind)
	hole.register_mechanic(wind)
	# Moonlit Hollow: crescent patch of 0.35x gravity.
	hole.set_meta("low_g_rect", Rect2(0.3, 0.3, 0.9, 0.9))
	hole.set_meta("low_g_factor", 0.35)
	var hollow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	hollow.mesh = quad
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.15, 0.25, 0.65, 0.55)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.emission_enabled = true
	hmat.emission = Color(0.2, 0.35, 0.9)
	hmat.emission_energy_multiplier = 0.5
	hollow.material_override = hmat
	hollow.rotation_degrees.x = -90
	hollow.position = Vector3(0.75, 0.008, 0.75)
	hole.add_child(hollow)


# ---------------------------------------------------------------- hole 14: Gull Gates

static func _build_gull_gates(hole: MinigolfHole) -> void:
	var gates := _GateNode.new()
	hole.add_child(gates)
	hole.register_mechanic(gates)


# ---------------------------------------------------------------- hole 15: The Rope Bridge

static func _build_rope_bridge(hole: MinigolfHole) -> void:
	# Narrow bridge over a cloud gap; gap = hazard.
	var gap := {"kind": "cloud", "pos": Vector3(0, 0, 0.4), "size": Vector3(1.1, 0.02, 2.6)}
	var hazards: Array = hole.get_meta("hazards", [])
	hazards.append(gap)
	hole.set_meta("hazards", hazards)
	var bridge := _BridgeNode.new()
	hole.add_child(bridge)
	hole.register_mechanic(bridge)


# ---------------------------------------------------------------- hole 16: Coral Maze

static func _build_coral_maze(hole: MinigolfHole) -> void:
	# Coral arches forming 3 lines; starfish gate on the middle line.
	for i in range(4):
		var arch := MeshInstance3D.new()
		var abox := BoxMesh.new()
		abox.size = Vector3(0.12, 0.35, 0.12)
		arch.mesh = abox
		var amat := StandardMaterial3D.new()
		amat.albedo_color = Color(1.0, 0.45, 0.35)
		amat.roughness = 0.8
		arch.material_override = amat
		arch.position = Vector3(-0.6 + i * 0.4, 0.17, -0.3)
		hole.add_child(arch)
		_add_aabb(hole, Vector3(-0.6 + i * 0.4, 0.17, -0.3), Vector3(0.12, 0.35, 0.12))
	var gate := _StarfishGate.new()
	gate.center = Vector3(0, 0.15, 0.4)
	hole.add_child(gate)
	hole.register_mechanic(gate)


# ---------------------------------------------------------------- hole 17: The Storm Cell

static func _build_storm_cell(hole: MinigolfHole) -> void:
	var storm := _StormNode.new()
	storm.center = Vector3(0, 0, 0.3)
	hole.add_child(storm)
	hole.register_mechanic(storm)


# ---------------------------------------------------------------- hole 18: The Skyfall Finale

static func _build_skyfall_finale(hole: MinigolfHole) -> void:
	var finale := _SkyfallNode.new()
	hole.add_child(finale)
	hole.register_mechanic(finale)


# ============================================================ mechanic nodes

## Base: wobbles a target mesh when the ball grazes it.
class _WobbleNode extends Node3D:
	var target: MeshInstance3D = null
	var _wob := 0.0

	func _mechanic_tick(_hole: MinigolfHole, ball: MinigolfBall, _delta: float) -> void:
		if target == null or ball == null:
			return
		if ball.global_position.distance_to(target.global_position) < 0.25 and ball.velocity.length() > 0.5:
			_wob = 1.0
			AudioKit.play_sfx_3d("mg_rail_click", target.global_position)
		if _wob > 0.0:
			_wob = maxf(0.0, _wob - _delta * 3.0)
			target.rotation.z = sin(_wob * 20.0) * 0.15 * _wob


## Koi fish that scatter when the ball rolls past.
class _KoiNode extends Node3D:
	var _fish: Array = []
	var _t := 0.0

	func _ready() -> void:
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(1.0, 0.55, 0.25)
		for i in range(3):
			var f := MeshInstance3D.new()
			var fbox := BoxMesh.new()
			fbox.size = Vector3(0.10, 0.03, 0.04)
			f.mesh = fbox
			f.material_override = fmat
			f.position = Vector3(-0.4 + i * 0.4, 0.02, 0.2)
			add_child(f)
			_fish.append({"node": f, "home": f.position, "scatter": 0.0})

	func _mechanic_tick(_hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		for fd in _fish:
			var n: MeshInstance3D = fd["node"]
			var home: Vector3 = fd["home"]
			if ball != null and ball.global_position.distance_to(n.global_position) < 0.5:
				fd["scatter"] = 1.0
			var s: float = fd["scatter"]
			if s > 0.0:
				fd["scatter"] = maxf(0.0, s - delta * 0.5)
				var away: Vector3 = (n.global_position - ball.global_position)
				away.y = 0.0
				n.position += away.normalized() * delta * 0.6
			else:
				n.position = n.position.lerp(home + Vector3(sin(_t * 1.5 + home.x * 5.0) * 0.1, 0, 0), delta * 2.0)
			n.rotation.y = sin(_t * 3.0 + home.x * 10.0) * 0.4


## Lighthouse beam: rotating visual sweep that briefly highlights the ideal line.
class _LighthouseBeam extends Node3D:
	var center := Vector3.ZERO
	var _t := 0.0
	var _beam: MeshInstance3D = null

	func _ready() -> void:
		_beam = MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(1.6, 0.02, 0.12)
		_beam.mesh = bbox
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 0.95, 0.7, 0.35)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.emission_enabled = true
		bmat.emission = Color(1.0, 0.9, 0.6)
		bmat.emission_energy_multiplier = 0.8
		_beam.material_override = bmat
		_beam.position = center + Vector3(0.8, 0, 0)
		add_child(_beam)

	func _mechanic_tick(_hole: MinigolfHole, _ball: MinigolfBall, delta: float) -> void:
		_t += delta
		rotation.y = _t * 0.5


## Counter-rotating gear that sweeps the green and knocks the ball.
class _GearNode extends Node3D:
	var radius := 0.28
	var speed := 0.9
	var center := Vector3.ZERO
	var _t := 0.0
	var _gear: MeshInstance3D = null

	func _ready() -> void:
		_gear = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.10
		cyl.radial_segments = 12
		_gear.mesh = cyl
		_gear.material_override = MinigolfMechanics._brass_mat()
		_gear.position = center
		add_child(_gear)
		# Teeth.
		for i in range(8):
			var tooth := MeshInstance3D.new()
			var tbox := BoxMesh.new()
			tbox.size = Vector3(0.08, 0.10, 0.08)
			tooth.mesh = tbox
			tooth.material_override = MinigolfMechanics._brass_mat()
			var a := i * TAU / 8.0
			tooth.position = center + Vector3(cos(a) * (radius + 0.03), 0, sin(a) * (radius + 0.03))
			tooth.rotation.y = -a
			add_child(tooth)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		_gear.rotation.y = _t * speed
		if ball == null or not ball.is_in_play:
			return
		# Gear teeth knock the ball: treat as a moving circular bumper.
		var bp := ball.global_position - hole.global_position
		var d := Vector2(bp.x - center.x, bp.z - center.z)
		if d.length() < radius + 0.06:
			var n := Vector3(d.x, 0, d.y).normalized()
			ball.velocity = n * 2.2 + Vector3(0, ball.velocity.y, 0)
			ball.global_position = hole.global_position + Vector3(center.x + n.x * (radius + 0.07), bp.y, center.z + n.z * (radius + 0.07))
			AudioKit.play_sfx_3d("mg_rail_click", ball.global_position)
			Haptics.play_sequence("rail_bounce", "right")


## Piston that punches up on a cycle; landing on top launches the ball.
class _PistonNode extends Node3D:
	var center := Vector3.ZERO
	var phase := 0.0
	var _t := 0.0
	var _head: MeshInstance3D = null

	func _ready() -> void:
		_head = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.14
		cyl.height = 0.06
		_head.mesh = cyl
		_head.material_override = MinigolfMechanics._brass_mat()
		add_child(_head)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		var cyc := fmod(_t * 0.8 + phase, TAU)
		var up := smoothstep(0.0, 0.6, sin(cyc)) * 0.22
		_head.position = center + Vector3(0, up, 0)
		# Shaft hazard when down (ball falls in = +1).
		if ball == null or not ball.is_in_play:
			return
		var bp := ball.global_position - hole.global_position
		var flat := Vector2(bp.x - center.x, bp.z - center.z).length()
		if flat < 0.15 and up < 0.05 and ball.global_position.y < hole.global_position.y + 0.05:
			ball.drop_at(hole.get_meta("drop_point", hole.tee_position()))
		elif flat < 0.16 and up > 0.15 and absf(ball.global_position.y - (hole.global_position.y + up)) < 0.06:
			# Launched off the piston top!
			ball.velocity.y = 2.4
			ball.velocity.x += randf_range(-0.5, 0.5)
			AudioKit.play_sfx_3d("mg_powerup_fire", ball.global_position)
			Haptics.play_sequence("jump_pad", "right")


## Copper tube: ball enters, rattles through, exits near cup.
class _TubeNode extends Node3D:
	var _transit := 0.0
	var _entry := Vector3(0, 0.1, -1.0)
	var _exit := Vector3(0, 0.1, 0.8)

	func _ready() -> void:
		# Transparent tube visual: torus arc (simplified as a curved pipe).
		var tube := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.28
		tor.outer_radius = 0.36
		tube.mesh = tor
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.8, 0.5, 0.25, 0.45)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.metallic = 0.7
		tube.material_override = tmat
		tube.position = Vector3(0, 0.45, 0)
		tube.rotation_degrees.x = 90
		add_child(tube)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		if ball == null:
			return
		if _transit > 0.0:
			_transit -= delta
			# Rattle the ball along the tube path.
			var k := 1.0 - _transit / 1.2
			ball.global_position = hole.global_position + _entry.lerp(_exit, k) + Vector3(0, sin(k * PI) * 0.35, 0)
			ball.velocity = Vector3.ZERO
			if _transit <= 0.0:
				ball.global_position = hole.global_position + _exit
				ball.velocity = Vector3(0, 0, 1.2)
				AudioKit.play_sfx_3d("mg_tee_pop", ball.global_position)
			return
		if not ball.is_in_play or ball.is_holed:
			return
		var bp := ball.global_position - hole.global_position
		if Vector2(bp.x - _entry.x, bp.z - _entry.z).length() < 0.12:
			_transit = 1.2
			ball.is_in_play = false  # scripted transit; re-enable on exit
			AudioKit.play_sfx_3d("mg_powerup_fire", ball.global_position)
		elif _transit <= 0.0 and not ball.is_in_play and ball.velocity == Vector3.ZERO:
			ball.is_in_play = true


## Conveyor belt: carries the ball sideways.
class _ConveyorNode extends Node3D:
	var center := Vector3.ZERO
	var direction := 1.0
	var length := 2.2
	var _belt: MeshInstance3D = null
	var _t := 0.0

	func _ready() -> void:
		_belt = MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(length, 0.03, 0.5)
		_belt.mesh = bbox
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.25, 0.25, 0.28)
		bmat.roughness = 0.6
		_belt.material_override = bmat
		_belt.position = center
		add_child(_belt)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		if ball == null or not ball.is_in_play:
			return
		var bp := ball.global_position - hole.global_position
		if absf(bp.x - center.x) < length / 2.0 and absf(bp.z - center.z) < 0.25:
			ball.velocity.x += direction * 1.8 * delta
			ball.set_meta("surface", "conveyor")


## Steam vent: timed puff pops the ball 15cm with lateral kick.
class _VentNode extends Node3D:
	var center := Vector3.ZERO
	var phase := 0.0
	var _t := 0.0

	func _ready() -> void:
		var grate := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.11
		cyl.bottom_radius = 0.11
		cyl.height = 0.02
		grate.mesh = cyl
		grate.material_override = MinigolfMechanics._brass_mat()
		grate.position = center + Vector3(0, 0.01, 0)
		add_child(grate)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		var cyc := fmod(_t * 0.5 + phase, 1.0)
		if cyc > 0.92 and ball != null and ball.is_in_play:
			var bp := ball.global_position - hole.global_position
			if Vector2(bp.x - center.x, bp.z - center.z).length() < 0.14:
				ball.velocity.y = 1.4  # ~15cm pop
				ball.velocity.x += randf_range(-0.6, 0.6)
				ball.velocity.z += randf_range(-0.6, 0.6)
				AudioKit.play_sfx_3d("mg_wind_gust", ball.global_position)
				Haptics.play_sequence("jump_pad", "right")


## Full vertical loop-the-loop (transparent tube).
class _LoopNode extends Node3D:
	var _in_loop := false
	var _loop_t := 0.0

	func _ready() -> void:
		var loop := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.32
		tor.outer_radius = 0.40
		loop.mesh = tor
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		loop.material_override = lmat
		loop.position = Vector3(0, 0.45, 0.4)
		add_child(loop)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		if ball == null:
			return
		if _in_loop:
			_loop_t += delta * ball.velocity.length() / 2.5
			var a := _loop_t * TAU
			var r := 0.36
			ball.global_position = hole.global_position + Vector3(0, 0.45 + sin(a) * r, 0.4 - cos(a) * r * 0.0 + (1.0 - cos(a)) * 0.0)
			# Simplified: circle in the YZ plane.
			ball.global_position = hole.global_position + Vector3(0, 0.45 - cos(a) * r, 0.4 + sin(a) * r)
			if _loop_t >= 1.0:
				_in_loop = false
				ball.velocity = Vector3(0, 0.5, 2.0)
				Haptics.play_sequence("trick_loop", "right")
			return
		if not ball.is_in_play or ball.is_holed:
			return
		var bp := ball.global_position - hole.global_position
		# Entry at the loop base: needs speed.
		if absf(bp.x) < 0.15 and absf(bp.z - 0.05) < 0.15:
			var spd := Vector2(ball.velocity.x, ball.velocity.z).length()
			if spd > 2.2:
				_in_loop = true
				_loop_t = 0.0
				AudioKit.play_sfx_3d("mg_powerup_fire", ball.global_position)
			elif spd > 0.3:
				# Too soft: rolls back.
				ball.velocity.z = -1.0


## Wind field with visible particles (Sky Reef).
class _WindFieldNode extends Node3D:
	var wind_dir := Vector3.RIGHT
	var wind_strength := 0.55
	var _parts: GPUParticles3D = null

	func _ready() -> void:
		_parts = GPUParticles3D.new()
		_parts.amount = 48
		_parts.lifetime = 2.5
		var pm := ParticleProcessMaterial.new()
		pm.direction = wind_dir
		pm.spread = 12.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.012
		pm.scale_max = 0.025
		pm.color = Color(1.0, 0.95, 0.8, 0.7)
		_parts.process_material = pm
		_parts.draw_pass_1 = SphereMesh.new()
		add_child(_parts)

	func _mechanic_tick(_hole: MinigolfHole, _ball: MinigolfBall, _delta: float) -> void:
		pass

	func wind_accel() -> Vector3:
		return wind_dir * wind_strength


## Teleporter gate pair (Gull Gates).
class _GateNode extends Node3D:
	var _gate_a := Vector3(-0.5, 0.1, -0.6)
	var _gate_b := Vector3(0.5, 0.1, 0.7)
	var _exit_dir := Vector3(0, 0, 1)
	var _cool := 0.0

	func _ready() -> void:
		for g in [_gate_a, _gate_b]:
			var arch := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.10
			tor.outer_radius = 0.16
			arch.mesh = tor
			var amat := StandardMaterial3D.new()
			amat.albedo_color = Color(1.0, 0.45, 0.35)
			amat.emission_enabled = true
			amat.emission = Color(1.0, 0.5, 0.4)
			amat.emission_energy_multiplier = 1.2
			arch.material_override = amat
			arch.position = g
			add_child(arch)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, _delta: float) -> void:
		if _cool > 0.0:
			_cool -= _delta
			return
		if ball == null or not ball.is_in_play or ball.is_holed:
			return
		var bp := ball.global_position - hole.global_position
		if Vector2(bp.x - _gate_a.x, bp.z - _gate_a.z).length() < 0.14:
			var spd := ball.velocity.length()
			ball.global_position = hole.global_position + _gate_b
			# Exit direction fixed; entry speed preserved.
			ball.velocity = _exit_dir * maxf(spd * 0.9, 0.8)
			ball.velocity.y = 0.0
			_cool = 1.0
			AudioKit.play_sfx_3d("mg_powerup_fire", ball.global_position)
			Haptics.play_sequence("teleport", "right")


## Swaying rope bridge over a cloud gap.
class _BridgeNode extends Node3D:
	var _bridge: MeshInstance3D = null
	var _t := 0.0
	var _sway := 0.0

	func _ready() -> void:
		_bridge = MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(0.30, 0.03, 3.0)
		_bridge.mesh = bbox
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.55, 0.40, 0.22)
		bmat.roughness = 0.85
		_bridge.material_override = bmat
		_bridge.position = Vector3(0, 0.02, 0.4)
		add_child(_bridge)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		# Sway: gentle base + extra when the player walks near.
		var player_near := 0.0
		_sway = lerpf(_sway, 0.5 + player_near, delta * 2.0)
		_bridge.rotation.z = sin(_t * 1.1) * 0.04 * _sway
		# Bridge walkable rect; off-bridge over the gap = cloud plunge.
		hole.set_meta("bridge_rect", Rect2(-0.15, -1.1, 0.30, 3.0))


## Spinning starfish gate (Coral Maze).
class _StarfishGate extends Node3D:
	var center := Vector3.ZERO
	var _t := 0.0
	var _arms: Array = []

	func _ready() -> void:
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.55, 0.30)
		for i in range(5):
			var arm := MeshInstance3D.new()
			var abox := BoxMesh.new()
			abox.size = Vector3(0.30, 0.10, 0.08)
			arm.mesh = abox
			arm.material_override = smat
			add_child(arm)
			_arms.append(arm)

	func _mechanic_tick(_hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		rotation.y = _t * 0.8
		for i in range(_arms.size()):
			var a: float = i * TAU / 5.0 + rotation.y
			(_arms[i] as MeshInstance3D).position = center + Vector3(cos(a) * 0.22, 0, sin(a) * 0.22)
			(_arms[i] as MeshInstance3D).rotation.y = -a
		# Ball collision with arms: simple radial push when overlapping.
		if ball != null and ball.is_in_play:
			var bp := ball.global_position - global_position
			for arm in _arms:
				var ap := (arm as MeshInstance3D).global_position
				if ball.global_position.distance_to(ap) < 0.12:
					var n := (ball.global_position - ap)
					n.y = 0.0
					ball.velocity = n.normalized() * 1.6
					AudioKit.play_sfx_3d("mg_rail_click", ball.global_position)


## Storm cell: heavy wind + periodic lightning gusts.
class _StormNode extends Node3D:
	var center := Vector3.ZERO
	var _t := 0.0
	var _gust := 0.0
	var _disc: MeshInstance3D = null

	func _ready() -> void:
		_disc = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.55
		cyl.height = 0.02
		_disc.mesh = cyl
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.3, 0.35, 0.5, 0.5)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.emission_enabled = true
		dmat.emission = Color(0.4, 0.5, 0.9)
		dmat.emission_energy_multiplier = 0.6
		_disc.material_override = dmat
		_disc.position = center + Vector3(0, 0.01, 0)
		add_child(_disc)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, delta: float) -> void:
		_t += delta
		_disc.rotation.y = _t * 2.0
		var cyc := fmod(_t * 0.25, 1.0)
		if cyc > 0.9 and _gust <= 0.0:
			_gust = 0.6
			AudioKit.play_sfx_3d("mg_wind_gust", hole.global_position + center)
		if _gust > 0.0:
			_gust -= delta
			if ball != null and ball.is_in_play:
				var bp := ball.global_position - (hole.global_position + center)
				bp.y = 0.0
				if bp.length() < 0.8:
					var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
					ball.velocity += dir * 2.2 * delta * 10.0


## Skyfall Finale: spiral ramp + jump pad legend line.
class _SkyfallNode extends Node3D:
	var _pad: MeshInstance3D = null

	func _ready() -> void:
		# Jump pad at the ramp end.
		_pad = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.18
		cyl.height = 0.05
		_pad.mesh = cyl
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(1.0, 0.8, 0.2)
		pmat.emission_enabled = true
		pmat.emission = Color(1.0, 0.75, 0.15)
		pmat.emission_energy_multiplier = 1.5
		_pad.material_override = pmat
		_pad.position = Vector3(0, 0.025, 1.4)
		add_child(_pad)

	func _mechanic_tick(hole: MinigolfHole, ball: MinigolfBall, _delta: float) -> void:
		if ball == null or not ball.is_in_play:
			return
		var bp := ball.global_position - hole.global_position
		if Vector2(bp.x, bp.z - 1.4).length() < 0.18 and absf(ball.velocity.z) > 0.5:
			# Legend line: launch toward the cup.
			var cup: Vector3 = hole.cup_position() - hole.global_position
			var dir := (cup - bp)
			dir.y = 0.0
			ball.velocity = dir.normalized() * 3.2 + Vector3(0, 1.8, 0)
			ball.set_meta("spring_airborne", true)
			AudioKit.play_sfx_3d("mg_powerup_fire", ball.global_position)
			Haptics.play_sequence("jump_pad", "right")
