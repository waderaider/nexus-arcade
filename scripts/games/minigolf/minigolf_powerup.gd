## MinigolfPowerup.gd - physical power-up tokens for NEXUS GREENS.
## Game Design §7: glowing charms on 8 holes; one held at a time; hand-grab /
## putter-touch to collect; trigger to activate; single use; no carrying
## between holes. Effects: spring-hop, cup-vacuum, sticky ball.
extends Node3D
class_name MinigolfPowerup

signal token_collected(token_kind: String)
signal activated(token_kind: String)

const KIND_SPRING := "spring"
const KIND_VACUUM := "vacuum"
const KIND_STICKY := "sticky"

const KIND_COLORS := {
	"spring": Color(1.0, 0.65, 0.20),  # amber
	"vacuum": Color(0.25, 0.45, 1.0),  # deep blue
	"sticky": Color(0.55, 0.85, 0.30),  # honey green
}

var kind := KIND_SPRING
var collected := false
var _charm: MeshInstance3D = null
var _t := 0.0
var _game = null  # MinigolfGame (untyped to avoid circular dependency)


static func spawn(parent: Node3D, game, token_kind: String, local_pos: Vector3) -> MinigolfPowerup:
	var p := MinigolfPowerup.new()
	p.kind = token_kind
	p._game = game
	p.position = local_pos
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	var col: Color = KIND_COLORS.get(kind, Color.WHITE)
	# Brass base pad.
	var pad := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.09
	pcyl.bottom_radius = 0.11
	pcyl.height = 0.03
	pad.mesh = pcyl
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.72, 0.53, 0.25)
	pmat.metallic = 0.9
	pmat.roughness = 0.35
	pad.material_override = pmat
	pad.position = Vector3(0, 0.015, 0)
	add_child(pad)
	# The charm: glowing octahedron floating at 1.2m (scaled for minigolf scale).
	_charm = MeshInstance3D.new()
	var oct := SphereMesh.new()
	oct.radial_segments = 4
	oct.rings = 2
	oct.radius = 0.04
	oct.height = 0.08
	_charm.mesh = oct
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = col
	cmat.emission_enabled = true
	cmat.emission = col
	cmat.emission_energy_multiplier = 2.0
	_charm.material_override = cmat
	_charm.position = Vector3(0, 0.55, 0)
	add_child(_charm)
	# Hum tone per effect (each has its own pitch).
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum"
	var pitch := 440.0
	match kind:
		KIND_SPRING:
			pitch = 660.0
		KIND_VACUUM:
			pitch = 220.0
		KIND_STICKY:
			pitch = 330.0
	# (AudioKit resolves the tone stream; guard for headless.)
	add_child(hum)


func _process(delta: float) -> void:
	if collected:
		return
	_t += delta
	# Bob + spin.
	_charm.position.y = 0.55 + sin(_t * 2.2) * 0.03
	_charm.rotation.y += delta * 1.5
	# Collect: putter head within 12cm, or hand pinch (checked by game).
	if _game != null and _game.club != null:
		var head: Vector3 = _game.club.get_club_head_global()
		if head != Vector3.INF and head.distance_to(_charm.global_position) < 0.12:
			collect()


## Collect the token: shrink to a pocket charm orbiting the putter grip.
func collect() -> void:
	if collected:
		return
	collected = true
	AudioKit.play_sfx("mg_powerup_collect")
	Haptics.play_sequence("ui_select", "right")
	token_collected.emit(kind)
	if _game != null:
		_game.on_token_collected(kind)
	# Visual: shrink to pocket charm on the club.
	if _charm != null:
		_charm.scale = Vector3.ONE * 0.45
		# Reparent to club grip (orbit).
		var club: Node3D = _game.club if _game != null else null
		if club != null:
			var gp := _charm.global_position
			remove_child(_charm)
			club.add_child(_charm)
			_charm.position = Vector3(0.06, -0.15, 0)
			_charm.global_position = gp  # keep continuity on the orbit frame
			_charm.position = Vector3(0.06, -0.15, 0)
		else:
			_charm.queue_free()


## Activate the held effect. Called by the game on trigger squeeze.
func activate(ball, hole) -> void:  # MinigolfBall, MinigolfHole (untyped: circular dep)
	activated.emit(kind)
	AudioKit.play_sfx("mg_powerup_fire")
	match kind:
		KIND_SPRING:
			# Launch ~25cm up with slight forward arc. Cup capture disabled
			# while airborne (anti-cheese).
			ball.velocity.y = 1.6
			ball.velocity += ball.velocity.normalized() * 0.3 if ball.velocity.length() > 0.1 else Vector3.ZERO
			ball.set_meta("spring_airborne", true)
			Haptics.play_sequence("jump_pad", "right")
		KIND_VACUUM:
			# 3s gentle suction within 1.5m of the cup.
			ball.set_meta("vacuum_time", 3.0)
			Haptics.play_sequence("teleport", "right")
		KIND_STICKY:
			# Dead stop within 0.1s.
			ball.velocity = Vector3.ZERO
			Haptics.play_sequence("putt_soft", "right")
	# Consume the charm.
	if _charm != null and is_instance_valid(_charm):
		_charm.queue_free()
	queue_free()
