class_name CaneSystem
extends Node3D

## 盲杖系统负责局部 yaw/pitch 挥动、碰撞射线和尖端 Area；不直接控制玩家视角。
@export var cone_angle: float = GameConfig.CANE_SWEEP_ANGLE
@export var pitch_angle: float = 60.0
@export var cane_length: float = GameConfig.CANE_LENGTH

var input_enabled: bool = true

var _current_angle: float = 0.0
var _current_pitch: float = 0.0
var _rod: CSGBox3D
var _tip_area: Area3D
var _was_hitting: bool = false


func _ready() -> void:
	_create_visuals()
	_update_visual_length(cane_length)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func apply_sweep(delta: Vector2) -> Vector2:
	if not input_enabled:
		return Vector2.ZERO

	# 返回值是盲杖局部边界没有消耗掉的弧度余量，InputManager 再把它转成玩家/视角旋转。
	var half_yaw := deg_to_rad(cone_angle * 0.5)
	var half_pitch := deg_to_rad(pitch_angle * 0.5)
	var yaw_result := _apply_axis(_current_angle, delta.x, -half_yaw, half_yaw)
	var pitch_result := _apply_axis(_current_pitch, delta.y, -half_pitch, half_pitch)

	_current_angle = yaw_result.x
	_current_pitch = pitch_result.x
	rotation = Vector3(_current_pitch, _current_angle, 0.0)
	return Vector2(yaw_result.y, pitch_result.y)


func get_tip_area() -> Area3D:
	return _tip_area


func _physics_process(_delta: float) -> void:
	var from := global_position
	var to := global_transform * Vector3(0.0, 0.0, -cane_length)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var parent_body := get_parent() as CollisionObject3D
	if parent_body:
		query.exclude = [parent_body.get_rid()]

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_update_visual_length(cane_length)
		_was_hitting = false
		return

	var hit_point: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var hit_collider: Object = result["collider"]
	var hit_distance := global_position.distance_to(hit_point)
	_update_visual_length(hit_distance)
	EventBus.cane_hit_object.emit(_object_name(hit_collider), hit_point, hit_normal)
	if not _was_hitting:
		EventBus.audio_requested.emit("cane_hit", hit_point, 0.0)
	_was_hitting = true


func _apply_axis(current: float, delta: float, min_value: float, max_value: float) -> Vector2:
	var target := current + delta
	var clamped_value := clampf(target, min_value, max_value)
	return Vector2(clamped_value, target - clamped_value)


func _create_visuals() -> void:
	if not _rod:
		_rod = CSGBox3D.new()
		_rod.name = "CaneRod"
		_rod.use_collision = false
		add_child(_rod)

	if not _tip_area:
		_tip_area = Area3D.new()
		_tip_area.name = "CaneTipArea"
		_tip_area.monitoring = true
		_tip_area.monitorable = true
		_tip_area.add_to_group("cane_tip")
		add_child(_tip_area)

		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.18
		shape.shape = sphere
		_tip_area.add_child(shape)


func _update_visual_length(length: float) -> void:
	var visible_length := maxf(length, 0.05)
	if _rod:
		_rod.size = Vector3(0.035, 0.035, visible_length)
		_rod.position = Vector3(0.0, -0.25, -visible_length * 0.5)
	if _tip_area:
		_tip_area.position = Vector3(0.0, -0.25, -visible_length)


func _object_name(object: Object) -> String:
	if object is Node:
		return (object as Node).name
	return "Object"
