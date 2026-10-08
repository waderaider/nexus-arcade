## ArtKit — v0.9.0 ART + GAMEPLAY shared helper for game scripts (scripts/games/).
##
## Two jobs:
## 1. Guarded wrappers around the shared-system API contract (JuiceFX, Haptics,
##    AudioKit, PassthroughFX). The systems land in parallel; these wrappers call
##    the EXACT contract names via call() so game scripts parse and run cleanly
##    whether or not the autoload is present yet. All no-op safely when missing.
## 2. Pure-tween juice (BACK-ease pops, squash-stretch, anticipation, banking,
##    arcs) and animated-model helpers (Quaternius FBX AnimationPlayer control).
##
## Usage: ArtKit.pop(self, node) / ArtKit.hit_stop(self) / ArtKit.scorch(self, pos, normal)
class_name ArtKit extends RefCounted


# ---------------------------------------------------------------- autoload plumbing

## Return the autoload node by name, or null when absent.
static func svc(ctx: Node, svc_name: String) -> Node:
	if ctx == null:
		return null
	var tree := ctx.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(svc_name)


## Guarded dynamic call: svc.method(*args) when the autoload and method exist.
static func call_svc(ctx: Node, svc_name: String, method: String, args: Array = []) -> Variant:
	var s := svc(ctx, svc_name)
	if s == null or not s.has_method(method):
		return null
	return s.callv(method, args)


# ---------------------------------------------------------------- JuiceFX (contract)

static func hit_stop(ctx: Node, frames: int = 3) -> void:
	call_svc(ctx, "JuiceFX", "hit_stop", [frames])


static func squash_stretch(ctx: Node, node: Node3D) -> void:
	if call_svc(ctx, "JuiceFX", "squash_stretch", [node]) == null and is_instance_valid(node):
		squash_land(node)


static func scale_pop(ctx: Node, node: Node3D) -> void:
	if call_svc(ctx, "JuiceFX", "scale_pop", [node]) == null and is_instance_valid(node):
		pop(node)


static func combo_popup(ctx: Node, pos: Vector3, text: String) -> void:
	call_svc(ctx, "JuiceFX", "combo_popup", [pos, text])


# ---------------------------------------------------------------- Haptics (contract)

static func h_confirm(ctx: Node) -> void:
	call_svc(ctx, "Haptics", "confirm")


static func h_deny(ctx: Node) -> void:
	call_svc(ctx, "Haptics", "deny")


static func h_impact(ctx: Node, force01: float = 0.6) -> void:
	call_svc(ctx, "Haptics", "impact", [force01])


static func h_tick(ctx: Node) -> void:
	call_svc(ctx, "Haptics", "texture_tick")


static func h_sub_bass(ctx: Node, duration: float = 0.8) -> void:
	call_svc(ctx, "Haptics", "sub_bass", [duration])


static func h_heartbeat(ctx: Node) -> void:
	call_svc(ctx, "Haptics", "heartbeat")


static func h_sequence(ctx: Node, seq_name: String) -> void:
	call_svc(ctx, "Haptics", "play_sequence", [seq_name])


# ---------------------------------------------------------------- AudioKit (contract)

static func register_game_sfx(ctx: Node, sfx_map: Dictionary) -> void:
	call_svc(ctx, "AudioKit", "register_game_sfx", [sfx_map])


## Plays a registered game sfx; tries play_game_sfx, falls back to play_sfx.
static func game_sfx(ctx: Node, sfx_name: String, pitch: float = 1.0) -> void:
	if call_svc(ctx, "AudioKit", "play_game_sfx", [sfx_name]) != null:
		return
	call_svc(ctx, "AudioKit", "play_sfx", [sfx_name, pitch])


static func set_intensity(ctx: Node, level: int) -> void:
	call_svc(ctx, "AudioKit", "set_intensity", [clampi(level, 0, 2)])


static func sfx_3d(ctx: Node, sfx_name: String, pos: Vector3) -> void:
	call_svc(ctx, "AudioKit", "play_sfx_3d", [sfx_name, pos])


static func stinger(ctx: Node, kind: String) -> void:
	call_svc(ctx, "AudioKit", "play_stinger", [kind])


# ---------------------------------------------------------------- PassthroughFX (contract)

static func scorch(ctx: Node, pos: Vector3, normal: Vector3, size: float = 0.4) -> void:
	call_svc(ctx, "PassthroughFX", "scorch_decal", [pos, normal, size])


static func splash_ripple(ctx: Node, pos: Vector3) -> void:
	call_svc(ctx, "PassthroughFX", "splash_ripple", [pos])


# ---------------------------------------------------------------- pure-tween juice (no autoload needed)

