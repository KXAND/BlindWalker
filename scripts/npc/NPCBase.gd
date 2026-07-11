class_name NPCBase
extends CharacterBody3D
## NPC 的最小巡逻基类。没有配置路径点时使用短距离往返路线，方便主场景直接验收。

@export var npc_name: String = "行人"
@export var waypoints: Array[Node3D] = []
@export var walk_speed: float = 2.0
@export var gravity: float = 9.8

var pathing_paused: bool = false

var _current_waypoint: int = 0
var _fallback_points: Array[Vector3] = []


func _ready() -> void:
	add_to_group("npc")
	if waypoints.is_empty():
		_fallback_points = [
			global_position + Vector3(-1.0, 0.0, 0.0),
			global_position + Vector3(1.0, 0.0, 0.0)
		]


func _physics_process(delta: float) -> void:
	if pathing_paused:
		_apply_gravity(delta)
		move_and_slide()
		return

	var target_value: Variant = _current_target()
	if target_value == null:
		_apply_gravity(delta)
		move_and_slide()
		return

	var target: Vector3 = target_value
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0

	if to_target.length() < 0.2:
		_advance_waypoint()
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var direction := to_target.normalized()
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed

	_apply_gravity(delta)
	move_and_slide()


func pause_pathing() -> void:
	pathing_paused = true
	velocity.x = 0.0
	velocity.z = 0.0


func resume_pathing() -> void:
	pathing_paused = false


func _current_target() -> Variant:
	if not waypoints.is_empty():
		return waypoints[_current_waypoint].global_position
	if not _fallback_points.is_empty():
		return _fallback_points[_current_waypoint]
	return null


func _advance_waypoint() -> void:
	var count := waypoints.size() if not waypoints.is_empty() else _fallback_points.size()
	if count > 0:
		_current_waypoint = (_current_waypoint + 1) % count


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1
