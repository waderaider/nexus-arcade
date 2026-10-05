## GolfHoleData.gd - configuration for a single mini-golf hole.
## Ports the HoleData concept from the Unity Golf implementation.
extends Resource
class_name GolfHoleData

@export var tee_pos := Vector3(0, 0.1, -2.0)
@export var cup_pos := Vector3(0, 0.0, 2.0)
@export var green_top_y := 0.0
@export var ball_radius := 0.05
@export var cup_radius := 0.09
## Playable rect in XZ: position = (min_x, min_z), end = (max_x, max_z)
@export var play_rect := Rect2(-1.5, -3.0, 3.0, 6.0)

var obstacles: Array[AABB] = []
var wells: Array[GravityWell] = []
var portals: PortalPair = null
