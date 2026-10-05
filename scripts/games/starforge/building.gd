class_name StarforgeBuilding
extends Node3D
## Starforge Command base/starbase: an armoured tower with a pulsing core.
## Destroying the enemy base wins the game; losing yours loses it.
## Ported from Unity BaseTower (in Ship.cs).

signal destroyed(building: StarforgeBuilding)

var side: int = StarforgeUnit.Side.PLAYER
var hp: float = 120.0
var max_hp: float = 120.0
var game: StarforgeGame = null

var _core_mat: StandardMaterial3D = null
var _t: float = 0.0


func setup(p_side: int, p_game: StarforgeGame) -> void:
	side = p_side
	game = p_game
	_build_visuals()


func _build_visuals() -> void:
	var c := Color(0.3, 0.6, 0.95) if side == StarforgeUnit.Side.PLAYER else Color(0.95, 0.35, 0.3)
	var tower := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.09
	cyl.height = 0.22
	tower.mesh = cyl
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = c
	tmat.metallic = 0.7
	tmat.roughness = 0.4
	tower.material_override = tmat
	tower.position = Vector3(0, 0.11, 0)
	add_child(tower)

	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.045
	sph.height = 0.09
	core.mesh = sph
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = c
	_core_mat.emission_enabled = true
	_core_mat.emission = c
	_core_mat.emission_energy_multiplier = 1.5
	core.material_override = _core_mat
	core.position = Vector3(0, 0.26, 0)
	add_child(core)


func is_alive() -> bool:
	return hp > 0.0


func take_damage(amount: float) -> void:
	if not is_alive():
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		destroyed.emit(self)
		queue_free()


func _process(delta: float) -> void:
	if _core_mat != null and is_alive():
		_t += delta
		_core_mat.emission_energy_multiplier = 1.2 + sin(_t * 4.0) * 0.5
