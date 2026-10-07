## ModelLib - v0.7.0 shared static helper for spawning real 3D models.
##
## Centralizes loading of .glb/.gltf game assets (KayKit, Quaternius,
## Sketchfab, CraftPix packs under assets/models/) with a cache so each
## model file is only loaded once per session.
##
## Usage:
##   var goblin := ModelLib.spawn("res://assets/models/hw_zombie_defense/goblin.glb", self, pos)
## All funcs are headless-safe: missing files return null, never crash.
class_name ModelLib extends RefCounted

static var _cache: Dictionary = {}


## Load (and cache) a model file as PackedScene. Null when missing/invalid.
static func load_model(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path] as PackedScene
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps != null and ps.can_instantiate():
		_cache[path] = ps
		return ps
	return null


## Instantiate a model as a child of parent at local pos. Null on failure.
static func spawn(path: String, parent: Node, pos := Vector3.ZERO) -> Node3D:
	var ps := load_model(path)
	if ps == null or parent == null or not is_instance_valid(parent):
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	parent.add_child(inst)
	inst.position = pos
	return inst


## True when the model file exists and is loadable.
static func exists(path: String) -> bool:
	return load_model(path) != null


## Clear the cache (e.g. on hub return to free memory).
static func clear_cache() -> void:
	_cache.clear()