## BACK-ease spawn/score pop: punch out to amount, settle back to base scale.
static func pop(node: Node3D, amount: float = 1.25, dur: float = 0.22) -> void:
	if not is_instance_valid(node):
		return
	var base: Vector3 = node.scale
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base * amount, dur * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", base, dur * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Landing/catch squash: flatten then spring back with overshoot.
static func squash_land(node: Node3D, dur: float = 0.28) -> void:
	if not is_instance_valid(node):
		return
	var base: Vector3 = node.scale
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(base.x * 1.25, base.y * 0.68, base.z * 1.25), dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "scale", base, dur * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Anticipation: quick dip opposite the action, then overshoot through, settle.
static func anticipate(node: Node3D, offset: Vector3, dur: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	var base: Vector3 = node.position
	var tw := node.create_tween()
	tw.tween_property(node, "position", base - offset, dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "position", base + offset * 0.35, dur * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", base, dur * 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Banking: ease rotation.z (roll) toward target — use for flight turns.
static func bank_to(node: Node3D, roll: float, dur: float = 0.35) -> void:
	if not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "rotation:z", roll, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Grow-in: spawn from near-zero with BACK overshoot (replaces flat appear).
static func grow_in(node: Node3D, dur: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	var base: Vector3 = node.scale
	node.scale = base * 0.01
	var tw := node.create_tween()
	tw.tween_property(node, "scale", base, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Arc a node to a target along a parabola (harvest coins, clue collect).
static func arc_to(node: Node3D, target: Vector3, height: float = 0.5, dur: float = 0.5) -> void:
	if not is_instance_valid(node):
		return
	var from: Vector3 = node.position
	var tw := node.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(node):
			return
		var p: Vector3 = from.lerp(target, t)
		p.y += sin(t * PI) * height
		node.position = p
	, 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Flash emissive on a MeshInstance3D (hit feedback), then restore.
static func hit_flash(mi: MeshInstance3D, dur: float = 0.12) -> void:
	if not is_instance_valid(mi):
		return
	var mat := mi.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	var dupe := mat.duplicate() as StandardMaterial3D
	mi.set_surface_override_material(0, dupe)
	dupe.emission_enabled = true
	dupe.emission = Color(1, 1, 1)
	dupe.emission_energy_multiplier = 2.5
	var tw := mi.create_tween()
	tw.tween_property(dupe, "emission_energy_multiplier", 0.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.set_surface_override_material(0, null)
	)


# ---------------------------------------------------------------- animated staged models

## First AnimationPlayer found under node (FBX imports nest one).
static func anim_player(node: Node) -> AnimationPlayer:
	if node == null or not is_instance_valid(node):
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var ap := anim_player(c)
		if ap != null:
			return ap
	return null


## Play the first animation whose name contains any keyword (case-insensitive).
## Returns the played animation name, "" when nothing matched.
static func play_anim(node: Node, keywords: Array, speed: float = 1.0) -> String:
	var ap := anim_player(node)
	if ap == null:
		return ""
	for anim_name in ap.get_animation_list():
		var low := anim_name.to_lower()
		for kw in keywords:
			if low.contains(str(kw).to_lower()):
				ap.speed_scale = speed
				ap.play(anim_name)
				return anim_name
	return ""


static func stop_anim(node: Node) -> void:
	var ap := anim_player(node)
	if ap != null:
		ap.stop()


# ---------------------------------------------------------------- model spawn + coherence

## Spawn a staged model; returns null when the file is missing (caller falls back).
static func spawn_model(path: String, parent: Node, pos: Vector3 = Vector3.ZERO, scl: float = 1.0) -> Node3D:
	var inst := ModelLib.spawn(path, parent, pos)
	if inst != null:
		inst.scale = Vector3.ONE * scl
	return inst


## Kill the default gray: give a StandardMaterial3D a real palette + PBR defaults.
static func de_gray(mat: StandardMaterial3D, albedo: Color, rough: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	if mat == null:
		return null
	mat.albedo_color = albedo
	mat.roughness = rough
	mat.metallic = metallic
	return mat


## Convenience: make a palette-locked StandardMaterial3D in one call.
static func mat(albedo: Color, rough: float = 0.85, metallic: float = 0.0, emission: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metallic
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.0
	return m


# ---------------------------------------------------------------- signature room helpers

## Largest RoomKit wall dict ({"position","size","normal"}), {} when none.
static func largest_wall(walls: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_area := 0.0
	for w in walls:
		if not (w is Dictionary):
			continue
		var size: Vector3 = w.get("size", Vector3.ZERO)
		var area := size.x * size.y
		if area > best_area:
			best_area = area
			best = w
	return best


## Point on a wall: u/v in 0..1 across width/height, out = offset along normal.
static func wall_point(wall: Dictionary, u: float = 0.5, v: float = 0.55, out: float = 0.02) -> Dictionary:
	if wall.is_empty():
		return {}
	var pos: Vector3 = wall.get("position", Vector3.ZERO)
	var size: Vector3 = wall.get("size", Vector3.ZERO)
	var normal: Vector3 = wall.get("normal", Vector3(0, 0, 1))
	var right := normal.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	var p := pos + right * (u - 0.5) * size.x + Vector3.UP * (v - 0.5) * size.y + normal * out
	return {"pos": p, "normal": normal}
